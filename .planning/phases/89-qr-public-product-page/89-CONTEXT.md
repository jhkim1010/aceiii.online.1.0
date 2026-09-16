# Phase 89 — CONTEXT

작성: 2026-09-16. 출처는 사용자와의 직접 논의 + **운영 실측**이다.
추측으로 적은 줄은 없다. 수치에는 전부 출처가 붙어 있다.

---

## 이 phase 가 실제로 무엇인가

**「QR 시스템을 만드는」 일이 아니다.** 인쇄는 이미 되고 있고 **도착지가 없다.**

운영 실측(2026-09-16):

```
QR 내용:  ${PUBLIC_WEB_URL}/m/stock?s={storeId}&p={parentProductId}
결과:     https://app.coolsistema.com/m/stock?s=6&p=1  →  308  →  404
```

`qr_print_log` 운영 **5행**, 최근 **2026-09-08**, 지점 6.
⤷ **매장에 이미 붙어 있는 라벨이 지금 404 로 떨어진다.** 그것을 살리는 것이 첫 가치다.

---

## 이미 있는 것 (새로 만들지 말 것)

| | 근거 |
|---|---|
| QR 인쇄 전 경로 | zebra-agent `^BQN,2,4^FDQA,…` + 자동 크기맞춤(`effectiveQrModule`) · 프론트 「QR DINÁMICO」 패널 · NUEVO/CAMBIO 델타 |
| 인쇄 이력 | `qr_print_log`(branch_id · product_id · price_type_id · printed_price · printed_name), 유니크 `uq_qr_print_log_branch_prod_pt` |
| 공개 서버렌더 HTML 패턴 | `GET /api/public/shop/:storeId/store` → **200**. 다크 네이비+골드 단일 HTML, 같은 오리진에서 공개 API 호출 (CORS 불필요) |
| 공개 카탈로그 API | `:storeId/products` · `:storeId/products/:slug` · `:storeId/categories` · `:storeId/theme` — 전부 `@Public()` |
| reseller 백엔드 | `reseller` **스키마**(resellers · reseller_tienda_link · reseller_documents) + `POST reseller/auth/register`(`@Public()`) |

## 없는 것 (만들어야 함)

| | 근거 |
|---|---|
| QR 도착지 페이지 | 위 404 |
| QR 안의 지점 | URL 에 branch 가 없다. `qr_print_log` 는 아는데 안 싣는다 |
| reseller 신청 **화면** | 백엔드 테이블 **전부 0행 — 한 번도 안 쓰임**. 빌드되는 앱 목록(admin-app · despacho-app · edge-agent · mobile-sales-app · print-agent · tienda-admin-app · zebra-agent)에 reseller 포털이 없다 |
| Ventago 리드 수집 | **아무것도 없다** |

---

## 사용자 결정 (2026-09-16)

### ① 가격 — **현재 가격을 보여주고, 라벨과 다를 때만 병기한다** (2026-09-16 개정)

★★ **개정 이유 (CODEX 자문 P1, 근거 대조 완료).** 종전 ⓐ 는 가격**유형**을 따라갈 뿐
**인쇄된 숫자**를 따라가지 않는다. 인쇄 뒤 `prices.amount` 가 바뀌면 종이와 화면이 갈린다.
`qr_print_log.printed_price`(double, NOT NULL)가 **인쇄된 숫자를 이미 보관하고 있다** —
종전 결정은 ⓐ vs base 만 비교했고 이 선택지는 비교 대상에 없었다.

**확정 (사용자, 2026-09-16):**
- **주 표시는 그 가격유형의 현재 가격**이다 (종전 ⓐ 의 조회 규칙 유지).
- **`printed_price` 와 다를 때만** 「라벨 표기 $X — 가격이 변경됐습니다」를 **병기**한다.
  같으면 아무것도 덧붙이지 않는다.
- ⤷ 고객이 종이를 들고 와도 설명이 되고, 매장은 가격을 올릴 수 있다.

**함께 확정된 것 — `prices` 에 UNIQUE 를 준다.**
`(product_id, price_type_id)` 에 UNIQUE 가 없어 「현재 가격」이 중복행 중 임의로 정해질
수 있었다(`productsPrice.service.ts:150` 주석이 명시). 운영 실측 2026-09-16:

