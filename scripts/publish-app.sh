#!/usr/bin/env bash
# =====================================================================
# Ventago Flutter 앱 빌드 산출물 → 배포 폴더 복사 (표준 명명)
# ---------------------------------------------------------------------
# 규칙(사장님 지시):
#   - 파일명은 항상 app_<키> 로 시작 + 운용체계(os) 기록 + 버전/빌드/날짜로 누적
#     예: app_sales_android_v1.0.0_b1_20260714-1619.apk
#         repositor_android_v1.0.0_b1_20260714-1619.apk   (operador/despacho 앱)
#   - 항상 Dropbox 배포 폴더로 복사(누적, 덮어쓰기 안 함)
#
# 사용법:
#   ./scripts/publish-app.sh <sales|operador> [android|macos]   (기본 android)
#   * 이미 빌드된 산출물을 찾아 복사만 한다(빌드 안 함).
#     빌드는 flutter build apk --release / flutter build macos --release 로 먼저 수행.
# =====================================================================
set -euo pipefail

APP_KEY="${1:-}"
OS="${2:-android}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="/Users/marcoskim/Dropbox/ACE_3_uversion/app herramientas download"

# 앱 키 → (디렉토리 · 파일명 접두)
case "$APP_KEY" in
  sales)    APP_DIR="$ROOT/mobile-sales-app"; PREFIX="app_sales" ;;
  operador) APP_DIR="$ROOT/despacho-app";     PREFIX="repositor" ;;
  *)
    echo "❌ 앱 키 필요: sales | operador   (받은 값: '$APP_KEY')"; exit 1 ;;
esac

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
    SRC="$APP_DIR/build/macos/Build/Products/Release/$(grep -E '^name:' "$APP_DIR/pubspec.yaml" | awk '{print $2}').app"
    EXT="app.zip"
    ;;
  *)
    echo "❌ 지원하지 않는 os: $OS (android|macos)"; exit 1 ;;
esac

if [ ! -e "$SRC" ]; then
  echo "❌ 빌드 산출물 없음: $SRC"
  echo "   먼저 빌드하세요: cd $(basename "$APP_DIR") && flutter build ${OS/android/apk} --release"
  exit 1
fi

mkdir -p "$DEST"
OUT_NAME="${PREFIX}_${OS}_v${VER}_b${BUILD}_${STAMP}.${EXT}"
OUT_PATH="$DEST/$OUT_NAME"

if [ "$EXT" = "app.zip" ]; then
  (cd "$(dirname "$SRC")" && zip -qr "$OUT_PATH" "$(basename "$SRC")")
else
  cp "$SRC" "$OUT_PATH"
fi

echo "✅ 복사 완료: $OUT_NAME"
echo "   → $OUT_PATH"
echo "   size: $(du -h "$OUT_PATH" | awk '{print $1}')"
