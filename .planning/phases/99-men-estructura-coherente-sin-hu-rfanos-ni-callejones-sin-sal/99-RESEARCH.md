# Phase 99: 메뉴 — 구조 일관성 — Research

**Researched:** 2026-10-05
**Domain:** 사내 모노레포 UI 내비게이션 구조 (Next.js Pages Router 사이드바/허브) + NestJS 권한 가드 정합성
**Confidence:** HIGH (전부 현재 코드·운영 DB 대조로 확인. 외부 레포 의존 1건만 LOW — 아래 D-01 참조)

## Summary

이 Phase 는 새 기능을 만들지 않는다. **메뉴의 다섯 출처(DB 구조 시드 · `menuRegistry.ts` 코드 주입 ·
`configuracion/index.tsx` 의 `HUB_TABS` 배열 · 화면 내 링크 · superadmin/agent 하드코딩) 사이의
불일치를 코드로 고치는 Phase** 다. `.planning/ANALISIS-2026-10-05-menu-estructura.md` 가 22건의
불일치(A2~A13, B1~B10)를 찾았고, `99-CONTEXT.md` 가 그중 사용자 결정이 필요한 9가지(D-01~D-09)에
답을 냈다.

연구 결과, CONTEXT.md 작성 이후(같은 날, 분석 직후) 이미 **4개 커밋**(353ab400·ba9c7b1b·8744399b·
a734bd68)이 들어가 A1(허브 키 충돌)·B10(빈 탭)·A13 일부(제어판 게이트 없음)를 해소했다. 현재
`HUB_TABS` 에는 `requiredPrivileged` 필드가 이미 존재하고 일부 탭(datos-tienda, qr)에 쓰이고 있다 —
이번 Phase 가 할 일은 **이 필드를 세 개 Avanzado 탭에 추가**하는 것뿐이지, 새 메커니즘을 만드는 게
아니다.

가장 중요한 신규 발견은 **D-09 범위 밖에서 나온 확인된 보안 결함**이다: `FunctionsController`
(`PUT/POST/DELETE /functions`) 가 `CrudController` 의 CRUD 메서드를 **아무 `@Auth()` 데코레이터
없이** 상속한다. `/admin/permisos` 프런트 페이지도 `WithAccess` 가 전혀 없다. `functions` 테이블은
**매장 구분이 없는 전역 카탈로그**(126+ 테넌트 공유) — 로그인한 어떤 역할의 사용자든 API 를 직접
호출하면 전체 시스템의 권한 정의를 수정·삭제할 수 있다. 이것은 가설이 아니라 소스 3곳(페이지 →
모달 → 컨트롤러)을 추적해 확인한 사실이다. `/admin/permisos` 는 메뉴 진입점도 없다(A9) — 지금은
URL 을 직접 쳐야 열리지만, 게이트가 없다는 사실 자체가 테넌트 격리 절대 규칙(CLAUDE.md, MEMORY
`tenant-isolation-is-absolute`)에 어긋난다.

D-01(지원 토큰 vs Acceso de Ventago 통합 가능성)은 **코드로 "불가능"을 증명**할 수 있었다 —
`ALCANCES_AGENTE` 는 `cert`·`usuarios_terminales`·`legacy` 3개뿐이고 일반 매장 데이터
열람/수정 범위가 없다. 반면 Token de soporte 검증 뒤 CoolSistema 직원이 실제로 무엇을 할 수
있는지는 **이 저장소 밖(CoolSistema 내부 포털, 별도 코드베이스)**에 있어 확인 불가능하다 — 기술
통합은 불가, UI 통합(한 화면 두 카드, 목업에 이미 반영됨)만 가능.

**Primary recommendation:** 코드만으로 되는 8개 항목(허브 게이트 상수화·주입 항목 게이트·
support-token `@Auth(admin)`·FunctionsController 보안 수정·Dashboard ventas 노출·Caja fuerte 탭·
defect-codes 게이트·Dispositivos 탭 신설)을 낮에 커밋 → 밤 배포. 시드가 필요한 2개
(`reporte-asistencia` function 신규 + `modules.name` 변경)는 운영 DML 승인 후 같은 밤에. Carpetas
compartidas(D-03)는 코드만으로는 "완전히 못 켠다" — Google 서비스 계정 키가 로컬·운영 둘 다
없다(인프라 작업, 사용자 조치 필요).

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| 사이드바 렌더 (apps→modules 필터링) | Frontend Server (Next.js) | API (구조 산출) | `/auth/me` 가 `user.structure` 산출(API), `navigation/vertical/index.ts` 가 그걸 소비해 렌더(Frontend) |
| Configuración 허브 탭 가시성 | Frontend Server | — | `HUB_TABS` 의 `canSeeTab()` 은 순수 클라이언트 판정 — 서버는 실제 데이터 접근만 재검증 |
| 권한 함수 카탈로그(`functions` 테이블) 편집 | API / Backend | — | 전역 테이블이므로 **반드시** 서버가 강제해야 함. 프런트 게이트는 UX 편의일 뿐, 지금은 서버도 비어 있음(보안 결함) |
| Carpetas compartidas 파일 I/O | API / Backend | 외부 서비스(Google Drive) | `GoogleDriveService` 가 서비스 계정으로 Drive API 호출. 프런트는 업로드/다운로드 스트림만 중계 |
| Watch(Galaxy) 페어링 | API / Backend | Frontend (RelojesCard) | 토큰 발급·검증은 서버, 웹 카드는 얇은 클라이언트 |
| Reportes v2 레지스트리(`legacyHref` 포함) | Frontend Server | — | 순수 TS 데이터 배열, 서버 왕복 없음 |
| 메뉴 재발 방지 시험(허브 계약·도달 가능성) | Frontend Server (jest) | — | 소스 텍스트 정적 분석(`fs.readFileSync` + regex), 렌더 없음 |

## Project Constraints (from CLAUDE.md)

- **낮 08–16시(AR) 운영 반영 금지** — 활동 사용자 ≤5명이면 예외(직전마다 재측정). 이 Phase 의
  코드 변경은 낮에 커밋 가능하지만 push 후 Jenkins 빌드가 운영 컨테이너까지 가는 것은 밤으로.
- **사이드바/권한 변경은 "시드 먼저 → 코드"** — `reporte-asistencia` function 추가,
  `modules.name` UPDATE(D-15 항목, 결정 안 됐으면 보류) 모두 이 순서.
- **DB 마이그레이션은 로컬(5432)+운영(5434) 동시 적용** — 한쪽만 하지 않는다.
- **권한 테이블 DML 은 `-- perm-cache:` 주석 필수** — `role_functions`/`functions` 등에 대한 DML.
  `reporte-asistencia` function 삽입 + 역할 부여가 여기 해당.
- **무중단 마이그레이션 규약**(expand→migrate→contract, `CREATE INDEX CONCURRENTLY`,
  `lock_timeout`) — 이 Phase 의 변경은 전부 작은 INSERT/UPDATE 라 해당 없음, 단
  `functions`/`modules` 테이블은 운영 트래픽이 읽는 테이블이므로 `SET lock_timeout` 관례는
  그대로 지킨다.
- **push 는 묻지 말고 한다** — 완료 후 커밋·push·빌드 확인하고 사후 통보. 운영 DML 은 SQL+영향
  행 제시 후 승인.
- **테넌트 격리는 절대 규칙** — `functions` 보안 수정은 이 규칙의 직접 적용 사례.
- **global_clients 등 전역 테이블은 절대 건드리지 않는다** — `functions`/`modules`/`apps` 도
  전역 테이블이다. 이번 수정은 **가드 추가**(읽기를 막지 않음, 쓰기만 superadmin 으로 좁힘)라
  이 규칙과 충돌하지 않는다.
- **app jest 는 `.tsx` 를 import 할 수 없다** — 순수 로직은 `.ts` 로 뽑아야 시험 가능 (아래
  Validation Architecture 참조).

<phase_requirements>
## Phase Requirements

이 Phase 는 REQUIREMENTS.md 의 공식 요건 ID 가 없다(TBD). `99-CONTEXT.md` 의 D-01~D-09 가 범위를
대신한다. 아래 표는 각 결정과 이 연구가 제공하는 근거를 매핑한다.

