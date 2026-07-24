import { useEffect, useRef, useState } from 'react';
import type { CSSProperties } from 'react';
import Head from 'next/head';
import type { GetServerSideProps } from 'next';
import Footer from '@/components/Footer';
import Header from '@/components/Header';
import WhatsAppFloat from '@/components/WhatsAppFloat';
import MasonryLayout from '@/components/macro/MasonryLayout';
import RailsLayout from '@/components/macro/RailsLayout';
import SectionRenderer from '@/components/sections/SectionRenderer';
import { ThemeContentProvider } from '@/context/ThemeContentContext';
import { useShop } from '@/context/ShopContext';
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
    const [list, categories] = await Promise.all([
      listProducts(storeId, { pageSize: 24 }),
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
          pageSize: 50,
        });
        setItems(res.items);
      } catch {
        setItems([]);
      }
    }, 300);

    return () => clearTimeout(t);
  }, [storeId, activeCat, q]);

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
          <title>CoolShop — Tienda online</title>
          <meta
            name="description"
            content="CoolShop — indumentaria online con probador virtual con IA."
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
};
