import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import 'usuarios_repository.dart';

class PermissionsEditorScreen extends ConsumerStatefulWidget {
  final StoreRole role;
  const PermissionsEditorScreen({super.key, required this.role});

  @override
  ConsumerState<PermissionsEditorScreen> createState() =>
      _PermissionsEditorScreenState();
}

class _PermissionsEditorScreenState
    extends ConsumerState<PermissionsEditorScreen> {
  // functionId → 부여된 액션 집합 (편집 중 로컬 상태)
  final Map<int, Set<String>> _actions = {};
  bool _seeded = false;
  bool _saving = false;

  void _seed(Map<int, Set<String>> grant) {
    _actions.clear();
    grant.forEach((k, v) => _actions[k] = {...v});
    _seeded = true;
  }

  // 리소스 그룹의 CRUD 칩 상태/토글 (버킷 내 아무 id 라도 있으면 ON, 전체 적용)
  bool _crudOn(List<int> bucket, String action) =>
      bucket.any((id) => _actions[id]?.contains(action) ?? false);

  void _toggleCrud(List<int> bucket, String action) {
    final on = _crudOn(bucket, action);
    setState(() {
      for (final id in bucket) {
        final set = _actions.putIfAbsent(id, () => <String>{});
        if (on) {
          set.remove(action);
        } else {
          set.add(action);
        }
      }
    });
  }

  // 비즈니스 액션: ON = 아무 액션이라도 있음, 토글 시 4개 전부 on/off
  bool _businessOn(int fnId) => (_actions[fnId]?.isNotEmpty ?? false);

  void _toggleBusiness(int fnId) {
    final on = _businessOn(fnId);
    setState(() {
      _actions[fnId] = on ? <String>{} : {...kActions};
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(usuariosRepositoryProvider)
          .saveBulkActions(widget.role.id, _actions);
      if (!mounted) return;
      ref.invalidate(roleFunctionsProvider(widget.role.id));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Permisos guardados.'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error al guardar: $e'),
        backgroundColor: AppColors.red,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final structAsync = ref.watch(permStructureProvider);
    final grantAsync = ref.watch(roleFunctionsProvider(widget.role.id));

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.navy2,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Permisos · ${widget.role.name}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const Text('Recurso = CRUD · Acción = interruptor',
                style: TextStyle(color: AppColors.dim, fontSize: 11)),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TextButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Guardando…' : 'Guardar',
                  style: const TextStyle(
                      color: AppColors.gold, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
      body: (structAsync.isLoading || grantAsync.isLoading)
          ? const Center(child: CircularProgressIndicator())
          : structAsync.hasError
              ? _err('estructura', structAsync.error)
              : grantAsync.hasError
                  ? _err('permisos', grantAsync.error)
                  : _tree(structAsync.value!, grantAsync.value!),
    );
  }

  Widget _err(String what, Object? e) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('No se pudo cargar $what.\n$e',
            style: const TextStyle(color: AppColors.red, fontSize: 12)),
      );

  Widget _tree(List<PermApp> apps, Map<int, Set<String>> grant) {
    if (!_seeded) _seed(grant);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
      children: [
        for (final app in apps)
          Theme(
            data: Theme.of(context)
                .copyWith(dividerColor: Colors.transparent),
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: AppColors.panel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.line),
              ),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                title: Text(app.name,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800)),
                iconColor: AppColors.gold,
                collapsedIconColor: AppColors.dim,
                children: [
                  for (final mod in app.modules) _moduleBlock(mod),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _moduleBlock(PermModule mod) {
    final g = groupModule(mod);
    if (g.resources.isEmpty && g.businessActions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 10, 2, 6),
          child: Text(mod.name.toUpperCase(),
              style: const TextStyle(
                  fontSize: 10.5,
                  letterSpacing: 0.4,
                  fontWeight: FontWeight.w800,
                  color: AppColors.dim)),
        ),
        for (final res in g.resources) _resourceRow(res),
        for (final ba in g.businessActions) _businessRow(ba),
      ],
    );
  }

  Widget _resourceRow(ResourceGroup res) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFF182036),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(res.label,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
          for (final a in kActions) _crudChip(res.crudMap[a] ?? const [], a),
        ],
      ),
    );
  }

  Widget _crudChip(List<int> bucket, String action) {
    final enabled = bucket.isNotEmpty;
    final on = enabled && _crudOn(bucket, action);
    final letter = action[0].toUpperCase(); // C R U D

    return Padding(
      padding: const EdgeInsets.only(left: 5),
      child: Opacity(
        opacity: enabled ? 1 : 0.28,
        child: GestureDetector(
          onTap: enabled ? () => _toggleCrud(bucket, action) : null,
          child: Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on
                  ? AppColors.green.withValues(alpha: 0.16)
                  : const Color(0xFF0E1428),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                  color: on
                      ? AppColors.green.withValues(alpha: 0.5)
                      : AppColors.line),
            ),
            child: Text(letter,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: on ? AppColors.green : AppColors.dim)),
          ),
        ),
      ),
    );
  }

  Widget _businessRow(PermFunction ba) {
    final on = _businessOn(ba.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF182036),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(ba.name,
                style: const TextStyle(fontSize: 12.5)),
          ),
          GestureDetector(
            onTap: () => _toggleBusiness(ba.id),
            child: Container(
              width: 40,
              height: 23,
              decoration: BoxDecoration(
                color: on ? AppColors.gold : const Color(0xFF0E1428),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                    color: on ? AppColors.gold : AppColors.line),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 150),
                alignment: on ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.all(2),
                  width: 17,
                  height: 17,
                  decoration: BoxDecoration(
                    color: on ? AppColors.navy : const Color(0xFFCFD6EA),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
