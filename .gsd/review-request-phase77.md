# 교차 검토 요청 — Phase 77: Solicitudes Internas

당신은 이 저장소(Ventago POS/ERP, NestJS + Sequelize + PostgreSQL 18 + Next.js 13)의
시니어 리뷰어입니다. 아래 계획을 **비판적으로** 검토해 주세요.

## 읽어야 할 파일

1. `.gsd/spec-phase77-solicitudes-internas.md` — 이번 Phase 계획서 (검토 대상)
2. `docs/solicitudes-internas-spec.md` — 설계 문서 (DB 스키마 · API · 프론트)
3. `mockups/solicitudes-internas-mockup.html` — UI 목업 (단일 페이지, 역할 2종)
4. `CLAUDE.md` — 프로젝트 규약 (특히 「쓰기 경로 규약 (Phase 64)」, 「성능 최적화 규약」)
5. `.planning/intel/db-schema-tables.md` / `db-schema-fks.md` — 실제 스키마 (199 테이블)

## 배경 요약

매장 직원이 고장난 장비(PC·프린터·스캐너) 수리를 의뢰하고 필요한 물품을 요청하는 기능.
Telegram 단방향 알림 + DB 기록 + 승인 단계. 사이드바 메뉴 1개, **서브메뉴 없는 단일 페이지** `/solicitudes`.
매장 admin 과 superadmin 이 같은 URL에서 다른 내용을 본다.

신규 테이블 8개: `internal_assets`, `internal_requests`, `internal_request_events`,
`internal_request_attachments`, `internal_request_items`, `internal_supplies`,
`internal_supply_stocks`, `internal_supply_movements`.

---

## 특별히 판단을 구하는 쟁점 8건

계획서를 쓰면서 확신이 서지 않았거나, 기존 코드베이스와 충돌할 소지가 있다고 본 지점입니다.
**동의/반대를 분명히 하고 근거를 코드로 지목해 주세요.**

### Q1. `sync_outbox` 를 안 쓰는 게 맞는가 (가장 중요)

`CLAUDE.md` 「쓰기 경로 규약」은 이렇게 말합니다:

> 트랜잭션 안 외부 I/O 금지 — 반드시 일어나야 하는 후속 작업은 같은 트랜잭션에서
> `sync_outbox` 에 INSERT 하고 워커가 집행한다.

저장소에는 이미 `api-ventago/src/app/integrations/core/outbox.service.ts` 와
`sync-orchestrator.service.ts` 가 있습니다.

현재 계획은 **커밋 후 `notifyTelegram()` fire-and-forget** 입니다.
즉 커밋 직후 프로세스가 죽으면 알림이 유실됩니다.

- 수리 의뢰 알림은 "반드시 일어나야 하는 후속 작업"인가, 아니면 유실을 감수해도 되는 부가 알림인가?
- outbox 를 쓴다면 기존 `OutboxService` 의 이벤트 타입 체계에 `solicitud.*` 를 얹는 게 자연스러운가,
  아니면 그 outbox 는 커머스 연동 전용이라 오염시키면 안 되는가?
- 절충안(중요 알림만 outbox, 나머지는 fire-and-forget)이 오히려 두 경로를 만들어 나쁜가?

### Q2. 승인 시스템 — 부분 재사용(D2-a) vs 전면 재사용(D2-b)

`approval_thresholds` / `approval_requests` 테이블과 `ApprovalService`(Phase 29,
`api-ventago/src/app/permissions/approval.service.ts`)가 이미 존재합니다.
`checkThreshold()` / `createRequest()` / `approve()` / `reject()` / socket 푸시 + `audit_log` 까지 구현돼 있고,
프론트에 `ThresholdEditor.tsx` 와 `useApprovalQueue.ts` 도 있습니다.

계획은 **D2-a: `approval_thresholds` 만 재사용**하고 승인/거절은 `internal_requests.status` 자체 전이로 처리입니다.
이유는 상태가 두 테이블로 갈라지는 걸 피하기 위함이고, `approval_requests.expires_at`(24시간 만료)이
수리 의뢰의 수명과 맞지 않는다고 봤습니다.

- 이 판단이 맞습니까? `ApprovalService` 를 우회하면 **audit_log 기록과 socket 푸시를 잃는데**,
  그 손실이 계획서에 반영돼 있지 않습니다. 이게 치명적입니까?
- 전면 재사용(D2-b)으로 갔을 때 상태 불일치를 막는 실용적 패턴이 이 코드베이스에 이미 있습니까?

### Q3. 소모품 잔량 — 애플리케이션 갱신 vs DB 트리거

`internal_supply_stocks`(잔량 캐시) + `internal_supply_movements`(append-only 원장) 구조입니다.
계획은 **같은 트랜잭션에서 애플리케이션이 둘 다 갱신**하고, `v_internal_supply_drift` 뷰로 사후 대조합니다.

그런데 이 저장소의 상품 재고는 다른 방식입니다:
`trg_stocks_immutable`(원장 불변 강제) + `trg_stock_balances_apply`(트리거가 잔액 반영).
즉 **DB 가 강제**하고 애플리케이션은 원장만 씁니다.

