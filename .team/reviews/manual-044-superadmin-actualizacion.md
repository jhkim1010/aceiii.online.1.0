Reading additional input from stdin...
2026-10-07T19:10:49.489212Z ERROR codex_models_manager::cache: failed to load models cache: missing field `base_instructions` at line 140 column 5
OpenAI Codex v0.146.0
--------
workdir: /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
model: gpt-5.6-sol
provider: openai
approval: never
sandbox: workspace-write [workdir, /tmp, $TMPDIR]
reasoning effort: none
reasoning summaries: none
session id: 01a117c6-8a2b-72b2-a0b1-88dfd4c80dfa
--------
user
Revisá este diff: se copia a ventago-admin-app (app Flutter superadmin, Android, APK fuera de Play) la actualización dentro de la app que ya funciona en tienda-admin-app (lib/core/update/actualizacion.dart y version_remota.dart copiados sin cambios: leen version.json, preguntan, bajan el APK, verifican sha256 y abren el instalador por FileProvider). Se agrega al build-apk.sh el aumento de build number y la publicación (scripts/publicar-apk.sh) en el tag ventago-admin-app-latest, y a publicar-apk.sh un ?t= anti-caché en las lecturas del feed. Buscá errores concretos (manifest, FileProvider authority, MethodChannel, navigatorKey, orden en build-apk.sh con set -e, tag/asset, anti-caché que rompa algo). No estilo.
diff --git a/scripts/publicar-apk.sh b/scripts/publicar-apk.sh
index d368e0f..0d02d78 100755
--- a/scripts/publicar-apk.sh
+++ b/scripts/publicar-apk.sh
@@ -43,7 +43,9 @@ if [[ "$cert" != "$CERT_ESPERADO"* ]]; then
 fi
 
 feed="https://github.com/$REPO/releases/download/$TAG/version.json"
-feed_actual="$(curl -fsSL "$feed" 2>/dev/null || true)"
+# [2026-10-07] ★ con «?t=» : sin eso la CDN de GitHub devuelve el version.json anterior durante
+#   minutos — la comprobación final fallaba («dice versionCode=2, no 3») aunque estuviera publicado
+feed_actual="$(curl -fsSL "$feed?t=$(date +%s)" 2>/dev/null || true)"
 publicado="$(sed -nE 's/.*"versionCode": *([0-9]+).*/\1/p' <<<"$feed_actual")"
 # el mismo APK ya publicado (p.ej. se re-ejecuta build-apk.sh --skip-build para las copias) → nada que hacer
 if [[ -n "$publicado" && "$code" == "$publicado" ]] \
@@ -78,7 +80,7 @@ gh release upload "$TAG" "$tmp/version.json" -R "$REPO" --clobber
 # (recién subido GitHub puede tardar unos segundos en servirlo: 404 → reintentar)
 vuelta=""
 for _ in 1 2 3 4 5 6; do
-  vuelta="$(curl -fsSL "$feed" 2>/dev/null | sed -nE 's/.*"versionCode": *([0-9]+).*/\1/p' || true)"
+  vuelta="$(curl -fsSL "$feed?t=$(date +%s)" 2>/dev/null | sed -nE 's/.*"versionCode": *([0-9]+).*/\1/p' || true)"
   [[ "$vuelta" == "$code" ]] && break
   sleep 5
 done
diff --git a/ventago-admin-app/android/app/src/main/AndroidManifest.xml b/ventago-admin-app/android/app/src/main/AndroidManifest.xml
index 0659027..efbca7c 100644
--- a/ventago-admin-app/android/app/src/main/AndroidManifest.xml
+++ b/ventago-admin-app/android/app/src/main/AndroidManifest.xml
@@ -2,6 +2,8 @@
     <!-- release APK 네트워크 필수: 없으면 소켓 EPERM(errno=1) -->
     <uses-permission android:name="android.permission.INTERNET"/>
     <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
+    <!-- [2026-10-07] actualización dentro de la app: abrir el instalador con el APK descargado -->
+    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>
     <uses-permission android:name="android.permission.USE_BIOMETRIC"/>
     <application
         android:label="ventago_admin_app"
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
diff --git a/ventago-admin-app/android/app/src/main/kotlin/com/coolsistema/ventago_admin_app/MainActivity.kt b/ventago-admin-app/android/app/src/main/kotlin/com/coolsistema/ventago_admin_app/MainActivity.kt
index e1a9520..5cc4b1c 100644
--- a/ventago-admin-app/android/app/src/main/kotlin/com/coolsistema/ventago_admin_app/MainActivity.kt
+++ b/ventago-admin-app/android/app/src/main/kotlin/com/coolsistema/ventago_admin_app/MainActivity.kt
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
diff --git a/ventago-admin-app/build-apk.sh b/ventago-admin-app/build-apk.sh
index af15cc3..0f93ea6 100755
--- a/ventago-admin-app/build-apk.sh
+++ b/ventago-admin-app/build-apk.sh
@@ -4,6 +4,7 @@
 # 사용법:
 #   ./build-apk.sh                # 빌드 후 복사
 #   ./build-apk.sh --skip-build   # 기존 빌드 산출물만 복사
+#   NOTAS="..." ./build-apk.sh    # 앱의 「Nueva versión」 창에 보일 안내(선택)
 #
 # 복사 대상:
 #   1) Dropbox/ACE_3_uversion/app herramientas download  — 버전명
@@ -26,7 +27,26 @@ FIXED_DEST="/Users/marcoskim/Google Drive/내 드라이브/ventago-superadmin/ve
 
 cd "$APP_DIR"
 
+# [2026-10-07] (tienda-admin 과 동일) 앱 안 업데이트: 빌드할 때마다 build 번호를 올린다(같으면 휴대폰이 새 버전으로 안 본다).
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
   echo "▶ flutter build apk --release (superadmin)"
   flutter build apk --release
 fi
@@ -37,6 +57,12 @@ if [[ ! -f "$APK_SRC" ]]; then
   exit 1
 fi
 
+# [2026-10-07] 앱 안 업데이트용 게시 (GitHub Releases → 앱이 열릴 때 「Nueva versión」 을 묻는다)
+#   ★ 복사(Dropbox/Drive)보다 먼저 — 폴더가 안 붙어 있어도 게시는 된다
+#   업로드 키로 서명된 APK 만 게시한다 — 다른 키면 휴대폰이 설치를 거부한다.
+CERT_UPLOAD="23747e710c3c77d8e989626b98d26464baee869d70e44857b8a5b0dc4e3927c7"
+"$APP_DIR/../scripts/publicar-apk.sh" "$APK_SRC" "ventago-admin-app-latest" "ventago-admin-app.apk" "$CERT_UPLOAD" "${NOTAS:-}"
+
 stamp="$(date -r "$APK_SRC" '+%Y%m%d-%H%M')"
 apk_name="ventago_superadmin_android_${stamp}.apk"
 missing=0
diff --git a/ventago-admin-app/lib/main.dart b/ventago-admin-app/lib/main.dart
index fb58b0e..94c8371 100644
--- a/ventago-admin-app/lib/main.dart
+++ b/ventago-admin-app/lib/main.dart
@@ -2,6 +2,7 @@ import 'package:flutter/material.dart';
 import 'package:flutter_riverpod/flutter_riverpod.dart';
 import 'core/network/session_signal.dart';
 import 'core/theme/app_theme.dart';
+import 'core/update/actualizacion.dart';
 import 'features/auth/auth_controller.dart';
 import 'features/auth/login_screen.dart';
 import 'shared/app_shell.dart';
@@ -10,12 +11,34 @@ void main() {
   runApp(const ProviderScope(child: VentagoAdminApp()));
 }
 
