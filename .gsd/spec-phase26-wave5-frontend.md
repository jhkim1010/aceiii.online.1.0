# SPEC: Phase 26 Wave 5 — 외상(Crédito/Seña/Favor) 프론트엔드

생성일: 2026-04-30

## 목표
백엔드 Phase 26 (외상 / 예약금 / 자유 잔액) 시스템을 프론트엔드 화면에서 사용할 수 있도록 구현. POS(nueva-venta) 통합 + 전용 관리 페이지 + 정책 설정 + InfoClient 잔액 표시.

## 배경 및 컨텍스트

**백엔드는 100% 완성 + 운영 배포 완료** (commit `fbd63a1`, 컨테이너 가동 시각 15:20 UTC). 사용 가능한 API:

| 엔드포인트 | 용도 |
|---|---|
| `POST /credit/payments` | 입금(payment) 등록 — FIFO 분배 |
| `GET /credit/reports/aging` | Aging (30/60/90/90+) 리포트 |
| `GET /credit/reports/top-debtors` | Top deudores |
| `GET /credit/clients/:id/summary` | 고객 외상 요약 |
| `GET /credit/clients/:id/ledger` | 고객 ledger 거래내역 |
| `PATCH /credit/policy/:storeClientId` | 정책(한도·기간·상태) 수정 |
| `POST /credit/senias` | Seña 예약금 등록 |
| `POST /credit/senias/cancel` | Seña 취소·환불 |

**DB 신규 컬럼:**
- `store_clients.senia_balance, favor_balance, credit_term_days, credit_status, last_payment_at`
- `stores.senia_ui_mode` (`'separated'` | `'unified'`)

**프론트엔드 코드 0% — Wave 5 가 통째로 미구현.**

## 기술 스택
- 언어/프레임워크: Next.js 13 + React 18 + TypeScript
- UI: Material-UI 5
- 데이터: SWR + axios (apiConnector)
- 상태관리: Redux Toolkit + Context (SaleProductsContext)
- DB: PostgreSQL (백엔드 통해서만 접근, pool 직접 사용 없음)
- ESLint 설정 파일: `ventago-app/.eslintrc.json`

## 태스크 목록

### Module A — 백엔드 API 한 곳에 묶기 (SWR 훅)
- [ ] **TASK-A1**: `src/hooks/api/useCreditClientSummary.ts` — 고객 요약 SWR 훅
- [ ] **TASK-A2**: `src/hooks/api/useCreditClientLedger.ts` — 고객 ledger SWR 훅
- [ ] **TASK-A3**: `src/hooks/api/useCreditAging.ts` — Aging 리포트 SWR 훅
- [ ] **TASK-A4**: `src/hooks/api/useCreditTopDebtors.ts` — Top deudores SWR 훅

### Module B — InfoClient 확장 (POS 화면 즉시 가시)
- [ ] **TASK-B1**: `src/views/homes/components/InfoClient.tsx` — Crédito/Seña/Favor 잔액 배지 추가 (selected client 가 있을 때 표시)
- [ ] **TASK-B2**: 잔액 클릭 시 ledger 미니뷰 모달 (간단)

### Module C — POS (nueva-venta) Crédito 통합
- [ ] **TASK-C1**: `src/views/homes/components/ProductList/components/InvoiceAditional.tsx` — 결제수단에 'Crédito' 추가
  - 선택 시 외상으로 잔액 추가, ledger SALE_CREDIT movement 자동 생성
  - DNI/CUIT 검증 통과 + credit_status='active' 인 고객만 가능
- [ ] **TASK-C2**: 'Seña 사용' 토글 — `senia_balance > 0` 인 고객에게만 노출
  - 사용 시 sale_senias 흡수 + ledger SENIA_USE movement
  - UI 모드 separated/unified 분기 (separated 면 Seña/Favor 별도, unified 면 합쳐 표시)
- [ ] **TASK-C3**: 'Favor 사용' opt-in 토글 — `favor_balance > 0` 인 고객에게만 노출
  - 자동 차감 안 됨 — 명시적 클릭 필요 (SPEC 의 핵심 결정사항)

### Module D — 전용 페이지 (Cuentas Corrientes)
- [ ] **TASK-D1**: `src/pages/cuentas-corrientes/index.tsx` — Top deudores + Aging 대시보드
- [ ] **TASK-D2**: `src/pages/cuentas-corrientes/[clientId].tsx` — 고객 외상 카드 (요약 + ledger 표 + 입금 버튼)
- [ ] **TASK-D3**: 입금 등록 모달 — `POST /credit/payments` 호출, FIFO 분배 결과 표시
- [ ] **TASK-D4**: `src/navigation/vertical/index.ts` — 사이드바 메뉴 'Cuentas Corrientes' 추가

### Module E — 정책 설정 페이지
- [ ] **TASK-E1**: `src/pages/configuracion/credito/index.tsx` — 매장 단위 정책 (`stores.senia_ui_mode`, 기본 credit_term_days)
- [ ] **TASK-E2**: 고객별 정책 수정 모달 — credit_limit, credit_term_days, credit_status

### Module F — Sena 화면
- [ ] **TASK-F1**: nueva-venta 에서 Seña 등록 모달 (POS 흐름 중 별도 버튼 'Reservar Seña')
- [ ] **TASK-F2**: 고객 카드의 Seña 목록 + 환불 버튼

### Module Z — 검증
- [ ] **TASK-Z1**: 모든 변경 파일 ESLint 검증 (오류 0개)
- [ ] **TASK-Z2**: tsc 타입 체크
- [ ] **TASK-Z3**: 운영 콘솔 캐시 클린업 후 동작 검증
- [ ] **TASK-Z4**: git commit + push (Jenkins 빌드 성공 확인)

## 완료 기준
- ESLint 오류 0개 (Warning은 다른 기존 파일에서 나오는 것이라 OK)
- tsc 0 errors
- 매장 직원이 화면에서 외상 등록 / 입금 / Seña 예약 / Favor 사용 가능
- 운영 배포 후 Jenkins 빌드 성공
- 디버그 console 로그 없음

## 금지사항 / 주의사항

1. **Favor 자동 차감 절대 금지** — 반드시 명시적 opt-in (SPEC 핵심 결정)
2. **백엔드 API 변경 금지** — 이번 Wave 는 프론트만, 백엔드는 fbd63a1 그대로
3. **DB 직접 접근 금지** — apiConnector 통해서만
4. **ESLint Warning은 무시 가능** — 기존 파일의 react-hooks/exhaustive-deps 등은 이번 Wave 범위 밖
5. **단계별 commit + push + 빌드 확인** — 한 번에 모두 push 하지 말고 Module 단위로 push 해서 Jenkins 빌드 실패 가능성 분산
6. **Phase 25 클라이언트 분리 호환** — store_clients.id 와 legacy clients.id 양쪽 모두 처리 필요할 수 있음
7. **F3 핫키, AG-Grid 등 기존 UX 깨지 않기** — InfoClient 변경 시 기존 form 동작 보존

## 우선순위 (사용자 요청: 순서대로)

순서: **A → B → C → D → E → F → Z**

이유:
- A 는 다른 모든 모듈의 기반
- B 는 사용자 가시성이 가장 빠름 (POS 에서 즉시 보임)
- C 는 매장 직원이 매일 쓰는 핵심 흐름
- D 는 관리자용 (덜 자주 사용)
- E, F 는 보완 기능

## Module 단위 push 계획
- Module A 완료 → push → 빌드 확인
- Module B 완료 → push → 빌드 확인 (운영에서 InfoClient 잔액 보이는지 즉시 검증)
- 이하 동일
