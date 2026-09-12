---
phase: 88-store-onboarding-setup-guide
type: spec
version: 3
created: 2026-09-09
revised: 2026-09-09 (v2 사용자 결정 4건 → v3 적대적 검토 반영: 88-FINDINGS.md)
findings: 88-FINDINGS.md
branch: feature/phase88-onboarding-guide
status: CONFIRMED — 결정 완료. **CODEX 자문 회신 후** W1 착수
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
| **D-7** ✎v3 | **`/auth/me` 에는 요약만**(`hidden`, `progress`) 얹고, 상세·갱신은 홈에서만 호출하는 **`GET /setup-guide`** 로 분리한다 | v2 의 「새 엔드포인트 금지」는 **틀린 규칙이었다.** `/me` 는 앱 부팅 1회뿐이라(`AuthContext.tsx:69`) 상품을 등록해도 가이드가 갱신되지 않는다 — 비용이 없는 곳에서 비용을 아끼려다 제품을 못 쓰게 만든다(FINDINGS H-6). 사이드바 클릭마다가 아니므로 pool 규약과 무관 |
| **D-14** ✎v3 | 이름을 **`setup-guide`** 로 분리한다 — 모듈 `app/setup-guide/`, 테이블 `store_setup_steps`/`store_setup_events`, 컬럼 `stores.setup_hidden_at`, `/me` 필드 `setupGuide` | `app/onboarding/` 은 **이미 공개 가입 OTP 모듈**이고 `AuthModule` 을 import 한다 → 역방향 주입은 순환·부팅 실패(FINDINGS C-3) |
| **D-15** ✎v3 | 완료 판정에 **시각 비교를 쓰지 않는다.** 술어는 시드 상수와의 대조로만 | 「5분/1분」 규칙은 15분 TTFV 목표와 충돌하고, `updated_at` 을 건드리는 마이그레이션 한 번에 전 매장 판정이 뒤집힌다(FINDINGS C-2) |
| **D-17** ✎v3 | 업태(rubro)를 **저장하지 않는다.** 위저드 답 → 일회성 시드 + 기존 `FLAG_FIELDS` 플래그. 카탈로그는 `use_restaurant_mode` 에서 파생 | 상태를 두 곳이 소유하면 갈라진다. 그리고 이 스위치는 **이미 존재한다**(§3-1c) |
| **D-16** ✎v3 | **읽기 경로(`/me`)에서는 아무것도 쓰지 않는다.** 완료 고정은 `GET /setup-guide` 에서만, 실패해도 응답은 성공 | `auth.service.ts:1242-1251` 이 모든 예외를 401 로 바꾼다 → 기록 실패가 곧 **로그인 실패**(FINDINGS H-4) |
| **D-8** | 로그인 직후 모달 순서를 **코드로 고정**: ① 셋업 위저드(미완 시) → ② `SelectBoxTerminalModal` → ③ `NoticesBanner`. 앞의 것이 열려 있으면 뒤의 것은 열리지 않는다 | 현재 `disabled` prop 이 배선돼 있지 않아 겹칠 수 있다 |
| **D-9** | 기존 `OnboardingTour`/`OnboardingWrapper` **폐지**, `OnboardingDialog`·`SetupWizardView` **삭제**(문안만 이관) | 두 개가 겹쳐 뜨는 것이 지금보다 나쁘다 |
| **D-10** | 첫 화면 랜딩은 스텁인 `pages/index.tsx` 를 채워 쓴다 | 빈 자리가 이미 있다 |
| **D-11** | **위저드는 3단계 전부 유지.** 업종 질문은 **실제로 분기**한다 — `talles`/`colores` 시드가 달라지고 해당 없는 단계가 카탈로그에서 빠진다 | 사용자 결정 2026-09-09. 분기 없는 질문은 순수 마찰이므로, 분기 구현이 안 되면 질문을 빼는 것이 아니라 **분기를 만든다** |
| ~~**D-12**~~ ✎**폐기 2026-09-11** | ~~기존 운영 매장에는 보이지 않는다~~ → **기존 매장에도 보인다.** 마이그레이션은 **아무것도 숨기지 않는다** | 사용자 결정 2026-09-11 이 뒤집었다 — 「아직 100% 활용 못 하고 있으니 셋업을 마쳐서 잘 쓰게 하자」. ★ 이 폐기가 **CODEX P1-1**(마이그레이션↔배포 사이 생성분이 오분류)을 **통째로 없앤다** — 숨기는 UPDATE 자체가 사라지므로 경쟁 구간이 없다 |
| **D-18** ✨**신규 2026-09-11** | **자동 중단: 진행률 ≥ 70% **그리고** 매장 생성 후 7일 경과 → 가이드를 더 보여주지 않는다.** 저장하지 않고 파생한다 | 사용자 결정. ★ Square 59% 고착을 **사용자 조작 없이** 푸는 장치다 — 결제수단·프린터처럼 「시드 그대로 써도 되는」 항목이 영원히 빨갛게 남는 문제를 시간이 해결한다. 실측(운영 14개): 이 규칙으로 5곳이 숨고 9곳이 보인다 |
| **D-19** ✨**신규 2026-09-11** | **D-18 의 분모는 8 고정**이고, **「해당 없음」은 분자에 넣는다**(해결된 것으로 친다) | 사용자 결정(분모 8). ★ 분자에 안 넣으면 3개를 「해당 없음」 처리한 매장이 최대 5/8=62% 로 **영원히 안 사라진다 — Square 고착의 재현**이다. 그리고 분모가 8 고정이라 dismiss 만으로 70% 에 닿으려면 **3번** 눌러야 한다(종전 `applicable` 분모는 2번) |
| **D-20** ✨**신규 2026-09-11** | 술어의 의미는 **「사용자가 직접 눌렀는가」가 아니라 「운영 가능한 실데이터가 있는가」**다. 따라서 **레거시 임포트로 들어온 상품·가격·판매는 완료로 인정한다** | **CODEX P2-1** 이 두 의미가 섞여 있다고 지적했다. 이관 매장은 실제로 상품·가격·판매가 있고, 사용자 요구의 문장도 「100% 활용」이지 「직접 눌렀나」가 아니다. ⤷ `import_legacy` 단계는 **대체 경로**로 명시한다 |
| **D-21** ✨**신규 2026-09-11** | 문구는 **첫 판매 여부로 갈린다** — 판매 0건이면 「첫 판매까지 안내」, 판매가 있는데 빈 곳이 있으면 **「아직 100% 활용 못 하고 있습니다 — 셋업을 마쳐 주세요」** | 사용자 요구. 저장 없이 `first_sale` 술어에서 파생된다. 실측(운영 14개): 판매 0건 7곳 · 판매 있고 미완 7곳 |
| **D-13** | 문구는 **i18n 키**로 쓴다(`public/locales/es.json` 의 `onboarding.*`). **단 언어 전환 스위치는 만들지 않는다** — `lng:'es'` 고정 유지, `supportedLngs` 변경 없음, 감지기 부활 금지 | §3-4 |

