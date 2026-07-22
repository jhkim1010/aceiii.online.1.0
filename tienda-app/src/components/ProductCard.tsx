import type { CSSProperties } from 'react';
import { useShop } from '@/context/ShopContext';
import { cuotas, money, placeholderGradient } from '@/lib/format';
import { minioImageUrl } from '@/services/shop-api';
import type { ShopProduct } from '@/types/shop';

export default function ProductCard({ product }: { product: ShopProduct }) {
  const { add, openTryOn } = useShop();

  return (
    <div style={s.card}>
      <div style={s.imgwrap}>
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
      </div>
      <div style={s.body}>
        <div style={s.name}>{product.name}</div>
        <div style={s.price}>{money(product.price)}</div>
        <div style={s.cuotas}>{cuotas(product.price)}</div>
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
  imgwrap: { height: 230 },
  img: { width: '100%', height: '100%', objectFit: 'cover' },
  ph: { width: '100%', height: '100%' },
  body: { padding: 14, display: 'flex', flexDirection: 'column', gap: 6 },
  name: { fontSize: 14, lineHeight: 1.35, minHeight: 38 },
  price: { fontSize: 18, fontWeight: 800, color: 'var(--ink)' },
  cuotas: { fontSize: 12, color: 'var(--green)', fontWeight: 600 },
  acts: { display: 'flex', gap: 8, marginTop: 8 },
  btn: { flex: 1, padding: 9, fontSize: 13, borderRadius: 'var(--radius)' },
};
