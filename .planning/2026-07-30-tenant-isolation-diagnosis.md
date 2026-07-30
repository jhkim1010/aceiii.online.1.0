# 진단서 — 병목 · 교차매장 오염 · 충돌 지점

작성: 2026-07-30 | 대상: Ventago POS/ERP (api-ventago, ventago-app)
방법: 코드 정적분석 3회(병렬) + 운영 로그 실측 + 운영 PG18(5434) read-only 실측 + 교차검증

---

## 0. 한 줄 결론

**병목은 현재 실측상 존재하지 않는다. 실재하는 위험은 매장 격리 결함이며, 그것은 이미 운영 데이터 59행을 오염시켰다.**

---

## 1. 운영 DB 실측 — 교차매장 오염 (★ 실제 발생)

FK 는 `product_id → products`, `branch_id → branches` 를 각각 검증할 뿐
**"그 둘이 같은 매장인가"는 DB 어디에서도 보장하지 않았다.**

| 유형 | 오염 | 상세 |
|---|---|---|
| `products.parent_id` | **22행** | 자식(store 3·8)의 부모가 store 6 — ★ 상류 원인 |
| `prices` | **24행** | products 21-26(store 8)이 store 6 의 price_type 11·12·13·14 사용 |
| `sale_items` | **10행** | sale 2·3·4·8(단품) / 10·14(혼합) — store 6↔3, 3↔8, 8↔6 |
| `ProductBranch` | **3행** | pb 109/110/111 = store 3 상품이 store 6 지점에 등록 |

### 인과 사슬 (중요)

```
products.parent_id 교차 (22)         ← 진짜 뿌리
   ├─▶ prices 교차 (24)              store 6 부모 밑에서 생성 → store 6 price_type 상속
   ├─▶ sale_items 교차 (10)          store 6 이 자기 상품의 variant 로 인식 → 판매
   └─▶ ProductBranch 교차 (3)        같은 이유로 store 6 지점에 재고 등록
              └─▶ stocks 원장 6행 (pb 당 net −8)
                     └─▶ products.stock 캐시 = 1 + (−8) = −7  (products 2·3·4)
```

구체 예: `products 2,3,4,5` (CAMPERA ESTAMPADA 변형, store 3) 의 부모 `product 1` 이 **store 6** 소속.
`products 7~18` (REMERA **CART** — CART 는 store 3 의 이름) 의 부모 `product 6` 도 store 6 소속.
`products 21~26` (blusa, store 8) 의 부모 `product 20` 도 store 6 소속.

### 정상 확인 (오염 0건)

terminals · boxes · users · cash_registers · active_sessions · terminal_devices ·
ventas_suspendidas · expenses · box_operations · sales(terminal·client) · product_promotions

### NULL store_id 실측

`payment_methods` 13, `roles` 4, `users` 1(superadmin id=1) — **전부 의도된 글로벌 행**.
나머지 16개 테이블 0건.
⚠ 다만 `sales.store_id` 는 스키마상 **NULLABLE** — NULL 이 되면 어떤 `WHERE store_id=X` 도 통과 못 하고 교차검출도 못 한다(잠복).

---

## 2. 운영 로그 실측 (`api_ventago:/app/logs/combined-2026-07-30.log`)

| 항목 | 실측 | 판정 |
|---|---|---|
| `error-2026-07-30.log` | **0 byte** | ✅ |
| `[SLOW]` 로그 | **0건** | ✅ |
| `slow_query_log` (7일) | **4건**, 최대 189ms | ✅ |
| cron 중복 실행 | `스케줄러 비리더 — cron/interval 21개 해제 (INSTANCE=1,2,3)` | ✅ 4워커 중 1개만 |
| pg 커넥션 | total 3, active 1, idle-in-tx 0 / max_connections 200 | ✅ 여유 |
| `ShopReadonlyDb` | ⚠ `공개몰 pool 이 메인 DB 로 폴백됨 — 커넥션 격리 미적용` (4회) | ⚠ |
| `StockDriftService` | ⚠ `4/190 productos con drift (8 unidades)` | ⚠ 위 pb 오염과 정합 |

