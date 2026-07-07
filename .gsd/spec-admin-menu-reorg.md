# SPEC: Admin 메뉴 재구성 (A안 — 순서 고정 + 아이콘 통일)
생성일: 2026-07-07

## 목표
매장 admin 사이드바 메뉴를 "개요 → 일상 운영(Caja) → 조직 관리 → 설정" 순으로 고정하고,
Sucursales 를 최상위로 승격, Generar Token 을 Configuración 하위로 이동, 아이콘을 tabler 세트로 통일한다.

## 배경 및 컨텍스트
- 파일: `ventago-app/src/navigation/vertical/index.ts` (useNavigation 훅)
- admin children 은 DB 모듈 시드 순서(id 순)대로 노출 — venta/producto/materia-prima 는 이미 코드에서 순서 고정 (동일 패턴 적용)
- admin DB 모듈 아이콘이 eos-icons/ri/mdi/ph 혼용 → 코드 오버라이드 맵으로 통일 (DB 무변경)
- iconify 슬림 번들: `src/iconify-bundle/bundle-icons-react.ts` 의 수동 icons 목록 → `npm run build:icons` 로 재생성
- tabler 에 `cash-register` 없음 → Estado de Caja 는 `tabler:cash-banknote` 사용
- 로그 확인 완료 (combined-2026-07-07.log): 관련 에러 없음, pool 정상

## 기술 스택
- 언어/프레임워크: Next.js 13 + TypeScript (ventago-app)
- DB: 변경 없음 (프론트 전용)
- ESLint: ventago-app 설정 (newline-before-return, lines-around-comment 주의)

## 최종 메뉴 구조 (매장 admin)
1. Dashboard (`/dashboards/admin`, tabler:chart-pie)
2. Estado de Caja (`/caja`, tabler:cash-banknote)
3. Cajas Registradoras (`/control-de-caja`, tabler:device-desktop-dollar)
4. Sucursales (`/sucursales`, tabler:building-store) ← Configuración 에서 승격
5. Usuarios (`/usuarios`, tabler:user-plus)
6. Logs de auditoría (`/admin/auditoria`, tabler:clipboard-list)
7. Configuración: Preferencias / Permisos Control / **Generar Token(이동)** / Importar datos legacy

superadmin 도 동일 원칙: Generar Token 을 Configuración 하위로 이동, audit 아이콘 tabler 통일.

## 태스크 목록
- [ ] TASK-1: `navigation/vertical/index.ts` — adminIconOverrides 맵 + forceDefaultIconApps 에 'admin' 추가
- [ ] TASK-2: `navigation/vertical/index.ts` — configChildrenBase 에 Generar Token 편입, superadmin/매장 admin 분기 재구성, adminOrder 정렬
- [ ] TASK-3: `iconify-bundle/bundle-icons-react.ts` — 신규 아이콘 5종 추가 + `npm run build:icons` 재생성
- [ ] TASK-4: ESLint 검증 실행

## 완료 기준
- ESLint 오류 0개
- 메뉴 순서가 위 구조와 일치, DB 시드 순서와 무관
- 신규 아이콘이 슬림 번들에 포함

## 금지사항 / 주의사항
- DB modules 테이블 변경 금지 (순수 프론트)
- 기존 경로(path)/subject 변경 금지 — CASL 권한에 영향
- venta/producto/materia-prima 분기 로직 건드리지 않기
