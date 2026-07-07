# SPEC: 채널별 Pedido 번호 + VentaVista 기본선택 + 결제모달리티 라벨

생성일: 2026-07-07

## 목표

POS "Internet Pedido"(envío) 흐름에서 (1) Canal 선택 시 채널별 독립 순차번호를 자동 채우고,
(2) VentaVista 목록의 Crédito·Internet(Envío) 필터를 기본 ON 으로 시작하며,
(3) EnvioRegistroModal 의 "Pago contra entrega" 라벨을 "Pago contra entrega (x Crédito)" 로 수정한다.

## 배경 및 컨텍스트

- **next-number 미리보기**: `online-orders.service.ts:getNextOrderNumberPreview(storeId)` 가
  매장 전체 `order_number` 최대값+1 로 `PED-XXXX` 단일 시퀀스만 반환. 컨트롤러
  `online-orders.controller.ts:@Get('next-number')` 가 storeId 만 넘김.
- **프론트**: `EnvioRegistroModal.tsx` 가 모달 open 시 1회만 `GET /online-orders/next-number`
  호출. Canal 은 chip(`CHANNELS`)으로 전환하지만 번호는 재조회 안 함.
- **결제 모달리티**: `EnvioRegistroModal.tsx:PAYMENT_MODES` 의 `contra_entrega` 라벨이
  'Pago contra entrega'. 이 화면엔 결제 기록 입력이 없어 contra_entrega = 사실상 외상(crédito).
- **VentaVista 필터**: `SalesListView.tsx` 의 filters 초기값 `showCredito:false, showInternet:false`.
  toolbar(`SalesListToolbar.tsx`)의 Phase 44 체크박스 2개와 연동.
- **채널 enum**(`online-order.model.ts:OnlineOrderChannel`): mercadolibre|webshop|instagram|whatsapp|other.

## 기술 스택

- 백엔드: NestJS 11 + Sequelize (PostgreSQL 10 운영 / 15·18 로컬)
- 프론트: Next.js 13 + MUI 5 (TS)
- ESLint: 프로젝트 규칙 (Warning=Error, newline-before-return / lines-around-comment 등)

## 설계 결정

**채널별 접두사(prefix)** — 사용자 확정:
| channel | prefix |
|---|---|
| mercadolibre | MELI |
| webshop | WEB |
| instagram | IG |
| whatsapp | WSP |
| other | OTRO |

**시퀀스** — 채널별 독립. 각 채널의 기존 `external_order_number` 중 `^PREFIX-[0-9]+$`
패턴의 최대 숫자 접미사 + 1 (없으면 1). 포맷 `PREFIX-####`(4자리 zero-pad).
외부 플랫폼 원본번호(WordPress/ML 등)는 패턴 불일치라 시퀀스에 영향 없음.

**Pool 안전**: 채널 전환 1회당 read 쿼리 1건(Sequelize 모델 경유, 자동 pool 관리 —
수동 connect/release 없음). `MAX(CAST(...))` 단일 집계라 행 fetch 없음.

## 태스크 목록

- [ ] TASK-1: `getNextOrderNumberPreview(storeId, channel?)` 로 시그니처 확장 —
  채널별 prefix 맵 + `^PREFIX-[0-9]+$` 최대 접미사+1 집계(단일 read). 미지정 시 webshop(WEB) fallback.
  — 파일: `api-ventago/src/app/online-orders/online-orders.service.ts`
- [ ] TASK-2: `@Get('next-number')` 에 `@Query('channel') channel?` 추가 후 서비스 전달.
  — 파일: `api-ventago/src/app/online-orders/online-orders.controller.ts`
- [ ] TASK-3: `EnvioRegistroModal` — next-number fetch 를 함수로 추출, open + channel 변경 시
  `?channel=` 붙여 재조회하여 orderNumber/placeholder 갱신.
  — 파일: `ventago-app/src/views/homes/components/ProductList/components/EnvioRegistroModal.tsx`
- [ ] TASK-4: `EnvioRegistroModal:PAYMENT_MODES` contra_entrega 라벨 →
  'Pago contra entrega (x Crédito)'.
  — 파일: `ventago-app/src/views/homes/components/ProductList/components/EnvioRegistroModal.tsx`
- [ ] TASK-5: `SalesListView` filters 초기값 `showCredito:true, showInternet:true`.
  — 파일: `ventago-app/src/views/sales/list/SalesListView.tsx`
- [ ] TASK-6: ESLint 검증 (`npx eslint --fix` 변경 파일) — 오류 0
- [ ] TASK-7: PostgreSQL pool 안전 점검 (신규 쿼리 단일 read, release 불필요 확인)

## 완료 기준

- Canal chip 전환 시 Nro. de Pedido 가 해당 채널 prefix + 다음 순번으로 즉시 갱신
- VentaVista 진입 시 Crédito·Internet(Envío) 체크박스 기본 체크
- contra_entrega 라벨이 "Pago contra entrega (x Crédito)"
- ESLint 오류 0, pool 낭비 없음(단일 read)

## 금지사항 / 주의사항

- `external_order_number` 유니크(store 범위) 로직·중복검사(createFromPos) 는 건드리지 않음
- 내부 `order_number` 자동 시퀀스/충돌 재시도 로직 변경 금지 (표시용 preview 만 채널화)
- PG10 호환: `SUBSTRING(... FROM 'regex')`, `~` 정규식, `CAST(... AS INTEGER)` 만 사용
  (신규 문법 회피). 파라미터 바인딩으로 SQL 인젝션 방지.
- 프론트: 사용자가 orderNumber 를 수동 편집했더라도 채널 전환 시 새 제안값으로 덮어씀(제안값 특성)
