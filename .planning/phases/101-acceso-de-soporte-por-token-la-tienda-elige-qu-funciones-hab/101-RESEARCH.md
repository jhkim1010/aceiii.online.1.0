# Phase 101: Acceso de soporte por token — 보기전용 용도 + 원격 세션 - Research

**Researched:** 2026-10-08
**Domain:** NestJS 메타데이터 가드(JwtGlobalGuard · @AgentScope) 확장 + Next 13 Pages Router 에이전트 조회 모드 + Phase 41 소켓 게이트웨이 통합
**Confidence:** HIGH (가드 경로·프론트 도달성·비밀 필드는 코드로 직접 확인) / MEDIUM (화면별 API 인벤토리 — 정적 추출이라 동적 캡처로 확정 필요) / LOW (운영 프론트 빌드 플래그, TN 채널 응답 필드)

> 표기: `[VERIFIED: 코드 path:line]` 이 세션에서 파일을 직접 읽어 확인 · `[VERIFIED: ssh]` 운영 서버 읽기 전용 조회 · `[CITED: 파일]` 파일 주석/문서 인용 · `[ASSUMED]` 확인 못 함.
> ★ 줄 번호 주의: 컨트롤러 핸들러 표(§인벤토리)는 데코레이터 정규화 후 추출이라 **줄 번호를 싣지 않는다.** 줄 번호는 직접 읽은 파일(가드·서비스·데코레이터·프론트)만 적었다.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01** 에이전트 접근 코드를 확장한다. 경계는 URL 이 아니라 **핸들러 메타데이터**(`@AgentScope`) — 2026-10-02 codex 원칙 유지. 표시 없는 핸들러는 에이전트에게 403.
- **D-02** 실효 범위 = 매장이 고른 용도 ∩ superadmin 이 그 매장에 허용한 용도 (`alcanceEfectivo` — 교집합, 합집합 금지). 새 용도도 이 규칙을 그대로 탄다.
- **D-03** 테넌트 격리 절대: grant 의 storeId 로만. `X-Store-Id` 와 동시 사용 400 유지.
- 용도 목록: `legacy`(운영 중 변경 없음) · `cert`(운영 중 변경 없음) · 보기전용×Venta · 보기전용×Producto · 보기전용×Factura · 보기전용×Admin (신규, GET 만) · `usuarios_terminales`(운영 중 — 손대지 않음) · **Sesión remota (ver pantalla)** (신규, D-11)
- **D-04** 보기전용 alcance 는 **조회 핸들러에만** 붙는다. 쓰기(POST/PUT/PATCH/DELETE) 핸들러에 보기전용 alcance 가 붙으면 시험이 깨진다 — 대조군 필수(쓰기 핸들러에 일부러 붙인 돌연변이가 죽어야 한다). 조회인데 POST 인 핸들러는 「HTTP 메서드」가 아니라 「상태를 바꾸는가」로 판정하고 **POST-조회는 허용 목록으로 명시**.
- **D-05** 한 핸들러가 여러 용도에 필요할 수 있다 → `@AgentScope` 를 **여러 alcance** 로 확장. 가드는 「grant 의 alcance 중 하나라도 핸들러 목록에 있으면 통과」.
- **D-06** 지원 담당자는 **매장의 일반 화면 그대로** 본다.
- **D-07** 그 화면이 같이 부르는 **공통 조회 API** 는 보기전용 용도들 공통으로 연다 — 화면별 호출 API **전수 인벤토리**가 근거. 인벤토리 없이 「대충 필요한 것」으로 열지 않는다.
- **D-08** 쓰기 버튼은 숨기되 **서버 403 이 경계**다(숨김은 보안이 아니다).
- **D-09** 화면이 범위 밖 API 에서 403 을 받으면 **깨지지 않고** 「이 코드로는 볼 수 없음」을 보여준다(전역 처리 우선, 화면별 땜질 지양).
- **D-10** 「admin 의 GET 전부」가 아니다. 응답이 **비밀을 싣는** 조회는 제외 목록으로 명시·시험 고정: 프린터 API Key, MercadoPago/WP/Drive OAuth 토큰, AFIP 인증서·키, 지원 토큰·접근 코드, 비밀번호 해시, 기기 토큰, webhook 비밀 (+ 조사에서 발견되는 것). 공통 조회 API 도 **응답 필드까지** 대조한다.
- **D-11** (2026-10-08 사용자 추가) Phase 41 원격 지원 세션도 용도 목록의 한 항목. 매장이 코드 발급 시 「Sesión remota」를 체크하면 그 코드로 지원자가 원격 세션(화면 보기, 15분)을 열 수 있다. 원격 세션의 기존 흐름(`api-ventago/src/app/support/` — 고객 요청 → UUID → socket 뷰어)을 접근 코드 체계와 **하나의 진입점**으로 묶는다 — 두 개의 「지원 코드」가 되지 않게. 기존 세션 만료(15분)·store 스코프·뷰어 권한 규칙은 유지.

### Claude's Discretion
- alcance 의 내부 식별자 이름(예: `ver_ventas` · `ver_productos` · `ver_facturas` · `ver_admin`)과 화면 라벨(스페인어).
- 프론트에서 에이전트 세션이 일반 화면에 도달하는 방법 — 조사 결과로 제안.
- 시험 배치(가드 단위 시험 vs 핸들러 메타데이터 전수 시험).

### Deferred Ideas (OUT OF SCOPE)
- Token de soporte 를 접근 코드로 통합·폐기 (D-1) / 쓰기 용도 (D-3) / 지원 담당자 개인별 신원 (D-4) / Phase 100 AI 진단 연결
- 미정(기본값으로 진행, 계획 확인 시 사용자에게 확인): D-5 유효시간 30/120분 유지 · D-6 감사 화면은 기존 이벤트 목록에 alcance·method 노출 · **권한 화면(역할·기능) 조회는 보기전용×Admin 에서 기본 제외**
</user_constraints>

## Summary

장치의 뼈대는 이미 충분하다. `JwtGlobalGuard` 가 핸들러 메타데이터(`@AgentScope`)를 읽어 grant 를 검증하고, 통과하면 **`request.user` 를 grant 의 storeId 로 치환**한다(복제본, 30초 캐시 객체 오염 방지). 그 뒤 `@Auth(역할)` 은 `UserRoleGuard` 의 에이전트 우회로 통과한다. **그러나 `@FunctionGuard`(= `FunctionPermissionGuard`)에는 에이전트 우회가 없다** — 이것이 이번 phase 의 첫 번째 구조적 막힘이다. 판매·상품·프린터·지점 편집 등 GET 중 `@FunctionGuard` 를 쓰는 핸들러(예: `GET /sales/all` = `ver-ventas`, `GET /sales/:id` = `detalle-de-venta`, `GET /print/overview` = `ver-impresoras`)는 에이전트가 grant 를 들고 와도 `FunctionPermissionService.resolvePermission` 에서 역할 행이 없어 **403** 이 된다. 우회는 **가드에만** 넣고 `isAllowed()`(서비스)에는 넣지 않는다 — 서비스는 원가(`PERMISO_VER_COSTO`) 같은 필드 게이팅에도 쓰여서, 서비스에 우회를 넣으면 에이전트가 원가를 보게 된다.

두 번째 막힘은 프론트다. agent@app 의 `/auth/me` 는 `storeId=null` · `structure=[]` 이고, `WithAccess` 는 `structure` 로 판정하며(에이전트는 `PRIVILEGED_ROLES` 가 아니다), 사이드바는 `esAgentePlataforma` 분기에서 고정 메뉴 2~3개만 돌려준다. 게다가 일반 화면 206곳이 `user.storeId` 로 URL 을 만든다. 최소 경로는 **grant 가 활성일 때 `GET /agente/tienda/contexto`(새 엔드포인트, 보기전용 4개 중 하나라도 있으면 통과)가 돌려준 `{storeId, 매장명, alcances, structure(허용 모듈만)}` 를 `AuthContext.user` 위에 겹치는 것**이다. 그러면 사이드바·`WithAccess`·`useHasFunction` 가 전부 기존 `structure` 코드로 동작한다. 쓰기 차단은 서버 403 이 경계이고, 프론트는 `apiConnector` 요청 인터셉터에서 비-GET 을 중앙 차단 + 상시 배너로 처리한다.

세 번째로 D-11: 이 저장소에는 「지원 코드」가 **세 개** 있다(Token de soporte 6자리 · 접근 코드 6자리 — 둘은 같은 `support_tokens` 테이블, `scopes IS NOT NULL` 로 구분 · Phase 41 UUID). Phase 41 은 **소켓 게이트웨이가 HTTP 가드를 안 지나가고**, 뷰어 판정이 `payload.storeId == session.storeId` + `PRIVILEGED_ROLES|support.view` 라서 **agent@app(storeId null, roles ['agent'])는 현재 어떤 경로로도 못 들어간다.** 운영 `REMOTE_SUPPORT_ENABLED` 는 비어 있어(실측) 기능 전체가 꺼져 있다. 이 용도를 열려면 게이트웨이가 `x-agent-grant` 에 해당하는 값을 handshake 로 받아 `decidirAcceso` 를 직접 호출하고(+ 만료·철회 재확인), 그 외 규칙(15분·store 스코프)은 유지해야 한다.

**Primary recommendation:** (1) `@AgentScope(...scopes)` 를 다중 값으로 확장하되 메타데이터는 기존 단일 문자열도 허용(기존 시험 호환) → (2) `FunctionPermissionGuard` 에 **에이전트 grant + 핸들러 AgentScope 가 있을 때만** 통과하는 분기 추가(서비스 `isAllowed` 는 건드리지 않는다) → (3) 핸들러 메타데이터 **런타임 열거 시험**(Reflect, 프로토타입 체인 포함 — 상속 라우트가 소스에 안 보인다)과 비밀 제외 목록 시험을 대조군·돌연변이와 함께 먼저 만들고 → (4) 백엔드 인벤토리 기준으로 GET 핸들러에 scope 를 붙이고 → (5) 프론트 컨텍스트 겹치기 + 403 코드 구분.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| 용도(alcance) 목록·라벨의 단일 출처 | API (`agent-access.decorator.ts` · `agente-rules.ts`) | Frontend 복제(`agente-logic.ts`, 코드 발급 화면) | 두 저장소라 물리적 단일 출처 불가 → 양쪽 일치 시험 필요 |
| 접근 판정(grant·scope·만료·철회) | API `JwtGlobalGuard` + `decidirAcceso` | Gateway(소켓)는 같은 함수를 직접 호출 | 판정은 한 곳. 소켓은 HTTP 가드를 안 지난다 |
| 쓰기 거부(보기전용) | API (핸들러에 보기전용 scope 가 **안 붙는 것** + 시험) | Frontend 인터셉터는 UX 보조 | 프론트 플래그는 보안 경계가 아니다 |
| 비밀 필드 제외 | API (응답 직렬화/attributes 포함목록) | — | 응답 필드까지 서버가 책임 |
| 일반 화면 도달(메뉴·게이트·storeId) | Frontend (`AuthContext` 겹치기 + 사이드바 분기) | API `GET /agente/tienda/contexto` | `/auth/me` 는 grant 를 모른다(@AgentePermitido) — 별도 엔드포인트 |
| 「이 코드로는 볼 수 없음」 표시 | Frontend `api.service.ts` 인터셉터 + `api-error-presentation.ts` | API 가 403 에 `code` 를 실어 구분 | 현재 403 메시지만으로는 만료/범위밖/미표시 구분 불가 |
| 원격 세션(화면 보기) | API Gateway(`/support` 네임스페이스) | Frontend `/soporte/visor` · `useRemoteSupport` | 라이브 데이터는 소켓, 권한은 grant |
| 감사(무엇을 봤나) | DB `support_access_events` | Acceso de Ventago 화면 | 이벤트 홍수 대책 필요(§Pitfalls) |

## Standard Stack

신규 외부 패키지 **없음.** 기존 스택만 쓴다.

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `@nestjs/core` Reflector / `SetMetadata` | ^11 [VERIFIED: api-ventago/package.json] | `@AgentScope` 메타데이터 | 기존 장치와 동일 |
| Sequelize raw query (`QueryTypes.SELECT`) | 기존 | `decidirAcceso` 확장 | 기존 코드가 raw SQL |
| socket.io + `RedisIoAdapter` | 기존 [VERIFIED: main.ts:24,81-84] | 원격 세션 | 이미 가동 |
| jest 29 + ts-jest | ^29.7 [VERIFIED: package.json] | 시험 | 기존 |
| `typescript` ^5.7 (api) / 5.0.4 (app) | 기존 | (선택) 소스 AST 검사 | 이미 devDependency |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| 런타임 Reflect 열거 시험 | 소스 정규식/AST 스캔 | 소스 스캔은 `CrudController` 상속 라우트를 못 본다(데코레이터가 부모에 있음 — memory `class-level-auth-decorator-is-ignored`). 보조로만 |
| `FunctionPermissionGuard` 에 우회 | `isAllowed()` 에 우회 | 서비스에 넣으면 필드 게이팅(원가)까지 열린다 → **금지** |
| 합성 `structure` 겹치기 | 에이전트를 `PRIVILEGED_ROLES` 로 취급 | 특권 취급은 `WithAccess` 전 게이트 우회(`withaccess-admin-bypasses-all-gates`) + 쓰기 UI 활성 → 금지 |

