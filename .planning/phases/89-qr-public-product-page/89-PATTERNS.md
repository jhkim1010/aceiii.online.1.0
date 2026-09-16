# Phase 89: QR → 공개 상품 페이지 + 두 갈래 CTA — Pattern Map

**Mapped:** 2026-09-16
**Files analyzed:** 15 (신규 11 · 수정 4)
**Analogs found:** 15 / 15 (전부 이 저장소 실사용 코드에서 발췌 — 추측 없음)

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `ventago-app/src/pages/m/stock/index.tsx` | route (Next.js public page) | request-response | `ventago-app/src/pages/entrega/[token].tsx` | **exact** (같은 요구사항: 무인증·BlankLayout·raw fetch) |
| `ventago-app/src/views/m-stock/QrProductView.tsx` | component | request-response | `entrega/[token].tsx` 본문 렌더 부분 + `ventago-app/src/components/product/ProductPhotoBox.tsx` (이미지 URL 조립) | role-match |
| `ventago-app/src/views/m-stock/ResellerApplyForm.tsx` | component (public form) | request-response (multipart) | `ventago-app/src/views/configuracion/tienda/DatosTiendaView.tsx`(FormData 조립) + `entrega/[token].tsx`(raw fetch) 조합 | partial-match(둘을 합쳐야 함, 공개+multipart 전례가 없음) |
| `ventago-app/src/views/m-stock/VentagoLeadForm.tsx` | component (public form) | request-response | `entrega/[token].tsx`(raw fetch POST, JSON body) | role-match |
| `api-ventago/src/app/print/qr-public.controller.ts` | controller | request-response | `api-ventago/src/app/online-orders/public-delivery.controller.ts` + `api-ventago/src/app/shop-public/shop-catalog.controller.ts` | **exact**(둘의 조합 — `@Public()+@Throttle` 골격은 전자, `storeId` 파라미터+쿼리 화이트리스트는 후자) |
| `api-ventago/src/app/print/qr-public.service.ts` (또는 `PrintService` 확장) | service | CRUD(단건 조회) | `api-ventago/src/app/shop-public/shop-catalog.service.ts`(`getProductBySlug`) | **exact** |
| `api-ventago/src/app/leads/lead.model.ts` | model | — | `api-ventago/src/app/onboarding/pending-registration.model.ts` | role-match |
| `api-ventago/src/app/leads/leads.module.ts` | config(Nest module) | — | `api-ventago/src/app/print/print.module.ts` | role-match |
| `api-ventago/src/app/leads/leads-public.controller.ts` | controller | request-response | `api-ventago/src/app/online-orders/public-delivery.controller.ts` | **exact** |
| `api-ventago/migrations/<date>-ventago-leads.sql` | migration | — | `api-ventago/migrations/2026-08-25-phase86-upload-sessions.sql` | **exact**(BIGSERIAL 신규 테이블 + owner/sequence 이전 DO 블록) |
| `api-ventago/migrations/<date>-store-configs-qr-precio-publico.sql` | migration | — | `api-ventago/migrations/2026-08-28-store-commerce-auto-sync.sql` | **exact**(기존 테이블에 boolean 컬럼 추가, `lock_timeout`+`w4-exempt` 불필요·owner DO 블록만) |
| `api-ventago/src/app/store/config/storeConfig.model.ts` (수정) | model | — | 같은 파일의 `commerceAutoSync`/`vtoEnabled` 선언 | **exact**(같은 파일에 컬럼 추가) |
| `api-ventago/src/app/store/config/storeConfig.controller.ts` (수정, `FLAG_FIELDS`) | controller(화이트리스트) | request-response | 같은 파일의 `FLAG_FIELDS` 배열 | **exact** |
| `ventago-app/src/context/StoreConfigContext.tsx` (수정) | provider(React Context) | request-response | 같은 파일의 `allowSaleWithoutStock`/`vtoEnabled` 3곳(interface·default·매핑) | **exact** |
| `ventago-app/src/views/configuracion/qr/QrConfigView.tsx` (신규, Configuración 화면) | component | request-response | `ventago-app/src/views/configuracion/inventario/InventarioConfigView.tsx` | **exact** |
| `api-ventago/src/app/print/qr-public.controller.spec.ts` / `leads-public.controller.spec.ts` | test | — | `api-ventago/src/app/store/config/storeConfig.controller.spec.ts` (화이트리스트 검증 스타일) | role-match |

---

## Pattern Assignments

### 1. `ventago-app/src/pages/m/stock/index.tsx` (route, request-response)

**Analog:** `ventago-app/src/pages/entrega/[token].tsx:1-260`(전체가 사실상 이 페이지의 템플릿)

**무인증 선언 (파일 최하단, line 245-247, 259-260):**
```typescript
EntregaPage.getLayout = (page: ReactNode) => <BlankLayout>{page}</BlankLayout>

// 로그인 없이 열린다 — 고객은 이 시스템의 사용자가 아니다.
EntregaPage.authGuard = false
EntregaPage.guestGuard = false
```
`/m/stock` 도 **정확히 이 세 줄**을 그대로 가져다 쓴다. `_app.tsx:247`의 `Component.authGuard ?? true` 기본값 때문에 이걸 빠뜨리면 QR 을 찍은 고객이 `/login`으로 튕긴다(Pitfall 1, RESEARCH.md).

