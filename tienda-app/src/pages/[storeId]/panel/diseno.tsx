import { useCallback, useEffect, useMemo, useState } from 'react';
import type { CSSProperties } from 'react';
import Head from 'next/head';
import { useRouter } from 'next/router';
import Header from '@/components/Header';
import ProductCard from '@/components/ProductCard';
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
  StoreThemeTokens,
} from '@/types/shop';
import {
  DEFAULT_TOKENS,
  GENRE_LABELS,
  MACRO_OPTIONS,
  THEME_PRESETS,
  tokensToCssVars,
} from '@/lib/theme-preset';

// 미리보기용 더미 상품 (실제 ProductCard 컴포넌트로 렌더 → 발행 결과와 동일한 룩)
const DUMMY: ShopProduct[] = [1, 2, 3].map((n) => ({
  id: -n,
  name: `Producto de ejemplo ${n}`,
  slug: null,
  description: null,
  longDescription: null,
  price: 12000 + n * 3500,
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
      })
      .catch((e: Error) => {
        if (!alive) return;
        setMsg(`초안을 불러오지 못했습니다: ${e.message}`);
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
      await saveThemeDraft(storeId, token, { baseTheme, macrostructure: macro, tokens });
      setState('saved');
      setMsg('초안이 저장되었습니다 (아직 공개에는 반영 안 됨)');
    } catch (e) {
      setState('error');
      setMsg(`저장 실패: ${(e as Error).message}`);
    }
  }, [storeId, token, baseTheme, macro, tokens]);

  const onPublish = useCallback(async () => {
    setState('publishing');
    try {
      // 발행 전 최신 초안 저장 후 발행
      await saveThemeDraft(storeId, token, { baseTheme, macrostructure: macro, tokens });
      await publishTheme(storeId, token);
      setState('published');
      setMsg('발행 완료 — 공개 홈페이지에 반영되었습니다');
    } catch (e) {
      setState('error');
      setMsg(`발행 실패: ${(e as Error).message}`);
    }
  }, [storeId, token, baseTheme, macro, tokens]);

  // 편집 토큰 없음 → 안내
  if (loaded && !token) {
    return (
      <div style={ui.gate}>
        <div>
          <h1 style={{ margin: '0 0 8px' }}>편집 링크가 필요합니다</h1>
          <p style={{ color: '#9aa2b1' }}>
            관리자 콘솔에서 &quot;디자인 편집&quot; 버튼으로 편집 링크를 생성해
            열어주세요.
          </p>
        </div>
      </div>
    );
  }

  const grid: CSSProperties = {
    display: 'grid',
    gap: macro === 'doc' ? 14 : 18,
    gridTemplateColumns:
      macro === 'bento'
        ? 'repeat(auto-fill, minmax(200px, 1fr))'
        : macro === 'doc'
          ? 'repeat(auto-fill, minmax(150px, 1fr))'
          : 'repeat(auto-fill, minmax(180px, 1fr))',
  };

  return (
    <>
      <Head>
        <title>내 매장 홈페이지 꾸미기</title>
      </Head>
      <div style={ui.app}>
        {/* 좌측 컨트롤 */}
        <aside style={ui.panel}>
          <div style={ui.brand}>
            <h1 style={ui.brandH}>🎨 내 매장 홈페이지 꾸미기</h1>
            <p style={ui.brandP}>테마·색·글꼴·레이아웃을 고르면 오른쪽에 바로 반영됩니다.</p>
          </div>

          <section style={ui.sec}>
            <h2 style={ui.secH}>1 · 스타일 테마</h2>
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
                              baseTheme === p.id ? '2px solid #6ea8fe' : 'none',
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
          </section>

          <section style={ui.sec}>
            <h2 style={ui.secH}>2 · 색상</h2>
            <label style={ui.lab}>
              포인트 색 <b style={ui.labB}>{tokens.accentHue}°</b>
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
              채도 <b style={ui.labB}>{tokens.sat}%</b>
            </label>
            <input
              type="range"
              min={10}
              max={100}
              value={tokens.sat}
              onChange={(e) => patch({ sat: Number(e.target.value) })}
              style={ui.range}
            />
            <label style={ui.lab}>배경 톤</label>
            <div style={ui.segs}>
              {(['light', 'mid', 'dark'] as PaperBand[]).map((b) => (
                <button
                  key={b}
                  onClick={() => patch({ paperBand: b })}
                  style={tokens.paperBand === b ? ui.segOn : ui.seg}
                >
                  {b === 'light' ? '밝게' : b === 'mid' ? '중간' : '어둡게'}
                </button>
              ))}
            </div>
          </section>

          <section style={ui.sec}>
            <h2 style={ui.secH}>3 · 글꼴 조합</h2>
            <select
              value={tokens.fontPair}
              onChange={(e) => patch({ fontPair: e.target.value as FontPair })}
              style={ui.select}
            >
              <option value="serif">에디토리얼 (세리프)</option>
              <option value="sans">모던 (산세리프)</option>
              <option value="mono">테크 (모노)</option>
              <option value="condensed">임팩트 (콘덴스드)</option>
            </select>
            <label style={ui.lab}>
              제목 굵기 <b style={ui.labB}>{tokens.weight}</b>
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
          </section>

          <section style={ui.sec}>
            <h2 style={ui.secH}>4 · 레이아웃</h2>
            <div style={ui.segs}>
              {MACRO_OPTIONS.map((m) => (
                <button
                  key={m.id}
                  onClick={() => {
                    setMacro(m.id);
                    setState('idle');
                  }}
                  style={macro === m.id ? ui.segOn : ui.seg}
                >
                  {m.label}
                </button>
              ))}
            </div>
            <label style={ui.lab}>
              모서리 둥글기 <b style={ui.labB}>{tokens.radius}px</b>
            </label>
            <input
              type="range"
              min={0}
              max={26}
              value={tokens.radius}
              onChange={(e) => patch({ radius: Number(e.target.value) })}
              style={ui.range}
            />
          </section>

          <div style={ui.actions}>
            <button onClick={onSave} style={ui.btnGhost} disabled={state === 'saving'}>
              {state === 'saving' ? '저장 중…' : '초안 저장'}
            </button>
            <button
              onClick={onPublish}
              style={ui.btnPrimary}
              disabled={state === 'publishing'}
            >
              {state === 'publishing' ? '발행 중…' : '발행하기'}
            </button>
          </div>
          {msg ? <p style={ui.msg}>{msg}</p> : null}
        </aside>

        {/* 우측 실시간 미리보기 (실제 컴포넌트) */}
        <main style={ui.stage}>
          <div style={{ ...(cssVars as CSSProperties), ...ui.preview }} data-macro={macro}>
            <Header
              categories={[]}
              q=""
              onQ={() => undefined}
              activeCat={null}
              onCat={() => undefined}
            />
            <div className="container" style={{ paddingBottom: 40 }}>
              <section style={ui.hero}>
                <h2 style={ui.heroTitle}>Nueva temporada</h2>
                <p style={ui.heroP}>당신 매장만의 셀렉션을, 당신이 꾸민 홈페이지에서.</p>
                <button className="btn btn-gold">Ver colección</button>
              </section>
              <h3 style={ui.secTitle}>Destacados</h3>
              <section style={grid}>
                {DUMMY.map((p) => (
                  <ProductCard key={p.id} product={p} />
                ))}
              </section>
            </div>
          </div>
        </main>
      </div>
    </>
  );
}

