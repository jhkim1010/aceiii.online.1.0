import { useState } from 'react';
import type { CSSProperties } from 'react';
import { useShop } from '@/context/ShopContext';
import { tryOnFromProduct } from '@/services/shop-api';

export default function TryOnModal() {
  const { tryOnProduct, closeTryOn, storeId, add } = useShop();
  const [file, setFile] = useState<File | null>(null);
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<string | null>(null);
  const [msg, setMsg] = useState('');
  const [err, setErr] = useState('');

  if (!tryOnProduct) return null;

  async function run() {
    setErr('');
    setMsg('');
    if (!file) {
      setErr('Subí una foto primero.');

      return;
    }

    setBusy(true);
    try {
      const res = await tryOnFromProduct(storeId, tryOnProduct!.id, file);
      setResult(res.resultImageDataUrl);
      setMsg(res.message || '');
    } catch (e) {
      setErr(`Error: ${(e as Error).message}`);
    } finally {
      setBusy(false);
    }
  }

  function close() {
    setFile(null);
    setResult(null);
    setMsg('');
    setErr('');
    closeTryOn();
  }

  return (
    <div style={s.overlay} onClick={close}>
      <div style={s.modal} onClick={(e) => e.stopPropagation()}>
        <div style={s.head}>
          <h3 style={s.title}>Probar: {tryOnProduct.name}</h3>
          <button style={s.x} onClick={close} aria-label="Cerrar">
            ×
          </button>
        </div>
        <p style={s.sub}>Subí tu foto y mirá cómo te queda. (No se guarda tu foto)</p>

        <input
          type="file"
          accept="image/*"
          onChange={(e) => setFile(e.target.files?.[0] ?? null)}
        />

        <button
          className="btn btn-gold"
          style={s.run}
          disabled={busy}
          onClick={run}
        >
          {busy ? 'Procesando...' : 'Probármelo'}
        </button>

        {err ? <div style={s.err}>{err}</div> : null}

        {result ? (
          <>
            {/* 결과 미리보기 — eslint-disable-next-line @next/next/no-img-element */}
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={result} alt="Resultado" style={s.res} />
            <div style={s.msg}>{msg}</div>
            <button
              className="btn btn-ghost"
              style={s.run}
              onClick={() => {
                add(tryOnProduct);
                close();
              }}
            >
              Agregar al carrito
            </button>
          </>
        ) : null}
      </div>
    </div>
  );
}

const s: Record<string, CSSProperties> = {
  overlay: {
    position: 'fixed',
    inset: 0,
    background: 'rgba(0,0,0,0.5)',
    zIndex: 50,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    padding: 16,
  },
  modal: {
    width: 440,
    maxWidth: '94vw',
    background: '#fff',
    borderRadius: 14,
    padding: 18,
  },
  head: { display: 'flex', alignItems: 'center', justifyContent: 'space-between' },
  title: { margin: 0, fontSize: 16, color: 'var(--ink)' },
  x: { border: 'none', background: 'transparent', fontSize: 22, color: 'var(--muted)' },
  sub: { color: 'var(--muted)', fontSize: 12, margin: '4px 0 14px' },
  run: { width: '100%', marginTop: 12, borderRadius: 10, padding: 12 },
  res: {
    width: '100%',
    maxHeight: 360,
    objectFit: 'contain',
    borderRadius: 10,
    background: 'var(--soft)',
    marginTop: 12,
  },
  msg: { fontSize: 12, color: 'var(--muted)', marginTop: 8 },
  err: { color: 'var(--red)', fontSize: 13, marginTop: 8 },
};
