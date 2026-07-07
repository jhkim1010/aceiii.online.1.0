# SPEC: zebra-agent 라벨 설정 페이지 + 4모드 ZPL 출력
생성일: 2026-07-07

## 목표
zebra-agent에 4가지 출력 모드(simple face / doble face / modo duplicado / poliamida vertical)와
요소별 위치·크기 설정 UI(실시간 미리보기 포함)를 구축하고, 서버 print_barcode 명령을
설정대로 정확하게 ZPL 출력한다.

## 배경 및 컨텍스트
- 현재 zebra-agent에는 3개 프리셋(50x25-simple, 50x25-doble, 100x25-cartulina)과
  X/Y 위치만 편집 가능한 간이 레이아웃 에디터 존재.
- 서버 흐름은 이미 완성: `POST /print/barcode` → `emitPrintBarcode` →
  socket `print_barcode` → agent `formatBatchLabels` → `sendZpl`.
  payload: `{ items: [{ name, sku, barcodeType, prices:[{label,amount}], qty }], agentId? }`
- 백엔드/DB 변경 없음 → PostgreSQL pool 영향 없음.
- 2026-07-07 로그 확인: error 0건, pool 정상 (size=10 using=0).

## 기술 스택
- Electron 28 (zebra-agent), 순수 JS (renderer는 단일 HTML)
- 설정 저장: electron-store
- ESLint: zebra-agent 자체 설정 없음 → `node --check` 문법 검증으로 대체
- DB: 사용 안 함 (pool 규칙 해당 없음)

## 출력 모드 정의 (4종)
| key | 이름 | 미디어 | 특징 |
|---|---|---|---|
| `simple-face` | Simple Face | 50x25mm | 단면 1장 (기존 50x25-simple) |
| `doble-face` | Doble Face | 50x25mm | 접이식 양면 배치 (기존 50x25-doble) |
| `modo-duplicado` | Modo Duplicado | 100x25mm | 좌+우 동일 내용 복제 (기존 cartulina) |
| `poliamida-vertical` | Poliamida Vertical | 25x50mm | 세로 리본 — 텍스트/바코드 90° 회전(^A0R/^BCR) |

## 설정 항목 (모드별 독립 저장 `labelLayouts[modeKey]`)
- 제품 설명(name): X, Y, fontSize
- 바코드: X, Y, height, moduleWidth(1~4)
- 가격: **precio nivel 선택 (0~3개)** — 서버에서 nivel 목록을 받아 선택.
  가격 값 자체는 서버 print_barcode payload로 전달됨 (수동 입력 없음).
  선택된 nivel 순서 = price1/2/3 슬롯. 각 슬롯 X, Y, fontSize.
  선택 0개 = 가격 미출력. 선택 없음(미설정) = payload 순서대로 1개 (하위 호환).
- 라벨 크기(고급): width/height dots 편집 가능 (poliamida 리본 길이 대응)

## 추가 요구 (사용자, 2026-07-07)
1. 셋업 화면에 **실시간 미리보기** — 1장(또는 duplicado는 1줄) 렌더 ✅
2. 가격은 운용서버 전달 — 셋업은 **precio nivel 콤보박스 선택만** ✅
3. print-agent처럼 **연결된 매장/지점/터미널 표시** ✅
4. 프린터 선택: network 폼 대신 **감지된 프린터 리스트(USB+RED) 우선**, 클릭 선택, 수동은 fallback ✅
5. **출력 밀도/속도 조절** — ~SD(0~30) 배치당 1회, ^PR(2~14 ips) 라벨별, 모드별 저장, 빈값=프린터 기본 ✅
6. **nivel 라벨 소형화** — 가격 폰트의 1/4 (최소 12dot), 금액 바로 위에 별도 표시 ✅
7. **가격 자동 배치** — 오른쪽 하단부터 가로로 (Precio 1 = 맨 오른쪽), autoPrices 체크박스 (기본 ON, 해제 시 수동 X/Y) ✅
8. **바코드 auto-fit** — 문자 포함 긴 SKU 시 module width 자동 축소 (설정값→1), CODE128 모듈 수 (n+2)*11+13 추정 ✅

