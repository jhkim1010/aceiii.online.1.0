import { useEffect, useState } from 'react';
import type { CSSProperties } from 'react';
import {
  HintBanner,
  NumberField,
  SelectField,
  SwitchField,
  TextField,
  WarnBanner,
} from '@/components/panel/PanelPrimitives';
import { listCategories } from '@/services/shop-api';
import type {
  CarouselSource,
  MacroSettings,
  Macrostructure,
  RailShelf,
  ShopCategory,
} from '@/types/shop';

const SOURCE_LABELS: Record<CarouselSource, string> = {
  newest: 'Más nuevos',
  bestseller: 'Más vendidos',
  category: 'Categoría',
};

const MAX_SHELVES = 6;

function newShelf(): RailShelf {
  return { title: 'Nuevo estante', source: 'newest', categoryId: null, limit: 10 };
}

export default function StructureFieldsEditor({
  macro,
  macroSettings,
  onChange,
  storeId,
}: {
  macro: Macrostructure;
  macroSettings: MacroSettings;
  onChange: (next: MacroSettings) => void;
  storeId: number;
}) {
  const [categories, setCategories] = useState<ShopCategory[]>([]);
  const [categoriesError, setCategoriesError] = useState(false);
  const [openShelf, setOpenShelf] = useState<number | null>(null);

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

  const updateRails = (patch: Partial<MacroSettings['rails']>) =>
    onChange({ ...macroSettings, rails: { ...macroSettings.rails, ...patch } });

  const updateMasonry = (patch: Partial<MacroSettings['masonry']>) =>
    onChange({ ...macroSettings, masonry: { ...macroSettings.masonry, ...patch } });

  const updateShelf = (idx: number, patch: Partial<RailShelf>) => {
    const shelves = macroSettings.rails.shelves.map((sh, k) =>
      k === idx ? { ...sh, ...patch } : sh,
    );
    updateRails({ shelves });
  };

  const moveShelf = (idx: number, dir: -1 | 1) => {
    const j = idx + dir;
    const shelves = macroSettings.rails.shelves;
    if (j < 0 || j >= shelves.length) return;
    const next = [...shelves];
    [next[idx], next[j]] = [next[j], next[idx]];
    updateRails({ shelves: next });
  };

  const removeShelf = (idx: number) => {
    updateRails({ shelves: macroSettings.rails.shelves.filter((_, k) => k !== idx) });
    setOpenShelf((o) => (o === idx ? null : o));
  };

  const addShelf = () => {
    if (macroSettings.rails.shelves.length >= MAX_SHELVES) return;
    updateRails({ shelves: [...macroSettings.rails.shelves, newShelf()] });
  };

  if (macro === 'marquee') {
    return (
      <div style={st.col}>
        <HintBanner>
          El orden de las secciones de abajo se edita en «Secciones de la home».
        </HintBanner>
        <p style={st.subInfo}>
          El título, subtítulo, botón e imágenes de la portada se editan en la
          sección «Portada (Hero)».
        </p>
      </div>
    );
  }

  if (macro === 'bento') {
    return (
      <div style={st.col}>
        <WarnBanner>
          Bento reemplaza al hero: la baldosa destacada cumple esa función. Si
          activás hero igual, queda duplicado.
        </WarnBanner>
      </div>
    );
  }

  if (macro === 'rails') {
    const { shelves, showArrows, lazyRows } = macroSettings.rails;

    return (
      <div style={st.col}>
        <div style={st.list}>
          {shelves.map((shelf, idx) => {
            const isOpen = openShelf === idx;

            return (
              <div key={idx} style={st.row}>
                <div style={st.rowHead}>
                  <div style={st.h}>
                    <b style={st.hName}>{shelf.title}</b>
                    <span style={st.hSub}>
                      {SOURCE_LABELS[shelf.source]} · {shelf.limit} productos
                    </span>
                  </div>
                  <div style={st.ord}>
                    <button
                      type="button"
                      disabled={idx === 0}
                      style={{ ...st.ordBtn, opacity: idx === 0 ? 0.3 : 1 }}
                      onClick={() => moveShelf(idx, -1)}
                      aria-label="Subir estante"
                    >
                      ▲
                    </button>
                    <button
                      type="button"
                      disabled={idx === shelves.length - 1}
                      style={{
                        ...st.ordBtn,
                        opacity: idx === shelves.length - 1 ? 0.3 : 1,
                      }}
                      onClick={() => moveShelf(idx, 1)}
                      aria-label="Bajar estante"
                    >
                      ▼
                    </button>
                  </div>
                  <button
                    type="button"
                    style={st.delBtn}
                    onClick={() => removeShelf(idx)}
                    aria-label="Eliminar estante"
                  >
                    ✕
                  </button>
                  <button
                    type="button"
                    style={st.expandBtn}
                    onClick={() => setOpenShelf(isOpen ? null : idx)}
                    aria-label={isOpen ? 'Contraer estante' : 'Editar estante'}
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

                {isOpen ? (
                  <div style={st.rowBody}>
                    <TextField
                      label="Título"
                      value={shelf.title}
                      maxLength={40}
                      onChange={(v) => updateShelf(idx, { title: v })}
                    />
                    <SelectField
                      label="Origen"
                      value={shelf.source}
                      onChange={(v) =>
                        updateShelf(idx, { source: v as CarouselSource })
                      }
                      options={[
                        { value: 'newest', label: 'Más nuevos' },
                        { value: 'bestseller', label: 'Más vendidos' },
                        { value: 'category', label: 'Categoría' },
                      ]}
                    />
                    {shelf.source === 'category' ? (
                      categoriesError ? (
                        <NumberField
                          label="ID de categoría"
                          value={shelf.categoryId ?? 0}
                          min={0}
                          onChange={(v) => updateShelf(idx, { categoryId: v })}
                        />
                      ) : (
                        <SelectField
                          label="Categoría"
                          value={
                            shelf.categoryId != null ? String(shelf.categoryId) : ''
                          }
                          onChange={(v) =>
                            updateShelf(idx, {
                              categoryId: v ? Number(v) : null,
                            })
                          }
                          options={[
                            { value: '', label: 'Elegí una categoría' },
                            ...categories.map((c) => ({
                              value: String(c.id),
                              label: c.name,
                            })),
                          ]}
                        />
                      )
                    ) : null}
                    <NumberField
                      label="Productos por fila"
                      value={shelf.limit}
                      min={4}
                      max={20}
                      step={1}
                      onChange={(v) => updateShelf(idx, { limit: v })}
                    />
                  </div>
                ) : null}
              </div>
            );
          })}
        </div>

        <button
          type="button"
          style={{
            ...st.addBtn,
            opacity: shelves.length >= MAX_SHELVES ? 0.4 : 1,
            cursor: shelves.length >= MAX_SHELVES ? 'default' : 'pointer',
          }}
          disabled={shelves.length >= MAX_SHELVES}
          onClick={addShelf}
        >
          + Agregar estante
        </button>

        <SwitchField
          label="Flechas ‹ › en escritorio"
          checked={showArrows}
          onChange={(v) => updateRails({ showArrows: v })}
        />
        <SwitchField
          label="Cargar cada estante al llegar"
          checked={lazyRows}
          hint="Más liviano en el celular."
          onChange={(v) => updateRails({ lazyRows: v })}
        />

        <WarnBanner>
          Con Rails, la sección «Carrusel» queda absorbida por los estantes — se
          deshabilita sola.
        </WarnBanner>
        <HintBanner>
          Cada estante es una consulta al catálogo que ya existe — sin consultas
          nuevas al servidor.
        </HintBanner>
      </div>
    );
  }

  // masonry
  const ms = macroSettings.masonry;

  return (
    <div style={st.col}>
      <div style={st.row2}>
        <SelectField
          label="Columnas en escritorio"
          value={String(ms.desktopCols)}
          onChange={(v) =>
            updateMasonry({ desktopCols: Number(v) as 3 | 4 | 5 })
          }
          options={[
            { value: '3', label: '3' },
            { value: '4', label: '4' },
            { value: '5', label: '5' },
          ]}
        />
        <SelectField
          label="Columnas en celular"
          value={String(ms.mobileCols)}
          onChange={(v) => updateMasonry({ mobileCols: Number(v) as 1 | 2 })}
          options={[
            { value: '2', label: '2' },
            { value: '1', label: '1' },
          ]}
        />
      </div>
      <NumberField
        label="Productos en la primera carga"
        value={ms.firstLoad}
        min={12}
        max={48}
        step={4}
        onChange={(v) => updateMasonry({ firstLoad: v })}
      />
      <SwitchField
        label="Respetar la proporción original de la foto"
        checked={ms.keepRatio}
        onChange={(v) => updateMasonry({ keepRatio: v })}
      />
      <SwitchField
        label="Barra de filtros fija arriba"
        checked={ms.stickyFilter}
        onChange={(v) => updateMasonry({ stickyFilter: v })}
      />
      <SwitchField
        label="Mostrar nombre y precio sobre la foto"
        checked={ms.showOverlayInfo}
        onChange={(v) => updateMasonry({ showOverlayInfo: v })}
      />

      <WarnBanner>
        Masonry luce mal con fotos recortadas en cuadrado. Si tu catálogo es
        cuadrado, mejor Marquee o Rails.
      </WarnBanner>
      <HintBanner>
        Beneficios y banners duo se deshabilitan: cortan la grilla y rompen el
        ritmo visual.
      </HintBanner>
      <HintBanner>
        El orden en Masonry se ve por columna (izquierda a derecha), no fila por
        fila.
      </HintBanner>
    </div>
  );
}