```
prices 총 1,607행 · (product_id, price_type_id) 중복 0 · 두 컬럼 NULL 0
soft-delete 컬럼 없음 · 교차 매장 prices 행 0 (trg_tenant_prices_store 가 막고 있다)
```

⤷ **정리 작업 없이** `CREATE UNIQUE INDEX CONCURRENTLY ... NULLS NOT DISTINCT` 가 통과한다.
  ★ 두 컬럼이 nullable 이라 기본 UNIQUE 는 NULL 을 서로 다른 값으로 본다 →
    `NULLS NOT DISTINCT`(PG15+, 운영·로컬 모두 PG18) 로 못 박는다.
  ★ `upsertPrices` 는 「조회 후 id 를 실어 갱신」이다. conflict target 이 생기므로
    `ON CONFLICT` 로 바꾼다 — 안 바꾸면 경합 시 **조용한 중복이 제약 오류(500)** 가 된다.

---

### ①-종전 (2026-09-16 오전, 위 개정으로 대체됨) — ⓐ 인쇄 당시 가격유형을 따라간다

`qr_print_log.price_type_id` 를 되찾아 **그 유형의 현재 가격**을 보여준다.
라벨과 화면이 항상 같은 값을 말하게 하는 것이 목적이다.

**왜 base 가 아닌가 (실측):** store 6 의 `PRECIO 1`(price_type 11)은
**가격 행 17건 중 14건이 `products.price`(base)와 다르다.**
지금까지 인쇄된 5건은 그 상품에 PRECIO 1 행이 **없어 base 로 폴백**해 우연히 일치했다.
base 를 보여주면 언젠가 **종이와 화면이 고객 앞에서 다른 가격**을 말한다.

**구현 전제 4가지 (전부 확인됨):**
1. 유니크 인덱스가 **있다** — `uq_qr_print_log_branch_prod_pt (branch_id, product_id, price_type_id)`.
   `bulkCreate(updateOnDuplicate)` 가 실제 upsert 로 동작한다.
2. ★ 유니크 키에 `price_type_id` 가 있어 **같은 상품이 가격유형별로 여러 행**이 될 수 있다
   (현재 0건이나 구조상 가능) → 조회는 **`printed_at` 최신 1건**으로 확정한다.
   「아무 행이나」 고르면 가격이 날마다 달라 보인다.
3. ★ `qr_print_log` 에 **`store_id` 가 없다** → `products` 조인으로 테넌트를 강제한다.
4. ★ **인쇄 기록이 없는 라벨**은 가격유형을 모른다. 폴백을 정해야 하고,
   **폴백에서는 일치 보장이 성립하지 않는다** — 화면이 그 사실을 숨기지 말 것.

### ② 재고 — **이 phase 의 공개 상품 페이지에서는 공개하지 않는다**

수량은 **판매원 전용 앱**으로만 본다. 이 phase 가 만드는 응답에서 수량 필드 자체를
내보내지 않는다. (경로 이름이 `/m/stock` 이지만 공개 화면의 성격은 재고가 아니다.)

★★ **다만 기존 공개몰은 이미 재고를 공개하고 있다 (실측 2026-09-16).**
  `GET /api/public/shop/6/products` → `"stock":21` · `"stock":369` 가 인증 없이 나온다.
  · `shop-catalog.service.ts` 가 `stock` 을 **항상** 내보낸다(104행, SQL 도 무조건 SELECT).
  · `stockClause`(158행)는 표시 여부가 아니라 **필터**다(재고 0 상품을 목록에서 뺄지),
    그나마 **요청 파라미터**이지 매장 설정이 아니다.
  · `store_themes` · `store_configs` 어디에도 재고 표시 스위치가 **없다**
    (`allow_sale_without_stock` 은 판매 허용 설정이라 무관).
  ⤷ 즉 **공개몰을 켜면 수량이 숫자 그대로 공개되고 매장이 끌 방법이 없다.**
  ⤷ 이것은 **이미 배포돼 쓰이는 동작**이라 이 phase 에서 조용히 바꾸지 않는다.
    **Phase 90 으로 분리**했다.

### ③ 열거 — **온라인 tienda 를 켠 매장만**

안 켠 매장은 **찍은 그 상품만** 보여준다(목록·카테고리·검색 없음).

