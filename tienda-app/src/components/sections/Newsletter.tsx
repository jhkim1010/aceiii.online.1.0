import { useState } from 'react';
import type { CSSProperties, FormEvent } from 'react';
import type { NewsletterSection } from '@/types/shop';

export default function Newsletter({ section }: { section: NewsletterSection }) {
  const [submitted, setSubmitted] = useState(false);

  const onSubmit = (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault();

    // TODO(후속 Phase): 뉴스레터 구독 저장 엔드포인트 없음 — 현재는 클라이언트 표시만. 실제 수집 연동 필요.
    setSubmitted(true);
  };

  return (
    <section style={s.wrap}>
      <h2 style={s.title}>{section.title || 'Suscribite a novedades'}</h2>
      {submitted ? (
        <p style={s.msg}>¡Listo! Te vamos a escribir.</p>
      ) : (
        <form style={s.form} onSubmit={onSubmit}>
          <input
            type="email"
            required
            placeholder="Tu email"
            style={s.input}
          />
          <button className="btn btn-gold" type="submit">
            Suscribirme
          </button>
        </form>
      )}
    </section>
  );
}

const s: Record<string, CSSProperties> = {
  wrap: {
    margin: '32px 0',
    borderRadius: 'var(--radius)',
    padding: 32,
    background: 'var(--soft)',
    border: '1px solid var(--line)',
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    gap: 16,
  },
  title: {
    fontSize: 20,
    margin: 0,
    fontFamily: 'var(--font-display)',
    fontWeight: 'var(--disp-weight)',
  },
  form: { display: 'flex', gap: 8 },
  input: {
    border: '1px solid var(--line)',
    borderRadius: 'var(--radius)',
    padding: '8px 12px',
    background: 'var(--card)',
    color: 'var(--ink)',
  },
  msg: { margin: 0, fontSize: 13, color: 'var(--muted)' },
};
