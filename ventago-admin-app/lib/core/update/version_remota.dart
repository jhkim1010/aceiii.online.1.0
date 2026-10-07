// [2026-10-06] Actualización dentro de la app (Android, APK fuera de Play) — reglas puras.
// (mismo archivo en mobile-sales-app, tienda-admin-app y ventago-admin-app)
//
// El build (build-apk.sh) publica en GitHub Releases (jhkim1010/ventago-downloads):
//   <app>-latest/version.json  →  {"versionCode": 9, "versionName": "1.1.0",
//                                  "apk": "https://…/app.apk", "sha256": "…", "notas": "…"}
// La app lo lee al abrir; si hay una versión más nueva PREGUNTA (nunca instala sola).

class VersionRemota {
  final int versionCode;
  final String versionName;
  final String apkUrl;
  final String sha256;
  final String notas;

  const VersionRemota({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    required this.sha256,
    this.notas = '',
  });

  // null = feed inválido → no se ofrece nada (nunca adivinar una URL o un hash)
  static VersionRemota? desdeJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final code = json['versionCode'];
    final name = json['versionName'];
    final apk = json['apk'];
    final sha = json['sha256'];
    if (code is! int || code <= 0 || name is! String || apk is! String || sha is! String) {
      return null;
    }
    // ★ sólo https y sólo nuestro repositorio de descargas
    final uri = Uri.tryParse(apk);
    if (uri == null || uri.scheme != 'https' || !esOrigenPermitido(uri)) {
      return null;
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha.toLowerCase())) {
      return null;
    }
    final notas = json['notas'];

    return VersionRemota(
      versionCode: code,
      versionName: name,
      apkUrl: apk,
      sha256: sha.toLowerCase(),
      notas: notas is String ? notas : '',
    );
  }

  bool esMasNuevaQue(int instalada) => versionCode > instalada;
}

bool esOrigenPermitido(Uri uri) =>
    uri.host == 'github.com' && uri.path.startsWith('/jhkim1010/ventago-downloads/releases/download/');
