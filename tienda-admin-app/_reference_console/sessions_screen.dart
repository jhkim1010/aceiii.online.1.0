import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import 'console_repository.dart';

// Sesiones — 현재 활성 로그인 세션 관제.
// 매장 콤보로 한 매장만 골라 보고 통제할 수 있다.
// Clientes 상세에서 initialStoreId 로 넘어오면 그 매장으로 미리 필터링된다.
class SessionsScreen extends ConsumerStatefulWidget {
  final int? initialStoreId;
  const SessionsScreen({super.key, this.initialStoreId});

  @override
  ConsumerState<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends ConsumerState<SessionsScreen> {
  int? _storeFilter; // null = 전체(Todas)

  @override
  void initState() {
    super.initState();
    _storeFilter = widget.initialStoreId;
  }

  Color _statusColor(String s) => switch (s) {
        'online' => AppColors.green,
        'away' => AppColors.amber,
        _ => AppColors.dim,
      };

  IconData _platformIcon(String p) => switch (p) {
        'android' => Icons.android,
        'ios' || 'macos' => Icons.apple,
        'windows' => Icons.desktop_windows,
        _ => Icons.public,
      };

  String _ago(int secs) {
    if (secs < 60) return 'hace ${secs}s';
    if (secs < 3600) return 'hace ${secs ~/ 60} min';

    return 'hace ${secs ~/ 3600} h';
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(sessionsProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(sessionsProvider),
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: AppColors.red))),
        data: (rows) {
          final filtered =
              _storeFilter == null ? rows : rows.where((r) => r.storeId == _storeFilter).toList();
          final onlineCount = filtered.where((r) => r.status == 'online').length;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(children: [
                const Text('Sesiones', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('$onlineCount online',
                    style: const TextStyle(color: AppColors.green, fontWeight: FontWeight.w700, fontSize: 13)),
              ]),
              const SizedBox(height: 12),
              _storePicker(rows),
              const SizedBox(height: 8),
              Text('${filtered.length} sesión(es)${_storeFilter == null ? " · todas las tiendas" : ""}',
                  style: const TextStyle(color: AppColors.dim, fontSize: 12)),
              const SizedBox(height: 8),
              ...filtered.map((s) => Card(
                    child: ListTile(
                      leading: Icon(_platformIcon(s.platform), color: AppColors.gold),
                      title: Text(s.name),
                      subtitle: Text(
                          '${s.storeName ?? '-'} · ${s.branchName ?? '-'} · ${s.publicIp ?? '-'} · ${_ago(s.idleSecs)}',
                          style: const TextStyle(color: AppColors.dim, fontSize: 12)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(color: _statusColor(s.status), shape: BoxShape.circle)),
                          const SizedBox(width: 12),
                          IconButton(
                            icon: const Icon(Icons.logout, color: AppColors.red, size: 20),
                            tooltip: 'Forzar logout',
                            onPressed: () => _confirmLogout(context, ref, s),
                          ),
                        ],
                      ),
                    ),
                  )),
              if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                        _storeFilter == null
                            ? 'Ningún empleado logueado'
                            : 'Nadie logueado en esta tienda',
                        style: const TextStyle(color: AppColors.dim)),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ── 매장 선택 콤보 (Todas + 매장명) ──
  Widget _storePicker(List<SessionRow> rows) {
    // 매장 목록: tenantsProvider(전체) 우선, 없으면 세션에 등장한 매장으로 대체.
    final Map<int, String> stores = {};
    ref.watch(tenantsProvider).whenData((ts) {
      for (final t in ts) {
        stores[t.storeId] = t.storeName;
      }
    });
    for (final r in rows) {
      if (r.storeId != 0) {
        stores.putIfAbsent(r.storeId, () => r.storeName ?? '#${r.storeId}');
      }
    }
    final entries = stores.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));

    // 선택된 매장이 목록에 없으면(예: 세션 0 + 테넌트 미로드) 항목 보강
    if (_storeFilter != null && !stores.containsKey(_storeFilter)) {
      entries.insert(0, MapEntry(_storeFilter!, '#$_storeFilter'));
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.panel,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        const Icon(Icons.store_mall_directory_outlined, size: 18, color: AppColors.dim),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int?>(
              isExpanded: true,
              value: _storeFilter,
              dropdownColor: AppColors.panel,
              style: const TextStyle(color: AppColors.txt, fontSize: 14),
              icon: const Icon(Icons.arrow_drop_down, color: AppColors.dim),
              hint: const Text('Todas las tiendas', style: TextStyle(color: AppColors.txt)),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Todas las tiendas')),
                ...entries.map((e) => DropdownMenuItem<int?>(value: e.key, child: Text(e.value))),
              ],
              onChanged: (v) => setState(() => _storeFilter = v),
            ),
          ),
        ),
        if (_storeFilter != null)
          InkWell(
            onTap: () => setState(() => _storeFilter = null),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, size: 16, color: AppColors.dim),
            ),
          ),
      ]),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref, SessionRow s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Forzar cierre de sesión'),
        content: Text('¿Cerrar la sesión de ${s.name}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Forzar logout'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(consoleRepositoryProvider).forceLogout(s.userId);
      ref.invalidate(sessionsProvider);
    }
  }
}
