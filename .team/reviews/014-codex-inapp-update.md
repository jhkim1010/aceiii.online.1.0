Reading additional input from stdin...
2026-10-06T17:44:41.285346Z ERROR codex_models_manager::cache: failed to load models cache: missing field `base_instructions` at line 140 column 5
OpenAI Codex v0.146.0
--------
workdir: /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
model: gpt-5.6-sol
provider: openai
approval: never
sandbox: workspace-write [workdir, /tmp, $TMPDIR]
reasoning effort: none
reasoning summaries: none
session id: 01a11251-5206-71d0-a063-1664a217fc85
--------
user
Revisá este cambio: actualización dentro de la app para dos apps Flutter Android distribuidas como APK fuera de Play (vendedor y tienda-admin). Requisitos: preguntar siempre (nunca instalar sola), verificar SHA-256, sólo URLs de nuestro repo de GitHub Releases, firmar con la clave de subida, el build sube versionCode y publica version.json después del APK. Buscá bugs concretos (archivo:línea, escenario, arreglo). Español, breve.
=== mobile-sales-app/lib/core/update/version_remota.dart
// [2026-10-06] Actualización dentro de la app (Android, APK fuera de Play) — reglas puras.
// (mismo archivo en mobile-sales-app y tienda-admin-app)
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
=== mobile-sales-app/lib/core/update/actualizacion.dart
// [2026-10-06] Actualización dentro de la app (Android, APK fuera de Play).
// (mismo archivo en mobile-sales-app y tienda-admin-app)
//
// Al abrir: lee version.json; si hay una versión más nueva pregunta «Actualizar / Más tarde».
// «Actualizar» baja el APK, verifica el SHA-256 y abre el instalador de Android — la persona
// toca «Instalar». Android sólo acepta el APK si está firmado con la MISMA clave que la app
// instalada, así que un APK ajeno no puede reemplazarla.
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'version_remota.dart';

const _canal = MethodChannel('ventago/actualizacion');

// Un chequeo por arranque de la app («Más tarde» = hasta la próxima vez que se abra)
bool _yaChequeado = false;

Future<void> chequearActualizacion(GlobalKey<NavigatorState> navegador, {required String feedUrl}) async {
  if (_yaChequeado || !Platform.isAndroid) {
    return;
  }
  _yaChequeado = true;

  final VersionRemota? remota;
  final int instalada;
  try {
    final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 8)));
    final r = await dio.get<Object?>(
      feedUrl,
      options: Options(responseType: ResponseType.json, headers: {'Cache-Control': 'no-cache'}),
    );
    remota = VersionRemota.desdeJson(r.data);
    instalada = await _canal.invokeMethod<int>('versionCode') ?? 0;
  } catch (_) {
    // sin red o feed caído: la app sigue normal, se vuelve a mirar en el próximo arranque
    return;
  }
  final nueva = remota;
  if (nueva == null || instalada <= 0 || !nueva.esMasNuevaQue(instalada)) {
    return;
  }

  final ctx = navegador.currentContext;
  if (ctx == null || !ctx.mounted) {
    return;
  }
  final acepta = await showDialog<bool>(
    context: ctx,
    builder: (c) => AlertDialog(
      title: const Text('Nueva versión disponible'),
      content: Text(
        'Versión ${nueva.versionName}${nueva.notas.isEmpty ? '' : '\n\n${nueva.notas}'}\n\n'
        'Se descarga y Android te pide confirmar la instalación.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Más tarde')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Actualizar')),
      ],
    ),
  );
  if (acepta != true) {
    return;
  }
  final ctx2 = navegador.currentContext;
  if (ctx2 == null || !ctx2.mounted) {
    return;
  }
  await showDialog<void>(
    context: ctx2,
    barrierDismissible: false,
    builder: (_) => _DescargaDialog(remota: nueva),
  );
}

class _DescargaDialog extends StatefulWidget {
  final VersionRemota remota;

  const _DescargaDialog({required this.remota});

  @override
  State<_DescargaDialog> createState() => _DescargaDialogState();
}

class _DescargaDialogState extends State<_DescargaDialog> {
  final CancelToken _cancel = CancelToken();
  double? _progreso;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bajarEInstalar();
  }

  @override
  void dispose() {
    _cancel.cancel();
    super.dispose();
  }

  Future<void> _bajarEInstalar() async {
    setState(() {
      _error = null;
      _progreso = null;
    });
    try {
      final dir = await _canal.invokeMethod<String>('dirDescarga');
      if (dir == null) {
        throw const _Falla('No se pudo preparar la descarga');
      }
      final ruta = '$dir/actualizacion.apk';
      await Dio().download(
        widget.remota.apkUrl,
        ruta,
        cancelToken: _cancel,
        onReceiveProgress: (r, t) {
          if (mounted && t > 0) {
            setState(() => _progreso = r / t);
          }
        },
      );
      final bytes = await File(ruta).readAsBytes();
      // ★ el archivo bajado tiene que ser exactamente el publicado
      if (sha256.convert(bytes).toString() != widget.remota.sha256) {
        await File(ruta).delete();
        throw const _Falla('La descarga llegó dañada. Probá de nuevo.');
      }
      final r = await _canal.invokeMethod<String>('instalar', {'ruta': ruta});
      if (!mounted) {
        return;
      }
      if (r == 'permiso') {
        setState(() => _error =
            'Activá «Permitir de esta fuente» para esta app en la pantalla que se abrió, volvé y tocá «Reintentar».');

        return;
      }
      Navigator.pop(context);
    } on _Falla catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } on DioException catch (e) {
      // «Cancelar» cierra el diálogo y corta la descarga: no es un error
      if (mounted && !CancelToken.isCancel(e)) {
        setState(() => _error = 'No se pudo descargar la actualización. Revisá la conexión.');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo instalar la actualización.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;

    return AlertDialog(
      title: Text('Actualizando a ${widget.remota.versionName}'),
      content: error != null
          ? Text(error)
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(value: _progreso),
                const SizedBox(height: 10),
                Text(_progreso == null ? 'Descargando…' : 'Descargando… ${(_progreso! * 100).floor()}%'),
              ],
            ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(error != null ? 'Cerrar' : 'Cancelar')),
        if (error != null) FilledButton(onPressed: _bajarEInstalar, child: const Text('Reintentar')),
      ],
    );
  }
}

class _Falla implements Exception {
  final String mensaje;

  const _Falla(this.mensaje);
}
=== mobile-sales-app/android/app/src/main/kotlin/com/ventago/mobile_sales_app/Actualizacion.kt
package com.ventago.mobile_sales_app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// [2026-10-06] Actualización dentro de la app (lib/core/update/actualizacion.dart).
// Canal «ventago/actualizacion»:
//   versionCode → versión instalada
//   dirDescarga → carpeta en caché para el APK (expuesta por FileProvider: res/xml/actualizacion_paths.xml)
//   instalar    → abre el instalador de Android ('ok'), o los ajustes de «instalar apps
//                 desconocidas» si falta el permiso ('permiso'). Android pide confirmar siempre.
object Actualizacion {
    fun registrar(engine: FlutterEngine, context: Context) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "ventago/actualizacion").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "versionCode" -> {
                        val info = context.packageManager.getPackageInfo(context.packageName, 0)
                        val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode.toInt() else @Suppress("DEPRECATION") info.versionCode
                        result.success(code)
                    }
                    "dirDescarga" -> {
                        val dir = File(context.cacheDir, "actualizacion")
                        dir.mkdirs()
                        result.success(dir.absolutePath)
                    }
                    "instalar" -> {
                        if (Build.VERSION.SDK_INT >= 26 && !context.packageManager.canRequestPackageInstalls()) {
                            val ajustes = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + context.packageName))
                            ajustes.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            context.startActivity(ajustes)
                            result.success("permiso")
                        } else {
                            val archivo = File(call.argument<String>("ruta")!!)
                            val uri = FileProvider.getUriForFile(context, context.packageName + ".actualizacion", archivo)
                            val intent = Intent(Intent.ACTION_VIEW)
                            intent.setDataAndType(uri, "application/vnd.android.package-archive")
                            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                            context.startActivity(intent)
                            result.success("ok")
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("actualizacion", e.message, null)
            }
        }
    }
}
=== scripts/publicar-apk.sh
#!/usr/bin/env bash
# [2026-10-06] Actualización dentro de la app — publica un APK para que las apps lo ofrezcan.
#
# Uso (lo llaman mobile-sales-app/build-apk.sh y tienda-admin-app/build-apk.sh):
#   scripts/publicar-apk.sh <apk> <tag-release> <nombre-asset.apk> <cert-sha256-esperado> ["notas"]
#
# Sube a GitHub Releases (jhkim1010/ventago-downloads, público):
#   <tag>/<nombre-asset.apk>   y después   <tag>/version.json
# El orden importa: version.json nunca apunta a un APK que todavía no está.
#
# ★ Se niega a publicar si:
#   · el APK no está firmado con el certificado esperado — Android rechaza instalar una
#     actualización con otra clave, así que publicarlo sólo produce «App no instalada»
#     en cada teléfono.
#   · el versionCode no es mayor que el publicado — la app no lo ofrecería.
set -euo pipefail

APK="$1"
TAG="$2"
ASSET="$3"
CERT_ESPERADO="$4"
NOTAS="${5:-}"
REPO="jhkim1010/ventago-downloads"

BT="${ANDROID_BUILD_TOOLS:-/opt/homebrew/share/android-commandlinetools/build-tools/36.0.0}"
export JAVA_HOME="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"

[[ -f "$APK" ]] || { echo "ERROR: no existe el APK: $APK" >&2; exit 1; }

badging="$("$BT/aapt2" dump badging "$APK" | head -1)"
code="$(sed -E "s/.*versionCode='([0-9]+)'.*/\1/" <<<"$badging")"
name="$(sed -E "s/.*versionName='([^']*)'.*/\1/" <<<"$badging")"
[[ "$code" =~ ^[0-9]+$ ]] || { echo "ERROR: no pude leer versionCode del APK" >&2; exit 1; }

