import { useEffect, useRef, useState } from 'react';
import type { CSSProperties } from 'react';
import { useRouter } from 'next/router';
import { useShop } from '@/context/ShopContext';
import { useThemeContent } from '@/context/ThemeContentContext';
import { money, placeholderGradient } from '@/lib/format';
import { listProducts, minioImageUrl } from '@/services/shop-api';
import type {
  QuizQuestion,
  QuizQuestionOption,
  QuizSection as QuizSectionData,
  ShopProduct,
} from '@/types/shop';

// 4상태 인라인 위저드 — 상태머신 라이브러리 금지(SPEC LOCKED), useState + 조건부 렌더로 충분.
type QuizState =
  | { step: 'banner' }
  | { step: 'question'; idx: number }
  | { step: 'result' };

interface MatchedProduct {
  product: ShopProduct;
  score: number;
}

// "0-15000" 형태 문자열을 [min, max] 로 파싱 — 형식이 어긋나면 null(가격 조건 무시).
function parsePriceRange(raw: string): [number, number] | null {
  const [minRaw, maxRaw] = raw.split('-').map((v) => v.trim());
  const min = Number(minRaw);
  const max = Number(maxRaw);

  if (!minRaw || !maxRaw || Number.isNaN(min) || Number.isNaN(max)) return null;

  return [min, max];
}