| ID | 결정 요약 | Research Support |
|----|-----------|------------------|
| D-01 | 지원 토큰·Acceso de Ventago 통합 가능성 | §D-01 — 코드로 "기술 통합 불가" 증명, UI 통합만 가능 |
| D-02 | 기기 연결 → Configuración › Dispositivos | §D-02 — 이동 대상 컴포넌트 3개 특정 |
| D-03 | Carpetas compartidas 복원 | §D-03 — 백엔드/프런트 완성, 인프라(SA 키) 미설정 확인 |
| D-04 | Dashboard ventas 재노출 | §D-04 — `exclude` 배열 1줄 수정 위치 특정 |
| D-05 | ClienteVista·CodigoVista 위치 유지 | §D-05 — 변경 없음, 확인만 |
| D-06 | 레거시 리포트 유지 + legacyHref 3개 수정 + asistencia 추가 | §D-06 — 깨진 경로 원인 확인, 함수 시드 설계 |
| D-07 | 「Control de envíos」 표시명 | §D-07 — 이미 전 출처 일치 확인(변경 불요) |
| D-08 | Admin 그룹 순서 유지 | §D-08 — 변경 없음 |
| D-09 | 허브 게이트 통일·주입 항목 필터·지원토큰 admin 전용·재발방지 시험 2개 | §D-09 + §보안 — 메커니즘·위치 전부 특정, **추가로 확인된 /functions 보안 결함 포함** |
</phase_requirements>

---

## D-01 — 지원 토큰(Token de soporte) ↔ Acceso de Ventago 통합 가능성

**결론: 백엔드 통합 불가(근거 있음). 목업이 이미 제안한 "한 화면, 두 카드" UI 통합은 가능.**

### 두 시스템의 실제 범위 비교 (코드 확인)

| | Token de soporte | Acceso de Ventago |
|---|---|---|
| 컨트롤러 | `api-ventago/src/app/support-token/support-token.controller.ts` | `api-ventago/src/app/agente/agente.controller.ts` |
| 생성 주체 | 매장 `generate`(현재 `@Auth()` — **어느 역할이든**, B6 미해결) | `AccesoVentagoController.generar` — `@Auth(ValidRoles.admin)` |
| 사용 주체 | CoolSistema 직원(`validate`, `@Auth()` — **이 저장소에 없는 별도 CoolSistema 포털**이 호출하는 것으로 추정) | `agent` 역할 전용 계정(`AgenteController`, 별도 `role=agent` 유저) |
| 범위(scope) | **없음** — `validateToken()` 은 `{valid, storeId, storeName}` 만 반환, 이후 CoolSistema 쪽이 무엇을 하는지 **이 코드베이스에 없음** | `alcancesValidos()` — `cert`(AFIP 인증서) · `usuarios_terminales`(세션 종료) · `legacy`(레거시 임포트) **3개뿐**. `@AgentScope()` 로 막힌 엔드포인트 6개(afip.controller.ts ×6, legacy-import ×12)만 통과 가능 |
| 유효시간 | 5분 고정(`TOKEN_TTL_MS`) | 30분 또는 2시간 선택(`duracionValida`) |
| 과금 | 월 20회 무료, 초과 시 ₱5,000/건(`OVERAGE_CHARGE`) | 없음 |
| 감사 로그 | `usedBy`/`usedAt` 필드만 | `eventos` 테이블 — `GET accesos/:id/eventos` 로 조회 가능한 상세 이벤트 로그 |
| 폐기(revoke) | 없음(5분 자동 만료만) | `POST accesos/:id/revocar` |

### 왜 기술 통합이 불가능한가

`AgenteController` 의 엔드포인트는 전부 `role=agent` 전용 계정(매장에 속하지 않는
`agent@app` 류 계정, `agent-access.decorator.ts` 주석 참조)만 호출할 수 있고, 그 계정이 접근
가능한 범위는 `ALCANCES_AGENTE`(`cert`/`usuarios_terminales`/`legacy`) 로 하드코딩된 6개
엔드포인트뿐이다. 일반적인 "고객 매장 화면을 보면서 문제를 재현"하는 지원 작업(상품 화면 확인,
판매 내역 조회, 설정 확인 등)에 대응하는 `@AgentScope` 가 **코드에 하나도 없다**. 이걸
Token de soporte 를 완전히 대체하도록 넓히려면 ALCANCES_AGENTE 에 새 scope 를 추가하고 해당
컨트롤러 전부에 `@AgentScope` 를 다는 대규모 작업이 필요하며, 이는 이 Phase(메뉴 정합성)의
범위를 크게 벗어난다.

### 확인 불가능한 부분 (LOW confidence, 외부 의존)

Token de soporte 의 `validateToken()` 뒤 CoolSistema 직원이 실제로 무엇을 할 수 있는지는
`/Users/marcoskim/TrabajoProgramming/` 아래 다른 어떤 로컬 저장소에도 없다(확인: 형제 디렉터리
전수 조사, CoolSistema 내부 포털 레포 없음). 이 메커니즘을 만든 당사자(CoolSistema 운영팀)만
답할 수 있는 질문 — "검증 후 매장 computed context 로 어떻게 전환하는가, 그 세션의 쓰기 범위는
무엇인가" — 는 **코드로 검증 불가**로 남긴다. [ASSUMED]

### 권장 (사용자 승인 전제)

분석 문서·목업이 이미 제안한 방식을 따른다: 허브에 **「Acceso para soporte」** 탭 하나를 만들고
그 안에 두 카드(Token de soporte / Acceso de Ventago)를 나란히 두되, 각 카드 상단에 "누가·얼마
동안·무엇을 할 수 있나"를 한 줄로 명시한다. 이것은 **UI 레이어 통합**이지 백엔드 병합이 아니다.

---

## D-02 — 기기 연결 → Configuración › Dispositivos

### 이동 대상 컴포넌트 (현재 위치 확인됨)

| 기능 | 현재 컴포넌트 | 현재 트리거 위치 | 비고 |
|---|---|---|---|
| 판매원 앱 기기 | `src/views/config/ventas/sellers/list/components/VendedorDispositivosModal.tsx` | `SellersList.tsx`(Configuración › Ventas › Vendedores) 의 버튼 | 매장별 N명 판매원 각각의 기기 토큰 |
| 출고(despacho) 앱 기기 | `src/views/ventas-online/components/DispositivosModal.tsx` | `VentasOnlineView.tsx:187` 「Dispositivos」 버튼(사이드바 Venta › Control de Envíos 안) | |
| Galaxy Watch | `src/views/relojes/RelojesCard.tsx` | 이미 `HUB_TABS` 의 `relojes` 키로 Configuración › Avanzado 에 임베드됨(2026-10-05, 8744399b) | **이미 독립 카드 컴포넌트**라 그대로 재사용 가능 — 새로 만들 필요 없음 |

### 설계 메모

`RelojesCard` 는 이미 자립적 카드(자체 fetch, 자체 상태)라 새 `Dispositivos` 탭에 그대로
드롭인 가능하다. `VendedorDispositivosModal`·`DispositivosModal` 은 **매장 전체 기기 목록이
아니라 "선택된 판매원 1명" 또는 "현재 화면 컨텍스트"에 묶인 모달**이므로, 세 카드를 나란히
두려면 두 모달의 기존 트리거(버튼)는 그대로 두고 **딥링크**(`/configuracion?tab=dispositivos`)로
연결하는 쪽이 재작업이 작다 — 로직을 모달에서 뽑아내 탭 전용 카드로 재작성하는 것은 선택지지만
필수는 아니다(분석 문서 3-2 안도 "기존 버튼은 지우지 않고 딥링크로 보낸다"를 권장).

---

## D-03 — Carpetas compartidas 복원

### 코드는 이미 완성돼 있다

- **백엔드**: `api-ventago/src/app/shared-folders/` — 모듈·컨트롤러 2개(`/carpetas-compartidas`,
  `/carpetas-compartidas/admin`)·서비스 3개(`GoogleDriveService`, `SharedFoldersService`,
  `SharedFoldersAdminService`)·모델 3개(`SharedFolder`, `SharedFolderRoleAccess`,
  `SharedFolderAccessLog`)·테스트 5개 spec. 마이그레이션
  `api-ventago/migrations/shared-folders-create.sql` 존재.
