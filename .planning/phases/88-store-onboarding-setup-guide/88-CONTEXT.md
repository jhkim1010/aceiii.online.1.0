---
phase: 88-store-onboarding-setup-guide
type: context
created: 2026-09-09
status: 실측 완료 — SPEC 의 근거 문서
---

# Phase 88 — CONTEXT · 신규 매장 온보딩 실측

이 문서는 **지금 코드가 실제로 어떤 상태인지**와 **바깥 세상이 검증해 둔 것**을 적는다.
결정은 `88-SPEC.md` 에 있다. 충돌하면 SPEC 이 이긴다.

---

## 1. 코드 실측 (2026-09-09, 저장소 직접 확인)

### 1-1. 매장 생성 경로는 **두 벌**이다 — 여기가 첫 함정

| 경로 | 진입 | 파일 |
|---|---|---|
| 공용 (셀프가입·OTP 자동개통·superadmin 승인 3경로가 여기로 수렴) | `provisionStoreAndOwner()` | `api-ventago/src/app/auth/auth.service.ts:671` |
| superadmin 콘솔 전용 | `POST /store/new` — 컨트롤러가 `create()`+`storeConfig`+`createStoreDefaults()` 를 **직접 조립** | `api-ventago/src/app/store/store.controller.ts:169` |

★ 온보딩 상태 초기화를 한쪽에만 넣으면 **superadmin 이 만든 매장은 상태가 비어 있다.**

### 1-2. 신규 매장은 **비어 있지 않다**

`StoreTemplateService.createStoreDefaults()` (`store/storeTemplate.service.ts:85`, 단일 트랜잭션)가
storeApps 6 · branch · box · terminal · **roles 8종** · cliente «Consumidor Final» ·
categoría «General» · subcategoría · ~~producto genérico~~(✎v3: `createDefaultGenericProduct` 는 `_storeId` 를 쓰지 않고 전역에 제네릭이 있으면 아무것도 만들지 않는다 — 실제 제네릭은 첫 빠른판매 때 `products.service.ts:550` 이 지연 생성한다) · proveedor · temporada · origen ·
colores · talles · **medios de pago 3종(`efectivo`·`tarjeta-debito`·`mercadopago`)** · transportes · etapas · roleFunctions · umbrales ·
configuration · 지출 카테고리 6종을 **전부 시드**한다.
**단 `price_types`·`price_type_ranges` 는 시드되지 않는다**(✎v3 실측 — `88-FINDINGS.md` C-1).

⤷ **「행이 0개인가」로 완료를 판정하면 신규 매장이 처음부터 100% 로 나온다.**
판정은 반드시 **「시드값에서 벗어났는가」** 여야 한다.

### 1-3. 온보딩 상태는 `users` 에만, 그것도 하나뿐

- `users.onboarding_completed boolean DEFAULT false` — `users/users.model.ts:86`, 스키마 `intel/db-schema-tables.md:3666`
- `stores`(32컬럼) · `store_configs`(36컬럼) · `branches`(12컬럼) 에는 **온보딩 관련 컬럼 0개**
- 마이그레이션 360개 중 온보딩 DDL **없음**

⤷ 지금 구조는 **「이 사용자가 투어를 봤다」** 이지 **「이 매장의 셋업이 끝났다」** 가 아니다.
직원 5명을 초대하면 5명이 각자 본다.

### 1-4. 이미 살아 있는 온보딩 UI 1개 + 죽은 코드 2개

| 파일 | 상태 |
|---|---|
| `ventago-app/src/components/OnboardingWrapper.tsx` (47줄) → `OnboardingTour.tsx` (347줄) | **동작 중.** `UserLayout.tsx:302` 에서 렌더. `onboardingCompleted===false` 면 2초 뒤 3스텝 스포트라이트 투어. 마커 `data-tour` 5곳 |
| `components/dialogs/OnboardingDialog.tsx` (167줄, MUI Stepper 4스텝, 스페인어 완성본) | **어디서도 import 안 됨.** 문안만 재활용 가치 |
| `pages/admin/store/setup-wizard.tsx` → `views/admin/store/SetupWizardView.tsx` (237줄) | **Phase 29 목업.** `apiConnector` 호출 0건, 라벨 전부 한국어, 금액 예시 `₩`. 라우트는 살아 있으나 아무것도 저장하지 않는다 |

