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
#   (2026-10-07 사용자: Dropbox 만으로 충분 — Google Drive 복사 제거. 휴대폰은 앱 안 업데이트로 받는다)
#
# 파일명 규칙: ventago_superadmin_android_<YYYYMMDD-HHMM>.apk (APK 컴파일 시각 기준)

set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APK_SRC="$APP_DIR/build/app/outputs/flutter-apk/app-release.apk"

DEST_DIRS=(
  "/Users/marcoskim/Dropbox/ACE_3_uversion/app herramientas download"
  "/Users/marcoskim/Dropbox/Personal de m. Marcos"
)

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

if [[ "$missing" -eq 1 ]]; then
  echo "ERROR: 일부 대상에 복사하지 못했습니다 (위 WARN 확인)" >&2
  exit 1
fi

echo "✔ 전체 복사 완료 ($apk_name)"
