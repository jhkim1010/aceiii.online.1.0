import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

final biometricServiceProvider = Provider<BiometricService>((ref) {
  return BiometricService();
});

// 생체(지문) 인증 래퍼.
class BiometricService {
  final LocalAuthentication _auth = LocalAuthentication();

  // 이 기기에서 지문 인증이 가능한가 (센서 존재 + 등록됨).
  Future<bool> isAvailable() async {
    try {
      if (!await _auth.isDeviceSupported()) return false;

      return await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  // 지문 프롬프트. 성공 시 true.
  Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Ingresá con tu huella para acceder',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
