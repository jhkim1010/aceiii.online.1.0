# SPEC: VentaVista 지점 귀속/caja inicial 버그 수정
생성일: 2026-07-06

## 목표
다지점 사용자가 지점 전환 후 판매하면 판매·현금이 처음 연 caja 의 지점으로 잘못 귀속되고,
VentaVista 통계/caja inicial 이 지점 선택을 무시하던 버그 수정.

## 근본 원인 (재현 확인: 로컬 DB sales 168/169 → 둘 다 terminal 13/지점 12)
1. `sales-create.service.ts` — terminalId 를 `CashRegister.findOne({userId, closingTime:null})`
   (지점 무필터) 로 해석 → caja 2개 오픈 시 항상 먼저 연 지점으로 귀속.
   efectivo 입금(`registerCashOperation`)도 동일 쿼리 → 현금이 다른 지점 caja(93)로 유입.
2. `GET /cash-register/open` (POS 의 caja 컨텍스트) 도 지점 무필터 → DTO branchId 오염.
3. `getDailyStats` — 판매 집계를 `u.branch_id`(로그인 소속 지점) 기준으로 → 목록 필터
   (terminal→box→branch, REG-1)와 불일치.
4. `DailySalesStats.tsx` — `/sales/all` 지점 필터 없음 + `/cash-register/status` branchId 미전달
   → caja inicial 이 항상 첫 caja 금액.

## 완료된 태스크
- [x] api: `resolveOpenCashRegister(userId, branchId, tx)` 헬퍼 — 지점 우선 + id DESC + fallback
- [x] api: 판매 생성 terminalId 해석에 dtoBranchId 지점 스코프 적용 + VentasDebug 로그
- [x] api: `registerCashOperation` 에 branchId 스레딩 (efectivo → 판매 지점 caja) + 디버그 로그
- [x] api: `GET /cash-register/open?branchId=` / `POST auto-open {branchId}` 지점 인지형
- [x] api: `autoOpenForUser(preferredBranchId)` — 선택 지점 우선 (admin user.branchId NULL 대응)
- [x] api: `getDailyStats` sale_per_branch CTE → COALESCE(terminal→box→branch, u.branch_id)
- [x] app: POS `/cash-register/open` 호출에 selectedBranchId 전달 + deps + 디버그 로그
- [x] app: `DailySalesStats` branchId prop — originBranchId 필터 + status?branchId + 디버그 로그
- [x] app: `SalesListView` → DailySalesStats 에 filters.originBranchId 전달

## 품질 검증
- ESLint(front 3파일): 오류 0
- ESLint(api): 수정 라인 범위 신규 오류 0 (파일 기존 부채는 별건)
- PG pool: 신규 쿼리 모두 sequelize 관리 (connect/release 수동 없음), 판매 트랜잭션 내
  registerCashOperation 은 기존과 동일하게 transaction 전달
- 집계 SQL 로컬 PG18 실행 확인

## 후속 작업 / 주의
- 서버 재시작 후 재테스트 필요 (지점 A caja → 판매 → 지점 B 전환 → caja → 판매 → VentaVista 확인)
- 로컬 dev 잘못 귀속된 테스트 데이터 보정(선택): sale 169 → terminal 1,
  box_operation 167 → cash_register 94/terminal 1
- 검증 후 [VentasDebug] 로그 제거 여부 결정 (debug 레벨이라 운영 노출 낮음)