cert="$("$BT/apksigner" verify --print-certs "$APK" | grep -m1 'certificate SHA-256 digest' | awk '{print $NF}')"
if [[ "$cert" != "$CERT_ESPERADO"* ]]; then
  echo "ERROR: el APK está firmado con ${cert:0:16}…, se esperaba ${CERT_ESPERADO:0:16}…" >&2
  echo "       Los teléfonos no podrían instalar esta actualización. No se publica." >&2
  exit 1
fi

feed="https://github.com/$REPO/releases/download/$TAG/version.json"
publicado="$(curl -fsSL "$feed" 2>/dev/null | sed -nE 's/.*"versionCode": *([0-9]+).*/\1/p' || true)"
if [[ -n "$publicado" && "$code" -le "$publicado" ]]; then
  echo "ERROR: versionCode $code no es mayor que el publicado ($publicado). Subí la versión en pubspec.yaml." >&2
  exit 1
fi

sha="$(shasum -a 256 "$APK" | awk '{print $1}')"
url="https://github.com/$REPO/releases/download/$TAG/$ASSET"

tmp="$(mktemp -d)"
cp "$APK" "$tmp/$ASSET"
python3 - "$tmp/version.json" "$code" "$name" "$url" "$sha" "$NOTAS" <<'EOF'
import json, sys
p, code, name, url, sha, notas = sys.argv[1:]
json.dump({"versionCode": int(code), "versionName": name, "apk": url, "sha256": sha, "notas": notas},
          open(p, "w"), ensure_ascii=False, indent=2)
EOF

gh release view "$TAG" -R "$REPO" >/dev/null 2>&1 \
  || gh release create "$TAG" -R "$REPO" --title "$TAG" --notes "Actualización dentro de la app (version.json + APK)"
gh release upload "$TAG" "$tmp/$ASSET" -R "$REPO" --clobber
gh release upload "$TAG" "$tmp/version.json" -R "$REPO" --clobber

# comprobar lo que realmente quedó publicado
vuelta="$(curl -fsSL "$feed" | sed -nE 's/.*"versionCode": *([0-9]+).*/\1/p')"
[[ "$vuelta" == "$code" ]] || { echo "ERROR: el feed publicado dice versionCode=$vuelta, no $code" >&2; exit 1; }
echo "✔ Publicado v$name (versionCode $code) → $feed"
=== DIFF
diff --git a/android/app/build.gradle.kts b/android/app/build.gradle.kts
index abd9e4e..0f9a31f 100644
--- a/android/app/build.gradle.kts
+++ b/android/app/build.gradle.kts
@@ -65,3 +65,8 @@ android {
 flutter {
     source = "../.."
 }
+
+// [2026-10-06] FileProvider para la actualización dentro de la app
+dependencies {
+    implementation("androidx.core:core-ktx:1.13.1")
+}
diff --git a/android/app/src/main/AndroidManifest.xml b/android/app/src/main/AndroidManifest.xml
index a378611..80aa4b4 100644
--- a/android/app/src/main/AndroidManifest.xml
+++ b/android/app/src/main/AndroidManifest.xml
@@ -2,6 +2,8 @@
     <!-- release APK 네트워크 필수: main 매니페스트에 없으면 release 만 차단됨 -->
     <uses-permission android:name="android.permission.INTERNET"/>
     <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
+    <!-- [2026-10-06] actualización dentro de la app: abrir el instalador con el APK descargado -->
+    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>
     <!-- reseller 홈 GPS 지역감지 (geolocator) — 대략적 위치로 충분하나 기기 지원을 위해 FINE 도 요청 -->
     <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
     <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
@@ -31,6 +33,15 @@
                 <category android:name="android.intent.category.LAUNCHER"/>
             </intent-filter>
         </activity>
+        <provider
+            android:name="androidx.core.content.FileProvider"
+            android:authorities="${applicationId}.actualizacion"
+            android:exported="false"
+            android:grantUriPermissions="true">
+            <meta-data
+                android:name="android.support.FILE_PROVIDER_PATHS"
+                android:resource="@xml/actualizacion_paths" />
+        </provider>
         <!-- Don't delete the meta-data below.
              This is used by the Flutter tool to generate GeneratedPluginRegistrant.java -->
         <meta-data
diff --git a/android/app/src/main/kotlin/com/ventago/mobile_sales_app/MainActivity.kt b/android/app/src/main/kotlin/com/ventago/mobile_sales_app/MainActivity.kt
index 2eda5c4..a7c3d7d 100644
--- a/android/app/src/main/kotlin/com/ventago/mobile_sales_app/MainActivity.kt
+++ b/android/app/src/main/kotlin/com/ventago/mobile_sales_app/MainActivity.kt
@@ -1,5 +1,12 @@
 package com.ventago.mobile_sales_app
 
 import io.flutter.embedding.android.FlutterActivity
+import io.flutter.embedding.engine.FlutterEngine
 
-class MainActivity : FlutterActivity()
+class MainActivity : FlutterActivity() {
+    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
+        super.configureFlutterEngine(flutterEngine)
+        // [2026-10-06] actualización dentro de la app
+        Actualizacion.registrar(flutterEngine, applicationContext)
+    }
+}
diff --git a/build-apk.sh b/build-apk.sh
index 7e3614b..a17ad61 100755
--- a/build-apk.sh
+++ b/build-apk.sh
@@ -4,6 +4,7 @@
 # 사용법:
 #   ./build-apk.sh                # 빌드 후 복사
 #   ./build-apk.sh --skip-build   # 기존 빌드 산출물만 복사
+#   NOTAS="Modo lector +1" ./build-apk.sh   # 앱의 「Nueva versión」 창에 보일 안내(선택)
 #
 # 복사 대상 (DEST_DIRS + FIXED_DEST):
 #   1) Dropbox/ACE_3_uversion/app herramientas download  — 버전명
@@ -30,6 +31,29 @@ FIXED_DEST="/Users/marcoskim/Google Drive/내 드라이브/ventago-superadmin/ve
 
 cd "$APP_DIR"
 
+# [2026-10-06] 앱 안 업데이트: 빌드할 때마다 build 번호를 올린다(같으면 휴대폰이 새 버전으로 안 본다).
+#   publicar-apk.sh 가 「게시된 것보다 큰가」를 다시 확인한다.
+subir_build() {
+  local v b
+  v="$(grep -E '^version:' pubspec.yaml | head -1 | awk '{print $2}')"
+  b="${v##*+}"
+  # ★ 고정 문자열 비교로 치환 — 정규식이면 버전의 「.」「+」가 메타문자가 된다
+  python3 - "$v" "${v%%+*}+$((b + 1))" <<'PY'
+import sys
+viejo, nuevo = sys.argv[1:]
+t = open('pubspec.yaml').read()
+linea = 'version: ' + viejo + '\n'
+assert t.count(linea) == 1, 'version: no encontrado exactamente una vez'
+open('pubspec.yaml', 'w').write(t.replace(linea, 'version: ' + nuevo + '\n'))
+PY
+  echo "▶ version: $v → $(grep -E '^version:' pubspec.yaml | awk '{print $2}')"
+}
+
+# 버전명(파일명)을 읽기 전에 올린다
+if [[ "${1:-}" != "--skip-build" ]]; then
+  subir_build
+fi
+
 raw_version="$(grep -E '^version:' pubspec.yaml | head -1 | awk '{print $2}')"
 if [[ -z "$raw_version" ]]; then
   echo "ERROR: pubspec.yaml 에서 version 을 읽지 못했습니다" >&2
@@ -85,3 +109,8 @@ if [[ "$missing" -eq 1 ]]; then
 fi
 
 echo "✔ 전체 복사 완료 ($apk_name)"
+
+# [2026-10-06] 앱 안 업데이트용 게시 (GitHub Releases → 앱이 열릴 때 「Nueva versión」 을 묻는다)
+#   업로드 키(Play 와 같은 키)로 서명된 APK 만 게시한다 — 다른 키면 휴대폰이 설치를 거부한다.
+CERT_UPLOAD="23747e710c3c77d8e989626b98d26464baee869d70e44857b8a5b0dc4e3927c7"
+"$APP_DIR/../scripts/publicar-apk.sh" "$APK_SRC" "vendedor-app-latest" "vendedor-app.apk" "$CERT_UPLOAD" "${NOTAS:-}"
diff --git a/lib/main.dart b/lib/main.dart
index 383af23..1a7b6db 100644
--- a/lib/main.dart
+++ b/lib/main.dart
@@ -4,6 +4,7 @@ import 'package:flutter/material.dart';
 import 'package:flutter/services.dart';
 import 'package:flutter_riverpod/flutter_riverpod.dart';
 import 'core/network/session_signal.dart';
+import 'core/update/actualizacion.dart';
 import 'core/theme/app_theme.dart';
 import 'router/app_router.dart';
 
@@ -18,12 +19,30 @@ void main() {
   runApp(const ProviderScope(child: MobileSalesApp()));
 }
 
+// [2026-10-06] 새 버전 안내 — build-apk.sh 가 이 주소에 version.json 을 올린다
+const _feedActualizacion =
+    'https://github.com/jhkim1010/ventago-downloads/releases/download/vendedor-app-latest/version.json';
+
 // 루트 앱 위젯 — router Provider 구독
