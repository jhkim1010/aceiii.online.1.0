# 설계: Mobile Access 권한 + 판매원-터미널 바인딩

생성일: 2026-06-11
상태: 승인됨 (사용자 승인 2026-06-11)
유형: Phase 37 (Mobile Sales Shell) SPEC 보강 (amendment) — Wave 1 (Backend Auth/Scope)에 흡수
선행 자료:
- `.planning/phases/37-mobile-sales-shell/37-SPEC.md` (Phase 37 본 스펙)
- `.planning/phases/33-permissions-v2/33-UAT.md` (Phase 33 권한 시스템, verified 2026-06-11)

---

## 목표

판매원(vendedor) 사용자의 **모바일 앱 사용 가능 여부를 Phase 33 권한 매트릭스에서 통제**하고,
**N명의 판매원을 1개 지점의 지정 터미널 1개에 명시적으로 연결(N:1)**하여 모바일 판매가
그 터미널/box로 집계되도록 한다.

확정된 설계 결정 (brainstorming 2026-06-11):
- **D-A**: mobile 사용 권한 위치 = Phase 33 권한 매트릭스 (role 단위 `mobile.access` 권한)
- **D-B**: 판매원↔터미널 카디널리티 = N명 → 1 공용 터미널 (N:1)
- **D-C**: 터미널 지정 방식 = 관리자가 유저별 명시 배정
- **D-D**: 배정 저장 위치 = `user_branches.mobile_terminal_id` 컬럼 (접근법 A)

---

## 배경 / 현재 상태 (운영 실측 2026-06-11)

- vendedor role 유저: coolsistema(store_id=6) 2명뿐 (role_id=21). 타 매장은 vendedor role 미사용(Admin/Gerente 운영).
- `user_branches` = 0 rows (Phase 33 휴면). Phase 37 backfill로 vendedor 2명 매핑 생성 예정.
- 스키마 사실:
  - `terminals`: id, name, **box_id**(NOT NULL), status, store_id, thermal_agent_id, zebra_agent_id. **branch 도달은 box_id → boxes.branch_id 경유** (직접 branch FK 없음).
  - `user_branches`: id, user_id, branch_id, role_id, is_default, valid_from, valid_until, granted_by, reason. **터미널 바인딩 없음** → 본 설계로 추가.
  - `users`: store_id, branch_id, ui_mode 있으나 mobile 플래그 없음.

---

## 데이터 모델

### (a) 권한 — Phase 33 매트릭스

`functions` 테이블에 신규 함수 1개 추가:

- `permission_slug = 'mobile.access'` (모듈 `mobile`, 액션 `access`)
- `/configuracion/permisos` 권한 매트릭스에서 **role 단위 토글**.
- 베타: coolsistema vendedor role(id=21)에 ON.

판매원이 모바일을 쓰려면 이 권한이 role에 부여되어 있어야 함. 데스크탑 동작에는 영향 없음(신규 함수, 기존 role_functions 불변).

### (b) 터미널 바인딩 — `user_branches` 컬럼 추가 (접근법 A)

```sql
ALTER TABLE user_branches
  ADD COLUMN IF NOT EXISTS mobile_terminal_id INT NULL
  REFERENCES terminals(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_user_branches_mobile_terminal
  ON user_branches(mobile_terminal_id);

COMMENT ON COLUMN user_branches.mobile_terminal_id IS
  'Phase 37 — 이 유저가 이 지점에서 모바일 판매 시 사용할 지정 터미널 (N:1 공용 가능). NULL=미배정.';
```

- `NULL` = 모바일 터미널 미배정.
- **N:1**: 여러 user_branches 행이 같은 `mobile_terminal_id`를 가리킴 → 자연 성립.
- **정합성 규칙 (앱 레벨 검증, DB FK로는 불가)**: 배정하려는 terminal의 `box_id → boxes.branch_id`가
  해당 user_branch의 `branch_id`와 일치해야 함. 불일치 시 배정 거부 → `TERMINAL_BRANCH_MISMATCH`.
  (terminals에 직접 branch_id가 없어 DB CHECK 제약 불가 → 서비스 레이어 검증.)

---

## 로그인 & 권한 강제 (`POST /mobile/auth/login`)

Phase 37 SPEC의 scope 결정 로직(MOBILE-A-04)에 2단계 게이트 추가:

1. **권한 게이트** — role에 `mobile.access` 없으면 → `403 MOBILE_ACCESS_DENIED`
2. **터미널 게이트** — scope branch의 user_branch `mobile_terminal_id`가 NULL이면 → `401 MOBILE_TERMINAL_NOT_ASSIGNED`
3. 통과 시 `mobile_sessions`에 해석된 `terminal_id` + `box_id`(= terminal.box_id) **캐시 복사** → 이후 판매가 이 값 사용.

순서: 기존 자격검증(bcrypt/active/store) → scope 결정 → **권한 게이트 → 터미널 게이트** → mobile_sessions UPSERT.

### mobile_sessions 컬럼 보강

Phase 37 SPEC의 `mobile_sessions`(MOBILE-A-01)에 다음 추가:
- `terminal_id INT NULL REFERENCES terminals(id)`
- `box_id INT NULL REFERENCES boxes(id)`

(로그인 시점 해석된 배정 터미널의 스냅샷. 판매 기록에 사용.)

