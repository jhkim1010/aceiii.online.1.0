Ventago(NestJS 11 + Sequelize + PG18 · pm2 4워커 cluster · pgbouncer transaction mode / Next.js 13 Pages Router).
아래 4개 문서는 **아직 구현하지 않은 계획**이다. 코드를 읽고 **계획의 결함만** 짚어라.
한국어로 P1/P2/P3 분류. 칭찬·요약 불필요. 이미 반영된 지적은 다시 말하지 마라(88-FINDINGS.md 참조).

읽을 것:
  .planning/phases/88-store-onboarding-setup-guide/88-SPEC.md      (v3)
  .planning/phases/88-store-onboarding-setup-guide/88-01-PLAN.md   (v2 — W1 구현 계획)
  .planning/phases/88-store-onboarding-setup-guide/88-FINDINGS.md  (이미 잡은 결함 20건)
  .planning/phases/88-store-onboarding-setup-guide/88-CONTEXT.md   (실측)
관련 코드: api-ventago/src/app/auth/auth.service.ts (me·signIn·provisionStoreAndOwner) ·
  app/store/storeTemplate.service.ts · common/cache/memory-cache.service.ts ·
  common/migrations/migration-conventions.spec.ts · database/database.module.ts · CLAUDE.md

특히 이 5가지에 대한 독립 판단을 원한다:

1. **술어 설계.** 완료를 저장하지 않고 실데이터에서 파생한다(Shopify/Stripe 모델).
   시드와 사용자 조작을 「시드 상수 대조」로 구분한다(시각 비교는 이미 폐기했다).
   이 코드베이스에서 이 판정이 무너지는 경로가 남아 있는가? 특히 legacy-import(Phase 86),
   매장 복제·이관, 시드 상수가 나중에 바뀌는 경우, 다지점 매장.

2. **CASE 단락.** 술어 쿼리가 `FROM stores s` 로 시작해
   `CASE WHEN s.setup_hidden_at IS NOT NULL THEN NULL ELSE EXISTS(...) END` 로 서브쿼리를 건너뛴다.
   PostgreSQL 18 플래너가 이 EXISTS 를 pull-up/사전평가해서 **단락이 실제로는 안 되는** 경우가 있는가?
   있다면 숨긴 매장(=운영 전 매장)이 매 로그인마다 5개 EXISTS 를 무는가?

3. **왕복 설계.** `/auth/me`(부팅 1회)에는 요약만 얹고, 상세·갱신은 `GET /setup-guide`(홈에서 SWR dedupe 10초).
   pool max=20/워커 × pm2 4워커 = 80, pgbouncer pool_size=50, 「사이드바 클릭 P95 ≤ 300ms」 규약에서
   이 분리가 맞는 선택인가? 더 나은 배치가 있는가?

4. **동시성.** 「새로 참이 된 단계는 completed 를 1회만 INSERT」를
   `store_setup_steps.completed_at` + `store_setup_events` 의 부분 UNIQUE(`WHERE event='completed'`) +
   `ON CONFLICT DO NOTHING` 으로 막는다. 4워커에서 이것으로 충분한가?
   이 저장소는 카하 세션에서 5ms 차이의 중복 INSERT 를 실제로 겪었다(CLAUDE.md 카하 규칙).

5. **마이그레이션 순서.** `stores.setup_hidden_at` 추가 + 전건 UPDATE 를 운영(5434)에 먼저 적용하고
   **적용 확인 후에만 push**(push=Jenkins=배포)하기로 했다. Sequelize 모델에 속성을 추가하면
   컬럼이 없을 때 `/auth/me` 가 500 이 된다. 이 게이트로 충분한가, 아니면 expand 단계를 더 쪼개야 하는가?

이 저장소에서 반복된 실패 형태를 의심해라:
- 트랜잭션 안에서 인쇄·소켓·HTTP · 커밋 후 단계에서 throw
- 좁히는 필터가 해석 실패 시 전체로 폴백 · 감시·판정이 「부재」에서 침묵
- 같은 상태를 두 곳이 소유해 갈라지는 것 · 멀티테넌트 store_id/지점 경계 누락
- 검사가 구현에서 정답을 가져와 헛통과
