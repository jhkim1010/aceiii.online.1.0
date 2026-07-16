# 설계: 판매원 앱 Prueba Virtual — 게시 게이트 해제 + 버튼 게이팅 + 메시지 스페인어화

날짜: 2026-07-15
대상: `api-ventago/src/app/tryon/`, `mobile-sales-app/lib/features/product|tryon/`

## 문제

판매원 앱에서 prueba virtual 에 사람 사진을 넣으면 **항상** `해당 상품을 찾을 수 없습니다(미게시/타매장).` 만 나온다.

## 원인 (조사 2026-07-15)

**`ShopTryOnService.tryOnFromProduct` 의 게이트가 `isPublishedShop: true` 다** (`shop-tryon.service.ts:45`).

이 서비스는 원래 **공개 온라인 상점(`shop-public`)** 용이다. 비인증 공개 경로이므로 "게시된 상품만" 이 올바른 격리 조건이다. 그런데 판매원 앱 컨트롤러(`mobile-tryon.controller.ts`)가 이 서비스를 그대로 재사용한다. 판매원은 **자기 매장 직원**이고 **매장 옷걸이의 QR** 을 찍는다 — 온라인 게시 여부와 무관해야 한다.

운영 실측 (2026-07-15, PG18 5434):

| 매장 | active 상품 | `is_published_shop=true` |
|---|---|---|
| CART(3) | 20 | **0** |
| coolsistema(6) | 107 | **0** |
| genius(8) | 10 | **0** |
| ACE(9) | 31 | **0** |
| mana(10) | 4 | **0** |
| Asado(11) | 29 | **0** |

**201개 중 0개.** 즉 판매원 앱의 prueba virtual 은 구조적으로 100% 실패한다. 사진을 무엇을 넣든 결과가 같다.

### 동반 발견

1. **백엔드는 stub 이 아니다.** `tryon_repository.dart:2` 주석 "현재 백엔드 stub" 은 낡았다. 운영 env 는 `TRYON_PROVIDER=fashn` + `FASHN_API_KEY` 설정됨 → **게이트만 풀면 실제 합성이 동작한다.**
2. **한국어 에러 메시지가 스페인어 사용자에게 그대로 노출된다.** `ApiException.message` 를 앱이 SnackBar 로 띄운다.
3. **상품 이미지(garment)가 대부분 없다.** 게이트를 풀어도 합성은 옷 사진이 있어야 한다.

   | 매장 | parent active | 이미지 있음 |
   |---|---|---|
   | coolsistema(6) | 15 | **6** |
   | ACE(9) | 15 | **0** |
   | Asado(11) | 14 | 0 |
   | mana(10) | 2 | 0 |
   | CART(3) | 1 | 0 |

   47개 중 6개. 이건 **코드가 아니라 데이터 문제** — 사용자가 CodigoVista 에서 채워야 한다.
4. **상품상세에 가상피팅 버튼이 2개다.** 상단 `Prueba Virtual`(실제 동작, `product_detail_screen.dart:124`)과 하단 `Probar con foto`(항상 "Próximamente" 스낵바만 띄우는 UI-D1 잔재, `:292`).

## 확정 결정

| # | 결정 | 근거 |
|---|------|------|
| D-1 | `tryOnFromProduct` 에 `requirePublished` opt 추가. **기본 `true`**, 판매원 경로만 `false` | shop-public 회귀 0. 게이트 자체를 지우면 공개 상점이 미게시 상품을 노출한다 |
| D-2 | `storeId` 격리는 **그대로 유지** | 판매원이라도 타매장 상품은 안 된다 |
| D-3 | tryon 경로의 사용자 노출 메시지를 **스페인어**로 | 앱/상점 모두 스페인어 사용자. 범위는 tryon 만 (앱 전체 점검은 별건) |
| D-4 | 이미지 없으면 **`Prueba Virtual` 버튼 비활성** + 사유 표시 | 헛수고 방지. 데이터를 코드로 만들 수는 없다 |
| D-5 | 하단 죽은 `Probar con foto` **제거**, `Añadir al carrito` 전폭 | 같은 기능 버튼 2개는 혼란. 하나는 항상 실패 |
| D-6 | **신규 API·스키마 변경 없음** | 앱이 이미 `productImageUrlProvider` 로 이미지 유무를 안다 (아래) |

### D-6 근거 — 앱이 이미 안다

`product_image_provider.dart:16` 의 규칙:
```dart
final first = urls.isNotEmpty ? urls.first?.toString() : data?['imageUrl']?.toString();
if (first == null || first.isEmpty) return null;
```
백엔드 `resolveImageName` (`shop-tryon.service.ts:92`) 의 규칙:
```ts
if (Array.isArray(urls) && urls.length > 0 && urls[0]) return urls[0];
return product.imageUrl || null;
```
**동일하다.** 그리고 `product_detail_screen.dart:209` 가 상세 진입 시 이미 이 provider 를 호출해 hero 이미지를 그린다(`url == null` → 🏷️ 폴백). 따라서 앱의 `url == null` 은 백엔드 `NO_PRODUCT_IMAGE` 조건의 정확한 거울이며, **버튼 게이팅에 새 API 필드가 필요 없다.**

`/mobile/stock/:productId` 에 `tryOnAvailable` 을 얹는 안도 검토했으나 기각 — 그 서비스는 parent 상품을 조회하지 않고 변형만 본다(`mobile-stock.service.ts:83`). 필드를 얹으려면 **쿼리가 늘어난다**(pool 규약 위반). 이미 있는 provider 재사용이 옳다.

## 컴포넌트 설계

