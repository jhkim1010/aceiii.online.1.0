---
phase: 88-store-onboarding-setup-guide
type: spec
version: 2
created: 2026-09-09
revised: 2026-09-09 (사용자 결정 4건 반영 — §8)
branch: feature/phase88-onboarding-guide
status: CONFIRMED — 결정 완료. W1 착수 가능
context: .planning/phases/88-store-onboarding-setup-guide/88-CONTEXT.md
mockup: .planning/mockups/onboarding-setup-guide/guia-configuracion.html
mockup_url: https://claude.ai/code/artifact/4c248621-b2da-4068-b537-2a3219ed0fa1
---

# Phase 88 — 신규 매장 셋업 가이드 (Guía de configuración)

## 0. 한 줄

**매장을 만든 사람이 첫 로그인에서 「지금 뭘 해야 하는지」를 화면에서 알고, 15분 안에 첫 판매까지 간다.**

---

## 1. 문제

새 매장을 열어 준 뒤 사용자가 무엇을 해야 할지 몰라 멈춘다. 지금 있는 것은
**사용자 단위 3스텝 스포트라이트 투어 하나**뿐이고(`OnboardingTour`), 셋업 자체는 안내하지 않는다.
설정 항목은 `HUB_TABS` 13탭 + 별도 화면 10여 개에 흩어져 있고, **어디부터 손대야 하는지에 대한 순서가 제품 안에 없다.**

★ 그리고 신규 매장은 **비어 있지 않다** — 시드 20종이 이미 들어간다. 그래서 화면 어디도 「비어 보이지」 않고,
사용자는 «이미 다 돼 있는 것 같은데 왜 판매가 안 되지» 상태에 놓인다. (근거: CONTEXT §1-2)

---

## 2. 목표 / 비목표

**목표**
1. 첫 로그인에 **3단계 이하**의 최소 위저드 1개. 그 외 어떤 것도 막지 않는다.
2. 홈에 상주하는 **셋업 체크리스트** — 최대 8항목, 완료는 실데이터에서 파생, 진행률은 링·분수.
3. 주요 화면의 **빈 상태**가 다음 행동을 말한다 (productos · caja · impresora · clientes).
4. 측정: 체크리스트 완료율이 아니라 **가입 → 첫 판매까지의 시간(TTFV)** 과 **어느 단계에서 멈추는가**.

**비목표 (명시적)**
- 새 코치마크/투어 체인 확대 — NN/g 실측상 효과 없음. 기존 투어는 **폐지** 대상이다.
- 온보딩용 데모 상품·가짜 판매 시딩 — POS 에서 실데이터 오염은 회계 사고다.
- 온보딩 전용 신규 설정 화면 — 목적지는 **전부 기존 화면 딥링크**다.
- i18n 전면 도입 — 사전이 141줄뿐인 현 실태에서 이 phase 가 감당할 일이 아니다(§8 D-4).
- 매뉴얼/AI 챗봇 개편 (`/manuales`, `/chat`) — 별건.

---

## 3. 확정 설계 결정

