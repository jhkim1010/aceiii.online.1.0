import type {
  CheckoutItemInput,
  CheckoutResult,
  ShopCategory,
  ShopListResult,
  ShopProduct,
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
