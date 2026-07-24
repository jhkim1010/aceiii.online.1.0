// 매장 테마 프리셋 + 토큰→CSS변수 변환 (프론트 미리보기용).
// ★백엔드 store-theme.constants.ts 와 동일 공식 — 미리보기와 발행 결과가 일치해야 함.

import type {
  FontPair,
  Macrostructure,
  PaperBand,
  SectionType,
  StoreThemeContent,
  StoreThemeTokens,
} from '@/types/shop';

export interface ThemePreset {
  id: string;
  genre: 'editorial' | 'modern-minimal' | 'atmospheric' | 'playful';
  tokens: StoreThemeTokens;
}

// hallmark 대표 프리셋 12
export const THEME_PRESETS: ThemePreset[] = [
  { id: 'Specimen', genre: 'editorial', tokens: { accentHue: 12, sat: 70, paperBand: 'light', fontPair: 'serif', weight: 800, radius: 2 } },
  { id: 'Newsprint', genre: 'editorial', tokens: { accentHue: 30, sat: 65, paperBand: 'light', fontPair: 'serif', weight: 700, radius: 0 } },
  { id: 'Almanac', genre: 'editorial', tokens: { accentHue: 145, sat: 55, paperBand: 'mid', fontPair: 'serif', weight: 700, radius: 4 } },
  { id: 'Editorial', genre: 'editorial', tokens: { accentHue: 352, sat: 68, paperBand: 'light', fontPair: 'serif', weight: 800, radius: 2 } },
  { id: 'Studio', genre: 'modern-minimal', tokens: { accentHue: 210, sat: 70, paperBand: 'light', fontPair: 'sans', weight: 600, radius: 12 } },
  { id: 'Quiet', genre: 'modern-minimal', tokens: { accentHue: 0, sat: 12, paperBand: 'light', fontPair: 'sans', weight: 500, radius: 16 } },
  { id: 'Atelier', genre: 'modern-minimal', tokens: { accentHue: 35, sat: 60, paperBand: 'mid', fontPair: 'sans', weight: 600, radius: 10 } },
  { id: 'Linen', genre: 'modern-minimal', tokens: { accentHue: 150, sat: 45, paperBand: 'mid', fontPair: 'sans', weight: 600, radius: 14 } },
  { id: 'Midnight', genre: 'atmospheric', tokens: { accentHue: 250, sat: 60, paperBand: 'dark', fontPair: 'sans', weight: 600, radius: 12 } },
  { id: 'Aurora', genre: 'atmospheric', tokens: { accentHue: 280, sat: 65, paperBand: 'dark', fontPair: 'sans', weight: 700, radius: 16 } },
  { id: 'Riso', genre: 'playful', tokens: { accentHue: 20, sat: 80, paperBand: 'light', fontPair: 'condensed', weight: 800, radius: 6 } },
  { id: 'Bloom', genre: 'playful', tokens: { accentHue: 330, sat: 72, paperBand: 'light', fontPair: 'condensed', weight: 800, radius: 20 } },
];

// 에디터(표면 A) 프리셋 그룹 라벨 — 사용자 노출 카피는 스페인어로 통일한다
// (61-08 Rule 1: 아코디언 그룹 안에 노출되면서 발견된 한국어 잔여 카피).
export const GENRE_LABELS: Record<ThemePreset['genre'], string> = {
  editorial: 'Editorial',
  'modern-minimal': 'Moderno minimalista',
  atmospheric: 'Atmosférico',
  playful: 'Lúdico',
};

const PAPER_PALETTE: Record<
  PaperBand,
  { bg: string; soft: string; ink: string; muted: string; line: string; card: string }
