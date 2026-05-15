# Ventago — 권한 관리 시스템 재설계 (분석 + 추천)

> 작성일: 2026-05-14 / 작성: 마르코스 김
> 모델: **RBAC + Branch Scope** + Approval Threshold (미니 ABAC)
> 단계: 분석 (구현 전 합의)
> 관련 산출물:
> - `mockup.html` — UI 인터랙티브 목업 (4 화면)
> - `Ventago_Permissions_Matrix.xlsx` — Role × Function 매트릭스 + Approval Threshold + DB 스키마

---

## 0. Executive Summary (한 화면)

| 항목 | 현재 (As-Is) | 목표 (To-Be) |
|---|---|---|
| Role 표준 | `superadmin / admin / gerente / vendedor` 4개, 정의 모호 | **8 표준 Role** (super_admin → viewer), 책임 명문화 |
| Branch 스코프 | `users.branch_id` 단일 컬럼 (1:1) | `user_branches` 매핑 (1:N), 지점별 다른 role 가능 |
| 권한 모델 | RBAC (3계층: role → role_function → role_function_action) | RBAC + Branch Scope + Approval Threshold |
| 감사 로그 | 제품/판매 위주, **권한 변경 누락** | `audit_logs` 에 `entity_type='permission'` 추가, 롤백 가능 |
| 일회성 권한 | 미지원 (영구 허용/차단만) | `valid_until` 컬럼으로 시간 제한 부여 |
| 금액 기반 분기 | 코드에 if 분기 산재 | `approval_thresholds` 테이블 + 승인 큐로 일원화 |
| Frontend ↔ Backend 어휘 | `function-slug` (BE) ≠ `subject` (FE-ACL) | 단일 어휘 (`function_slug`) + FE generator 로 ACL 자동 생성 |

---

## 1. 다층 사고법 분석 (빌 게이츠 방식)

### 1층 — 표면 문제

세 가지 명시된 불편이 있습니다.

첫째, 지점(Branch) 별 권한 분리가 불가합니다. `users.branch_id` 가 단일 FK 라서, 한 사용자가 본점에서는 매니저, 분점에서는 캐셔로 일하는 시나리오를 표현할 수 없습니다. 매장이 5-10개 지점으로 확장되면 인사 운영이 막힙니다.

둘째, Role 표준이 없습니다. 시드된 4개 role (`superadmin/admin/gerente/vendedor`) 만으로는 실제 매장 운영의 다양한 직무 (회계 담당, 재고 담당, 외주 담당, 외부 감사) 를 표현할 수 없어, 매번 `user_functions` 오버라이드로 메우는 상태입니다.

셋째, 권한 변경 감사 로그가 없습니다. `audit_logs` 테이블은 존재하지만 제품/판매 중심으로만 기록되고, 누가 누구에게 언제 어떤 권한을 부여했는지 추적할 수 없습니다. 사고 발생 시 책임 소재 불명.

### 2층 — 구조적 원인

권한 모델은 **3단계 혼합형**으로 자라났습니다.
`roles` → `role_functions` + `role_function_actions` (역할이 어떤 함수의 어떤 액션 가능?)
→ `user_functions` + `user_function_actions` (사용자별 오버라이드)

이론상 잘 설계됐지만 실제로는:

1. **스코프 차원이 "Store" 한 단계뿐** — `role_functions.store_id` 만 있고 `branch_id` 가 없습니다. 멀티지점이 1급 시민이 아닙니다.
2. **Frontend 와 Backend 가 다른 어휘를 씁니다** — BE 는 `function-slug` (예: `sales.refund`), FE 는 ACL 메타데이터 `{action:'read', subject:'admin-permisos'}`. 두 곳 동기화 비용이 큽니다.
3. **권한 편집 UI 가 사실상 read-only** — `PermissionsListView.tsx` 가 함수 목록만 보여주고 CRUD 액션 토글 UI 가 없습니다. 권한 부여를 위해 SQL 직접 수정이 필요한 상황.
4. **`function-permission.guard.ts` 가 매 요청마다 3-stage 쿼리** — RoleFunction → RoleFunctionAction → UserFunction 을 순차 조회. 캐시 전략이 없으면 P95 지연 + connection pool 압박.

### 3층 — 근본 본질

본질적으로 이건 **"권한이 무엇으로 정의되는가"** 라는 RBAC 의 3가지 본질 질문에 답이 정해지지 않은 상태입니다.

1. **WHO** — User
2. **CAN DO WHAT** — Permission = Resource × Action
3. **WHERE / WHEN** — Scope (Store, Branch, Time, Amount)