export default function QuizSection({
  storeId,
  section,
}: {
  storeId: number;
  section: QuizSectionData;
}) {
  const router = useRouter();
  const { add } = useShop();
  const { contact } = useThemeContent();
  const [state, setState] = useState<QuizState>({ step: 'banner' });
  const [answers, setAnswers] = useState<Record<string, QuizQuestionOption>>({});
  const [results, setResults] = useState<MatchedProduct[] | null>(null);
  const [catalogHref, setCatalogHref] = useState(`/${storeId}`);
  const [focusedOpt, setFocusedOpt] = useState<number | null>(null);
  const headingRef = useRef<HTMLHeadingElement>(null);

  // 상태 전환(질문/결과) 시 헤딩에 포커스 이동 — 스크린리더/키보드 사용자가 전환을 인지하도록.
  useEffect(() => {
    if (state.step === 'question' || state.step === 'result') {
      headingRef.current?.focus();
    }
  }, [state]);

  // 표시 토글이 꺼졌거나 질문이 하나도 없으면 렌더할 근거가 없다.
  if (!section.enabled || section.questions.length === 0) return null;

  const totalQuestions = section.questions.length;

  const startQuiz = () => {
    setAnswers({});
    setResults(null);
    setState({ step: 'question', idx: 0 });
  };

  const goBack = () => {
    if (state.step === 'question' && state.idx > 0) {
      setState({ step: 'question', idx: state.idx - 1 });
    }
  };

  const repeatQuiz = () => {
    setAnswers({});
    setResults(null);
    setState({ step: 'banner' });
  };

  // 답변 → 필터 변환(프런트 전용) + 단계적 완화 매칭. 신규 백엔드 엔드포인트 0 —
  // 기존 listProducts(카탈로그 목록 조회)만 사용한다(T-61-71 DoS 완화).
  const runMatch = async (finalAnswers: Record<string, QuizQuestionOption>) => {
    const params: { globalCategoryId?: number; gender?: string } = {};
    let priceRange: [number, number] | null = null;
    const catalogParams = new URLSearchParams();

    for (const [qKey, ans] of Object.entries(finalAnswers)) {
      const target = section.mapping[qKey];

      if (target === 'categoryId') {
        const catId = Number(ans.value);
        if (catId) {
          params.globalCategoryId = catId;
          catalogParams.set('categoryId', String(catId));
        }
      } else if (target === 'gender') {
        if (ans.value) {
          params.gender = ans.value;
          catalogParams.set('gender', ans.value);
        }
      } else if (target === 'priceRange') {
        const range = parsePriceRange(ans.value);
        if (range) {
          priceRange = range;
          catalogParams.set('minPrice', String(range[0]));
          catalogParams.set('maxPrice', String(range[1]));
        }
      }
    }

    const qs = catalogParams.toString();
    setCatalogHref(`/${storeId}${qs ? `?${qs}` : ''}`);

    try {
      const res = await listProducts(storeId, { ...params, pageSize: 24 });
      const pool = res.items;
      const withinPrice = (p: ShopProduct) =>
        !priceRange || (p.price >= priceRange[0] && p.price <= priceRange[1]);

      // 1단계: 카테고리/성별(서버 필터) + 가격(클라이언트 필터) 전부 매치
      let matched = pool.filter(withinPrice);

      // 2단계: 가격 조건만 완화(카테고리/성별 유지) — 이미 받은 목록 내에서, 추가 요청 없이
      if (matched.length < 3) {
        matched = matched.concat(pool.filter((p) => !withinPrice(p)));
      }

      // 3단계: 카테고리/성별까지 완화 — 전체 카탈로그에서 채운다(최대 1회 추가 요청)
      if (matched.length < 3) {
        const fallback = await listProducts(storeId, { pageSize: 24 });
        const already = new Set(matched.map((p) => p.id));
        matched = matched.concat(fallback.items.filter((p) => !already.has(p.id)));
      }

      const top3 = matched.slice(0, 3);
      // MATCH NN% — 순위 기반 단조감소 공식(난수 금지, 정렬 순서와 배지 숫자 일관)
      const scored: MatchedProduct[] = top3.map((product, i) => ({
        product,
        score: Math.max(60, 98 - i * 6),
      }));

      setResults(scored);
    } catch {
      setResults([]);
    }
  };

  const selectOption = (question: QuizQuestion, option: QuizQuestionOption) => {
    if (state.step !== 'question') return;
    const nextAnswers = { ...answers, [question.key]: option };
    setAnswers(nextAnswers);

    if (state.idx < totalQuestions - 1) {
      setState({ step: 'question', idx: state.idx + 1 });

      return;
    }

    setResults(null);
    setState({ step: 'result' });
    void runMatch(nextAnswers);
  };

  const whatsappHref = (() => {
    if (!contact.whatsapp) return null;
    const digits = contact.whatsapp.replace(/[^0-9]/g, '');

    if (!digits) return null;
    const text = encodeURIComponent(
      'Hola! Hice el quiz y me interesa que me asesoren.',
    );

    return `https://wa.me/${digits}?text=${text}`;
  })();

  // ---- 상태 1: 배너 ----
  if (state.step === 'banner') {
    return (
      <section style={s.bannerWrap}>
        <span aria-hidden="true" style={s.bannerEmoji}>
          🧭
        </span>
        <div style={s.bannerText}>
          <h2 style={s.bannerTitle}>{section.banner.title}</h2>
          <p style={s.bannerSubtitle}>{section.banner.subtitle}</p>
        </div>
        <button
          type="button"
          className="btn btn-gold"
          style={s.bannerCta}
          onClick={startQuiz}
        >
          Empezar el quiz →
        </button>
      </section>
    );
  }

  // ---- 상태 2: 질문(1~4단계) ----
  if (state.step === 'question') {
    const question = section.questions[state.idx];
    const n = state.idx + 1;
    const progressPct = Math.round((n / totalQuestions) * 100);

    return (
      <section style={s.quizWrap}>
        <div style={s.prog}>
          <div style={s.progTrack} aria-hidden="true">
            <div style={{ ...s.progFill, width: `${progressPct}%` }} />
          </div>
          <span style={s.progLabel} aria-live="polite">
            {n} / {totalQuestions}
          </span>
        </div>
        <div style={s.kicker}>PREGUNTA {n}</div>
        <h2 ref={headingRef} tabIndex={-1} style={s.questionText}>
          {question.text}
        </h2>
        <div className="qz-opts">
          {question.options.map((opt, idx) => (
            <button
              key={idx}
              type="button"
              className="qz-opt"
              aria-label={`${opt.label}. ${opt.sub}`}
              onFocus={() => setFocusedOpt(idx)}
              onBlur={() => setFocusedOpt((f) => (f === idx ? null : f))}
              style={{
                ...s.opt,
                // onFocus/onBlur 로 키보드 포커스 시 시각 피드백 보장(globals.css 무변경 —
                // :focus-visible/​:hover 자체는 아래 styled-jsx 스코프 CSS 로 처리).
                outline: focusedOpt === idx ? '2px solid var(--gold)' : 'none',
                outlineOffset: focusedOpt === idx ? 2 : 0,
              }}
              onClick={() => selectOption(question, opt)}
            >
              <span aria-hidden="true" style={s.optEmoji}>
                {opt.emoji}
              </span>
              <span style={s.optLabel}>{opt.label}</span>
              <span style={s.optSub}>{opt.sub}</span>
            </button>
          ))}
        </div>
        {state.idx > 0 ? (
          <button type="button" style={s.back} onClick={goBack}>
            ← Volver
          </button>
        ) : null}
        <style jsx>{`
          .qz-opts {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
            gap: 12px;
          }
          @media (max-width: 639px) {
            .qz-opts {
              grid-template-columns: 1fr;
            }
          }
          .qz-opt {
            transition:
              border-color 0.15s,
              transform 0.1s;
          }
          .qz-opt:hover {
            border-color: var(--gold);
            transform: translateY(-2px);
          }
          .qz-opt:focus-visible {
            outline: 2px solid var(--gold);
            outline-offset: 2px;
          }
        `}</style>
      </section>
    );
  }

  // ---- 상태 3: 결과 ----
  const answeredOptions = Object.values(answers);
  const loading = results === null;
  const isEmpty = results !== null && results.length === 0;

  return (
    <section style={s.resWrap}>
      <div style={s.resHead}>
        <div style={s.kicker}>TU SELECCIÓN</div>
        <h2 ref={headingRef} tabIndex={-1} style={s.resHeading}>
          {loading
            ? 'Buscando lo tuyo...'
            : isEmpty
              ? 'Por ahora no tenemos algo que combine exacto'
              : 'Esto es lo tuyo'}
        </h2>
        {!loading && !isEmpty ? (
          <p style={s.resSub}>
            Elegimos 3 según tus respuestas — el resto del catálogo sigue
            disponible.
          </p>
        ) : null}
        <div style={s.tags}>
          {answeredOptions.map((opt, idx) => (
            <span key={idx} style={s.tag}>
              {opt.label}
            </span>
          ))}
        </div>
      </div>

      {!loading && !isEmpty ? (
        <div className="qz-rgrid">
          {(results ?? []).map(({ product, score }) => (
            <div key={product.id} style={s.pc}>
              <span style={s.match}>MATCH {score}%</span>
              {product.imageUrl ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img
                  src={minioImageUrl(product.imageUrl)}
                  alt={product.name}
                  style={s.pcImg}
                />
              ) : (
                <div
                  style={{
                    ...s.pcImg,
                    backgroundImage: placeholderGradient(product.id),
                  }}
                />
              )}
              <div style={s.pcBody}>
                <div style={s.pcName}>{product.name}</div>
                <div style={s.pcPrice}>{money(product.price)}</div>
                <div style={s.pcWhy}>
                  {answeredOptions.map((opt, idx) => (
                    <div key={idx}>✓ {opt.sub}</div>
                  ))}
                </div>
              </div>
              <button type="button" style={s.pcAdd} onClick={() => add(product)}>
                Agregar al carrito
              </button>
            </div>
          ))}
        </div>
      ) : !loading && isEmpty ? (
        <p style={s.emptyMsg}>
          Probá con otras combinaciones o mirá el catálogo completo — seguro
          encontrás algo.
        </p>
      ) : null}

      <div style={s.resAlt}>
        {whatsappHref ? (
          <a
            href={whatsappHref}
            target="_blank"
            rel="noopener noreferrer"
            style={s.whatsappBtn}
          >
            💬 Asesorame por WhatsApp
          </a>
        ) : null}
        <button type="button" style={s.altBtn} onClick={repeatQuiz}>
          ↺ Repetir quiz
        </button>
        <button
          type="button"
          style={isEmpty ? s.altBtnPrimary : s.altBtn}
          onClick={() => router.push(catalogHref)}
        >
          Ver catálogo completo →
        </button>
      </div>
      <style jsx>{`
        .qz-rgrid {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
          gap: 16px;
          padding: 24px 24px 8px;
        }
        @media (min-width: 640px) {
          .qz-rgrid {
            grid-template-columns: repeat(3, 1fr);
          }
        }
      `}</style>
    </section>
  );
}

