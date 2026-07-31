# Phase 69 — CONTEXT: 테넌트 격리 잔여 구멍 봉쇄

**작성:** 2026-07-31
**근거:** `69-REVIEW-SOURCE.md` (외부 AI 테넌트 보안 리뷰, 대상 `api-ventago@81474ab`)
**선행 Phase:** 67(절대 격리 훅) · 67-B(store_id NULL 탈출구) · 67-C(superadmin 대행) · 68(파생 스코프 observe)
**성격:** 신규 기능 0 — 전부 무회귀 보안 교정

---

## 왜 이 Phase 가 필요한가

Phase 67/68 은 **`store_id` 컬럼을 가진 모델**에 대해 Sequelize 훅으로 하드 블록을 걸었다. 그러나 세 부류가 그 그물 밖에 남아 있다:

1. **HTTP 요청이 아닌 경로** — Socket.io 공용 게이트웨이는 TenantContext 자체가 없다.
2. **`store_id` 없는 관계 모델** — Phase 68 이 등록했지만 기본 모드가 `observe`(로그만)라 실제 차단하지 않는다.
3. **자체 인증 서브시스템** — vendor-portal 은 별도 JWT 전략을 쓰며 매장 경계를 토큰에 담지 않는다.

리뷰가 제기한 5건을 **전부 코드에서 직접 확인**했다. 추정 아님 — 아래 증거는 실제 파일·라인이다.

---

## 확인된 결함 (5건, 전부 코드 대조 완료)

### R1 (CR-01) — `/realtime` 게이트웨이 무인증 room 가입

**증거 — `src/common/socket/websocket.gateway.ts`**
- `L25-27` `handleConnection` 이 JWT/API key 검증 없이 `welcome` 만 emit.
- `L54-57` `register_user` 가 클라이언트가 보낸 `userId`, `storeId` 를 그대로 `registerUser` 로 전달.
- `L67-69` `register_terminal` 이 `data.terminalId` 를 소유권 조회 없이 등록.
- `L79-81` `register_branch` 가 `data.branchId` 를 소유권 조회 없이 등록.
- `L34-35` `register_api_key` 가 key 존재/활성 검증 없이 `registerClient` 호출.

**노출 데이터:** 팀 채팅 본문·발신자(`team-chat.service.ts`), MP 결제 승인 `intentId`/`paymentId`/금액/판매ID(`mp-webhook.service.ts`), 매장 공지(`admin-console.service.ts`), 프린터 상태.

**전제 조건:** 인증 불요. ID 는 순차 정수라 열거 가능. `ws-cors.ts` 는 Origin 없는 네이티브 연결을 허용하므로 CORS 는 방어가 아니다.

**수정 방향:** handshake JWT 검증 → 서버가 토큰에서 `userId/storeId` 파생(클라이언트 값 폐기) → terminal/branch 는 DB 에서 `storeId` 일치 확인 후에만 join → room 전환 시 이전 room leave. 기존 `online-orders-board.gateway.ts` / `restaurant-delivery.gateway.ts` 의 JWT+지점 소유권 패턴을 이식한다.

### R2 (CR-02) — `correct-today` 가 타 매장 ProductBranch 원장을 변경

**증거**
- `products.controller.ts:820-825` — `assertProductInStore(parentId, ...)` 로 **URL 의 부모 상품만** 검증.
- `products.controller.ts:826-833` — body 의 `branchIds` / `items[].variantId` 는 검증 없이 서비스로 전달.
- `productStock.service.ts:463-466` — 서비스도 `parentId` 만 조회하고 `parent.storeId` 를 이후 비교에 쓰지 않음.
- `productStock.service.ts:477-483` — `ProductBranch.findAll({ where: { productId: IN variantIds, branchId: IN branchIds }})` — storeId JOIN 없음.
- `tenant-scope.registry.ts:91` — ProductBranch 는 파생 스코프 대상이나, `L122-127` 기본 모드가 `observe` 라 JOIN 미주입.
- `productStock.service.ts:505-510` 이후 — 선택된 ProductBranch 의 원장을 읽고 절대재고 차이만큼 `Stocks` 보정 행 생성.

