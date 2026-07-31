# Ventago 테넌트 격리 심층 보안 리뷰

작성: 2026-07-31  
대상: `api-ventago` 현재 HEAD (`81474ab`)  
범위: Phase 67/68 테넌트 훅, 인증/권한 가드, `@Public` 벤더·웹훅, raw Sequelize, ID 기반 소유권 검사, reports/sales/products/production/subcon, WebSocket 및 캐시 키  
결과: **Critical 3 / Warning 2 / Info 0 — issues found**

## 요약

Phase 67의 직접 `store_id` 훅과 reports 관문은 현재 코드에서 광범위하게 적용되어 있다. 그러나 `store_id`가 없는 관계 모델은 Phase 68의 기본값이 `observe`라 실제 차단하지 않으며, HTTP TenantContext와 별개인 공용 Socket.io 게이트웨이는 인증 없이 추측 가능한 room 가입을 허용한다. 또한 벤더 로그인은 전화번호가 같은 여러 매장의 벤더를 한 주체로 합치면서 첫 번째 행의 PIN만 검증한다.

아래 세 경로는 일반 매장 사용자 또는 인터넷 클라이언트가 타 매장 데이터의 기밀성/무결성을 침해할 수 있는 구체적인 호출 사슬이다.

## Critical

### CR-01 — 인증 없는 Socket.io room 가입으로 타 매장 실시간 데이터 구독

**증거**

- `api-ventago/src/common/socket/websocket.gateway.ts:14-17` — `/realtime` namespace가 노출된다.
- `api-ventago/src/common/socket/websocket.gateway.ts:25-27` — 연결 시 JWT/API key 검증 없이 환영 메시지만 보낸다.
- `api-ventago/src/common/socket/websocket.gateway.ts:49-57` — 클라이언트가 보낸 `userId`, `storeId`를 그대로 `registerUser`에 전달한다.
- `api-ventago/src/common/socket/websocket.gateway.ts:62-69` — 클라이언트가 보낸 `terminalId`를 검증 없이 등록한다.
- `api-ventago/src/common/socket/websocket.gateway.ts:74-81` — 클라이언트가 보낸 `branchId`를 검증 없이 등록한다.
- `api-ventago/src/common/socket/websocket.service.ts:54-59,80-82,94-101` — 값 그대로 `user:{id}`, `store:{id}`, `terminal:{id}`, `branch:{id}` room에 가입시킨다.
- `api-ventago/src/common/socket/ws-cors.ts:29-35` — Origin 없는 네이티브 연결을 허용한다. CORS는 비브라우저 공격자의 인증 수단이 아니다.
- `api-ventago/src/app/team-chat/team-chat.service.ts:44-55` — 팀 채팅 본문과 발신자 정보를 user/store room으로 전송한다.
- `api-ventago/src/app/mercadopago/webhook/mp-webhook.service.ts:183-199` — 결제 승인 `intentId`, `paymentId`, 금액, 판매 ID를 terminal room으로 전송한다.
- `api-ventago/src/app/admin-console/admin-console.service.ts:599-603` — 매장 공지를 store room으로 전송한다.

**공격 사슬**

1. 공격자는 인증 없이 Socket.io `/realtime`에 연결한다(Origin 헤더를 생략할 수 있음).
2. `register_user({userId: victimId, storeId: victimStoreId})`, `register_terminal({terminalId: victimTerminalId})` 또는 `register_branch({branchId: victimBranchId})`를 보낸다.
3. 서버는 소유권 조회 없이 공격자 소켓을 피해자 room에 가입시킨다.
4. 공격자는 타 매장 채팅, 결제 승인 정보, 보류판매/공지/프린터 상태 이벤트를 수신한다. ID가 순차 정수라 열거도 가능하다.

**영향:** 타 매장 영업·결제·내부 대화 데이터의 지속적 유출. 이벤트에 따라 업무 흐름 정보도 실시간으로 노출된다.

**수정 제안**

- handshake에서 JWT를 검증하고 서버가 토큰에서 `userId/storeId`를 파생한다.
- terminal/branch 가입 시 DB에서 `terminal/branch.storeId === authenticatedStoreId`를 확인한다.
- `register_api_key`는 API key의 존재/활성/지점 소유권을 서버에서 검증한 후에만 room 가입을 허용한다.
- 클라이언트 제공 `userId/storeId`는 제거하고, room 전환 시 이전 store/user/terminal room도 leave한다.
- 다른 보안 게이트웨이(`online-orders-board.gateway.ts`, `restaurant-delivery.gateway.ts`)의 JWT + branch 소유권 패턴을 공용 게이트웨이에 적용한다.

### CR-02 — `correct-today`가 타 매장 ProductBranch를 선택해 재고 원장을 변경할 수 있음

**증거**

