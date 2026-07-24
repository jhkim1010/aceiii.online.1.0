import type { CSSProperties } from 'react';
import { useThemeContent } from '@/context/ThemeContentContext';
import { minioImageUrl } from '@/services/shop-api';

export default function Footer({ storeName }: { storeName?: string }) {
  const { contact, trust, brand } = useThemeContent();

  const contactEmpty =
    !contact.whatsapp &&
    !contact.instagram &&
    !contact.facebook &&
    !contact.footerText;
  const trustEmpty =
    trust.paymentLogos.length === 0 &&
    trust.shippingLogos.length === 0 &&
    trust.policyLinks.length === 0 &&
    !trust.protectedBadge;

  // 확장 키 없는 기존 매장은 <footer> 자체가 없던 것이 현행 — 데이터가 전무하면 렌더하지 않는다(무회귀).
  if (contactEmpty && trustEmpty) return null;

  const igHref = contact.instagram
    ? contact.instagram.startsWith('http')
      ? contact.instagram
      : `https://instagram.com/${contact.instagram}`
    : null;
  const fbHref = contact.facebook
    ? contact.facebook.startsWith('http')
      ? contact.facebook
      : `https://facebook.com/${contact.facebook}`
    : null;

  const paymentAndShippingLogos = [...trust.paymentLogos, ...trust.shippingLogos];

  return (
    <footer style={s.wrap}>
      <div className="container" style={s.grid}>
        <div>
          <h3 style={s.brandHeading}>{brand.displayName || storeName}</h3>
          {contact.footerText ? <p style={s.body}>{contact.footerText}</p> : null}
        </div>

        {igHref || fbHref ? (
          <div>
            <p style={s.colLabel}>Redes</p>
            {igHref ? (
              <a
                href={igHref}
                target="_blank"
                rel="noopener noreferrer"
                style={s.link}
              >
                Instagram
              </a>
            ) : null}
            {fbHref ? (
              <a
                href={fbHref}
                target="_blank"
                rel="noopener noreferrer"
                style={s.link}
              >
                Facebook
              </a>
            ) : null}
          </div>
        ) : null}

        {trust.policyLinks.length > 0 ? (
          <div>
            <p style={s.colLabel}>Políticas</p>
            {trust.policyLinks.map((l, i) => (
              <a key={i} href={l.href} style={s.link}>
                {l.label}
              </a>
            ))}
          </div>
        ) : null}

        {paymentAndShippingLogos.length > 0 ? (
          <div>
            <p style={s.colLabel}>Pagos y envíos</p>
            <div style={s.chipRow}>
              {paymentAndShippingLogos.map((f, i) => (
                <span key={i} style={s.chip}>
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img src={minioImageUrl(f)} alt="" style={s.chipImg} />
                </span>
              ))}
            </div>
          </div>
        ) : null}
      </div>

      {trust.protectedBadge ? (
        <div className="container" style={s.badgeRow}>
          <span style={s.badgeLabel}>
            <span aria-hidden="true">🛡</span> Compra protegida
          </span>
        </div>
      ) : null}
    </footer>
  );
}

const s: Record<string, CSSProperties> = {
  wrap: {
    background: 'var(--navy)',
    color: 'rgba(255,255,255,0.75)',
    padding: '32px 0 24px',
    marginTop: 40,
  },
  grid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))',
    gap: 24,
  },
  brandHeading: {
    fontSize: 20,
    margin: '0 0 8px',
    color: 'var(--on-navy)',
    fontFamily: 'var(--font-display)',
    fontWeight: 'var(--disp-weight)',
  },
  body: { fontSize: 13, margin: 0, lineHeight: 1.5 },
  colLabel: {
    fontSize: 12,
    fontWeight: 700,
    color: 'var(--on-navy)',
    margin: '0 0 8px',
  },
  link: {
    display: 'block',
    fontSize: 13,
    color: 'inherit',
    textDecoration: 'none',
    marginBottom: 6,
  },
  chipRow: { display: 'flex', flexWrap: 'wrap', gap: 8 },
  chip: {
    background: 'rgba(255,255,255,0.08)',
    border: '1px solid rgba(255,255,255,0.13)',
    borderRadius: 5,
    padding: '4px 8px',
    display: 'inline-flex',
    alignItems: 'center',
  },
  chipImg: { height: 16, display: 'block' },
  badgeRow: {
    borderTop: '1px solid rgba(255,255,255,0.1)',
    marginTop: 24,
    paddingTop: 16,
  },
  badgeLabel: { fontSize: 12 },
};
