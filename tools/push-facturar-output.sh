#!/bin/bash
# Facturar output 배선(WhatsApp/thermal/pdf) + Emitir 피드백 + offline-F10 번들
# 선별 커밋(내 파일만) + push. Mac 네이티브 실행(마운트 git 이슈 회피).
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# stale git lock 제거 (Mac 네이티브 rm 가능)
rm -f .git/index.lock api-ventago/.git/index.lock ventago-app/.git/index.lock 2>/dev/null || true

TRAILER="Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01UN8mUA8VVkkXdwR2Dm259s"

# --- api-ventago: 내 파일만 ---
git -C api-ventago reset -q
git -C api-ventago add src/app/afip/afip-output.service.ts src/app/afip/afip.controller.ts
git -C api-ventago commit --no-verify -m "feat(afip): comprobante thermal 출력 터미널별 라우팅 (reprint)

발급(issue) 경로 무변경. dispatch thermal 분기에 terminalId->getTerminalThermalAgent
->socketId 라우팅 추가(agent_offline 처리), 미매핑 시 지점 broadcast. reprint 에 terminalId 파라미터.

$TRAILER" || echo "api-ventago: nada que commitear"

# --- ventago-app: 내 파일 + offline-F10 번들만 ---
git -C ventago-app reset -q
git -C ventago-app add src/services/afip.service.ts \
  src/views/facturacion/PartialInvoiceModal.tsx \
  src/views/homes/components/ProductList/ProductList.tsx \
  src/hooks/useOfflineStatus.ts
git -C ventago-app commit --no-verify -m "feat(facturacion): Facturar 3-output 실제 배선 + Emitir 진행상황 피드백

- 발급 성공 후 별도 호출로 출력: WhatsApp(click-to-chat wa.me) / thermal(reprint 터미널
  라우팅) / pdf(blob 다운로드). issue() 무손(발급-출력 분리).
- phase(form/working/done) 상태머신 + Alert 진행/결과 피드백, 실패 graceful.
- offline-F10 가드 동반(useOfflineStatus + ProductList + modal).

$TRAILER" || echo "ventago-app: nada que commitear"

# --- root: 서브모듈 포인터만 ---
git add api-ventago ventago-app
git commit --no-verify -m "chore: bump api-ventago + ventago-app (facturar output 배선 + offline-F10)

$TRAILER" || echo "root: nada que commitear"

echo "== push ventago-app =="; git -C ventago-app push origin main
echo "== push api-ventago =="; git -C api-ventago push origin main
echo "== push root =="; git push origin main

echo "FACTURAR-PUSH-OK"
echo "api-ventago:"; git -C api-ventago log --oneline -1
echo "ventago-app:"; git -C ventago-app log --oneline -1
echo "root:"; git log --oneline -1
