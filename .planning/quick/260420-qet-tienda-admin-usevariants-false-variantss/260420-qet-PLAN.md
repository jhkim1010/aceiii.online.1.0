---
phase: quick-260420
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - api-ventago/migrations/add-use-variants-to-stores.sql
  - api-ventago/src/app/store/store.model.ts
  - api-ventago/src/app/store/dto/update-store.dto.ts
  - api-ventago/src/app/store/store.service.ts
  - api-ventago/src/app/auth/auth.service.ts
  - ventago-app/src/context/types.ts
  - ventago-app/src/context/AuthContext.tsx
  - ventago-app/src/views/admin/stores/list/components/ModalStore.tsx
  - ventago-app/src/views/products/list/ProductsView.tsx
autonomous: true
requirements:
  - QUICK-UV-01
  - QUICK-UV-02
  - QUICK-UV-03

must_haves:
  truths:
    - "stores 테이블에 use_variants 컬럼이 존재하고 기본값은 TRUE (기존 매장 호환)"
    - "Admin이 tienda 편집 모달에서 'Variantes (color/talle) 사용' 토글을 껐다 켰다 할 수 있다"
    - "/me 응답에 useVariants 가 포함되어 프론트 useAuth().user.useVariants 로 접근된다"
    - "useVariants=false 매장에서 ProductsView 진입 시 VariantsStock 과 상하 resizer 가 렌더되지 않는다"
    - "useVariants=false 매장에서 우측 패널은 SelectorBranch + ProductParentList 만 남고 ProductParentList 가 남는 공간을 채운다"
    - "useVariants=false 매장의 Action Bar 는 수량 입력 TextField(type=number)를 노출하며, 현재 cantidad 값을 실시간으로 상태에 반영한다"
    - "useVariants=false 매장에서 '신규 상품 저장' 버튼 클릭 시 cantidad 값으로 단일 variant ({sizeId: 기본 Talle Única id, colorId: 기본 Color Único id, stock: cantidad}) 가 POST /products/variants/batch 로 전송된다"
    - "useVariants=true 매장의 기존 동작(VariantsStock + 상하 resizer + 색×사이즈 grid)은 이 변경으로 회귀하지 않는다"
  artifacts:
    - path: "api-ventago/migrations/add-use-variants-to-stores.sql"
      provides: "stores.use_variants BOOLEAN NOT NULL DEFAULT TRUE 컬럼 추가 마이그레이션"
      contains: "ALTER TABLE stores"
    - path: "api-ventago/src/app/store/store.model.ts"
      provides: "Store 모델에 useVariants 필드 선언"
      contains: "declare useVariants: boolean"
    - path: "api-ventago/src/app/store/dto/update-store.dto.ts"
      provides: "UpdateStoreDto 가 useVariants(boolean) 를 허용"
      contains: "useVariants"
    - path: "api-ventago/src/app/auth/auth.service.ts"
      provides: "/me 응답에 useVariants 포함"
      contains: "useVariants"
    - path: "ventago-app/src/context/types.ts"
      provides: "UserDataType.useVariants?: boolean 선언"
      contains: "useVariants"
    - path: "ventago-app/src/context/AuthContext.tsx"
      provides: "로그인/세션 복원 시 useVariants 필드를 user 에 저장"
      contains: "useVariants"
    - path: "ventago-app/src/views/admin/stores/list/components/ModalStore.tsx"
      provides: "Tienda 편집 모달에 useVariants 토글 UI + formData 전송"
      contains: "useVariants"
    - path: "ventago-app/src/views/products/list/ProductsView.tsx"
      provides: "useVariants=false 분기: VariantsStock 숨김 + cantidad 입력 + handleSubmit 단일 variant 생성"
      contains: "useVariants"
  key_links:
    - from: "ventago-app/src/views/products/list/ProductsView.tsx"
      to: "useAuth().user.useVariants"
      via: "const useVariants = user?.useVariants ?? true"
      pattern: "user\\?.useVariants"
    - from: "ventago-app/src/views/products/list/ProductsView.tsx"
      to: "POST /products/variants/batch"
      via: "apiConnector.post('/products/variants/batch', { parentId, sizeIds, colorIds, quantities, variants, baseSku, branchIds })"
      pattern: "products/variants/batch"
    - from: "ventago-app/src/views/admin/stores/list/components/ModalStore.tsx"
      to: "PUT /store/:id"
      via: "apiConnector.putFile(`/store/${store.id}`, formData) with useVariants field"
      pattern: "formData.append\\('useVariants'"
    - from: "api-ventago/src/app/auth/auth.service.ts"
      to: "Store.findOne -> store.useVariants -> /me response"
      via: "store?.useVariants ?? true 를 응답에 포함"
      pattern: "useVariants"
