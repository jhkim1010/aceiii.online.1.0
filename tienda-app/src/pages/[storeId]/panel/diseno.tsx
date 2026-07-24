import { useCallback, useEffect, useMemo, useState } from 'react';
import type { CSSProperties } from 'react';
import Head from 'next/head';
import { useRouter } from 'next/router';
import MasonryLayout from '@/components/macro/MasonryLayout';
import RailsLayout from '@/components/macro/RailsLayout';
import AssetUploadField from '@/components/panel/AssetUploadField';
import MacroSelector from '@/components/panel/MacroSelector';
import {
  AccordionGroup,
  NumberField,
  SelectField,
  SwitchField,
  TextField,
} from '@/components/panel/PanelPrimitives';
import SectionGatingChips from '@/components/panel/SectionGatingChips';
import SectionListEditor from '@/components/panel/SectionListEditor';
import StructureFieldsEditor from '@/components/panel/StructureFieldsEditor';
import Header from '@/components/Header';
import SectionRenderer from '@/components/sections/SectionRenderer';
import { ThemeContentProvider } from '@/context/ThemeContentContext';
import {
  getThemeDraft,
  publishTheme,
  saveThemeDraft,
} from '@/services/shop-api';
import type {
  CatalogSort,
  FontPair,
  HeroSection,
  Macrostructure,
  PaperBand,
  ShopProduct,
  StoreThemeContent,
  StoreThemeTokens,
} from '@/types/shop';
import {
  DEFAULT_CONTENT,
  DEFAULT_TOKENS,
  GATED_BY_MACRO,
  GENRE_LABELS,
  MACRO_OPTIONS,
  THEME_PRESETS,
  tokensToCssVars,
} from '@/lib/theme-preset';

// 그룹 2 제목("Ajustes de {구조명}")·미리보기 상단 바에 쓰는 구조명 라벨 — MACRO_OPTIONS 에서 파생.
const MACRO_LABEL: Record<Macrostructure, string> = Object.fromEntries(
  MACRO_OPTIONS.map((o) => [o.id, o.label]),
) as Record<Macrostructure, string>;

// 미리보기 상단 바 우측 힌트 — 구조별 hint 카피(UI-SPEC 미리보기 연동 절).
const MACRO_PREVIEW_HINTS: Record<Macrostructure, string> = {
  marquee: 'El orden de las secciones de abajo se edita en «Secciones de la home».',
  bento: 'La baldosa destacada cumple la función del hero.',
  rails:
    'Cada estante es una consulta al catálogo que ya existe — sin consultas nuevas al servidor.',
  masonry: 'El orden en Masonry se ve por columna, no fila por fila.',
};

// 미리보기용 더미 상품 — carousel 섹션의 initialItems 로 전달해 실제 API 호출 없이
// 실제 ProductCard 컴포넌트로 렌더한다(T-61-43: 편집마다 카탈로그 조회 금지).
const DUMMY: ShopProduct[] = [1, 2, 3].map((n) => ({
  id: -n,
  name: `Producto de ejemplo ${n}`,
  slug: null,
  description: null,
  longDescription: null,
  price: 12000 + n * 3500,
  priceOrig: null,
  stock: null,
  imageUrl: null,
  imageUrls: null,
  gender: null,
  material: null,
  categoryId: null,
}));

type SaveState = 'idle' | 'saving' | 'saved' | 'publishing' | 'published' | 'error';