**결과:** 매장 A 사용자가 자기 부모 상품 ID + 매장 B 의 `variantId`/`branchId` 조합으로 **B 의 재고 원장에 조정 행을 만든다.** DB 교차 FK 트리거는 "B 상품 ↔ B 지점" 관계가 내부적으로 정합하므로 차단하지 못한다.

**수정 방향:** `branchIds` 를 `Branch.findAll({where:{id, storeId: requesterStoreId}})` 로 전량 검증 · `variantId` 가 `parentId` 의 자식이며 동일 storeId 인지 검증 · ProductBranch 조회에 `Product{required, where:{storeId}}` + `Branch{required, where:{storeId}}` 동시 강제 · 검증과 원장 생성을 한 트랜잭션에.

### R3 (CR-03) — 동일 전화번호 벤더의 PIN 1개로 타 매장 벤더 권한 획득

**증거 — `vendor-portal/vendor-auth/vendor-auth.service.ts`**
- `L18-26` `Vendor.findAll({where:{phone, isActive:true}})` — 매장 구분 없이 전체 조회.
- `L34-42` `vendors[0].pinHash` **하나만** bcrypt 검증.
- `L45-49` 검증되지 않은 나머지 매장 vendor 를 포함해 `vendorIds: vendors.map(v=>v.id)` 를 토큰에 발급.
- `vendor-jwt.strategy.ts:24-39` — 매 요청마다 phone 으로 전체 vendor 재조회, 토큰의 `vendorIds` 조차 상한으로 쓰지 않음.
- 이 합쳐진 vendorIds 를 `vendor-envios` / `vendor-settlements` / `vendor-notifications` 가 권한으로 사용(알림은 변경까지 허용).

**결과:** 매장별로 **독립적으로 PIN 을 발급했더라도** 한 매장 PIN 만 알면 같은 전화번호로 등록된 다른 매장의 배송·정산·수령·알림에 접근·변경할 수 있다.

**수정 방향:** 로그인 입력에 `storeId`(또는 `vendorId`) 요구 → `{phone, storeId}` 단일 행의 PIN 만 검증 → 토큰에 단일 `vendorId/storeId` → strategy 가 정확히 그 행만 복원. 멀티스토어 전환이 필요하면 `VendorIdentity` + 매장별 membership 으로 모델을 분리한다. **마이그레이션 전 `phone` 동일 + `pinHash` 상이 조합을 먼저 탐지**해 계정 병합 여부를 매장에 확인한다(되돌리기 어려운 작업).

### R4 (WR-01) — Phase 68 파생 격리가 기본 `observe` 라 방어막이 아님

**증거**
- `tenant-scope.registry.ts:89-103` — 등록 모델이 `ProductBranch` / `Stocks` / `Price` **3개뿐**.
- `tenant-scope.registry.ts:113-127` — `resolveDerivedMode()` 기본값 `observe`.
- `tenant-hooks.ts:262-277` — observe 모드는 로그만 남기고 쿼리를 그대로 실행.

**결과:** 이 3개 모델을 **주 모델로** 조회하는 모든 호출부가 각자 부모 소유권을 검증해야만 안전한데, R2 가 그 가정이 이미 깨진 실증 사례다. 레지스트리에 없는 다른 `store_id` 미보유 관계 모델은 관측 로그조차 없다.

**수정 방향:** DB FK 그래프(`.planning/intel/db-schema-fks.md`) 기준으로 파생 대상 목록을 반자동 생성 → observe 로그에 걸린 호출부 전량 정리 → `TENANT_DERIVED_MODE=enforce` 를 운영 기본값으로 승격. `ProductBranch` 는 Product·Branch **양쪽** 소유권을 검증한다.

### R5 (WR-02) — TenantContext 확정 실패가 fail-open

**증거 — `auth/guards/jwt-global.guard.ts:53-82`**
- 인증 후 `TenantContext.resolve(...)` 블록 전체가 `try { … } catch {}` 로 감싸여 있고, 주석은 "컨텍스트 확정 실패가 인증 결과를 바꾸지 않는다 (격리는 미해석=no-op 로 폴백)".

