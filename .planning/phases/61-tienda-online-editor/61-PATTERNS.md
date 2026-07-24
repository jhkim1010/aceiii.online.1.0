# Phase 61: Tienda Online 에디터 확장 — Pattern Map

**Mapped:** 2026-07-23
**Files analyzed:** 23 (명시 파일 15 + 암묵 파일 8)
**Analogs found:** 18 / 23 (exact/role-match), 5 는 No Analog(신규 패턴 도입 — 코드베이스에 grep 0건)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `api-ventago/src/app/shop-public/store-theme.constants.ts` | config/utility (SSOT) | transform | 자기 자신(기존 6-토큰 부분 확장) | exact |
| `api-ventago/src/app/shop-public/store-theme-admin.controller.ts` | controller | request-response + file-I/O(신규 asset 라우트) | 자기 자신 + `store.controller.ts`(업로드 라우트) | exact(기존부) / role-match(신규 asset 라우트) |
| `api-ventago/src/app/shop-public/store-theme-admin.service.ts` | service | CRUD | 자기 자신 | exact |
| `api-ventago/src/app/shop-public/shop-public.module.ts` | config(module) | — | 자기 자신 + `MinioModule` import 참고처 다수 모듈 | exact |
| `api-ventago/src/app/shop-public/shop-catalog.controller.ts` | controller | request-response | 자기 자신 | exact |
| `api-ventago/src/app/shop-public/shop-catalog.service.ts` | service | CRUD | 자기 자신 | exact |
| `api-ventago/migrations/2026-07-XX-store-themes-macro-rails-masonry.sql` | migration | batch(DDL) | `api-ventago/migrations/2026-07-22-store-themes-enabled.sql` | exact |
| `api-ventago/src/app/shop-public/store-theme.constants.spec.ts` | test | — | `api-ventago/src/app/afip/code-maps.spec.ts` | exact(순수함수 유닛테스트 관례) |
| `tienda-app/src/pages/[storeId]/panel/diseno.tsx` | provider/page(에디터) | request-response(draft/publish) | 자기 자신 | exact |
| `tienda-app/src/components/panel/SectionListEditor.tsx` | component | CRUD(순서/토글) | `diseno.tsx`의 `ui.segs`/`ui.seg`/`ui.segOn` 버튼그룹 패턴 | role-match(신규 파일, 없음) |
| `tienda-app/src/pages/[storeId]/index.tsx` | page(스토어프론트) | request-response(SSR) | 자기 자신 | exact |
| `tienda-app/src/components/sections/Hero.tsx` | component | transform(render) | `index.tsx`의 `s.hero`/`s.heroBig`/`s.heroTitle` 블록 | role-match |
| `tienda-app/src/components/sections/Benefits.tsx` | component | transform(render) | `index.tsx`의 `s.aistrip` 블록 | role-match |
| `tienda-app/src/components/sections/Carousel.tsx` | component | request-response(fetch) + transform | `index.tsx`의 그리드 섹션(`s.secHead`+`gridStyle`+`ProductCard.map`) | role-match |
| `tienda-app/src/components/sections/DuoBanners.tsx` | component | transform(render) | `index.tsx`의 `s.promo` 블록 | role-match |
| `tienda-app/src/components/sections/Newsletter.tsx` | component | request-response(폼 제출) | `Header.tsx`의 `s.search` 입력 스타일 | partial-match |
| `tienda-app/src/components/sections/ReelsSection.tsx` | component | streaming(video) | 없음(코드베이스 `<video>`/`IntersectionObserver` 사용례 0건) | no-analog — RESEARCH 코드 스케치가 유일 근거 |
| `tienda-app/src/components/sections/QuizSection.tsx` | component | event-driven(다단계 위저드) | 없음(멀티스텝 위저드 패턴 0건) — `diseno.tsx` state/patch 패턴을 행동 패턴으로 재사용 | no-analog(구조) / role-match(상태관리 스타일) |
| `tienda-app/src/components/macro/RailsLayout.tsx` | component | transform(render)+event-driven(lazy load) | 없음(`IntersectionObserver`/`scroll-snap` 사용례 0건) | no-analog — RESEARCH 코드 스케치가 유일 근거 |
| `tienda-app/src/components/macro/MasonryLayout.tsx` | component | transform(render) | `index.tsx`의 `gridStyle` 삼항 분기(교체 대상) | role-match(구조 참고용, CSS 접근은 신규) |
| `tienda-app/src/components/ProductCard.tsx` | component | transform(render) | 자기 자신 | exact |
| `tienda-app/src/lib/theme-preset.ts` | utility(SSOT 미러) | transform | 자기 자신 | exact |
| `tienda-app/src/services/shop-api.ts` *(암묵 — R2/R6/R9 파라미터 확장 필요)* | service(API client) | request-response | 자기 자신 | exact |
| `tienda-app/src/types/shop.ts` *(암묵 — StoreTheme content/priceOrig/stock/Macrostructure 5종)* | model(타입) | — | 자기 자신 | exact |

**참고 — 명시 목록에 없지만 RESEARCH 「핵심 발견 2」로 반드시 선행 필요한 암묵 파일:**
- `shop-catalog.service.ts` 의 `ShopProductDto`/`toDto()`/SELECT 절 확장(`priceOrig`/`stock`) — R5(ProductCard) 의 데이터 소스. 이미 위 표에 포함.
- `shop-api.ts`/`types/shop.ts` — 프런트가 백엔드 확장 응답(`content`, `priceOrig`, `stock`, 5종 macrostructure, sort/pageSize/showOutOfStock 쿼리)을 받으려면 타입·API 클라이언트도 함께 확장돼야 함. 계획 단계에서 누락하면 TS 컴파일이 막힘.

---

## Pattern Assignments

### 그룹 A — 백엔드 SSOT 확장: `store-theme.constants.ts` / `store-theme-admin.controller.ts` / `store-theme-admin.service.ts`

**Analog:** 세 파일 모두 자기 자신(기존 코드를 확장하는 작업) — 기존 구조를 그대로 이어간다.

