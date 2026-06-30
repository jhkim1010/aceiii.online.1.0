import {
  createContext,
  useCallback,
  useContext,
  useMemo,
  useState,
} from 'react';
import type { ReactNode } from 'react';
import type { ShopProduct } from '@/types/shop';

interface CartLine {
  product: ShopProduct;
  qty: number;
}

interface ShopState {
  storeId: number;
  setStoreId: (id: number) => void;
  cart: Record<number, CartLine>;
  add: (p: ShopProduct) => void;
  inc: (id: number) => void;
  dec: (id: number) => void;
  clear: () => void;
  count: number;
  total: number;
  drawerOpen: boolean;
  openDrawer: () => void;
  closeDrawer: () => void;
  tryOnProduct: ShopProduct | null;
  openTryOn: (p: ShopProduct) => void;
  closeTryOn: () => void;
}

const ShopCtx = createContext<ShopState | null>(null);

export function ShopProvider({ children }: { children: ReactNode }) {
  const [storeId, setStoreId] = useState<number>(1);
  const [cart, setCart] = useState<Record<number, CartLine>>({});
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [tryOnProduct, setTryOnProduct] = useState<ShopProduct | null>(null);

  // 장바구니 조작 — 함수 정체성 유지(불필요 리렌더 방지)
  const add = useCallback((p: ShopProduct) => {
    setCart((prev) => {
      const line = prev[p.id];

      return { ...prev, [p.id]: { product: p, qty: (line?.qty ?? 0) + 1 } };
    });
    setDrawerOpen(true);
  }, []);

  const inc = useCallback((id: number) => {
    setCart((prev) => {
      const line = prev[id];
      if (!line) return prev;

      return { ...prev, [id]: { ...line, qty: line.qty + 1 } };
    });
  }, []);

  const dec = useCallback((id: number) => {
    setCart((prev) => {
      const line = prev[id];
      if (!line) return prev;

      const qty = line.qty - 1;
      if (qty <= 0) {
        const next = { ...prev };
        delete next[id];

        return next;
      }

      return { ...prev, [id]: { ...line, qty } };
    });
  }, []);

  const clear = useCallback(() => setCart({}), []);

  const { count, total } = useMemo(() => {
    let c = 0;
    let t = 0;
    for (const id of Object.keys(cart)) {
      const line = cart[Number(id)];
      c += line.qty;
      t += (line.product.price || 0) * line.qty;
    }

    return { count: c, total: t };
  }, [cart]);

  const value = useMemo<ShopState>(
    () => ({
      storeId,
      setStoreId,
      cart,
      add,
      inc,
      dec,
      clear,
      count,
      total,
      drawerOpen,
      openDrawer: () => setDrawerOpen(true),
      closeDrawer: () => setDrawerOpen(false),
      tryOnProduct,
      openTryOn: (p: ShopProduct) => setTryOnProduct(p),
      closeTryOn: () => setTryOnProduct(null),
    }),
    [storeId, cart, add, inc, dec, clear, count, total, drawerOpen, tryOnProduct],
  );

  return <ShopCtx.Provider value={value}>{children}</ShopCtx.Provider>;
}

export function useShop(): ShopState {
  const ctx = useContext(ShopCtx);
  if (!ctx) {
    throw new Error('useShop must be used within ShopProvider');
  }

  return ctx;
}
