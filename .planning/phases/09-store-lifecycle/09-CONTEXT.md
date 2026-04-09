# Phase 9: Store Lifecycle & Admin IA 통합 - Context

**Gathered:** 2026-04-06
**Status:** Ready for planning
**Source:** Conversation-derived (superadmin 메뉴 UX 문제 진단, 사용자 확정 2026-04-06)

<domain>
## Phase Boundary

Admin 영역의 IA(정보 구조) 혼란 해결 + Store 상태 머신 도입.

**해결할 문제:**
1. 사이드바 "Tiendas"와 "Registros" 두 메뉴의 역할 불명확 (둘 다 같은 stores 테이블을 다른 필터로 조회)
2. Registros의 상세 진입 시 사이드바 active가 Tiendas로 점프 (경로: `/admin/tiendas/detalle/[id]`)
3. Trial/Suspended 등 실제 상태가 `Users.status`에 분산 저장되어 Store 단위 조회 불가
4. Tiendas 목록이 `status IN (0,1)` 필터로 trial 매장을 누락

**해결 방안:**
- "Registros" 메뉴 제거, "Tiendas" 단일 진입점으로 통합
- Store 레벨 lifecycle 상태 머신 도입 (TRIAL/ACTIVE/SUSPENDED/ARCHIVED/DELETED)
- Tiendas 화면에 탭 스트립 + KPI 카드
- 상세 경로 단순화 `/admin/tiendas/[id]` + breadcrumb 출처 표시

</domain>

<decisions>
## Locked Decisions (사용자 확정 2026-04-06)

### 상태 머신 (Locked)
```
TRIAL ─┬─→ ACTIVE ─┬─→ SUSPENDED ─┬─→ ARCHIVED ─→ DELETED
       │           │              │
       └─ (cron)──→ SUSPENDED ←───┘ (수동 복구 가능)
```

| 상태 | 의미 | 진입 조건 | POS 접근 |
|------|------|-----------|---------|
| **TRIAL** | 30일 체험 | 매장 자체 생성 시 기본값, `trialEndsAt = now + 30일` | ✅ 가능 |
| **ACTIVE** | 결제 확정 운영 | superadmin이 수동 승인 (결제 확인 후) | ✅ 가능 |
| **SUSPENDED** | 정지 (미결제/만료) | cron: `trialEndsAt + gracePeriod < now` / 수동 | ❌ 로그인 차단 |
| **ARCHIVED** | 장기 보관 (휴면) | superadmin 수동 보관 | ❌ 읽기전용 |
| **DELETED** | 삭제 예정 (soft) | superadmin 수동 삭제 | ❌ 숨김 |

### 핵심 규칙 (Locked)
- **매장 생성 = 무조건 TRIAL 30일** 자동 부여 (사용자 자체 생성)
- **trialEndsAt은 Store 레벨 단일 값** (복수 admin 있어도 매장 단위 1개)
- **Trial 연장은 superadmin 수동**으로만 가능 (`PUT /store/:id/extend-trial` 기존 엔드포인트 재활용)
- **ARCHIVED 상태 필수** — 장기 미결제 매장을 삭제하지 않고 데이터 보존
- **기존 `Users.status` (trial/active/suspended) 는 Store lifecycle과 동기화** (cascade update)

### 데이터 모델 변경 (Locked)
```sql
ALTER TABLE stores ADD COLUMN lifecycle_state VARCHAR(20) NOT NULL DEFAULT 'TRIAL';
ALTER TABLE stores ADD COLUMN trial_ends_at TIMESTAMP;       -- 매장 단위 단일값
ALTER TABLE stores ADD COLUMN activated_at TIMESTAMP;         -- TRIAL→ACTIVE 전이 시각
ALTER TABLE stores ADD COLUMN suspended_at TIMESTAMP;         -- SUSPENDED 진입 시각
ALTER TABLE stores ADD COLUMN archived_at TIMESTAMP;          -- ARCHIVED 진입 시각
ALTER TABLE stores ADD COLUMN lifecycle_reason TEXT;          -- 상태 변경 사유 (감사용)
CREATE INDEX idx_stores_lifecycle ON stores(lifecycle_state);
CREATE INDEX idx_stores_trial_ends ON stores(trial_ends_at) WHERE lifecycle_state = 'TRIAL';
```

**기존 컬럼 처리:**
- `status` (VARCHAR '0'|'1'|'2'), `isActive` (BOOLEAN) → **deprecate**하되 1 사이클 동안 읽기 호환 유지
- 신규 코드는 `lifecycle_state` 만 참조
- Phase 9 종료 후 별도 cleanup phase에서 제거

### 프론트엔드 경로 변경 (Locked)
| Before | After |
|--------|-------|
| `/admin/tiendas` (status=0,1 필터) | `/admin/tiendas` (탭: Todas/Trial/Activas/Suspendidas/Archivadas/Papelera) |
| `/admin/registros` | **제거** (삭제) |
| `/admin/tiendas/detalle/[id]` | `/admin/tiendas/[id]` (기존 경로는 307 리디렉트) |
| Sidebar: Tiendas + Registros | Sidebar: **Tiendas 단일** |

