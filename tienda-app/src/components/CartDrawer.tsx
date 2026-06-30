import { useState } from 'react';
import type { CSSProperties } from 'react';
import { useShop } from '@/context/ShopContext';
import { money } from '@/lib/format';
import { checkout } from '@/services/shop-api';

export default function CartDrawer() {
  const { cart, inc, dec, total, drawerOpen, closeDrawer, storeId } = useShop();
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);

  const lines = Object.values(cart);

  async function finalize() {
    setNote('');
    if (lines.length === 0) {
      setNote('El carrito está vacío.');

      return;
    }

    setBusy(true);
    try {
      const res = await checkout(storeId, {
        clientName: name.trim() || undefined,
        clientEmail: email.trim() || undefined,
        items: lines.map((l) => ({ productId: l.product.id, quantity: l.qty })),
      });

      if (res.initPoint) {
        window.location.href = res.initPoint;

        return;
      }
      setNote(`Orden #${res.orderNumber} creada. (Pago no disponible: sin cuenta MP)`);
    } catch (e) {
      setNote(`No se pudo pagar: ${(e as Error).message}`);
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <div
        style={{ ...s.overlay, display: drawerOpen ? 'block' : 'none' }}
        onClick={closeDrawer}
      />
      <aside
        style={{
          ...s.drawer,
          transform: drawerOpen ? 'translateX(0)' : 'translateX(100%)',
        }}
      >
        <h3 style={s.title}>Tu carrito</h3>
        <div style={s.items}>
          {lines.length === 0 ? (
            <div style={s.muted}>Carrito vacío.</div>
          ) : (
            lines.map((l) => (
              <div key={l.product.id} style={s.ci}>
                <div style={s.ciName}>
                  {l.product.name}
                  <br />
                  <span style={s.muted}>{money(l.product.price)}</span>
                </div>
                <div style={s.qty}>
                  <button style={s.qtyBtn} onClick={() => dec(l.product.id)}>
                    −
                  </button>
                  <span>{l.qty}</span>
                  <button style={s.qtyBtn} onClick={() => inc(l.product.id)}>
                    +
                  </button>
                </div>
              </div>
            ))
          )}
        </div>
        <div style={s.foot}>
          <div style={s.total}>
            Total <b style={{ color: 'var(--gold-d)' }}>{money(total)}</b>
          </div>
          <input
            style={s.input}
            placeholder="Tu nombre"
            value={name}
            onChange={(e) => setName(e.target.value)}
          />
          <input
            style={s.input}
            type="email"
            placeholder="Tu email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
          />
          <button
            className="btn btn-gold"
            style={s.pay}
            disabled={busy}
            onClick={finalize}
          >
            {busy ? 'Procesando...' : 'Finalizar compra'}
          </button>
          {note ? <div style={s.note}>{note}</div> : null}
        </div>
      </aside>
    </>
  );
}

const s: Record<string, CSSProperties> = {
  overlay: {
    position: 'fixed',
    inset: 0,
    background: 'rgba(0,0,0,0.45)',
    zIndex: 40,
  },
  drawer: {
    position: 'fixed',
    top: 0,
    right: 0,
    height: '100%',
    width: 380,
    maxWidth: '92vw',
    background: '#fff',
    borderLeft: '1px solid var(--line)',
    zIndex: 41,
    transition: 'transform 0.2s',
    display: 'flex',
    flexDirection: 'column',
  },
  title: {
    margin: 0,
    padding: '16px 18px',
    borderBottom: '1px solid var(--line)',
    color: 'var(--ink)',
  },
  items: { flex: 1, overflow: 'auto', padding: '12px 18px' },
  ci: {
    display: 'flex',
    gap: 10,
    alignItems: 'center',
    padding: '10px 0',
    borderBottom: '1px solid var(--line)',
  },
  ciName: { flex: 1, fontSize: 13 },
  qty: { display: 'flex', alignItems: 'center', gap: 6 },
  qtyBtn: {
    width: 26,
    height: 26,
    borderRadius: 6,
    border: '1px solid var(--line)',
    background: '#fff',
  },
  foot: { padding: '16px 18px', borderTop: '1px solid var(--line)' },
  total: {
    display: 'flex',
    justifyContent: 'space-between',
    fontSize: 17,
    margin: '4px 0 12px',
  },
  input: {
    width: '100%',
    margin: '6px 0',
    background: '#fff',
    border: '1px solid var(--line)',
    borderRadius: 8,
    padding: '9px 10px',
    fontSize: 14,
  },
  pay: { width: '100%', borderRadius: 10, padding: 13, fontSize: 15 },
  note: { fontSize: 12, color: 'var(--muted)', marginTop: 8 },
  muted: { color: 'var(--muted)', fontSize: 13 },
};