`stores.slug` 가 곧 공개몰 활성 플래그다 — 운영 **14개 매장 중 2개만** 있다
(6=`cool`, 9=`stock`).

★ **이미 인쇄된 라벨과 충돌하지 않는다.** 인쇄된 5건은 전부 store 6 이고 공개몰이
켜져 있어 연번 `p=` 노출이 허용되는 쪽이다. 불투명 토큰은 **공개몰 미활성 매장에만**
필요하므로 기존 라벨을 죽이지 않고 도입할 수 있다.

### ④ 설정 스위치 — **기본값 꺼짐** · 꺼졌을 때의 동작은 3갈래

Admin·Configuración 에 「구입자가 QR 로 가격을 볼 수 있게 할 것인가」를 둔다.
`store_configs` 의 기존 boolean 명명(`use_*` · `commerce_auto_sync` · `vto_enabled`)을 따른다.

기존 14개 매장이 전부 꺼짐으로 시작하므로 **켜기 전까지 아무것도 바뀌지 않는다**(배포 안전).

**QR 을 찍었을 때 — 3갈래 (사용자 확정 2026-09-16):**

| QR 가격 설정 | virtual tienda(`stores.slug`) | 결과 |
|---|---|---|
| **켜짐** | 무관 | **상품 상세** — 매장 · 지점 · 사진 · 가격 |
| **꺼짐** | 켜짐 | **공개몰 목록**으로 보낸다 |
| **꺼짐** | 꺼짐 | **아무것도 안 보인다** (닫힘 화면) |

⤷ 보여줄 것이 있으면 막다른 길이 안 되고, 없으면 명확히 닫힌다.

★ **이 설정은 「가격을 숨기는」 것이 아니라 「상품 상세 딥링크」를 통제하는 것이다.**
  가격은 **이미 종이 라벨에 인쇄돼 있다** — 라벨을 든 사람은 눈으로 이미 본다.
  그 사람에게 화면에서만 가격을 숨기는 것은 아무것도 보호하지 못하고
  「종이엔 있는데 화면엔 없다」는 모순만 만든다.

★★ **꺼짐+공개몰켜짐 조합에서는 결국 가격이 보인다 (실측).**
  `GET /api/public/shop/6/products` 가 인증 없이 **200** 이고 응답에 `price` 가 있다.
  이것은 모순이 아니라 **범위의 차이**로 정의한다 — 찍은 상품 하나 vs 목록 전체.

### ⑤ 페이지 끝의 두 갈래 CTA

- **이 매장의 reseller 가 되시겠습니까?** → 그 매장으로 연결되는 신청
- **당신의 매장에도 같은 시스템을?** → **기존 가입 화면 `/register`** (아래 개정)

#### ⑤-개정 (사용자, 2026-09-16) — CTA ② 의 도착지는 **이미 있는 `/register`** 다

새 리드 폼이 **주 도착지가 아니다.** 「당신 매장에도 이 시스템을」은
**기존 매장 가입 화면**으로 보낸다: `/register?ref={QR 매장의 apodo}`.

**② 실측으로 확인한 것 (2026-09-16):**

| | 근거 |
|---|---|
| 라우트 실재 | `ventago-app/src/pages/register/index.tsx` — `BlankLayout` + `guestGuard = true` (무인증 접근 가능) |
| 추천인 필드 실재 | `RegisterForm.tsx:422` 「¿Quién te recomendó? (opcional)」 → `referredByApodo`, blur 시 `GET /onboarding/referral/check?apodo=` 조회 (`@Public()`) |
| 보상 구조 실재 | `referral_credits` — 추천한 매장이 **월사용료의 50% bonificación** (`percent` 기본값 50) |
| **실사용 중** | 운영 `pending_registrations` **9행**, 그중 **3행**이 `referred_by_apodo` 를 담고 있다 |
| 매장 apodo | store 6 = `cool` · store 9 = `Stock` (`stores.alias_name`) |

★★ **그래서 귀속이 리드 테이블이 아니라 실제 돈으로 흐른다.** 새 테이블을 만들어
  「누가 어느 매장 QR 에서 왔는지」를 따로 기록할 이유가 사라진다 — 이미 있는
  추천 경로가 그 일을 하고 **보상까지 준다.**

