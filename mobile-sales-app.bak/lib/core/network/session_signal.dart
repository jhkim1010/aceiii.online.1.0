// 세션 만료 신호 — dio 인터셉터(비 UI 컨텍스트)에서 발생시켜 라우터/토스트로 전파
// MOBILE-C-07 (criterion 12): 401 MOBILE_SESSION_EXPIRED → /login redirect + toast.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 앱 어디서든(인터셉터 포함) 토스트를 띄우기 위한 전역 messenger 키
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

// go_router refreshListenable 로 사용 — expired 가 true 로 바뀌면 redirect 재평가
class SessionExpiredSignal extends ChangeNotifier {
  bool _expired = false;

  bool get expired => _expired;

  // 세션 만료 발생 (dio onError)
  void trigger() {
    if (_expired) {
      return;
    }
    _expired = true;
    notifyListeners();
  }

  // 로그인 성공 시 초기화
  void reset() {
    if (!_expired) {
      return;
    }
    _expired = false;
    notifyListeners();
  }
}

// 전역 세션 만료 신호 Provider
final sessionExpiredSignalProvider = Provider<SessionExpiredSignal>(
  (ref) => SessionExpiredSignal(),
);