| # | 결정 | 근거 |
|---|---|---|
| **D-1** | 상태의 단위는 **`store_id`**, 지점 종속 단계는 **`branch_id`** 까지. `users.onboarding_completed` 는 셋업 판정에 쓰지 않는다 | 직원 5명이면 5번 뜬다. 「장부의 단위와 대상의 단위를 갈라놓지 않는다」 — 카하 규칙과 같은 논리 |
| **D-2** | **완료는 저장하지 않는다.** 실데이터 술어(predicate)로 파생한다. 저장하는 것은 **의도**뿐 — `dismissed_at`(No aplica) · `snoozed_until`(나중에) | Shopify automatic completion markers · Stripe `currently_due` |
| **D-3** | 단, **한 번 완료된 단계는 되돌리지 않는다.** `onboarding_events` 의 `completed` 가 술어보다 우선 | 상품을 지웠다고 온보딩이 되살아나면 안 된다 |
| **D-4** | 판정은 **「시드값에서 벗어났는가」**. 「행 존재」로 판정하지 않는다 | CONTEXT §1-2 |
| **D-5** | 진행률 **분모 = 적용되는 항목 수**. 모든 항목에 「No aplica」, 가이드 전체에 **영구 닫기** + Ayuda 에서 재진입 | Square 59% 고착 반면교사 |
| **D-6** | 이미 끝난 3항목(매장·지점·카하/터미널)을 **완료로 표시해 3/8 로 시작** | Endowed progress 19%→34% |
| **D-7** | 상태는 **`GET /auth/me` 응답에 얹는다.** 새 엔드포인트를 만들지 않는다. `POST /auth/login` 응답에도 같은 필드를 추가한다(현재 없음) | pool 규약 — 요청당 왕복·커넥션 증가 금지. CONTEXT §1-7 |
| **D-8** | 로그인 직후 모달 순서를 **코드로 고정**: ① 셋업 위저드(미완 시) → ② `SelectBoxTerminalModal` → ③ `NoticesBanner`. 앞의 것이 열려 있으면 뒤의 것은 열리지 않는다 | 현재 `disabled` prop 이 배선돼 있지 않아 겹칠 수 있다 |
| **D-9** | 기존 `OnboardingTour`/`OnboardingWrapper` **폐지**, `OnboardingDialog`·`SetupWizardView` **삭제**(문안만 이관) | 두 개가 겹쳐 뜨는 것이 지금보다 나쁘다 |
| **D-10** | 첫 화면 랜딩은 스텁인 `pages/index.tsx` 를 채워 쓴다 | 빈 자리가 이미 있다 |
| **D-11** | **위저드는 3단계 전부 유지.** 업종 질문은 **실제로 분기**한다 — `talles`/`colores` 시드가 달라지고 해당 없는 단계가 카탈로그에서 빠진다 | 사용자 결정 2026-09-09. 분기 없는 질문은 순수 마찰이므로, 분기 구현이 안 되면 질문을 빼는 것이 아니라 **분기를 만든다** |
| **D-12** | **기존 운영 매장에는 보이지 않는다.** 마이그레이션이 기존 매장 전부에 `onboarding_hidden_at = now()` 를 채운 상태로 배포한다. 신규 매장만 대상 | 사용자 결정 2026-09-09 |
| **D-13** | 문구는 **i18n 키**로 쓴다(`public/locales/es.json` 의 `onboarding.*`). **단 언어 전환 스위치는 만들지 않는다** — `lng:'es'` 고정 유지, `supportedLngs` 변경 없음, 감지기 부활 금지 | §3-4 |

### 3-1. 단계 카탈로그 (초안 — 8항목)

| code | 단위 | 완료 술어 | 비고 |
|---|---|---|---|
| `create_store` | 매장 | 항상 참 | 가입 시점 |
| `create_branch` | 매장 | 항상 참 | 시드 |
| `open_box_terminal` | 지점 | 항상 참 | 시드 |
| `load_products` | 매장 | 시드 제네릭 외 제품 1건 이상 | ★ 맨 위 |
| `set_prices` | 매장 | 가격유형 범위가 시드 기본값과 다름 | |
| `check_payment_methods` | 매장 | 시드 결제수단을 수정·비활성화한 적 있음 | |
| `connect_printer` | 지점 | `print_agents` 에 `last_seen_at IS NOT NULL` | 「No aplica」 빈도 높음 |
| `first_sale` ★ | 지점 | `sales` 1건 이상 | **진짜 가치 도달점 = TTFV 종점** |

`eventually_due` (체크리스트 밖, 「más adelante」 접이식): `invite_staff` · `electronic_invoicing`(ARCA) ·
`mercado_pago` · `online_shop` · `import_legacy`.

### 3-2. 응답 형태 (Stripe 차용)

```json
"onboarding": {
  "completed": ["create_store","create_branch","open_box_terminal"],
  "currently_due": ["load_products","set_prices","first_sale"],
  "eventually_due": ["invite_staff","electronic_invoicing"],
  "dismissed": ["connect_printer"],
  "progress": { "done": 3, "applicable": 8 },
  "hidden_at": null,
  "rubro": "indumentaria"
}
```

### 3-3. 스키마 (추가만 · nullable · 기존 테이블 변경 없음)

```
store_onboarding_state
  store_id int NOT NULL, branch_id int NULL, step_code varchar(40) NOT NULL,
  dismissed_at timestamptz NULL, snoozed_until timestamptz NULL,
  created_at, updated_at
  UNIQUE (store_id, branch_id, step_code)

onboarding_events                 -- append-only
  id, store_id, branch_id NULL, user_id, step_code,
  event varchar(20),              -- viewed | started | completed | dismissed | undismissed
  occurred_at timestamptz DEFAULT now()
  INDEX (store_id, step_code)
```

`stores` 에는 컬럼 **1개만** 추가: `onboarding_hidden_at timestamptz NULL` (가이드 영구 닫기).
→ `me()` 가 이미 `Store` 행을 가져오므로 **추가 쿼리 0**.

### 3-4. 언어 — 왜 「하드코딩 아님, 그렇다고 전환 스위치도 아님」인가

