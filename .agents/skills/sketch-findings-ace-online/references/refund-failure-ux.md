# Refund Failure UX (Inline Alert + Toast + Retry + Dashboard Link + History)

외부 결제 게이트웨이의 자동 환불이 실패할 때 사용자에게 **즉시 visible + actionable** 한 UX. memory `feedback_error_visibility` 규약 준수 (인라인 + 글로벌 동시 노출).

## Design Decisions

**5개 element 동시 노출 (모두 한 화면에 visible):**

1. **Inline Alert** in `SalesDetailView` — 환불 결과 영역
   - `<Alert severity="error">` 빨간 톤
   - 제목: "Devolución MP fallida"
   - 본문: 에러 코드 + 메시지 (mono font 코드, 빨간 톤 backdrop)
   - 보조 안내: "Reintentá en unos segundos, o gestioná manualmente desde el panel de Mercadopago. La devolución del efectivo ya se procesó." (부분 환불 성공 case 명시)

2. **Action buttons** in same Alert (수평 배치):
   - 🔄 "Reintentar devolución" — primary danger button
   - ↗ "Abrir MP Dashboard" — outlined button → `https://www.mercadopago.com.ar/activities` 새 탭
   - "Ver historial" — text button → 페이지 내 attempts 영역으로 scroll

3. **Global toast** (자동 fired by axios interceptor 또는 manual):
   - 좌측 빨간 border + ⚠️ icon + 에러 메시지
   - `position: fixed; bottom-right`, `transform: translateY(120%)` → `translateY(0)` 슬라이드인
   - 3.5초 후 자동 dismiss

4. **Attempt history** (collapsible 또는 scroll target):
   - mono font row: `#N | FAILED | error_code — message | timestamp`
   - 모든 시도 기록 (시간 역순)

5. **Sale summary** 위에 상태 chip 변경: `<Chip color="warning">⚠ Devolución parcial</Chip>` (전체 실패 / 부분 성공 구분)

## CSS Patterns

```css
.toast {
  position: fixed; bottom: 24px; right: 24px;
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-left: 4px solid var(--color-danger);
  padding: 14px 18px;
  border-radius: var(--radius-md);
  box-shadow: var(--shadow-lg);
  display: flex; align-items: center; gap: 12px;
  font-size: 0.875rem;
  max-width: 360px;
  z-index: 200;
  transform: translateY(120%);
  transition: transform 0.3s ease;
}
.toast.show { transform: translateY(0); }
.toast.success { border-left-color: var(--color-success); }
.toast.error { border-left-color: var(--color-danger); }

.attempt-row {
  display: grid;
  grid-template-columns: 60px 100px 1fr 100px;
  gap: 12px;
  padding: 8px 12px;
  border-radius: 6px;
  background: var(--color-surface-2);
  margin-bottom: 4px;
  align-items: center;
  font-family: var(--font-mono);
  font-size: 0.75rem;
}
.attempt-row .status-fail { color: var(--color-danger); }
.attempt-row .status-ok { color: var(--color-success); }
```

## React / MUI 5 Implementation