---

<objective>
Tienda admin 에서 `useVariants=false` 로 설정한 매장은 신상품 등록 화면(`ProductsView`)을
색×사이즈 grid 없이 단일 수량(cantidad) 입력만으로 상품 1개 + variant 1건을 생성할 수
있도록 전체 스택을 관통해서 연결한다.

Purpose: 의류처럼 다(多) variant 가 필요한 매장과 단일 상품만 취급하는 매장을 한 코드베이스에서
지원한다. 기본값 TRUE 로 설정해 기존 매장 동작은 건드리지 않는다.

Output:
- DB 마이그레이션(`stores.use_variants`)
- 백엔드: Store 모델 + UpdateStoreDto + /me 응답 확장
- 프론트: 타입 + AuthContext + Tienda 편집 모달 토글
- 프론트: ProductsView 분기 렌더링 + cantidad 입력 + 단일 variant submit
</objective>

<execution_context>
@.claude/get-shit-done/workflows/execute-plan.md
@.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@CLAUDE.md

# 중심 변경 대상
@ventago-app/src/views/products/list/ProductsView.tsx
@ventago-app/src/views/products/hook/ProductContext.tsx
@ventago-app/src/views/products/list/components/VariantsStock.tsx
@ventago-app/src/views/products/list/components/BasicDataCard.tsx
@ventago-app/src/views/products/list/components/ProductParentList.tsx
@ventago-app/src/views/products/list/components/SelectorBranch.tsx

# 백엔드 연결부
@api-ventago/src/app/store/store.model.ts
@api-ventago/src/app/store/dto/update-store.dto.ts
@api-ventago/src/app/store/store.service.ts
@api-ventago/src/app/auth/auth.service.ts
@api-ventago/src/app/store/storeTemplate.service.ts
@api-ventago/src/app/products/products.controller.ts
@api-ventago/src/app/products/productStock.service.ts

# 프론트 Auth & 관리 UI
@ventago-app/src/context/types.ts
@ventago-app/src/context/AuthContext.tsx
@ventago-app/src/hooks/useAuth.tsx
@ventago-app/src/views/admin/stores/list/components/ModalStore.tsx
@ventago-app/src/views/admin/stores/details/components/StoreProfile.tsx
@ventago-app/src/services/api.service.ts

<interfaces>
<!-- 실제 코드에서 추출한 현재 계약. 실행자는 이 값들을 재탐색하지 말고 그대로 사용한다. -->

## 1) ProductContext (ventago-app/src/views/products/hook/ProductContext.tsx)
```typescript
// 관련 setter 만 발췌
product, setProduct,
variants, setVariants,              // Array<{ colorId, stocks: Array<{ sizeId, stock }>, _isExisting?, _colorName? }>
prices, setPrices,                  // Array<{ priceTypeId, amount, currency }>
selectedDate, setSelectedDate,      // 'yyyy-MM-dd'
mode,                               // 'add' | 'edit'
loading, setLoading,
resetAll,                           // () => void
```

