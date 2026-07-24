import { useEffect, useState } from 'react';
import type { CSSProperties } from 'react';
import AssetUploadField from '@/components/panel/AssetUploadField';
import { NumberField, SelectField, TextField } from '@/components/panel/PanelPrimitives';
import { listCategories } from '@/services/shop-api';
import type {
  BenefitsSection,
  CarouselSection,
  CarouselSource,
  DuoBannersSection,
  HeroSection,
  NewsletterSection,
  SectionConfig,
  SectionType,
  ShopCategory,
} from '@/types/shop';

// 섹션 추가/삭제는 지원하지 않는다 — sections 는 SPEC 스키마상 7종 고정 슬롯이며
// 이 컴포넌트는 순서(▲▼)와 표시 여부(👁)만 바꾼다. 타입별 콘텐츠는 펼침 시 인라인 편집한다.

const TYPE_LABELS: Record<SectionType, string> = {
  hero: 'Portada (Hero)',
  benefits: 'Beneficios',
  carousel: 'Carrusel de productos',
  duoBanners: 'Banners dobles',
  newsletter: 'Newsletter',
  reels: 'Reels de video',
  quiz: 'Quiz — asesor guiado',
};

function updateAt<T extends SectionConfig>(
  list: SectionConfig[],
  i: number,
  patch: Partial<T>,
): SectionConfig[] {
  return list.map((s, k) => (k === i ? ({ ...s, ...patch } as SectionConfig) : s));
}

