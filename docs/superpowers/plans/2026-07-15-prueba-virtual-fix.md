# Prueba Virtual 수정 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 판매원 앱의 prueba virtual 이 항상 실패하는 원인(공개 상점용 게시 게이트 재사용)을 제거하고, 이미지 없는 상품에서는 버튼을 비활성화하며, 사용자 노출 메시지를 스페인어로 바꾼다.

**Architecture:** `ShopTryOnService.tryOnFromProduct` 는 공개 상점(shop-public)과 판매원 앱이 공유한다. 게이트를 지우는 대신 `requirePublished` opt 를 추가해 **기본 `true`(shop-public 회귀 0)**, 판매원 경로만 `false` 로 넘긴다. 앱은 이미 `productImageUrlProvider` 로 이미지 유무를 알고 있으므로 신규 API 없이 버튼을 게이팅한다.

**Tech Stack:** NestJS 11 + Sequelize (api-ventago), Flutter + Riverpod 3.3.1 (mobile-sales-app)

**설계 문서:** `docs/superpowers/specs/2026-07-15-prueba-virtual-fix-design.md`

## Global Constraints

- **DB 마이그레이션 0. 신규 API 엔드포인트 0. 신규 응답 필드 0.** 스키마 변경 없음.
- **shop-public 회귀 0:** `requirePublished` 기본값은 `true`. 공개 상점이 미게시 상품을 노출하면 안 된다.
- **매장 격리 불변:** `storeId` 조건은 두 경로 모두 유지. 판매원이라도 타매장 상품은 안 된다.
- **에러 `code` 는 바꾸지 않는다** (`SHOP_PRODUCT_UNAVAILABLE` / `NO_PRODUCT_IMAGE` / `PRODUCT_IMAGE_LOAD_FAILED`) — 기존 소비자가 코드로 분기할 수 있다. **바뀌는 것은 `message` 뿐이다.**
- **pool 보호:** 쿼리 수를 늘리지 않는다. `/mobile/stock` 에 필드를 얹는 안은 spec D-6 에서 기각됨.
- **주석은 한국어, 함수/변수명은 영어** (CLAUDE.md). **사용자 노출 UI/에러 문자열은 스페인어** (Argentina/Colombia 제품).
- api-ventago 테스트: `npx jest src/app/tryon`. mobile-sales-app: `flutter analyze lib` + `flutter test`.
- **`git add -A` / `git add .` 금지.** 이 모노레포엔 3rd-party WIP(`variant_stock_matrix.dart`, `GeneratedPluginRegistrant.swift`, `build-apk.sh`)가 있다. 항상 파일명을 명시해 add 한다. **이 파일들을 커밋하거나 되돌리지 말 것.**
- **`git stash` 금지.** 이 repo 에서 stash 후 flutter 명령이 `GeneratedPluginRegistrant.swift` 를 재생성해 `stash pop` 이 충돌한다(이번 세션에서 실제 발생).
- api-ventago 는 **gitlink 서브모듈** → `cd api-ventago` 후 커밋. mobile-sales-app 도 **nested repo** → `cd mobile-sales-app` 후 커밋. (zebra-agent 와 다르다.)

---

### Task 1: 백엔드 — `requirePublished` opt + 스페인어 메시지

**Files:**
- Modify: `api-ventago/src/app/tryon/shop-tryon.service.ts:38-79`
- Modify: `api-ventago/src/app/tryon/mobile-tryon.controller.ts:37-52`
- Test: `api-ventago/src/app/tryon/shop-tryon.service.spec.ts` (신규)

**Interfaces:**
- Consumes: 없음
- Produces:
  ```ts
  async tryOnFromProduct(
    storeId: number,
    productId: number,
    person: PersonPhoto,
    opts?: { requirePublished?: boolean },   // 기본 true
  ): Promise<TryOnResult>
  ```
  `tryon.controller.ts`(shop-public, `from-product/:storeId/:productId`)는 **호출부를 바꾸지 않는다** — 4번째 인자를 안 주면 기본 `true` 라 기존 동작 그대로다. 확인만 하고 손대지 말 것.

