import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import '../features/auth/auth_controller.dart';
import '../features/console/dashboard_screen.dart';
import '../features/console/diagnostics_screen.dart';
import '../features/console/sessions_screen.dart';
import '../features/console/tenants_screen.dart';
import '../features/console/mensajes_screen.dart';
import '../features/console/actividad_screen.dart';
import 'nav_state.dart';

// 반응형 셸 — 넓으면 NavigationRail, 좁으면 Drawer(항목 6개라 BottomNav 대신).
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  static const _nav = [
    (Icons.dashboard_outlined, Icons.dashboard, 'Panel'),
    (Icons.monitor_heart_outlined, Icons.monitor_heart, 'Diagnóstico'),
    (Icons.people_outline, Icons.people, 'Sesiones'),
    (Icons.storefront_outlined, Icons.storefront, 'Clientes'),
    (Icons.forward_to_inbox_outlined, Icons.forward_to_inbox, 'Mensajes'),
    (Icons.timeline_outlined, Icons.timeline, 'Actividad'),
  ];

  Widget _body(int index) => switch (index) {
        0 => const DashboardScreen(),
        1 => const DiagnosticsScreen(),
        2 => const SessionsScreen(),
        3 => const TenantsScreen(),
        4 => const MensajesScreen(),
        _ => const ActividadScreen(),
      };

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 720;
    final user = ref.watch(authControllerProvider).user;
    final index = ref.watch(navIndexProvider);

    final appBar = AppBar(
      backgroundColor: AppColors.navy2,
      title: Text(_nav[index].$3),
      actions: [
        Center(child: Text(user?.name ?? 'superadmin', style: const TextStyle(color: AppColors.dim, fontSize: 13))),
        IconButton(
          icon: const Icon(Icons.logout),
          tooltip: 'Salir',
          onPressed: () => ref.read(authControllerProvider.notifier).logout(),
        ),
        const SizedBox(width: 8),
      ],
    );

    if (wide) {
      return Scaffold(
        appBar: appBar,
        body: Row(
          children: [
            NavigationRail(
              backgroundColor: AppColors.navy2,
              selectedIndex: index,
              onDestinationSelected: (i) => ref.read(navIndexProvider.notifier).state = i,
              labelType: NavigationRailLabelType.all,
              destinations: _nav
                  .map((d) => NavigationRailDestination(
                        icon: Icon(d.$1),
                        selectedIcon: Icon(d.$2),
                        label: Text(d.$3),
                      ))
                  .toList(),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _body(index)),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: appBar,
      drawer: Drawer(
        backgroundColor: AppColors.navy2,
        child: SafeArea(
          child: ListView(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Ventago Admin', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              ..._nav.asMap().entries.map((e) => ListTile(
                    selected: index == e.key,
                    leading: Icon(index == e.key ? e.value.$2 : e.value.$1),
                    title: Text(e.value.$3),
                    onTap: () {
                      ref.read(navIndexProvider.notifier).state = e.key;
                      Navigator.pop(context);
                    },
                  )),
            ],
          ),
        ),
      ),
      body: _body(index),
    );
  }
}