**Installation:** 없음.

## Package Legitimacy Audit

이 phase 는 외부 패키지를 설치하지 않는다. **해당 없음** (slopcheck 불필요). 새 의존성이 필요해 보이면 계획 단계에서 `checkpoint:human-verify` 로 올릴 것.

## Architecture Patterns

### System Architecture Diagram

```
 [agent@app 브라우저]                                   [매장 admin 브라우저]
   로그인(JWT roles=['agent'], storeId=null)               Configuración › Acceso de Ventago
   ↓ POST /agente/canjear {codigo}                         POST /acceso-ventago/codigo {alcances,minutos}
   ↓  → grant.key(UUID) → sessionStorage 'ventago.agentGrant'   → support_tokens(token_hash, scopes[])
   ↓ apiConnector 가 모든 요청에 x-agent-grant 부착 (api.service.ts:123-128)
   ▼
 ┌─────────────── NestJS HTTP ────────────────────────────────────────────────┐
 │ ProxyThrottlerGuard → JwtGlobalGuard (APP_GUARD, app.module.ts:365-373)    │
 │   @Public? → 통과                                                           │
 │   passport(JWT) → agente? = roles∋'agent' ∧ storeId=null ∧ !superadmin     │
 │   decidirAgente():                                                         │
 │     scope = reflect(@AgentScope)   ← 없으면 false → (끝에서 403)           │
 │     X-Store-Id 동시 → 400                                                  │
 │     decidirAcceso(userId, grantKey, scope[]) 한 번의 SQL                   │
 │        grant 유효·미철회·미만료 ∧ agent active ∧ store 미삭제               │
 │        ∧ scope ∈ grant.scopes ∧ agent_action_policies(scope).enabled        │
 │     registrarEvento('permitido'|'denegado')  ← 핸들러 전에 await           │
 │     request[AGENT_GRANT_DECISION]={userId,grantId,storeId,scope}           │
 │     request.user = {...user, storeId=grant.storeId, agentGrantId}          │
 │   TenantContext.resolve(storeId=grant.storeId, isSuperAdmin=false)         │
 │ ──── 라우트 가드 ────                                                      │
 │   @Auth(roles): passport 재실행(JwtStrategy.validate 가 decision 재적용)   │
 │       UserRoleGuard: decision ∧ AgentScope → return true (역할 무시)       │
 │   @FunctionGuard: FunctionPermissionGuard → ★우회 없음 → 403 (현재)        │
 │       ⇒ 이번 phase: decision ∧ AgentScope → return true  (가드에만)        │
 │   커스텀 가드(PermissionGuard·SharedFolderAccessGuard·SetupGuideRoleGuard…)│
 │       ⇒ 그 라우트에는 보기전용 scope 를 붙이지 않는다                      │
 │ ──── 핸들러 → 서비스(Sequelize 훅이 store 강제) → 응답(비밀 필드 제외)     │
 └────────────────────────────────────────────────────────────────────────────┘

 [소켓 /support] handleConnection: JWT 만 검증 (HTTP 가드 안 지남)
    payload.storeId=null(agent) → 현재 viewer:join 전부 거부
    ⇒ 이번 phase: handshake 에 x-agent-grant 상당 값 → decidirAcceso(…,'sesion_remota')
                  → client.data.storeId=grant.storeId · 주기 재확인(setInterval) · 이벤트 기록
```

### Recommended Project Structure
```
api-ventago/src/
├── app/auth/decorators/agent-access.decorator.ts   # ALCANCES_AGENTE + @AgentScope(...다중) + 정규화 헬퍼
├── app/auth/guards/function-permission.guard.ts    # 에이전트 분기 (서비스 isAllowed 는 불변)
├── app/auth/guards/jwt-global.guard.ts             # 다중 scope · 403 code 구분
├── common/tenant/agent-grant.ts                    # decidirAcceso(다중 scope, 일치 scope 목록 반환)
├── app/agente/agente-rules.ts                      # ETIQUETA_ALCANCE · 보기전용 집합 · 제외 목록 상수
├── app/agente/agente.controller.ts                 # GET /agente/tienda/contexto (신규)
├── app/support/support.gateway.ts · support.service.ts  # 에이전트 viewer 경로
├── migrations/2026-10-XX-a-agente-alcances-ver.sql # CHECK 확장 + 정책 시드
└── (시험) app/auth/guards/agent-readonly-scopes.spec.ts, test/mutantes/agente-ver.json
ventago-app/src/
├── services/agent-grant.ts           # + alcances/storeId 보관(sessionStorage), 모드 판정
├── context/AuthContext.tsx           # 에이전트 모드 겹치기
├── navigation/vertical/index.ts      # esAgentePlataforma 분기에 grant 모드 병합
├── services/api.service.ts           # 비-GET 중앙 차단 · 403 code 구분
├── services/api-error-presentation.ts# 「이 코드로는 볼 수 없음」
└── views/agente/agente-logic.ts · views/acceso-ventago/AccesoVentagoView.tsx # 용도 목록
```

### Pattern 1: 다중 scope — 기존 시험 호환을 유지하는 형태
**What:** `@AgentScope('cert')`(단일)는 그대로 문자열로 저장, 다중은 배열로 저장하고 읽는 쪽이 `scopesDe(meta)` 로 정규화. 기존 시험이 `Reflect.getMetadata(AGENT_SCOPE_KEY, fn)` 를 `toBe('legacy')` 로 단언하고(`legacy-import/admin-role.guard.spec.ts:105`), `jwt-global.guard.spec.ts` 가 `{[AGENT_SCOPE_KEY]: 'cert'}` 문자열을 주입하며(`:188,201,214…`), `agent-grant.spec.ts` 가 SQL 문자열 `'p.action = $3 AND p.enabled'` · `'$3 = ANY (g.scopes)'` 와 bind `[KEY,50,'cert']` 를 단언한다 [VERIFIED]. 메타데이터 형태/SQL 을 바꾸면 이 시험들을 같이 고쳐야 한다 — **고치는 것은 허용되지만 의도적으로 갱신**할 것.
**Example:**
```typescript
// Source: agent-access.decorator.ts (현재) 를 확장하는 제안
export const ALCANCES_VER = ['ver_ventas','ver_productos','ver_facturas','ver_admin'] as const;
export const ALCANCES_AGENTE = ['cert','usuarios_terminales','legacy',...ALCANCES_VER,'sesion_remota'] as const;

export const AgentScope = (...scopes: [AlcanceAgente, ...AlcanceAgente[]]) =>
  SetMetadata(AGENT_SCOPE_KEY, scopes.length === 1 ? scopes[0] : scopes);

export const scopesDe = (meta: unknown): AlcanceAgente[] =>
  (Array.isArray(meta) ? meta : meta ? [meta] : []).filter(esAlcanceAgente);

/** 공통 조회 API 용 — D-07 */
export const AgentScopeVer = () => AgentScope(...ALCANCES_VER);
```
**decidirAcceso 다중화 요점:** `$3::text[] && g.scopes`(교집합) + 정책 조인은 `p.action = ANY($3::text[]) AND p.enabled` + **일치한 scope 목록을 반환**(`matched: string[]`). `DecisionAgente.scope`(단수)를 `scopes`(복수)로 바꾸고, `puedeImportarLegacy` 는 `d?.scopes.includes('legacy')` 로 — 핸들러가 `['legacy','ver_admin']` 같은 목록일 때 decision 이 `ver_admin` 만 골라 `legacy` 판정이 틀어지는 것을 막는다(**단수 scope 를 계속 쓰면 생기는 실제 함정**). `support_access_events.scope` 는 `VARCHAR(30)` [VERIFIED: migrations/2026-10-02-a:…] → 이벤트에는 **일치한 첫 scope 하나**만 기록(배열 join 은 30자 초과 가능).

### Pattern 2: FunctionPermissionGuard 에이전트 분기 (가드에만)
```typescript
// function-permission.guard.ts — canActivate 맨 앞 (required 읽은 직후)
// UserRoleGuard(user-role.guard.ts:51-61) 와 같은 판정. getAllAndOverride 로 JwtGlobalGuard 와 같은 읽기 방식.
const request = context.switchToHttp().getRequest();
if (
  request?.[AGENT_GRANT_DECISION] &&
  scopesDe(this.reflector.getAllAndOverride(AGENT_SCOPE_KEY, [context.getHandler(), context.getClass()])).length
) {
  return true; // 역할이 아니라 grant 가 연다 — 단, isAllowed()/필드 게이팅은 안 탄다(에이전트는 원가 못 봄)
}
```
- ★ `FunctionPermissionGuard` 는 `reflector.get(FUNCTION_METADATA_KEY, context.getHandler())` **핸들러만** 읽는다(`function-permission.guard.ts:26-30`). `AGENT_SCOPE_KEY` 는 JwtGlobalGuard 와 똑같이 `[handler, class]` 로 읽어야 두 가드가 갈라지지 않는다.
- ★ `@FunctionGuard` 안의 `AuthGuard('jwt')` 는 passport 를 **다시** 돌린다 → `JwtStrategy.validate` 가 decision 을 재적용(`jwt.strategy.ts:98-106`)하므로 `request.user.storeId` 는 유지된다. 그러나 **decision 은 request 의 Symbol 에 있어야만** 이 분기가 선다 — `request[AGENT_GRANT_DECISION]` 으로 읽을 것(`decisionAgenteDe(req, user.id)` 도 가능 — `admin-role.guard.ts:47` 전례, userId 일치까지 보므로 더 안전).

### Anti-Patterns to Avoid
- **`isAllowed()` 에 에이전트 우회 추가:** 필드 게이팅(`products.controller.ts:102`, `cotizacion.controller.ts:108,162`, reports `isAllowedStrict`)까지 열려 원가·이익이 새 나간다.
- **클래스 레벨 `@AgentScope`:** 상속·오버라이드와 섞여 의도치 않은 라우트까지 연다. 핸들러 레벨만 쓰고 시험으로 클래스 레벨 금지.
- **「admin GET 전부」 일괄 부착:** D-10. 부착은 인벤토리의 **포함 목록**으로만(제외 목록이 아니라). `emisor-campos-sensibles.ts`(`CAMPOS_SENSIBLES_EMISOR`) 가 이미 같은 철학의 전례다 [VERIFIED: afip.controller.ts `listIssuers`].
- **에이전트에게 `roles` 를 admin 으로 위장:** `WithAccess` 의 `isPrivileged` 가 전 게이트를 우회한다.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| grant 검증 | 가드/게이트웨이마다 따로 SQL | `decidirAcceso`(다중화) 하나 | 판정이 갈라지면 한쪽이 철회·만료를 놓친다(codex 2026-10-02 P1 「UNA sola decisión」) |
| 역할 판정 위장 | `user.roles` 에 admin 주입 | `AGENT_GRANT_DECISION` + `scopesDe` | 우회가 퍼진다 |
| 응답 비밀 제거 | 컨트롤러마다 delete | 모델 `toJSON` redact(StoreConfig·StoreWhatsappConfig 전례) 또는 `attributes.exclude`+포함목록 | 새 컬럼이 늘 때 자동으로 새는 것 방지 |
| 핸들러 전수 | 소스 grep | `Reflect.getMetadata('method'/'path')` 를 프로토타입 체인으로 | 상속 라우트(CrudController 37개) |
| 세션 만료 타이머(소켓) | 크론 | 소켓별 `setInterval`(워커 로컬) | 비리더 워커는 크론이 전부 삭제된다(memory `non-leader-workers-lose-all-crons`) |

**Key insight:** 이 phase 의 위험은 기능 구현이 아니라 **「열린 면적」을 세는 방법**이다. 열린 핸들러 집합을 시험이 코드에서 직접 계산해야 하고, 그 집합의 응답 필드를 따로 계산해야 한다.

## 1. 현재 에이전트 가드 경로 (정밀)