**API 호출 — raw `fetch`, `apiConnector` 금지 (line 22-24, 34-49):**
```typescript
const API_HOST =
  process.env.NODE_ENV === 'development' ? 'http://localhost:5002/api' : 'https://newapi.coolsistema.com/api'

const post = async (path: string, body: Record<string, unknown>) => {
  const res = await fetch(`${API_HOST}/public/entrega/${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-api-key': '12345' },
    body: JSON.stringify(body)
  })

  const json = await res.json().catch(() => null)

  if (!res.ok) {
    throw new Error(json?.message || 'No pudimos procesar tu pedido')
  }

  return json
}
```
`/m/stock` 은 QR 의 `s`/`p`(store/productId)를 `router.query`에서 읽어 `GET ${API_HOST}/public/qr-stock/${storeId}/${productId}`를 raw `fetch`로 부른다(POST 가 아니라 GET — 상태를 바꾸지 않고, 토큰이 아니라 이미 라벨에 인쇄된 숫자이므로 URL 노출이 문제되지 않음. `entrega`의 "토큰은 body 로" 원칙은 **토큰에만** 적용되고 여기엔 없다).

**이 phase에서 바꿀 것:** 새 파일 하나 생성. 레이아웃/가드/fetch 세 조각을 그대로 복제하고, `Envio` 타입 자리에 QR 응답 DTO(`name, storeName, branchName, imageUrl, price, priceSource, resellerCtaUrl, leadCtaVisible` 등)를 채운다.

---

### 2. `ventago-app/src/views/m-stock/QrProductView.tsx` (component)

**Analog 1 — 로딩/에러/데이터 3단 렌더링 골격:** `entrega/[token].tsx:119-147`(loading/error/success 분기 그대로)

**Analog 2 — 상품 이미지 URL 조립 (null 폴백 포함):** `ventago-app/src/components/product/ProductPhotoBox.tsx:8-9`
```typescript
/^https?:\/\//.test(name) ? name : `${constants.api}/minio/${name}`
```
store 9(부모상품 사진 0%)·store 6(65% 없음) 실측(RESEARCH Q2) 때문에 `imageUrl === null`일 때 자리표시자(다크 네이비+골드 톤)를 반드시 그린다 — "사진 없음"을 예외가 아니라 주 경로로 설계.

**이 phase에서 바꿀 것:** 신규 파일. `entrega` 의 상태 분기 구조를 재사용하되 버튼 2개(확인/거부) 대신 상품 카드 + CTA 2개(reseller 신청 / Ventago 리드)로 교체.

---

### 3. `ventago-app/src/views/m-stock/ResellerApplyForm.tsx` (component, multipart)

**Analog 1 — 무인증 raw fetch + JSON:** `entrega/[token].tsx:34-49`(위 발췌 그대로, 단 `Content-Type: application/json` 대신 `FormData` 라 헤더를 **직접 세팅하지 않는다** — 브라우저가 boundary 를 자동 지정).

**Analog 2 — FormData 조립(3개 파일 첨부 실전 패턴):** `ventago-app/src/views/configuracion/tienda/DatosTiendaView.tsx:103-113`
```typescript
const formData = new FormData()
formData.append('logoFile', logoFile)
const res: any = await apiConnector.putFile(`/store/${storeId}`, formData)
```
차이점: 이 저장소 예시는 인증된 `apiConnector.putFile`을 쓴다. `/m/stock`은 공개 페이지이므로 **`apiConnector`를 쓰지 않고** `fetch(url, { method: 'POST', body: formData })`로 직접 보낸다(Content-Type 헤더 생략 필수 — 수동 지정하면 boundary 가 깨진다).

**백엔드 계약(그대로 재사용, 무변경) — `api-ventago/src/app/reseller/auth/dto/reseller-register.dto.ts:1-12`:**
```typescript
export class ResellerRegisterDto {
  @IsString() @IsNotEmpty() readonly name: string;
  @IsString() @IsNotEmpty() readonly phone: string;
  @IsString() @IsNotEmpty() readonly document: string;
  @IsString() @MinLength(6) readonly password: string;

  // 판매 희망 매장 id[] (multipart 라 문자열로 옴 → number 변환)
  @IsArray() @Type(() => Number) readonly storeIds: number[];
}
```
필수 파일 3개: `dniPhoto`, `residenceCert`, `selfie` (컨트롤러 `FileFieldsInterceptor`, `reseller-auth.controller.ts:32-38`).

**이 phase에서 바꿀 것:** `storeIds`를 사용자가 고르게 두지 말고 QR 의 `storeId` 하나로 **프론트에서 고정**해 전송(Pitfall 4). 매장 선택 UI 노출 금지. 엔드포인트는 `POST ${API_HOST}/reseller/auth/register` 그대로, 백엔드 코드는 무변경.

---

### 4. `ventago-app/src/views/m-stock/VentagoLeadForm.tsx` (component)

**Analog:** `entrega/[token].tsx:34-49`(raw fetch, JSON body) — `ResellerApplyForm`과 달리 파일 첨부가 없으므로 이 패턴을 그대로(변형 없이) 쓴다.

**이 phase에서 바꿀 것:** `POST ${API_HOST}/public/ventago-leads`(신규)에 `{ storeId, contactName, contactPhone }` 전송.

---

### 5. `api-ventago/src/app/print/qr-public.controller.ts` (controller, request-response)

**Analog 1 — `@Public()` + `@Throttle` 골격:** `api-ventago/src/app/online-orders/public-delivery.controller.ts:20-38`
```typescript
import { Public } from 'src/app/auth/decorators/public.decorator';
import { PUBLIC_DELIVERY_THROTTLE } from 'src/common/throttle/throttle.constants';

