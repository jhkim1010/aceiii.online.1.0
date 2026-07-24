import type { CSSProperties } from 'react';
import type { BenefitsSection } from '@/types/shop';

export default function Benefits({ section }: { section: BenefitsSection }) {
  const { items } = section;

  if (items.length === 0) return null;

  return (
    <section style={s.wrap}>
      {items.map((item, i) => (
        <div key={i} style={s.item}>
          {item.icon ? (
            // 이모지는 장식 — 의미는 text 가 전달하므로 스크린리더에서 숨김
            <span aria-hidden="true" style={s.icon}>
              {item.icon}
            </span>
          ) : null}
          <span style={s.text}>{item.text}</span>
        </div>
      ))}
    </section>
  );
}

const s: Record<string, CSSProperties> = {
  wrap: {
    margin: '40px 0',
    borderRadius: 'var(--radius)',
    padding: 32,
    background: 'linear-gradient(120deg, var(--hero-from), var(--hero-to))',
    color: 'var(--on-navy)',
    display: 'grid',
    gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))',
    gap: 16,
  },
  item: { display: 'flex', alignItems: 'center', gap: 8 },
  icon: { fontSize: 24 },
  text: { fontSize: 13 },
};