## 2) /me 응답 구조 (api-ventago/src/app/auth/auth.service.ts ~L502 / L533)
```typescript
// 두 경로(super/일반) 모두 flat 필드 — `store` 객체로 래핑하지 않음
return {
  id, name, lastName, email, username, status,
  trialEndsAt, onboardingCompleted, uiMode, roles,
  storeId, branchId,
  storeName, aliasName, logoUrl,
  // ← 여기에 useVariants 추가
  structure, cashRegister, permissions, accessToken
};
```

## 3) UserDataType (ventago-app/src/context/types.ts ~L25)
```typescript
export type UserDataType = {
  id: number;
  storeId: number;
  storeName?: string | null;
  aliasName?: string | null;
  logoUrl?: string | null;
  // ← 여기에 useVariants 추가
  // store?: {...}  (현재 optional subobject, 여전히 존재)
};
```

## 4) POST /products/variants/batch (api-ventago/src/app/products/products.controller.ts:147)
```typescript
// 컨트롤러에 DTO 스키마가 없고 service 의 createVariantsBatch(dto) 로 바로 위임된다.
// createVariantsBatch 계약 (productStock.service.ts:23):
{
  parentId: number;
  sizeIds: number[];
  colorIds: number[];
  quantities: number[];
  variants?: Array<{ sizeId: number; colorId: number; stock?: number; prices?: Array<{priceTypeId, amount, currency?}> }>;
  baseSku?: string;
  branchIds: number[] | number;
  imageUrl?: string;
  price?: number;
}
// 주의: Products 테이블의 colorId / sizeId 는 NOT NULL 이므로 `null` 을 보낼 수 없다.
// 매장 생성 시 storeTemplate.service.ts 가 이미 'Color Único' / 'Talle Única' 기본 엔티티를
// 만들어 두었으므로 useVariants=false 경로에서는 이 기본 id 를 조회해 사용한다.
```

## 5) Store 모델 (api-ventago/src/app/store/store.model.ts)
- `@Table({ timestamps: true })` + Sequelize 전역 `underscored: true` → `useVariants` 는 DB `use_variants` 로 자동 매핑
- `declare useVariants: boolean` (기본 true)

## 6) UpdateStoreDto (api-ventago/src/app/store/dto/update-store.dto.ts)
- `PartialType(CreateStoreDto)` 확장 → `@IsOptional() @IsBoolean() useVariants?: boolean` 추가
- 단, `ModalStore` 는 `putFile` 로 FormData 전송하므로 값은 문자열 'true'/'false' 로 온다 → 서비스/컨트롤러에서 boolean 변환 필요 (`value === 'true'`).

## 7) ModalStore 의 현재 전송 패턴 (ventago-app/src/views/admin/stores/list/components/ModalStore.tsx ~L88)
```typescript
const formData = new FormData();
formData.append('name', data.name);
formData.append('aliasName', data.aliasName);
// ... 다른 필드
formData.append('useVariants', data.useVariants ? 'true' : 'false');  // ← 추가
if (isEdit) {
  await apiConnector.putFile(`/store/${store.id}`, formData);
}
```
</interfaces>
</context>

<tasks>