## 백엔드 소규모 변경 (허용 범위)
- print.gateway.ts: `get_price_types` SubscribeMessage (ack 콜백) — 인증된 에이전트의
  지점→매장 precio nivel 목록 반환. pool 안전: 단일 SELECT 2회, findAll attributes 최소화.
- ventago-app ProductsList.tsx: prices payload에 `priceTypeId` 추가 (하위 호환 유지).

## 실시간 미리보기 (사용자 요청)
- 설정 탭에 canvas 미리보기 — 값 변경 즉시 다시 그림 (input 이벤트)
- 샘플 데이터로 렌더: 이름, 바코드(막대 패턴 + 숫자), 가격 1~3
- modo-duplicado: 100mm 1줄 전체(좌+우 복제) 표시
- poliamida-vertical: 세로 방향으로 회전된 모습 표시
- 실제 dot 좌표계를 스케일 변환하여 ZPL 결과와 1:1 대응

## 태스크 목록
- [x] TASK-1: zpl-formatter.js — 4모드 프리셋, priceCount, 요소 크기, 세로(R) 렌더 — 파일: zebra-agent/src/zpl-formatter.js
- [x] TASK-2: main.js — labelMode/labelLayouts 저장 구조(구버전 마이그레이션), print_barcode·print:labels에 nivel 필터 적용 — 파일: zebra-agent/main.js
- [x] TASK-3: renderer/index.html — Etiqueta 탭 신설: 모드 카드 4종, nivel 콤보박스 3개, 요소별 편집기, canvas 실시간 미리보기, 터미널 표시 — 파일: zebra-agent/renderer/index.html
- [x] TASK-4: preload.js — setPriceSelection / fetchPriceTypes IPC 노출 — 파일: zebra-agent/preload.js
- [x] TASK-5: 백엔드 get_price_types ack 핸들러 + listPriceTypesByBranch + 프론트 priceTypeId 동봉
- [x] TASK-6: 검증 — node --check 4파일, ZPL 스냅샷(4모드×가격 0/2/3, legacy alias, batch qty), eslint(api/app 파일), tsc --noEmit 모두 통과

## E2E 검증 (2026-07-07)
- 체인 추적: ProductsList(Imprimir x ZPL) → POST /print/barcode (JWT, user.branchId) →
  emitPrintBarcode → branch room broadcast → agent print_barcode → prepareItems → formatBatchLabels → sendZpl
- stock-today 응답에 Price+PriceType include 확인 → payload 에 priceTypeId/label 실림
- thermal print-agent 는 print_barcode 핸들러 없음 → broadcast 무해
- nivel 매칭 로직을 `zebra-agent/src/price-select.js` 순수 모듈로 분리 (main.js 공용)
- `zebra-agent/test/print-flow.test.js` — 28개 체크 전부 통과
  (nivel 필터/순서/이름 fallback, 4모드, 회전, duplicado 복제, ~SD/^PR, auto-fit ^BY1,
   sanitize, 문자열 금액, 가격 없음, qty 반복, null 방어)
- 단위 dots↔mm 전환 (1mm=8dots), 저장은 dots
- 제약: 샌드박스에서 api jest 실행 불가 (bcrypt Mac 바이너리) → Mac 에서 실행 필요

## 완료 기준
- 4모드 모두 ZPL 생성 정상 (^XA…^XZ, 회전 모드는 ^A0R/^BCR)
- priceCount=0 시 가격 미출력, payload 가격 3개+priceCount=2 시 2개만 출력
- 미리보기가 설정값 변경에 즉시 반응
- 구버전 설정(labelPreset/labelLayout) 자동 마이그레이션 — 기존 사용자 설정 유실 없음
- node --check 오류 0개

## 금지사항 / 주의사항
- 서버(api-ventago)·프론트(ventago-app) 변경 금지 — payload 하위 호환 유지
- print_barcode payload 형식 변경 금지 (기존 ProductsList 전송 코드 그대로 동작해야 함)
- SERVER_URL 고정 유지, API Key 인증 흐름 변경 금지
- push는 사용자 승인 후 (push-both.sh가 태그 증가 → CI 빌드 트리거하므로)
