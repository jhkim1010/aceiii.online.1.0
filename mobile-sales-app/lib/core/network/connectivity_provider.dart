// 연결 상태 Provider (criterion #11) — 판매 확정(Mandar a Caja) 온라인 게이트.
// 오프라인 시 카탈로그/재고는 lastFetch 캐시로 브라우징 가능하나 판매 확정은 차단.
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 온라인 여부 스트림. 초기 로딩/에러 시 online(true)으로 낙관 처리(판매 시도는 서버가 최종 판정).
final isOnlineProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();

  bool online(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  yield online(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(online);
});
