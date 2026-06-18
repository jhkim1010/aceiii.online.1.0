# 배달 판매 VentaVista 표시 + DeliveryBoard 이력 조회 — 설계

- **날짜**: 2026-06-18
- **대상 저장소**: api-ventago (백엔드), ventago-app (프론트)
- **선행**: Phase 39(식당 모드), Phase 40(배달/배차/수금), 배달 주문 편집
- **회귀 제약**: 소매(의류) 판매 무회귀 — 공유 경로(VentaVista 목록) 변경 시 `source='delivery'` 분기에서만 동작 변경

---

## 1. 문제 / 배경

배달 주문은 `Sale(source='delivery', activityType='sale', tableId=null)` + `restaurant_deliveries` 1:1로 생성된다. 그런데:

1. **VentaVista(/ventas) 표시 누락** — 배달 주문 생성 시 `Sale`에는 `sellerId`, `clientId`, `storeClientId`가 채워지지 않는다(`restaurant-delivery.service.ts` `createOrder`). 고객명·전화·주소·canal·repartidor는 전부 `restaurant_deliveries` 행에만 있다. 결과적으로 ventas 목록에서:
   - **Vendedor** 컬럼(`row.seller?.name`) → `—`
   - **Cliente** 컬럼(`row.client?.fullname || storeClient?.fullname || 'Cliente Indefinido'`) → `Cliente Indefinido`

2. **정산 완료 배달 재조회 불가** — DeliveryBoard 컬럼은 6개(`Nuevo·En cocina·Listo·En camino·Por cobrar·Conciliación`)뿐이라 `liquidado` 컬럼이 없다. 현금 정산이 끝나 status가 `liquidado`가 되면 카드가 그룹핑 버킷을 못 찾아 보드에서 사라진다. `cancelado`는 `getBoard` 쿼리(`status <> 'cancelado'`)에서 제외된다. 종료된 배달의 전체 내역을 다시 볼 전용 UI가 없다(데이터는 DB에 보존됨).

## 2. 목표

- **A**: VentaVista에서 배달 판매의 **Vendedor 칸에 canal 라벨**, **Cliente 칸에 배달 등록 고객명** 표시. 상세 드로어에도 배달 메타 노출.
- **B**: DeliveryBoard에 **Historial(이력) 보기**를 추가해 종료 상태(`liquidado`, `conciliacion`, `cancelado`) 배달을 날짜 범위로 읽기전용 조회.

비목표(YAGNI): 이력 화면에서의 상태 전이/편집/취소, conciliacion 라이브 컬럼 제거, Sale 모델 구조 변경, 배달 메타의 Sale 백필.

## 3. 접근법 결정

**Part A 데이터 연결**: ventas 목록 service에서 페이지 결과 중 `source='delivery'`인 saleId를 모아 `restaurant_deliveries`를 **1회 batch SELECT**(saleId IN, storeId 스코프)로 enrichment. 각 row에 `delivery` 객체 부착.

- 채택 이유: Sale ↔ RestaurantDelivery 모델 association 추가(순환 import/모듈 결합) 회피, 페이지당 쿼리 +1건만(pageSize ≤ 50이라 pool 안전), enrichment 로직이 한 곳에 격리됨.
- 기각: (A2) Sale에 `@HasOne(RestaurantDelivery)` + LEFT JOIN — 모듈 간 모델 결합/순환 import 위험. (A3) 프론트 per-row GET — N+1.

## 4. 상세 설계

### Part A — VentaVista 배달 판매 표시

#### 백엔드 (`api-ventago/src/app/sales/sales.service.ts`)

VentaVista 목록을 반환하는 페이지네이션 메서드(`findAndCountAll` 기반, Seller/Clients include) 결과에 enrichment 단계 추가:

1. 반환 rows 중 `source === 'delivery'`인 sale의 `id` 수집.
2. id가 1개 이상이면 단일 쿼리 실행:
   ```sql
   SELECT sale_id        AS "saleId",
          canal,
          customer_name  AS "customerName",
          customer_phone AS "customerPhone",
          address,
          status,
          repartidor_id  AS "repartidorId"
     FROM restaurant_deliveries
    WHERE store_id = :storeId
      AND sale_id IN (:saleIds)
   ```
   - `storeId`는 호출 컨텍스트의 store 스코프(멀티테넌트 IDOR 가드). `:saleIds` 빈 배열이면 쿼리 자체를 스킵.
