# PEDIDO 9 — Zebra 에이전트: 「Stocks」 체크 → 날짜 없이 코드·이름으로 찾고 현재 재고 수량 표시

## 요청 원문 요약
- 매장: Cielo (store 22) · 지점: Cielo (지점 1개, branch 31, zebra 에이전트 1대) · 작성자: Joo Eun Um · 2026-10-05 12:55 (매장 시각)
- 원문: «agregue un boton de check.. "Stocks" cuando activo.. y tipeo codigo y descripcion en input box "busqueda", aparezca items k coincide y cantidad actual.. asi pueda imprimir etiqueta sin buscar la fecha de ingreso de articulos»
- **분류: 개선** (zebra-agent + api)

## 현재 동작 (코드 근거)
- 「Productos」 카드는 **입고일 단위로만** 찾습니다.
  - `zebra-agent/renderer/index.html:225-245` — 검색창 + 날짜 + 지점 + Buscar
  - 같은 파일 `:1423-1430` — 2026-09-30 요청으로 «검색어는 그날·그 지점 목록 안에서만 거른다»로 바꿨습니다
    (그 전엔 전체 카탈로그를 찾아서 「kren」 → 아무 날의 KRENCIA 50개가 나왔다는 불만).
  - `:1446` `api.fetchProductsByDate` → WS `get_stock_today` → 그날 입고분만 반환
  - Cant. 기본값 = 그날 입고 수량 (`:1537` `stockAddedToday`)
- ★ **전체 상품 검색 경로는 이미 있지만 화면에서 안 씁니다.**
  - 서버: `api-ventago/src/app/print/print.gateway.ts:505` `search_products` → `print.service.ts:769` `searchProductsForAgent`
    (SKU/이름 부분일치, 매장 격리, madre 제외, 최대 100건)
  - 에이전트: `main.js` `products:search`, `preload.js:40` `searchProducts` — renderer 에서 호출하는 곳 0건
  - 단, 이 응답엔 **재고가 없습니다**: `stockAddedToday: 0` 고정 (`print.service.ts` rows 매핑).

그래서 오래전에 입고된 상품의 라벨을 찍으려면 입고일을 기억해서 찾아가야 합니다.

## 제안 (권고안)
**「Stock actual」 체크박스로 검색 모드를 전환** — 기본은 지금처럼 「입고일」 모드, 9-30 요청의 동작은 그대로 유지.

1. **app(에이전트) 화면** — 검색창 오른쪽에 체크박스 **«Stock actual»** (요청 표현 «Stocks»)
   - 켜면: 날짜 칸 비활성(흐리게), 안내문 → «Busca en todo el catálogo de la sucursal y muestra el stock actual»
   - 2자 이상 입력(300ms 디바운스) / Enter / Buscar → 기존 `searchProducts` 호출
   - 표에 **「Stock」 열**(읽기 전용, 현재 재고) 추가. Cant. 기본값 = **현재 재고**(0 이하면 1, 편집 가능)
   - 100건이 차면 «Se muestran 100 — escribí más para afinar» 표시
   - 끄면 지금의 입고일 모드로 복귀. 마지막 모드는 에이전트 설정에 기억
2. **api** — `searchProductsForAgent` 응답에 `stock` 필드 추가
   - 지점 = 선택 지점, 없으면 에이전트 지점
   - `stock_balances.on_hand` 를 **`product_branch_id` 기준**으로 1회 SELECT (CLAUDE.md 재고 읽기 규약 — `products.stock` 금지)
   - 행이 없으면 0. 쿼리 3 → 4회, limit 100 유지
   - `stockAddedToday` 는 그대로 0 (의미가 다른 값이라 섞지 않음)

### 결정해 주실 점
- **Cant. 기본값**: 권고 = 현재 재고. 대안 = 1장. 재고가 큰 상품을 「Todos」로 찍으면 장수가 많아지므로,
  **합계가 200장을 넘으면 확인창**을 띄우는 것을 같이 넣기를 권합니다.
- **재고 값**: `on_hand`(실물) 권고. 대안 = `available`(예약분 제외).

### 범위 밖
- 「Todas las sucursales」 선택 시 전 지점 합계(Cielo 는 지점 1개라 해당 없음 → 에이전트 지점 기준)
- QR 탭 검색(별도 경로 `get_qr_pending`)
- 재고 0 상품 숨김 옵션

## 영향
- **api**: `print.service.ts` 응답 필드 1개 추가(추가형) — 구 에이전트는 무시하므로 안전
- **zebra-agent**: renderer 변경 → **새 릴리스 필요**(현재 태그 `zebra-agent-v1.0.30` → v1.0.31 — PEDIDO 10 과 같은 renderer 파일이라 한 릴리스로 묶기 권장). 태그를 손으로 올려 Actions 빌드
  (로컬 electron-builder 금지 — 루트 node_modules 손상 전례). 매장 PC 는 자동 업데이트로 받음
- **배포 순서**: api 먼저 → 에이전트. 반대로 가면 새 에이전트가 「Stock」 열을 「-」로 보여 줄 뿐 깨지지는 않음
- DB 마이그레이션: 없음 · 다른 매장: 체크를 켜야만 동작이 바뀜(기본 모드 동일) · 위험: 낮음
- 테넌트 격리: 기존 `search_products` 가 API key 의 지점→매장으로 이미 격리. 선택 지점이 **그 매장 지점인지** 서버에서 검증 추가

## 규모 · 검증
- 규모: **S~M** (api 1 함수 + spec, renderer 1 파일, 에이전트 릴리스)
- 검증:
  - api jest: `searchProductsForAgent` — 재고 반환, 행 없음=0, 다른 매장 지점 id 를 넘기면 무시
  - 돌연변이: `product_branch_id` 조건 제거 / 지점 조건 제거 시 spec 이 실패하는지
  - 에이전트 smoke + 로컬에서 Cielo 데이터로 「Stock actual」 켜고 SKU·이름 검색 → 재고 = `stock_balances.on_hand` 대조
  - 끈 상태에서 9-30 동작(그날 목록 안에서만 거름) 회귀 없음 확인
- 운영 반영: 낮(08–16)이면 직전 활동 사용자 수 측정 후

## 목업
`mockup.png` — 왼쪽 현재(입고일 모드) / 오른쪽 제안(Stock actual 켬)

## 구현 결과 (2026-10-06)
- 결정: 권고안 그대로 — Cant. 기본값 = 현재 재고(0 이하 → 1), 200장 초과 시 확인창, 재고 = `on_hand`.
- api `4227231e` (Jenkins #1091 SUCCESS): `searchProductsForAgent` 응답에 `stock`. payload 지점은 같은 매장일 때만 사용.
  spec 4건 + 돌연변이 3건(매장 검증 제거 · 지점 필터 제거 · store_id 조건 제거) 전부 잡힘.
- zebra-agent `56a4c64`, 태그 **zebra-agent-v1.0.31** (Actions 성공, ventago-downloads 에 exe·dmg 2개).
- CODEX: 모드 전환 중 날짜 모드 응답이 덮어쓰는 경합 지적 → 반영. 「재고 0 → 1장」 지적은 계획서 결정대로 유지.
- 검증: 스텁 API 로 renderer 를 브라우저에 띄워 확인(검색·Stock 열·Cant.·200장 확인창·모드 복귀). 실제 매장 PC 에서는 미확인.
