# 핸드오프 2026-09-27 (b) — Admin › Impresoras (커밋됨·미배포) · 결정된 다음 작업 2개

> 앞 문서: `HANDOFF-2026-09-27-ganancia-impresoras-cambio.md` (그 뒤에 나간 것은 §1).
> ★★ **첫 작업: §2 의 운영 시드 승인 → 적용 → push.** api·app 이 각각 **1커밋 ahead(미push)** 다.
>   시드 없이 코드가 먼저 나가면 `/print/overview` 가 FunctionGuard 에서 거부되고 메뉴도 안 보인다.

## 1. (a) 이후 운영에 나간 것

| 내용 | api | app | Jenkins |
|---|---|---|---|
| 히스토리·상세 재인쇄 프린터 선택 (`GET /sales/:id/printers`) | `9ae7372c` | `c296d816` | #980 · #823 |
| Ventas 보고서 Costo·Ganancia 칼럼 (reporte-ganancia 권한일 때만) | `9d76df14` | `b36f96f5` | #981 · #824 |
| auto impTiq = 선택 프린터 기준 (`printerReady`) | — | `47330e67` | #825 |
| 목업: Admin › Impresoras · print-agent 터미널 표시 | — | — | `.planning/sketches/admin-impresoras-seccion.html` · `print-agent-terminales.html` |

## 2. ★ 미배포 — Admin › Impresoras (메뉴 이동)

사용자 결정: 이름 **Impresoras** · Sucursales 의 Impresora 페이지 **바로 제거** · 터미널 모달의 프린터 칸은 **빼고 링크(A안)**.

- api `5272b5c7` (로컬 커밋, **미push**)
  - `GET /print/overview` (ver-impresoras) — 매장 전체 에이전트 + 터미널 배정
  - `PUT /print/terminal/:id/assignment` (editar-terminal) — 기본·Zebra(=터미널 지점)·추가(같은 매장)를
    **한 트랜잭션**으로. `setTerminalPrinters(…, outer?)` 에 트랜잭션 인자 추가
  - itest `terminal-printers` 14/14 · 돌연변이 2개 사망(트랜잭션 분리 → 행 잠금 대기로 멈춤 = 잡힘, 매장 조건 제거)
- app `f4d46999` (로컬 커밋, **미push**)
  - `/impresoras` 페이지 · `views/impresoras/ImpresorasView.tsx` (탭: Agentes=PrinterConfigTab 지점별 재사용 ·
    Terminales=일괄 편집표 · Instalación=`GuiaInstalacion` 분리) · 문제 감지 `problemas.ts`(+spec 5)
  - menuRegistry: Admin `order` 에 `/impresoras`(Configuración 다음), 아이콘 `tabler:printer`
  - 제거: `pages/sucursales/[id]/impresora.tsx` · BranchTable 프린터 버튼 · BranchList 의 AgentsTable ·
    `AgentsTable.tsx` · `ModalAgent.tsx` · `useAgents.ts`
  - ModalTerminal: 프린터 칸 → 링크. **저장 시 name·boxId 만 보낸다**(열 때 값으로 Impresoras 변경을 덮지 않게)
  - 관련 app spec 53 통과, tsc·eslint 0
- ★ 화면은 아직 브라우저로 확인 안 함. Agentes 탭은 목업의 표 대신 **기존 카드(PrinterConfigTab)** 를
  지점별로 재사용했다(기능 보존 우선) — 사용자에게 알릴 것.

**운영 시드 — 승인 대기** `api-ventago/migrations/2026-09-27-e-modulo-impresoras.sql`
- 드라이런(ROLLBACK): modules 1 · functions 1 · role_functions 18 · actions 18 — 18개 매장 **admin** 역할
  (오늘 editar-terminal update 를 가진 역할 = 종전 페이지를 쓰던 사람). 로컬은 적용됨(14매장).
- 순서: 운영 적용 → 스테이징 적용 → api push → app push → 빌드·컨테이너 확인 → 루트 포인터.

## 3. 결정됐고 아직 시작 안 한 일

### 3-1. Ganancia 환율 기준 (사용자 결정 2026-09-27: 전부 권장안) — ★ 원가 입력 시작 전에 할 것
- 현재: `unit_cost` = 원가 × **판매 당시 환율**(ARS 만 저장) → 「판매 당시」 방식은 이미 동작.
- 추가: `sale_items` 에 `unit_cost_orig`(원래 금액) · `unit_cost_currency` · `unit_cost_rate`(당시 환율) — expand, nullable.
  훅(`costo-unitario.ts`)이 함께 채우고, 취소는 원본 복사(keepUnitCost).
- 보고서(Ganancia + Ventas 칼럼 **둘 다**): 기간 내 USD 원가 판매의 당시 환율 최저·최고 차이가 **3% 초과**면
  상단에 **전환 스위치**「Cotización de cada venta / Cotización actual (N)」. 이하면 묻지 않음(판매 당시).
- 운영 원가 입력 0건 → 지금 넣으면 모든 원가 판매가 두 방식 지원.

### 3-2. print-agent / zebra-agent 「이 프린터를 쓰는 터미널」 (결정: 사용 중 = **서랍 열림**, **Zebra 도 동일**)
- 목업 `print-agent-terminales.html`. 역할(predeterminada/adicional·지점 태그) · 서랍 열림(누가 언제) ·
  마지막 티켓(에이전트가 작업의 terminalId 로 직접 기억).
- 서버: `listMappedTerminals` 를 기본+`terminal_printers` 로 확장, 배정 저장(assignment·printers PUT·터미널 수정) 시
  그 에이전트들에 `terminals_changed` emit. 서랍 상태는 heartbeat 에 실음(cash_registers closing_time IS NULL, box 단위).
- 릴리스: print-agent v1.2.7 · zebra-agent 도 — **태그 수동**(push-both 는 커밋 후 스킵).

## 4. 기타 남은 일 (앞 핸드오프에서 이월)

- 운영 화면 확인 전부(Ganancia·Ventas 칼럼·프린터 선택·재인쇄 메뉴·교환 취소·Impresoras)
- 교환 **수정(modificar)** 2단계 · Phase 95 W0 · bulkUpdatePrices N+1 측정
- NOIX(19) 터미널 기본 comandera 미지정(2대 → 티켓 안 나감) — Impresoras 가 배포되면 화면에 경고로 뜬다

## 5. 교훈 (이번 구간)

- 돌연변이가 「실패」가 아니라 **멈춤**으로 나타날 수 있다(트랜잭션 분리 → 같은 행 FOR UPDATE 대기).
  백그라운드로 돌리고 600초 넘으면 멈춤을 의심, **파일 복구부터**(돌연변이가 워킹트리에 남는다).
- 모달에서 칸을 빼도 `...terminal` 스프레드가 옛 값을 계속 보낸다 — 저장 payload 를 명시 필드로 좁힐 것.
