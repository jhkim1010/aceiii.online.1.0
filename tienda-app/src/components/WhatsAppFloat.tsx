import type { CSSProperties } from 'react';
import { useThemeContent } from '@/context/ThemeContentContext';

export default function WhatsAppFloat() {
  const { contact } = useThemeContent();

  if (!contact.whatsapp) return null;

  const digits = contact.whatsapp.replace(/[^0-9]/g, '');

  if (!digits) return null;

  return (
    <a
      href={`https://wa.me/${digits}`}
      target="_blank"
      rel="noopener noreferrer"
      aria-label="Contactar por WhatsApp"
      style={s.fab}
    >
      <span aria-hidden="true">💬</span>
    </a>
  );
}

// WhatsApp 브랜드 고정색 — UI-SPEC 이 명시적으로 허용한 하드코딩 예외 2건 중 하나(테마 CSS
// 변수 체계 밖). z-index 30 은 Header(20)보다 위, 마케팅 팝업(Plan 61-15, 50)보다 아래.
const s: Record<string, CSSProperties> = {
  fab: {
    position: 'fixed',
    bottom: 16,
    right: 16,
    width: 48,
    height: 48,
    borderRadius: '50%',
    background: '#25d366',
    color: '#ffffff',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    fontSize: 24,
    textDecoration: 'none',
    boxShadow: '0 4px 12px rgba(0,0,0,0.25)',
    zIndex: 30,
  },
};