| 단계 | 위치 | 동작 |
|---|---|---|
| 전역 가드 등록 | `app.module.ts:365-373` | `APP_GUARD` 2개: `ProxyThrottlerGuard` → `JwtGlobalGuard` (이 둘뿐) |
| @Public | `jwt-global.guard.ts:63-70` | 핸들러→클래스 순 `getAllAndOverride`. true 면 즉시 통과(아래 §6) |
| 에이전트 판정 | `jwt-global.guard.ts:83-95`, `tenant-user.util.ts` `isPlatformAgentUser` | `storeId===null ∧ !superadmin ∧ roles∋'agent'` |
| @AgentePermitido | `:86-91` | 있으면 grant 없이도 통과(`/auth/me`, 코드 교환, 받은편지함 …) — `:158-166` 에서 storeId 없이 조기 return |
| 메타 읽기 | `:190-194` | `getAllAndOverride<AlcanceAgente>(AGENT_SCOPE_KEY,[handler,class])`. 없으면 `false` |
| 충돌 검사 | `:205-209` | `X-Store-Id` 동시 → 400 |
| 판정 | `:211-226`, `agent-grant.ts:55-76` | 한 SQL. 실패 시 `denegado` 이벤트 + 403 「No tenés un acceso vigente…」 |
| 감사 | `:228-245` | **핸들러 전에 await.** 실패 시 GET 은 통과(로그만), 쓰기는 403 |
| 치환 | `:247-259` | `request[AGENT_GRANT_DECISION]={userId,grantId,storeId,scope}` + `request.user={...user, storeId, actingAsStoreId, agentGrantId}` |
| 테넌트 | `:121-127` | `TenantContext.resolve({storeId, isSuperAdmin:false})` → 격리 훅 강제 |
| 미표시 핸들러 | `:168-174` | 에이전트가 storeId 없이 여기 오면 「Tu cuenta no tiene tienda asignada」 403 (**grant 가 있어도** — 헤더는 무시됨) |
| `@Auth(roles)` | `auth.decorator.ts:7-12` → `AuthGuard('jwt'), UserRoleGuard` | passport 재실행 → `JwtStrategy.validate:98-106` 가 decision 재적용 |
| UserRoleGuard | `user-role.guard.ts:51-61` | **decision ∧ 핸들러 AgentScope → true**(역할 무시). `agente.spec.ts:~340` 이 고정 |
| `@FunctionGuard` | `function-guard.decorator.ts:79-88` → `AuthGuard('jwt'), FunctionPermissionGuard` | **에이전트 우회 없음.** `function-permission.guard.ts:25-42` → `FunctionPermissionService.isAllowed` → `resolvePermission:113-201`: `UserRole.findOne({userId})` → agent 의 `roles.store_id IS NULL` 행 → `RoleFunction where storeId=user.storeId`(grant 매장) → 없음 → `false` → 403 |
| 역할 가드 전례 | `legacy-import/admin-role.guard.ts:41-50` | `decisionAgenteDe(req,user.id)` + `d?.scope==='legacy'` — **가드가 grant 를 인정하는 유일한 전례** |

**일반 FunctionGuard GET 이 에이전트에게 통과하려면:** (a) 그 핸들러에 `@AgentScope(...)`, (b) `FunctionPermissionGuard` 에 위 분기. 둘 다 필요하다. `@Auth(roles)` 핸들러는 (a) 만으로 된다. 가드가 없는 핸들러(전역 JWT 만)도 (a) 만으로 된다.
**커스텀 가드:** `PermissionGuard`(permissions/approval 컨트롤러 — 역할 PRIVILEGED 기준), `SetupGuideRoleGuard`, `SharedFolderAccessGuard`, `StoreThemeEditGuard`, `MobileScopeGuard`, `VendedorDeviceGuard`/`DespachoDeviceGuard`(기기 키) 는 각자 판정한다 → **이 라우트들은 보기전용 scope 대상에서 제외**(권한 화면은 D 기본 제외와도 일치).

## 2. 프론트 도달성

**현황 [VERIFIED]:**
- `api.service.ts:123-128` 요청 인터셉터가 `getAgentGrant()` 가 있으면 **모든 요청**에 `x-agent-grant` 부착. `getHeaders()`(`:330-331`)도 동일. → 일반 화면의 API 호출도 헤더는 이미 실린다.
- agent@app 로그인 후 `getRedirectUrl`(`AuthContext.tsx:44`) · `getHomeRoute.tsx:8` → `/admin/pedidos`. URL 직접 입력으로 `/ventas` 등에 **갈 수는 있다**(Next 라우팅에 차단 없음).
- `/auth/me`(`auth.controller.ts:46`, `@AgentePermitido` 만 — `@AgentScope` 아님)는 grant 를 무시. `auth.service.ts:926-1060`: 에이전트는 `isSuperadmin` 도 `user.storeId` 도 아니므로 `structure=[]`, `storeId=null`. 사이드바 주석도 「structure vacío a propósito」(`navigation/vertical/index.ts:327`).
- `WithAccess`(`configs/withAccess.tsx:33-117`): `isPrivileged`(roles∩`PRIVILEGED_ROLES` = superadmin/super_admin/admin) 아니면 `allowedApps/Modules/Functions` 를 `user.structure` 로, `allowedRoles` 를 `expandRoleAliases(user.roles)` 로 판정 → 에이전트는 전부 `/unauthorized`. 예: `/facturacion` 은 `allowedRoles={SUPERVISOR_ROLES}`(`facturacion/index.tsx`) → 합성 structure 만으로는 **통과 못 한다**(역할 게이트).
- `useHasFunction`(`hooks/useHasFunction.ts`): 특권 역할이 아니면 `user.structure` 의 function slug.
- `AclGuard`(`@core/components/auth/AclGuard.tsx:36-46`): 판정 없음, `/` → 홈 라우트로 replace 만. (`home-route-is-intercepted-by-aclguard`)
- 사이드바: `navigation/vertical/index.ts:327-355` `esAgentePlataforma(rolesArr)` → 고정 항목(Pedidos de tiendas · Acceso a tiendas …) **반환 후 structure 를 안 본다.**
- `user.storeId` 사용 206곳(grep). 에이전트 `user.storeId=null` → `/branch/store/${user.storeId}` 등이 `undefined` 로 호출된다.
- `AgenteAccesoView`(`views/agente/AgenteAccesoView.tsx`): `activo`(grant 선택)는 **컴포넌트 state** — 다른 페이지로 이동하면 사라진다. 키만 sessionStorage.

**최소 경로 (제안):**
1. **grant 모드 저장:** `services/agent-grant.ts` 에 `{key, storeId, tienda, alcances, hasta}` 를 sessionStorage 로 같이 보관(`elegir()` 에서 기록). 모드 판정은 `getAgentGrant()` + 만료.
2. **API:** `GET /agente/tienda/contexto` — `@Auth(ValidRoles.agent)` + `@AgentScopeVer()` (보기전용 4개 중 하나라도) → `{storeId, storeName, aliasName, logoUrl, branches 요약?, alcances, structure}`. `structure` 는 **서버가 만든 허용 모듈만**(아래), `slimStructureForMe` 재사용(`auth.service.ts:207`).
3. **AuthContext 겹치기:** grant 모드면 `user = {...agentMe, storeId, storeName, aliasName, logoUrl, structure}`; `roles` 는 `['agent']` **유지**. `refreshUser` 가 `/auth/me` 를 다시 받아 덮어쓰지 않게 겹치기 단계를 그 뒤에 둔다(`AuthContext.tsx` `refreshUser` ~`:52-59`).
4. **게이트 보정:** `WithAccess` 에 `esAgenteConAcceso` 분기 — `allowedApps/Modules/Functions` 는 합성 structure 로, `allowedRoles` 는 **에이전트 모드에서 건너뜀**(역할 게이트가 아니라 grant 가 열었음), `superadminOnly` 는 **그대로 막음**. (`PRIVILEGED_ROLES` 에 넣지 않는다.)
5. **사이드바:** `esAgentePlataforma` 분기에서 grant 모드면 고정 항목 + 허용 structure 기반 메뉴를 병합(기존 일반 사용자 경로 코드 재사용 — `sidebar-derives-from-structure`).
6. **쓰기 차단(중앙):** `apiConnector` 요청 인터셉터 — grant 모드 + 비-GET + 허용 POST-조회 목록 밖 → 네트워크 없이 거절 + 「Modo solo lectura」. 상시 배너(모드·남은 시간·Terminar). 버튼 개별 숨김은 장꼬리라 **1차 범위에서 제외 권장**(서버 403 이 경계 — D-08).
7. **허용 structure 산출(서버):** 4개 용도 → 모듈 slug 집합의 **명시 상수**(예: ver_ventas → app `venta`: `ventas`; ver_productos → `producto`: `productos`; ver_facturas → `facturacion`(app `venta`); ver_admin → app `admin`: `sucursales`, `usuarios`(목록만), `impresoras`, `configuracion`(하위 기능 중 포함 목록)). **`usuarios` 모듈은 권한 편집 화면과 같은 모듈**(`UsersListView` 가 `/functions/structure`·`/role-functions/:id`·`/user-functions/:id` 를 부른다) → 포함 여부는 질문(§Open Questions).

## 3. 인벤토리 (D-07)

### 3.0 방법과 한계
- 백엔드: 205개 컨트롤러 파일에서 핸들러·가드 추출(1,197 핸들러 중 GET 602). **`CrudController`(`src/common/crud/crud.controller.ts`) 상속 37개 컨트롤러의 상속 라우트는 소스에 안 보여 표에 없다** — 시험은 런타임 Reflect 로 센다. 상속 `@Get('/')`·`@Get(':id')` 는 `@AgentScope` 가 없으므로 에이전트에게 **기본 403(fail-closed)** 이고, 열려면 오버라이드해야 한다.
- 프론트: `views/*` 의 `apiConnector.*` 호출과 `hooks/api/*`(SWR)를 정규식으로 추출. 템플릿/서비스 래퍼/훅을 놓칠 수 있다 → **MEDIUM**.
- ★ **확정은 동적 캡처로:** cmux browser(운영 빌드, memory `cmux-needs-production-build-for-this-app`)로 매장 admin 계정이 각 화면을 열 때의 네트워크 호출을 기록해 표와 대조한다. 에이전트 계정으로 돌릴 때는 `support_access_events` 의 `denegado` 행이 곧 「빠진 공통 API 목록」이다(`registrarEvento` 가 route 를 남김) — **스테이징/로컬에서 grant 를 만들어 화면을 돌린 뒤 `SELECT route,count(*) FROM support_access_events WHERE kind='denegado' …`** 가 가장 싸고 정확한 인벤토리 보정이다.
- 공통 참조(shared)는 아래 §3.5 에 따로 모은다. 표의 「가드」: `FG(slug,action)`=@FunctionGuard, `Auth(…)`=@Auth(역할), `-`=전역 JWT 만, `CLS`=클래스 레벨.

### 3.1 Venta (판매 목록·상세)
| 화면 | 호출 | 핸들러(컨트롤러) | 현재 가드 | 비고 |
|---|---|---|---|---|
| `/ventas` (SalesListView) | `GET /sales/all` | `findFiltered` (sales) | FG(ver-ventas,read) | pageSize 상한 BULK 9999. 포함 |
| 〃 | `GET /sales/daily-summary` · `/sales/daily-stats` | sales | FG(ver-ventas,read) | 포함 |
| 〃 | `GET /online-orders/venta-vista` · `/online-orders/cobros-resumen` | online-orders | Auth(admin,superadmin,gerente,vendedor,envioManager) | 포함. **응답 필드 대조(confirmToken)** |
| 〃 | `GET /expenses/daily-summary` | expenses | Auth(A,S,V,G) | 포함(공통) |
| 〃 | `GET /cash-register/status` · `/cash-register/cierre` · `/box` | cashRegister / box | Auth(A,S,V,G) | **사용자 기준**(`user.id`)이라 에이전트에게는 빈 결과 — 화면은 「카하 없음」으로 보임(한계로 기록) |
| `/ventas/detalle/[id]` | `GET /sales/:id` | `findOneAdmin` | FG(detalle-de-venta,read) | 포함. **Venta·Factura 다중 scope(D-05)** |
| 〃 | `GET /online-orders/:id` | online-orders | Auth(…) | ★ **confirmToken 노출 → 필드 제거 필수**(§4) |
| 〃 | `GET /sales/:id/printers` | `reprintPrinters` | Auth(vendedor,gerente,admin,superadmin) | 조회(프린터 목록). 응답 필드 확인. **`POST /sales/:id/reprint` 는 절대 붙이지 않는다**(무인 인쇄·중복 인쇄 금지, memory `no-duplicate-print-is-absolute`) |
| (제외) | `GET /sales/` (`findAll()` 전체) · `GET /sales/by-store` · `GET /sales/by-store/:storeId` | sales | FG/Auth(superadmin) | URL 의 storeId 를 받는 형태 + 비페이지 — **제외**(redundant) |
| (제외) | `GET /online-orders/:id/confirm-link` | `confirmLink` | Auth(admin,superadmin,gerente,envioManager) | ★ **GET 인데 쓰기+비밀**(§4,§5) |