-class MobileSalesApp extends ConsumerWidget {
+class MobileSalesApp extends ConsumerStatefulWidget {
   const MobileSalesApp({super.key});
 
   @override
-  Widget build(BuildContext context, WidgetRef ref) {
+  ConsumerState<MobileSalesApp> createState() => _MobileSalesAppState();
+}
+
+class _MobileSalesAppState extends ConsumerState<MobileSalesApp> {
+  @override
+  void initState() {
+    super.initState();
+    // 첫 화면이 뜬 뒤 1회 — 새 버전이 있으면 묻는다(절대 혼자 설치하지 않음)
+    WidgetsBinding.instance.addPostFrameCallback(
+      (_) => chequearActualizacion(rootNavigatorKey, feedUrl: _feedActualizacion),
+    );
+  }
+
+  @override
+  Widget build(BuildContext context) {
     final router = ref.watch(appRouterProvider);
 
     return MaterialApp.router(
diff --git a/lib/router/app_router.dart b/lib/router/app_router.dart
index 917b663..c868f6e 100644
--- a/lib/router/app_router.dart
+++ b/lib/router/app_router.dart
@@ -1,5 +1,6 @@
 // 앱 라우터 — go_router + scope(인증) 기반 redirect + 세션만료 신호 반영.
 // 미인증/세션만료 → /login, 인증 → /home. 판매 화면은 Wave 4 에서 채운다.
+import 'package:flutter/widgets.dart';
 import 'package:flutter_riverpod/flutter_riverpod.dart';
 import 'package:go_router/go_router.dart';
 import '../core/network/session_signal.dart';
@@ -28,11 +29,15 @@ import '../features/revendedor/views/reseller_register_screen.dart';
 import '../features/revendedor/views/reseller_store_selector_screen.dart';
 import '../features/revendedor/views/revendedor_home.dart';
 
+// 라우터 바깥(앱 시작 시 업데이트 확인 등)에서 다이얼로그를 띄우기 위한 루트 navigator 키
+final rootNavigatorKey = GlobalKey<NavigatorState>();
+
 // GoRouter Provider — scope 상태 + 세션만료 신호 변화 시 자동 리다이렉트
 final appRouterProvider = Provider<GoRouter>((ref) {
   final sessionSignal = ref.read(sessionExpiredSignalProvider);
 
   final router = GoRouter(
+    navigatorKey: rootNavigatorKey,
     initialLocation: '/login',
     // 세션만료 신호가 바뀌면 redirect 재평가 (MOBILE-C-07)
     refreshListenable: sessionSignal,
diff --git a/pubspec.yaml b/pubspec.yaml
index 1bd5713..d04f192 100644
--- a/pubspec.yaml
+++ b/pubspec.yaml
@@ -16,7 +16,7 @@ publish_to: 'none' # Remove this line if you wish to publish to pub.dev
 # https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CoreFoundationKeys.html
 # In Windows, build-name is used as the major, minor, and patch parts
 # of the product and file versions while build-number is used as the build suffix.
-version: 1.0.0+1
+version: 1.1.0+8
 
 environment:
   sdk: ^3.11.0
diff --git a/tienda-admin-app/android/app/build.gradle.kts b/tienda-admin-app/android/app/build.gradle.kts
index 8eb03c8..09fd193 100644
--- a/tienda-admin-app/android/app/build.gradle.kts
+++ b/tienda-admin-app/android/app/build.gradle.kts
@@ -65,3 +65,8 @@ android {
 flutter {
     source = "../.."
 }
+
+// [2026-10-06] FileProvider para la actualización dentro de la app
+dependencies {
+    implementation("androidx.core:core-ktx:1.13.1")
+}
diff --git a/tienda-admin-app/android/app/src/main/AndroidManifest.xml b/tienda-admin-app/android/app/src/main/AndroidManifest.xml
index 5c44fb9..901a1e6 100644
--- a/tienda-admin-app/android/app/src/main/AndroidManifest.xml
+++ b/tienda-admin-app/android/app/src/main/AndroidManifest.xml
@@ -2,6 +2,8 @@
     <!-- release APK 네트워크 필수: 없으면 소켓 EPERM(errno=1) -->
     <uses-permission android:name="android.permission.INTERNET"/>
     <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
+    <!-- [2026-10-06] actualización dentro de la app: abrir el instalador con el APK descargado -->
+    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>
     <uses-permission android:name="android.permission.USE_BIOMETRIC"/>
     <application
         android:label="Admin de Tienda"
@@ -29,6 +31,15 @@
                 <category android:name="android.intent.category.LAUNCHER"/>
             </intent-filter>
         </activity>
+        <provider
+            android:name="androidx.core.content.FileProvider"
+            android:authorities="${applicationId}.actualizacion"
+            android:exported="false"
+            android:grantUriPermissions="true">
+            <meta-data
+                android:name="android.support.FILE_PROVIDER_PATHS"
+                android:resource="@xml/actualizacion_paths" />
+        </provider>
         <!-- Don't delete the meta-data below.
              This is used by the Flutter tool to generate GeneratedPluginRegistrant.java -->
         <meta-data
diff --git a/tienda-admin-app/android/app/src/main/kotlin/com/coolsistema/ventago_admin_app/MainActivity.kt b/tienda-admin-app/android/app/src/main/kotlin/com/coolsistema/ventago_admin_app/MainActivity.kt
index e1a9520..5cc4b1c 100644
--- a/tienda-admin-app/android/app/src/main/kotlin/com/coolsistema/ventago_admin_app/MainActivity.kt
+++ b/tienda-admin-app/android/app/src/main/kotlin/com/coolsistema/ventago_admin_app/MainActivity.kt
@@ -1,6 +1,13 @@
 package com.coolsistema.ventago_admin_app
 
 import io.flutter.embedding.android.FlutterFragmentActivity
+import io.flutter.embedding.engine.FlutterEngine
 
 // local_auth(지문) 는 FragmentActivity 를 요구한다.
-class MainActivity : FlutterFragmentActivity()
+class MainActivity : FlutterFragmentActivity() {
+    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
+        super.configureFlutterEngine(flutterEngine)
+        // [2026-10-06] actualización dentro de la app
+        Actualizacion.registrar(flutterEngine, applicationContext)
+    }
+}
diff --git a/tienda-admin-app/build-apk.sh b/tienda-admin-app/build-apk.sh
index 6d1cf58..23ad832 100755
--- a/tienda-admin-app/build-apk.sh
+++ b/tienda-admin-app/build-apk.sh
@@ -4,6 +4,7 @@
 # 사용법:
 #   ./build-apk.sh                # 빌드 후 복사
 #   ./build-apk.sh --skip-build   # 기존 빌드 산출물만 복사
+#   NOTAS="Modo lector +1" ./build-apk.sh   # 앱의 「Nueva versión」 창에 보일 안내(선택)
 #
 # 복사 대상:
 #   1) Dropbox/ACE_3_uversion/app herramientas download  — 버전명 + 고정명(tienda-admin-android.apk)
@@ -26,7 +27,26 @@ FIXED_DEST="/Users/marcoskim/Dropbox/ACE_3_uversion/app herramientas download/ti
 
 cd "$APP_DIR"
 
+# [2026-10-06] 앱 안 업데이트: 빌드할 때마다 build 번호를 올린다(같으면 휴대폰이 새 버전으로 안 본다).
+#   publicar-apk.sh 가 「게시된 것보다 큰가」를 다시 확인한다.
+subir_build() {
+  local v b
+  v="$(grep -E '^version:' pubspec.yaml | head -1 | awk '{print $2}')"
+  b="${v##*+}"
+  # ★ 고정 문자열 비교로 치환 — 정규식이면 버전의 「.」「+」가 메타문자가 된다
+  python3 - "$v" "${v%%+*}+$((b + 1))" <<'PY'
+import sys
+viejo, nuevo = sys.argv[1:]
+t = open('pubspec.yaml').read()
+linea = 'version: ' + viejo + '\n'
+assert t.count(linea) == 1, 'version: no encontrado exactamente una vez'
+open('pubspec.yaml', 'w').write(t.replace(linea, 'version: ' + nuevo + '\n'))
+PY
+  echo "▶ version: $v → $(grep -E '^version:' pubspec.yaml | awk '{print $2}')"
+}
+
 if [[ "${1:-}" != "--skip-build" ]]; then
+  subir_build
   echo "▶ flutter build apk --release (tienda-admin)"
   flutter build apk --release
 fi
@@ -66,3 +86,8 @@ if [[ "$missing" -eq 1 ]]; then
 fi
 
 echo "✔ 전체 복사 완료 ($apk_name)"
+
+# [2026-10-06] 앱 안 업데이트용 게시 (GitHub Releases → 앱이 열릴 때 「Nueva versión」 을 묻는다)
+#   업로드 키(Play 와 같은 키)로 서명된 APK 만 게시한다 — 다른 키면 휴대폰이 설치를 거부한다.
+CERT_UPLOAD="23747e710c3c77d8e989626b98d26464baee869d70e44857b8a5b0dc4e3927c7"
+"$APP_DIR/../scripts/publicar-apk.sh" "$APK_SRC" "tienda-admin-app-latest" "tienda-admin-app.apk" "$CERT_UPLOAD" "${NOTAS:-}"
diff --git a/tienda-admin-app/lib/main.dart b/tienda-admin-app/lib/main.dart
index 685203f..82b1fb0 100644
--- a/tienda-admin-app/lib/main.dart
+++ b/tienda-admin-app/lib/main.dart
@@ -2,6 +2,7 @@ import 'package:flutter/material.dart';
 import 'package:flutter_riverpod/flutter_riverpod.dart';
 import 'core/network/session_signal.dart';
 import 'core/theme/app_theme.dart';
+import 'core/update/actualizacion.dart';
 import 'features/auth/auth_controller.dart';
 import 'features/auth/login_screen.dart';
 import 'shared/app_shell.dart';
@@ -10,12 +11,34 @@ void main() {
   runApp(const ProviderScope(child: TiendaAdminApp()));
 }
 
-class TiendaAdminApp extends StatelessWidget {
+// [2026-10-06] 새 버전 안내 — build-apk.sh 가 이 주소에 version.json 을 올린다
+const _feedActualizacion =
+    'https://github.com/jhkim1010/ventago-downloads/releases/download/tienda-admin-app-latest/version.json';
+
+// 앱 시작 시 업데이트 다이얼로그를 띄우기 위한 루트 navigator 키
+final rootNavigatorKey = GlobalKey<NavigatorState>();
+
+class TiendaAdminApp extends StatefulWidget {
   const TiendaAdminApp({super.key});
 
+  @override
+  State<TiendaAdminApp> createState() => _TiendaAdminAppState();
+}
+
+class _TiendaAdminAppState extends State<TiendaAdminApp> {
+  @override
+  void initState() {
+    super.initState();
+    // 첫 화면이 뜬 뒤 1회 — 새 버전이 있으면 묻는다(절대 혼자 설치하지 않음)
+    WidgetsBinding.instance.addPostFrameCallback(
+      (_) => chequearActualizacion(rootNavigatorKey, feedUrl: _feedActualizacion),
+    );
+  }
+
   @override
   Widget build(BuildContext context) {
     return MaterialApp(
+      navigatorKey: rootNavigatorKey,
       title: 'Admin de Tienda',
       debugShowCheckedModeBanner: false,
       scaffoldMessengerKey: rootScaffoldMessengerKey,
warning: `--dangerously-bypass-hook-trust` is enabled. Enabled hooks may run without review for this invocation.
warning: `--dangerously-bypass-hook-trust` is enabled. Enabled hooks may run without review for this invocation.
hook: SessionStart
hook: SessionStart
hook: SessionStart
hook: SessionStart Failed
hook: SessionStart Failed
hook: SessionStart Completed
hook: UserPromptSubmit
hook: UserPromptSubmit Completed
codex
Voy a contrastar el diff con los archivos reales y el protocolo de revisión, enfocándome en escenarios reproducibles: origen del feed/APK, integridad, firma, flujo de permisos y atomicidad de publicación. No voy a modificar archivos.
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse Failed
hook: PreToolUse Completed
hook: PreToolUse Completed
exec
/bin/zsh -lc "sed -n '1,240p' .team/REVIEW-PROTOCOL.md && rg -n \"class VersionRemota|chequearActualizacion|object Actualizacion|actualizacion_paths|publicar-apk|subir_build|CERT_UPLOAD\" mobile-sales-app tienda-admin-app scripts . 2>/dev/null" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 210ms:
hook: PostToolUse
hook: PostToolUse
hook: PostToolUse Failed
hook: PostToolUse Completed
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse Failed
hook: PreToolUse Completed
hook: PreToolUse Completed
exec
/bin/zsh -lc "git status --short && git diff --stat && nl -ba scripts/publicar-apk.sh | sed -n '1,180p' && nl -ba mobile-sales-app/lib/core/update/actualizacion.dart | sed -n '1,230p' && nl -ba mobile-sales-app/lib/core/update/version_remota.dart | sed -n '1,130p' && nl -ba mobile-sales-app/android/app/src/main/kotlin/com/ventago/mobile_sales_app/Actualizacion.kt | sed -n '1,180p' && find mobile-sales-app/android/app/src/main/res tienda-admin-app/android/app/src/main/res -path '*actualizacion_paths.xml' -print -exec sh -c 'nl -ba \""'$1"'"' _ {} \\;" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 30ms:
     1	#!/usr/bin/env bash
     2	# [2026-10-06] Actualización dentro de la app — publica un APK para que las apps lo ofrezcan.
     3	#
     4	# Uso (lo llaman mobile-sales-app/build-apk.sh y tienda-admin-app/build-apk.sh):
     5	#   scripts/publicar-apk.sh <apk> <tag-release> <nombre-asset.apk> <cert-sha256-esperado> ["notas"]
     6	#
     7	# Sube a GitHub Releases (jhkim1010/ventago-downloads, público):
     8	#   <tag>/<nombre-asset.apk>   y después   <tag>/version.json
     9	# El orden importa: version.json nunca apunta a un APK que todavía no está.
    10	#
    11	# ★ Se niega a publicar si:
    12	#   · el APK no está firmado con el certificado esperado — Android rechaza instalar una
    13	#     actualización con otra clave, así que publicarlo sólo produce «App no instalada»
    14	#     en cada teléfono.
    15	#   · el versionCode no es mayor que el publicado — la app no lo ofrecería.
    16	set -euo pipefail
    17	
    18	APK="$1"
    19	TAG="$2"
    20	ASSET="$3"
    21	CERT_ESPERADO="$4"
    22	NOTAS="${5:-}"
    23	REPO="jhkim1010/ventago-downloads"
    24	
    25	BT="${ANDROID_BUILD_TOOLS:-/opt/homebrew/share/android-commandlinetools/build-tools/36.0.0}"
    26	export JAVA_HOME="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
    27	
    28	[[ -f "$APK" ]] || { echo "ERROR: no existe el APK: $APK" >&2; exit 1; }
    29	
    30	badging="$("$BT/aapt2" dump badging "$APK" | head -1)"
    31	code="$(sed -E "s/.*versionCode='([0-9]+)'.*/\1/" <<<"$badging")"
    32	name="$(sed -E "s/.*versionName='([^']*)'.*/\1/" <<<"$badging")"
    33	[[ "$code" =~ ^[0-9]+$ ]] || { echo "ERROR: no pude leer versionCode del APK" >&2; exit 1; }
    34	
    35	cert="$("$BT/apksigner" verify --print-certs "$APK" | grep -m1 'certificate SHA-256 digest' | awk '{print $NF}')"
    36	if [[ "$cert" != "$CERT_ESPERADO"* ]]; then
    37	  echo "ERROR: el APK está firmado con ${cert:0:16}…, se esperaba ${CERT_ESPERADO:0:16}…" >&2
    38	  echo "       Los teléfonos no podrían instalar esta actualización. No se publica." >&2
    39	  exit 1
    40	fi
    41	
    42	feed="https://github.com/$REPO/releases/download/$TAG/version.json"
    43	publicado="$(curl -fsSL "$feed" 2>/dev/null | sed -nE 's/.*"versionCode": *([0-9]+).*/\1/p' || true)"
    44	if [[ -n "$publicado" && "$code" -le "$publicado" ]]; then
    45	  echo "ERROR: versionCode $code no es mayor que el publicado ($publicado). Subí la versión en pubspec.yaml." >&2
    46	  exit 1
    47	fi
    48	
    49	sha="$(shasum -a 256 "$APK" | awk '{print $1}')"
    50	url="https://github.com/$REPO/releases/download/$TAG/$ASSET"
    51	
    52	tmp="$(mktemp -d)"
    53	cp "$APK" "$tmp/$ASSET"
    54	python3 - "$tmp/version.json" "$code" "$name" "$url" "$sha" "$NOTAS" <<'EOF'
    55	import json, sys
    56	p, code, name, url, sha, notas = sys.argv[1:]
    57	json.dump({"versionCode": int(code), "versionName": name, "apk": url, "sha256": sha, "notas": notas},
    58	          open(p, "w"), ensure_ascii=False, indent=2)
    59	EOF
    60	
    61	gh release view "$TAG" -R "$REPO" >/dev/null 2>&1 \
    62	  || gh release create "$TAG" -R "$REPO" --title "$TAG" --notes "Actualización dentro de la app (version.json + APK)"
    63	gh release upload "$TAG" "$tmp/$ASSET" -R "$REPO" --clobber
    64	gh release upload "$TAG" "$tmp/version.json" -R "$REPO" --clobber
    65	
    66	# comprobar lo que realmente quedó publicado
    67	vuelta="$(curl -fsSL "$feed" | sed -nE 's/.*"versionCode": *([0-9]+).*/\1/p')"
    68	[[ "$vuelta" == "$code" ]] || { echo "ERROR: el feed publicado dice versionCode=$vuelta, no $code" >&2; exit 1; }
    69	echo "✔ Publicado v$name (versionCode $code) → $feed"
     1	// [2026-10-06] Actualización dentro de la app (Android, APK fuera de Play).
     2	// (mismo archivo en mobile-sales-app y tienda-admin-app)
     3	//
     4	// Al abrir: lee version.json; si hay una versión más nueva pregunta «Actualizar / Más tarde».
     5	// «Actualizar» baja el APK, verifica el SHA-256 y abre el instalador de Android — la persona
     6	// toca «Instalar». Android sólo acepta el APK si está firmado con la MISMA clave que la app
     7	// instalada, así que un APK ajeno no puede reemplazarla.
     8	import 'dart:io';
     9	
    10	import 'package:crypto/crypto.dart';
    11	import 'package:dio/dio.dart';
    12	import 'package:flutter/material.dart';
    13	import 'package:flutter/services.dart';
    14	
    15	import 'version_remota.dart';
    16	
    17	const _canal = MethodChannel('ventago/actualizacion');
    18	
    19	// Un chequeo por arranque de la app («Más tarde» = hasta la próxima vez que se abra)
    20	bool _yaChequeado = false;
    21	
    22	Future<void> chequearActualizacion(GlobalKey<NavigatorState> navegador, {required String feedUrl}) async {
    23	  if (_yaChequeado || !Platform.isAndroid) {
    24	    return;
    25	  }
    26	  _yaChequeado = true;
    27	
    28	  final VersionRemota? remota;
    29	  final int instalada;
    30	  try {
    31	    final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 8)));
    32	    final r = await dio.get<Object?>(
    33	      feedUrl,
    34	      options: Options(responseType: ResponseType.json, headers: {'Cache-Control': 'no-cache'}),
    35	    );
    36	    remota = VersionRemota.desdeJson(r.data);
    37	    instalada = await _canal.invokeMethod<int>('versionCode') ?? 0;
    38	  } catch (_) {
    39	    // sin red o feed caído: la app sigue normal, se vuelve a mirar en el próximo arranque
    40	    return;
    41	  }
    42	  final nueva = remota;
    43	  if (nueva == null || instalada <= 0 || !nueva.esMasNuevaQue(instalada)) {
    44	    return;
    45	  }
    46	
    47	  final ctx = navegador.currentContext;
    48	  if (ctx == null || !ctx.mounted) {
    49	    return;
    50	  }
    51	  final acepta = await showDialog<bool>(
    52	    context: ctx,
    53	    builder: (c) => AlertDialog(
    54	      title: const Text('Nueva versión disponible'),
    55	      content: Text(
    56	        'Versión ${nueva.versionName}${nueva.notas.isEmpty ? '' : '\n\n${nueva.notas}'}\n\n'
    57	        'Se descarga y Android te pide confirmar la instalación.',
    58	      ),
    59	      actions: [
    60	        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Más tarde')),
    61	        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Actualizar')),
    62	      ],
    63	    ),
    64	  );
    65	  if (acepta != true) {
    66	    return;
    67	  }
    68	  final ctx2 = navegador.currentContext;
    69	  if (ctx2 == null || !ctx2.mounted) {
    70	    return;
    71	  }
    72	  await showDialog<void>(
    73	    context: ctx2,
    74	    barrierDismissible: false,
    75	    builder: (_) => _DescargaDialog(remota: nueva),
    76	  );
    77	}
    78	
    79	class _DescargaDialog extends StatefulWidget {
    80	  final VersionRemota remota;
    81	
    82	  const _DescargaDialog({required this.remota});
    83	
    84	  @override
    85	  State<_DescargaDialog> createState() => _DescargaDialogState();
    86	}
    87	
    88	class _DescargaDialogState extends State<_DescargaDialog> {
    89	  final CancelToken _cancel = CancelToken();
    90	  double? _progreso;
    91	  String? _error;
    92	
    93	  @override
    94	  void initState() {
    95	    super.initState();
    96	    _bajarEInstalar();
    97	  }
    98	
    99	  @override
   100	  void dispose() {
   101	    _cancel.cancel();
   102	    super.dispose();
   103	  }
   104	
   105	  Future<void> _bajarEInstalar() async {
   106	    setState(() {
   107	      _error = null;
   108	      _progreso = null;
   109	    });
   110	    try {
   111	      final dir = await _canal.invokeMethod<String>('dirDescarga');
   112	      if (dir == null) {
   113	        throw const _Falla('No se pudo preparar la descarga');
   114	      }
   115	      final ruta = '$dir/actualizacion.apk';
   116	      await Dio().download(
   117	        widget.remota.apkUrl,
   118	        ruta,
   119	        cancelToken: _cancel,
   120	        onReceiveProgress: (r, t) {
   121	          if (mounted && t > 0) {
   122	            setState(() => _progreso = r / t);
   123	          }
   124	        },
   125	      );
   126	      final bytes = await File(ruta).readAsBytes();
   127	      // ★ el archivo bajado tiene que ser exactamente el publicado
   128	      if (sha256.convert(bytes).toString() != widget.remota.sha256) {
   129	        await File(ruta).delete();
   130	        throw const _Falla('La descarga llegó dañada. Probá de nuevo.');
   131	      }
   132	      final r = await _canal.invokeMethod<String>('instalar', {'ruta': ruta});
   133	      if (!mounted) {
   134	        return;
   135	      }
   136	      if (r == 'permiso') {
   137	        setState(() => _error =
   138	            'Activá «Permitir de esta fuente» para esta app en la pantalla que se abrió, volvé y tocá «Reintentar».');
   139	
   140	        return;
   141	      }
   142	      Navigator.pop(context);
   143	    } on _Falla catch (e) {
   144	      if (mounted) setState(() => _error = e.mensaje);
   145	    } on DioException catch (e) {
   146	      // «Cancelar» cierra el diálogo y corta la descarga: no es un error
   147	      if (mounted && !CancelToken.isCancel(e)) {
   148	        setState(() => _error = 'No se pudo descargar la actualización. Revisá la conexión.');
   149	      }
   150	    } catch (_) {
   151	      if (mounted) setState(() => _error = 'No se pudo instalar la actualización.');
   152	    }
   153	  }
   154	
   155	  @override
   156	  Widget build(BuildContext context) {
   157	    final error = _error;
   158	
   159	    return AlertDialog(
   160	      title: Text('Actualizando a ${widget.remota.versionName}'),
   161	      content: error != null
   162	          ? Text(error)
   163	          : Column(
   164	              mainAxisSize: MainAxisSize.min,
   165	              crossAxisAlignment: CrossAxisAlignment.start,
   166	              children: [
   167	                LinearProgressIndicator(value: _progreso),
   168	                const SizedBox(height: 10),
   169	                Text(_progreso == null ? 'Descargando…' : 'Descargando… ${(_progreso! * 100).floor()}%'),
   170	              ],
   171	            ),
   172	      actions: [
   173	        TextButton(onPressed: () => Navigator.pop(context), child: Text(error != null ? 'Cerrar' : 'Cancelar')),
   174	        if (error != null) FilledButton(onPressed: _bajarEInstalar, child: const Text('Reintentar')),
   175	      ],
   176	    );
   177	  }
   178	}
   179	
   180	class _Falla implements Exception {
   181	  final String mensaje;
   182	
   183	  const _Falla(this.mensaje);
   184	}
     1	// [2026-10-06] Actualización dentro de la app (Android, APK fuera de Play) — reglas puras.
     2	// (mismo archivo en mobile-sales-app y tienda-admin-app)
     3	//
     4	// El build (build-apk.sh) publica en GitHub Releases (jhkim1010/ventago-downloads):
     5	//   <app>-latest/version.json  →  {"versionCode": 9, "versionName": "1.1.0",
     6	//                                  "apk": "https://…/app.apk", "sha256": "…", "notas": "…"}
     7	// La app lo lee al abrir; si hay una versión más nueva PREGUNTA (nunca instala sola).
     8	
     9	class VersionRemota {
    10	  final int versionCode;
    11	  final String versionName;
    12	  final String apkUrl;
    13	  final String sha256;
    14	  final String notas;
    15	
    16	  const VersionRemota({
    17	    required this.versionCode,
    18	    required this.versionName,
    19	    required this.apkUrl,
    20	    required this.sha256,
    21	    this.notas = '',
    22	  });
    23	
    24	  // null = feed inválido → no se ofrece nada (nunca adivinar una URL o un hash)
    25	  static VersionRemota? desdeJson(Object? json) {
    26	    if (json is! Map) {
    27	      return null;
    28	    }
    29	    final code = json['versionCode'];
    30	    final name = json['versionName'];
    31	    final apk = json['apk'];
    32	    final sha = json['sha256'];
    33	    if (code is! int || code <= 0 || name is! String || apk is! String || sha is! String) {
    34	      return null;
    35	    }
    36	    // ★ sólo https y sólo nuestro repositorio de descargas
    37	    final uri = Uri.tryParse(apk);
    38	    if (uri == null || uri.scheme != 'https' || !esOrigenPermitido(uri)) {
    39	      return null;
    40	    }
    41	    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha.toLowerCase())) {
    42	      return null;
    43	    }
    44	    final notas = json['notas'];
    45	
    46	    return VersionRemota(
    47	      versionCode: code,
    48	      versionName: name,
    49	      apkUrl: apk,
    50	      sha256: sha.toLowerCase(),
    51	      notas: notas is String ? notas : '',
    52	    );
    53	  }
    54	
    55	  bool esMasNuevaQue(int instalada) => versionCode > instalada;
    56	}
    57	
    58	bool esOrigenPermitido(Uri uri) =>
    59	    uri.host == 'github.com' && uri.path.startsWith('/jhkim1010/ventago-downloads/releases/download/');
     1	package com.ventago.mobile_sales_app
     2	
     3	import android.content.Context
     4	import android.content.Intent
     5	import android.net.Uri
     6	import android.os.Build
     7	import android.provider.Settings
     8	import androidx.core.content.FileProvider
     9	import io.flutter.embedding.engine.FlutterEngine
    10	import io.flutter.plugin.common.MethodChannel
    11	import java.io.File
    12	
    13	// [2026-10-06] Actualización dentro de la app (lib/core/update/actualizacion.dart).
    14	// Canal «ventago/actualizacion»:
    15	//   versionCode → versión instalada
    16	//   dirDescarga → carpeta en caché para el APK (expuesta por FileProvider: res/xml/actualizacion_paths.xml)
    17	//   instalar    → abre el instalador de Android ('ok'), o los ajustes de «instalar apps
    18	//                 desconocidas» si falta el permiso ('permiso'). Android pide confirmar siempre.
    19	object Actualizacion {
    20	    fun registrar(engine: FlutterEngine, context: Context) {
    21	        MethodChannel(engine.dartExecutor.binaryMessenger, "ventago/actualizacion").setMethodCallHandler { call, result ->
    22	            try {
    23	                when (call.method) {
    24	                    "versionCode" -> {
    25	                        val info = context.packageManager.getPackageInfo(context.packageName, 0)
    26	                        val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode.toInt() else @Suppress("DEPRECATION") info.versionCode
    27	                        result.success(code)
    28	                    }
    29	                    "dirDescarga" -> {
    30	                        val dir = File(context.cacheDir, "actualizacion")
    31	                        dir.mkdirs()
    32	                        result.success(dir.absolutePath)
    33	                    }
    34	                    "instalar" -> {
    35	                        if (Build.VERSION.SDK_INT >= 26 && !context.packageManager.canRequestPackageInstalls()) {
    36	                            val ajustes = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + context.packageName))
    37	                            ajustes.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    38	                            context.startActivity(ajustes)
    39	                            result.success("permiso")
    40	                        } else {
    41	                            val archivo = File(call.argument<String>("ruta")!!)
    42	                            val uri = FileProvider.getUriForFile(context, context.packageName + ".actualizacion", archivo)
    43	                            val intent = Intent(Intent.ACTION_VIEW)
    44	                            intent.setDataAndType(uri, "application/vnd.android.package-archive")
    45	                            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
    46	                            context.startActivity(intent)
    47	                            result.success("ok")
    48	                        }
    49	                    }
    50	                    else -> result.notImplemented()
    51	                }
    52	            } catch (e: Exception) {
    53	                result.error("actualizacion", e.message, null)
    54	            }
    55	        }
    56	    }
    57	}
mobile-sales-app/android/app/src/main/res/xml/actualizacion_paths.xml
     1	<?xml version="1.0" encoding="utf-8"?>
     2	<!-- [2026-10-06] Actualización dentro de la app: sólo la carpeta del APK descargado -->
     3	<paths>
     4	    <cache-path name="actualizacion" path="actualizacion/" />
     5	</paths>
tienda-admin-app/android/app/src/main/res/xml/actualizacion_paths.xml
     1	<?xml version="1.0" encoding="utf-8"?>
     2	<!-- [2026-10-06] Actualización dentro de la app: sólo la carpeta del APK descargado -->
     3	<paths>
     4	    <cache-path name="actualizacion" path="actualizacion/" />
     5	</paths>

hook: PostToolUse
hook: PostToolUse
hook: PostToolUse Failed
hook: PostToolUse Completed
codex
Ya confirmé que ambos `FileProvider` limitan el acceso a la subcarpeta de caché correcta. Estoy verificando ahora dos zonas con riesgo real: reemplazo de assets bajo una URL estable de GitHub y estados de reintento/cancelación en el diálogo.
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse Failed
hook: PreToolUse Completed
hook: PreToolUse Completed
exec
/bin/zsh -lc "nl -ba mobile-sales-app/build-apk.sh | sed -n '1,150p'; nl -ba tienda-admin-app/build-apk.sh | sed -n '1,125p'; nl -ba tienda-admin-app/lib/core/update/actualizacion.dart | sed -n '100,185p'; nl -ba tienda-admin-app/android/app/src/main/kotlin/com/coolsistema/ventago_admin_app/Actualizacion.kt | sed -n '20,70p'; nl -ba mobile-sales-app/test/version_remota_test.dart 2>/dev/null | sed -n '1,220p'; nl -ba tienda-admin-app/test/version_remota_test.dart | sed -n '1,220p'; rg -n \"signingConfig|storeFile|buildTypes\" mobile-sales-app/android/app/build.gradle.kts tienda-admin-app/android/app/build.gradle.kts" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 0ms:
     1	#!/usr/bin/env bash
     2	# 판매원 앱(Android) 릴리즈 빌드 + 배포 폴더 자동 복사.
     3	#
     4	# 사용법:
     5	#   ./build-apk.sh                # 빌드 후 복사
     6	#   ./build-apk.sh --skip-build   # 기존 빌드 산출물만 복사
     7	#   NOTAS="Modo lector +1" ./build-apk.sh   # 앱의 「Nueva versión」 창에 보일 안내(선택)
     8	#
     9	# 복사 대상 (DEST_DIRS + FIXED_DEST):
    10	#   1) Dropbox/ACE_3_uversion/app herramientas download  — 버전명
    11	#   2) Dropbox/Personal de m. Marcos                     — 버전명 (설치 파일 개인 보관)
    12	#   3) Google Drive/내 드라이브/ventago-superadmin/vendedor-app.apk — 고정명(배포 링크)
    13	#
    14	# 파일명 규칙: app_sales_android_v<version>_b<build>_<YYYYMMDD-HHMM>.apk
    15	# (pubspec.yaml 의 `version: 1.0.0+1` → v1.0.0_b1)
    16	
    17	set -euo pipefail
    18	
    19	APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    20	APK_SRC="$APP_DIR/build/app/outputs/flutter-apk/app-release.apk"
    21	
    22	# 버전명(app_sales_android_v..._b..._날짜.apk)으로 복사할 폴더들.
    23	# 두 번째 폴더는 설치 파일 개인 보관용 — 항상 함께 복사한다.
    24	DEST_DIRS=(
    25	  "/Users/marcoskim/Dropbox/ACE_3_uversion/app herramientas download"
    26	  "/Users/marcoskim/Dropbox/Personal de m. Marcos"
    27	)
    28	
    29	# 고정 파일명으로 덮어쓸 경로 (Google Drive 배포 링크가 이 이름을 가리킨다)
    30	FIXED_DEST="/Users/marcoskim/Google Drive/내 드라이브/ventago-superadmin/vendedor-app.apk"
    31	
    32	cd "$APP_DIR"
    33	
    34	# [2026-10-06] 앱 안 업데이트: 빌드할 때마다 build 번호를 올린다(같으면 휴대폰이 새 버전으로 안 본다).
    35	#   publicar-apk.sh 가 「게시된 것보다 큰가」를 다시 확인한다.
    36	subir_build() {
    37	  local v b
    38	  v="$(grep -E '^version:' pubspec.yaml | head -1 | awk '{print $2}')"
    39	  b="${v##*+}"
    40	  # ★ 고정 문자열 비교로 치환 — 정규식이면 버전의 「.」「+」가 메타문자가 된다
    41	  python3 - "$v" "${v%%+*}+$((b + 1))" <<'PY'
    42	import sys
    43	viejo, nuevo = sys.argv[1:]
    44	t = open('pubspec.yaml').read()
    45	linea = 'version: ' + viejo + '\n'
    46	assert t.count(linea) == 1, 'version: no encontrado exactamente una vez'
    47	open('pubspec.yaml', 'w').write(t.replace(linea, 'version: ' + nuevo + '\n'))
    48	PY
    49	  echo "▶ version: $v → $(grep -E '^version:' pubspec.yaml | awk '{print $2}')"
    50	}
    51	
    52	# 버전명(파일명)을 읽기 전에 올린다
    53	if [[ "${1:-}" != "--skip-build" ]]; then
    54	  subir_build
    55	fi
    56	
    57	raw_version="$(grep -E '^version:' pubspec.yaml | head -1 | awk '{print $2}')"
    58	if [[ -z "$raw_version" ]]; then
    59	  echo "ERROR: pubspec.yaml 에서 version 을 읽지 못했습니다" >&2
    60	  exit 1
    61	fi
    62	
    63	ver="${raw_version%%+*}"
    64	build_no="${raw_version##*+}"
    65	
    66	if [[ "${1:-}" != "--skip-build" ]]; then
    67	  echo "▶ flutter build apk --release (v${ver}+${build_no})"
    68	  # 홈 헤더의 "build ..." 표기 = 컴파일 시각. 어느 APK 인지 사용자가 식별한다.
    69	  flutter build apk --release --dart-define=BUILD_DATE="$(date '+%Y%m%d-%H%M')"
    70	fi
    71	
    72	if [[ ! -f "$APK_SRC" ]]; then
    73	  echo "ERROR: APK 산출물 없음: $APK_SRC" >&2
    74	  echo "       --skip-build 없이 다시 실행하세요." >&2
    75	  exit 1
    76	fi
    77	
    78	# 복사 시각이 아니라 APK 가 실제로 컴파일된 시각(산출물 mtime)을 파일명에 넣는다.
    79	# → --skip-build 로 나중에 복사해도 이름이 빌드 시점을 그대로 가리킨다.
    80	stamp="$(date -r "$APK_SRC" '+%Y%m%d-%H%M')"
    81	apk_name="app_sales_android_v${ver}_b${build_no}_${stamp}.apk"
    82	
    83	# 폴더 하나가 없어도(예: Drive 미동기화) 나머지 복사는 계속한다 — 마지막에 실패를 모아 보고.
    84	missing=0
    85	
    86	for dir in "${DEST_DIRS[@]}"; do
    87	  if [[ ! -d "$dir" ]]; then
    88	    echo "WARN: 폴더 없음, 건너뜀: $dir" >&2
    89	    missing=1
    90	    continue
    91	  fi
    92	
    93	  cp "$APK_SRC" "$dir/$apk_name"
    94	  echo "✔ 복사: $dir/$apk_name"
    95	done
    96	
    97	fixed_dir="$(dirname "$FIXED_DEST")"
    98	if [[ -d "$fixed_dir" ]]; then
    99	  cp "$APK_SRC" "$FIXED_DEST"
   100	  echo "✔ 복사: $FIXED_DEST"
   101	else
   102	  echo "WARN: 폴더 없음, 건너뜀: $fixed_dir" >&2
   103	  missing=1
   104	fi
   105	
   106	if [[ "$missing" -eq 1 ]]; then
   107	  echo "ERROR: 일부 대상에 복사하지 못했습니다 (위 WARN 확인)" >&2
   108	  exit 1
   109	fi
   110	
   111	echo "✔ 전체 복사 완료 ($apk_name)"
   112	
   113	# [2026-10-06] 앱 안 업데이트용 게시 (GitHub Releases → 앱이 열릴 때 「Nueva versión」 을 묻는다)
   114	#   업로드 키(Play 와 같은 키)로 서명된 APK 만 게시한다 — 다른 키면 휴대폰이 설치를 거부한다.
   115	CERT_UPLOAD="23747e710c3c77d8e989626b98d26464baee869d70e44857b8a5b0dc4e3927c7"
   116	"$APP_DIR/../scripts/publicar-apk.sh" "$APK_SRC" "vendedor-app-latest" "vendedor-app.apk" "$CERT_UPLOAD" "${NOTAS:-}"
     1	#!/usr/bin/env bash
     2	# 매장 주인 앱(tienda-admin-app, Android) 릴리즈 빌드 + 배포 폴더 자동 복사.
     3	#
     4	# 사용법:
     5	#   ./build-apk.sh                # 빌드 후 복사
     6	#   ./build-apk.sh --skip-build   # 기존 빌드 산출물만 복사
     7	#   NOTAS="Modo lector +1" ./build-apk.sh   # 앱의 「Nueva versión」 창에 보일 안내(선택)
     8	#
     9	# 복사 대상:
    10	#   1) Dropbox/ACE_3_uversion/app herramientas download  — 버전명 + 고정명(tienda-admin-android.apk)
    11	#   2) Dropbox/Personal de m. Marcos                     — 버전명 (설치 파일 개인 보관)
    12	#
    13	# 파일명 규칙: tienda_admin_android_<YYYYMMDD-HHMM>.apk (APK 컴파일 시각 기준)
    14	
    15	set -euo pipefail
    16	
    17	APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    18	APK_SRC="$APP_DIR/build/app/outputs/flutter-apk/app-release.apk"
    19	
    20	DEST_DIRS=(
    21	  "/Users/marcoskim/Dropbox/ACE_3_uversion/app herramientas download"
    22	  "/Users/marcoskim/Dropbox/Personal de m. Marcos"
    23	)
    24	
    25	# 기존 배포 링크가 가리키는 고정 파일명
    26	FIXED_DEST="/Users/marcoskim/Dropbox/ACE_3_uversion/app herramientas download/tienda-admin-android.apk"
    27	
    28	cd "$APP_DIR"
    29	
    30	# [2026-10-06] 앱 안 업데이트: 빌드할 때마다 build 번호를 올린다(같으면 휴대폰이 새 버전으로 안 본다).
    31	#   publicar-apk.sh 가 「게시된 것보다 큰가」를 다시 확인한다.
    32	subir_build() {
    33	  local v b
    34	  v="$(grep -E '^version:' pubspec.yaml | head -1 | awk '{print $2}')"
    35	  b="${v##*+}"
    36	  # ★ 고정 문자열 비교로 치환 — 정규식이면 버전의 「.」「+」가 메타문자가 된다
    37	  python3 - "$v" "${v%%+*}+$((b + 1))" <<'PY'
    38	import sys
    39	viejo, nuevo = sys.argv[1:]
    40	t = open('pubspec.yaml').read()
    41	linea = 'version: ' + viejo + '\n'
    42	assert t.count(linea) == 1, 'version: no encontrado exactamente una vez'
    43	open('pubspec.yaml', 'w').write(t.replace(linea, 'version: ' + nuevo + '\n'))
    44	PY
    45	  echo "▶ version: $v → $(grep -E '^version:' pubspec.yaml | awk '{print $2}')"
    46	}
    47	
    48	if [[ "${1:-}" != "--skip-build" ]]; then
    49	  subir_build
    50	  echo "▶ flutter build apk --release (tienda-admin)"
    51	  flutter build apk --release
    52	fi
    53	
    54	if [[ ! -f "$APK_SRC" ]]; then
    55	  echo "ERROR: APK 산출물 없음: $APK_SRC" >&2
    56	  echo "       --skip-build 없이 다시 실행하세요." >&2
    57	  exit 1
    58	fi
    59	
    60	stamp="$(date -r "$APK_SRC" '+%Y%m%d-%H%M')"
    61	apk_name="tienda_admin_android_${stamp}.apk"
    62	missing=0
    63	
    64	for dir in "${DEST_DIRS[@]}"; do
    65	  if [[ ! -d "$dir" ]]; then
    66	    echo "WARN: 폴더 없음, 건너뜀: $dir" >&2
    67	    missing=1
    68	    continue
    69	  fi
    70	
    71	  cp "$APK_SRC" "$dir/$apk_name"
    72	  echo "✔ 복사: $dir/$apk_name"
    73	done
    74	
    75	if [[ -d "$(dirname "$FIXED_DEST")" ]]; then
    76	  cp "$APK_SRC" "$FIXED_DEST"
    77	  echo "✔ 복사: $FIXED_DEST"
    78	else
    79	  echo "WARN: 폴더 없음, 건너뜀: $(dirname "$FIXED_DEST")" >&2
    80	  missing=1
    81	fi
    82	
    83	if [[ "$missing" -eq 1 ]]; then
    84	  echo "ERROR: 일부 대상에 복사하지 못했습니다 (위 WARN 확인)" >&2
    85	  exit 1
    86	fi
    87	
    88	echo "✔ 전체 복사 완료 ($apk_name)"
    89	
    90	# [2026-10-06] 앱 안 업데이트용 게시 (GitHub Releases → 앱이 열릴 때 「Nueva versión」 을 묻는다)
    91	#   업로드 키(Play 와 같은 키)로 서명된 APK 만 게시한다 — 다른 키면 휴대폰이 설치를 거부한다.
    92	CERT_UPLOAD="23747e710c3c77d8e989626b98d26464baee869d70e44857b8a5b0dc4e3927c7"
    93	"$APP_DIR/../scripts/publicar-apk.sh" "$APK_SRC" "tienda-admin-app-latest" "tienda-admin-app.apk" "$CERT_UPLOAD" "${NOTAS:-}"
   100	  void dispose() {
   101	    _cancel.cancel();
   102	    super.dispose();
   103	  }
   104	
   105	  Future<void> _bajarEInstalar() async {
   106	    setState(() {
   107	      _error = null;
   108	      _progreso = null;
   109	    });
   110	    try {
   111	      final dir = await _canal.invokeMethod<String>('dirDescarga');
   112	      if (dir == null) {
   113	        throw const _Falla('No se pudo preparar la descarga');
   114	      }
   115	      final ruta = '$dir/actualizacion.apk';
   116	      await Dio().download(
   117	        widget.remota.apkUrl,
   118	        ruta,
   119	        cancelToken: _cancel,
   120	        onReceiveProgress: (r, t) {
   121	          if (mounted && t > 0) {
   122	            setState(() => _progreso = r / t);
   123	          }
   124	        },
   125	      );
   126	      final bytes = await File(ruta).readAsBytes();
   127	      // ★ el archivo bajado tiene que ser exactamente el publicado
   128	      if (sha256.convert(bytes).toString() != widget.remota.sha256) {
   129	        await File(ruta).delete();
   130	        throw const _Falla('La descarga llegó dañada. Probá de nuevo.');
   131	      }
   132	      final r = await _canal.invokeMethod<String>('instalar', {'ruta': ruta});
   133	      if (!mounted) {
   134	        return;
   135	      }
   136	      if (r == 'permiso') {
   137	        setState(() => _error =
   138	            'Activá «Permitir de esta fuente» para esta app en la pantalla que se abrió, volvé y tocá «Reintentar».');
   139	
   140	        return;
   141	      }
   142	      Navigator.pop(context);
   143	    } on _Falla catch (e) {
   144	      if (mounted) setState(() => _error = e.mensaje);
   145	    } on DioException catch (e) {
   146	      // «Cancelar» cierra el diálogo y corta la descarga: no es un error
   147	      if (mounted && !CancelToken.isCancel(e)) {
   148	        setState(() => _error = 'No se pudo descargar la actualización. Revisá la conexión.');
   149	      }
   150	    } catch (_) {
   151	      if (mounted) setState(() => _error = 'No se pudo instalar la actualización.');
   152	    }
   153	  }
   154	
   155	  @override
   156	  Widget build(BuildContext context) {
   157	    final error = _error;
   158	
   159	    return AlertDialog(
   160	      title: Text('Actualizando a ${widget.remota.versionName}'),
   161	      content: error != null
   162	          ? Text(error)
   163	          : Column(
   164	              mainAxisSize: MainAxisSize.min,
   165	              crossAxisAlignment: CrossAxisAlignment.start,
   166	              children: [
   167	                LinearProgressIndicator(value: _progreso),
   168	                const SizedBox(height: 10),
   169	                Text(_progreso == null ? 'Descargando…' : 'Descargando… ${(_progreso! * 100).floor()}%'),
   170	              ],
   171	            ),
   172	      actions: [
   173	        TextButton(onPressed: () => Navigator.pop(context), child: Text(error != null ? 'Cerrar' : 'Cancelar')),
   174	        if (error != null) FilledButton(onPressed: _bajarEInstalar, child: const Text('Reintentar')),
   175	      ],
   176	    );
   177	  }
   178	}
   179	
   180	class _Falla implements Exception {
   181	  final String mensaje;
   182	
   183	  const _Falla(this.mensaje);
   184	}
    20	    fun registrar(engine: FlutterEngine, context: Context) {
    21	        MethodChannel(engine.dartExecutor.binaryMessenger, "ventago/actualizacion").setMethodCallHandler { call, result ->
    22	            try {
    23	                when (call.method) {
    24	                    "versionCode" -> {
    25	                        val info = context.packageManager.getPackageInfo(context.packageName, 0)
    26	                        val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode.toInt() else @Suppress("DEPRECATION") info.versionCode
    27	                        result.success(code)
    28	                    }
    29	                    "dirDescarga" -> {
    30	                        val dir = File(context.cacheDir, "actualizacion")
    31	                        dir.mkdirs()
    32	                        result.success(dir.absolutePath)
    33	                    }
    34	                    "instalar" -> {
    35	                        if (Build.VERSION.SDK_INT >= 26 && !context.packageManager.canRequestPackageInstalls()) {
    36	                            val ajustes = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + context.packageName))
    37	                            ajustes.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    38	                            context.startActivity(ajustes)
    39	                            result.success("permiso")
    40	                        } else {
    41	                            val archivo = File(call.argument<String>("ruta")!!)
    42	                            val uri = FileProvider.getUriForFile(context, context.packageName + ".actualizacion", archivo)
    43	                            val intent = Intent(Intent.ACTION_VIEW)
    44	                            intent.setDataAndType(uri, "application/vnd.android.package-archive")
    45	                            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
    46	                            context.startActivity(intent)
    47	                            result.success("ok")
    48	                        }
    49	                    }
    50	                    else -> result.notImplemented()
    51	                }
    52	            } catch (e: Exception) {
    53	                result.error("actualizacion", e.message, null)
    54	            }
    55	        }
    56	    }
    57	}
     1	// [2026-10-06] Actualización dentro de la app — el feed nunca puede apuntar a otro lado.
     2	import 'package:flutter_test/flutter_test.dart';
     3	import 'package:mobile_sales_app/core/update/version_remota.dart';
     4	
     5	const _apk = 'https://github.com/jhkim1010/ventago-downloads/releases/download/x-latest/app.apk';
     6	final _sha = 'a' * 64;
     7	
     8	Map<String, Object?> _feed({Object? code = 9, Object? apk = _apk, Object? sha}) =>
     9	    {'versionCode': code, 'versionName': '1.1.0', 'apk': apk, 'sha256': sha ?? _sha, 'notas': 'x'};
    10	
    11	void main() {
    12	  test('feed válido', () {
    13	    final v = VersionRemota.desdeJson(_feed())!;
    14	    expect(v.versionCode, 9);
    15	    expect(v.esMasNuevaQue(8), isTrue);
    16	    expect(v.esMasNuevaQue(9), isFalse, reason: 'misma versión: no ofrecer');
    17	    expect(v.esMasNuevaQue(10), isFalse, reason: 'nunca ofrecer bajar de versión');
    18	  });
    19	
    20	  test('★ APK fuera de nuestro repositorio de descargas → nada', () {
    21	    for (final url in [
    22	      'http://github.com/jhkim1010/ventago-downloads/releases/download/x/app.apk',
    23	      'https://evil.com/jhkim1010/ventago-downloads/releases/download/x/app.apk',
    24	      'https://github.com/otro/ventago-downloads/releases/download/x/app.apk',
    25	      'https://github.com.evil.com/jhkim1010/ventago-downloads/releases/download/x/app.apk',
    26	    ]) {
    27	      expect(VersionRemota.desdeJson(_feed(apk: url)), isNull, reason: url);
    28	    }
    29	  });
    30	
    31	  test('sin hash válido o versión inválida → nada', () {
    32	    expect(VersionRemota.desdeJson(_feed(sha: 'abc')), isNull);
    33	    expect(VersionRemota.desdeJson(_feed(code: '9')), isNull);
    34	    expect(VersionRemota.desdeJson(_feed(code: 0)), isNull);
    35	    expect(VersionRemota.desdeJson('no es un mapa'), isNull);
    36	    expect(VersionRemota.desdeJson(null), isNull);
    37	  });
    38	
    39	  test('hash en mayúsculas se normaliza (sha256sum vs comparación)', () {
    40	    expect(VersionRemota.desdeJson(_feed(sha: 'A' * 64))!.sha256, 'a' * 64);
    41	  });
    42	}
     1	// [2026-10-06] Actualización dentro de la app — el feed nunca puede apuntar a otro lado.
     2	import 'package:flutter_test/flutter_test.dart';
     3	import 'package:tienda_admin_app/core/update/version_remota.dart';
     4	
     5	const _apk = 'https://github.com/jhkim1010/ventago-downloads/releases/download/x-latest/app.apk';
     6	final _sha = 'a' * 64;
     7	
     8	Map<String, Object?> _feed({Object? code = 9, Object? apk = _apk, Object? sha}) =>
     9	    {'versionCode': code, 'versionName': '1.1.0', 'apk': apk, 'sha256': sha ?? _sha, 'notas': 'x'};
    10	
    11	void main() {
    12	  test('feed válido', () {
    13	    final v = VersionRemota.desdeJson(_feed())!;
    14	    expect(v.versionCode, 9);
    15	    expect(v.esMasNuevaQue(8), isTrue);
    16	    expect(v.esMasNuevaQue(9), isFalse, reason: 'misma versión: no ofrecer');
    17	    expect(v.esMasNuevaQue(10), isFalse, reason: 'nunca ofrecer bajar de versión');
    18	  });
    19	
    20	  test('★ APK fuera de nuestro repositorio de descargas → nada', () {
    21	    for (final url in [
    22	      'http://github.com/jhkim1010/ventago-downloads/releases/download/x/app.apk',
    23	      'https://evil.com/jhkim1010/ventago-downloads/releases/download/x/app.apk',
    24	      'https://github.com/otro/ventago-downloads/releases/download/x/app.apk',
    25	      'https://github.com.evil.com/jhkim1010/ventago-downloads/releases/download/x/app.apk',
    26	    ]) {
    27	      expect(VersionRemota.desdeJson(_feed(apk: url)), isNull, reason: url);
    28	    }
    29	  });
    30	
    31	  test('sin hash válido o versión inválida → nada', () {
    32	    expect(VersionRemota.desdeJson(_feed(sha: 'abc')), isNull);
    33	    expect(VersionRemota.desdeJson(_feed(code: '9')), isNull);
    34	    expect(VersionRemota.desdeJson(_feed(code: 0)), isNull);
    35	    expect(VersionRemota.desdeJson('no es un mapa'), isNull);
    36	    expect(VersionRemota.desdeJson(null), isNull);
    37	  });
    38	
    39	  test('hash en mayúsculas se normaliza (sha256sum vs comparación)', () {
    40	    expect(VersionRemota.desdeJson(_feed(sha: 'A' * 64))!.sha256, 'a' * 64);
    41	  });
    42	}
