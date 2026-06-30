# SPEC: Materia Prima 색상(자식) 추가/편집/삭제 UI

생성일: 2026-06-29

## 목표
등록된 material(부모, codigoMadre)의 디테일 패널에서 색상 자식(codigoHijito)을
추가·이름/최소재고 편집·삭제할 수 있는 UI 와 백엔드 엔드포인트를 만든다.

## 배경 및 컨텍스트
- 현재 색상은 "Nuevo material" 생성 시에만 입력 가능. 이후엔 입고(Reponer)만 됨.
- 디테일 패널: `ventago-app/src/views/materia-prima/TelasMadreView.tsx`
  의 `DetailPanel`(약 405~618줄). 색상 행을 grid 로 렌더. 편집/삭제 버튼 없음.
- 부모/자식 모델: `mes_materials` (self-ref parentId, isParent). code UNIQUE(code, store_id).
- 자식 생성 로직 참고: service `createParentWithVariants` (parentId 연결 + code= base-TOKEN).
- 자식 참조 테이블(삭제 안전성): mes_bom_items, mes_material_movements,
  talleres_envio_materiales, mes_materials(parent_id). → 참조 있으면 삭제 차단.

## 기술 스택
- 백엔드: NestJS + Sequelize. DB PostgreSQL. (트랜잭션 콜백형 → pool 자동 반환)
- 프론트: Next.js + MUI. apiConnector. SWR 색상/카테고리 훅.
- ESLint: newline-before-return, lines-around-comment 빌드 차단.

## 태스크 목록
- [ ] TASK-1: (백엔드 service) addColorVariant(parentId, item, storeId)
      — 부모 검증 + code 중복 사전검사 + 자식 1건 생성. 파일: materials.service.ts
- [ ] TASK-2: (백엔드 service) deleteColorVariant(id, storeId)
      — 참조(movements/bom/envio) 검사 후 삭제. 참조 있으면 BadRequest. 파일: materials.service.ts
- [ ] TASK-3: (백엔드 service) updateColorVariant(id, patch, storeId)
      — color/colorName/minStock 만 수정(code/stock 직접변경 금지). 파일: materials.service.ts
- [ ] TASK-4: (백엔드 controller) POST :id/colors, PUT colors/:childId, DELETE colors/:childId
      파일: materials.controller.ts
- [ ] TASK-5: (프론트) DetailPanel 색상 행에 편집/삭제 IconButton + 헤더에 "Agregar color" 버튼
      파일: TelasMadreView.tsx
- [ ] TASK-6: (프론트) 색상 추가/편집 다이얼로그 (Color Autocomplete + minStock)
      파일: TelasMadreView.tsx
- [ ] TASK-7: ESLint 검증 (front + api)
- [ ] TASK-8: tsc 타입 검증 (front 변경분 + api)

## 완료 기준
- ESLint 오류 0개 (양쪽)
- 색상 추가 시 code 자동생성(base-TOKEN), 중복이면 친절한 메시지
- 삭제 시 재고이력/BOM/외주 참조 있으면 차단 + 안내, 없으면 삭제
- 편집은 이름(color)·최소재고만. 현재고/code 는 건드리지 않음
- 트랜잭션/쿼리에서 pool 누수 없음 (콜백형 transaction, pool.query)

## 금지사항 / 주의사항
- code 는 사용자가 직접 수정 못 함 (자동생성 유지). 색상 변경 시 code 재생성은 이번 범위 제외(혼란 방지).
- 현재고(currentStock) 직접 편집 금지 — 재고는 movements 로만 변경(설계 원칙).
- 한국어 주석, 영어 식별자. 스페인어 UI 텍스트.
- 운영 DB 무관(스키마 변경 없음, 기존 컬럼만 사용).
