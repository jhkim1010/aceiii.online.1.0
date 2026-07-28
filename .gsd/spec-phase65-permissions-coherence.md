# SPEC: Phase 65 — 권한·접근제어 정합화 (Permissions Coherence)
생성일: 2026-07-28
상태: PLAN (승인 대기)

## 목표
권한이 4개 층·5종 게이트에 흩어져 서로 다른 기준으로 판정하는 상태를 하나의 경로로 수렴시키고,
스키마·코드·문서가 각각 다른 이야기를 하는 계약 충돌을 제거한다.

## 왜 지금인가
2026-07-28 하루 동안 서로 무관해 보이는 4건이 신고됐고 전부 이 문제로 수렴했다.
- "roles 3개만 보임" → 데이터(백필 미적용)
- "권한 편집이 작동 안 함" → 결함 8건 (stale state·전체삭제 위험·버튼 미노출)
- "CRUD 키 없는 줄" → 빈 모듈 18개 + 메뉴가 권한과 무관
- "로그인 안 됨" → active_sessions UNIQUE ↔ 코드 정책 충돌 (500)

같은 유형의 잠복 폭탄이 조사에서 추가로 확인됐다(§Wave D). 특히 MP 환불은 **이미 차단 상태**였다.

---

## 실측 근거 (2026-07-28 조사)

### 권한 게이트 5종 병행
| 게이트 | 규모 | 실제 동작 |
|---|---|---|
| CASL `Page.acl` | 109개 파일 | **전량 no-op** — `acl.ts` 36·49·64 세 분기가 모두 `can('manage','all')` |
| `<WithAccess allowedModules>` | 82개 파일 | **전량 no-op** — `withAccess.tsx:19` 가 화살표 함수에서 `arguments[0]` 참조 |
| `<WithAccess allowedApps>` | 95개 태그 | 동작 (앱 단위만) |
| `<WithFunctionAccess>` | 36파일 / 97태그 / 66 slug | 동작 — 실질적으로 유일한 프론트 게이트 |
| `menuRegistry.roles` | 1개 항목 (Facturación AFIP) | 동작 |
| `configuracion/index.tsx` 인라인 | 1개 화면 | 동작 (같은 로직 재구현, 버그 없음) |

- `<Can>` 컴포넌트 사용처 **0개** — `Can.tsx` default export 사문화
- role 집합 정의가 **6곳**에 서로 다르게 존재 (`useHasFunction` PRIVILEGED 5종 / `menuRegistry` supervisorRoles 5종·supportRoles 4종 / `acl.ts`·`withAccess`·`configuracion` 각각 superadmin 단독)
- 사이드바 메뉴는 `modules` 행 존재만으로 노출 (권한 무관) — 2026-07-28 대표 function 도입으로 1차 해소

### functions 카탈로그
- slug 중복: `ver-dashboard` 5건, `ver-cajas` 2건 — `permissions` 맵이 slug 키라 **서로 덮어씀**
- id 드리프트: 로컬 150(max 150) vs 운영 160(max 160), 동일 기능이 다른 id (`stock-movement` 로컬149/운영160)
- 악센트 소실 slug 다수 (`crear-categora`, `crear-mtodo-de-pago`) — 모델 `@BeforeCreate setSlug` 가 name 을 덮어쓴 결과
- `resource_key` 128/160, `permission_slug` 33/160만 채워짐
- 권한 편집 UI **4벌**, 그중 `/admin/permisos`(217줄)는 참조 0건 도달 불가 + `WithAccess` 미적용