<task type="auto" tdd="false">
  <name>Task 1: Backend — stores.use_variants DB 컬럼 + Store 모델 + Update DTO/Service + /me 응답 확장</name>
  <files>
    api-ventago/migrations/add-use-variants-to-stores.sql,
    api-ventago/src/app/store/store.model.ts,
    api-ventago/src/app/store/dto/update-store.dto.ts,
    api-ventago/src/app/store/store.service.ts,
    api-ventago/src/app/auth/auth.service.ts
  </files>
  <action>
  1) **마이그레이션 SQL 추가** — `api-ventago/migrations/add-use-variants-to-stores.sql` 신규 생성.
     `add-is-active-to-stocks.sql` 패턴을 그대로 따른다 (주석 + 실행 방법 + ALTER + 검증 SELECT).
     SQL 본문:
     ```sql
     ALTER TABLE stores
       ADD COLUMN IF NOT EXISTS use_variants BOOLEAN NOT NULL DEFAULT TRUE;
     -- 검증
     SELECT 'stores.use_variants' AS col,
       EXISTS(SELECT 1 FROM information_schema.columns
              WHERE table_name='stores' AND column_name='use_variants') AS ok;
     ```
     Docker 운영에서 실행 방법을 주석으로 명시 (`docker exec -i dbpostgres psql ...`).

  2) **Store 모델 확장** — `store.model.ts` 에 `logoUrl` 필드 아래에 다음을 추가.
     Sequelize 전역 `underscored: true` 이므로 camelCase 선언이 DB `use_variants` 로 자동 매핑된다.
     ```ts
     // 단일 매장이 색·사이즈 variant 를 사용하는지 여부.
     // false 면 신상품 등록 UI 가 VariantsStock 없이 cantidad 하나만 받는다.
     @Column({ type: DataType.BOOLEAN, allowNull: false, defaultValue: true })
     declare useVariants: boolean;
     ```

  3) **UpdateStoreDto 에 필드 추가** — `dto/update-store.dto.ts` 에 `useVariants?: boolean` 을 `@IsOptional() @IsBoolean()` 로 선언. class-validator 에서 `IsBoolean` import.
     주의: FormData 로 오는 'true'/'false' 문자열 파싱을 위해 `@Transform(({ value }) => value === true || value === 'true')` 를 붙인다 (`class-transformer` import).

  4) **store.service.ts** — 기존 `update(id, dto)` 메서드에서 `dto.useVariants` 가 `undefined` 가 아닌 경우에만 필드를 저장하도록 처리 (`Partial` 패턴으로 이미 지원된다면 추가 작업 없음). CLAUDE.md 지침대로 기존 쿼리 구조는 유지하되, 필요한 부분만 수정.

  5) **auth.service.ts /me 응답 확장** — `storeName, aliasName, logoUrl` 을 세팅하는 블록(~L407-409) 근처에 `useVariants` 도 동일하게 꺼내 변수로 저장.
     ```ts
     let useVariants: boolean = true;
     // ... store 조회 직후:
     useVariants = store?.useVariants ?? true;
     ```
     그리고 두 개의 `return { ... }` (L502 superadmin 경로, L533 일반 경로) 모두에 `useVariants` 를 추가.
     CLAUDE.md ESLint 규칙 준수: `return` 위 빈 줄, 주석 위 빈 줄.

  6) **주석 한국어 + async/await + 에러 핸들링 유지** — CLAUDE.md 기본 원칙 적용.
  </action>
  <verify>
    <automated>cd api-ventago && npx tsc --noEmit</automated>
    수동 확인:
    - `docker exec -i dbpostgres psql -U coolsistema -d ventago -f - < api-ventago/migrations/add-use-variants-to-stores.sql` 실행 후 검증 SELECT 가 `ok=t` 반환
    - `curl -s -H "Authorization: Bearer $TOKEN" http://localhost:5002/api/auth/me | jq .useVariants` → `true`
    - PUT /store/:id 로 `useVariants=false` 전송 후 다시 /me 조회 → `false`
  </verify>
  <done>
    - `stores.use_variants` 컬럼이 DB 에 존재하고 모든 기존 row 는 `true`
    - Store 모델이 TypeScript 빌드를 통과
    - /me 응답 JSON 에 `useVariants` 필드가 포함됨 (boolean)
    - ESLint/tsc 에러 없음
  </done>
</task>