export default function DisenoPage() {
  const router = useRouter();
  const storeId = Number(router.query.storeId);
  const token = typeof router.query.t === 'string' ? router.query.t : '';

  const [baseTheme, setBaseTheme] = useState('Studio');
  const [macro, setMacro] = useState<Macrostructure>('marquee');
  const [tokens, setTokens] = useState<StoreThemeTokens>(DEFAULT_TOKENS);
  // 이 플랜은 content 편집 UI 를 다루지 않는다(Plan 61-08/61-11 범위) — 로드된 초안의
  // content 를 그대로 보존해 색/레이아웃만 저장해도 기존 섹션 설정이 유실되지 않게 한다.
  const [content, setContent] = useState<StoreThemeContent>(DEFAULT_CONTENT);
  const [state, setState] = useState<SaveState>('idle');
  const [msg, setMsg] = useState<string>('');
  const [loaded, setLoaded] = useState(false);

  // 초안 로드
  useEffect(() => {
    if (!router.isReady) return;
    if (!token || !storeId) {
      setLoaded(true);

      return;
    }

    let alive = true;
    getThemeDraft(storeId, token)
      .then((t) => {
        if (!alive) return;
        setBaseTheme(t.baseTheme || 'Studio');
        setMacro(t.macrostructure || 'marquee');
        setTokens({ ...DEFAULT_TOKENS, ...t.tokens });
        setContent(t.content ?? DEFAULT_CONTENT);
      })
      .catch((e: Error) => {
        if (!alive) return;
        setMsg(`No se pudo cargar el borrador: ${e.message}`);
      })
      .finally(() => alive && setLoaded(true));

    return () => {
      alive = false;
    };
  }, [router.isReady, storeId, token]);

  const patch = useCallback((p: Partial<StoreThemeTokens>) => {
    setTokens((prev) => ({ ...prev, ...p }));
    setState('idle');
  }, []);

  const patchContent = useCallback((p: Partial<StoreThemeContent>) => {
    setContent((prev) => ({ ...prev, ...p }));
    setState('idle');
  }, []);

  const applyPreset = useCallback((id: string) => {
    const preset = THEME_PRESETS.find((p) => p.id === id);
    if (!preset) return;
    setBaseTheme(id);
    setTokens(preset.tokens);
    setState('idle');
  }, []);

  const cssVars = useMemo(() => tokensToCssVars(tokens), [tokens]);

  // 구조에 맞지 않는 섹션은 미리보기에서도 렌더만 생략한다(값은 JSONB 에 그대로 보존).
  // index.tsx(Plan 61-09)와 동일한 게이팅 규칙 — GATED_BY_MACRO 단일 소유지에서 import.
  const gatedTypes = GATED_BY_MACRO[macro] ?? [];
  const visibleSections = content.sections.filter(
    (sec) => !gatedTypes.includes(sec.type),
  );
  const previewHeroSection = visibleSections.find(
    (sec) => sec.type === 'hero',
  ) as HeroSection | undefined;

  const onSave = useCallback(async () => {
    setState('saving');
    try {
      await saveThemeDraft(storeId, token, {
        baseTheme,
        macrostructure: macro,
        tokens,
        content,
      });
      setState('saved');
      setMsg('Borrador guardado (todavía no está publicado).');
    } catch (e) {
      setState('error');
      setMsg(`No se pudo guardar el borrador: ${(e as Error).message}`);
    }
  }, [storeId, token, baseTheme, macro, tokens, content]);

  const onPublish = useCallback(async () => {
    setState('publishing');
    try {
      // 발행 전 최신 초안 저장 후 발행
      await saveThemeDraft(storeId, token, {
        baseTheme,
        macrostructure: macro,
        tokens,
        content,
      });
      await publishTheme(storeId, token);
      setState('published');
      setMsg('¡Publicado! Ya está en vivo.');
    } catch (e) {
      setState('error');
      setMsg(`No se pudo publicar: ${(e as Error).message}`);
    }
  }, [storeId, token, baseTheme, macro, tokens, content]);

  // 편집 토큰 없음 → 안내
  if (loaded && !token) {
    return (
      <div style={ui.gate}>
        <div>
          <h1 style={{ margin: '0 0 8px' }}>Necesitás un link de edición</h1>
          <p style={{ color: '#9aa2b1' }}>
            Generá el link desde el panel de administración con el botón
            «Editar diseño».
          </p>
        </div>
      </div>
    );
  }

  return (
    <>
      <Head>
        <title>Personalizá tu tienda</title>
      </Head>
      <div style={ui.app}>
        {/* 좌측 컨트롤 — 아코디언 그룹 */}
        <aside style={ui.panel}>
          <div style={ui.brand}>
            <h1 style={ui.brandH}>🎨 Personalizá tu tienda</h1>
            <p style={ui.brandP}>
              Elegí colores, tipografías y secciones. Todo se ve al instante a
              la derecha.
            </p>
          </div>

          <div style={ui.groups}>
            <AccordionGroup icon="🧱" title="Estructura de la home" defaultOpen>
              <MacroSelector
                value={macro}
                onChange={(m) => {
                  setMacro(m);
                  setState('idle');
                }}
              />
            </AccordionGroup>

            <AccordionGroup
              icon="⚙️"
              title={`Ajustes de ${MACRO_LABEL[macro]}`}
              defaultOpen
            >
              <StructureFieldsEditor
                macro={macro}
                macroSettings={content.macroSettings}
                onChange={(ms) => patchContent({ macroSettings: ms })}
                storeId={storeId}
              />
            </AccordionGroup>

            <AccordionGroup
              icon="🧩"
              title="Secciones disponibles en esta estructura"
              defaultOpen
            >
              <SectionGatingChips macro={macro} />
            </AccordionGroup>

            <AccordionGroup icon="🏷" title="Identidad de marca">
              <TextField
                label="Nombre visible en la tienda"
                value={content.brand.displayName}
                maxLength={60}
                onChange={(v) =>
                  patchContent({ brand: { ...content.brand, displayName: v } })
                }
              />
              <AssetUploadField
                storeId={storeId}
                token={token}
                kind="logo"
                value={content.brand.logoFile}
                onChange={(fileName) =>
                  patchContent({ brand: { ...content.brand, logoFile: fileName } })
                }
                label="Logo"
                accept="image/png,image/jpeg,image/webp,image/svg+xml"
              />
              <AssetUploadField
                storeId={storeId}
                token={token}
                kind="favicon"
                value={content.brand.faviconFile}
                onChange={(fileName) =>
                  patchContent({
                    brand: { ...content.brand, faviconFile: fileName },
                  })
                }
                label="Favicon"
                accept="image/png,image/jpeg,image/webp"
              />
            </AccordionGroup>

            <AccordionGroup icon="📣" title="Barra de anuncio">
              <SwitchField
                label="Mostrar barra superior"
                checked={content.announce.enabled}
                onChange={(v) =>
                  patchContent({ announce: { ...content.announce, enabled: v } })
                }
              />
              <TextField
                label="Texto"
                value={content.announce.text}
                maxLength={200}
                onChange={(v) =>
                  patchContent({ announce: { ...content.announce, text: v } })
                }
              />
              <TextField
                label="Link (opcional)"
                value={content.announce.href ?? ''}
                maxLength={500}
                placeholder="https://... o /ruta"
                onChange={(v) =>
                  patchContent({
                    announce: { ...content.announce, href: v || null },
                  })
                }
              />
            </AccordionGroup>

            <AccordionGroup icon="🧩" title="Secciones del inicio">
              <SectionListEditor
                sections={content.sections}
                onChange={(sections) => patchContent({ sections })}
                storeId={storeId}
                token={token}
                disabledTypes={GATED_BY_MACRO[macro]}
              />
            </AccordionGroup>

            <AccordionGroup icon="🎨" title="Colores y tipografía">
              {(['editorial', 'modern-minimal', 'atmospheric', 'playful'] as const).map(
                (g) => (
                  <div key={g}>
                    <div style={ui.genre}>{GENRE_LABELS[g]}</div>
                    <div style={ui.themeGrid}>
                      {THEME_PRESETS.filter((p) => p.genre === g).map((p) => {
                        const v = tokensToCssVars(p.tokens);

                        return (
                          <button
                            key={p.id}
                            onClick={() => applyPreset(p.id)}
                            style={{
                              ...ui.theme,
                              outline:
                                baseTheme === p.id ? '2px solid #f5a623' : 'none',
                            }}
                          >
                            <span style={ui.sw}>
                              <i style={{ background: v['--bg'] }} />
                              <i style={{ background: v['--gold'] }} />
                              <i style={{ background: v['--ink'] }} />
                            </span>
                            <span style={ui.themeNm}>{p.id}</span>
                          </button>
                        );
                      })}
                    </div>
                  </div>
                ),
              )}

              <label style={ui.lab}>
                Color de acento <b style={ui.labB}>{tokens.accentHue}°</b>
              </label>
              <input
                type="range"
                min={0}
                max={360}
                value={tokens.accentHue}
                onChange={(e) => patch({ accentHue: Number(e.target.value) })}
                style={ui.range}
              />
              <label style={ui.lab}>
                Saturación <b style={ui.labB}>{tokens.sat}%</b>
              </label>
              <input
                type="range"
                min={10}
                max={100}
                value={tokens.sat}
                onChange={(e) => patch({ sat: Number(e.target.value) })}
                style={ui.range}
              />
              <label style={ui.lab}>Tono de fondo</label>
              <div style={ui.segs}>
                {(['light', 'mid', 'dark'] as PaperBand[]).map((b) => (
                  <button
                    key={b}
                    onClick={() => patch({ paperBand: b })}
                    style={tokens.paperBand === b ? ui.segOn : ui.seg}
                  >
                    {b === 'light' ? 'Claro' : b === 'mid' ? 'Medio' : 'Oscuro'}
                  </button>
                ))}
              </div>

              <label style={ui.lab}>Tipografía</label>
              <select
                value={tokens.fontPair}
                onChange={(e) => patch({ fontPair: e.target.value as FontPair })}
                style={ui.select}
              >
                <option value="serif">Editorial (serif)</option>
                <option value="sans">Moderno (sans)</option>
                <option value="mono">Técnico (mono)</option>
                <option value="condensed">Impacto (condensada)</option>
              </select>
              <label style={ui.lab}>
                Grosor de títulos <b style={ui.labB}>{tokens.weight}</b>
              </label>
              <input
                type="range"
                min={400}
                max={900}
                step={100}
                value={tokens.weight}
                onChange={(e) => patch({ weight: Number(e.target.value) })}
                style={ui.range}
              />
              <label style={ui.lab}>
                Redondeo de esquinas <b style={ui.labB}>{tokens.radius}px</b>
              </label>
              <input
                type="range"
                min={0}
                max={26}
                value={tokens.radius}
                onChange={(e) => patch({ radius: Number(e.target.value) })}
                style={ui.range}
              />
            </AccordionGroup>

            <AccordionGroup icon="🛍" title="Tarjeta de producto">
              <SwitchField
                label="Mostrar % de descuento"
                checked={content.productCard.discountBadge}
                onChange={(v) =>
                  patchContent({
                    productCard: { ...content.productCard, discountBadge: v },
                  })
                }
              />
              <SwitchField
                label="Mostrar cuotas"
                checked={content.productCard.installments}
                onChange={(v) =>
                  patchContent({
                    productCard: { ...content.productCard, installments: v },
                  })
                }
              />
              <SwitchField
                label="Botón de agregado rápido (＋)"
                checked={content.productCard.quickAdd}
                onChange={(v) =>
                  patchContent({ productCard: { ...content.productCard, quickAdd: v } })
                }
              />
              <SwitchField
                label="Cambiar a 2ª foto al pasar el mouse"
                checked={content.productCard.hoverSecondImage}
                onChange={(v) =>
                  patchContent({
                    productCard: { ...content.productCard, hoverSecondImage: v },
                  })
                }
              />
              <SwitchField
                label="Aviso «Últimas unidades»"
                checked={content.productCard.lastUnitsBadge}
                onChange={(v) =>
                  patchContent({
                    productCard: { ...content.productCard, lastUnitsBadge: v },
                  })
                }
              />
              <SwitchField
                label="Puntos de color de variantes"
                checked={content.productCard.variantDots}
                onChange={(v) =>
                  patchContent({
                    productCard: { ...content.productCard, variantDots: v },
                  })
                }
                hint="Sin datos de color de variantes aún — este interruptor no afecta la vista pública por ahora."
              />
            </AccordionGroup>

            <AccordionGroup icon="📚" title="Catálogo y filtros">
              <SelectField
                label="Orden por defecto"
                value={content.catalog.defaultSort}
                onChange={(v) =>
                  patchContent({
                    catalog: { ...content.catalog, defaultSort: v as CatalogSort },
                  })
                }
                options={[
                  { value: 'newest', label: 'Más nuevos' },
                  { value: 'price_asc', label: 'Precio: menor a mayor' },
                  { value: 'price_desc', label: 'Precio: mayor a menor' },
                  { value: 'bestseller', label: 'Más vendidos' },
                ]}
              />
              <NumberField
                label="Productos por página"
                value={content.catalog.pageSize}
                min={12}
                max={48}
                step={4}
                onChange={(v) =>
                  patchContent({ catalog: { ...content.catalog, pageSize: v } })
                }
              />
              <SwitchField
                label="Mostrar productos sin stock"
                checked={content.catalog.showOutOfStock}
                onChange={(v) =>
                  patchContent({
                    catalog: { ...content.catalog, showOutOfStock: v },
                  })
                }
              />
              <SwitchField
                label="Filtro de talles"
                checked={content.catalog.filters.size}
                onChange={(v) =>
                  patchContent({
                    catalog: {
                      ...content.catalog,
                      filters: { ...content.catalog.filters, size: v },
                    },
                  })
                }
                hint="Los filtros de talle y color todavía no están disponibles en la vista pública (faltan datos de variantes) — se guardan para cuando lo estén."
              />
              <SwitchField
                label="Filtro de colores"
                checked={content.catalog.filters.color}
                onChange={(v) =>
                  patchContent({
                    catalog: {
                      ...content.catalog,
                      filters: { ...content.catalog.filters, color: v },
                    },
                  })
                }
                hint="Los filtros de talle y color todavía no están disponibles en la vista pública (faltan datos de variantes) — se guardan para cuando lo estén."
              />
              <SwitchField
                label="Filtro de precio"
                checked={content.catalog.filters.price}
                onChange={(v) =>
                  patchContent({
                    catalog: {
                      ...content.catalog,
                      filters: { ...content.catalog.filters, price: v },
                    },
                  })
                }
                hint={
                  content.catalog.filters.price
                    ? 'El filtro de precio ya funciona en la vista pública.'
                    : undefined
                }
              />
            </AccordionGroup>

            <AccordionGroup icon="💬" title="Contacto & redes">
              <TextField
                label="WhatsApp"
                value={content.contact.whatsapp ?? ''}
                maxLength={20}
                placeholder="+54 9 11 ..."
                onChange={(v) =>
                  patchContent({
                    contact: { ...content.contact, whatsapp: v || null },
                  })
                }
              />
              <TextField
                label="Instagram"
                value={content.contact.instagram ?? ''}
                maxLength={100}
                onChange={(v) =>
                  patchContent({
                    contact: { ...content.contact, instagram: v || null },
                  })
                }
              />
              <TextField
                label="Facebook"
                value={content.contact.facebook ?? ''}
                maxLength={100}
                onChange={(v) =>
                  patchContent({
                    contact: { ...content.contact, facebook: v || null },
                  })
                }
              />
              <TextField
                label="Texto del pie de página"
                value={content.contact.footerText ?? ''}
                maxLength={200}
                multiline
                onChange={(v) =>
                  patchContent({
                    contact: { ...content.contact, footerText: v || null },
                  })
                }
              />
            </AccordionGroup>

            <AccordionGroup icon="🛡" title="Confianza, pagos y envíos">
              <span style={ui.subLabel}>Logos de pago (máx. 8)</span>
              {[
                ...content.trust.paymentLogos,
                ...(content.trust.paymentLogos.length < 8 ? [null] : []),
              ].map((f, idx) => (
                <AssetUploadField
                  key={idx}
                  storeId={storeId}
                  token={token}
                  kind="payment"
                  value={f}
                  onChange={(fileName) => {
                    const logos = [...content.trust.paymentLogos];
                    if (idx < logos.length) {
                      if (fileName) logos[idx] = fileName;
                      else logos.splice(idx, 1);
                    } else if (fileName) {
                      logos.push(fileName);
                    }
                    patchContent({ trust: { ...content.trust, paymentLogos: logos } });
                  }}
                  label={
                    idx < content.trust.paymentLogos.length
                      ? `Logo de pago ${idx + 1}`
                      : '+ Agregar logo de pago'
                  }
                  accept="image/png,image/jpeg,image/webp,image/svg+xml"
                />
              ))}

              <span style={ui.subLabel}>Logos de envío (máx. 8)</span>
              {[
                ...content.trust.shippingLogos,
                ...(content.trust.shippingLogos.length < 8 ? [null] : []),
              ].map((f, idx) => (
                <AssetUploadField
                  key={idx}
                  storeId={storeId}
                  token={token}
                  kind="shipping"
                  value={f}
                  onChange={(fileName) => {
                    const logos = [...content.trust.shippingLogos];
                    if (idx < logos.length) {
                      if (fileName) logos[idx] = fileName;
                      else logos.splice(idx, 1);
                    } else if (fileName) {
                      logos.push(fileName);
                    }
                    patchContent({ trust: { ...content.trust, shippingLogos: logos } });
                  }}
                  label={
                    idx < content.trust.shippingLogos.length
                      ? `Logo de envío ${idx + 1}`
                      : '+ Agregar logo de envío'
                  }
                  accept="image/png,image/jpeg,image/webp,image/svg+xml"
                />
              ))}

              <SwitchField
                label="Mostrar «Compra protegida»"
                checked={content.trust.protectedBadge}
                onChange={(v) =>
                  patchContent({ trust: { ...content.trust, protectedBadge: v } })
                }
              />

              <span style={ui.subLabel}>Enlaces de políticas (máx. 6)</span>
              {content.trust.policyLinks.map((l, idx) => (
                <div key={idx} style={ui.linkRow}>
                  <div style={ui.linkLabelCol}>
                    <TextField
                      label="Texto"
                      value={l.label}
                      maxLength={60}
                      onChange={(v) => {
                        const policyLinks = content.trust.policyLinks.map((pl, k) =>
                          k === idx ? { ...pl, label: v } : pl,
                        );
                        patchContent({ trust: { ...content.trust, policyLinks } });
                      }}
                    />
                  </div>
                  <div style={ui.linkHrefCol}>
                    <TextField
                      label="Link"
                      value={l.href}
                      maxLength={500}
                      placeholder="https://... o /ruta"
                      onChange={(v) => {
                        const policyLinks = content.trust.policyLinks.map((pl, k) =>
                          k === idx ? { ...pl, href: v } : pl,
                        );
                        patchContent({ trust: { ...content.trust, policyLinks } });
                      }}
                    />
                  </div>
                  <button
                    type="button"
                    onClick={() => {
                      const policyLinks = content.trust.policyLinks.filter(
                        (_, k) => k !== idx,
                      );
                      patchContent({ trust: { ...content.trust, policyLinks } });
                    }}
                    style={ui.linkRemove}
                  >
                    ✕
                  </button>
                </div>
              ))}
              {content.trust.policyLinks.length < 6 ? (
                <button
                  type="button"
                  onClick={() =>
                    patchContent({
                      trust: {
                        ...content.trust,
                        policyLinks: [
                          ...content.trust.policyLinks,
                          { label: '', href: '' },
                        ],
                      },
                    })
                  }
                  style={ui.addBtn}
                >
                  + Agregar enlace
                </button>
              ) : null}
            </AccordionGroup>

            <AccordionGroup icon="📈" title="Marketing & SEO">
              <SwitchField
                label="Popup de bienvenida"
                checked={content.marketing.popup.enabled}
                onChange={(v) =>
                  patchContent({
                    marketing: {
                      ...content.marketing,
                      popup: { ...content.marketing.popup, enabled: v },
                    },
                  })
                }
              />
              <TextField
                label="Título del popup"
                value={content.marketing.popup.title}
                maxLength={120}
                placeholder="¡10% OFF en tu primera compra!"
                onChange={(v) =>
                  patchContent({
                    marketing: {
                      ...content.marketing,
                      popup: { ...content.marketing.popup, title: v },
                    },
                  })
                }
              />
              <TextField
                label="Cupón (opcional)"
                value={content.marketing.popup.coupon ?? ''}
                maxLength={32}
                placeholder="BIENVENIDO10"
                hint="El código se muestra pero todavía no se valida automáticamente."
                onChange={(v) =>
                  patchContent({
                    marketing: {
                      ...content.marketing,
                      popup: { ...content.marketing.popup, coupon: v || null },
                    },
                  })
                }
              />
              <TextField
                label="Título SEO"
                value={content.marketing.seoTitle ?? ''}
                maxLength={70}
                hint="Aparece en la pestaña del navegador y en Google."
                onChange={(v) =>
                  patchContent({ marketing: { ...content.marketing, seoTitle: v || null } })
                }
              />
              <TextField
                label="Descripción SEO"
                value={content.marketing.seoDescription ?? ''}
                maxLength={160}
                multiline
                onChange={(v) =>
                  patchContent({
                    marketing: { ...content.marketing, seoDescription: v || null },
                  })
                }
              />
              <TextField
                label="Pixel ID"
                value={content.marketing.pixelId ?? ''}
                maxLength={64}
                placeholder="1234567890"
                hint="Meta Pixel ID — solo números, letras, guiones."
                onChange={(v) =>
                  patchContent({ marketing: { ...content.marketing, pixelId: v || null } })
                }
              />
            </AccordionGroup>
          </div>

          <div style={ui.actions}>
            <button onClick={onSave} style={ui.btnGhost} disabled={state === 'saving'}>
              {state === 'saving' ? 'Guardando…' : 'Guardar borrador'}
            </button>
            <button
              onClick={onPublish}
              style={ui.btnPrimary}
              disabled={state === 'publishing'}
            >
              {state === 'publishing' ? 'Publicando…' : 'Publicar'}
            </button>
          </div>
          {msg ? <p style={ui.msg}>{msg}</p> : null}
        </aside>

        {/* 우측 실시간 미리보기 (실제 컴포넌트, content.sections 순회) */}
        <main style={ui.stage}>
          <div style={{ ...(cssVars as CSSProperties), ...ui.preview }} data-macro={macro}>
            <div style={ui.pbar}>
              <span style={ui.pbarDot} />
              <span style={ui.pbarText}>
                Vista previa en vivo — <b style={ui.pbarName}>{MACRO_LABEL[macro]}</b>
              </span>
              <span style={ui.pbarHint}>{MACRO_PREVIEW_HINTS[macro]}</span>
            </div>
            <ThemeContentProvider content={content}>
              <Header
                categories={[]}
                q=""
                onQ={() => undefined}
                activeCat={null}
                onCat={() => undefined}
              />
              <div className="container" style={{ paddingBottom: 40 }}>
                {/* macrostructure 는 그리드 밀도가 아니라 렌더 구조 자체가 다르므로 index.tsx(Plan
                    61-09)와 동일하게 최상위 분기로 구현한다 — 에디터 전용 스키매틱 렌더러는 만들지
                    않고 실제 RailsLayout/MasonryLayout 을 재사용한다(UI-SPEC 미리보기 연동 절). */}
                {macro === 'rails' ? (
                  <>
                    <RailsLayout
                      storeId={storeId}
                      heroSection={previewHeroSection}
                      previewItems={DUMMY}
                    />
                    {visibleSections
                      .filter((sec) => sec.type !== 'hero' && sec.type !== 'carousel')
                      .map((sec) => (
                        <SectionRenderer key={sec.type} storeId={storeId} section={sec} />
                      ))}
                  </>
                ) : macro === 'masonry' ? (
                  <>
                    {visibleSections
                      .filter((sec) => sec.type !== 'carousel')
                      .map((sec) => (
                        <SectionRenderer key={sec.type} storeId={storeId} section={sec} />
                      ))}
                    <MasonryLayout
                      storeId={storeId}
                      initialItems={DUMMY}
                      categories={[]}
                      activeCat={null}
                      onCat={() => undefined}
                    />
                  </>
                ) : (
                  content.sections.map((s) => (
                    <SectionRenderer
                      key={s.type}
                      storeId={storeId}
                      section={s}
                      initialItems={s.type === 'carousel' ? DUMMY : undefined}
                    />
                  ))
                )}
              </div>
            </ThemeContentProvider>
          </div>
        </main>
      </div>
    </>
  );
}