- [ ] **Step 1: 실패하는 테스트 작성**

Create `api-ventago/src/app/tryon/shop-tryon.service.spec.ts`:

```ts
import { ShopTryOnService } from './shop-tryon.service';
import { Product } from '../products/products.model';

// tryOnFromProduct 의 게이트 계약 — shop-public(게시 필수) vs 판매원 앱(게시 무관).
// 위치 인자 생성자를 우회하고(Object.create) provider/minio 만 mock 으로 주입한다.
describe('ShopTryOnService — tryOnFromProduct 게이트', () => {
  const STORE_ID = 6;
  const PRODUCT_ID = 10;

  const person = { buffer: Buffer.from('person'), mimetype: 'image/jpeg' };

  const makeService = (product: any) => {
    const provider = {
      name: 'stub',
      tryOn: jest.fn().mockResolvedValue({
        provider: 'stub',
        isStub: true,
        resultImageDataUrl: 'data:image/png;base64,AA',
      }),
    } as any;
    const minio = {} as any;

    const svc: any = Object.create(ShopTryOnService.prototype);
    svc.provider = provider;
    svc.minio = minio;
    svc.logger = { error: jest.fn(), log: jest.fn() };
    // MinIO 스트림 수집은 이 테스트의 관심사가 아니다 — 바이트를 바로 준다
    svc.fetchObjectBytes = jest.fn().mockResolvedValue(Buffer.from('garment'));

    const findOne = jest
      .spyOn(Product, 'findOne')
      .mockResolvedValue(product as any);

    return { svc, provider, findOne };
  };

  const productWithImage = {
    id: PRODUCT_ID,
    storeId: STORE_ID,
    imageUrls: ['foto.png'],
    imageUrl: null,
  };

  afterEach(() => jest.restoreAllMocks());

  // ── shop-public 회귀 가드 ──────────────────────────────────────────────
  it('opts 미지정 → where 에 isPublishedShop:true 포함 (공개 상점 기본)', async () => {
    const { svc, findOne } = makeService(productWithImage);

    await svc.tryOnFromProduct(STORE_ID, PRODUCT_ID, person);

    expect(findOne.mock.calls[0][0]!.where).toEqual({
      id: PRODUCT_ID,
      storeId: STORE_ID,
      isPublishedShop: true,
    });
  });

  it('requirePublished:true 명시 → 동일하게 게시 필수', async () => {
    const { svc, findOne } = makeService(productWithImage);

    await svc.tryOnFromProduct(STORE_ID, PRODUCT_ID, person, {
      requirePublished: true,
    });

    expect((findOne.mock.calls[0][0]!.where as any).isPublishedShop).toBe(true);
  });

  // ── 판매원 앱 경로 ────────────────────────────────────────────────────
  it('requirePublished:false → where 에 isPublishedShop 없음, 격리 조건은 유지', async () => {
    const { svc, findOne } = makeService(productWithImage);

    await svc.tryOnFromProduct(STORE_ID, PRODUCT_ID, person, {
      requirePublished: false,
    });

    const where = findOne.mock.calls[0][0]!.where as any;
    expect(where).toEqual({ id: PRODUCT_ID, storeId: STORE_ID });
    expect('isPublishedShop' in where).toBe(false);
  });

  it('requirePublished:false 여도 미게시 상품이 실제로 합성까지 간다', async () => {
    const { svc, provider } = makeService(productWithImage);

    const res = await svc.tryOnFromProduct(STORE_ID, PRODUCT_ID, person, {
      requirePublished: false,
    });

    expect(provider.tryOn).toHaveBeenCalledTimes(1);
    expect(res.resultImageDataUrl).toContain('data:image');
  });

  // ── 격리 가드 (D-2) ───────────────────────────────────────────────────
  it('타매장 상품(findOne null) → SHOP_PRODUCT_UNAVAILABLE, 메시지 스페인어', async () => {
    const { svc, provider } = makeService(null);

    await expect(
      svc.tryOnFromProduct(STORE_ID, PRODUCT_ID, person, {
        requirePublished: false,
      }),
    ).rejects.toMatchObject({
      response: {
        code: 'SHOP_PRODUCT_UNAVAILABLE',
        message: 'Producto no encontrado en tu tienda.',
      },
    });
    expect(provider.tryOn).not.toHaveBeenCalled();
  });

  it('공개 상점에서 못 찾으면 게시/타매장 문구', async () => {
    const { svc } = makeService(null);

    await expect(
      svc.tryOnFromProduct(STORE_ID, PRODUCT_ID, person),
    ).rejects.toMatchObject({
      response: {
        code: 'SHOP_PRODUCT_UNAVAILABLE',
        message: 'Producto no disponible (no publicado o de otra tienda).',
      },
    });
  });

  // ── 이미지 없음 (운영 47개 중 41개가 이 경로) ──────────────────────────
  it('이미지 없는 상품 → NO_PRODUCT_IMAGE, 메시지 스페인어', async () => {
    const { svc, provider } = makeService({
      id: PRODUCT_ID,
      storeId: STORE_ID,
      imageUrls: [],
      imageUrl: null,
    });

    await expect(
      svc.tryOnFromProduct(STORE_ID, PRODUCT_ID, person, {
        requirePublished: false,
      }),
    ).rejects.toMatchObject({
      response: {
        code: 'NO_PRODUCT_IMAGE',
        message:
          'Este producto no tiene foto. Cargá una imagen en CodigoVista para usar la prueba virtual.',
      },
    });
    expect(provider.tryOn).not.toHaveBeenCalled();
  });

  it('imageUrls 비어도 imageUrl 있으면 진행 (폴백 유지)', async () => {
    const { svc, provider } = makeService({
      id: PRODUCT_ID,
      storeId: STORE_ID,
      imageUrls: [],
      imageUrl: 'legacy.png',
    });

    await svc.tryOnFromProduct(STORE_ID, PRODUCT_ID, person, {
      requirePublished: false,
    });

    expect(provider.tryOn).toHaveBeenCalledTimes(1);
  });
});
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd api-ventago && npx jest src/app/tryon/shop-tryon.service.spec.ts`
Expected: FAIL — `requirePublished:false → where 에 isPublishedShop 없음` 이 실패한다 (현행은 `isPublishedShop: true` 를 무조건 넣음). 한국어 메시지 단언들도 실패한다.

