# Phase 26 — CONTEXT

**Phase**: 26 — Gastos N차 카테고리 트리 (무한 깊이, 최대 5단계)
**Created**: 2026-04-27
**Source**: `/gsd-discuss-phase 26` (manual workflow execution)

---

## 1. Phase Goal (recap)

기존 2단계 평면 카테고리(`expenses_categories` + `expenses_subcategories`)를 단일 자기참조 트리(`expense_categories`)로 통합. 사용자가 매장별로 N차 카테고리를 자유롭게 만들고, subtree 째 이동/삭제/시각 관리하고, 어느 깊이의 노드든 gasto 등록에 사용. Reports 는 recursive CTE 로 부모에 자손 합계 자동 롤업, 사용자가 depth 조절 가능.

---

## 2. Locked Decisions (Add-phase + Discussion)

### Add-phase 단계에서 사용자 확정 (4건)

| # | Decision | 근거 |
|---|---|---|
| L1 | **깊이 5단계 제한** | UX 안전 + DB CHECK + app-level 가드 모두 적용 |
| L2 | **삭제 시 자식 처리 정책 3종 선택** | (a) 부모로 승격 (b) 다른 노드로 이동 (c) 전체 subtree 삭제 |
| L3 | **Reports depth 사용자 선택** | UI에 "1까지 / 2까지 / 전체" 토글 |
| L4 | **다른 부모로 subtree 이동 지원** | API 레벨 `PUT /:id/move` |

### Discuss-phase 단계 추가 결정 (Area 1-4)

#### Area 1 — 트리 컴포넌트 + 드래그 UX
- **D1.1 트리 라이브러리**: **`react-arborist`** 채택
  - 사유: 네이티브 D&D + 가상화 + 검색 + 키보드 내장. RolePermissionsDrawer가 사용 중인 `@mui/lab/TreeView`와 라이브러리는 다르지만 충돌 없음. 새 의존성 ~30KB 허용.
  - 영향: researcher가 react-arborist API/v3 best practice 조사. planner가 컴포넌트 구조 설계.
- **D1.2 드래그 범위**: **같은 부모 내 정렬만**
  - 사유: 실수 사고 최소화. 다른 부모로 이동은 명시적 [Move to...] 메뉴 + dialog 경유.
  - 영향: drag handler는 sibling reorder만 처리. cross-parent move는 별도 endpoint `/move` + dialog UI. 두 경로 모두 depth 5 검증 + 사이클 검증.

#### Area 2 — 기본 카테고리 시드 + 빈 트리 UX
- **D2.1 신규 매장 자동 시드**: **6개 기본 카테고리 자동 생성**
  - 시드 목록: `Servicios`, `Comida`, `Transporte`, `Insumos`, `Sueldos`, `Otros` (모두 루트, depth=0)
  - 사용자가 각자 이름/색상/아이콘 수정 + 자식 추가 + 삭제 자유
  - 트리거: `expense_categories` 마이그레이션 직후 + `signUp`/`createStoreDefaults` 흐름에서 카테고리 0개일 때
  - 영향: planner가 seed 함수를 `storeTemplate.service.ts` 또는 별도 `expenseCategorySeed.service.ts`에 배치
- **D2.2 기존 매장 카테고리**: **그대로 유지 (추가 시드 없음)**
  - 마이그레이션이 기존 categories → 루트 + subcategories → 자식으로 변환만. 기본 6개 추가 시드는 신규 매장 한정.

#### Area 3 — Soft delete + In-use 보호 정책
- **D3.1 삭제 처리**: **Soft delete (`status=0`)**
  - row 보존, 기본 트리 뷰에서는 숨김
  - 관리 페이지에 `[Mostrar archivados]` 토글 → archived 표시 + `[↶ Restaurar]` 버튼
  - 기존 expense 레코드의 category_id FK는 그대로 유효 (path 도 그대로 표시 가능)
  - hard delete은 별도 admin-only endpoint `DELETE /:id?force=true`로만 (UI 노출 X)
- **D3.2 In-use 보호**: **경고 dialog 후 진행**
  - rename/move/delete 시 `WHERE category_id = ?` count → N>0이면 confirm dialog
  - dialog 내용: "Esta categoría está usada en N gastos (N este mes). Continuar?"
  - admin 사용자가 confirm 누르면 진행. cascade 없이 단순 변경 — expense.category_id는 그대로, path는 join으로 자동 재계산되므로 historical reports에서 새 path 표시됨

