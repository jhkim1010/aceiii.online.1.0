// 디바이스 fingerprint — 설치 단위 안정 식별자를 SHA-256 해시로 생성
// Ventago 웹의 device-fingerprint 패턴(브라우저 특성 SHA-256)을 모바일에 이식.
// 모바일에서는 안정 traits 가 제한적이라 최초 1회 생성한 salt 를 secure storage 에
// 영속화하고 플랫폼 정보와 결합해 해시한다. (user_id, fingerprint) 로 세션 UPSERT.
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../storage/secure_storage.dart';

const String _deviceSaltKey = 'device_salt';

// fingerprint 서비스 Provider
final deviceFingerprintProvider = Provider<DeviceFingerprintService>(
  (ref) => DeviceFingerprintService(ref.read(secureStorageProvider)),
);

class DeviceFingerprintService {
  final SecureStorageService _storage;

  DeviceFingerprintService(this._storage);

  // 안정 fingerprint 반환 (없으면 salt 생성 후 영속화)
  Future<String> getFingerprint() async {
    var salt = await _storage.read(_deviceSaltKey);
    if (salt == null || salt.isEmpty) {
      salt = _randomSalt();
      await _storage.write(_deviceSaltKey, salt);
    }

    final traits = '$salt|${_platformLabel()}';

    return sha256.convert(utf8.encode(traits)).toString();
  }

  // 플랫폼 라벨 (traits 일부) — 테스트/웹 환경 방어
  String _platformLabel() {
    try {
      return '${Platform.operatingSystem}:${Platform.operatingSystemVersion}';
    } catch (_) {
      return 'unknown';
    }
  }

  // 128비트 랜덤 hex salt
  String _randomSalt() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));

    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
