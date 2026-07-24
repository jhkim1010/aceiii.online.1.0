import { useCallback, useEffect, useRef, useState } from 'react';
import type { CSSProperties } from 'react';
import ProductCard from '@/components/ProductCard';
import { useThemeContent } from '@/context/ThemeContentContext';
import { listProducts } from '@/services/shop-api';
import type { HeroSection, RailShelf, ShopProduct } from '@/types/shop';

// 선반 헤더 "전체 보기" 링크가 조립하는 내부 상대경로만 생성한다 — 외부 URL 조립 금지(T-61-37).
function hrefForShelf(storeId: number, shelf: RailShelf): string {
  if (shelf.source === 'category' && shelf.categoryId != null) {
    return `/${storeId}?categoryId=${shelf.categoryId}`;
  }

  return `/${storeId}?sort=${shelf.source}`;
}

// 화살표는 데스크톱(≥640px)에서만 노출 — 모바일은 터치 스크롤이 주 조작수단이다.
function useIsDesktopViewport(): boolean {
  const [isDesktop, setIsDesktop] = useState(false);

  useEffect(() => {
    if (typeof window === 'undefined' || !window.matchMedia) return;

    const mq = window.matchMedia('(min-width: 640px)');

    setIsDesktop(mq.matches);

    const handleChange = (e: MediaQueryListEvent) => setIsDesktop(e.matches);

    mq.addEventListener('change', handleChange);

    return () => mq.removeEventListener('change', handleChange);
  }, []);

  return isDesktop;
}

function Rail({
  storeId,
  shelf,
  lazy,
  showArrows,
  previewItems,
}: {
  storeId: number;
  shelf: RailShelf;
  lazy: boolean;
  showArrows: boolean;
  previewItems?: ShopProduct[];
}) {
  const { title, source, categoryId, limit } = shelf;
  // null = 아직 조회 안 함, [] = 조회했으나 상품 0개.
  // previewItems 가 있으면(에디터 미리보기, T-61-53) 그 값으로 즉시 채우고 fetch 하지 않는다.
  const [items, setItems] = useState<ShopProduct[] | null>(previewItems ?? null);
  const wrapRef = useRef<HTMLElement>(null);
  const scrollRef = useRef<HTMLDivElement>(null);
  const leftArrowRef = useRef<HTMLButtonElement>(null);
  const rightArrowRef = useRef<HTMLButtonElement>(null);
  const isDesktop = useIsDesktopViewport();

  const fetchItems = useCallback((): Promise<ShopProduct[]> => {
    // 카테고리 소스인데 categoryId 미지정이면 조회 근거가 없다
    if (source === 'category' && categoryId == null) {
      return Promise.resolve([]);
    }

    const params =
      source === 'category'
        ? { categoryId: categoryId ?? undefined, pageSize: limit }
        : { sort: source, pageSize: limit };

    return listProducts(storeId, params)
      .then((res) => res.items)
      .catch(() => []);
  }, [storeId, source, categoryId, limit]);

  // 행 단위 lazy load — 화면 진입 200px 전 미리 조회. lazy=false 는 mount 즉시 조회.
  // SSR/구형 브라우저(IntersectionObserver 미지원)는 즉시 조회로 폴백.
  useEffect(() => {
    if (previewItems) return; // 미리보기 모드 — 네트워크 조회 0(T-61-53)
    if (items !== null) return;

    if (!lazy) {
      fetchItems().then(setItems);

      return;
    }

    const el = wrapRef.current;

    if (!el || typeof IntersectionObserver === 'undefined') {
      fetchItems().then(setItems);

      return;
    }

    const io = new IntersectionObserver(
      (entries) => {
        if (entries[0].isIntersecting) {
          fetchItems().then(setItems);
          io.disconnect();
        }
      },
      { rootMargin: '200px' },
    );

    io.observe(el);

    return () => io.disconnect();
  }, [items, lazy, fetchItems, previewItems]);

  // 끝 도달 시 화살표 숨김 — React state 갱신 대신 DOM 을 직접 조작한다
  // (스크롤마다 리렌더를 유발하면 버벅임 — RESEARCH 함정 대응).
  const updateArrowVisibility = useCallback(() => {
    const el = scrollRef.current;

    if (!el) return;

    const atStart = el.scrollLeft <= 0;
    const atEnd = el.scrollLeft + el.clientWidth >= el.scrollWidth - 1;

    if (leftArrowRef.current) {
      leftArrowRef.current.style.opacity = atStart ? '0' : '1';
      leftArrowRef.current.style.pointerEvents = atStart ? 'none' : 'auto';
    }

    if (rightArrowRef.current) {
      rightArrowRef.current.style.opacity = atEnd ? '0' : '1';
      rightArrowRef.current.style.pointerEvents = atEnd ? 'none' : 'auto';
    }
  }, []);

  useEffect(() => {
    const el = scrollRef.current;

    if (!el || !showArrows || !isDesktop || items === null) return;

    updateArrowVisibility();
    el.addEventListener('scroll', updateArrowVisibility, { passive: true });

    return () => el.removeEventListener('scroll', updateArrowVisibility);
  }, [showArrows, isDesktop, items, updateArrowVisibility]);

  const scrollByAmount = (dir: 1 | -1) => {
    const el = scrollRef.current;

    if (!el) return;

    el.scrollBy({ left: dir * el.clientWidth * 0.8, behavior: 'smooth' });
  };

  // 상품 0개인 행은 렌더하지 않는다 — 빈 선반 노출 금지(UI-SPEC 확정 카피 계약).
  if (items !== null && items.length === 0) return null;

  return (
    <section ref={wrapRef} style={s.shelf}>
      <div style={s.header}>
        <h2 style={s.title}>{title}</h2>

        {items !== null ? (
          <>
            <a href={hrefForShelf(storeId, shelf)} style={s.viewAll}>
              Ver todo →
            </a>

            {showArrows && isDesktop ? (
              <div style={s.arrowGroup}>
                <button
                  ref={leftArrowRef}
                  type="button"
                  aria-label="Anterior"
                  onClick={() => scrollByAmount(-1)}
                  style={s.arrow}
                >
                  ‹
                </button>
                <button
                  ref={rightArrowRef}
                  type="button"
                  aria-label="Siguiente"
                  onClick={() => scrollByAmount(1)}
                  style={s.arrow}
                >
                  ›
                </button>
              </div>
            ) : null}
          </>
        ) : null}
      </div>

      <div className="sf-rail" style={s.railPad} ref={scrollRef}>
        {items === null
          ? Array.from({ length: limit }).map((_, i) => (
              <div key={i} style={s.skeleton} />
            ))
          : items.map((p) => <ProductCard key={p.id} product={p} />)}
      </div>
    </section>
  );
}