- `api-ventago/src/app/products/products.controller.ts:780-796` — `PUT /products/:id/correct-today`가 `branchIds`와 `variantId/newStock`을 body에서 받으며 `@Auth()`는 역할 제한 없이 인증만 요구한다.
- `api-ventago/src/app/products/products.controller.ts:819-832` — URL의 부모 상품만 요청자 매장 소속인지 검증하고, body의 branch/variant 소유권은 검증하지 않은 채 서비스로 넘긴다.
- `api-ventago/src/app/products/productStock.service.ts:462-466` — 서비스도 부모 `parentId`만 조회한다.
- `api-ventago/src/app/products/productStock.service.ts:474-483` — body의 `variantIds`와 `branchIds` 조합으로 `ProductBranch.findAll`을 직접 수행한다.
- `api-ventago/src/common/tenant/tenant-scope.registry.ts:89-103` — ProductBranch/Stocks/Price는 파생 스코프 대상이다.
- `api-ventago/src/common/tenant/tenant-scope.registry.ts:113-126` — 파생 스코프 기본값은 `observe`; 부모 JOIN을 주입하지 않는다.
- `api-ventago/src/common/tenant/tenant-hooks.ts:262-277` — observe 모드에서는 로그만 남기고 쿼리를 그대로 실행한다.
- `api-ventago/src/app/products/productStock.service.ts:503-510,529-576` — 선택된 타 매장 ProductBranch의 기존 원장을 읽고, 요청한 절대 재고와의 차이를 새 `Stocks` 조정 행으로 기록한다.

**공격 사슬**

1. 매장 A의 인증 사용자는 자기 매장 부모 상품 ID를 URL에 넣어 첫 소유권 검사를 통과한다.
2. body에는 열거한 매장 B의 `variantId`와 `branchId`를 넣는다.
3. ProductBranch 파생 훅은 기본 observe라 매장 필터를 주입하지 않아 B의 합법적인 ProductBranch를 반환한다.
4. 서비스는 B의 해당 일자 재고를 기준으로 delta를 계산하고 B ProductBranch에 `adjust` 원장 행을 생성한다.
5. DB 교차 FK 트리거도 “B 상품 ↔ B 지점”이라는 내부 관계는 정상이라 요청자 매장이 A라는 사실을 알 수 없어 차단하지 못한다.

**영향:** 타 매장 재고 수량 및 원장 무결성 훼손, 판매 가능 수량·회계/재고 보고 왜곡.

**수정 제안**

- 컨트롤러/서비스에서 모든 `branchIds`를 `Branch.findAll({ where: { id: ..., storeId: requesterStoreId }})`로 검증한다.
- 모든 `variantId`가 `parentId`의 자식이며 `storeId === requesterStoreId`인지 검증한다.
- ProductBranch 조회에 `Product(required:true, where:{storeId})`와 `Branch(required:true, where:{storeId})`를 동시에 강제한다.
- 검증과 원장 생성은 하나의 트랜잭션에서 수행한다.
- Phase 68 파생 훅 테스트를 보강한 후 `TENANT_DERIVED_MODE=enforce`를 운영 기본값으로 전환한다.

### CR-03 — 동일 전화번호의 첫 번째 벤더 PIN 하나로 다른 매장 벤더 권한까지 획득

**증거**

- `api-ventago/src/app/vendor-portal/vendor-auth/vendor-auth.service.ts:17-26` — 전화번호가 같은 모든 활성 Vendor를 매장 구분 없이 조회한다.
- `api-ventago/src/app/vendor-portal/vendor-auth/vendor-auth.service.ts:33-41` — `vendors[0].pinHash` 하나만 검증한다.
- `api-ventago/src/app/vendor-portal/vendor-auth/vendor-auth.service.ts:44-50` — 검증 후 같은 전화번호의 모든 vendor ID를 토큰에 넣는다.
- `api-ventago/src/app/vendor-portal/vendor-auth/vendor-jwt.strategy.ts:24-39` — 이후 요청에서도 토큰의 phone으로 모든 활성 Vendor를 다시 조회하며 토큰의 vendorIds조차 제한에 사용하지 않는다.
- `api-ventago/src/app/vendor-portal/vendor-envios/vendor-envios.service.ts:18-39` 및 `vendor-settlements/vendor-settlements.service.ts:16-41` — 이 합쳐진 vendorIds를 배송/정산 조회 권한으로 사용한다.
- `api-ventago/src/app/vendor-portal/vendor-notifications/vendor-notifications.service.ts:68-85` — 합쳐진 vendorIds 중 하나와 일치하면 알림 변경도 허용한다.

**공격 사슬**

1. 한 전화번호가 매장 A와 B에 각각 Vendor로 등록되어 있고 PIN이 서로 다르다고 가정한다(코드는 멀티스토어를 명시적으로 지원).
2. 공격자는 자신이 아는 한 매장의 PIN으로 로그인한다. 조회 순서상 `vendors[0]`의 PIN과 일치하면 된다.
3. 서버는 PIN을 검증하지 않은 나머지 매장 Vendor ID까지 동일 토큰 주체에 포함한다.
4. VendorJwtStrategy는 매 요청마다 같은 전화번호의 전체 Vendor 집합을 복원한다.
5. 공격자는 타 매장의 envíos, settlements, recepciones 및 notifications에 접근하거나 상태를 변경할 수 있다.

