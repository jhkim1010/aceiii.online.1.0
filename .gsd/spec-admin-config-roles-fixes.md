# SPEC: Admin/Config 화면 3건 수정 + 권한 편집 UI 재설계
생성일: 2026-07-28

## 목표
Preferencias>Precios 전체 표시, Config>Ventas gastos 중복 제거, roles 백필(운영 3·6·8) + 권한 편집 Drawer를 기능 단위 스위치 방식으로 재설계.

## 배경 및 컨텍스트
- Precios: `PriceTypesList.tsx` — minHeight 320 고정으로 4.9행만 표시, id DESC 정렬로 PRECIO 1 잘림, 서버 pageSize 10, baseId를 현재 페이지 최소 id로 계산하는 버그.
- Ventas 탭: `ConfigurationSalesView.tsx` L9-16, L38-40 CategoriasGastosTreeView — Preferencias>Gastos 탭과 중복.
- Roles 3개: 운영 DB store 3·6·8이 레거시 3 role만 보유(실측). `phase30-existing-stores-roles-backfill.sql` 운영 미적용. 코드 필터 아님.
- 권한 편집 결함 8건: 체크박스↔트리 토글 충돌, 역할 전환 시 stale state로 오저장, 로드 실패 후 저장 시 권한 전체 삭제, store_owner에 편집 버튼 미노출(`includes('admin')`), userRols 표시 항상 0, 편집자 본인 structure로 앱 필터링, slug 동사 추론 실패 시 read 버킷, bulk-actions 응답 없음.
- DB 정책(2026-07-28 reseed): 기능 단위 on/off + 4액션 자동 부여. → UI도 기능 단위 스위치로 확정(사용자 승인).

## 확정 결정 (사용자 승인)
- D1: 권한 UI = 기능 단위 스위치 (App>Módulo>Función, 모듈 토글+검색+diff 미리보기)
- D2: 운영 DB에 phase30 백필 + reseed 바로 적용 (백업 테이블 포함), 로컬 5432 명령 사용자 전달
- D3: 레거시 role(admin/vendedor/gerente)은 'Legacy' 뱃지로 구분 표시

## 기술 스택
- Next.js 13 + MUI5 / NestJS + Sequelize / PG18 (운영 5434, 로컬 5432)
- ESLint: ventago-app (newline-before-return, lines-around-comment, no-unused-vars 주의)
- pool: 마이그레이션은 단일 트랜잭션 psql 실행 — 앱 pool 무관

## 태스크 목록
- [ ] TASK-1: Precios 전체 표시 — `views/config/productos/price-types/list/PriceTypesList.tsx` (pageSize 100, autoHeight/높이 확장, id ASC 표시, baseId 버그 수정)
- [ ] TASK-2: Ventas 탭 gastos 카드 제거 — `views/config/ventas/ConfigurationSalesView.tsx` (dynamic import 포함 정리)
- [ ] TASK-3: RoleCards 수정 — Legacy 뱃지, privileged 게이트(store_owner 등 포함), totalUsers 표시 수정
- [ ] TASK-4: useRoleFunctions 훅 수정 — roleId 변경 시 초기화, error 노출
- [ ] TASK-5: RolePermissionsDrawer 재설계 — 기능 단위 스위치 UI (트리뷰 제거)
- [ ] TASK-6: 운영 5434에 phase30 백필 + reseed 적용 (백업 확인), 로컬 5432 명령 전달
- [ ] TASK-7: ESLint 검증 (변경 파일 단위 — VM OOM 회피)

## 완료 기준
- ESLint 오류 0개 (변경 파일)
- 운영 roles: store 3·6·8 = 10개, 백업 테이블 존재
- 저장 payload: 활성 기능마다 actions 4종 전송 (DB 정책 일치)
- 로드 실패 시 Guardar 비활성 (권한 전체 삭제 사고 차단)

## 금지사항 / 주의사항
- UserPermissionsDrawer(유저 오버라이드)는 이번 범위 밖 — 건드리지 않음
- groupByResource/CrudActionRow 파일 삭제 금지 (UserPermissionsDrawer 사용 여부 미확인)
- 백엔드 API 시그니처 변경 금지 (bulk-actions 그대로 사용)
- device VM에서 jest/전체 eslint 금지 (OOM) — 파일 단위만
