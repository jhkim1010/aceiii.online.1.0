import type { AppProps } from 'next/app';
import '@/styles/globals.css';
import { ShopProvider } from '@/context/ShopContext';
import CartDrawer from '@/components/CartDrawer';
import TryOnModal from '@/components/TryOnModal';

export default function App({ Component, pageProps }: AppProps) {
  return (
    <ShopProvider>
      <Component {...pageProps} />
      <CartDrawer />
      <TryOnModal />
    </ShopProvider>
  );
}
