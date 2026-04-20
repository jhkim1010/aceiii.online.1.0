---
phase: quick-260420
plan: 01
subsystem: admin/products
tags: [tienda, variants, cantidad, products, admin, auth]
dependency_graph:
  requires:
    - stores 테이블 (기존)
    - storeTemplate.service.ts 가 생성하는 'Color Único' / 'Talle Única' 기본 엔티티
    - AuthContext 가 /me 응답을 {...response} 로 setUser 에 전달
    - ProductContext 의 colors/sizes state
    - products/variants/batch 기존 컨트롤러 계약
  provides:
    - stores.use_variants 컬럼 + Store.useVariants 모델 필드
    - /api/auth/me 응답에 useVariants flat 필드
    - UserDataType.useVariants 프론트 타입
    - ModalStore 'Usar variantes (color / talle)' Switch 토글
    - ProductsView 단순 cantidad 모드 (useVariants=false)
  affects:
    - Admin → Tiendas 편집 모달 UI
    - 상품 등록 화면 레이아웃 (우측 패널)
    - POST /products + POST /products/variants/batch 호출 payload (단일 variant)
tech-stack:
  added: []
  patterns:
    - FormData boolean 문자열 → server-side coerce 패턴 (controller 에서 'true'/'false' → boolean)
    - DTO 측 @Transform(({ value }) => value === true || value === 'true') 패턴
    - useMemo 기반 기본 Color/Size id 조회 후 단일 variant 재사용
key-files:
  created:
    - api-ventago/migrations/add-use-variants-to-stores.sql
  modified:
    - api-ventago/src/app/store/store.model.ts
    - api-ventago/src/app/store/dto/update-store.dto.ts
    - api-ventago/src/app/store/store.controller.ts
    - api-ventago/src/app/auth/auth.service.ts
    - ventago-app/src/context/types.ts
    - ventago-app/src/views/admin/stores/list/components/ModalStore.tsx
    - ventago-app/src/views/products/list/ProductsView.tsx
decisions:
  - "stores.use_variants DEFAULT TRUE 로 설정 — 기존 매장 회귀 방지"
  - "FormData 'true'/'false' 변환은 controller + DTO 양쪽에서 안전장치 (controller 는 현재 사용 중인 @Body() any 경로 보호, DTO 는 향후 ValidationPipe 적용 대비)"
  - "단순 모드 단일 variant 는 기존 'Color Único' / 'Talle Única' 기본 id 재사용 — Products.color_id/size_id NOT NULL 제약 충족"
  - "AuthContext 는 기존 {...response} 스프레드 그대로 활용 — useVariants 는 타입만 확장"
  - "useVariants=false 모드에서 재입고(parentId 존재 시)도 기본 id 1건으로 stock 증분"
  - "cantidad 상태는 product 가 비어있을 때 자동 0 리셋 (resetAll 후 product.name/id 비어짐 감지)"
metrics:
  duration: "~20분"
  completed_date: "2026-04-20"
  tasks_total: 3
  tasks_completed: 3
  files_touched: 8
---

# Quick Task 260420-qet: Tienda admin useVariants=false — 단순 cantidad 모드 Summary

Tienda admin 에서 `useVariants=false` 로 설정한 매장은 ProductsView 진입 시 색·사이즈 grid 없이
cantidad TextField 하나만으로 단일 variant 상품을 생성할 수 있도록 전체 스택을 관통해서 연결.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] ESLint `lines-around-comment` 오류 수정**
- **Found during:** Task 3 ESLint 실행 중
- **Issue:** Action Bar cantidad 분기 `: (` 뒤 주석 `// 단순 모드: 수량 직접 입력...` 위에 빈 줄이 없어 ESLint 에러
- **Fix:** 주석 위에 빈 줄 삽입 (CLAUDE.md lines-around-comment 규칙 준수)
- **Files modified:** ventago-app/src/views/products/list/ProductsView.tsx
- **Commit:** 89184d0 (동일 커밋 내 포함)

**2. [Rule 2 - Missing Critical] store.controller PUT /store/:id 의 isActive FormData 문자열 → boolean 변환 추가**
- **Found during:** Task 1 controller 작업
- **Issue:** PUT 경로에서 `@Body() body: any` 로 받기 때문에 기존 FormData 의 `isActive: 'true'` 문자열이 sequelize update 에 그대로 전달되던 잠재 이슈 존재. 동일한 boolean 변환 로직을 useVariants 와 함께 보강.
- **Fix:** `if (body.isActive !== undefined && typeof body.isActive === 'string') body.isActive = body.isActive === 'true'` 추가
- **Files modified:** api-ventago/src/app/store/store.controller.ts
- **Commit:** c777561