### 3-1. 단계 카탈로그 (초안 — 8항목)

| code | 단위 | 완료 술어 | 비고 |
|---|---|---|---|
| `create_store` | 매장 | 항상 참 | 가입 시점 |
| `create_branch` | 매장 | 항상 참 | 시드 |
| `open_box_terminal` | 지점 | 항상 참 | 시드 |
| `load_products` | 매장 | `products` 에 `is_generic=false` 1건 이상 | ★ 맨 위 |
| `set_prices` | 매장 | `price_types` 1건 이상 — **시드가 없으므로 존재만으로 참**(v2 의 `price_type_ranges` 는 영원히 거짓이었다) | |
| `check_payment_methods` | 매장 | 시드 3종(`efectivo`·`tarjeta-debito`·`mercadopago`) 밖의 slug 가 있거나 시드 중 하나가 `is_active=false` | slug 상수는 `storeTemplate.service.ts` 에서 import |
| `connect_printer` | 지점 | `branch_agents` 에 `last_seen_at IS NOT NULL` — **`JOIN branches ... store_id` 필수**(테넌트 경계) | 「No aplica」 빈도 높음 |
| `first_sale` ★ | **매장** ✎v3 | `sales` 에 `activity_type='sale' AND nullified_by_sale_id IS NULL` 1건 이상 | `sales.branch_id` 가 nullable 이라 지점 단위로 두면 판매를 놓친다 |

