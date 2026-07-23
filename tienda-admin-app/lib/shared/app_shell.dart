import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import '../features/auth/auth_controller.dart';
import '../features/dashboard/panel_screen.dart';
import '../features/caja/caja_screen.dart';
import '../features/reportes/reportes_screen.dart';
import '../features/usuarios/usuarios_screen.dart';
import '../features/actividad/actividad_screen.dart';
import 'nav_state.dart';

// 매장 admin 셸 — 폰 하단 5탭 네비게이션.
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  // (아이콘, 선택아이콘, 라벨)
  static const _nav = [
    (Icons.dashboard_outlined, Icons.dashboard, 'Panel'),
    (Icons.point_of_sale_outlined, Icons.point_of_sale, 'Caja'),
    (Icons.bar_chart_outlined, Icons.bar_chart, 'Reportes'),
    (Icons.people_outline, Icons.people, 'Usuarios'),
    (Icons.timeline_outlined, Icons.timeline, 'Actividad'),
  ];

  Widget _body(int index) => switch (index) {
        0 => const PanelScreen(),
        1 => const CajaScreen(),
        2 => const ReportesScreen(),
        3 => const UsuariosScreen(),
        _ => const ActividadScreen(),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final index = ref.watch(navIndexProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.navy2,
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_nav[index].$3,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            Text(
              [user?.displayStore, user?.name]
                  .where((e) => e != null && e.isNotEmpty)
                  .join(' · '),
              style: const TextStyle(color: AppColors.dim, fontSize: 11.5),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Salir',
            onPressed: () =>
                ref.read(authControllerProvider.notifier).logout(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _body(index),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: AppColors.navy2,
          indicatorColor: AppColors.gold.withValues(alpha: 0.16),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);

            return TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: selected ? AppColors.gold : AppColors.dim,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);

            return IconThemeData(
              color: selected ? AppColors.gold : AppColors.dim,
            );
          }),
        ),
        child: NavigationBar(
          height: 64,
          selectedIndex: index,
          onDestinationSelected: (i) =>
              ref.read(navIndexProvider.notifier).state = i,
          destinations: _nav
              .map((d) => NavigationDestination(
                    icon: Icon(d.$1),
                    selectedIcon: Icon(d.$2),
                    label: d.$3,
                  ))
              .toList(),
        ),
      ),
    );
  }
}
