# Ventago — POS/ERP System

## What This Is

다점포 소매업 대상 POS/ERP 시스템. 재고, 판매, 재무, 생산, 외주 관리를 포함한 종합 업무 플랫폼.
NestJS 백엔드 + Next.js 프론트엔드로 구성된 모노레포 구조이며, Docker/Jenkins CI/CD로 운영 배포 중.

## Core Value

매장 운영자가 POS 판매부터 재고/재무/외주까지 하나의 플랫폼에서 관리할 수 있어야 한다.

## Requirements

### Validated

- [x] POS 판매 화면 (nueva-venta) — v1.0
- [x] 상품/카테고리/재고 관리 — v1.0
- [x] 사용자/역할/권한 관리 (CASL) — v1.0
- [x] 지점(Branch)/금전함(Box)/터미널 관리 — v1.0
- [x] JWT 인증 + 세션 보안 (중복로그인 차단, 디바이스/IP 감지) — v1.0
- [x] 판매 내역/보고서 — v1.0
- [x] 비용(Gastos) 관리 — v1.0
- [x] 금전함/금고 운영 — v1.0
- [x] MinIO 파일 업로드 (매장 로고 등) — v1.0
- [x] 외주(Subcon) 관리: 납품업체, 발주, 검수, 정산 — v1.0
- [x] 생산 관리 (BOM, 작업지시) — v1.0

### Active

- [ ] UI/UX 개선 (로그인 화면 등 세련화)
- [ ] 마켓플레이스 기능 강화
- [ ] 재판매자(Revendedor) 포털 완성
- [ ] AI 채팅 (Knowledge base) 고도화
- [ ] 대시보드/분석 강화

### Out of Scope

- 모바일 네이티브 앱 — 웹 PWA 우선, 네이티브는 차후 검토
- 다국어 지원 — 현재 스페인어 단일 언어로 운영

## Context

- **운영 URL**: API `https://newapi.coolsistema.com/api`, 프론트 `https://app.coolsistema.com`
- **배포**: Jenkins CI/CD → Docker (srv803182)
- **DB**: PostgreSQL 15 (Docker 컨테이너 `dbpostgres`, DB명 `ventago`)
- **멀티테넌트**: `store_id` FK로 매장 단위 데이터 격리
- **계층**: Store → Branch(Sucursal) → Box(Caja) → Terminal (1:N:N:N)
- **ORM**: Sequelize (`underscored: true` → DB snake_case, 모델 camelCase)

## Constraints

- **Tech Stack**: NestJS 11 + Sequelize (백엔드), Next.js 13 Pages Router + MUI 5 (프론트)
- **ESLint**: Warning도 에러 처리 → `newline-before-return`, `lines-around-comment`, `no-unused-vars` 준수 필수
- **npm workspaces**: 패키지 호이스팅 → webpack alias에 `require.resolve` 사용 필수
- **DB**: SQL 직접 실행 시 반드시 snake_case 컬럼명 사용

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Sequelize `underscored: true` 전역 설정 | DB와 JS 네이밍 컨벤션 자동 변환 | ✓ Good |
| MinIO로 파일 저장 통합 | S3 호환, 자체 호스팅 가능 | ✓ Good |
| CASL 기반 권한 관리 | 속성 기반 유연한 접근 제어 | ✓ Good |
| 세션 보안: 유저당 1세션 + 디바이스/IP 바인딩 | 부정 사용 방지 | ✓ Good |
| Pages Router 유지 (App Router 미전환) | 안정성 우선, 대규모 마이그레이션 리스크 회피 | ✓ Good |

---
*Last updated: 2026-04-01 after GSD initialization*
