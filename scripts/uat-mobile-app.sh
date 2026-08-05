#!/usr/bin/env bash
# =============================================================================
# Phase 37 — mobile-sales-app 실기기 UAT 런처
# =============================================================================
# 판매원(vendedor) 앱을 iOS 시뮬레이터 / Android 에뮬레이터 / 실기기에 띄워
# 딥 화면 UAT(U1 매트릭스 / U3·U4 2기기 세션 / 오프라인 CTA)를 눈으로 확인하기 위한 헬퍼.
#
# 웹(Chrome)은 flutter_secure_storage(HTTP localhost) 제약으로 로그인 후 진입 불가 →
# 반드시 시뮬레이터/에뮬레이터/실기기에서 실행할 것.
#
# 사용법:
#   ./scripts/uat-mobile-app.sh ios       # iOS 시뮬레이터 (localhost, 가장 쉬움)
#   ./scripts/uat-mobile-app.sh android   # Android 에뮬레이터 (10.0.2.2)
#   ./scripts/uat-mobile-app.sh device    # USB/LAN 실기기 (Mac LAN IP)
#   ./scripts/uat-mobile-app.sh           # 사용법 + 기기/에뮬레이터 목록
#
# 사전: 백엔드가 :5002 에서 기동 중이어야 함 (npm run dev:api).
# =============================================================================
set -euo pipefail

# --- 경로/상수 ---------------------------------------------------------------
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/mobile-sales-app"
API_DIR="$ROOT/api-ventago"
export PATH="/Users/marcoskim/flutter/bin:$PATH"

API_PORT=5002
BACKEND_LOCAL="http://localhost:${API_PORT}/api"       # iOS 시뮬레이터
BACKEND_ANDROID="http://10.0.2.2:${API_PORT}/api"      # Android 에뮬레이터 (호스트 별칭)
LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo '')"
BACKEND_DEVICE="http://${LAN_IP}:${API_PORT}/api"      # 실기기 (같은 Wi-Fi)

# 테스트 계정 (로컬 dev)
UAT_USER="miguel@cool"
UAT_PIN="1234"
UAT_USER_ID=19

# [Phase 65 W7] 비밀번호를 파일에 두지 않는다 — 환경변수에서 받는다.
#   PG_PASS='...' bash scripts/uat-mobile-app.sh
# 미설정이면 즉시 중단한다(빈 값으로 붙어 조용히 실패하는 것보다 낫다).
PG_HOST=127.0.0.1; PG_PORT=5432; PG_USER=postgres; PG_DB=ventago
PG_PASS="${PG_PASS:?PG_PASS 환경변수를 설정하세요 (postgres 계정 비밀번호)}"

# --- 유틸 --------------------------------------------------------------------
say(){ printf "\033[1;33m[uat]\033[0m %s\n" "$*"; }
err(){ printf "\033[1;31m[uat:ERROR]\033[0m %s\n" "$*" >&2; }

check_backend(){
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' -X POST "${BACKEND_LOCAL}/mobile/auth/login" \
          -H 'Content-Type: application/json' -d '{}' 2>/dev/null || echo 000)"
  # 400 = 라우트 존재(검증 실패), 그 외 정상 2xx/4xx = 살아있음. 000 = 다운.
  if [ "$code" = "000" ]; then
    err "백엔드가 :${API_PORT} 에서 응답하지 않습니다. 먼저 'npm run dev:api' 로 기동하세요."
    exit 1
  fi
  say "백엔드 OK (:${API_PORT}, /mobile/auth/login http=${code})"
}

