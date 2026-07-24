import { useCallback, useEffect, useRef, useState } from 'react';
import type { CSSProperties } from 'react';
import ProductCard from '@/components/ProductCard';
import { useThemeContent } from '@/context/ThemeContentContext';
import { listProducts } from '@/services/shop-api';
import type { ShopCategory, ShopProduct } from '@/types/shop';

// ★ CSS columns 는 "위→아래 채우고 다음 열"(신문 조판) 순서다. 정렬이 행 우선이 아닌 것은
// 버그가 아니라 masonry 의 본질 — 에디터에 힌트 카피로 안내한다(Plan 61-13).
export default function MasonryLayout({
  storeId,
  initialItems,
  categories,
  activeCat,
  onCat,
}: {
  storeId: number;
  initialItems: ShopProduct[];
  categories: ShopCategory[];
  activeCat: number | null;
  onCat: (id: number | null) => void;
}) {
  const content = useThemeContent();
  const ms = content.macroSettings.masonry;
  const { catalog } = content;

  const [items, setItems] = useState<ShopProduct[]>(() =>
    initialItems.slice(0, ms.firstLoad),
  );
  const [page, setPage] = useState(1);
  const [done, setDone] = useState(initialItems.length <= ms.firstLoad);
  const [loadingMore, setLoadingMore] = useState(false);
  const hintRef = useRef<HTMLParagraphElement>(null);

  // 상위(index.tsx)가 activeCat 변경 등으로 initialItems 를 교체하면 내부 페이지네이션
  // 상태(items/page/done)를 재동기화한다 — 그렇지 않으면 필터 변경 후에도 이전 목록이 남는다.
  useEffect(() => {
    setItems(initialItems.slice(0, ms.firstLoad));
    setPage(1);
    setDone(initialItems.length <= ms.firstLoad);
  }, [initialItems, ms.firstLoad]);

  // 더 보기 — 신규 무한스크롤 로직을 만들지 않고 기존 카탈로그 페이지네이션을 재사용한다.
  const loadMore = useCallback(() => {
    if (done || loadingMore) return;

    setLoadingMore(true);

    const nextPage = page + 1;

    listProducts(storeId, {
      page: nextPage,
      pageSize: ms.firstLoad,
      sort: catalog.defaultSort,
      showOutOfStock: catalog.showOutOfStock,
      categoryId: activeCat ?? undefined,
    })
      .then((res) => {
        setItems((prev) => [...prev, ...res.items]);
        setPage(nextPage);

        if (res.items.length < ms.firstLoad) setDone(true);
      })
      .catch(() => setDone(true))
      .finally(() => setLoadingMore(false));
  }, [
    done,
    loadingMore,
    page,
    storeId,
    ms.firstLoad,
    catalog.defaultSort,
    catalog.showOutOfStock,
    activeCat,
  ]);

  // 하단 힌트가 뷰포트 300px 전에 들어오면 다음 페이지 로드 — done 이면 관찰 해제.
  useEffect(() => {
    if (done) return;

    const el = hintRef.current;

    if (!el || typeof IntersectionObserver === 'undefined') return;

    const io = new IntersectionObserver(
      (entries) => {
        if (entries[0].isIntersecting) loadMore();
      },
      { rootMargin: '300px' },
    );

    io.observe(el);

    return () => io.disconnect();
  }, [done, loadMore]);

  // 열 수는 인라인 style.columnCount 대신 globals.css .sf-masonry 의 CSS 변수(--sf-mas-cols-*)로
  // 주입한다 — admin 미설정 시 CSS 변수 기본값(데스크톱4/모바일2)으로 자동 폴백.
  const colsStyle = {
    '--sf-mas-cols-mobile': String(ms.mobileCols),
    '--sf-mas-cols-desktop': String(ms.desktopCols),
  } as CSSProperties;

  return (
    <section style={s.wrap}>
      <div style={ms.stickyFilter ? s.chipRowSticky : s.chipRow}>
        <button
          type="button"
          onClick={() => onCat(null)}
          style={activeCat === null ? s.chipOn : s.chip}
        >
          Todo
        </button>

        {categories.map((c) => (
          <button
            key={c.id}
            type="button"
            onClick={() => onCat(c.id)}
            style={activeCat === c.id ? s.chipOn : s.chip}
          >
            {c.name}
          </button>
        ))}
      </div>

      {items.length === 0 ? (
        <p style={s.empty}>No hay productos.</p>
      ) : (
        <>
          <div className="sf-masonry" style={colsStyle}>
            {items.map((p) => (
              <div
                key={p.id}
                style={{ aspectRatio: ms.keepRatio ? 'auto' : '3 / 4' }}
              >
                {/* TODO(Plan 61-12): keepRatio=true 시 실제 이미지 비율 반영은 ProductCard 의 imgwrap 고정 높이(230px) 제거가 선행돼야 함. */}
                <ProductCard product={p} />
              </div>
            ))}
          </div>

          {!done ? (
            <p ref={hintRef} style={s.hint}>
              ···  scroll para descubrir más  ···
            </p>
          ) : null}
        </>
      )}
    </section>
  );
}

const s: Record<string, CSSProperties> = {
  wrap: { margin: '24px 0' },
  chipRow: {
    display: 'flex',
    gap: 8,
    padding: '12px 24px',
    overflowX: 'auto',
  },
  chipRowSticky: {
    display: 'flex',
    gap: 8,
    padding: '12px 24px',
    overflowX: 'auto',
    position: 'sticky',
    top: 0,
    zIndex: 5,
    background: 'var(--bg)',
  },
  chip: {
    border: '1px solid var(--line)',
    borderRadius: 16,
    padding: '8px 16px',
    fontSize: 12,
    fontWeight: 400,
    color: 'var(--muted)',
    background: 'transparent',
    cursor: 'pointer',
    whiteSpace: 'nowrap',
  },
  chipOn: {
    border: '1px solid var(--navy)',
    borderRadius: 16,
    padding: '8px 16px',
    fontSize: 12,
    fontWeight: 400,
    color: 'var(--on-navy)',
    background: 'var(--navy)',
    cursor: 'pointer',
    whiteSpace: 'nowrap',
  },
  hint: {
    textAlign: 'center',
    fontSize: 12,
    color: 'var(--muted)',
    padding: '16px 24px',
    margin: 0,
  },
  empty: { color: 'var(--muted)', padding: '0 24px' },
};