지금 시스템은 1, 2 는 구현되어 있는데, 3번 스코프가 **Store 단일 차원** 에 고정. POS/ERP 의 본질은 "돈과 재고가 지점 단위로 흐른다" 는 것이라, **Branch 가 1급 시민** 으로 권한 모델에 들어가야 합니다.

또 POS 는 "환불 X 원 이상은 매니저 승인" 같은 **금액 기반 분기**가 필수라, 단순 RBAC 만으로는 부족합니다. **Approval Threshold** 라는 미니 ABAC 요소를 한두 개 도입해야 운영이 됩니다.

---

## 2. 추천 Role 체계 (8 표준)

| # | slug | 한글 | 스코프 | 추천 인원 | 핵심 책임 |
|---|---|---|---|---|---|
| 1 | `super_admin` | 슈퍼관리자 | Global | 1-2 | 시스템 전체 운영, 매장 생성/삭제, 라이선스, 인프라 |
| 2 | `store_owner` | 매장주 | Store 전체 | 1-2 | 모든 지점·재무·구독, 권한 위임의 정점 |
| 3 | `store_admin` | 관리자 | Store 전체 | 1-3 | 사용자·권한·임계값 관리, 리포트 |
| 4 | `branch_manager` | 지점장 | Branch (1-N) | 지점당 1-2 | 지정 지점 운영, 환불·할인 승인, 일일 마감 |
| 5 | `cashier` | 캐셔 | Branch (단일) | 지점당 3-10 | POS 판매·결제, 소액 환불, 금전함 운영 |
| 6 | `inventory_clerk` | 재고담당 | Branch (1-N) 또는 Store | 1-3 | 입출고·실사·이동·발주 입력 |
| 7 | `accountant` | 회계담당 | Store (회계 한정) | 1-2 | 비용·정산·금고·외주 지급, 재무 리포트 |
| 8 | `viewer` | 조회 전용 | Store 또는 Branch | 필요시 | 감사·외부 컨설턴트, 모든 데이터 read-only |

> 상세 권한 매트릭스는 `Ventago_Permissions_Matrix.xlsx` 의 **Permission Matrix** 시트 참조.

---

## 3. 권한 모델 — RBAC + Branch Scope + Approval Threshold

### 3.1 데이터 모델 (DB 스키마 변경)

**신규 테이블 4개**

```sql
-- 사용자 ↔ 지점 ↔ 역할 매핑 (핵심)
CREATE TABLE user_branches (
  id          BIGSERIAL PRIMARY KEY,
  user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  branch_id   INTEGER NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  role_id     INTEGER NOT NULL REFERENCES roles(id),
  is_default  BOOLEAN NOT NULL DEFAULT false,
  valid_from  TIMESTAMP NOT NULL DEFAULT NOW(),
  valid_until TIMESTAMP NULL,
  granted_by  INTEGER NOT NULL REFERENCES users(id),
  reason      TEXT,
  created_at  TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMP NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, branch_id)
);
CREATE INDEX idx_user_branches_user_active
  ON user_branches (user_id) WHERE valid_until IS NULL OR valid_until > NOW();

-- 승인 임계값 (어떤 role 가 어느 액션에서 어느 금액까지 가능한가)
CREATE TABLE approval_thresholds (
  id                  BIGSERIAL PRIMARY KEY,
  store_id            INTEGER NOT NULL REFERENCES stores(id),
  branch_id           INTEGER NULL REFERENCES branches(id), -- NULL = 매장 전체
  function_slug       VARCHAR(100) NOT NULL,                -- 'sales.refund'
  role_slug           VARCHAR(50)  NOT NULL,                -- 'cashier'
  max_amount          NUMERIC(12,2) NULL,
  max_quantity        INTEGER NULL,
  approver_role_slug  VARCHAR(50) NOT NULL,                 -- 'branch_manager'
  created_at          TIMESTAMP NOT NULL DEFAULT NOW(),
  UNIQUE (store_id, branch_id, function_slug, role_slug)
);

-- 승인 대기 큐 (임계값 초과 시 거부 대신 큐잉)
CREATE TABLE approval_requests (
  id              BIGSERIAL PRIMARY KEY,
  store_id        INTEGER NOT NULL,
  branch_id       INTEGER NOT NULL,
  requested_by    INTEGER NOT NULL REFERENCES users(id),
  function_slug   VARCHAR(100) NOT NULL,
  payload         JSONB NOT NULL,                           -- 원래 요청 본문
  status          VARCHAR(20) NOT NULL DEFAULT 'pending',   -- pending|approved|rejected|expired
  approved_by     INTEGER NULL REFERENCES users(id),
  approval_note   TEXT NULL,
  expires_at      TIMESTAMP NOT NULL,                       -- 기본 NOW() + 24h
  created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
  resolved_at     TIMESTAMP NULL
);
CREATE INDEX idx_approval_requests_pending
  ON approval_requests (store_id, branch_id, status) WHERE status = 'pending';

-- 권한 캐시 (read 성능)
CREATE TABLE user_permission_cache (
  user_id      INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  branch_id    INTEGER NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  permissions  JSONB NOT NULL,    -- { "sales.refund": ["create","read"], ... }
  computed_at  TIMESTAMP NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, branch_id)
);
```

