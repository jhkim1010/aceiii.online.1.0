// 알림 화면 — 알림 목록, 읽음/미읽음 구분, 일괄 읽음 처리
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../data/notification_dto.dart';
import '../data/notification_repository.dart';
import '../providers/notification_provider.dart';

// 알림 화면 — ConsumerWidget으로 Riverpod 상태 구독
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentStore = ref.watch(currentStoreProvider);

    // 현재 선택된 매장이 없으면 안내 메시지 표시
    if (currentStore == null) {
      return const Center(child: Text('Selecciona una tienda'));
    }

    final storeId = currentStore.storeId;
    final notificationsAsync = ref.watch(notificationListProvider(storeId));
    final unreadCountAsync = ref.watch(unreadCountProvider(storeId));

    // 미읽음 카운트 — 에러 시 0으로 처리
    final unreadCount = unreadCountAsync.value ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificaciones'),
        centerTitle: false,
        actions: [
          // 미읽음 알림이 있을 때만 일괄 읽음 버튼 표시
          if (unreadCount > 0)
            TextButton(
              onPressed: () => _markAllAsRead(context, ref, storeId),
              child: const Text('Marcar todo como leído'),
            ),
        ],
      ),
      body: notificationsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'Error: $error',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () =>
                    ref.invalidate(notificationListProvider(storeId)),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
        data: (notifications) => _NotificationList(
          notifications: notifications,
          storeId: storeId,
          onRefresh: () async {
            ref.invalidate(notificationListProvider(storeId));
            ref.invalidate(unreadCountProvider(storeId));
          },
          onMarkRead: (id) => _markAsRead(context, ref, storeId, id),
        ),
      ),
    );
  }

  // 단일 알림 읽음 처리
  Future<void> _markAsRead(
    BuildContext context,
    WidgetRef ref,
    int storeId,
    int notificationId,
  ) async {
    try {
      await ref.read(notificationRepositoryProvider).markAsRead(notificationId);

      // 목록과 카운트 새로고침
      ref.invalidate(notificationListProvider(storeId));
      ref.invalidate(unreadCountProvider(storeId));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  // 모든 알림 일괄 읽음 처리
  Future<void> _markAllAsRead(
    BuildContext context,
    WidgetRef ref,
    int storeId,
  ) async {
    try {
      await ref
          .read(notificationRepositoryProvider)
          .markAllAsRead(storeId);

      // 목록과 카운트 새로고침
      ref.invalidate(notificationListProvider(storeId));
      ref.invalidate(unreadCountProvider(storeId));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }
}

// 알림 목록 위젯 — pull-to-refresh 지원
class _NotificationList extends StatelessWidget {
  final List<NotificationDto> notifications;
  final int storeId;
  final Future<void> Function() onRefresh;
  final void Function(int id) onMarkRead;

  const _NotificationList({
    required this.notifications,
    required this.storeId,
    required this.onRefresh,
    required this.onMarkRead,
  });

  @override
  Widget build(BuildContext context) {
    // 알림이 없을 때 빈 상태 화면
    if (notifications.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.5,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_off_outlined,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No hay notificaciones',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.grey.shade500,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        itemCount: notifications.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final notification = notifications[index];

          return _NotificationTile(
            notification: notification,
            onTap: () {
              // 미읽음 알림을 탭하면 읽음 처리
              if (!notification.isRead) {
                onMarkRead(notification.id);
              }
            },
          );
        },
      ),
    );
  }
}

// 알림 항목 타일 — 읽음/미읽음 시각적 구분
class _NotificationTile extends StatelessWidget {
  final NotificationDto notification;
  final VoidCallback onTap;

  const _NotificationTile({
    required this.notification,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isUnread = !notification.isRead;

    return ListTile(
      // 알림 타입별 아이콘
      leading: Icon(
        notification.icon,
        color: isUnread
            ? Theme.of(context).colorScheme.primary
            : Colors.grey.shade500,
      ),

      // 제목 — 미읽음이면 굵게 표시
      title: Text(
        notification.title,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
            ),
      ),

      // 내용 + 시간
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (notification.body != null && notification.body!.isNotEmpty)
            Text(
              notification.body!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 2),
          Text(
            _formatRelativeTime(notification.createdAt),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade500,
                ),
          ),
        ],
      ),

      // 미읽음 표시 — 파란 원형 점
      trailing: isUnread
          ? Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
            )
          : null,

      // 읽음 처리되지 않은 알림은 배경색으로 구분
      tileColor: isUnread
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.05)
          : null,

      onTap: onTap,
    );
  }

  // 상대적 시간 포맷 — 스페인어로 표시
  String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) {
      return 'hace un momento';
    } else if (diff.inHours < 1) {
      final minutes = diff.inMinutes;

      return 'hace $minutes ${minutes == 1 ? 'minuto' : 'minutos'}';
    } else if (diff.inDays < 1) {
      final hours = diff.inHours;

      return 'hace $hours ${hours == 1 ? 'hora' : 'horas'}';
    } else if (diff.inDays < 7) {
      final days = diff.inDays;

      return 'hace $days ${days == 1 ? 'día' : 'días'}';
    } else {
      // 7일 이상이면 날짜 표시
      return DateFormat('dd/MM/yyyy', 'es').format(dateTime);
    }
  }
}