3. saleId → delivery 맵 구성 후 각 row에 부착:
   - delivery sale: `row.delivery = { canal, customerName, customerPhone, address, status, repartidorId }`
   - 그 외: `row.delivery = null`

> 구현 메모: 응답 row가 Sequelize 인스턴스면 `.get({ plain: true })` 후 부착하거나 `setDataValue('delivery', ...)`로 직렬화에 포함되도록 한다. 기존 응답 직렬화 방식(plain 변환 위치)을 따라 일관되게 처리.

#### 프론트 (`ventago-app/src/views/sales/list/components/DataConfig.tsx`)

- canal 라벨 헬퍼(모듈 상수):
  ```
  whatsapp → 'WhatsApp', telefono → 'Teléfono', app → 'App', otro → 'Otro'
  (미매칭/누락 시 'Delivery')
  ```
- **Vendedor** 렌더러(현재 `params.row.seller?.name || '—'`):
  `row.source === 'delivery' ? canalLabel(row.delivery?.canal) : (row.seller?.name || '—')`
- **Cliente** 렌더러(`renderClienteOrRoute`): activityType=sale 경로에서 delivery sale이면 `row.delivery?.customerName || 'Cliente Indefinido'`를 우선 사용(기존 movido/fallado 경로는 불변).
- ESLint: `newline-before-return`, `lines-around-comment` 준수.

#### 상세 드로어 (`ventago-app/src/views/sales/list/components/SaleDetailPanel.tsx`)

- `row.delivery`가 존재하면 작은 "Delivery" 정보 블록 추가: 고객명, 전화, 주소, canal 라벨, 상태칩. 동일 row 데이터 재사용(추가 fetch 없음).

#### 회귀 안전

- 모든 표시 분기는 `source === 'delivery'`(또는 `row.delivery != null`)일 때만. 소매(`pos`) sale은 `delivery: null`이라 렌더러가 기존 분기를 그대로 탄다 → 소매 VentaVista 무회귀.

### Part B — DeliveryBoard Historial

#### 백엔드 (`api-ventago/src/app/restaurant-delivery/`)

- 신규 라우트 `GET /restaurant-delivery/history/:branchId?from=&to=` (`@Auth()`, `restaurant-delivery.controller.ts`). 라우트 순서상 `:id` 경로 앞(구체 경로)에 배치.
- 서비스 `getHistory(storeId, branchId, from, to)`:
  ```sql
  SELECT rd.id, rd.sale_id AS "saleId", rd.status, rd.tipo, rd.canal,
         rd.payment_mode AS "paymentMode",
         rd.customer_name AS "customerName", rd.customer_phone AS "customerPhone",
         rd.address, rd.repartidor_id AS "repartidorId", rd.external_ref AS "externalRef",
         rd.ordered_at AS "orderedAt", rd.delivered_at AS "deliveredAt",
         rd.settled_at AS "settledAt",
         COALESCE(s.total_amount, 0) AS "total", s.daily_number AS "dailyNumber"
    FROM restaurant_deliveries rd
    LEFT JOIN sales s ON s.id = rd.sale_id
   WHERE rd.store_id = :storeId
     AND rd.branch_id = :branchId
     AND rd.status IN ('liquidado','conciliacion','cancelado')
     AND rd.ordered_at >= :from AND rd.ordered_at < :to
   ORDER BY rd.ordered_at DESC
  ```
  - 날짜 범위 필수(unbounded scan 방지). `from`/`to`는 ISO 문자열, `to`는 exclusive(다음날 0시). 누락 시 기본 = 오늘 00:00 ~ 내일 00:00.
  - 카드 매핑은 `getBoard`의 매핑 형태 재사용 + `settledAt` 추가.
- `getBoard` 라이브 쿼리는 변경하지 않음(`liquidado`는 여전히 컬럼이 없어 보드에서 자연히 빠짐 — 의도된 동작).

#### 프론트 (`ventago-app/src/views/restaurante/DeliveryBoard.tsx`)

