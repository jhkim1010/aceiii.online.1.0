# 설계: Zebra QR 배치·델타 출력 (Phase 38 개정)

생성일: 2026-07-09
상태: 승인됨 (사용자 승인 2026-07-09)
유형: Phase 38 개정 — CodigoMadre QR 라벨을 **Zebra 배치·델타 출력**으로 재정의
선행 설계: [2026-06-11-codigomadre-qr-thermal-print-design.md](2026-06-11-codigomadre-qr-thermal-print-design.md) (thermal per-row, **본 문서로 대체**)

## 목표

zebra-agent에 **QR 배치 출력 탭(TAB3)** 을 추가한다. 운영자가 price-type을 하나 고르고
"Buscar cambios"를 누르면, **마지막 출력 이후 신규이거나 이름/가격이 바뀐 codigomadre 상품**의
리스트를 받아, 원치 않는 항목을 체크 해제한 뒤, Zebra 접착 라벨(좌 QR / 우 이름+가격, 1:3 분할)로
일괄 출력한다. QR은 Phase 37 판매원 앱이 스캔하는 딥링크를 인코딩한다.

QR 라벨은 매장 선반/percha에 부착되어, 판매원이 스캔하면 해당 codigomadre의 지점별 변형 재고를
본다(Phase 37 Half B). 본 문서는 **출력(생성) 측**을 다룬다.

## 배경 — 기존 groundwork (탐색 2026-07-09)

- **Phase 37 스캐너 파서:** `mobile-sales-app/lib/features/scanner/views/qr_scanner_sheet.dart` —
  딥링크 `${PUBLIC_WEB_URL}/m/stock?s={storeId}&p={parentProductId}` 를 파싱. **QR 페이로드는 이 포맷과 정확히 일치해야 함.**
- **zebra-agent:** Electron. renderer(`renderer/index.html`) ↔ preload IPC(`preload.js`) ↔ main(`main.js`, 소켓 + API key).
  현재 탭 = TAB1 "Imprimir"(상품 Buscar → 체크박스 테이블 → 라벨 출력), TAB2 "Etiqueta"(라벨 설정: `label:presets/getConfig/setPreset/setLayout` IPC).
  라벨 프리셋: 50x25 simple / 50x25 doble / 100x25 cartulina. ZPL은 `src/zpl-formatter.js`가 생성, `src/zebra-printer.js`가 TCP 9100/USB 전송.
- **zpl-formatter QR 지원:** `zpl-formatter.js`에 QR 케이스 존재 — `^FO{x},{y}^BQN,2,{mag}^FDQA,{value}^FS`. 재사용.
- **백엔드 print 모듈:** `api-ventago/src/app/print/` — `print.gateway.ts`(namespace `/print-agent`, room `branch:{branchId}`, API key 인증), `print.service.ts`, `print.controller.ts`. barcode 패턴(`POST /print/barcode`) 존재 → QR 엔드포인트는 동일 패턴.
- **print_log류 테이블:** **없음** → 신규 생성 필요.
- **가격 모델:** base 가격(PRECIO 1)은 `products.price` 컬럼(prices 행 아님). 그 외 price-type은 `prices` 행(product_id + price_type_id).

## 확정 결정

- **D-1 위치:** zebra-agent 신규 **TAB3 "QR"** (renderer 탭 + main IPC 핸들러). 웹(CodigoVista)에는 트리거 없음.
- **D-2 프린터:** **Zebra 접착 라벨(zebra-agent, ZPL)** 전용. 기존 thermal per-row 설계는 폐기/보류.
- **D-3 델타 정의:** 신규(이 지점에 print-log 없음) **OR** 현재 이름 ≠ 스냅샷 이름 **OR** 현재 {선택 price-type} 가격 ≠ 스냅샷 가격.
- **D-4 델타 추적 단위:** **지점(branch)별** — 각 sucursal의 zebra-agent가 자기 지점 print-log를 독립 추적. `qr_print_log`에 `branch_id` 포함.
- **D-5 price-type:** **배치 전체 단일** 선택. 델타는 이 price-type 가격 기준으로 계산. 로그도 `price_type_id`별로 스냅샷.
- **D-6 QR 페이로드:** `${PUBLIC_WEB_URL}/m/stock?s={storeId}&p={productId}` (운영 `https://ventago.coolsistema.com`, dev 호스트 치환). storeId/branchId는 **API key에서 서버가 도출**(클라이언트 미전송 = 멀티테넌트/IDOR 안전).
- **D-7 대상 상품:** codigomadre parent(`isParent=true`)만.
- **D-8 라벨 레이아웃:** ZPL 1:3 좌우 분할 — 좌 1/4 QR, 우 3/4 제품명(굵게, 줄바꿈) + `{priceLabel}: {price}`. 기본 **50×25mm**, 좌측 패널에서 수치 조정.
- **D-9 출력 단위:** 1개씩(simple) / 2개씩(doble = **같은 상품 2장**, 리스트 N개 → 2N장) 토글. 기존 simple/doble 프리셋에 매핑.
- **D-10 TAB3 UI:** 2패널 — 좌 = 라이브 프리뷰 + 수치 조정(폭/높이/QR 모듈/1:3 비율/폰트), 우 = 델타 리스트(NUEVO/CAMBIO 뱃지 + 체크박스).
- **D-11 스냅샷 시점:** 출력 **성공한 항목만** print-log upsert(부분 실패 안전 — 실패분은 다음 배치에 다시 잡힘).

