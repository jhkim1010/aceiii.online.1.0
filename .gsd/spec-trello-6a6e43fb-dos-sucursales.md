# SPEC: 같은 날 2개 지점에 입고 불가 (Trello bklfCOX3 / 6a6e43fb)

생성일: 2026-08-03

## 목표

같은 날 같은 상품을 두 번째 지점(sucursal)에 입고하려 하면 "No hay cambios para actualizar" 토스트가 뜨며
저장이 되지 않는 결함을 제거한다.

## 배경 및 컨텍스트

신고 원문: "no deja agregar en un mismo dia a 2 sucursales distintas, el sistema detecta que no hay cambios para hacer"

### 근본 원인 (코드 정독으로 확정)

재입고 화면의 **비교 기준선(originalStocks)이 지점 단위가 아니라 전 지점 합산**이다.

1. `ProductParentList.handleRowSelection` (L176) 이 `GET /products/:id/inventory-by-date` 를 **branchId 없이** 호출한다.
   이 엔드포인트는 `ProductBranch.findAll({ where: { productId } })` 로 **모든 지점의 당일 입고를 합산**한다
   (`productStock.service.ts:1336-1362`).
2. 그 합산값으로 `setOriginalStocks(...)` (L289) 와 `setMode(todayHasEntries ? 'edit' : 'add')` (L292) 이 정해진다.
   → 지점 A 에 오늘 입고가 있으면, 지점 B 작업이어도 무조건 `edit` 모드 + 지점 A 수량이 기준선이 된다.
3. 사용자가 SelectorBranch 로 지점 B 를 고르면 `ProductsView` 의 지점전환 effect(L517-596)가
   `inventory-by-date-branch` 로 **variants 그리드만** 다시 채운다. **originalStocks 와 mode 는 갱신하지 않는다.**
4. 결과: `handleEdit` (L1056-1069) 이 지점 B 의 입력값을 **지점 A 기준선**과 비교 →
   같은 수량이면 `oldStock === newStock` 으로 전부 skip → `diff.length === 0` →
   `toast.success('No hay cambios para actualizar')` (L1102). **신고 증상과 정확히 일치.**

### 2차 결함 (기준선을 고쳐도 남는 조용한 무저장)

`correctTodayStocks` (`productStock.service.ts:554-675`) 는 대상 ProductBranch 를 `findAll` 로만 찾고,
없으면 `if (!pbs || pbs.length === 0) continue;` 로 **조용히 건너뛴 뒤 성공 응답**을 낸다.
상품이 아직 지점 B 에 연결된 적 없으면(= 최초 입고) ProductBranch 행이 없으므로
"Cambios aplicados correctamente" 토스트만 뜨고 아무것도 저장되지 않는다.
같은 파일의 다른 경로들은 이미 `ProductBranch.findOrCreate` 를 쓴다(L88, L338, L1622, L1694 —
L1618 주석: "새로 추가된 지점(아직 ProductBranch 없음)도 처리하도록 findOrCreate").
즉 correct-today 만 예외적으로 누락된 것.

또한 대상 지점을 `pbs[0]` (정렬 없는 findAll 결과)로 고르므로 다지점 선택 시 **어느 지점이 정정될지 비결정적**이다.

## 기술 스택

- 프론트: Next.js 13 / React 18 / MUI 5 — ESLint 는 warning 도 빌드를 막음
- 백엔드: NestJS 11 / Sequelize (`underscored: true`)
- DB: PostgreSQL 18. 본 변경은 **DDL/마이그레이션 없음**

## 태스크 목록

- [x] TASK-1: `ProductParentList` 가 현재 선택 지점을 받아 `inventory-by-date-branch` 로 조회 — 파일: `ventago-app/src/views/products/list/components/ProductParentList.tsx`
- [x] TASK-2: `ProductsView` 에서 `branchId` 전달 + 지점전환 effect 가 `originalStocks`/`mode` 를 함께 재동기화 — 파일: `ventago-app/src/views/products/list/ProductsView.tsx`
- [x] TASK-3: `correctTodayStocks` 대상 지점 결정론화(branchIds[0]) + `findOrCreate` 로 조용한 무저장 제거 — 파일: `api-ventago/src/app/products/productStock.service.ts`
- [x] TASK-4: ESLint 검증
- [x] TASK-5: PostgreSQL pool 안전 점검

## 완료 기준

- 지점 A 에 당일 입고가 있어도, 지점 B 선택 시 기준선/모드가 **지점 B 기준**으로 잡힌다
- 지점 B 에 ProductBranch 가 없어도 입고가 실제로 저장된다 (조용한 성공 없음)
- ESLint 오류 0개
- 추가 DB 커넥션 없음 — 모든 백엔드 쓰기는 기존 트랜잭션(`tx`) 안에서 수행

## 금지사항 / 주의사항

- `stocks` 는 append-only 원장 — UPDATE/DELETE 금지, 보정은 반대부호 행으로만 (CLAUDE.md 쓰기 경로 규약)
- 트랜잭션 안에서 외부 I/O 금지
- 다지점 동시 정정 의미론은 **바꾸지 않는다** (절대값 newStock 을 여러 지점에 적용하면 재고가 중복 증가)
- 기존 uncommitted 변경 파일은 커밋에 포함하지 않는다
