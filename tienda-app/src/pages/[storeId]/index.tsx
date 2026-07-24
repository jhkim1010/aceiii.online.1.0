import { useEffect, useRef, useState } from 'react';
import type { CSSProperties } from 'react';
import Head from 'next/head';
import Script from 'next/script';
import type { GetServerSideProps } from 'next';
import Footer from '@/components/Footer';
import Header from '@/components/Header';
import MarketingPopup from '@/components/MarketingPopup';
import WhatsAppFloat from '@/components/WhatsAppFloat';
import MasonryLayout from '@/components/macro/MasonryLayout';
import RailsLayout from '@/components/macro/RailsLayout';
import SectionRenderer from '@/components/sections/SectionRenderer';
import { ThemeContentProvider } from '@/context/ThemeContentContext';
import { useShop } from '@/context/ShopContext';
import { money } from '@/lib/format';
import { DEFAULT_CONTENT, GATED_BY_MACRO } from '@/lib/theme-preset';
import { getStoreTheme, listCategories, listProducts, minioImageUrl } from '@/services/shop-api';
import type { HeroSection, ShopCategory, ShopProduct, StoreTheme } from '@/types/shop';

interface Props {
  storeId: number;
  initialItems: ShopProduct[];
  categories: ShopCategory[];
  theme: StoreTheme;
  error?: string;
}

// 테마 조회 실패 시 폴백 — cssVars 비움(=globals.css :root 기본값 유지). 몰은 절대 깨지지 않는다.
function defaultTheme(storeId: number): StoreTheme {
  return {
    storeId,
    baseTheme: 'Studio',
    macrostructure: 'marquee',
    tokens: {
      accentHue: 210,
      sat: 70,
      paperBand: 'light',
      fontPair: 'sans',
      weight: 600,
      radius: 10,
    },
    cssVars: {},
    enabled: true,
    content: DEFAULT_CONTENT,
  };
}

export const getServerSideProps: GetServerSideProps<Props> = async (ctx) => {
  const storeId = Number(ctx.params?.storeId);
  if (!storeId || Number.isNaN(storeId)) {
    return { notFound: true };
  }

  // 공개몰 활성 여부 먼저 확인 — 비활성(admin 이 끔)이면 공개몰 미노출(404).
  // 조회 실패 시엔 기본 활성으로 폴백해 일시 오류가 공개몰을 내리지 않게 한다.
  const theme = await getStoreTheme(storeId).catch(() => defaultTheme(storeId));
  if (!theme.enabled) {
    return { notFound: true };
  }

  try {
    // catalog 토큰(정렬/페이지/품절 표시)은 이미 위에서 조회된 theme 을 그대로 따른다 —
    // SSR 초기 목록과 클라이언트 재조회가 다른 기본값을 쓰면 첫 화면이 깜빡인다.
    const [list, categories] = await Promise.all([
      listProducts(storeId, {
        pageSize: theme.content.catalog.pageSize,
        sort: theme.content.catalog.defaultSort,
        showOutOfStock: theme.content.catalog.showOutOfStock,
      }),
      listCategories(storeId),
    ]);

    return { props: { storeId, initialItems: list.items, categories, theme } };
  } catch (e) {
    return {
      props: {
        storeId,
        initialItems: [],
        categories: [],
        theme,
        error: (e as Error).message,
      },
    };
  }
};

