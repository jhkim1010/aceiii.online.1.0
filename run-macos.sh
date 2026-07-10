#!/bin/bash
# Ventago 판매원 앱 — macOS 데스크톱 실행 스크립트
# 하는 일: ① macOS 플랫폼 스캐폴드 추가 ② 샌드박스 네트워크(client) 권한 패치
#          ③ 백엔드(5002) 확인 ④ flutter run -d macos
# 사용법(프로젝트 루트에서): bash run-macos.sh
set -e
cd "$(dirname "$0")/mobile-sales-app"

echo "▶ 1/4  macOS 플랫폼 스캐폴드 확인/추가..."
if [ ! -d "macos" ]; then
  flutter create --platforms=macos .
else
  echo "  이미 macos/ 존재 — 건너뜀"
fi

echo "▶ 2/4  샌드박스 네트워크(client) 권한 추가 (localhost:5002 접속용)..."
# macOS 앱은 기본 샌드박스라 network.client 가 없으면 모든 외부 접속이 막힘(로그인 실패 원인)
for ENT in macos/Runner/DebugProfile.entitlements macos/Runner/Release.entitlements; do
  if /usr/libexec/PlistBuddy -c "Add :com.apple.security.network.client bool true" "$ENT" 2>/dev/null; then
    echo "  + $ENT 패치됨"
  else
    echo "  = $ENT 이미 설정됨"
  fi
done

echo "▶ 3/4  백엔드(5002) 확인..."
if lsof -nP -iTCP:5002 -sTCP:LISTEN >/dev/null 2>&1; then
  echo "  ✅ 백엔드 실행 중 (localhost:5002)"
else
  echo "  ⚠️  5002 백엔드가 안 떠 있습니다. 다른 터미널에서 먼저 실행하세요:  ./dev.sh"
fi

echo "▶ 4/4  flutter run -d macos ..."
flutter run -d macos --dart-define=BASE_URL=http://localhost:5002/api