### 3.2 Producto (목록·상세·재고)
| 화면 | 호출 | 핸들러 | 현재 가드 | 비고 |
|---|---|---|---|---|
| `/productos` (ProductsView) | `GET /products/by-store` · `/products/all` · `/products/by-parent` · `/products/stock-today` | products | Auth(A,S,V,G) | 포함. 원가는 `PERMISO_VER_COSTO` 로 필드 게이팅(에이전트=미보유 → 숨김, **의도된 기본**) |
| 〃 | `GET /products/` · `/products/generic` · `/products/last-created` · `/products/next-serial` | products | Auth() | `next-serial`·`last-created` 가 번호 예약/상태 변경이 아닌지 **확인 필요**(LOW) |
| 〃 | `GET /products/:id/inventory` · `/inventory-by-date` · `/inventory-by-date-branch` · `/live-stock` · `/images` · `/routing-template` | products | Auth() / Auth(A,S,V,G) | 포함 |
| 〃 | `GET /products/:id/delete-impact` | products | FG(eliminar-un-producto,**delete**) | 읽기지만 가드가 delete — 우회 분기 후 열림. **포함 여부는 질문**(삭제 의도 화면 소속) |
| 〃 | `GET /products/price-changes` | products | FG(cambiar-precio-individual,**update**) | 위와 동일 |
| 〃 | `GET /cotizacion/actual` · `/cotizacion/moneda` | cotizacion | Auth() | 공통. `GET /cotizacion/historial` FG(cambiar-precio-individual,read) |
| 〃 | `GET /photo-library` · `/photo-library/destinos` | photo-library | FG(crear-producto,**create**) | 「생성」 가드의 GET — 포함 여부 질문(보통 제외) |
| 설정(productos) | `GET /categories`·`/by-store` · `/subcategories`(+`by-category/:id`,`by-store`) · `/sizes` · `/colors` · `/seasons` · `/origins` · `/suppliers`(`by-store`) · `/price-types`(+`all`) · `/prices/matrix`(가드 `-`) · `/prices/`(Auth A,S,G) | 각 컨트롤러 | Auth(A,S,V,G) 다수 | 공통 참조(§3.5) |
| (제외) | `POST /products/:id/inventory` · `POST /products/print-codes` | products | Auth() | POST — 쓰기/인쇄. D-04 허용목록에도 안 넣는다 |
| 상속 | `CrudController` 상속 `GET /`·`/:id` (products 등) | — | 상속 | `@AgentScope` 없음 → 기본 403 |

### 3.3 Factura (AFIP 전표 목록·상세)
| 화면 | 호출 | 핸들러 | 현재 가드 | 비고 |
|---|---|---|---|---|
| `/facturacion` (FacturacionShell) | `GET /afip/emitidas?date=` · `/afip/pendientes` · `/afip/verificar` · `/afip/notas/pendientes` | afip | Auth(admin,superadmin,gerente,vendedor) / Auth(A,S,G) | 포함. **화면은 `allowedRoles=SUPERVISOR_ROLES` 게이트** — 에이전트 모드 분기 필요(§2-4) |
| 〃 | `GET /afip/issuers`(+`?storeId=`) | `listIssuers` | Auth(A,S,G,V) **+ 이미 `@AgentScope('cert')`** | ★ 이미 cert 용으로 열려 있음 — `['cert','ver_facturas']` 로 확장. `CAMPOS_SENSIBLES_EMISOR`(certSlug·coolUser) 제외 확인됨 |
| 〃 | `GET /afip/issuers/sugerencia` · `GET /afip/issue/opciones` | afip | Auth(admin,superadmin) / Auth(A,S,V,G) | 읽기 |
| 〃 | `GET /afip/vouchers/:saleId/preview` · `/diagnostico` · `GET /afip/vouchers/:id/pdf` | afip | Auth(…) | pdf 는 `outputService.dispatch(output:'pdf', branchId:0)` — **부작용 없음 확인 필요**(MEDIUM) |
| 〃 | `GET /afip/iibb` · `/afip/iibb/xlsx` · `/afip/reportes/excel` · `/afip/reportes/iva-digital` · `GET /afip/externos` | afip | Auth(A,S,G) | 포함 가능(회계 보고). 파일 다운로드라 **대량 반출 면적** — 질문 |
| (제외) | `GET /afip/padron/:cuit` · `/afip/padron/estado` · `/afip/gateway/cuit/:cuit` | afip | Auth(admin,superadmin) | **AFIP 외부 호출**(쿼터·부작용) — 제외 |
| (제외, 이미 cert) | `GET /afip/cert` · `/afip/cert/csr` · `/afip/issuers/certificados` · `/afip/issuers/by-branch/:id` · `/afip/sucursales/:id/emisores` · `/afip/issuers/cuit/:cuit/tiendas` | afip | Auth(…) | **cert 용도 전용**. ver_* 에 안 붙인다(인증서 폴더명=발급 권한) |
| (제외) | `GET /afip/public/voucher/:token/pdf` (@Public, 토큰) | public-pdf | `-` | 공개 경로(§6) |
| 상세 | `GET /sales/:id` | sales | FG | Venta·Factura 다중 scope |

### 3.4 Admin (지점·사용자·프린터·설정)
| 화면 | 호출 | 핸들러 | 현재 가드 | 비고 |
|---|---|---|---|---|
| `/sucursales` (BranchList) | `GET /branch/store/:storeId`(+`?search`) | branch | `-`(전역 JWT 만) | **URL storeId** — 테넌트 훅이 격리하나 핸들러가 `where:{storeId}` 로 직접 쓴다. ★ **`Branch.apiKey` 가 응답에 실림**(§4). 포함 + 필드 제거 |
| 〃 | `GET /branch/`(`findByStore`, Auth()) · `GET /branch/:id/details` · `/branch/price-types-disabled` | branch | Auth()/Auth(A,S,G) | 포함 |
| 〃 | `GET /branch/:id/sin-variantes` | `vistaPreviaSinVariantes` | FG(editar-sucursal,**update**) | 미리보기(읽기) — 우회 분기 후 열림, 포함 여부 질문 |
| 〃 | `GET /box` · `GET /terminal/by-branch/:id` · `/terminal/store/:id` · `/terminal/by-box/:id` | box / terminal | Auth() | 포함 |
| 〃 | `GET /print/agents/:branchId` | print `listAgents` | CLS `AuthGuard('jwt')` | **이미 마스킹**(`maskApiKey` → `apiKeyPrefix`·`hasKey`). 포함 가능 |
| 〃 | `GET /integrations/wp/channels/branch/:id` · `/integrations/wp/channels` | wp-channel | Auth(admin,superadmin,gerente) | `sanitize()` 로 secret 제외(`wp-channel.service.ts:19,65`) — 필드 시험으로 고정 후 포함 가능 |
| `/impresoras` | `GET /print/overview` | print | FG(ver-impresoras,read) | 포함. apiKey 필드 유무 시험 |
| 〃 | `GET /print/terminal/:id/printers` · `/print/thermal-agents` | print | CLS `AuthGuard('jwt')`(핸들러 가드 `-`) | 읽기 |
| `/usuarios` (UsersListView) | `GET /users/store/:storeId` · `GET /users/`(Auth A,S,G) · `GET /users/:id` | users | `-` / Auth | `Users` 기본 스코프가 `password`·`mobilePin` 제외(`users.model.ts:27-29`) |
| 〃 | `GET /functions/structure` · `/functions/acciones-de-guardia` · `GET /role` · `/role/store/:id` · `GET /role-functions/:id` · `GET /user-functions/:id` | functions / role / user-function | `-` / Auth | **권한 구조** — 기본 제외(D 미정 항목). 포함하려면 질문 후 |
| `/configuracion` 허브·하위 | `GET /store/:id`(`-`) · `GET /store-config/:storeId`(`-`, 본인 매장만) · `GET /configuration/by-store`·`/by-key`(CLS `@Auth()`) · `GET /store/:id/fe-documents`(Auth admin,superadmin) | store / config | 혼재 | `StoreConfig.toJSON` 이 `emailApiKeyEnc` 제거(`storeConfig.model.ts:213-217`) |
| 〃 | `GET /store-whatsapp-config/:storeId` | store-whatsapp-config | Auth(A,S,G) | `toJSON` 이 `accessToken` 제거 → `accessTokenSet` 만 — 안전 |
| 〃 | `GET /mercadopago/accounts` · `/wallets` · `/wallets/:id/movements` · `/refunds/sale/:id/attempts` · `/payment-intents/:id` | mercadopago | Auth(…) | `accounts` 는 attributes 화이트리스트(`T-29-02`). 나머지 **필드 시험 필요**(LOW) |
| 〃 | `GET /integrations/commerce/config` · `/integrations/tiendanube/channels` | integrations | Auth(A,S,G) | **TN 채널·commerce config 응답 미확인(LOW)** — 확인 전 제외 |
| 〃 | `GET /campaigns`·`/clients`·`/vto/usage`·`/watch/devices`·`/despacho/devices`·`/sellers/devices` | 각각 | 혼재 | `/sellers/devices`·`/despacho/devices` = **apiKey 노출**(§4) → 제외. `/watch/devices` 는 tokenHash 컬럼 존재 → 응답 확인 전 제외 |
| (제외) | `GET /carpetas-compartidas/*` (files/preview/download) | shared-folders | CLS Auth+SessionGuard+`SharedFolderAccessGuard` | 고객 파일 내용 — 제외 |
| (제외) | `GET /audit-log/*` | audit-log | Auth(A,S,G) | 감사 로그에 사용자 행위·IP — 기본 제외(질문) |
| (제외) | `GET /mercadopago/oauth/start` | mp-oauth | Auth(admin,superadmin) | OAuth 연결 개시(서명된 state, `storeId` 쿼리 입력) — **GET 이지만 상태 개시** |
| (제외) | `GET /support-token/usage` · `/acceso-ventago/*` · `/agente/*` · `/session/*` | — | — | 지원 토큰·접근 코드·세션 |

### 3.5 공통 참조 조회 (D-07 — 보기전용 4개 공통, 다중 scope `@AgentScopeVer()`)
화면 셸·여러 화면이 공통으로 부르는 것. **응답 필드 시험 대상.**
`GET /branch/store/:storeId` · `GET /branch/` · `GET /store/:id`(`-`) · `GET /store-config/:storeId` · `GET /configuration/by-store`·`/by-key` · `GET /payment-methods`(`/all`) · `GET /price-types`(`/all`) · `GET /categories|/subcategories|/sizes|/colors|/seasons|/origins|/suppliers`(+`by-store`) · `GET /cotizacion/actual` · `GET /box` · `GET /terminal/*` · `GET /sellers`(목록만 — `hasPin` 으로 마스킹됨, `sellers.service.ts` map) · `GET /expenses/categories|subcategories`(`all`,`by-store`) · `GET /discounts/all` · `GET /module-alias`(Auth()) · `GET /daily-quotes/today`(@Public — 에이전트 무관).
★ `GET /store/:id` 는 가드가 `-` 이고 `store.controller.ts` 에서 응답 필드를 확인하지 못했다(**LOW — 시험 필수**). `GET /sellers/:id`(`findOne`)는 `pinHash` 를 싣는지 미확인 → **목록만 포함, 단건 제외**.
★ 셸이 부르는 `/auth/me`·`/notices`·`/notas`·`/afip/cert/aviso-tienda` 등은 에이전트 모드에서 **부르지 않게** 프론트가 이미 분기한다(`useNotices.ts:58`, `CertAvisoBanner.tsx:31`, `UserLayout.tsx:378-389`).

## 4. 비밀을 싣는 GET 응답 (D-10) — 제외/제거 대상

