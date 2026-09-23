# precio1 을 precio base 로 — legacy import 가격 계약 변경

사용자 요구(2026-09-23):
> 「legacy importacion 을 할 경우 **precio base 는 없애지 말고, precio1 은 precio base 로
>  인식해서 precio2 부터 적용**하게 하면 좋겠어.」
범위: **앞으로의 import 만**(사용자 확정). 기존 매장 데이터는 건드리지 않는다.

근거: codex 자문 전문 `.team/reviews/manual-precio-codex.md`

---

## 1. 증상과 원인 (실측)

store 19(NOIX) — 「productos nuevos 에서 제품을 새로 생성할 때 precio base 가 안 보인다」.

**`precio1` 이 두 군데에 저장된다:**

| 위치 | 값 |
|---|---|
| `code-import.service.ts:857` | `products.price = row.price1 ?? row.price ?? 0` ← precio base |
| `code-import.service.ts:982` | slot 1 → `prices` 행(`PRECIO 1` 유형) = **같은** `row.price1` |

그 중복을 프론트가 흡수한다 — `ventago-app/src/utils/price-types.ts:12`
```ts
return inc === 0 && /^precio\s*(1|base)\b/i.test(name);
```
이런 유형을 동적 목록에서 빼고 **그 이름으로 「Precio base」 박스 라벨을 덮어쓴다**
(`BasicDataCard.tsx:184` → 렌더 `:1072`). ⤷ 「Precio base」 글자가 사라진다.

★ store 19 현재 상태(2026-09-23 12:07~12:09, 사용자가 직접): PRECIO 2~5 를 status=0 으로
  비활성화. PRECIO 1(storeEntityId=1, inc 0, status 1)은 **그대로 남아 있다.**

---

## 2. codex 가 짚은, 내가 못 본 위험 3건 — **전부 직접 확인했다**

### [P1-a] 기준가 소비 경로가 `products.price` 를 **맨 마지막**에 본다

`api-ventago/src/app/products/menu-price.util.ts:71`
```ts
const base =
  rows.find((r) => normalizeTypeName(r.priceType?.name) === 'precio1') ??
  rows[0];
const amount = Number(base?.amount ?? product.price ?? 0);
```
→ `prices` 행이 하나라도 있으면 **그게 이긴다.** `rows[0]` 은 **정렬 보장이 없다.**

★ 범위 정정: 이 함수를 쓰는 곳은 **식당 경로뿐**이다
  (`restaurant-sale.service.ts:99`, `restaurant-delivery.service.ts:168·699`).
  일반 POS 판매는 이 경로가 아니다 — codex 표현보다 좁다.

### [P1-b] 백엔드에도 **이름 기반** 기준가 판정이 따로 있다

`api-ventago/src/app/products/productsPrice.service.ts:427` (주석 원문)
> base = name 에 'PRECIO' 포함 + increaseValue=0 (frontend isBaseLike 조건과 일치).
> base 가 변경되면 product.price 컬럼도 함께 update

→ 프론트 정규식만 고치면 **백엔드가 계속 이름으로 판정한다.**
  store 15 처럼 `PRECIO 1` 인데 inc=4000 이면 놓치고,
  수동 유형(inc=0)이 `PRECIO` 를 포함하면 **기준가로 오인**한다.

### [P1-c] 부모·자식·합성부모의 기준가 출처가 제각각이다

- 부모 `products.price` ← `todocodigos.pre1` (`legacy-import.service.ts:596`)
- 자식 `products.price` ← `codigos.pre1` (`:689`)
- `price2~5` 는 **자식 경로에서만** 기록 (`code-import.service.ts:900`)
- 합성 부모는 **처음 만난 자식**의 price1 을 쓴다 (`:809`) → 입력 순서에 따라 달라진다

---

## 3. 핵심 제약 — slot 매핑이 위치 기반이다

`code-import.service.ts:159-172`
```ts
order: [['storeEntityId','ASC'], ['id','ASC']], limit: 5
priceTypes.forEach((pt, idx) => priceSlotMap.set(idx+1, pt.id));
```
**slot 번호 = 정렬 순서.** 앞에서 하나만 빠져도 전부 한 칸 밀린다.

그리고 `ensurePriceTypes`(`legacy-import.service.ts:486`)는 **총 개수만** 본다 —
`count>=5` 면 아무것도 안 한다. 매장에 무관한 유형이 5개 있으면 `PRECIO 2~5` 가
하나도 없어도 «충분하다» 고 오판한다.

⤷ **「PRECIO 1 을 안 만든다」만 하면 기존 첫 유형이 무엇이든 `pre2` 대상이 된다.**
  store 6(PRE.21) · 9(DESC.5) · 15 · 17 은 정렬 위치가 레거시 슬롯을 **보장하지 않는다.**

---

## 4. 설계 (codex 권고 수용)

### 4-1. 명시적 슬롯 키 — 위치 의존 폐기

`price_types.legacy_slot` (nullable, 허용값 **2..5**, `(store_id, legacy_slot)` UNIQUE).
- `legacy_slot IS NULL` = 일반 가격유형, import 대상 아님
- import 는 `WHERE legacy_slot IN (2,3,4,5)` 로 **직접** 매핑
- `ensurePriceTypes` 는 총 개수가 아니라 **슬롯 2~5 각각의 존재**를 보장
- 슬롯이 중복·누락인데 만들 수 없으면 **import 중단**(fail-closed)