<task type="auto" tdd="false">
  <name>Task 2: Frontend Auth + Tienda 편집 모달 토글</name>
  <files>
    ventago-app/src/context/types.ts,
    ventago-app/src/context/AuthContext.tsx,
    ventago-app/src/views/admin/stores/list/components/ModalStore.tsx
  </files>
  <action>
  1) **UserDataType 확장** — `context/types.ts` L25 근처 `UserDataType` 에 `logoUrl?` 아래로 다음 한 줄 추가:
     ```ts
     useVariants?: boolean;  // 매장이 색·사이즈 variant 를 사용하는지 (false 면 신상품 UI 단순화)
     ```

  2) **AuthContext 에서 useVariants 전달** — `AuthContext.tsx` 의 `/me` 응답을 `setUser` 로 매핑하는 부분을 찾아 (현재 `storeName`, `aliasName`, `logoUrl` 을 user 에 복사하는 곳) `useVariants: meResult.useVariants ?? true` 를 동일한 방식으로 추가.
     - 로그인 응답 처리 블록 + 세션 복원 블록 모두 동일하게 반영.
     - 기본값 `true` 로 fallback 해서 서버가 필드를 누락해도 기존 UI 가 유지되게 한다.

  3) **ModalStore 에 Switch 토글 추가** — `ModalStore.tsx`:
     (a) MUI import 에 `Switch`, `FormControlLabel` 추가 (이미 있으면 스킵).
     (b) `react-hook-form` 의 `useForm` 에 `useVariants` 기본값 세팅:
         ```ts
         defaultValues: {
           // 기존 필드들...
           useVariants: store?.useVariants ?? true,
         }
         ```
         `watch('useVariants')` 또는 `Controller` 로 제어.
     (c) `timezone` 입력 바로 위/아래에 새 섹션 추가:
         ```tsx
         <Grid item xs={12}>
           <FormControlLabel
             control={
               <Controller
                 name="useVariants"
                 control={control}
                 render={({ field }) => (
                   <Switch
                     checked={!!field.value}
                     onChange={(e) => field.onChange(e.target.checked)}
                   />
                 )}
               />
             }
             label="Usar variantes (color / talle)"
           />
           <Typography variant="caption" sx={{ display: 'block', color: '#9E9E9E' }}>
             Si está desactivado, la creación de productos usará solo cantidad total.
           </Typography>
         </Grid>
         ```
     (d) `onSubmit` 의 `formData.append` 블록에 추가:
         ```ts
         formData.append('useVariants', data.useVariants ? 'true' : 'false');
         ```

  4) **ESLint 규칙 준수**:
     - `return` 문 위 빈 줄 (newline-before-return)
     - 주석(`//`) 위 빈 줄 (lines-around-comment)
     - 모든 import 는 실제로 사용 (no-unused-vars)
     - 사용하지 않는 `FormControlLabel`, `Switch`, `Controller` import 는 넣지 말 것
  </action>
  <verify>
    <automated>cd ventago-app && npx eslint src/context/types.ts src/context/AuthContext.tsx src/views/admin/stores/list/components/ModalStore.tsx --max-warnings 0</automated>
    <automated>cd ventago-app && npx tsc --noEmit</automated>
    수동 확인:
    - Admin 로그인 → /admin/tiendas/[id] → "Editar" → 모달에 "Usar variantes (color / talle)" 토글 표시
    - 토글 OFF → 저장 → DB stores.use_variants=false 확인
    - 새로고침 후 /me 응답 → `useVariants:false` 반영
  </verify>
  <done>
    - `UserDataType.useVariants` 필드 존재
    - `useAuth().user?.useVariants` 가 /me 응답값을 반영
    - Tienda 편집 모달에서 토글 변경이 PUT /store/:id 로 전송되고 서버에 반영
    - ESLint/tsc 에러 없음
  </done>
</task>

