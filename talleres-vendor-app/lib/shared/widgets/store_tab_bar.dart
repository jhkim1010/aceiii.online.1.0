// 매장 전환 탭 바 — 연결된 매장이 2개 이상일 때만 표시
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/providers/auth_provider.dart';

// 하단 매장 탭 바 위젯
class StoreTabBar extends ConsumerWidget {
  const StoreTabBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stores = ref.watch(authNotifierProvider).value?.stores ?? [];
    final selectedIndex = ref.watch(selectedStoreIndexProvider);

    // 매장이 1개 이하이면 탭 미표시
    if (stores.length <= 1) {
      return const SizedBox.shrink();
    }

    return BottomNavigationBar(
      currentIndex: selectedIndex.clamp(0, stores.length - 1),
      onTap: (i) => ref.read(selectedStoreIndexProvider.notifier).setIndex(i),
      type: BottomNavigationBarType.fixed,
      items: stores
          .map(
            (s) => BottomNavigationBarItem(
              icon: const Icon(Icons.store_outlined),
              activeIcon: const Icon(Icons.store),
              label: s.aliasName ?? s.storeName,
            ),
          )
          .toList(),
    );
  }
}
