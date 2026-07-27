# Virtual Wallet in Control de Caja

가상 지갑 (Mercadopago wallet, 향후 다른 결제 게이트웨이) 을 물리 caja 들과 함께 표시하고 관리하는 패턴. **Highlighted row variant 가 winner** — 한 테이블에서 모든 자산을 한눈에.

## Design Decisions

**Layout: 같은 테이블, highlighted row 로 구분 (winner)**
- `boxes` 와 `mp_wallets` 데이터를 한 row 리스트로 합침 (UNION ALL on backend, 또는 frontend merge)
- 가상 wallet row 는 cyan-tinted bg (`row-highlight` class — `var(--color-mp-soft)`)
- 행 좌측: cyan badge "MP" 28×28 + "Caja Mercadopago" + `<Chip label="VIRTUAL">` 작은 사이즈
- 액션 컬럼: "Transferir →" primary button + "Detalle" text button (mp-row 만)

**Why highlighted row won (vs Sectioned):**
- POS 운영자는 "오늘 받은 돈 전체" 한 화면에서 보고 싶다 — 섹션 분리는 시야 분산
- "Transferir →" 버튼이 row 액션 컬럼에 자연스럽게 위치
- 섹션 헤더 추가 없이 더 컴팩트 (가상 wallet 1~2 개 case 가 일반적)

**Row 구조:**
```
| Caja / Wallet                | Apertura | Ingresos | Egresos | Actual    | Actions      |
| 💵 Caja física #1           | $0       | +$142.5k | -$8.2k  | $134.3k   | Ver          |
| 💵 Caja física #2           | $0       | +$89k    | $0      | $89k      | Ver          |
| [MP] Caja Mercadopago [VIR] | $47.3k   | +$78.9k  | $0      | $126.2k   | Transferir → Detalle |
| 🏦 Caja fuerte              | $250k    | $0       | $0      | $250k     | Ver          |
```

## Transfer Modal (MP → Caja física)

**가상 wallet 의 핵심 액션** — 사용자가 MP 잔액을 물리 caja 로 "이체" (회계상 기록 — 실제 자금은 이미 MP 계정에 있음).

Modal 구조:
- **Info alert** 가운데: "Saldo disponible en Caja MP: $X. La transferencia es solo registro contable — el dinero ya está en su cuenta MP real."
- 타겟 선택: `<Select>` 같은 sucursal 의 물리 caja (옵션 마다 현재 잔액 노출)
- 금액 입력: mono font, 우측 정렬, 25%/50%/100% quick fill 버튼
- Note (optional): "Cobro entregado al gerente" 같은 메모

트랜잭션 (백엔드):
- `mp_movements` insert (debit, type='transfer_out', amount, target_box_id)
- `movements` insert (credit, type='mp_transfer', amount, box_id)
- `mp_wallets.balance` decrement, `box.balance` increment
- `mp_transfers` insert (id, mp_wallet_id, target_box_id, amount, user_id, transferred_at)

## Detail Modal (mp_movements 시간순)

- 시간 (mono) | 설명 (sale_id 클릭으로 navigate) | credit/debit | running balance
- 환불 row 는 `warning-soft` bg + `REFUND` chip 로 강조
- 푸터: "Transferir saldo" 버튼 → close + open transfer modal (chained action)

## CSS Patterns

```css
.ctrl-table {
  background: var(--color-surface);
  border-radius: var(--radius-lg);
  overflow: hidden;
  border: 1px solid var(--color-border);
}

.caja-mp-row td { font-weight: 500; }
.caja-mp-row .caja-icon { display: inline-flex; align-items: center; gap: 8px; }
.caja-mp-row .caja-icon .badge {
  width: 28px; height: 28px;
  border-radius: 6px;
  background: var(--color-mp);
  display: inline-flex; align-items: center; justify-content: center;
  color: #fff;
  font-size: 11px;
  font-weight: 700;
}

.row-highlight { background: var(--color-mp-soft); }
.row-highlight:hover { background: rgba(0, 177, 234, 0.18); }

.balance-positive { color: var(--color-success); font-family: var(--font-mono); font-weight: 600; }
.balance-zero { color: var(--color-text-muted); font-family: var(--font-mono); }

/* Movement detail row */
.movement-row {
  background: var(--color-surface);
  padding: 12px 16px;
  display: grid;
  grid-template-columns: 80px 1fr 100px 100px;
  gap: 16px;
  align-items: center;
  font-size: 0.85rem;
}
.movement-row .ts { font-family: var(--font-mono); font-size: 0.75rem; color: var(--color-text-muted); }
.movement-row .credit { color: var(--color-success); font-family: var(--font-mono); text-align: right; }
.movement-row .debit { color: var(--color-danger); font-family: var(--font-mono); text-align: right; }
.movement-row .balance { color: var(--color-text); font-family: var(--font-mono); text-align: right; font-weight: 600; }
```

