import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/format.dart';
import 'codigo_madre_repository.dart';

// Código madre — 제품 마스터 편집: 이름 / 가격유형별 가격 / 공개몰(Tienda Web) 게시.
//
// ★ 재고는 여기서 건드리지 않는다. 색·사이즈·수량 편집은 웹에서 한다.
//
// 세 가지를 지킨다:
//  1) **바꾼 것만 보낸다.** 손대지 않은 가격유형은 요청에 넣지 않는다 — 가격 저장은
//     부모+자식 전부를 같은 값으로 덮으므로, 안 만진 유형까지 보내면 조용히 통일된다.
//  2) **갈려 있으면 미리 경고한다.** 부모와 자식(또는 자식끼리) 금액이 다른 가격유형은
//     화면과 확인창에서 표시한다. 저장하면 그 차이가 사라지고 되돌릴 수 없다.
//  3) **부분 실패를 숨기지 않는다.** 세 엔드포인트는 권한 가드가 서로 다르다
//     (editar-un-producto / cambiar-precio-individual / publicar-o-no-publicar-producto).
//     하나가 403 이어도 나머지는 이미 저장됐다 — 롤백하지 않고 항목별로 결과를 보여준다.
class CodigoMadreEditorScreen extends ConsumerStatefulWidget {
  final MadreParent parent;

  const CodigoMadreEditorScreen({super.key, required this.parent});

  @override
  ConsumerState<CodigoMadreEditorScreen> createState() =>
      _CodigoMadreEditorScreenState();
}

