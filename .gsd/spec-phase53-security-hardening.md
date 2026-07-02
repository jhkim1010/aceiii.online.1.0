# SPEC: Phase 53 — 보안 취약점 강화 (Critical + High, 발견 #1~#6)

생성일: 2026-07-01
상태: 실행 중 (Wave 1~3 · Wave 4 는 Phase 53.1 로 분리)
근거: 2026-07-01 보안 감사 (백엔드/에이전트/프론트 3영역 병렬). 발견 #1~#6 대응.
브랜치: main (사용자 지시)

## 범위 결정 (확정)
- **D-1 = 공개 prefix 유지**: MinIO `public/` prefix 는 무인증 공개(로고 등), 그 외 업로드/목록/열람은 인증 필수.
- **D-4 = Phase 53.1 분리**: 토큰 localStorage→쿠키(#4)는 회귀 범위가 커서 **본 phase 제외**. 본 phase = #1,#2,#3,#5,#6.

## 목표
운영 중인 Ventago POS/ERP 의 실익스플로잇 가능 취약점 5건(Critical 2 + High 3, #1·#2·#3·#5·#6)을 제거한다.
익명 파일 접근 차단, 하드코딩 시크릿 제거, 브루트포스 방어, 자격증명 로그 유출 차단, WS origin 제한. (#4 토큰 저장은 Phase 53.1)

## 배경 및 컨텍스트
- 백엔드: NestJS 11 + Sequelize + PG (pool min=10/max=80, 현재 PM2 instances=1 stopgap).
- 프론트: Next.js 13 (Pages Router) + CASL(클라이언트 라우팅 게이팅).
- 인증: JWT(6h) + 세션 보안(active_sessions / terminal_devices / branch_ip_registries) + SessionGuard.
- 마지막 에러 로그(error-2026-06-30.log) 비어 있음 — 현재 런타임 에러 없음.
- 전역 가드 부재: NestJS 는 `@Auth()`/`@UseGuards` 를 명시한 엔드포인트만 보호됨.

## 기술 스택
- 언어/프레임워크: Node.js (NestJS), TypeScript / Next.js (React)
- DB: PostgreSQL (Sequelize). **rate-limit 은 pool 미사용**(in-memory 또는 Redis) → pool 영향 없음.
- ESLint: 프로젝트 규칙 Warning=에러 (빌드 차단). 각 파일 수정 후 `npx eslint <file>` 필수.

---

## 발견 요약 (대응 대상)

| # | 심각도 | 항목 | 핵심 파일 |
|---|--------|------|-----------|
| 1 | Critical | MinIO 컨트롤러 무인증 (목록/업로드/열람) | `common/minio/minio.controller.ts` |
| 2 | Critical | 운영 DB 비밀번호 하드코딩 (다수 파일) | `pre-deploy.sh`, `scripts/*.sh`, `CLAUDE.md`, `.planning/**` |
| 3 | High | rate limiting 전무 (로그인/apiKey 브루트포스) | `auth`, `caja-fuerte`, `print.gateway.ts` |
| 4 | High | JWT/세션 토큰 localStorage 저장 (XSS 탈취) | `AuthContext.tsx`, `api.service.ts` |
| 5 | High | API Key 전체 평문 로그 | `print.gateway.ts:56` |
| 6 | High | WS 게이트웨이 `cors: origin '*'` + 일부 미인증 의심 | `print/online-orders-board/restaurant-delivery/support` gateways |

---

## Wave 별 태스크 목록

### Wave 1 — 즉시 격리 (완료 2026-07-01)

- [x] TASK-1 (#1): `minio.controller.ts` 재작성.
  - `GET /minio`(목록) → `@Auth(admin, superadmin)` (전체 열거로 인한 파일명 노출 차단).
  - `POST /minio`(업로드) → `@Auth()` + `sanitizeFileName`(경로 구분자/`..` 제거, basename 강제) → 익명 업로드·임의 prefix 덮어쓰기 차단.
  - `GET /minio/:filename`(서빙) → 공개 유지(로고·상품이미지 `<img>` 호환)하되 `isPubliclyServable`로 슬래시/상위경로 및 비이미지 확장자(.csv/.pdf/.xlsx 등 민감 파일) 차단. 정산 CSV(`payout-*.csv`)·QC/공유폴더 노출 제거.
  - D-1(공개 prefix) 반영: 로고 `store_logo_*`·상품이미지 `{sku}_{ts}` 는 슬래시 없어 계속 공개, 민감 문서는 차단. 회귀 없음(슬래시 경로는 원래 라우트 매칭 불가).
  - 파일: `api-ventago/src/common/minio/minio.controller.ts`

- [x] TASK-2 (#5): `print.gateway.ts` 의 `token(full)` 로그 제거 → 마스킹된 tokenPreview 만 기록. 추가로 `/realtime` 게이트웨이 `register_api_key` 의 apiKey 평문 로그도 prefix 마스킹.
  - 파일: `print.gateway.ts`, `common/socket/websocket.gateway.ts`

- [x] TASK-3 (#6): 5개 게이트웨이 `cors.origin '*'` → 공용 `wsCorsOptions`(env `CORS_ORIGINS` 화이트리스트, 기본: 운영 프론트+localhost). 네이티브 에이전트(Origin 없음)는 허용.
  - 신규: `common/socket/ws-cors.ts`
  - 적용: `print.gateway.ts`, `online-orders-board.gateway.ts`, `restaurant-delivery.gateway.ts`, `support.gateway.ts`, `common/socket/websocket.gateway.ts`
  - 검증: `tsc --noEmit` 통과(에러 0).

- [x] TASK-4 (#6 후속): 게이트웨이 연결 인증 점검 결과 —
  - `/envios`(online-orders-board), `/restaurant`(restaurant-delivery), `/support` → **JWT 검증 있음(OK)**.
  - `/print-agent` → apiKey 검증 있음(OK).
  - `/realtime`(common/socket/websocket.gateway.ts) → **connect 시 인증 없음**(welcome 만 emit, register_api_key 메시지 레벨). CORS 화이트리스트로 브라우저 CSWSH 는 차단됨. 다만 connect-time 인증 부재는 잔여 위험 → **후속(Wave 3 이후) 처리**: handleConnection 에 JWT/apiKey 검증 추가(팀챗 회귀 주의). apiKey 평문 로그(line 37)는 이번에 마스킹 완료.

### Wave 2 — 브루트포스 방어 (#3) — 코드 완료 2026-07-01 (런타임 스모크는 Wave 5)

- [x] TASK-5: `@nestjs/throttler@^6.5.0` 설치 + `ThrottlerModule.forRoot` 전역 등록(기본 완화 정책 ttl 60s/limit 600 per IP, env 재정의 가능). `APP_GUARD` = `ProxyThrottlerGuard`.
  - **프록시 IP 보정**: main.ts 에 trust proxy 미설정 → 커스텀 `getTracker` 로 `x-forwarded-for`(첫 홉)/`x-real-ip`/req.ip 파싱(auth.controller signIn 과 동일 규칙). 미보정 시 전 시스템이 프록시 단일 IP 로 뭉쳐 오작동.
  - **WS 무영향**: `canActivate` 에서 `context.getType() !== 'http'` → skip(소켓 게이트웨이는 TASK-7 자체 rate-limit).
  - **pool 무영향**: in-memory storage(기본). instances=1 이므로 워커 분리 문제 없음(D-2).
  - 신규: `common/throttle/proxy-throttler.guard.ts`, `common/throttle/throttle.constants.ts`. 수정: `app.module.ts`, `package.json`.
- [x] TASK-6: 민감 엔드포인트 엄격 throttle — 공유 IP(다중 터미널 branch_ip_registries) 정상 트래픽 고려해 login 15회/분·IP(blockDuration 60s), 자격증명류 10회/분·IP.
  - `POST /login`(15/분), `POST /verify-admin-credentials`(10/분), `PUT /change-password`(10/분), `POST /caja-fuerte/withdrawal`(10/분). 모두 `@Throttle(...)` 데코레이터.
  - 파일: `auth.controller.ts`, `caja-fuerte.controller.ts`. 값은 `THROTTLE_LOGIN_LIMIT`/`THROTTLE_SENSITIVE_LIMIT` env 로 튜닝.
- [x] TASK-7: `print.gateway.ts handleConnection` 에 IP 슬라이딩 윈도우 rate-limit(기본 60회/60s·IP) 추가 — apiKey 검증(DB 조회) 전에 차단해 소켓 재접속 브루트포스 방어.
  - 신규: `common/socket/socket-rate-limiter.ts`(in-memory, prune 포함). 값은 `THROTTLE_SOCKET_CONNECT_*` env.
  - **검증**: `tsc --noEmit`(신규/수정 파일 에러 0, 무관 mp-webhook.spec 기존 에러만) + `nest build` 성공 + 신규 3파일 eslint exit0 + prettier 정리.

### Wave 3 — 시크릿 제거/로테이션 (#2, 일부 사용자/운영 액션)

- [ ] TASK-8: 코드/스크립트에서 하드코딩 DB 비밀번호 제거 → `$PGPASSWORD`/`.env` 참조로 교체.
  - 파일: `pre-deploy.sh:53,103`, `scripts/measure-cockpit-pool.sh:55`, 기타 `node -e` 스니펫
- [ ] TASK-9: 문서 레다크션 — `CLAUDE.md:245` 및 `.planning/**`, `docs/superpowers/**`, `.gsd/spec-codigo-import-review.md:65` 의 평문 비밀번호를 플레이스홀더로 치환.
- [ ] TASK-10 (**사용자/운영 액션**): 운영 PG 비밀번호 **로테이션**(coolsistema) + 앱/스크립트 env 갱신 + 재배포. (SSH/DDL 성격 → 사용자 승인 후 실행)
- [ ] TASK-11 (**사용자 결정, 파괴적**): git 히스토리 purge(BFG/filter-repo). 히스토리 재작성 → 협업자 재클론 필요. (D-3)

### Wave 4 — (Phase 53.1 로 분리됨) 토큰 저장 방식 전환 (#4)
> D-4 결정에 따라 본 phase 에서 제외. 별도 `spec-phase53.1-token-httponly-cookie.md` 로 독립 실행.
> 내용: 백엔드 httpOnly/Secure/SameSite 쿠키 발급 + CSRF, 프론트 withCredentials 전환 + localStorage 토큰 제거, 세션 만료 회귀 검증.

### Wave 5 — 검증

- [ ] TASK-15: ESLint 전체 0 오류(변경 파일).
- [~] TASK-16: 스모크 — **로그인 throttle 429 검증 완료(2026-07-01, 로컬 dist 기동)**: `POST /api/auth/login` 15회 404(자격증명 오류, throttler 통과) → 16회째부터 429(`Retry-After: 42`, blockDuration 동작). 전역 기본(600)은 `GET /api/version` 200 정상 통과(정상 트래픽 무차단). `X-Forwarded-For: 203.0.113.99` 신규 IP 첫 요청 404(429 아님) = getTracker IP 격리 정상. **잔여**: 미인증 `GET/POST /minio` 401(Wave 1 소관), WS 비허용 origin 거부, 로그 full apiKey 미출력 확인.
- [ ] TASK-17: pool 영향 점검 — throttler in-memory/Redis 로 pool 소비 없음 재확인(현 min10/max80 유지). PM2 instances 변경 없음.
- [ ] TASK-18: 마지막 에러 로그 확인(신규 에러 없음).

---

## 결정 사항
- **D-1 (#1) = 공개 prefix 유지** ✅ (확정): `public/` 무인증 + 나머지 인증. TASK-1 은 이 방식으로 구현.
- **D-4 (#4) = Phase 53.1 분리** ✅ (확정): 본 phase 제외.
- **D-2 (#3, in-memory 로 진행 확정)**: instances=1(현 stopgap) → in-memory throttler. **PM2 cluster 복귀(instances≥2) 시 Redis storage 필수**(워커별 카운터 분리로 실효 한도 N배 완화됨) — ecosystem.config.js instances 변경 spec 과 연동 필요.
- **D-3 (#2, 미확정 — Wave 3 진입 시 확인)**: git 히스토리 purge 실행 여부(파괴적). 최소 로테이션(TASK-10)만으로도 노출 무력화 가능.

## 완료 기준
- 미인증 MinIO 접근 불가(401). 로그인/apiKey 브루트포스 throttle 동작(429).
- 소스/스크립트에 평문 DB 비밀번호 0건. 운영 비밀번호 로테이션 완료(TASK-10).
- 서버 로그에 API Key 전체 미출력. WS 는 허용 origin 만 연결.
- ESLint 0 오류. 신규 런타임 에러 0. PG pool 설정/소비 불변.

## 금지 / 주의사항
- pool 설정(min10/max80) 및 PM2 instances 변경 금지(별도 spec 소관).
- MinIO 인증 추가 시 **로고 공개 로드 회귀** 주의(D-1 먼저 확정).
- 운영 DB 비밀번호 로테이션·git purge·서비스 재시작은 **사용자 승인 후** 실행(CLAUDE.md 운영 규칙 준수).
- CORS 화이트리스트에 개발(localhost:3050/5001) origin 누락 시 dev 깨짐 주의.
- 토큰→쿠키(Wave 4)는 회귀 범위가 커서 독립 검증 필요 — 승인 없이 병합 금지.
