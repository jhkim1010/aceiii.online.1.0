// 사용자별 권한 화면 — 역할(role_functions)이 base, 이 화면에서 그 사용자만의
// 예외(override)를 얹는다. 웹 UserPermissionsDrawer 와 같은 계약:
//   GET  /user-functions/{id}            — 현재 override
//   PUT  /user-functions/actions/{id}    — 액션 단위 override 저장
//   POST /user-functions/reset/{id}      — 역할 기본값으로 복원
//
// 칩 3상태: 역할에서 상속(초록) / 이 사용자만 추가(골드) / 이 사용자만 차단(빨강).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import 'usuarios_repository.dart';

// 사용자 override — 화면 진입 시 서버 값으로 시드
final userOverridesProvider = FutureProvider.autoDispose
    .family<Map<int, Map<String, bool>>, int>((ref, userId) {
  return ref.read(usuariosRepositoryProvider).getUserOverrides(userId);
});

// 사용자의 역할들에서 오는 base 권한 (여러 역할이면 합집합).
// ★family 키는 반드시 값 동등성이 있는 타입이어야 한다 — List<int> 를 키로 쓰면
// 매 빌드마다 새 인스턴스라 캐시 미적중 → 무한 refetch 루프(1~2초 간격 반복 호출,
// 화면이 30초 넘게 로딩만 반복되던 원인). String CSV 키로 고정한다. (2026-07-28)
final userRoleActionsProvider = FutureProvider.autoDispose
    .family<Map<int, Set<String>>, String>((ref, roleIdsCsv) async {
  final repo = ref.read(usuariosRepositoryProvider);
  final roleIds = roleIdsCsv.isEmpty
      ? const <int>[]
      : roleIdsCsv.split(',').map(int.parse).toList();
  final merged = <int, Set<String>>{};
  for (final roleId in roleIds) {
    final one = await repo.getRoleFunctions(roleId);
    one.forEach((fnId, actions) {
      merged.putIfAbsent(fnId, () => <String>{}).addAll(actions);
    });
  }

  return merged;
});

enum _Filter { todos, permitidos, modificados }

class UserPermissionsScreen extends ConsumerStatefulWidget {
  final StoreUser user;

  const UserPermissionsScreen({super.key, required this.user});

  @override
  ConsumerState<UserPermissionsScreen> createState() =>
      _UserPermissionsScreenState();
}

class _UserPermissionsScreenState extends ConsumerState<UserPermissionsScreen> {
  // 편집 중인 override (functionId → action → allowed). 역할과 같아지면 항목을 지운다.
  final Map<int, Map<String, bool>> _over = {};
  // 서버에서 받은 원본 — 변경 개수 계산 + 저장 대상 판별용
  Map<int, Map<String, bool>> _serverOver = const {};
  bool _seeded = false;
  bool _saving = false;
  _Filter _filter = _Filter.todos;

  // family 키 — 정렬된 CSV 로 안정화 (List 키 금지: 무한 refetch 원인)
  String get _roleIdsKey =>
      (widget.user.roles.map((r) => r.id).toList()..sort()).join(',');

  void _seed(Map<int, Map<String, bool>> server) {
    _over
      ..clear()
      ..addAll({for (final e in server.entries) e.key: {...e.value}});
    _serverOver = {for (final e in server.entries) e.key: {...e.value}};
    _seeded = true;
  }

  // 역할 기본값
  bool _roleHas(Map<int, Set<String>> role, int fnId, String action) =>
      role[fnId]?.contains(action) ?? false;

  // 역할에 이 기능 자체가 없으면 예외로도 부여할 수 없다.
  // 서버 가드가 role_functions 에 행이 없으면 즉시 거부하기 때문(추가는 역할에서 해야 함).
  bool _grantable(Map<int, Set<String>> role, int fnId) => role.containsKey(fnId);

  // 최종 권한 = override 있으면 그 값, 없으면 역할 값
  bool _effective(Map<int, Set<String>> role, int fnId, String action) =>
      _over[fnId]?[action] ?? _roleHas(role, fnId, action);

  // 역할과 다른가 (= 이 사용자만의 예외)
  bool _isOverridden(Map<int, Set<String>> role, int fnId, String action) {
    final o = _over[fnId]?[action];

    return o != null && o != _roleHas(role, fnId, action);
  }