실측(2026-09-09):

- 인프라는 **이미 있다** — i18next 22.4 + `i18next-http-backend`, `src/configs/i18n.ts`, 사전 3개(`es` 143 / `en` 141 / `ko` 141줄), `useTranslation` 사용처 22개.
- 그러나 `lng:'es'` **고정**이고 `supportedLngs: ['es','en']` — **`ko.json` 은 목록에 없어 로드되지 않는다.**
- 고정된 이유가 파일 주석에 남아 있다: *"개발자 브라우저 ko-KR 이면 ko.json 로드되어 한글 메뉴가 노출되는 문제 있었음"* → **브라우저 감지기는 다시 켜지 않는다.**
- **언어를 저장할 곳이 없다** — `users` 에 `locale`/`idioma` 컬럼이 없다.
- 화면 문구는 대부분 JSX 하드코딩. 즉 **전면 전환은 이 phase 가 아니라 별도 프로젝트다.**

⤷ 그래서 **비용이 갈린다.** 온보딩은 **새로 쓰는 화면**이라 문구가 한 곳에 모이고 개수도 35개 안팎이다.
  키로 넣는 추가 비용은 **거의 0**이고, 하드코딩해 두면 나중에 전면 번역할 때 **다시 찾아 뜯어야 한다.**
  반대로 **전환 스위치를 지금 켜면 온보딩만 한국어이고 나머지는 스페인어**인 반쪽 상태가 되고,
  선택을 저장할 컬럼도 없다.

**나중에 한국어·영어를 켤 때 남는 일 (이 phase 밖):** ① `users.locale` 컬럼 + `/me` 응답,
② `supportedLngs` 에 `ko` 추가 + `i18n.changeLanguage(user.locale)` (감지기 아님, **명시 설정만**),
③ 나머지 화면 문구 이관. ①②는 반나절, ③이 진짜 일이다. **온보딩은 그때 이미 끝나 있다.**

---

## 4. 웨이브

**W1 — 서버 계산기 (프런트 없이 값이 맞는지부터)**
- [ ] `88-01` 마이그레이션 2건 + `stores.onboarding_hidden_at` (추가만·nullable, 로컬 5432 / 운영 5434 양쪽). **같은 파일에서 기존 매장 전체에 `onboarding_hidden_at = now()` 백필 (D-12)** — 배포 순간부터 기존 매장에는 아무것도 보이지 않는다
- [ ] `88-02` `OnboardingService.resolve(storeId, branchId)` — 술어 8개, **단일 쿼리(EXISTS UNION ALL)** 로 묶고 60초 `MemoryCacheService` 캐시. `sequelize.transaction()` 불필요(읽기 전용), 새 풀 금지
- [ ] `88-03` `/auth/me` + `/auth/login` 응답에 `onboarding` 필드 (조립부 `auth.service.ts:599·1163·1225`)
- [ ] `88-04` `PATCH /onboarding/steps/:code` — `dismiss` / `undismiss` / `snooze` 만. 완료 마킹 API 는 **만들지 않는다**(D-2)
- [ ] `88-05` 매장 생성 **두 경로** 모두 `onboarding_events(create_store, completed)` 기록 (`auth.service.ts:671`, `store.controller.ts:169`)

**W2 — 홈 체크리스트 (핵심 산출물)**
- [ ] `88-06` `<SetupGuide/>` — 링 진행률 · 접이식 · 항목 펼침 · 「No aplica」/「Recordármelo luego」/영구 닫기. 목적지는 전부 `/configuracion?tab=<key>` 딥링크
- [ ] `88-07` `pages/index.tsx` 랜딩 + `menuRegistry.ts` 에 「Guía de configuración」 + `currently_due.length` 배지
- [ ] `88-08` 모달 순서 고정(D-8) + `OnboardingTour`/`OnboardingWrapper` 제거 + `OnboardingDialog`·`SetupWizardView` 삭제

**W3 — 첫 로그인 위저드 (3단계)**
- [ ] `88-09` 3스텝 모달: 업종 → 매장 데이터(nombre·CUIT·IVA) → 지점 확인. **CUIT 는 선택**(전자청구 활성화 때만 필수)
- [ ] `88-10` 업종 분기 **(필수 — D-11)** — `indumentaria`/`calzado`/`accesorios`/`otro` 별로 `sizes`·`colores` 시드를 바꾸고 해당 없는 단계를 카탈로그에서 뺀다. 분기 없이 질문만 남기는 결과물은 **미완성으로 간주한다**

