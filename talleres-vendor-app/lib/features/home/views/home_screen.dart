// 홈 화면 — 매장 탭 쉘, 향후 기능 화면의 진입점
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/widgets/store_tab_bar.dart';

// 홈 화면 — ConsumerWidget으로 인증 상태 구독
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentStore = ref.watch(currentStoreProvider);
    final authState = ref.watch(authNotifierProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Portal de Talleres'),
        centerTitle: false,
        actions: [
          // 로그아웃 버튼
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () async {
              await ref.read(authNotifierProvider.notifier).logout();
            },
          ),
        ],
      ),

      // 현재 선택된 매장 정보와 향후 기능 안내
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 매장 정보 카드
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.store,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Tienda actual',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: Colors.grey.shade600,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      currentStore?.storeName ?? 'Sin tienda seleccionada',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    if (currentStore?.aliasName != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        currentStore!.aliasName!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.grey.shade600,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 사용자 정보
            if (authState != null) ...[
              Text(
                'Bienvenido',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              ),
              Text(
                authState.phone,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 32),
            ],

            // 향후 기능 안내
            Text(
              'Próximamente',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            const _ComingSoonItem(
              icon: Icons.send_outlined,
              label: 'Envíos — Ver lotes enviados por la tienda',
            ),
            const _ComingSoonItem(
              icon: Icons.check_circle_outline,
              label: 'Recepciones — Confirmar recepción de trabajos',
            ),
            const _ComingSoonItem(
              icon: Icons.notifications_outlined,
              label: 'Notificaciones — Avisos de nuevos envíos y vencimientos',
            ),
            const _ComingSoonItem(
              icon: Icons.account_balance_wallet_outlined,
              label: 'Liquidaciones — Ver historial de pagos',
            ),
          ],
        ),
      ),

      // 매장 전환 탭 바 — 매장이 2개 이상일 때만 표시
      bottomNavigationBar: const StoreTabBar(),
    );
  }
}

// 향후 기능 항목 위젯
class _ComingSoonItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ComingSoonItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey.shade500),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
