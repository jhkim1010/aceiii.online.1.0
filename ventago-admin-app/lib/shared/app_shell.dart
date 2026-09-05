import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import '../core/tenant/acting_store.dart';
import '../features/auth/auth_controller.dart';
import '../features/console/dashboard_screen.dart';
import '../features/console/diagnostics_screen.dart';
import '../features/console/facturacion_screen.dart';
import '../features/console/sessions_screen.dart';
import '../features/console/tenants_screen.dart';
import '../features/console/mensajes_screen.dart';
import '../features/console/actividad_screen.dart';
import '../features/console/aprobaciones_screen.dart';
import '../features/console/cobranzas_screen.dart';
import 'acting_store_bar.dart';
import 'nav_state.dart';

// 반응형 셸 — 넓으면 NavigationRail, 좁으면 Drawer(항목이 8개라 BottomNav 대신).
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
    (Icons.how_to_reg_outlined, Icons.how_to_reg, 'Aprobaciones'),
    (Icons.point_of_sale_outlined, Icons.point_of_sale, 'Cobranzas'),
    (Icons.receipt_long_outlined, Icons.receipt_long, 'Fac. electrónica'),
  ];

  Widget _body(int index) => switch (index) {
        0 => const DashboardScreen(),
        1 => const DiagnosticsScreen(),
        2 => const SessionsScreen(),
        3 => const TenantsScreen(),
        4 => const MensajesScreen(),
        5 => const ActividadScreen(),
        6 => const AprobacionesScreen(),
        7 => const CobranzasScreen(),
        _ => const FacturacionScreen(),
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
        // [Phase 67-C] 매장 대행 시작/변경 — 대행 중이면 아이콘을 골드로 강조
        IconButton(
          icon: Icon(
            Icons.storefront_outlined,
            color: ref.watch(actingStoreProvider) != null ? AppColors.gold : null,
          ),
          tooltip: 'Actuar como tienda',
          onPressed: () => showActingStorePicker(context, ref),
        ),
        // [Phase 72-03] 로그아웃은 두 가지다 — 무엇이 단말에 남는지가 갈린다.
        // 예전처럼 아이콘 하나로 처리하면 "자격증명은 남긴다"가 사용자에게 안 보인다.
        PopupMenuButton<String>(
          icon: const Icon(Icons.logout),
          tooltip: 'Salir',
          onSelected: (value) {
            final ctrl = ref.read(authControllerProvider.notifier);
            if (value == 'forget') {
              ctrl.forgetDevice();
            } else {
              ctrl.logout();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'logout',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.logout, size: 20),
                title: Text('Cerrar sesión'),
                subtitle: Text('Podés volver a entrar con huella'),
              ),
            ),
            PopupMenuItem(
              value: 'forget',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.no_accounts, size: 20, color: AppColors.red),
                title: Text('Olvidar este dispositivo'),
                subtitle: Text('Revoca el acceso por huella en el servidor'),
              ),
            ),
          ],
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
        bottomNavigationBar: const ActingStoreBar(),
      );
    }

    return Scaffold(
      appBar: appBar,
      bottomNavigationBar: const ActingStoreBar(),
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
