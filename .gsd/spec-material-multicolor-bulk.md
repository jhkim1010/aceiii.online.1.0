# SPEC: Materia Prima 색상별 다건 일괄 등록

생성일: 2026-06-25

## 목표

원단(자재) 하나를 여러 색상으로 한 번에 등록하는 기능 구현. 신규 등록 모드에서
색상 행을 N개 입력하면, 단일 트랜잭션으로 색상별 자재 N건을 한 번에 생성한다.
(이전에 InventarioView 에 정의만 되고 미연결되어 ESLint 오류를 내던 죽은 코드를
실제 동작하는 기능으로 완성)

## 배경 및 컨텍스트

### 현재 구조
- 프론트: `ventago-app/src/views/materia-prima/InventarioView.tsx`
  - `handleSave` 는 단건만 처리 — `formData.color` 1개로 `POST /mes/materials` 1회 호출
  - 다이얼로그 line ~881 에 색상 단건 `<Select>` 존재
  - 헬퍼 보유: `applyColorSuffix(name,color)`, `generateNextCode(prefix,materials)`,
    `codePrefixFromCategory`, `stripColorSuffix` — 재활용
  - `colors` (시스템 색상 마스터, hex 포함) 이미 로드됨
- 백엔드: `api-ventago/src/app/production/materials/`
  - `MaterialsController extends CrudController<Material>` — 제네릭 CRUD (커스텀 라우트 없음)
  - `MaterialsService extends CrudService<Material>` — `create(data)` = `model.create(data)`
  - `CrudController.create` 가 `body.storeId` 없으면 `user.storeId` 자동 주입
  - 모델 `Material` (테이블 `mes_materials`): unique index `(code, store_id)`
    → 색상별 code 가 서로 달라야 함 (suffix 로 해결)

### 제약사항
- Sequelize ORM 사용 — pool 은 Sequelize 가 자동 관리 (수동 connect/release 없음).
  트랜잭션은 `sequelize.transaction()` 콜백형 사용 → 자동 commit/rollback + connection 자동 반환.
- ESLint: warning 도 빌드 차단. `newline-before-return`, `lines-around-comment`,
  `no-unused-vars` 준수.
- 주석 한국어, 함수/변수명 영어, 모든 async 에 에러 핸들링.

## 기술 스택
- 언어/프레임워크: NestJS 11 (백) / Next.js 13 + MUI 5 (프론트)
- DB: PostgreSQL (Sequelize ORM, pool 자동 관리)
- ESLint 설정: ventago-app `.eslintrc` (next lint)

## 코드 규칙: code 생성
- 기본 코드 + 색상 suffix 방식
- `colorToCodeToken(color)`: NFD 정규화 → 악센트 제거 → 영숫자만 → 대문자 → 최대 6자
  - 예: 'Rojo' → 'ROJO', 'Económico' → 'ECONOM'
- 최종 code = `${baseCode}-${token}` (예: `TEL-001-ROJO`)
- 색상이 비어있는 행은 token 없이 baseCode 그대로 (단, 다건 모드에서 최소 1색 권장)

## 태스크 목록

- [ ] TASK-1: 백엔드 — `MaterialsService.createBulk(items, storeId)` 추가.
      `sequelize.transaction()` 으로 N건 `Material.create({...,storeId},{transaction})`.
      중복 code 충돌 시 명확한 에러 메시지. — 파일: materials.service.ts
- [ ] TASK-2: 백엔드 — `MaterialsController` 에 `@Post('bulk')` 라우트 추가.
      `@GetUser` 로 storeId 주입, superadmin 은 body.storeId 허용. — 파일: materials.controller.ts
      (CrudController 상속 유지 + 커스텀 메서드 추가)
- [ ] TASK-3: 백엔드 — Sequelize 인스턴스 주입 확인.
      service 에 `@InjectConnection() private sequelize: Sequelize` 추가. — materials.service.ts
- [ ] TASK-4: 프론트 — `colorToCodeToken`, `ColorRow`, `EMPTY_COLOR_ROW` 재도입.
      `colorRows` state + add/remove/change 핸들러. — InventarioView.tsx
- [ ] TASK-5: 프론트 — 다이얼로그 신규 모드에서 색상 단건 Select 를 색상 행 리스트 UI 로 교체.
      (편집 모드는 기존 단건 Select 유지) — InventarioView.tsx
- [ ] TASK-6: 프론트 — `handleSave` 분기: 신규+다건이면 `POST /mes/materials/bulk`,
      그 외 기존 단건 흐름. baseCode + colorToCodeToken 으로 색상별 code/name 생성. — InventarioView.tsx
- [ ] TASK-7: ESLint 검증 (`npx next lint`) 오류 0개
- [ ] TASK-8: 마지막 로그 재확인 (error-2026-06-25.log 신규 에러 없음)

## 완료 기준
- ESLint 오류 0개
- 신규 모드에서 색상 3개 입력 → 3건 자재가 색상별 code (`-ROJO` 등) 로 1회 요청에 생성
- 편집 모드 동작 변화 없음 (회귀 없음)
- 트랜잭션: 한 건이라도 실패하면 전체 rollback (부분 생성 방지)
- Sequelize transaction connection 자동 반환 (pool 누수 없음)

## 금지사항 / 주의사항
- 편집(update) 흐름 변경 금지 — 단건 유지
- 운영 DB 직접 변경 금지 (스키마 변경 없음 — 기존 컬럼만 사용)
- `apiConnector.remove()` 사용 (`.delete()` 아님)
- pool 설정(min=10/max=80) 변경 금지
- raw `pool.connect()` 직접 사용 금지 — Sequelize transaction 만 사용