**3. [Rule 2 - Missing Critical] 신규 매장 생성 시 useVariants 기본값 보정**
- **Found during:** Task 2 ModalStore 작업
- **Issue:** `isEdit=false` (신규 생성) 경로에서 `defaultValues` 에 useVariants 가 없어 `undefined` 로 토글되면 서버에 `useVariants=false` 로 저장될 위험
- **Fix:** `getInitialValues()` 신규 분기에서 `{ ...defaultValues, useVariants: true }` 반환하도록 기본값 고정
- **Files modified:** ventago-app/src/views/admin/stores/list/components/ModalStore.tsx
- **Commit:** 1087dde

### Out-of-scope (deferred)

- **Pre-existing `react-hooks/exhaustive-deps` warning in ModalStore.tsx (L73)** — 기존 코드의 `React.useEffect(..., [open, store, typeOfPayers])` 가 `getInitialValues`/`reset` 의존성을 누락. 본 task 이전에도 존재하던 warning 이므로 scope boundary 원칙에 따라 수정하지 않음.
- **Pre-existing tsc error in `src/@fake-db/mock.ts`** — axios 타입 충돌 (ventago-app / 루트 모노레포 이중 설치 이슈). 본 task 이전에도 존재했고 변경 파일과 무관하므로 건드리지 않음.

## Files Touched

### api-ventago (sub-repo commit `c777561`)
- `migrations/add-use-variants-to-stores.sql` — NEW (19 lines)
  - `ALTER TABLE stores ADD COLUMN IF NOT EXISTS use_variants BOOLEAN NOT NULL DEFAULT TRUE`
  - 검증 SELECT + Docker 실행 주석 포함
- `src/app/store/store.model.ts` — +7 lines
  - `@Column({ type: DataType.BOOLEAN, allowNull: false, defaultValue: true }) declare useVariants: boolean`
- `src/app/store/dto/update-store.dto.ts` — +7 lines
  - `class-transformer` Transform import, `@IsOptional() @Transform(...) @IsBoolean() useVariants?: boolean`
- `src/app/store/store.controller.ts` — +10 lines (updateStore 핸들러)
  - FormData 'true'/'false' 문자열을 boolean 으로 변환 (useVariants + isActive 안전장치)
- `src/app/auth/auth.service.ts` — +4 lines (3곳)
  - `let useVariants: boolean = true` 선언
  - store 조회 직후 `useVariants = store?.useVariants ?? true`
  - superadmin/일반 두 return 블록 모두에 `useVariants` flat 필드 포함

### ventago-app (sub-repo commits `1087dde`, `89184d0`)
- `src/context/types.ts` — +3 lines
  - `UserDataType.useVariants?: boolean` 필드 선언 (주석 포함)
- `src/views/admin/stores/list/components/ModalStore.tsx` — +33 lines
  - MUI `Switch`, `FormControlLabel` + react-hook-form `Controller` import
  - `useForm` 에 `control` 추출, 기본값 `useVariants: store?.useVariants ?? true`
  - `onSubmit` 에서 `formData.append('useVariants', data.useVariants ? 'true' : 'false')`
  - Grid item xs=12 토글 UI + helper caption
- `src/views/products/list/ProductsView.tsx` — +202 / -98 lines (분기 전환 위주)
  - `TextField` import 추가
  - `const useVariants = user?.useVariants ?? true` + `useState<number>(0)` cantidad
  - `defaultColorId` / `defaultSizeId` useMemo (Color Único / Talle Única id 조회)
  - `handleSubmit` cantidad>0 검증 분기
  - `doSubmit` 단일 variant 빌드 분기 (기존 parent 존재 시 동일 조합 stock 증분)
  - Action Bar chip → `useVariants ? Stock chip : Cantidad TextField`
  - 우측 패널: `useVariants=false` 면 VariantsStock + TB Resizer + editingMadre info bar 모두 미렌더, SelectorBranch + ProductParentList 만 표시
  - Confirm 다이얼로그 Stock total 도 동일하게 분기
  - `useEffect` 로 product 비어있을 때 cantidad 0 자동 리셋

## Commits

| # | Commit (sub-repo) | Scope | Type |
|---|-------------------|-------|------|
| 1 | `c777561` (api-ventago) | backend stores.use_variants + /me | feat |
| 2 | `1087dde` (ventago-app) | types.ts + ModalStore toggle | feat |
| 3 | `89184d0` (ventago-app) | ProductsView cantidad 단순 모드 | feat |

