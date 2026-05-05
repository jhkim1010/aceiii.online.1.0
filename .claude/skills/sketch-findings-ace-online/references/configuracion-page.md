# Configuración Page Pattern (e.g. `configuracion/mercadopago`)

OAuth 또는 외부 서비스 연결 관리 페이지의 표준 구조. Phase 29 의 MP OAuth 페이지에서 검증됨. 향후 다른 OAuth/integration 설정 페이지도 동일 패턴 적용.

## Design Decisions

**3-section structure (top → middle → bottom):**

1. **Top: Store-level connection card** — 1 hero card (`grid-template-columns: 1fr auto`).
   - 좌: 제목 + 설명 + 메타 (User ID, email, 연결일, 만료까지 N일)
   - 우: environment chip + Renovar/Desconectar 버튼 vertical stack
   - 상태 chip (`✓ Conectada` 성공 / `❌ Desconectada` 위험) 자체 헤더에

2. **Middle: Branch-level configuration card** — `padding: 0` overflow.
   - 카드 헤더: 제목 + 통계 chip (예: "2 / 5 con cuenta propia")
   - 본문: 각 branch row — `grid-template-columns: minmax(180px,1fr) auto auto auto auto` (branch-name | email | env-chip | expires | toggle)
   - Toggle ON 시 OAuth flow 시작, OFF 시 store-level inheritance
   - Branch row 내부 chip: `usa tienda` (neutral) / `cuenta propia` (success) / `sandbox` (warning)

3. **Bottom: Info alert** — `<Alert severity="info">` "¿Cómo funciona?" 섹션.

**Expiration warning (D-7):**
- 글로벌 alert (warning) at top of card list — count of expiring accounts
- 각 row 마다 빨간 `expires-warn` 스팬 (`⚠️ renueva en 3 días`) 노출

**Disconnect protection:**
- 빨간 텍스트 `<Button>` (no destructive bg — text only, less alarming)
- `confirm()` dialog 또는 modal 로 확인 — "pending payments seguirán" 안내

## CSS Patterns

```css
.config-grid {
  display: grid;
  gap: 24px;
  grid-template-columns: 1fr;
}

.store-card {
  display: grid;
  grid-template-columns: 1fr auto;
  gap: 24px;
  align-items: center;
}

.account-meta {
  display: flex;
  flex-wrap: wrap;
  gap: 8px 16px;
  margin-top: 12px;
  font-size: 0.8rem;
  color: var(--color-text-muted);
}
.account-meta strong { color: var(--color-text); font-weight: 500; }

.branch-row {
  display: grid;
  grid-template-columns: minmax(180px,1fr) auto auto auto auto;
  gap: 16px;
  padding: 14px 18px;
  align-items: center;
  border-bottom: 1px solid var(--color-border);
}
.branch-row:last-child { border-bottom: 0; }
.branch-row:hover { background: var(--color-surface-2); }

.branch-icon {
  width: 28px; height: 28px;
  border-radius: 6px;
  background: var(--color-surface-3);
  display: inline-flex; align-items: center; justify-content: center;
  font-size: 14px;
}

.expires-warn { color: var(--color-danger); font-size: 0.75rem; font-weight: 600; }
```

## HTML / MUI 5 Structure

```tsx
<Box className="config-grid">
  {/* 1. Hero store card */}
  <Card sx={{ p: 3 }}>
    <Box sx={{ display: 'grid', gridTemplateColumns: '1fr auto', gap: 3 }}>
      <Box>
        <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 1 }}>
          <Box>
            <Typography variant="h6">🏪 Cuenta de la tienda</Typography>
            <Typography variant="body2" color="text.secondary">…</Typography>
          </Box>
          <Chip color="success" label="✓ Conectada" />
        </Box>
        <Box className="account-meta">{/* MP User ID, email, fecha conexión */}</Box>
      </Box>
      <Stack spacing={1} alignItems="flex-end">
        <Chip color="info" label="🌐 PRODUCCIÓN" />
        <Button variant="outlined" onClick={handleReconnect}>Renovar ahora</Button>
        <Button color="error" onClick={handleDisconnect}>Desconectar</Button>
      </Stack>
    </Box>
  </Card>

  {/* Expiration warning */}
  {expiringCount > 0 && (
    <Alert severity="warning" icon="⏰">
      <AlertTitle>{expiringCount} cuenta(s) expira(n) en menos de 7 días</AlertTitle>
      Renueve antes de la fecha …
    </Alert>
  )}

  {/* 2. Branch config card */}
  <Card sx={{ p: 0 }}>
    <Box sx={{ p: 3, pb: 1.5 }}>
      <Box sx={{ display: 'flex', justifyContent: 'space-between' }}>
        <Typography variant="h6">🏬 Configuración por sucursal</Typography>
        <Chip label={`${withOwnAccount} / ${total} con cuenta propia`} />
      </Box>
    </Box>
    {branches.map(b => (
      <Box className="branch-row" key={b.id}>
        <Box className="branch-name">
          <span className="branch-icon">🏬</span>
          {b.name}
          <Chip size="small" {...statusChip(b)} />
        </Box>
        <Typography variant="caption">{b.email}</Typography>
        <Chip size="small" color={b.environment === 'sandbox' ? 'warning' : 'info'} label={b.environment} />
        <Typography variant="caption" className={daysLeft < 7 ? 'expires-warn' : undefined}>
          renueva en {daysLeft} días
        </Typography>
        <Switch checked={b.hasOwnAccount} onChange={toggleBranchAccount(b.id)} />
      </Box>
    ))}
  </Card>

  {/* 3. Info panel */}
  <Alert severity="info">
    <AlertTitle>¿Cómo funciona?</AlertTitle>
    Cada cuenta MP genera automáticamente una "Caja Mercadopago" virtual …
  </Alert>
</Box>
```

## Sidebar / Navigation Integration

새 `configuracion/{integration}` 페이지를 사이드바에 추가할 때:
- 위치: `navigation/vertical/index.ts` 의 "Configuración" 그룹 하위
- CASL function slug 필요 (e.g. `mercadopago_admin`) — Phase 14 권한 시스템과 통합

## What to Avoid

- **모든 계정을 한 테이블에 평면화** — store-level은 hero, branch-level은 row 가 옳다. 계층 시각화가 인지 부담을 낮춘다.
- **Toggle 대신 Connect 버튼만 둔다** — 사용자가 store-level 사용 ↔ branch-level override 의 의미를 모름. Toggle 이 명확하다.
- **Disconnect 를 빨간 background button** — 너무 attention-grabbing. text button + confirm dialog 가 적절.

## Origin

Synthesized from sketch 001 area 1 (Configuración › Mercadopago) — D-A4-04 + D-A1-02 + D-A1-04.
Source: `sources/001-phase-29-mp-qr-suite/index.html` Area 1 section.