- **프런트**: `src/pages/carpetas-compartidas/index.tsx`(직원용 조회, 게이트:
  `allowedApps:['admin'] allowedModules:['configuracion'] allowedFunctions:['carpetas-compartidas']`)
  + `src/pages/configuracion/carpetas-compartidas/index.tsx`(관리용, 같은 게이트) + 뷰 8개
  (`src/views/carpetas-compartidas/`).

### 실제로 막혀 있는 것 — 인프라, 코드 아님

```
GOOGLE_SA_KEY_JSON 환경변수 — 로컬(.env) 없음, 운영(docker exec 확인) 없음, /run/secrets/ 없음
```

`GoogleDriveService` 는 lazy init 이라 이 변수가 없어도 **부팅은 성공**하지만, 실제 API 호출
시(`sa-info`, `folders` 등) **503 Service Unavailable** 을 던진다. `.env.example:76-78` 에
설정 안내가 있다:

```
# Enable Drive API on the project. Share each target folder (or a Shared Drive)
# with the SA email as Editor before registering it in the admin UI.
GOOGLE_SA_KEY_JSON=/run/secrets/google-sa.json
```

### D-03 "살린다"의 실제 범위

1. **메뉴 진입점 추가**(이 Phase 범위) — `/carpetas-compartidas` 를 Herramientas 섹션에,
   `/configuracion/carpetas-compartidas` 를 Configuración 허브(Avanzado, 목업상 「Carpetas
   compartidas」) 탭으로.
2. **기능 게이트 모순**(이 Phase 범위, 발견) — `functions.slug='carpetas-compartidas'`(id=230)
   은 DB 상 `module_id=62`(configuracion) → `app_id=1`(admin) 소속이다. 즉 **admin 앱이 없는
   사용자는 이 기능을 영원히 가질 수 없다** — D-02 처럼 "직원용은 Herramientas 로" 두더라도
   일반 vendedor/cashier 는 admin 앱이 없으면 이 함수 자체를 role_functions 로 부여받을 수
   없다. Herramientas 에 놓고 싶다면 이 함수를 `is_auxiliary` 모듈로 옮기거나(시드 DML) 별도
   함수를 만들어야 한다.
3. **Google 서비스 계정 프로비저닝**(이 Phase 범위 밖, 사람 작업) — GCP 콘솔에서 서비스 계정
   생성 → JSON 키 다운로드 → 로컬 `.env` + 운영 docker secret 등록 → 대상 Drive 폴더를 SA
   이메일에 Editor 로 공유. **Claude 가 Google 계정에 접근할 수 없으므로 이 단계는
   checkpoint:human-verify 로 플랜에 남겨야 한다.** 이게 없으면 메뉴를 붙여도 클릭 시 503 만
   본다.

**권장**: 메뉴는 이 Phase 에서 붙이되, 백엔드 설정이 없는 상태에서도 UX 가 깨지지 않도록
(이미 `shared-folders-admin.service.ts:55` 가 명확한 한국어 아님 스페인어 안내 메시지를 던지는
걸 확인) 그대로 노출. 설정 전까지는 "관리자에게 문의"로 보이는 게 설계 의도와 일치한다.

---

## D-04 — Dashboard ventas 재노출

**정확한 수정 위치**: `ventago-app/src/navigation/menuRegistry.ts:278`

```ts
exclude: ['/dashboards/ventas', '/configuracion/ventas'],
```

`/dashboards/ventas` 를 이 배열에서 제거하면 끝 — DB 권한(`dashboard-venta`)은 이미
살아 있고 vendedor 에게도 부여돼 있으므로(분석 A4) 시드 변경 불필요, **코드 1줄**.

주의: 같은 줄의 `/configuracion/ventas` 는 그대로 둔다(그건 Configuración 허브로 이미
통합된 별도 독립 URL이고 제외 유지가 맞다 — Preferencias/허브 패턴과 동일).

---

## D-05 — ClienteVista·CodigoVista 위치 유지

변경 없음. 분석 문서 §C4/C8 이 제안한 이동(Herramientas → Venta/Producto)은 **채택하지
않는다** — 이 Phase 의 다른 작업에 영향 없음. 이름(ClienteVista, CodigoVista)도 유지하므로
`modules.name` UPDATE 불필요(C4/C12 의 해당 항목 범위 제외).

---

## D-06 — Reportes v2: legacyHref 수정 + `/reportes/asistencia` 추가

### legacyHref 3개의 정확한 원인 (확인됨)

`src/views/reports-v2/registry.ts` 의 `enviado`(246행)·`stock-vistas`(435행)·
`season-turnover`(499행) 엔트리가 각각 `/reportes/enviado`·`/reportes/stock-vistas`·
`/reportes/season-turnover` 를 가리킨다. `src/pages/reportes/` 디렉터리를 전수 확인한 결과
**이 세 경로의 페이지 파일이 존재한 적이 없다**(기존 legacy 페이지 17개는 `ventas, items,
vendedor, clientes-credito, breve-venta, reservado, alertas, facturacion, gastos, dashboards,
cheque-estado, ingreso, stocks, corregido, movidos, fallados` + index 뿐 — `enviado`,
`stock-vistas`, `season-turnover` 는 처음부터 v2 전용 신규 리포트였다).

`legacyHref` 는 `ReportsPreviewPanel.tsx` 가 `bodyComponent` **없을 때만** "Ver versión
clásica" 버튼으로 렌더한다(53행). 세 엔트리 모두 `bodyComponent` 가 있으므로 **지금은 죽은
코드지만, 나중에 bodyComponent 를 제거하면 즉시 404 버튼**이 된다(분석 A12 재확인).

**수정안**: 세 엔트리의 `legacyHref` 값을 실재하지 않는 `/reportes/*` 경로 대신
`/reportes-v2?report=<slug>`(자기 자신, v2 셸)로 바꾼다 — 또는 `legacyHref` 를 `undefined`
로 두고 `ReportsPreviewPanel` 이 폴백 문구("이 보고서는 레거시 버전이 없습니다")를 보이도록
타입을 `legacyHref?: string` 로 선택적화. 후자가 더 정직하다(실제로 레거시가 없으므로).

### `/reportes/asistencia` 추가

페이지는 이미 있다: `src/pages/reportes/asistencia/index.tsx` → `AsistenciaReport` 컴포넌트
(게이트: `allowedApps:['reportes']` 뿐, 세부 함수 게이트 없음). registry 에 새 엔트리를 만들
때 `permissionSlug: 'reporte-asistencia'` 를 쓰려면 **함수 시드가 선행**돼야 한다 — DB 확인
결과 이 슬러그는 **존재하지 않는다**:

```sql
-- 운영 확인 2026-10-05: 0 rows
select id from functions where slug='reporte-asistencia';

-- module_id=16 (dashboard-reportes, app=reportes) 가 다른 23개 reporte-* 함수와 같은 소속.
-- 새 함수도 같은 module_id 로 시드해야 reportes-v2 의 권한 필터 패턴과 맞는다.
```

기존 `reporte-*` 함수 24개 전부 `module_id=16` 이므로 동일 패턴으로 INSERT 하고 admin·
gerente 역할에 `role_functions` 부여(매장 수만큼) — **밤 배포, `-- perm-cache:` 주석 필수**
(DML 이 `role_functions`/`functions` 를 건드림).

즉시 가능한 임시 대안(분석 문서 §4 1단계 권고): registry 등록 전에 Configuración ›
Ventas › Vendedores 화면에 「Asistencia y adelantos」 링크를 먼저 달아 진입점만 살리는
방법도 있다(코드만, 함수 시드 불필요) — 운영에서 `seller_attendance`(16행, 최근
2026-10-02)·`seller_adelantos`(3행)가 실사용 중이므로 우선순위가 높다.

---

## D-07 — 「Control de envíos」 표시명

**코드 확인 결과: 변경 불필요 — 이미 모든 출처가 일치한다.**

| 출처 | 현재 값 |
|---|---|
| `public/locales/es.json` `nav_online_sales` | `"Control de Envíos"` |
| `VentasOnlineView.tsx:168,255` (화면 내 하드코딩 헤더) | `"Control de Envíos"` |
| `src/pages/_app.tsx:154` (브라우저 탭/브레드크럼 타이틀 맵) | `[/^\/ventas-online(\/|$)/, 'Control de Envíos']` |

