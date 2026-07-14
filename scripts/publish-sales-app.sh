#!/usr/bin/env bash
# =====================================================================
# 판매원 앱(mobile-sales-app) 빌드 산출물 → 배포 폴더 복사 (표준 명명)
# ---------------------------------------------------------------------
# 규칙(사장님 지시):
#   - 파일명은 항상 app_sales 로 시작 + 운용체계(os) 기록 + 버전/빌드/날짜로 누적
#     예: app_sales_android_v1.0.0_b1_20260714-1619.apk
#   - 항상 Dropbox 배포 폴더로 복사(누적, 덮어쓰기 안 함)
#
# 사용법:
#   ./scripts/publish-sales-app.sh [android|macos]   (기본 android)
#   * 이미 빌드된 산출물을 찾아 복사만 한다(빌드 안 함).
#     빌드는 flutter build apk --release / flutter build macos --release 로 먼저 수행.
# =====================================================================
set -euo pipefail

OS="${1:-android}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/mobile-sales-app"
DEST="/Users/marcoskim/Dropbox/ACE_3_uversion/app herramientas download"

# 버전(pubspec: version: X.Y.Z+B) 파싱
RAW_VER="$(grep -E '^version:' "$APP_DIR/pubspec.yaml" | awk '{print $2}')"
VER="${RAW_VER%%+*}"          # 1.0.0
BUILD="${RAW_VER##*+}"        # 1
[ "$BUILD" = "$RAW_VER" ] && BUILD="0"
STAMP="$(date '+%Y%m%d-%H%M')"

case "$OS" in
  android)
    SRC="$APP_DIR/build/app/outputs/flutter-apk/app-release.apk"
    EXT="apk"
    ;;
  macos)
    # macos 는 .app 디렉토리 → zip 로 묶어서 복사
    SRC="$APP_DIR/build/macos/Build/Products/Release/mobile_sales_app.app"
    EXT="app.zip"
    ;;
  *)
    echo "❌ 지원하지 않는 os: $OS (android|macos)"; exit 1 ;;
esac

if [ ! -e "$SRC" ]; then
  echo "❌ 빌드 산출물 없음: $SRC"
  echo "   먼저 빌드하세요: cd mobile-sales-app && flutter build ${OS/macos/macos} --release"
  exit 1
fi

mkdir -p "$DEST"
OUT_NAME="app_sales_${OS}_v${VER}_b${BUILD}_${STAMP}.${EXT}"
OUT_PATH="$DEST/$OUT_NAME"

if [ "$EXT" = "app.zip" ]; then
  (cd "$(dirname "$SRC")" && zip -qr "$OUT_PATH" "$(basename "$SRC")")
else
  cp "$SRC" "$OUT_PATH"
fi

echo "✅ 복사 완료: $OUT_NAME"
echo "   → $OUT_PATH"
echo "   size: $(du -h "$OUT_PATH" | awk '{print $1}')"