## Verification

### 자동 검증 (실행됨)
- [x] `cd api-ventago && npx tsc --noEmit` → **통과** (에러 없음)
- [x] `cd ventago-app && npx eslint src/views/products/list/ProductsView.tsx` → **통과** (0 errors, 0 warnings)
- [x] `cd ventago-app && npx eslint src/context/types.ts src/views/admin/stores/list/components/ModalStore.tsx` → **ProductsView/types.ts 0 error**; ModalStore 는 pre-existing react-hooks/exhaustive-deps warning 1건 (본 task 이전부터 존재, 파일 다른 부분)
- [x] `cd ventago-app && npx tsc --noEmit` → 변경 파일에서 에러 0건 (pre-existing `@fake-db/mock.ts` axios 타입 충돌은 out-of-scope)

### 수동 검증 (운영 적용 시 체크리스트 — 미실행)
- [ ] 마이그레이션 적용:
  ```bash
  docker exec -i dbpostgres psql -U coolsistema -d ventago -f - < api-ventago/migrations/add-use-variants-to-stores.sql
  ```
  기대: `ok=t` 반환, 기존 모든 stores row 의 use_variants=true
- [ ] 백엔드 재시작 후 `curl -s -H "Authorization: Bearer $TOKEN" http://localhost:5002/api/auth/me | jq .useVariants` → `true`
- [ ] Admin → Tiendas 편집 모달에 "Usar variantes (color / talle)" 토글 표시
- [ ] 토글 OFF 저장 후 `SELECT id, use_variants FROM stores WHERE id=?;` → `false`
- [ ] 새로고침 후 /me → `useVariants: false`
- [ ] `/productos/nueva` 진입:
  - useVariants=true: 기존 VariantsStock + TB resizer + Stock chip (회귀 없음)
  - useVariants=false: SelectorBranch + ProductParentList + Cantidad TextField
- [ ] Cantidad=5 입력 → Guardar producto → DB 확인:
  ```sql
  SELECT p.id, p.name, p.is_parent, p.color_id, p.size_id, p.stock
  FROM products p WHERE p.store_id=? ORDER BY id DESC LIMIT 5;
  ```
  기대: parent 1건 (is_parent=true), child 1건 (color_id=Color Único.id, size_id=Talle Única.id, stock=5)
- [ ] Cantidad=0 → "La cantidad debe ser mayor a 0" toast

## Self-Check: PASSED

**Files verified:**
- FOUND: /Users/marcoskim/Trabajos_Programming/ACE_online_1.0/api-ventago/migrations/add-use-variants-to-stores.sql
- FOUND: api-ventago/src/app/store/store.model.ts
- FOUND: api-ventago/src/app/store/dto/update-store.dto.ts
- FOUND: api-ventago/src/app/store/store.controller.ts
- FOUND: api-ventago/src/app/auth/auth.service.ts
- FOUND: ventago-app/src/context/types.ts
- FOUND: ventago-app/src/views/admin/stores/list/components/ModalStore.tsx
- FOUND: ventago-app/src/views/products/list/ProductsView.tsx

**Commits verified (sub-repos):**
- FOUND: c777561 (api-ventago)
- FOUND: 1087dde (ventago-app)
- FOUND: 89184d0 (ventago-app)

## Known Stubs

없음 — 모든 기능이 실제 DB/엔드포인트/UI 에 연결됨. cantidad 는 사용자 입력을 실시간 반영, defaultColorId/defaultSizeId 는 실제 SWR colors/sizes 데이터에서 조회하여 기존 엔티티 id 를 사용.

## Follow-up / Pending

- **StoreProfile.tsx** 에서 useVariants 상태를 시각적으로 노출 (현재는 ModalStore 토글에서만 확인 가능)
- **단순 모드에서 재입고 수정 UX 고도화** — 현재는 신규 생성만 테스트함. `mode === 'edit'` (재입고 정정) 흐름은 기존 variants 기반 코드가 그대로 동작하므로 useVariants=false 매장에서도 동일한 variant 그리드가 표시될 수 있음 → 추후 별도 quick task 로 단순화 검토 필요
- **신규 매장 생성 경로 POST /store/new** — 현재 CreateStoreDto 에 useVariants 필드가 없어 신규 생성 시에는 DB DEFAULT TRUE 에 의존. 필요 시 CreateStoreDto 확장
- **useMemo dep warnings in AuthContext 관련 무관 파일** — deferred
