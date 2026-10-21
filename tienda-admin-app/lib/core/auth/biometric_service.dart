import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

// En iPhone no decir «huella» (2026-10-21, app iOS): Face ID, o Touch ID en iPhone SE / iPad.
//   El tipo se conoce en isAvailable() (corre antes de mostrar el botón); hasta entonces, Face ID.
bool _iosConTouchId = false;
String get nombreBiometria =>
    !Platform.isIOS ? 'huella' : (_iosConTouchId ? 'Touch ID' : 'Face ID');

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
      if (Platform.isIOS) {
        final tipos = await _auth.getAvailableBiometrics();
        _iosConTouchId = !tipos.contains(BiometricType.face) &&
            tipos.contains(BiometricType.fingerprint);
      }

      return await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  // 지문 프롬프트. 성공 시 true.
  Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: Platform.isIOS
            ? 'Ingresá con $nombreBiometria para acceder'
            : 'Ingresá con tu huella para acceder',
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
