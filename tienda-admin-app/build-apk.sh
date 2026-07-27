#!/usr/bin/env bash
# 매장 주인 앱(tienda-admin-app, Android) 릴리즈 빌드 + 배포 폴더 자동 복사.
#
# 사용법:
#   ./build-apk.sh                # 빌드 후 복사
#   ./build-apk.sh --skip-build   # 기존 빌드 산출물만 복사
#
# 복사 대상:
#   1) Dropbox/ACE_3_uversion/app herramientas download  — 버전명 + 고정명(tienda-admin-android.apk)
#   2) Dropbox/Personal de m. Marcos                     — 버전명 (설치 파일 개인 보관)
#
# 파일명 규칙: tienda_admin_android_<YYYYMMDD-HHMM>.apk (APK 컴파일 시각 기준)

set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APK_SRC="$APP_DIR/build/app/outputs/flutter-apk/app-release.apk"

DEST_DIRS=(
  "/Users/marcoskim/Dropbox/ACE_3_uversion/app herramientas download"
  "/Users/marcoskim/Dropbox/Personal de m. Marcos"
)

# 기존 배포 링크가 가리키는 고정 파일명
FIXED_DEST="/Users/marcoskim/Dropbox/ACE_3_uversion/app herramientas download/tienda-admin-android.apk"

cd "$APP_DIR"

if [[ "${1:-}" != "--skip-build" ]]; then
  echo "▶ flutter build apk --release (tienda-admin)"
  flutter build apk --release
fi

if [[ ! -f "$APK_SRC" ]]; then
  echo "ERROR: APK 산출물 없음: $APK_SRC" >&2
  echo "       --skip-build 없이 다시 실행하세요." >&2
  exit 1
fi

stamp="$(date -r "$APK_SRC" '+%Y%m%d-%H%M')"
apk_name="tienda_admin_android_${stamp}.apk"
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