분석 문서 §C3 이 지적한 "메뉴 등록명은 Ventas Online 인데 화면은 Control de Envíos" 는
**내부 코드 식별자**(`titleKey: 'nav_online_sales'`, `/ventas-online` URL 세그먼트)와
**사용자가 보는 문자열**을 혼동한 것이다 — 내부 식별자가 영어/다른 이름이어도 사용자에게는
문제없다. `en.json`/`ko.json` 은 각각 `"Shipment Control"`/`"배송 관리"` — 이것도 같은
의미라 다국어 정합성 문제 없음(이 프로젝트는 스페인어 단일 운영, REQUIREMENTS.md Out of
Scope "다국어 지원" 참조이므로 en/ko 는 미사용 추정).

**결론**: D-07 은 확인 완료, 실제 코드 변경 작업 없음. 플랜에는 "검증만" 태스크로 반영.

---

## D-08 — Admin 그룹 순서 유지

변경 없음. `menuRegistry.ts` 의 `appOrder` 는 그대로 Admin 최상단 유지.

---

## D-09 — 재발 방지 장치 (허브 게이트 통일 · 주입 항목 필터 · 지원토큰 admin 전용 · 시험 2개)

### 9-1. 허브 탭 게이트 ↔ 단독 페이지 게이트 통일

**메커니즘**: 대상 페이지 파일이 게이트 조건을 **export** 하고, `HUB_TABS` 가 그 값을 import
해서 쓴다. 현재는 각자 손으로 중복 작성돼 있어 어긋난다(확인된 불일치 2건):

| 탭 key | 현재 HUB_TABS 게이트 | 단독 페이지(`/configuracion/...`) 게이트 | 불일치 |
|---|---|---|---|
| `permisos` | `requiredModules: ['configuracion-permisos']` (DB 에 **존재하지 않는 모듈 슬러그** — 확인: 0 rows) | `allowedModules: ['usuarios']` | **B7 확정 — 재현 가능** |
| `generar-token`/`relojes`/`token-soporte` | `requiredApps: ['admin']` 만 (app 슬러그, 역할 아님) | 서버는 `@Auth(ValidRoles.admin)`(watch)/없음(support-token, B6) — **role** 기준 | **B5 확정 — 재현 가능** |

**수정 패턴** (예시, `permisos`):

```ts
// src/pages/configuracion/permisos/index.tsx
export const PERMISOS_GATE = { allowedModules: ['usuarios'] } as const

function PermissionsPage() {
  return (
    <WithAccess {...PERMISOS_GATE}>
      ...
```

```ts
// src/pages/configuracion/index.tsx
import { PERMISOS_GATE } from 'src/pages/configuracion/permisos'
...
{ key: 'permisos', ..., requiredModules: PERMISOS_GATE.allowedModules, render: () => <PermissionsView /> },
```

**역할 기반 게이트(`requiredPrivileged`)는 이미 타입에 존재한다** — `HubTab.requiredPrivileged`
(`configuracion/index.tsx:54`), 이미 `datos-tienda`·`qr` 탭이 사용 중. `WithAccess` 의
`PRIVILEGED_ROLES = ['superadmin','super_admin','admin']`(`src/configs/roles.ts:31`) 과
동일 집합이라 서버의 `@Auth(ValidRoles.admin)`(= admin 또는 superadmin)과 **정확히 일치**한다.
**주의**: `WithAccess` 의 `allowedRoles` prop 은 `isPrivileged` 가 먼저 bypass 하므로
`allowedRoles={['superadmin']}` 로 store admin 을 제외하는 건 **불가능**하다(기존 결함,
MEMORY `withaccess-admin-bypasses-all-gates.md`) — 이 Phase 는 그 함정을 밟지 않고
`requiredPrivileged: true` 만 추가한다(= admin 이상, 기존 서버 가드와 정확히 같은 집합).

```ts
// configuracion/index.tsx 수정 3줄
{ key: 'token-soporte', ..., requiredApps: ['admin'], requiredPrivileged: true, render: ... },
{ key: 'generar-token', ..., requiredApps: ['admin'], requiredPrivileged: true, render: ... },
{ key: 'relojes', ..., requiredApps: ['admin'], requiredPrivileged: true, render: ... },
```

### 9-2. 코드 주입 항목(`menuRegistry.ts`)에 권한 필터

**문제(B1·B2 확정 재현)**: `RegistryNavItem` 의 `action`/`subject` 필드는 Phase 65 CASL
제거 뒤 장식만 남았다(`CanViewNavLink.tsx` 가 children 만 반환, 필터링 없음). `Mi suscripción`
(`menuRegistry.ts:261` 부근, admin 앱만 있으면 보임 ↔ 페이지는 `ver-mi-suscripcion` 함수
요구)과 `Biblioteca de fotos`(producto 앱만 있으면 보임 ↔ 페이지는 `productos` 모듈 요구)가
운영에서 실측 9명(cashier 2+gerente 1, vendedor 6)에게 `/unauthorized` 로 떨어진다.

**수정 패턴**: `RegistryNavItem` 타입에 `requiredModules?`/`requiredFunctions?` 추가,
`navigation/vertical/index.ts` 의 렌더 직전 필터에 적용(허브와 같은 `canSee` 개념을
사이드바에도 이식). 기존 `vis()`(DB 모듈 숨김 전용)와는 별개 레이어로 추가한다 —
`vis()` 는 Preferencias › Menú 숨김이고 이건 **기본 가시성**이다.

### 9-3. support-token API 를 admin 전용으로

**확정된 미해결 항목(B6)**: `support-token.controller.ts:18-37` 의 `generate`/`usage`/
`validate` 전부 `@Auth()`(역할 무관, 로그인만 하면 통과)다. 생성(`generate`)은 분명히
"매장 관리자"용이라고 주석에 적혀 있으면서 가드가 그렇지 않다. `@Auth(ValidRoles.admin)`
으로 좁힌다(`agente.controller.ts` 의 `AccesoVentagoController` 와 동일 패턴 — import 는
이미 존재, `ValidRoles` enum 참조만 추가).

```ts
// 수정 전 — support-token.controller.ts:18-23
@Post('generate')
@HttpCode(HttpStatus.OK)
@Auth()
async generate(@GetUser() user: any) { ... }

// 수정 후
@Post('generate')
@HttpCode(HttpStatus.OK)
@Auth(ValidRoles.admin)
async generate(@GetUser() user: any) { ... }
```

`usage`(조회)는 admin 외 gerente 도 보고 싶을 수 있으나 원 설계 의도가 "매장 관리자"이므로
동일하게 좁히는 게 일관적이다. `validate`(CoolSistema 직원이 호출)는 다른 성격 — 그 호출자가
누구 JWT 로 오는지(아마 별도 CoolSistema 내부 계정)는 확인 불가(LOW), 섣불리 좁히면 외부
시스템이 끊길 위험이 있으므로 **이 Phase 범위에서는 손대지 않음**을 권고.

★ api·app 짝 배포 규칙: `@Auth(admin)` 서버 변경과 프런트 `requiredPrivileged` 는 같은 밤에
배포한다(옛 프런트가 먼저 나가도 403 만 뜨므로 순서는 안전, CLAUDE.md "짝을 이루는 변경" 규칙).

### 9-4. 재발 방지 시험 2개 — 어디에 어떻게 두는가

**제약**: app jest 는 `.tsx` 를 import 하지 못한다(ts-jest 설정에 JSX/React transform 없음,
`package.json` jest 블록 확인 — `transform: {"^.+\\.tsx?$": "ts-jest"}` 뿐, babel-jest 나
React preset 없음). 기존 `menu-paths-exist.spec.ts`/`sidebar-module-contract.spec.ts` 가
증명하는 패턴: **`.tsx` 파일을 import 하지 않고 `fs.readFileSync` + 정규식으로 소스 텍스트를
읽는다.** `sidebar-module-contract.spec.ts` 는 `menuRegistry.ts`(순수 `.ts`, JSX 없음)를
직접 import 하지만, `configuracion/index.tsx` 는 JSX 를 포함하므로 **반드시 텍스트 분석**.