export default function CatalogPage({
  storeId,
  initialItems,
  categories,
  theme,
  error,
}: Props) {
  const { setStoreId } = useShop();
  const [items, setItems] = useState<ShopProduct[]>(initialItems);
  const [activeCat, setActiveCat] = useState<number | null>(null);
  const [q, setQ] = useState('');
  // R6 filters.price 실구현 — 적용된 가격 구간(minPrice/maxPrice 로 listProducts 에 전달).
  // filters.color/filters.size 는 no-op(아래 렌더 지점 주석 참조) — 여기 state 를 두지 않는다.
  const [minP, setMinP] = useState<number | null>(null);
  const [maxP, setMaxP] = useState<number | null>(null);
  const [minDraft, setMinDraft] = useState('');
  const [maxDraft, setMaxDraft] = useState('');
  const first = useRef(true);

  // 장바구니/체크아웃이 알도록 현재 매장 등록
  useEffect(() => {
    setStoreId(storeId);
  }, [storeId, setStoreId]);

  // 필터/검색 변경 시 클라이언트 재조회 (초기는 SSR). 각 섹션/레이아웃 컴포넌트가 자체
  // 로딩 표시를 갖고 있으므로(Carousel/MasonryLayout) 여기서는 별도 loading 상태를 두지 않는다.
  useEffect(() => {
    if (first.current) {
      first.current = false;

      return;
    }

    const t = setTimeout(async () => {
      try {
        const res = await listProducts(storeId, {
          q: q.trim() || undefined,
          globalCategoryId: activeCat ?? undefined,
          pageSize: theme.content.catalog.pageSize,
          sort: theme.content.catalog.defaultSort,
          showOutOfStock: theme.content.catalog.showOutOfStock,
          minPrice: minP ?? undefined,
          maxPrice: maxP ?? undefined,
        });
        setItems(res.items);
      } catch {
        setItems([]);
      }
    }, 300);

    return () => clearTimeout(t);
  }, [storeId, activeCat, q, minP, maxP, theme.content.catalog]);

  // 매장 테마를 최상위 래퍼에 CSS 변수로 주입(SSR 무플리커). data-macro 로 레이아웃 분기.
  const wrapStyle = {
    ...theme.cssVars,
    background: 'var(--bg)',
    color: 'var(--ink)',
    minHeight: '100vh',
    fontFamily: 'var(--font-body)',
  } as CSSProperties;

  // 구조에 맞지 않는 섹션은 렌더만 생략한다(값은 JSONB 에 그대로 보존 — 구조를 되돌리면 복귀).
  // 게이팅 규칙은 lib/theme-preset.ts 단일 소유지에서 import 한다 — 로컬 재정의 금지
  // (에디터 안내(Plan 61-10)와 실제 렌더 게이팅이 갈라지지 않게).
  const gated = GATED_BY_MACRO[theme.macrostructure] ?? [];
  const visibleSections = theme.content.sections.filter((sec) => !gated.includes(sec.type));
  const heroSection = visibleSections.find((sec) => sec.type === 'hero') as
    | HeroSection
    | undefined;

  return (
    <ThemeContentProvider content={theme.content}>
      <div style={wrapStyle} data-macro={theme.macrostructure}>
        <Head>
          <title>{theme.content.marketing.seoTitle || 'CoolShop — Tienda online'}</title>
          <meta
            name="description"
            content={
              theme.content.marketing.seoDescription ||
              'CoolShop — indumentaria online con probador virtual con IA.'
            }
          />
          {theme.content.brand.faviconFile ? (
            <link rel="icon" href={minioImageUrl(theme.content.brand.faviconFile)} />
          ) : null}
        </Head>

        <Header
          categories={categories}
          q={q}
          onQ={setQ}
          activeCat={activeCat}
          onCat={setActiveCat}
        />

        {/* macrostructure 는 그리드 밀도가 아니라 렌더 구조 자체가 다르므로(rails=선반이 hero/carousel
            흡수, masonry=상품 영역 전체 대체) gridStyle 삼항이 아니라 최상위 분기로 구현한다. */}
        <main className="container" style={{ paddingBottom: 40 }}>
          {error ? <p style={s.muted}>Error: {error}</p> : null}

          {/* R6 filters.price 실구현 — 토글 ON 일 때만 가격 구간 필터 UI 노출(OFF 면 완전히 숨김).
              filters.color/filters.size 는 이 아래에 렌더하지 않는다.
              TODO(Phase 61 이후): color/size 필터 UI 는 공개 API 에 variant 색상/사이즈 집계가 없어 미구현(R5 variantDots 와 동일 제약). 토글 값은 저장되나 렌더 대상 없음 — 가짜 필터 금지. price 필터만 실구현. */}
          {theme.content.catalog.filters.price ? (
            <div style={s.priceFilter}>
              <input
                type="number"
                inputMode="numeric"
                placeholder="Precio mín."
                value={minDraft}
                onChange={(e) => setMinDraft(e.target.value)}
                style={s.priceInput}
              />
              <span style={s.priceSep}>—</span>
              <input
                type="number"
                inputMode="numeric"
                placeholder="Precio máx."
                value={maxDraft}
                onChange={(e) => setMaxDraft(e.target.value)}
                style={s.priceInput}
              />
              <button
                type="button"
                style={s.priceApply}
                onClick={() => {
                  setMinP(minDraft.trim() ? Number(minDraft) : null);
                  setMaxP(maxDraft.trim() ? Number(maxDraft) : null);
                }}
              >
                Aplicar
              </button>
              {minP != null || maxP != null ? (
                <button
                  type="button"
                  style={s.priceChip}
                  onClick={() => {
                    setMinP(null);
                    setMaxP(null);
                    setMinDraft('');
                    setMaxDraft('');
                  }}
                  aria-label="Quitar filtro de precio"
                >
                  {minP != null ? money(minP) : '$0'} – {maxP != null ? money(maxP) : '∞'} ✕
                </button>
              ) : null}
            </div>
          ) : null}

          {theme.macrostructure === 'rails' ? (
            <>
              <RailsLayout storeId={storeId} heroSection={heroSection} />
              {visibleSections
                .filter((sec) => sec.type !== 'hero' && sec.type !== 'carousel')
                .map((sec, i) => (
                  <SectionRenderer
                    key={`${sec.type}-${i}`}
                    storeId={storeId}
                    section={sec}
                  />
                ))}
            </>
          ) : theme.macrostructure === 'masonry' ? (
            <>
              {visibleSections
                .filter((sec) => sec.type !== 'carousel')
                .map((sec, i) => (
                  <SectionRenderer
                    key={`${sec.type}-${i}`}
                    storeId={storeId}
                    section={sec}
                  />
                ))}
              <MasonryLayout
                storeId={storeId}
                initialItems={items}
                categories={categories}
                activeCat={activeCat}
                onCat={setActiveCat}
              />
            </>
          ) : (
            visibleSections.map((sec, i) => (
              <SectionRenderer
                key={`${sec.type}-${i}`}
                storeId={storeId}
                section={sec}
                initialItems={sec.type === 'carousel' ? items : undefined}
              />
            ))
          )}
        </main>

        <Footer storeName={theme.content.brand.displayName} />
        <WhatsAppFloat />
        <MarketingPopup storeId={storeId} />

        {/* pixelId 는 백엔드 PIXEL_ID_RE(영숫자/하이픈/언더스코어만 허용)로 이미 걸러진 값이라
            템플릿 리터럴에 직접 삽입해도 스크립트 인젝션 벡터가 되지 않는다(Plan 61-01, T-61-64). */}
        {theme.content.marketing.pixelId ? (
          <Script id="meta-pixel" strategy="afterInteractive">
            {`!function(f,b,e,v,n,t,s){if(f.fbq)return;n=f.fbq=function(){n.callMethod?n.callMethod.apply(n,arguments):n.queue.push(arguments)};if(!f._fbq)f._fbq=n;n.push=n;n.loaded=!0;n.version='2.0';n.queue=[];t=b.createElement(e);t.async=!0;t.src=v;s=b.getElementsByTagName(e)[0];s.parentNode.insertBefore(t,s)}(window,document,'script','https://connect.facebook.net/en_US/fbevents.js');fbq('init','${theme.content.marketing.pixelId}');fbq('track','PageView');`}
          </Script>
        ) : null}
      </div>
    </ThemeContentProvider>
  );
}