> = {
  light: { bg: '#f8f7f4', soft: '#eeece7', ink: '#16181d', muted: '#6b6b76', line: 'rgba(0,0,0,0.09)', card: '#ffffff' },
  mid: { bg: '#e7e2d8', soft: '#dcd6c8', ink: '#20211c', muted: '#5c5b52', line: 'rgba(0,0,0,0.12)', card: '#f4f1ea' },
  dark: { bg: '#14161c', soft: '#1c1f27', ink: '#eceef2', muted: '#9aa2b1', line: 'rgba(255,255,255,0.10)', card: '#1c1f27' },
};

const FONT_PAIRS: Record<FontPair, { display: string; body: string }> = {
  serif: { display: "Georgia, 'Times New Roman', serif", body: 'system-ui, -apple-system, sans-serif' },
  sans: { display: "system-ui, -apple-system, 'Segoe UI', sans-serif", body: 'system-ui, -apple-system, sans-serif' },
  mono: { display: "'Courier New', ui-monospace, monospace", body: 'system-ui, -apple-system, sans-serif' },
  condensed: { display: "'Arial Narrow', 'Helvetica Neue', sans-serif", body: 'system-ui, -apple-system, sans-serif' },
};

function clampPct(n: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, n));
}

// 토큰 → CSS 변수 맵 (백엔드 tokensToCssVars 와 동일)
export function tokensToCssVars(tokens: StoreThemeTokens): Record<string, string> {
  const { accentHue: h, sat, paperBand, fontPair, weight, radius } = tokens;
  const pal = PAPER_PALETTE[paperBand];
  const fonts = FONT_PAIRS[fontPair];
  const isDark = paperBand === 'dark';

  const accentL = isDark ? 66 : 44;
  const accent = `hsl(${h}, ${sat}%, ${accentL}%)`;
  const accentStrong = `hsl(${h}, ${sat}%, ${isDark ? 72 : 34}%)`;
  const navy = `hsl(${h}, ${Math.min(40, sat)}%, 15%)`;
  const heroFrom = `hsl(${h}, ${clampPct(sat, 20, 50)}%, 18%)`;
  const heroTo = `hsl(${(h + 28) % 360}, ${clampPct(sat, 30, 60)}%, 32%)`;
  const promoBg = `hsl(${h}, ${Math.min(sat, 60)}%, ${isDark ? 16 : 94}%)`;
  const promoLine = `hsl(${h}, ${Math.min(sat, 50)}%, ${isDark ? 26 : 84}%)`;

  return {
    '--bg': pal.bg,
    '--soft': pal.soft,
    '--ink': pal.ink,
    '--muted': pal.muted,
    '--line': pal.line,
    '--card': pal.card,
    '--gold': accent,
    '--gold-d': accentStrong,
    '--navy': navy,
    '--green': '#1d9e75',
    '--on-navy': '#ffffff',
    '--font-display': fonts.display,
    '--font-body': fonts.body,
    '--disp-weight': String(weight),
    '--radius': `${radius}px`,
    '--hero-from': heroFrom,
    '--hero-to': heroTo,
    '--promo-bg': promoBg,
    '--promo-line': promoLine,
  };
}

export const DEFAULT_TOKENS: StoreThemeTokens = {
  accentHue: 210,
  sat: 70,
  paperBand: 'light',
  fontPair: 'sans',
  weight: 600,
  radius: 12,
};

export interface MacroOption {
  id: Macrostructure;
  label: string; // 카드 이름
  tag: 'exist' | 'new'; // YA EXISTE(초록) | NUEVO(gold)
  desc: string; // 설명 1줄
  fit: string; // 적합 매장 1줄
}

