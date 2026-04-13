// 알림 Provider — 알림 목록 및 미읽음 카운트 상태 관리 (Riverpod 3.x)
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/notification_dto.dart';
import '../data/notification_repository.dart';

// 매장별 알림 목록 — storeId 기반 family provider
// autoDispose: 화면을 벗어나면 자동으로 메모리 해제
final notificationListProvider =
    FutureProvider.family.autoDispose<List<NotificationDto>, int>(
  (ref, storeId) async {
    return ref.read(notificationRepositoryProvider).fetchNotifications(storeId);
  },
);

// 미읽음 알림 카운트 — 홈 화면 배지에 사용
// autoDispose: 탭 이동 시 자동 해제 후 재조회로 최신 상태 유지
final unreadCountProvider =
    FutureProvider.family.autoDispose<int, int>((ref, storeId) async {
  return ref.read(notificationRepositoryProvider).fetchUnreadCount(storeId);
});
