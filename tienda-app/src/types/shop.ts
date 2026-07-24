// 백엔드 공개 API 응답 타입 (api-ventago/src/app/shop-public 의 DTO 와 일치)
// ★ 백엔드 store-theme.constants.ts 의 의도적 미러 — 값이 어긋나면 미리보기≠발행결과.

export interface ShopProduct {
  id: number;
  name: string;
  slug: string | null;
  description: string | null;
  longDescription: string | null;
  price: number;
  priceOrig: number | null;
  stock: number | null;
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

// 매장 홈페이지 테마 (api-ventago store-theme.constants 와 일치)
export type PaperBand = 'light' | 'mid' | 'dark';
export type FontPair = 'serif' | 'sans' | 'mono' | 'condensed';
export type Macrostructure = 'marquee' | 'bento' | 'rails' | 'masonry';
export type CatalogSort = 'newest' | 'price_asc' | 'price_desc' | 'bestseller';

export interface StoreThemeTokens {
  accentHue: number;
  sat: number;
  paperBand: PaperBand;
  fontPair: FontPair;
  weight: number;
  radius: number;
}

// ── 콘텐츠 확장 스키마 (Phase 61) — store-theme.constants.ts 미러 ──────────
export type SectionType =
  | 'hero'
  | 'benefits'
  | 'carousel'
  | 'duoBanners'
  | 'newsletter'
  | 'reels'
  | 'quiz';
export type CarouselSource = 'newest' | 'bestseller' | 'category';

export interface HeroSection {
  type: 'hero';
  enabled: boolean;
  title: string;
  subtitle: string;
  cta: string;
  images: string[];
}
export interface BenefitsSection {
  type: 'benefits';
  enabled: boolean;
  items: { icon: string; text: string }[];
}
export interface CarouselSection {
  type: 'carousel';
  enabled: boolean;
  title: string;
  source: CarouselSource;
  categoryId: number | null;
}
export interface DuoBannersSection {
  type: 'duoBanners';
  enabled: boolean;
  banners: {
    image: string | null;
    title: string;
    subtitle: string;
    href: string | null;
  }[];
}
export interface NewsletterSection {
  type: 'newsletter';
  enabled: boolean;
  title: string;
}
export interface ReelsSection {
  type: 'reels';
  enabled: boolean;
  title: string;
  items: {
    videoFile: string;
    posterFile: string;
    productId: number | null;
    durationLabel: string;
  }[];
}
export interface QuizQuestionOption {
  value: string;
  label: string;
  sub: string;
  emoji: string;
}
export interface QuizQuestion {
  key: string;
  text: string;
  options: QuizQuestionOption[];
}
export interface QuizSection {
  type: 'quiz';
  enabled: boolean;
  banner: { title: string; subtitle: string };
  questions: QuizQuestion[];
  mapping: Record<string, string>;
}

export type SectionConfig =
  | HeroSection
  | BenefitsSection
  | CarouselSection
  | DuoBannersSection
  | NewsletterSection
  | ReelsSection
  | QuizSection;

// ── macrostructure 구조별 설정 (Plan 61-04) — rails/masonry 만 정의 ────────
export interface RailShelf {
  title: string;
  source: CarouselSource;
  categoryId: number | null;
  limit: number; // 4~20
}

export interface MacroSettings {
  rails: { shelves: RailShelf[]; showArrows: boolean; lazyRows: boolean };
  masonry: {
    desktopCols: 3 | 4 | 5;
    mobileCols: 1 | 2;
    firstLoad: number; // 12~48, 4의 배수
    keepRatio: boolean;
    stickyFilter: boolean;
    showOverlayInfo: boolean;
  };
}

export interface StoreThemeContent {
  brand: {
    displayName: string;
    logoFile: string | null;
    faviconFile: string | null;
  };
  announce: { enabled: boolean; text: string; href: string | null };
  sections: SectionConfig[];
  contact: {
    whatsapp: string | null;
    instagram: string | null;
    facebook: string | null;
    footerText: string | null;
  };
  productCard: {
    discountBadge: boolean;
    installments: boolean;
    quickAdd: boolean;
    hoverSecondImage: boolean;
    lastUnitsBadge: boolean;
    variantDots: boolean;
  };
  catalog: {
    defaultSort: CatalogSort;
    pageSize: number;
    showOutOfStock: boolean;
    filters: { size: boolean; color: boolean; price: boolean };
  };
  trust: {
    paymentLogos: string[];
    shippingLogos: string[];
    protectedBadge: boolean;
    policyLinks: { label: string; href: string }[];
  };
  marketing: {
    popup: { enabled: boolean; title: string; coupon: string | null };
    seoTitle: string | null;
    seoDescription: string | null;
    pixelId: string | null;
  };
  macroSettings: MacroSettings;
}

export interface StoreTheme {
  storeId: number;
  baseTheme: string;
  macrostructure: Macrostructure;
  tokens: StoreThemeTokens;
  // 최상위 래퍼에 그대로 주입할 CSS 변수 맵 (예: { '--gold': 'hsl(...)', ... })
  cssVars: Record<string, string>;
  // 공개몰(스토어프론트) 활성 여부 — false 면 해당 매장 공개몰 미노출
  enabled: boolean;
  content: StoreThemeContent;
}