**기존 테이블 수정**

```sql
-- role_functions 에 branch 스코프
ALTER TABLE role_functions ADD COLUMN branch_id INTEGER NULL REFERENCES branches(id);

-- user_functions 에 시간 제한 + 사유 + 부여자
ALTER TABLE user_functions ADD COLUMN branch_id INTEGER NULL REFERENCES branches(id);
ALTER TABLE user_functions ADD COLUMN valid_from  TIMESTAMP NOT NULL DEFAULT NOW();
ALTER TABLE user_functions ADD COLUMN valid_until TIMESTAMP NULL;
ALTER TABLE user_functions ADD COLUMN reason      TEXT;
ALTER TABLE user_functions ADD COLUMN granted_by  INTEGER NULL REFERENCES users(id);

-- audit_logs ENUM 확장
ALTER TYPE audit_action ADD VALUE 'assign';
ALTER TYPE audit_action ADD VALUE 'revoke';
ALTER TYPE audit_action ADD VALUE 'grant';
ALTER TYPE audit_action ADD VALUE 'threshold_change';
```

### 3.2 권한 결정 알고리즘 (런타임)

요청 들어올 때 권한 결정 순서 (deny-by-default):

```
1. JWT 검증 → user_id, store_id 추출
2. SessionGuard 검증 → x-session-token, terminal/branch 컨텍스트 추출
3. 캐시 조회: user_permission_cache (user_id, branch_id)
   - HIT → JSONB 안의 permissions[function_slug] 확인
   - MISS → 4번부터 계산
4. 권한 합성:
   a. user_branches 에서 (user_id, branch_id) 의 role_id 조회
   b. role_functions + role_function_actions 로 base 권한 set 빌드
   c. user_functions 에서 (user_id, branch_id, valid_until > NOW()) 오버라이드 적용
      - allowed=true → 추가
      - allowed=false → 차단
   d. user_permission_cache 에 INSERT (TTL 5분)
5. 최종 set 에 (function_slug, action) 가 있으면 통과, 없으면 403
6. 요청에 amount/quantity 가 있으면 approval_thresholds 확인
   - 임계값 이내 → 통과
   - 초과 → approval_requests INSERT, 응답 202 (대기) + 승인자에게 socket.io 푸시
```

### 3.3 PostgreSQL Connection Pool 보호 가이드

마르코스님께서 항상 강조하시는 부분 — 권한 시스템은 **모든 요청** 에서 호출되기 때문에 pool 사용량이 폭증하기 쉽습니다. 다음 규칙 적용:

1. **마이그레이션은 2단계로**: ① `ADD COLUMN NULL` (즉시) → ② backfill 은 batch 1000건씩 separate connection (운영 pool 안 건드림) → ③ 다음 배포에서 `NOT NULL` 적용. 한 트랜잭션 안에 다 넣으면 long-running tx 가 vacuum 막아 pool degradation.
2. **인덱스는 `CREATE INDEX CONCURRENTLY`** — pool wait 없이 추가. PG10/15 모두 지원.
3. **권한 체크 쿼리는 1회 join** — `user_branches JOIN roles JOIN role_functions JOIN role_function_actions` 를 단일 쿼리로 (현재의 3-stage 분리 쿼리 → 1 쿼리로 합치기). 캐시 hit 시 0회.
4. **Cache invalidation** — 권한 변경 시 `user_permission_cache` 의 해당 row DELETE (Redis 안 쓰고 DB로). 변경 빈도가 낮으니 충분.
5. **Audit log 적재** — 권한 변경 트랜잭션 안에 동기 INSERT (분리하면 권한은 바뀌었는데 로그만 빠지는 케이스 발생). volume 이 폭증하면 별도 pool (현재 max=50 유지하고 audit 전용 별도 pool 5개) 검토.

