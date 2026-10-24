#!/usr/bin/env bash
# Despacho 앱 (Android) 릴리즈 빌드 + 앱 안 업데이트 게시.
# (mobile-sales-app/build-apk.sh 와 같은 절차 — 배포 폴더 복사는 하지 않는다)
#
# 사용법:
#   ./build-apk.sh                # build 번호 +1 → 빌드 → 게시
#   ./build-apk.sh --skip-build   # 기존 빌드 산출물만 게시
#   NOTAS="..." ./build-apk.sh    # 앱의 「Nueva versión disponible」 창에 보일 안내(선택)
#
# 게시: GitHub Releases jhkim1010/ventago-downloads, 태그 despacho-app-latest
#   → 앱이 열릴 때 version.json 을 읽고, 더 새 버전이면 「Actualizar / Más tarde」 를 묻는다.

set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APK_SRC="$APP_DIR/build/app/outputs/flutter-apk/app-release.apk"

# 업로드 키(~/android-keys/key.properties — mobile-sales-app 과 같은 키)의 인증서 SHA-256.
#   android/app/build.gradle.kts 가 release 를 이 키로 서명한다(키가 없으면 debug 키 → 게시 거부됨).
CERT_UPLOAD="23747e710c3c77d8e989626b98d26464baee869d70e44857b8a5b0dc4e3927c7"

cd "$APP_DIR"

if [[ -z "$CERT_UPLOAD" ]]; then
  echo "ERROR: release 서명 키가 아직 없습니다 — 게시하지 않습니다 (위 주석 참조)." >&2
  exit 1
fi

# 빌드할 때마다 build 번호를 올린다(같으면 휴대폰이 새 버전으로 안 본다).
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
  echo "▶ flutter build apk --release ($(grep -E '^version:' pubspec.yaml | awk '{print $2}'))"
  flutter build apk --release
fi

if [[ ! -f "$APK_SRC" ]]; then
  echo "ERROR: APK 산출물 없음: $APK_SRC" >&2
  echo "       --skip-build 없이 다시 실행하세요." >&2
  exit 1
fi

# 업로드 키로 서명된 APK 만 게시한다 — 다른 키면 휴대폰이 설치를 거부한다(publicar-apk.sh 가 검사).
"$APP_DIR/../scripts/publicar-apk.sh" "$APK_SRC" "despacho-app-latest" "despacho-app.apk" "$CERT_UPLOAD" "${NOTAS:-}"