  void _toggle(Map<int, Set<String>> role, int fnId, String action) {
    final next = !_effective(role, fnId, action);
    setState(() {
      final bucket = _over.putIfAbsent(fnId, () => <String, bool>{});
      if (next == _roleHas(role, fnId, action)) {
        // 역할 기본값과 같아짐 → 예외를 남길 이유가 없다
        bucket.remove(action);
        if (bucket.isEmpty) {
          _over.remove(fnId);
        }
      } else {
        bucket[action] = next;
      }
    });
  }

  // 한 항목(function)의 예외 전부 해제 → 역할 기본값으로
  void _resetFunction(int fnId) => setState(() => _over.remove(fnId));

  int get _changedCount {
    var n = 0;
    final ids = {..._over.keys, ..._serverOver.keys};
    for (final id in ids) {
      final a = _over[id] ?? const <String, bool>{};
      final b = _serverOver[id] ?? const <String, bool>{};
      final keys = {...a.keys, ...b.keys};
      for (final k in keys) {
        if (a[k] != b[k]) {
          n++;
        }
      }
    }

    return n;
  }

  (int added, int removed) _counts(Map<int, Set<String>> role) {
    var added = 0;
    var removed = 0;
    _over.forEach((fnId, actions) {
      actions.forEach((action, allowed) {
        if (allowed != _roleHas(role, fnId, action)) {
          allowed ? added++ : removed++;
        }
      });
    });

    return (added, removed);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      // 서버에 있었지만 지금은 사라진 항목도 빈 액션으로 보내 역할 기본값으로 되돌린다
      final payload = <int, Map<String, bool>>{..._over};
      for (final id in _serverOver.keys) {
        payload.putIfAbsent(id, () => <String, bool>{});
      }

      await ref
          .read(usuariosRepositoryProvider)
          .saveUserOverrides(widget.user.id, payload);
      if (!mounted) {
        return;
      }
      ref.invalidate(userOverridesProvider(widget.user.id));
      setState(() => _serverOver = {
            for (final e in _over.entries) e.key: {...e.value}
          });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Permisos guardados.'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error al guardar: $e'),
        backgroundColor: AppColors.red,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _resetAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text('Restablecer permisos'),
        content: Text(
          'Se borran todas las excepciones de ${widget.user.fullName} y '
          'quedan solo los permisos del rol. ¿Continuar?',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Restablecer',
                style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );

