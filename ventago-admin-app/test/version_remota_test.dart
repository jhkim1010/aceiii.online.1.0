// [2026-10-06] Actualización dentro de la app — el feed nunca puede apuntar a otro lado.
import 'package:flutter_test/flutter_test.dart';
import 'package:ventago_admin_app/core/update/version_remota.dart';

const _apk = 'https://github.com/jhkim1010/ventago-downloads/releases/download/x-latest/app.apk';
final _sha = 'a' * 64;

Map<String, Object?> _feed({Object? code = 9, Object? apk = _apk, Object? sha}) =>
    {'versionCode': code, 'versionName': '1.1.0', 'apk': apk, 'sha256': sha ?? _sha, 'notas': 'x'};

void main() {
  test('feed válido', () {
    final v = VersionRemota.desdeJson(_feed())!;
    expect(v.versionCode, 9);
    expect(v.esMasNuevaQue(8), isTrue);
    expect(v.esMasNuevaQue(9), isFalse, reason: 'misma versión: no ofrecer');
    expect(v.esMasNuevaQue(10), isFalse, reason: 'nunca ofrecer bajar de versión');
  });

  test('★ APK fuera de nuestro repositorio de descargas → nada', () {
    for (final url in [
      'http://github.com/jhkim1010/ventago-downloads/releases/download/x/app.apk',
      'https://evil.com/jhkim1010/ventago-downloads/releases/download/x/app.apk',
      'https://github.com/otro/ventago-downloads/releases/download/x/app.apk',
      'https://github.com.evil.com/jhkim1010/ventago-downloads/releases/download/x/app.apk',
    ]) {
      expect(VersionRemota.desdeJson(_feed(apk: url)), isNull, reason: url);
    }
  });

  test('sin hash válido o versión inválida → nada', () {
    expect(VersionRemota.desdeJson(_feed(sha: 'abc')), isNull);
    expect(VersionRemota.desdeJson(_feed(code: '9')), isNull);
    expect(VersionRemota.desdeJson(_feed(code: 0)), isNull);
    expect(VersionRemota.desdeJson('no es un mapa'), isNull);
    expect(VersionRemota.desdeJson(null), isNull);
  });

  test('hash en mayúsculas se normaliza (sha256sum vs comparación)', () {
    expect(VersionRemota.desdeJson(_feed(sha: 'A' * 64))!.sha256, 'a' * 64);
  });
}