@Controller('public/entrega')
export class PublicDeliveryController {
  constructor(private readonly service: OnlineOrdersService) {}

  @Public()
  @Throttle(PUBLIC_DELIVERY_THROTTLE)
  @Post('consultar')
  async consultar(@Body() body: { token?: string }) {
    return this.service.getPublicDelivery(body?.token ?? '');
  }
}
```

**Analog 2 — `storeId` 파라미터 + 쿼리 화이트리스트:** `api-ventago/src/app/shop-public/shop-catalog.controller.ts:1-33`
```typescript
const CATALOG_SORTS = ['newest', 'price_asc', 'price_desc', 'bestseller'] as const;

@Controller('public/shop')
export class ShopCatalogController {
  @Public()
  @Get(':storeId/products/:slug')
  async detail(
    @Param('storeId', ParseIntPipe) storeId: number,
    @Param('slug') slug: string,
  ): Promise<ShopProductDto> {
    return this.catalog.getProductBySlug(storeId, slug);
  }
}
```

**이 phase에서 바꿀 것:** 신규 `@Controller('public/qr-stock')`, `GET :storeId/:productId`(둘 다 `ParseIntPipe`), 새 `PUBLIC_LEAD_THROTTLE`(아래 §throttle 참조) 또는 기존 `PUBLIC_DELIVERY_THROTTLE` 그대로 재사용. `qr_precio_publico`가 꺼진 매장·`stores.slug` 유무 분기는 서비스 계층에서 처리(Open Question #1 — PLAN 단계에서 "가격만 숨김 vs 페이지 자체 404" 확정 필요, RESEARCH.md 참조).

---

### 6. `api-ventago/src/app/print/qr-public.service.ts` (service, CRUD 단건 조회)

**Analog — 명시적 필드 나열 + `store_id` 강제 + NotFound:** `api-ventago/src/app/shop-public/shop-catalog.service.ts:324-365`
```typescript
async getProductBySlug(storeId: number, slug: string): Promise<ShopProductDto> {
  ...
  const rows = await this.db.query<Record<string, unknown>>(
    `SELECT p.id, p.name, p.slug, p.description, p.long_description, p.price,
            p.image_url, p.image_urls, p.gender, p.material, p.category_id,
            p.price_orig, COALESCE(m.available, 0) AS stock
       FROM products p
       LEFT JOIN v_stock_total_madre m
              ON m.madre_id = p.id AND m.store_id = p.store_id
      WHERE p.store_id = $1
        AND p.slug = $2
        AND p.is_published_shop = TRUE
        AND COALESCE(p.is_active, TRUE) = TRUE
        AND p.parent_id IS NULL
      LIMIT 1`,
    [storeId, slug],
  );

  if (rows.length === 0) {
    throw new NotFoundException('상품을 찾을 수 없습니다');
  }
  ...
}
```
★ **`WHERE p.store_id = $1 AND ...`** 가 테넌트 격리의 전부다 — `@Public()` 라우트는 전역 테넌트 가드가 no-op 이므로 이 조건이 없으면 남의 매장 상품을 조회할 수 있다(CLAUDE.md·CONTEXT ③ 경고 그대로).

**`qr_print_log` 최신 1건 조회 + 테넌트 강제(신규 쿼리, CONTEXT ① 전제 2·3 반영):**
```sql
SELECT l.price_type_id, l.printed_price, l.printed_at
  FROM qr_print_log l
  JOIN products p ON p.id = l.product_id   -- ★ store_id 가 log 테이블엔 없다 → products 조인으로 강제
 WHERE l.product_id = $1
   AND p.store_id = $2                      -- 테넌트 강제 지점
 ORDER BY l.printed_at DESC
 LIMIT 1
```
- `qr_print_log` 모델(`api-ventago/src/app/print/qr-print-log.model.ts:12-17`)의 자체 주석이 이미 "이 모델엔 store_id 가 없어 association 이 없으면 격리 훅이 붙을 자리가 없다"고 경고하고 있다 — 그대로 raw SQL 조인이 유일한 방어선.
- 인쇄 기록이 없으면(0행) `products.price`(base)로 폴백하고 응답에 `priceSource: 'exact' | 'fallback'`을 반드시 포함(Pitfall 2, CONTEXT ① 전제 4). `ShopProductDto`처럼 필드를 열거해 원가·공급처 등 내부 컬럼을 실수로 흘리지 않는다(Anti-Pattern, RESEARCH.md).

**`@Public()` 라우트의 IDOR 방지 선례(참고용 — 같은 모듈 내 유사 교훈):** `api-ventago/src/app/print/print.service.ts:170-181`
```typescript
/**
 * [Phase 85 W6] 상품이 어느 매장 것인지 알려준다 (소유권 검사용).
 *
 * ★ `getBranchStoreId` · `getAgentOwnership` 과 짝을 이루는 것이 원래 있어야 했다.
 *   지점·에이전트에는 있었는데 **상품에만 없어서** 남의 매장 라벨이 출력됐다.
 */
