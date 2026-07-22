import type {
  CheckoutItemInput,
  CheckoutResult,
  ShopCategory,
  ShopListResult,
  ShopProduct,
  StoreTheme,
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
    page?: number;
    pageSize?: number;
  } = {},
): Promise<ShopListResult> {
  const qs = new URLSearchParams();
  if (params.q) qs.set('q', params.q);
  if (params.globalCategoryId) {
    qs.set('globalCategoryId', String(params.globalCategoryId));
  }
  qs.set('page', String(params.page ?? 1));
  qs.set('pageSize', String(params.pageSize ?? 24));

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

// 매장 발행 테마 조회 (공개) — 홈페이지 색/폰트/레이아웃 CSS 변수 맵 포함
export function getStoreTheme(storeId: number): Promise<StoreTheme> {
  return req<StoreTheme>(`/public/shop/${storeId}/theme`);
}

// ---- 소유자 편집(인증: 편집 토큰 Bearer) ----

// 편집 저장 바디
export interface SaveThemeBody {
  baseTheme: string;
  macrostructure: StoreTheme['macrostructure'];
  tokens: StoreThemeTokens;
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
  });
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
  });
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
