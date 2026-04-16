#!/bin/bash
# SVG → PNG 아이콘 생성 스크립트 (sharp-cli 사용)
# 사용법: bash scripts/generate-icons.sh

set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

generate() {
  local NAME="$1"
  local SVG="$ROOT/$NAME/renderer/assets/icon.svg"
  local ASSETS="$ROOT/$NAME/renderer/assets"

  if [ ! -f "$SVG" ]; then
    echo "⚠️  $SVG 없음 — 스킵"
    return
  fi

  echo "🎨 $NAME 아이콘 생성 중..."

  # 트레이 아이콘 (16x16)
  npx --yes sharp-cli -i "$SVG" -o "$ASSETS/tray-icon.png" resize 16 16

  # 앱 아이콘 (256x256)
  npx --yes sharp-cli -i "$SVG" -o "$ASSETS/icon-256.png" resize 256 256

  # electron-builder 용 (512x512)
  npx --yes sharp-cli -i "$SVG" -o "$ASSETS/icon-512.png" resize 512 512

  echo "✅ $NAME: tray-icon.png, icon-256.png, icon-512.png 생성 완료"
}

generate "print-agent"
generate "zebra-agent"

echo ""
echo "📌 electron-builder에서 사용하려면 package.json build.icon 설정:"
echo '   "icon": "renderer/assets/icon-512.png"'