    if (ok != true) {
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(usuariosRepositoryProvider).resetUserOverrides(widget.user.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _over.clear();
        _serverOver = const {};
      });
      ref.invalidate(userOverridesProvider(widget.user.id));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Permisos restablecidos al rol.'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'),
        backgroundColor: AppColors.red,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final structAsync = ref.watch(permStructureProvider);
    final roleAsync = ref.watch(userRoleActionsProvider(_roleIdsKey));
    final overAsync = ref.watch(userOverridesProvider(widget.user.id));

    final loading =
        structAsync.isLoading || roleAsync.isLoading || overAsync.isLoading;
    final error = structAsync.error ?? roleAsync.error ?? overAsync.error;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.navy2,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Permisos · ${widget.user.fullName}',
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            const Text('El rol es la base · acá se hacen excepciones',
                style: TextStyle(color: AppColors.dim, fontSize: 11)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Restablecer al rol',
            onPressed: _saving ? null : _resetAll,
            icon: const Icon(Icons.restart_alt, color: AppColors.dim),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('No se pudieron cargar los permisos.\n$error',
                      style:
                          const TextStyle(color: AppColors.red, fontSize: 12)),
                )
              : _body(structAsync.value!, roleAsync.value!, overAsync.value!),
      bottomNavigationBar: loading || error != null
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                decoration: const BoxDecoration(
                  color: AppColors.navy2,
                  border: Border(top: BorderSide(color: AppColors.line)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _changedCount == 0
                            ? 'Sin cambios'
                            : '$_changedCount cambio(s) sin guardar',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.dim),
                      ),
                    ),
                    ElevatedButton(
                      onPressed:
                          (_saving || _changedCount == 0) ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        foregroundColor: AppColors.navy,
                      ),
                      child: Text(_saving ? 'Guardando…' : 'Guardar cambios'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _body(
    List<PermApp> apps,
    Map<int, Set<String>> role,
    Map<int, Map<String, bool>> serverOver,
  ) {
    if (!_seeded) {
      _seed(serverOver);
    }

    final (added, removed) = _counts(role);
    final roleTotal = role.values.fold<int>(0, (a, b) => a + b.length);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      children: [
        _headerCard(roleTotal, added, removed),
        _filterRow(),
        const SizedBox(height: 6),
        for (final app in apps) _appBlock(app, role),
        const SizedBox(height: 10),
        _legend(),
      ],
    );
  }

  Widget _headerCard(int roleTotal, int added, int removed) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.user.username != null && widget.user.username!.isNotEmpty)
            Row(
              children: [
                const Icon(Icons.badge_outlined, size: 13, color: AppColors.dim),
                const SizedBox(width: 5),
                Text(widget.user.username!,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.gold)),
              ],
            ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final r in widget.user.roles)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                    border:
                        Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
                  ),
                  child: Text(r.name,
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.gold)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$roleTotal del rol · $added agregado(s) · $removed quitado(s)',
            style: const TextStyle(fontSize: 11.5, color: AppColors.dim),
          ),
        ],
      ),
    );
  }

  Widget _filterRow() {
    Widget chip(String label, _Filter f) {
      final on = _filter == f;

      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: GestureDetector(
          onTap: () => setState(() => _filter = f),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: on ? AppColors.gold.withValues(alpha: 0.16) : AppColors.panel,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: on ? AppColors.gold : AppColors.line),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: on ? AppColors.gold : AppColors.dim)),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip('Todos', _Filter.todos),
        chip('Permitidos', _Filter.permitidos),
        chip('Modificados', _Filter.modificados),
      ],
    );
  }

  Widget _legend() {
    Widget item(Color c, String text) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: c.withValues(alpha: 0.6)),
              ),
            ),
            const SizedBox(width: 5),
            Text(text,
                style: const TextStyle(fontSize: 10.5, color: AppColors.dim)),
          ],
        );

    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        item(AppColors.green, 'Del rol'),
        item(AppColors.gold, 'Agregado a este usuario'),
        item(AppColors.red, 'Quitado a este usuario'),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.lock_outline, size: 12, color: AppColors.dim),
            SizedBox(width: 5),
            Text('Gris = no está en el rol (agregalo al rol primero)',
                style: TextStyle(fontSize: 10.5, color: AppColors.dim)),
          ],
        ),
      ],
    );
  }

  // 필터에 걸리는 function 만 남긴다 (빈 모듈/앱은 통째로 숨김)
  bool _visible(Map<int, Set<String>> role, int fnId) {
    switch (_filter) {
      case _Filter.todos:
        return true;
      case _Filter.permitidos:
        return kActions.any((a) => _effective(role, fnId, a));
      case _Filter.modificados:
        return kActions.any((a) => _isOverridden(role, fnId, a));
    }
  }

  Widget _appBlock(PermApp app, Map<int, Set<String>> role) {
    final modules = <Widget>[];
    for (final mod in app.modules) {
      final block = _moduleBlock(mod, role);
      if (block != null) {
        modules.add(block);
      }
    }
    if (modules.isEmpty) {
      return const SizedBox.shrink();
    }

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
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
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          iconColor: AppColors.gold,
          collapsedIconColor: AppColors.dim,
          initiallyExpanded: _filter == _Filter.modificados,
          children: modules,
        ),
      ),
    );
  }

  Widget? _moduleBlock(PermModule mod, Map<int, Set<String>> role) {
    final g = groupModule(mod);

    final resources = g.resources
        .where((r) => r.crudMap.values
            .expand((ids) => ids)
            .any((id) => _visible(role, id)))
        .toList();
    final business =
        g.businessActions.where((f) => _visible(role, f.id)).toList();

    if (resources.isEmpty && business.isEmpty) {
      return null;
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
        for (final res in resources) _resourceRow(res, role),
        for (final ba in business) _businessRow(ba, role),
      ],
    );
  }

  Widget _resourceRow(ResourceGroup res, Map<int, Set<String>> role) {
    // 그룹 안에 예외가 하나라도 있으면 ● 표시 + ↺(그룹 예외 해제)
    final ids = res.crudMap.values.expand((e) => e).toSet();
    final touched =
        ids.any((id) => kActions.any((a) => _isOverridden(role, id, a)));

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFF182036),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
            color: touched ? AppColors.gold.withValues(alpha: 0.45) : AppColors.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                if (touched)
                  const Padding(
                    padding: EdgeInsets.only(right: 5),
                    child: Icon(Icons.circle, size: 7, color: AppColors.gold),
                  ),
                Flexible(
                  child: Text(res.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          if (touched)
            GestureDetector(
              onTap: () {
                for (final id in ids) {
                  _resetFunction(id);
                }
              },
              child: const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.restart_alt, size: 15, color: AppColors.dim),
              ),
            ),
          for (final a in kActions) _crudChip(res.crudMap[a] ?? const [], a, role),
        ],
      ),
    );
  }

  Widget _crudChip(List<int> bucket, String action, Map<int, Set<String>> role) {
    // 역할에 없는 기능은 잠근다 — 켜도 서버에서 막히므로 켤 수 있게 보이면 안 된다
    final enabled =
        bucket.isNotEmpty && bucket.any((id) => _grantable(role, id));
    // 버킷 안 아무 function 이라도 허용이면 ON (역할 편집기와 같은 규칙)
    final on = enabled && bucket.any((id) => _effective(role, id, action));
    final overridden =
        enabled && bucket.any((id) => _isOverridden(role, id, action));
    final letter = action[0].toUpperCase(); // C R U D

    // 상속=초록 / 추가=골드 / 차단=빨강
    final color = !on && overridden
        ? AppColors.red
        : (overridden ? AppColors.gold : AppColors.green);

    return Padding(
      padding: const EdgeInsets.only(left: 5),
      child: Opacity(
        opacity: enabled ? 1 : 0.28,
        child: GestureDetector(
          onTap: enabled
              ? () {
                  for (final id in bucket) {
                    if (_grantable(role, id)) {
                      _toggle(role, id, action);
                    }
                  }
                }
              : null,
          child: Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on || overridden
                  ? color.withValues(alpha: 0.16)
                  : const Color(0xFF0E1428),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: on || overridden
                    ? color.withValues(alpha: 0.6)
                    : AppColors.line,
                width: overridden ? 1.6 : 1,
              ),
            ),
            child: Text(
              letter,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: on
                    ? color
                    : (overridden ? AppColors.red : AppColors.dim),
                decoration: !on && overridden
                    ? TextDecoration.lineThrough
                    : TextDecoration.none,
                decorationColor: AppColors.red,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 비즈니스 액션 — CRUD 가 아닌 단일 스위치(내부적으로 4액션 일괄)
  Widget _businessRow(PermFunction fn, Map<int, Set<String>> role) {
    final on = kActions.any((a) => _effective(role, fn.id, a));
    final overridden = kActions.any((a) => _isOverridden(role, fn.id, a));
    final grantable = _grantable(role, fn.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF182036),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
            color: overridden
                ? AppColors.gold.withValues(alpha: 0.45)
                : AppColors.line),
      ),
      child: Row(
        children: [
          if (overridden)
            const Padding(
              padding: EdgeInsets.only(right: 5),
              child: Icon(Icons.circle, size: 7, color: AppColors.gold),
            ),
          Expanded(
            child: Text(fn.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
          if (overridden)
            GestureDetector(
              onTap: () => _resetFunction(fn.id),
              child: const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.restart_alt, size: 15, color: AppColors.dim),
              ),
            ),
          Switch(
            value: on,
            activeThumbColor: overridden ? AppColors.gold : AppColors.green,
            onChanged: !grantable
                ? null
                : (_) {
              setState(() {
                for (final a in kActions) {
                  final target = !on;
                  final bucket = _over.putIfAbsent(fn.id, () => <String, bool>{});
                  if (target == _roleHas(role, fn.id, a)) {
                    bucket.remove(a);
                  } else {
                    bucket[a] = target;
                  }
                }
                if ((_over[fn.id] ?? const {}).isEmpty) {
                  _over.remove(fn.id);
                }
              });
            },
          ),
        ],
      ),
    );
  }
}
