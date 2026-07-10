import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import '../features/auth/auth_controller.dart';
import '../features/console/dashboard_screen.dart';
import '../features/console/sessions_screen.dart';
import '../features/console/tenants_screen.dart';
import '../features/console/mensajes_screen.dart';

// 반응형 셸 — 넓으면 NavigationRail, 좁으면 BottomNavigationBar.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;

  static const _titles = ['Dashboard', 'Sesiones', 'Clientes', 'Mensajes'];

  Widget _body() => switch (_index) {
        0 => const DashboardScreen(),
        1 => const SessionsScreen(),
        2 => const TenantsScreen(),
        _ => const MensajesScreen(),
      };

  static const _destinations = [
    (Icons.dashboard_outlined, Icons.dashboard, 'Panel'),
    (Icons.people_outline, Icons.people, 'Sesiones'),
    (Icons.storefront_outlined, Icons.storefront, 'Clientes'),
    (Icons.forward_to_inbox_outlined, Icons.forward_to_inbox, 'Mensajes'),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 720;
    final user = ref.watch(authControllerProvider).user;

    final appBar = AppBar(
      backgroundColor: AppColors.navy2,
      title: Text(_titles[_index]),
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
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              destinations: _destinations
                  .map((d) => NavigationRailDestination(
                        icon: Icon(d.$1),
                        selectedIcon: Icon(d.$2),
                        label: Text(d.$3),
                      ))
                  .toList(),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _body()),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: appBar,
      body: _body(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: _destinations
            .map((d) => NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3))
            .toList(),
      ),
    );
  }
}