ensure_pin(){
  # miguel 에게 PIN 재설정 (bcrypt, 멱등). api-ventago/node_modules 의 bcrypt/pg 사용.
  say "테스트 계정 PIN 설정: ${UAT_USER} / ${UAT_PIN}"
  ( cd "$API_DIR" && PGPASSWORD="$PG_PASS" node -e "
    const bcrypt=require('bcrypt'), {Client}=require('pg');
    (async()=>{
      const hash=await bcrypt.hash('${UAT_PIN}',10);
      const c=new Client({host:'${PG_HOST}',port:${PG_PORT},user:'${PG_USER}',password:'${PG_PASS}',database:'${PG_DB}'});
      await c.connect();
      const r=await c.query('UPDATE users SET mobile_pin=\$1 WHERE id=${UAT_USER_ID} RETURNING username',[hash]);
      console.log('  PIN 설정 완료:', r.rows[0] ? r.rows[0].username : '(대상 없음)');
      await c.end();
    })().catch(e=>{console.error('  PIN 설정 실패:',e.message);process.exit(1);});
  " )
}

print_checklist(){
  local base="$1"
  cat <<EOF

  ┌──────────────────────────────────────────────────────────────────────────┐
  │  Phase 37 판매원 앱 UAT — 딥 화면 체크리스트                                │
  └──────────────────────────────────────────────────────────────────────────┘
  로그인:  Usuario = ${UAT_USER}   PIN = ${UAT_PIN}   (Sucursal 은 자동 배정=HELGUERA)
  서버:    ${base}

  U1 매트릭스 렌더 (D-15/UI-D2)
     · 카탈로그에서 "TIGRE"(상품73) 검색 → 상세 진입
     · color×size 셀에 숫자 직접 입력(+/- 없음), 자기 지점 재고 굵게 + otras:N 읽기전용
     · 자기 지점 재고 상한 초과 입력 불가(빨강/traslado 없음)
     · "Probar con foto" 는 비활성 + "Próximamente"
  U5 보류판매 (앱→데스크톱)
     · 매트릭스 담기 → Comanda "Mandar a Caja" → Done "En la lista de espera"
     · 데스크톱 nueva-venta 보류 목록에 도착 토스트 + 배지 확인
  U3/U4 2기기 세션
     · 이 기기 로그인 유지 상태에서 다른 기기(또는 재실행)로 재로그인
     · 첫 기기는 다음 동작 시 401 → "세션 만료" 토스트 + 로그인 화면 복귀
  오프라인 CTA (criterion 11)
     · 기기 비행기모드/Wi-Fi 끄기 → 카탈로그·재고는 캐시로 열람 가능
     · "Mandar a Caja" 는 비활성 + "Requiere conexión" 안내
  QR (Phase 38 대기 → 딥링크 수동 대체)
     · 스캐너 대신 딥링크 /m/stock?s=1&p=73 로 해당 상품 매트릭스 진입 확인

  종료: 터미널에서 'q' 입력 (flutter run 종료)
  결과 기록: .planning/phases/37-mobile-sales-shell/37-HUMAN-UAT.md (9~12번 항목)

EOF
}

run_app(){
  local device_id="$1" base_url="$2"
  ensure_pin
  print_checklist "$base_url"
  say "flutter run → device=${device_id}, BASE_URL=${base_url}"
  cd "$APP_DIR"
  flutter pub get >/dev/null
  exec flutter run -d "$device_id" --dart-define=BASE_URL="$base_url"
}

# --- 타깃 분기 ---------------------------------------------------------------
TARGET="${1:-}"
check_backend

case "$TARGET" in
  ios)
    say "iOS 시뮬레이터 부팅 확인..."
    open -a Simulator || true
    # 부팅된 시뮬레이터가 잡힐 때까지 잠깐 대기
    for i in $(seq 1 15); do
      DID="$(flutter devices --machine 2>/dev/null | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{try{const a=JSON.parse(d);const s=a.find(x=>x.targetPlatform&&x.targetPlatform.includes('ios')&&x.emulator);console.log(s?s.id:'')}catch(e){console.log('')}})")"
      [ -n "$DID" ] && break; sleep 2
    done
    if [ -z "${DID:-}" ]; then err "iOS 시뮬레이터를 찾지 못했습니다. Xcode > Simulator 를 먼저 켜세요."; exit 1; fi
    run_app "$DID" "$BACKEND_LOCAL"
    ;;
  android)
    say "Android 에뮬레이터 확인..."
    DID="$(flutter devices --machine 2>/dev/null | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{try{const a=JSON.parse(d);const s=a.find(x=>x.targetPlatform&&x.targetPlatform.includes('android'));console.log(s?s.id:'')}catch(e){console.log('')}})")"
    if [ -z "${DID:-}" ]; then
      say "실행 중인 에뮬레이터 없음 → 첫 AVD 부팅 시도"
      AVD="$(flutter emulators 2>/dev/null | awk '/•/{print $1; exit}')"
      [ -n "$AVD" ] && flutter emulators --launch "$AVD" || { err "AVD 없음. Android Studio 에서 에뮬레이터를 만드세요."; exit 1; }
      for i in $(seq 1 30); do
        DID="$(flutter devices --machine 2>/dev/null | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{try{const a=JSON.parse(d);const s=a.find(x=>x.targetPlatform&&x.targetPlatform.includes('android'));console.log(s?s.id:'')}catch(e){console.log('')}})")"
        [ -n "$DID" ] && break; sleep 2
      done
    fi
    if [ -z "${DID:-}" ]; then err "Android 에뮬레이터 부팅 실패"; exit 1; fi
    run_app "$DID" "$BACKEND_ANDROID"
    ;;
  device)
    if [ -z "$LAN_IP" ]; then err "Mac LAN IP 를 찾지 못했습니다(Wi-Fi 연결 확인)."; exit 1; fi
    say "실기기 대상 — 기기와 Mac 이 같은 Wi-Fi 여야 함. baseUrl=${BACKEND_DEVICE}"
    DID="$(flutter devices --machine 2>/dev/null | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{try{const a=JSON.parse(d);const s=a.find(x=>!x.emulator && (x.targetPlatform||'').match(/ios|android/));console.log(s?s.id:'')}catch(e){console.log('')}})")"
    if [ -z "${DID:-}" ]; then err "USB/무선 연결된 실기기를 찾지 못했습니다. 케이블 연결 + 신뢰 허용 후 재시도."; exit 1; fi
    run_app "$DID" "$BACKEND_DEVICE"
    ;;
  *)
    cat <<EOF

  Phase 37 판매원 앱 UAT 런처
  ────────────────────────────────────────────
  사용법:
    ./scripts/uat-mobile-app.sh ios       iOS 시뮬레이터  (localhost, 가장 쉬움)
    ./scripts/uat-mobile-app.sh android   Android 에뮬레이터 (10.0.2.2)
    ./scripts/uat-mobile-app.sh device    USB/LAN 실기기   (${BACKEND_DEVICE:-LAN})

  ⚠ 웹(Chrome)은 flutter_secure_storage 제약으로 로그인 후 진입 불가 → 사용 금지.
  ⚠ 먼저 백엔드 기동: npm run dev:api

  현재 연결된 기기:
EOF
    flutter devices 2>/dev/null | sed 's/^/    /' | head -12
    echo ""
    say "권장: iOS 시뮬레이터가 가장 간단 → ./scripts/uat-mobile-app.sh ios"
    ;;
esac