export default function SectionListEditor({
  sections,
  onChange,
  storeId,
  token,
  disabledTypes,
}: {
  sections: SectionConfig[];
  onChange: (next: SectionConfig[]) => void;
  storeId: number;
  token: string;
  disabledTypes?: SectionType[];
}) {
  const [openIdx, setOpenIdx] = useState<number | null>(null);
  const [categories, setCategories] = useState<ShopCategory[]>([]);
  const [categoriesError, setCategoriesError] = useState(false);

  useEffect(() => {
    let alive = true;
    listCategories(storeId)
      .then((cats) => {
        if (alive) setCategories(cats);
      })
      .catch(() => {
        if (alive) setCategoriesError(true);
      });

    return () => {
      alive = false;
    };
  }, [storeId]);

  const onMove = (i: number, dir: -1 | 1) => {
    const j = i + dir;
    if (j < 0 || j >= sections.length) return;
    const next = [...sections];
    [next[i], next[j]] = [next[j], next[i]];
    onChange(next);
  };

  const onToggle = (i: number) => {
    onChange(sections.map((s, k) => (k === i ? { ...s, enabled: !s.enabled } : s)));
  };

  function renderFields(s: SectionConfig, i: number) {
    switch (s.type) {
      case 'hero': {
        const sec = s;
        const update = (patch: Partial<HeroSection>) =>
          onChange(updateAt(sections, i, patch));

        return (
          <div style={st.fieldsCol}>
            <TextField
              label="Título"
              value={sec.title}
              maxLength={200}
              onChange={(v) => update({ title: v })}
            />
            <TextField
              label="Subtítulo"
              value={sec.subtitle}
              maxLength={200}
              onChange={(v) => update({ subtitle: v })}
            />
            <TextField
              label="Texto del botón"
              value={sec.cta}
              maxLength={40}
              onChange={(v) => update({ cta: v })}
            />
            {sec.images.map((img, imgIdx) => (
              <div key={img} style={st.itemRow}>
                <span style={st.itemName}>{img}</span>
                <button
                  type="button"
                  style={st.removeBtn}
                  onClick={() =>
                    update({ images: sec.images.filter((_, k) => k !== imgIdx) })
                  }
                >
                  ✕
                </button>
              </div>
            ))}
            {sec.images.length < 5 ? (
              <AssetUploadField
                storeId={storeId}
                token={token}
                kind="hero"
                value={null}
                onChange={(fileName) => {
                  if (fileName) update({ images: [...sec.images, fileName] });
                }}
                label={`Imagen del hero (${sec.images.length}/5)`}
                accept="image/png,image/jpeg,image/webp"
              />
            ) : null}
          </div>
        );
      }
      case 'benefits': {
        const sec = s;
        const update = (patch: Partial<BenefitsSection>) =>
          onChange(updateAt(sections, i, patch));

        return (
          <div style={st.fieldsCol}>
            {sec.items.map((item, idx) => (
              <div key={idx} style={st.itemRow}>
                <div style={st.emojiField}>
                  <TextField
                    label="Emoji"
                    value={item.icon}
                    maxLength={8}
                    onChange={(v) => {
                      const items = sec.items.map((it, k) =>
                        k === idx ? { ...it, icon: v } : it,
                      );
                      update({ items });
                    }}
                  />
                </div>
                <div style={st.textFieldFlex}>
                  <TextField
                    label="Texto"
                    value={item.text}
                    maxLength={200}
                    onChange={(v) => {
                      const items = sec.items.map((it, k) =>
                        k === idx ? { ...it, text: v } : it,
                      );
                      update({ items });
                    }}
                  />
                </div>
                <button
                  type="button"
                  style={st.removeBtn}
                  onClick={() => update({ items: sec.items.filter((_, k) => k !== idx) })}
                >
                  ✕
                </button>
              </div>
            ))}
            {sec.items.length < 6 ? (
              <button
                type="button"
                style={st.addBtn}
                onClick={() =>
                  update({ items: [...sec.items, { icon: '', text: '' }] })
                }
              >
                + Agregar beneficio
              </button>
            ) : null}
          </div>
        );
      }
      case 'carousel': {
        const sec = s;
        const update = (patch: Partial<CarouselSection>) =>
          onChange(updateAt(sections, i, patch));

        return (
          <div style={st.fieldsCol}>
            <TextField
              label="Título"
              value={sec.title}
              maxLength={80}
              onChange={(v) => update({ title: v })}
            />
            <SelectField
              label="Fuente"
              value={sec.source}
              onChange={(v) => update({ source: v as CarouselSource })}
              options={[
                { value: 'newest', label: 'Más nuevos' },
                { value: 'bestseller', label: 'Más vendidos' },
                { value: 'category', label: 'Categoría' },
              ]}
            />
            {sec.source === 'category' ? (
              categoriesError ? (
                <NumberField
                  label="ID de categoría"
                  value={sec.categoryId ?? 0}
                  min={0}
                  onChange={(v) => update({ categoryId: v })}
                />
              ) : (
                <SelectField
                  label="Categoría"
                  value={sec.categoryId != null ? String(sec.categoryId) : ''}
                  onChange={(v) => update({ categoryId: v ? Number(v) : null })}
                  options={[
                    { value: '', label: 'Elegí una categoría' },
                    ...categories.map((c) => ({ value: String(c.id), label: c.name })),
                  ]}
                />
              )
            ) : null}
          </div>
        );
      }
      case 'duoBanners': {
        const sec = s;
        const update = (patch: Partial<DuoBannersSection>) =>
          onChange(updateAt(sections, i, patch));

        return (
          <div style={st.fieldsCol}>
            {sec.banners.map((b, idx) => (
              <div key={idx} style={st.bannerBlock}>
                <AssetUploadField
                  storeId={storeId}
                  token={token}
                  kind="banner"
                  value={b.image}
                  onChange={(fileName) => {
                    const banners = sec.banners.map((bb, k) =>
                      k === idx ? { ...bb, image: fileName } : bb,
                    );
                    update({ banners });
                  }}
                  label={`Banner ${idx + 1} — imagen`}
                  accept="image/png,image/jpeg,image/webp"
                />
                <TextField
                  label="Título"
                  value={b.title}
                  maxLength={200}
                  onChange={(v) => {
                    const banners = sec.banners.map((bb, k) =>
                      k === idx ? { ...bb, title: v } : bb,
                    );
                    update({ banners });
                  }}
                />
                <TextField
                  label="Subtítulo"
                  value={b.subtitle}
                  maxLength={200}
                  onChange={(v) => {
                    const banners = sec.banners.map((bb, k) =>
                      k === idx ? { ...bb, subtitle: v } : bb,
                    );
                    update({ banners });
                  }}
                />
                <TextField
                  label="Link"
                  value={b.href ?? ''}
                  maxLength={500}
                  placeholder="https://... o /ruta"
                  onChange={(v) => {
                    const banners = sec.banners.map((bb, k) =>
                      k === idx ? { ...bb, href: v || null } : bb,
                    );
                    update({ banners });
                  }}
                />
                <button
                  type="button"
                  style={st.addBtn}
                  onClick={() =>
                    update({ banners: sec.banners.filter((_, k) => k !== idx) })
                  }
                >
                  ✕ Quitar banner
                </button>
              </div>
            ))}
            {sec.banners.length < 2 ? (
              <button
                type="button"
                style={st.addBtn}
                onClick={() =>
                  update({
                    banners: [
                      ...sec.banners,
                      { image: null, title: '', subtitle: '', href: null },
                    ],
                  })
                }
              >
                + Agregar banner
              </button>
            ) : null}
          </div>
        );
      }
      case 'newsletter': {
        const sec = s;
        const update = (patch: Partial<NewsletterSection>) =>
          onChange(updateAt(sections, i, patch));

        return (
          <div style={st.fieldsCol}>
            <TextField
              label="Título"
              value={sec.title}
              maxLength={120}
              onChange={(v) => update({ title: v })}
            />
          </div>
        );
      }
      case 'reels':
        // TODO(Plan 61-11): reels 편집 서브폼
        return null;
      case 'quiz':
        // TODO(Plan 61-14): quiz 편집 서브폼
        return null;
      default:
        return null;
    }
  }

  if (sections.length === 0) {
    return (
      <div style={st.empty}>
        <div style={st.emptyH}>Todavía no hay secciones</div>
        <div style={st.emptyP}>
          Guardá el borrador para restaurar las secciones por defecto.
        </div>
      </div>
    );
  }

  return (
    <div style={st.list}>
      {sections.map((s, i) => {
        const isDisabled = disabledTypes?.includes(s.type) ?? false;
        const isOpen = openIdx === i;

        return (
          <div key={s.type} style={{ ...st.row, opacity: isDisabled ? 0.45 : 1 }}>
            <div style={st.rowHead}>
              <span style={st.order}>{i + 1}</span>
              <span
                style={{
                  ...st.typeLabel,
                  textDecoration: isDisabled ? 'line-through' : 'none',
                }}
              >
                {TYPE_LABELS[s.type]}
              </span>
              <div style={st.moveCol}>
                <button
                  type="button"
                  disabled={i === 0}
                  style={{ ...st.moveBtn, opacity: i === 0 ? 0.3 : 1 }}
                  onClick={() => onMove(i, -1)}
                >
                  ▲
                </button>
                <button
                  type="button"
                  disabled={i === sections.length - 1}
                  style={{
                    ...st.moveBtn,
                    opacity: i === sections.length - 1 ? 0.3 : 1,
                  }}
                  onClick={() => onMove(i, 1)}
                >
                  ▼
                </button>
              </div>
              <button
                type="button"
                style={st.eyeBtn}
                onClick={() => onToggle(i)}
                aria-label={s.enabled ? 'Ocultar sección' : 'Mostrar sección'}
              >
                {s.enabled ? '👁' : '🚫'}
              </button>
              <button
                type="button"
                style={st.expandBtn}
                onClick={() => setOpenIdx(isOpen ? null : i)}
              >
                <span
                  style={{
                    display: 'inline-block',
                    transition: 'transform .2s',
                    transform: isOpen ? 'rotate(90deg)' : 'none',
                  }}
                >
                  ›
                </span>
              </button>
            </div>
            {isOpen ? <div style={st.rowBody}>{renderFields(s, i)}</div> : null}
          </div>
        );
      })}
    </div>
  );
}

