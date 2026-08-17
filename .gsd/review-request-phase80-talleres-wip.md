# 자문 요청 — Phase 80: 생산 중(WIP) 수량·완성 예상시점을 Stocks 리포트에 노출

당신은 이 저장소(Ventago POS/ERP — NestJS + Sequelize + PostgreSQL 18 + Next.js 13 + MUI 5)의
시니어 리뷰어입니다. **비판적으로** 검토해 주세요. 아직 구현 전, 설계 단계입니다.

## 사용자 요구 (원문 요약)

1. Talleres 에서 어떤 상품이 생산 과정에 들어가면 **예상 완성 시간을 대략 기록**할 수 있으면 좋겠다
2. Stocks & Reportes 화면 **맨 마지막 열**에 ① 몇 장이 생산 과정에 있는지 ② 완료 예상 시점을 표시
3. **"1000장이 생산에 들어갔고 지점이 2개면 각 지점 500장"** 으로 지점별 표시
4. 아직 공정이 많이 남았으면 예상 완료시점은 **"미정"**, 마지막 또는 penúltima 공정이면 대략 표시
5. 이 정보(WIP 수량·예상시점)는 **권한 가진 사람만** 볼 수 있게, 매장 admin 이 사용자별로 조정

## 내가 실측한 것 (운영 DB + 코드, 2026-08-17)

### 지점 정보가 있는 곳
| 테이블 | 지점 컬럼 |
|---|---|
| `talleres_lotes` (생산 로트) | **없음** |
| `talleres_envios` (공정 발송) | **없음** |
| `talleres_recepciones` (수령) | `target_branch_id` — 여기서 처음 정해진다 |

→ 생산 중 WIP 에는 **지점이 존재하지 않는다.** 지점은 완성품 수령 시점에 결정된다.

### ETA 원본은 이미 있다
- `talleres_envios.due_date` (date) — 공정별 납기. 운영 3건 중 3건 채워져 있음
- `talleres_lotes.routing_path` (jsonb) — 공정 순서 전체. 운영 5건 전부 존재
  예: `[{"order":1,"etapaId":1,"etapaName":"corte"}, ... {"order":5,"etapaName":"planchero"}]`
- `talleres_etapas` 에 **소요시간 컬럼 없음**

### 운영 데이터 규모
- `talleres_lotes` 5건(760장), `talleres_envios` 3건(전부 `COMPLETED`)
- envío 상태 enum: `PENDING` · `PARTIAL` · `COMPLETED` · `CANCELLED`

### 붙일 자리
- 서버: `api-ventago/src/app/reports/reportsStocksCockpit.service.ts` 의 `getItems()`
  — 제품 목록을 raw SQL 한 방으로 만든다. 정렬은 `sortWhitelist` 로 관리
- 화면: `ventago-app/src/views/reports/stocks/panels/PanelB_ItemTable.tsx`
- 권한: `functions.seed.ts` 에 항목 추가 → slug → `@FunctionGuard('<slug>','read')`
  (`reporte-stocks`, `reporte-items` 가 같은 패턴)

## 내가 사용자에게 한 제안과, 사용자의 결정

- **나**: 지점별 균등 분배는 **데이터가 아니라 추측**이므로 하지 말자.
  전 지점 합계(TOTAL 행)에서만 보여주고 지점 선택 시 `— (sin asignar)`.
  꼭 지점별로 봐야 하면 로트에 **계획 배분을 사람이 직접 입력**하자.
  이유: 이 화면은 발주·이동 판단에 쓰인다. "곧 500장 온다"를 보고 발주를 미뤘는데
  실제로 0장이 오면 그 지점은 품절로 남고, **틀렸다는 걸 알아챌 방법이 없다.**
- **사용자 결정**: ③ **균등 분배로 진행**한다.
- 나는 이 결정을 받아들이고, 대신 **화면이 추정치임을 스스로 말하도록** 하려 한다.

## 계획 초안