async getProductStoreId(productId: number): Promise<number | null> {
  const product = await this.productRepo.findByPk(productId, { attributes: ['id', 'storeId'] });
  return product ? Number(product.storeId) : null;
}
```
같은 실수(상품 소유권 검사 누락)가 이 모듈에 **전례로 기록돼 있다** — `qr-public.service.ts`를 새로 짤 때 반드시 상품→매장 소유권을 조회 조건에 넣을 것.

**이 phase에서 바꿀 것:** 신규 파일/메서드. `getProductBySlug`의 필드-열거+store_id 강제 패턴을 그대로 복제하고, `qr_print_log` JOIN 을 추가.

---

### 7~9. Leads 모듈 (신규) — `lead.model.ts` / `leads.module.ts` / `leads-public.controller.ts`

**모델 analog:** `api-ventago/src/app/onboarding/pending-registration.model.ts:1-15`
```typescript
import { Column, DataType, Model, Table } from 'sequelize-typescript';

@Table({ tableName: 'pending_registrations', timestamps: false })
export class PendingRegistration extends Model {
  @Column({ type: DataType.BIGINT, primaryKey: true, autoIncrement: true })
  declare id: number;

  @Column({ type: DataType.STRING(255), allowNull: false })
  declare companyName: string;
  ...
}
```
★ **모든 `@Column`에 명시적 `type`이 있다** — CLAUDE.md·이 저장소 메모리("@Column 에 type 을 안 쓰면 운영 부팅이 죽는다")의 이유. `lead.model.ts`도 `storeId: DataType.INTEGER`, `contactName: DataType.STRING(160)` 등 전부 명시.

**모듈 analog:** `api-ventago/src/app/print/print.module.ts:20-41`
```typescript
@Module({
  imports: [
    SequelizeModule.forFeature([ ... QrPrintLog ]),
    WebsocketModule,
    ProductsModule,
  ],
  controllers: [PrintController],
  providers: [PrintService, PrintGateway, PrintAgentReaperCron],
  exports: [PrintService],
})
export class PrintModule {}
```
`leads.module.ts`는 `SequelizeModule.forFeature([Lead])` + `LeadsPublicController` + `LeadsService`만 있으면 된다 — Websocket/Products 불필요.

**컨트롤러 analog:** `PublicDeliveryController`(§5 참조) 그대로 — `@Public() @Throttle(...) @Post()`.

**텔레그램 알림 재사용 — `api-ventago/src/app/onboarding/onboarding-alta.service.ts:218-226`:**
```typescript
notifyTelegram(
  `⏳ <b>Aprobación pendiente — se suspende mañana</b>\n` +
    `• Tienda: <b>${p.companyName}</b>\n` +
    `• CUIT: <code>${p.companyCuit}</code>\n` +
    `• Titular: ${p.name} ${p.lastName} · ${p.email}\n` +
    `Si no la aprobás, la tienda queda suspendida.`,
  { dedupKey: `alta-aviso-${p.id}` },
);
```
`notifyTelegram` 전체 구현은 `api-ventago/src/common/telegram/telegram.ts:1-121`(발췌 위 「Shared Patterns」 참조) — import 만 하면 되고 재작성 불필요.

**이 phase에서 바꿀 것:** 저장(`Lead.create`) 후 `notifyTelegram(..., { dedupKey: 'ventago-lead-' + lead.id })` 한 줄 호출. 메일 발송은 1차 범위 제외(RESEARCH Q4 권장).

---

### 10. `api-ventago/migrations/<date>-ventago-leads.sql` (migration, 신규 테이블)

**Analog — BIGSERIAL 신규 테이블 + owner/sequence 이전:** `api-ventago/migrations/2026-08-25-phase86-upload-sessions.sql:30-88`(전문)
```sql
SET lock_timeout = '5s';

BEGIN;

CREATE TABLE IF NOT EXISTS legacy_upload_sessions (
  id           BIGSERIAL PRIMARY KEY,
  store_id     INTEGER     NOT NULL REFERENCES stores (id) ON DELETE CASCADE,
  ...
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'coolsistema') THEN
    ALTER TABLE    legacy_upload_sessions        OWNER TO coolsistema;
    ALTER SEQUENCE legacy_upload_sessions_id_seq OWNER TO coolsistema;
  END IF;
END
$$;