### 3.4 Frontend 동기화

기존 ACL `subject` 와 BE `function_slug` 가 다른 어휘인 게 큰 부채입니다. 전략:

- BE 가 source of truth: `functions` 테이블의 slug
- FE 빌드 시 `npm run gen:permissions` 스크립트로 `functions/role_functions` snapshot 을 가져와 TypeScript enum 자동 생성
- CASL 도입 (선택) — 현재 ACL 으로도 충분하지만, 복잡한 조건부 (예: "본인이 만든 판매만 환불 가능") 가 늘어나면 CASL 의 conditions 가 유용

---

## 4. UI/UX 추천 — 4 화면 구성

> 인터랙티브 목업: `mockup.html` (4 탭 전환 가능)

### 4.1 화면 1 — 권한 매트릭스 (Role × Module)

- **Y축**: 모듈 → 함수 (그룹핑, accordion)
- **X축**: 8 Role 컬럼
- **셀**: CRUD 요약 배지 (`CRUD`, `CR—`, `——R—`, `⚠ 승인필요`, `—`)
- **Sticky**: 첫 컬럼(함수명) 과 첫 행(role 헤더)
- **편집 모드**: 셀 클릭 → CRUD 4 체크박스 popover, 저장 시 audit_log 자동
- **필터**: 검색바 + 지점 셀렉트 (전체/특정 지점)
- **권한**: `store_owner / store_admin` 만 편집

### 4.2 화면 2 — 사용자 상세 (Multi-Branch)

- **헤더**: 아바타 + 이름 + 상태 배지 + 마지막 접속
- **섹션 1 — 지점별 역할**: 각 row = (지점 셀렉트, role 셀렉트, 요약, 삭제). `+ 지점 추가` 버튼으로 row 증가
- **섹션 2 — 개별 오버라이드**: 추가(+ 녹색) / 차단(− 적색) 카드. 각 카드에 사유 + 부여자 + 부여일 표시
- **섹션 3 — 보안 설정**: 고정 IP, 2FA, 세션 타임아웃, 활성 세션 수
- **권한**: 본인은 read-only, `store_admin` 이상은 편집

### 4.3 화면 3 — 감사 로그 (타임라인)

- **레이아웃**: 시간 컬럼 + 액션 카드 + 롤백 버튼
- **액션 태그**: `role.assign`(녹), `role.revoke`(적), `permission.grant`(파), `threshold.change`(노), `role.create`(보)
- **메타**: IP / 브라우저 / 사유 / ticket 링크
- **롤백**: 단일 액션 되돌리기 (역방향 변경 자동 생성, audit_log 연쇄)
- **필터**: 대상 사용자 / 액션 / 기간
- **CSV 내보내기**: 외부 감사용

### 4.4 화면 4 — 승인 임계값 설정

- **표 형식**: 액션 × Role 별 한도 + 승인자
- **편집**: 인라인 셀 편집, 저장 시 audit
- **단위**: 매장 통화 (ARS / KRW 등) 자동 표시
- **푸터 노트**: "임계값 초과 시 거부가 아니라 승인 큐에 들어갑니다" 명시

### UX 디자인 원칙

1. **다크 네이비 + 골드** (기존 Ventago 테마 유지) — 이질감 없도록.
2. **Sentence case** — "권한 관리" / "사용자 추가" (Title Case 금지).
3. **변경사항 표시** — 저장 전 변경된 셀에 노란 배경, "저장하지 않음" 토스트.
4. **위험 액션은 2단계 확인** — `super_admin` 부여, role 삭제 등은 모달 + 비밀번호 재입력.
5. **읽기 전용 상태** — 본인 권한이 없으면 셀이 회색이고 hover 시 "권한 없음 / X role 필요" 툴팁.
6. **Bulk 작업** — 여러 사용자 선택 → "선택 사용자에게 X role 부여" 액션 (대량 인사 이동 대응).
7. **Loading skeleton** — 매트릭스 데이터 fetch 중 skeleton 표시 (300ms 이상이면).

---

## 5. 액션 플랜 (단계별 실행)

### Phase A — 기반 (1주)

1. DB 스키마 마이그레이션 SQL 작성 (`api-ventago/migrations/0XX_user_branches.sql` 등)
2. 로컬 PG18 dev 에서 적용 → `db-schema.regen.sh` 실행 → 스키마 reference 갱신
3. 8 표준 Role seed 데이터 작성 + `users.seeder.ts` 갱신
4. backfill 스크립트: 기존 `users.branch_id` → `user_branches` 1:1 마이그레이션