`pg_stat_statements` 상위도 mean 5ms 이하. **현재 데이터량**(sales 110행/312kB)에서는 병목이 물리적으로 발생할 수 없다.

> ⚠️ 앞선 다른 분석의 "sync_outbox UPDATE 0.7~3초 / campaign_recipients 0.4~2.1초" 는 **재현되지 않았다.**
> `sync_outbox` 는 현재 0행이며 seq_scan 46,879 · idx_scan 0 은 "빈 테이블이라 플래너가 seq scan 을 고른" 정상 상태다.

### 병목은 "없다"가 아니라 "아직 안 왔다"

3,000 터미널 목표 기준 잠복 리스크로 확인된 것:

| 지점 | 내용 |
|---|---|
| 공개몰 pool 미격리 | `SHOP_DB_HOST` 미설정 → 공개 트래픽이 POS 와 같은 PG 슬롯. 4워커×5=20 클라이언트 |
| 커넥션 예산 | 워커 4 × (메인 20 + 공개몰 5) = **100** vs pgbouncer pool_size **50** → 부하 시 큐잉 |
| `ProductList.tsx:202` | POS 최고 트래픽 화면이 `pageSize=1000` (규약 상한 50) |
| `SaleProductsContext.tsx:431` | POS 장바구니 Provider value 미 `useMemo` → 키 입력마다 전체 리렌더 |
| `reportsSales.service.ts:64` | hasMany 2개 동시 include(`separate` 없음) → 카티션 곱 + 날짜필터 optional |
| `SalonView.tsx:24` | 10초 폴링 → 3,000단말 시 이론상 300 req/s |
| `/me` 권한 백필 | `auth.service.ts:926` 캐시·once-flag 없이 매 호출 실행 |
| `productsDashboards.service.ts:48` | `where: { branchId: storeId }` — **컬럼 오용 버그**. 대부분 빈 결과라 N+1 이 가려져 있음 |

*(위 8건은 이번 Phase 67 범위 밖 — 별도 처리 필요)*

### 이미 해결되어 있던 것 (오해 방지)

- `audit_logs` 인덱스: 운영에 `entity_type_entity_id` · `created_at` · `store_id` · `user_id` **존재** (마이그레이션 파일만 보면 없어 보임)
- `ProductBranch (product_id, branch_id)` UNIQUE: **존재** (`ProductBranch_product_id_branch_id_key`)
- `active_sessions.user_id` UNIQUE: **존재**
- cron 다중 워커 중복: `common/cron/cron-leader.ts` 로 **해결됨**
- 트랜잭션 내 외부 I/O: 전 경로 커밋 후 실행으로 **규약 준수 중**

---

## 3. 코드 격리 결함 (전수 검증 완료)