#### Area 4 — Gasto 폼 카테고리 셀렉터 UX
- **D4.1 검색 범위**: **Path 전체 매칭**
  - 입력 키워드를 노드 name + 부모 path 모두에서 부분 검색
  - 다중 공백 키워드 = AND 매칭 (`"serv móv"` → "Servicios > Internet > Móvil" 매치)
  - 매칭된 노드의 부모는 자동 펼침
  - 매칭 부분 highlight (옵션, planner 결정)
- **D4.2 MRU (Most Recently Used)**: **사용자별 최근 5개 상단 노출**
  - 드롭다운 열림 시 상단 "Recientes" 섹션 + 그 아래 전체 트리
  - 데이터: 사용자가 최근 30일 내 등록한 expense의 category_id 중 빈도 상위 5
  - 저장 위치: `localStorage` 키 (`expense_category_mru_user_${userId}`) — 서버 라운드트립 절약
  - 또는 `users.preferences` JSON 컬럼에 (planner 결정. 두 옵션 다 OK)
- **D4.3 인라인 카테고리 생성**: **하단 `[+ Crear "{입력값}" en...]` 버튼**
  - 검색 입력값과 일치하는 노드 없을 때 또는 항상 표시
  - 클릭 시 부모 선택 mini-dialog → 부모 트리 → 선택 → POST `/expense-categories` → 생성된 노드 자동 선택
  - 마찰 최소화 (Gasto 등록 흐름 끊지 않음)

---

## 3. Architecture Locked

(researcher가 알아야 할 내용)

- **DB 패턴**: Adjacency list (`parent_id` self-FK) + Materialized path (`path` 컬럼)
- **path/depth 자동 갱신**: PostgreSQL BEFORE INSERT/UPDATE 트리거
- **Reports 롤업**: `WITH RECURSIVE` CTE
- **Sequelize**: self-FK + HasMany `children` / BelongsTo `parent`
- **Frontend tree library**: `react-arborist`
- **삭제 정책**: Soft delete (`status=0`)
- **Cycle/depth 가드**: DB CHECK + app-level pre-validation

---

## 4. Open Questions for Researcher

(planner 가 spec할 때 검토 필요)

1. **react-arborist의 Korean/Spanish 입력 (composition event)** 동작 검증 필요 — 한글 입력 중 Enter 키 처리
2. **Materialized path 트리거의 cascade 깊이 처리** — 부모 path 변경 시 모든 자손 path 재계산 — 효율적 방식 (재귀 트리거 vs 단일 UPDATE with CTE)
3. **react-arborist 가상화** 가 트리 노드 50개 이하에서 오히려 부담인지 — 실제 매장 카테고리 수 보면 5단계 × 5형제 = 최대 ~625개, 평균 ~30개. 가상화 불필요 가능성
4. **MRU 저장 위치** 결정 — localStorage (간단, 디바이스 별 분리) vs `users.preferences` (서버 동기화, 멀티 디바이스). 권장: localStorage first-cut, 추후 동기화 필요시 서버 이관

---

## 5. Deferred Ideas (Scope-Out)

이번 phase 범위 아님. 별도 backlog 또는 다음 milestone:

- **Color/Icon 편집 UI 풍부도** — 현재 결정: 컬럼만 추가, 기본 UI는 단순 (default color=null, default icon=null). 컬러 피커/iconify picker는 follow-up phase에서.
- **Bulk operations** — 여러 노드 동시 선택해 한 번에 이동/삭제. 일단 단일 노드만.
- **CSV/Excel 카테고리 트리 일괄 import** — Phase 25 패턴 재사용 가능하나 이번 phase는 UI 수동 입력만.
- **카테고리 변경 audit log** — REQ-17에 명시되어 있으나 audit table 통합은 Phase 25 client_audit 패턴 따라가는 정도로 가볍게.
- **다국어 노드 이름 lookup** — 사용자 입력 텍스트 그대로. i18n은 UI 라벨만 (es/ko).
- **Hard delete UI 노출** — 현재는 endpoint만 제공, UI 버튼 없음. 데이터 정리 필요시 SQL 직접.

---

## 6. Implementation Hints (Planner를 위한)