**저장/응답 퍼널 패턴** (`store-theme-admin.service.ts:79-107`):
```typescript
async saveDraft(
  storeId: number,
  body: SaveDraftBody,
): Promise<StoreThemeResponse> {
  const { baseTheme, tokens } = sanitizeTokens(
    body.baseTheme ?? 'Studio',
    body.tokens,
  );
  const macro = sanitizeMacrostructure(body.macrostructure);
  const draft = { baseTheme, macrostructure: macro, ...tokens };   // ★ flat 병합

  await this.sequelize.query(
    `INSERT INTO store_themes (store_id, draft_tokens, updated_at)
     VALUES ($1, $2::jsonb, NOW())
     ON CONFLICT (store_id)
     DO UPDATE SET draft_tokens = EXCLUDED.draft_tokens, updated_at = NOW()`,
    { bind: [storeId, JSON.stringify(draft)], type: QueryTypes.INSERT },
  );

  return buildThemeResponse(storeId, baseTheme, macro, tokens);
}
```
**확장 방법**: `sanitizeContent(body.content)` 를 나란히 호출 → `draft = { baseTheme, macrostructure: macro, ...tokens, ...content }` 로 spread 확장. `buildThemeResponse()` 시그니처에 raw content 파라미터 추가, 반환 객체에 `content: StoreThemeContent` 필드 추가.

**sanitize 가드레일 패턴** (`store-theme.constants.ts:199-246`):
```typescript
// 값 범위 강제 (JSONB 가 오염돼도 안전한 렌더 보장)
function clamp(n: number, min: number, max: number, fallback: number): number {
  if (typeof n !== 'number' || Number.isNaN(n)) return fallback;
  return Math.min(max, Math.max(min, n));
}

export function sanitizeTokens(
  baseTheme: string,
  raw: Partial<StoreThemeTokens> | null | undefined,
): { baseTheme: string; tokens: StoreThemeTokens } {
  const safeBase = THEME_PRESETS[baseTheme] ? baseTheme : DEFAULT_BASE_THEME;
  const preset = THEME_PRESETS[safeBase];
  const r = raw ?? {};
  // ... whitelist(paperBand/fontPair) + clamp(accentHue/sat/weight/radius) + preset 기본값 폴백
}

export function sanitizeMacrostructure(raw: unknown): Macrostructure {
  return (['marquee', 'bento', 'doc'] as Macrostructure[]).includes(
    raw as Macrostructure,
  )
    ? (raw as Macrostructure)
    : DEFAULT_MACROSTRUCTURE;
}
```
**확장 방법**: `sanitizeMacrostructure()` 배열에 `'rails','masonry'` 추가(R9). 신규 `sanitizeContent(raw)` 함수를 이 옆에 추가해 brand/announce/sections/contact/productCard/catalog/trust/marketing 을 동일한 whitelist+clamp+default 철학으로 처리(RESEARCH 「Code Examples」 스켈레톤 재사용 — `sanitizeHref()`/`clampText()` 헬퍼 포함).

**컨트롤러 라우팅 패턴** (`store-theme-admin.controller.ts:39-79`):
```typescript
@Controller('shop')
export class StoreThemeAdminController {
  constructor(private readonly admin: StoreThemeAdminService) {}

  @UseGuards(StoreThemeEditGuard)
  @Put(':storeId/theme/draft')
  saveDraft(
    @Param('storeId', ParseIntPipe) storeId: number,
    @Body() body: SaveThemeBody,
  ): Promise<StoreThemeResponse> {
    return this.admin.saveDraft(storeId, body ?? {});
  }
```
**확장 방법**: `SaveThemeBody` 인터페이스에 `content?: Partial<StoreThemeContent>` 추가. 신규 asset 업로드 라우트는 그룹 C 패턴 참조, 동일 `@UseGuards(StoreThemeEditGuard)` 재사용.

**모듈 imports 패턴** (`shop-public.module.ts:31-38`):
```typescript
@Module({
  imports: [
    OnlineOrdersModule,
    PaymentsModule,
    AuthModule,
    PassportModule.register({ defaultStrategy: 'jwt' }),
  ],
```
**확장 방법**: `import { MinioModule } from 'src/common/minio/minio.module';` 추가 후 `imports` 배열에 `MinioModule` 추가.

---

### 그룹 B — 카탈로그 정렬/페이지/필터: `shop-catalog.controller.ts` / `shop-catalog.service.ts`

**Analog:** 자기 자신.

**컨트롤러 쿼리 파라미터 파싱 + clamp 패턴** (`shop-catalog.controller.ts:29-60`):
```typescript
@Public()
@Get(':storeId/products')
async list(
  @Param('storeId', ParseIntPipe) storeId: number,
  @Query('page') page?: string,
  @Query('pageSize') pageSize?: string,
  @Query('q') q?: string,
  @Query('categoryId') categoryId?: string,
  @Query('globalCategoryId') globalCategoryId?: string,
  @Query('gender') gender?: string,
): Promise<ShopListResult> {
  const safePage = Math.max(1, parseInt(page ?? '1', 10) || 1);
  const safePageSize = Math.min(
    50,   // ★ R6 요구사항대로 48 로 낮출 것 — SPEC 상한과 통일
    Math.max(1, parseInt(pageSize ?? '24', 10) || 24),
  );
  const parsedCat = categoryId ? parseInt(categoryId, 10) : NaN;
  const safeCat = Number.isNaN(parsedCat) ? null : parsedCat;
  // ...
  return this.catalog.listProducts(storeId, { page: safePage, pageSize: safePageSize, /* ... */ });
}
```
**확장 방법**: `@Query('sort')`, `@Query('showOutOfStock')` 추가. `sort` 는 whitelist(`'newest'|'price_asc'|'price_desc'`)로만 서비스에 전달 — 원시 문자열을 SQL 에 직접 넣지 않는다(Pitfall 5 / R8 gate).

