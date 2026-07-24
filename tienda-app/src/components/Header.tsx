import type { CSSProperties } from 'react';
import { useThemeContent } from '@/context/ThemeContentContext';
import { useShop } from '@/context/ShopContext';
import { minioImageUrl } from '@/services/shop-api';
import type { ShopCategory } from '@/types/shop';

interface Props {
  categories: ShopCategory[];
  q: string;
  onQ: (v: string) => void;
  activeCat: number | null;
  onCat: (id: number | null) => void;
}

// href 방어심층 가드 — 백엔드 sanitizeHref 가 1차 방어이나, 렌더 직전에도
// http(s):// 또는 '/' 상대경로만 통과시켜 javascript:/data: 스킴을 재차단한다.
function safeHref(href: string | null): string | null {
  if (!href) return null;

  return /^(https?:\/\/|\/)/i.test(href) ? href : null;
}

export default function Header({ categories, q, onQ, activeCat, onCat }: Props) {
  const { count, openDrawer } = useShop();
  const { announce, brand } = useThemeContent();
  // 아래에서는 로컬 변수만 참조한다(중복 접근 방지).
  const logoFile = brand.logoFile;
  const announceHref = safeHref(announce.href);

  return (
    <header style={s.header}>
      {announce.enabled && announce.text ? (
        <div style={s.announce}>
          {announceHref ? (
            <a href={announceHref} style={{ color: 'inherit', textDecoration: 'none' }}>
              {announce.text}
            </a>
          ) : (
            announce.text
          )}
        </div>
      ) : null}

      <div className="container" style={s.hdr}>
        <div style={s.logo}>
          {logoFile ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={minioImageUrl(logoFile)}
              alt={brand.displayName || 'Logo'}
              style={s.logoImg}
            />
          ) : brand.displayName ? (
            brand.displayName
          ) : (
            // 무회귀 폴백 — displayName 도 로고도 없는 기존 매장은 워드마크를 그대로 유지한다.
            <>
              Cool<span style={{ color: 'var(--gold)' }}>Shop</span>
            </>
          )}
        </div>
        <div style={s.search}>
          <span aria-hidden="true">🔎</span>
          <input
            style={s.searchInput}
            placeholder="Buscar remeras, jeans, vestidos..."
            value={q}
            onChange={(e) => onQ(e.target.value)}
          />
        </div>
        <button style={s.cart} onClick={openDrawer}>
          Carrito
          <b style={s.cartBadge}>{count}</b>
        </button>
      </div>

      <nav style={s.navWrap}>
        <div className="container" style={s.nav}>
          <button
            style={chip(activeCat === null)}
            onClick={() => onCat(null)}
          >
            Inicio
          </button>
          {categories.map((c) => (
            <button
              key={c.id}
              style={chip(activeCat === c.id)}
              onClick={() => onCat(c.id)}
            >
              {c.name}
            </button>
          ))}
        </div>
      </nav>
    </header>
  );
}

const s: Record<string, CSSProperties> = {
  header: {
    position: 'sticky',
    top: 0,
    zIndex: 20,
    background: 'var(--card)',
    borderBottom: '1px solid var(--line)',
  },
  announce: {
    background: 'var(--navy)',
    color: 'var(--on-navy)',
    fontSize: 13,
    textAlign: 'center',
    padding: '8px 12px',
  },
  hdr: { display: 'flex', alignItems: 'center', gap: 20, padding: '16px 20px' },
  logo: {
    fontSize: 22,
    fontWeight: 800,
    letterSpacing: '-0.5px',
    fontFamily: 'var(--font-display)',
  },
  logoImg: { height: 32, objectFit: 'contain', display: 'block' },
  search: {
    flex: 1,
    display: 'flex',
    alignItems: 'center',
    gap: 8,
    background: 'var(--soft)',
    border: '1px solid var(--line)',
    borderRadius: 'var(--radius)',
    padding: '10px 14px',
    color: 'var(--muted)',
  },
  searchInput: {
    border: 'none',
    background: 'transparent',
    outline: 'none',
    flex: 1,
    fontSize: 14,
    color: 'var(--ink)',
  },
  cart: {
    position: 'relative',
    background: 'var(--gold)',
    color: 'var(--navy)',
    border: 'none',
    borderRadius: 'var(--radius)',
    padding: '10px 16px',
    fontWeight: 700,
  },
  cartBadge: {
    background: 'var(--navy)',
    color: '#fff',
    borderRadius: 20,
    padding: '1px 7px',
    fontSize: 12,
    marginLeft: 6,
  },
  navWrap: { borderTop: '1px solid var(--line)', background: 'var(--card)' },
  nav: { display: 'flex', gap: 22, padding: '12px 20px', overflow: 'auto' },
};

function chip(active: boolean): CSSProperties {
  return {
    whiteSpace: 'nowrap',
    background: active ? 'var(--gold)' : 'transparent',
    color: active ? 'var(--navy)' : '#33333f',
    border: 'none',
    borderRadius: 20,
    padding: active ? '4px 12px' : '4px 0',
    fontSize: 14,
    fontWeight: active ? 700 : 400,
  };
}
