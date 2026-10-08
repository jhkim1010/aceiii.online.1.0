# Phase 101: Acceso de soporte por token — la tienda elige qué funciones habilita - Context

**Gathered:** 2026-10-08
**Status:** Ready for planning
**Source:** 101-PREP.md (대화로 확정한 결정, 2026-10-08) — discuss-phase 대신 PREP 변환 (사용자 선택)

<domain>
## Phase Boundary

매장이 지원용 코드를 발급할 때 **용도를 고르고**, 지원 담당자는 그 코드로 **그 용도의 API 에만** 들어간다.
기존 「에이전트 접근 코드」(`support_access_grants` · `@AgentScope` · agent@app · `X-Agent-Grant`)를 **확장**한다 —
새 토큰 장치를 만들지 않는다.

이 phase 가 전달하는 것:
- 새 용도(alcance) 4개 — **보기전용 × Venta / Producto / Factura / Admin** — 를 조회(GET) 핸들러에 붙인다.
- 지원 담당자가 **매장이 쓰는 일반 화면 그대로**(판매·상품·전표·admin) 조회 모드로 볼 수 있다.
- 코드 발급 화면(Configuración › Acceso de Ventago)에 새 용도 체크박스.
- 경계·비밀 제외·쓰기 거부를 시험으로 고정(대조군·돌연변이 포함).

범위 밖: Phase 100(WhatsApp/AI/Codex 워커), 쓰기 권한 용도. (Token de soporte 통합은 범위 안 — D-16)
</domain>

<decisions>
## Implementation Decisions

### 장치 (LOCKED)
- **D-01** 에이전트 접근 코드를 확장한다. 경계는 URL 이 아니라 **핸들러 메타데이터**(`@AgentScope`) — 2026-10-02 codex 원칙 유지. 표시 없는 핸들러는 에이전트에게 403.
- **D-02** 실효 범위 = 매장이 고른 용도 ∩ superadmin 이 그 매장에 허용한 용도 (`alcanceEfectivo` — 교집합, 합집합 금지). 새 용도도 이 규칙을 그대로 탄다.
- **D-03** 테넌트 격리 절대: grant 의 storeId 로만. `X-Store-Id` 와 동시 사용 400 유지.

### 용도 목록 (LOCKED)
| 용도 | alcance | 상태 |
|---|---|---|
| Importar legacy | `legacy` | 운영 중 — 변경 없음 |
| Renovar certificado digital | `cert` | 운영 중 — 변경 없음 |
| 보기전용 × Venta | 신규 | GET 만 |
| 보기전용 × Producto | 신규 | GET 만 |
| 보기전용 × Factura | 신규 | GET 만 |
| 보기전용 × Admin | 신규 | GET 만 |
| Usuarios y terminales | `usuarios_terminales` | 운영 중 — 손대지 않음 |
| **Sesión remota (ver pantalla)** | 신규 | Phase 41 원격 지원 세션(15분, 화면 보기)을 **같은 코드의 용도 하나로** 연다 |

- **D-11** (2026-10-08 사용자 추가) Phase 41 원격 지원 세션도 용도 목록의 한 항목이다. 매장이 코드 발급 시
  「Sesión remota」를 체크하면 그 코드로 지원자가 원격 세션(화면 보기, 15분)을 열 수 있다. 원격 세션의 기존 흐름
  (`api-ventago/src/app/support/` — 고객 요청 → UUID → socket 뷰어)을 접근 코드 체계와 **하나의 진입점**으로 묶는다
  — 두 개의 「지원 코드」가 되지 않게. 기존 세션 만료(15분)·store 스코프·뷰어 권한 규칙은 유지.

- **D-04** 보기전용 alcance 는 **조회 핸들러에만** 붙는다. 쓰기(POST/PUT/PATCH/DELETE) 핸들러에 보기전용 alcance 가 붙으면 시험이 깨진다 — 대조군 필수(쓰기 핸들러에 일부러 붙인 돌연변이가 죽어야 한다).
  ★ 예외 주의: 조회인데 POST 인 핸들러(검색·리포트 body)가 있을 수 있다 → 「HTTP 메서드」가 아니라 「상태를 바꾸는가」로 판정하고, POST-조회는 허용 목록으로 명시.
- **D-05** 한 핸들러가 여러 용도에 필요할 수 있다(판매 상세 = Venta·Factura) → `@AgentScope` 를 **여러 alcance** 로 확장. 가드는 「grant 의 alcance 중 하나라도 핸들러 목록에 있으면 통과」.