### 1-5. 로그인 직후 화면에서 **최대 3개가 경쟁**한다

- `SelectBoxTerminalModal` — `UserLayout.tsx:90` 이 `/cash-register/status` 를 보고 `:103` 에서 연다
- `OnboardingTour` — 2초 지연(위 모달을 피하려는 장치). 그런데 `OnboardingWrapper` 의 `disabled` prop 은 **선언만 있고 배선돼 있지 않다**
- `NoticesBanner` — superadmin 공지 배너 (읽음 상태 패턴이 이미 검증돼 있다 — 참고 모델)

### 1-6. 첫 로그인 판별과 리디렉션

- `POST /auth/login` 응답에 **`onboardingCompleted` 가 없다** (`auth.service.ts:599-610`)
- `GET /auth/me` 응답에는 있다 (`:1163`, `:1225`)
- `AuthContext.tsx:226` 이 `window.location.href` 로 **전체 리로드** → 결과적으로 `/me` 를 타므로 값이 채워진다.
  **로그인 응답만 보고 판단하는 코드를 새로 쓰면 `undefined` 를 받는다.**
- `getRedirectUrl` (`AuthContext.tsx:36`) 폴백은 `/` = `pages/index.tsx` 인데 내용이 `<>Home Page</>` **스텁**이다 — 가이드 랜딩으로 비어 있는 자리

### 1-7. 추가 쿼리 0 지점 ★ pool 규약

`me()` 는 이미 `Promise.all` 로 **`Store` 행 전체**를 가져온다 (`auth.service.ts:930-960`).

- `stores` 에 온보딩 컬럼을 얹으면 **`/me` 는 추가 쿼리 없이** 값을 얻는다. 응답 조립부 두 곳에 한 줄씩.
- 별도 `GET /onboarding/status` 를 만들면 **요청당 1왕복 + 커넥션 1개**가 는다. 「사이드바 클릭 P95 ≤ 300ms」 규약에 불리하다.
- DB 접근은 전부 **Sequelize** (`database/database.module.ts`, 워커당 `max:20` · pgbouncer transaction mode).
  앱 코드에 `pool.connect()/release()` 수동 관리는 없고, 원시 `new Pool()` 은 `shop-readonly-db.service.ts:101` 한 곳뿐(공개 상점 전용, 무관).
  **이 phase 에서 새 풀을 만들지 않는다.** 트랜잭션은 `sequelize.transaction()` + `{ transaction }` 전달.

### 1-8. 재사용할 최대 자산 — 설정 지도가 이미 있다

`ventago-app/src/pages/configuracion/index.tsx:53-67` 의 **`HUB_TABS`** 배열: 13개 탭이
`section`(General/Operación/Avanzado) + `requiredApps`/`requiredModules`/`requiredPrivileged` 게이트와
함께 한 곳에 선언돼 있고, 딥링크 규약 `/configuracion?tab=<key>` 도 여기서 처리된다(`:104`).
체크리스트의 이동 목적지는 **전부 이 규약을 쓴다.**

셋업 항목별 화면·API 대응표는 조사 원본에 있다(주요 항목):
지점 `/sucursales`→`/branch`, 사용자 `/usuarios`→`/users`, 가격 `/precios`→`/price-types`,
결제수단 `configuracion?tab=ventas`→`/payment-methods`, 프린터 `/sucursales/[id]/impresora`→`/print/agents`,
카하 `/caja`→`/cash-register/open`, ARCA `CertificadoCard.tsx`→`/afip/cert`, MP `/mercadopago/oauth/*`.

### 1-9. 프런트 실태

Next.js 13.5 (Pages Router) + React 18 + **MUI 5** + Redux Toolkit(인증·지점은 Context) + **SWR**(훅 80여 개) +
RHF/Yup + AG Grid. **i18n 사전이 141줄뿐**이고 `lng:'es'` 고정 — 화면 문구는 대부분 **JSX 하드코딩 스페인어**.
범용 `EmptyState` 컴포넌트 **없음**(talleres 에만 3개). 범용 Stepper **없음**(MUI Stepper 를 6곳이 각자 사용).

---

## 2. 바깥 세상이 검증해 둔 것 (핵심만)

