// Recepcion Repository — 수령 확인 API 연동
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';

// RecepcionRepository Provider
final recepcionRepositoryProvider = Provider<RecepcionRepository>((ref) {
  return RecepcionRepository(ref.read(dioClientProvider));
});

// 수령 확인 API 연동 레포지토리
class RecepcionRepository {
  final DioClient _client;

  RecepcionRepository(this._client);

  // 수령 확인 생성 요청
  Future<Map<String, dynamic>> createRecepcion({
    required int envioId,
    required int receivedQuantity,
    int rejectedQuantity = 0,
    String? notes,
  }) async {
    try {
      final body = <String, dynamic>{
        'envioId': envioId,
        'receivedQuantity': receivedQuantity,
        'rejectedQuantity': rejectedQuantity,
      };

      // 메모가 있을 때만 포함
      if (notes != null && notes.isNotEmpty) {
        body['notes'] = notes;
      }

      final response = await _client.dio.post(
        '/vendor-portal/recepciones',
        data: body,
      );

      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      // DioException을 더 명확한 메시지로 변환
      final message =
          e.response?.data?['message'] as String? ?? e.message ?? 'Error al registrar recepción';
      throw Exception(message);
    }
  }
}