| # | 핸들러 | 비밀 필드 | 근거 | 처방 |
|---|---|---|---|---|
| S1 | `GET /online-orders/:id` (+ 목록·보드가 모델을 그대로 반환하는 경로) | `confirmToken`(+`confirmTokenExpiresAt`) — **공개 확인 링크 토큰 = 배송 확인 쓰기 능력**(`/public/entrega/*` @Public) | `online-orders.service.ts:280-293`(`findById` 전체 모델) · `online-order.model.ts:210`. 속성 제외 없음(`grep attributes` 결과 목록 조회에도 없음) | 에이전트 응답에서 필드 제거(모델 `toJSON` redact 또는 서비스 `attributes.exclude`). **일반 사용자에게도 현재 노출 중** — 별도 결함으로 기록 |
| S2 | `GET /online-orders/:id/confirm-link` | `token`·`url` **발급** | `online-orders.service.ts:1340-1370`(`ensureConfirmToken` 가 `order.save()`) | **제외 + 쓰기 GET**. 시험 제외 목록 |
| S3 | `GET /sellers/devices` | 기기 `apiKey`(복사 UI 용) | `sellers.service.ts:214` 주석, `vendedor_devices.api_key` | **제외** |
| S4 | `GET /despacho/devices` | 기기 `apiKey` | `despacho.service.ts:69` 주석 | **제외** |
| S5 | `GET /branch/store/:id` · `GET /branch/` (`findAllByStorePaginated`·`findByStore`) | `Branch.apiKey`(레거시) | `branch.model.ts:45`, `branch.service.ts:63-68,131-136`(속성 제외 없음). **운영 35개 지점 중 non-null 0** `[VERIFIED: ssh]` | 현재 값이 비어 위험은 낮으나 **응답에 필드가 존재**. 공통 API 라 `attributes.exclude:['apiKey']` 또는 toJSON redact. 백업에 평문으로 실려 온 전력(`store-backup-coverage.ts:659-667`) |
| S6 | `POST /print/agents/:id/key` | 프린터 API Key 평문 | `print.controller.ts` `copyApiKey` | POST — 보기전용 대상 아님(핸들러에 scope 안 붙음). 「읽는 POST」 사례로 시험 주석 |
| S7 | `GET /print/agents/:branchId` | (마스킹됨) `apiKeyPrefix` | `maskApiKey` | 안전 — **필드 시험으로 고정** |
| S8 | `GET /afip/issuers*`, `/afip/cert*` | `certSlug`·`coolUser`(= 인증서 폴더 = 발급 권한) | `CAMPOS_SENSIBLES_EMISOR`, `afip.controller.ts` 주석(D-16/W-F2) | `listIssuers` 만 제외 처리. 나머지 emisor 조회는 **ver_* 제외** |
| S9 | `GET /mercadopago/oauth/start` | 서명된 state URL(연결 개시) | `mp-oauth.controller.ts:57` | 제외(상태 개시, `storeId` 쿼리 입력) |
| S10 | `GET /store-whatsapp-config/:storeId` · `GET /store-config/:storeId` | `accessToken` · `emailApiKeyEnc`(암호문) | 모델 `toJSON` 이 제거 | 안전 — redact **시험 고정**(toJSON 이 빠지면 새는 구조) |
| S11 | `GET /integrations/wp/channels*` | `secret`·`secretPrev`·`wcConsumerSecret` | `wp-channel.service.ts:65 sanitize` | 안전 — 필드 시험 |
| S12 | `GET /integrations/commerce/config` · `/tiendanube/channels` | `commerce_channels.secret`·`wc_consumer_secret` | DB 컬럼 존재 | **미확인(LOW)** → 확인 전 제외 |
| S13 | `GET /mercadopago/*`(wallets 등) | `mp_accounts.access_token`·`refresh_token` | DB 컬럼 존재, `accounts` 는 화이트리스트 | `accounts` 외는 확인 전 제외 |
| S14 | `GET /watch/devices` · `GET /store/:id/fe-documents/:kind` · `GET /carpetas-compartidas/*` | 기기 토큰해시 / 신분 서류 / 고객 파일 | `watch_devices.token_hash` | 제외 |
| S15 | `GET /users/*` | `password`·`mobilePin` | `Users` DefaultScope(`users.model.ts:27-29`) | 안전. **`include` 로 들어온 Users 도 기본 스코프를 따르는지** 시험 |
| S16 | 지원 토큰/접근 코드 | `support_tokens.token`·`token_hash`, `support_access_grants.key` | — | `GET /support-token/*`·`/acceso-ventago/*`·`/agente/*` 는 ver_* 대상 아님 |

**DB 전수 카탈로그 (로컬 `information_schema`, 컬럼명 정규식)** — 비밀 후보 컬럼 목록(이 중 위 표에 없는 것은 해당 GET 이 없거나 이번 4개 영역 밖): `active_sessions.session_token` · `admin_device_tokens.*` · `branch_agents.api_key` · `branch_printer_configs.api_key` · `branches.api_key` · `commerce_channels.secret/wc_consumer_secret` · `despacho_devices.api_key` · `despacho_operarios.pin_hash` · `legacy_*lease_token` · `mobile_sessions.active_session_token/fcm_token` · `mp_accounts.access_token/refresh_token` · `notas.secret_hash` · `online_orders.confirm_token` · `pending_registrations.password_hash/token` · `revendedores.password` · `store_configs.email_api_key_enc` · `store_whatsapp_config.access_token` · `subscription_config.mp_access_token/stripe_secret_key` · `Sellers.pin_hash` · `support_tokens.token/token_hash` · `talleres_vendors.pin_hash` · `terminal_devices.device_token` · `users.password/mobile_pin` · `vendedor_devices.api_key` · `watch_devices.token_hash` · `wp_channels.secret/secret_prev/wc_consumer_secret`. **계획 시 같은 쿼리를 다시 돌려 새 컬럼을 대조**(`intel-catalog-can-lag`).
→ **응답 시험 방법:** 핸들러별로 서비스를 mock 해 비밀 필드가 **들어 있는 모델 객체**를 반환하게 하고(대조군), 컨트롤러 응답을 JSON 직렬화한 문자열에서 위 컬럼명(camelCase+snake_case)이 **없는지** 단언. 대조군: redact 를 제거하면 시험이 실패해야 한다.

## 5. 쓰기처럼 보이는 읽기 / 읽기처럼 보이는 쓰기 (D-04)

**GET 인데 상태를 바꾸거나 개시** (제외 목록 — 시험이 「보기전용 scope 가 붙으면 실패」를 단언):
- `GET /online-orders/:id/confirm-link` — 토큰 생성·저장·반환 (S2)
- `GET /mercadopago/oauth/start` — OAuth 연결 개시 (S9)
- `GET /afip/padron/:cuit` · `/afip/gateway/cuit/:cuit` — AFIP 외부 호출(쿼터)
- 확인 필요(LOW): `GET /products/next-serial` · `GET /products/last-created` · `GET /online-orders/next-number`(주석상 「미리보기」) · `GET /cash-register/*`(사용자 기준 조회) · `GET /afip/vouchers/:id/pdf`

**POST 인데 읽기** (허용 목록 후보 — **v1 은 비워 두기를 권장**, 허용 목록 장치만 시험과 함께 만든다): `POST /user-functions/effective/:userId`(권한 — 제외 영역) · `POST /promotions/evaluate-cart`(POS 계산) · `POST /sales/:id/modify/preview`(가드가 modificar-venta/update) · `POST /products/print-codes`(인쇄 — 절대 제외). 허용 목록 파일은 「핸들러 → 이유」 형태로 두고 **목록이 늘 때마다 시험이 열거 결과와 대조**하게 한다.

**GET 가드가 쓰기 권한 슬러그:** `GET /products/:id/delete-impact`(delete) · `GET /products/price-changes`(update) · `GET /branch/:id/sin-variantes`(update) · `GET /photo-library*`(create). `FunctionPermissionGuard` 에 에이전트 분기가 들어가면 **scope 가 붙는 순간** 가드를 통과한다 — 슬러그 이름으로 포함 여부를 판단하지 말고(`inferir del verbo` 실패 전례, `function-guard.decorator.ts:28-33`) 응답이 읽기인지로 판단.

## 6. 메타데이터 가드를 우회하는 경로

| 유형 | 경로(이 영역) | 에이전트 영향 |
|---|---|---|
| `@Public()`(29개) | `GET /daily-quotes/today` · `GET /public/qr-stock/…` · `POST /public/entrega/*` · `GET /afip/public/voucher/:token/pdf` · `GET /mercadopago/oauth/callback` · 웹훅 · `GET /watch/resumen`(`WatchTokenGuard`) | `JwtGlobalGuard` 가 JWT 없이 통과 → 에이전트와 무관. 단 **`@Public` 라우트는 테넌트 가드가 꺼진다**(memory `public-routes-disable-tenant-guard`) — 보기전용 scope 를 `@Public` 핸들러에 붙이지 않는다(시험: Public ∧ AgentScope 금지) |
| 기기 키 가드 | `VendedorDeviceGuard`·`DespachoDeviceGuard` 라우트(`/despacho/orders`·`/sellers/operarios`) | JWT 아님 — 에이전트 무관 |
| 소켓 게이트웨이 | `common/socket/websocket.gateway.ts`(realtime) · `online-orders-board.gateway.ts` · `restaurant-delivery.gateway.ts` · `print.gateway.ts` · `support.gateway.ts` | **HTTP 가드를 지나지 않는다.** 모두 handshake JWT 의 `payload.storeId` 로 방 가입 판정(`websocket.gateway.ts:115`, `board.gateway.ts:59,95`) → agent 는 storeId null → 방 가입 거부. 안전하나 **grant 를 알지 못함**. `support.gateway` 만 D-11 로 grant 인지 필요 |
| SSE | `@Sse(` **0건** [VERIFIED: grep] | 해당 없음 |
| 크론/무인 | 36개 파일에 `@Cron/@Interval`(afip-cert-watch, auto-prod, mp-token-refresh, reports.schedule, outbox …) | 사용자 컨텍스트 없음 — 보기전용 scope 대상 아님. 「전수 가드」 시험은 컨트롤러 열거라 이 경로를 못 본다(memory `controller-enumeration-misses-cron-paths`) → **새로 열리는 것이 컨트롤러 GET 뿐임을 시험 주석에 명시** |
| 상속 라우트 | `CrudController` 상속 37개 | 오버라이드 안 하면 `@AgentScope` 없음 → 기본 403(안전). 시험은 런타임 Reflect 로 전체 열거 |

## 7. 시험 (재사용·확장)

| 파일 | 현재 | 이번 확장 |
|---|---|---|
| `app/auth/guards/jwt-global.guard.spec.ts` (`describe('JwtGlobalGuard — agente de plataforma')` `:129-…`) | `{[AGENT_SCOPE_KEY]: 'cert'}` 문자열 주입 | 다중 scope 배열 · 일치 scope 목록 · 403 `code` 구분 · 「scope 일부만 grant 에 있음」 |
| `common/tenant/agent-grant.spec.ts` | SQL 문자열·bind 단언 | 다중 scope SQL(`&&`/`ANY`) 단언으로 **의도적 갱신** + 반환 형태 |
| `app/agente/agente.spec.ts` | `UserRoleGuard` 우회(`:~330`), `crearAgente` 정책 | 새 alcance 로 정책 시드·`alcanceEfectivo` 교집합 시험 |
| `app/legacy-import/admin-role.guard.spec.ts` (`:73-110`) | 「todos los handlers llevan @AgentScope('legacy')」 — **프로토타입 열거의 모범** | `toBe('legacy')` 유지(단일 문자열 호환이므로 불변) |
| `app/auth/guards/function-permission.guard.spec.ts` | 가드 단위 | **에이전트 분기 + 대조군**(분기 제거 시 실패), 「grant 없는 agent → 403」, 「일반 사용자에겐 변화 없음」, 「AgentScope 없는 핸들러」 |
| `app/print/print-api-key-copy.spec.ts` | `FUNCTION_METADATA_KEY` 를 `Reflect.getMetadata` 로 읽음 | 핸들러 메타 열거 방식의 전례 |
| `ventago-app/src/__tests__/agente-logic.spec.ts` | `etiquetasAlcances` | 새 alcance 라벨·`ALCANCES` 일치 |

**핸들러 메타데이터 열거 시험 설계 (신규, 권장 위치 `app/auth/guards/agent-readonly-scopes.spec.ts`):**
```typescript
// 런타임 열거 — 프로토타입 체인(CrudController 상속) 포함. 소스 grep 이 아니다.
const METHOD = { 0:'GET',1:'POST',2:'PUT',3:'DELETE',4:'PATCH',5:'ALL',6:'OPTIONS',7:'HEAD' }; // RequestMethod enum
function handlersOf(ctrl: Function) {
  const out: { name: string; method: string; scopes: string[] }[] = [];
  for (let p = ctrl.prototype; p && p !== Object.prototype; p = Object.getPrototypeOf(p)) {
    for (const n of Object.getOwnPropertyNames(p)) {
      const fn = p[n];
      if (n === 'constructor' || typeof fn !== 'function') continue;
      if (Reflect.getMetadata('path', fn) == null) continue;           // 라우트가 아님
      out.push({ name: n, method: METHOD[Reflect.getMetadata('method', fn)],
                 scopes: scopesDe(Reflect.getMetadata(AGENT_SCOPE_KEY, fn)) });
    }
  }
  return out;
}
```
검사 4종: ① `ver_*` scope 가 붙은 핸들러는 `method==='GET'` 이거나 `POSTS_QUE_LEEN`(허용 목록)에 있다 ② 제외 목록(§4·§5)의 핸들러는 `ver_*` 가 **없다** ③ `@Public` 핸들러는 어떤 AgentScope 도 없다 ④ 클래스 레벨 AgentScope 가 없다. 입력 컨트롤러 목록은 **영역별 명시 배열**(sales, online-orders, products, afip, branch, print, users, configuration 등 ≈25개) — 205개 전부 import 하면 모델 순환·메모리 문제(memory `jest-rootdir-import-oom`, `model-cycle-makes-constants-undefined`). 컨트롤러 파일 생성 시 목록에 안 넣으면 열리지 않는 쪽이 fail-closed 이므로 안전한 실패 방향이다.
**대조군(필수):** (a) 시험 안에서 임시 클래스를 만들어 `@Post` + `@AgentScope('ver_ventas')` 를 붙인 핸들러를 `handlersOf` 에 넣으면 ①이 **실패해야** 하고, (b) 제외 목록 핸들러에 scope 를 붙인 변형이 ②에서 실패해야 한다. **돌연변이 스크립트** `api-ventago/scripts/mutantes-wp.sh` + `test/mutantes/wp.json` 형식을 복제해 `test/mutantes/agente-ver.json` 로 4종 이상(가드 분기 삭제, 쓰기 핸들러에 scope 부착, `isAllowed` 쪽 우회로 이동, 제외 목록에서 `confirm-link` 삭제)을 둔다. 돌연변이는 `Tests: 0`(컴파일 실패)·`NO_APLICA` 를 「살았다」로 읽지 말 것(memory `mutation-zero-tests-means-compile-error`, `mutant-may-not-have-been-applied`).
**비밀 필드 시험(§4 방식)** · **`decidirAcceso` 가 다중 scope 일 때 한쪽만 grant 에 있어도 통과, 둘 다 없으면 null** · **정책 미시드(agent_action_policies 에 행 없음) → null** (JOIN 이 행 존재를 요구하므로 신규 alcance 는 시드 없으면 영영 거부).