COMMIT;
```
★ **`ALTER SEQUENCE ... OWNER`를 빠뜨리면 안 된다** — `ALTER TABLE OWNER`는 시퀀스 owner 를 안 옮긴다(CLAUDE.md 명시). 새 테이블이라 `w4-exempt` 주석도 함께 넣는다:
```sql
-- w4-exempt: 이 배포에서 처음 만들어지는 테이블이라 읽는 코드가 아직 없다.
```
(문구는 `2026-08-25-phase86-upload-sessions.sql:24-25`, `2026-08-23-mp-oauth-states.sql:29-30` 두 파일이 동일하게 사용)

**테넌트 격리 컬럼 설계 analog(참고) — `api-ventago/migrations/2026-08-23-mp-oauth-states.sql:36-67`:** `@Public()` 콜백이 쓰는 테이블은 반드시 `store_id integer NOT NULL REFERENCES stores(id)`를 갖고, 그 값은 **인가된 요청이 정한 값**이어야 한다(“판정의 근거는 저장의 근거와 같아야” — 이 저장소 메모리). `ventago_leads.store_id`도 QR 을 찍은 그 매장 id를 서버가 `qr-public` 조회에서 이미 검증한 값으로 채운다(클라이언트가 임의로 보낸 storeId 를 그대로 믿지 않는다 — 프론트가 보낸 storeId 는 참고용이고, 서버가 상품→매장 조회로 재검증).

**이 phase에서 바꿀 것:** `ventago_leads(id BIGSERIAL, store_id INT NOT NULL REFERENCES stores(id), contact_name TEXT, contact_phone TEXT, source_product_id INT, created_at TIMESTAMPTZ DEFAULT now())` + owner DO 블록. 로컬 5432 + 운영 5434 동시 적용(CLAUDE.md 규칙).

---

### 11. `api-ventago/migrations/<date>-store-configs-qr-precio-publico.sql` (migration, boolean 컬럼 추가)

**Analog(가장 최근 `store_configs` boolean 전례):** `api-ventago/migrations/2026-08-28-store-commerce-auto-sync.sql`(전문)
```sql
BEGIN;

SET lock_timeout = '5s';

ALTER TABLE store_configs
  ADD COLUMN IF NOT EXISTS commerce_auto_sync BOOLEAN NOT NULL DEFAULT true;

COMMENT ON COLUMN store_configs.commerce_auto_sync IS
  '판매·재고·상품 편집이 일어나면 연동된 쇼핑몰로 자동 전송할까. 목적지 공통.';

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'coolsistema') THEN
    EXECUTE 'ALTER TABLE store_configs OWNER TO coolsistema';
  END IF;
END $$;

COMMIT;
```
★★ **기본값만 다르게(false)** — CONTEXT ④ 결정 그대로. `commerce_auto_sync`는 `DEFAULT true`였지만 이번 컬럼은 **`DEFAULT false`**(Pitfall 3, RESEARCH.md — "기존 14개 매장이 전부 꺼짐으로 시작"). `NOT NULL DEFAULT false`로 한 파일에서 끝낼 수 있다(기존 행에 컬럼이 추가돼도 값이 즉시 채워지므로 별도 백필 불필요 — `users.email` 케이스와 달리 nullable 단계가 필요 없다).

**이 phase에서 바꿀 것:** `ADD COLUMN IF NOT EXISTS qr_precio_publico BOOLEAN NOT NULL DEFAULT false;` + 동일 owner DO 블록. (컬럼명은 RESEARCH.md Assumption A1 — PLAN 단계에서 최종 확정 필요.)

---

### 12. `api-ventago/src/app/store/config/storeConfig.model.ts` (수정)

**Analog(바로 위/아래 줄, 같은 파일):** line 92-95, 207-213
```typescript
// Prueba Virtual(VTO) 활성 토글 — 매장 admin 이 update-flag 로 제어 (Phase 49-M).
// false 면 판매원 앱에서 버튼 숨김 + 서버 403.
@Column({ field: 'vto_enabled', type: DataType.BOOLEAN, defaultValue: true })
vtoEnabled: boolean;

...

@Column({
  field: 'commerce_auto_sync',
  type: DataType.BOOLEAN,
  allowNull: false,
  defaultValue: true,
})
commerceAutoSync: boolean;
```
★ `type: DataType.BOOLEAN`을 **반드시 명시**(CLAUDE.md — 유니온 타입은 `design:type`이 Object 라 운영 부팅이 죽는다는 규칙과 같은 이유로, `@Column()`에 `type` 자체를 생략해도 위험. 이 파일은 전부 명시적으로 쓰고 있다).

**이 phase에서 바꿀 것:** 파일 끝에 `qrPrecioPublico` 컬럼 추가:
```typescript
@Column({
  field: 'qr_precio_publico',
  type: DataType.BOOLEAN,
  allowNull: false,
  defaultValue: false,
})
qrPrecioPublico: boolean;
```

---

### 13. `api-ventago/src/app/store/config/storeConfig.controller.ts` (수정, `FLAG_FIELDS`)

**Analog(같은 파일, line 108-121):**
```typescript
private static readonly FLAG_FIELDS = [
  'useSupplier',
  ...
  'vtoEnabled', // Prueba Virtual(VTO) 활성 토글 (Phase 49-M)
  'useFacturaElectronica', // AFIP Factura Electrónica 활성 토글
  'afipAutoIssue', // AFIP 무모달 자동발급 (기본 OFF — F10 확인 플로우 사용)
  'afipPrintTermica', // 발급 모달의 Térmica 기본 선택 (기본 ON — 종전 동작)
];
```
★ 이 배열이 **유일한 화이트리스트**다 — `updateFlag()`가 `PATCH`/`PUT` 둘 다 같은 구현을 호출하므로(line 79-87 주석: "한쪽에만 조건을 추가하면 다른 동사가 우회로가 된다") 한 곳에만 추가하면 된다.

**이 phase에서 바꿀 것:** `'qrPrecioPublico', // QR 상품 상세 딥링크 노출 토글 (Phase 89)`를 배열에 추가. `useFacturaElectronica`처럼 "켜는 순간에만" 추가 검증이 필요한지는 이번엔 불필요(서류 요구 없음) — `body.field === 'useFacturaElectronica'` 같은 조건부 블록은 복제하지 않는다.

---