| 사실 | 출처 |
|---|---|
| **「온보딩 5단계 초과 금지 — 단계가 늘면 머천트가 이탈한다」** (Shopify 공식 문구) · 단계는 **자동 완료 표시**(automatic completion markers) · 카드는 개별 dismissible · 오래 걸리는 단계엔 «Remind me later» | shopify.dev/docs/apps/design/user-experience/onboarding |
| Setup guide 는 **접이식 + 「0 out of 3 steps completed」 분수 표시** 로 규격화 | shopify.dev/docs/api/app-home/latest/patterns/compositions/setup-guide |
| Square 9단계 중 **강제 게이트는 본인확인/결제 검증뿐**, 상품·팀·하드웨어는 뒤로 | squareup.com/help/gb/en/article/5123 |
| ★ **Square 실패 사례**: 진행률이 «59% 에 고정», 닫기 버튼 없음, 안 쓰는 기능(키오스크·주방)을 계속 요구 → 모더레이터도 못 고침 | community.squareup.com/…/td-p/746410 |
| **체크리스트 완료율 평균 19.2% / 중앙값 10.1%** (188개 SaaS 계측) → 아래 항목은 아무도 안 본다. **가장 중요한 것을 맨 위에** | userpilot 2024 벤치마크(자사 계측) |
| Activation rate 벤치마크 **35% 내외**, 이커머스·마켓플레이스가 최저(첫 거래를 기준으로 잡기 때문) | Lenny(설문 500+) · Userpilot(62개사) |
| **Endowed progress**: 8칸 빈 카드 19% vs 10칸 중 2칸 선물 34% (요구량 동일, 세차장 300명) | Nunes & Drèze 2006, JCR 32 |
| **Goal-gradient**: 목표에 가까울수록 가속 (카페 스탬프 현장실험) | Kivetz, Urminsky & Zheng 2006, JMR 43(1):39–58 |
| **투어·코치마크는 과제 수행을 개선하지 못한다.** 힌트를 연달아 띄우면 유용성과 무관하게 더 빨리 닫는다. 단기기억 ≈20초 | NN/g — Mobile-App Onboarding · Instructional Overlays |
| Stripe 는 온보딩을 UI 가 아니라 **서버가 계산하는 요구사항 배열**로 모델링: `currently_due` / `eventually_due` / `past_due` / `errors[].reason` | docs.stripe.com/connect/handling-api-verification |
| Tiendanube(AR) 공식 5단계: 가입 → 디자인 → 첫 상품 → 결제수단 → 배송. 헬프센터가 **「영상은 아르헨티나 기준이라 결제·배송은 국가마다 다르다」** 고 명시 | tiendanube.com/blog/como-hacer-una-tiendanube |
| Mercado Libre 보이스: cálida · leal · alegre · curiosa. 자기비판 — *「el usuario no lee」* 전제로 단순화했더니 **로봇 같은 톤**이 됐다 | medium.com/mercadolibre-ux |

### 검증 실패 — 쓰지 말 것

Mercado Shops 온보딩 구조(403/robots 차단) · Shopify·Tiendanube 관리자 내부 UI(로그인 필요) ·
CACE 2025 모바일 구매 비중(공개 요약 미수록) · **「Facebook 10일 7친구」「Slack 2,000 메시지」 류 aha moment 수치(1차 출처 없음)** ·
아르헨티나 소상공인 디지털 리터러시 정량 자료 · voseo/tuteo 제품 UI 가이드라인.

⤷ **voseo 여부는 검색보다 실제 사용자에게 묻는 게 빠르다.** 우리는 이미 매장을 운영 중이다.

---

## 3. 이 실측이 SPEC 에 강제하는 것

1. 완료 판정은 **시드 대비 변화**여야 한다 (1-2)
2. 상태의 단위는 **`store_id`**, 일부는 **`branch_id`** (1-3, 프린터·카하·가격은 지점 단위)
3. 상태는 **`/me` 에 실어 보낸다** — 새 엔드포인트를 만들지 않는다 (1-7)
4. 매장 생성 **두 경로 모두** 초기화해야 한다 (1-1)
5. 로그인 직후 모달 **순서를 명시적으로 정해야 한다** (1-5)
6. 모든 항목에 **「No aplica」**, 가이드 전체에 **영구 닫기** (Square 반면교사)
7. 진행률 분모는 **적용되는 항목 수**여야 한다 (같은 이유)
8. 투어를 늘리지 말고 **빈 상태**에 투자한다 (NN/g)

