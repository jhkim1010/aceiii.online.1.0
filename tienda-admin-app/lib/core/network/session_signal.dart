import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 인터셉터(비 UI)에서 토스트를 띄우기 위한 전역 messenger 키
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

// go_router refreshListenable — expired 로 바뀌면 redirect 재평가
class SessionExpiredSignal extends ChangeNotifier {
  bool _expired = false;

  bool get expired => _expired;

  void trigger() {
    if (_expired) return;
    _expired = true;
    notifyListeners();
  }

  void reset() {
    if (!_expired) return;
    _expired = false;
    notifyListeners();
  }
}

final sessionExpiredSignalProvider = Provider<SessionExpiredSignal>((ref) {
  return SessionExpiredSignal();
});