### 1. `api-ventago/src/app/tryon/shop-tryon.service.ts`

```ts
async tryOnFromProduct(
  storeId: number,
  productId: number,
  person: PersonPhoto,
  opts?: { requirePublished?: boolean },
): Promise<TryOnResult> {
  // 공개 상점(shop-public)은 게시된 상품만. 판매원 앱은 자기 매장 직원이 매장 옷걸이
  // QR 을 찍으므로 게시 여부와 무관 — 단, storeId 격리는 두 경로 모두 유지한다.
  const requirePublished = opts?.requirePublished !== false;

  const product = await Product.findOne({
    where: {
      id: productId,
      storeId,
      ...(requirePublished ? { isPublishedShop: true } : {}),
    },
  });

  if (!product) {
    throw new BadRequestException({
      message: requirePublished
        ? 'Producto no disponible (no publicado o de otra tienda).'
        : 'Producto no encontrado en tu tienda.',
      code: 'SHOP_PRODUCT_UNAVAILABLE',
    });
  }
  ...
```

나머지 메시지도 스페인어로:
- `NO_PRODUCT_IMAGE` → `'Este producto no tiene foto. Cargá una imagen en CodigoVista para usar la prueba virtual.'`
- `PRODUCT_IMAGE_LOAD_FAILED` → `'No se pudo cargar la foto del producto.'`

**에러 `code` 는 바꾸지 않는다** — 기존 소비자가 코드로 분기할 수 있다.

### 2. `api-ventago/src/app/tryon/mobile-tryon.controller.ts`

```ts
return this.shopTryOn.tryOnFromProduct(storeId, productId, {
  buffer: person.buffer,
  mimetype: person.mimetype,
}, { requirePublished: false });
```

컨트롤러 자신의 검증 메시지 3개도 스페인어로:
- `'person 이미지 파일이 필요합니다.'` → `'Falta la foto de la persona.'`
- `'이미지 파일만 업로드할 수 있습니다.'` → `'Solo se permiten archivos de imagen.'`
- `'이미지는 12MB 이하만 가능합니다.'` → `'La imagen no puede superar los 12 MB.'`

### 3. `mobile-sales-app/lib/features/product/views/product_detail_screen.dart`

- 상단 `Prueba Virtual` OutlinedButton: `productImageUrlProvider(widget.productId)` 를 watch.
  - `data(url != null)` → 활성 (현행 동작)
  - `data(url == null)` → **비활성** + 라벨 아래 사유 `Sin foto del producto`
  - `loading` → 비활성 (판정 전 헛클릭 방지)
  - `error` → 활성 (이미지 조회 실패가 곧 이미지 없음은 아니다 — 서버가 최종 판정)
- `_ProbarConFotoButton` 클래스와 그 `Row`/`Expanded` 래핑 **삭제**. `Añadir al carrito` 를 전폭으로.
- 파일 헤더 주석(`:4`)의 "Probar con foto(disabled+Próximamente, UI-D1)" 서술 갱신.

### 4. `mobile-sales-app/lib/features/tryon/data/tryon_repository.dart`

낡은 주석 `현재 백엔드 stub` 제거 — 운영은 FASHN 이다. 사실과 다른 주석은 다음 사람을 오도한다.

## 에러 핸들링

기존 경로 유지 (`tryon_flow.dart:117` `on ApiException` → 빨강 SnackBar). 메시지만 스페인어가 된다.

## 테스트 전략

**`api-ventago` 유닛 (jest)** — 신규 `shop-tryon.service.spec.ts`:
- `requirePublished` 미지정 → `where` 에 `isPublishedShop: true` **포함** (shop-public 회귀 가드)
- `requirePublished: false` → `where` 에 `isPublishedShop` **없음**, `storeId`/`id` 는 유지 (격리 가드)
- `requirePublished: false` + 타매장 상품 → `SHOP_PRODUCT_UNAVAILABLE` (D-2 가드)
- 이미지 없는 상품 → `NO_PRODUCT_IMAGE`, 메시지 스페인어

**`mobile-sales-app`** — 위젯 테스트 하네스가 이 화면엔 없다. `flutter analyze` + 수동 UAT.

## 수동 UAT

1. **이미지 있는 상품**(coolsistema 6개 중 하나) → `Prueba Virtual` 활성 → 사람 사진 → **실제 합성 결과**
2. **이미지 없는 상품**(ACE 전부) → 버튼 비활성 + `Sin foto del producto`
3. 하단에 `Probar con foto` 가 **없고** `Añadir al carrito` 가 전폭
4. 에러 메시지가 스페인어

## 범위 외 (YAGNI)

- 앱 전체 한국어 메시지 점검 (별건, D-3)
- 상품 이미지 일괄 등록 — 데이터 작업이지 코드가 아니다
- variant 이미지 폴백 — parent 에 없으면 자식에도 없을 가능성이 높고, 미검증 가정이다
- `/mobile/stock` 에 `tryOnAvailable` 추가 (D-6 에서 기각 — 쿼리 증가)
- `shop-public` 경로 동작 변경 — 기본값 `true` 로 완전 보존

## 의존성 / 배포

- **DB 마이그레이션 없음.** 스키마 변경 0.
- 백엔드 = Jenkins 수동 배포. 앱 = APK 빌드.
- **배포 순서: API 먼저, APK 나중.** 구 API + 신 APK 면 버튼은 활성화됐는데 서버가 여전히 게시 게이트로 막아 실패한다.
- 신 API + 구 APK 는 안전 — 구 앱도 게이트가 풀려 오히려 동작한다(이미지 있는 상품 한정).
