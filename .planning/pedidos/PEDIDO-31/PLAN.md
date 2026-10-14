# PEDIDO 31 — Zebra 라벨: 「Sin precio」 저장해도 가격이 찍힘 · Modo Duplicado 매수 2배

## 요청 원문 요약
- 매장: coolsistema (store 6) · 작성자 is.smc@gmail.com (user 16) · 2026-10-14 08:53
- 원문: 「cuando se selecciona imprimir sin precio y se guarda Precio, imprime con precio. Ahora cuando se
  selecciona para imprimir 2 en el modo duplicado, imprime cuatro etiquetas en total, al parecer cuando
  duplica toma como uno la fila.」
- 사진 1: zebra-agent › Etiqueta 탭. Modo Duplicado 선택, Precio 1·2·3 모두 「— Sin precio —」.
  그런데 Vista previa 에 **$12.999,00 가 그대로** 찍혀 있습니다.
- 사진 2: 실제 출력. 같은 상품(JEAN LONDON 2026 NARANJA) 스티커 **4장(2줄 × 좌우)**, 모두 「PRECIO 1 $100」.
- **분류: 버그 2건** (zebra-agent 단독, api·app·DB 변경 없음)

## 버그 1 — 「Sin precio」 를 저장해도 가격이 찍힌다

### 현재 동작
- 화면 안내문: 「"— Sin precio —" en todos = no se imprimen precios」 (`zebra-agent/renderer/index.html:553`)
- 저장: 세 칸 모두 Sin precio → `priceSelection = []` 저장 (`zebra-agent/main.js:461-471`, 주석도 「[] = 가격 미출력」)
- **그런데 출력 쪽은 `[]` 를 「한 번도 설정 안 함」 으로 읽습니다** —
  `zebra-agent/src/price-select.js:20-25`: 선택이 비어 있으면 *하위 호환*으로 서버 가격의 앞에서 `priceCount`(기본 1)개를 그대로 씁니다.
  `main.js:141-150` `getPrintMode` 도 선택이 1개 이상일 때만 `priceCount` 를 덮어씁니다.
- 결과: 「아무 가격도 안 고름」 과 「아직 설정한 적 없음」 이 같은 값(`[]`, 저장소 기본값도 `[]` — `main.js:43`)이라
  구별이 안 되고, 항상 첫 번째 가격(PRECIO 1)이 찍힙니다. 미리보기도 같은 함수를 타서 같이 틀립니다(`src/vista-zebra.js:97-110`).

### 제안 (권고)
- 「저장한 적 있음」 표시를 따로 둔다: `label:setPriceSelection` 이 `priceSelectionGuardada: true` 를 함께 저장.
- `selectItemPrices`: **저장한 적 있음 + 빈 선택 → 가격 0개.** 저장한 적 없음 + 빈 선택 → 지금처럼(하위 호환).
- `getPrintMode` · 미리보기: 같은 규칙으로 `priceCount = 0`. (`renderCopy` 는 0 이면 가격을 안 그림 — `src/zpl-formatter.js:432-434`)
- ★ **coolsistema 는 업데이트 후 「Guardar niveles」 를 한 번 더 눌러야 합니다.** 지금 저장된 `[]` 는 표시 없이
  저장된 값이라 「설정 안 함」 과 구별할 수 없습니다. 매장 답장에 이 한 줄을 넣습니다.
- 대안: `[]` 를 무조건 「가격 없음」 으로 읽기 — 한 번도 설정 안 한 다른 매장 설치본이 업데이트 순간 **가격이 사라집니다.** 권고하지 않습니다.

## 버그 2 — Modo Duplicado 에서 「2」 를 찍으면 스티커 4장

### 현재 동작
- Modo Duplicado = 100×25mm 롤, 한 줄에 스티커 2장(izq + der).
- 바코드 라벨 1장(`formatLabel`)이 **왼쪽·오른쪽에 같은 상품을 둘 다** 그립니다 (`src/zpl-formatter.js:545-558`).
- 일괄 출력은 수량만큼 그 **줄**을 반복합니다 (`src/zpl-formatter.js:707-716`).
  → 수량 2 = 2줄 = 스티커 4장. 매장 직원이 짚은 그대로 「한 줄을 1로 센다」.
