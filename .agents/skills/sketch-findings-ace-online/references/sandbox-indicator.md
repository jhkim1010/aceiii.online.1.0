# Sandbox Visual Indicator (Double-Signal Pattern)

외부 결제 통합이 sandbox 환경일 때 사용자가 "테스트 모드" 인지 즉시 인식하게 만드는 더블 시그널 패턴. **운영 매장이 실수로 테스트 결제 받지 않도록** 하는 것이 목적.

## Design Decisions

**더블 indicator (둘 다 동시에 노출):**

1. **Top banner** in `nueva-venta` (또는 결제 발생 페이지) 헤더:
   - `<Alert severity="warning">` 골드 톤
   - 좌측 🧪 flask icon + "SANDBOX MERCADOPAGO ACTIVO"
   - 우측 보조 정보 (계정 email) + "Cambiar a producción" text button → Configuración 으로 라우팅
   - **Sandbox account 가 활성일 때만 mount** — production 만 사용 시 invisible

2. **Modal QR borde** 가운데 결제 흐름 동안:
   - QR 패널의 `border-left` (side-panel variant) 또는 modal 전체 borde
   - Production: `info.main` (cyan) 2px
   - Sandbox: `warning.main` (gold) 2px + `box-shadow` 골드 glow

**색상 일관성:**
- Sandbox = warning = primary gold `#f5a623` (3개 모두 동일 색)
- "테스트 모드" 가 alarming 한 빨강이 아니라 친근한 골드 — Ventago 전체 톤과 자연스럽게 통합

## Why Double Signal

- POS 직원의 시야는 결제 흐름에 집중 — 상단 banner 만 두면 무시되기 쉬움.
- QR 모달 borde 는 가장 중요한 순간 (고객이 스캔 직전) 에 시각적 단서 제공.
- 고객도 모달을 보고 있으므로 sandbox borde 노출이 "이게 진짜 결제인가?" 혼동을 줄여줌.

## CSS Patterns

```css
.sandbox-banner {
  background: var(--color-warning-soft);
  border: 1px solid var(--color-warning-border);
  border-left: 4px solid var(--color-warning);
  padding: 10px 16px;
  display: flex; align-items: center; gap: 12px;
  border-radius: var(--radius-md);
  color: var(--color-warning);
  font-size: 0.875rem;
  font-weight: 500;
}
.sandbox-banner .flask { font-size: 18px; }
.sandbox-banner .label { letter-spacing: 0.04em; }

/* Modal/panel border (driven by environment prop) */
.modal-side-panel.sandbox {
  border-left: 2px solid var(--color-warning);
  box-shadow: 0 0 30px rgba(245,166,35,0.15);
}
.modal-side-panel.production {
  border-left: 2px solid var(--color-mp);
  box-shadow: 0 0 30px rgba(0,177,234,0.15);
}
```

## React / MUI 5 Implementation

```tsx
// Banner (mount conditionally at top of nueva-venta)
function SandboxBanner({ account }: { account?: MpAccount }) {
  const router = useRouter();
  if (account?.environment !== 'sandbox') return null;

  return (
    <Alert
      severity="warning"
      icon="🧪"
      action={
        <Button color="warning" size="small" onClick={() => router.push('/configuracion/mercadopago')}>
          Cambiar a producción
        </Button>
      }
      sx={{ mb: 2, borderLeftWidth: 4, borderLeftStyle: 'solid', borderLeftColor: 'warning.main' }}
    >
      <strong>SANDBOX MERCADOPAGO ACTIVO</strong>
      <Typography variant="caption" sx={{ ml: 2 }}>
        Los pagos no son reales. Cuenta sandbox: <strong>{account.email}</strong>
      </Typography>
    </Alert>
  );
}

// Border on QR panel (passed as prop)
<Box sx={{
  borderLeft: 2,
  borderColor: account?.environment === 'sandbox' ? 'warning.main' : 'info.main',
  boxShadow: account?.environment === 'sandbox'
    ? '0 0 30px rgba(245,166,35,0.15)'
    : '0 0 30px rgba(0,177,234,0.15)',
}}>
  {/* QR contents */}
</Box>
```

## When to Mount

- Banner: `MpAccountContext` 같은 hook 으로 현재 활성 계정 조회 → environment 확인 → conditional render
- Modal borde: `MpAccount` 가 props 또는 context 로 전달돼서 `environment` 분기

## What to Avoid

- **Sandbox 빨강 색** — 너무 alarming. POS 운영자가 "고장났나?" 오해.
- **Banner 만, modal borde 생략** — 결제 시점에 시각 단서 누락.
- **Modal borde 만, banner 생략** — 결제 모달 열기 전엔 sandbox 인지 모름.
- **계정 환경이 변경되었는데도 banner state 가 stale** — context invalidation 필수 (계정 disconnect / reconnect 시 즉시 갱신).

## Re-usable for

- Phase 30 (MP Point 단말기) — sandbox/production 동일 토글
- Phase 31 (MP Online Checkout) — preference 발급 시 같은 sandbox 표시
- 향후 다른 외부 결제 통합 (Ualá, Modo, etc.) — 동일 패턴 재사용

## Origin

Synthesized from sketch 001 area 3 (Sandbox indicator) — D-A4-02.
Source: `sources/001-phase-29-mp-qr-suite/index.html` Area 3 section.