- 소모품도 같은 트리거 방식으로 가야 합니까? 아니면 규모(매장 4개, 품목 수십)를 감안하면 과합니까?
- 애플리케이션 갱신을 택할 경우, drift 뷰만으로 충분합니까 아니면 최소한
  `internal_supply_movements` 에 immutable 트리거는 걸어야 합니까?
- Phase 70-06 에서 `trg_stocks_sync_product_cache` 를 **폐기**한 이력이 있습니다(부모행 잠금 제거).
  그 교훈이 여기에도 적용됩니까?

### Q4. 부트스트랩 엔드포인트 `GET /internal-requests/page` 가 안티패턴인가

단일 페이지가 KPI + 목록(상세 선적재) + 우측 레일(장비/소모품 or 소진랭킹) 4덩어리를 필요로 합니다.
pool 절약을 위해 **하나의 엔드포인트로 묶고** 목록 응답에 events/items/asset 요약까지 실었습니다.

- 이게 SWR 의 캐시 세분화 이점을 버리는 대가로 정당합니까?
- 응답 크기(pageSize 25 × events 포함)가 실제로 문제될 수준입니까?
- 이 저장소에 유사한 "페이지 부트스트랩" 선례가 있습니까? 있다면 그 형태를 따라야 합니다.
- 반대로, `Promise.all` 로 3~4개 엔드포인트를 병렬 호출하는 게 pool 관점에서 실질적으로 더 나쁩니까?
  (워커당 max=20, PM2 4워커, pgbouncer pool_size=50 환경)

### Q5. 멱등성 — 장바구니 다품목 POST

`POST /internal-requests` 에 `items[]` 를 담아 다품목 구매 요청 1건을 만듭니다.
저장소에는 이미 `sale-idempotency.service.ts` / `sale-idempotency.model.ts` 와
`Idempotency-Key` 헤더 처리(sales.controller.ts)가 있습니다.

- 판매만큼 중요하진 않지만, 네트워크 재시도로 **같은 장바구니가 2건 생기는** 문제는 실제로 발생합니다.
  기존 idempotency 인프라를 재사용해야 합니까, 아니면 과잉입니까?
- 재사용한다면 `sale_idempotency` 테이블을 일반화해야 합니까, 별도 테이블이 맞습니까?

### Q6. 자산 자동 시드의 정확성

`terminals` 에 `branch_id` 가 없어 `terminals.box_id → boxes.branch_id` 로 지점을 유도합니다.
`branch_agents` 는 `branch_id` 직접 FK 입니다.

- 이 경로가 맞습니까? `boxes.is_deleted` / `terminals.is_deleted` 처리를 빠뜨리지 않았습니까?
- 자동 생성한 자산 코드가 나중에 사용자 수정과 충돌할 여지는? (`UNIQUE (store_id, code)`)
- 애초에 `terminals` 를 자산으로 취급하는 게 개념적으로 맞습니까?
  터미널은 논리적 POS 단위이고 물리 PC 와 1:1 이 아닐 수 있습니다.

### Q7. 단일 페이지 역할 분기의 보안

같은 URL 에서 서버가 `role: 'store' | 'super'` 를 내려주고 프론트가 그에 따라 렌더합니다.

- 매장 admin 이 `GET /internal-requests/page?storeId=<타매장>` 을 직접 호출했을 때
  차단이 보장됩니까? `installTenantGuard`(Phase 67 `common/tenant/tenant-hooks.ts`)가
  신규 모델에도 자동 적용되는지 확인해 주세요.
- superadmin 판정을 서버가 payload 로 내려주는 설계인데, `isSuperAdminUser` 유틸과
  일관되게 쓰이고 있습니까?

### Q8. 누락된 것

계획서에 **없지만 있어야 하는 것**을 지적해 주세요. 후보:

- `audit_log` 기록 (승인/거절은 감사 대상 아닌가?)
- 첨부파일 MinIO 삭제 정책 (요청 삭제 시 orphan 파일)
- `internal_requests` 소프트 삭제 / 취소 후 복구
- 다국어 (i18n 키 — 이 프로젝트는 스페인어 UI + i18n 키 체계 사용)
- 권한(CASL `action`/`subject`) 정의 — 목록/승인/자산등록 각각
- 저재고 cron 이 매장별 `telegram_chat_id` 미설정 시 전역 채널로 새는 문제
- 테스트 (이 저장소의 `*.spec.ts` 관행)

---

## 출력 형식

```markdown
## 총평
[3~5문장. 이 계획을 그대로 실행해도 되는가?]

## 반드시 고쳐야 할 것 (Blocker)
- [ ] [항목] — 근거: [파일:라인] — 제안: [구체적 대안]

## 고치는 게 좋은 것 (Should)
- [ ] ...

## 쟁점 8건에 대한 답
| # | 내 판단 | 근거 | 계획 수정 필요 |
|---|---|---|---|
| Q1 | ... | ... | 예/아니오 |
...

## 계획에 없지만 필요한 태스크
- TASK-NN: ...

## 과하다고 보는 것 (제거 권장)
- ...
```

**추측하지 말고 파일을 읽고 답해 주세요.** 근거가 없으면 "확인 불가"라고 쓰십시오.
칭찬은 생략하고 문제만 지적하십시오.
