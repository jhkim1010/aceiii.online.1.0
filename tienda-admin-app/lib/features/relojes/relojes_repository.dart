import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/dio_client.dart';
import '../../shared/format.dart';

// claim/목록 조회 실패 사유 — 화면이 사유별 안내 문구를 고르는 데 쓴다.
enum ClaimError { invalid, notAdmin, tooMany, network }

class RelojesException implements Exception {
  final ClaimError error;
  const RelojesException(this.error);

  @override
  String toString() => 'RelojesException($error)';
}

// 워치 1대 — GET /watch/devices 의 한 행.
class WatchDevice {
  final int id;
  final String? model;
  final String issuedAt;
  final String? lastSeenAt;
  final String expiresAt;

  WatchDevice.fromJson(Map<String, dynamic> j)
      : id = asInt(j['id']),
        model = j['model'] as String?,
        issuedAt = (j['issuedAt'] ?? '').toString(),
        lastSeenAt = j['lastSeenAt'] as String?,
        expiresAt = (j['expiresAt'] ?? '').toString();

  // model 이 없는 워치(구형/미확인)는 'Reloj' 로 표시.
  String get displayName =>
      (model != null && model!.isNotEmpty) ? model! : 'Reloj';
}

final relojesRepositoryProvider = Provider<RelojesRepository>((ref) {
  return RelojesRepository(ref.read(dioClientProvider));
});

class RelojesRepository {
  final Dio _dio;

  RelojesRepository(this._dio);

  // 코드는 body 로만 전송 — URL/프록시 로그에 안 남는다 (T-98-31).
  Future<void> claimCode(String raw) async {
    final userCode = _normalize(raw);
    try {
      await _dio.post<dynamic>(
        '/watch/pairing-codes/claim',
        data: {'userCode': userCode},
      );
    } on DioException catch (e) {
      throw RelojesException(_mapClaimError(e));
    }
  }

  // 403 은 빈 목록으로 삼키지 않는다 — 화면이 "admin 만" 안내를 보여줘야 한다.
  Future<List<WatchDevice>> listDevices() async {
    try {
      final res = await _dio.get<dynamic>('/watch/devices');
      final list = (res.data as List?) ?? const [];

      return list
          .map((e) => WatchDevice.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        throw const RelojesException(ClaimError.notAdmin);
      }
      throw const RelojesException(ClaimError.network);
    }
  }

  Future<void> revoke(int id) async {
    await _dio.delete<dynamic>('/watch/devices/$id');
  }

  // 공백·하이픈 제거 + 대문자 — 워치 화면 표기(K7Q4-29XM)와 서버 저장 형식(K7Q429XM) 차이를 흡수.
  String _normalize(String raw) =>
      raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  ClaimError _mapClaimError(DioException e) {
    switch (e.response?.statusCode) {
      case 404:
        return ClaimError.invalid;
      case 403:
        return ClaimError.notAdmin;
      case 429:
        return ClaimError.tooMany;
      default:
        return ClaimError.network;
    }
  }
}