-class VentagoAdminApp extends StatelessWidget {
+// [2026-10-07] 새 버전 안내 — build-apk.sh 가 이 주소에 version.json 을 올린다 (tienda-admin 과 같은 방식)
+const _feedActualizacion =
+    'https://github.com/jhkim1010/ventago-downloads/releases/download/ventago-admin-app-latest/version.json';
+
+// 앱 시작 시 업데이트 다이얼로그를 띄우기 위한 루트 navigator 키
+final rootNavigatorKey = GlobalKey<NavigatorState>();
+
+class VentagoAdminApp extends StatefulWidget {
   const VentagoAdminApp({super.key});
 
+  @override
+  State<VentagoAdminApp> createState() => _VentagoAdminAppState();
+}
+
+class _VentagoAdminAppState extends State<VentagoAdminApp> {
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
       title: 'Ventago Admin',
       debugShowCheckedModeBanner: false,
       scaffoldMessengerKey: rootScaffoldMessengerKey,
diff --git a/ventago-admin-app/pubspec.yaml b/ventago-admin-app/pubspec.yaml
index 6ab13e8..98d3327 100644
--- a/ventago-admin-app/pubspec.yaml
+++ b/ventago-admin-app/pubspec.yaml
@@ -39,6 +39,7 @@ dependencies:
   flutter_riverpod: ^2.5.1
   # HTTP (async/await + 인터셉터)
   dio: ^5.4.0
+  crypto: ^3.0.6
   # 토큰 보안 저장
   flutter_secure_storage: ^9.0.0
   # 숫자/날짜 포맷
=== NEW Actualizacion.kt
package com.coolsistema.ventago_admin_app

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
=== NEW res/xml/actualizacion_paths.xml
<?xml version="1.0" encoding="utf-8"?>
<!-- [2026-10-06] Actualización dentro de la app: sólo la carpeta del APK descargado -->
<paths>
    <cache-path name="actualizacion" path="actualizacion/" />
</paths>
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
요청하신 범위만 검토하겠습니다. 특히 기존 `tienda-admin-app` 구현과 실제 파일을 대조하고, 빌드·게시 스크립트의 실패 경로 및 Android 설정 연결을 확인한 뒤 확실한 문제만 보고하겠습니다. 파일은 수정하지 않습니다.
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse Failed
hook: PreToolUse Completed
hook: PreToolUse Completed
exec
/bin/zsh -lc "sed -n '1,220p' .team/REVIEW-PROTOCOL.md && sed -n '1,240p' CLAUDE.md && sed -n '1,220p' scripts/publicar-apk.sh && sed -n '1,180p' ventago-admin-app/build-apk.sh" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 0ms:
# cmux team 협업 프로토콜 — Claude Code(구현) ↔ codex(보안 검토)

역할 경계는 [`AGENTS.md`](../AGENTS.md) 가 정의한다. 이 문서는 **두 에이전트가 어디서 만나는지**만 정한다.

## 원칙

| | Claude Code | codex |
|---|---|---|
| 코드 수정 | **한다** | 하지 않는다 (보고서만) |
| 커밋·push | 한다 | 하지 않는다 |
| 마이그레이션 | 새 파일 작성·적용 | 초안 제안만, 기존 파일 수정 금지 |
| 운영 DB | 조회 허용(CLAUDE.md 규칙) | **접속 금지** |
| 최종 판단 | **한다** — 검토 지적의 수용/반박을 결정 | 하지 않는다 |

**codex 의 지적은 입력이지 명령이 아니다.** Claude 는 각 지적에 대해 수용하거나 근거를 대고 반박한다.
반박도 기록으로 남긴다 — 다음 검토에서 같은 지적이 반복되는 것을 막는다.

## 디렉터리 규약

```
.team/
├── config.json              # 모델 설정 (추적됨)
├── REVIEW-PROTOCOL.md       # 이 문서
├── tasks/NNN-<slug>/
│   └── task.md              # 구현 태스크 정의 (Claude 가 집행)
└── reviews/
    ├── NNN-codex.md         # codex 검토 보고서 (codex 가 생성)
    └── NNN-resolution.md    # 지적별 수용/반박 결정 (Claude 가 생성)
```

`reviews/` 는 추적한다 — 무엇을 왜 수용/반박했는지가 다음 phase 의 근거가 된다.

## 흐름

```
1. Claude   구현 → 커밋 (아직 push 안 함)
2. Claude   scripts/codex-review.sh --task NNN   ← 변경 diff 를 codex 에 넘긴다
3. codex    .team/reviews/NNN-codex.md 생성 (AGENTS.md 보고 형식)
4. Claude   지적별 판단 → .team/reviews/NNN-resolution.md
              - 수용 → 수정 커밋
              - 반박 → 근거 기록 (코드 그대로)
5. Claude   CRITICAL/HIGH 가 모두 해소·반박된 뒤에만 push
```

**게이트:** `CRITICAL` 또는 `HIGH` 가 미해소 상태로 남아 있으면 push 하지 않는다.
`MEDIUM`/`LOW` 는 resolution 에 기록만 하고 넘어갈 수 있다.

## 검토 입력에서 제외하는 것

`scripts/codex-review.sh` 가 diff 를 만들 때 아래를 제외한다. codex 가 값을 보지 못하게 하는 것이 목적이다.

- `.env`, `.env.*` (AGENTS.md 금지 항목)
- `*.pem`, `*.key`, `id_*`
- `package-lock.json`, `node_modules/` (노이즈)

## 실행

```bash
# 태스크 단위 검토 — main 대비 현재 브랜치 diff
scripts/codex-review.sh --task 001

# 워킹트리 검토 — 커밋 전 빠른 점검
scripts/codex-review.sh --working

# 특정 경로만
scripts/codex-review.sh --task 002 --paths api-ventago/src/app/products
```

cmux team 으로 병렬 실행할 때:

```bash
cmux claude-teams     # 구현 측 (기존 .team/tasks 집행)
cmux codex-teams      # 검토 측
```

> **codex 미설치 상태면 `cmux codex-teams` 가 `codex not found in PATH` 로 실패한다.**
> `npm i -g @openai/codex` 후 `codex login` 을 한 번 거쳐야 한다.

## 검토 대상 우선순위 (이 저장소 기준)

AGENTS.md 의 일반 기준 위에, 이 프로젝트에서 실제로 사고가 났던 지점을 얹는다.

1. **쓰기 경로의 트랜잭션 누락** — 여러 모델을 순차 호출하며 `transaction` 인자를 빠뜨리면 그 문장만 별도 커밋돼 부분 저장이 된다 (Phase 64 결함 2·3·4)
2. **`stocks` 원장 규약** — append-only. UPDATE/DELETE 금지, 조회·기록은 `product_branch_id` 기준 (`product_id` 컬럼은 없다)
3. **테넌트 경계** — 사용자가 준 `branchId`/`variantId`/`storeId` 를 소유권 확인 없이 쓰는 경로 (Phase 69 CR-02 유형)
4. **fail-open** — 권한·역할 판정에 실패했을 때 *더 주는* 분기 (Phase 65 W6 6-2 유형)
5. **트랜잭션 안 외부 I/O** — HTTP·프린터·소켓 호출은 커밋 후에 (pool 고갈)
# Ventago — POS/ERP 시스템 개발 가이드

## 프로젝트 개요

다점포 소매업 대상 POS/ERP 시스템. 재고·판매·재무·생산·외주 관리를 포함한 종합 업무 플랫폼.

- **운영 URL**: https://newapi.coolsistema.com/api (API), https://app.coolsistema.com (프론트)
- **운영 서버**: srv803182 (IP: 62.72.7.245, 포트 5002)
- **배포**: Jenkins CI/CD → Docker
- **저장소 구조**: npm workspaces 모노레포

```
ACE_online_1.0/
├── api-ventago/     # NestJS 백엔드 (포트 5002)
├── ventago-app/     # Next.js 프론트엔드 (포트 5001 docker / 3050 dev)
├── print-agent/     # 열감지(comandera) 프린터 에이전트 (Electron)
└── zebra-agent/     # Zebra 바코드 라벨 에이전트 (Electron)
```

---

## 기술 스택

### 백엔드 (api-ventago)
- **Framework**: NestJS 11 + TypeScript
- **ORM**: Sequelize + sequelize-typescript (`underscored: true` 전역 설정 → DB 컬럼은 snake_case)
- **DB**: PostgreSQL 18, DB명 `ventago` — 로컬 Mac 5432 / 운영 srv803182 5434 (둘 다 **호스트 OS 설치**, Docker 아님). 상세는 「DB 마이그레이션 적용 규칙」
- **인증**: JWT (Passport)
- **파일 저장**: MinIO (S3 호환, MinioService/MinioModule로 공유)
- **실시간**: Socket.io
- **로깅**: Winston (nest-winston)
- **스케줄링**: @nestjs/schedule

### 프론트엔드 (ventago-app)
- **Framework**: Next.js 13 (Pages Router) + React 18
- **UI**: Material-UI (MUI) 5
- **상태관리**: Redux Toolkit
- **폼**: React Hook Form + Yup
- **HTTP**: Axios (`src/services/api.service.ts`의 `apiConnector`)
- **데이터 캐시**: SWR (`src/hooks/api/` — 5분 dedup)
- **인가**: CASL (Attribute-based ACL)
- **분석**: PostHog

### 프린터 에이전트 (print-agent / zebra-agent)
- **Framework**: Electron 28
- **WebSocket**: socket.io-client (네임스페이스: `/print-agent`)
- **서버 URL 고정**: 운영 **`https://newapi.coolsistema.com/api`**(nginx+TLS 경유 —
  `print-agent/main.js:33` · `zebra-agent/main.js:17` 실측 2026-09-26), 개발 `http://localhost:5002/api`
  ★ 종전에 「운영 `http://62.72.7.245:5002/api`」로 적혀 있었으나 **틀렸다.** 서버에 공개된
    5002 포트는 없다(공개된 것은 5003, 5002 는 컨테이너 내부 포트). 에이전트는 IP 로 안 붙는다.
- **인증**: API Key (BranchAgent 테이블) — 서버 URL 입력 불필요, API Key만 입력
- **print-agent**: ESC/POS 열감지 프린터 (escpos 라이브러리, Network + USB)
- **zebra-agent**: ZPL II 바코드 라벨 (TCP Raw Socket 9100 + USB lp/PowerShell)
- **라벨 타입**: 50x25mm simple, 50x25mm doble, 100x25mm cartulina (좌우 복제)
- **UI 테마**: 다크 네이비 (#1a1a2e) + 골드 (#f5a623)

---

## 아키텍처 핵심 규칙

### DB 컬럼 네이밍
Sequelize `underscored: true` 설정으로 모델의 camelCase 속성이 DB snake_case 컬럼으로 자동 매핑됨.
- 모델: `logoUrl` → DB: `logo_url`
- 모델: `aliasName` → DB: `alias_name`
- **SQL 직접 실행 시 반드시 snake_case 사용**

### DB 스키마 reference (혼동 방지)
SQL/마이그레이션/raw query 작성 전 **반드시 다음 파일 참조** — 추측 X, 컬럼명 확인:
- `.planning/intel/db-schema-tables.md` — 133개 테이블의 모든 컬럼 (타입/NOT NULL/default)
- `.planning/intel/db-schema-fks.md` — 모든 외래 키 관계 (`src_table.src_col → fk_table.fk_col`)

스키마 변경 후 재생성:
```bash
./.planning/intel/db-schema.regen.sh   # local PG18 ventago DB → 두 파일 갱신
```
운영에도 같은 마이그레이션이 적용되므로 로컬 결과를 git commit 하면 됨.

자주 헷갈리는 컬럼명 (실수 방지):
- `sales.branch_id` **있음** (2026-08-19 추가). 판매의 지점은 **이 컬럼**이 권위다 —
  `user_id → users.branch_id` 로 조인하면 판매자가 다른 지점에서 팔았을 때 틀린다
  (2026-08-20 에 실제로 그렇게 잘못 읽었다). 순번도 이 컬럼 기준으로 매장이 아니라
  **지점별**로 매겨진다 (`uq_sales_branch_daylocal_dn`)
- `terminal_id` 만 직접 FK. `box`/`branch` 도달은 join 필요
- `sale_items` 의 promo 컬럼: `is_promo_free` / `promotion_id` / `promo_group_id`

### 멀티테넌트 구조
거의 모든 테이블에 `store_id` FK가 있어 매장 단위로 데이터 격리됨.

**계층 구조:** `Store → Branch(Sucursal) → Box(Caja) → Terminal` (1:N:N:N)
- 1개 매장에 여러 지점, 1개 지점에 여러 카하, 1개 카하에 여러 터미널 가능
- Branch 생성 시 기본 Box + Terminal 자동 생성 (`branch.service.ts`의 `createBranch`)
- 매장 최초 등록 시 기본 Branch/Box/Terminal 생성 (`storeTemplate.service.ts`의 `createStoreDefaults`)

### ★★ 카하(Box) 규칙 — 돈은 **서랍 단위로만** 모인다 (2026-09-09 확정)

**이미 열려 있는 caja 는 절대로 다시 열지 않는다.** 권한 있는 사람이 한 번 열었으면,
다른 사용자·다른 터미널이 와도 **그 세션을 그대로 쓴다.**

- 현금은 서랍 하나에 섞여 있다. 장부가 사람 수만큼 나뉘면 **돈의 단위와 장부의 단위가
  갈라진다** — 그 상태에서는 어떤 화면도 "이 서랍에 얼마가 있어야 하는가" 에 답할 수 없다.
- 종전 설계(폐기): "여러 사용자가 같은 서랍에 각자 세션을 갖는다".
  실측 2026-09-08 HELGUERA box 20 — israel 11:13 · jungho 15:55 로 세션 2개.
- 정산(`box_settlements`)은 처음부터 **서랍·구간 단위**였다. 그래서 금액은 안 틀렸지만
  세션을 세는 화면들이 "카하가 두 번 열렸다" 로 보였다.

★ 이 규칙은 **애플리케이션 체크만으로는 지켜지지 않는다.** `findOne` 과 `create`
  사이에 다른 요청이 끼면 둘 다 "없음" 을 보고 둘 다 INSERT 한다 —
  실측으로 **5ms 차이의 중복 세션**이 여러 건 있다(2026-09-08 box 6: 292·293,
  2026-08-16 box 6: 3개, 2026-08-10 box 20: 3개).
  DB 부분 UNIQUE 인덱스가 같이 있어야 실제로 강제된다:

  ```sql
  CREATE UNIQUE INDEX CONCURRENTLY uq_cash_registers_open_por_box
    ON cash_registers (box_id) WHERE closing_time IS NULL;
  ```

  ⤷ **기존 중복 행 정리가 먼저다.** 인덱스만 넣으면 생성이 실패한다.

★ 남은 정합 작업(규칙은 확정, 코드 미반영):
  `getOpenCashRegister(userId)` · `status().openedToday(userId)` · 1770·476·1804행의
  `where: { userId, closingTime: null }` 는 아직 **사용자 기준**이다. 서랍 기준으로
  옮겨야 규칙이 화면까지 일관된다(`openedToday` 는 VentaVista 의 「Inicial」 오류의 원인이기도 하다).

### 프린터 에이전트 구조
```
branch_agents (지점당 N개 등록 가능)
  - branchId (NOT UNIQUE → 다중 프린터 허용)
  - agentType: 'thermal' | 'zebra'
  - label: 'Comandera Cocina', 'Zebra Almacén' 등
  - apiKey: UNIQUE (에이전트별 고유 인증 키)
  - isOnline, socketId, lastSeenAt

terminals (터미널별 에이전트 매핑)
  - thermalAgentId FK → branch_agents (어떤 comandera로 출력?)
  - zebraAgentId FK → branch_agents (어떤 zebra로 출력?)
```

### 파일 업로드 (MinIO)
- `MinioModule`을 해당 모듈의 `imports`에 추가
- `MinioService.uploadFile(file, fileName)` → `{ fileName }` 반환
- 프론트엔드 이미지 URL: `{API_HOST}/minio/{fileName}`
- 개발: `http://localhost:5002/api`, 운영: `https://newapi.coolsistema.com/api`

### API 서비스 (`api.service.ts`)
```typescript
apiConnector.get(path)           // GET
apiConnector.post(path, body)    // POST
apiConnector.put(path, body)     // PUT
apiConnector.remove(path)        // DELETE
apiConnector.sendFile(path, formData)  // POST multipart
apiConnector.putFile(path, formData)   // PUT multipart
```

### 인증 컨텍스트
- `useAuth()` 훅으로 `user` 객체 접근. user에는 `storeId`, `storeName`, `aliasName`, `logoUrl`, 권한 정보 포함.
- `AuthContext` + `BranchContext` 분리: `selectedBranchId`는 BranchContext에서 관리 (지점 전환 시 110+ 컴포넌트 불필요 리렌더 방지)
- auth 응답은 `api-ventago/src/app/auth/auth.service.ts`의 `/me` 엔드포인트에서 구성.

### 세션 & 터미널 보안 (`api-ventago/src/app/session/`)
중복 로그인 절대 차단 + 디바이스/IP 기반 부정 사용 방지 시스템.

**테이블 3개:**
- `active_sessions` — 유저당 1개만 존재 (UNIQUE userId). 새 로그인 시 기존 세션 삭제 → 기존 세션은 즉시 401 `SESSION_EXPIRED`
- `terminal_devices` — 브라우저 fingerprint ↔ 터미널 바인딩. 새 디바이스 접속 시 터미널 등록 강제
- `branch_ip_registries` — public IP ↔ 지점(sucursal) 매핑. 새 IP 접속 시 지점 등록 강제

**로그인 플로우:**
1. 자격 증명 검증 → 기존 ActiveSession 삭제 (중복 로그인 차단)
2. IP 확인 → 미등록 IP면 `requireBranchRegistration: true` 반환
3. Fingerprint 확인 → 미등록이면 `requireTerminalRegistration: true` 반환
4. 정상이면 `sessionToken` (UUID v4) 발급

**프론트엔드 연동:**
- `api.service.ts`: 모든 요청에 `x-session-token` 헤더 자동 주입
- `AuthContext.tsx`: 디바이스 fingerprint 수집, sessionToken 저장
- `LoginView.tsx`: Branch/Terminal 등록 모달, 세션만료 알림 (`?reason=session_expired`)
- `utils/device-fingerprint.ts`: 브라우저 특성 SHA-256 해시

**SessionGuard 적용:** `guards/session.guard.ts` — JWT 인증 후 추가로 sessionToken 검증. 필요한 컨트롤러에 `@UseGuards(SessionGuard)` 적용.

---

## 주요 모듈 맵

### 백엔드 모듈 위치
```
api-ventago/src/app/
├── auth/           # JWT 인증, 권한 가드
├── store/          # 매장 관리 (로고 업로드 포함)
├── branch/         # 지점 관리
├── users/          # 사용자, 역할, 권한
├── products/       # 상품, 카테고리, 재고
├── sales/          # 판매, 결제수단, 할인
├── expenses/       # 비용 관리
├── box/            # 금전함 운영
├── caja-fuerte/    # 금고 관리
├── production/     # 생산 관리 (BOM, 작업지시)
├── subcon/         # 외주 (납품업체, 발주, 검수, 정산)
├── print/          # 프린터 에이전트 관리 (BranchAgent, WebSocket 게이트웨이)
├── terminal/       # 터미널 관리 (에이전트 매핑 포함)
├── marketplace/    # 마켓플레이스
├── revendedor/     # 재판매자 포털
├── session/        # 세션 보안 (중복로그인 차단, 디바이스/IP 감지)
└── chat/           # AI 채팅 (Knowledge base)
```

### 프론트엔드 페이지 구조
```
ventago-app/src/pages/
├── nueva-venta/    # POS 판매 화면
├── ventas/         # 판매 내역
├── productos/      # 상품 관리
├── precios/        # 가격 관리
├── gastos/         # 비용 관리
├── caja/           # 금전함
├── caja-fuerte/    # 금고
├── control-de-caja/# 금전함 통제
├── sucursales/     # 지점 관리
│   └── [id]/impresora  # 에이전트(프린터) 관리 페이지
├── usuarios/       # 사용자 관리
├── talleres/       # 외주 관리
├── dashboards/     # 대시보드
├── reportes/       # 보고서
├── configuracion/  # 설정
├── herramientas/   # 도구 (다운로드 페이지)
└── admin/          # 관리자 (매장, 앱, 구독 등)
```

---

## 레이아웃 구조

### 사이드바
- `ventago-app/src/layouts/UserLayout.tsx` — 메인 레이아웃 진입점
- `ventago-app/src/@core/layouts/VerticalLayout.tsx` — 레이아웃 프레임
- `ventago-app/src/@core/layouts/components/vertical/navigation/index.tsx` — 네비게이션 (React.memo 적용)
- `ventago-app/src/layouts/components/vertical/SidebarFooter.tsx` — 사이드바 하단 (로고/매장명 + 시계)

### 사이드바 리렌더링 방지 (적용됨)
- `Navigation` 컴포넌트: `React.memo` 적용, `darkTheme`을 `useMemo`로 메모이제이션
#!/usr/bin/env bash
# [2026-10-06] Actualización dentro de la app — publica un APK para que las apps lo ofrezcan.
#
# Uso (lo llaman mobile-sales-app/build-apk.sh y tienda-admin-app/build-apk.sh):
#   scripts/publicar-apk.sh <apk> <tag-release> <nombre-asset.apk> <cert-sha256-esperado> ["notas"]
#
# Sube a GitHub Releases (jhkim1010/ventago-downloads, público):
#   <tag>/<nombre-asset>-<versionCode>.apk   y después   <tag>/version.json
# El orden importa: version.json nunca apunta a un APK que todavía no está. Y el APK lleva el
# versionCode en el nombre (inmutable): si la subida del json falla, el feed viejo sigue
# apuntando a SU APK con SU hash — nunca a un archivo reemplazado (codex 014).
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

# ★ head/grep -m1 cortan la tubería: con pipefail, aapt2/apksigner mueren por SIGPIPE (141)
badging="$("$BT/aapt2" dump badging "$APK" | sed -n 1p)"
code="$(sed -E "s/.*versionCode='([0-9]+)'.*/\1/" <<<"$badging")"
name="$(sed -E "s/.*versionName='([^']*)'.*/\1/" <<<"$badging")"
[[ "$code" =~ ^[0-9]+$ ]] || { echo "ERROR: no pude leer versionCode del APK" >&2; exit 1; }

cert="$("$BT/apksigner" verify --print-certs "$APK" | awk '/certificate SHA-256 digest/ && !f {print $NF; f=1}')"
if [[ "$cert" != "$CERT_ESPERADO"* ]]; then
  echo "ERROR: el APK está firmado con ${cert:0:16}…, se esperaba ${CERT_ESPERADO:0:16}…" >&2
  echo "       Los teléfonos no podrían instalar esta actualización. No se publica." >&2
  exit 1
fi

feed="https://github.com/$REPO/releases/download/$TAG/version.json"
# [2026-10-07] ★ con «?t=» : sin eso la CDN de GitHub devuelve el version.json anterior durante
#   minutos — la comprobación final fallaba («dice versionCode=2, no 3») aunque estuviera publicado
feed_actual="$(curl -fsSL "$feed?t=$(date +%s)" 2>/dev/null || true)"
publicado="$(sed -nE 's/.*"versionCode": *([0-9]+).*/\1/p' <<<"$feed_actual")"
# el mismo APK ya publicado (p.ej. se re-ejecuta build-apk.sh --skip-build para las copias) → nada que hacer
if [[ -n "$publicado" && "$code" == "$publicado" ]] \
   && grep -q "\"sha256\": *\"$(shasum -a 256 "$APK" | awk '{print $1}')\"" <<<"$feed_actual"; then
  echo "✔ v$name (versionCode $code) ya estaba publicado — sin cambios"
  exit 0
fi
if [[ -n "$publicado" && "$code" -le "$publicado" ]]; then
  echo "ERROR: versionCode $code no es mayor que el publicado ($publicado). Subí la versión en pubspec.yaml." >&2
  exit 1
fi

sha="$(shasum -a 256 "$APK" | awk '{print $1}')"
ASSET="${ASSET%.apk}-$code.apk"
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
# (recién subido GitHub puede tardar unos segundos en servirlo: 404 → reintentar)
vuelta=""
for _ in 1 2 3 4 5 6; do
  vuelta="$(curl -fsSL "$feed?t=$(date +%s)" 2>/dev/null | sed -nE 's/.*"versionCode": *([0-9]+).*/\1/p' || true)"
  [[ "$vuelta" == "$code" ]] && break
  sleep 5
done
[[ "$vuelta" == "$code" ]] || { echo "ERROR: el feed publicado dice versionCode=$vuelta, no $code" >&2; exit 1; }
echo "✔ Publicado v$name (versionCode $code) → $feed"
#!/usr/bin/env bash
# superadmin 앱(ventago-admin-app, Android) 릴리즈 빌드 + 배포 폴더 자동 복사.
#
# 사용법:
#   ./build-apk.sh                # 빌드 후 복사
#   ./build-apk.sh --skip-build   # 기존 빌드 산출물만 복사
#   NOTAS="..." ./build-apk.sh    # 앱의 「Nueva versión」 창에 보일 안내(선택)
#
# 복사 대상:
#   1) Dropbox/ACE_3_uversion/app herramientas download  — 버전명
#   2) Dropbox/Personal de m. Marcos                     — 버전명 (설치 파일 개인 보관)
#   3) Google Drive/내 드라이브/ventago-superadmin/ventago-superadmin.apk — 고정명(배포 링크)
#
# 파일명 규칙: ventago_superadmin_android_<YYYYMMDD-HHMM>.apk (APK 컴파일 시각 기준)

set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APK_SRC="$APP_DIR/build/app/outputs/flutter-apk/app-release.apk"

DEST_DIRS=(
  "/Users/marcoskim/Dropbox/ACE_3_uversion/app herramientas download"
  "/Users/marcoskim/Dropbox/Personal de m. Marcos"
)

FIXED_DEST="/Users/marcoskim/Google Drive/내 드라이브/ventago-superadmin/ventago-superadmin.apk"

cd "$APP_DIR"

# [2026-10-07] (tienda-admin 과 동일) 앱 안 업데이트: 빌드할 때마다 build 번호를 올린다(같으면 휴대폰이 새 버전으로 안 본다).
#   publicar-apk.sh 가 「게시된 것보다 큰가」를 다시 확인한다.
subir_build() {
  local v b
  v="$(grep -E '^version:' pubspec.yaml | head -1 | awk '{print $2}')"
  b="${v##*+}"
  # ★ 고정 문자열 비교로 치환 — 정규식이면 버전의 「.」「+」가 메타문자가 된다
  python3 - "$v" "${v%%+*}+$((b + 1))" <<'PY'
import sys
viejo, nuevo = sys.argv[1:]
t = open('pubspec.yaml').read()
linea = 'version: ' + viejo + '\n'
assert t.count(linea) == 1, 'version: no encontrado exactamente una vez'
open('pubspec.yaml', 'w').write(t.replace(linea, 'version: ' + nuevo + '\n'))
PY
  echo "▶ version: $v → $(grep -E '^version:' pubspec.yaml | awk '{print $2}')"
}

if [[ "${1:-}" != "--skip-build" ]]; then
  subir_build
  echo "▶ flutter build apk --release (superadmin)"
  flutter build apk --release
fi

if [[ ! -f "$APK_SRC" ]]; then
  echo "ERROR: APK 산출물 없음: $APK_SRC" >&2
  echo "       --skip-build 없이 다시 실행하세요." >&2
  exit 1
fi

# [2026-10-07] 앱 안 업데이트용 게시 (GitHub Releases → 앱이 열릴 때 「Nueva versión」 을 묻는다)
#   ★ 복사(Dropbox/Drive)보다 먼저 — 폴더가 안 붙어 있어도 게시는 된다
#   업로드 키로 서명된 APK 만 게시한다 — 다른 키면 휴대폰이 설치를 거부한다.
CERT_UPLOAD="23747e710c3c77d8e989626b98d26464baee869d70e44857b8a5b0dc4e3927c7"
"$APP_DIR/../scripts/publicar-apk.sh" "$APK_SRC" "ventago-admin-app-latest" "ventago-admin-app.apk" "$CERT_UPLOAD" "${NOTAS:-}"

stamp="$(date -r "$APK_SRC" '+%Y%m%d-%H%M')"
apk_name="ventago_superadmin_android_${stamp}.apk"
missing=0

for dir in "${DEST_DIRS[@]}"; do
  if [[ ! -d "$dir" ]]; then
    echo "WARN: 폴더 없음, 건너뜀: $dir" >&2
    missing=1
    continue
  fi

  cp "$APK_SRC" "$dir/$apk_name"
  echo "✔ 복사: $dir/$apk_name"
done

if [[ -d "$(dirname "$FIXED_DEST")" ]]; then
  cp "$APK_SRC" "$FIXED_DEST"
  echo "✔ 복사: $FIXED_DEST"
else
  echo "WARN: 폴더 없음, 건너뜀: $(dirname "$FIXED_DEST")" >&2
  missing=1
fi

if [[ "$missing" -eq 1 ]]; then
  echo "ERROR: 일부 대상에 복사하지 못했습니다 (위 WARN 확인)" >&2
  exit 1
fi

echo "✔ 전체 복사 완료 ($apk_name)"

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
/bin/zsh -lc "git status --short && git diff -- ventago-admin-app scripts/publicar-apk.sh && printf '\\nFILES\\n' && rg --files ventago-admin-app/lib/core/update ventago-admin-app/android/app/src/main tienda-admin-app/lib/core/update tienda-admin-app/android/app/src/main | sort && printf '\\nDART\\n' && sed -n '1,280p' ventago-admin-app/lib/core/update/actualizacion.dart && sed -n '1,220p' ventago-admin-app/lib/core/update/version_remota.dart && printf '\\nGRADLE/MANIFEST\\n' && sed -n '1,220p' ventago-admin-app/android/app/build.gradle && sed -n '1,180p' ventago-admin-app/android/app/src/main/AndroidManifest.xml && printf '\\nTIENDA ANALOG\\n' && sed -n '1,220p' tienda-admin-app/android/app/src/main/kotlin/*/*/*/Actualizacion.kt 2>/dev/null || true && sed -n '1,160p' tienda-admin-app/android/app/src/main/AndroidManifest.xml" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 0ms:
 M .claude/hooks/.gsd-snapshot.json
 M .planning/config.json
 M api-ventago
 M despacho-app/android/gradle.properties
 M despacho-app/pubspec.lock
 M scripts/publicar-apk.sh
 M talleres-vendor-app/android/gradle.properties
 M talleres-vendor-app/pubspec.lock
 M ventago-admin-app/android/app/src/main/AndroidManifest.xml
 M ventago-admin-app/android/app/src/main/kotlin/com/coolsistema/ventago_admin_app/MainActivity.kt
 M ventago-admin-app/build-apk.sh
 M ventago-admin-app/lib/main.dart
 M ventago-admin-app/pubspec.lock
 M ventago-admin-app/pubspec.yaml
 M ventago-app
?? ".planning/ANALISIS-2026-09-17-legacy-vcontrolgrid2-\352\262\251\354\260\250\353\266\204\354\204\235.md"
?? .planning/ANALISIS-2026-10-05-menu-estructura.md
?? .planning/ANALISIS-2026-10-06-reportes-ux/
?? .planning/GUIA-miguel-acceso-servidor2.md
?? ".planning/PLAN-2026-09-16-\354\204\234\353\262\204-\353\266\204\353\246\254\354\231\200-\354\213\240\352\267\234-\354\235\264\354\240\204.md"
?? .planning/SETUP-2026-08-26-servidor2-74.208.60.137.md
?? .planning/pedidos/PEDIDO-10/mockup.html
?? .planning/pedidos/PEDIDO-10/mockup.png
?? .planning/pedidos/PEDIDO-11/
?? .planning/pedidos/PEDIDO-12/
?? .planning/pedidos/PEDIDO-13/
?? .planning/pedidos/PEDIDO-14/
?? .planning/pedidos/PEDIDO-15/
?? .planning/pedidos/PEDIDO-16/
?? .planning/pedidos/PEDIDO-18/
?? .planning/pedidos/PEDIDO-5/captura-tienda.jpg
?? .planning/pedidos/PEDIDO-6/captura-tienda.jpg
?? .planning/pedidos/PEDIDO-7/mockup.html
?? .planning/pedidos/PEDIDO-7/mockup.png
?? .planning/pedidos/PEDIDO-8/
?? .planning/pedidos/PEDIDO-9/mockup.html
?? .planning/pedidos/PEDIDO-9/mockup.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-live-s2-medios.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-live-s3-gastos.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-live-s4-ingresos.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-live-s5-facturacion.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-live-s6-cajas.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-offline-coldstart.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-offline-hoy.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-online-recovered.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step2.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step3-s2.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step3-s3.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step3-s4.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step3-s5.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step3-s6.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step4-back-to-hoy.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step4-helguera-cajas.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step4-helguera-cajas2.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step4-helguera.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step4-reopen-persist.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step4-reselector.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step4-selector.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step5-back-from-hoy-exit.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step5-back-from-s4.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step5-pulltorefresh.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step5-relaunch.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step5-section4.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step5-todas.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-afterapply.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-aftertopswipe.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-appinfo.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-appinfo2.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-appinfo3.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-atpilotbold.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-back1.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-backcheck.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-backcheck2.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-backfromblack.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-bigtime.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-cancelled.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-complication-list2.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-complication-picker.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-dateprovider.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-edit2.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-editwatchface.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-everyday.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-everyday2.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-everydayface.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-face2.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-facelist2.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-finalstate.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-home.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-home2.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-layoutpage.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-longpress.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-nav1.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-nav2.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-nav3.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-nav4-complications.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-nav5.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-nav6-list.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-nextface.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-notifprovider.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-page2.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-page2b.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-pbedit.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-providerchooser.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-radcomplications.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-radedit1.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-radial.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-recover.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-recover2.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-reenter.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-retry-list.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-settings.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-settings2.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-settings3.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-settings4.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-settings5.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-settings6.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-settingsbottom.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-sunriseprovider.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-sunriseprovider2.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-swipe-left.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-swipe-right.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-swipeface.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-taparea.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-taponcomplication.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-tileA.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-tileB.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-tileC.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-tileLongpress.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-tiles-a.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-tiles-b.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-tiles1.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-timertile.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-topilotbold.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-track-p2.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-track-p2b.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-track-p3.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-track-p4.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-track-p4b.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-trackedit.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-wake.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step6-wftab2.png
?? .planning/phases/98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es/98-12-step9-final-app-check.png
?? .planning/phases/99-men-estructura-coherente-sin-hu-rfanos-ni-callejones-sin-sal/.gitkeep
?? .planning/sketches/factura-pdf-ticket.html
?? .planning/sketches/factura-pdf-ticket.png
?? .planning/sketches/menu-propuesta.html
?? .planning/sketches/menu-propuesta.png
?? .planning/sketches/novedades-alt-f1.html
?? .planning/sketches/pedidos-checklist.html
?? .planning/sketches/pedidos-checklist.png
?? .team/reviews/.manual-89-diseno.prompt
?? .team/reviews/.manual-cheques.prompt
?? .team/reviews/.manual-money.prompt
?? .team/reviews/.manual-phase93-p1.prompt
?? .team/reviews/.manual-phase93-p4.prompt
?? .team/reviews/010-codex.md
?? .team/reviews/015-codex-whatsapp-es.md
?? .team/reviews/016-codex-pedido-11-12.md
?? .team/reviews/017-codex-costo-sin-stock.md
?? .team/reviews/_diff-030.txt
?? .team/reviews/auto-.-c44b566.md
?? .team/reviews/auto-api-ventago-0100d26.md
?? .team/reviews/auto-api-ventago-053ddffc.md
?? .team/reviews/auto-api-ventago-06a888ff_ventago-app-afbcbf3.md
?? .team/reviews/auto-api-ventago-0748b9a2.md
?? .team/reviews/auto-api-ventago-0b2566bb_ventago-app-a64924d8.md
?? .team/reviews/auto-api-ventago-0d891ec8.md
?? .team/reviews/auto-api-ventago-1058cc89.md
?? .team/reviews/auto-api-ventago-1152e1f6.md
?? .team/reviews/auto-api-ventago-18ba95a.md
?? .team/reviews/auto-api-ventago-1a3bcf9.md
?? .team/reviews/auto-api-ventago-21ee29d.md
?? .team/reviews/auto-api-ventago-2528ffd5.md
?? .team/reviews/auto-api-ventago-25f0ecb0.md
?? .team/reviews/auto-api-ventago-282c86d6.md
?? .team/reviews/auto-api-ventago-29480476.md
?? .team/reviews/auto-api-ventago-3504e05.md
?? .team/reviews/auto-api-ventago-35b0727.md
?? .team/reviews/auto-api-ventago-3635b207_ventago-app-375d3f2.md
?? .team/reviews/auto-api-ventago-425a17d.md
?? .team/reviews/auto-api-ventago-45ac4a54.md
?? .team/reviews/auto-api-ventago-472b6112.md
?? .team/reviews/auto-api-ventago-4a17657.md
?? .team/reviews/auto-api-ventago-4ec4109.md
?? .team/reviews/auto-api-ventago-50459e81.md
?? .team/reviews/auto-api-ventago-55f92a09.md
?? .team/reviews/auto-api-ventago-580f24a9.md
?? .team/reviews/auto-api-ventago-597bdd21.md
?? .team/reviews/auto-api-ventago-59c7cc5.md
?? .team/reviews/auto-api-ventago-5c8f36fe.md
?? .team/reviews/auto-api-ventago-632c6780.md
?? .team/reviews/auto-api-ventago-64564cd6.md
?? .team/reviews/auto-api-ventago-668b650.md
?? .team/reviews/auto-api-ventago-66c67888.md
?? .team/reviews/auto-api-ventago-6a9d579_ventago-app-c98f001.md
?? .team/reviews/auto-api-ventago-6b66516.md
?? .team/reviews/auto-api-ventago-6ee2d011.md
?? .team/reviews/auto-api-ventago-6f0a8f4.md
?? .team/reviews/auto-api-ventago-754af978.md
?? .team/reviews/auto-api-ventago-7731d9bd.md
?? .team/reviews/auto-api-ventago-773e6240.md
?? .team/reviews/auto-api-ventago-777e9de.md
?? .team/reviews/auto-api-ventago-77b88753.md
?? .team/reviews/auto-api-ventago-7fc0a74.md
?? .team/reviews/auto-api-ventago-833aacf2.md
?? .team/reviews/auto-api-ventago-853b72ab.md
?? .team/reviews/auto-api-ventago-857ace55.md
?? .team/reviews/auto-api-ventago-94d8502.md
?? .team/reviews/auto-api-ventago-9eba587.md
?? .team/reviews/auto-api-ventago-9f759f15.md
?? .team/reviews/auto-api-ventago-a306d98.md
?? .team/reviews/auto-api-ventago-a3529d83.md
?? .team/reviews/auto-api-ventago-a36e84f_ventago-app-3cb66fe.md
?? .team/reviews/auto-api-ventago-a4543fb.md
?? .team/reviews/auto-api-ventago-aa2dc54.md
?? .team/reviews/auto-api-ventago-b3d65374_ventago-app-30b1b95.md
?? .team/reviews/auto-api-ventago-b4f34a9a_ventago-app-9573e76.md
?? .team/reviews/auto-api-ventago-bfa7695.md
?? .team/reviews/auto-api-ventago-c02b018.md
?? .team/reviews/auto-api-ventago-c0585fac.md
?? .team/reviews/auto-api-ventago-c0da8ce3.md
?? .team/reviews/auto-api-ventago-c325b48.md
?? .team/reviews/auto-api-ventago-c99d7441.md
?? .team/reviews/auto-api-ventago-cf384a75_ventago-app-e2c618bb.md
?? .team/reviews/auto-api-ventago-d4d1f715.md
?? .team/reviews/auto-api-ventago-d5b36a0.md
?? .team/reviews/auto-api-ventago-d7f3d10.md
?? .team/reviews/auto-api-ventago-dc80c95.md
?? .team/reviews/auto-api-ventago-dce04cb.md
?? .team/reviews/auto-api-ventago-de4a318f.md
?? .team/reviews/auto-api-ventago-df2ce772.md
?? .team/reviews/auto-api-ventago-e09c69a.md
?? .team/reviews/auto-api-ventago-e118a2d8.md
?? .team/reviews/auto-api-ventago-ea8b563f.md
?? .team/reviews/auto-api-ventago-eb118343.md
?? .team/reviews/auto-api-ventago-ef8910d7.md
?? .team/reviews/auto-api-ventago-f00005c_ventago-app-72564f4.md
?? .team/reviews/auto-api-ventago-f0380fd.md
?? .team/reviews/auto-api-ventago-f1a3cf93.md
?? .team/reviews/auto-api-ventago-f30b2ff5.md
?? .team/reviews/auto-api-ventago-f36b3633.md
?? .team/reviews/auto-api-ventago-f45d4ce.md
?? .team/reviews/auto-api-ventago-f770585f.md
?? .team/reviews/auto-api-ventago-fb8b4f6f.md
?? .team/reviews/auto-manual-89-root-bcc975f..694041e_api-ventago-1152e1f6..2c7201a2_ventago-app-fe69bdc..5931ca9.md
?? .team/reviews/auto-root-08c4868_api-ventago-adfe292e.md
?? .team/reviews/auto-root-09a7240_api-ventago-1c9d7abd_ventago-app-8aab1a3.md
?? .team/reviews/auto-root-16630d1_api-ventago-b3ce2588_ventago-app-946619a7.md
?? .team/reviews/auto-root-19ec460_ventago-app-fe69bdc.md
?? .team/reviews/auto-root-22c651d_api-ventago-b4d9ad8.md
?? .team/reviews/auto-root-2a9328a_api-ventago-3138dc48.md
?? .team/reviews/auto-root-33dbd94_api-ventago-3840f54f.md
?? .team/reviews/auto-root-378f116.md
?? .team/reviews/auto-root-3e6f981.md
?? .team/reviews/auto-root-3fec244_ventago-app-57d99ec.md
?? .team/reviews/auto-root-411425a.md
?? .team/reviews/auto-root-42ebfa8.md
?? .team/reviews/auto-root-432a75a_api-ventago-0da64b9c.md
?? .team/reviews/auto-root-47a50a0_api-ventago-62f2988.md
?? .team/reviews/auto-root-4854608.md
?? .team/reviews/auto-root-4d715b0.md
?? .team/reviews/auto-root-521a4cf_api-ventago-d1eaa8b6.md
?? .team/reviews/auto-root-5386cbd_api-ventago-7eda8f6e.md
?? .team/reviews/auto-root-5442b7b_ventago-app-b5a2ca52.md
?? .team/reviews/auto-root-5457333.md
?? .team/reviews/auto-root-55e1704_api-ventago-670810d8.md
?? .team/reviews/auto-root-58ff2f0_ventago-app-c14b7c3.md
?? .team/reviews/auto-root-5bfcdc2_ventago-app-964a64f.md
?? .team/reviews/auto-root-5c51654_api-ventago-7058340.md
?? .team/reviews/auto-root-5de413f_api-ventago-7d74ca88.md
?? .team/reviews/auto-root-5e21236_ventago-app-89843d4.md
?? .team/reviews/auto-root-6028fde.md
?? .team/reviews/auto-root-626e9d8_api-ventago-66ad6c9d.md
?? .team/reviews/auto-root-63a228b.md
?? .team/reviews/auto-root-63b6671_api-ventago-94fb796.md
?? .team/reviews/auto-root-63f30dc_ventago-app-97e20c4d.md
?? .team/reviews/auto-root-68a0f48.md
?? .team/reviews/auto-root-697b267.md
?? .team/reviews/auto-root-6bb77cb_api-ventago-66d3a16b.md
?? .team/reviews/auto-root-6bdfdcb_ventago-app-55ad5d7.md
?? .team/reviews/auto-root-6d486bb_ventago-app-2288179.md
?? .team/reviews/auto-root-6ed05de_api-ventago-eae27de3.md
?? .team/reviews/auto-root-6f3fafb_api-ventago-6ce906a_ventago-app-36cdff4.md
?? .team/reviews/auto-root-721fb49_api-ventago-fee04b3f_ventago-app-1443ce1.md
?? .team/reviews/auto-root-73f151f_api-ventago-4a73ab7.md
?? .team/reviews/auto-root-75ba1db_api-ventago-dbd8e417.md
?? .team/reviews/auto-root-7887027.md
?? .team/reviews/auto-root-7e534c9.md
?? .team/reviews/auto-root-7ffa413_api-ventago-b1a5caf_ventago-app-9591702.md
?? .team/reviews/auto-root-8138b91_api-ventago-f8f5c55.md
?? .team/reviews/auto-root-82b4d8c_ventago-app-86e66dd.md
?? .team/reviews/auto-root-83e89ab_ventago-app-3e7aae8.md
?? .team/reviews/auto-root-840bc21.md
?? .team/reviews/auto-root-8dba188_api-ventago-91779fd.md
?? .team/reviews/auto-root-8f898a8.md
?? .team/reviews/auto-root-90589fa_api-ventago-2039a599_ventago-app-d3c93bc.md
?? .team/reviews/auto-root-98313e8_api-ventago-04b7df2.md
?? .team/reviews/auto-root-9bfb6c0.md
?? .team/reviews/auto-root-9d9d384_api-ventago-36838e02.md
?? .team/reviews/auto-root-a111972.md
?? .team/reviews/auto-root-a518fa4_api-ventago-70301b2f.md
?? .team/reviews/auto-root-ab3d9b4_ventago-app-aa9bbb2.md
?? .team/reviews/auto-root-ac27be6_api-ventago-02627644.md
?? .team/reviews/auto-root-b0482ed.md
?? .team/reviews/auto-root-b0ffdc0_api-ventago-14b62419_ventago-app-2127d6e.md
?? .team/reviews/auto-root-b3a0fdf.md
?? .team/reviews/auto-root-b5dc3a9_api-ventago-b92e599d.md
?? .team/reviews/auto-root-b6d5267.md
?? .team/reviews/auto-root-b8232d5_api-ventago-45eff50b.md
?? .team/reviews/auto-root-babdf1f.md
?? .team/reviews/auto-root-bbf6d1f_api-ventago-cc15268.md
?? .team/reviews/auto-root-bcc975f.md
?? .team/reviews/auto-root-cbd2c33.md
?? .team/reviews/auto-root-cbecb15_api-ventago-f0c2510c.md
?? .team/reviews/auto-root-cd1aa02.md
?? .team/reviews/auto-root-cdb6d94_api-ventago-b0233b6.md
?? .team/reviews/auto-root-d002590.md
?? .team/reviews/auto-root-d176110_api-ventago-ca25e19.md
?? .team/reviews/auto-root-d178e3d.md
?? .team/reviews/auto-root-d386412_api-ventago-39c3ffb.md
?? .team/reviews/auto-root-d71925e_ventago-app-54e6247.md
?? .team/reviews/auto-root-d914335_api-ventago-2a0fe93f_ventago-app-f9a295b.md
?? .team/reviews/auto-root-de35c1c_api-ventago-c6eb194d_ventago-app-cf8c9e0.md
?? .team/reviews/auto-root-e3a69e0.md
?? .team/reviews/auto-root-e5db900_api-ventago-1fac5fac_ventago-app-231278b.md
?? .team/reviews/auto-root-e64bc67.md
?? .team/reviews/auto-root-e73dfed.md
?? .team/reviews/auto-root-eb3df1e.md
?? .team/reviews/auto-root-ebf072e.md
?? .team/reviews/auto-root-edbc743_api-ventago-2622468.md
?? .team/reviews/auto-root-f2c0b38_ventago-app-c354ba0.md
?? .team/reviews/auto-root-f6ba6ea_api-ventago-2522635.md
?? .team/reviews/auto-root-f952fbb_api-ventago-b9bcfa58.md
?? .team/reviews/auto-root-fbc477f_ventago-app-94085459.md
?? .team/reviews/auto-root-fcb5af0.md
?? .team/reviews/auto-root-fe36fb9_api-ventago-c5a709f.md
?? .team/reviews/auto-ventago-app-0f2ff49.md
?? .team/reviews/auto-ventago-app-3219faf.md
?? .team/reviews/auto-ventago-app-3cc1782.md
?? .team/reviews/auto-ventago-app-6a877d5.md
?? .team/reviews/auto-ventago-app-743d409f.md
?? .team/reviews/auto-ventago-app-88c7b7c.md
?? .team/reviews/auto-ventago-app-908bd19.md
?? .team/reviews/auto-ventago-app-b0da036.md
?? .team/reviews/auto-ventago-app-b80335b.md
?? .team/reviews/auto-ventago-app-dbcdf5af.md
?? .team/reviews/auto-ventago-app-df9dbbe.md
?? .team/reviews/auto-ventago-app-e2bf728.md
?? .team/reviews/auto-ventago-app-f7ccd1a9.md
?? .team/reviews/auto-ventago-app-fa9e8fc.md
?? .team/reviews/commit-32744e5c-codex.md
?? .team/reviews/manual-018-sucursal-unica.md
?? .team/reviews/manual-019-copiar-ingresados.md
?? .team/reviews/manual-020-copiar-historial.md
?? .team/reviews/manual-021-copiar-texto.md
?? .team/reviews/manual-022-reportes-diseno.md
?? .team/reviews/manual-023-numeros-reportes.md
?? .team/reviews/manual-024-stock-nuevo.md
?? .team/reviews/manual-025-pdf-madres.md
?? .team/reviews/manual-026-pdf-masonry.md
?? .team/reviews/manual-027-pdf-vertical.md
?? .team/reviews/manual-028-pedido17.md
?? .team/reviews/manual-029-ventas-totales.md
?? .team/reviews/manual-030-codigomadre-inicial.md
?? .team/reviews/manual-031-pedido14-fallados.md
?? .team/reviews/manual-032-pedido15-scrolltop.md
?? .team/reviews/manual-033-pedido16-whatsapp.md
?? .team/reviews/manual-034-pedido18-paso1.md
?? .team/reviews/manual-035-pedido18-paso2.md
?? .team/reviews/manual-036-pedido18-paso2-verif.md
?? .team/reviews/manual-037-pedido18-paso2-verif2.md
?? .team/reviews/manual-038-reportes-periodo-comun.md
?? .team/reviews/manual-039-ventas-totales-extras.md
?? .team/reviews/manual-040-sku-web-nombre-identico.md
?? .team/reviews/manual-041-zebra-test-doble-banda.md
?? .team/reviews/manual-044-superadmin-actualizacion.md
?? .team/reviews/manual-57-F1F5-282c86d6.md
?? .team/reviews/manual-57-F3b-F6-833aacf2.md
?? .team/reviews/manual-89-diseno.md
?? .team/reviews/manual-91-05-dp-front-r2.md
?? .team/reviews/manual-91-05-dp-front.md
?? .team/reviews/manual-96-11/
?? .team/reviews/manual-98-14-a.md
?? .team/reviews/manual-98-14-b.md
?? .team/reviews/manual-98-14-c.md
?? .team/reviews/manual-98-14-r2.md
?? .team/reviews/manual-agent-grant-design.md
?? .team/reviews/manual-agente-2bb81249.md
?? .team/reviews/manual-agente-dfcf5ec3.md
?? .team/reviews/manual-cheques-codex.md
?? .team/reviews/manual-comanda-e9cf727_c9a9850.md
?? .team/reviews/manual-contract-onboarding-bee7279.md
?? .team/reviews/manual-costo-api.md
?? .team/reviews/manual-costo-app.md
?? .team/reviews/manual-cuentas-fixed.md
?? .team/reviews/manual-legacy-variantes-ac3f3b0a.md
?? .team/reviews/manual-manuales-06b806d5.md
?? .team/reviews/manual-money-double-52b14e3.md
?? .team/reviews/manual-p2-caja-fuerte-c628bfb.md
?? .team/reviews/manual-padron-2bec577b.md
?? .team/reviews/manual-padron-ac40b533.md
?? .team/reviews/manual-padron-e0f60e24.md
?? .team/reviews/manual-padron-r4.md
?? .team/reviews/manual-pedidos-fd30cee4.md
?? .team/reviews/manual-phase93-codex.md
?? .team/reviews/manual-phase93-p1-codex.md
?? .team/reviews/manual-phase93-p4-migracion.md
?? .team/reviews/manual-phase93-p4.md
?? .team/reviews/manual-phase93-p4c.md
?? .team/reviews/manual-pos-footer-f340eaf.md
?? .team/reviews/manual-precio-codex.md
?? .team/reviews/manual-precio/
?? .team/reviews/manual-revivir-clientes.md
?? .team/reviews/manual-sucursal-sin-variantes.md
?? .team/reviews/phase86-partial-upload-codex-2026-08-25.md
?? .team/reviews/phase88-codex.md
?? .team/reviews/phase88-w1w2-codex-prompt.md
?? .team/reviews/phase88-w1w2-codex.md
?? "Claude outputs/"
?? legacy-query-mcp.zip
?? legacy-query-mcp/
?? loadtest/print/agent-keys.txt
?? loadtest/print/received-q.jsonl
?? "manuales/ACE III Online \354\213\234\354\212\244\355\205\234 \354\264\210\352\270\260 \354\205\213\354\227\205\355\225\230\352\270\260.docx"
?? "manuales/ACE III Online \354\213\234\354\212\244\355\205\234 \354\264\210\352\270\260 \354\205\213\354\227\205\355\225\230\352\270\260.pdf"
?? "manuales/ACE III Online \354\213\234\354\212\244\355\205\234 \354\264\210\352\270\260 \354\205\213\354\227\205\355\225\230\352\270\260_\353\252\251\354\260\250\352\260\261\354\213\240.docx"
?? "manuales/ACE III Online \354\213\234\354\212\244\355\205\234 \354\264\210\352\270\260 \354\205\213\354\227\205\355\225\230\352\270\260_\353\252\251\354\260\250\352\260\261\354\213\240.pdf"
?? "manuales/ACE III Online \354\213\234\354\212\244\355\205\234 \354\264\210\352\270\260 \354\205\213\354\227\205\355\225\230\352\270\260_\353\260\261\354\227\205.docx"
?? scripts/pg-lan-access.sh
?? scripts/server2-setup.sh
?? ventago-admin-app/android/app/src/main/kotlin/com/coolsistema/ventago_admin_app/Actualizacion.kt
?? ventago-admin-app/android/app/src/main/res/xml/
?? ventago-admin-app/lib/core/update/
?? ventago-admin-app/test/version_remota_test.dart
?? zebra-agent/mockups/qr-v1029-posiciones-mockup.html
?? zebra-agent/mockups/qr-v1029-posiciones-mockup.png
diff --git a/scripts/publicar-apk.sh b/scripts/publicar-apk.sh
index d368e0f..0d02d78 100755
--- a/scripts/publicar-apk.sh
+++ b/scripts/publicar-apk.sh
@@ -43,7 +43,9 @@ if [[ "$cert" != "$CERT_ESPERADO"* ]]; then
 fi
 
 feed="https://github.com/$REPO/releases/download/$TAG/version.json"
-feed_actual="$(curl -fsSL "$feed" 2>/dev/null || true)"
+# [2026-10-07] ★ con «?t=» : sin eso la CDN de GitHub devuelve el version.json anterior durante
+#   minutos — la comprobación final fallaba («dice versionCode=2, no 3») aunque estuviera publicado
+feed_actual="$(curl -fsSL "$feed?t=$(date +%s)" 2>/dev/null || true)"
 publicado="$(sed -nE 's/.*"versionCode": *([0-9]+).*/\1/p' <<<"$feed_actual")"
 # el mismo APK ya publicado (p.ej. se re-ejecuta build-apk.sh --skip-build para las copias) → nada que hacer
 if [[ -n "$publicado" && "$code" == "$publicado" ]] \
@@ -78,7 +80,7 @@ gh release upload "$TAG" "$tmp/version.json" -R "$REPO" --clobber
 # (recién subido GitHub puede tardar unos segundos en servirlo: 404 → reintentar)
 vuelta=""
 for _ in 1 2 3 4 5 6; do
-  vuelta="$(curl -fsSL "$feed" 2>/dev/null | sed -nE 's/.*"versionCode": *([0-9]+).*/\1/p' || true)"
+  vuelta="$(curl -fsSL "$feed?t=$(date +%s)" 2>/dev/null | sed -nE 's/.*"versionCode": *([0-9]+).*/\1/p' || true)"
   [[ "$vuelta" == "$code" ]] && break
   sleep 5
 done
diff --git a/ventago-admin-app/android/app/src/main/AndroidManifest.xml b/ventago-admin-app/android/app/src/main/AndroidManifest.xml
index 0659027..efbca7c 100644
--- a/ventago-admin-app/android/app/src/main/AndroidManifest.xml
+++ b/ventago-admin-app/android/app/src/main/AndroidManifest.xml
@@ -2,6 +2,8 @@
     <!-- release APK 네트워크 필수: 없으면 소켓 EPERM(errno=1) -->
     <uses-permission android:name="android.permission.INTERNET"/>
     <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
+    <!-- [2026-10-07] actualización dentro de la app: abrir el instalador con el APK descargado -->
+    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>
     <uses-permission android:name="android.permission.USE_BIOMETRIC"/>
     <application
         android:label="ventago_admin_app"
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
diff --git a/ventago-admin-app/android/app/src/main/kotlin/com/coolsistema/ventago_admin_app/MainActivity.kt b/ventago-admin-app/android/app/src/main/kotlin/com/coolsistema/ventago_admin_app/MainActivity.kt
index e1a9520..5cc4b1c 100644
--- a/ventago-admin-app/android/app/src/main/kotlin/com/coolsistema/ventago_admin_app/MainActivity.kt
+++ b/ventago-admin-app/android/app/src/main/kotlin/com/coolsistema/ventago_admin_app/MainActivity.kt
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
diff --git a/ventago-admin-app/build-apk.sh b/ventago-admin-app/build-apk.sh
index af15cc3..0f93ea6 100755
--- a/ventago-admin-app/build-apk.sh
+++ b/ventago-admin-app/build-apk.sh
@@ -4,6 +4,7 @@
 # 사용법:
 #   ./build-apk.sh                # 빌드 후 복사
 #   ./build-apk.sh --skip-build   # 기존 빌드 산출물만 복사
+#   NOTAS="..." ./build-apk.sh    # 앱의 「Nueva versión」 창에 보일 안내(선택)
 #
 # 복사 대상:
 #   1) Dropbox/ACE_3_uversion/app herramientas download  — 버전명
@@ -26,7 +27,26 @@ FIXED_DEST="/Users/marcoskim/Google Drive/내 드라이브/ventago-superadmin/ve
 
 cd "$APP_DIR"
 
+# [2026-10-07] (tienda-admin 과 동일) 앱 안 업데이트: 빌드할 때마다 build 번호를 올린다(같으면 휴대폰이 새 버전으로 안 본다).
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
   echo "▶ flutter build apk --release (superadmin)"
   flutter build apk --release
 fi
@@ -37,6 +57,12 @@ if [[ ! -f "$APK_SRC" ]]; then
   exit 1
 fi
 
+# [2026-10-07] 앱 안 업데이트용 게시 (GitHub Releases → 앱이 열릴 때 「Nueva versión」 을 묻는다)
+#   ★ 복사(Dropbox/Drive)보다 먼저 — 폴더가 안 붙어 있어도 게시는 된다
+#   업로드 키로 서명된 APK 만 게시한다 — 다른 키면 휴대폰이 설치를 거부한다.
+CERT_UPLOAD="23747e710c3c77d8e989626b98d26464baee869d70e44857b8a5b0dc4e3927c7"
+"$APP_DIR/../scripts/publicar-apk.sh" "$APK_SRC" "ventago-admin-app-latest" "ventago-admin-app.apk" "$CERT_UPLOAD" "${NOTAS:-}"
+
 stamp="$(date -r "$APK_SRC" '+%Y%m%d-%H%M')"
 apk_name="ventago_superadmin_android_${stamp}.apk"
 missing=0
diff --git a/ventago-admin-app/lib/main.dart b/ventago-admin-app/lib/main.dart
index fb58b0e..94c8371 100644
--- a/ventago-admin-app/lib/main.dart
+++ b/ventago-admin-app/lib/main.dart
@@ -2,6 +2,7 @@ import 'package:flutter/material.dart';
 import 'package:flutter_riverpod/flutter_riverpod.dart';
 import 'core/network/session_signal.dart';
 import 'core/theme/app_theme.dart';
+import 'core/update/actualizacion.dart';
 import 'features/auth/auth_controller.dart';
 import 'features/auth/login_screen.dart';
 import 'shared/app_shell.dart';
@@ -10,12 +11,34 @@ void main() {
   runApp(const ProviderScope(child: VentagoAdminApp()));
 }
 
-class VentagoAdminApp extends StatelessWidget {
+// [2026-10-07] 새 버전 안내 — build-apk.sh 가 이 주소에 version.json 을 올린다 (tienda-admin 과 같은 방식)
+const _feedActualizacion =
+    'https://github.com/jhkim1010/ventago-downloads/releases/download/ventago-admin-app-latest/version.json';
+
+// 앱 시작 시 업데이트 다이얼로그를 띄우기 위한 루트 navigator 키
+final rootNavigatorKey = GlobalKey<NavigatorState>();
+
+class VentagoAdminApp extends StatefulWidget {
   const VentagoAdminApp({super.key});
 
+  @override
+  State<VentagoAdminApp> createState() => _VentagoAdminAppState();
+}
+
+class _VentagoAdminAppState extends State<VentagoAdminApp> {
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
       title: 'Ventago Admin',
       debugShowCheckedModeBanner: false,
       scaffoldMessengerKey: rootScaffoldMessengerKey,
diff --git a/ventago-admin-app/pubspec.lock b/ventago-admin-app/pubspec.lock
index a4fc94f..c054c5c 100644
--- a/ventago-admin-app/pubspec.lock
+++ b/ventago-admin-app/pubspec.lock
@@ -82,7 +82,7 @@ packages:
     source: hosted
     version: "1.19.1"
   crypto:
-    dependency: transitive
+    dependency: "direct main"
     description:
       name: crypto
       sha256: c8ea0233063ba03258fbcf2ca4d6dadfefe14f02fab57702265467a19f27fadf
diff --git a/ventago-admin-app/pubspec.yaml b/ventago-admin-app/pubspec.yaml
index 6ab13e8..98d3327 100644
--- a/ventago-admin-app/pubspec.yaml
+++ b/ventago-admin-app/pubspec.yaml
@@ -39,6 +39,7 @@ dependencies:
   flutter_riverpod: ^2.5.1
   # HTTP (async/await + 인터셉터)
   dio: ^5.4.0
+  crypto: ^3.0.6
   # 토큰 보안 저장
   flutter_secure_storage: ^9.0.0
   # 숫자/날짜 포맷

FILES
tienda-admin-app/android/app/src/main/AndroidManifest.xml
tienda-admin-app/android/app/src/main/kotlin/com/coolsistema/ventago_admin_app/Actualizacion.kt
tienda-admin-app/android/app/src/main/kotlin/com/coolsistema/ventago_admin_app/MainActivity.kt
tienda-admin-app/android/app/src/main/res/drawable-hdpi/ic_launcher_foreground.png
tienda-admin-app/android/app/src/main/res/drawable-mdpi/ic_launcher_foreground.png
tienda-admin-app/android/app/src/main/res/drawable-v21/launch_background.xml
tienda-admin-app/android/app/src/main/res/drawable-xhdpi/ic_launcher_foreground.png
tienda-admin-app/android/app/src/main/res/drawable-xxhdpi/ic_launcher_foreground.png
tienda-admin-app/android/app/src/main/res/drawable-xxxhdpi/ic_launcher_foreground.png
tienda-admin-app/android/app/src/main/res/drawable/launch_background.xml
tienda-admin-app/android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml
tienda-admin-app/android/app/src/main/res/mipmap-hdpi/ic_launcher.png
tienda-admin-app/android/app/src/main/res/mipmap-mdpi/ic_launcher.png
tienda-admin-app/android/app/src/main/res/mipmap-xhdpi/ic_launcher.png
tienda-admin-app/android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png
tienda-admin-app/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png
tienda-admin-app/android/app/src/main/res/values-night/styles.xml
tienda-admin-app/android/app/src/main/res/values/colors.xml
tienda-admin-app/android/app/src/main/res/values/styles.xml
tienda-admin-app/android/app/src/main/res/xml/actualizacion_paths.xml
tienda-admin-app/lib/core/update/actualizacion.dart
tienda-admin-app/lib/core/update/version_remota.dart
ventago-admin-app/android/app/src/main/AndroidManifest.xml
ventago-admin-app/android/app/src/main/kotlin/com/coolsistema/ventago_admin_app/Actualizacion.kt
ventago-admin-app/android/app/src/main/kotlin/com/coolsistema/ventago_admin_app/MainActivity.kt
ventago-admin-app/android/app/src/main/res/drawable-hdpi/ic_launcher_foreground.png
ventago-admin-app/android/app/src/main/res/drawable-mdpi/ic_launcher_foreground.png
ventago-admin-app/android/app/src/main/res/drawable-v21/launch_background.xml
ventago-admin-app/android/app/src/main/res/drawable-xhdpi/ic_launcher_foreground.png
ventago-admin-app/android/app/src/main/res/drawable-xxhdpi/ic_launcher_foreground.png
ventago-admin-app/android/app/src/main/res/drawable-xxxhdpi/ic_launcher_foreground.png
ventago-admin-app/android/app/src/main/res/drawable/launch_background.xml
ventago-admin-app/android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml
ventago-admin-app/android/app/src/main/res/mipmap-hdpi/ic_launcher.png
ventago-admin-app/android/app/src/main/res/mipmap-mdpi/ic_launcher.png
ventago-admin-app/android/app/src/main/res/mipmap-xhdpi/ic_launcher.png
ventago-admin-app/android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png
ventago-admin-app/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png
ventago-admin-app/android/app/src/main/res/values-night/styles.xml
ventago-admin-app/android/app/src/main/res/values/colors.xml
ventago-admin-app/android/app/src/main/res/values/styles.xml
ventago-admin-app/android/app/src/main/res/xml/actualizacion_paths.xml
ventago-admin-app/lib/core/update/actualizacion.dart
ventago-admin-app/lib/core/update/version_remota.dart

DART
// [2026-10-06] Actualización dentro de la app (Android, APK fuera de Play).
// (mismo archivo en mobile-sales-app, tienda-admin-app y ventago-admin-app)
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
  CancelToken _cancel = CancelToken();
  bool _procesando = false;
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
    // un intento por vez: dos descargas sobre el mismo archivo se pisan (codex 014)
    if (_procesando) {
      return;
    }
    _procesando = true;
    _cancel = CancelToken();
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
      // ★ el archivo bajado tiene que ser exactamente el publicado (hash por partes: sin cargar
      //   el APK entero en memoria)
      final digest = await sha256.bind(File(ruta).openRead()).first;
      if (digest.toString() != widget.remota.sha256) {
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
    } finally {
      _procesando = false;
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
        if (error != null) FilledButton(onPressed: _procesando ? null : _bajarEInstalar, child: const Text('Reintentar')),
      ],
    );
  }
}

