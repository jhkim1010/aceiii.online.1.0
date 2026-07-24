import { useEffect, useState } from 'react';
import type { CSSProperties } from 'react';
import { minioImageUrl } from '@/services/shop-api';
import type { HeroSection } from '@/types/shop';

const AUTO_INTERVAL_MS = 5000;

export default function Hero({ section }: { section: HeroSection }) {
  const { title, subtitle, cta, images } = section;
  const [index, setIndex] = useState(0);

  // 이미지 2장 이상일 때만 자동 순환 캐러셀 — 신규 라이브러리 없이 setInterval 로 처리.
  // effect cleanup 에서 반드시 인터벌을 해제한다(메모리 누수 방지, T-61-32).
  useEffect(() => {
    if (images.length < 2) return;

    const t = setInterval(() => {
      setIndex((i) => (i + 1) % images.length);
    }, AUTO_INTERVAL_MS);

    return () => clearInterval(t);
  }, [images.length]);

  // 제목/부제가 둘 다 비어있으면 렌더할 콘텐츠가 없다 — 섹션 자체를 생략(무회귀 안전)
  if (!title && !subtitle) return null;

  return (
    <section style={s.hero}>
      {images.length > 0 ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          key={index}
          src={minioImageUrl(images[index])}
          alt=""
          style={s.heroImg}
        />
      ) : null}

      <div style={s.heroContent}>
        <h1 style={s.heroTitle}>{title}</h1>
        {subtitle ? <p style={s.heroP}>{subtitle}</p> : null}
        {cta ? <button className="btn btn-gold">{cta}</button> : null}
      </div>

      {images.length >= 2 ? (
        <div style={s.dots}>
          {images.map((_, i) => (
            <span key={i} style={i === index ? s.dotOn : s.dotOff} />
          ))}
        </div>
      ) : null}
    </section>
  );
}

const s: Record<string, CSSProperties> = {
  hero: {
    borderRadius: 'var(--radius)',
    padding: '48px 40px',
    minHeight: 280,
    position: 'relative',
    overflow: 'hidden',
    display: 'flex',
    flexDirection: 'column',
    justifyContent: 'center',
    margin: '24px 0',
    // 매장 테마 히어로 그라디언트(무이미지/1장/캐러셀 공통 배경)
    background: 'linear-gradient(120deg, var(--hero-from), var(--hero-to))',
  },
  heroImg: {
    position: 'absolute',
    inset: 0,
    width: '100%',
    height: '100%',
    objectFit: 'cover',
    opacity: 0.55,
  },
  heroContent: { position: 'relative', zIndex: 1 },
  heroTitle: {
    fontSize: 'clamp(24px, 6vw, 34px)',
    margin: '0 0 8px',
    lineHeight: 1.1,
    fontFamily: 'var(--font-display)',
    fontWeight: 'var(--disp-weight)',
    color: 'var(--on-navy)',
  },
  heroP: {
    margin: '0 0 20px',
    fontSize: 13,
    color: 'var(--on-navy)',
    opacity: 0.8,
    maxWidth: 380,
  },
  dots: {
    position: 'absolute',
    bottom: 16,
    left: 0,
    right: 0,
    display: 'flex',
    justifyContent: 'center',
    gap: 8,
    zIndex: 1,
  },
  dotOn: { width: 8, height: 8, borderRadius: '50%', background: 'var(--gold)' },
  dotOff: {
    width: 8,
    height: 8,
    borderRadius: '50%',
    background: 'var(--on-navy)',
    opacity: 0.4,
  },
};
