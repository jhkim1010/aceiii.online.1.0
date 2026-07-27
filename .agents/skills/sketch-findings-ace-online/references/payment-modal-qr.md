# Payment Modal + QR Side-Panel Pattern

`PaymentSummaryModal` 확장으로 QR 기반 결제 (Mercadopago QR Dinámico, 향후 Point/online 결제 등) 를 처리하는 패턴. **Side-panel variant 가 winner** — 좌측에서 다른 결제수단 동시 입력 가능.

## Design Decisions

- **Layout: 1fr + 320px grid** — 좌측은 기존 결제수단 UI 그대로 유지, 우측에 320px panel 추가 (`gridTemplateColumns: '1fr 320px'`)
- **Panel 은 mp-row 가 선택된 경우에만 mount** — 없으면 grid 단일 컬럼 (`1fr` 만)
- **Panel border** 좌측 2px:
  - Production: `info.main` (cyan `#00b1ea`)
  - Sandbox: `warning.main` (gold `#f5a623`)
- **QR 위치:** 패널 가운데, `<QRCodeSVG size={180}>` (모달 컨텍스트에서는 256보다 180 이 적절 — panel width 가 320px)
- **카운트다운:** mono font, `#f5a623` 골드, 30초 미만 시 `#ef4444` 빨강 전환
- **Panel actions:** "Cancelar QR" 버튼 (outlined small) — primary "Generar Venta" 와 분리해서 사용자가 실수로 venta 생성 안 하도록
- **Auto Generar Venta trigger:** webhook 또는 polling 으로 `mercadopago:approved` 이벤트 수신 시 `handleSubmit("INVOICED", paymentMethods)` 자동 호출 → modal close

## Why side-panel won (vs Inline / Dialog)

| Variant | 장점 | 단점 | 결과 |
|---------|-----|------|------|
| A: Inline (QR 행 아래) | 한 화면 통합 | 모달 세로 길어짐, 다른 결제수단 행 아래로 밀림 | ❌ |
| **B: Side-panel** | **좌측 변하지 않음, cash 입력 + QR 모니터링 동시 가능** | **모달 가로 ≥ 920px 필요 (POS 화면 크기 충분)** | **★ winner** |
| C: Separate dialog | 모달 분리로 깔끔 | 사용자 시선 분산, dimmed background 혼란 | ❌ |

POS 의 핵심 사용 케이스: split payment (예: 50,000 = MP 30,000 + Efectivo 20,000). 사용자가 QR 보여주는 동안 cash 행 입력 → MP confirm 도착 → 자동 venta. 이 흐름에 side-panel 이 자연스럽다.

## State Flow (3 states)

```
waiting (orange pulse dot, countdown 02:47 → 0:00)
  ↓ webhook arrives OR polling tick OR manual cancel
approved (green ✓ check, fade-in success state, "Generando venta…")
  ↓ 약 1초 후 자동 venta 생성 + modal close
expired (red ✗, "QR expirado", "Generar nuevo QR" button)
```

Frontend `processedIntentId` ref guard 필수 (webhook + polling 양쪽 도착 시 sale 중복 생성 방지 — RESEARCH.md 발견).

## CSS Patterns

```css
.modal-with-side {
  display: grid;
  grid-template-columns: 1fr 320px;
  gap: 0;
  max-width: 920px;
}
.modal-side-panel {
  background: var(--color-surface-2);
  border-left: 1px solid var(--color-border);
  padding: 24px;
  display: flex; flex-direction: column; gap: 16px;
}

/* Sandbox border override */
.modal-side-panel.sandbox { border-left: 2px solid var(--color-warning); }
.modal-side-panel.production { border-left: 2px solid var(--color-mp); }

/* Pulse animation for waiting state */
.qr-status .dot {
  width: 8px; height: 8px; border-radius: 50%;
  background: var(--color-warning);
  animation: pulse 1.4s ease-in-out infinite;
}
@keyframes pulse {
  0%, 100% { opacity: 1; box-shadow: 0 0 0 0 rgba(245,166,35,0.5); }
  50% { opacity: 0.6; box-shadow: 0 0 0 6px rgba(245,166,35,0); }
}

/* Countdown */
.countdown {
  display: flex; align-items: center; gap: 10px;
  background: var(--color-surface-2);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  padding: 8px 14px;
  font-family: var(--font-mono);
  font-size: 1.125rem; font-weight: 600;
  color: var(--color-warning);
}
.countdown.expiring { color: var(--color-danger); }

/* Success / expired states */
.qr-success {
  display: flex; flex-direction: column; align-items: center; gap: 16px;
  padding: 40px 24px;
  background: var(--color-success-soft);
  border: 2px solid var(--color-success);
  border-radius: var(--radius-lg);
  color: var(--color-success);
  animation: fadeIn 0.3s ease;
}
@keyframes fadeIn { from { opacity: 0; transform: translateY(8px); } to { opacity: 1; transform: translateY(0); } }
```

