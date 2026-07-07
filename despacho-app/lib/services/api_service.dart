import 'package:dio/dio.dart';

import '../models/order.dart';

/// 백엔드 통신 서비스 — dio 기반. baseUrl/token 을 주입받아 사용.
/// 모든 호출에 에러 핸들링 포함(사용자 규약). 신규 커넥션 남용 없음(서버 pool 재사용).
class ApiService {
  ApiService({required String baseUrl, required String token})
      : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 15),
            headers: {
              'Content-Type': 'application/json',
              'x-api-key': '12345',
              if (token.isNotEmpty) 'Authorization': 'Bearer $token',
            },
          ),
        );

  final Dio _dio;

  /// preparing 상태의 매장 전체 주문 목록.
  /// Phase 1: 기존 board 엔드포인트를 재사용하고 클라이언트에서 preparing 만 필터.
  /// Phase 2: 전용 GET /despacho/orders 로 교체 예정.
  Future<List<OnlineOrder>> fetchPreparingOrders() async {
    try {
      final res = await _dio.get('/online-orders/board');
      final data = res.data;
      final list = _asList(data);
      final orders = list
          .whereType<Map<String, dynamic>>()
          .map(OnlineOrder.fromJson)
          .where(_isPreparing)
          .toList();

      return orders;
    } on DioException catch (e) {
      throw _mapError(e, '준비 목록을 불러오지 못했습니다');
    }
  }

  /// 주문 상세 — picking 항목 포함.
  Future<OnlineOrder> fetchOrderDetail(int id) async {
    try {
      final res = await _dio.get('/online-orders/$id');
      final data = res.data;
      final map = data is Map<String, dynamic>
          ? data
          : (data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{});

      return OnlineOrder.fromJson(map);
    } on DioException catch (e) {
      throw _mapError(e, '주문 상세를 불러오지 못했습니다');
    }
  }

  /// Preparando → Listo p/ despacho 전환.
  Future<void> markReady(int id) async {
    try {
      await _dio.patch('/online-orders/$id/mark-ready');
    } on DioException catch (e) {
      throw _mapError(e, 'Listo 처리에 실패했습니다');
    }
  }

  /// preparing 판별 — columnKey 우선, 없으면 status 기준.
  bool _isPreparing(OnlineOrder o) {
    final col = (o.columnKey ?? '').toLowerCase();
    if (col.isNotEmpty) return col == 'preparando';

    return (o.status ?? '').toLowerCase() == 'preparing';
  }

  /// 응답이 배열/래핑객체 어느 쪽이든 리스트로 정규화.
  List<dynamic> _asList(Object? data) {
    if (data is List) return data;
    if (data is Map && data['data'] is List) return data['data'] as List;
    if (data is Map && data['rows'] is List) return data['rows'] as List;

    return const <dynamic>[];
  }

  /// dio 에러 → 사용자 표시용 메시지.
  Exception _mapError(DioException e, String fallback) {
    final resp = e.response;
    final msg = resp?.data is Map ? (resp!.data as Map)['message'] : null;
    final text = msg is List ? msg.join(', ') : (msg?.toString() ?? e.message ?? fallback);

    return Exception('$fallback: $text');
  }
}
