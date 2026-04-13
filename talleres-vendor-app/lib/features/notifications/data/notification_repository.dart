// 알림 Repository — 알림 관련 API 연동
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import 'notification_dto.dart';

// NotificationRepository Provider
final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(ref.read(dioClientProvider));
});

// 알림 API 연동 레포지토리
class NotificationRepository {
  final DioClient _client;

  NotificationRepository(this._client);

  // 매장별 알림 목록 조회 — isRead 필터 선택적 적용
  Future<List<NotificationDto>> fetchNotifications(
    int storeId, {
    bool? isRead,
  }) async {
    try {
      final params = <String, dynamic>{'storeId': storeId};

      // 읽음 여부 필터가 있을 때만 파라미터 추가
      if (isRead != null) {
        params['isRead'] = isRead;
      }

      final response = await _client.dio.get(
        '/vendor-portal/notifications',
        queryParameters: params,
      );

      final data = response.data;
      final List<dynamic> rows;

      if (data is List) {
        rows = data;
      } else if (data is Map<String, dynamic> && data.containsKey('rows')) {
        rows = data['rows'] as List<dynamic>;
      } else {
        rows = [];
      }

      return rows
          .map((e) => NotificationDto.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      final message = e.response?.data?['message'] as String? ??
          e.message ??
          'Error al cargar notificaciones';

      throw Exception(message);
    }
  }

  // 미읽음 알림 수 조회 — 홈 배지에 사용
  Future<int> fetchUnreadCount(int storeId) async {
    try {
      final response = await _client.dio.get(
        '/vendor-portal/notifications/unread-count',
        queryParameters: {'storeId': storeId},
      );

      final data = response.data;

      if (data is Map<String, dynamic>) {
        return data['count'] as int? ?? 0;
      }

      return 0;
    } on DioException catch (e) {
      final message = e.response?.data?['message'] as String? ??
          e.message ??
          'Error al cargar conteo';

      throw Exception(message);
    }
  }

  // 단일 알림 읽음 처리
  Future<void> markAsRead(int id) async {
    try {
      await _client.dio.patch('/vendor-portal/notifications/$id/read');
    } on DioException catch (e) {
      final message = e.response?.data?['message'] as String? ??
          e.message ??
          'Error al marcar como leído';

      throw Exception(message);
    }
  }

  // 매장의 모든 알림 읽음 처리
  Future<void> markAllAsRead(int storeId) async {
    try {
      await _client.dio.patch(
        '/vendor-portal/notifications/read-all',
        data: {'storeId': storeId},
      );
    } on DioException catch (e) {
      final message = e.response?.data?['message'] as String? ??
          e.message ??
          'Error al marcar todo como leído';

      throw Exception(message);
    }
  }
}