<task type="auto" tdd="false">
  <name>Task 3: ProductsView 분기 렌더링 + cantidad 입력 + 단일 variant 생성 submit</name>
  <files>
    ventago-app/src/views/products/list/ProductsView.tsx
  </files>
  <action>
  1) **useVariants 상수 도입** — 컴포넌트 최상단 hook 영역 (L38 `const { user } = useAuth();` 바로 아래) 에 추가:
     ```ts
     // 매장이 variant 를 사용하지 않으면 단순 cantidad 입력 모드로 전환
     const useVariants = user?.useVariants ?? true;

     // 단순 모드 전용: 등록할 총 수량
     const [cantidad, setCantidad] = useState<number>(0);
     ```

  2) **resetAll 후 cantidad 초기화** — `resetAll()` 을 호출하는 모든 지점(`doSubmit`, `doEdit`, 다이얼로그 닫기 등) 직후에 `setCantidad(0)` 추가. 또는 `useEffect` 로 `mode` 변경 시 0 으로 리셋.

  3) **우측 패널 분기 렌더링** — 현재 우측 패널(`rightPanelRef` 담긴 Box, ~L856 부터 `ProductParentList` 닫힐 때까지):
     - `useVariants=true` 이면 기존 그대로 유지 (SelectorBranch → editingMadre infoBar → VariantsStock → TB Resizer → ProductParentList).
     - `useVariants=false` 이면 내부 JSX 를 다음으로 교체:
       ```tsx
       <Box ref={rightPanelRef} sx={{ flex: 1, minWidth: MIN_RIGHT, overflow: 'hidden',
            display: 'flex', flexDirection: 'column', gap: 1.5, p: 2 }}>
         <Box sx={{ flexShrink: 0 }}>
           <SelectorBranch value={selectedBranches} onChange={setSelectedBranches} />
         </Box>
         <Box sx={{ flex: 1, minHeight: 0, overflow: 'auto',
              '&::-webkit-scrollbar': { width: 6 },
              '&::-webkit-scrollbar-thumb': { bgcolor: 'rgba(0,0,0,.15)', borderRadius: 3 } }}>
           <ProductParentList refresh={refreshProducts} />
         </Box>
       </Box>
       ```
     - 구현은 `{useVariants ? (<>기존 블록</>) : (<>단순 블록</>)}` 삼항. 들여쓰기 유지.

  4) **Action Bar cantidad 입력** — 현재 "Stock a ingresar: … u" chip(~L767-778) 을 분기:
     - `useVariants=true` → 기존 chip 유지 (`variants.reduce(...)` 계산).
     - `useVariants=false` → chip 자리에 TextField 삽입:
       ```tsx
       <Box sx={{ display: 'flex', alignItems: 'center', gap: 1,
            px: 1.5, py: 0.25, borderRadius: '20px', background: '#F5F5F5' }}>
         <Typography sx={{ fontSize: 12, color: '#616161' }}>Cantidad:</Typography>
         <TextField
           size="small"
           type="number"
           value={cantidad}
           onChange={(e) => setCantidad(Math.max(0, Number(e.target.value) || 0))}
           inputProps={{ min: 0, style: { width: 70, padding: '4px 8px', fontSize: 13 } }}
           variant="outlined"
         />
         <Typography sx={{ fontSize: 12, color: '#616161' }}>u</Typography>
       </Box>
       ```
     - MUI `TextField` import (이미 `@mui/material` 에서 가져오면 된다).

  5) **handleSubmit 분기** — 현재 `handleSubmit`(L323) 내부 로직 수정:
     ```ts
     if (editingMadre) return handleMadreSave();
     if (mode === 'edit') return handleEdit(e);
     if (!user?.storeId) { toast.error(...); return; }

     // ── 단순 cantidad 모드 (useVariants=false) ──
     if (!useVariants) {
       if (!cantidad || cantidad <= 0) {
         toast.error('La cantidad debe ser mayor a 0');

         return;
       }
       setOpenConfirm(true);
       setPendingSubmit(() => doSubmit);

       return;
     }

     // ── 기존 variants 기반 검증 (그대로) ──
     const totalStock = variants.reduce(...);
     if (totalStock === 0) { ... }
     setOpenConfirm(true);
     setPendingSubmit(() => doSubmit);
     ```

  6) **doSubmit 분기** — `validVariants` 빌드 루프(~L398-433) 를 분기:
     - `useVariants=true` → 기존 루프 유지.
     - `useVariants=false` → 기본 'Color Único' / 'Talle Única' id 를 조회해 단일 variant 생성. 두 가지 접근 중 **B 선택**:

       - **A (거부)**: ProductContext 의 `colors`, `sizes` state 에서 name === 'Color Único' / 'Talle Única' 를 찾아 id 확보.
       - **B (선택)**: ProductsView 진입 시 한 번만 `apiConnector.get('/colors/by-store')` 와 `/sizes/by-store` 데이터(이미 `useColorsByStore`, `useSizesByStore` SWR 로 로드 중)에서 "Color Único" / "Talle Única" 를 찾아 `defaultColorId`, `defaultSizeId` 를 `useMemo` 로 도출. 매장 최초 생성 시 storeTemplate.service.ts 가 이미 만들어둔 기본값이므로 항상 존재한다.

       구현:
       ```ts
       const defaultColorId = useMemo(
         () => (colors || []).find((c: any) => c.name === 'Color Único')?.id ?? null,
         [colors]
       );
       const defaultSizeId = useMemo(
         () => (sizes || []).find((s: any) => s.name === 'Talle Única')?.id ?? null,
         [sizes]
       );
       ```

       `doSubmit` 내부 분기(신규 상품 생성 경로, `} else {` 블록):
       ```ts
       let validVariants: any[];
       let colorIds: number[];
       let sizeIds: number[];
       let quantities: number[];
       let totalStock: number;

       if (!useVariants) {
         if (!defaultColorId || !defaultSizeId) {
           toast.error('Faltan entidades base (Color Único / Talle Única) en la tienda');
           setLoading(false); setOpenConfirm(false);

           return;
         }
         validVariants = [{
           colorId: defaultColorId,
           sizeId: defaultSizeId,
           stock: cantidad,
           prices,
         }];
         colorIds = [defaultColorId];
         sizeIds = [defaultSizeId];
         quantities = [cantidad];
         totalStock = cantidad;
       } else {
         // 기존 루프 결과를 그대로 사용
         // (기존 코드를 이 else 안으로 옮긴다)
       }
       ```

       그 뒤의 `POST /products` + `POST /products/variants/batch` 호출은 공통 — `validVariants`, `sizeIds`, `colorIds`, `quantities`, `totalStock` 변수를 그대로 사용한다. `price` 와 `prices` 는 기존 로직 그대로.

       - existingVariants(parentId 있는 재입고 분기)에서도 `useVariants=false` 는 단일 variant 로 처리. 단, 이 흐름(`if (id) { ... }`)은 기존 상품 재입고이므로 단순화해도 되고 — 안전하게는 `useVariants=false` 에서는 `id` 분기를 허용하지 않거나(새 상품 전용) 동일한 단일 variant 조합으로 처리.
         **구현 정책**: `useVariants=false` 모드에서는 `id` 가 있으면 `existingVariants` 에서 colorId/sizeId 가 `defaultColorId/defaultSizeId` 인 variant 를 찾아 stock 증분. 없으면 신규 variant 추가 (existing batch 와 동일 경로).

  7) **상하 resizer / variantsH 관련 코드 보호** — `useVariants=false` 분기에서는 `rightPanelRef`, `variantsH`, `onTBResizerMouseDown` 을 사용하지 않는다. 기존 `useEffect` 의 mousemove 핸들러가 `ds.type === 'tb'` 일 때 `rightPanelRef.current` 가 null 이 될 수 있으므로 이미 guard 처리되어 있다 — 추가 수정 불필요.

  8) **ESLint 규칙 엄격 준수**:
     - `return` 앞 빈 줄 (newline-before-return)
     - 주석 위 빈 줄 (lines-around-comment)
     - 새로 추가한 `useState`, `useMemo`, `TextField` import 모두 실사용
     - 사용 안 하는 변수 즉시 삭제
     - CLAUDE.md 의 `apiConnector.remove()` 규칙은 본 task 에서 DELETE 호출 없으므로 무관
     - 신규 상태/핸들러에 한국어 주석으로 목적 설명
  </action>
  <verify>
    <automated>cd ventago-app && npx eslint src/views/products/list/ProductsView.tsx --max-warnings 0</automated>
    <automated>cd ventago-app && npx tsc --noEmit</automated>
    수동 확인 (useVariants=true 매장):
    - `/productos/nueva` → 기존과 동일: VariantsStock grid + TB resizer + Action Bar chip ("Stock a ingresar: N u")
    - 신상품 등록 정상 동작 (회귀 없음)

    수동 확인 (useVariants=false 매장):
    - `/productos/nueva` → 우측 패널: SelectorBranch + ProductParentList 만, VariantsStock/TB resizer 없음
    - Action Bar 에 "Cantidad: [입력] u" TextField 표시
    - Cantidad=5 입력 → "Guardar producto" → 확인 다이얼로그 → OK →
      DB products 테이블에 parent(isParent=true) 1개, child variant 1개(sizeId=Talle Única.id, colorId=Color Único.id, stock=5)
    - Cantidad=0 → "La cantidad debe ser mayor a 0" toast
  </verify>
  <done>
    - useVariants=true 기존 경로 회귀 없음 (동일 레이아웃/동일 submit payload)
    - useVariants=false 매장에서 VariantsStock + TB resizer 미렌더
    - useVariants=false 에서 cantidad 입력 → 단일 variant 생성 성공
    - ESLint 0 warnings, tsc pass
  </done>