- [ ] **Step 3: 서비스 구현**

`shop-tryon.service.ts:38-64` 를 교체:

```ts
  async tryOnFromProduct(
    storeId: number,
    productId: number,
    person: PersonPhoto,
    opts?: { requirePublished?: boolean },
  ): Promise<TryOnResult> {
    // 1) 매장 격리는 두 경로 공통. 게시 조건은 공개 상점(shop-public)에만 적용한다 —
    //    판매원 앱은 자기 매장 직원이 매장 옷걸이 QR 을 찍으므로 게시 여부와 무관하다.
    //    (기본 true: 4번째 인자를 안 주는 기존 shop-public 호출부의 동작을 보존)
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

    // 2) 상품 이미지(garment) 확보 — imageUrls[0] 우선, 없으면 imageUrl
    const fileName = this.resolveImageName(product);

    if (!fileName) {
      throw new BadRequestException({
        message:
          'Este producto no tiene foto. Cargá una imagen en CodigoVista para usar la prueba virtual.',
        code: 'NO_PRODUCT_IMAGE',
      });
    }
```

이어서 `PRODUCT_IMAGE_LOAD_FAILED` 메시지(`:76`)를 교체 (로거 문구는 한국어 유지 — 개발자용):

```ts
      throw new BadRequestException({
        message: 'No se pudo cargar la foto del producto.',
        code: 'PRODUCT_IMAGE_LOAD_FAILED',
      });
```

`:81` 의 낡은 주석도 고친다 (운영은 FASHN 이다):

