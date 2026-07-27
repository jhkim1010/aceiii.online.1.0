# Theme — Ventago Dark Navy + Gold

Validated visual vocabulary for all new Ventago UI surfaces. Matches `print-agent` / `zebra-agent` Electron windows so users see one cohesive Ventago across the entire stack.

## Design Decisions

- **Bg base:** `#0f0f1e` — deeper navy than the surface, used on `<body>` so card-shaped surfaces float visually.
- **Surface:** `#1a1a2e` — matches print-agent / zebra-agent exactly. Used for cards, modals, sidebar.
- **Surface-2 / Surface-3:** `#232342` / `#2a2a4a` — for input fields, hover backgrounds, cycler buttons.
- **Border:** `#333355` resting / `#4a4a6e` hover.
- **Primary (gold):** `#f5a623` — same gold as print-agent / zebra-agent. CTAs, brand dot, active tab underline, primary button bg.
- **Primary hover:** `#ffb84d` — slightly lighter gold.
- **MP brand (cyan):** `#00b1ea` — Mercadopago's brand cyan. Reserved for MP-specific UI: chips, row-highlight tint, modal borde when production.
- **Sandbox === warning:** `#f5a623` (same as primary gold). Banner + modal borde reuse the primary gold so "test mode" reads as a friendly Ventago accent rather than alarming red.
- **Danger:** `#ef4444` red for refund failure / disconnect / dangerous destructive actions.
- **Success:** `#4ade80` green for "Conectada", money positive balances, paid status.
- **Info:** `#60a5fa` blue for neutral "how it works" alerts.

## Typography

- **Font sans:** `'Roboto', 'Helvetica Neue', system-ui, -apple-system, sans-serif` — matches MUI default chain.
- **Font mono:** `'JetBrains Mono', 'SF Mono', Menlo, monospace` — used for currency amounts, payment_id, timestamps, account IDs.
- **Sizes (rem):** xs 0.7 · sm 0.825 · base 0.9375 · lg 1.0625 · xl 1.25 · 2xl 1.5 · 3xl 1.875.
- Body line-height 1.5, antialiased.

## Spacing scale

`4 · 8 · 12 · 16 · 20 · 24 · 32 · 40 · 48` (px) → CSS vars `--space-1` through `--space-12` (matches MUI's 0.5/1/1.5/2/2.5/3/4/5/6 multiplier × 8px).

## Shapes

`--radius-sm` 4px (input small) · `--radius-md` 8px (button, input, alert) · `--radius-lg` 12px (card) · `--radius-xl` 16px (modal) · `--radius-full` 9999px (chip, toggle).

## Shadows

- `--shadow-sm`: subtle 1px shadow for chips/buttons elevated state.
- `--shadow-md`: card resting shadow `0 4px 12px rgba(0,0,0,0.4)`.
- `--shadow-lg`: modal shadow `0 12px 28px rgba(0,0,0,0.55)`.
- `--shadow-glow`: 3px halo of `--color-primary-soft` for focus states.

## CSS Patterns

```css
:root {
  --color-bg: #0f0f1e;
  --color-surface: #1a1a2e;
  --color-surface-2: #232342;
  --color-border: #333355;
  --color-text: #f4f4f8;
  --color-text-muted: #9999b3;
  --color-primary: #f5a623;
  --color-primary-soft: rgba(245, 166, 35, 0.12);
  --color-mp: #00b1ea;
  --color-mp-soft: rgba(0, 177, 234, 0.12);
  --color-warning: #f5a623; /* sandbox shares the gold */
  --color-warning-soft: rgba(245, 166, 35, 0.16);
  --color-danger: #ef4444;
  --color-success: #4ade80;
  --color-info: #60a5fa;
}

.mui-card {
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
  padding: var(--space-6);
  box-shadow: var(--shadow-md);
}
```

## What to Avoid

- **Pure black bg** — feels inert next to the navy. The 12% blue-tint base (`#0f0f1e`) is what gives Ventago its identity.
- **Bright `#fff` text on surface** — too much contrast. `#f4f4f8` (slightly off-white) is calmer.
- **Distinct sandbox color (red/yellow)** — tested mentally, decided gold reuse is intentional: sandbox is a friendly "Ventago is helping you test" signal, not a "warning, danger" signal.
- **MUI default blue** — never use `#1976d2`. Replace with cyan `#00b1ea` (MP) or gold `#f5a623` (primary).

## Origin

Synthesized from sketch 001 (phase-29-mp-qr-suite).
Theme file: `sources/themes/ventago-dark.css`.

## MUI 5 mapping (구현 시)

이 테마를 MUI 5 의 `createTheme()` 로 옮길 때:

```ts
createTheme({
  palette: {
    mode: 'dark',
    background: { default: '#0f0f1e', paper: '#1a1a2e' },
    primary: { main: '#f5a623', dark: '#1a1a2e', contrastText: '#1a1a2e' },
    info: { main: '#00b1ea' }, // MP brand
    warning: { main: '#f5a623' }, // sandbox
    success: { main: '#4ade80' },
    error: { main: '#ef4444' },
    text: { primary: '#f4f4f8', secondary: '#9999b3' },
    divider: '#333355',
  },
  shape: { borderRadius: 8 },
  typography: {
    fontFamily: 'Roboto, "Helvetica Neue", system-ui, sans-serif',
  },
});
```