**서비스 파라미터화 쿼리 + DTO + 캐시 패턴** (`shop-catalog.service.ts:23-134`):
```typescript
export interface ShopProductDto {
  id: number; name: string; slug: string | null; description: string | null;
  longDescription: string | null; price: number; imageUrl: string | null;
  imageUrls: string[] | null; gender: string | null; material: string | null;
  categoryId: number | null;
  // ★ 여기에 priceOrig / stock 추가 (R5 선행조건)
}

private toDto(row: Record<string, unknown>): ShopProductDto {
  return {
    id: Number(row.id),
    // ...
    price: row.price != null ? Number(row.price) : 0,
    // ★ priceOrig: row.price_orig != null ? Number(row.price_orig) : null,
    // ★ stock: row.stock != null ? Number(row.stock) : null,
  };
}

async listProducts(storeId: number, params: ShopListParams): Promise<ShopListResult> {
  // ...
  const cacheKey = `shop:list:${storeId}:${q ?? ''}:${categoryId ?? ''}:...:${page}:${pageSize}`;
  const cached = this.cache.get<ShopListResult>(cacheKey);
  if (cached) return cached;

  const rows = await this.db.query<Record<string, unknown>>(
    `SELECT p.id, p.name, p.slug, /* ... */ p.category_id,
            COUNT(*) OVER() AS total_count
       FROM products p
      WHERE p.store_id = $1 AND p.is_published_shop = TRUE AND COALESCE(p.is_active, TRUE) = TRUE
        AND ($2::text IS NULL OR p.name ILIKE '%' || $2 || '%')
        /* ... 파라미터 바인딩만, 문자열 보간 없음 */
      ORDER BY p.updated_at DESC   -- ★ whitelist switch 로 교체
      LIMIT $5 OFFSET $6`,
    [storeId, q ?? null, /* ... */],
  );
  // ...
  this.cache.set(cacheKey, result, LIST_TTL_MS); // 60초 TTL 컨벤션
}
```
**확장 방법**:
1. `SELECT` 에 `p.price_orig, p.stock` 추가 (컬럼 실존 — `.planning/intel/db-schema-tables.md:1206-1207,1218`, 단 stale 문서이니 `products` 관련 마이그레이션 파일로 교차검증).
2. `ORDER BY` 를 whitelist `switch`문으로 매핑(`newest→p.updated_at DESC`, `price_asc→p.price ASC`, `price_desc→p.price DESC`) — **절대 문자열 보간 금지**.
3. `showOutOfStock=false` → `AND p.stock > 0` 조건 추가.
4. 캐시 키에 `sort`/`showOutOfStock` 포함.

---

### 그룹 C — 테마 이미지/영상 업로드 엔드포인트 (R2, R10)

**Analog 1 — 기존 MinIO 업로드 컨트롤러 패턴** (`api-ventago/src/app/store/store.controller.ts:1-37, 73-86`):
```typescript
import { FileInterceptor } from '@nestjs/platform-express';
import { MinioService } from 'src/common/minio/minio.service';

@Controller('store')
export class StoreController {
  constructor(
    private readonly storeService: StoreService,
    // ...
    private readonly minioService: MinioService,
  ) {}

  @Post('new')
  @UseInterceptors(FileInterceptor('logoFile'))
  async create(
    @Body() body: CreateStoreDto,
    @UploadedFile() logoFile?: Express.Multer.File,
  ): Promise<any> {
    let logoUrl: string | undefined;
    if (logoFile) {
      const fileName = `store_logo_${Date.now()}_${logoFile.originalname}`;
      const result = await this.minioService.uploadFile(logoFile, fileName);
      logoUrl = result.fileName;
    }
    // ...
  }
}
```
**주의 (RESEARCH 확인)**: 이 패턴엔 확장자/MIME 검증이 없다 — SPEC 요구(png/jpg/webp/svg-logo-only, 2MB / mp4/webm, 20MB, poster 필수, UUID 파일명)는 이 패턴을 그대로 베껴선 안 되고 직접 추가해야 함.

**Analog 2 — 검증 있는 `FileInterceptor` limits 패턴** (`api-ventago/src/app/legacy-import/legacy-import.controller.ts:42-43, 79-100`):
```typescript
// 업로드 상한 (운영 PG10 메모리 보호) — 25MB
const MAX_FILE_BYTES = 25 * 1024 * 1024;

@Post('preview')
@UseGuards(AuthGuard('jwt'))
@UseInterceptors(
  FileInterceptor('file', { limits: { fileSize: MAX_FILE_BYTES } }),
)
async preview(
  @UploadedFile() file: Express.Multer.File,
  @GetUser() user: any,
): Promise<LegacyPreviewResult> {
  this.assertAdmin(user);
  const sqlText = await this.prepareSqlText(file);
  // ...
}
```

**Analog 3 — `MinioService.uploadFile()` 실제 시그니처** (`api-ventago/src/common/minio/minio.service.ts:43-52`):
```typescript
async uploadFile(
  file: Express.Multer.File,
  customName?: string,
): Promise<{ fileName: string }> {
  const fileName = customName || file.originalname;
  await this.client.putObject(this.bucket, fileName, file.buffer, file.size, {
    'Content-Type': file.mimetype || 'application/octet-stream',
  });
  return { fileName };
}
```
`FileInterceptor` 는 **memoryStorage**(기본값) — `file.buffer` 필요, `diskStorage` 로 바꾸면 깨진다.