```ts
    // 4) 가상 피팅 (provider 는 TRYON_PROVIDER env 로 결정 — 운영은 fashn)
```

- [ ] **Step 4: 컨트롤러 구현**

`mobile-tryon.controller.ts:37-52` 를 교체 (판매원 경로 = `requirePublished: false` + 검증 메시지 스페인어화):

```ts
    if (!person) {
      throw new BadRequestException('Falta la foto de la persona.');
    }
    if (!person.mimetype.startsWith('image/')) {
      throw new BadRequestException('Solo se permiten archivos de imagen.');
    }
    if (person.size > MAX_IMAGE_BYTES) {
      throw new BadRequestException('La imagen no puede superar los 12 MB.');
    }

    const storeId = Number(req.user?.storeId);

    // 판매원은 자기 매장 직원 — 온라인 게시 여부와 무관하게 자기 매장 상품을 입어본다.
    // (storeId 격리는 서비스가 유지)
    return this.shopTryOn.tryOnFromProduct(
      storeId,
      productId,
      { buffer: person.buffer, mimetype: person.mimetype },
      { requirePublished: false },
    );
```

파일 헤더 주석(`:4`)의 "현재 StubTryOnProvider" 서술도 갱신:

```ts
// 합성은 기존 ShopTryOnService(TryOnProvider 추상화) 재사용 — provider 는 TRYON_PROVIDER
//   env 로 결정(운영: fashn). 사람 사진 미저장(처리 후 폐기).
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `cd api-ventago && npx jest src/app/tryon`
Expected: PASS — 신규 8개.

shop-public 호출부가 안 바뀌었는지 확인:
Run: `cd api-ventago && grep -n "tryOnFromProduct" src/app/tryon/tryon.controller.ts`
Expected: 3인자 호출 그대로 (4번째 인자 없음)

한국어 사용자 메시지가 남았는지 확인:
Run: `cd api-ventago && grep -n "message:" src/app/tryon/shop-tryon.service.ts src/app/tryon/mobile-tryon.controller.ts`
Expected: 전부 스페인어 (로거 문구는 한국어 유지 — `this.logger.error(...)` 는 대상 아님)

- [ ] **Step 6: 커밋**

```bash
cd api-ventago
git add src/app/tryon/shop-tryon.service.ts src/app/tryon/mobile-tryon.controller.ts src/app/tryon/shop-tryon.service.spec.ts
git commit -m "fix(tryon): 판매원 앱은 게시 게이트 무관 + 메시지 스페인어화

prueba virtual 이 항상 'SHOP_PRODUCT_UNAVAILABLE' 로 실패하던 원인:
공개 상점용 ShopTryOnService 를 판매원 앱이 재사용하는데 isPublishedShop:true
게이트가 걸려 있었다. 운영 활성 상품 201개 중 게시된 것은 0개 — 구조적 100% 실패.

- requirePublished opt 추가(기본 true) → shop-public 회귀 0, 판매원만 false
- storeId 격리는 두 경로 모두 유지
- 사용자 노출 메시지 한국어 → 스페인어 (앱/상점 모두 스페인어 사용자)
- 에러 code 는 불변 (기존 소비자 분기 보호)"
```

---

### Task 2: 앱 — 이미지 없으면 버튼 비활성 + 죽은 버튼 제거

**Files:**
- Modify: `mobile-sales-app/lib/features/product/views/product_detail_screen.dart` (헤더 주석 `:4`, 상단 버튼 `:119-133`, 하단 Row `:265-281`, `_ProbarConFotoButton` `:291-320`)
- Modify: `mobile-sales-app/lib/features/tryon/data/tryon_repository.dart:2` (낡은 주석)

**Interfaces:**
- Consumes: `productImageUrlProvider(productId)` — `FutureProvider.autoDispose.family<String?, int>`, 이미 존재. `null` = 이미지 없음. 규칙이 백엔드 `resolveImageName`(`imageUrls[0] ?? imageUrl`)과 동일하므로 백엔드 `NO_PRODUCT_IMAGE` 의 정확한 거울이다.
- Produces: 없음 (최종 태스크)

**이 화면엔 위젯 테스트 하네스가 없다.** 검증은 `flutter analyze` + 수동 UAT.

**주의 — 남의 WIP:** `git status` 에 `variant_stock_matrix.dart`, `macos/Flutter/GeneratedPluginRegistrant.swift`, `build-apk.sh` 가 떠 있다. **건드리지도, 커밋하지도, 되돌리지도 말 것.** `git stash` 도 쓰지 말 것(이번 세션에서 stash pop 충돌 사고 발생).

- [ ] **Step 1: 상단 Prueba Virtual 버튼 게이팅**

`product_detail_screen.dart:119-133` 의 `Padding(...)` 블록을 교체:

```dart
              _tryOnButton(),