★ v3 정정 3건(근거 `88-FINDINGS.md`): `price_types`·`price_type_ranges` 는 **시드되지 않는다** ·
`sales` 는 판매 전용 테이블이 아니다(`movido`/`fallado` 포함) · 시드 결제수단은 **3개**다.

### 3-1b. 업태(rubro) 분기 ✎v3 — 「실제로 분기시킬 것」의 실체

업태 선택지: `indumentaria` · `calzado` · `accesorios` · **`restaurante`** · `otro`.
분기가 가장 큰 것은 **레스토랑**이다 — 이미 제품 안에 있는 별개 업태다(실측):
`restaurant_tables`(store_id·branch_id·name·shape·seats·pos_x·pos_y·zone·status·current_sale_id) ·
백엔드 모듈 `restaurant-tables` / `restaurant-elements` / `restaurant-delivery` ·
프런트 `views/restaurante/{RestauranteShell, SalonView, DeliveryBoard}` ·
`sales` 의 `table_id`·`num_pedido`·`ordered_at`·`served_at`·`last_comanda_at`.

| 단계 | indumentaria / calzado / accesorios | restaurante |
|---|---|---|
| 4 | `load_products` 「Cargá tus productos」 — talles·colores 시드 | **`load_menu`** 「Cargá tu carta」 — 카테고리(entradas·principales·bebidas)만, talles·colores **없음** |
| 5 | `set_prices` (`price_types` 존재) | **`setup_tables`** 「Armá tu salón」 — `EXISTS(restaurant_tables WHERE store_id=$1 AND branch_id=$2)` · **지점 단위** |
| 7 | `connect_printer` — `eventually`(티켓 없이도 판다) | `connect_printer` — **`currently_due`**. 코만다가 없으면 **주문이 주방에 안 간다** |
| 8 | `first_sale` 「Hacé tu primera venta」 | `first_sale` 「Tomá tu primer pedido」 — 같은 술어, 다른 문구 |

⤷ **문구만 바꾸는 게 아니라 항목과 필수 여부가 바뀐다.** 이것이 D-11 이 요구한 「실제 분기」다.

### 3-1c. 업태 스위치 ✎v3 — **이미 존재한다. 새로 만들지 않는다** (실측 2026-09-10)

| | 실측 |
|---|---|
| 플래그 | **`store_configs.use_restaurant_mode`** — `boolean NOT NULL DEFAULT false`. 신규 매장은 `provisionStoreAndOwner`(`auth.service.ts:698-714`)가 이 값을 세우지 않으므로 **false 로 시작한다** |
| 켜는 API | **`PUT /store-config/:storeId/update-flag`** — `{ field:'useRestaurantMode', value:true }`. Phase 39 화이트리스트(`store/config/storeConfig.controller.ts:107-122` `FLAG_FIELDS`)에 이미 있다 |
| 사람이 켜는 화면 | `/configuracion/restaurante` → `views/configuracion/restaurante/RestauranteConfigView.tsx:62` (**`HUB_TABS` 에는 없는 별도 페이지** — M-6 의 딥링크 정정과 같은 사례) |
| 프런트 상태 | `StoreConfigContext` 의 `useRestaurantMode` (이미 전 화면에서 읽는다) |

⤷ **위저드는 이 스위치를 그대로 쓴다.** 앱 slug 도, 새 컬럼도, 새 엔드포인트도 필요 없다.

**D-17 ✎v3 — 업태를 저장하지 않는다.** 위저드의 답은 **일회성 효과 + 기존 플래그**로 표현하고,
카탈로그 선택은 **`use_restaurant_mode` 에서 파생**한다(D-2 와 같은 원리 — 상태를 두 곳이 소유하지 않는다):