const st: Record<string, CSSProperties> = {
  list: { display: 'flex', flexDirection: 'column', gap: 6 },
  row: {
    background: '#1a1a2e',
    border: '1px solid #32325a',
    borderRadius: 8,
    padding: 8,
  },
  rowHead: { display: 'flex', alignItems: 'center', gap: 8 },
  order: { fontSize: 11, color: '#9aa2b1', width: 14, flexShrink: 0 },
  typeLabel: { fontSize: 12.5, color: '#e8eaed', flex: 1 },
  moveCol: { display: 'flex', flexDirection: 'column', gap: 4 },
  moveBtn: {
    background: 'transparent',
    border: 0,
    color: '#9aa2b1',
    cursor: 'pointer',
    fontSize: 10,
    lineHeight: 1,
    padding: 2,
  },
  eyeBtn: {
    background: 'transparent',
    border: 0,
    color: '#9aa2b1',
    cursor: 'pointer',
    fontSize: 14,
    padding: 4,
  },
  expandBtn: {
    background: 'transparent',
    border: 0,
    color: '#9aa2b1',
    cursor: 'pointer',
    fontSize: 14,
    padding: 4,
  },
  rowBody: {
    marginTop: 8,
    paddingTop: 8,
    borderTop: '1px solid #32325a',
    display: 'flex',
    flexDirection: 'column',
    gap: 12,
  },
  fieldsCol: { display: 'flex', flexDirection: 'column', gap: 12 },
  itemRow: { display: 'flex', alignItems: 'flex-end', gap: 8 },
  emojiField: { width: 56, flexShrink: 0 },
  textFieldFlex: { flex: 1 },
  itemName: {
    fontSize: 11,
    color: '#e8eaed',
    flex: 1,
    wordBreak: 'break-all',
  },
  bannerBlock: {
    display: 'flex',
    flexDirection: 'column',
    gap: 8,
    border: '1px solid #32325a',
    borderRadius: 8,
    padding: 8,
  },
  removeBtn: {
    background: 'transparent',
    border: 0,
    color: '#9aa2b1',
    cursor: 'pointer',
    fontSize: 13,
    padding: '0 4px',
  },
  addBtn: {
    border: '1.5px dashed #32325a',
    borderRadius: 8,
    padding: 8,
    textAlign: 'center',
    color: '#9aa2b1',
    fontSize: 11,
    cursor: 'pointer',
    background: 'transparent',
  },
  empty: {
    border: '1px dashed #32325a',
    borderRadius: 8,
    padding: 16,
    textAlign: 'center',
  },
  emptyH: { fontSize: 13, color: '#e8eaed', fontWeight: 700 },
  emptyP: { fontSize: 11, color: '#9aa2b1', marginTop: 4 },
};
