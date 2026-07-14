// 출퇴근 Repository — POST /attendance/punch 호출 (37-06 계약).
// 백엔드 에러 코드(QR_EXPIRED/QR_INVALID/QR_OTHER_STORE/NOT_A_SELLER/RESELLER_NOT_APPROVED)를
// ApiException.code 로 보존해 화면에서 es-AR 카피로 매핑한다.
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import 'attendance_dto.dart';

// 출퇴근 Repository Provider
final attendanceRepositoryProvider = Provider<AttendanceRepository>((ref) {
  return AttendanceRepository(ref.read(dioClientProvider));
});

class AttendanceRepository {
  final DioClient _client;

  AttendanceRepository(this._client);

  // fichaje QR punch — POST /attendance/punch { s, b, d, t } → PunchResult.
  // MobileScopeGuard 가 role 라우팅(vendedor 출퇴근 / revendedor 매장권)을 서버에서 판정.
  Future<PunchResult> punch(FichajeQr qr) async {
    try {
      final response = await _client.dio.post(
        '/attendance/punch',
        data: qr.toJson(),
      );

      return PunchResult.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  // DioException → ApiException (code + message 보존, es-AR 카피 매핑용)
  ApiException _toApiException(DioException e) {
    final data = e.response?.data;
    String? code;
    String? message;
    if (data is Map) {
      code = (data['code'] ?? data['error'])?.toString();
      message = data['message']?.toString();
    }

    return ApiException(
      message ?? 'Error de conexión',
      statusCode: e.response?.statusCode,
      code: code,
    );
  }
}