| # | 위치 | 결함 | 조치 |
|---|---|---|---|
| A1 | `common/crud/crud.service.ts:41` | `if (!isSuperAdmin && storeId && …)` — storeId 미전달 시 검사 **소멸(fail-open)**. CRUD 스캐폴드 7+ 모듈 영향 | ✅ fail-closed |
| A2 | `branch/branch.service.ts:21` | `findOne(id)` 1-인자 오버라이드가 base 소유검사 무력화 → 타 매장 지점 PUT/DELETE | ✅ 시그니처 복원 |
| A3 | `reports/reports.controller.ts` | `query.storeId` 신뢰 **50건** vs `user.storeId` 1건. `scope.helper.ts` 사용 0건(죽은 코드) | ✅ **84개** 전부 강제 |
| A4 | `reports/reportsStocks·reportsProducts` | `storeId` 를 아예 읽지 않음 → 전 매장 재고/상품 노출 | ✅ 필터 + N+1 제거 |
| A5 | `sales/sales.controller.ts:339` | `findOneAdmin` 만 검사 누락(형제 4개는 있음) | ✅ |
| A6 | `sales/sales.service.ts:157` | `literal()` 문자열 보간 + DTO 검증 없는 `@Query` → SQLi & storeId 조건 무력화 | ✅ 정규화 + Pipe |
| A7 | `print/print.controller.ts` | agent CRUD·**apiKey 평문 노출**·출력 라우팅 전부 무검증 | ✅ 소유검증 + 마스킹 |
| A8 | `users/user-role/user-role.controller.ts` | 가드 전무 → **권한 상승** | ✅ `@Auth` + 스코프 |
| A9 | `payment-methods.controller.ts:76` | PUT/DELETE 무스코프 → 공용 글로벌 행 파괴 가능(전 매장 결제 중단) | ✅ 글로벌행 쓰기 금지 |
| A10 | `suspended-sales.controller.ts:46` | vendedor 가 타 매장 보류판매 열람/삭제 → 타 매장 **재고 원장 변동** | ✅ |
| A11 | `session/session.service.ts:483` | `Box.findByPk(boxId)` 무검증 → 타 매장 branch 가 내 매장 device/session 에 박힘 | ✅ |
| A12 | `products.controller.ts:329` | `@GetUser()` 주입만 하고 미전달 → 타 매장 가격 변경 | ✅ 필수 인자화 |
| A13 | `promotions/*` | `@UseGuards(jwt)` 만 — FunctionGuard 조차 없음 | ✅ |
| A14 | `subcon/envios/*` | `:id` 무스코프 + lote 수량 lost-update | ✅ + `FOR UPDATE` |
| A15 | `terminal`·`caja-fuerte`·`box-operation`·`subcon vendors/orders` | `:id`/`:storeId` 무스코프. box-operation 은 `userId` 를 **body** 에서 취득(위조) | ✅ |
| A16 | `permissions/guards/permission.guard.ts:74` | PRIVILEGED 우회에 storeId 비교 없음 | ✅ |
| **A17** | `auth/guards/function-permission.guard.ts:44` | `user.roles.some(r => r.slug===…)` 인데 런타임 `roles` 는 **string[]** → **superadmin 우회가 작동한 적 없음** (신규 발견) | ✅ |
| A18 | `boxes/*` (복수형) | 격리 없는 컨트롤러. `BoxesModule` 미등록이라 비활성이나 언젠가 배선되면 전 매장 개방 | ✅ 정의 제거 |

### 충돌·경합

| 지점 | 내용 | 조치 |
|---|---|---|
| `session.service.ts` | `destroy → create` 6곳 비원자 + `UNIQUE(user_id)` → 동시 로그인 시 500 또는 토큰 소실 | ✅ `ON CONFLICT` 원자 교체 |
| `session.service.ts:311` | Branch/Box/Terminal/IP/Device/Session 개별 생성 → 중간 실패 시 고아 행 | ✅ 단일 트랜잭션 |
| `envio.service.ts:92` | lote 수량 read-modify-write, lock 없음 → 잔량 10 에 7+7 동시 통과 | ✅ `LOCK.UPDATE` + 취소 멱등화 |
| `online-order-sales-mirror.service.ts:80` | `dailyNumber` 재도출에 advisory lock·day 필터·`saleDayLocal` 없음 → unique 인덱스가 NULL 로 무력화 | ⬜ **미처리** |

---

## 4. 적용한 방어 — 4중 (Defense in Depth)

```
요청 ─▶ [L1] TenantContext (AsyncLocalStorage)        요청당 storeId 확정
          ├─▶ [L2] Sequelize 전역 훅   ← 114개 모델 일괄, 컨트롤러 무관
          ├─▶ [L3] CrudService fail-closed
          └─▶ [L4] DB 교차매장 트리거 21개 ← raw SQL·psql·외부도구까지
```

**핵심 안전장치: L2 는 컨텍스트가 없으면 no-op.** 크론·워커·공개몰·로그인·웹훅(@Public 33파일)은 컨텍스트가 없어 영향 없음.
글로벌 행(payment_methods 13, roles 4)은 조회에 union → POS 결제 회귀 없음.
탈출구: `TENANT_GUARD_MODE=warn|off` — 재배포 없이 즉시 하향 가능.