---

## 4. 추가 조사 (2026-09-11) — **이미 쓰고 있는 매장**에게 언제까지 권할 것인가

★ §2 의 조사는 전부 **신규 온보딩**에 관한 것이었다. 사용자가 2026-09-11 에
  요구를 바꾸면서(「기존 매장에도 보여 주자 — 아직 100% 활용 못 하고 있으니」)
  **다른 질문**이 생겼다: 이미 팔고 있는 매장에게 미완 셋업을 어떻게 권하고,
  **언제 멈추는가.** D-12(기존 매장 비노출)는 이 요구로 **뒤집혔다.**

| 발견 | 출처 |
|---|---|
| **멈추는 기준은 달력이 아니라 «행동»이다.** 「활성화(activation) 완료 **그리고** 3회 이상 사용」이면 넛지를 멈춘다. 활성화 전이면 사람이 개입하지 않고 자동 재참여만 한다 | hopscotch.club — SaaS onboarding framework |
| 「Day 3 두 번째 기능 넛지 · Day 7 팀 초대 넛지 — 단 **활성화를 못 했으면 건너뛴다**」 — 날짜와 행동을 **함께** 본다 | 같은 문서 |
| **빈도 캡 · dismissal 쿨다운 · 우선순위** 셋이 피로를 막는 통제 장치다. 사용자는 캠페인이 아니라 **합계**를 겪는다 — 각 캠페인 담당자는 자기 넛지가 합당하다고 본다 | digia.tech — Designing Non-Annoying Nudges |
| 알림 볼륨을 **30~40% 줄이자 CTR 이 올랐다** — 남은 메시지의 무게가 커진다 | courier.com — Reducing notification fatigue |
| 셋업 체크리스트와 **채택(adoption) 체크리스트는 다른 물건**이다. 전자는 계정을 구성하고, 후자는 「가입한 보람」이 증명되는 순간까지 데려간다 | hopscotch.club |

### ★★ 사용자 규칙(**70% 이상 + 일주일 경과 → 중단**)과의 대조

업계 통설은 **퍼센트가 아니라 활성화 이벤트**로 멈추라고 한다. Ventago 에서
그 이벤트는 자연히 **첫 판매**다. 그런데 **이 제품에서는 그 규칙이 틀린다**:

실측(2026-09-11 운영 14개 매장) — 두 규칙이 갈리는 곳은 **kim(16)** 하나다.
그 매장은 **팔았지만**(`first_sale=true`) 진행률이 **4/8 = 50%** 다 —
제네릭 제품만으로 판매했고 실제 상품도 가격유형도 등록하지 않았다.
「첫 판매하면 멈춘다」로 하면 **가장 도움이 필요한 매장이 안내를 잃는다.**

⤷ **퍼센트 기준이 이 제품에는 더 맞다.** 첫 판매는 **아무것도 설정하지 않고도**
  도달할 수 있기 때문이다(제네릭 제품 경로). 업계 heuristic 을 그대로 베끼면
  안 되는 자리다.

### ★★★ 남은 위험 — 「해당 없음」이 분모를 줄여 70% 를 **공짜로** 넘긴다

D-5 는 분모를 「적용되는 항목 수」로 둔다. 그러면 항목 2개를 「해당 없음」으로
누른 매장은 분모가 6 이 되어 **4개만 해도 67%**, 5개면 83% 다. 즉 **아무것도 더
설정하지 않고 dismiss 두 번으로 가이드를 끌 수 있다.**

- 이것이 **결함인지 기능인지는 결정 사항**이다. 「전체 영구 닫기」가 이미 있으므로
  끄고 싶은 사람에게는 더 쉬운 길이 있고, dismiss 는 「나에게 해당 없다」는
  **정직한 신고**로 볼 수도 있다.
- 반대 위험도 있다: 분모가 줄면 **의도치 않게** 70% 를 넘겨 조용히 사라진다.

⤷ 후보 ①: 70% 판정의 분모를 **8 고정**(dismissed 는 분자에도 분모에도 안 넣는다)
   후보 ②: 지금대로 `applicable` 분모 — dismiss 는 곧 「끄겠다」는 뜻으로 인정
   ★ 화면에 보이는 진행률과 **같은 값**을 쓸 것. 두 벌이면 「83% 인데 왜 계속 뜨나」가 된다.