**인가 재사용** (`store-theme-edit.guard.ts:14-34`, 전체):
```typescript
@Injectable()
export class StoreThemeEditGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const req = context.switchToHttp().getRequest<Request>();
    const auth = req.headers.authorization ?? '';
    const token = auth.startsWith('Bearer ') ? auth.slice(7) : '';
    const payload = verifyEditToken(token);
    if (!payload) throw new UnauthorizedException('유효하지 않거나 만료된 편집 토큰입니다');
    const storeId = Number(req.params.storeId);
    if (payload.storeId !== storeId) throw new UnauthorizedException('편집 토큰의 매장이 일치하지 않습니다');
    return true;
  }
}
```
**신규 엔드포인트 조립 방향** (3개 analog 합성 — RESEARCH 「MinIO 업로드 패턴」 섹션에 이미 완성 스케치 있음):
```typescript
const ALLOWED_IMAGE_EXT = ['png', 'jpg', 'jpeg', 'webp'];
const MAX_IMAGE_BYTES = 2 * 1024 * 1024;
const ALLOWED_VIDEO_EXT = ['mp4', 'webm'];
const MAX_VIDEO_BYTES = 20 * 1024 * 1024;

@Post(':storeId/theme/asset')
@UseGuards(StoreThemeEditGuard)                                // ★ Analog store-theme-edit.guard.ts 재사용
@UseInterceptors(FileInterceptor('file', { limits: { fileSize: MAX_VIDEO_BYTES } })) // ★ Analog 2
async uploadAsset(
  @Param('storeId', ParseIntPipe) storeId: number,
  @UploadedFile() file: Express.Multer.File,
  @Query('kind') kind: 'logo' | 'favicon' | 'hero' | 'banner' | 'reelVideo' | 'reelPoster',
) {
  // 확장자(originalname) + mimetype 이중 체크 → 실패 시 BadRequestException(400)
  // UUID 파일명 재부여: `${randomUUID()}.${ext}` (Date.now()+originalname 패턴 아님 — SPEC 명시)
  // logo 만 svg 허용, reelVideo 는 mp4/webm+20MB, 나머지 png/jpg/webp+2MB, poster 는 이미지 규칙 재사용
  const result = await this.minioService.uploadFile(file, uuidFileName); // ★ Analog 3
  return { fileName: result.fileName };
}
```

---

### 그룹 D — DDL 마이그레이션 (R9, 본 Phase 유일 DDL)

**Analog** (`api-ventago/migrations/2026-07-22-store-themes-enabled.sql`, 전체 — ALTER-only 마이그레이션의 헤더/트랜잭션 관례):
```sql
-- 2026-07-22 store_themes.enabled — 공개몰(스토어프론트) 활성 여부 admin 토글
-- 정책: 컬럼 기본 FALSE = 앞으로 새로 생성되는 매장은 비활성(유료 opt-in).
--       단, 이 마이그 시점의 기존 매장은 전부 활성으로 grandfather(서비스 중단 방지).
BEGIN;

ALTER TABLE store_themes
  ADD COLUMN IF NOT EXISTS enabled BOOLEAN NOT NULL DEFAULT FALSE;

-- ...

COMMIT;
```

**원 테이블 생성 마이그레이션의 role 존재 체크 DO 블록 관례** (`api-ventago/migrations/2026-07-22-store-themes.sql:18-30`):
```sql
-- 공개몰 조회는 shop_readonly role 로 접속 → SELECT 권한 부여 (role 존재 시에만)
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'shop_readonly') THEN
    GRANT SELECT ON store_themes TO shop_readonly;
  END IF;
END $$;

-- 쓰기 소유권 → coolsistema (role 존재 시에만)
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'coolsistema') THEN
    ALTER TABLE store_themes OWNER TO coolsistema;
  END IF;
END $$;
```
**신규 마이그레이션은 CHECK 제약 교체만이므로 이 DO 블록 2개는 불필요**(CLAUDE.md·SPEC 이 명시: "기존 테이블 ALTER 라 owner 이전 불필요"). RESEARCH 제안 SQL 그대로 사용:
```sql
BEGIN;

ALTER TABLE store_themes DROP CONSTRAINT chk_store_theme_macro;

ALTER TABLE store_themes ADD CONSTRAINT chk_store_theme_macro
  CHECK (macrostructure IN ('marquee', 'bento', 'doc', 'rails', 'masonry'));

COMMIT;
```
로컬 5432 + 운영 5434 양쪽 `psql ... --single-transaction -v ON_ERROR_STOP=1 -f <file>.sql` 로 적용 후 `\d store_themes` 대조(CLAUDE.md 「DB 마이그레이션 적용 규칙」 섹션 그대로).

---

### 그룹 E — Jest 유닛테스트 (신규 파일, 이 모듈 최초)

**Analog** (`api-ventago/src/app/afip/code-maps.spec.ts:1-47`) — `createTestingModule` 없이 순수 함수를 직접 import 해 테스트하는 관례(DI/mock 불필요, `sanitizeContent`/`sanitizeTokens`/`sanitizeMacrostructure`/`buildThemeResponse` 성격과 정확히 일치):
```typescript
import {
  INVOICE_TYPE,
  IVA,
  decideComprobante,
  // ...
} from './code-maps';

describe('afip code-maps', () => {
  it('C 계열 CbteTipo 코드', () => {
    expect(INVOICE_TYPE.C).toBe(11);
    // ...
  });

  describe('decideComprobante — 발행자 IVA 조건 분기', () => {
    it('Monotributo 발행자는 수신자 무관 항상 C', () => {
      expect(decideComprobante('MONO', { docNro: '20304050609' })).toBe('C');
    });
    // ...
  });
});
```
**적용 방향** — `store-theme.constants.spec.ts`:
```typescript
import {
  sanitizeTokens, sanitizeMacrostructure, sanitizeContent, buildThemeResponse,
} from './store-theme.constants';

describe('store-theme.constants', () => {
  describe('buildThemeResponse — 하위호환(R1 acceptance)', () => {
    it('확장 키 없는 published_tokens 는 현행과 동일 + 확장 키 default 포함', () => {
      const resp = buildThemeResponse(1, 'Studio', 'marquee', {});
      expect(resp.content.sections).toEqual([]); // 또는 default sections
    });
  });
  describe('sanitizeContent — clamp(R1 acceptance)', () => {
    it('sections 9개는 8개로, 텍스트 300자는 200자로, javascript: href 는 null 로 clamp', () => { /* ... */ });
  });
  describe('sanitizeMacrostructure — 5종 확장(R9 acceptance)', () => {
    it("알 수 없는 값('foo')은 marquee 로 강등", () => {
      expect(sanitizeMacrostructure('foo')).toBe('marquee');
    });
    it("rails/masonry 는 그대로 통과", () => {
      expect(sanitizeMacrostructure('rails')).toBe('rails');
    });
  });
});
```
실행: `cd api-ventago && npx jest src/app/shop-public/store-theme.constants --silent`.