const s: Record<string, CSSProperties> = {
  secHead: {
    display: 'flex',
    alignItems: 'baseline',
    justifyContent: 'space-between',
    margin: '24px 0 16px',
  },
  secTitle: {
    fontSize: 22,
    margin: 0,
    fontFamily: 'var(--font-display)',
    fontWeight: 'var(--disp-weight)',
  },
  muted: { color: 'var(--muted)' },
  priceFilter: {
    display: 'flex',
    alignItems: 'center',
    gap: 8,
    flexWrap: 'wrap',
    margin: '20px 0 4px',
    padding: '10px 12px',
    border: '1px solid var(--line)',
    borderRadius: 'var(--radius)',
    background: 'var(--card)',
  },
  priceInput: {
    width: 100,
    padding: '7px 9px',
    fontSize: 13,
    border: '1px solid var(--line)',
    borderRadius: 'var(--radius)',
    background: 'var(--bg)',
    color: 'var(--ink)',
  },
  priceSep: { color: 'var(--muted)' },
  priceApply: {
    padding: '7px 14px',
    fontSize: 13,
    fontWeight: 700,
    border: 'none',
    borderRadius: 'var(--radius)',
    background: 'var(--gold)',
    color: 'var(--navy)',
    cursor: 'pointer',
  },
  priceChip: {
    padding: '6px 10px',
    fontSize: 12,
    fontWeight: 600,
    border: 'none',
    borderRadius: 20,
    background: 'var(--navy)',
    color: 'var(--on-navy)',
    cursor: 'pointer',
  },
};
