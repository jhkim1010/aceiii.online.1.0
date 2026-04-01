#!/bin/bash
# 배포/업그레이드 전 자동 점검 스크립트
# 사용법: bash scripts/precheck.sh [api|app|all]

set -e

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:-all}"
ERRORS=0
WARNINGS=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; ERRORS=$((ERRORS + 1)); }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; WARNINGS=$((WARNINGS + 1)); }
log_info() { echo -e "       $1"; }

echo "========================================"
echo " VentaGO 배포 전 점검 (precheck)"
echo " 대상: $TARGET"
echo "========================================"
echo ""

# ─── 1. 호이스팅 의존성 점검 (Docker 호환성) ───
echo "--- 1. Docker 호환성: 호이스팅된 의존성 점검 ---"

check_imports_vs_packagejson() {
  local workspace=$1
  local workspace_dir="$ROOT_DIR/$workspace"
  local pkg="$workspace_dir/package.json"

  if [ ! -f "$pkg" ]; then
    log_warn "$workspace/package.json 없음 - 건너뜀"
    return
  fi

  # src 디렉토리에서 사용하는 외부 import 추출
  local imports
  imports=$(grep -rh "from '[^./]" "$workspace_dir/src/" 2>/dev/null \
    | grep -oP "from '\K[^'/@]+" \
    | sort -u || true)

  # @scope 패키지도 추출
  local scoped_imports
  scoped_imports=$(grep -rh "from '@" "$workspace_dir/src/" 2>/dev/null \
    | grep -oP "from '\K@[^']+(?=/|')" \
    | sort -u || true)

  local all_imports="$imports"$'\n'"$scoped_imports"

  # Node.js 내장 모듈 제외
  local builtins="crypto fs path os net http https url stream events buffer util child_process cluster dgram dns readline tls vm zlib assert"

  for imp in $all_imports; do
    [ -z "$imp" ] && continue

    # 내장 모듈 건너뛰기
    local is_builtin=false
    for b in $builtins; do
      if [ "$imp" = "$b" ]; then
        is_builtin=true
        break
      fi
    done
    $is_builtin && continue

    # package.json에 있는지 확인
    if ! grep -q "\"$imp\"" "$pkg" 2>/dev/null; then
      # 루트 node_modules에만 있는지 확인
      if [ -d "$ROOT_DIR/node_modules/$imp" ] && [ ! -d "$workspace_dir/node_modules/$imp" ]; then
        log_fail "$workspace: '$imp' -> 루트에만 호이스팅됨 (Docker에서 실패)"
        log_info "  해결: cd $workspace && npm install $imp"
      fi
    fi
  done
}

if [ "$TARGET" = "api" ] || [ "$TARGET" = "all" ]; then
  check_imports_vs_packagejson "api-ventago"
fi
if [ "$TARGET" = "app" ] || [ "$TARGET" = "all" ]; then
  check_imports_vs_packagejson "ventago-app"
fi
echo ""

# ─── 2. TypeScript 컴파일 체크 ───
echo "--- 2. TypeScript 컴파일 점검 ---"

if [ "$TARGET" = "api" ] || [ "$TARGET" = "all" ]; then
  echo "  [api-ventago] tsc --noEmit..."
  if (cd "$ROOT_DIR/api-ventago" && npx tsc --noEmit 2>&1); then
    log_pass "api-ventago TypeScript 컴파일 OK"
  else
    log_fail "api-ventago TypeScript 컴파일 에러"
  fi
fi

if [ "$TARGET" = "app" ] || [ "$TARGET" = "all" ]; then
  echo "  [ventago-app] tsc --noEmit..."
  if (cd "$ROOT_DIR/ventago-app" && npx tsc --noEmit 2>&1); then
    log_pass "ventago-app TypeScript 컴파일 OK"
  else
    log_fail "ventago-app TypeScript 컴파일 에러"
  fi
fi
echo ""

# ─── 3. ESLint 점검 ───
echo "--- 3. ESLint 점검 ---"

if [ "$TARGET" = "api" ] || [ "$TARGET" = "all" ]; then
  if (cd "$ROOT_DIR/api-ventago" && npx eslint "src/**/*.ts" --quiet 2>&1); then
    log_pass "api-ventago ESLint OK"
  else
    log_fail "api-ventago ESLint 에러"
  fi
fi

if [ "$TARGET" = "app" ] || [ "$TARGET" = "all" ]; then
  if (cd "$ROOT_DIR/ventago-app" && npx eslint "src/**/*.{ts,tsx}" --quiet 2>&1); then
    log_pass "ventago-app ESLint OK"
  else
    log_fail "ventago-app ESLint 에러"
  fi
fi
echo ""

# ─── 4. 빌드 테스트 ───
echo "--- 4. 빌드 테스트 ---"

if [ "$TARGET" = "api" ] || [ "$TARGET" = "all" ]; then
  echo "  [api-ventago] nest build..."
  if (cd "$ROOT_DIR/api-ventago" && npx nest build 2>&1); then
    log_pass "api-ventago 빌드 OK"
  else
    log_fail "api-ventago 빌드 실패"
  fi
fi

if [ "$TARGET" = "app" ] || [ "$TARGET" = "all" ]; then
  echo "  [ventago-app] next build..."
  if (cd "$ROOT_DIR/ventago-app" && npx next build 2>&1); then
    log_pass "ventago-app 빌드 OK"
  else
    log_fail "ventago-app 빌드 실패"
  fi
fi
echo ""

# ─── 5. @types 패키지 누락 점검 ───
echo "--- 5. @types 패키지 점검 ---"

check_missing_types() {
  local workspace=$1
  local pkg="$ROOT_DIR/$workspace/package.json"

  # dependencies에서 타입이 필요한 패키지 확인
  local deps
  deps=$(node -e "
    const pkg = require('$pkg');
    const deps = Object.keys(pkg.dependencies || {}).filter(d => !d.startsWith('@'));
    const devDeps = Object.keys(pkg.devDependencies || {});
    for (const d of deps) {
      const typePkg = '@types/' + d;
      if (!devDeps.includes(typePkg) && !Object.keys(pkg.dependencies || {}).includes(typePkg)) {
        try {
          require.resolve(typePkg + '/package.json', { paths: ['$ROOT_DIR/node_modules'] });
          // 루트에만 있고 workspace package.json에 없음
          console.log(d);
        } catch(e) {}
      }
    }
  " 2>/dev/null || true)

  for dep in $deps; do
    [ -z "$dep" ] && continue
    log_warn "$workspace: '@types/$dep' 루트에만 있음 - devDependencies에 추가 권장"
  done
}

if [ "$TARGET" = "api" ] || [ "$TARGET" = "all" ]; then
  check_missing_types "api-ventago"
fi
if [ "$TARGET" = "app" ] || [ "$TARGET" = "all" ]; then
  check_missing_types "ventago-app"
fi
echo ""

# ─── 결과 요약 ───
echo "========================================"
if [ $ERRORS -eq 0 ]; then
  echo -e "${GREEN} 점검 완료: 에러 0개, 경고 ${WARNINGS}개${NC}"
  echo " 배포 가능합니다."
  exit 0
else
  echo -e "${RED} 점검 완료: 에러 ${ERRORS}개, 경고 ${WARNINGS}개${NC}"
  echo " 에러를 수정한 후 배포하세요."
  exit 1
fi
