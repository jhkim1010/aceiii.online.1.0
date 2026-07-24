import { useCallback, useEffect, useMemo, useState } from 'react';
import type { CSSProperties } from 'react';
import Head from 'next/head';
import { useRouter } from 'next/router';
import AssetUploadField from '@/components/panel/AssetUploadField';
import {
  AccordionGroup,
  SwitchField,
  TextField,
} from '@/components/panel/PanelPrimitives';
import SectionListEditor from '@/components/panel/SectionListEditor';
import Header from '@/components/Header';
import SectionRenderer from '@/components/sections/SectionRenderer';
import { ThemeContentProvider } from '@/context/ThemeContentContext';
import {
  getThemeDraft,
  publishTheme,
  saveThemeDraft,
} from '@/services/shop-api';
import type {
  FontPair,
  Macrostructure,
  PaperBand,
  ShopProduct,
  StoreThemeContent,
  StoreThemeTokens,
} from '@/types/shop';
import {
  DEFAULT_CONTENT,
  DEFAULT_TOKENS,
  GENRE_LABELS,
  THEME_PRESETS,
  tokensToCssVars,
} from '@/lib/theme-preset';

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
            <AccordionGroup icon="🏷" title="Identidad de marca" defaultOpen>
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

            <AccordionGroup icon="🧩" title="Secciones del inicio" defaultOpen>
              <SectionListEditor
                sections={content.sections}
                onChange={(sections) => patchContent({ sections })}
                storeId={storeId}
                token={token}
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

              {/* TODO(Plan 61-10): 구조 선택 UI 는 그룹 1(🧱 Estructura de la home)로 이동 예정. 그때까지 macro state 는 초안 값 유지. */}
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
            <ThemeContentProvider content={content}>
              <Header
                categories={[]}
                q=""
                onQ={() => undefined}
                activeCat={null}
                onCat={() => undefined}
              />
              <div className="container" style={{ paddingBottom: 40 }}>
                {content.sections.map((s) => (
                  <SectionRenderer
                    key={s.type}
                    storeId={storeId}
                    section={s}
                    initialItems={s.type === 'carousel' ? DUMMY : undefined}
                  />
                ))}
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
  gate: { display: 'flex', alignItems: 'center', justifyContent: 'center', height: '100vh', background: '#15152a', color: '#e8eaed', textAlign: 'center', fontFamily: 'system-ui, sans-serif' },
  stage: { overflow: 'auto', background: '#15152a', padding: 22 },
  preview: { background: 'var(--bg)', color: 'var(--ink)', fontFamily: 'var(--font-body)', borderRadius: 12, overflow: 'hidden', minHeight: '100%' },
};