const ui: Record<string, CSSProperties> = {
  app: { display: 'grid', gridTemplateColumns: '380px 1fr', height: '100vh', fontFamily: 'system-ui, sans-serif' },
  panel: { background: '#1a1a2e', color: '#e8eaed', borderRight: '1px solid #32325a', overflowY: 'auto' },
  brand: { padding: '16px 18px', borderBottom: '1px solid #32325a' },
  brandH: { fontSize: 15, margin: 0, fontWeight: 650 },
  brandP: { fontSize: 11.5, color: '#9aa2b1', margin: '4px 0 0' },
  groups: { padding: '12px 12px 8px' },
  genre: { fontSize: 10, color: '#828b9b', margin: '10px 0 6px', fontWeight: 600 },
  themeGrid: { display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 7 },
  theme: { cursor: 'pointer', border: '1px solid #32325a', borderRadius: 8, padding: 8, background: '#20203c', color: '#e8eaed', textAlign: 'left' },
  sw: { display: 'flex', gap: 3, marginBottom: 6 },
  themeNm: { fontSize: 11, fontWeight: 600 },
  lab: { display: 'block', fontSize: 11, margin: '10px 0 6px', color: '#9aa2b1' },
  labB: { float: 'right', color: '#9aa2b1', fontWeight: 500 },
  range: { width: '100%', accentColor: '#f5a623' },
  segs: { display: 'flex', gap: 6, marginBottom: 4 },
  seg: { flex: 1, background: '#20203c', color: '#9aa2b1', border: '1px solid #32325a', padding: '7px 4px', borderRadius: 7, fontSize: 11, cursor: 'pointer' },
  segOn: { flex: 1, background: '#f5a623', color: '#1a1a2e', border: '1px solid #f5a623', padding: '7px 4px', borderRadius: 7, fontSize: 11, cursor: 'pointer', fontWeight: 700 },
  select: { width: '100%', background: '#20203c', color: '#e8eaed', border: '1px solid #32325a', padding: 8, borderRadius: 7, fontSize: 12 },
  actions: { display: 'flex', gap: 8, padding: '16px 18px' },
  btnGhost: { flex: 1, background: '#20203c', color: '#e8eaed', border: '1px solid #32325a', padding: '10px', borderRadius: 8, cursor: 'pointer', fontSize: 13 },
  btnPrimary: { flex: 1, background: '#f5a623', color: '#1a1a2e', border: 'none', padding: '10px', borderRadius: 8, cursor: 'pointer', fontSize: 13, fontWeight: 700 },
  msg: { padding: '0 18px 16px', fontSize: 11.5, color: '#8fc2ff', margin: 0 },
  subLabel: { fontSize: 10, color: '#828b9b', fontWeight: 600, marginTop: 4 },
  linkRow: { display: 'flex', gap: 6, alignItems: 'flex-end' },
  linkLabelCol: { flex: '0 0 32%' },
  linkHrefCol: { flex: 1 },
  linkRemove: {
    background: 'transparent',
    border: '1px solid #32325a',
    borderRadius: 6,
    color: '#9aa2b1',
    cursor: 'pointer',
    padding: '8px 10px',
    fontSize: 12,
    flexShrink: 0,
  },
  addBtn: {
    background: '#20203c',
    color: '#f5a623',
    border: '1px dashed #32325a',
    borderRadius: 8,
    padding: '8px 10px',
    fontSize: 12,
    cursor: 'pointer',
    textAlign: 'left',
  },
  gate: { display: 'flex', alignItems: 'center', justifyContent: 'center', height: '100vh', background: '#15152a', color: '#e8eaed', textAlign: 'center', fontFamily: 'system-ui, sans-serif' },
  stage: { overflow: 'auto', background: '#15152a', padding: 22 },
  preview: { background: 'var(--bg)', color: 'var(--ink)', fontFamily: 'var(--font-body)', borderRadius: 12, overflow: 'hidden', minHeight: '100%' },
  pbar: { height: 48, borderBottom: '1px solid #32325a', display: 'flex', alignItems: 'center', gap: 12, padding: '0 12px' },
  pbarDot: { width: 8, height: 8, borderRadius: '50%', background: '#2e7d5b', flexShrink: 0 },
  pbarText: { fontSize: 11, color: '#9aa2b1' },
  pbarName: { fontSize: 13, color: '#e8eaed' },
  pbarHint: { fontSize: 11, color: '#9aa2b1', marginLeft: 'auto', textAlign: 'right' },
};