| 답 | 위저드가 실제로 하는 일 (전부 `FLAG_FIELDS` 안) |
|---|---|
| `restaurante` | `useRestaurantMode=true` · `useSize=false` · `useColor=false` · `useSeason=false` · `useOrigin=false` → 상품 등록 화면이 카르타에 맞게 단순해진다 |
| `indumentaria` | 기본 유지(S–XXL 시드) |
| `calzado` | 사이즈 시드를 34–46 으로 교체(일회성) |
| `accesorios` | `useSize=false` |
| `otro` | 아무것도 하지 않는다 |

- 왕복은 **1회** — 플래그를 5번 PUT 하지 않고 `POST /setup-guide/rubro { rubro }` 가 서버에서
  같은 화이트리스트 로직으로 묶어 적용한다(단일 트랜잭션). **W3 태스크.**
- 부수 효과: 사장님이 나중에 Configuración 에서 식당 모드를 켜면 **체크리스트가 저절로
  레스토랑 카탈로그로 바뀐다.** 파생이라 공짜다.

`eventually_due` (체크리스트 밖, 「más adelante」 접이식): `invite_staff` · `electronic_invoicing`(ARCA) ·
`mercado_pago` · `online_shop` · `import_legacy`.

### 3-2. 응답 형태 (Stripe 차용) ✎v3 — 요약과 상세를 나눈다

`GET /auth/me` (부팅 1회 · 요약만):
```json
"setupGuide": { "hidden": false, "progress": { "done": 3, "applicable": 8 } }
```

`GET /setup-guide` (홈에서 가이드를 볼 때 · SWR dedupe 10초):
```json
{ "completed": ["create_store","create_branch","open_box_terminal"],
  "currently_due": ["load_products","set_prices","first_sale"],
  "eventually_due": ["invite_staff","electronic_invoicing"],
  "dismissed": ["connect_printer"],
  "progress": { "done": 3, "applicable": 8 },
  "hidden": false, "rubro": "indumentaria" }
```

### 3-3. 스키마 ✎v3 (추가만 · 기존 테이블 변경 없음)

```
store_setup_steps                 -- 저장하는 것은 「의도」와 「고정된 완료」뿐
  store_id int NOT NULL, branch_id int NOT NULL DEFAULT 0,   -- 0 = 매장 단위. FK 없음
  step_code varchar(40) NOT NULL,
  dismissed_at, snoozed_until, completed_at  timestamptz NULL,
  UNIQUE (store_id, branch_id, step_code)   -- 평범한 UNIQUE (COALESCE 표현식은 upsert 42P10)

store_setup_events                -- append-only 계측 원장
  store_id, branch_id, user_id, step_code, event, occurred_at
  UNIQUE (store_id, branch_id, step_code) WHERE event='completed'   -- 4워커 중복 방지
```

`stores` 에 컬럼 **1개**: `setup_hidden_at timestamptz NULL` (+ 기존 매장 전체 백필 — D-12).
술어 쿼리는 `FROM stores s WHERE s.id=$1` 로 시작해 `CASE WHEN s.setup_hidden_at IS NOT NULL
THEN NULL ELSE EXISTS(...) END` 로 **단락**한다 — 숨긴 매장은 PK 조회 1건으로 끝난다.

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
| 「영원히 만족시킬 수 없는 항목」 → Square 의 59% 고착 | 모든 항목 dismissible + 분모 = applicable + 전체 영구 닫기. **v2 의 `set_prices` 가 실제로 이 함정이었다**(FINDINGS C-1) |
| **마이그레이션이 배포보다 늦으면 `/auth/me` 500 → 전 사용자 로그인 불가** | 운영 5434 적용 확인 **전에는 push 금지**(PLAN TASK-1 게이트) |
| `branch_agents` 에 `store_id` 가 없고 raw query 는 테넌트 훅을 안 탄다 | `JOIN branches ... b.store_id=$1` + `branchId` 사전 검증 |
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
- **착수 전 적대적 검토: `88-FINDINGS.md`** (CRITICAL 3 · HIGH 6 · MEDIUM 11 — 전부 반영)
- 목업: `.planning/mockups/onboarding-setup-guide/guia-configuracion.html` (화면 5종, 상호작용 가능) — https://claude.ai/code/artifact/4c248621-b2da-4068-b537-2a3219ed0fa1
- 외부 사례·수치 원문 출처는 CONTEXT §2 표에 URL 로 있다