const s: Record<string, CSSProperties> = {
  // ── 상태 1: 배너 ──
  bannerWrap: {
    display: 'flex',
    alignItems: 'center',
    gap: 20,
    background: 'linear-gradient(120deg, var(--hero-from), var(--hero-to))',
    color: 'var(--on-navy)',
    padding: '24px 32px',
    borderRadius: 'var(--radius)',
    margin: '24px 0',
  },
  bannerEmoji: { fontSize: 32, flexShrink: 0 },
  bannerText: { flex: 1 },
  bannerTitle: {
    fontSize: 20,
    fontFamily: 'var(--font-display)',
    fontWeight: 'var(--disp-weight)',
    margin: 0,
  },
  bannerSubtitle: { fontSize: 13, opacity: 0.8, margin: '4px 0 0' },
  bannerCta: { flexShrink: 0, padding: '12px 24px' },

  // ── 상태 2: 질문 ──
  quizWrap: {
    maxWidth: 640,
    margin: '0 auto',
    padding: '32px 24px 48px',
    minHeight: 432,
  },
  prog: { display: 'flex', alignItems: 'center', gap: 8, marginBottom: 24 },
  progTrack: {
    flex: 1,
    height: 4,
    background: 'var(--soft)',
    borderRadius: 3,
    overflow: 'hidden',
  },
  progFill: {
    display: 'block',
    height: '100%',
    background: 'var(--gold)',
    borderRadius: 3,
    transition: 'width .3s',
  },
  progLabel: { fontSize: 12, color: 'var(--muted)', fontWeight: 400 },
  kicker: {
    fontSize: 12,
    letterSpacing: 2,
    color: 'var(--gold-d)',
    fontWeight: 800,
  },
  questionText: {
    fontSize: 20,
    margin: '8px 0 24px',
    lineHeight: 1.25,
    fontFamily: 'var(--font-display)',
    fontWeight: 'var(--disp-weight)',
  },
  opt: {
    background: 'var(--card)',
    border: '1.5px solid var(--line)',
    borderRadius: 12,
    padding: 16,
    textAlign: 'center',
    cursor: 'pointer',
  },
  optEmoji: { fontSize: 32, display: 'block', marginBottom: 8 },
  optLabel: { fontSize: 13, display: 'block', color: 'var(--ink)' },
  optSub: {
    fontSize: 12,
    color: 'var(--muted)',
    display: 'block',
    marginTop: 4,
    lineHeight: 1.4,
  },
  back: {
    marginTop: 24,
    background: 'none',
    border: 'none',
    fontSize: 12,
    color: 'var(--muted)',
    cursor: 'pointer',
    textDecoration: 'underline',
  },

  // ── 상태 3: 결과 ──
  resWrap: { margin: '24px 0' },
  resHead: { textAlign: 'center', padding: '32px 24px 8px' },
  resHeading: {
    fontSize: 20,
    fontFamily: 'var(--font-display)',
    fontWeight: 'var(--disp-weight)',
    margin: '8px 0 0',
  },
  resSub: { fontSize: 13, color: 'var(--muted)', margin: '6px 0 0' },
  tags: {
    display: 'flex',
    gap: 8,
    justifyContent: 'center',
    flexWrap: 'wrap',
    marginTop: 12,
  },
  tag: {
    background: 'var(--card)',
    border: '1px solid var(--line)',
    borderRadius: 14,
    padding: '4px 12px',
    fontSize: 12,
    color: 'var(--ink)',
  },
  pc: {
    background: 'var(--card)',
    border: '1px solid var(--line)',
    borderRadius: 10,
    overflow: 'hidden',
    position: 'relative',
  },
  match: {
    position: 'absolute',
    top: 8,
    left: 8,
    background: 'var(--navy)',
    color: 'var(--gold)',
    fontSize: 12,
    fontWeight: 800,
    borderRadius: 5,
    padding: '4px 8px',
    zIndex: 2,
  },
  pcImg: { width: '100%', height: 172, objectFit: 'cover' },
  pcBody: { padding: 12 },
  pcName: { fontSize: 13, color: 'var(--ink)' },
  pcPrice: {
    fontSize: 20,
    fontWeight: 'var(--disp-weight)',
    color: 'var(--ink)',
    marginTop: 3,
  },
  pcWhy: {
    fontSize: 12,
    color: 'var(--muted)',
    marginTop: 8,
    lineHeight: 1.4,
    borderTop: '1px dashed var(--line)',
    paddingTop: 8,
  },
  pcAdd: {
    display: 'block',
    width: '100%',
    background: 'var(--navy)',
    color: 'var(--on-navy)',
    border: 'none',
    padding: 8,
    fontSize: 14,
    fontWeight: 700,
    cursor: 'pointer',
  },
  emptyMsg: {
    textAlign: 'center',
    color: 'var(--muted)',
    fontSize: 13,
    padding: '24px 24px 8px',
  },
  resAlt: {
    display: 'flex',
    gap: 12,
    justifyContent: 'center',
    flexWrap: 'wrap',
    padding: '12px 24px 32px',
  },
  // WhatsApp 브랜드 고정색 — UI-SPEC 이 명시한 하드코딩 허용 예외 2건 중 하나(WhatsAppFloat.tsx 와 동일)
  whatsappBtn: {
    background: '#25d366',
    color: 'var(--on-navy)',
    borderRadius: 'var(--radius)',
    padding: '12px 20px',
    fontWeight: 700,
    fontSize: 14,
    textDecoration: 'none',
    display: 'inline-block',
  },
  altBtn: {
    background: 'var(--card)',
    border: '1px solid var(--line)',
    color: 'var(--ink)',
    borderRadius: 'var(--radius)',
    padding: '12px 20px',
    fontWeight: 700,
    fontSize: 14,
    cursor: 'pointer',
  },
  altBtnPrimary: {
    background: 'var(--gold)',
    border: '1px solid var(--gold)',
    color: 'var(--navy)',
    borderRadius: 'var(--radius)',
    padding: '12px 20px',
    fontWeight: 700,
    fontSize: 14,
    cursor: 'pointer',
  },
};