### Phase B — Backend (1.5주)

5. Sequelize 모델 추가: `UserBranch`, `ApprovalThreshold`, `ApprovalRequest`, `UserPermissionCache`
6. `function-permission.guard.ts` 리팩터: 3-stage → 1 query + cache lookup
7. `BranchScopeGuard` 신설 (요청 path 의 `branchId` 와 user 의 `user_branches` 매칭 검증)
8. `approval.service.ts` 신설 (임계값 체크 + 큐잉 + socket.io 푸시)
9. `audit-log.service.ts` 확장: `entity_type='permission'` + assign/revoke/grant/threshold_change
10. `/api/permissions/matrix` 엔드포인트 (FE 매트릭스 화면용)
11. 단위테스트 + integration 테스트 (real DB, mock 금지)

### Phase C — Frontend (1.5주)

12. `pages/configuracion/permisos/` 페이지 4탭 신설
13. `usePermissionsMatrix` SWR 훅 (5분 dedup)
14. 매트릭스 그리드 컴포넌트 (sticky header/column, 가상 스크롤)
15. 사용자 상세 카드 (multi-branch row + 오버라이드)
16. 감사 로그 타임라인 + 롤백 버튼
17. 임계값 설정 인라인 편집 표
18. CASL `subject` ↔ BE `function_slug` 동기화 generator 스크립트

### Phase D — 운영 적용 (1주)

19. 운영 PG10 마이그레이션 (① ADD COLUMN → ② backfill → ③ NOT NULL, 점진적 배포)
20. 모든 매장에 대해 기존 user 들 `user_branches` 자동 생성 (1:1 매핑)
21. 사용자별 안내 + 8 Role 매핑 가이드 (각 매장 owner 에게)
22. 7일 모니터링: pool 사용률, P95 권한 체크 latency, 에러율
23. 1주 후 회고: 실제 사용 패턴 분석, 임계값 조정

---

## 6. 빠지기 쉬운 함정 (3가지)

### ❌ 함정 1 — "한 번에 이상적 모델로 갈아엎기"

**증상**: 8 Role 정의 + 매트릭스 변경 + Branch 스코프 + 임계값 + 감사 + 캐시를 동시에 배포.
**위험**: 권한이 한 곳에서 잘못 계산되면 모든 사용자가 401/403 폭주. 운영 매장이 멈춥니다.
**대응**:
- 기능 플래그 (`PERMISSIONS_V2`) 로 개별 매장씩 점진 롤아웃 (ACE → coolsistema → genius → CART 순)
- 신규 가드와 구 가드 병렬 운영 (신규 가드는 log only 모드로 7일, deny 차이 분석 후 enforce)
- 각 매장에 1주일 dry-run 기간 부여

### ❌ 함정 2 — "Connection pool 폭주 (성능 함정)"

**증상**: 권한 체크는 모든 요청에 들어가므로 잘못 짜면 RPS × 5 쿼리. pool 50개로는 부족.
**구체 시나리오**:
- 캐시 미적용 → 매 요청마다 user_branches + role_functions + role_function_actions + user_functions = 4 쿼리
- N+1: 매트릭스 화면 로딩 시 사용자 100명 × role 8개 × function 40개 = 32,000 쿼리
**대응**:
- `user_permission_cache` 테이블 + 5분 TTL (DB 캐시, Redis 안 씀)
- 매트릭스 API 는 단일 SQL with CTE + JSONB aggregate (1 round trip)
- 권한 변경 시 affected user 들의 cache row만 DELETE (selective invalidation)
- Phase D 모니터링에서 pool 사용률 80% 넘으면 자동 알림

### ❌ 함정 3 — "감사 로그를 사후에 추가" + "롤백 없는 권한 변경"

**증상**: V1 출시 후 "audit 는 다음 phase 에" 로 미루다가, 누가 누구의 권한을 바꿨는지 6개월 동안 못 본 채 사고 발생.
**위험**: 내부 부정 (cashier 가 본인에게 환불 권한 부여) 적발 불가. 외부 감사 (SOX 등) 대응 불가.
**대응**:
- audit_log INSERT 를 권한 변경 트랜잭션 안에 강제 (DB constraint 또는 service decorator)
- audit_log INSERT 실패 시 전체 트랜잭션 ROLLBACK
- "롤백 버튼" 을 UI 에 노출 — 실수 복구가 쉬워야 사용자가 audit 를 신뢰함
- Phase A 에서 audit_log 확장을 같이 하기 (절대 후순위로 미루지 말기)

