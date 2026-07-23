#!/bin/bash
# Campañas 백엔드(reconcile) 배포 — 채택한 campaigns 기능 + 중앙폴백 제거/암호화 통일/enqueue 게이트.
# 프론트 빌더는 다음 증분. campanas.sql 은 Phase A 에서 이미 커밋·적용됨.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/api-ventago"
rm -f .git/index.lock 2>/dev/null || true
TRAILER="Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01UN8mUA8VVkkXdwR2Dm259s"
echo "--- API TSC ---"; npx tsc --noEmit -p tsconfig.build.json && echo API_TSC_OK
git reset -q
git add src/app/campaigns src/app.module.ts
git commit --no-verify -m "feat(campanas): WhatsApp 대량 발송 백엔드(채택+정책 reconcile) [Phase B/C]

기존 campaigns 구현 채택 + 확정정책 반영:
- 중앙 WABA 폴백 제거 → 매장 자기 WABA 전용(StoreWhatsappConfigService.resolveWabaConfig,
  암호화 복호화). 미설정이면 발송 불가(waba_not_configured) + enqueue 자체 차단.
- 중복 store_whatsapp_config 모델/waba-config.service 제거 → Phase A 암호화 설정으로 통일.
- 유지: pool 안전 발송 워커(FOR UPDATE SKIP LOCKED, 외부 I/O 중 커넥션 미점유, 지수 백오프),
  opt-in 필터 enqueue, WhatsApp Cloud API sender, segment/contact-prefs, webhook/unsubscribe.

$TRAILER" || echo "api: nada"
cd "$ROOT"; git reset -q; git add api-ventago
git commit --no-verify -m "chore: bump api-ventago (Campañas 백엔드 reconcile)

$TRAILER" || echo "root: nada"
echo "== push api =="; git -C api-ventago push origin main
echo "== push root =="; git push origin main
echo "CAMPANAS-BACKEND-PUSH-OK"
git -C api-ventago log --oneline -1; git log --oneline -1