---

### 그룹 F — 에디터 아코디언 + 섹션 리스트 편집기 (R3)

**Analog** — `diseno.tsx` 의 기존 state/patch/save/publish 흐름과 인라인 `CSSProperties` 스타일 체계(전체가 이 파일 하나의 관례, MUI 아님·styled-components 아님):

**state 관리 패턴** (`diseno.tsx:49-95`):
```typescript
const [baseTheme, setBaseTheme] = useState('Studio');
const [macro, setMacro] = useState<Macrostructure>('marquee');
const [tokens, setTokens] = useState<StoreThemeTokens>(DEFAULT_TOKENS);
// ...
const patch = useCallback((p: Partial<StoreThemeTokens>) => {
  setTokens((prev) => ({ ...prev, ...p }));
  setState('idle');
}, []);
```
**확장 방법**: `const [content, setContent] = useState<StoreThemeContent>(DEFAULT_CONTENT);` 추가 + `patchContent()` 동일 패턴.

**저장/발행 패턴** (`diseno.tsx:99-123`):
```typescript
const onSave = useCallback(async () => {
  setState('saving');
  try {
    await saveThemeDraft(storeId, token, { baseTheme, macrostructure: macro, tokens });
    setState('saved');
    setMsg('초안이 저장되었습니다 (아직 공개에는 반영 안 됨)');
  } catch (e) {
    setState('error');
    setMsg(`저장 실패: ${(e as Error).message}`);
  }
}, [storeId, token, baseTheme, macro, tokens]);
```
**확장 방법**: `saveThemeDraft(...)` body 에 `content` 필드 추가, `deps` 배열에 `content` 추가. `SaveThemeBody`(`shop-api.ts`)도 동일 확장 필요.

**세그먼트 버튼그룹(택일 UI) 패턴** (`diseno.tsx:263-278`, macrostructure 선택 UI — SectionListEditor 의 표시토글/순서이동 버튼도 이 스타일 재사용):
```typescript
<div style={ui.segs}>
  {MACRO_OPTIONS.map((m) => (
    <button
      key={m.id}
      onClick={() => { setMacro(m.id); setState('idle'); }}
      style={macro === m.id ? ui.segOn : ui.seg}
    >
      {m.label}
    </button>
  ))}
</div>
```
스타일 오브젝트(`ui.seg`/`ui.segOn`, `diseno.tsx:353-355`):
```typescript
seg: { flex: 1, background: '#1e222b', color: '#9aa2b1', border: '1px solid #2a2f3a', padding: '7px 4px', borderRadius: 7, fontSize: 11, cursor: 'pointer' },
segOn: { flex: 1, background: '#6ea8fe', color: '#08121f', border: '1px solid #6ea8fe', padding: '7px 4px', borderRadius: 7, fontSize: 11, cursor: 'pointer', fontWeight: 600 },
```
**아코디언 신설**: 코드베이스에 아코디언 컴포넌트가 없다(0건) — `diseno.tsx` 의 `ui.sec`/`ui.secH`(`263-264`, 섹션 구획 스타일)를 펼침/접힘 가능한 `<details>`/커스텀 토글 state 로 감싸는 방식이 기존 스타일 체계와 가장 잘 맞는다(신규 라이브러리 도입 없이). 승인 목업 `tienda-online-editor-mockup.html`(레포 루트) 이 그룹 명칭/순서의 시각 정본.

**SectionListEditor.tsx** — No Analog(신규 컴포넌트, 파일 자체가 존재하지 않음). ▲▼ 순서이동은 배열 swap(`content.sections`의 index 교체) + 위 세그먼트 버튼 스타일로 조립 — 목업의 리스트 아이템 UI(순서 번호 + 제목 + ▲▼ + 토글 스위치)를 참고.

---

### 그룹 G — 스토어프런트 sections 배열 렌더 (R4)

**Analog** — `index.tsx` 자기 자신의 현재 렌더 구조(현재는 sections 순회가 없고 hero/promo/aistrip 하드코딩 — R4 가 이 구조를 배열 순회로 교체):

**SSR 데이터 페칭 + 테마 주입 패턴** (`index.tsx:38-69, 117-136`):
```typescript
export const getServerSideProps: GetServerSideProps<Props> = async (ctx) => {
  const storeId = Number(ctx.params?.storeId);
  const theme = await getStoreTheme(storeId).catch(() => defaultTheme(storeId));
  if (!theme.enabled) return { notFound: true };
  const [list, categories] = await Promise.all([
    listProducts(storeId, { pageSize: 24 }),
    listCategories(storeId),
  ]);
  return { props: { storeId, initialItems: list.items, categories, theme } };
};

// ...
const wrapStyle = {
  ...theme.cssVars,
  background: 'var(--bg)', color: 'var(--ink)', minHeight: '100vh', fontFamily: 'var(--font-body)',
} as CSSProperties;
```
```tsx
<div style={wrapStyle} data-macro={theme.macrostructure}>
  <Head><title>CoolShop — Tienda online</title></Head>
  <Header categories={categories} q={q} onQ={setQ} activeCat={activeCat} onCat={setActiveCat} />
  <main className="container" style={{ paddingBottom: 40 }}>
    <section style={s.hero}>{/* 하드코딩 히어로 */}</section>
    {/* ... */}
    <section style={gridStyle}>{items.map((p) => <ProductCard key={p.id} product={p} />)}</section>
  </main>
</div>
```
**확장 방법**: `<main>` 내부를 `theme.content.sections.filter(s => s.enabled).map(s => sectionRenderer(s))` 순회로 교체 — 각 `type`(hero/benefits/carousel/duoBanners/newsletter/reels/quiz)별 컴포넌트 분기(`switch`). macrostructure 분기(rails/masonry)는 그룹 그리드 블록 자체를 최상위에서 분기해야 함(RESEARCH 「index.tsx 스토어프런트의 macrostructure 분기 현황」참조 — `gridStyle` 삼항 확장이 아니라 렌더 트리 분기).