**영향:** 서로 독립적으로 PIN을 발급한 매장 사이의 외주 발주·배송·정산·알림 데이터 유출 및 변경.

**수정 제안**

- 로그인 입력에 `storeId` 또는 `vendorId`를 요구하고 `{phone, storeId}` 한 행의 PIN만 검증한다.
- 토큰에는 단일 `vendorId/storeId`를 넣고 strategy가 정확히 그 행을 재조회하도록 한다.
- 한 계정으로 여러 매장을 전환하려면 공통 VendorIdentity 테이블과 매장별 membership을 분리하고, 모든 membership이 동일 자격 증명을 공유한다는 명시적 모델을 사용한다.
- 데이터 마이그레이션 전 동일 phone + 상이한 `pinHash` 조합을 탐지해 계정 병합 여부를 매장에 확인한다.

## Warnings

### WR-01 — Phase 68 파생 격리가 기본 `observe`라 보호막으로 기능하지 않음

**파일:** `api-ventago/src/common/tenant/tenant-scope.registry.ts:58-68,89-126`; `api-ventago/src/common/tenant/tenant-hooks.ts:262-277`

**문제:** 레지스트리는 ProductBranch, Stocks, Price 세 모델만 알고 있으며 기본 설정에서는 모두 로그만 남긴다. 이 모델을 주 모델로 조회하는 현재 호출부가 다수이고(`productStock.service.ts`, reports, sales, print, work-orders), 각각이 누락 없이 부모 소유권을 검증해야만 안전하다. CR-02는 이 가정이 이미 깨진 실제 예다. `store_id` 없는 다른 관계 모델은 레지스트리에 없으므로 관측 로그조차 없다.

**수정:** DB 스키마의 FK 그래프를 기준으로 테넌트 파생 모델 목록을 자동/반자동 생성하고, read/write별 정책을 추가한다. observe 로그 호출부를 모두 정리한 뒤 enforce를 기본값으로 바꾸며, `ProductBranch`는 Product와 Branch 양쪽 소유권을 검증한다.

### WR-02 — TenantContext 확정 오류가 fail-open으로 삼켜짐

**파일:** `api-ventago/src/app/auth/guards/jwt-global.guard.ts:53-82`; `api-ventago/src/common/tenant/tenant-context.ts:77-91`

**문제:** JWT 인증 후 테넌트 컨텍스트를 확정하는 전체 블록이 빈 `catch`로 감싸져 있으며 오류가 나면 인증 요청을 그대로 통과시킨다. 현재 `TenantContext.resolve` 자체는 일반적으로 throw하지 않지만, 사용자 객체 getter/향후 owner scope 처리/리팩터링에서 예외가 생기면 `resolved=false`가 유지되고 모든 Sequelize 훅이 no-op가 된다. 보안 경계의 실패 정책이 명시적으로 fail-open이다.

**수정:** 일반 인증 요청에서 컨텍스트 확정 실패는 요청을 500/403으로 종료하고 보안 로그를 남긴다. 공개/시스템 경로만 명시적 no-op로 유지한다. 최소한 catch에서 `TenantContext.get()?.resolved`를 검사해 미확정 인증 요청을 거부한다.

## 확인된 방어 및 비발견 사항

- reports controller의 84개 라우트는 현재 85회의 `scopedQuery`/`resolveScopedStoreId` 호출을 통해 raw SQL 진입 전 사용자 매장 관문을 통과한다. 일반 사용자의 타 `query.storeId`는 403 처리된다(`reports.controller.ts:114-156`).
- MercadoPago webhook은 `accountId`를 공개 query에서 받지만 MP API를 해당 account token으로 재조회하고, 결제 intent의 `mpAccountId` 일치를 검사한 뒤 반영한다(`mp-webhook.service.ts:80-109,126-179`). 이번 리뷰에서 교차매장 반영 사슬은 확인되지 않았다.
- 공개 shop catalog/checkout/try-on의 상품 조회는 요청 storeId와 product storeId를 함께 조건으로 사용한다.
- 조사한 캐시 키는 dashboard/catalog/reference/subcon 상세 경로에서 storeId 또는 branchId를 포함했다. 현재 범위에서 재현 가능한 교차매장 캐시 충돌은 확인하지 못했다.

## 우선순위

1. `/realtime` 게이트웨이 인증 및 room 소유권 검증 — 즉시 차단 권고.
2. `correct-today`의 branch/variant 소유권 검증 — 배포 전 회귀 테스트 포함.
3. 벤더 토큰을 단일 store/vendor scope로 변경.
4. Phase 68 호출부 정리 후 derived enforce 전환.
5. TenantContext catch를 fail-closed로 변경.

---

_Reviewer: Codex tenant security review_  
_Source files were not modified._