const st: Record<string, CSSProperties> = {
  col: { display: 'flex', flexDirection: 'column', gap: 12 },
  subInfo: { fontSize: 11, color: '#9aa2b1', lineHeight: 1.5, margin: 0 },
  row2: { display: 'flex', gap: 12 },
  list: { display: 'flex', flexDirection: 'column', gap: 8 },
  row: {
    background: '#1a1a2e',
    border: '1px solid #32325a',
    borderRadius: 8,
    padding: 8,
  },
  rowHead: { display: 'flex', alignItems: 'center', gap: 8 },
  h: { flex: 1, minWidth: 0 },
  hName: {
    display: 'block',
    fontSize: 13,
    fontWeight: 700,
    color: '#e8eaed',
    whiteSpace: 'nowrap',
    overflow: 'hidden',
    textOverflow: 'ellipsis',
  },
  hSub: { display: 'block', fontSize: 11, color: '#9aa2b1', marginTop: 2 },
  ord: { display: 'flex', flexDirection: 'column', gap: 4 },
  ordBtn: {
    background: 'transparent',
    border: '1px solid #32325a',
    color: '#9aa2b1',
    borderRadius: 5,
    cursor: 'pointer',
    fontSize: 10,
    lineHeight: 1,
    padding: '2px 5px',
  },
  delBtn: {
    background: 'transparent',
    border: '1px solid #32325a',
    color: '#9aa2b1',
    borderRadius: 5,
    cursor: 'pointer',
    fontSize: 12,
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
  addBtn: {
    background: 'transparent',
    border: '1px dashed #32325a',
    color: '#9aa2b1',
    borderRadius: 8,
    padding: 8,
    fontSize: 12.5,
    textAlign: 'center',
  },
};
