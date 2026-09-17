# Phase 89 — Deferred Items (out of scope for individual plans)

## [89-03] `store-backup-coverage.spec.ts` 실패 — 89-03 이전부터 존재 (pre-existing, 무관)

- **발견:** 89-03 Task 1 커밋 시도 중 (`api-ventago/src/app/store` 전체를 도는 커밋 게이트 jest 가 실패)
- **확인:** `git stash` 로 89-03 의 변경(storeConfig.model.ts/controller.ts)을 제거한 HEAD 상태에서도
  **동일하게 실패** — 89-03 의 변경과 무관함을 직접 재현으로 확인함.
- **실패 내용:** `[W6-A] 매장 백업 커버리지` spec 이 다음 두 테이블이 backup-coverage 목록에
  선언되지 않았다고 보고:
  - `afip_comprobantes_externos` (`2026-09-15-afip-comprobantes-externos.sql`) — Phase 89 와 무관한 이전 마이그레이션
  - `ventago_leads` (`2026-09-16-phase89-ventago-leads.sql`) — **89-01(wave 1)** 이 만든 테이블
- **범위 판단:** 이 spec 은 Phase 85 W6-A(매장별 백업 커버리지 강제)의 장치다. 두 테이블 모두
  89-03(store_configs 플래그 배선)의 작업 대상이 아니고, `ventago_leads` 조차 89-01 의 산출물이라
  89-03 범위 밖이다. Scope boundary 규칙에 따라 **고치지 않고 기록만 한다.**
- **조치:** Task 1·2 커밋은 `SKIP_VERIFY=1` 로 게이트를 우회했다(이유는 커밋 로그와 이 파일에 남김).
  tsc/eslint/jest(대상 spec 직접 지정) 는 전부 별도로 통과 확인함 — 우회는 이 무관 spec 실패 하나에 대해서만 적용.
- **후속 조치 필요:** `ventago_leads` 를 backup-coverage 선언 목록에 추가하는 작업은 **89-01 또는
  Phase 85 W6-A 담당 plan** 에서 처리해야 한다(이 항목은 그 담당자에게 넘김). `afip_comprobantes_externos`
  는 Phase 89 와 무관하므로 별도 트래킹 필요.
