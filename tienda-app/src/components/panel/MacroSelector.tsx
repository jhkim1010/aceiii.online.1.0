import { useState } from 'react';
import type { CSSProperties, ReactElement } from 'react';
import { MACRO_OPTIONS } from '@/lib/theme-preset';
import type { Macrostructure } from '@/types/shop';

// 구조 선택 카드의 46×34 와이어프레임 — 손수 작성한 인라인 SVG(아이콘 라이브러리 아님,
// UI-SPEC "Icon library: none" 예외). 시각 정본: 레포 루트
// tienda-online-estructuras-editor-mockup.html 의 EST.{key}.icon 마크업을 그대로 이식.
const MACRO_ICONS: Record<Macrostructure, ReactElement> = {
  marquee: (
    <svg width="46" height="34" viewBox="0 0 46 34">
      <rect width="46" height="34" rx="3" fill="#15152a" stroke="#32325a" />
      <rect x="4" y="4" width="38" height="11" rx="2" fill="#f5a623" opacity=".75" />
      <rect x="4" y="19" width="8" height="11" rx="2" fill="#4a4a80" />
      <rect x="14" y="19" width="8" height="11" rx="2" fill="#4a4a80" />
      <rect x="24" y="19" width="8" height="11" rx="2" fill="#4a4a80" />
      <rect x="34" y="19" width="8" height="11" rx="2" fill="#4a4a80" />
    </svg>
  ),
  bento: (
    <svg width="46" height="34" viewBox="0 0 46 34">
      <rect width="46" height="34" rx="3" fill="#15152a" stroke="#32325a" />
      <rect x="4" y="4" width="22" height="16" rx="2" fill="#f5a623" opacity=".75" />
      <rect x="28" y="4" width="14" height="7" rx="2" fill="#4a4a80" />
      <rect x="28" y="13" width="14" height="7" rx="2" fill="#4a4a80" />
      <rect x="4" y="22" width="14" height="8" rx="2" fill="#4a4a80" />
      <rect x="20" y="22" width="22" height="8" rx="2" fill="#4a4a80" />
    </svg>
  ),
  rails: (
    <svg width="46" height="34" viewBox="0 0 46 34">
      <rect width="46" height="34" rx="3" fill="#15152a" stroke="#32325a" />
      <rect x="4" y="4" width="10" height="8" rx="2" fill="#f5a623" opacity=".75" />
      <rect x="16" y="4" width="10" height="8" rx="2" fill="#4a4a80" />
      <rect x="28" y="4" width="10" height="8" rx="2" fill="#4a4a80" />
      <rect x="40" y="4" width="4" height="8" rx="1" fill="#4a4a80" opacity=".5" />
      <rect x="4" y="15" width="10" height="8" rx="2" fill="#4a4a80" />
      <rect x="16" y="15" width="10" height="8" rx="2" fill="#4a4a80" />
      <rect x="28" y="15" width="10" height="8" rx="2" fill="#4a4a80" />
      <rect x="40" y="15" width="4" height="8" rx="1" fill="#4a4a80" opacity=".5" />
      <rect x="4" y="26" width="10" height="5" rx="2" fill="#4a4a80" />
      <rect x="16" y="26" width="10" height="5" rx="2" fill="#4a4a80" />
      <rect x="28" y="26" width="10" height="5" rx="2" fill="#4a4a80" />
    </svg>
  ),
  masonry: (
    <svg width="46" height="34" viewBox="0 0 46 34">
      <rect width="46" height="34" rx="3" fill="#15152a" stroke="#32325a" />
      <rect x="4" y="4" width="8" height="14" rx="2" fill="#f5a623" opacity=".75" />
      <rect x="4" y="20" width="8" height="10" rx="2" fill="#4a4a80" />
      <rect x="14" y="4" width="8" height="9" rx="2" fill="#4a4a80" />
      <rect x="14" y="15" width="8" height="15" rx="2" fill="#4a4a80" />
      <rect x="24" y="4" width="8" height="16" rx="2" fill="#4a4a80" />
      <rect x="24" y="22" width="8" height="8" rx="2" fill="#4a4a80" />
      <rect x="34" y="4" width="8" height="11" rx="2" fill="#4a4a80" />
      <rect x="34" y="17" width="8" height="13" rx="2" fill="#4a4a80" />
    </svg>
  ),
};