**시험 1 — 허브 「키 → 화면」 고정 (스냅숏)**:

```ts
// src/__tests__/hub-tab-contract.spec.ts
import fs from 'fs'
import path from 'path'

const HUB = path.join(__dirname, '..', 'pages', 'configuracion', 'index.tsx')

// key: 'xxx', ... render: () => <Componente ... 를 쌍으로 추출
const extraerPares = (): Array<[string, string]> => {
  const src = fs.readFileSync(HUB, 'utf8')
  const bloque = src.slice(src.indexOf('HUB_TABS'), src.indexOf('const SECTIONS'))
  const entradas = [...bloque.matchAll(/key:\s*'([^']+)'[\s\S]*?render:\s*\(\)\s*=>\s*<(\w+)/g)]
  return entradas.map(m => [m[1], m[2]])
}

describe('허브 키↔화면 계약', () => {
  it('★ 대조군 — 실제로 여러 쌍을 읽어온다', () => {
    expect(extraerPares().length).toBeGreaterThan(10)
  })

  it('키가 가리키는 컴포넌트가 고정값과 같다 (RETIRADOS 없이 바뀌면 실패)', () => {
    const esperado: Record<string, string> = {
      'datos-tienda': 'DatosTiendaView',
      preferencias: 'PreferenciasPage',
      facturacion: 'FacturacionPrefsView',
      integraciones: 'IntegracionesHubView',
      permisos: 'PermissionsView',
      referidos: 'ReferidosView',
      ventas: 'ConfigurationSalesView',
      productos: 'ConfigurationProductsView',
      envios: 'EnviosConfigView',
      inventario: 'InventarioConfigView',
      qr: 'QrConfigView',
      'prueba-virtual': 'VtoConfigView',
      'tienda-online': 'StorefrontDesignView',
      campanas: 'CampanasView',
      'token-soporte': 'TokenSoporteView',
      'generar-token': 'AccesoVentagoView',
      relojes: 'RelojesCard',
      'importar-legacy': 'ImportLegacyView',
      // RETIRADOS: (없음 — 키를 지우거나 render 를 바꾸면 여기 이유와 함께 옮길 것)
    }
    expect(Object.fromEntries(extraerPares())).toEqual(esperado)
  })
})
```

이 패턴은 `menu-paths-exist.spec.ts` 가 이미 증명한 "텍스트 정규식 + 대조군" 기법을 그대로
재사용한다. 키의 `render` 가 바뀌거나 지워지면 이 시험이 즉시 실패 — A1(8de0d88c 가
`generar-token` 키를 덮어쓴 사고) 재발을 막는다.

**시험 2 — 라우트 진입점 등록 목록 + 대조군**:

`src/__tests__/menu-paths-exist.spec.ts`·`sidebar-module-contract.spec.ts` 가 이미 "레지스트리
path → 페이지 파일 존재"는 검증한다. 이번에 추가할 것은 **반대 방향** — `src/pages/**/*.tsx`
전수를 스캔해 **사이드바에도, 허브에도, 알려진 화면 내 링크 목록에도, `SIN_MENU` 화이트리스트
에도 없는 라우트**를 찾아내는 시험이다.

```ts
// src/__tests__/route-reachability.spec.ts (개요 — 상세 목록은 플랜 단계에서 전수 확정)
import fs from 'fs'
import path from 'path'

const PAGES = path.join(__dirname, '..', 'pages')

// SIN_MENU: 이유와 함께 명시 등록 — 로그인/에러/공개 QR/리다이렉트 전용 등
const SIN_MENU: Record<string, string> = {
  '/login': '공개 — 인증 전 진입점',
  '/unauthorized': '에러 화면',
  '/404': 'Next.js 예약',
  '/reportes': 'redirect-only shell (→ /reportes-v2)',
  // ... 레거시 /reportes/* 17개는 reports-v2 registry 의 legacyHref 로 "등록됨" 처리
  // ... 화면 내 링크로만 닿는 것들(setup-guide.catalog.ts 등)도 출처를 적어 등록
}

// 모든 pages/**/*.tsx 라우트를 나열 → 사이드바(menuRegistry) ∪ 허브(configuracion/index.tsx)
// ∪ reports-v2 registry(legacyHref만이 아니라 실제 slug 라우트) ∪ SIN_MENU 와 대조
```

**대조군 요구(가드레일 원칙 준수)**: 등록을 하나 지운 상태에서 반드시 실패해야 한다 — 즉
새 테스트에는 "알려진 라우트 목록에서 하나를 빼면 실패한다"는 대조군 케이스를 넣는다. 이
저장소는 "대조군 없는 검사는 검사가 아니다"(MEMORY `control-group-can-pass-too.md`) 교훈이
이미 있다.

★ 이 시험의 완전한 `SIN_MENU` 목록(137개 라우트 중 등록 안 된 30+ 개 전부)은 **플랜/실행
단계에서 전수 확정**해야 한다 — 이 연구는 메커니즘과 샘플만 제공한다. 전수 확정 없이 빈
화이트리스트로 커밋하면 시험이 즉시 실패(의도된 것 — 플랜이 하나씩 채워 넣는 작업이 됨).

### 9-5. ★★ 신규 발견 — `/functions` 쓰기 엔드포인트에 역할 가드 없음 (보안, D-09 범위 확장 권고)

**확인된 사실 체인** (추측 없음, 소스 3곳 추적):

1. `src/pages/admin/permisos/index.tsx` — `PermissionsPage` 에 `WithAccess` 자체가 없음
   (다른 superadmin 전용 페이지 `revendedores.tsx`/`vto.tsx`/`soporte-remoto.tsx` 와 다름,
   STATE.md 98-15 가 같은 패턴을 generar-token 에서 이미 한 번 고쳤음에도 이 페이지는
   그대로).
2. `src/views/admin/permissions/components/ModalPermissions.tsx:35,37` —
   `apiConnector.put('/functions/${id}', data)` / `apiConnector.post('/functions', data)`.
3. `api-ventago/src/app/functions/functions.controller.ts:12` —
   `export class FunctionsController extends CrudController<Functions>` — **클래스 레벨도,
   상속된 `create`/`update`/`remove` 메서드도 `@Auth()` 데코레이터가 전혀 없다**
   (`crud.controller.ts` 원본 확인, `@Auth` import 자체가 없음).

**영향 범위**: `functions` 테이블은 DB 확인 결과 **`store_id` 컬럼이 없는 전역 카탈로그**
(`\d functions` — id/name/slug/description/module_id/permission_slug/resource_key 뿐,
126+ 테넌트 공유). 로그인한 어떤 역할(vendedor, cashier 포함)이든 `PUT /functions/:id` 를
직접 호출하면 **전체 시스템의 권한 정의**(어느 slug 가 어느 module 에 속하는지, 어떤
`permission_slug`/`resource_key` 로 매핑되는지)를 바꿀 수 있다. `role_functions`/
`user_functions` 가 이 테이블을 FK 참조하므로, 예컨대 `module_id` 를 바꿔 어떤 함수를
의도치 않은 모듈로 옮기면 전 매장의 가시성 판정이 동시에 바뀐다.

**근본 원인**: `CrudController<T>` 베이스 클래스 자체가 범용이라 `@Auth` 를 강제하지 않는다
(`getAll`/`getById` 는 `user` 없으면 빈 배열/null 반환으로 최소 방어가 있지만, `create`/
`update`/`remove` 는 그 방어조차 role 체크가 아니라 "로그인 여부"만 본다). 이 패턴을 쓰는
다른 컨트롤러도 같은 취약점을 가질 수 있다(이번 조사는 `functions.controller.ts` 만
확인했다 — **CrudController 를 상속하면서 클래스/메서드 레벨 `@Auth` 가 없는 컨트롤러
전수조사는 이 Phase 범위를 벗어나지만, 플랜에 "같은 패턴 재발 방지" 항목으로 남길 가치가
있다**).

**권장 수정**:

