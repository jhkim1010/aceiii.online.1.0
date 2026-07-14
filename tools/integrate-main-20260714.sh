#!/bin/bash
# 2026-07-14 전체 main 통합 — ventago-app(변경 lint 후 커밋) + 루트(gitlink 포함) push
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "════ ventago-app ════"
cd "$ROOT/ventago-app"
rm -f .git/index.lock .git/HEAD.lock .git/next-index-*.lock 2>/dev/null || true

# 변경 파일 lint 게이트 (실패 시 push 없이 중단 — 프론트 빌드 보호)
npx eslint \
  src/views/talleres/drawers/IngresoStockDialog.tsx \
  src/views/talleres/drawers/LoteDetailDrawer.tsx \
  src/views/talleres/envios/RecepcionFormDialog.tsx \
  src/views/talleres/tabs/EnviosTab.tsx \
  "src/views/homes/components/ProductList/ProductList.tsx" \
  && echo "LINT_OK"

git add -A
git -c user.name=Marcos.J.Kim -c user.email=junghokim10@gmail.com commit -m "feat(talleres): 완제품 입고 다이얼로그(창고/매장 선택) + 진행분 통합

- IngresoStockDialog: 대상 지점(Depósito/local) 선택 → /talleres/lotes/:id/ingreso-stock
- LoteDetailDrawer: 'Ingresar a stock' 버튼
- ProductList/EnviosTab/RecepcionFormDialog 진행분 포함

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01JX4xRJVBifRiMweJxdsiQM" || echo "(커밋 변경 없음)"
git push origin main

echo "════ root ════"
cd "$ROOT"
rm -f .git/index.lock .git/HEAD.lock .git/next-index-*.lock 2>/dev/null || true
git add -A
git -c user.name=Marcos.J.Kim -c user.email=junghokim10@gmail.com commit -m "chore: 판매원앱 암호 로그인·운영 URL 기본값·keychain 픽스 + repo 분리 도구 + gitlink 갱신

- mobile-sales-app: CONTRASEÑA 로그인, BASE_URL 기본=운영, usesDataProtectionKeychain:false
- scripts: split/sync-mobile-sales-app.sh, agent-runner-jobs(판매원앱 빌드/실행/APK)
- docs: mobile-sales-app-repo-split.md, .gsd 스펙 2건
- api-ventago/ventago-app gitlink 갱신

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01JX4xRJVBifRiMweJxdsiQM" || echo "(커밋 변경 없음)"
git push origin main

echo "== 전체 통합 완료 =="
git log --oneline -2