### 운영 검증 결과

```
[TenantGuard] 격리 훅 설치 완료 — mode=enforce 보호모델=114 (글로벌행 허용 26) 제외=69
```

- Jenkins api-new-coolsistema **#564 SUCCESS**, `api_ventago` 재생성 → healthy (4워커 전부 정상)
- `tsc --noEmit` 0 errors (의도적 타입오류 주입으로 실제 수행 검증)
- 트리거 6종 시나리오 테스트: 교차 INSERT 차단 ✓ / 동일매장 INSERT 통과 ✓ / 기존 오염행 무관컬럼 UPDATE 통과 ✓
- 배포 후 8분 관측: TenantGuard 경고 **0건**, error 로그 **0건**

---

## 5. 완료 현황

### ✅ 전부 완료 (2026-07-30)

| 항목 | 결과 |
|---|---|
| 백엔드 배포 | Jenkins **api #564 SUCCESS** → `api_ventago` 재생성, healthy. `89389dd` |
| 운영 트리거 | **21개** 적용 (5434). 시나리오 6종 테스트 통과 |
| 로컬 트리거 | **21개** 적용 (5432) → dev·운영 스키마 일치 |
| 오염 보정 DML | **59행 → 0행**. `e2d7fcc` |
| 프론트 대응 | Jenkins **front #515 SUCCESS** → `ventagoapp` 재생성. `9c721f9` |
| 배포 후 관측 | TenantGuard 경고 **0건**, api error **0건** |

### 오염 보정 결과 (운영 5434)

| 유형 | 전 | 후 | 방법 |
|---|---|---|---|
| `products.parent_id` | 22 | **0** | 부모 1·6·20 을 자식 매장(3,3,8)으로 이동 |
| `prices` | 24 | **0** | store 8 상품 21~26 을 자기 price_type(3) 6행으로 이전 |
| `sale_items` | 10 | **0** | 전액교차 판매 2·3·4·8·14 삭제 / 혼합 sale 10 은 아이템만 |
| `ProductBranch` | 3 | **0** | 원장 6행 + pb 3행 제거 (`stocks_maintenance` 플래그) |

`sale 10` 은 교차 아이템 3개가 **금액 0.00** 이었고 366,300 은 전부 정상 store 6 아이템이라
판매를 보존하고 아이템만 제거했다. store 3·8 은 전체 판매 이력이 교차 테스트여서 0건이 됐고, store 6 은 84→83건.
`products` 2·3·4 재고 캐시 −7 → +1 (원장과 일치).

**사후 검증 — 아래 2건은 이번 작업과 무관한 기존 상태**
- 고아 `stocks` 3건 (id 33·35·38) — `product_branch_id` 가 NULL 인 2026-03~04 행
- 재고 캐시 drift 27건 — 전부 store 6 의 다른 상품(FRONT CAT·PANT MEZC·CONJUNTO 등, id 148~289).
  기존 `StockDriftService` 경고와 동일 건

### 프론트 변경 (breaking, 대응 완료)

`GET /print/agents/:branchId`·`/print/config/:branchId` 응답에서 `apiKey` 제거 → `apiKeyPrefix` + `hasKey`.
전체 키는 **생성/재발급 응답에서만 1회** 반환된다.
- `useAgents.ts` — 타입 교체
- `PrinterConfigTab.tsx` — 평소 접두어만(복사 버튼 숨김), 생성·재발급 시 그 자리에서 1회 복사.
  **생성 경로도 포함** (안 하면 새 에이전트 키를 영영 볼 수 없다)
- `AgentsTable.tsx` — 복사 버튼 제거, 재발급 후 다이얼로그 노출
- `ApiKeyModal.tsx` — 조회 시 잠금 표시, 재발급 시에만 전체 키 + 경고

---