export const MACRO_OPTIONS: MacroOption[] = [
  {
    id: 'marquee',
    label: 'Marquee',
    tag: 'exist',
    desc: 'Hero grande arriba + grilla de productos abajo. El clásico.',
    fit: 'Ideal si tenés una campaña o una foto fuerte por temporada.',
  },
  {
    id: 'bento',
    label: 'Bento',
    tag: 'exist',
    desc: 'Mosaico de baldosas de distinto tamaño. Cada baldosa es una categoría o un destacado.',
    fit: 'Ideal si vendés varias categorías bien distintas y querés que se vean todas de una.',
  },
  {
    id: 'rails',
    label: 'Rails',
    tag: 'new',
    desc: 'Estantes horizontales tipo Netflix. Cada fila es una selección con scroll lateral.',
    fit: 'Ideal si tenés mucho SKU y clientes que vuelven seguido: se recorre rapidísimo en el celular.',
  },
  {
    id: 'masonry',
    label: 'Masonry',
    tag: 'new',
    desc: 'Grilla irregular tipo Pinterest: cada foto conserva su alto real.',
    fit: 'Ideal si tus fotos son verticales y de producción propia. Se navega mirando, no leyendo.',
  },
];

// 구조별로 렌더에서 생략되는 섹션(값은 JSONB 에 보존, 렌더만 skip). marquee=전부 가능.
// index.tsx(Plan 61-09)와 SectionGatingChips.tsx(Plan 61-10)가 둘 다 여기서 import 한다
// (중복 정의 금지 — 에디터 안내와 실제 렌더 게이팅이 갈라지면 안 됨).
export const GATED_BY_MACRO: Record<Macrostructure, SectionType[]> = {
  marquee: [],
  bento: ['hero', 'duoBanners'],
  rails: ['carousel'],
  masonry: ['benefits', 'duoBanners'],
};

// 콘텐츠 확장 키 기본값 — 백엔드 store-theme.constants.ts 의 DEFAULT_CONTENT 와
// 문자 단위로 동일한 값. ThemeContentContext 의 폴백으로 쓰인다.
export const DEFAULT_CONTENT: StoreThemeContent = {
  brand: { displayName: '', logoFile: null, faviconFile: null },
  announce: {
    enabled: true,
    text: 'Envío gratis desde $50.000 · 3 cuotas sin interés · probador virtual con IA',
    href: null,
  },
  sections: [
    {
      type: 'hero',
      enabled: true,
      title: 'Nueva temporada otoño 2026',
      subtitle: 'Descubrí las últimas tendencias. Hasta 30% en seleccionados.',
      cta: 'Ver colección',
      images: [],
    },
    {
      type: 'benefits',
      enabled: true,
      items: [{ icon: '👗', text: 'Probador virtual con IA' }],
    },
    {
      type: 'carousel',
      enabled: true,
      title: 'Destacados',
      source: 'newest',
      categoryId: null,
    },
    { type: 'duoBanners', enabled: false, banners: [] },
    { type: 'newsletter', enabled: false, title: '' },
    { type: 'reels', enabled: false, title: '', items: [] },
    {
      type: 'quiz',
      enabled: false,
      banner: { title: '', subtitle: '' },
      questions: [],
      mapping: {},
    },
  ],
  contact: {
    whatsapp: null,
    instagram: null,
    facebook: null,
    footerText: null,
  },
  productCard: {
    discountBadge: true,
    installments: true,
    quickAdd: false,
    hoverSecondImage: true,
    lastUnitsBadge: false,
    variantDots: false,
  },
  catalog: {
    defaultSort: 'newest',
    pageSize: 24,
    showOutOfStock: true,
    filters: { size: true, color: true, price: true },
  },
  trust: {
    paymentLogos: [],
    shippingLogos: [],
    protectedBadge: false,
    policyLinks: [],
  },
  marketing: {
    popup: { enabled: false, title: '', coupon: null },
    seoTitle: null,
    seoDescription: null,
    pixelId: null,
  },
  macroSettings: {
    rails: {
      shelves: [
        { title: 'Novedades', source: 'newest', categoryId: null, limit: 10 },
        {
          title: 'Más vendidos',
          source: 'bestseller',
          categoryId: null,
          limit: 10,
        },
      ],
      showArrows: true,
      lazyRows: true,
    },
    masonry: {
      desktopCols: 4,
      mobileCols: 2,
      firstLoad: 24,
      keepRatio: true,
      stickyFilter: true,
      showOverlayInfo: false,
    },
  },
};
