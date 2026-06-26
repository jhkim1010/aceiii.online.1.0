# SPEC: Materia Prima 부모-자식(codigoMadre/Hijito) 구현

생성일: 2026-06-25
설계 근거: `.gsd/design-materia-prima-parent-child.md`, `.gsd/prototype-materia-prima.html`

## 목표

원자재를 제품과 동일한 부모-자식 구조로 관리. 부모 원단(codigoMadre) 선택 시
색상별 자식(codigoHijito) 재고를 1D 리스트로 표시. 마스터-디테일 레이아웃.

## 범위 (이번 세션)

- **Phase A 백엔드**: 스키마/모델/API — 로컬 dev DB 기준 구현·검증
- **Phase B 프론트**: InventarioView 마스터-디테일 + 색상 1D 리스트 + 부모생성/입고 모달
- **운영 적용 제외**: 운영 DDL/재배선 SQL 은 작성만, 적용은 사용자 확인 후 별도

## 배경 (확인된 사실)

- `mes_materials` 현재 컬럼: parent_id/is_parent/color_id **없음**. `color varchar` 존재.
- 로컬 dev 데이터: store 1=6건, store 6=2건 (모두 color 보유). ACE(9)는 운영 전용.
- `colors` 테이블 존재 (39행). 컬럼: name, hex, storeId.
- materials 는 `production.module.ts` 에 등록. CrudController/CrudService 상속.
- 마이그레이션은 `migrations/*.sql` 파일 형식. PG10(운영)/PG15(dev) 호환 필요.
- 제품 부모-자식: Product self-ref (parentId, BelongsTo as 'parent', HasMany variants).
- `POST /mes/materials/bulk` 이미 구현됨 (이번에 부모생성 포함하도록 확장).

## 기술 스택
- NestJS 11 / Sequelize (pool 자동관리) / PostgreSQL
- Next.js 13 + MUI 5
- ESLint: warning=빌드차단

## 태스크 목록

### Phase A — 백엔드
- [ ] TASK-A1: 마이그레이션 SQL `migrations/wave14-materials-parent-child.sql`
      — mes_materials 에 parent_id(FK self), is_parent(bool default false), color_id(FK colors) 추가.
      color varchar 는 유지(점진 이전). PG10 호환 문법.
- [ ] TASK-A2: dev DB 에 마이그레이션 적용 (로컬만)
- [ ] TASK-A3: Material 모델 — parentId/parent(BelongsTo)/variants(HasMany)/isParent/colorId/color(BelongsTo) 추가
- [ ] TASK-A4: MaterialsService — getParents(storeId), getParentWithColors(parentId, storeId),
      createParentWithVariants(parent, items, storeId) (트랜잭션). 기존 createBulk 와 통합.
- [ ] TASK-A5: MaterialsController — GET parents, GET :id/colors, POST bulk 확장 (부모 생성 분기)
- [ ] TASK-A6: 백엔드 타입체크 통과

### Phase B — 프론트
- [ ] TASK-B1: InventarioView 마스터-디테일 레이아웃 (좌 부모 List / 우 디테일)
- [ ] TASK-B2: 색상별 1D 재고 리스트 컴포넌트 (스와치/현재고+단위/상태배지/빠른입고)
      — 기존 stockStatus/stockColor 재사용. 음수 표기하되 차단 없음.
- [ ] TASK-B3: 부모 생성 모달 — 색상 행 리스트 승격 + 코드 미리보기 (기존 colorRows UI 확장)
- [ ] TASK-B4: Reponer stock 모달 — 헤더 메타(공급자/단가/결제/날짜) + 색상별 수량
- [ ] TASK-B5: 빈/로딩 상태 (Skeleton), 좁은 폭 대응
- [ ] TASK-B6: ESLint 검증 통과

### Phase C — 운영 (작성만, 적용은 사용자 확인)
- [ ] TASK-C1: 운영 DDL SQL + 기존 데이터 재배선 SQL 초안 (Agrupar 로직)
- [ ] TASK-C2: 사용자에게 SQL + 영향 row 수 제시

## 완료 기준
- dev: 부모 선택 → 색상별 재고 1D 리스트 표시
- 부모 생성 시 부모1 + 자식N 단일 트랜잭션, 코드 자동
- 음수 재고 표기하되 거래 차단 없음
- ESLint 0, 백엔드 타입체크 0
- pool 누수 0 (Sequelize transaction)
- 마지막 error 로그 신규 에러 없음

## 금지/주의
- 운영 DB 직접 변경 금지 (사용자 확인 전)
- color varchar 즉시 DROP 금지 (점진 이전)
- BOM(bom_items)은 자식 Material 참조 — 부모 참조로 바꾸지 말 것
- 편집(update) 단건 흐름 유지
- raw pool.connect 금지 — Sequelize transaction 만
- pool 설정(min10/max80) 변경 금지
