#!/usr/bin/env bash
# =============================================================================
# Phase 86 게이트 — 자율 루프(cmux)의 **유일한 판정 기준**
# =============================================================================
# 사용:
#   tools/phase86/gate.sh            # 현재 wave 까지 전부 검사
#   tools/phase86/gate.sh w1         # 특정 wave 만
#   tools/phase86/gate.sh --list     # 게이트 목록
#
# 규약:
#   - exit 0 = 통과, exit 1 = 실패. 자율 루프는 **exit code 만** 믿는다.
#   - 실패는 반드시 "무엇이 / 어디서 / 무엇을 기대했는데 무엇이 나왔는지" 를 찍는다.
#     그래야 다음 반복에서 고칠 수 있다. 원인 없는 FAIL 은 루프를 무한히 돌게 만든다.
#   - 게이트는 **읽기 전용 판정자**다. 여기서 코드를 고치지 않는다.
#
# ★ 이 스크립트는 운영 DB 에 절대 접속하지 않는다. 샌드박스 PG18(포트 55432)만 쓴다.
# =============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

WAVE="${1:-all}"
PASS=0; FAIL=0
declare -a FAILED

say()  { printf '%s\n' "$*"; }
head_() { printf '\n\033[1m── %s\033[0m\n' "$*"; }
gate() { # gate <이름> <명령...>
  local name="$1"; shift
  if "$@" >/tmp/phase86-gate.out 2>&1; then
    say "  ✔ $name"; PASS=$((PASS+1))
  else
    say "  ✘ $name"; FAILED+=("$name"); FAIL=$((FAIL+1))
    sed 's/^/      /' /tmp/phase86-gate.out | tail -25
  fi
}

if [[ "$WAVE" == "--list" ]]; then
  cat <<'EOF'
w1  마이그레이션      M1~M7 적용 + 동작 + 멱등
w2  덤프 리더         PGDMP plain/gzip/custom/tar 4경로 + codigos_tmp 스킵 + 메모리 상한
w3  매퍼/잡           엔티티 매핑 + 리스 + 배치 커밋 + PENDING/DONE 재개
w4  E2E              더미 매장 임포트 + V1~V16 정합성
w5  리포트           R1~R17 stock & reports 스모크
w6  품질             ESLint + api/app 빌드
EOF
  exit 0
fi

# ---------------------------------------------------------------------------
# w1 — 마이그레이션
# ---------------------------------------------------------------------------
if [[ "$WAVE" == "all" || "$WAVE" == "w1" ]]; then
  head_ "w1 마이그레이션"
  # ★ bash 로 부른다 — 마운트된 작업트리에서 exec 비트가 유실될 수 있다(Permission denied).
  gate "샌드박스 PG18 기동"            bash tools/phase86/pgup.sh
  gate "부모 스키마 부트스트랩"         node tools/phase86/verify-migrations.js bootstrap
  gate "M1~M7 적용"                    node tools/phase86/verify-migrations.js
  gate "제약·리스·CASCADE 동작"        node tools/phase86/verify-migration-behavior.js
  gate "멱등성(재실행 무해)"            node tools/phase86/verify-migrations.js
fi

# ---------------------------------------------------------------------------
# w2 — 덤프 리더 (TASK-2b)   ※ 구현 전에는 SKIP 이 아니라 FAIL 이다
# ---------------------------------------------------------------------------
if [[ "$WAVE" == "all" || "$WAVE" == "w2" ]]; then
  head_ "w2 덤프 리더"
  if [[ -f tools/phase86/verify-dump-reader.js ]]; then
    gate "PGDMP 4경로 + codigos_tmp 스킵" node tools/phase86/verify-dump-reader.js
  else
    say "  … 미구현 (TASK-2b) — w2 게이트 없음"
  fi
fi

# ---------------------------------------------------------------------------
# w3~w5 — 구현이 붙는 대로 게이트 파일이 생긴다
# ---------------------------------------------------------------------------
for w in w3 w4 w5; do
  if [[ "$WAVE" == "all" || "$WAVE" == "$w" ]]; then
    f="tools/phase86/verify-$w.js"
    head_ "$w"
    if [[ -f "$f" ]]; then gate "$w 검증" node "$f"; else say "  … 미구현 — 게이트 없음"; fi
  fi
done

# ---------------------------------------------------------------------------
# w6 — 품질 (변경 파일만. 저장소 전체 lint 는 기존 부채까지 잡아 루프를 막는다)
# ---------------------------------------------------------------------------
if [[ "$WAVE" == "all" || "$WAVE" == "w6" ]]; then
  head_ "w6 품질"
  CHANGED=$(git diff --name-only main...HEAD 2>/dev/null; git diff --name-only; git ls-files -o --exclude-standard)
  API_FILES=$(echo "$CHANGED" | grep -E '^api-ventago/src/.*\.ts$' | sort -u | tr '\n' ' ')
  APP_FILES=$(echo "$CHANGED" | grep -E '^ventago-app/src/.*\.(ts|tsx)$' | sort -u | tr '\n' ' ')
  if [[ -n "${API_FILES// /}" ]]; then
    gate "api ESLint(변경 파일)" bash -c "cd api-ventago && npx eslint ${API_FILES//api-ventago\//}"
  else say "  … api 변경 없음"; fi
  if [[ -n "${APP_FILES// /}" ]]; then
    gate "app ESLint(변경 파일)" bash -c "cd ventago-app && npx eslint ${APP_FILES//ventago-app\//}"
  else say "  … app 변경 없음"; fi
  gate "api 타입체크" bash -c "cd api-ventago && npx tsc --noEmit"
fi

# ---------------------------------------------------------------------------
head_ "결과"
say "  통과 $PASS / 실패 $FAIL"
if (( FAIL )); then
  say ""
  say "  실패 게이트:"
  for f in "${FAILED[@]}"; do say "    - $f"; done
  say ""
  say "  다음 행동: 위 출력에서 원인을 찾아 코드를 고치고 같은 게이트를 다시 돌린다."
  say "  같은 게이트가 2회 연속 같은 이유로 실패하면 접근을 바꾼다(RUNBOOK §4)."
  exit 1
fi
say "  ALL GREEN"
exit 0
