import { useEffect, useState } from 'react';
import type { CSSProperties } from 'react';
import { useThemeContent } from '@/context/ThemeContentContext';

// TODO(후속 Phase): 쿠폰 코드 ↔ Campañas discounts 실검증/발급 연동은 Phase 61 범위 외 — 현재는 표시 전용.
export default function MarketingPopup({ storeId }: { storeId: number }) {
  const { marketing } = useThemeContent();
  const [show, setShow] = useState(false);

  useEffect(() => {
    if (!marketing.popup.enabled || !marketing.popup.title) return;
    if (typeof window === 'undefined') return;
    const key = `popup_shown_${storeId}`;
    if (sessionStorage.getItem(key)) return;
    setShow(true);
    sessionStorage.setItem(key, '1');
  }, [storeId, marketing.popup.enabled, marketing.popup.title]);

  // 접근성: ESC 로도 닫히게 한다(닫기 ✕ 클릭과 동등한 경로).
  useEffect(() => {
    if (!show) return undefined;
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setShow(false);
    };
    window.addEventListener('keydown', onKeyDown);

    return () => window.removeEventListener('keydown', onKeyDown);
  }, [show]);

  if (!show) return null;

  return (
    <div style={s.overlay} onClick={() => setShow(false)}>
      <div style={s.box} onClick={(e) => e.stopPropagation()}>
        <button
          type="button"
          onClick={() => setShow(false)}
          style={s.close}
          aria-label="Cerrar"
        >
          ✕
        </button>
        <h2 style={s.title}>{marketing.popup.title}</h2>
        {marketing.popup.coupon ? (
          <div style={s.coupon}>{marketing.popup.coupon}</div>
        ) : null}
      </div>
    </div>
  );
}

const s: Record<string, CSSProperties> = {
  overlay: {
    position: 'fixed',
    inset: 0,
    background: 'rgba(0,0,0,0.4)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    zIndex: 50,
    padding: 16,
  },
  box: {
    position: 'relative',
    background: 'var(--card)',
    color: 'var(--ink)',
    borderRadius: 14,
    padding: 32,
    maxWidth: 380,
    width: '100%',
    textAlign: 'center',
    fontFamily: 'var(--font-body)',
  },
  close: {
    position: 'absolute',
    top: 10,
    right: 10,
    background: 'transparent',
    border: 'none',
    color: 'var(--muted)',
    fontSize: 16,
    cursor: 'pointer',
    lineHeight: 1,
    padding: 6,
  },
  title: {
    margin: '0 0 16px',
    fontSize: 22,
    fontFamily: 'var(--font-display)',
    fontWeight: 'var(--disp-weight)',
  },
  coupon: {
    display: 'inline-block',
    border: '1.5px dashed var(--gold)',
    color: 'var(--gold)',
    borderRadius: 8,
    padding: '8px 16px',
    fontSize: 15,
    fontWeight: 700,
    letterSpacing: 1,
  },
};
