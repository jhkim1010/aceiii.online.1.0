# SPEC: Wave 1 — DB 정합성·보안·성능 백엔드 개선
생성일: 2026-07-27

## 목표
DB 위험 분석(docs/db-risk-analysis-20260727.md) 후속 코드 수정. 민감컬럼 노출 제거, 재고 lost-update 제거, nullify 재고복원 버그 수정, 채번 쿼리 인덱스 활용, 권한/유저 조회 캐시. **API 응답 형태 불변 → 프론트 무변경.**

## 배경 및 컨텍스트 (실측)
- Users SELECT에 password 포함 44,231회 (jwt.strategy → findOneByEmail이 매 요청 DB 조회)
- processSaleItems: `product.stock -= q; save()` 절대값 덮어쓰기 → lost update (드리프트 실재)
- **nullifySale 버그**: `Stocks.create({ productId, stock })` — Stocks에 productId 컬럼 없음(무시됨) → productBranchId NULL 고아 행 + products.stock 미복원
- reserveDailyNumber: advisory lock은 Phase 63 B-0 적용됨(정확성 OK), 단 `DATE(sale_date AT TIME ZONE tz)` non-sargable → 판매 누적 시 채번 선형 악화. idx_sales_store_date(2026-07-27 적용됨) 활용하도록 범위 조건화
- FunctionPermissionGuard: 요청당 순차 findOne 6회
- mp_accounts 토큰은 AES-256-GCM 암호문 저장 — Wave 1 제외 (노출 위험 낮음)
- daily_counters 테이블 신설 **취소** — advisory lock으로 충분, 쿼리 최적화만

## 기술 스택
- NestJS 11 + Sequelize(sequelize-typescript), PG18, pgbouncer transaction mode
- MemoryCacheModule @Global (어디서든 주입 가능, Redis pub/sub 무효화 내장)
- ESLint: newline-before-return, lines-around-comment 주의

## 태스크 목록
- [x] TASK-1: Users 모델 defaultScope로 password·mobilePin 기본 제외 + `withSecrets` scope — users.model.ts
- [x] TASK-2: findOneByEmailOrUsername → withSecrets(로그인 compare용), findOneByEmail → password 반환 제거(JWT용, 호출자 jwt.strategy뿐) — users.service.ts
- [x] TASK-3: changePassword·verifyAdminCredentials → withSecrets — auth.service.ts
- [x] TASK-4: 모바일 로그인 user 조회 → withSecrets — mobile-auth.service.ts
- [x] TASK-5: caja-fuerte 비번검증 — request.user.password 의존 제거, withSecrets로 해시 직접 조회 — caja-fuerte.service.ts
- [x] TASK-6: jwt.strategy 유저 조회 30s 캐시(MemoryCacheService) + changePassword/유저수정·매장 활성/정지 시 무효화 — jwt.strategy.ts, users.service.ts, auth.service.ts
- [x] TASK-7: processSaleItems 재고 원자적 감소(decrement, parent 포함) — sales-create.service.ts
- [x] TASK-8: nullifySale 재고 복원 수정: branchId 해석→ProductBranch→Stocks(+qty)+products.stock increment(parent 포함) — sales-create.service.ts
- [x] TASK-9: reserveDailyNumber 당일 조건을 sargable 범위로 교체 — sales-create.service.ts
- [x] TASK-10: FunctionPermissionGuard 결과 60s 캐시(perm:{userId}:{storeId}:{slug}:{action}) — function-permission.guard.ts + spec 보정
- [x] TASK-11: 권한 변경 시 perm: prefix 무효화 — role-function.service(bulk/교체, spec 보정), user-function.service(@Optional 주입 — 수동 new 경로 2곳 호환)
- [x] TASK-12: 검증 — prettier 전체 통과, TS transpile 문법 12/12 OK. 타입 ESLint는 VM OOM(기존 제약) → Jenkins 게이트 위임

## 리뷰 리포트 (2026-07-27)
- 변경 12파일 (서비스 10 + spec 2). API 응답 shape 불변 — 프론트 무변경 확인.
- pool: 신규 쿼리는 caja-fuerte 해시 1건(attributes 2개)뿐, 나머지는 기존 트랜잭션 커넥션 재사용/조회 제거. 캐시로 요청당 DB 왕복 순감소.
- 발견/처리: ①daily_counters 계획 취소(Phase 63 B-0 advisory lock 기적용) ②nullifySale 재고복원 버그 신규 발견·수정 ③new UserFunctionService(모델) 수동생성 2곳 → @Optional 주입으로 호환
- 후속: Jenkins 빌드(타입 ESLint 게이트) → 배포 후 daily_number partial unique 인덱스 활성화(마이그 주석) / Wave 2(크로스테넌트 13행 정리+stock 백필) / sales-create.service.spec 의 로직 사본 주석은 구식화됨(테스트는 통과)

## 완료 기준
- ESLint 오류 0개 (변경 파일)
- API 응답 shape 불변 (프론트 무변경 확인)
- 모든 신규 쿼리 pool 안전 (기존 트랜잭션 커넥션 재사용, 신규 장기점유 없음)

## 금지사항 / 주의사항
- 재고 부족 차단 로직 추가 금지 (음수 재고 허용 정책 — allowSaleWithoutStock 기존 분기만 유지)
- afip-issuer.service.ts 건드리지 말 것 (Mac 워킹트리 미커밋 WIP)
- .fuse_hidden* 파일 무시
- sale/hold 응답 구조 변경 금지
- 커밋/push는 사용자 (로컬 워크플로우) — 이 세션은 파일 수정까지만
