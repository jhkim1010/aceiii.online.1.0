import { useEffect, useRef, useState } from 'react';
import type { CSSProperties } from 'react';
import Head from 'next/head';
import type { GetServerSideProps } from 'next';
import Header from '@/components/Header';
import ProductCard from '@/components/ProductCard';
import { useShop } from '@/context/ShopContext';
import { getStoreTheme, listCategories, listProducts } from '@/services/shop-api';
import type { ShopCategory, ShopProduct, StoreTheme } from '@/types/shop';

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
  const { setStoreId, openTryOn } = useShop();
  const [items, setItems] = useState<ShopProduct[]>(initialItems);
  const [activeCat, setActiveCat] = useState<number | null>(null);
  const [q, setQ] = useState('');
  const [loading, setLoading] = useState(false);
  const first = useRef(true);

  // 장바구니/체크아웃이 알도록 현재 매장 등록
  useEffect(() => {
    setStoreId(storeId);
  }, [storeId, setStoreId]);

  // 필터/검색 변경 시 클라이언트 재조회 (초기는 SSR)
  useEffect(() => {
    if (first.current) {
      first.current = false;

      return;
    }

    const t = setTimeout(async () => {
      setLoading(true);
      try {
        const res = await listProducts(storeId, {
          q: q.trim() || undefined,
          globalCategoryId: activeCat ?? undefined,
          pageSize: 50,
        });
        setItems(res.items);
      } catch {
        setItems([]);
      } finally {
        setLoading(false);
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

  // macrostructure(레이아웃)별 상품 그리드 밀도
  const gridStyle: CSSProperties = {
    display: 'grid',
    gap: theme.macrostructure === 'doc' ? 14 : 18,
    gridTemplateColumns:
      theme.macrostructure === 'bento'
        ? 'repeat(auto-fill, minmax(240px, 1fr))'
        : theme.macrostructure === 'doc'
          ? 'repeat(auto-fill, minmax(160px, 1fr))'
          : 'repeat(auto-fill, minmax(200px, 1fr))',
  };

  return (
    <div style={wrapStyle} data-macro={theme.macrostructure}>
      <Head>
        <title>CoolShop — Tienda online</title>
        <meta
          name="description"
          content="CoolShop — indumentaria online con probador virtual con IA."
        />
      </Head>

      <Header
        categories={categories}
        q={q}
        onQ={setQ}
        activeCat={activeCat}
        onCat={setActiveCat}
      />

      <main className="container" style={{ paddingBottom: 40 }}>
        <section style={s.hero}>
          <div style={s.heroBig}>
            <h2 style={s.heroTitle}>Nueva temporada otoño 2026</h2>
            <p style={s.heroP}>
              Descubrí las últimas tendencias. Hasta 30% en seleccionados.
            </p>
            <button className="btn btn-gold">Ver colección</button>
          </div>
          <div style={s.promo}>
            <span style={s.tag}>★ Exclusivo IA</span>
            <h3 style={s.promoTitle}>Probate la ropa sin salir de casa</h3>
            <p style={s.promoP}>
              Subí tu foto y mirá cómo te queda cada prenda antes de comprar.
            </p>
            <button
              className="btn btn-ghost"
              onClick={() => items[0] && openTryOn(items[0])}
            >
              Probador virtual
            </button>
          </div>
        </section>

        <div style={s.secHead}>
          <h2 style={s.secTitle}>Destacados</h2>
          {loading ? <span style={s.muted}>Cargando...</span> : null}
        </div>

        {error ? <p style={s.muted}>Error: {error}</p> : null}

        {!loading && items.length === 0 ? (
          <p style={s.muted}>No hay productos.</p>
        ) : (
          <section style={gridStyle}>
            {items.map((p) => (
              <ProductCard key={p.id} product={p} />
            ))}
          </section>
        )}

        <section style={s.aistrip}>
          <div>
            <h2 style={s.aiTitle}>Probador virtual con IA 👗</h2>
            <p style={s.aiP}>
              Elegí un producto, subí tu foto y mirá el resultado al instante.
            </p>
          </div>
        </section>
      </main>
    </div>
  );
}

const s: Record<string, CSSProperties> = {
  hero: {
    display: 'grid',
    gridTemplateColumns: '2fr 1fr',
    gap: 16,
    margin: '22px 0',
  },
  heroBig: {
    borderRadius: 'var(--radius)',
    padding: '48px 40px',
    color: '#fff',
    // 매장 테마 히어로 그라디언트
    background: 'linear-gradient(120deg, var(--hero-from), var(--hero-to))',
    display: 'flex',
    flexDirection: 'column',
    justifyContent: 'center',
    minHeight: 280,
  },
  heroTitle: {
    fontSize: 34,
    margin: '0 0 8px',
    lineHeight: 1.1,
    fontFamily: 'var(--font-display)',
    fontWeight: 'var(--disp-weight)',
  },
  heroP: { margin: '0 0 20px', color: '#d8d6ea', maxWidth: 380 },
  promo: {
    borderRadius: 'var(--radius)',
    padding: 28,
    background: 'var(--promo-bg)',
    border: '1px solid var(--promo-line)',
    display: 'flex',
    flexDirection: 'column',
    justifyContent: 'center',
  },
  tag: {
    display: 'inline-flex',
    alignItems: 'center',
    gap: 6,
    background: 'var(--gold)',
    color: 'var(--navy)',
    fontWeight: 700,
    fontSize: 12,
    borderRadius: 20,
    padding: '5px 12px',
    width: 'max-content',
  },
  promoTitle: {
    fontSize: 20,
    margin: '14px 0 6px',
    fontFamily: 'var(--font-display)',
    fontWeight: 'var(--disp-weight)',
  },
  promoP: { margin: '0 0 16px', color: 'var(--muted)', fontSize: 14 },
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
  aistrip: {
    margin: '40px 0',
    borderRadius: 'var(--radius)',
    padding: 36,
    color: '#fff',
    background: 'linear-gradient(120deg, var(--hero-from), var(--hero-to))',
  },
  aiTitle: {
    fontSize: 26,
    margin: '0 0 8px',
    fontFamily: 'var(--font-display)',
    fontWeight: 'var(--disp-weight)',
  },
  aiP: { margin: 0, color: '#d8d6ea', maxWidth: 440 },
  muted: { color: 'var(--muted)' },
};