class _Falla implements Exception {
  final String mensaje;

  const _Falla(this.mensaje);
}
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

GRADLE/MANIFEST
sed: ventago-admin-app/android/app/build.gradle: No such file or directory
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- release APK 네트워크 필수: 없으면 소켓 EPERM(errno=1) -->
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
    <!-- [2026-10-06] actualización dentro de la app: abrir el instalador con el APK descargado -->
    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>
    <uses-permission android:name="android.permission.USE_BIOMETRIC"/>
    <application
        android:label="Admin de Tienda"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:taskAffinity=""
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <!-- Specifies an Android theme to apply to this Activity as soon as
                 the Android process has started. This theme is visible to the user
                 while the Flutter UI initializes. After that, this theme continues
                 to determine the Window background behind the Flutter UI. -->
            <meta-data
              android:name="io.flutter.embedding.android.NormalTheme"
              android:resource="@style/NormalTheme"
              />
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <provider
            android:name="androidx.core.content.FileProvider"
            android:authorities="${applicationId}.actualizacion"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/actualizacion_paths" />
        </provider>
        <!-- Don't delete the meta-data below.
             This is used by the Flutter tool to generate GeneratedPluginRegistrant.java -->
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
    <!-- Required to query activities that can process text, see:
         https://developer.android.com/training/package-visibility and
         https://developer.android.com/reference/android/content/Intent#ACTION_PROCESS_TEXT.

         In particular, this is used by the Flutter engine in io.flutter.plugin.text.ProcessTextPlugin. -->
    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
    </queries>