```ts
// functions.controller.ts
import { Auth } from '../auth/decorators/auth.decorator';
import { ValidRoles } from '../auth/interfaces/valid-roles';

@Controller('functions')
@Auth(ValidRoles.superadmin)   // ← 전역 카탈로그이므로 매장 admin 도 제외, superadmin 전용
export class FunctionsController extends CrudController<Functions> {
  // getStructure · accionesDeGuardia · full-structure 는 읽기 전용이라
  // 기존 호출부(권한 화면 등)가 깨지지 않는지 별도 확인 필요 —
  // 클래스 레벨 @Auth 를 걸면 이 GET 들도 superadmin 전용이 되므로
  // 다른 화면이 일반 admin 으로 읽고 있었다면 영향 범위를 먼저 확인할 것.
```

★★★ 주의: `@Controller` 클래스 레벨 `@Auth` 데코레이터는 **상속 라우트에는 적용되지만
현재 `getStructure`/`accionesDeGuardia`/`full-structure` 를 호출하는 다른 화면(예:
`/configuracion/permisos` 의 `PermissionsView`, `menuRegistry` 소비 경로)이 superadmin
이 아닌 일반 admin/gerente 로도 읽고 있었다면 그 화면들이 깨진다.** 이 Phase 의 플랜은
**읽기(`GET`)는 기존 범위 유지, 쓰기(`POST`/`PUT`/`DELETE`)만 `ValidRoles.superadmin`
으로 좁히는 메서드 레벨 오버라이드**를 우선 검토해야 한다(클래스 레벨 일괄 적용보다 안전).
MEMORY `class-level-auth-decorator-is-ignored.md`(상속 라우트 37개 중 일부 아직
미정리)도 참조 — 클래스 레벨 데코레이터가 상속 메서드에 실제로 적용되는지 **이 컨트롤러
기준으로 별도 확인**이 필요하다(일반화하지 말 것).

프런트도 `/admin/permisos` 페이지에 `<WithAccess allowedRoles={['superadmin']}>` 를
추가해야 하는데, 위에서 확인했듯 `WithAccess` 의 `allowedRoles` 는 `isPrivileged`
(admin 포함) 를 먼저 bypass 하므로 **"superadmin 만"을 표현할 수 없다** — store admin 을
배제하려면 `WithAccess` 가 아닌 별도 판정(`isSuperAdminRole` 류, `roles.ts` 에
`isPrivilegedRole`/`isSupervisorRole` 과 나란히 존재 여부 확인 필요)을 써야 한다. 이
세부사항은 플랜 단계에서 `roles.ts` 전체를 다시 확인해 확정할 것.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| 허브 탭 가시성 재검증 로직 | `canSeeTab()` 복사해서 새 판정 함수 작성 | 기존 `canSeeTab()` 패턴 그대로 확장(`requiredPrivileged` 필드 추가만) | 이미 superadmin bypass·loading race 두 함정을 겪고 고친 코드(주석에 기록됨) |
| `.tsx` 소스 검사 시험 | 컴포넌트를 렌더해서 시험 작성 시도 | `fs.readFileSync` + 정규식(기존 2개 spec 과 동일 패턴) | ts-jest 에 JSX transform 설정이 없어 `.tsx` import 자체가 실패함(확인됨) |
| CoolSistema 직원 권한 범위 설계 | 이 Phase 에서 새 scope 체계 설계 | `ALCANCES_AGENTE` 확장은 별도 Phase | 이 Phase 는 메뉴 정합성이 목적, 지원 접근 체계 재설계는 범위 초과 |
| Google Drive 연동 재구현 | 새 업로드/프리뷰 API | 기존 `shared-folders` 모듈(이미 완성) | 테스트 5개 포함 완성 코드, 재구현은 순수 낭비 |

---

## Common Pitfalls

### Pitfall 1: 클래스 레벨 `@Auth` 가 상속 메서드에 적용 안 될 수 있다
**What goes wrong:** `FunctionsController` 에 클래스 레벨 `@Auth(superadmin)` 를 걸었는데
`PermissionsView`(일반 admin 이 쓰는 권한 화면)가 `GET /functions/full-structure` 를 못
불러 전체 화면이 깨짐.
**Why it happens:** 클래스 레벨 데코레이터와 상속 라우트의 상호작용은 NestJS 가드 체인에서
직관과 다를 수 있다(MEMORY: 상속 라우트 37개 중 일부가 "클래스 레벨 `@Auth` 무시됨" 결함이
있었음, 일부만 고쳐짐).
**How to avoid:** 쓰기 메서드만 메서드 레벨로 오버라이드해서 좁히고, 읽기는 그대로 둔다.
배포 후 `PermissionsView`·`/admin/permisos` 양쪽을 실제 admin 계정으로 클릭 확인.
**Warning signs:** 권한 화면이 빈 표로 보이거나 403.

### Pitfall 2: 허브 게이트를 "같은 상수"로 통일하면서 서버 가드와 다시 벌어질 수 있다
**What goes wrong:** `requiredModules` 를 페이지에서 import 했는데, 페이지의 `WithAccess`
자체가 서버 가드(`@Auth`/module 필요조건)와 원래부터 달랐다면 "같은 상수"로 통일해도
근본 불일치가 남는다.
**Why it happens:** 이 저장소는 프런트 게이트(`WithAccess`)와 서버 게이트(`@Auth`)가
독립적으로 진화해왔다 — "프론트 플래그는 보안 경계가 아니다"(MEMORY).
**How to avoid:** 9-1/9-3 수정 후 반드시 서버 엔드포인트의 `@Auth` 인자와 프런트 게이트를
나란히 표로 다시 대조(이 연구의 9-1 표처럼).
**Warning signs:** 허브 탭은 보이는데 클릭하면 403 배너.

### Pitfall 3: `SIN_MENU` 화이트리스트가 "일단 다 넣고 시작"이 되면 시험이 무력화된다
**What goes wrong:** route-reachability 시험을 통과시키려고 30+ 개 고아 라우트를 전부
`SIN_MENU` 에 이유 없이 넣으면, 진짜 고아(A2 asistencia 같은)와 의도된 정상 고아(로그인
화면)가 구분 안 된다.
**Why it happens:** 시험 통과가 목적이 되면 화이트리스트가 쓰레기통이 된다.
**How to avoid:** `SIN_MENU` 항목마다 이유를 **문자열로 필수** 요구(타입을
`Record<string,string>` 로, 빈 문자열 금지). 코드 리뷰에서 "레거시, 삭제 후보"처럼
모호한 이유도 반려.
**Warning signs:** `SIN_MENU` 목록이 30줄을 넘으면서 이유가 전부 비슷한 문구.

---

## Code Examples

### `requiredPrivileged` 패턴 (기존 코드에서 검증됨)

```ts
// configuracion/index.tsx:106-125 (발췌, 기존 코드 그대로 — 새로 만들 필요 없음)
const isSuperadmin = isPrivilegedRole(user?.roles)
const canSeeTab = (tab: HubTab) => {
  if (isSuperadmin) return true
  if (tab.requiredPrivileged) return false   // ★ privileged 통과 이후에만 도달하므로 안전
  if (tab.requiredApps && !tab.requiredApps.some(slug => userApps.includes(slug))) return false
  if (tab.requiredModules && !tab.requiredModules.some(slug => userModules.includes(slug))) return false
  return true
}
```

### Tesorería 탭 확장 패턴 (Caja fuerte 추가, `tesoreriaTabs.ts` 는 순수 `.ts` 라 시험 쉬움)

```ts
// src/views/tesoreria/tesoreriaTabs.ts 수정안
export type TesoreriaTabKey = 'estado' | 'registros' | 'cheques' | 'gastos' | 'caja-fuerte'
...
// /caja-fuerte 페이지 게이트가 allowedModules:['caja'] 이므로 has('/caja') 재사용 — 기존 Estado 탭과 동일 기준
if (has('/caja')) list.push({ label: 'Caja fuerte', key: 'caja-fuerte' })
```

### Dashboard ventas 재노출 (1줄)

```ts
// src/navigation/menuRegistry.ts:278
- exclude: ['/dashboards/ventas', '/configuracion/ventas'],
+ exclude: ['/configuracion/ventas'],
```

### `reporte-asistencia` 함수 시드 (패턴, 기존 24개 reporte-* 함수와 동일 구조)