### 화면 방식 (LOCKED — D-8 (a))
- **D-06** 지원 담당자는 **매장의 일반 화면 그대로** 본다(같은 화면을 보며 안내).
- **D-07** 그 화면이 같이 부르는 **공통 조회 API**(지점·설정·카탈로그 참조 데이터 등)는 보기전용 용도들 공통으로 연다 — 화면별 호출 API **전수 인벤토리**가 근거. 인벤토리 없이 「대충 필요한 것」으로 열지 않는다.
- **D-08** 쓰기 버튼은 숨기되 **서버 403 이 경계**다(숨김은 보안이 아니다).
- **D-09** 화면이 범위 밖 API 에서 403 을 받으면 **깨지지 않고** 「이 코드로는 볼 수 없음」을 보여준다(전역 처리 우선, 화면별 땜질 지양).

### 비밀 제외 (LOCKED)
- **D-10** 「admin 의 GET 전부」가 아니다. 응답이 **비밀을 싣는** 조회는 제외 목록으로 명시·시험 고정:
  프린터 API Key, MercadoPago/WP/Drive OAuth 토큰, AFIP 인증서·키, 지원 토큰·접근 코드, 비밀번호 해시, 기기 토큰, webhook 비밀
  (+ 조사에서 발견되는 것). 공통 조회 API 도 **응답 필드까지** 대조한다 — `SELECT *` 성 응답이 토큰을 실은 전례 있음.

### 조사 후 확정 (2026-10-08 사용자, plan-phase 질문)
- **D-12** 보기전용 × Admin 에 **권한 화면(역할·기능별 권한) 조회를 포함**한다 — 보기만. 쓰기(권한 저장)는 당연히 403.
- **D-13** 원가·이익(costo · ganancia · 환율 기준가 등 `PERMISO_VER_COSTO` 대상)은 **보여주지 않는다.** 에이전트 분기는 `FunctionPermissionGuard` 에만 두고 `isAllowed()` 에 넣지 않는다(넣으면 원가가 열린다 — RESEARCH).
- **D-14** 원격 세션(D-11)은 **연결 + 운영에서 켜기**까지 이번 phase. 접근 코드의 「Sesión remota」 용도로 에이전트가 들어가게 하고, 스테이징·운영에서 처음부터 끝까지 실측한 뒤 `REMOTE_SUPPORT_ENABLED` 를 켠다(운영 반영 규칙·사용자 승인 따름).
- **D-15** UI-SPEC 을 먼저 만든다(`/gsd:ui-phase 101`) — 계획은 그 뒤.
- 기본값(질문 안 함): 쓰기 권한 슬러그로 가드된 GET(`delete-impact` · `price-changes` · `sin-variantes`)은 1차 제외.

### Token de soporte 통합 (2026-10-08 사용자 「좋아」 — D-1 확정, 기본값 뒤집힘)
- **D-16** 매장 메뉴 **「Token de soporte」 화면을 접근 코드 발급 화면으로 바꾼다.** 매장은 익숙한 그 메뉴에서
  **용도를 골라** 6자리 코드를 만들고, 지원자는 「Usar código」 하나로 받는다. 지원 코드는 **한 종류**만 남는다.
- 근거(실측 2026-10-08): 옛 토큰은 권한을 주지 않는다(validate 는 매장명만 반환, superadmin act-as 는 토큰 무관).
  운영 7개 발급 · **사용 0** · 5 만료. 사용자가 옛 토큰(106741)을 「Usar código」에 넣어 Inválido 를 받은 혼동이 실제로 발생.
- 따르는 일: ① 옛 `POST /support-token/generate` · `/validate` 와 superadmin `/admin/soporte-remoto` 의 처분(폐기 또는
  접근 코드 화면으로 안내) ② 「Mandar Token a CoolSistema」(AI 채팅으로 전송) 버튼은 새 코드를 보낸다
  ③ 같은 매장 메뉴 하나 — Configuración › Acceso de Ventago 와 **중복 진입점이 되지 않게** 정리(Phase 99 원칙: 기능당 진입점 하나)
  ④ 화면 문구가 실제 권한과 일치(「visualizar y modificar」 같은 과장 금지 — 고른 용도만).
