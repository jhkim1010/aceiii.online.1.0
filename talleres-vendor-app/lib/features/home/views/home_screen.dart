// 홈 화면 — 4탭 NavigationBar + 매장 선택 드롭다운
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_provider.dart';
import '../../envios/views/envios_screen.dart';
import '../../notifications/providers/notification_provider.dart';
import '../../notifications/views/notifications_screen.dart';
import '../../settlements/views/settlements_screen.dart';

// 현재 선택된 하단 탭 인덱스 Notifier (Riverpod 3.x — StateNotifier 대체)
class _BottomTabNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void setTab(int index) => state = index;
}

final _bottomTabIndexProvider = NotifierProvider<_BottomTabNotifier, int>(
  () => _BottomTabNotifier(),
);

// 홈 화면 — ConsumerWidget으로 인증 상태 구독
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentStore = ref.watch(currentStoreProvider);
    final authState = ref.watch(authNotifierProvider).value;
    final tabIndex = ref.watch(_bottomTabIndexProvider);

    // 미읽음 알림 카운트 — 현재 매장 기준, 에러 시 0으로 처리
    final storeId = currentStore?.storeId;
    final unreadCount = storeId != null
        ? ref.watch(unreadCountProvider(storeId)).value ?? 0
        : 0;

    // 4개 탭 본문 — IndexedStack으로 탭 상태 유지
    final tabBodies = <Widget>[
      const EnviosScreen(),
      const NotificationsScreen(),
      const SettlementsScreen(),
      _ProfileSection(phone: authState?.phone ?? ''),
    ];

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,

        // 매장 선택 — 매장이 2개 이상일 때 드롭다운으로 표시
        title: (authState != null && authState.stores.length > 1)
            ? _StoreDropdown(stores: authState.stores)
            : Text(currentStore?.storeName ?? 'Portal de Talleres'),

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

      // 현재 탭 본문 — IndexedStack으로 탭 상태 유지
      body: IndexedStack(
        index: tabIndex,
        children: tabBodies,
      ),

      // 4섹션 하단 탭 바 — 알림 탭에 미읽음 배지 표시
      bottomNavigationBar: NavigationBar(
        selectedIndex: tabIndex,
        onDestinationSelected: (index) {
          ref.read(_bottomTabIndexProvider.notifier).setTab(index);
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.local_shipping_outlined),
            selectedIcon: Icon(Icons.local_shipping),
            label: 'Envíos',
          ),

          // 알림 탭 — 미읽음 카운트 배지 표시
          NavigationDestination(
            icon: Badge(
              isLabelVisible: unreadCount > 0,
              label: Text('$unreadCount'),
              child: const Icon(Icons.notifications_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: unreadCount > 0,
              label: Text('$unreadCount'),
              child: const Icon(Icons.notifications),
            ),
            label: 'Notificaciones',
          ),

          const NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Liquidaciones',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}

// 매장 선택 드롭다운 — AppBar 제목으로 사용
class _StoreDropdown extends ConsumerWidget {
  final List stores;

  const _StoreDropdown({required this.stores});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(selectedStoreIndexProvider);

    return DropdownButtonHideUnderline(
      child: DropdownButton<int>(
        value: selectedIndex.clamp(0, stores.length - 1),
        icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
        dropdownColor: Theme.of(context).colorScheme.surface,
        style: Theme.of(context).textTheme.titleMedium,
        onChanged: (index) {
          if (index != null) {
            ref.read(selectedStoreIndexProvider.notifier).setIndex(index);
          }
        },
        items: stores.asMap().entries.map((entry) {
          return DropdownMenuItem<int>(
            value: entry.key,
            child: Text(
              // ignore: avoid_dynamic_calls
              entry.value.storeName as String? ?? 'Tienda ${entry.key + 1}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          );
        }).toList(),
      ),
    );
  }
}

// 프로필 섹션
class _ProfileSection extends ConsumerWidget {
  final String phone;

  const _ProfileSection({required this.phone});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentStore = ref.watch(currentStoreProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 사용자 정보 카드
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 28,
                    child: Icon(Icons.person, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        phone,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      if (currentStore != null)
                        Text(
                          currentStore.storeName,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.grey.shade600,
                              ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // 로그아웃 버튼
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.logout),
              label: const Text('Cerrar sesión'),
              onPressed: () async {
                await ref.read(authNotifierProvider.notifier).logout();
              },
            ),
          ),
        ],
      ),
    );
  }
}