★ **아직 실행된 적 없는 절반이 있다:** `referral_credits` 운영 **0행**.
  보상은 승인 시점에 생기므로, **추천 가입이 승인까지 간 적이 없다**는 뜻이다.
  「추천하면 보상을 받는다」를 화면에 단정해 적기 전에 그 경로를 확인할 것.

★ **지금은 `?ref=` 프리필이 안 된다.** `RegisterForm.tsx` 에 `useRouter` 가 **없다**
  (`defaultValues` 가 정적이다). 쿼리에서 읽어 `referredByApodo` 를 채우는 것이
  이 phase 가 더할 유일한 변경이다.

★ `guestGuard = true` 라 **로그인 상태면 튕긴다.** QR 을 찍는 사람은 보통 비로그인이라
  문제없지만, 자기 매장 직원이 찍으면 가입 화면에 못 간다 — 그 동작을 확인하고 적을 것.

#### 리드 폼은 **이탈 받이**로 남긴다 (사용자 확정 2026-09-16)

`/register` 는 **CUIT · 주소 · 비밀번호 · 방문검증 동의 · 이메일/WhatsApp 이중 OTP** 를
요구한다. 매장 계산대 앞에서 폰으로 끝까지 채우기엔 문턱이 높다.

⤷ **가입이 주(主), 리드 폼이 종(從)이다.** 가입 화면까지 갔다가 이탈하는 사람을 위해
  「연락처만 남기기」를 **작게** 남긴다. 목업의 「Ventago para tu negocio」 화면이
  이 역할을 한다 — **주 도착지가 아니라 이탈 받이**로 위치를 바꾼다.

★ **「받는 곳」을 먼저 정한다.** 받는 곳이 없으면 수집은 사라진다(ROADMAP W5 가 이미
  경고했고, CODEX 도 같은 지적을 했다 — 알림 실패가 침묵하면 리드는 테이블에만 쌓인다).

★★ 이 저장소에는 **없는 페이지로 보낸 전례**가 기록돼 있다(막다른 CTA).
   도착지가 **실제로 열리는지**를 검사로 못 박지 않으면 「버튼은 있는데 눌러도
   아무 일 없음」이 된다. 두 도착지 모두 현재 **없거나 한 번도 안 쓰였다.**

---

## 제약과 함정 (이 저장소 고유)

- **URL 을 바꾸지 않는 것이 기본안.** 바꾸면 이미 붙은 라벨이 영구히 죽는다.
- `/m/stock` 은 **프론트 호스트**(app.coolsistema.com)다. 서빙 위치가 미결 —
  ⓐ Next.js 공개 페이지(★ 이 저장소는 홈 라우트를 AclGuard 가 가로챈 전례가 있다) ·
  ⓑ nginx 가 그 경로만 API 로 프록시 · ⓒ 그 외. **연구 단계에서 결정한다.**
- `@Public()` 라우트는 **테넌트 가드를 무력화한다** → `storeId` 를 코드에서 직접 강제.
- 공개 응답은 **내보내는 필드를 명시적으로 고른다.** 이 저장소에는 `SELECT *` 가
  OAuth 토큰을 실어 보낸 전례가 있다 — 「무엇이 빠졌나」가 아니라 **「무엇이 새로 나가나」**를 센다.
- `reseller` 는 `public` 이 아닌 **별도 스키마**다. 전 테이블 훑는 검사·백업·purge 에서 빠지기 쉽다.
- 이미지 URL 은 `{API_HOST}/minio/{fileName}` — 공개 접근 가능 여부를 확인할 것.
- 마이그레이션은 **로컬 5432 + 운영 5434 동시 적용**, 무중단 규약(additive·nullable) 준수.

---

## 성공 판정 (이 셋이 다 되면 끝)

1. 매장에 붙어 있는 **실물 라벨을 폰으로 찍어** 페이지가 열린다 — 계정 없이.
2. 그 페이지가 **매장 · 지점 · 상품 사진 · 가격**을 보여준다. 가격은 **그 가격유형의 현재
   가격**이고, `printed_price` 와 **다를 때만** 「라벨 표기 $X — 가격이 변경됐습니다」가
   함께 보인다(같으면 병기가 **없다** — 이 「없음」도 판정 대상이다).
3. 두 CTA 를 **끝까지 눌러** 각각 실제 화면에 도달한다(막다른 곳 없음).