★ 이게 없으면 **멱등성도 깨진다** — 같은 파일을 두 번 넣었을 때 매핑이 달라지면
  같은 `preN` 이 **다른 price_type 에 새 행**으로 생긴다.
  `(product_id, price_type_id)` UNIQUE 는 그걸 못 막는다.

### 4-2. 기준가의 원천은 `products.price` 하나

- `pre1` → `products.price` **만** 쓴다. `prices` 행을 쓰지 않는다.
- `is_base` 플래그를 **새로 만들지 않는다** — 이중 원천을 영구화한다(codex).
- 이름 기반 base 판정을 **프론트·백엔드 양쪽에서** 제거한다(P1-b).
- 기준가 소비 경로는 `products.price` 를 **명시적으로** 읽는다(P1-a).

### 4-3. 기존 매장 보호 — 스키마 버전

`legacy_price_schema`: `v1`(pre1 도 PRECIO 1 에 기록) / `v2`(이번 계약).
- 신규 매장 = v2
- **기존 매장은 명시적 전환 없이 v2 적용 금지**
- 프로필이 없고 가격 데이터가 있으면 **추론하지 말고 중단**

### 4-4. 정책 키 분리

`pricePolicies.p1` 의 뜻을 조용히 바꾸지 않는다 → **`pBase`** 로 분리.
v2 에서 `p1` 은 거부하거나 deprecated.

### 4-5. UI

「Precio base」 라벨을 **항상 고정**한다(`BasicDataCard.tsx:1072`).
필요하면 보조 문구로 «Importado desde precio1» 만 덧붙인다.

---

## 5. 착수 순서

| # | 하는 것 | 데이터 |
|---|---|---|
| 1 | 기준가 소비 경로에서 이름/첫행 폴백 제거 (`menu-price.util.ts`, `productsPrice.service.ts`) | 없음 |
| 2 | 프론트 이름 기반 base 판정 제거 + 라벨 고정 | 없음 |
| 3 | `price_types.legacy_slot` 추가 (nullable) + UNIQUE — **expand** | INSERT only |
| 4 | `ensurePriceTypes` 를 슬롯별 보장으로 · import 가 `legacy_slot` 으로 매핑 | 없음 |
| 5 | `pre1` 의 `prices` 행 쓰기 제거 · `pBase` 정책 분리 | 없음 |
| 6 | `legacy_price_schema` 로 기존 매장 fail-closed | INSERT only |

★ 1·2 가 **먼저**다 — 그게 없으면 `products.price` 를 올바로 써도
  **판매에서 안 쓰인다.**

## 5-bis. 이름 기반 base 판정 — **전수 census** (2026-09-23)

codex 가 1건(`productsPrice.service.ts`)을 짚었는데, 세어 보니 **5개 파일**이었다.
(형태를 하나 고치면 그 형태를 전수로 세는 규칙 — 여기서도 지켰다.)

| 파일 | 위치 | 성격 | 상태 |
|---|---|---|---|
| `api/productsPrice.service.ts` | :455 | 기준가 판정 → `products.price` 를 덮는다 | ✅ 좁힘 |
| `app/utils/price-types.ts` | :12 | 공용 헬퍼 | ✅ 좁힘 |
| `app/views/homes/.../ProductsInputs.tsx` | :20 | **POS 판매 단가** | ✅ 공용 헬퍼로 통합(복사본 제거) |
| `app/views/codigo-vista/CodigoVistaView.tsx` | :537 | 셀 값 결정 | ✅ 공용 헬퍼로 |
| 〃 | :480·:712 | **정렬 + 그 정렬에 기댄 baseIdx** | ⏳ 보류 |
| 〃 | :1425 | 편집 모달의 `ptEditIsBase` 표시 플래그 | ⏳ 보류 |
| `app/views/branches/.../BranchPriceTypesCard.tsx` | :80·:81·:240 | 정렬 + `i===0` 결합 판정 | ⏳ 보류 |

★ **보류한 것들은 「정렬」과 「그 정렬 순서에 기댄 인덱스」가 짝이다.**
  `:480` 이 base 성격을 앞으로 보내고 `:712` 가 `findIndex` 로 첫 번째를 집는다.
  판정만 좁히면 **CodigoVista 의 열 순서가 바뀐다** — 그 화면을 실제로 열어 재기 전에는
  건드리지 않는다. `BranchPriceTypesCard:240` 은 `i === 0` 과 결합돼 이미 좁다.
  ⤷ 3단계(명시 표식)에서 **정렬 기준까지 함께** 옮긴다.

## 6. 이번 범위에서 **제외**

- 기존 매장(6·9·10·11·14·19)의 `PRECIO 1` 유형·`prices` 행 정리 — 사용자 확정
- 합성 부모 가격 정책 확정(P1-c) — 별도 결정 필요
- ACE 규칙 적용(`ace-price-rules.ts`) — 여전히 「저장만, 적용 안 함」
