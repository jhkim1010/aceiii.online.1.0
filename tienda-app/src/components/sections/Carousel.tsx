import { useEffect, useState } from 'react';
import type { CSSProperties } from 'react';
import ProductCard from '@/components/ProductCard';
import { listProducts } from '@/services/shop-api';
import type { CarouselSection, ShopProduct } from '@/types/shop';

export default function Carousel({
  storeId,
  section,
  initialItems,
}: {
  storeId: number;
  section: CarouselSection;
  initialItems?: ShopProduct[];
}) {
  const { title, source, categoryId } = section;

  // SSR 이 이미 newest 목록을 받아왔으면 재조회하지 않고 그대로 사용(요청 절약, T-61-33)
  const canUseInitial = source === 'newest' && initialItems !== undefined;
  const [items, setItems] = useState<ShopProduct[] | null>(
    canUseInitial ? (initialItems as ShopProduct[]) : null,
  );
  const [loading, setLoading] = useState(!canUseInitial);

  useEffect(() => {
    if (canUseInitial) return;
    // categoryId 미지정인 카테고리 소스는 조회 자체를 하지 않는다
    if (source === 'category' && categoryId == null) return;

    let alive = true;
    setLoading(true);

    const params =
      source === 'bestseller'
        ? { sort: 'bestseller' as const, pageSize: 12 }
        : source === 'category'
          ? { categoryId: categoryId ?? undefined, pageSize: 12 }
          : { sort: 'newest' as const, pageSize: 12 };

    listProducts(storeId, params)
      .then((res) => {
        if (!alive) return;
        setItems(res.items);
      })
      .catch(() => {
        if (!alive) return;
        setItems([]);
      })
      .finally(() => {
        if (!alive) return;
        setLoading(false);
      });

    return () => {
      alive = false;
    };
  }, [storeId, source, categoryId, canUseInitial]);

  // category 소스인데 categoryId 가 없으면 렌더할 근거가 없다
  if (source === 'category' && categoryId == null) return null;

  return (
    <section style={s.wrap}>
      <div style={s.secHead}>
        <h2 style={s.secTitle}>{title || 'Destacados'}</h2>
        {loading ? <span style={s.muted}>Cargando...</span> : null}
      </div>

      {!loading && (items ?? []).length === 0 ? (
        <p style={s.muted}>No hay productos.</p>
      ) : (
        <section style={s.grid}>
          {(items ?? []).map((p) => (
            <ProductCard key={p.id} product={p} />
          ))}
        </section>
      )}
    </section>
  );
}

const s: Record<string, CSSProperties> = {
  wrap: { margin: '24px 0' },
  secHead: {
    display: 'flex',
    alignItems: 'baseline',
    justifyContent: 'space-between',
    margin: '24px 0 16px',
  },
  secTitle: {
    fontSize: 20,
    margin: 0,
    fontFamily: 'var(--font-display)',
    fontWeight: 'var(--disp-weight)',
  },
  grid: {
    display: 'grid',
    gap: 16,
    gridTemplateColumns: 'repeat(auto-fill, minmax(200px, 1fr))',
  },
  muted: { color: 'var(--muted)', fontSize: 13 },
};