## 컴포넌트 설계

### 1. 신규 테이블 `qr_print_log`

PG10/PG15 호환 마이그레이션 (`api-ventago/migrations/phase38-qr-print-log.sql`).

| 컬럼 | 타입 | 비고 |
|------|------|------|
| `id` | app-level 또는 serial | PK |
| `branch_id` | int NOT NULL | FK branches. 지점별 추적(D-4) |
| `product_id` | int NOT NULL | FK products. codigomadre parent |
| `price_type_id` | int NOT NULL | FK price_types. 어떤 가격 기준(D-5) |
| `printed_price` | numeric NOT NULL | 출력 당시 가격 스냅샷 |
| `printed_name` | text NOT NULL | 출력 당시 제품명 스냅샷 |
| `printed_at` | timestamptz NOT NULL | 마지막 출력 시각 |

- UNIQUE `(branch_id, product_id, price_type_id)` → upsert(`ON CONFLICT ... DO UPDATE`).
- 인덱스: `(branch_id, price_type_id)` (델타 조회용).
- Sequelize 모델 `QrPrintLog` (underscored:true → snake_case 자동).

### 2. 백엔드 — `print` 모듈

> **전송 계층 정정 (계획 중 2026-07-09):** 아래 REST 시그니처는 **`/print-agent` 소켓 ack**로 구현한다
> (`get_qr_pending` / `mark_qr_printed`). zebra-agent 는 소켓 API key(`handleConnection`→`client.data.branchId`)로만
> 인증되고 기존 에이전트 요청이 모두 `emitWithAck` 패턴이며 `print.controller` 는 웹 JWT 전용이기 때문.
> 데이터 계약·페이로드·D-6 도출 로직은 아래와 동일. 기존 `PrintService.buildQrPayload` 재사용 + base/PRECIO 1
> = `products.price` 폴백 보강. (아래 "REST" 표기는 데이터 계약 명세로 읽을 것.)

**`GET /print/qr/pending?priceTypeId={id}`** (에이전트 API key 인증):
- API key → BranchAgent → `branchId` → branch → `storeId` 도출.
- 매장의 codigomadre parent 상품 전체 조회 + 각 상품의 {priceTypeId} 현재 가격 계산
  (base/PRECIO 1이면 `products.price`, 그 외 `prices` 행).
- `qr_print_log`(branch_id, price_type_id) LEFT JOIN → 각 상품 판정:
  - 로그 없음 → `status: 'NUEVO'`
  - 이름≠printed_name 또는 가격≠printed_price → `status: 'CAMBIO'` (+ oldPrice/oldName)
  - 동일 → 제외
- 반환: `[{ productId, code, name, price, priceLabel, oldPrice?, status, qrUrl }]` (qrUrl 서버 조립).
- 성능/pool: 상품·가격·로그를 **단일/최소 쿼리 세트**로(N+1 금지), 필요 시 MemoryCache 짧은 TTL. codigomadre 수는 제한적이라 페이지네이션 불필요(대량이면 상한).

**`POST /print/qr/mark-printed`** body `{ priceTypeId, items: [{ productId, price, name }] }` (에이전트 API key):
- 서버가 branchId/storeId 도출 → 각 item을 `qr_print_log` upsert(printed_price/name/at 갱신).
- **성공 출력분만** 전달됨(D-11). 트랜잭션으로 일괄 upsert.

- 권한: 기존 print 컨트롤러/게이트웨이의 API key 인증 posture와 일관. 웹 유저 JWT 아님(에이전트 전용).
- Jest: pending 델타 판정(신규/변경/동일 3케이스 + price-type별 가격 계산 + store 격리), mark-printed upsert(신규 insert + 기존 update).

### 3. zebra-agent — `zpl-formatter.js` `formatQrLabel()`

```
formatQrLabel({ qrUrl, name, price, priceLabel, layout }) → ZPL 문자열
```
- `layout`: `{ widthMm, heightMm, qrModule, splitRatio, fontSize, mode: 'simple'|'doble' }` (기본 50×25, 1:3).
- 좌 패널: `^FO{x},{y}^BQN,2,{qrModule}^FDQA,{qrUrl}^FS` (QR = qrUrl 인코딩).
- 우 패널: 제품명(`^A0N` 굵게, 폭 초과 시 줄바꿈) + `{priceLabel}: {price}`.
- `mode:'doble'` → **같은 상품 2장**을 한 미디어에 나란히(기존 doble 프리셋 좌우 오프셋 재사용).
- 순수 함수 → 단위 테스트 용이(QR 페이로드 정확/1:3 좌표/doble 복제 검증).

### 4. zebra-agent — main.js IPC + renderer TAB3