class _CodigoMadreEditorScreenState
    extends ConsumerState<CodigoMadreEditorScreen> {
  late final TextEditingController _name =
      TextEditingController(text: widget.parent.name);
  late bool _published = widget.parent.isPublishedShop;

  // priceTypeId → 입력 컨트롤러. 가격유형이 로드된 뒤 1회 생성한다.
  final Map<int, TextEditingController> _priceCtrls = {};
  final Map<int, int> _priceOriginal = {}; // priceTypeId → 최초 금액

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    for (final c in _priceCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  // 가격유형이 다시 로드돼도 **이미 만든 컨트롤러는 건드리지 않는다** — 사용자가 입력한
  // 값이 날아가면 안 된다. 새로 나타난 유형에만 컨트롤러를 만든다(없으면 저장에서 누락된다).
  void _buildCtrls(List<PriceTypeRef> types) {
    for (final pt in types) {
      if (_priceCtrls.containsKey(pt.id)) continue;
      final amount = widget.parent.amountFor(pt).round();
      _priceOriginal[pt.id] = amount;
      _priceCtrls[pt.id] = TextEditingController(text: amount.toString());
    }
  }

  bool get _nameChanged =>
      _name.text.trim().isNotEmpty &&
      _name.text.trim().toUpperCase() != widget.parent.name.trim().toUpperCase();

  bool get _publishChanged => _published != widget.parent.isPublishedShop;

  /// 손댄 가격유형만 — 값이 같으면 보내지 않는다.
  Map<int, num> get _changedPrices {
    final out = <int, num>{};
    for (final e in _priceCtrls.entries) {
      final typed = int.tryParse(e.value.text.trim());
      if (typed == null || typed < 0) continue;
      if (typed != _priceOriginal[e.key]) out[e.key] = typed;
    }

    return out;
  }

  bool get _dirty =>
      _nameChanged || _publishChanged || _changedPrices.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final types = ref.watch(madrePriceTypesProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.navy2,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.parent.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            Text(widget.parent.sku,
                style: const TextStyle(fontSize: 10.5, color: AppColors.dim)),
          ],
        ),
      ),
      body: types.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _hint('No se pudieron cargar los tipos de precio.\n$e'),
        data: (list) {
          _buildCtrls(list);

          return _form(list);
        },
      ),
      bottomNavigationBar: types.hasValue ? _footer() : null,
    );
  }

  Widget _form(List<PriceTypeRef> types) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      children: [
        _section('DATOS'),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Nombre',
                  style: TextStyle(fontSize: 11, color: AppColors.dim)),
              const SizedBox(height: 6),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 14, color: AppColors.txt),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 11, vertical: 11),
                ),
              ),
              const SizedBox(height: 6),
              // 서버가 name 을 대문자로 정규화한다 (products.controller updateProducts).
              // 미리 알려주지 않으면 "내가 쓴 대로 안 저장됐다" 는 문의가 온다.
              const Text('Se guarda en MAYÚSCULAS.',
                  style: TextStyle(fontSize: 10.5, color: AppColors.dim)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _card(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Tienda Web',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(
                      _published
                          ? 'Visible en la tienda online.'
                          : 'No se publica en la tienda online.',
                      style: const TextStyle(fontSize: 11, color: AppColors.dim),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _published,
                activeThumbColor: AppColors.gold,
                onChanged: (v) => setState(() => _published = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _section('PRECIOS'),
        if (types.isEmpty)
          _card(
            child: const Text('Esta tienda no tiene tipos de precio activos.',
                style: TextStyle(fontSize: 12, color: AppColors.dim)),
          )
        else
          for (final pt in types) ...[
            _priceRow(pt),
            const SizedBox(height: 8),
          ],
        const SizedBox(height: 6),
        // 무엇이 바뀌는지 — 이 화면의 저장은 자식(codigos hijitos)까지 간다.
        Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: AppColors.navy2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, size: 15, color: AppColors.dim),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'El precio se aplica al código madre y a sus '
                  '${widget.parent.variantCount} variante(s). '
                  'El stock no se modifica desde esta pantalla.',
                  style: const TextStyle(fontSize: 11, color: AppColors.dim),
                ),
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!,
              style: const TextStyle(fontSize: 12, color: AppColors.red)),
        ],
      ],
    );
  }

  Widget _priceRow(PriceTypeRef pt) {
    final mixed = widget.parent.isMixed(pt);

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(pt.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w700)),
                    ),
                    if (pt.isBase) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.navy2,
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: AppColors.line),
                        ),
                        child: const Text('BASE',
                            style: TextStyle(
                                fontSize: 9,
                                color: AppColors.gold,
                                fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 128,
                child: TextField(
                  controller: _priceCtrls[pt.id],
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.right,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.txt,
                      fontFeatures: [FontFeature.tabularFigures()]),
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixText: r'$ ',
                    prefixStyle:
                        TextStyle(fontSize: 12.5, color: AppColors.dim),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                ),
              ),
            ],
          ),
          // 갈려 있으면 반드시 말한다 — 저장하면 차이가 사라지고 되돌릴 수 없다.
          if (mixed) ...[
            const SizedBox(height: 7),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 14, color: AppColors.amber),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Las variantes tienen precios distintos '
                    '(${_mixedSummary(pt)}). Si guardás este campo, todas '
                    'quedan con el mismo valor.',
                    style:
                        const TextStyle(fontSize: 10.5, color: AppColors.amber),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _mixedSummary(PriceTypeRef pt) {
    final values = <num>{
      ...?widget.parent.variantPrices[pt.id],
      if (widget.parent.parentPrices[pt.id] != null)
        widget.parent.parentPrices[pt.id]!,
    }.toList()
      ..sort();

    if (values.isEmpty) return 'sin precio cargado';
    if (values.length == 1) return 'faltan variantes sin precio';

    return '${money(values.first)} – ${money(values.last)}';
  }

  Widget _footer() {
    final changes = _changeLines();

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: const BoxDecoration(
          color: AppColors.navy2,
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                changes.isEmpty
                    ? 'Sin cambios'
                    : '${changes.length} cambio(s) sin guardar',
                style: TextStyle(
                    fontSize: 11.5,
                    color: changes.isEmpty ? AppColors.dim : AppColors.gold),
              ),
            ),
            ElevatedButton(
              onPressed: (!_dirty || _saving) ? null : _confirmAndSave,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: AppColors.navy,
                disabledBackgroundColor: AppColors.panel,
                disabledForegroundColor: AppColors.dim,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(_saving ? 'Guardando…' : 'Guardar',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  // ── 저장 ──────────────────────────────────────────────────────────────

  /// 확인창에 그대로 쓰는 변경 요약. 저장 대상과 1:1 이어야 한다.
  List<String> _changeLines() {
    final out = <String>[];
    if (_nameChanged) {
      out.add('Nombre → ${_name.text.trim().toUpperCase()}');
    }
    final prices = _changedPrices;
    if (prices.isNotEmpty) {
      final types = ref.read(madrePriceTypesProvider).value ?? const [];
      for (final e in prices.entries) {
        final pt = types.where((t) => t.id == e.key).firstOrNull;
        final label = pt?.name ?? 'Tipo ${e.key}';
        final warn = (pt != null && widget.parent.isMixed(pt))
            ? '  ⚠ unifica todas las variantes'
            : '';
        out.add('$label → ${money(e.value)}$warn');
      }
    }
    if (_publishChanged) {
      out.add(_published
          ? 'Tienda Web → publicar'
          : 'Tienda Web → quitar de la tienda');
    }

    return out;
  }

  Future<void> _confirmAndSave() async {
    final changes = _changeLines();
    if (changes.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text('Confirmar cambios',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final c in changes)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('• $c',
                    style:
                        const TextStyle(fontSize: 12, color: AppColors.txt)),
              ),
            if (_changedPrices.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Los precios se aplican al código madre y a sus '
                '${widget.parent.variantCount} variante(s).',
                style: const TextStyle(fontSize: 11, color: AppColors.dim),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar',
                style: TextStyle(color: AppColors.dim)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Guardar',
                style: TextStyle(
                    color: AppColors.gold, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );

    if (ok == true) await _save();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    final repo = ref.read(codigoMadreRepositoryProvider);
    final id = widget.parent.id;
    final results = <String>[];
    final failures = <String>[];

    // 세 호출은 각각 독립이다. 하나가 403 이어도 앞의 것은 이미 커밋됐다 —
    // 보상 요청도 같은 이유로 실패할 수 있으므로 롤백하지 않고 결과만 정직하게 알린다.
    if (_nameChanged) {
      try {
        await repo.updateName(id, _name.text.trim());
        results.add('Nombre');
      } catch (e) {
        failures.add('Nombre: ${_extract(e)}');
      }
    }

    final prices = _changedPrices;
    if (prices.isNotEmpty) {
      try {
        await repo.updatePrices(id, prices);
        results.add('Precios (${prices.length})');
      } catch (e) {
        failures.add('Precios: ${_extract(e)}');
      }
    }

    if (_publishChanged) {
      try {
        await repo.setPublishedShop(id, _published);
        results.add('Tienda Web');
      } catch (e) {
        failures.add('Tienda Web: ${_extract(e)}');
      }
    }

    if (!mounted) return;

    // 부분 성공이라도 서버 값이 바뀌었으므로 목록은 반드시 다시 읽는다.
    ref.invalidate(madreParentsProvider);

    if (failures.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Guardado: ${results.join(', ')}'),
        behavior: SnackBarBehavior.floating,
      ));
      Navigator.of(context).pop();

      return;
    }

    setState(() {
      _saving = false;
      _error = [
        if (results.isNotEmpty) 'Guardado: ${results.join(', ')}.',
        ...failures,
      ].join('\n');
    });
  }

  String _extract(Object e) {
    if (e is DioException) {
      if (e.response?.statusCode == 403) {
        return 'sin permiso para esta acción (403)';
      }
      final data = e.response?.data;
      if (data is Map && data['message'] != null) {
        final m = data['message'];

        return m is List ? m.join(', ') : m.toString();
      }
    }

    return e.toString();
  }

  // ── 조각 ──────────────────────────────────────────────────────────────

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
        child: Text(t,
            style: const TextStyle(
                fontSize: 11,
                letterSpacing: 0.5,
                fontWeight: FontWeight.w800,
                color: AppColors.dim)),
      );

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.line),
        ),
        child: child,
      );

  Widget _hint(String t) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text(t,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: AppColors.dim)),
      );
}
