// 출퇴근 punch 상태 — 스캔한 QR 을 POST /attendance/punch 로 보내고 결과를 노출.
// vendedor 성공 punch(in/out) 후에는 scopeNotifierProvider 를 invalidate 해
// /mobile/me 의 clockedIn 을 재조회 → 홈 게이트가 잠금/해제된다.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/scope_provider.dart';
import '../data/attendance_dto.dart';
import '../data/attendance_repository.dart';

// punch 호출 상태(로딩/성공/에러). 화면은 이 provider 로 결과/진행을 관찰.
final punchControllerProvider =
    AsyncNotifierProvider<PunchController, PunchResult?>(PunchController.new);

class PunchController extends AsyncNotifier<PunchResult?> {
  @override
  Future<PunchResult?> build() async => null;

  // QR punch 실행. 성공 시 PunchResult 반환(홈 재게이트를 위한 scope 무효화 포함).
  // 실패 시 ApiException(code 포함)을 rethrow 해 호출부가 es-AR 토스트로 매핑.
  Future<PunchResult> punch(FichajeQr qr) async {
    state = const AsyncLoading();
    try {
      final result = await ref.read(attendanceRepositoryProvider).punch(qr);
      state = AsyncData(result);

      // vendedor 출퇴근(in/out) → clockedIn 이 바뀌므로 scope 재조회 강제.
      // revendedor(store_authorized) 는 출근 세션 무관이라 무효화 불필요하나,
      // 무해하므로 in/out 에만 한정한다(불필요한 /mobile/me 라운드트립 절약).
      if (result.isIn || result.isOut) {
        ref.invalidate(scopeNotifierProvider);
      }

      return result;
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }
}