## 8. 프론트 403 처리 (D-09)

**현황 [VERIFIED]:** `api.service.ts:230-236` — 403 ∧ 요청에 `x-agent-grant` → `notifyAgentGrantRejected()` 가 `ventago:agent-grant-rejected` 이벤트를 발행. 그 구독자는 **`AgenteAccesoView` 뿐**이고(`AgenteAccesoView.tsx` `useEffect(addEventListener(AGENT_GRANT_REJECTED_EVENT, onProhibido))`), `onProhibido=perdido()` 는 **grant 를 지우고 화면을 접는다**(`setAgentGrant(null)`). → 이 이벤트를 일반 화면에 그대로 쓰면 **범위 밖 API 하나의 403 이 grant 전체를 종료시킨다.**
`api.service.ts:299-305` — 403 은 이미 `presentApiError` 로 「warning」 배너(`SIN_PERMISO_TITULO`, `api-error-presentation.ts:38`)이고 `errorBus.push`. 서버 403 은 에이전트에게 메시지만 있고 `code` 가 없다(`jwt-global.guard.ts:223-226, :173`).
**제안:**
1. 서버가 403 에 `code` 를 싣는다: `AGENT_SCOPE_DENIED`(유효한 grant 가 있으나 이 핸들러 scope 불일치/미표시) vs `AGENT_GRANT_INVALID`(만료·철회·정책 꺼짐·헤더 없음). 구분을 위해 `decidirAcceso` 실패 후 **같은 키로 「grant 자체가 유효한가」 한 번 더 조회**(실패 경로에서만). 미표시 핸들러 403(`:173`)은 `AGENT_NO_SCOPE`.
2. `api.service.ts`: 에이전트 모드에서 `AGENT_GRANT_INVALID` 만 이벤트(→ 모드 종료·안내), `AGENT_SCOPE_DENIED`/`NO_SCOPE` 는 **전역 비치명 처리**: 배너 문구를 「이 코드로는 볼 수 없음」(`presentApiError` 에 `agentMode` 입력 추가 — 순수 함수라 시험 가능, 호출부 시험으로 인터셉터 배선 고정 [memory `mutation-survivors-mean-callsite-untested`])하고 `silenceErrorToast` 와 무관하게 **화면은 그대로**.
3. SWR 훅의 403: `useApi` 가 에러를 던지므로 각 훅 소비 화면이 빈 상태로 렌더하는지 **샘플 화면 3곳을 동적으로 확인**(ventas·productos·sucursales).
4. `AgenteAccesoView` 의 `perdido` 는 `AGENT_GRANT_INVALID` 만 받도록 이벤트 페이로드에 `code` 를 실어 보낸다 — 지금 시그니처(`new Event`)에는 페이로드가 없으므로 `CustomEvent` 로 바꾼다.

## 9. 이 저장소 특유의 함정 (메모리 근거)

| 함정 | 근거 | 이번 phase 에서 |
|---|---|---|
| 프론트 플래그는 보안 경계가 아니다 | `frontend-flag-is-not-a-security-boundary` | 쓰기 버튼 숨김만으로 끝내지 말 것 — 서버가 비-GET 에 보기전용 scope 를 안 붙임 + 시험 |
| 범위를 넓히면 노출도 넓어진다 | `widening-scope-widens-exposure` | **응답 필드 시험이 핵심** — `SELECT *` 성 모델 반환이 `confirmToken`·`apiKey` 를 싣고 있음(S1,S5) |
| `@Public` 라우트엔 테넌트 가드가 없다 | `public-routes-disable-tenant-guard` | Public ∧ AgentScope 금지 시험 |
| 열거는 크론·소켓을 못 본다 | `controller-enumeration-misses-cron-paths` | §6 에 소켓·크론을 따로 셌다 |
| `@Auth` 가 passport 를 다시 돌린다 | `route-guard-undoes-global-guard-user` | `FunctionPermissionGuard` 분기에서 decision 은 request Symbol 로 읽고 `request.user.storeId` 는 JwtStrategy 가 유지 |
| 클래스 레벨 데코레이터는 무시돼 왔다 | `class-level-auth-decorator-is-ignored` | `FunctionPermissionGuard` 는 핸들러만 읽는다 — 새 분기는 `[handler,class]`. `@Get(':id')` 오버라이드는 **맨 뒤** |
| WithAccess 가 admin 을 전 게이트에서 통과 | `withaccess-admin-bypasses-all-gates` | 에이전트를 PRIVILEGED 로 만들지 말 것. 합성 structure 로 |
| 서명은 인가가 아니다 | `signature-is-not-authorization` | `GET /mercadopago/oauth/start?storeId=` 제외 |
| 중복 인쇄 절대 금지 | `no-duplicate-print-is-absolute` | `POST /sales/:id/reprint`·`/afip/vouchers/:id/reprint`·`/print/*` 에 scope 부착 금지(시험 제외 목록) |
| 통과 ≠ 지켜짐 | `mutation-testing-measures-what-tests-guard`, `source-grep-tests-need-control-groups`, `control-group-can-pass-too` | 열거 시험 + 돌연변이, 소스 검사는 대조군 |
| 사용자 기준 조회가 에이전트엔 비어 보인다 | `caja-money-accumulates-per-box`, `cash-register-id-is-a-session-not-a-drawer` | `/cash-register/*` 는 `user.id` 기준이라 에이전트 화면은 「카하 없음」 — 장애로 오인 금지, 범위 밖 한계로 문서화 |
| 운영 낮 시간 반영 금지 | CLAUDE.md | 마이그레이션·push 는 16시 이후 또는 활동 사용자 ≤5 측정 후 |
| 마이그레이션 파일 존재 ≠ 적용 | `migration-file-is-not-proof-of-application` | CHECK 확장 **양쪽(로컬 5432·운영 5434)** 에서 `\d agent_action_policies` 로 확인 |
| 감사 이벤트 홍수 | `agente.service.ts:193-204` `LIMIT 200` | 일반 화면 1개가 GET 10~30건 → 200건이 한 번 열람에 소진, 쓰기 시도·denegado 가 밀려난다 |

**추가 함정:**
- **정책 시드:** `decidirAcceso` 는 `agent_action_policies` JOIN 이라 신규 alcance 는 **행이 없으면 거부**. `crearAgente` 는 `ALCANCES_AGENTE` 순회로 새 에이전트에 시드하지만(`agente.service.ts:640-649`) **기존 agent@app 에는** 마이그레이션 시드 필요(전례 `2026-10-03-a-agente-alcance-legacy.sql`). 기본 enabled 값은 **질문**(전례는 agent@app TRUE).
- **CHECK 제약:** `agent_action_policies.action` CHECK 를 새 값으로 재생성해야 한다(전례 동일 파일). 안 하면 `crearAgente` 가 500. 마이그레이션 규약(`SET lock_timeout`, `-- perm-cache:` 주석 불필요(권한 테이블 아님), 작은 테이블이라 `-- w4-exempt` 로 NOT VALID 생략 사유 기록, 운영 owner 이전).
- **`politicas()`** 는 `ALCANCES_AGENTE` 순회라 새 값이 자동으로 토글 가능. `listarAgentes` 의 `acciones` 는 정책 행 기준 jsonb — **행이 없는 새 alcance 는 UI 에 안 보인다**(시드로 해결).
- **프론트 목록 3중 복제:** `agent-access.decorator.ts`(API) · `agente-rules.ts ETIQUETA_ALCANCE`(API, `Record<AlcanceAgente,string>` 라 누락은 컴파일 오류) · `agente-logic.ts ALCANCES/ETIQUETAS`(App, 타입 `Alcance` 별도) · `AccesoVentagoView.tsx` 체크박스 하드코딩 · `AgentesAdminView.tsx`. 두 저장소라 한쪽만 고치면 갈라진다(`edit-target-needs-single-source`) → 시험으로 대조.
- **`generarCodigo`:** `alcancesValidos(body.alcances)` 가 `ALCANCES_AGENTE` 순서로 필터 — 새 값은 자동 수용. 그러나 `AgenteService.avisarTienda`(`:387-430`) 의 라벨 매핑도 확인.
- **`@Auth()` 만 있고 `@AgentScope` 가 없는 `/auth/me` 에 scope 를 붙이지 말 것:** 붙이면 에이전트 로그인 직후 `/me` 가 403 이 되어 앱 진입이 막힌다(`/me` 는 `@AgentePermitido` 로 남겨야 함 → 컨텍스트는 별도 엔드포인트).

## Code Examples

### 프론트 비-GET 중앙 차단 (제안)
```typescript
// api.service.ts 요청 인터셉터, x-agent-grant 부착(:123-128) 직후
// ★ UX 보조. 경계는 서버 403 (D-08)
const modoAgente = getAgentGrant() !== null
if (modoAgente && String(config.method ?? 'get').toLowerCase() !== 'get' && !esPostDeLectura(config)) {
  return Promise.reject(Object.assign(new Error('Modo solo lectura'), { agenteSoloLectura: true }))
}
```

### 403 code (서버)
```typescript
// jwt-global.guard.ts decidirAgente 실패 분기 (현재 :216-226)
throw new ForbiddenException({
  message: 'No tenés un acceso vigente de la tienda para esta acción. Pedile un código nuevo.',
  code: valido ? 'AGENT_SCOPE_DENIED' : 'AGENT_GRANT_INVALID',
});
```

## 10. Phase 41 원격 세션 통합 (D-11)

### 10.1 현재 흐름 (end-to-end) [VERIFIED: 코드]
1. **고객이 요청:** `POST /support/sessions`(`support.controller.ts` `create`, `@Auth()`) — 로그인 사용자 누구나 자기 store 세션 생성. `isRemoteSupportEnabled()` 가 false 면 404. `SupportService.createSession`(`support.service.ts:31-63`): `uuid=randomUUID()`, `expires_at=now+15분`(`SUPPORT_SESSION_TTL_MS`, `:9`), `status='waiting'`, `store_id`·`user_id` 는 **JWT 에서**(`req.user`), `support_sessions` 에 저장.
2. **고객 소켓:** 프론트 `useRemoteSupport`(`hooks/useRemoteSupport.ts`) → `acquire('support')`(`realtime/socket-registry.ts:162-167,266-272`, `auth:{token}`) → `customer:start{uuid}`(`support.gateway.ts:159-220`): 세션 존재 · `session.storeId===client.data.storeId ∧ session.userId===client.data.userId`(`:188`) · 만료 아님 → room `support:{uuid}` 가입 + 만료 타이머(`armExpiryTimer`, 최대 15분 클램프 `:390`). 이후 rrweb 이벤트를 `rrweb:event` 로 방송(`:300-320`; `maskAllInputs`+`blockClass:'rr-block'`).
3. **뷰어 인증:** 소켓 네임스페이스 **`/support`**(`:31`), handshake `auth.token`=브라우저 JWT. `handleConnection`(`:50-117`): 플래그 OFF 면 즉시 disconnect(`:52`) · 토큰 없으면 `auth_error` · `jwtService.verifyAsync` 후 `client.data.{userId,storeId=payload.storeId,roles=payload.roles}`. **HTTP `JwtGlobalGuard` 를 지나지 않는다.**
4. **뷰어 join:** `viewer:join{uuid}`(`:223-297`): `canView(userId, roles)`(`support.service.ts:194-233`) = roles∩`PRIVILEGED_ROLES`(`super_admin`,`superadmin`,`admin`)이면 통과, 아니면 `user_branches/role_functions` 또는 `user_functions` 의 **`functions.permission_slug='support.view'`** · **단일 뷰어**(`viewerByUuid` Map, `:255-263`) · `activateSession(uuid, viewerUserId, viewerStoreId)`(`support.service.ts:90-130`): `session.storeId===viewerStoreId` 아니면 `cross_tenant`, 만료면 `expired`, 통과 시 `status='active'`. → `viewer:joined`.
5. **HTTP 보조:** `GET /support/sessions/active`(`assertCanView` = `canView`) · `GET /support/sessions/:uuid`(store 일치만) · `POST /support/sessions/:uuid/end`(store 일치만).
6. **종료:** 고객/뷰어 `session:end`, 고객 소켓 끊김 → `endSession`, 15분 → `EXPIRED`.
7. **프론트 화면:** 고객 `components/support/RemoteSupportLayer.tsx`(`_app.tsx:327`, `REMOTE_SUPPORT_ENABLED` 빌드 env), 대시보드 `pages/soporte/index.tsx`(`GET /support/sessions/active`, 403 시 「권한 없음」), 뷰어 `pages/soporte/visor.tsx`(**UUID 를 사람이 입력**), 메뉴 `canSeeSupport = REMOTE_SUPPORT_ENABLED ∧ roles∩SUPPORT_ROLES(admin,gerente)`(`navigation/vertical/index.ts`).
- ★ **정정:** `pages/admin/soporte-remoto.tsx` 는 Phase 41 세션이 **아니다.** 그것은 **Token de soporte**(`POST /support-token/validate`, `allowedApps=['admin']`, 6자리)의 화면이다. 따라서 현재 「지원 코드」는 **세 가지**: ① Token de soporte(6자리, 의식뿐) ② 접근 코드(6자리 — **같은 `support_tokens` 테이블**, `scopes IS NOT NULL` 로 구분: `agente.service.ts:305`) ③ Phase 41 UUID(사람이 불러줌).

