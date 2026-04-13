// Recepcion Provider — 수령 확인 액션 상태 관리 (Riverpod 3.x)
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../envios/providers/envio_provider.dart';
import '../data/recepcion_repository.dart';

// 수령 확인 생성 요청 파라미터 타입
typedef RecepcionParams = ({
  int envioId,
  int receivedQuantity,
  int rejectedQuantity,
  String? notes,
});

// 수령 확인 AsyncNotifier — 요청 실행 + 완료 후 envio 목록 새로고침
class CreateRecepcionNotifier extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {
    // 초기 상태는 null (대기 중)
  }

  // 수령 확인 생성 실행
  Future<void> create(RecepcionParams params) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(recepcionRepositoryProvider).createRecepcion(
            envioId: params.envioId,
            receivedQuantity: params.receivedQuantity,
            rejectedQuantity: params.rejectedQuantity,
            notes: params.notes,
          );

      // 수령 완료 후 envio 목록 전체 새로고침
      ref.invalidate(envioListProvider);
    });
  }
}

// Provider 등록
final createRecepcionProvider = AsyncNotifierProvider<CreateRecepcionNotifier, void>(
  () => CreateRecepcionNotifier(),
);