- 상단 툴바에 **"Tablero / Historial" 토글**(ToggleButtonGroup 또는 탭). Historial 선택 시에만 **날짜 범위 필터**(from/to, 기본 오늘) 노출.
- 신규 SWR 훅 `useDeliveryHistory(branchId, from, to)` (`src/hooks/api/useDeliveryHistory.ts`) → `/restaurant-delivery/history/:branchId?from=&to=`. Socket push 없음(정적 이력). dedup 표준 5분.
- Historial 렌더: **읽기전용** 목록/카드 — 주문번호(dailyNumber), 고객명, canal 라벨, 총액, 결제수단, 상태칩(liquidado=green / conciliacion=cyan / cancelado=gray), 배달완료(deliveredAt)·정산(settledAt) 시각. **상태 전이·편집·취소 버튼 없음.**
- 라이브 보드(6컬럼) 동작·소켓 연동은 그대로. Historial은 별도 데이터 소스라 라이브 보드와 독립.
- 테마: 기존 식당 다크 네이비(#1a1a2e)+골드(#f5a623) 규약 유지.

## 5. 데이터 흐름

```
[A] GET /sales (목록)
    → sales.service: 페이지 조회 → delivery saleId 수집
    → restaurant_deliveries batch SELECT (storeId 스코프)
    → row.delivery 부착 → 프론트 DataConfig 렌더러가 canal/customerName 표시

[B] DeliveryBoard "Historial" 토글
    → useDeliveryHistory(branchId, from, to)
    → GET /restaurant-delivery/history/:branchId?from=&to=
    → getHistory: status IN(terminal) + 날짜범위 SELECT → 읽기전용 목록
```

## 6. 엣지 / 에러 처리

- 배달 saleId 0건 → enrichment 쿼리 스킵(불필요 쿼리 방지).
- delivery 행에 `customerName`이 null(미입력)인데 매칭 → Cliente는 `'Cliente Indefinido'` 폴백.
- takeaway(tipo=takeaway) 주문도 `source='delivery'`이므로 동일하게 canal/customerName 표시(의도됨).
- Historial 날짜 범위 미지정 → 기본 오늘. 잘못된 날짜 형식 → 400(`BadRequestException`).
- 멀티테넌트: 두 신규 쿼리 모두 `store_id` 스코프 강제(IDOR 가드).
- conciliacion은 라이브 보드 Conciliación 컬럼과 Historial 양쪽에 노출됨(아카이브 렌즈, 중복 허용 — 의도됨).

## 7. 테스트 / 검증

- 백엔드: `sales.service` enrichment 단위(배달 row에 delivery 부착 / pos row는 null), `restaurant-delivery.service` getHistory(상태 필터·날짜 범위·storeId 스코프) 단위. 기존 자동 게이트(nest build / jest / eslint / tsc) PASS.
- 프론트 UAT:
  1. WhatsApp 배달 주문 생성 → 배달완료/정산 → VentaVista에서 Vendedor=WhatsApp, Cliente=등록 고객명 확인
  2. 상세 드로어에 Delivery 블록 표시 확인
  3. 소매(pos) 판매는 Vendedor/Cliente 기존대로(회귀 0) 확인
  4. DeliveryBoard Historial 토글 → 날짜 범위로 liquidado/conciliacion/cancelado 조회, 읽기전용(버튼 없음) 확인
  5. 라이브 보드 6컬럼·소켓 push 정상 동작 확인

## 8. 영향 파일 (예상)

**api-ventago**
- `src/app/sales/sales.service.ts` — 목록 enrichment
- `src/app/restaurant-delivery/restaurant-delivery.controller.ts` — history 라우트
- `src/app/restaurant-delivery/restaurant-delivery.service.ts` — `getHistory`
- (옵션) DTO/쿼리 파라미터 검증

**ventago-app**
- `src/views/sales/list/components/DataConfig.tsx` — Vendedor/Cliente 렌더러 + canal 라벨 헬퍼
- `src/views/sales/list/components/SaleDetailPanel.tsx` — Delivery 정보 블록
- `src/hooks/api/useDeliveryHistory.ts` — 신규 SWR 훅
- `src/views/restaurante/DeliveryBoard.tsx` — Tablero/Historial 토글 + 날짜 필터 + 이력 렌더

**DDL**: 없음(기존 테이블만 사용).