export default function MacroSelector({
  value,
  onChange,
}: {
  value: Macrostructure;
  onChange: (m: Macrostructure) => void;
}) {
  const [hoveredId, setHoveredId] = useState<Macrostructure | null>(null);

  return (
    <div style={s.wrap}>
      <p style={s.instructions}>
        Elegí el esqueleto de tu home. No cambia solo el color — cambia cómo se
        ordena todo.
      </p>

      {MACRO_OPTIONS.map((opt) => {
        const isOn = value === opt.id;
        const isHover = hoveredId === opt.id;

        return (
          <button
            key={opt.id}
            type="button"
            aria-pressed={isOn}
            onClick={() => onChange(opt.id)}
            onMouseEnter={() => setHoveredId(opt.id)}
            onMouseLeave={() => setHoveredId((h) => (h === opt.id ? null : h))}
            style={{
              ...s.card,
              borderColor: isOn ? '#f5a623' : isHover ? '#4a4a80' : '#32325a',
              background: isOn ? '#f5a6230f' : '#20203c',
              boxShadow: isOn ? '0 0 0 1px #f5a623 inset' : 'none',
            }}
          >
            {MACRO_ICONS[opt.id]}

            <span style={s.textBlock}>
              <span style={s.nameRow}>
                <span style={s.name}>{opt.label}</span>
                <span style={opt.tag === 'exist' ? s.tagExist : s.tagNew}>
                  {opt.tag === 'exist' ? 'YA EXISTE' : 'NUEVO'}
                </span>
              </span>
              <span style={s.desc}>{opt.desc}</span>
              <span style={s.fit}>{opt.fit}</span>
            </span>

            {isOn ? <span style={s.editBadge}>EDITANDO</span> : null}
          </button>
        );
      })}
    </div>
  );
}

const s: Record<string, CSSProperties> = {
  wrap: { display: 'flex', flexDirection: 'column', gap: 8 },
  instructions: { fontSize: 11, color: '#9aa2b1', marginBottom: 8, lineHeight: 1.5 },
  card: {
    display: 'flex',
    gap: 12,
    alignItems: 'flex-start',
    border: '1px solid #32325a',
    background: '#20203c',
    borderRadius: 10,
    padding: '8px 12px',
    cursor: 'pointer',
    transition: '.15s',
    textAlign: 'left',
    color: '#e8eaed',
    font: 'inherit',
  },
  textBlock: { minWidth: 0, flex: 1 },
  nameRow: { display: 'flex', alignItems: 'center', gap: 8, fontSize: 13, fontWeight: 700 },
  name: { color: '#e8eaed' },
  tagExist: {
    fontSize: 11,
    fontWeight: 800,
    borderRadius: 6,
    padding: '4px 8px',
    letterSpacing: '.4px',
    background: '#2e7d5b33',
    color: '#6ee7b7',
    border: '1px solid #2e7d5b',
  },
  tagNew: {
    fontSize: 11,
    fontWeight: 800,
    borderRadius: 6,
    padding: '4px 8px',
    letterSpacing: '.4px',
    background: '#f5a62322',
    color: '#f5a623',
    border: '1px solid #f5a62366',
  },
  desc: { display: 'block', fontSize: 11, color: '#9aa2b1', marginTop: 4, lineHeight: 1.45 },
  fit: { display: 'block', fontSize: 11, color: '#8fd3b0', marginTop: 6 },
  editBadge: {
    flexShrink: 0,
    marginLeft: 'auto',
    fontSize: 11,
    fontWeight: 800,
    background: '#f5a623',
    color: '#1a1a2e',
    borderRadius: 5,
    padding: '4px 8px',
  },
};