```sql
-- api-ventago/migrations/2026-10-0X-phase99-seed-reporte-asistencia.sql
-- perm-cache: 신규 부여만(회수 없음)이므로 워커 캐시가 낡아도 "더 주지는" 않는다
BEGIN;
INSERT INTO functions (name, slug, module_id, created_at, updated_at)
VALUES ('Asistencia y adelantos', 'reporte-asistencia', 16, now(), now())
ON CONFLICT DO NOTHING;

-- admin·gerente 역할 전체에 부여 (매장 수만큼) — 대상 role 목록은 실행 시점에
-- role_functions 기존 reporte-* 부여 패턴을 복제해 생성할 것 (INSERT ... SELECT)
COMMIT;
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| 지원 토큰 생성이 `@Auth()`(역할 무관) | `@Auth(ValidRoles.admin)` 로 좁힘(D-09 권고, 미적용 상태) | 이 Phase | cashier 가 CoolSistema 접근 토큰을 발급하는 경로 차단 |
| `/admin/generar-token` 게이트 없음 | `WithAccess allowedApps={['admin']}` | a734bd68(2026-10-05, 이 Phase 전) | 이미 적용됨 — 추가 조치 불요 |
| 허브 `generar-token` 키가 토큰/Acceso 두 기능을 겸용 | `token-soporte`/`generar-token` 키 분리 | 353ab400(2026-10-05, 이 Phase 전) | 이미 적용됨 |

**Deprecated/outdated:**
- `/reportes/*` 레거시 17개 리포트 화면: v2 가 기능적으로 전부 대체했으나 CONTEXT D-06 결정에
  따라 **삭제하지 않고 유지**한다(과거 북마크/습관 보존 목적으로 추정, 이 연구는 삭제를
  권고하지 않음).

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Token de soporte 검증(`validateToken`) 뒤 CoolSistema 직원이 실제로 어떤 작업을 수행하는지는 이 저장소 밖(별도 CoolSistema 내부 포털)에 있어 코드로 확인 불가 | D-01 | D-01 의 "완전 통합 불가" 결론이 실제로는 더 유연할 수도, 반대로 더 위험할 수도 있음 — 사용자나 CoolSistema 담당자 확인 필요 |
| A2 | `CrudController` 를 상속하면서 `@Auth` 가 빠진 컨트롤러가 `functions.controller.ts` 외에도 더 있을 가능성(전수조사는 이 Phase 범위 밖) | §D-09 9-5 | 같은 패턴의 보안 결함이 다른 전역 테이블에도 있을 수 있음 — 별도 보안 점검 Phase 권장 |
| A3 | `FunctionsController` 에 클래스 레벨 `@Auth` 를 걸면 `PermissionsView` 등 기존 GET 호출부가 깨지지 않는다고 가정하지 않고, 메서드 레벨 오버라이드를 권고했으나 — `getStructure`/`accionesDeGuardia`/`full-structure` 가 실제로 어느 역할까지 호출하는지는 호출부 전수 확인이 플랜 단계에서 필요 | §D-09 9-5 | 과잉 제한 시 권한 화면이 깨짐, 과소 제한 시 보안 구멍 잔존 |

## Open Questions

1. **D-01 의 UI 통합("Acceso para soporte" 한 화면 두 카드) 채택 여부**
   - What we know: 목업(`menu-propuesta.png`)이 이미 이 형태를 반영했고 분석 문서 §5-Q1 이
     같은 안을 권고.
   - What's unclear: 사용자가 이 UI 통합까지 승인했는지(CONTEXT.md D-01 은 "합칠 수 있으면
     합친다 — 불가하면 근거와 함께 보고"까지만 명시, UI 통합안 자체의 승인 여부는 플랜/논의
     단계에서 재확인 필요).
   - Recommendation: 플랜 단계에서 이 연구의 D-01 절을 제시하고 UI 통합 여부를 확정.

2. **functions 보안 수정의 영향 범위(Pitfall 1)**
   - What we know: 쓰기(`POST`/`PUT`/`DELETE /functions`)에 가드가 없다는 사실은 확정.
   - What's unclear: 클래스 레벨 vs 메서드 레벨 적용 중 어느 쪽이 기존 호출부를 안 깨는지는
     `PermissionsView.tsx`·`menuRegistry` 소비 경로의 실제 역할 요구사항을 플랜/실행
     단계에서 재확인해야 함.
   - Recommendation: 메서드 레벨(쓰기만 제한)로 보수적으로 시작, 배포 후 admin/gerente
     양쪽 계정으로 권한 화면 클릭 검증.

3. **Carpetas compartidas Google SA 키 프로비저닝 책임자**
   - What we know: 로컬·운영 둘 다 미설정, 코드는 완성.
   - What's unclear: 이 키를 누가/언제 발급할지(GCP 콘솔 접근 권한이 있는 사람 — 사용자
     본인 추정).
   - Recommendation: 플랜에 `checkpoint:human-verify` 태스크로 명시, 메뉴 노출은 그와
     독립적으로 먼저 진행 가능(503 메시지가 이미 친절함).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `GOOGLE_SA_KEY_JSON`(Google Drive SA 키) | D-03 Carpetas compartidas 실제 파일 I/O | ✗ (로컬·운영 둘 다 확인) | — | 메뉴는 노출하되 미설정 시 503 안내 메시지로 폴백(이미 구현됨) |
| PostgreSQL 18 (로컬 5432, 운영 5434) | D-06 함수 시드, D-09 해당 없음(코드만) | ✓ | 18 | — |
| slopcheck / npm 신규 패키지 | 해당 없음 — 이 Phase 는 신규 패키지 설치가 없음 | — | — | — |

**Missing dependencies with no fallback:**
- 없음 (Carpetas compartidas 는 폴백 있음 — 위 표 참조)

## Package Legitimacy Audit

**이 Phase 는 신규 외부 패키지를 설치하지 않는다.** 전부 기존 코드(이미 설치된 라이브러리:
`googleapis`, 기존 MUI/Next 컴포넌트)의 배선/게이트 변경이다. slopcheck 실행 불필요.

| Package | Registry | Age | Downloads | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------|-------------|-----------|-------------|
| (해당 없음) | — | — | — | — | — | N/A — 신규 설치 없음 |

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | jest 29.7.0 + ts-jest 29.4.9 (app), jest 29.7.0 + ts-jest 29.2.5 (api) |
| Config file | `ventago-app/package.json` `"jest"` 블록 (별도 jest.config 파일 없음) / api 는 NestJS 기본 |
| Quick run command (app) | `cd ventago-app && npx jest src/__tests__/<파일>.spec.ts --runInBand` |
| Full suite command (app) | `cd ventago-app && npm test` |
| Quick run command (api) | `cd api-ventago && npx jest src/app/functions --runInBand` (변경 모듈 디렉터리만 — 커밋 게이트 관례) |
| Full suite command (api) | `cd api-ventago && npm test` (★ `--maxWorkers=1` 필수, MEMORY `jest-maxworkers-1-required.md`) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| D-04 | `/dashboards/ventas` 가 Venta 그룹 메뉴에 다시 보인다 | unit(정적 분석) | `npx jest src/__tests__/sidebar-module-contract.spec.ts` (기존 시험이 `appMenuConfigs` 를 통해 간접 커버 — exclude 제거 후 재실행해 회귀 없는지 확인) | ✅ 기존 파일 |
| D-06 | `/reportes-v2` 의 `enviado`/`stock-vistas`/`season-turnover` 의 `legacyHref` 가 더 이상 존재하지 않는 `/reportes/*` 를 가리키지 않는다 | unit | 신규, `registry.ts` 를 import 해 3개 slug 의 `legacyHref` 가 `/reportes/enviado` 등이 아님을 단언 | ❌ Wave 0 신규 필요 |
| D-06 | `/reportes/asistencia` 가 reports-v2 목록에 노출된다 | unit | 신규, registry 에 `slug:'asistencia'` 존재 + `permissionSlug:'reporte-asistencia'` 단언 | ❌ Wave 0 신규 필요 |
| D-09-1 | 허브 탭 게이트가 단독 페이지 게이트와 같은 상수를 쓴다 | unit(정적 분석) | 신규 — 각 수정 탭마다 import 출처 텍스트 검사, 또는 간단히 "두 파일이 같은 식별자를 공유"를 grep 으로 확인 | ❌ Wave 0 신규 필요 |
| D-09-4 | 허브 「키→화면」 고정 스냅숏 | unit(정적 분석) | §D-09 9-4 코드 예시 그대로 — `hub-tab-contract.spec.ts` | ❌ Wave 0 신규 필요 |
| D-09-4 | 라우트 진입점 등록 목록 + 대조군 | unit(정적 분석) | §D-09 9-4 — `route-reachability.spec.ts` | ❌ Wave 0 신규 필요 |
| D-09-5 | `POST/PUT/DELETE /functions` 는 비-superadmin 요청을 403 으로 거절한다 | integration(api) | 신규 — `functions.controller.spec.ts` 또는 e2e, superadmin 아닌 JWT 로 403 단언 | ❌ Wave 0 신규 필요 |
| D-09-3 | `support-token generate/usage` 는 admin 아닌 역할을 403 으로 거절한다 | integration(api) | 신규 — `support-token.controller.spec.ts` | ❌ Wave 0 신규 필요 (디렉터리에 기존 spec 없음, 확인됨) |

### Sampling Rate

- **Per task commit:** 변경한 모듈 디렉터리만(`npx jest <경로> --runInBand`, api 쪽 커밋 게이트
  관례와 동일 — `--findRelatedTests` 금지, MEMORY 참조).
- **Per wave merge:** app `npm test` 전체 + api `npm test -- --maxWorkers=1`.
- **Phase gate:** 두 전체 스위트 그린 + 운영 유사 계정(admin, gerente, vendedor, cashier 각
  1개씩, 기존 "권한 실측용 더미 계정 4개" MEMORY 참조)으로 cmux browser 실측 — 정적 분석
  시험이 "리다이렉트"·"렌더 예외"를 못 잡는다고 기존 spec 주석이 명시하므로 반드시 브라우저로
  최종 확인.

### Wave 0 Gaps

- [ ] `src/__tests__/hub-tab-contract.spec.ts` — 허브 키→화면 고정 (D-09 9-4)
- [ ] `src/__tests__/route-reachability.spec.ts` — 라우트 전수 등록 + 대조군 (D-09 9-4)
- [ ] `src/__tests__/registry-legacyhref.spec.ts` 또는 기존 reports-v2 spec 확장 — D-06
- [ ] `api-ventago/src/app/functions/functions.controller.spec.ts` — 쓰기 가드 403 (D-09 9-5)
- [ ] `api-ventago/src/app/support-token/support-token.controller.spec.ts` — admin 전용 403 (D-09 9-3)
- [ ] 허브 게이트 상수 공유를 검증하는 간단한 정적 시험(permisos 등 수정 대상마다) — D-09 9-1

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | 아니오 (기존 JWT 인증 변경 없음) | — |
| V3 Session Management | 아니오 | — |
| V4 Access Control | **예 — 이 Phase 의 핵심** | NestJS `@Auth(ValidRoles.X)` 데코레이터(기존 패턴), 프런트 `WithAccess`/`requiredPrivileged`(기존 패턴). 새 메커니즘 도입 없음, 기존 패턴의 누락분을 메움 |
| V5 Input Validation | 아니오(이 Phase 는 신규 입력 처리 없음) | — |
| V6 Cryptography | 아니오 | — |

### Known Threat Patterns for 이 스택

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| 전역(비-테넌트) 테이블에 역할 가드 없이 CRUD 상속 | Elevation of Privilege / Tampering | 쓰기 메서드에 `@Auth(ValidRoles.superadmin)`(또는 해당 테이블 성격에 맞는 최소 역할) 명시 — `CrudController` 를 상속하는 모든 전역 테이블 컨트롤러에 대해 클래스 또는 메서드 레벨 가드 존재 여부를 플랜에서 점검 항목으로 남길 것 |
| 프런트 게이트만 있고 서버 게이트가 더 넓거나 없음 | Elevation of Privilege | 모든 새/수정 메뉴 항목에 대해 "프런트 게이트 ↔ 서버 `@Auth`" 표를 만들어 대조(이 연구의 9-1/9-5 표 패턴을 플랜·검증 단계에서 반복) |
| 역할 이름과 앱 슬러그가 같은 문자열('admin')이라 혼동 | Tampering(의도 왜곡) | `requiredApps`(앱 소유 여부) 와 `requiredPrivileged`/서버 역할(권한 수준)을 **별개 필드**로 유지 — 이미 `HubTab` 타입이 이렇게 설계돼 있음(혼동 방지 설계는 유지, 실수로 합치지 말 것) |

---

## Sources

### Primary (HIGH confidence — 코드/운영 DB 직접 확인)

- `ventago-app` 워킹트리 HEAD `f0be7c7a` (git log 직접 확인), `api-ventago` HEAD `c060ae2d`
- `ventago-app/src/navigation/menuRegistry.ts` — 전체 구조·`exclude`·`nav_online_sales` 등
- `ventago-app/src/pages/configuracion/index.tsx` — `HUB_TABS` 전체(219줄 전문 읽음)
- `ventago-app/src/pages/admin/generar-token.tsx`, `src/views/soporte/TokenSoporteView.tsx`
- `api-ventago/src/app/support-token/{support-token.controller.ts,support-token.service.ts}`
- `api-ventago/src/app/agente/{agente.controller.ts,agente.service.ts}`,
  `api-ventago/src/app/auth/decorators/agent-access.decorator.ts`
- `api-ventago/src/app/shared-folders/**` (컨트롤러 2·서비스 3·모델 3·spec 5), `.env.example:76-83`
- `api-ventago/src/common/crud/crud.controller.ts`, `api-ventago/src/app/functions/{functions.controller.ts,functions.model.ts}`
- `ventago-app/src/views/admin/permissions/{PermissionsListView.tsx,components/ModalPermissions.tsx}`
- `ventago-app/src/views/reports-v2/{registry.ts,ReportsPreviewPanel.tsx}`,
  `ventago-app/src/pages/reportes/**`(전체 디렉터리 `find` 확인), `src/pages/reportes/asistencia/index.tsx`
- `ventago-app/src/views/tesoreria/tesoreriaTabs.ts`, `src/pages/caja-fuerte/index.tsx`
- `ventago-app/src/views/relojes/RelojesCard.tsx`,
  `src/views/config/ventas/sellers/list/components/VendedorDispositivosModal.tsx`,
  `src/views/ventas-online/components/DispositivosModal.tsx`
- `ventago-app/src/__tests__/{menu-paths-exist.spec.ts,sidebar-module-contract.spec.ts}` (전문)
- `ventago-app/src/configs/{roles.ts,withAccess.tsx}`
- `ventago-app/package.json`(jest 블록), `api-ventago/package.json`(jest 스크립트)
- 운영 Postgres 5434 직접 SELECT(`functions`/`modules`/`apps` 조인, `\d functions`,
  `reporte-*` function 24건, `carpetas-compartidas` function 1건)
- 운영 서버 docker exec(`api_ventago` 컨테이너 env 확인, `GOOGLE_SA_KEY_JSON` 부재),
  로컬 `.env` 확인(동일 부재)
- `.planning/ANALISIS-2026-10-05-menu-estructura.md`(전문), `.planning/phases/.../99-CONTEXT.md`(전문)
- `.planning/sketches/menu-propuesta.png`(이미지 직접 열람)

### Secondary (MEDIUM confidence)

- 없음 — 이번 연구는 전부 1차 소스(코드·DB·운영 서버)로 검증됨.

### Tertiary (LOW confidence — 검증 불가, Assumptions Log 참조)

- CoolSistema 내부 포털이 Token de soporte 검증 후 실제로 수행하는 작업의 범위(D-01 A1)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — 신규 스택 없음, 기존 NestJS/Next.js 패턴 재사용
- Architecture: HIGH — 모든 파일 직접 읽고 라인 번호까지 확인
- Pitfalls: HIGH — 과거 동일 저장소 MEMORY 항목과 직접 대조, 이번 조사에서 1건 신규 확정(보안)

**Research date:** 2026-10-05
**Valid until:** 7일 (이 저장소는 당일에도 메뉴 관련 커밋이 4건 들어갈 만큼 변경이 잦다 —
플랜 착수 직전 `git log --oneline -10`(ventago-app, api-ventago) 으로 이 연구 이후 변경 여부
재확인 권장)
