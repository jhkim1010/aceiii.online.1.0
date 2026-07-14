#!/usr/bin/env bash
# =====================================================================
# Ventago Flutter 앱 빌드 → 컴파일 날짜 주입(--dart-define) → Dropbox 배포
# ---------------------------------------------------------------------
# 사용법:
#   ./scripts/build-app.sh <sales|operador> [android|macos]   (기본 android)
#
# 하는 일:
#   1) BUILD_DATE = 현재 시각(YYYY-MM-DD HH:MM) 을 --dart-define 으로 주입
#      → 앱 헤더에 'build ...' 로 표시(BuildInfo.date).
#   2) flutter build (apk release / macos release)
#   3) scripts/publish-app.sh 로 표준 명명 + Dropbox 복사.
# =====================================================================
set -euo pipefail

APP_KEY="${1:-}"
OS="${2:-android}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

case "$APP_KEY" in
  sales)    APP_DIR="$ROOT/mobile-sales-app" ;;
  operador) APP_DIR="$ROOT/despacho-app" ;;
  *) echo "❌ 앱 키 필요: sales | operador"; exit 1 ;;
esac

BUILD_DATE="$(date '+%Y-%m-%d %H:%M')"
echo "▶ $APP_KEY / $OS — BUILD_DATE='$BUILD_DATE'"

cd "$APP_DIR"
case "$OS" in
  android) flutter build apk --release --dart-define=BUILD_DATE="$BUILD_DATE" ;;
  macos)   flutter build macos --release --dart-define=BUILD_DATE="$BUILD_DATE" ;;
  *) echo "❌ os: android|macos"; exit 1 ;;
esac

"$ROOT/scripts/publish-app.sh" "$APP_KEY" "$OS"
