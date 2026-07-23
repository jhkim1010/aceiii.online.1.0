import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import 'console_repository.dart';
import '../../shared/nav_state.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenants = ref.watch(tenantsProvider);
    final sessions = ref.watch(sessionsProvider);

    final online = sessions.maybeWhen(data: (s) => s.where((x) => x.status == 'online').length, orElse: () => 0);
    final errors = tenants.maybeWhen(data: (t) => t.fold<int>(0, (a, b) => a + b.errors24h), orElse: () => 0);
    final clients = tenants.maybeWhen(data: (t) => t.length, orElse: () => 0);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(tenantsProvider);
        ref.invalidate(sessionsProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Dashboard', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.7,
            children: [
              GestureDetector(
                // 대시보드 Clientes 카드 더블탭 → Clientes 리스트 탭(3)으로 이동
                onDoubleTap: () => ref.read(navIndexProvider.notifier).state = 3,
                child: _kpi('Clientes', '$clients', AppColors.txt),
              ),
              _kpi('Empleados online', '$online', AppColors.green),
              _kpi('Errores 24h', '$errors', errors > 0 ? AppColors.red : AppColors.txt),
              _kpi('Estado', 'OK', AppColors.cyan),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kpi(String label, String value, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label.toUpperCase(), style: const TextStyle(color: AppColors.dim, fontSize: 11)),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(color: color, fontSize: 26, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}