---

## 7. 점검 포인트 (1주 / 1개월 / 3개월)

### 1주 후 점검
- [ ] 운영 매장 401/403 발생률이 V1 대비 10% 이내인가?
- [ ] PG pool 사용률 P95 ≤ 70% 인가? (현재 max=50)
- [ ] 권한 체크 latency P95 ≤ 30ms 인가?
- [ ] audit_logs 의 `entity_type='permission'` 일일 row 수가 합리적인가? (너무 적으면 누락 의심)
- [ ] 매장 owner 가 신규 UI 에서 사용자 추가 / role 부여를 SQL 도움 없이 완료할 수 있는가?

### 1개월 후 점검
- [ ] Approval Threshold 의 실제 사용 (큐잉 발생 빈도) 분석 — 임계값이 너무 빡빡하거나 느슨한가?
- [ ] 가장 많이 사용된 user_function 오버라이드 top 10 — 표준 role 에 흡수할 만한 패턴이 있는가?
- [ ] Branch_manager 가 본인 지점 외 데이터 접근 시도 (403) 빈도 — UI 가 명확한가?
- [ ] Cache hit ratio ≥ 95% 인가?
- [ ] 운영 매장 4곳 (ACE/coolsistema/genius/CART) 모두 V2 적용 완료?

### 3개월 후 점검
- [ ] 신규 매장 셋업 시 권한 부여 시간 단축 여부 (목표: 30분 → 5분)
- [ ] 권한 변경 사고 (잘못된 부여로 인한 데이터 사고) 발생 건수 (목표: 0)
- [ ] Audit log 를 활용한 외부 감사/회계 보고 가능 여부 (실제 try)
- [ ] Customizable Role 생성 패턴 분석 — base template 에서 평균 몇 개 함수를 추가/제거하는가?
- [ ] **다음 단계 ABAC 도입 검토**: "본인이 만든 판매만 환불 가능", "근무 시간 외 금고 접근 차단" 같은 조건부 권한이 필요한가?

---

## 8. 참고 — 기존 코드 영향 범위

| 영역 | 영향 파일 | 변경 종류 |
|---|---|---|
| BE Models | `users/users.model.ts`, `role/role.model.ts`, `users/user-role/user-role.model.ts` | 신규 모델 추가, 기존 그대로 |
| BE Guards | `auth/guards/function-permission.guard.ts`, `auth/guards/user-role.guard.ts` | 핵심 리팩터 (1-query + cache) |
| BE Services | `auth/auth.service.ts` (`/me`), `audit-log/audit-log.service.ts`, 신규 `approval.service.ts` | 확장 + 신규 |
| BE Controllers | 신규 `permissions.controller.ts`, `approval.controller.ts` | 신규 |
| FE Pages | 신규 `pages/configuracion/permisos/index.tsx` (4 탭) | 신규 |
| FE Hooks | 신규 `hooks/api/usePermissionsMatrix.ts`, `useUserBranches.ts`, `useApprovalQueue.ts` | 신규 SWR 훅 |
| FE Contexts | `BranchContext.tsx` 에 multi-branch 지원 추가 | 확장 |
| FE ACL | `configs/acl.ts`, `configs/roles.ts` | generator 스크립트로 자동 생성 |
| Migrations | `api-ventago/migrations/0XX-0XY_*.sql` (총 5-6 파일) | 신규 |

---

## 9. 결론 — 무엇이 가장 중요한가

세 가지 우선순위:

1. **Branch 스코프** 가 모든 변화의 기반입니다. 이게 없으면 나머지(role 표준, 임계값, audit) 가 다 매장 단일 차원에 묶여서 멀티지점 매장에 가치를 못 주게 됩니다.
2. **감사 로그를 처음부터** 넣으세요. 후순위로 미루면 영원히 안 들어갑니다. 감사 로그가 있어야 신뢰성 있는 권한 위임이 가능합니다.
3. **8 Role 은 시작점이지 종착점이 아닙니다.** 3개월 운영 후 실제 사용 패턴을 보고 9-10번째 role 추가 또는 일부 통합을 결정하세요. 처음부터 완벽한 role 셋을 만들려 하지 마시고, 평균적인 80% 매장이 표준 8개 안에서 운영 가능하면 충분합니다.

---

*문서 끝. 의견·수정 요청은 issue 또는 직접 commit 으로.*
