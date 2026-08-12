import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/format.dart';
import '../usuarios/usuarios_repository.dart' show Branch, branchesProvider;
import 'codigo_madre_repository.dart';

// Código madre 편집 — 특정 **날짜 + 지점**의 변형(색×사이즈)과 수량.
//
// ★ 저장은 재고 원장을 움직인다. 그래서 두 가지를 지킨다:
//   1) 날짜·지점을 항상 화면 맨 위에 보여준다 (무엇을 고치는지 착각하지 않게)
//   2) 저장 전에 무엇이 바뀌는지 요약해서 확인받는다 (누른 뒤에 알면 늦다)
class CodigoMadreEditorScreen extends ConsumerStatefulWidget {
  final int parentId;
  final String parentName;
  final String parentSku;

  const CodigoMadreEditorScreen({
    super.key,
    required this.parentId,
    required this.parentName,
    required this.parentSku,
  });

  @override
  ConsumerState<CodigoMadreEditorScreen> createState() =>
      _CodigoMadreEditorScreenState();
}

class _CodigoMadreEditorScreenState
    extends ConsumerState<CodigoMadreEditorScreen> {
  late String _date = todayStr();
  int? _branchId;
  bool _saving = false;

  // 편집 상태 — 날짜/지점이 바뀌면 전부 버린다(그 조합에만 유효한 값이므로).
  final Map<int, int> _updates = {}; // variantId → newStock
  final Set<int> _deletedColors = {}; // colorId
  final List<({int colorId, String colorName, int sizeId, String sizeName, int stock})>
      _added = [];

  bool get _dirty =>
      _updates.isNotEmpty || _deletedColors.isNotEmpty || _added.isNotEmpty;

  void _resetEdits() {
    _updates.clear();
    _deletedColors.clear();
    _added.clear();
  }

  @override
  Widget build(BuildContext context) {
    final branches = ref.watch(branchesProvider);

    // 지점 기본값 — 첫 지점. 사용자가 고르기 전까지 조회를 시작하지 않는다.
    branches.whenData((list) {
      if (_branchId == null && list.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _branchId = list.first.id);
        });
      }
    });

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.navy2,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.parentName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            Text(widget.parentSku,
                style: const TextStyle(fontSize: 10.5, color: AppColors.dim)),
          ],
        ),
      ),
      body: Column(
        children: [
          _scopeBar(branches),
          Expanded(child: _branchId == null ? _hint('Elegí una sucursal') : _body()),
        ],
      ),
      bottomNavigationBar: _branchId == null ? null : _footer(),
    );
  }

  // ── 날짜 + 지점 (편집 범위) ───────────────────────────────────────────
  Widget _scopeBar(AsyncValue<List<Branch>> branches) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: const BoxDecoration(
        color: AppColors.navy2,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _chip(
              icon: Icons.calendar_today_outlined,
              label: _date,
              onTap: _pickDate,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: branches.when(
              loading: () => _chip(icon: Icons.store_outlined, label: '...'),
              error: (e, _) =>
                  _chip(icon: Icons.store_outlined, label: 'error', danger: true),
              data: (list) => _chip(
                icon: Icons.store_outlined,
                label: list
                        .where((b) => b.id == _branchId)
                        .map((b) => b.name)
                        .firstOrNull ??
                    'Sucursal',
                onTap: () => _pickBranch(list),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    bool danger = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: danger ? AppColors.red : AppColors.line),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: AppColors.gold),
            const SizedBox(width: 7),
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
            if (onTap != null)
              const Icon(Icons.expand_more, size: 15, color: AppColors.dim),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final parts = _date.split('-').map(int.tryParse).toList();
    final initial = parts.length == 3 && !parts.contains(null)
        ? DateTime(parts[0]!, parts[1]!, parts[2]!)
        : now;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1),
    );
    if (picked == null || !mounted) return;

    final s = '${picked.year.toString().padLeft(4, '0')}-'
        '${picked.month.toString().padLeft(2, '0')}-'
        '${picked.day.toString().padLeft(2, '0')}';
    if (s == _date) return;
    if (!await _confirmDiscardIfDirty()) return;
    if (!mounted) return;
    setState(() {
      _date = s;
      _resetEdits();
    });
  }

  Future<void> _pickBranch(List<Branch> list) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.navy,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final b in list)
              ListTile(
                title: Text(b.name, style: const TextStyle(fontSize: 14)),
                trailing: b.id == _branchId
                    ? const Icon(Icons.check, size: 18, color: AppColors.gold)
                    : null,
                onTap: () => Navigator.of(context).pop(b.id),
              ),
          ],
        ),
      ),
    );
    if (picked == null || picked == _branchId || !mounted) return;
    if (!await _confirmDiscardIfDirty()) return;
    if (!mounted) return;
    setState(() {
      _branchId = picked;
      _resetEdits();
    });
  }

  // 편집 중 범위를 바꾸면 입력이 사라진다 — 조용히 버리지 않는다.
  Future<bool> _confirmDiscardIfDirty() async {
    if (!_dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.navy,
        title: const Text('Cambios sin guardar', style: TextStyle(fontSize: 15)),
        content: const Text(
          'Si cambiás la fecha o la sucursal se descartan los cambios cargados.',
          style: TextStyle(fontSize: 13, color: AppColors.dim),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Volver')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Descartar',
                  style: TextStyle(color: AppColors.red))),
        ],
      ),
    );

    return ok ?? false;
  }

  // ── 변형 목록 ────────────────────────────────────────────────────────
  Widget _body() {
    final scope =
        (parentId: widget.parentId, date: _date, branchId: _branchId!);
    final async = ref.watch(madreInventoryProvider(scope));

    return RefreshIndicator(
      onRefresh: () async {
        if (!await _confirmDiscardIfDirty()) return;
        setState(_resetEdits);
        ref.invalidate(madreInventoryProvider(scope));
      },
      child: async.isLoading
          ? const Center(child: CircularProgressIndicator())
          : async.hasError
              ? ListView(children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('No se pudo cargar el detalle.\n${async.error}',
                        style: const TextStyle(color: AppColors.red, fontSize: 12)),
                  )
                ])
              : _grid(async.value!.variants),
    );
  }

  Widget _grid(List<MadreVariant> variants) {
    // 색상별로 묶는다 — 삭제 단위가 색상이기 때문이다(deleteColorIds).
    final byColor = <int, List<MadreVariant>>{};
    final colorNames = <int, String>{};
    for (final v in variants) {
      byColor.putIfAbsent(v.colorId, () => []).add(v);
      colorNames[v.colorId] = v.colorName;
    }

    final addedByColor = <int, List<int>>{}; // colorId → _added 인덱스
    for (var i = 0; i < _added.length; i++) {
      addedByColor.putIfAbsent(_added[i].colorId, () => []).add(i);
      colorNames.putIfAbsent(_added[i].colorId, () => _added[i].colorName);
    }

    final colorIds = <int>{...byColor.keys, ...addedByColor.keys}.toList()
      ..sort((a, b) => (colorNames[a] ?? '').compareTo(colorNames[b] ?? ''));

    if (colorIds.isEmpty) {
      return ListView(children: [
        _hint('No hay variantes cargadas en esta fecha y sucursal.'),
      ]);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
      children: [
        for (final cid in colorIds)
          _colorCard(
            colorId: cid,
            colorName: colorNames[cid] ?? '—',
            existing: byColor[cid] ?? const [],
            addedIdx: addedByColor[cid] ?? const [],
          ),
        const SizedBox(height: 4),
        _hint('Los valores son del día y la sucursal seleccionados.'),
      ],
    );
  }

  Widget _colorCard({
    required int colorId,
    required String colorName,
    required List<MadreVariant> existing,
    required List<int> addedIdx,
  }) {
    final deleted = _deletedColors.contains(colorId);

    return Opacity(
      opacity: deleted ? 0.45 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: deleted ? AppColors.red : AppColors.line),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(13, 10, 8, 10),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.line)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(colorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                  if (deleted)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Text('Se elimina',
                          style: TextStyle(fontSize: 10.5, color: AppColors.red)),
                    ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      deleted ? Icons.undo : Icons.delete_outline,
                      size: 18,
                      color: deleted ? AppColors.gold : AppColors.dim,
                    ),
                    onPressed: () => setState(() {
                      if (deleted) {
                        _deletedColors.remove(colorId);
                      } else {
                        _deletedColors.add(colorId);
                        // 삭제 표시한 색의 수량 수정은 의미가 없다 — 같이 지운다.
                        for (final v in existing) {
                          _updates.remove(v.id);
                        }
                      }
                    }),
                  ),
                ],
              ),
            ),
            for (final v in existing)
              _row(
                size: v.sizeName,
                value: _updates[v.id] ?? v.stock,
                original: v.stock,
                enabled: !deleted,
                onChanged: (n) => setState(() {
                  if (n == v.stock) {
                    _updates.remove(v.id);
                  } else {
                    _updates[v.id] = n;
                  }
                }),
              ),
            for (final i in addedIdx)
              _row(
                size: _added[i].sizeName,
                value: _added[i].stock,
                original: null,
                enabled: !deleted,
                onRemove: () => setState(() => _added.removeAt(i)),
                onChanged: (n) => setState(() {
                  final a = _added[i];
                  _added[i] = (
                    colorId: a.colorId,
                    colorName: a.colorName,
                    sizeId: a.sizeId,
                    sizeName: a.sizeName,
                    stock: n,
                  );
                }),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row({
    required String size,
    required int value,
    required int? original,
    required bool enabled,
    required ValueChanged<int> onChanged,
    VoidCallback? onRemove,
  }) {
    final changed = original != null && value != original;
    final isNew = original == null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(13, 7, 8, 7),
      child: Row(
        children: [
          SizedBox(
            width: 62,
            child: Text(size,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: AppColors.dim)),
          ),
          if (isNew)
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(99),
              ),
              child: const Text('nueva',
                  style: TextStyle(fontSize: 9.5, color: AppColors.gold)),
            )
          else if (changed)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text('$original →',
                  style: const TextStyle(fontSize: 11, color: AppColors.dim)),
            ),
          const Spacer(),
          SizedBox(
            width: 78,
            child: TextFormField(
              key: ValueKey('$size-$original-$isNew'),
              initialValue: '$value',
              enabled: enabled,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: changed || isNew ? AppColors.gold : AppColors.txt,
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                filled: true,
                fillColor: AppColors.navy2,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                      color: changed || isNew ? AppColors.gold : AppColors.line),
                ),
              ),
              onChanged: (t) => onChanged(int.tryParse(t) ?? 0),
            ),
          ),
          if (onRemove != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 16, color: AppColors.dim),
              onPressed: onRemove,
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    );
  }

  // ── 하단 (추가 / 저장) ───────────────────────────────────────────────
  Widget _footer() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: const BoxDecoration(
          color: AppColors.navy2,
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          children: [
            OutlinedButton.icon(
              onPressed: _saving ? null : _addVariantSheet,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Variante'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.txt,
                side: const BorderSide(color: AppColors.line),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: (!_dirty || _saving) ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: const Color(0xFF20160A),
                  disabledBackgroundColor: AppColors.line,
                  disabledForegroundColor: AppColors.dim,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_dirty ? 'Guardar cambios' : 'Sin cambios',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addVariantSheet() async {
    final colors = await ref.read(madreColorsProvider.future);
    final sizes = await ref.read(madreSizesProvider.future);
    if (!mounted) return;

    NamedRef? color;
    NamedRef? size;
    var qty = 0;

    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.navy,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Agregar variante',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              _dropdown<NamedRef>(
                hint: 'Color',
                value: color,
                items: colors,
                label: (c) => c.name,
                onChanged: (c) => setSheet(() => color = c),
              ),
              const SizedBox(height: 10),
              _dropdown<NamedRef>(
                hint: 'Talle',
                value: size,
                items: sizes,
                label: (s) => s.name,
                onChanged: (s) => setSheet(() => size = s),
              ),
              const SizedBox(height: 10),
              TextFormField(
                initialValue: '0',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(
                  labelText: 'Cantidad',
                  labelStyle: TextStyle(color: AppColors.dim, fontSize: 13),
                  filled: true,
                  fillColor: AppColors.panel,
                  border: OutlineInputBorder(),
                ),
                onChanged: (t) => qty = int.tryParse(t) ?? 0,
              ),
              const SizedBox(height: 8),
              const Text(
                'Cantidad 0 también crea la variante (para repartir después).',
                style: TextStyle(fontSize: 11, color: AppColors.dim),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (color == null || size == null)
                      ? null
                      : () => Navigator.of(ctx).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: const Color(0xFF20160A),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  child: const Text('Agregar',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (added != true || color == null || size == null || !mounted) return;

    // 같은 색·사이즈를 두 번 넣으면 백엔드에서 중복 변형이 된다 — 여기서 막는다.
    final dup = _added.any((a) => a.colorId == color!.id && a.sizeId == size!.id);
    if (dup) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Esa combinación ya está en la lista')),
      );

      return;
    }

    setState(() => _added.add((
          colorId: color!.id,
          colorName: color!.name,
          sizeId: size!.id,
          sizeName: size!.name,
          stock: qty,
        )));
  }

  Widget _dropdown<T>({
    required String hint,
    required T? value,
    required List<T> items,
    required String Function(T) label,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      dropdownColor: AppColors.navy,
      style: const TextStyle(fontSize: 14, color: AppColors.txt),
      decoration: InputDecoration(
        labelText: hint,
        labelStyle: const TextStyle(color: AppColors.dim, fontSize: 13),
        filled: true,
        fillColor: AppColors.panel,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final i in items) DropdownMenuItem(value: i, child: Text(label(i))),
      ],
      onChanged: onChanged,
    );
  }

  // ── 저장 ─────────────────────────────────────────────────────────────
  Future<void> _save() async {
    final payload = MadreSavePayload(
      date: _date,
      branchIds: [_branchId!],
      deleteColorIds: _deletedColors.toList(),
      addVariants: [
        for (final a in _added)
          (colorId: a.colorId, sizeId: a.sizeId, stock: a.stock),
      ],
      updateVariants: [
        for (final e in _updates.entries) (variantId: e.key, newStock: e.value),
      ],
    );
    if (payload.isEmpty) return;

    // 재고를 움직이는 저장이다 — 무엇이 바뀌는지 먼저 보여준다.
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.navy,
        title: const Text('Confirmar cambios', style: TextStyle(fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Fecha $_date',
                style: const TextStyle(fontSize: 12.5, color: AppColors.dim)),
            const SizedBox(height: 10),
            if (payload.updateVariants.isNotEmpty)
              _sum('${payload.updateVariants.length} cantidad(es) modificada(s)'),
            if (payload.addVariants.isNotEmpty)
              _sum('${payload.addVariants.length} variante(s) nueva(s)'),
            if (payload.deleteColorIds.isNotEmpty)
              _sum('${payload.deleteColorIds.length} color(es) eliminado(s)',
                  danger: true),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Guardar',
                  style: TextStyle(color: AppColors.gold))),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await ref
          .read(codigoMadreRepositoryProvider)
          .save(widget.parentId, payload);
      if (!mounted) return;
      setState(_resetEdits);
      ref.invalidate(madreInventoryProvider(
          (parentId: widget.parentId, date: _date, branchId: _branchId!)));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cambios guardados')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.red,
          content: Text('No se pudo guardar: ${_msg(e)}'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // 서버가 보낸 이유를 그대로 보여준다 — 'Error' 만 띄우면 원인이 사라진다.
  String _msg(Object e) {
    final s = e.toString();
    final m = RegExp(r'"message"\s*:\s*"([^"]+)"').firstMatch(s);

    return m?.group(1) ?? s;
  }

  Widget _sum(String text, {bool danger = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Icon(danger ? Icons.remove_circle_outline : Icons.check_circle_outline,
                size: 14, color: danger ? AppColors.red : AppColors.gold),
            const SizedBox(width: 7),
            Expanded(
                child: Text(text, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );

  Widget _hint(String text) => Padding(
        padding: const EdgeInsets.all(20),
        child: Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: AppColors.dim)),
      );
}