**개별 섹션 스타일 원형**:
- Hero — `s.hero`/`s.heroBig`/`s.heroTitle`/`s.heroP`(`index.tsx:210-235`)
- DuoBanners — `s.promo`/`s.promoTitle`/`s.promoP`(`index.tsx:236-263`)
- Benefits/Newsletter — `s.aistrip`/`s.aiTitle`/`s.aiP`(`index.tsx:276-289`)
- Carousel — `s.secHead`/`s.secTitle` + `gridStyle` + `ProductCard.map`(`index.tsx:180-195, 264-275`)

모든 신규 `components/sections/*.tsx` 는 위 스타일 오브젝트 패턴(`Record<string, CSSProperties>` 파일 하단 상수)을 그대로 이어간다 — `ProductCard.tsx:55-74` 도 동일 관례.

---

### 그룹 H — ReelsSection / QuizSection / RailsLayout / MasonryLayout (No Analog — 신규 패턴)

이 4개 컴포넌트는 코드베이스에 직접 analog 가 없다(`IntersectionObserver`/`scroll-snap`/`<video>`/멀티스텝 위저드 grep 전부 0건). RESEARCH.md 의 코드 스케치가 유일한 구현 근거이므로 플래너는 이를 "분석된 코드"가 아니라 **표준 웹 기법 스케치**로 취급해야 한다.

**ReelsSection — 영상 렌더 스켈레톤** (RESEARCH 「reels 영상 렌더 패턴」):
```tsx
<video
  muted
  playsInline
  preload="none"
  poster={minioImageUrl(item.posterFile)}
  onClick={(e) => {
    const v = e.currentTarget;
    document.querySelectorAll('video').forEach((other) => { if (other !== v) other.pause(); });
    v.paused ? v.play() : v.pause();
  }}
>
  <source src={minioImageUrl(item.videoFile)} type="video/mp4" />
</video>
```
`minioImageUrl()` 유틸(`shop-api.ts:37-39`)을 그대로 재사용(영상 파일명도 동일 MinIO 경로 규칙).