```

그리고 이 State 클래스에 메서드를 추가한다 (`_heroPhoto()` 근처, 같은 스타일):

```dart
  // Prueba Virtual — 옷 사진(garment)이 있어야 합성 가능하므로 이미지 없는 상품에선
  // 비활성(헛클릭 방지). 판정 규칙은 백엔드 resolveImageName(imageUrls[0] ?? imageUrl)과
  // 동일하다 — 즉 이 버튼의 비활성 조건은 서버 NO_PRODUCT_IMAGE 의 거울이다.
  Widget _tryOnButton() {
    final imgAsync = ref.watch(productImageUrlProvider(widget.productId));
    // 이미지 조회 실패는 "이미지 없음"이 아니다 → 활성(서버가 최종 판정).
    // 로딩 중엔 판정 전이므로 비활성.
    final hasPhoto = imgAsync.when(
      data: (url) => url != null,
      loading: () => false,
      error: (_, _) => true,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed:
                  hasPhoto ? () => showTryOnFlow(context, ref, widget.productId) : null,
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('Prueba Virtual'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.gold,
                side: BorderSide(color: hasPhoto ? AppColors.gold : AppColors.line),
              ),
            ),
          ),
          if (!hasPhoto && !imgAsync.isLoading) ...[
            const SizedBox(height: 4),
            const Text(
              'Sin foto del producto',
              style: TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ],
        ],
      ),
    );
  }
```

**`Consumer` 로 감싸지 않는 이유:** 이 화면은 이미 `_heroPhoto()` 에서 같은 `productImageUrlProvider(widget.productId)` 를 `ref.watch` 하고 있다. 화면 전체가 이미 그 provider 에 묶여 있으므로 `Consumer` 는 구독 범위를 좁히지 못하고 중첩과 `ref` 섀도잉만 만든다. 파일의 기존 스타일(`_hero`/`_heroPhoto` 메서드)을 따른다.

- [ ] **Step 2: 하단 죽은 버튼 제거 + 전폭화**

`product_detail_screen.dart:265-281` 의 `Row(...)` 블록을 교체:

```dart
                // Añadir al carrito ({n}) — navy solid, n==0 이면 disabled
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: controller.addEnabled ? () => _addToCart(item) : null,
                    child: Text('Añadir al carrito ($total)'),
                  ),
                ),
```

`_ProbarConFotoButton` 클래스(`:291-320`, `// disabled 상태로 렌더 + 탭 시 "Próximamente" 토스트 (UI-D1 — AI 미구현)` 주석 포함) **전체 삭제**.

- [ ] **Step 3: 낡은 주석 정리**

`product_detail_screen.dart:4` 헤더:
```dart
// 하단: Añadir al carrito({n})(navy). 상단 Prueba Virtual 은 상품 사진이 있을 때만 활성.
```

`tryon_repository.dart:2`:
```dart
// 결과는 data URL(base64) — 저장 없이 즉시 표시. provider 는 서버 TRYON_PROVIDER env 로 결정(운영: fashn).
```

- [ ] **Step 4: 검증**

Run: `cd mobile-sales-app && flutter analyze lib/features/product/views/product_detail_screen.dart lib/features/tryon/data/tryon_repository.dart`
Expected: `No issues found!`