### 스키마-코드 계약 충돌 (위험도 순)
| # | 위치 | 충돌 | 상태 |
|---|---|---|---|
| 1 | `mp_movements` CHECK vs `mp-wallet.service.ts:93` | DB가 `refund_debit` 금지, 코드는 그 값 INSERT | **★2026-07-28 수정** (`2026-07-28-fix-mp-constraints.sql`) |
| 2 | `mp_wallets` `balance>=0` vs 정산 시차 | 정상 환불도 차단 | **★동 마이그레이션에서 제거** |
| 3 | `active_sessions` UNIQUE(user_id) vs 조건부 destroy | 재로그인 500 | **★2026-07-28 수정** (6개 생성지점 정렬) |
| 4 | `TerminalDevice.branchId` NOT NULL vs `terminal.box?.branchId` | Box 1건 삭제 시 해당 터미널 전원 로그인 500 | 미해결 |
| 5 | `GlobalClient` 모델 2벌 (전역 unique vs owner_group 스코프) | 두 그룹이 같은 CUIT 등록 시 500 | 미해결 |
| 6 | `global_categories.name` 전역 unique + find-then-create | 동시 요청 시 500 (400 변환 없음) | 미해결 |
| 7 | `mobile_sessions` 복합 UNIQUE 가 모델에 미선언 | 동일 기기 동시 로그인 시 500 | 미해결 |
| 8 | 매장 복원이 users 전역 UNIQUE 무시 | 복원 트랜잭션 통째 롤백 | 미해결 |

구조적 배경: `sync.service.ts:17` 이 부팅마다 `sequelize.sync()` 를 실행해 **모델 선언이 DB 에 반영**되고,
마이그레이션 SQL 도 독립적으로 제약을 만든다. 두 경로가 갈라진 결과가
`2026-07-28-phase64-missing-constraints.sql:3-14` 에 실측 기록 — 운영/로컬 제약 106 vs 62건 불일치,
그 중 43건은 sync 가 부팅마다 만든 중복 쓰레기(`*_keyN`).

### 에러 삼킴 (권한·세션·결제·재고)
가장 위험한 것부터:
- `permission-cache.service.ts:108,125,154,185,210` — invalidate 실패 시 `return 0` → **권한 회수가 실패해도 성공으로 보고**, 낡은 캐시로 접근 계속 허용
- `reportsStocksCockpit.service.ts:471,720,846` — `catch {}` → `stocks.type` 조회 실패 시 조정·보류 행이 실입고/판매로 집계돼 **재고 수치가 조용히 틀려짐**
- `mp-wallet.service.ts:41-46,86-90` — wallet 행 없으면 원장 기록 건너뛰고 webhook 은 성공 처리 → **장부 누락**
- `sync.service.ts:18-21` — sync 실패해도 부팅 성공 → 모델/DB 불일치가 런타임까지 감
- `permissions.service.ts:101,134` — 실패 시 `return []` → UI 가 "권한 0개"로 오해

### 문서 불일치 (CLAUDE.md 「세션 & 터미널 보안」)
- "유저당 1개 (UNIQUE userId)" — 모델엔 선언 없음, 제약은 `hot-fk-indexes.sql:8` 에만
- "기존 세션 삭제" — 실제는 다른 fingerprint 만 조건부 삭제
- "IP 확인 → Fingerprint 확인" 순서 — 실제는 반대, 기기 토큰만 있으면 IP 검증 스킵
- "새 디바이스 터미널 등록 강제" — 우회 경로 3개(deviceToken 우선·첫 기기 자동등록·private IP 스킵)
- 세션 6시간 idle TTL 이 문서에 없음
- `mobile_sessions` 4번째 세션 테이블 누락 — 모바일은 중복 로그인 차단 대상 아님

---

## 기술 스택
- 프론트: Next.js 13 Pages Router, MUI 5, CASL(@casl/ability)
- 백엔드: NestJS 11, Sequelize(sync 활성), PG18 (로컬 5432 / 운영 5434)
- ESLint: ventago-app (Warning=빌드 실패). 백엔드는 Prettier + Jenkins 타입체크
- 검증: device VM 에서 jest/전체 eslint 금지(OOM) — 파일 단위 또는 러너 잡

---

## Wave A — 권한 판정 경로 단일화