- **테이블명**: `expense_categories` (단수 → 복수 변환 sequelize 자동)
- **컬럼**: `id, store_id, parent_id, name, path, depth, sort_order, color, icon, status, created_at, updated_at`
- **인덱스**: `(store_id, parent_id)`, `(store_id, status, path)` (path prefix 검색용)
- **Trigger**: `update_expense_category_path()` BEFORE INSERT/UPDATE — parent 변경 시 본인 + 모든 자손 path/depth 재계산. UPDATE 트리거는 `OLD.parent_id IS DISTINCT FROM NEW.parent_id OR OLD.name IS DISTINCT FROM NEW.name` 조건으로 효율화
- **Sequelize hook 대안**: 트리거 대신 `beforeSave` hook으로도 가능 — 운영 PG 10 + 로컬 PG 15 호환성 검증 필요
- **마이그레이션 단계**:
  1. `expense_categories` 테이블 + 트리거 + 인덱스 생성
  2. 기존 `expenses_categories` → 루트 노드 INSERT (parent_id=NULL)
  3. 기존 `expenses_subcategories` → 자식 노드 INSERT (parent_id=루트.id)
  4. `expenses.category_id` 재배선: 기존에 subcategory_id 가 있던 row → 새 자식 노드 id로 매핑, 없던 row → 새 루트 노드 id로 유지
  5. `expenses.subcategory_id` 컬럼 drop
  6. 기존 `expenses_categories` / `expenses_subcategories` 테이블 deprecated 표시 (즉시 drop 안 함, 2주 후 별도 cleanup phase)
- **새 매장 시드** (Area 2 D2.1): `createStoreDefaults` 또는 `signUp` 흐름 마지막에 카테고리 0개면 6개 기본값 INSERT
- **UI 페이지 위치**: `/configuracion/categorias-gastos` (또는 `/gastos/categorias` — planner가 navigation 일관성 보고 결정)
- **권한**: 기본 expenses CRUD 권한 (admin OK, vendedor 차단). 트리 구조 변경(create/move/delete)은 admin only

---

## 7. Testing Strategy Hints

- **유닛**: path/depth 트리거 정확성 (5단계 깊이 + 사이클 + UPDATE 시 자손 재계산)
- **통합**: 기존 매장 마이그레이션 결과 검증 — 카테고리 수 보존, expense.category_id 재배선 정확도, reports rollup 일치
- **E2E**: 새 매장 가입 → 기본 6개 시드 확인 → 카테고리 추가 → 자식 추가 → 다른 부모로 이동 → 삭제 → archive 토글
- **회귀**: 기존 gasto 등록/리스트/reports 화면 모두 새 모델로 정상 동작 (subcategory_id drop 후에도)

---

## 8. Next Steps

이 CONTEXT.md 가 정해졌으니:

```
/gsd-plan-phase 26
```

planner가 이 결정을 바탕으로 Wave 단위 plan 생성. 예상 wave 분할:
- **Wave 1 (Schema)**: 새 테이블 + 트리거 + 마이그레이션 + Sequelize 모델
- **Wave 2 (Backend API)**: tree CRUD endpoints + 시드 함수 + soft delete + in-use guard
- **Wave 3 (관리 UI)**: react-arborist 트리 페이지 + 삭제 다이얼로그 (3옵션) + Mostrar archivados 토글
- **Wave 4 (Gasto Form + Reports)**: 트리 드롭다운 셀렉터 (검색/MRU/inline create) + Reports depth 토글 + recursive CTE 롤업
- **Wave 5 (Migration & Cleanup)**: 운영 마이그레이션 실행 + deprecated 테이블 모니터링 + 회귀 검증

---

## 9. Risks / Gotchas

- **PG 10 (운영) vs PG 15 (로컬) 호환성**: 트리거 함수 + recursive CTE 모두 PG 10 호환. `WITH RECURSIVE` OK, `GENERATED AS IDENTITY` 같은 신규 기능은 사용 안 함 (CLAUDE.md 명시)
- **Sequelize underscored 매핑**: 모델은 camelCase (`parentId`, `sortOrder`), DB는 snake_case (`parent_id`, `sort_order`). 트리거에서 SQL 작성 시 snake_case 사용
- **Sequelize 자기참조 + 무한 include 위험**: HasMany `children`을 무한 재귀하면 stack overflow. tree 조회는 단일 SQL + 메모리 트리 빌드 권장 (recursive CTE로 한 번에 가져와 client-side 트리 구성)
- **Soft delete된 카테고리의 자식 처리**: 부모가 archive되면 자식들은? — 기본: archive cascade 안 함 (자식은 active 그대로). 단 부모가 archive면 트리 뷰에서 자식도 안 보임 (부모 펼치기 불가). 사용자가 archived 토글로 확인 가능. **결정 필요시 planner에서 추가 논의**.
- **MRU localStorage**: 디바이스 변경 시 손실 OK (UX 보조 기능, critical 아님). 멀티 매장 superadmin은 storeId별로 MRU 분리 필요 (`expense_category_mru_user_${userId}_store_${storeId}`).