Run: `cd mobile-sales-app && flutter analyze lib`
Expected: 기존 2건(`product_detail_screen.dart:229` `unnecessary_underscores`)만 — **신규 issue 0**. 이 2건이 사라지거나 늘면 보고할 것.

Run: `cd mobile-sales-app && flutter test`
Expected: **40 passed, 1 failed**. 실패는 `test/widget_test.dart` (`Couldn't find constructor 'MyApp'`) — Flutter 템플릿 잔재로 이 앱에 존재한 적 없는 클래스를 참조한다. **선존재이며 이 태스크와 무관하다.** 카운트가 이와 다르면 보고할 것.

죽은 버튼이 사라졌는지 확인:
Run: `cd mobile-sales-app && grep -rn "Probar con foto\|Próximamente\|_ProbarConFotoButton" lib/`
Expected: 출력 없음

- [ ] **Step 5: 커밋**

```bash
cd mobile-sales-app
git add lib/features/product/views/product_detail_screen.dart lib/features/tryon/data/tryon_repository.dart
git commit -m "fix(product): Prueba Virtual 은 사진 있을 때만 활성 + 죽은 버튼 제거

- 상품 사진이 없으면 합성이 불가능(백엔드 NO_PRODUCT_IMAGE)하므로 버튼 비활성 +
  'Sin foto del producto' 사유 표시. 판정은 이미 있는 productImageUrlProvider 재사용
  (규칙이 백엔드 resolveImageName 과 동일) — 신규 API 없음
- 하단 'Probar con foto'(항상 Próximamente 스낵바만 뜨던 UI-D1 잔재) 삭제,
  Añadir al carrito 전폭. 같은 기능 버튼 2개 중 하나는 항상 실패했다
- 낡은 주석 정리: 백엔드는 stub 이 아니다(운영 TRYON_PROVIDER=fashn)"
```

---

## 수동 UAT (구현 후 필수)

**API 를 먼저 배포해야 한다** (Jenkins `api-new-coolsistema` 수동). 구 API + 신 APK 면 버튼은 활성인데 서버가 게시 게이트로 막아 여전히 실패한다.

1. **이미지 있는 상품** — coolsistema(store 6)의 이미지 보유 6개 중 하나. `Prueba Virtual` 활성 → 사람 사진 업로드 → **실제 합성 결과**가 나오는지 (stub 원본 사진 그대로가 아니라)
2. **이미지 없는 상품** — ACE(store 9)는 전부 해당. 버튼 비활성 + `Sin foto del producto`
3. 하단에 `Probar con foto` 가 **없고** `Añadir al carrito` 가 전폭
4. 에러 메시지가 **스페인어**
5. **공개 온라인 상점 회귀** — shop-public 의 try-on 이 미게시 상품을 여전히 거부하는지 (게시된 상품이 0개라 실사용 검증이 어렵다면 최소한 Task 1 의 회귀 테스트 2개로 갈음)

## 알려진 한계 (코드로 해결 불가)

운영 parent 상품 47개 중 이미지 보유는 **6개**(coolsistema)뿐, ACE 는 **0개**다. 게이트를 풀어도 이미지 없는 상품은 여전히 prueba virtual 을 쓸 수 없다 — 이번 변경은 그걸 **정직하게(버튼 비활성 + 사유)** 만들 뿐이다. 실제로 쓰려면 CodigoVista 에서 상품 사진을 등록해야 한다.

## 배포

- **DB 마이그레이션 없음.**
- 백엔드: Jenkins `api-new-coolsistema` 수동 빌드. git push 는 자동배포 안 됨.
- 앱: `./build-apk.sh` (Dropbox 배포 폴더로 자동 복사).
- **순서: API 먼저 → APK 나중.** 역순이면 신 APK 가 구 API 의 게시 게이트에 막힌다.
- 신 API + 구 APK 는 안전 — 구 앱도 게이트가 풀려 오히려 동작한다(이미지 있는 상품 한정).