export default function RailsLayout({
  storeId,
  heroSection,
  previewItems,
}: {
  storeId: number;
  heroSection?: HeroSection;
  // 에디터 미리보기 전용 — 값이 있으면 모든 선반이 fetch 대신 이 배열을 쓴다(T-61-53).
  previewItems?: ShopProduct[];
}) {
  const content = useThemeContent();
  const { shelves, showArrows, lazyRows } = content.macroSettings.rails;

  // shelves 가 비어 있으면 기본 2선반으로 재차 폴백하지 않는다 — DEFAULT_CONTENT 가 이미
  // 2개(Novedades/Más vendidos)를 보장하므로, 여기서는 그대로 null 을 반환해 상위(index.tsx)가
  // 일반 상품 그리드로 폴백하도록 둔다.
  if (shelves.length === 0) return null;

  return (
    <>
      {heroSection?.enabled && heroSection.title ? (
        <div style={s.heroBand}>
          <div>
            <h1 style={s.heroTitle}>{heroSection.title}</h1>
            {heroSection.subtitle ? (
              <p style={s.heroSubtitle}>{heroSection.subtitle}</p>
            ) : null}
          </div>

          {heroSection.cta ? (
            <button className="btn btn-gold" style={s.heroCta}>
              {heroSection.cta}
            </button>
          ) : null}
        </div>
      ) : null}

      {shelves.map((shelf, i) => (
        <Rail
          key={`${i}-${shelf.source}-${shelf.categoryId ?? 'x'}`}
          storeId={storeId}
          shelf={shelf}
          lazy={lazyRows}
          showArrows={showArrows}
          previewItems={previewItems}
        />
      ))}
    </>
  );
}

const s: Record<string, CSSProperties> = {
  heroBand: {
    background: 'linear-gradient(120deg, var(--hero-from), var(--hero-to))',
    padding: '24px 32px',
    borderRadius: 'var(--radius)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 16,
    margin: '24px 0',
    color: 'var(--on-navy)',
  },
  heroTitle: {
    fontSize: 24,
    margin: 0,
    fontFamily: 'var(--font-display)',
    fontWeight: 'var(--disp-weight)',
    color: 'var(--on-navy)',
  },
  heroSubtitle: {
    fontSize: 13,
    opacity: 0.8,
    margin: '4px 0 0',
    color: 'var(--on-navy)',
  },
  heroCta: { padding: '8px 20px', flexShrink: 0 },
  shelf: { margin: '24px 0' },
  header: {
    display: 'flex',
    alignItems: 'center',
    gap: 12,
    padding: '0 24px',
    marginBottom: 16,
  },
  title: {
    fontSize: 20,
    margin: 0,
    flex: 1,
    fontFamily: 'var(--font-display)',
    fontWeight: 'var(--disp-weight)',
    color: 'var(--ink)',
  },
  viewAll: {
    fontSize: 12,
    fontWeight: 400,
    color: 'var(--gold-d)',
    whiteSpace: 'nowrap',
  },
  arrowGroup: { display: 'flex', gap: 8 },
  arrow: {
    width: 28,
    height: 28,
    borderRadius: '50%',
    background: 'var(--card)',
    border: '1px solid var(--line)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    fontSize: 14,
    color: 'var(--ink)',
    cursor: 'pointer',
    transition: 'opacity .15s',
  },
  railPad: { paddingLeft: 24, paddingRight: 24 },
  skeleton: {
    flex: '0 0 172px',
    height: 240,
    background: 'var(--soft)',
    borderRadius: 'var(--radius)',
  },
};
