// 백엔드 공개 API 응답 타입 (api-ventago/src/app/shop-public 의 DTO 와 일치)

export interface ShopProduct {
  id: number;
  name: string;
  slug: string | null;
  description: string | null;
  longDescription: string | null;
  price: number;
  imageUrl: string | null;
  imageUrls: string[] | null;
  gender: string | null;
  material: string | null;
  categoryId: number | null;
}

export interface ShopListResult {
  items: ShopProduct[];
  total: number;
  page: number;
  pageSize: number;
}

export interface ShopCategory {
  id: number;
  name: string;
}

export interface CheckoutItemInput {
  productId: number;
  quantity: number;
}

export interface CheckoutResult {
  orderId: number;
  orderNumber: number;
  total: number;
  initPoint?: string;
  isSandbox?: boolean;
}

export interface TryOnResult {
  provider: string;
  isStub: boolean;
  resultImageDataUrl: string;
  message?: string;
}