</task>

</tasks>

<verification>
전체 검증 (로컬):
1. 마이그레이션 적용: `docker exec -i dbpostgres psql ... -f add-use-variants-to-stores.sql`
2. 백엔드 재시작 후 `curl /api/auth/me` → `useVariants: true` (기존 매장 기본값)
3. 테스트 매장 생성 후 Admin UI 토글 OFF → PUT /store/:id → 재로그인 → /me `useVariants: false`
4. useVariants=false 매장 로그인 → /productos/nueva → 우측 단순 레이아웃 + cantidad 입력
5. 상품 생성 → DB 확인:
   - `SELECT id, name, is_parent, color_id, size_id, stock FROM products WHERE store_id=? ORDER BY id DESC LIMIT 5;`
   - parent 1건 (is_parent=true), child 1건 (color_id=<Color Único>, size_id=<Talle Única>, stock=cantidad)
6. useVariants=true 매장 (기본) 회귀 테스트: 기존 variant grid 등록 플로우 정상
</verification>

<success_criteria>
- [ ] 마이그레이션 실행 후 stores 테이블 use_variants 컬럼 존재, 기존 모든 row = true
- [ ] api-ventago TypeScript 빌드 에러 없음
- [ ] ventago-app ESLint/TypeScript 에러 없음
- [ ] Admin tienda 편집 모달에서 useVariants 토글 변경 가능
- [ ] /me 응답에 useVariants 필드 포함
- [ ] useVariants=false 매장: ProductsView 우측 단순 레이아웃 + cantidad 입력
- [ ] useVariants=false 에서 상품 생성 시 POST /products/variants/batch 가 단일 variant 로 호출되고 DB 에 저장됨
- [ ] useVariants=true 매장 (기본): 기존 variant grid 등록이 완전히 동일하게 동작 (회귀 없음)
</success_criteria>

<output>
완료 후 `.planning/quick/260420-qet-tienda-admin-usevariants-false-variantss/260420-qet-SUMMARY.md` 작성.
포함 사항:
- 실제 변경 파일 목록 + 라인 수
- DB 마이그레이션 적용 로그
- 수동 검증 결과 (useVariants=true / false 각 1건 상품 생성 스크린샷 또는 SQL 결과)
- 남은 이슈 / 후속 작업 (예: StoreProfile 에서도 useVariants 상태 표시, 단순 모드에서의 "재입고" 편집 UX 고도화 등)
</output>