**W1 (새 컬럼 0개 — 기존 데이터만)**
- 집계 CTE 한 번으로 `product_id → (wip_qty, no_iniciado, eta_date, etapas_restantes)`
  - `wip_qty` = 열린 envío(`PENDING`/`PARTIAL`) 의 `pending_quantity` 합
  - `no_iniciado` = `lote.total_quantity − lote.stocked_quantity − wip_qty`
  - `etapas_restantes` = `routing_path` 길이 − 현재 공정 order
  - `eta_date` = `etapas_restantes <= 2` 이면 열린 envío 의 `max(due_date)`, 아니면 NULL(=미정)
- `getItems()` 에 LEFT JOIN (Flutter 소비자가 있으므로 **필드 추가만**)
- PanelB 마지막에 열 2개: `En producción` / `Listo aprox.`
- 지점 선택 시 `wip_qty / 지점수` (균등 분배) — **"≈ estimado" 표기 + 툴팁**으로 추정임을 명시
- 권한 slug 신설, 없으면 **열 자체를 숨김**(값 마스킹 금지 — 합계·CSV·PDF 로 샌다)

**W2** 수동 ETA(`talleres_lotes.estimated_ready_date`) + "언제 적었는지" 함께 표시
**W3** 계획 배분 명시 입력(균등 분배를 대체할 수 있으면)
**W4** 실적 기반 리드타임 (완료 로트가 쌓인 뒤)

## 질문

1. **균등 분배**를 사용자가 선택했다. 이걸 안전하게 만들려면 표시·API 설계에서 무엇을 반드시
   해야 하는가? (예: 필드명에 `estimated` 를 넣기, 합계 행과 지점 행의 정합성, 반올림 잔여 처리 —
   1000/3 처럼 나누어떨어지지 않을 때 합이 원본과 어긋나는 문제)
2. **"현재 공정"** 판정 방법이 맞는가? 나는 열린 envío 의 `etapa_id` 를 `routing_path` 에서 찾아
   `order` 를 얻으려 한다. 그런데 한 로트에 **여러 공정의 envío 가 동시에 열려 있을 수 있고**
   (분할 발송), rework(`rework_order_id`)로 **되돌아가는 경로**도 있다. 어떻게 정의해야 하는가?
3. `wip_qty` 의 정의로 열린 envío 의 `pending_quantity` 합이 맞는가?
   `talleres_recepciones` 의 부분 수령·불량(`rejected_quantity`)과 이중 계산될 위험은?
4. ETA 를 `max(due_date)` 로 잡는 것이 맞는가? due_date 가 **과거**인 경우(지연)는 어떻게 보여야
   하는가 — 지난 날짜를 그대로 "완료 예정" 으로 보여주면 거짓말이 된다.
5. 권한: 열 숨김 외에 **정렬·엑셀/PDF export·집계 합계**까지 막아야 할 곳이 어디인가?
   `getItems` 는 export 경로(`getItemsForExport`)를 공유한다.
6. 성능: 제품 목록(pageSize 최대 50, export 는 더 큼)에 이 집계를 LEFT JOIN 할 때
   주의할 점은? 인덱스가 필요한가?
7. 그 밖에 놓친 위험 — 특히 **조용히 틀린 값이 나오는** 경로.

## 읽어야 할 파일

- `api-ventago/src/app/reports/reportsStocksCockpit.service.ts` (getItems / getItemsForExport)
- `api-ventago/src/app/reports/reports.controller.ts` (FunctionGuard 패턴)
- `api-ventago/src/app/subcon/` (talleres 도메인 서비스)
- `ventago-app/src/views/reports/stocks/panels/PanelB_ItemTable.tsx`
- `.planning/intel/db-schema-tables.md` (talleres_* 테이블)
- `.planning/phases/80-talleres-wip-visibility-in-stocks-report/80-FINDINGS.md`
- `CLAUDE.md` (쓰기 경로 규약 · 성능 규약)

## 출력 형식

**총평** → **반드시 고쳐야 할 것(Blocker)** → **고치는 게 좋은 것(Should)** → **선택(Nice)**.
각 항목에 `[근거: 파일:줄]` 과 **구체적 대안**을 붙일 것.