## React / MUI 5 Implementation Sketch

```tsx
function PaymentSummaryModal({ open, total, onClose }) {
  const [methods, setMethods] = useState<PaymentMethod[]>([]);
  const mpRow = methods.find(m => m.slug === 'mercadopago');
  const mpSelected = Boolean(mpRow);
  const [intent, setIntent] = useState<MpPaymentIntent | null>(null);
  const processedIntentRef = useRef<string | null>(null);

  // SWR polling fallback
  const { data: intentStatus, mutate } = useSWR(
    intent?.id ? `/api/mercadopago/payment-intents/${intent.id}` : null,
    apiConnector.get,
    { refreshInterval: 5000 }
  );

  // Socket.io webhook listener
  useSocketEvent('mercadopago:approved', (payload) => {
    if (payload.intentId === intent?.id) mutate();
  });

  // Auto-trigger generar venta on approved (with idempotency guard)
  useEffect(() => {
    if (intentStatus?.status === 'approved' && processedIntentRef.current !== intent.id) {
      processedIntentRef.current = intent.id;
      handleSubmit('INVOICED', methods);
    }
  }, [intentStatus?.status]);

  return (
    <Dialog open={open} onClose={onClose} maxWidth={false}>
      <Box sx={{
        display: 'grid',
        gridTemplateColumns: mpSelected ? '1fr 320px' : '1fr',
        maxWidth: mpSelected ? 920 : 600,
      }}>
        {/* Left — payment methods */}
        <Box sx={{ p: 2.5 }}>
          <PaymentMethodList methods={methods} onChange={setMethods} total={total} />
          <DialogActions>
            <Button onClick={onClose}>Cancelar</Button>
            <Button variant="contained" disabled={!isComplete(methods, total)}>
              Generar Venta (F2)
            </Button>
          </DialogActions>
        </Box>

        {/* Right — QR side panel (only when MP selected) */}
        {mpSelected && (
          <Box sx={{
            bgcolor: 'background.default',
            borderLeft: 2,
            borderColor: account?.environment === 'sandbox' ? 'warning.main' : 'info.main',
            p: 3,
            display: 'flex',
            flexDirection: 'column',
            gap: 2,
          }}>
            {intentStatus?.status === 'approved' ? (
              <ApprovedState payment={intentStatus} />
            ) : intentStatus?.status === 'expired' ? (
              <ExpiredState onRetry={() => createIntent(mpRow.amount)} />
            ) : (
              <>
                <Stack direction="row" alignItems="center" spacing={1}>
                  <Chip size="small" color={account?.environment === 'sandbox' ? 'warning' : 'info'}
                        label="QR DINÁMICO" />
                  <Typography variant="caption" sx={{ fontFamily: 'monospace' }}>
                    {formatCountdown(secondsLeft)}
                  </Typography>
                </Stack>
                <Box sx={{ bgcolor: '#fff', p: 1.5, borderRadius: 2, display: 'flex', justifyContent: 'center' }}>
                  <QRCodeSVG value={intent.qrData} size={180} level="M" />
                </Box>
                <Typography variant="caption" align="center">Escaneá con la app MP</Typography>
                <Typography variant="h6" align="center" sx={{ fontFamily: 'monospace', color: 'primary.main' }}>
                  $ {formatAmount(mpRow.amount)}
                </Typography>
                <Button size="small" variant="outlined" onClick={cancelIntent}>Cancelar QR</Button>
              </>
            )}
          </Box>
        )}
      </Box>
    </Dialog>
  );
}
```

## What to Avoid

- **Inline QR** — 사용자가 다른 결제수단 입력하려면 스크롤 필요
- **Separate dialog** — 사용자가 어느 모달에서 작업해야 할지 혼동
- **MP API SDK 사용** — RESEARCH.md confirmed MP Node SDK does NOT cover QR Dinámico endpoints. Use raw axios (`MpApiClientService`) with per-store token injection.
- **Webhook 만 의존** — 양쪽 (webhook + 5초 polling) 모두 필요. webhook 지연/유실 흔함.

## Origin

Synthesized from sketch 001 area 2 (PaymentSummaryModal + QR Dinámico) — D-A4-01 + D-A4-02. Winner: Variant B (Side-panel).
Source: `sources/001-phase-29-mp-qr-suite/index.html` Area 2 section.