### 14. `ventago-app/src/context/StoreConfigContext.tsx` (수정)

**Analog(같은 파일 3곳, line 33-34 / 100-101 / 197):**
```typescript
// interface
vtoEnabled: boolean;

// default
vtoEnabled: true,

// API 응답 매핑
vtoEnabled: res?.vtoEnabled ?? true,
```
**이 phase에서 바꿀 것:** 동일한 3곳에 `qrPrecioPublico: boolean` 추가하되 기본값은 **`false`**(vtoEnabled 와 반대 — CONTEXT ④ "기본값 꺼짐" 그대로, "store_config 행 부재 매장 안전 폴백"도 false 가 안전).

---

### 15. `ventago-app/src/views/configuracion/qr/QrConfigView.tsx` (신규)

**Analog(전체 구조):** `ventago-app/src/views/configuracion/inventario/InventarioConfigView.tsx:28-80`
```typescript
const InventarioConfigView = () => {
  const { user } = useAuth()
  const storeId = user?.storeId
  const { allowSaleWithoutStock, unpaidHoldAlertDays, reload } = useStoreConfig()
  const [enabled, setEnabled] = useState<boolean>(allowSaleWithoutStock)
  ...
  const handleToggle = async (next: boolean) => {
    if (!storeId) return
    setEnabled(next)
    setSaving(true)
    setError(null)
    try {
      await apiConnector.put(`/store-config/${storeId}/update-flag`, {
        field: 'allowSaleWithoutStock',
        value: next,
      })
      await reload()
      toast.success(next ? '...' : '...')
    } catch {
      setEnabled(!next)
      reportError('No se pudo guardar la configuración. Reintentá en unos segundos.')
    } finally {
      setSaving(false)
    }
  }
```
**이 phase에서 바꿀 것:** `field: 'qrPrecioPublico'`로 교체, 문구를 "구입자가 QR 로 가격을 볼 수 있게 할 것인가"(CONTEXT ④)로 변경. 낙관적 업데이트+실패 시 원복 패턴은 그대로 복제.

---

## Shared Patterns

### A. 공개 페이지 = `authGuard=false` + `guestGuard=false` + `BlankLayout` + raw `fetch`
**Source:** `ventago-app/src/pages/entrega/[token].tsx:245-247, 22-24, 34-49`
**Apply to:** `pages/m/stock/index.tsx` 전체, `ResellerApplyForm`/`VentagoLeadForm`의 데이터 전송 로직.
**핵심 이유:** `apiConnector`는 401 시 `/login`으로 리다이렉트하는 전역 인터셉터를 갖고 있다 — 공개 페이지에서 쓰면 고객이 로그인 화면으로 튕긴다.

### B. `@Public()` 라우트는 서버가 직접 `storeId`를 강제한다
**Source:** `api-ventago/src/app/shop-public/shop-catalog.service.ts:341` (`WHERE p.store_id = $1`), `api-ventago/migrations/2026-08-23-mp-oauth-states.sql`(설계 원칙 주석), `api-ventago/src/app/print/print.service.ts:170-181`(상품 소유권 검사 누락 전례)
**Apply to:** `qr-public.controller.ts`/`.service.ts`, `leads-public.controller.ts`.
**핵심 이유:** 전역 테넌트 가드는 `@Public()` 라우트에서 no-op — 컨트롤러/서비스 코드가 유일한 방어선.

### C. 공개 응답은 필드를 명시적으로 나열한다 (`SELECT *` 금지)
**Source:** `api-ventago/src/app/shop-public/shop-catalog.service.ts:96-108`(`ShopProductDto` 인터페이스) + `:190-203`(`toDto` 매핑)
**Apply to:** `qr-public.service.ts`의 응답 DTO.

### D. Rate limit — `@Throttle` + `throttle.constants.ts`
**Source:** `api-ventago/src/common/throttle/throttle.constants.ts:72-79`
```typescript
export const PUBLIC_DELIVERY_THROTTLE = {
  default: {
    ttl: 60000,
    limit: toInt(process.env.THROTTLE_PUBLIC_DELIVERY_LIMIT, 20),
    blockDuration: 60000,
  },
};
```
**Apply to:** `qr-public.controller.ts`, `leads-public.controller.ts`. 새 상수(`PUBLIC_QR_THROTTLE`/`PUBLIC_LEAD_THROTTLE`)를 같은 형태로 추가하거나 값이 같다면 `PUBLIC_DELIVERY_THROTTLE`을 그대로 재사용(둘 다 "정상 고객은 새로고침 몇 번" 수준의 트래픽).

### E. 텔레그램 알림 — `notifyTelegram()` (재작성 금지)
**Source:** `api-ventago/src/common/telegram/telegram.ts:114-121`
```typescript
export function notifyTelegram(text: string, options: TelegramOptions = {}): void {
  sendTelegramMessage(text, options).catch(() => { /* already logged */ });
}
```
**Apply to:** `leads-public.controller.ts`(또는 `leads.service.ts`) — 리드 저장 성공 후 fire-and-forget 호출.

### F. `store_configs` boolean 추가 = 모델+화이트리스트+Context+Configuración 4벌 세트
**Source:** `vtoEnabled`/`allowSaleWithoutStock`가 이미 이 4곳(모델 `@Column`, 컨트롤러 `FLAG_FIELDS`, `StoreConfigContext.tsx`, `*ConfigView.tsx`)에 전부 있다.
**Apply to:** `qrPrecioPublico` 전 과정. **한 곳이라도 빠뜨리면** 저장은 되는데 화면에 안 보이거나(Context 누락), 토글 버튼을 눌러도 400(FLAG_FIELDS 누락)이 난다.