**결과:** 예외 발생 시 `resolved=false` 가 유지되고 **모든 Sequelize 격리 훅이 no-op** 이 된 채 요청이 통과한다. 현재 `resolve` 가 일반적으로 throw 하지 않는다는 것에 의존하는 구조 — 보안 경계의 실패 정책이 명시적으로 fail-open 이다.

**수정 방향:** 일반 인증 요청에서 확정 실패는 403/500 으로 종료 + 보안 로그. 공개/시스템 경로만 명시적 no-op 유지. 최소한 catch 에서 `TenantContext.get()?.resolved` 를 검사해 미확정 인증 요청을 거부한다.

---

## 리뷰가 확인한 기존 방어 (재작업 금지)

- reports 컨트롤러 84 라우트: raw SQL 진입 전 `scopedQuery`/`resolveScopedStoreId` 관문 85회 통과. 일반 사용자의 타 `query.storeId` 는 403.
- MercadoPago webhook: 공개 query 의 `accountId` 를 MP API 로 재조회하고 intent 의 `mpAccountId` 일치를 확인한 뒤 반영 — 교차매장 사슬 미발견.
- 공개 shop catalog/checkout/try-on: 요청 storeId + product storeId 동시 조건.
- 조사 범위의 캐시 키(dashboard/catalog/reference/subcon)는 storeId 또는 branchId 포함 — 재현 가능한 교차매장 충돌 미발견.

---

## 범위 밖 (명시)

- **RLS 도입** — `docs/db-risk-analysis-20260727.md:105` 에서 기각(pgbouncer transaction pooling 에서 세션변수 RLS 는 오히려 누출 위험).
- **복합 FK `(id, store_id)` 전면 도입** — Phase 65 와 동일 사유로 범위 과대.
- **vendor 멀티스토어 UX 재설계** — R3 은 경계 봉쇄까지. 통합 identity 모델은 별도 Phase.
- **인증 체계 전면 교체(SSO/MFA)**.

---

## Success Criteria (무엇이 참이어야 하는가)

- 인증 없는 소켓이 `user:*` / `store:*` / `terminal:*` / `branch:*` room 에 가입 불가 — 회귀 테스트로 고정.
- 토큰 매장 ≠ 대상 terminal/branch 매장이면 join 거부.
- `correct-today` 에 타 매장 `branchId`/`variantId` 를 넣으면 403 이며 `Stocks` 행이 **생성되지 않음**.
- 벤더 토큰이 단일 `vendorId/storeId` scope — 타 매장 envíos/settlements/notifications 접근 403.
- 동일 phone·상이 pinHash 조합 사전 조사 결과가 문서화되고 매장 확인을 거침.
- `TENANT_DERIVED_MODE=enforce` 운영 기본값 + observe 로그 잔여 0.
- TenantContext 미확정 인증 요청 통과 0건(fail-closed) + 보안 로그 발생.
- Phase 64 동시성 스위트 8종 및 기존 회귀 통과 유지 — 무회귀.

---

## Waves (제안)

| Wave | 내용 | 의존 |
|---|---|---|
| W1 | R1 `/realtime` handshake 인증 + room 소유권 검증 + 이전 room leave | — (즉시, 최우선) |
| W2 | R2 `correct-today` branch/variant 소유권 검증 + 단일 트랜잭션 | — |
| W3 | R3 vendor 토큰 단일 store scope + 사전 조사(동일 phone·상이 PIN) | — |
| W4 | R4 파생 모델 목록 확장 + observe 호출부 정리 → enforce 승격 | W2 |
| W5 | R5 TenantContext fail-closed 전환 | W4 |
| W6 | 교차매장 회귀 테스트 스위트 + 운영 배포 + UAT | W1~W5 |

W1·W2·W3 병렬 → W4 → W5 → W6.

**되돌리기 어려운 작업(사전 측정 → 승인 → 실행):** W3 벤더 계정 분리/병합 · W4 enforce 승격(회귀 위험).