## React / MUI 5 Implementation

```tsx
function ControlDeCajaTable({ rows }: { rows: (Box | MpWallet)[] }) {
  return (
    <TableContainer component={Paper}>
      <Table>
        <TableHead>
          <TableRow>
            <TableCell>Caja / Wallet</TableCell>
            <TableCell align="right">Apertura</TableCell>
            <TableCell align="right">Ingresos</TableCell>
            <TableCell align="right">Egresos</TableCell>
            <TableCell align="right">Actual</TableCell>
            <TableCell />
          </TableRow>
        </TableHead>
        <TableBody>
          {rows.map(row => (
            <TableRow
              key={row.kind + ':' + row.id}
              className={row.kind === 'mp_wallet' ? 'caja-mp-row row-highlight' : ''}
            >
              <TableCell>
                <Stack direction="row" alignItems="center" spacing={1}>
                  {row.kind === 'mp_wallet' ? (
                    <>
                      <Box className="badge">MP</Box>
                      <strong>Caja Mercadopago</strong>
                      <Chip size="small" color="info" label="VIRTUAL" />
                    </>
                  ) : (
                    <>
                      <span>{iconForBoxType(row.type)}</span>
                      {row.name}
                    </>
                  )}
                </Stack>
              </TableCell>
              <TableCell align="right" className="balance-positive">$ {fmt(row.opening)}</TableCell>
              <TableCell align="right" className="balance-positive">+ $ {fmt(row.credits)}</TableCell>
              <TableCell align="right" className={row.debits > 0 ? 'balance-positive' : 'balance-zero'}>
                $ {fmt(row.debits)}
              </TableCell>
              <TableCell align="right" className="balance-positive">$ {fmt(row.balance)}</TableCell>
              <TableCell align="right">
                {row.kind === 'mp_wallet' ? (
                  <>
                    <Button color="warning" variant="contained" size="small" onClick={openTransfer(row)}>
                      Transferir →
                    </Button>
                    <Button size="small" onClick={openDetail(row)}>Detalle</Button>
                  </>
                ) : (
                  <Button size="small">Ver</Button>
                )}
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </TableContainer>
  );
}
```

## Permissions

- "Transferir MP→Caja" 액션은 admin/gerente 권한만. Vendedor 는 비활성 (button disabled with tooltip).
- CASL ability: `can('transfer', 'MpWallet')` 검증.

## What to Avoid

- **`box` 테이블에 가상 wallet row 추가** — `box.branchId NOT NULL` 제약과 충돌. 별도 `mp_wallets` 테이블이 옳다.
- **`movements` 테이블에 MP 거래 직접 기록** — `box` 의존 구조. `mp_movements` 별도.
- **Sectioned layout (variant B)** — 깔끔해 보이지만 운영자 인지 부담 증가.
- **Transfer 시 즉시 reconcile 가정** — DB 저장은 즉시지만 MP API 와의 실제 reconcile 은 nightly cron 이 검증 (`mp_wallets.last_synced_at`).

## Re-usable for

- Phase 30 — MP Point 결제도 같은 mp_wallets 누적 (1 wallet per mp_account, 결제수단 무관)
- 향후 다른 가상 wallet (예: 마켓플레이스 pending payouts) 도 동일 패턴

## Origin

Synthesized from sketch 001 area 4 (Caja MP en Control de Caja) — D-A3-01 + D-A3-03 + D-A3-04. Winner: Variant A (Highlighted row).
Source: `sources/001-phase-29-mp-qr-suite/index.html` Area 4 section.