### 10.2 현재 에이전트가 못 들어가는 이유
agent@app JWT: `payload.storeId=null`, `roles=['agent']`. → `viewer:join`: `canView` 거짓(PRIVILEGED 아님·`support.view` 없음) **그리고** `activateSession` 에서 `storeId` 불일치(`cross_tenant`). **superadmin 도 `payload.storeId` 가 null 이면 같은 이유로 못 들어간다**(act-as 는 HTTP 전용). 즉 Phase 41 은 현재 **같은 매장 내 admin/support.view 보유자**만 뷰어가 될 수 있고, 외부 지원자용으로는 설계상 작동하지 않는다. 운영 `REMOTE_SUPPORT_ENABLED` 는 **미설정** `[VERIFIED: ssh docker exec api_ventago printenv → 빈 출력]` → 지금은 세션 생성 404, 소켓 전부 disconnect. 프론트 `NEXT_PUBLIC_ENABLE_REMOTE_SUPPORT` 는 빌드 시점 값이라 확인 못 함 `[ASSUMED: off]`. 기능 활성은 코드 주석상 **보안 게이트(R-4 입력 마스킹 검증 + UAT + 보안결정 승인)** 통과가 전제(`support.config.ts:1-4`) → 이 phase 가 그 게이트를 대신하지 않는다 — **용도 체크박스는 플래그가 꺼져 있으면 숨기고 서버도 거부**할 것(권장).

### 10.3 grant 로 에이전트가 세션을 열고 들어가는 방법 (제안)
- **scope:** `sesion_remota`(D-11). `ver_*` 와 달리 읽기 전용이지만 **라이브 데이터 구독 + 세션 종료(쓰기)** 가 있어 D-04 열거 시험의 `ver_*` 규칙 대상이 아니다 — 별도 규칙(핸들러 3개: `list`, `detail`, `end`)으로 시험.
- **HTTP(`GET /support/sessions/active`, `…/:uuid`, `POST …/:uuid/end`):** 핸들러에 `@AgentScope('sesion_remota')`. 이 컨트롤러는 `@Auth()`(역할 없음) → `UserRoleGuard` 는 이미 통과하므로 분기 추가 불필요. `assertCanView` 만 에이전트 decision 을 인정하도록 변경(`decisionAgenteDe(req,user.id)?.scopes.includes('sesion_remota')`). `session.storeId !== user.storeId` 검사는 grant 가 `user.storeId` 를 치환하므로 그대로 동작(테넌트 격리 유지).
- **소켓(`viewer:join`):** handshake `auth:{token, agentGrant}` — 프론트 `socket-registry.ts` 의 두 `auth:{token}`(`:167,:272`)에 `agentGrant: getAgentGrant()` 추가(support 네임스페이스만). 게이트웨이 `handleConnection`: payload.roles∋`'agent'` ∧ storeId 없음 → `grantKey` 형식(UUID) 검증 → `decidirAcceso(userId, key, 'sesion_remota')`(다중화된 함수 재사용, **반환에 `expires_at` 추가**) → 성공 시 `client.data.storeId=acceso.storeId`, `client.data.agentGrantId/Key/ExpiresAt`, 이벤트 `registrarEvento({tipo:'permitido', method:'WS', route:'connect', scope:'sesion_remota'})`. `viewer:join` 은 `canView` 대신 `client.data.agentGrantId` 가 있으면 허용(그 순간 `decidirAcceso` 한 번 더). 이후 `activateSession(uuid, userId, client.data.storeId)` 가 매장 일치·만료를 기존대로 판정.
- **수명:** 뷰어 소켓은 `min(세션 expires_at, grant expires_at)` 에 끊고, **소켓별 `setInterval`(15~30초)** 로 `decidirAcceso` 재확인 → 철회·정책 꺼짐·에이전트 비활성 시 `disconnect`. 크론은 비리더 워커에서 삭제되므로 쓰지 않는다. 철회 즉시 반영이 필요하면 `server.in(room).disconnectSockets()`(Redis 어댑터가 워커 간 전파) — 단순성을 위해 폴링 우선.
- **세션 생성의 단일 진입(D-11 「하나의 진입점」):** 고객이 UUID 를 불러주지 않도록 — 에이전트는 `GET /support/sessions/active` 목록에서 고른다. 고객 측 시작은 유지(명시적 동의 REQ-3: 사용자가 눌러야 rrweb 기록 시작)하되 **grant 에 `sesion_remota` 가 있는 동안 생성**이라는 연결을 둘지 결정 필요(§Open Questions Q4). 최소: `support_sessions.grant_id` nullable 컬럼 추가(expand 단계, `-- w4`) → 감사·철회 시 세션 연쇄 종료에 쓴다.
- **뷰어 화면:** `pages/soporte/visor.tsx` 의 UUID 입력은 에이전트 모드에선 **활성 세션 목록 선택**으로 대체. `SUPPORT_ROLES` 게이트(`navigation`) 는 에이전트 모드 분기 필요.
- **「하나의 코드」 정리:** 접근 코드가 단일 진입이 되면 Token de soporte(의식)와 UUID 입력 화면이 중복으로 남는다. D-1(구 토큰 통합)은 **이번 phase 에서 건드리지 않기로 했으므로**(CONTEXT) 최소한 UI 문구에서 UUID 입력은 같은 매장 내부용으로 한정하고, 외부 지원은 접근 코드만 안내.

### 10.4 함정 (Phase 41 특유)
1. **소켓은 `JwtGlobalGuard`·`UserRoleGuard`·`@AgentScope` 를 전부 우회한다.** 메타데이터 열거 시험이 소켓을 못 본다 → 게이트웨이에 **전용 단위 시험**(grant 없는 agent → 거부, 만료/철회 → 끊김, 다른 매장 세션 uuid → `cross_tenant`, 대조군: 분기 제거 시 실패).
2. **프로세스 로컬 상태:** `viewerByUuid`·`expiryTimers`(`support.gateway.ts:38,41`)는 **워커별 Map**. PM2 4워커(CLAUDE.md)에서 고객이 워커 A, 뷰어가 워커 B 면 R-5 「단일 뷰어」·만료 타이머가 서로 안 보인다(Redis 어댑터는 방 방송만 공유). 에이전트가 들어오면 노출이 커지므로 단일 뷰어는 **DB**(`support_sessions.viewer_user_id` 조건부 UPDATE)로 강제하는 것을 계획에 포함(권장). `[ASSUMED]` PM2 클러스터가 4워커.
3. **`payload.storeId` 는 로그인 시점 JWT 값.** 에이전트는 null 이고 grant 로만 매장이 생긴다 — `client.data.storeId` 를 **절대 payload 로 되돌리지 말 것**(재연결 시 grant 재검증 필수).
4. **고객 화면이 비밀을 보여준다:** rrweb 마스킹은 입력(`maskAllInputs`)과 `rr-block` 표시 요소뿐이다. 프린터 API Key 복사 모달·인증서 업로드·`confirmToken` 이 DOM 텍스트로 나오면 뷰어에 간다 → 해당 요소에 `rr-block` 가 붙었는지 R-4 점검을 이 phase 의 선행 조건으로(플래그 OFF 의 이유).
5. **감사:** 소켓 이벤트는 HTTP 로그에 안 남는다 → `registrarEvento`(method `'WS'`, route `'connect'|'viewer:join'|'session:end'`)를 직접 호출. `support_access_events.route` 는 `VARCHAR(300)`, `scope` `VARCHAR(30)`.
6. **`census.admitClient('support', client, jwtIdentity(payload, client.id))`**(`support.gateway.ts:104-111`) — 에이전트 소켓도 같은 제한을 받는다(정상).
7. **`SupportController.detail/end` 의 `session.storeId !== user.storeId`** 는 에이전트에서 grant 매장과 비교되어 올바르다 — 단 `@AgentScope` 가 없으면 에이전트는 JwtGlobalGuard 에서 미표시 403.
8. **`@Public` 아님:** `support.controller` 는 전부 `@Auth()`, 게이트웨이는 `@Public` 개념 자체가 없다. 새 공개 엔드포인트를 만들지 말 것.

## Common Pitfalls (요약 — 검증 단계에서 점검)

1. **FunctionGuard 가 에이전트를 막는데 `@AgentScope` 만 붙이고 끝냄** → 통과한 줄 알았는데 403. 검증: 에이전트 계정으로 `GET /sales/all` 200, grant 없는 에이전트 403.
2. **우회를 `isAllowed()` 에** → 원가 노출. 검증: 에이전트 응답에 `costo` 계열 필드 없음.
3. **단수 `decision.scope` 유지** → 다중 scope 에서 `legacy` 판정 오작동.
4. **기존 시험 문자열 단언**을 모르고 SQL/메타 형태를 바꿈 → 의도적으로 갱신할 것.
5. **정책 시드·CHECK 누락** → 코드 발급은 되는데 교환 시 `sin_permiso`(`canjear` 가 `alcanceEfectivo` 비어 코드를 소비하지 않고 거부, `agente.service.ts:313-322`).
6. **403 이벤트가 grant 를 통째로 종료**(`AgenteAccesoView.perdido`).
7. **에이전트 모드에서 `/auth/me` 재호출이 겹치기를 지움**(`refreshUser`).
8. **응답 필드**: `confirmToken`·`Branch.apiKey` 가 공통/목록 API 에 실림.
9. **이벤트 홍수**: `LIMIT 200` 이 한 번의 화면 열람으로 소진.
10. **`GET /store/:id`·`/branch/store/:storeId` 가 URL 의 id 를 신뢰** — 에이전트 컨텍스트에서 URL 의 다른 매장 id 를 줘도 테넌트 훅이 격리하는지 **시험으로 확인**(`tenant-isolation-is-absolute`).

## State of the Art

| Old | Current | Impact |
|---|---|---|
| alcance 3개 · 핸들러 23개(cert 6 · legacy 15 · usuarios_terminales 2) | +보기전용 4 + 원격 세션 1 | 정책 CHECK·시드·라벨 3중 복제 갱신 |
| `@AgentScope(단일)` | `@AgentScope(...다중)` | 가드·decision·이벤트·시험 형태 변화 |
| `/auth/me` 가 에이전트에 빈 structure | `/agente/tienda/contexto` 겹치기 | 일반 화면 도달 |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | PM2 클러스터가 4워커라 `viewerByUuid`·`expiryTimers` 가 워커별로 갈라진다 | §10.4-2 | 단일 뷰어 DB 강제 작업 범위가 달라짐 |
| A2 | 운영 프론트 빌드의 `NEXT_PUBLIC_ENABLE_REMOTE_SUPPORT` 가 off | §10.2 | 이미 노출된 메뉴가 있다면 정리 필요 |
| A3 | `GET /products/next-serial`·`/last-created`·`/online-orders/next-number`·`/afip/vouchers/:id/pdf` 에 상태 변경 부작용이 없다 | §3·§5 | 있으면 제외 목록으로 이동 |
| A4 | TN 채널·commerce config·mercadopago wallets 응답에 비밀이 없거나 sanitize 됨 | §4 S11-S13 | 있으면 제외(이미 「확인 전 제외」로 설계) |
| A5 | `GET /store/:id`(가드 없음) 응답에 비밀이 없다 | §3.5 | 있으면 공통 API 에서 제외·필드 제거 |
| A6 | `GET /sellers/:id`(단건)가 `pinHash` 를 싣지 않는다 | §3.5 | 이미 「단건 제외」로 설계 |
| A7 | agent@app 에게 신규 alcance 정책을 기본 enabled=TRUE 로 시드 | 함정 | 사용자 결정 필요(전례는 TRUE) |