</manifest>

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
/bin/zsh -lc "printf '%s\\n' '--- build config ---'; rg -n \"namespace|applicationId|versionCode|versionName|minSdk|targetSdk\" ventago-admin-app/android/app ventago-admin-app/android -g '*.gradle*'; printf '%s\\n' '--- tracked/new status ---'; git status --short -- ventago-admin-app/lib/core/update ventago-admin-app/android/app/src/main/kotlin/com/coolsistema/ventago_admin_app/Actualizacion.kt ventago-admin-app/android/app/src/main/res/xml/actualizacion_paths.xml; git ls-files --stage -- ventago-admin-app/lib/core/update ventago-admin-app/android/app/src/main/kotlin/com/coolsistema/ventago_admin_app/Actualizacion.kt ventago-admin-app/android/app/src/main/res/xml/actualizacion_paths.xml; printf '%s\\n' '--- exact comparisons ---'; diff -u tienda-admin-app/lib/core/update/actualizacion.dart ventago-admin-app/lib/core/update/actualizacion.dart || true; diff -u tienda-admin-app/lib/core/update/version_remota.dart ventago-admin-app/lib/core/update/version_remota.dart || true; diff -u tienda-admin-app/android/app/src/main/kotlin/com/coolsistema/ventago_admin_app/Actualizacion.kt ventago-admin-app/android/app/src/main/kotlin/com/coolsistema/ventago_admin_app/Actualizacion.kt || true; printf '%s\\n' '--- relevant main files numbered ---'; nl -ba ventago-admin-app/android/app/build.gradle.kts | sed -n '1,180p'; nl -ba ventago-admin-app/android/app/src/main/AndroidManifest.xml | sed -n '1,130p'; nl -ba ventago-admin-app/android/app/src/main/kotlin/com/coolsistema/ventago_admin_app/Actualizacion.kt | sed -n '1,180p'; nl -ba ventago-admin-app/lib/main.dart | sed -n '1,130p'; nl -ba ventago-admin-app/build-apk.sh | sed -n '1,130p'; nl -ba scripts/publicar-apk.sh | sed -n '35,115p'" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 0ms:
--- build config ---
ventago-admin-app/android/app/build.gradle.kts:23:    namespace = "com.coolsistema.ventago_admin_app"
ventago-admin-app/android/app/build.gradle.kts:38:        applicationId = "com.coolsistema.ventago_admin_app"
ventago-admin-app/android/app/build.gradle.kts:41:        minSdk = flutter.minSdkVersion
ventago-admin-app/android/app/build.gradle.kts:42:        targetSdk = flutter.targetSdkVersion
ventago-admin-app/android/app/build.gradle.kts:43:        versionCode = flutter.versionCode
ventago-admin-app/android/app/build.gradle.kts:44:        versionName = flutter.versionName
ventago-admin-app/android/app/build.gradle.kts:23:    namespace = "com.coolsistema.ventago_admin_app"
ventago-admin-app/android/app/build.gradle.kts:38:        applicationId = "com.coolsistema.ventago_admin_app"
ventago-admin-app/android/app/build.gradle.kts:41:        minSdk = flutter.minSdkVersion
ventago-admin-app/android/app/build.gradle.kts:42:        targetSdk = flutter.targetSdkVersion
ventago-admin-app/android/app/build.gradle.kts:43:        versionCode = flutter.versionCode
ventago-admin-app/android/app/build.gradle.kts:44:        versionName = flutter.versionName
--- tracked/new status ---
?? ventago-admin-app/android/app/src/main/kotlin/com/coolsistema/ventago_admin_app/Actualizacion.kt
?? ventago-admin-app/android/app/src/main/res/xml/actualizacion_paths.xml
?? ventago-admin-app/lib/core/update/
--- exact comparisons ---
--- tienda-admin-app/lib/core/update/actualizacion.dart	2026-10-07 16:09:43
+++ ventago-admin-app/lib/core/update/actualizacion.dart	2026-10-07 16:09:31
@@ -1,5 +1,5 @@
 // [2026-10-06] Actualización dentro de la app (Android, APK fuera de Play).