### `GET /mobile/me` 응답 확장

기존 user 객체 + `terminalId`, `terminalName`, `boxId` 추가.

---

## 판매 기록 (`POST /mobile/sales`)

- **클라이언트가 보낸 `terminalId`/`boxId`는 신뢰하지 않음** — `mobile_sessions`에 캐시된
  배정 터미널 값으로 **강제 덮어쓰기** (SPEC의 SCOPE_VIOLATION / "query param 신뢰 금지" 원칙과 일관).
- N명이 같은 터미널 공유 → 매출이 한 box로 집계됨(D-B 의도).
- 기존 `sales-create.service` 트랜잭션 그대로 재사용 (신규 Pool/SERIALIZABLE 금지, SPEC 준수).
- 영수증 라우팅: `terminal.thermal_agent_id`로 print-agent hint만 반환(실제 출력 deferred, SPEC대로).

---

## 관리자 UI

### 터미널 배정 화면
- **위치**: 기존 사용자 상세 화면(또는 지점 관리 화면)에 "모바일 터미널" 셀렉터 추가.
- 드롭다운에는 **그 user_branch의 지점에 속한 터미널만** 표시 (box_id → branch 일치 필터, 정합성 보장).
- 배정/해제 시 `user_branches.mobile_terminal_id` UPDATE. 불일치 값은 서버가 `TERMINAL_BRANCH_MISMATCH`로 거부.
- 프론트 ESLint 규칙 준수(newline-before-return / lines-around-comment / no-unused-vars).

### mobile.access 토글
- 권한 매트릭스(`/configuracion/permisos`)에서 role 단위 토글. 위 배정 화면과 별개.

---

## 마이그레이션 / 베타 데이터

모두 PG10/PG15 호환, idempotent. DDL/DML은 CLAUDE.md 규칙대로 사용자 단계별 확인 후 운영 적용.

1. **DDL** — `user_branches.mobile_terminal_id` 컬럼 + 인덱스 추가 (위 SQL).
2. **DDL** — `mobile_sessions`에 terminal_id/box_id 컬럼 (Phase 37 Wave 1 마이그레이션에 포함).
3. **DML** — `mobile.access` function INSERT + vendedor role(21) role_function ON.
4. **DML** — coolsistema vendedor 2명: SPEC backfill로 user_branches 생성 후,
   각자 지점의 모바일 터미널을 `mobile_terminal_id`로 배정 (2-row UPDATE, 사용자 확인 후).

배포 전제: **Phase 35/36 운영 적용 완료 후** Phase 37 운영 배포 (SPEC L185, `activity_type='sale'` 의존).

---

## 테스트

### Jest (백엔드)
- 권한 없는 role 로그인 → 403 `MOBILE_ACCESS_DENIED`
- 터미널 미배정(NULL) 로그인 → 401 `MOBILE_TERMINAL_NOT_ASSIGNED`
- 판매 시 클라이언트 `terminalId` 위조 → 세션 배정 터미널로 강제(위조 무시) 검증
- 타 지점 터미널 배정 시도 → `TERMINAL_BRANCH_MISMATCH`
- 같은 지점 2 vendedor → 동일 box_id로 매출 집계 검증

### UAT (Phase 37 MOBILE-D-02 시나리오에 추가)
- U7: mobile.access OFF인 vendedor 로그인 시도 → 차단(403)
- U8: 터미널 미배정 vendedor → 401 + 안내
- U9: 같은 지점 vendedor 2명이 각자 모바일 판매 → 데스크탑 ventaVista에 같은 box/터미널로 표시

---

## 금지사항 / 주의

- **신규 Pool 인스턴스 생성 금지** — Sequelize 전역 pool 재사용.
- **클라이언트 terminalId/boxId 신뢰 금지** — 항상 세션 배정값으로 덮어쓰기.
- **terminals 직접 branch_id 가정 금지** — box_id → boxes.branch_id 경유로 정합성 검증.
- **mobile.access를 데스크탑 권한과 혼동 금지** — 모바일 전용 게이트.
- DDL/DML 운영 적용은 단계별 사용자 확인(CLAUDE.md DDL 규칙).

---

## 범위 외 (YAGNI)

- N:M (유저 다중 터미널), 로그인 시 터미널 선택, 동적 터미널 전환 — MVP 제외.
- revendedor 모드 터미널 바인딩 — Phase 37 Wave 5(Phase 24 의존)에서 별도 검토.
- 영수증 실제 출력(print-agent WebSocket 호출) — SPEC대로 deferred.

---

## Phase 37 매핑

- **MOBILE-A-01** (mobile_sessions) → terminal_id/box_id 컬럼 추가
- **MOBILE-A-03** (JWT payload) → 변경 없음 (터미널은 세션 조회로 해석)
- **MOBILE-A-04** (login) → 권한 게이트 + 터미널 게이트 2단계 추가
- **MOBILE-A-06** (/mobile/me) → terminalId/terminalName/boxId 추가
- **MOBILE-B-04** (POST /mobile/sales) → 세션 배정 터미널 강제
- 신규: `user_branches.mobile_terminal_id` DDL + `mobile.access` function + 관리자 배정 UI

*Brainstorming 설계 완료 2026-06-11. Phase 37 SPEC 및 Phase 33 권한 시스템과 모순 없음.*
