import { DEFAULT_CONTENT } from '@/lib/theme-preset';
import type {
  CatalogSort,
  CheckoutItemInput,
  CheckoutResult,
  ShopCategory,
  ShopListResult,
  ShopProduct,
  StoreTheme,
  StoreThemeContent,
  StoreThemeTokens,
  TryOnResult,
} from '@/types/shop';

// 공개 API 베이스 — 브라우저/SSR 공통. env 미설정 시 dev 기본값.
export const API_HOST =
  process.env.NEXT_PUBLIC_API_HOST || 'http://localhost:5002/api';

// 공개 API 호출 래퍼 — 에러 메시지를 백엔드 응답에서 추출(없으면 HTTP 코드)
async function req<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(`${API_HOST}${path}`, init);

  if (!res.ok) {
    let message = `HTTP ${res.status}`;
    try {
      const body = (await res.json()) as { message?: unknown };
      if (typeof body?.message === 'string') {
        message = body.message;
      }
    } catch {
      // JSON 파싱 실패는 무시하고 HTTP 코드 메시지 유지
    }
    throw new Error(message);
  }

  return res.json() as Promise<T>;
}

// 상품 이미지(MinIO 파일명)를 표시용 URL 로 변환
export function minioImageUrl(fileName: string): string {
  return `${API_HOST}/minio/${encodeURIComponent(fileName)}`;
}

export function listProducts(
  storeId: number,
  params: {
    q?: string;
    globalCategoryId?: number;
    categoryId?: number;
    gender?: string;
    page?: number;
    pageSize?: number;
    sort?: CatalogSort;
    showOutOfStock?: boolean;
    minPrice?: number;
    maxPrice?: number;
  } = {},
): Promise<ShopListResult> {
  const qs = new URLSearchParams();
  if (params.q) qs.set('q', params.q);
  if (params.globalCategoryId) {
    qs.set('globalCategoryId', String(params.globalCategoryId));
  }
  if (params.categoryId) qs.set('categoryId', String(params.categoryId));
  // gender — 백엔드 shop-catalog.controller.ts 가 이미 지원하는 기존 쿼리 파라미터
  // (Plan 61-14 quiz 매핑 'gender' 대상용 — 신규 엔드포인트 아님).
  if (params.gender) qs.set('gender', params.gender);
  qs.set('page', String(params.page ?? 1));
  qs.set('pageSize', String(params.pageSize ?? 24));
  if (params.sort) qs.set('sort', params.sort);
  // showOutOfStock=true 는 기본값이라 안 보냄 — 캐시 키 파편화 방지
  if (params.showOutOfStock === false) qs.set('showOutOfStock', 'false');
  if (params.minPrice != null) qs.set('minPrice', String(params.minPrice));
  if (params.maxPrice != null) qs.set('maxPrice', String(params.maxPrice));

  return req<ShopListResult>(`/public/shop/${storeId}/products?${qs.toString()}`);
}

export function getProduct(
  storeId: number,
  slug: string,
): Promise<ShopProduct> {
  return req<ShopProduct>(
    `/public/shop/${storeId}/products/${encodeURIComponent(slug)}`,
  );
}

export function listCategories(storeId: number): Promise<ShopCategory[]> {
  return req<ShopCategory[]>(`/public/shop/${storeId}/categories`);
}

// 구버전/오류 응답에 content 가 누락돼도 크래시하지 않도록 기본값을 채운다
// (T-61-25 — 공개몰은 어떤 경우에도 렌더되어야 함).
function withContentFallback(t: StoreTheme): StoreTheme {
  return { ...t, content: t.content ?? DEFAULT_CONTENT };
}

// 매장 발행 테마 조회 (공개) — 홈페이지 색/폰트/레이아웃 CSS 변수 맵 포함
export function getStoreTheme(storeId: number): Promise<StoreTheme> {
  return req<StoreTheme>(`/public/shop/${storeId}/theme`).then(
    withContentFallback,
  );
}

// ---- 소유자 편집(인증: 편집 토큰 Bearer) ----

// 편집 저장 바디
export interface SaveThemeBody {
  baseTheme: string;
  macrostructure: StoreTheme['macrostructure'];
  tokens: StoreThemeTokens;
  content: StoreThemeContent;
}

function authHeaders(token: string): HeadersInit {
  return { Authorization: `Bearer ${token}` };
}

// 편집 초안 조회
export function getThemeDraft(
  storeId: number,
  token: string,
): Promise<StoreTheme> {
  return req<StoreTheme>(`/shop/${storeId}/theme/draft`, {
    headers: authHeaders(token),
  }).then(withContentFallback);
}

// 초안 저장(발행 전, 공개 미반영)
export function saveThemeDraft(
  storeId: number,
  token: string,
  body: SaveThemeBody,
): Promise<StoreTheme> {
  return req<StoreTheme>(`/shop/${storeId}/theme/draft`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json', ...authHeaders(token) },
    body: JSON.stringify(body),
  }).then(withContentFallback);
}

// 테마 에셋 업로드 (편집 토큰 필요). 응답의 fileName 만 JSONB 에 저장한다.
export type ThemeAssetKind =
  | 'logo'
  | 'favicon'
  | 'hero'
  | 'banner'
  | 'payment'
  | 'shipping'
  | 'reelVideo'
  | 'reelPoster';

export function uploadThemeAsset(
  storeId: number,
  token: string,
  file: File,
  kind: ThemeAssetKind,
): Promise<{ fileName: string }> {
  const fd = new FormData();
  fd.append('file', file);

  // 주의: Content-Type 을 직접 설정하지 않는다 — FormData 는 브라우저가
  // boundary 를 포함해 자동 설정해야 한다(수동 설정 시 multipart 파싱 실패).
  return req<{ fileName: string }>(
    `/shop/${storeId}/theme/asset?kind=${encodeURIComponent(kind)}`,
    { method: 'POST', headers: authHeaders(token), body: fd },
  );
}

// 발행(공개 반영)
export function publishTheme(
  storeId: number,
  token: string,
): Promise<{ published: boolean }> {
  return req<{ published: boolean }>(`/shop/${storeId}/theme/publish`, {
    method: 'POST',
    headers: authHeaders(token),
  });
}

export function checkout(
  storeId: number,
  body: {
    clientName?: string;
    clientEmail?: string;
    items: CheckoutItemInput[];
  },
): Promise<CheckoutResult> {
  return req<CheckoutResult>(`/public/shop/${storeId}/checkout`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
}

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
