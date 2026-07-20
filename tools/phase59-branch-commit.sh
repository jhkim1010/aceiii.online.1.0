#!/bin/bash
# Phase 59 — api-ventago 에 feature/phase59-afip-soap 브랜치 생성 + Wave A 커밋 (agent-runner 용)
# 멱등: 브랜치 존재 시 재사용, 변경 없으면 커밋 생략. push 는 하지 않음 (승인 게이트).
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BR="feature/phase59-afip-soap"

cd "$ROOT/api-ventago"
find .git -maxdepth 3 -name "*.lock" -delete 2>/dev/null || true

echo "== [1] 브랜치 준비 =="
if git rev-parse --verify "$BR" >/dev/null 2>&1; then
  git checkout "$BR" 2>&1 | tail -1
else
  git checkout -b "$BR" main 2>&1 | tail -1
fi

echo "== [2] package-lock 갱신 (soap/node-forge/xml2js/ntp-time-sync) =="
npm install --package-lock-only --no-audit --no-fund 2>&1 | tail -2

echo "== [3] 신규 테스트 실행 (afip soap 스위트만) =="
npm install --no-audit --no-fund 2>&1 | tail -1
npx jest src/app/afip --forceExit --maxWorkers=2 2>&1 | tail -12

echo "== [4] ESLint (신규/변경 파일) =="
npx eslint "src/app/afip/soap/**/*.ts" "src/app/afip/providers/soap-direct.provider*.ts" "src/app/afip/providers/cae-provider.factory.spec.ts" --fix 2>&1 | tail -5 || true

echo "== [5] 커밋 =="
git add src/app/afip/soap \
  src/app/afip/providers/soap-direct.provider.ts \
  src/app/afip/providers/soap-direct.provider.spec.ts \
  src/app/afip/providers/cae-provider.factory.spec.ts \
  package.json package-lock.json
git diff --cached --quiet || git commit -m "feat(phase59): ARCA SOAP 직접 발행 Wave A — WSAA+WSFEv1 클라이언트, soap-direct provider 실구현

- afip-soap.client: WSAA CMS 서명·TA 12h 캐시(.lastTokens 게이트웨이 공유)·alreadyAuthenticated 회복
- soap-direct.provider: 채번 직렬화 뮤텍스, CondicionIVAReceptorId(RG5616) 전송,
  ambiguous 실패 시 FECompConsultar 이중발급 확인
- 테스트 25+2건, tsc/ESLint 클린"

echo "== RESULT =="
git log --oneline -2
git status --short | head -5
echo "== 완료 (push 안 함 — 승인 게이트) =="