### G. 마이그레이션 — `lock_timeout` + owner DO 블록 (+ 신규 테이블은 `w4-exempt`)
**Source:** `api-ventago/migrations/2026-08-25-phase86-upload-sessions.sql`, `2026-08-28-store-commerce-auto-sync.sql`
**Apply to:** 이 phase의 마이그레이션 파일 2개 전부. 신규 테이블(`ventago_leads`)엔 `w4-exempt` 주석 필수(읽는 코드가 아직 없으므로 무중단 규약 검사 대상에서 면제 — 근거를 그 자리에 적는다), 기존 테이블 컬럼 추가(`store_configs`)는 `NOT NULL DEFAULT false` 한 문장으로 끝나 별도 백필 불필요.

### H. `reseller` 스키마 — Sequelize `@Table({schema:'reseller'})` + raw SQL `FROM reseller.xxx`
**Source:** `api-ventago/src/app/reseller/reseller.model.ts:10-11`
```typescript
// 재판매자 (Phase 24 reseller 스키마. legacy public.revendedores 와 별개).
@Table({ tableName: 'resellers', schema: 'reseller', timestamps: true })
export class Reseller extends Model { ... }
```
및 `api-ventago/src/app/reseller/auth/reseller-auth.service.ts:188`
```sql
FROM reseller.reseller_tienda_link l
```
**Apply to:** 이 phase 는 `reseller` 모듈 코드를 수정하지 않지만(RESEARCH 권장 — 백엔드 무변경), `ResellerApplyForm`이 부르는 `POST /reseller/auth/register`가 내부적으로 이 스키마에 쓴다는 것을 계획서에 명시해 `revendedor`(legacy, `public` 스키마) 레거시 모듈과 혼동하지 않게 한다.

---

## 진단 전용 절: 상품 이미지 URL 모지바케 (114건 중 60건, 53%)

**요청 사항:** 고치지 않는다. 이미지 URL을 만드는 코드 경로 전부를 찾아 후보를 남긴다.

### 경로 1 — 상품 생성 시 서버측 파일명 생성 (`products.service.ts:339-361`)
```typescript
let finalImageName = imageName;
if (!finalImageName && imageFile) {
  const createdAt =
    product.createdAt instanceof Date
      ? product.createdAt.toISOString().replace(/[-:T.]/g, '').slice(0, 14)
      : '';
  finalImageName = `${product.sku}_${createdAt}`;
}

if (finalImageName) {
  if (imageFile) {
    await this.minioService.uploadFile({ ...imageFile, originalname: finalImageName });
  }
  await product.update({ imageUrl: finalImageName });
}
```
- `create()` 호출 시 이미지가 새로 업로드되면 파일명은 **서버가 `{sku}_{timestamp}`로 생성**한다 — SKU 는 통상 ASCII 라 이 경로 자체는 모지바케 원인이 아니다.
- ★ 그러나 `imageName`(호출자가 넘기는 값, `CreateProductDto.imageName?: string` — `create-products.dto.ts:132`)이 **있으면 그 값을 그대로 쓴다.** 이 값이 어디서 오는지(변형 생성 시 부모 imageName 복사? 일괄 편집 스크립트?)는 이번 조사에서 호출부를 전부 추적하지 못했다 — **후보 1순위**: `imageName`을 넘기는 다른 호출부가 원본 파일명(비ASCII)을 그대로 실어 보냈을 가능성.

### 경로 2 — MinIO 업로드 자체는 파일명을 검증/정규화하지 않는다 (`api-ventago/src/common/minio/minio.service.ts:74-83`)
```typescript
async uploadFile(file: Express.Multer.File, customName?: string): Promise<{ fileName: string }> {
  const fileName = customName || file.originalname;
  await this.client.putObject(this.bucket, fileName, file.buffer, file.size, {
    'Content-Type': file.mimetype || 'application/octet-stream',
  });
  return { fileName };
}
```
- `customName`이 없으면 **`file.originalname`을 그대로 S3 키로 쓴다.** Multer(Busboy 기반)가 `multipart/form-data`의 `Content-Disposition: filename="..."` 헤더를 어떤 charset 으로 디코드하는지에 따라, 브라우저가 UTF-8 바이트를 그대로 실어 보내는 필드를 서버가 latin1 로 잘못 해석하면 정확히 `RiÃ±onera` 같은 이중 인코딩(모지바케)이 생긴다 — 이 저장소에서 **busboy `defParamCharset`/`defCharset` 설정을 명시적으로 지정한 곳이 없다**(grep 결과 0건, `main.ts`/`products.module.ts` 확인). **후보 2순위(가장 유력)**: 원본 상품 이미지 업로드(관리자 화면에서 "Riñonera113-1.jpg" 같은 파일을 직접 첨부) 시 Multer/Busboy 기본 디코딩 경로.