const ui: Record<string, CSSProperties> = {
  app: { display: 'grid', gridTemplateColumns: '340px 1fr', height: '100vh', fontFamily: 'system-ui, sans-serif' },
  panel: { background: '#171a21', color: '#e8eaed', borderRight: '1px solid #2a2f3a', overflowY: 'auto' },
  brand: { padding: '16px 18px', borderBottom: '1px solid #2a2f3a' },
  brandH: { fontSize: 15, margin: 0, fontWeight: 650 },
  brandP: { fontSize: 11.5, color: '#9aa2b1', margin: '4px 0 0' },
  sec: { padding: '14px 18px', borderBottom: '1px solid #2a2f3a' },
  secH: { fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.9px', color: '#9aa2b1', margin: '0 0 10px', fontWeight: 650 },
  genre: { fontSize: 10, color: '#828b9b', margin: '10px 0 6px', fontWeight: 600 },
  themeGrid: { display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 7 },
  theme: { cursor: 'pointer', border: '1px solid #2a2f3a', borderRadius: 8, padding: 8, background: '#1e222b', color: '#e8eaed', textAlign: 'left' },
  sw: { display: 'flex', gap: 3, marginBottom: 6 },
  themeNm: { fontSize: 11, fontWeight: 600 },
  lab: { display: 'block', fontSize: 11.5, margin: '10px 0 6px', color: '#c3c9d4' },
  labB: { float: 'right', color: '#9aa2b1', fontWeight: 500 },
  range: { width: '100%', accentColor: '#6ea8fe' },
  segs: { display: 'flex', gap: 6, marginBottom: 4 },
  seg: { flex: 1, background: '#1e222b', color: '#9aa2b1', border: '1px solid #2a2f3a', padding: '7px 4px', borderRadius: 7, fontSize: 11, cursor: 'pointer' },
  segOn: { flex: 1, background: '#6ea8fe', color: '#08121f', border: '1px solid #6ea8fe', padding: '7px 4px', borderRadius: 7, fontSize: 11, cursor: 'pointer', fontWeight: 600 },
  select: { width: '100%', background: '#1e222b', color: '#e8eaed', border: '1px solid #2a2f3a', padding: 8, borderRadius: 7, fontSize: 12 },
  actions: { display: 'flex', gap: 8, padding: '16px 18px' },
  btnGhost: { flex: 1, background: '#1e222b', color: '#e8eaed', border: '1px solid #2a2f3a', padding: '10px', borderRadius: 8, cursor: 'pointer', fontSize: 13 },
  btnPrimary: { flex: 1, background: '#6ea8fe', color: '#08121f', border: 'none', padding: '10px', borderRadius: 8, cursor: 'pointer', fontSize: 13, fontWeight: 600 },
  msg: { padding: '0 18px 16px', fontSize: 11.5, color: '#8fc2ff', margin: 0 },
  gate: { display: 'flex', alignItems: 'center', justifyContent: 'center', height: '100vh', background: '#0f1115', color: '#e8eaed', textAlign: 'center', fontFamily: 'system-ui, sans-serif' },
  stage: { overflow: 'auto', background: '#0a0c10', padding: 22 },
  preview: { background: 'var(--bg)', color: 'var(--ink)', fontFamily: 'var(--font-body)', borderRadius: 12, overflow: 'hidden', minHeight: '100%' },
  hero: { margin: '22px 0', borderRadius: 'var(--radius)', padding: '44px 36px', color: '#fff', background: 'linear-gradient(120deg, var(--hero-from), var(--hero-to))' },
  heroTitle: { fontSize: 32, margin: '0 0 8px', fontFamily: 'var(--font-display)', fontWeight: 'var(--disp-weight)' },
  heroP: { margin: '0 0 18px', color: '#d8d6ea', maxWidth: 380 },
  secTitle: { fontSize: 20, margin: '24px 0 14px', fontFamily: 'var(--font-display)', fontWeight: 'var(--disp-weight)' },
};
