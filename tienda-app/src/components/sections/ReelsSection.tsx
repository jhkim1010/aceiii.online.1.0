import { useEffect, useState } from 'react';
import type { CSSProperties, MouseEvent } from 'react';
import { useShop } from '@/context/ShopContext';
import { money } from '@/lib/format';
import { listProducts, minioImageUrl } from '@/services/shop-api';
import type { ReelsSection as ReelsSectionData, ShopProduct } from '@/types/shop';

export default function ReelsSection({
  storeId,
  section,
}: {
  storeId: number;
  section: ReelsSectionData;
}) {
  const { add } = useShop();
  const [playingIdx, setPlayingIdx] = useState<number | null>(null);
  const [productMap, setProductMap] = useState<Map<number, ShopProduct>>(new Map());

  // 상품 오버레이용 — "id 목록으로 조회" 공개 엔드포인트가 없으므로 1회 목록 조회 후
  // 클라이언트에서 매칭한다(productId 연결된 item 이 없으면 조회 자체를 생략).
  useEffect(() => {
    let alive = true;
    const needsLookup = section.items.some((it) => it.productId != null);
    if (!needsLookup) return;

    listProducts(storeId, { pageSize: 48 })
      .then((res) => {
        if (!alive) return;
        setProductMap(new Map(res.items.map((p) => [p.id, p])));
      })
      .catch(() => undefined); // 매칭 실패는 오버레이 미렌더로 안전 처리(가짜 데이터 금지)

    return () => {
      alive = false;
    };
  }, [storeId, section.items]);

  if (section.items.length === 0) return null;

  const handleTap = (e: MouseEvent<HTMLVideoElement>, idx: number) => {
    const v = e.currentTarget;
    // 탭한 영상 외 모든 video 를 멈춘다(동시 재생 방지, 전역 상태 불필요 — DOM 순회로 충분)
    document.querySelectorAll('video').forEach((other) => {
      if (other !== v) other.pause();
    });
    if (v.paused) {
      v.play().catch(() => undefined); // iOS 재생 거부는 조용히 무시
      setPlayingIdx(idx);
    } else {
      v.pause();
      setPlayingIdx(null);
    }
  };

  return (
    <section style={s.wrap}>
      {section.title ? <h2 style={s.title}>{section.title}</h2> : null}
      <div className="sf-rail" style={s.rail}>
        {section.items.map((item, idx) => {
          const product =
            item.productId != null ? productMap.get(item.productId) : undefined;

          return (
            <div key={idx} style={s.card}>
              <video
                muted
                playsInline
                preload="none"
                poster={minioImageUrl(item.posterFile)}
                style={s.video}
                onClick={(e) => handleTap(e, idx)}
              >
                <source
                  src={minioImageUrl(item.videoFile)}
                  type={item.videoFile.endsWith('.webm') ? 'video/webm' : 'video/mp4'}
                />
              </video>
              {playingIdx !== idx ? <span style={s.play}>▶</span> : null}
              {item.durationLabel ? (
                <span style={s.dur}>▶ {item.durationLabel}</span>
              ) : null}
              {product ? (
                <div style={s.prod}>
                  {product.imageUrl ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img
                      src={minioImageUrl(product.imageUrl)}
                      alt=""
                      style={s.prodImg}
                    />
                  ) : (
                    <div style={s.prodImg} />
                  )}
                  <div style={s.prodInfo}>
                    <div style={s.prodName}>{product.name}</div>
                    <div style={s.prodPrice}>{money(product.price)}</div>
                  </div>
                  <button
                    type="button"
                    aria-label="Agregar al carrito"
                    style={s.addBtn}
                    onClick={(ev) => {
                      ev.stopPropagation();
                      add(product);
                    }}
                  >
                    🛒
                  </button>
                </div>
              ) : null}
            </div>
          );
        })}
      </div>
    </section>
  );
}

const s: Record<string, CSSProperties> = {
  wrap: { margin: '24px 0' },
  title: {
    fontSize: 20,
    margin: '0 0 12px',
    padding: '0 24px',
    fontFamily: 'var(--font-display)',
    fontWeight: 'var(--disp-weight)',
  },
  // .sf-rail(globals.css) 은 overflow-x/scroll-snap/스크롤바 숨김을 제공한다 — reels 전용
  // 크기(gap 16/카드 192px)는 인라인 스타일로 덮어쓴다(인라인 > 클래스 우선순위).
  rail: { gap: 16, padding: '4px 24px 20px' },
  card: {
    flex: '0 0 min(192px, 60vw)',
    aspectRatio: '9 / 16',
    borderRadius: 12,
    overflow: 'hidden',
    position: 'relative',
    cursor: 'pointer',
  },
  video: { width: '100%', height: '100%', objectFit: 'cover' },
  play: {
    position: 'absolute',
    inset: 0,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    fontSize: 32,
    color: 'rgba(255,255,255,0.85)',
    textShadow: '0 2px 10px rgba(0,0,0,0.5)',
    pointerEvents: 'none',
  },
  dur: {
    position: 'absolute',
    top: 8,
    right: 8,
    background: 'rgba(0,0,0,0.5)',
    color: 'var(--on-navy)',
    fontSize: 12,
    borderRadius: 5,
    padding: '4px 8px',
  },
  prod: {
    position: 'absolute',
    left: 8,
    right: 8,
    bottom: 8,
    background: 'var(--card)',
    borderRadius: 9,
    padding: '8px 12px',
    display: 'flex',
    alignItems: 'center',
    gap: 8,
  },
  prodImg: {
    width: 32,
    height: 40,
    borderRadius: 6,
    objectFit: 'cover',
    flexShrink: 0,
  },
  prodInfo: { flex: 1, minWidth: 0 },
  prodName: {
    fontSize: 12,
    color: 'var(--ink)',
    lineHeight: 1.3,
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap',
  },
  prodPrice: { fontSize: 12, color: 'var(--ink)', fontWeight: 400 },
  addBtn: {
    marginLeft: 'auto',
    background: 'var(--navy)',
    color: 'var(--on-navy)',
    border: 0,
    borderRadius: 6,
    padding: 8,
    fontSize: 14,
    cursor: 'pointer',
    flexShrink: 0,
  },
};
