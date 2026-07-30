import 'package:flutter_riverpod/flutter_riverpod.dart';

// [Phase 67-C] superadmin 매장 대행(act-as-store) 상태
//
// 백엔드는 요청 헤더 `X-Store-Id: 6` 을 받으면 그 요청 동안 superadmin 을
// 매장 6 사용자와 **완전히 동일하게** 취급한다(조회도 쓰기도 그 매장으로 한정).
// JwtGlobalGuard 가 request.user.storeId 를 채우므로 백엔드 컨트롤러는 무수정이다.
//
// 저장하지 않는 이유
//   secure_storage 에 남기면 앱을 껐다 켜도 대행 상태가 유지돼, 본인도 모르게
//   남의 매장 데이터를 만들 수 있다. 고객 데이터를 대신 다루는 기능이므로
//   메모리에만 두고 앱 재시작 시 자동 해제되게 한다.

class ActingStore {
  final int id;
  final String name;

  const ActingStore({required this.id, required this.name});
}

class ActingStoreNotifier extends StateNotifier<ActingStore?> {
  ActingStoreNotifier() : super(null);

  void actAs(int id, String name) => state = ActingStore(id: id, name: name);

  void stop() => state = null;
}

final actingStoreProvider =
    StateNotifierProvider<ActingStoreNotifier, ActingStore?>(
  (ref) => ActingStoreNotifier(),
);