**결정 필요 (D-A-1): CASL 을 살릴 것인가 걷어낼 것인가**
- A안: CASL 폐기. `Page.acl` 109개 제거, `AclGuard` 를 function-slug 기반 게이트로 교체.
  근거: `<Can>` 0개 사용, `ability.can()` 실질 3곳, subject 체계가 DB slug 와 애초에 불일치(acl.ts:43-44 주석이 자백).
- B안: CASL 유지. `manage:all` 제거하고 페이지 subject ↔ function slug 매핑 테이블 신설.
  비용: 109개 페이지 subject 를 160개 function slug 에 수동 매핑.

→ **A안 권장.** 실사용이 없는 층을 되살리는 비용이 제거 비용보다 크다.

- [x] TASK-A1: `withAccess.tsx:19` `arguments[0]` 버그 수정 — destructuring 정상화 + useMemo
      ★선행 완료: 검증 스크립트가 DB 미존재 slug 25건을 잡아내 33개 파일 정리 후 활성화
- [x] TASK-A2: role 집합 6벌 통합 — `configs/roles.ts` 의 `PRIVILEGED_ROLES`/`SUPERVISOR_ROLES`/
      `SUPPORT_ROLES` + `isPrivilegedRole()` 헬퍼. menuRegistry·useHasFunction·RoleCards·
      configuracion/index 가 이를 import
- [x] TASK-A3: CASL 제거 (A안 채택) — `acl.ts`·`Can.tsx`·`__tests__/acl.spec.ts`·`pages/acl` 삭제,
      `Page.acl` 109개 제거, AclGuard 는 홈 리다이렉트만 남김, `@casl/*` 의존성 제거
      ※ `npm install` 로 package-lock 갱신 필요 (Docker 가 `npm ci` 사용)
- [x] TASK-A4: `configuracion/index.tsx` 게이트를 `isPrivilegedRole()` 로 정렬
- [ ] TASK-A5: `console.log` 상시 출력 제거 (`user-structure.service` 다수 잔존)

## Wave B — functions 카탈로그 정합화

- [x] TASK-B1: slug 유일성 확보 — `2026-07-28-functions-slug-uniqueness.sql`
      완전중복 4건 삭제(권한 이관 후) + 모듈 간 동명 16건에 접미사.
      프론트 어긋난 참조 3곳 동반 수정(CashControlList·CashRegisterList·InfoClient)
- [x] TASK-B2: `functions.model.ts` `setSlug` — 명시 slug 보존 + NFD 정규화로 악센트 소실 차단
- [x] TASK-B3: 계약 키 (module_slug, function_slug) 전환 — 이번 마이그레이션 2건이 기준 사례
- [ ] TASK-B4: 로컬-운영 functions 동기화 스크립트 — slug 기준 diff 출력 + 누락분 시드 생성
      (현재 로컬 150 / 운영 160)
- [ ] TASK-B5: `resource_key` / `permission_slug` 미채움 항목 정리 방침 결정 후 백필

## Wave C — 모듈·화면 정리

- [ ] TASK-C1: `reporte-*` 18개를 `dashboard-reportes` 에서 각자 모듈로 환원
      (module_id 만 변경, function id 유지 → 권한 영향 없음)
      ※ 2026-07-28 대표 function 시드와 중복되는 모듈은 대표 function 제거
- [ ] TASK-C2: 죽은 코드 제거 — `/admin/permisos` 계통 4파일(217줄+), `pages/acl`(49줄),
      `Can.tsx` default export, `views/config/TypePrices`(미참조), `.fuse_hidden*` 잔여파일
- [ ] TASK-C3: 권한 편집 UI 4벌 → 2벌로 정리.
      유지: `RolePermissionsDrawer`(역할) + `UserPermissionsDrawer`(유저 오버라이드) — 2026-07-28 UI 통일 완료
      재검토: `configuracion/permisos` 4탭 (MatrixGrid 는 `permission_slug` 기반이라 slug 체계가 다름)
- [ ] TASK-C4: `menuRegistry` 의 `hiddenModuleUrls` 하드코딩을 권한 기반으로 이관 가능한지 검토

## Wave D — 스키마·코드·문서 계약