-// (mismo archivo en mobile-sales-app y tienda-admin-app)
+// (mismo archivo en mobile-sales-app, tienda-admin-app y ventago-admin-app)
 //
 // Al abrir: lee version.json; si hay una versión más nueva pregunta «Actualizar / Más tarde».
 // «Actualizar» baja el APK, verifica el SHA-256 y abre el instalador de Android — la persona
--- tienda-admin-app/lib/core/update/version_remota.dart	2026-10-07 16:09:43
+++ ventago-admin-app/lib/core/update/version_remota.dart	2026-10-07 16:09:31
@@ -1,5 +1,5 @@
 // [2026-10-06] Actualización dentro de la app (Android, APK fuera de Play) — reglas puras.
-// (mismo archivo en mobile-sales-app y tienda-admin-app)
+// (mismo archivo en mobile-sales-app, tienda-admin-app y ventago-admin-app)
 //
 // El build (build-apk.sh) publica en GitHub Releases (jhkim1010/ventago-downloads):
 //   <app>-latest/version.json  →  {"versionCode": 9, "versionName": "1.1.0",
--- relevant main files numbered ---
     1	import java.io.FileInputStream
     2	import java.util.Properties
     3	
     4	plugins {
     5	    id("com.android.application")
     6	    id("kotlin-android")
     7	    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
     8	    id("dev.flutter.flutter-gradle-plugin")
     9	}
    10	
    11	// Play 업로드 키 — 저장소 밖(~/android-keys/key.properties). 없으면 release 는 debug 키로 서명되지만
    12	// AAB(bundle*) 는 Play 가 거부하므로 조용히 만들지 않고 실패시킨다.
    13	val uploadKeyProps = Properties().apply {
    14	    val f = file(System.getenv("ANDROID_KEY_PROPERTIES") ?: "${System.getProperty("user.home")}/android-keys/key.properties")
    15	    if (f.exists()) FileInputStream(f).use { load(it) }
    16	}
    17	val hasUploadKey = uploadKeyProps.getProperty("storeFile") != null
    18	if (!hasUploadKey && gradle.startParameter.taskNames.any { it.contains("bundle", ignoreCase = true) }) {
    19	    throw GradleException("AAB 빌드에는 업로드 키가 필요합니다: ~/android-keys/key.properties 가 없습니다.")
    20	}
    21	
    22	android {
    23	    namespace = "com.coolsistema.ventago_admin_app"
    24	    compileSdk = flutter.compileSdkVersion
    25	    ndkVersion = flutter.ndkVersion
    26	
    27	    compileOptions {
    28	        sourceCompatibility = JavaVersion.VERSION_17
    29	        targetCompatibility = JavaVersion.VERSION_17
    30	    }
    31	
    32	    kotlinOptions {
    33	        jvmTarget = JavaVersion.VERSION_17.toString()
    34	    }
    35	
    36	    defaultConfig {
    37	        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
    38	        applicationId = "com.coolsistema.ventago_admin_app"
    39	        // You can update the following values to match your application needs.
    40	        // For more information, see: https://flutter.dev/to/review-gradle-config.
    41	        minSdk = flutter.minSdkVersion
    42	        targetSdk = flutter.targetSdkVersion
    43	        versionCode = flutter.versionCode
    44	        versionName = flutter.versionName
    45	    }
    46	
    47	    signingConfigs {
    48	        if (hasUploadKey) {
    49	            create("upload") {
    50	                storeFile = file(uploadKeyProps.getProperty("storeFile"))
    51	                storePassword = uploadKeyProps.getProperty("storePassword")
    52	                keyAlias = uploadKeyProps.getProperty("keyAlias")
    53	                keyPassword = uploadKeyProps.getProperty("keyPassword")
    54	            }
    55	        }
    56	    }
    57	
    58	    buildTypes {
    59	        release {
    60	            signingConfig = if (hasUploadKey) signingConfigs.getByName("upload") else signingConfigs.getByName("debug")
    61	        }
    62	    }
    63	}
    64	
    65	flutter {
    66	    source = "../.."
    67	}
     1	<manifest xmlns:android="http://schemas.android.com/apk/res/android">
     2	    <!-- release APK 네트워크 필수: 없으면 소켓 EPERM(errno=1) -->
     3	    <uses-permission android:name="android.permission.INTERNET"/>
     4	    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
     5	    <!-- [2026-10-07] actualización dentro de la app: abrir el instalador con el APK descargado -->
     6	    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>
     7	    <uses-permission android:name="android.permission.USE_BIOMETRIC"/>
     8	    <application
     9	        android:label="ventago_admin_app"
    10	        android:name="${applicationName}"
    11	        android:icon="@mipmap/ic_launcher">
    12	        <activity
    13	            android:name=".MainActivity"
    14	            android:exported="true"
    15	            android:launchMode="singleTop"
    16	            android:taskAffinity=""
    17	            android:theme="@style/LaunchTheme"
    18	            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
    19	            android:hardwareAccelerated="true"
    20	            android:windowSoftInputMode="adjustResize">
    21	            <!-- Specifies an Android theme to apply to this Activity as soon as
    22	                 the Android process has started. This theme is visible to the user
    23	                 while the Flutter UI initializes. After that, this theme continues
    24	                 to determine the Window background behind the Flutter UI. -->
    25	            <meta-data
    26	              android:name="io.flutter.embedding.android.NormalTheme"
    27	              android:resource="@style/NormalTheme"
    28	              />
    29	            <intent-filter>
    30	                <action android:name="android.intent.action.MAIN"/>
    31	                <category android:name="android.intent.category.LAUNCHER"/>
    32	            </intent-filter>
    33	        </activity>
    34	        <provider
    35	            android:name="androidx.core.content.FileProvider"
    36	            android:authorities="${applicationId}.actualizacion"
    37	            android:exported="false"
    38	            android:grantUriPermissions="true">
    39	            <meta-data
    40	                android:name="android.support.FILE_PROVIDER_PATHS"
    41	                android:resource="@xml/actualizacion_paths" />
    42	        </provider>
    43	        <!-- Don't delete the meta-data below.
    44	             This is used by the Flutter tool to generate GeneratedPluginRegistrant.java -->
    45	        <meta-data
    46	            android:name="flutterEmbedding"
    47	            android:value="2" />
    48	    </application>
    49	    <!-- Required to query activities that can process text, see:
    50	         https://developer.android.com/training/package-visibility and
    51	         https://developer.android.com/reference/android/content/Intent#ACTION_PROCESS_TEXT.
    52	
    53	         In particular, this is used by the Flutter engine in io.flutter.plugin.text.ProcessTextPlugin. -->
    54	    <queries>
    55	        <intent>
    56	            <action android:name="android.intent.action.PROCESS_TEXT"/>
    57	            <data android:mimeType="text/plain"/>
    58	        </intent>
    59	    </queries>
    60	</manifest>
     1	package com.coolsistema.ventago_admin_app
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
     1	import 'package:flutter/material.dart';
     2	import 'package:flutter_riverpod/flutter_riverpod.dart';
     3	import 'core/network/session_signal.dart';
     4	import 'core/theme/app_theme.dart';
     5	import 'core/update/actualizacion.dart';
     6	import 'features/auth/auth_controller.dart';
     7	import 'features/auth/login_screen.dart';
     8	import 'shared/app_shell.dart';
     9	
    10	void main() {
    11	  runApp(const ProviderScope(child: VentagoAdminApp()));
    12	}
    13	
    14	// [2026-10-07] 새 버전 안내 — build-apk.sh 가 이 주소에 version.json 을 올린다 (tienda-admin 과 같은 방식)
    15	const _feedActualizacion =
    16	    'https://github.com/jhkim1010/ventago-downloads/releases/download/ventago-admin-app-latest/version.json';
    17	
    18	// 앱 시작 시 업데이트 다이얼로그를 띄우기 위한 루트 navigator 키
    19	final rootNavigatorKey = GlobalKey<NavigatorState>();
    20	
    21	class VentagoAdminApp extends StatefulWidget {
    22	  const VentagoAdminApp({super.key});
    23	
    24	  @override
    25	  State<VentagoAdminApp> createState() => _VentagoAdminAppState();
    26	}
    27	
    28	class _VentagoAdminAppState extends State<VentagoAdminApp> {
    29	  @override
    30	  void initState() {
    31	    super.initState();
    32	    // 첫 화면이 뜬 뒤 1회 — 새 버전이 있으면 묻는다(절대 혼자 설치하지 않음)
    33	    WidgetsBinding.instance.addPostFrameCallback(
    34	      (_) => chequearActualizacion(rootNavigatorKey, feedUrl: _feedActualizacion),
    35	    );
    36	  }
    37	
    38	  @override
    39	  Widget build(BuildContext context) {
    40	    return MaterialApp(
    41	      navigatorKey: rootNavigatorKey,
    42	      title: 'Ventago Admin',
    43	      debugShowCheckedModeBanner: false,
    44	      scaffoldMessengerKey: rootScaffoldMessengerKey,
    45	      theme: buildAppTheme(),
    46	      home: const _AuthGate(),
    47	    );
    48	  }
    49	}
    50	
    51	// 앱 시작 시 저장 토큰으로 세션 복원 → 로그인/셸 분기.
    52	class _AuthGate extends ConsumerStatefulWidget {
    53	  const _AuthGate();
    54	
    55	  @override
    56	  ConsumerState<_AuthGate> createState() => _AuthGateState();
    57	}
    58	
    59	class _AuthGateState extends ConsumerState<_AuthGate> {
    60	  bool _booting = true;
    61	
    62	  @override
    63	  void initState() {
    64	    super.initState();
    65	    _boot();
    66	  }
    67	
    68	  Future<void> _boot() async {
    69	    await ref.read(authControllerProvider.notifier).bootstrap();
    70	    if (mounted) setState(() => _booting = false);
    71	  }
    72	
    73	  @override
    74	  Widget build(BuildContext context) {
    75	    if (_booting) {
    76	      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    77	    }
    78	    final loggedIn = ref.watch(authControllerProvider).isLoggedIn;
    79	
    80	    return loggedIn ? const AppShell() : const LoginScreen();
    81	  }
    82	}
     1	#!/usr/bin/env bash
     2	# superadmin 앱(ventago-admin-app, Android) 릴리즈 빌드 + 배포 폴더 자동 복사.
     3	#
     4	# 사용법:
     5	#   ./build-apk.sh                # 빌드 후 복사
     6	#   ./build-apk.sh --skip-build   # 기존 빌드 산출물만 복사
     7	#   NOTAS="..." ./build-apk.sh    # 앱의 「Nueva versión」 창에 보일 안내(선택)
     8	#
     9	# 복사 대상:
    10	#   1) Dropbox/ACE_3_uversion/app herramientas download  — 버전명
    11	#   2) Dropbox/Personal de m. Marcos                     — 버전명 (설치 파일 개인 보관)
    12	#   3) Google Drive/내 드라이브/ventago-superadmin/ventago-superadmin.apk — 고정명(배포 링크)
    13	#
    14	# 파일명 규칙: ventago_superadmin_android_<YYYYMMDD-HHMM>.apk (APK 컴파일 시각 기준)
    15	
    16	set -euo pipefail
    17	
    18	APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    19	APK_SRC="$APP_DIR/build/app/outputs/flutter-apk/app-release.apk"
    20	
    21	DEST_DIRS=(
    22	  "/Users/marcoskim/Dropbox/ACE_3_uversion/app herramientas download"
    23	  "/Users/marcoskim/Dropbox/Personal de m. Marcos"
    24	)
    25	
    26	FIXED_DEST="/Users/marcoskim/Google Drive/내 드라이브/ventago-superadmin/ventago-superadmin.apk"
    27	
    28	cd "$APP_DIR"
    29	
    30	# [2026-10-07] (tienda-admin 과 동일) 앱 안 업데이트: 빌드할 때마다 build 번호를 올린다(같으면 휴대폰이 새 버전으로 안 본다).
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
    50	  echo "▶ flutter build apk --release (superadmin)"
    51	  flutter build apk --release
    52	fi
    53	
    54	if [[ ! -f "$APK_SRC" ]]; then
    55	  echo "ERROR: APK 산출물 없음: $APK_SRC" >&2
    56	  echo "       --skip-build 없이 다시 실행하세요." >&2
    57	  exit 1
    58	fi
    59	
    60	# [2026-10-07] 앱 안 업데이트용 게시 (GitHub Releases → 앱이 열릴 때 「Nueva versión」 을 묻는다)
    61	#   ★ 복사(Dropbox/Drive)보다 먼저 — 폴더가 안 붙어 있어도 게시는 된다
    62	#   업로드 키로 서명된 APK 만 게시한다 — 다른 키면 휴대폰이 설치를 거부한다.
    63	CERT_UPLOAD="23747e710c3c77d8e989626b98d26464baee869d70e44857b8a5b0dc4e3927c7"
    64	"$APP_DIR/../scripts/publicar-apk.sh" "$APK_SRC" "ventago-admin-app-latest" "ventago-admin-app.apk" "$CERT_UPLOAD" "${NOTAS:-}"
    65	
    66	stamp="$(date -r "$APK_SRC" '+%Y%m%d-%H%M')"
    67	apk_name="ventago_superadmin_android_${stamp}.apk"
    68	missing=0
    69	
    70	for dir in "${DEST_DIRS[@]}"; do
    71	  if [[ ! -d "$dir" ]]; then
    72	    echo "WARN: 폴더 없음, 건너뜀: $dir" >&2
    73	    missing=1
    74	    continue
    75	  fi
    76	
    77	  cp "$APK_SRC" "$dir/$apk_name"
    78	  echo "✔ 복사: $dir/$apk_name"
    79	done
    80	
    81	if [[ -d "$(dirname "$FIXED_DEST")" ]]; then
    82	  cp "$APK_SRC" "$FIXED_DEST"
    83	  echo "✔ 복사: $FIXED_DEST"
    84	else
    85	  echo "WARN: 폴더 없음, 건너뜀: $(dirname "$FIXED_DEST")" >&2
    86	  missing=1
    87	fi
    88	
    89	if [[ "$missing" -eq 1 ]]; then
    90	  echo "ERROR: 일부 대상에 복사하지 못했습니다 (위 WARN 확인)" >&2
    91	  exit 1
    92	fi
    93	
    94	echo "✔ 전체 복사 완료 ($apk_name)"
    35	name="$(sed -E "s/.*versionName='([^']*)'.*/\1/" <<<"$badging")"
    36	[[ "$code" =~ ^[0-9]+$ ]] || { echo "ERROR: no pude leer versionCode del APK" >&2; exit 1; }
    37	
    38	cert="$("$BT/apksigner" verify --print-certs "$APK" | awk '/certificate SHA-256 digest/ && !f {print $NF; f=1}')"
    39	if [[ "$cert" != "$CERT_ESPERADO"* ]]; then
    40	  echo "ERROR: el APK está firmado con ${cert:0:16}…, se esperaba ${CERT_ESPERADO:0:16}…" >&2
    41	  echo "       Los teléfonos no podrían instalar esta actualización. No se publica." >&2
    42	  exit 1
    43	fi
    44	
    45	feed="https://github.com/$REPO/releases/download/$TAG/version.json"
    46	# [2026-10-07] ★ con «?t=» : sin eso la CDN de GitHub devuelve el version.json anterior durante
    47	#   minutos — la comprobación final fallaba («dice versionCode=2, no 3») aunque estuviera publicado
    48	feed_actual="$(curl -fsSL "$feed?t=$(date +%s)" 2>/dev/null || true)"
    49	publicado="$(sed -nE 's/.*"versionCode": *([0-9]+).*/\1/p' <<<"$feed_actual")"
    50	# el mismo APK ya publicado (p.ej. se re-ejecuta build-apk.sh --skip-build para las copias) → nada que hacer
    51	if [[ -n "$publicado" && "$code" == "$publicado" ]] \
    52	   && grep -q "\"sha256\": *\"$(shasum -a 256 "$APK" | awk '{print $1}')\"" <<<"$feed_actual"; then
    53	  echo "✔ v$name (versionCode $code) ya estaba publicado — sin cambios"
    54	  exit 0
    55	fi
    56	if [[ -n "$publicado" && "$code" -le "$publicado" ]]; then
    57	  echo "ERROR: versionCode $code no es mayor que el publicado ($publicado). Subí la versión en pubspec.yaml." >&2
    58	  exit 1
    59	fi
    60	
    61	sha="$(shasum -a 256 "$APK" | awk '{print $1}')"
    62	ASSET="${ASSET%.apk}-$code.apk"
    63	url="https://github.com/$REPO/releases/download/$TAG/$ASSET"
    64	
    65	tmp="$(mktemp -d)"
    66	cp "$APK" "$tmp/$ASSET"
    67	python3 - "$tmp/version.json" "$code" "$name" "$url" "$sha" "$NOTAS" <<'EOF'
    68	import json, sys
    69	p, code, name, url, sha, notas = sys.argv[1:]
    70	json.dump({"versionCode": int(code), "versionName": name, "apk": url, "sha256": sha, "notas": notas},
    71	          open(p, "w"), ensure_ascii=False, indent=2)
    72	EOF
    73	
    74	gh release view "$TAG" -R "$REPO" >/dev/null 2>&1 \
    75	  || gh release create "$TAG" -R "$REPO" --title "$TAG" --notes "Actualización dentro de la app (version.json + APK)"
    76	gh release upload "$TAG" "$tmp/$ASSET" -R "$REPO" --clobber
    77	gh release upload "$TAG" "$tmp/version.json" -R "$REPO" --clobber
    78	
    79	# comprobar lo que realmente quedó publicado
    80	# (recién subido GitHub puede tardar unos segundos en servirlo: 404 → reintentar)
    81	vuelta=""
    82	for _ in 1 2 3 4 5 6; do
    83	  vuelta="$(curl -fsSL "$feed?t=$(date +%s)" 2>/dev/null | sed -nE 's/.*"versionCode": *([0-9]+).*/\1/p' || true)"
    84	  [[ "$vuelta" == "$code" ]] && break
    85	  sleep 5
    86	done
    87	[[ "$vuelta" == "$code" ]] || { echo "ERROR: el feed publicado dice versionCode=$vuelta, no $code" >&2; exit 1; }
    88	echo "✔ Publicado v$name (versionCode $code) → $feed"

