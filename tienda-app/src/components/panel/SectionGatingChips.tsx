import type { CSSProperties } from 'react';
import { GATED_BY_MACRO } from '@/lib/theme-preset';
import type { Macrostructure, SectionType } from '@/types/shop';

// SectionListEditor.tsx 의 스페인어 라벨과 동일 문구 유지(중복 정의지만 값은 반드시 일치).
const SECTION_LABELS: Record<SectionType, string> = {
  hero: 'Portada (Hero)',
  benefits: 'Beneficios',
  carousel: 'Carrusel de productos',
  duoBanners: 'Banners dobles',
  newsletter: 'Newsletter',
  reels: 'Reels de video',
  quiz: 'Quiz — asesor guiado',
};

const ALL_TYPES: SectionType[] = [
  'hero',
  'benefits',
  'carousel',
  'duoBanners',
  'newsletter',
  'reels',
  'quiz',
];

// 이 컴포넌트는 읽기 전용 안내다 — sections[].enabled 를 절대 변경하지 않는다.
// 현재 구조에서 비활성인 섹션 타입을 취소선+흐림으로 보여줄 뿐이다.
export default function SectionGatingChips({ macro }: { macro: Macrostructure }) {
  const gated = GATED_BY_MACRO[macro] ?? [];

  return (
    <div style={st.wrap}>
      <p style={st.intro}>
        Las secciones que no aplican quedan deshabilitadas — no se borran, se guardan por si cambiás de estructura.
      </p>
      <div style={st.chips}>
        {ALL_TYPES.map((t) => {
          const isDisabled = gated.includes(t);

          return (
            <span
              key={t}
              style={{
                ...st.chip,
                ...(isDisabled ? st.chipOff : st.chipOn),
              }}
            >
              {SECTION_LABELS[t]}
            </span>
          );
        })}
      </div>
    </div>
  );
}

const st: Record<string, CSSProperties> = {
  wrap: { display: 'flex', flexDirection: 'column', gap: 8 },
  intro: { fontSize: 11, color: '#9aa2b1', lineHeight: 1.5, margin: 0 },
  chips: { display: 'flex', flexWrap: 'wrap', gap: 8, marginTop: 8 },
  chip: {
    fontSize: 11,
    borderRadius: 999,
    padding: '4px 12px',
    border: '1px solid #32325a',
    color: '#9aa2b1',
    background: '#20203c',
  },
  chipOn: {
    borderColor: '#2e7d5b',
    color: '#6ee7b7',
    background: '#2e7d5b1f',
  },
  chipOff: {
    opacity: 0.45,
    textDecoration: 'line-through',
  },
};
