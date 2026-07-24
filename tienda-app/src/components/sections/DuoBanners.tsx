import type { CSSProperties } from 'react';
import { minioImageUrl } from '@/services/shop-api';
import type { DuoBannersSection } from '@/types/shop';

export default function DuoBanners({ section }: { section: DuoBannersSection }) {
  const { banners } = section;

  if (banners.length === 0) return null;

  return (
    <section style={s.wrap}>
      {banners.map((banner, i) => {
        // 2번째(index 1) 배너는 UI-SPEC 상 "세일" 강조 배경 사용
        const isSale = i === 1;
        const content = (
          <div style={isSale ? s.bannerSale : s.banner}>
            {banner.image ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img
                src={minioImageUrl(banner.image)}
                alt=""
                style={s.bannerImg}
              />
            ) : null}
            <div style={s.bannerContent}>
              <h3 style={s.bannerTitle}>{banner.title}</h3>
              <p style={isSale ? s.bannerSubSale : s.bannerSub}>
                {banner.subtitle}
              </p>
            </div>
          </div>
        );

        // href 는 백엔드 sanitizeHref() 를 통과한 값만 저장된다(javascript:/data: 는 이미
        // null 로 강등됨) — 프런트는 재검증하지 않고 null 아니면 그대로 <a> 로 감싼다(SSOT 원칙)
        return banner.href ? (
          <a key={i} href={banner.href} style={s.link}>
            {content}
          </a>
        ) : (
          <div key={i}>{content}</div>
        );
      })}
    </section>
  );
}

const s: Record<string, CSSProperties> = {
  wrap: {
    display: 'grid',
    gridTemplateColumns: '1fr 1fr',
    gap: 16,
    margin: '24px 0',
  },
  banner: {
    borderRadius: 'var(--radius)',
    padding: 24,
    background: 'var(--promo-bg)',
    border: '1px solid var(--promo-line)',
    display: 'flex',
    flexDirection: 'column',
    justifyContent: 'center',
    position: 'relative',
    overflow: 'hidden',
    minHeight: 160,
  },
  bannerSale: {
    borderRadius: 'var(--radius)',
    padding: 24,
    background: 'linear-gradient(120deg, var(--hero-from), var(--gold))',
    color: 'var(--on-navy)',
    display: 'flex',
    flexDirection: 'column',
    justifyContent: 'center',
    position: 'relative',
    overflow: 'hidden',
    minHeight: 160,
  },
  bannerImg: {
    position: 'absolute',
    inset: 0,
    width: '100%',
    height: '100%',
    objectFit: 'cover',
    opacity: 0.35,
  },
  bannerContent: { position: 'relative', zIndex: 1 },
  bannerTitle: {
    fontSize: 20,
    margin: '0 0 6px',
    fontFamily: 'var(--font-display)',
    fontWeight: 'var(--disp-weight)',
  },
  bannerSub: { margin: 0, fontSize: 13, color: 'var(--muted)' },
  bannerSubSale: { margin: 0, fontSize: 13, color: 'var(--on-navy)', opacity: 0.8 },
  link: { textDecoration: 'none', color: 'inherit' },
};
