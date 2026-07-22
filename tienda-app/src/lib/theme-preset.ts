// 매장 테마 프리셋 + 토큰→CSS변수 변환 (프론트 미리보기용).
// ★백엔드 store-theme.constants.ts 와 동일 공식 — 미리보기와 발행 결과가 일치해야 함.

import type {
  FontPair,
  Macrostructure,
  PaperBand,
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

export const GENRE_LABELS: Record<ThemePreset['genre'], string> = {
  editorial: '에디토리얼',
  'modern-minimal': '모던 미니멀',
  atmospheric: '분위기',
  playful: '플레이풀',
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

export const MACRO_OPTIONS: { id: Macrostructure; label: string }[] = [
  { id: 'marquee', label: '마퀴 히어로' },
  { id: 'bento', label: '벤토 그리드' },
  { id: 'doc', label: '롱 도큐먼트' },
];