## Open Questions

1. **권한 화면(역할·기능) 조회를 보기전용×Admin 에 포함할지** — CONTEXT 기본 제외. `/usuarios` 화면이 `/functions/structure`·`/role-functions/:id`·`/user-functions/:id` 를 같이 불러 **포함하지 않으면 사용자 목록 화면이 일부 깨진다**(D-09 처리). 권장: 제외 유지 + 화면은 「이 코드로는 볼 수 없음」.
2. **`@FunctionGuard` GET 중 쓰기 슬러그**(`delete-impact`·`price-changes`·`sin-variantes`·`photo-library`) 포함 여부 — 읽기 미리보기이지만 가드 이름은 쓰기. 권장: 1차 제외.
3. **POST-조회 허용 목록 v1** — 비워 둘지(권장), `promotions/evaluate-cart` 같은 것을 넣을지.
4. **`sesion_remota` 와 세션 생성의 연결** — 고객이 grant 와 무관하게 세션을 만들 수 있게 둘지(현행), grant 가 있을 때만 만들게 할지. 후자는 같은 매장 내부 뷰어 흐름(「뷰어 권한 규칙은 유지」)과 충돌 가능.
5. **`REMOTE_SUPPORT_ENABLED` 활성화 게이트**(R-4 마스킹 검증·UAT·보안 승인)를 이 phase 에서 어떻게 다룰지 — 용도는 만들되 플래그 OFF 동안 코드 발급 단계에서 거부.
6. **신규 alcance 정책 기본값**(agent@app enabled?) 및 superadmin 화면(`AgentesAdminView`) 토글 노출.
7. **에이전트 모드에서 원가·이익 필드**를 숨기는 기본(=`PERMISO_VER_COSTO` 미보유 취급)을 확정할지.
8. **감사 화면:** `permitido` 이벤트 집계(route 정규화 + count)로 바꿀지 — 현재 `LIMIT 200` 원시 나열.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|---|---|---|---|---|
| Node / npx (api, app) | jest · tsc | ✓ (단 `NODE_OPTIONS` 오염 주의) | — | `env -u NODE_OPTIONS` |
| 로컬 PG18 `ventago` | 마이그레이션 로컬 적용·카탈로그 쿼리 | ✓ (`psql -p 5432` 응답 확인) | PG18 | — |
| 운영 SSH `jhkim-server` (읽기 전용) | 플래그/컬럼 실측 | ✓ (이 세션에서 실행됨) | — | — |
| cmux browser | 동적 인벤토리 캡처 | 미확인 | — | 로컬 dev + 브라우저 DevTools |
| 스테이징 DB | 에이전트 화면 검증 | ✓(존재) 단 **운영 복사본 아님** | — | 금액·스키마 의존 검증은 스테이징 결과로 통과 처리 금지 |

**Missing:** 없음(차단 없음).

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | jest 29 + ts-jest (api `package.json` jest 블록, `testRegex .*\.spec\.ts$`, `testEnvironment node`) · app jest(`ventago-app/package.json`) |
| Config file | api: `api-ventago/package.json` `"jest"` / app: `ventago-app/package.json` `"jest"` |
| Quick run command | `cd api-ventago && env -u NODE_OPTIONS npx jest --maxWorkers=1 src/app/auth/guards` (디렉터리 **하나씩**) |
| Full suite command | **돌리지 않는다**(memory `jest-memory-blowup`·`jest-maxworkers-1-required`). 필요 시 `NODE_OPTIONS=--max-old-space-size=2048 npx jest --maxWorkers=1 --workerIdleMemoryLimit=800MB` — 수 분, CI/사람이 |
| 금지 | `--findRelatedTests`(17 suites/91초), `--runInBand`(OOM), 여러 폴더 동시 지정, 짧은 `workerIdleMemoryLimit` |
| grep | 이 저장소는 일부 소스가 바이너리로 판정 → `grep -a` 필수. 출력이 비면 「안 돈 것」으로 의심(`|| echo "!! 안 돈 것"`) |

### Phase Requirements → Test Map (CONTEXT 결정 기준)
| ID | Behavior | Test Type | Automated Command | File Exists? |
|---|---|---|---|---|
| D-01/D-03 | 미표시 핸들러 403 · X-Store-Id 동시 400 · request.user 매장 치환 | unit | `npx jest --maxWorkers=1 src/app/auth/guards` | ✅ `jwt-global.guard.spec.ts` 확장 |
| D-02 | 실효 범위 교집합(새 alcance) | unit | `npx jest --maxWorkers=1 src/app/agente` | ✅ `agente.spec.ts` 확장 |
| D-05 | 다중 scope 일부만 grant 에 있어도 통과, 일치 목록 반환 | unit | `npx jest --maxWorkers=1 src/common/tenant` | ✅ `agent-grant.spec.ts` 갱신 |
| D-01+FG | `FunctionPermissionGuard` 에이전트 분기 + 대조군 | unit | `npx jest --maxWorkers=1 src/app/auth/guards` | ✅ `function-permission.guard.spec.ts` 확장 |
| D-04 | `ver_*` 는 GET 만 / 허용 POST 목록 / Public·클래스레벨 금지 | unit(런타임 열거) | `npx jest --maxWorkers=1 src/app/auth/guards/agent-readonly-scopes.spec.ts` | ❌ Wave 0 |
| D-10 | 비밀 필드 부재(+ 대조군) · 제외 목록 핸들러에 scope 없음 | unit | 〃 + `src/app/online-orders`·`branch` | ❌ Wave 0 |
| D-07 | 인벤토리 보정(동적) | 수동+쿼리 | `support_access_events` `denegado` 집계 | 수동(자동화 불가 — 사유: 실제 화면 호출 의존) |
| D-08/D-09 | 비-GET 중앙 차단 · 403 code 구분 · `presentApiError` | unit | `cd ventago-app && env -u NODE_OPTIONS npx jest src/__tests__/<파일>` | ❌ Wave 0 (순수 로직은 `.ts` 로 — app jest 는 `.tsx` import 불가, memory `app-jest-cannot-import-tsx`) |
| D-11 | 게이트웨이 agent join/만료/철회/교차매장 | unit(하네스) | `npx jest --maxWorkers=1 src/app/support` | ❌ Wave 0 (spec 이 없다 — `ls support/` 에 spec 0건) |
| 마이그레이션 | CHECK 확장·시드 양쪽 적용 | 수동 | `psql -p 5432 -d ventago -c '\d agent_action_policies'` + 운영 5434 | 수동(DDL, 사용자 승인 필요) |
| 돌연변이 | 가드 분기 삭제 등 4종+ | script | `bash api-ventago/scripts/mutantes-agente.sh` (신규, `mutantes-wp.sh` 복제) | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** 변경 모듈 디렉터리 jest 1개 + `env -u NODE_OPTIONS npx tsc --noEmit`(api / app 각각) — 커밋 게이트(`verify-before-commit.sh`)가 같은 범위를 돌린다.
- **Per wave merge:** 영역별 spec 디렉터리(guards · agente · tenant · support · online-orders · branch) 순차 + 돌연변이 스크립트.
- **Phase gate:** 위 + 로컬/운영 마이그레이션 양쪽 확인 + 에이전트 계정 동적 화면 순회(제외 목록이 403 인지, 공통 API 가 200 인지) + 대조군 계정(역할 0개 계정 — `permission-test-accounts-exist`)으로 grant 없이 403.

### Wave 0 Gaps
- [ ] `src/app/auth/guards/agent-readonly-scopes.spec.ts` — D-04/D-10 열거·제외·비밀
- [ ] `src/app/support/support.gateway.agent.spec.ts`(또는 `support.agent.spec.ts`) — D-11 (하네스: memory `nest-service-needs-harness-not-manual-new`)
- [ ] `test/mutantes/agente-ver.json` + `scripts/mutantes-agente.sh`
- [ ] app `src/__tests__/` — `api-error-presentation`(에이전트 문구)·`agente-logic`(새 alcance)·모드 판정 순수 함수
- [ ] 프레임워크 설치: 없음

## Security Domain

### Applicable ASVS Categories
| ASVS Category | Applies | Standard Control |
|---|---|---|
| V2 Authentication | 부분 | 기존 JWT + grant(UUID, 만료·철회). 소켓은 handshake 에서 같은 `decidirAcceso` |
| V3 Session Management | 예 | grant 수명(30/120분) · 소켓 주기 재확인 · 철회 즉시 |
| V4 Access Control | **핵심** | 핸들러 메타데이터 fail-closed · scope∩정책 · 테넌트 훅(grant storeId) · 보기전용=GET 열거 시험 |
| V5 Input Validation | 예 | grant 헤더 UUID 정규식(`RE_UUID`), `ParseIntPipe` 유지 |
| V6 Cryptography | 아니오(신규 없음) | 코드는 HMAC 해시 저장(`hashCodigo`) 기존 |
| V8 Data Protection | 예 | 비밀 필드 제외·`toJSON` redact·응답 필드 시험 |
| V7 Logging | 예 | `support_access_events`(코드·비밀번호·인증서 내용 금지) |

### Known Threat Patterns
| Pattern | STRIDE | Standard Mitigation |
|---|---|---|
| 에이전트가 쓰기 핸들러 도달 | Elevation | 보기전용 scope 는 GET 만(시험+돌연변이) · 프론트 차단은 보조 |
| 공통 조회로 비밀 유출(`confirmToken`·`apiKey`) | Info disclosure | 포함 목록 기반 필드 · 응답 시험 · 제외 목록 |
| 다중 scope 오판(단수 decision) | Elevation | `scopes[]` 반환 · `legacy` 판정은 포함 여부 |
| `@Public`·소켓 경유 우회 | Elevation | Public∧AgentScope 금지 시험 · 게이트웨이 전용 시험 |
| 타 매장 id 를 URL/쿼리로 | Tampering | 테넌트 훅(grant storeId) · `X-Store-Id` 400 · URL id 시험 |
| 만료·철회 후 소켓 생존 | Elevation | 소켓 주기 재확인 · 세션 15분 · grant 만료 상한 |
| 감사 우회(이벤트 기록 실패) | Repudiation | 쓰기는 기록 실패 시 403(기존), GET 은 허용 — 보기전용이라 허용 유지(결정 필요 시 질문) |
| 응답에 PII 대량(회계 엑셀) | Info disclosure | 파일 다운로드 GET 포함 여부 질문(Q) |

## Sources

### Primary (HIGH — 이 세션에서 코드 직접 확인)
- `api-ventago/src/app/auth/guards/jwt-global.guard.ts` · `user-role.guard.ts` · `function-permission.guard.ts`
- `api-ventago/src/app/auth/services/function-permission.service.ts` · `strategies/jwt.strategy.ts` · `decorators/{agent-access,auth,function-guard}.decorator.ts`
- `api-ventago/src/common/tenant/{agent-grant,tenant-user.util}.ts` · `app/agente/{agente-rules,agente.service,agente.controller}.ts` · `app/legacy-import/admin-role.guard.ts`
- `api-ventago/migrations/2026-10-02-a-agente-accesos.sql` · `2026-10-03-a-agente-alcance-legacy.sql`
- `api-ventago/src/app/support/*` (gateway·service·controller·model·config) · 컨트롤러 열거(205개) · 모델 컬럼 · 서비스(sellers, despacho, branch, online-orders, print, store-config, wp-channel)
- `ventago-app/src/services/{api.service,agent-grant,api-error-presentation}.ts` · `configs/{withAccess,roles}` · `hooks/useHasFunction.ts` · `navigation/vertical/index.ts` · `context/AuthContext.tsx` · `views/agente/*` · `views/acceso-ventago/AccesoVentagoView.tsx` · `pages/soporte/*` · `hooks/useRemoteSupport.ts` · `realtime/socket-registry.ts`
- 실측: `[VERIFIED: ssh]` 운영 `api_ventago` `REMOTE_SUPPORT_ENABLED` 빈 값 · `branches.api_key` 35행 중 0 · 로컬 `information_schema` 비밀 컬럼 카탈로그

### Secondary (MEDIUM)
- 정적 정규식 추출한 프론트 화면별 호출(`views/*`, `hooks/api/*`) — 템플릿·래퍼 누락 가능

### Tertiary (LOW)
- TN 채널·commerce config·mercadopago wallets 응답 필드, 운영 프론트 빌드 플래그, PM2 워커 수

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — 신규 패키지 없음
- Architecture(가드 경로·프론트 도달·Phase 41): HIGH — 코드 직접 확인
- 인벤토리: MEDIUM — 정적 추출 + 상속 라우트 미포함 → 동적 보정 필수
- Pitfalls: HIGH(코드/메모리 근거) / 일부 LOW(위 가정 로그)

**Research date:** 2026-10-08
**Valid until:** 2026-10-22 (코드가 빠르게 변함 — 인벤토리는 구현 직전 재생성)