## 5-B. Phase 67-B — store_id NULL 탈출구 봉쇄 (완료)

### 오염과는 다른 실패 모드였다

| | 오염(contamination) | 누수(leak) |
|---|---|---|
| 정의 | 자식이 **타 매장의** 부모를 가리킴 | 행의 `store_id` 가 **NULL** |
| 실례 | 59행 (§1) | 0행 (잠복) |
| 왜 위험 | 매장 A 상품이 매장 B 재고·매출에 섞임 | 격리 훅이 NULL 을 "전 매장 공용"으로 해석 → **모든 매장에 노출** |
| 해법 | FK 쌍 트리거 (§4 L4) | 글로벌 허용목록 축소 + 앱 가드 + `NOT NULL` |

`store_id` 를 모든 테이블에 붙이는 것은 해법이 **아니다** — 실측상 83개 테이블에 `store_id` 가
없고 그게 정상 설계다(`sale_items`·`prices`·`ProductBranch` 는 부모에서 매장을 유도한다).
붙이면 진실의 원천이 둘이 되어 서로 어긋나는 새 오염 경로가 생긴다.

### ★ 배포된 훅에서 발견한 실제 구멍

`allowedStores()` 는 `ctx.isSuperAdmin === true` 일 때 `null` 을 반환한다 → **스탬프가 안 걸린다.**
그런데 superadmin 은 `users.store_id` 가 NULL 이라 컨트롤러의 `storeId: user.storeId` 패턴이
그대로 NULL 을 넣는다. 즉 **Phase 67 훅은 superadmin 요청을 전혀 보호하지 않았다.**
운영 NULL 0행은 "안전"이 아니라 "아직 안 터짐"이었다.

확인된 도달 경로: `expenses.controller.ts:47`(`@Body() body: any`, storeId 주입 없음),
`clients.controller.ts:137`, `cashRegister.controller.ts:135`(user 를 받고 미사용),
`user-function.controller.ts:85`(`user.storeId as number` — 타입 단언이 null 을 가림),
`branch.controller.ts:61`(인라인 TS 타입 → ValidationPipe 무동작),
`crud.controller.ts:53` 제네릭 PUT(`Partial<T>` → whitelist 무력)

### 조치

1. `tenant-scope.registry.ts` — 글로벌 허용 목록 **28 → 9**.
   실측 NULL 보유(`role_functions` 24 / `store_error_log` 23 / `payment_methods` 13 /
   `roles` 4 / `users` 1 / `audit_logs` 1) + 모델이 글로벌을 명시한
   `knowledge_documents`·`whatsapp_templates` + `user.storeId || 0` 결함이 있는 `chat_messages` 만 유지
2. `tenant-hooks.ts guardCreate` — superadmin 이 비글로벌 테이블에 `storeId` 없이 생성하면 **400**.
   조용한 누수보다 시끄러운 실패가 낫다
3. `crud.service.update` — 제네릭 PUT body 에서 `storeId` 제거.
   `configurations`·`cash_registers`·`module_aliases`·`discounts`·`recharges` 의 유일한 update 경로였다
4. `user-function.controller` — 권한 행의 귀속 매장을 **요청자가 아니라 대상 유저**에서 취득
5. `migrations/2026-07-30-tenant-store-id-not-null.sql` — 19개 테이블 `SET NOT NULL` (DB 안전망)

### 결과

- Jenkins **api #566 SUCCESS** → `api_ventago` healthy · `53add88`
- 부팅 로그: `격리 훅 설치 완료 — mode=enforce 보호모델=114 (글로벌행 허용 8) 제외=69` ← 26에서 축소
- 운영 5434 `SET NOT NULL` **19건 적용**, nullable 잔여 = 의도한 글로벌 9종뿐
- 배포·마이그레이션 후 error 0, TenantGuard 경고 0

> ⚠ 로컬 5432 에도 같은 파일 적용 필요 (아래 명령)

---

## 5-C. Phase 67-C — superadmin 매장 대행 (X-Store-Id) (완료)