**W4 — 빈 상태 + 계측**
- [ ] `88-11` 공용 `<EmptyState/>` 신설 + productos · caja · impresora · clientes 4곳 적용
- [ ] `88-12` PostHog 이벤트: `onboarding_step_viewed/started/completed/dismissed` + **TTFV**(가입→첫 판매) 대시보드 쿼리

---

## 5. 성공 기준 (참이어야 하는 것)

- 신규 매장 첫 로그인에서 **모달이 정확히 하나** 뜨고, 끝내면 홈에 **3/8** 로 시작하는 가이드가 보인다
- 제품 1건을 등록하면 **새로고침만으로** `load_products` 가 완료로 바뀐다 (사용자가 체크하지 않는다)
- 「No aplica」를 누르면 **분모가 8→7 로 줄고**, 다시는 요구하지 않는다
- 「Ocultar guía」 후 가이드가 사라지고, **Ayuda 에서 되돌아올 수 있다**
- 두 번째 지점을 만들면 **지점 단위 항목만** 다시 나타난다
- superadmin 이 만든 매장도 상태가 동일하다
- `/me` 의 P95 가 이 phase 전후로 **증가하지 않는다** (추가 왕복·추가 커넥션 0)
- 기존 투어가 **완전히 제거**돼 두 안내가 겹치지 않는다

---

## 6. DB / pool 규약 (프로젝트 상시 규칙)

- 마이그레이션은 **추가만 · nullable**. 인덱스는 `CREATE INDEX CONCURRENTLY`, `SET lock_timeout='5s'`
- **로컬 5432 + 운영 5434 양쪽 적용.** 스키마 변경이므로 둘 다 대상
- Sequelize 싱글턴만 사용. **`new Pool()` 금지**, 요청마다 커넥션을 늘리는 폴링 금지
- 홈 화면 조회는 **캐시 60초** — 매 렌더마다 EXISTS 8회가 나가면 안 된다
- 술어 쿼리는 반드시 `store_id` 조건 포함 — 테넌트 가드(`installTenantGuard`) 우회 경로를 만들지 않는다

---

## 7. 위험 / 되돌리기 어려운 것

| 위험 | 방어선 |
|---|---|
| 「영원히 만족시킬 수 없는 항목」 → Square 의 59% 고착 | 모든 항목 dismissible + 분모 = applicable + 전체 영구 닫기 |
| 투어 폐지 시 기존 사용자 혼란 | 기존 사용자는 `hidden_at` 을 채워 **아예 안 보이게** 배포 (신규 매장만 대상) |
| 술어가 무거워 홈이 느려진다 | 단일 쿼리 + 60초 캐시 + `completed` 이벤트 우선 조회 |
| 단계 정의를 바꾸면 기존 매장 상태가 튄다 | 카탈로그에 `version`, 완료 이벤트가 있는 매장은 구 정의 유지 |
| 업종 질문만 하고 분기하지 않음 | W3 에서 분기 구현이 안 되면 **질문을 뺀다**(순수 마찰) |
| `store_owner` role 미배정 시 로그인 불가 경로(`auth.service.ts:748`)가 가이드 도입으로 더 드러난다 | W1 에서 provision 실패를 **명시적 오류**로 승격 (별건이지만 같은 경로) |

---

## 8. 사용자 결정 — **완료 (2026-09-09)**

| | 질문 | 결정 |
|---|---|---|
| D-A | 위저드 단계 수 | **3단계 유지** — 업종 질문 포함, **실제 분기 구현이 조건**(D-11) |
| D-B | 체크리스트 8항목 | **그대로 확정** — §3-1 카탈로그가 최종 |
| D-C | 기존 운영 매장 노출 | **보이지 않게 한다** — 마이그레이션에서 `hidden_at` 백필(D-12) |
| D-D | 문구 관리 | **i18n 키 사용, 전환 스위치는 만들지 않음**(D-13, 근거 §3-4) |

**남은 열린 항목 하나** — **voseo(configurá/tenés) vs tuteo(configura/tienes)**.
목업과 초안은 **voseo** 로 썼다(아르헨티나 구어 기준). 사전 파일 한 곳만 고치면 되므로
구현을 막지 않는다. 실제 매장 사장님에게 확인되면 `es.json` 에서 일괄 교체한다.

## 9. 근거

- 실측: `88-CONTEXT.md`
- 목업: `.planning/mockups/onboarding-setup-guide/guia-configuracion.html` (화면 5종, 상호작용 가능) — https://claude.ai/code/artifact/4c248621-b2da-4068-b537-2a3219ed0fa1
- 외부 사례·수치 원문 출처는 CONTEXT §2 표에 URL 로 있다