### API 변경 (Locked)
- `GET /store?state=TRIAL,ACTIVE&page=&pageSize=` — state 쿼리 추가 (기존 status 파라미터는 deprecate)
- `GET /store/with-admin` → `GET /store?include=admin` 로 통합 후 `/with-admin`은 내부 리디렉트 유지
- `PUT /store/:id/activate` — TRIAL/SUSPENDED → ACTIVE (결제 확인 후 superadmin)
- `PUT /store/:id/suspend` — ACTIVE → SUSPENDED (수동 정지)
- `PUT /store/:id/archive` — SUSPENDED → ARCHIVED
- `PUT /store/:id/restore` — ARCHIVED → ACTIVE/SUSPENDED (이전 상태로 복구)
- `PUT /store/:id/extend-trial` — 기존 엔드포인트 유지, trialEndsAt만 갱신
- `GET /store/lifecycle-stats` — 상단 KPI 4개용 집계 (한 번 쿼리로 모든 count)

### Cron 재작성 (Locked)
기존 `store.cron.ts`의 `suspendExpiredStores`를 Store 레벨로 재작성:
```typescript
// 매일 00:00
WHERE lifecycle_state = 'TRIAL'
  AND trial_ends_at + interval '{gracePeriodDays} days' < NOW()
→ 배치 UPDATE: lifecycle_state='SUSPENDED', suspended_at=NOW()
→ cascade: Users.status='suspended' (해당 storeId)
→ 알림: superadmin 이메일 + 매장 admin 이메일
```
**pool 낭비 없도록:** 단일 SELECT + 단일 batch UPDATE + 단일 batch Users UPDATE. for-loop 금지.

### Session Guard 연동 (Locked)
`guards/session.guard.ts`에 체크 추가:
- Store.lifecycle_state IN ('SUSPENDED','ARCHIVED','DELETED') → 401 `STORE_SUSPENDED`
- 프론트: 로그인 시도 또는 기존 세션 토큰 사용 시 해당 에러 → "매장이 정지되었습니다. 관리자에게 문의하세요" 모달

</decisions>

<data>
## Current State (확인됨 2026-04-06)

### 발견된 코드 현실
- **`Store.status`**: VARCHAR, `'0'`(INACTIVE) / `'1'`(ACTIVE) / `'2'`(DELETED) — enum `Status`
- **`Store.isActive`**: BOOLEAN, toggle 용도
- **`Users.status`**: VARCHAR, `'trial'` / `'active'` / `'suspended'` ← **실제 trial 상태가 여기 있음**
- **`Users.trialEndsAt`**: TIMESTAMP, admin 유저에 설정
- **`SubscriptionConfig.gracePeriodDays`**: 기본 3일
- **`StoresListView`**: `/store?status=0,1` 쿼리 → trial 매장 누락의 원인
- **`RegistrationsList`**: `/store/with-admin` 쿼리 → 필터 없음, 실상 "admin 정보가 붙은 tiendas 뷰"
- **상세 페이지**: 두 뷰 모두 `/admin/tiendas/detalle/[id]` 로 진입 → 사이드바 점프
- **`store.cron.ts`**: 기존에 Users.status='trial' + trialEndsAt 기준으로 suspend 처리 중

### Backfill 전략
```sql
-- Users.status + trialEndsAt 기반으로 Store.lifecycle_state 백필
UPDATE stores s SET
  lifecycle_state = CASE
    WHEN s.status = '2' THEN 'DELETED'
    WHEN (SELECT u.status FROM users u
          WHERE u.store_id=s.id AND u.role='admin' LIMIT 1) = 'suspended' THEN 'SUSPENDED'
    WHEN (SELECT u.status FROM users u
          WHERE u.store_id=s.id AND u.role='admin' LIMIT 1) = 'trial' THEN 'TRIAL'
    WHEN s.is_active = true THEN 'ACTIVE'
    ELSE 'SUSPENDED'
  END,
  trial_ends_at = (SELECT MAX(u.trial_ends_at) FROM users u WHERE u.store_id=s.id),
  activated_at = CASE WHEN s.is_active THEN s.created_at ELSE NULL END;
```

</data>

<constraints>
## Constraints

- **운영 중 시스템**: 현재 2개 매장이 운영 중 → 다운타임 없이 마이그레이션해야 함
- **Phase 6/8과 경로 분리**: Phase 9는 `api-ventago/src/app/store/`, `ventago-app/src/views/admin/stores/`, `pages/admin/tiendas/` 만 건드림. reportes 경로와 겹치지 않음
- **Pool 낭비 금지**:
  - KPI 집계는 단일 쿼리 `SELECT lifecycle_state, COUNT(*) FROM stores GROUP BY lifecycle_state`
  - Cron의 만료 처리는 배치 UPDATE 1회 (for-loop 금지)
  - 목록 조회 시 admin 정보 join은 `include` 옵션으로 N+1 방지
- **기존 API 호환성**: `/store?status=...` 파라미터는 1 사이클 동안 내부적으로 `state=`로 매핑 후 deprecate
- **Sequelize underscored**: 신규 컬럼 snake_case 준수 (`lifecycle_state`, `trial_ends_at` 등)
- **ESLint**: newline-before-return, lines-around-comment 준수
- **세션 보안**: SUSPENDED 매장의 기존 active_sessions 즉시 invalidate

</constraints>