### 경로 3 — 관리자 수동 업로드는 sanitize 되지만 규칙이 다르다 (`minio.controller.ts:47-63, 74-88`)
```typescript
function sanitizeFileName(raw?: string): string | undefined {
  if (!raw) return undefined;
  const base = raw.split(/[/\\]/).pop() || '';
  const cleaned = base.replace(/\.\./g, '').replace(/[^\w.-]/g, '_').trim();
  return cleaned || undefined;
}

@Post('')
@Auth()
@UseInterceptors(FileInterceptor('file'))
async uploadImage(@UploadedFile() file: Express.Multer.File, @Body() body: any) {
  ...
  const safeName = sanitizeFileName(body?.fileName);
  return await this.service.uploadFile(file, safeName);
}
```
- `[^\w.-]`(ASCII `\w`만 인정)는 `ñ` 같은 비ASCII 문자를 `_`로 치환한다 — **이 경로를 탔다면 애초에 모지바케가 생길 수 없다**(결과가 `_` 아니면 이 경로가 아니다). 운영에서 관측된 파일명(`RiÃ±onera113-1.jpg`)은 밑줄로 치환된 흔적이 없으므로, **이 sanitize 를 거치지 않은 다른 업로드 경로(= 경로 1 또는 경로 2, 혹은 상품 모듈 전용 별도 컨트롤러)를 통과했다는 간접 증거**다.

### 경로 4 — 프론트 이미지 URL 조립 (인코딩 없이 그대로 삽입)
```typescript
// ventago-app/src/components/product/ProductPhotoBox.tsx:8-9 (외 columns.tsx, ImgProducts.tsx 등 총 9곳 동일 패턴)
/^https?:\/\//.test(name) ? name : `${constants.api}/minio/${name}`
```
```typescript
// api-ventago/src/app/integrations/wp/wp-sync.service.ts:59-65
private imageSrc(imageUrl: string | null | undefined): string | null {
  const v = (imageUrl || '').trim();
  if (!v) return null;
  if (/^https?:\/\//i.test(v)) return v;
  return `${this.apiBase()}/minio/${v.replace(/^\/+/, '')}`;
}
```
- **아홉 곳 전부 `encodeURIComponent()`를 쓰지 않는다.** DB 값이 이미 모지바케(예: `RiÃ±onera113-1.jpg`, 이것 자체가 유효한 문자열)라면 이 조립 단계는 **그 값을 그대로 옮길 뿐 새로 깨뜨리지 않는다** — 즉 이 경로는 원인이 아니라 **증상을 그대로 통과시키는 지점**일 가능성이 높다(브라우저가 URL 의 비ASCII 문자를 자동으로 percent-encode 하는데, 그 결과가 MinIO 에 실제 저장된 키와 다르면 404 — RESEARCH 실측과 일치).

### 경로 5 — `MinioController.getImage`(서빙) 자체는 디코딩을 하지 않는다
```typescript
// api-ventago/src/common/minio/minio.controller.ts:91-105
@Public()
@Get(':filename')
async getImage(@Param('filename') filename: string, @Res() res: any) {
  if (!isPubliclyServable(filename)) { throw new ForbiddenException(...); }
  try {
    const stream = await this.service.getObjectStream(filename);
    ...
  } catch (err) { res.status(404).send('Not found'); }
}
```
- `@Param('filename')`은 Express 가 URL 디코딩을 자동으로 해준 뒤의 문자열이다. 브라우저가 보낸 percent-encoded 값과 MinIO 에 실제 저장된 오브젝트 키가 바이트 단위로 다르면(경로 2/4의 결과) 여기서 **404**가 난다 — RESEARCH.md 의 "ASCII 이름은 200, 비ASCII는 404" 실측과 정확히 들어맞는 지점.

### 진단 우선순위 제안 (고치지 말고 다음 세션에서 이 순서로 좁힐 것)
1. **경로 2(Multer/Busboy 기본 charset)**를 재현: 로컬에서 `curl -F "file=@Riñonera.jpg"`로 상품 이미지 업로드 API 를 직접 호출해 `products.image_url` 에 저장된 바이트를 확인 — 모지바케가 재현되면 원인 확정.
2. 재현 안 되면 **경로 1(`imageName` 호출부)**을 `grep -rn "imageName:" api-ventago/src/app`으로 전수 추적 — 어느 호출부가 원본 파일명을 그대로 넘기는지 특정.
3. 위 둘 다 아니면 **DB 데이터 자체가 이미 모지바케**(예: 레거시 엑셀 임포트 당시 인코딩 오류)일 가능성 — `import.service.ts`/구 마이그레이션 스크립트의 CSV/XLSX 읽기 인코딩을 확인.

---

## No Analog Found

없음 — 15개 파일 전부 이 저장소 안에서 최소 role-match 이상의 analog 을 찾았다(위 표 참조). `ResellerApplyForm.tsx`만 "공개+multipart" 조합의 **정확한 선례가 없어** 두 패턴(무인증 raw fetch + FormData 조립)을 조합해야 한다는 점을 표에 partial-match 로 명시했다.

## Metadata

**Analog 검색 범위:** `ventago-app/src/pages`, `ventago-app/src/views`, `ventago-app/src/context`, `ventago-app/src/components/product`, `api-ventago/src/app/{shop-public,print,reseller,onboarding,store,online-orders,leads(신규),common/{telegram,minio,throttle}}`, `api-ventago/migrations/2026-08-* ~ 2026-09-*`
**파일 스캔:** grep/read 약 40여 개 파일
**추출 날짜:** 2026-09-16
