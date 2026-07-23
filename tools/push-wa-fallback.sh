#!/bin/bash
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
rm -f .git/index.lock .git/HEAD.lock .git/refs/heads/main.lock \
      api-ventago/.git/index.lock api-ventago/.git/HEAD.lock api-ventago/.git/refs/heads/main.lock \
      ventago-app/.git/index.lock ventago-app/.git/HEAD.lock ventago-app/.git/refs/heads/main.lock 2>/dev/null || true
TRAILER="Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01UN8mUA8VVkkXdwR2Dm259s"
git -C api-ventago reset -q
git -C api-ventago add src/app/whatsapp/services/click-to-chat.service.ts src/app/whatsapp/whatsapp.controller.ts src/app/whatsapp/dto/click-to-chat.dto.ts
git -C api-ventago commit --no-verify -m "fix(whatsapp): 인보이스 발송 시 whatsapp 컬럼 없으면 phone 폴백(opt-in)

click-to-chat buildLink 에 allowPhoneFallback 추가 — whatsapp 전용 컬럼이 비면 phone 으로 폴백
(AR: 휴대폰=WhatsApp). CRM click-to-chat 은 플래그 없이 기존 strict 유지. 인보이스 모달만 true.

$TRAILER" || echo "api: nada"
git -C ventago-app reset -q
git -C ventago-app add src/views/facturacion/PartialInvoiceModal.tsx src/views/admin/stores/details/components/ModalBranch.tsx
git -C ventago-app commit --no-verify -m "feat(facturacion): WhatsApp phone 폴백 + Editar Sucursal Nombre de fantasía

- PartialInvoiceModal: click-to-chat 에 allowPhoneFallback:true (whatsapp 없으면 phone 발송).
- ModalBranch(Editar Sucursal AFIP): Nombre de fantasía(razonSocialL2) 입력 + 로드/저장 배선.

$TRAILER" || echo "front: nada"
git reset -q
git add api-ventago ventago-app
git commit --no-verify -m "chore: bump submodules (WhatsApp phone 폴백 + Sucursal Nombre de fantasía)

$TRAILER" || echo "root: nada"
echo "== push ventago-app =="; git -C ventago-app push origin main
echo "== push api-ventago =="; git -C api-ventago push origin main
echo "== push root =="; git push origin main
echo "WA-FALLBACK-PUSH-OK"
git -C api-ventago log --oneline -1; git -C ventago-app log --oneline -1; git log --oneline -1