```tsx
function SalesDetailView({ sale }) {
  const refundFailed = sale.refundStatus === 'failed';
  const lastAttempt = sale.refundAttempts?.[0];

  const [retrying, setRetrying] = useState(false);
  const handleRetry = async () => {
    setRetrying(true);
    try {
      await apiConnector.post(`/api/mercadopago/refunds/${sale.id}/retry`);
      mutate(`/api/sales/${sale.id}`);
      toast('Devolución completada', 'success');
    } catch (e) {
      toast(`Reintento #${attempts + 1} falló (${e.code}). Revisar manualmente en MP Dashboard.`, 'error');
    } finally {
      setRetrying(false);
    }
  };

  return (
    <Stack spacing={2}>
      <SaleSummary sale={sale} />
      <PaymentBreakdown methods={sale.paymentMethods} refundStatuses={sale.refundStatuses} />

      {refundFailed && (
        <Alert severity="error" icon="⚠️">
          <AlertTitle>Devolución MP fallida</AlertTitle>
          <Typography variant="body2">
            La devolución automática a Mercadopago no pudo procesarse:&nbsp;
            <Box component="code" sx={{ fontFamily: 'monospace', bgcolor: 'rgba(0,0,0,0.25)', px: 0.75, py: 0.25, borderRadius: 0.5, fontSize: '0.8rem', color: '#ffb4b4' }}>
              MP API {lastAttempt.errorCode}: {lastAttempt.errorMessage}
            </Box>
          </Typography>
          <Typography variant="body2" sx={{ my: 1.5 }}>
            Reintentá en unos segundos, o gestioná manualmente desde el panel de Mercadopago.
            {sale.cashRefunded && ' La devolución del efectivo ya se procesó.'}
          </Typography>
          <Stack direction="row" spacing={1} flexWrap="wrap">
            <Button color="error" variant="contained" size="small" onClick={handleRetry} disabled={retrying}>
              {retrying ? '⏳ Procesando…' : '🔄 Reintentar devolución'}
            </Button>
            <Button
              variant="outlined"
              size="small"
              component="a"
              href="https://www.mercadopago.com.ar/activities"
              target="_blank"
              rel="noopener"
            >
              ↗ Abrir MP Dashboard
            </Button>
            <Button
              size="small"
              onClick={() => document.getElementById('refund-attempts')?.scrollIntoView({ behavior: 'smooth' })}
            >
              Ver historial ({sale.refundAttempts.length} intentos)
            </Button>
          </Stack>
        </Alert>
      )}

      {sale.refundAttempts.length > 0 && (
        <Box id="refund-attempts">
          <Typography variant="caption" color="text.secondary">Historial de intentos</Typography>
          <Stack spacing={0.5} sx={{ mt: 1 }}>
            {sale.refundAttempts.map(a => (
              <Box className="attempt-row" key={a.id}>
                <span>#{a.attemptNo}</span>
                <span className={a.status === 'failed' ? 'status-fail' : 'status-ok'}>{a.status.toUpperCase()}</span>
                <span>{a.errorCode} — {a.errorMessage}</span>
                <span style={{ color: 'var(--color-text-muted)', textAlign: 'right' }}>
                  {format(a.attemptedAt, 'HH:mm:ss')}
                </span>
              </Box>
            ))}
          </Stack>
        </Box>
      )}
    </Stack>
  );
}
```

## Backend Schema

`mp_refund_attempts` 테이블 (모든 시도 기록 — 재시도 횟수 제한 없음, 사용자 액션):
```sql
CREATE TABLE mp_refund_attempts (
  id BIGSERIAL PRIMARY KEY,
  sale_id BIGINT NOT NULL REFERENCES sales(id),
  mp_payment_id VARCHAR(64) NOT NULL,
  attempt_no INTEGER NOT NULL,
  status VARCHAR(16) NOT NULL,  -- 'failed' | 'success'
  error_code VARCHAR(32),
  error_message TEXT,
  attempted_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX ON mp_refund_attempts (sale_id, attempted_at DESC);
```

## Key Principle (memory: feedback_error_visibility)

모든 에러는 **인라인 Alert + 글로벌 prominent 토스트** 동시 노출. 사용자가 한 곳만 봐도 (운이 나쁘면) 에러를 놓치지 않도록.

- 인라인 Alert: 컨텍스트 (어떤 sale, 어떤 결제) 가 명확
- 토스트: 사용자 시야가 다른 곳에 있을 때 (스크롤 다른 위치) 보장

## What to Avoid

- **토스트만, 인라인 없음** — 사용자가 토스트 dismiss 후 컨텍스트 잃음
- **인라인만, 토스트 없음** — 페이지 다른 영역 보고 있으면 못 봄
- **자동 재시도 로직** — 사용자 액션으로만 재시도. 자동 재시도는 같은 에러 반복 (4001 payment_already_refunded 등) 또는 race condition 위험.
- **MP Dashboard 링크 누락** — 자동 환불 실패 시 사용자가 어디로 가야 할지 명확해야 함.
- **Attempt history 숨김** — operator 가 "왜 실패했는지" debug 가능해야 함.

## Re-usable for

- 다른 외부 게이트웨이 환불 (Point, Online Checkout, 향후 다른 PSP)
- 외부 API 호출 실패 일반 (예: 배송 API 실패, 인보이스 발급 실패)

## Origin

Synthesized from sketch 001 area 5 (SalesDetailView Refund Failure UX) — D-A4-03 + memory: feedback_error_visibility.
Source: `sources/001-phase-29-mp-qr-suite/index.html` Area 5 section.