- QR 라벨은 이미 2026-10-03 에 고쳐져 있습니다: 수량 = 스티커 수, 줄을 상품 사이에서 이어 채움(`qrLoteFilas`, `:642-666`).
  **바코드만 옛 방식**으로 남은 것입니다.

### 제안 (권고)
- 바코드도 QR 과 같은 규칙: **수량 = 스티커 장수.** 모든 상품의 스티커를 순서대로 늘어놓고 2장씩 한 줄에 채움.
  - 2장 → 1줄 · 3장 → 2줄(마지막 줄 오른쪽은 비움) · A 1장 + B 1장 → 1줄(왼 A · 오른 B)
- `formatLabel` 에 「오른쪽 칸 상품」 인자를 추가(없으면 오른쪽 비움). 기존 1줄 1상품 호출은 그대로 동작.
- 화면·로그의 「N etiqueta(s)」 는 **스티커 수**를 그대로 표시(이미 단위 수를 세고 있어 숫자가 맞게 됩니다).
- 「Imprimir 1 de prueba」 는 지금처럼 1줄(바코드 = 왼쪽 1장 + 오른쪽 같은 상품 1장)로 유지 — 시험 출력은 줄 단위가 자연스럽습니다.
- 웹에서 보내는 출력(Productos › Imprimir x ZPL → `print_barcode`, `main.js:1073`)도 같은 함수라 같이 고쳐집니다.
- 대안: 상품마다 줄을 새로 시작(A 1장 + B 1장 → 2줄, 각 줄 오른쪽 비움). 상품 경계가 분명하지만 스티커가 남습니다.
  QR 과 규칙이 달라지므로 권고하지 않습니다.

## 범위 밖
- Simple Face · Doble Face · Poliamida 는 한 줄에 1장이라 영향 없음(그대로).
- PEDIDO 32(Print Agent 「Actualizar」 가 앱만 닫힘)는 별건. 다만 **zebra-agent 도 같은 업데이트 구조**
  (`src/updater.js`)라, 32 원인이 공통이면 이번 수정판이 매장에 설치되지 않을 수 있습니다 → 배포 후 매장 설치 버전을 로그로 확인합니다.

## 영향
- 파일: `zebra-agent/src/price-select.js` · `main.js` · `src/zpl-formatter.js` · `src/vista-zebra.js` · `test/*`
- api / app / DB: **없음**
- 다른 매장: zebra-agent 쓰는 모든 매장에 적용.
  - Duplicado 를 쓰는 매장은 **같은 수량에 스티커가 절반**이 됩니다 — 지금까지 2배로 나와서 수량을 절반으로 넣어 쓰던 매장이 있으면 그 매장엔 「줄어든」 것으로 보입니다. 매장 답장·릴리스 노트에 명시.
  - 가격: 「Guardar niveles」 를 누른 적 없는 설치본은 변화 없음.
- 배포: 태그 `zebra-agent-v1.0.39` 수동 push → GitHub Actions 빌드 → 매장에서 업데이트 수락.

## 규모 · 검증
- 규모: **S**
- 단위 시험(node): ① 저장함+빈 선택 → 가격 0 ② 저장 안 함+빈 선택 → 첫 가격(하위 호환) ③ Duplicado 수량 2 → `^XA` 1개, 왼·오른 둘 다 ④ 수량 3 → `^XA` 2개, 둘째 줄 오른쪽 없음 ⑤ A1+B1 → 1줄 ⑥ Simple Face 수량 2 → `^XA` 2개(변화 없음)
- 돌연변이: 「빈 선택 → 0」 분기를 지우면 ①이 죽는지, 이어 채우기를 줄 단위로 되돌리면 ③이 죽는지.
- 「Vista Zebra」(emulador)로 수정 전·후 ZPL 을 그려 비교.

## 매장 답장 초안 (승인 후 배포가 끝나면)
> ¡Hola! Ya corregimos los dos puntos en el Zebra Agent v1.0.39:
> 1. **Sin precio**: después de actualizar, entrá a Etiqueta, dejá los tres en «— Sin precio —» y tocá **Guardar niveles** una vez más. Desde ahí las etiquetas salen sin precio (la vista previa también).
> 2. **Modo Duplicado**: la cantidad ahora es la cantidad de **etiquetas** (stickers), no de filas. Si pedís 2, sale una fila con 2 etiquetas. Si pedís 3, salen 2 filas y la última con el lado derecho vacío.
> Cualquier cosa nos avisás por acá.