- [x] TASK-D1: MP CHECK 2건 수정 (`2026-07-28-fix-mp-constraints.sql`) — **적용 대기**
- [x] TASK-D2: `active_sessions` 생성 경로 6곳 정렬
- [ ] TASK-D3: `TerminalDevice.branchId` — `include` 에 `required:true` 또는 명시적 검증 후 400 반환
- [ ] TASK-D4: `GlobalClient` 레거시 모델 제거 — `app.module.ts:78,186` 등록 해제, 레거시 create 경로 2곳 정리
- [ ] TASK-D5: `global_categories` find-then-create → `findOrCreate` + UNIQUE 위반 400 변환
      (`users.service.ts:269-280` 패턴 이식)
- [ ] TASK-D6: `mobile_sessions` 복합 UNIQUE 를 모델에 선언 + findOrCreate 전환
- [ ] TASK-D7: 매장 복원 시 email/username 충돌 사전 검사 + 명확한 에러
- [ ] TASK-D8: 에러 삼킴 정리 — permission-cache invalidate 실패는 반드시 상위 전파,
      `reportsStocksCockpit` 의 `catch {}` 3곳은 로깅 + 명시적 폴백 표시,
      `sync.service` 실패는 부팅 중단 여부 결정
- [ ] TASK-D9: **제약 단일 출처 확립** — 모델 `unique`/`allowNull` 선언과 마이그레이션 SQL 중
      어느 쪽을 진실로 삼을지 결정. sync() 를 끄고 마이그레이션 일원화하는 것이 권장
      (현재 sync 가 부팅마다 `*_keyN` 중복 제약 43건 생성 중)
- [ ] TASK-D10: CLAUDE.md 「세션 & 터미널 보안」 6개 항목을 실제 동작에 맞게 갱신

## Wave E — 검증

- [ ] TASK-E1: 권한 회귀 테스트 — 역할별로 기대 메뉴·기대 접근 가능 페이지 매트릭스를 만들고
      실제 `/me` structure 와 대조하는 스크립트
- [ ] TASK-E2: 제약 정합성 점검 스크립트 — 모델 선언 vs `pg_constraint` diff (로컬·운영 양쪽)
- [ ] TASK-E3: ESLint 0오류, Prettier 통과, Jenkins 빌드 SUCCESS

---

## 완료 기준
- 권한 게이트가 2종 이하로 수렴 (앱 단위 + 기능 단위), 각 게이트가 실제로 차단함이 테스트로 증명됨
- `functions.slug` 유일, 로컬·운영 카탈로그 동일
- 모델 선언과 DB 제약이 일치 (D-9 결정에 따른 단일 출처)
- CLAUDE.md 세션 섹션이 코드와 일치
- 회귀 없음: 기존 사용자의 메뉴·접근 범위가 의도치 않게 좁아지지 않음

## 금지사항 / 주의사항
- **TASK-A1(withAccess 버그 수정)은 단독 배포 금지** — 82개 파일의 게이트가 동시에 켜지므로
  반드시 검증 스크립트(E1) 통과 후 배포
- 마이그레이션은 항상 slug 기반 (id 하드코딩 금지 — 로컬/운영 id 체계 상이)
- 매트릭스 추출 시 글로벌 role(`store_id IS NULL`) 제외 필수
- 운영 DDL/DML 은 사용자 승인 게이트
- device VM 에서 jest·전체 eslint 실행 금지 (OOM)
- Wave 간 순서 의존: D1·D2(긴급) → B1·B2(slug) → A1(게이트 활성화) → C1(모듈 이동)

## 미결 질문
- D-A-1: CASL 폐기(A안) vs 유지(B안)
- D-B-5: `permission_slug` 를 전면 채울지, 아니면 `FunctionPermissionGuard` 를 slug 없이도
  동작하도록 단순화할지
- D-C-3: `configuracion/permisos` 4탭의 존치 여부 (MatrixGrid 는 다른 slug 체계)
- D-D-9: sync() 비활성화 시점 — 운영 영향 검토 필요
