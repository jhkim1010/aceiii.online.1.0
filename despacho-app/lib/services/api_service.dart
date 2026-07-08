import 'package:dio/dio.dart';

import '../models/order.dart';
import '../models/transporte.dart';
import '../models/operario.dart';

/// 백엔드 통신 서비스 — dio 기반.
/// 인증은 기기 토큰(x-device-key 헤더). 서버가 /despacho/* 에서 매장 스코프 + 단계 필터를 처리.
/// 모든 호출에 에러 핸들링 포함(사용자 규약). 서버 pool 재사용(신규 커넥션 남용 X).
class ApiService {
  ApiService({required String baseUrl, required String deviceKey, String? operarioName})
      : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 15),
            headers: {
              'Content-Type': 'application/json',
              'x-api-key': '12345',
              if (deviceKey.isNotEmpty) 'x-device-key': deviceKey,
              // 감사 추적 — 현재 작업자 이름(액션의 stageActors 에 기록됨).
              if (operarioName != null && operarioName.isNotEmpty) 'x-operario': operarioName,
            },
          ),
        );

  final Dio _dio;

  /// 단계별 주문 목록. stage: 'preparando'(준비) | 'listo'(발송 대기).
  Future<List<OnlineOrder>> fetchOrders(String stage) async {
    try {
      final res = await _dio.get('/despacho/orders',
          queryParameters: {'stage': stage});
      final list = _asList(res.data);

      return list
          .whereType<Map<String, dynamic>>()
          .map(OnlineOrder.fromJson)
          .toList();
    } on DioException catch (e) {
      throw _mapError(e, '목록을 불러오지 못했습니다');
    }
  }

  /// 주문 상세 — picking 항목 포함.
  Future<OnlineOrder> fetchOrderDetail(int id) async {
    try {
      final res = await _dio.get('/despacho/orders/$id');
      final data = res.data;
      final map = data is Map<String, dynamic>
          ? data
          : (data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{});

      return OnlineOrder.fromJson(map);
    } on DioException catch (e) {
      throw _mapError(e, '주문 상세를 불러오지 못했습니다');
    }
  }

  /// 매장 활성 운송업체 목록.
  Future<List<Transporte>> fetchTransportes() async {
    try {
      final res = await _dio.get('/despacho/transportes');

      return _asList(res.data)
          .whereType<Map<String, dynamic>>()
          .map(Transporte.fromJson)
          .toList();
    } on DioException catch (e) {
      throw _mapError(e, '운송업체를 불러오지 못했습니다');
    }
  }

  /// Preparando → Listo p/ despacho 전환.
  Future<void> markReady(int id) async {
    try {
      await _dio.patch('/despacho/orders/$id/mark-ready');
    } on DioException catch (e) {
      throw _mapError(e, 'Listo 처리에 실패했습니다');
    }
  }

  /// Listo → 발송(운송사 인계). transporte + tracking 필수.
  Future<void> ship(int id, {required int transporteId, required String trackingCode}) async {
    try {
      await _dio.patch('/despacho/orders/$id/ship', data: {
        'transporteId': transporteId,
        'trackingCode': trackingCode,
      });
    } on DioException catch (e) {
      throw _mapError(e, '발송 처리에 실패했습니다');
    }
  }

  /// 작업자 목록(이름 선택 그리드).
  Future<List<Operario>> fetchOperarios() async {
    try {
      final res = await _dio.get('/despacho/operarios');

      return _asList(res.data)
          .whereType<Map<String, dynamic>>()
          .map(Operario.fromJson)
          .toList();
    } on DioException catch (e) {
      throw _mapError(e, '작업자 목록을 불러오지 못했습니다');
    }
  }

  /// 작업자 PIN 검증 — 성공 시 Operario.
  Future<Operario> verifyOperario(int operarioId, String pin) async {
    try {
      final res = await _dio.post('/despacho/operarios/verify',
          data: {'operarioId': operarioId, 'pin': pin});
      final data = res.data;
      final map = data is Map<String, dynamic>
          ? data
          : (data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{});

      return Operario.fromJson(map);
    } on DioException catch (e) {
      throw _mapError(e, 'PIN 검증 실패');
    }
  }

  /// Enviado → Entregado(배송 완료).
  Future<void> deliver(int id) async {
    try {
      await _dio.patch('/despacho/orders/$id/deliver');
    } on DioException catch (e) {
      throw _mapError(e, '배송 완료 처리에 실패했습니다');
    }
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