- **preload.js:** `qrFetchPending(priceTypeId)`, `qrPrint(items, layout, mode)`, `qrMarkPrinted(...)` IPC 추가.
- **main.js:**
  - `qr:fetchPending` → 백엔드 `GET /print/qr/pending`(API key) 호출 → 리스트 반환.
  - `qr:print` → 선택 items를 `formatQrLabel`로 ZPL 생성(mode/layout 반영) → `sendZpl`(TCP/USB) 항목별 출력 → **성공분 수집**.
  - 성공분 → 백엔드 `POST /print/qr/mark-printed` 호출.
  - 실패분 → renderer로 실패 표시(스냅샷 미기록).
- **renderer/index.html:** TAB3 "QR" 추가(2패널, D-10):
  - price-type 드롭다운(백엔드에서 price_types 목록 — 기존 price-select 패턴 재사용) + 1개/2개 토글.
  - 좌: 라벨 프리뷰(canvas/HTML) + 수치 입력(폭/높이/QR모듈/비율/폰트) → layout 실시간 반영, label config로 저장.
  - 우: "Buscar cambios" → 델타 리스트 테이블(체크박스, NUEVO/CAMBIO 뱃지, 코드/이름/가격(구→신)). 전체선택 토글. "Imprimir seleccionados (N)".
  - UI 테마: 기존 다크 네이비(#1a1a2e) + 골드(#f5a623) 유지.

## 데이터 흐름

```
zebra-agent TAB3 [price-type 선택 + Buscar cambios]
  → IPC qr:fetchPending → main → GET /print/qr/pending?priceTypeId= (API key)
      → 백엔드: API key→branch/store, codigomadre×priceType 현재값 vs qr_print_log
      → [ {productId, code, name, price, status:NUEVO|CAMBIO, oldPrice?, qrUrl} ]
  → 우 패널 리스트 렌더 (체크박스)
사용자 체크 해제 → [Imprimir seleccionados]
  → IPC qr:print(items, layout, mode)
      → formatQrLabel() ZPL(1:3, mode) → sendZpl TCP9100/USB (항목별)
      → 성공분 수집
  → IPC/main → POST /print/qr/mark-printed { priceTypeId, items(성공분) }
      → qr_print_log upsert(printed_price/name/at)
  → 다음 Buscar 시 해당 항목은 델타에서 빠짐
```

## 에러 핸들링

- **프린터 오프라인/출력 실패:** 해당 행 실패 표시, **스냅샷 미기록** → 다음 배치에 재등장. 전체 배치 중단 아님(항목별 처리).
- **백엔드 미도달/API key 무효:** main에서 캐치 → renderer 에러 배너(에러 가시성 규약: 인라인 + 토스트).
- **priceTypeId/상품 무효:** 백엔드 400/404 → 프론트 인라인 노출.
- **부분 성공:** 성공분만 mark-printed(원자성은 mark-printed 트랜잭션 내에서만).

## 테스트 전략

- **백엔드 Jest:** `pending` 델타(NUEVO/CAMBIO/동일 + price-type별 가격 계산 + store 격리), `mark-printed` upsert(insert/update), 딥링크 URL 조립.
- **zebra-agent:** `formatQrLabel` 순수 함수(QR 페이로드 = qrUrl 정확, 1:3 좌표, doble=같은상품2장, layout 수치 반영).
- **에이전트 IPC:** fetchPending→print→markPrinted 흐름(성공/부분실패 시 mark-printed 호출 항목 검증).

## 범위 외 (YAGNI)

- 웹(CodigoVista) 행별 thermal QR 버튼 — **폐기/보류**(기존 2026-06-11 설계). 기존 print-agent `qr-formatter.js`는 미사용/재활용 가능.
- 자동 스케줄/이벤트 트리거 출력 — 수동 "Buscar cambios" 버튼만.
- 변형(자식) 상품 개별 QR — codigomadre parent만.
- QR 재고 뷰(스캔 후 화면) = Phase 37 Half B, 본 문서 범위 외.

## 의존성

- 백엔드: print.gateway/service/controller(기존, API key 인증), Product/PriceType/Prices/Branch 모델, 신규 QrPrintLog 모델 + 마이그레이션.
- zebra-agent: 기존 `zpl-formatter`/`zebra-printer`/label config IPC + 신규 QR IPC/탭.
- 환경: `PUBLIC_WEB_URL`(운영 `https://ventago.coolsistema.com`, dev 치환) — 딥링크 호스트.
- CI: zebra-agent 변경 시 `build-zebra-agent.yml` 태그 자동 증가(push-both.sh).
- 운영 DB: `phase38-qr-print-log.sql` PG10 수동 적용(마이그레이션 규약).

## 마이그레이션/배포 노트

- `qr_print_log`는 신규 테이블(멱등 `CREATE TABLE IF NOT EXISTS`) — 로컬 PG18 적용 후 운영 PG10 RUNBOOK.
- Phase 37(mobile) 딥링크 파서와 QR 포맷 **계약 일치** 회귀 검증(포맷 바뀌면 스캔 깨짐).

*Brainstorming 설계 완료 2026-07-09. 구현 계획은 /gsd-plan-phase 38 또는 writing-plans로 진행.*
