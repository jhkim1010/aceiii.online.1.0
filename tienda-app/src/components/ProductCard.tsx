import type { CSSProperties } from 'react';
import { useThemeContent } from '@/context/ThemeContentContext';
import { useShop } from '@/context/ShopContext';
import { cuotas, money, placeholderGradient } from '@/lib/format';
import { minioImageUrl } from '@/services/shop-api';
import type { ShopProduct } from '@/types/shop';

export interface ProductCardOptions {
  discountBadge: boolean;
  installments: boolean;
  quickAdd: boolean;
  hoverSecondImage: boolean;
  lastUnitsBadge: boolean;
  variantDots: boolean;
}

export default function ProductCard({
  product,
  options,
}: {
  product: ShopProduct;
  options?: ProductCardOptions;
}) {
  const { add, openTryOn } = useShop();
  // options 미지정 시 테마 content 를 폴백으로 사용 — Provider 밖(또는 미지정)에서도
  // useThemeContent() 가 DEFAULT_CONTENT 를 반환해 절대 크래시하지 않는다. 이렇게 하면
  // Carousel/RailsLayout/MasonryLayout 어디서 렌더되든 options prop 없이도 자동으로
  // 에디터에서 설정한 productCard 옵션이 적용된다(prop drilling 불필요).
  // 훅은 조건 없이 항상 호출(rules-of-hooks) — 폴백 여부만 이후 `??` 로 결정한다.
  const themeProductCard = useThemeContent().productCard;
  const o: ProductCardOptions = options ?? themeProductCard;

  const showDiscount =
    o.discountBadge &&
    product.priceOrig != null &&
    product.priceOrig > product.price;
  const discountPct = showDiscount
    ? Math.round((1 - product.price / product.priceOrig!) * 100)
    : 0;
  const showLastUnits =
    o.lastUnitsBadge && product.stock != null && product.stock > 0 && product.stock < 3;
  const showHover2 = o.hoverSecondImage && !!product.imageUrls?.[1];

  return (
    <div style={s.card}>
      <div
        style={s.imgwrap}
        className={showHover2 ? 'pc-hover2' : undefined}
      >
        {product.imageUrl ? (
          // 최적화는 후속(next/Image); MVP 는 안정적인 img
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={minioImageUrl(product.imageUrl)}
            alt={product.name}
            style={s.img}
          />
        ) : (
          <div
            style={{
              ...s.ph,
              backgroundImage: placeholderGradient(product.id),
            }}
          />
        )}
        {showHover2 ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={minioImageUrl(product.imageUrls![1])}
            alt={product.name}
            className="pc-img2"
            style={s.img2}
          />
        ) : null}
        {showDiscount ? (
          <span style={s.badgeDiscount}>-{discountPct}%</span>
        ) : null}
        {showLastUnits ? (
          <span style={s.badgeLastUnits}>ÚLTIMAS UNIDADES</span>
        ) : null}
        {o.quickAdd ? (
          <button
            type="button"
            style={s.quickAdd}
            aria-label="Agregar al carrito"
            onClick={(e) => {
              e.stopPropagation();
              add(product);
            }}
          >
            ＋
          </button>
        ) : null}
      </div>
      <div style={s.body}>
        <div style={s.name}>{product.name}</div>
        <div style={s.price}>{money(product.price)}</div>
        {o.installments ? (
          <div style={s.cuotas}>{cuotas(product.price)}</div>
        ) : null}
        {/* TODO(Phase 61 이후): variant 색상 집계 API 필요 — 데이터 없이 가짜 점 금지(no-op) */}
        <div style={s.acts}>
          <button
            className="btn btn-gold"
            style={s.btn}
            onClick={() => add(product)}
          >
            Agregar
          </button>
          <button
            className="btn btn-ghost"
            style={s.btn}
            onClick={() => openTryOn(product)}
          >
            👗 Probar
          </button>
        </div>
      </div>
    </div>
  );
}

const s: Record<string, CSSProperties> = {
  card: {
    border: '1px solid var(--line)',
    // 매장 테마 모서리 토큰 적용
    borderRadius: 'var(--radius)',
    overflow: 'hidden',
    background: 'var(--card)',
    display: 'flex',
    flexDirection: 'column',
  },
  imgwrap: { height: 230, position: 'relative' },
  img: { width: '100%', height: '100%', objectFit: 'cover' },
  img2: {
    position: 'absolute',
    inset: 0,
    width: '100%',
    height: '100%',
    objectFit: 'cover',
  },
  ph: { width: '100%', height: '100%' },
  badgeDiscount: {
    position: 'absolute',
    top: 8,
    left: 8,
    background: 'var(--gold)',
    color: 'var(--navy)',
    fontSize: 12,
    fontWeight: 800,
    padding: '4px 8px',
    borderRadius: 5,
  },
  badgeLastUnits: {
    position: 'absolute',
    top: 8,
    right: 8,
    background: 'var(--navy)',
    color: 'var(--gold)',
    fontSize: 12,
    fontWeight: 800,
    padding: '4px 8px',
    borderRadius: 5,
  },
  quickAdd: {
    position: 'absolute',
    right: 8,
    bottom: 8,
    width: 32,
    height: 32,
    borderRadius: '50%',
    background: 'var(--gold)',
    color: 'var(--navy)',
    border: 'none',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    fontSize: 16,
    fontWeight: 700,
    cursor: 'pointer',
    boxShadow: '0 3px 8px rgba(0,0,0,0.2)',
  },
  body: { padding: 14, display: 'flex', flexDirection: 'column', gap: 6 },
  name: { fontSize: 14, lineHeight: 1.35, minHeight: 38 },
  price: { fontSize: 20, fontWeight: 'var(--disp-weight)', color: 'var(--ink)' },
  cuotas: { fontSize: 12, color: 'var(--green)', fontWeight: 600 },
  acts: { display: 'flex', gap: 8, marginTop: 8 },
  btn: { flex: 1, padding: 9, fontSize: 13, borderRadius: 'var(--radius)' },
};
