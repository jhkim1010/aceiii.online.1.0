# SPEC: 판매원 근무시간(기간 리포트) + Adelanto(가불)
생성일: 2026-07-14

## 목표
QR 출퇴근으로 각 판매원의 근무시간을 기록·집계하고, 관리자가 이번 달/임의 기간으로 조회한다.
향후 앱에서 판매원이 adelanto(가불)를 요청하면 월급 정산 시 자동 차감한다.

## 현재 상태 (Phase 37-06 로 이미 구현됨 — 재작업 금지)
- `seller_attendance` 테이블: 1 세션 = 1 행 (`check_in_at` open, `check_out_at` close).
- QR punch = **토글**: 열린 세션 없으면 entrada 생성, 있으면 salida(닫기). `mobile_scanner` 스캔 → `POST /attendance/punch`.
- **점심 자동 구별·제외**: 08:00 entrada → 12:00 salida(세션1) → 13:00 entrada → 18:00 salida(세션2). 근무=세션1+세션2, 점심(12–13) 자동 제외. 별도 라벨 불필요.
- 집계: `todayWorkedSeconds()` (당일), `GET /attendance/report?month=YYYY-MM` (판매원별 `totalSeconds`/`sessionCount`/`openCount`).
- 세션 상세: `GET /attendance/sessions`. UI: `AsistenciaReport.tsx` (Reportes → Asistencia), 훅 `useAttendanceReport(month)`.
- Seller ↔ user 매핑: `Sellers.linked_user_id`. **미연결 유저는 NOT_A_SELLER** (admin 등은 출퇴근 불가 — 정상).

## 진짜 gap (이번 SPEC 범위)
1. 리포트가 **월 단위만** (`month=YYYY-MM`). 사장님 요구 = "이번 달 **혹은 원하는 기간**" → from/to 날짜 범위 필요.
2. **adelanto(가불)**: 앱에서 요청 → 관리자 승인 → 월급 정산 시 차감. 완전 신규.
3. (선택) 잊고 안 찍은 punch / 열린 채 자정 넘김(overnight) 처리 명확화.

## 범위 분리 (Phase)

### Phase A — 근무시간 기간 리포트 (작음, 기존 확장)
- 서버: `GET /attendance/report` 에 `from=YYYY-MM-DD&to=YYYY-MM-DD` 지원(월 파라미터 하위호환 유지).
  - 판매원별 기간 `totalSeconds` + 세션수 + 열린세션수. 지점 필터 유지.
  - 기간 경계 세션: `check_in_at`/`check_out_at` 를 [from,to] 로 클램프해 합산.
- 프론트: `AsistenciaReport` 에 기간 선택기(이번달/지난달/사용자지정 from-to) + 시간(HH:MM) 표시 + 판매원별 상세(일자별 세션 in/out) 드릴다운.
- 성능: 기간 SUM 은 단일 집계 쿼리(판매원 GROUP BY). N+1 금지. pool 무영향.

### Phase B — Adelanto(가불) (신규, 큼)
- 신규 테이블 `seller_adelantos`: id, seller_id FK, store_id, amount, currency?, status(pending/approved/rejected/paid), requested_at, decided_by, decided_at, note, payroll_period(YYYY-MM) nullable.
- 앱(판매원): "Solicitar adelanto" 화면 → 금액 입력 → `POST /mobile/adelanto`. 본인 pending/승인 내역 조회.
- 웹(관리자): 승인/거절 UI + 목록. 월급 정산 화면에서 해당 기간 승인 adelanto 합계를 급여에서 차감 표시.
- 리포트 연동: 판매원 상세에 "근무시간 · 가불 차감 · 실지급(선택)".
- 마이그레이션: 로컬 5432 + 운영 5434 동시, owner=coolsistema (CLAUDE.md 규칙).

## 결정 (LOCKED 2026-07-14)
- **D2 잊은 punch = 관리자 수동보정**. 자동 salida 없음. 열린 세션이 자정 넘으면 관리자가 리포트에서 `adjusted_by`/`check_out_at` 보정. (기존 컬럼 재사용)
- **D3 급여 계산 안 함**. 시스템은 근무시간 집계 + 승인 adelanto 합계 차감만 표시. 실지급액은 사장님이 계산.
- **D5 판매원 앱에 본인 근무시간 누계 화면 추가** (A3 확정 — 이번달/기간 본인 근무시간 조회).

## 남은 결정
- D1 근무시간 기준: 세션 실측 합(현재 방식) 유지로 진행 — 지각/예정근무 대비는 범위 밖(필요 시 별도).
- **D4 LOCKED (2026-07-14)**: 승인권자=관리자+지점장(gerente), 한도=없음(승인 시 판단), 차감월=관리자가 payroll_period 지정. → Phase B PLAN: `.gsd/plan-adelanto-phaseB.md`.

## 태스크 (초안 — 결정 후 확정)
- [ ] A1 서버 report from/to 파라미터 + 기간 클램프 집계
- [ ] A2 프론트 기간 선택기 + HH:MM + 일자별 드릴다운
- [ ] A3 판매원 앱 본인 근무시간 누계 화면 (D5 확정)
- [ ] B1 seller_adelantos 마이그레이션(로컬+운영, owner coolsistema)
- [ ] B2 앱 adelanto 요청/조회
- [ ] B3 웹 승인/거절 + 목록
- [ ] B4 월급 정산에서 승인 adelanto 차감 표시
- [ ] B5 리포트 연동(근무시간 · 가불 차감)

## 완료 기준
- Phase A: 관리자가 임의 기간으로 판매원별 근무시간(HH:MM, 점심 제외)을 정확히 조회.
- Phase B: 앱에서 가불 요청 → 관리자 승인 → 해당 월 정산에 차감 반영.

## 참고
- 기존 코드 재사용: `attendance.service.ts`(집계), `AsistenciaReport.tsx`, `useAttendanceReport`, `Sellers.linked_user_id`, `seller_attendance.adjusted_by`(수동보정 이미 존재).
- 관련 SPEC: [[spec-mobile-login-password]], 메모리 project_phase37_06_qr_attendance.
