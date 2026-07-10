import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import 'console_repository.dart';

class SessionsScreen extends ConsumerWidget {
  const SessionsScreen({super.key});

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
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(sessionsProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(sessionsProvider),
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: AppColors.red))),
        data: (rows) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Sesiones (${rows.where((r) => r.status == 'online').length} online)',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...rows.map((s) => Card(
                  child: ListTile(
                    leading: Icon(_platformIcon(s.platform), color: AppColors.gold),
                    title: Text(s.name),
                    subtitle: Text('${s.storeName ?? '-'} · ${s.branchName ?? '-'} · ${s.publicIp ?? '-'} · ${_ago(s.idleSecs)}',
                        style: const TextStyle(color: AppColors.dim, fontSize: 12)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 9, height: 9, decoration: BoxDecoration(color: _statusColor(s.status), shape: BoxShape.circle)),
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
            if (rows.isEmpty)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Ningún empleado logueado', style: TextStyle(color: AppColors.dim)))),
          ],
        ),
      ),
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