hook: PostToolUse
hook: PostToolUse
hook: PostToolUse Failed
hook: PostToolUse Completed
codex
현재 연결 관계는 일치합니다. `applicationId`, Kotlin 패키지, Manifest의 `${applicationId}.actualizacion`, 런타임 authority가 모두 `com.coolsistema.ventago_admin_app.actualizacion`으로 수렴하고, MethodChannel 이름도 Dart/Kotlin 양쪽이 같습니다. 이제 실제 빌드·정적 분석과 GitHub asset URL의 쿼리 문자열 동작을 확인하겠습니다.
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse Failed
hook: PreToolUse Completed
hook: PreToolUse Completed
hook: PostToolUse
hook: PostToolUse
hook: PostToolUse Failed
hook: PostToolUse Completed
hook: PreToolUse
hook: PreToolUse Completed
web search: 
web search: https://github.com/jhkim1010/ventago-downloads/releases/download/ventago-admin-app-latest/version.json?t=1791390000
hook: PostToolUse
hook: PostToolUse Completed
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse Failed
hook: PreToolUse Completed
hook: PreToolUse Completed
exec
/bin/zsh -lc "curl -sSIL --max-time 10 'https://github.com/jhkim1010/ventago-downloads/releases/download/ventago-admin-app-latest/version.json?t=1791390000' | sed -n '1,40p'" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 0ms:
curl: (6) Could not resolve host: github.com

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
/bin/zsh -lc "sed -n '1,260p' .team/reviews/014-codex.md 2>/dev/null || true; rg -n \"publicar-apk|actualizacion|version.json|anti.cach|FileProvider|build-apk\" .team/reviews -g '*.md' | head -120; printf '%s\\n' '--- pubspec versions and scripts ---'; rg -n '"'^version:'"' ventago-admin-app/pubspec.yaml tienda-admin-app/pubspec.yaml mobile-sales-app/pubspec.yaml 2>/dev/null; diff -u tienda-admin-app/build-apk.sh ventago-admin-app/build-apk.sh || true; printf '%s\\n' '--- ignored? ---'; git check-ignore -v ventago-admin-app/lib/core/update/actualizacion.dart ventago-admin-app/android/app/src/main/kotlin/com/coolsistema/ventago_admin_app/Actualizacion.kt || true; printf '%s\\n' '--- manifest merger existing outputs ---'; rg -n \"actualizacion|REQUEST_INSTALL_PACKAGES|FileProvider\" ventago-admin-app/build -g 'AndroidManifest.xml' -g '*.xml' 2>/dev/null | head -80" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 0ms:
.team/reviews/manual-pos-atajos-codex.md:58:  Deberían ser actualizaciones funcionales:
.team/reviews/manual-044-superadmin-actualizacion.md:15:Revisá este diff: se copia a ventago-admin-app (app Flutter superadmin, Android, APK fuera de Play) la actualización dentro de la app que ya funciona en tienda-admin-app (lib/core/update/actualizacion.dart y version_remota.dart copiados sin cambios: leen version.json, preguntan, bajan el APK, verifican sha256 y abren el instalador por FileProvider). Se agrega al build-apk.sh el aumento de build number y la publicación (scripts/publicar-apk.sh) en el tag ventago-admin-app-latest, y a publicar-apk.sh un ?t= anti-caché en las lecturas del feed. Buscá errores concretos (manifest, FileProvider authority, MethodChannel, navigatorKey, orden en build-apk.sh con set -e, tag/asset, anti-caché que rompa algo). No estilo.
.team/reviews/manual-044-superadmin-actualizacion.md:16:diff --git a/scripts/publicar-apk.sh b/scripts/publicar-apk.sh
.team/reviews/manual-044-superadmin-actualizacion.md:18:--- a/scripts/publicar-apk.sh
.team/reviews/manual-044-superadmin-actualizacion.md:19:+++ b/scripts/publicar-apk.sh
.team/reviews/manual-044-superadmin-actualizacion.md:23: feed="https://github.com/$REPO/releases/download/$TAG/version.json"
.team/reviews/manual-044-superadmin-actualizacion.md:25:+# [2026-10-07] ★ con «?t=» : sin eso la CDN de GitHub devuelve el version.json anterior durante
.team/reviews/manual-044-superadmin-actualizacion.md:29: # el mismo APK ya publicado (p.ej. se re-ejecuta build-apk.sh --skip-build para las copias) → nada que hacer
.team/reviews/manual-044-superadmin-actualizacion.md:31:@@ -78,7 +80,7 @@ gh release upload "$TAG" "$tmp/version.json" -R "$REPO" --clobber
.team/reviews/manual-044-superadmin-actualizacion.md:58:+            android:name="androidx.core.content.FileProvider"
.team/reviews/manual-044-superadmin-actualizacion.md:59:+            android:authorities="${applicationId}.actualizacion"
.team/reviews/manual-044-superadmin-actualizacion.md:64:+                android:resource="@xml/actualizacion_paths" />
.team/reviews/manual-044-superadmin-actualizacion.md:88:diff --git a/ventago-admin-app/build-apk.sh b/ventago-admin-app/build-apk.sh
.team/reviews/manual-044-superadmin-actualizacion.md:90:--- a/ventago-admin-app/build-apk.sh
.team/reviews/manual-044-superadmin-actualizacion.md:91:+++ b/ventago-admin-app/build-apk.sh
.team/reviews/manual-044-superadmin-actualizacion.md:94: #   ./build-apk.sh                # 빌드 후 복사
.team/reviews/manual-044-superadmin-actualizacion.md:95: #   ./build-apk.sh --skip-build   # 기존 빌드 산출물만 복사
.team/reviews/manual-044-superadmin-actualizacion.md:96:+#   NOTAS="..." ./build-apk.sh    # 앱의 「Nueva versión」 창에 보일 안내(선택)
.team/reviews/manual-044-superadmin-actualizacion.md:105:+#   publicar-apk.sh 가 「게시된 것보다 큰가」를 다시 확인한다.
.team/reviews/manual-044-superadmin-actualizacion.md:135:+"$APP_DIR/../scripts/publicar-apk.sh" "$APK_SRC" "ventago-admin-app-latest" "ventago-admin-app.apk" "$CERT_UPLOAD" "${NOTAS:-}"
.team/reviews/manual-044-superadmin-actualizacion.md:148:+import 'core/update/actualizacion.dart';
.team/reviews/manual-044-superadmin-actualizacion.md:157:+// [2026-10-07] 새 버전 안내 — build-apk.sh 가 이 주소에 version.json 을 올린다 (tienda-admin 과 같은 방식)
.team/reviews/manual-044-superadmin-actualizacion.md:159:+    'https://github.com/jhkim1010/ventago-downloads/releases/download/ventago-admin-app-latest/version.json';
.team/reviews/manual-044-superadmin-actualizacion.md:208:import androidx.core.content.FileProvider
.team/reviews/manual-044-superadmin-actualizacion.md:213:// [2026-10-06] Actualización dentro de la app (lib/core/update/actualizacion.dart).
.team/reviews/manual-044-superadmin-actualizacion.md:214:// Canal «ventago/actualizacion»:
.team/reviews/manual-044-superadmin-actualizacion.md:216://   dirDescarga → carpeta en caché para el APK (expuesta por FileProvider: res/xml/actualizacion_paths.xml)
.team/reviews/manual-044-superadmin-actualizacion.md:221:        MethodChannel(engine.dartExecutor.binaryMessenger, "ventago/actualizacion").setMethodCallHandler { call, result ->
.team/reviews/manual-044-superadmin-actualizacion.md:230:                        val dir = File(context.cacheDir, "actualizacion")
.team/reviews/manual-044-superadmin-actualizacion.md:242:                            val uri = FileProvider.getUriForFile(context, context.packageName + ".actualizacion", archivo)
.team/reviews/manual-044-superadmin-actualizacion.md:253:                result.error("actualizacion", e.message, null)
.team/reviews/manual-044-superadmin-actualizacion.md:258:=== NEW res/xml/actualizacion_paths.xml
.team/reviews/manual-044-superadmin-actualizacion.md:262:    <cache-path name="actualizacion" path="actualizacion/" />
.team/reviews/manual-044-superadmin-actualizacion.md:283:/bin/zsh -lc "sed -n '1,220p' .team/REVIEW-PROTOCOL.md && sed -n '1,240p' CLAUDE.md && sed -n '1,220p' scripts/publicar-apk.sh && sed -n '1,180p' ventago-admin-app/build-apk.sh" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
.team/reviews/manual-044-superadmin-actualizacion.md:615:# Uso (lo llaman mobile-sales-app/build-apk.sh y tienda-admin-app/build-apk.sh):
.team/reviews/manual-044-superadmin-actualizacion.md:616:#   scripts/publicar-apk.sh <apk> <tag-release> <nombre-asset.apk> <cert-sha256-esperado> ["notas"]
.team/reviews/manual-044-superadmin-actualizacion.md:619:#   <tag>/<nombre-asset>-<versionCode>.apk   y después   <tag>/version.json
.team/reviews/manual-044-superadmin-actualizacion.md:620:# El orden importa: version.json nunca apunta a un APK que todavía no está. Y el APK lleva el
.team/reviews/manual-044-superadmin-actualizacion.md:656:feed="https://github.com/$REPO/releases/download/$TAG/version.json"
.team/reviews/manual-044-superadmin-actualizacion.md:657:# [2026-10-07] ★ con «?t=» : sin eso la CDN de GitHub devuelve el version.json anterior durante
.team/reviews/manual-044-superadmin-actualizacion.md:661:# el mismo APK ya publicado (p.ej. se re-ejecuta build-apk.sh --skip-build para las copias) → nada que hacer
.team/reviews/manual-044-superadmin-actualizacion.md:678:python3 - "$tmp/version.json" "$code" "$name" "$url" "$sha" "$NOTAS" <<'EOF'
.team/reviews/manual-044-superadmin-actualizacion.md:686:  || gh release create "$TAG" -R "$REPO" --title "$TAG" --notes "Actualización dentro de la app (version.json + APK)"
.team/reviews/manual-044-superadmin-actualizacion.md:688:gh release upload "$TAG" "$tmp/version.json" -R "$REPO" --clobber
.team/reviews/manual-044-superadmin-actualizacion.md:704:#   ./build-apk.sh                # 빌드 후 복사
.team/reviews/manual-044-superadmin-actualizacion.md:705:#   ./build-apk.sh --skip-build   # 기존 빌드 산출물만 복사
.team/reviews/manual-044-superadmin-actualizacion.md:706:#   NOTAS="..." ./build-apk.sh    # 앱의 「Nueva versión」 창에 보일 안내(선택)
.team/reviews/manual-044-superadmin-actualizacion.md:730:#   publicar-apk.sh 가 「게시된 것보다 큰가」를 다시 확인한다.
.team/reviews/manual-044-superadmin-actualizacion.md:763:"$APP_DIR/../scripts/publicar-apk.sh" "$APK_SRC" "ventago-admin-app-latest" "ventago-admin-app.apk" "$CERT_UPLOAD" "${NOTAS:-}"
.team/reviews/manual-044-superadmin-actualizacion.md:806:/bin/zsh -lc "git status --short && git diff -- ventago-admin-app scripts/publicar-apk.sh && printf '\\nFILES\\n' && rg --files ventago-admin-app/lib/core/update ventago-admin-app/android/app/src/main tienda-admin-app/lib/core/update tienda-admin-app/android/app/src/main | sort && printf '\\nDART\\n' && sed -n '1,280p' ventago-admin-app/lib/core/update/actualizacion.dart && sed -n '1,220p' ventago-admin-app/lib/core/update/version_remota.dart && printf '\\nGRADLE/MANIFEST\\n' && sed -n '1,220p' ventago-admin-app/android/app/build.gradle && sed -n '1,180p' ventago-admin-app/android/app/src/main/AndroidManifest.xml && printf '\\nTIENDA ANALOG\\n' && sed -n '1,220p' tienda-admin-app/android/app/src/main/kotlin/*/*/*/Actualizacion.kt 2>/dev/null || true && sed -n '1,160p' tienda-admin-app/android/app/src/main/AndroidManifest.xml" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
.team/reviews/manual-044-superadmin-actualizacion.md:813: M scripts/publicar-apk.sh
.team/reviews/manual-044-superadmin-actualizacion.md:818: M ventago-admin-app/build-apk.sh
.team/reviews/manual-044-superadmin-actualizacion.md:1183:?? .team/reviews/manual-044-superadmin-actualizacion.md
.team/reviews/manual-044-superadmin-actualizacion.md:1244:diff --git a/scripts/publicar-apk.sh b/scripts/publicar-apk.sh
.team/reviews/manual-044-superadmin-actualizacion.md:1246:--- a/scripts/publicar-apk.sh
.team/reviews/manual-044-superadmin-actualizacion.md:1247:+++ b/scripts/publicar-apk.sh
.team/reviews/manual-044-superadmin-actualizacion.md:1251: feed="https://github.com/$REPO/releases/download/$TAG/version.json"
.team/reviews/manual-044-superadmin-actualizacion.md:1253:+# [2026-10-07] ★ con «?t=» : sin eso la CDN de GitHub devuelve el version.json anterior durante
.team/reviews/manual-044-superadmin-actualizacion.md:1257: # el mismo APK ya publicado (p.ej. se re-ejecuta build-apk.sh --skip-build para las copias) → nada que hacer
.team/reviews/manual-044-superadmin-actualizacion.md:1259:@@ -78,7 +80,7 @@ gh release upload "$TAG" "$tmp/version.json" -R "$REPO" --clobber
.team/reviews/manual-044-superadmin-actualizacion.md:1286:+            android:name="androidx.core.content.FileProvider"
.team/reviews/manual-044-superadmin-actualizacion.md:1287:+            android:authorities="${applicationId}.actualizacion"
.team/reviews/manual-044-superadmin-actualizacion.md:1292:+                android:resource="@xml/actualizacion_paths" />
.team/reviews/manual-044-superadmin-actualizacion.md:1316:diff --git a/ventago-admin-app/build-apk.sh b/ventago-admin-app/build-apk.sh
.team/reviews/manual-044-superadmin-actualizacion.md:1318:--- a/ventago-admin-app/build-apk.sh
.team/reviews/manual-044-superadmin-actualizacion.md:1319:+++ b/ventago-admin-app/build-apk.sh
.team/reviews/manual-044-superadmin-actualizacion.md:1322: #   ./build-apk.sh                # 빌드 후 복사
.team/reviews/manual-044-superadmin-actualizacion.md:1323: #   ./build-apk.sh --skip-build   # 기존 빌드 산출물만 복사
.team/reviews/manual-044-superadmin-actualizacion.md:1324:+#   NOTAS="..." ./build-apk.sh    # 앱의 「Nueva versión」 창에 보일 안내(선택)
.team/reviews/manual-044-superadmin-actualizacion.md:1333:+#   publicar-apk.sh 가 「게시된 것보다 큰가」를 다시 확인한다.
.team/reviews/manual-044-superadmin-actualizacion.md:1363:+"$APP_DIR/../scripts/publicar-apk.sh" "$APK_SRC" "ventago-admin-app-latest" "ventago-admin-app.apk" "$CERT_UPLOAD" "${NOTAS:-}"
.team/reviews/manual-044-superadmin-actualizacion.md:1376:+import 'core/update/actualizacion.dart';
.team/reviews/manual-044-superadmin-actualizacion.md:1385:+// [2026-10-07] 새 버전 안내 — build-apk.sh 가 이 주소에 version.json 을 올린다 (tienda-admin 과 같은 방식)
.team/reviews/manual-044-superadmin-actualizacion.md:1387:+    'https://github.com/jhkim1010/ventago-downloads/releases/download/ventago-admin-app-latest/version.json';
.team/reviews/manual-044-superadmin-actualizacion.md:1462:tienda-admin-app/android/app/src/main/res/xml/actualizacion_paths.xml
.team/reviews/manual-044-superadmin-actualizacion.md:1463:tienda-admin-app/lib/core/update/actualizacion.dart
.team/reviews/manual-044-superadmin-actualizacion.md:1484:ventago-admin-app/android/app/src/main/res/xml/actualizacion_paths.xml
.team/reviews/manual-044-superadmin-actualizacion.md:1485:ventago-admin-app/lib/core/update/actualizacion.dart
.team/reviews/manual-044-superadmin-actualizacion.md:1492:// Al abrir: lee version.json; si hay una versión más nueva pregunta «Actualizar / Más tarde».
.team/reviews/manual-044-superadmin-actualizacion.md:1505:const _canal = MethodChannel('ventago/actualizacion');
.team/reviews/manual-044-superadmin-actualizacion.md:1610:      final ruta = '$dir/actualizacion.apk';
.team/reviews/manual-044-superadmin-actualizacion.md:1686:// El build (build-apk.sh) publica en GitHub Releases (jhkim1010/ventago-downloads):
.team/reviews/manual-044-superadmin-actualizacion.md:1687://   <app>-latest/version.json  →  {"versionCode": 9, "versionName": "1.1.0",
.team/reviews/manual-044-superadmin-actualizacion.md:1779:            android:name="androidx.core.content.FileProvider"
.team/reviews/manual-044-superadmin-actualizacion.md:1780:            android:authorities="${applicationId}.actualizacion"
.team/reviews/manual-044-superadmin-actualizacion.md:1785:                android:resource="@xml/actualizacion_paths" />
.team/reviews/manual-044-superadmin-actualizacion.md:1817:/bin/zsh -lc "printf '%s\\n' '--- build config ---'; rg -n \"namespace|applicationId|versionCode|versionName|minSdk|targetSdk\" ventago-admin-app/android/app ventago-admin-app/android -g '*.gradle*'; printf '%s\\n' '--- tracked/new status ---'; git status --short -- ventago-admin-app/lib/core/update ventago-admin-app/android/app/src/main/kotlin/com/coolsistema/ventago_admin_app/Actualizacion.kt ventago-admin-app/android/app/src/main/res/xml/actualizacion_paths.xml; git ls-files --stage -- ventago-admin-app/lib/core/update ventago-admin-app/android/app/src/main/kotlin/com/coolsistema/ventago_admin_app/Actualizacion.kt ventago-admin-app/android/app/src/main/res/xml/actualizacion_paths.xml; printf '%s\\n' '--- exact comparisons ---'; diff -u tienda-admin-app/lib/core/update/actualizacion.dart ventago-admin-app/lib/core/update/actualizacion.dart || true; diff -u tienda-admin-app/lib/core/update/version_remota.dart ventago-admin-app/lib/core/update/version_remota.dart || true; diff -u tienda-admin-app/android/app/src/main/kotlin/com/coolsistema/ventago_admin_app/Actualizacion.kt ventago-admin-app/android/app/src/main/kotlin/com/coolsistema/ventago_admin_app/Actualizacion.kt || true; printf '%s\\n' '--- relevant main files numbered ---'; nl -ba ventago-admin-app/android/app/build.gradle.kts | sed -n '1,180p'; nl -ba ventago-admin-app/android/app/src/main/AndroidManifest.xml | sed -n '1,130p'; nl -ba ventago-admin-app/android/app/src/main/kotlin/com/coolsistema/ventago_admin_app/Actualizacion.kt | sed -n '1,180p'; nl -ba ventago-admin-app/lib/main.dart | sed -n '1,130p'; nl -ba ventago-admin-app/build-apk.sh | sed -n '1,130p'; nl -ba scripts/publicar-apk.sh | sed -n '35,115p'" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
.team/reviews/manual-044-superadmin-actualizacion.md:1834:?? ventago-admin-app/android/app/src/main/res/xml/actualizacion_paths.xml
.team/reviews/manual-044-superadmin-actualizacion.md:1837:--- tienda-admin-app/lib/core/update/actualizacion.dart	2026-10-07 16:09:43
.team/reviews/manual-044-superadmin-actualizacion.md:1838:+++ ventago-admin-app/lib/core/update/actualizacion.dart	2026-10-07 16:09:31
.team/reviews/manual-044-superadmin-actualizacion.md:1844: // Al abrir: lee version.json; si hay una versión más nueva pregunta «Actualizar / Más tarde».
.team/reviews/manual-044-superadmin-actualizacion.md:1853: // El build (build-apk.sh) publica en GitHub Releases (jhkim1010/ventago-downloads):
.team/reviews/manual-044-superadmin-actualizacion.md:1854: //   <app>-latest/version.json  →  {"versionCode": 9, "versionName": "1.1.0",
.team/reviews/manual-044-superadmin-actualizacion.md:1957:    35	            android:name="androidx.core.content.FileProvider"
.team/reviews/manual-044-superadmin-actualizacion.md:1958:    36	            android:authorities="${applicationId}.actualizacion"
.team/reviews/manual-044-superadmin-actualizacion.md:1963:    41	                android:resource="@xml/actualizacion_paths" />
.team/reviews/manual-044-superadmin-actualizacion.md:1990:     8	import androidx.core.content.FileProvider
.team/reviews/manual-044-superadmin-actualizacion.md:1995:    13	// [2026-10-06] Actualización dentro de la app (lib/core/update/actualizacion.dart).
.team/reviews/manual-044-superadmin-actualizacion.md:1996:    14	// Canal «ventago/actualizacion»:
.team/reviews/manual-044-superadmin-actualizacion.md:1998:    16	//   dirDescarga → carpeta en caché para el APK (expuesta por FileProvider: res/xml/actualizacion_paths.xml)
.team/reviews/manual-044-superadmin-actualizacion.md:2003:    21	        MethodChannel(engine.dartExecutor.binaryMessenger, "ventago/actualizacion").setMethodCallHandler { call, result ->
.team/reviews/manual-044-superadmin-actualizacion.md:2012:    30	                        val dir = File(context.cacheDir, "actualizacion")
.team/reviews/manual-044-superadmin-actualizacion.md:2024:    42	                            val uri = FileProvider.getUriForFile(context, context.packageName + ".actualizacion", archivo)
.team/reviews/manual-044-superadmin-actualizacion.md:2035:    53	                result.error("actualizacion", e.message, null)
.team/reviews/manual-044-superadmin-actualizacion.md:2044:     5	import 'core/update/actualizacion.dart';
.team/reviews/manual-044-superadmin-actualizacion.md:2053:    14	// [2026-10-07] 새 버전 안내 — build-apk.sh 가 이 주소에 version.json 을 올린다 (tienda-admin 과 같은 방식)
.team/reviews/manual-044-superadmin-actualizacion.md:2055:    16	    'https://github.com/jhkim1010/ventago-downloads/releases/download/ventago-admin-app-latest/version.json';
.team/reviews/manual-044-superadmin-actualizacion.md:2126:     5	#   ./build-apk.sh                # 빌드 후 복사
.team/reviews/manual-044-superadmin-actualizacion.md:2127:     6	#   ./build-apk.sh --skip-build   # 기존 빌드 산출물만 복사
.team/reviews/manual-044-superadmin-actualizacion.md:2128:     7	#   NOTAS="..." ./build-apk.sh    # 앱의 「Nueva versión」 창에 보일 안내(선택)
.team/reviews/manual-044-superadmin-actualizacion.md:2152:    31	#   publicar-apk.sh 가 「게시된 것보다 큰가」를 다시 확인한다.
.team/reviews/manual-044-superadmin-actualizacion.md:2185:    64	"$APP_DIR/../scripts/publicar-apk.sh" "$APK_SRC" "ventago-admin-app-latest" "ventago-admin-app.apk" "$CERT_UPLOAD" "${NOTAS:-}"
.team/reviews/manual-044-superadmin-actualizacion.md:2226:    45	feed="https://github.com/$REPO/releases/download/$TAG/version.json"
.team/reviews/manual-044-superadmin-actualizacion.md:2227:    46	# [2026-10-07] ★ con «?t=» : sin eso la CDN de GitHub devuelve el version.json anterior durante
.team/reviews/manual-044-superadmin-actualizacion.md:2231:    50	# el mismo APK ya publicado (p.ej. se re-ejecuta build-apk.sh --skip-build para las copias) → nada que hacer
.team/reviews/manual-044-superadmin-actualizacion.md:2248:    67	python3 - "$tmp/version.json" "$code" "$name" "$url" "$sha" "$NOTAS" <<'EOF'
.team/reviews/manual-044-superadmin-actualizacion.md:2256:    75	  || gh release create "$TAG" -R "$REPO" --title "$TAG" --notes "Actualización dentro de la app (version.json + APK)"
.team/reviews/manual-044-superadmin-actualizacion.md:2258:    77	gh release upload "$TAG" "$tmp/version.json" -R "$REPO" --clobber
.team/reviews/manual-044-superadmin-actualizacion.md:2276:현재 연결 관계는 일치합니다. `applicationId`, Kotlin 패키지, Manifest의 `${applicationId}.actualizacion`, 런타임 authority가 모두 `com.coolsistema.ventago_admin_app.actualizacion`으로 수렴하고, MethodChannel 이름도 Dart/Kotlin 양쪽이 같습니다. 이제 실제 빌드·정적 분석과 GitHub asset URL의 쿼리 문자열 동작을 확인하겠습니다.
.team/reviews/manual-044-superadmin-actualizacion.md:2290:web search: https://github.com/jhkim1010/ventago-downloads/releases/download/ventago-admin-app-latest/version.json?t=1791390000
--- pubspec versions and scripts ---
ventago-admin-app/pubspec.yaml:19:version: 1.1.2+4
tienda-admin-app/pubspec.yaml:19:version: 1.0.1+3
mobile-sales-app/pubspec.yaml:19:version: 1.1.0+9
--- tienda-admin-app/build-apk.sh	2026-10-06 14:46:07
+++ ventago-admin-app/build-apk.sh	2026-10-07 16:10:03
@@ -1,16 +1,17 @@
 #!/usr/bin/env bash
-# 매장 주인 앱(tienda-admin-app, Android) 릴리즈 빌드 + 배포 폴더 자동 복사.
+# superadmin 앱(ventago-admin-app, Android) 릴리즈 빌드 + 배포 폴더 자동 복사.
 #
 # 사용법:
 #   ./build-apk.sh                # 빌드 후 복사
 #   ./build-apk.sh --skip-build   # 기존 빌드 산출물만 복사
-#   NOTAS="Modo lector +1" ./build-apk.sh   # 앱의 「Nueva versión」 창에 보일 안내(선택)
+#   NOTAS="..." ./build-apk.sh    # 앱의 「Nueva versión」 창에 보일 안내(선택)
 #
 # 복사 대상:
-#   1) Dropbox/ACE_3_uversion/app herramientas download  — 버전명 + 고정명(tienda-admin-android.apk)
+#   1) Dropbox/ACE_3_uversion/app herramientas download  — 버전명
 #   2) Dropbox/Personal de m. Marcos                     — 버전명 (설치 파일 개인 보관)
+#   3) Google Drive/내 드라이브/ventago-superadmin/ventago-superadmin.apk — 고정명(배포 링크)
 #
-# 파일명 규칙: tienda_admin_android_<YYYYMMDD-HHMM>.apk (APK 컴파일 시각 기준)
+# 파일명 규칙: ventago_superadmin_android_<YYYYMMDD-HHMM>.apk (APK 컴파일 시각 기준)
 
 set -euo pipefail
 
@@ -22,12 +23,11 @@
   "/Users/marcoskim/Dropbox/Personal de m. Marcos"
 )
 
-# 기존 배포 링크가 가리키는 고정 파일명
-FIXED_DEST="/Users/marcoskim/Dropbox/ACE_3_uversion/app herramientas download/tienda-admin-android.apk"
+FIXED_DEST="/Users/marcoskim/Google Drive/내 드라이브/ventago-superadmin/ventago-superadmin.apk"
 
 cd "$APP_DIR"
 
-# [2026-10-06] 앱 안 업데이트: 빌드할 때마다 build 번호를 올린다(같으면 휴대폰이 새 버전으로 안 본다).
+# [2026-10-07] (tienda-admin 과 동일) 앱 안 업데이트: 빌드할 때마다 build 번호를 올린다(같으면 휴대폰이 새 버전으로 안 본다).
 #   publicar-apk.sh 가 「게시된 것보다 큰가」를 다시 확인한다.
 subir_build() {
   local v b
@@ -47,7 +47,7 @@
 
 if [[ "${1:-}" != "--skip-build" ]]; then
   subir_build
-  echo "▶ flutter build apk --release (tienda-admin)"
+  echo "▶ flutter build apk --release (superadmin)"
   flutter build apk --release
 fi
 
@@ -57,14 +57,14 @@
   exit 1
 fi
 
-# [2026-10-06] 앱 안 업데이트용 게시 (GitHub Releases → 앱이 열릴 때 「Nueva versión」 을 묻는다)
-#   ★ 복사(Dropbox/Drive)보다 먼저 — 폴더가 안 붙어 있어도 게시는 된다(codex 014)
-#   업로드 키(Play 와 같은 키)로 서명된 APK 만 게시한다 — 다른 키면 휴대폰이 설치를 거부한다.
+# [2026-10-07] 앱 안 업데이트용 게시 (GitHub Releases → 앱이 열릴 때 「Nueva versión」 을 묻는다)
+#   ★ 복사(Dropbox/Drive)보다 먼저 — 폴더가 안 붙어 있어도 게시는 된다
+#   업로드 키로 서명된 APK 만 게시한다 — 다른 키면 휴대폰이 설치를 거부한다.
 CERT_UPLOAD="23747e710c3c77d8e989626b98d26464baee869d70e44857b8a5b0dc4e3927c7"
-"$APP_DIR/../scripts/publicar-apk.sh" "$APK_SRC" "tienda-admin-app-latest" "tienda-admin-app.apk" "$CERT_UPLOAD" "${NOTAS:-}"
+"$APP_DIR/../scripts/publicar-apk.sh" "$APK_SRC" "ventago-admin-app-latest" "ventago-admin-app.apk" "$CERT_UPLOAD" "${NOTAS:-}"
 
 stamp="$(date -r "$APK_SRC" '+%Y%m%d-%H%M')"
-apk_name="tienda_admin_android_${stamp}.apk"
+apk_name="ventago_superadmin_android_${stamp}.apk"
 missing=0
 
 for dir in "${DEST_DIRS[@]}"; do
--- ignored? ---
--- manifest merger existing outputs ---

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
/bin/zsh -lc "command -v dart; dart analyze lib/main.dart lib/core/update test 2>&1 | sed -n '1,160p'; bash -n build-apk.sh ../scripts/publicar-apk.sh; find android/app/src/main/res -maxdepth 2 -type f -name '*.xml' -print | sort" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/ventago-admin-app
 succeeded in 0ms:
/opt/homebrew/bin/dart
/opt/homebrew/share/flutter/bin/internal/update_engine_version.sh: line 71: /opt/homebrew/share/flutter/bin/cache/engine.stamp.tmp.68446: Operation not permitted
/opt/homebrew/share/flutter/bin/internal/update_engine_version.sh: line 78: /opt/homebrew/share/flutter/bin/cache/engine.realm: Operation not permitted
android/app/src/main/res/drawable-v21/launch_background.xml
android/app/src/main/res/drawable/launch_background.xml
android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml
android/app/src/main/res/values-night/styles.xml
android/app/src/main/res/values/colors.xml
android/app/src/main/res/values/styles.xml
android/app/src/main/res/xml/actualizacion_paths.xml

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
/bin/zsh -lc 'git diff --check -- scripts/publicar-apk.sh ventago-admin-app; kotlinc_path=$(command -v kotlinc || true); printf '"'kotlinc=%s\\n' \""'$kotlinc_path"; rg -n "rootNavigatorKey|scaffoldMessengerKey|MaterialApp'"\\(\" ventago-admin-app/lib; rg -n \"ventago-admin-app-latest|ventago-admin-app-[0-9]+\\.apk\" -S . --glob '"'!**/.git/**'"' --glob '"'!/.team/reviews/manual-044-superadmin-actualizacion.md'"' | head -80" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 204ms:
./ventago-admin-app/lib/main.dart:16:    'https://github.com/jhkim1010/ventago-downloads/releases/download/ventago-admin-app-latest/version.json';
./ventago-admin-app/build-apk.sh:64:"$APP_DIR/../scripts/publicar-apk.sh" "$APK_SRC" "ventago-admin-app-latest" "ventago-admin-app.apk" "$CERT_UPLOAD" "${NOTAS:-}"

hook: PostToolUse
hook: PostToolUse
hook: PostToolUse Failed
hook: PostToolUse Completed
codex
이상 없음.

확인 결과:

- Manifest 권한 및 `FileProvider` 선언 정상
- authority가 `${applicationId}.actualizacion` ↔ `context.packageName + ".actualizacion"`으로 일치
- `actualizacion_paths.xml`이 실제 다운로드 경로만 노출
- MethodChannel `ventago/actualizacion`이 Dart/Kotlin 양쪽에서 일치
- `configureFlutterEngine()`의 등록 방식 정상
- `navigatorKey`가 동일 `MaterialApp`에 연결되어 첫 프레임 이후 다이얼로그 표시 가능
- tag, feed URL, APK asset 이름이 서로 일치
- APK → `version.json` 순서로 게시되어 feed가 미업로드 APK를 가리키지 않음
- `set -e`에서 게시 실패 시 복사 단계로 진행하지 않으며, 복사 실패 후에는 `--skip-build`로 재실행 가능
- `?t=...`는 따옴표 안에서 URL query로만 사용되므로 셸 파싱을 깨뜨리지 않음
- 쉘 문법 검사와 `git diff --check` 통과

단, 새 Dart/Kotlin/XML 파일은 현재 Git에서 `untracked` 상태입니다. 커밋할 때 누락되면 컴파일이 실패하므로 반드시 포함해야 합니다.

Flutter 전체 분석·Android release 컴파일은 샌드박스가 Flutter SDK 캐시 쓰기를 막아 실행하지 못했습니다. 정적 대조상 구체적인 결함은 발견되지 않았습니다.
hook: Stop
hook: Stop
hook: Stop Failed
hook: Stop Completed
tokens used
47,822
이상 없음.

확인 결과:

- Manifest 권한 및 `FileProvider` 선언 정상
- authority가 `${applicationId}.actualizacion` ↔ `context.packageName + ".actualizacion"`으로 일치
- `actualizacion_paths.xml`이 실제 다운로드 경로만 노출
- MethodChannel `ventago/actualizacion`이 Dart/Kotlin 양쪽에서 일치
- `configureFlutterEngine()`의 등록 방식 정상
- `navigatorKey`가 동일 `MaterialApp`에 연결되어 첫 프레임 이후 다이얼로그 표시 가능
- tag, feed URL, APK asset 이름이 서로 일치
- APK → `version.json` 순서로 게시되어 feed가 미업로드 APK를 가리키지 않음
- `set -e`에서 게시 실패 시 복사 단계로 진행하지 않으며, 복사 실패 후에는 `--skip-build`로 재실행 가능
- `?t=...`는 따옴표 안에서 URL query로만 사용되므로 셸 파싱을 깨뜨리지 않음
- 쉘 문법 검사와 `git diff --check` 통과

단, 새 Dart/Kotlin/XML 파일은 현재 Git에서 `untracked` 상태입니다. 커밋할 때 누락되면 컴파일이 실패하므로 반드시 포함해야 합니다.

Flutter 전체 분석·Android release 컴파일은 샌드박스가 Flutter SDK 캐시 쓰기를 막아 실행하지 못했습니다. 정적 대조상 구체적인 결함은 발견되지 않았습니다.

## 처리
- 지적 0건. 새 파일 untracked 주의 → 커밋에 명시적으로 포함. release 컴파일은 build-apk.sh 실행으로 확인.