**RailsLayout — 가로 스크롤 + lazy load 스켈레톤** (RESEARCH 「rails 렌더 구현 패턴」):
```tsx
function Rail({ title, fetchItems }: { title: string; fetchItems: () => Promise<ShopProduct[]> }) {
  const ref = useRef<HTMLDivElement>(null);
  const [items, setItems] = useState<ShopProduct[] | null>(null);
  useEffect(() => {
    if (!ref.current || items !== null) return;
    const io = new IntersectionObserver((entries) => {
      if (entries[0].isIntersecting) { fetchItems().then(setItems); io.disconnect(); }
    }, { rootMargin: '200px' });
    io.observe(ref.current);
    return () => io.disconnect();
  }, [items, fetchItems]);
  return (
    <section ref={ref}>
      <h2>{title}</h2>
      <div style={{ display: 'flex', gap: 12, overflowX: 'auto', scrollSnapType: 'x mandatory' }}>
        {(items ?? []).map((p) => (
          <div key={p.id} style={{ flex: '0 0 200px', scrollSnapAlign: 'start' }}><ProductCard product={p} /></div>
        ))}
      </div>
    </section>
  );
}
```
데이터 소스는 기존 `listProducts()`(`shop-api.ts:41-59`) 재사용(`newest`/카테고리별) — `bestseller` 만 신규 백엔드 집계 필요(그룹 B 확장 범위 밖, Open Question #2).

**MasonryLayout — CSS columns 스켈레톤**:
```css
.masonry { columns: 2; column-gap: 12px; }
@media (min-width: 900px) { .masonry { columns: 4; } }
.masonry > * { break-inside: avoid; margin-bottom: 12px; display: inline-block; width: 100%; }
```
JS masonry 라이브러리 금지(SPEC 명시) — `next.config.js`/`globals.css` 에 클래스 추가.

**QuizSection — 상태관리는 `diseno.tsx` 의 useState/useCallback 스타일을 행동 패턴으로 재사용**(그룹 F 「state 관리 패턴」 인용 참조), 다만 UI 흐름(배너→질문→결과) 자체는 목업 `tienda-online-quiz-mockup.html` 이 유일 시각 정본. 답변→필터 매핑은 `content.sections[quizIdx].mapping` 을 순회해 기존 `listProducts()` 쿼리 파라미터 객체를 조립 — **신규 API 클라이언트 함수 불필요**, 기존 `listProducts(storeId, params)`(`shop-api.ts:41-59`) 그대로 호출.

---

### 그룹 I — `ProductCard.tsx` 6개 표시 옵션 (R5)

**Analog:** 자기 자신.

**현재 하드코딩 표시 구조** (`ProductCard.tsx:7-53`):
```tsx
export default function ProductCard({ product }: { product: ShopProduct }) {
  const { add, openTryOn } = useShop();
  return (
    <div style={s.card}>
      <div style={s.imgwrap}>
        {product.imageUrl ? (
          <img src={minioImageUrl(product.imageUrl)} alt={product.name} style={s.img} />
        ) : (
          <div style={{ ...s.ph, backgroundImage: placeholderGradient(product.id) }} />
        )}
      </div>
      <div style={s.body}>
        <div style={s.name}>{product.name}</div>
        <div style={s.price}>{money(product.price)}</div>
        <div style={s.cuotas}>{cuotas(product.price)}</div>  {/* 항상 표시 — installments 토글 없음 */}
        <div style={s.acts}>
          <button className="btn btn-gold" style={s.btn} onClick={() => add(product)}>Agregar</button>
          <button className="btn btn-ghost" style={s.btn} onClick={() => openTryOn(product)}>👗 Probar</button>
        </div>
      </div>
    </div>
  );
}
```
**확장 방법**: props 를 `{ product, options?: ProductCardOptions }` 로 확장(`options` 는 `theme.content.productCard` 를 그대로 전달). `discountBadge` = `product.priceOrig != null && product.priceOrig > product.price` 조건부 렌더, `hoverSecondImage` 는 mockup CSS 패턴(`.card:hover .img2{opacity:1}`) 이식 — `product.imageUrls?.[1]` 을 절대위치 오버레이 `<img>` 로 추가. `variantDots` 는 **공개 API 에 데이터 소스가 없음(Open Question #1)** — 플래너가 "no-op + TODO" 로 명시적으로 좁히지 않으면 실행 중 막힘.

**의존 유틸 재사용**: `minioImageUrl()`/`money()`/`cuotas()`/`placeholderGradient()`(`ProductCard.tsx:2-4`) — 신규 섹션 컴포넌트(Hero/Carousel/Reels 등)도 이미지 URL 조립엔 반드시 `minioImageUrl()` 을 재사용해야 한다(직접 문자열 조립 금지 — SSOT 원칙).

---

### 그룹 J — `theme-preset.ts` (프런트 미러) + `shop-api.ts`/`types/shop.ts` (암묵)

**Analog:** 자기 자신. `theme-preset.ts` 는 백엔드 `store-theme.constants.ts` 의 **의도적 복제본**(주석에 명시, `theme-preset.ts:1-2`):
```typescript
// 매장 테마 프리셋 + 토큰→CSS변수 변환 (프론트 미리보기용).
// ★백엔드 store-theme.constants.ts 와 동일 공식 — 미리보기와 발행 결과가 일치해야 함.
```
```typescript
export const MACRO_OPTIONS: { id: Macrostructure; label: string }[] = [
  { id: 'marquee', label: '마퀴 히어로' },
  { id: 'bento', label: '벤토 그리드' },
  { id: 'doc', label: '롱 도큐먼트' },
];
```
**확장 방법**: `MACRO_OPTIONS` 배열에 `rails`/`masonry` 항목 2개 추가(라벨 + discretion 범위인 미니 와이어프레임 아이콘). 이 배열이 바뀌면 `types/shop.ts` 의 `Macrostructure` 유니온도 5종으로 맞춰야 함(현재 `types/shop.ts:52`는 3종).

**`shop-api.ts` 확장 지점**(현재 `types/shop.ts:1-73`/`shop-api.ts:41-59, 82-113`):
- `listProducts()` 파라미터에 `sort`/`showOutOfStock` 추가(그룹 B 컨트롤러 확장과 짝).
- `SaveThemeBody` 에 `content` 필드 추가(그룹 F 와 짝).
- 신규 `uploadThemeAsset(storeId, token, file, kind)` 함수 추가 — `FormData` + `fetch(..., { method: 'POST', body: fd, headers: authHeaders(token) })` 패턴, 기존 `tryOnFromProduct()`(`shop-api.ts:141-153`, `FormData` 업로드의 유일한 기존 예시)를 analog 로 재사용.

```typescript
// Analog: 기존 FormData 업로드 함수 (shop-api.ts:141-153)
export function tryOnFromProduct(
  storeId: number,
  productId: number,
  person: File,
): Promise<TryOnResult> {
  const fd = new FormData();
  fd.append('person', person);
  return req<TryOnResult>(
    `/public/shop/tryon/from-product/${storeId}/${productId}`,
    { method: 'POST', body: fd },
  );
}
```

---

## Shared Patterns

### sanitize 게이트키퍼 (가장 중요 — SSOT)
**Source:** `api-ventago/src/app/shop-public/store-theme.constants.ts:199-246`
**Apply to:** `store-theme-admin.service.ts` 의 `saveDraft()`만 (유일한 쓰기 진입점), 확장 키를 다루는 모든 신규 코드
```typescript
function clamp(n: number, min: number, max: number, fallback: number): number {
  if (typeof n !== 'number' || Number.isNaN(n)) return fallback;
  return Math.min(max, Math.max(min, n));
}
```
`publish()`(`store-theme-admin.service.ts:110-134`)는 재검증 없이 `draft_tokens`→`published_tokens` 복사 — 이 불변조건(=쓰기는 오직 `saveDraft()` 경유)을 테스트/주석으로 못박을 것(SPEC 「주의사항」).

### MinIO 업로드 + 검증
**Source:** `api-ventago/src/common/minio/minio.service.ts:43-52` + `api-ventago/src/app/legacy-import/legacy-import.controller.ts:42-43`
**Apply to:** `store-theme-admin.controller.ts` 신규 `/theme/asset` 라우트
- `FileInterceptor` 는 memoryStorage 고정(`file.buffer` 필요)
- `limits.fileSize` 로 서버측 강제(클라이언트 검증은 우회 가능)
- 확장자 **+** MIME 이중 체크, UUID 파일명(`crypto.randomUUID()`) — 기존 `store.controller.ts` 의 `Date.now()+originalname` 패턴은 grandfather 코드, 신규 엔드포인트 기준 아님

### 편집 인가 (magic-link)
**Source:** `api-ventago/src/app/shop-public/store-theme-edit.guard.ts` (전체)
**Apply to:** 모든 신규 admin 쓰기 라우트(`/theme/draft`, `/theme/asset`) — cross-store 편집 차단이 이미 내장돼 있으므로 신규 라우트도 반드시 `@UseGuards(StoreThemeEditGuard)` 적용

### 읽기/쓰기 DB 경로 분리
**Source:** RESEARCH 「Pitfall 5」
**Apply to:** 전 백엔드 신규 코드
- 읽기(공개 API, bestseller 집계 포함) → `ShopReadonlyDbService.query()` 만
- 쓰기(draft/publish) → `StoreThemeAdminService` 의 `@InjectConnection() Sequelize` 만
- `grep -rn "new Pool(\|new Client(" <변경파일>` 0건이 R8 게이트

### CSS-in-JS 스타일 오브젝트 관례 (tienda-app 전역)
**Source:** `tienda-app/src/components/ProductCard.tsx:55-74`, `tienda-app/src/components/Header.tsx:65-138`, `tienda-app/src/pages/[storeId]/index.tsx:210-291`
**Apply to:** 모든 신규 `components/sections/*.tsx`, `components/macro/*.tsx`, `components/panel/SectionListEditor.tsx`
```typescript
const s: Record<string, CSSProperties> = {
  card: { border: '1px solid var(--line)', borderRadius: 'var(--radius)', /* ... */ },
  // ...
};
```
MUI 없음, styled-components 없음 — 파일 하단 `Record<string, CSSProperties>` 상수 + `var(--*)` CSS 변수(테마 토큰) 참조가 유일한 스타일 관례. 신규 컴포넌트도 이 패턴을 벗어나지 않는다.

### MinIO 이미지 URL 조립
**Source:** `tienda-app/src/services/shop-api.ts:37-39`
**Apply to:** 로고/파비콘/hero/배너/reels 영상·poster 등 모든 신규 이미지·영상 표시
```typescript
export function minioImageUrl(fileName: string): string {
  return `${API_HOST}/minio/${encodeURIComponent(fileName)}`;
}
```
직접 문자열 템플릿 조립 금지 — 항상 이 함수 경유.

### fetch 기반 API 클라이언트 (tienda-app 은 `apiConnector` 아님)
**Source:** `tienda-app/src/services/shop-api.ts:17-34`
**Apply to:** 신규 `uploadThemeAsset()` 등 shop-api.ts 함수 전부
```typescript
async function req<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(`${API_HOST}${path}`, init);
  if (!res.ok) { /* 백엔드 message 추출, 없으면 HTTP 코드 */ throw new Error(message); }
  return res.json() as Promise<T>;
}
```
**주의**: 프로젝트 CLAUDE.md 의 `apiConnector.remove()` 규약은 `ventago-app`(관리자 프론트) 전용 — `tienda-app`(공개 스토어프런트/에디터)은 이 `req()`/`fetch` 패턴을 쓴다. 이 Phase 는 삭제(DELETE) 엔드포인트가 없으므로 해당 규약은 직접 적용 대상 아님(참고만).

### 마이그레이션 SQL 관례
**Source:** `api-ventago/migrations/2026-07-22-store-themes-enabled.sql`, `2026-07-22-store-themes.sql`
**Apply to:** `2026-07-XX-store-themes-macro-rails-masonry.sql`
- 헤더: 날짜 + 목적 1~2줄 한국어 주석
- `BEGIN;` ... `COMMIT;` 트랜잭션 래핑
- role 존재 체크 DO 블록은 **owner/GRANT 변경이 필요할 때만** — 이번 마이그는 순수 CHECK 제약 교체라 불필요(SPEC 이 명시)
- 적용 커맨드는 `--single-transaction -v ON_ERROR_STOP=1` (CLAUDE.md 「DB 마이그레이션 적용 규칙」)

### Jest 순수함수 스펙 관례
**Source:** `api-ventago/src/app/afip/code-maps.spec.ts`
**Apply to:** `store-theme.constants.spec.ts` (이 모듈 첫 스펙 파일)
- `createTestingModule`/DI mock 불필요 — 순수 함수 직접 import
- `describe(파일명)` → `describe(함수명 — 시나리오)` → `it(한국어 시나리오 설명)` 3단 중첩

---

## No Analog Found

| File | Role | Data Flow | Reason |
|---|---|---|---|
| `tienda-app/src/components/sections/ReelsSection.tsx` | component | streaming | 코드베이스에 `<video>`/영상 렌더 컴포넌트 0건 — RESEARCH 코드 스케치(§"reels 영상 렌더 패턴")가 유일 근거, 표준 HTML5 video API 기반 |
| `tienda-app/src/components/sections/QuizSection.tsx` | component | event-driven(위저드) | 멀티스텝 폼/위저드 UI 패턴 0건 — 목업 `tienda-online-quiz-mockup.html` 이 시각 정본, 상태관리만 `diseno.tsx` 패턴 차용 |
| `tienda-app/src/components/macro/RailsLayout.tsx` | component | event-driven(lazy) | `IntersectionObserver`/`scroll-snap` 사용례 0건(grep 검증) — RESEARCH 코드 스케치가 유일 근거 |
| `tienda-app/src/components/macro/MasonryLayout.tsx` | component | transform | CSS `columns` 기반 레이아웃 사용례 0건 — `index.tsx` 의 `gridStyle` 은 flex/grid 밀도 분기일 뿐 구조가 다름 |
| `tienda-app/src/components/panel/SectionListEditor.tsx` | component | CRUD(순서/토글) | 순서 이동(▲▼)+표시 토글 리스트 편집기 컴포넌트가 코드베이스에 없음 — `diseno.tsx` 의 세그먼트 버튼 스타일만 재사용 가능, 구조 자체는 신규 |

이 5개 파일은 PATTERNS.md 상 "role-match" 대신 RESEARCH.md 의 「rails/masonry 렌더 구현 패턴」/「reels 영상 렌더 패턴」/승인 목업 파일(`tienda-online-rails-masonry-reels-mockup.html`, `tienda-online-quiz-mockup.html`, `tienda-online-editor-mockup.html`)을 1차 근거로 계획해야 한다.

## Metadata

**Analog search scope:** `api-ventago/src/app/shop-public/`, `api-ventago/src/app/store/`, `api-ventago/src/app/legacy-import/`, `api-ventago/src/common/minio/`, `api-ventago/src/app/afip/` (spec 패턴), `api-ventago/migrations/`, `tienda-app/src/pages/[storeId]/`, `tienda-app/src/components/`, `tienda-app/src/lib/`, `tienda-app/src/services/`, `tienda-app/src/types/`
**Files scanned:** 약 20개 직접 Read + `find`/`grep` 스캔(`*.spec.ts` 76개, `migrations/*.sql` 최신 10개, `IntersectionObserver`/`scroll-snap`/`<video>` grep 0건 확인은 RESEARCH.md 기존 검증 재확인)
**Pattern extraction date:** 2026-07-23