- **미정(계획 확인 시 질문):** 옛 토큰의 월 무료 20개 / 초과 개당 $5,000(`OVERAGE_CHARGE`) 과금 규칙을 새 코드에 이어받을지.
  실제 청구 경로가 있는지 먼저 확인.

### Claude's Discretion
- alcance 의 내부 식별자 이름(예: `ver_ventas` · `ver_productos` · `ver_facturas` · `ver_admin`)과 화면 라벨(스페인어).
- 프론트에서 에이전트 세션이 일반 화면에 도달하는 방법(아래 미정 사항 참조) — 조사 결과로 제안.
- 시험 배치(가드 단위 시험 vs 핸들러 메타데이터 전수 시험).

### 미정 — 기본값으로 진행, 계획 확인 시 사용자에게 확인
- ~~D-1~~ → D-16 으로 확정(통합한다).
- **D-3** 쓰기 용도: 이번 phase 는 **보기전용만**. 쓰기 용도는 후속.
- **D-4** 지원자 신원: **agent@app 공용 유지**(기본값). 개인별 신원은 후속.
- **D-5** 유효시간: 기존 30/120 분 유지.
- **D-6** 감사 화면: 기존 Acceso de Ventago 이벤트 목록에 **용도(alcance)와 메서드**가 보이면 충분.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### 기존 접근 코드 장치
- `api-ventago/src/app/auth/decorators/agent-access.decorator.ts` — `ALCANCES_AGENTE`, `@AgentScope`, `@AgentePermitido`
- `api-ventago/src/app/auth/guards/jwt-global.guard.ts` — 에이전트 판정(metadata 읽기, grant 확인, 감사 이벤트, request.user 매장 치환)
- `api-ventago/src/common/tenant/agent-grant.ts` — `grantKeyDe`, `decidirAcceso`, `registrarEvento`
- `api-ventago/src/app/agente/agente-rules.ts` · `agente.service.ts` · `agente.controller.ts` — 코드 생성·교환·철회, `alcanceEfectivo`
- `api-ventago/src/app/legacy-import/admin-role.guard.ts` — 에이전트 grant 를 역할 가드에서 인정하는 전례
- `ventago-app/src/views/acceso-ventago/AccesoVentagoView.tsx` — 매장 쪽 코드 발급 화면
- `ventago-app/src/views/agente/AgenteAccesoView.tsx` · `AgentesAdminView.tsx` — 에이전트 쪽 화면, superadmin 허용 설정
- `ventago-app/src/__tests__/agente-logic.spec.ts` — `etiquetasAlcances`

### 권한·가드 체계 (일반 화면이 통과해야 하는 것)
- `api-ventago/src/app/auth/decorators/function-guard.decorator.ts` · `FunctionPermissionGuard` — 기능 슬러그 가드(에이전트는 역할이 없다)
- `ventago-app/src/configs/withAccess*` — 화면 게이트(모듈·역할), `WithFunctionAccess`
- `api-ventago/src/app/auth/auth.service.ts` `/me` — 프론트가 받는 권한 형태

### 프로젝트 규칙
- `./CLAUDE.md` — 테넌트 격리, 낮 시간 운영 반영 규칙, 커밋 게이트, CODEX 자문
- `.planning/phases/101-…/101-PREP.md` — 기존 장치 3개 대조, 설계 쟁점
</canonical_refs>

<specifics>
## Specific Ideas

- 매장 관점 흐름: Configuración › Acceso de Ventago → 「Generar código」 → 용도 체크(Ver ventas · Ver productos · Ver facturas · Ver administración · Importar legacy · Certificado) → 6자리 코드를 전화/WhatsApp 로 불러줌 → 지원자가 교환 → 매장은 이벤트 목록에서 무엇을 봤는지 확인·철회.
- 지원자 관점: 교환 후 그 매장의 일반 화면을 조회 모드로 탐색. 쓰기 버튼은 안 보이고, 눌러도 서버가 403.
- Phase 100 의 AI 진단은 이 grant 위에서만 조회한다(후속).
</specifics>

<deferred>
## Deferred Ideas

- 쓰기 용도(예: 상품 수정 허용) (D-3)
- 지원 담당자 개인별 신원 (D-4)
- Phase 100 AI 진단 연결
</deferred>

---

*Phase: 101-acceso-de-soporte-por-token-la-tienda-elige-qu-funciones-hab*
*Context gathered: 2026-10-08 (PREP 변환)*
