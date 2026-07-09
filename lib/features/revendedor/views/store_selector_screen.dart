// Modo Revendedor — Store selector STUB (BLOCKED, D-07).
// Phase 24(reseller.catalog_unified MV + reseller_tienda_link)가 스키마에 도착하기 전엔
// 실제 다중 매장 선택 로직을 구현하지 않는다. 지금은 placeholder 만 렌더한다.
// 활성화 체크리스트: lib/features/revendedor/README.md 참조.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/scope_provider.dart';

// 혁명적 로직 없음 — MultiStoreScope 진입점의 자리표시자.
class StoreSelectorScreen extends ConsumerWidget {
  const StoreSelectorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(scopeNotifierProvider).value;
    final name = switch (scope) {
      MultiStoreScope(:final user) => user.name,
      _ => 'Revendedor',
    };

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Modo revendedor'),
        actions: [
          IconButton(
            onPressed: () => ref.read(scopeNotifierProvider.notifier).logout(),
            icon: const Icon(Icons.logout),
            tooltip: 'Salir',
          ),
        ],
      ),
      body: _ComingSoon(
        title: 'Hola, $name',
        // 활성화 게이트: Phase 24 가 도착하면 실제 매장 선택기로 교체된다.
        subtitle: 'Modo revendedor — Próximamente (requiere Phase 24)',
        actionLabel: 'Ver cotización',
        onAction: () => context.push('/revendedor/quote'),
      ),
    );
  }
}

// Ventago 테마 자리표시자 (store_selector / quote 공용 룩).
class _ComingSoon extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _ComingSoon({
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: AppColors.amberSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.storefront_outlined,
                  color: AppColors.goldDark, size: 34),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 14),
            ),
            const SizedBox(height: 24),
            if (actionLabel != null && onAction != null)
              OutlinedButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
          ],
        ),
      ),
    );
  }
}