mobile-sales-app/android/app/build.gradle.kts:17:val hasUploadKey = uploadKeyProps.getProperty("storeFile") != null
mobile-sales-app/android/app/build.gradle.kts:47:    signingConfigs {
mobile-sales-app/android/app/build.gradle.kts:50:                storeFile = file(uploadKeyProps.getProperty("storeFile"))
mobile-sales-app/android/app/build.gradle.kts:58:    buildTypes {
mobile-sales-app/android/app/build.gradle.kts:60:            signingConfig = if (hasUploadKey) signingConfigs.getByName("upload") else signingConfigs.getByName("debug")
tienda-admin-app/android/app/build.gradle.kts:17:val hasUploadKey = uploadKeyProps.getProperty("storeFile") != null
tienda-admin-app/android/app/build.gradle.kts:47:    signingConfigs {
tienda-admin-app/android/app/build.gradle.kts:50:                storeFile = file(uploadKeyProps.getProperty("storeFile"))
tienda-admin-app/android/app/build.gradle.kts:58:    buildTypes {
tienda-admin-app/android/app/build.gradle.kts:60:            signingConfig = if (hasUploadKey) signingConfigs.getByName("upload") else signingConfigs.getByName("debug")

hook: PostToolUse
hook: PostToolUse
hook: PostToolUse Failed
hook: PostToolUse Completed
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse Failed
hook: PreToolUse Completed
hook: PreToolUse Completed
hook: PreToolUse Failed
hook: PreToolUse Completed
hook: PreToolUse Completed
hook: PostToolUse
hook: PostToolUse
hook: PostToolUse
hook: PostToolUse
hook: PostToolUse Failed
hook: PostToolUse Completed
hook: PostToolUse Failed
hook: PostToolUse Completed
codex
[HIGH] `scripts/publicar-apk.sh:50,63-64` — La URL estable del APK rompe la consistencia durante publicaciones parciales.

Escenario: `--clobber` reemplaza `vendedor-app.apk`, pero falla o demora la subida de `version.json`. El feed anterior queda apuntando a la misma URL con el hash anterior; todos los equipos descargan el APK nuevo y rechazan su SHA-256.

Arreglo: publicar el APK con nombre inmutable, por ejemplo `vendedor-app-<versionCode>.apk`, y recién después reemplazar `version.json`.

[MEDIUM] `mobile-sales-app/build-apk.sh:106-116` y `tienda-admin-app/build-apk.sh:83-93` — Una carpeta local faltante impide publicar una compilación válida.

Escenario: Dropbox/Google Drive no está montado. El script sale antes de invocar `publicar-apk.sh`, aunque el APK fue construido correctamente.

Arreglo: publicar antes de las copias opcionales o convertir esos faltantes en advertencias sin `exit 1`.

[MEDIUM] `mobile-sales-app/lib/core/update/actualizacion.dart:126` y copia de tienda-admin — El APK completo se carga en memoria para calcular el hash.

Escenario: un APK grande en un teléfono con poca RAM puede provocar OOM y cerrar la app antes de instalar.

Arreglo: calcular SHA-256 por streaming con `File(ruta).openRead()`.

[LOW] `mobile-sales-app/lib/core/update/actualizacion.dart:105,174` y copia de tienda-admin — “Reintentar” permite ejecuciones simultáneas.

Escenario: doble toque rápido inicia dos descargas sobre `actualizacion.apk`; pueden corromperse mutuamente o abrir dos instaladores.

Arreglo: agregar `_procesando`, deshabilitar el botón mientras corre y crear un `CancelToken` nuevo por intento.

La validación de origen, el SHA-256, la confirmación previa y el `FileProvider` restringido están correctamente planteados. No pude ejecutar Flutter test/analyze porque el sandbox bloqueó escrituras en la caché global de Flutter.
hook: Stop
hook: Stop
hook: Stop Failed
hook: Stop Completed
tokens used
94,571
[HIGH] `scripts/publicar-apk.sh:50,63-64` — La URL estable del APK rompe la consistencia durante publicaciones parciales.

Escenario: `--clobber` reemplaza `vendedor-app.apk`, pero falla o demora la subida de `version.json`. El feed anterior queda apuntando a la misma URL con el hash anterior; todos los equipos descargan el APK nuevo y rechazan su SHA-256.

Arreglo: publicar el APK con nombre inmutable, por ejemplo `vendedor-app-<versionCode>.apk`, y recién después reemplazar `version.json`.

[MEDIUM] `mobile-sales-app/build-apk.sh:106-116` y `tienda-admin-app/build-apk.sh:83-93` — Una carpeta local faltante impide publicar una compilación válida.

Escenario: Dropbox/Google Drive no está montado. El script sale antes de invocar `publicar-apk.sh`, aunque el APK fue construido correctamente.

Arreglo: publicar antes de las copias opcionales o convertir esos faltantes en advertencias sin `exit 1`.

[MEDIUM] `mobile-sales-app/lib/core/update/actualizacion.dart:126` y copia de tienda-admin — El APK completo se carga en memoria para calcular el hash.

Escenario: un APK grande en un teléfono con poca RAM puede provocar OOM y cerrar la app antes de instalar.

Arreglo: calcular SHA-256 por streaming con `File(ruta).openRead()`.

[LOW] `mobile-sales-app/lib/core/update/actualizacion.dart:105,174` y copia de tienda-admin — “Reintentar” permite ejecuciones simultáneas.

Escenario: doble toque rápido inicia dos descargas sobre `actualizacion.apk`; pueden corromperse mutuamente o abrir dos instaladores.

Arreglo: agregar `_procesando`, deshabilitar el botón mientras corre y crear un `CancelToken` nuevo por intento.

La validación de origen, el SHA-256, la confirmación previa y el `FileProvider` restringido están correctamente planteados. No pude ejecutar Flutter test/analyze porque el sandbox bloqueó escrituras en la caché global de Flutter.