67-B 가 "superadmin 의 storeId 없는 매장데이터 생성"을 400 으로 막으면서,
**고객 요청으로 그 매장 데이터를 대신 편집한다**는 정당한 업무 통로가 사라졌다.
원래도 통로가 없긴 했다 — 컨트롤러 대부분이 `storeId: user.storeId` 를 쓰는데
superadmin 은 `users.store_id` 가 NULL 이기 때문이다.

### 설계

요청 헤더 `X-Store-Id: 6` 으로 "이 요청 동안 나는 매장 6 이다" 를 명시한다.
`JwtGlobalGuard` 가 검증 후 `request.user.storeId` 를 채우므로
**85개 컨트롤러를 한 줄도 고치지 않고** 그대로 매장 6 으로 동작한다.

| 상황 | 동작 |
|---|---|
| 헤더 없음 | 기존과 동일 — 전 매장 집계(GROUP BY용), 매장데이터 쓰기는 400 |
| `X-Store-Id: 6` | 매장 6 사용자와 **완전히 동일**하게 읽고 씀 |
| 일반 사용자가 헤더 전송 | 조용히 무시 (프록시가 흘려도 요청이 안 깨지게) |
| 없는 매장 id | 400 |
| 삭제된 매장 | 허용 + 경고 로그 (삭제 테넌트 조사·복구 지원) |

대행 중에는 `TenantContext` 를 `isSuperAdmin=false` 로 확정한다 → 격리 훅이 조회를
좁히고 생성 시 6 을 찍으므로, **실수로 타 매장 id 를 건드리는 사고까지 막힌다.**

### 구현상 함정 (기록)

- ★ `request.user` 는 **복제해서 교체**해야 한다. `JwtStrategy` 가 이 객체를
  `auth:user:{email}` 키로 30초 캐시하므로, 직접 변형하면 대행이 끝난 뒤의
  다른 요청까지 매장이 오염된다.
- reports 는 raw SQL 이라 격리 훅이 닿지 않는다 → `resolveScopedStoreId` 에서
  `requestedId ?? storeIdOfUser(user)` 로 명시 반영. 대행이 아니면 superadmin 의
  storeId 가 null 이라 기존 전 매장 집계가 그대로 유지된다.
- 매장 존재 검증은 60초 캐시 — 대행이 붙는 순간 모든 요청에 DB 왕복이 1회
  추가되므로 (pool 규약).

### 감사 로그

모든 대행 요청이 남는다: `[ACT-AS] user=1(superadmin@…) → store=6(coolsistema) PUT /api/clients/12`

### 결과

- Jenkins **api #568 SUCCESS** → `api_ventago` healthy · `364db24`
- 스모크: 헤더+무인증 401 / 헤더없음 401 / 공개라우트+헤더 200 / 잘못된 헤더값 401 — **500 없음**
- 배포 후 error 0

### 앱 연동 (잔여)

superadmin 웹·모바일 앱의 axios 인터셉터에 한 줄 + 매장 선택 UI:
```ts
if (actingStoreId) config.headers['X-Store-Id'] = String(actingStoreId)
```

### 계속 관측할 것

아르헨티나 영업시간에 오탐이 없는지 확인:
```bash
ssh jhkim-server "docker logs --since 1h api_ventago 2>&1 | grep TenantGuard | grep -v '설치 완료'"
```
문제 발생 시 재배포 없이 즉시 하향: `TENANT_GUARD_MODE=warn`

### 후속 (Phase 68 후보)

- `sales.store_id` NOT NULL 화
- `online-order-sales-mirror` dailyNumber advisory lock + `saleDayLocal`
- 공개몰 pool 실제 격리(`SHOP_DB_HOST`) — 현재 예산 100 vs pgbouncer 50
- 위 2절 "잠복 병목" 8건
- `boxes/` 잔여 파일 `git rm`
- `suspended-sales`·`mobile-sales`·`terminal.service` spec 3종 시그니처 갱신 (빌드엔 무영향, jest 실행 시 필요)
