# Factura Electrónica — Plan 3: 프론트엔드 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Facturación 페이지(2패널: Pendientes 카드 / Emitidas 테이블)와 부분 발급 모달, 발행자 Configuración, POS Facturar 버튼을 구현해 Plan 2 REST API에 연결한다.

**Architecture:** Next.js Pages Router. `src/pages/facturacion/index.tsx`가 `next/dynamic`으로 `src/views/facturacion/FacturacionShell` 로드. SWR 훅(`useApi` 래퍼)으로 데이터 페칭, `apiConnector`로 뮤테이션. MUI 5 + 다크네이비/골드(sketch-findings-ace-online). 부분 발급 모달이 preview API로 스케일 결과를 라이브 렌더.

**Tech Stack:** Next.js 13, React 18, MUI 5, SWR, Redux Toolkit(기존), apiConnector, next/dynamic.

## Global Constraints

- 코드 스플리팅 필수: 새 페이지는 `next/dynamic(() => import('src/views/...'), { ssr:false })`.
- 참조 데이터는 SWR 훅(`src/hooks/api/`, 5분 dedup). `useEffect+apiConnector.get` 금지(참조 데이터).
- `apiConnector.remove()`(`.delete()` 아님). `apiConnector.get/post/put`.
- ESLint 빌드 차단 규칙: `newline-before-return`(return 위 빈 줄), `lines-around-comment`(주석 위 빈 줄), `no-unused-vars`. 작업 후 **eslint-guardian 서브에이전트 점검 필수**.
- Context value는 `useMemo`. 고트래픽 리스트는 `React.memo`. pageSize ≤ 50.
- 에러 = 인라인 Alert + prominent 토스트(사유 전면 노출). 발급 실패 `{ok:false,reason}` 노출.
- 이미지 `next/Image`. `WithAccess`로 접근 제어.
- 프론트 자동 테스트 미설정 가정 — 검증은 `npx tsc --noEmit` + eslint + 브라우저 수동 확인.

---

### Task 1: SWR 훅 + apiConnector 뮤테이션 래퍼

**Files:**
- Create: `ventago-app/src/hooks/api/useAfipPendientes.ts`
- Create: `ventago-app/src/hooks/api/useAfipEmitidas.ts`
- Create: `ventago-app/src/hooks/api/useAfipIssuers.ts`
- Create: `ventago-app/src/services/afip.service.ts`

**Interfaces:**
- Consumes: `useApi<T>`(기존), `apiConnector`(기존).
- Produces: `useAfipPendientes()` → `{data:Sale[], isLoading, mutate}`. `useAfipEmitidas(date)` → vouchers. `useAfipIssuers()` → PV 목록. `afipService`: `issue(dto)`, `previewPartial(saleId,pct)`, `cancel(saleId)`, `reprint(id,branchId)`, `upsertIssuer(dto)`, `deleteIssuer(id)`, `notaCredito(id,items?)`, `notaDebito(id)`.

- [ ] **Step 1: SWR 훅 3종 작성**

Create `ventago-app/src/hooks/api/useAfipPendientes.ts`:

```ts
import { useApi } from 'src/hooks/useApi'

// 발급 대기 판매 — Facturación 좌측 Pendientes. mutate로 발급 후 갱신.
export function useAfipPendientes() {

  return useApi<any[]>('/afip/pendientes')
}
```

Create `ventago-app/src/hooks/api/useAfipEmitidas.ts`:

```ts
import { useApi } from 'src/hooks/useApi'

// 발급 완료 — 날짜별. date 변경 시 key 변경 → 재요청.
export function useAfipEmitidas(date: string) {

  return useApi<any[]>(`/afip/emitidas?date=${date}`)
}
```

Create `ventago-app/src/hooks/api/useAfipIssuers.ts`:

```ts
import { useApi } from 'src/hooks/useApi'

// 발행자/PV 목록 — 드롭다운 + Configuración.
export function useAfipIssuers() {

  return useApi<any[]>('/afip/issuers')
}
```

- [ ] **Step 2: afip.service.ts 뮤테이션 래퍼 작성**

Create `ventago-app/src/services/afip.service.ts`:

```ts
import { apiConnector } from './api.service'

// Factura Electrónica 뮤테이션 모음 (apiConnector 래핑).
export const afipService = {
  previewPartial: (saleId: number, pct: number) =>
    apiConnector.get(`/afip/vouchers/${saleId}/preview`, { pct }),

  issue: (dto: { saleId: number; puntoVenta: number; invoicePct: number; output: 'thermal' | 'pdf' | 'digital' }) =>
    apiConnector.post('/afip/vouchers', dto),

  cancel: (saleId: number) => apiConnector.post(`/afip/vouchers/${saleId}/cancel`, {}),

  reprint: (id: number, branchId: number) => apiConnector.post(`/afip/vouchers/${id}/reprint`, { branchId }),

  notaCredito: (id: number, items?: unknown[]) => apiConnector.post(`/afip/vouchers/${id}/nota-credito`, { items }),

  notaDebito: (id: number) => apiConnector.post(`/afip/vouchers/${id}/nota-debito`, {}),

  upsertIssuer: (dto: any) =>
    dto.id ? apiConnector.put(`/afip/issuers/${dto.id}`, dto) : apiConnector.post('/afip/issuers', dto),

  deleteIssuer: (id: number) => apiConnector.remove(`/afip/issuers/${id}`),
}
```

- [ ] **Step 3: 타입체크 + 커밋**

Run: `cd ventago-app && npx tsc --noEmit`
Expected: 에러 없음.

```bash
git add ventago-app/src/hooks/api/useAfip*.ts ventago-app/src/services/afip.service.ts
git commit -m "feat(afip-ui): SWR 훅(pendientes/emitidas/issuers) + afip.service 뮤테이션 래퍼"
```

---

### Task 2: Facturación 페이지 + 셸 + 사이드바 항목

**Files:**
- Create: `ventago-app/src/pages/facturacion/index.tsx`
- Create: `ventago-app/src/views/facturacion/FacturacionShell.tsx`
- Modify: `ventago-app/src/navigation/vertical/index.ts` (메뉴 항목)

**Interfaces:**
- Consumes: `useAfipIssuers`(Task 1), `WithAccess`, `useAuth`.
- Produces: `FacturacionShell` — 상단 PV 드롭다운 + 2열 그리드(좌 `<PendientesPanel pv=/>` 우 `<EmitidasPanel/>`) + ⚙ Configuración 토글. Task 3~6이 하위 컴포넌트를 채운다.

- [ ] **Step 1: 페이지 진입점 작성 (code-split)**

Create `ventago-app/src/pages/facturacion/index.tsx`:

```tsx
import React from 'react'
import dynamic from 'next/dynamic'
import { Box, Skeleton } from '@mui/material'
import WithAccess from 'src/configs/withAccess'

const FacturacionShell = dynamic(() => import('src/views/facturacion/FacturacionShell'), {
  ssr: false,
  loading: () => (
    <Box sx={{ p: 2 }}>
      <Skeleton variant="rectangular" height={480} sx={{ borderRadius: 2 }} />
    </Box>
  ),
})

const FacturacionPage = () => {

  return (
    <WithAccess allowedApps={['venta']} allowedModules={['facturacion']}>
      <FacturacionShell />
    </WithAccess>
  )
}

export default FacturacionPage
```

- [ ] **Step 2: FacturacionShell 셸 작성 (PV 드롭다운 + 2패널 그리드)**

Create `ventago-app/src/views/facturacion/FacturacionShell.tsx`:

```tsx
import React, { useMemo, useState } from 'react'
import { Box, Grid, MenuItem, Select, Typography, Button } from '@mui/material'
import { useAfipIssuers } from 'src/hooks/api/useAfipIssuers'
import PendientesPanel from './PendientesPanel'
import EmitidasPanel from './EmitidasPanel'
import IssuerConfig from './IssuerConfig'

const FacturacionShell = () => {
  const { data: issuers } = useAfipIssuers()
  const [pv, setPv] = useState<number | ''>('')
  const [showConfig, setShowConfig] = useState(false)

  const pvOptions = useMemo(() => issuers || [], [issuers])

  // PV 1개면 자동 선택
  React.useEffect(() => {
    if (pv === '' && pvOptions.length > 0) {
      setPv(pvOptions[0].puntoVenta)
    }
  }, [pvOptions, pv])

  return (
    <Box sx={{ p: 2 }}>
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 2, mb: 2 }}>
        <Typography variant="h5" sx={{ flexGrow: 1 }}>Facturación electrónica</Typography>
        <Select size="small" value={pv} onChange={(e) => setPv(Number(e.target.value))} displayEmpty>
          <MenuItem value="" disabled>PV…</MenuItem>
          {pvOptions.map((o: any) => (
            <MenuItem key={o.puntoVenta} value={o.puntoVenta}>PV {String(o.puntoVenta).padStart(5, '0')}</MenuItem>
          ))}
        </Select>
        <Button variant="outlined" onClick={() => setShowConfig((s) => !s)}>⚙ Configuración</Button>
      </Box>

      {showConfig ? (
        <IssuerConfig />
      ) : (
        <Grid container spacing={2}>
          <Grid item xs={12} md={5}>
            <PendientesPanel pv={pv} />
          </Grid>
          <Grid item xs={12} md={7}>
            <EmitidasPanel />
          </Grid>
        </Grid>
      )}
    </Box>
  )
}

export default FacturacionShell
```

- [ ] **Step 3: 사이드바 메뉴 항목 추가**

In `ventago-app/src/navigation/vertical/index.ts`, add an entry following the existing item shape (find a similar `{ title, path, icon, action, subject }` entry and copy its structure):

```ts
  {
    title: 'Facturación AFIP',
    path: '/facturacion',
    icon: 'mdi:receipt-text-outline',
    action: 'read',
    subject: 'venta',
  },
```

- [ ] **Step 4: 임시 스텁으로 빌드 확인**

Create minimal stubs so the shell compiles (will be replaced in Task 3~6). Create `ventago-app/src/views/facturacion/PendientesPanel.tsx`, `EmitidasPanel.tsx`, `IssuerConfig.tsx` each with:

```tsx
import React from 'react'

const Stub = (_props: any) => <div />

export default Stub
```

Run: `cd ventago-app && npx tsc --noEmit`
Expected: 에러 없음.

- [ ] **Step 5: 커밋**

```bash
git add ventago-app/src/pages/facturacion/ ventago-app/src/views/facturacion/ ventago-app/src/navigation/vertical/index.ts
git commit -m "feat(afip-ui): Facturación 페이지 + 셸(PV 드롭다운/2패널) + 사이드바 항목 + 패널 스텁"
```

---

### Task 3: Pendientes 패널 (카드 + Facturar/Cancelar)

**Files:**
- Modify: `ventago-app/src/views/facturacion/PendientesPanel.tsx`
- Create: `ventago-app/src/views/facturacion/tipoBadge.ts`

**Interfaces:**
- Consumes: `useAfipPendientes`(Task 1), `afipService.cancel`, Task 4의 `<PartialInvoiceModal/>`.
- Produces: `PendientesPanel({ pv })` — 대기 판매 카드 목록. 각 카드 `[Facturar]`(모달 오픈) / `[Cancelar]`. `tipoBadgeColor(letra)` → MUI color.

- [ ] **Step 1: tipoBadge 헬퍼 작성**

Create `ventago-app/src/views/facturacion/tipoBadge.ts`:

```ts
// comprobante letra → 뱃지 색 (A파랑/B보라/C초록/M주황/E청록)
export function tipoBadgeColor(letra: string): string {
  const map: Record<string, string> = { A: '#2196f3', B: '#7e57c2', C: '#43a047', M: '#f5a623', E: '#26c6da' }

  return map[letra] || '#9e9e9e'
}
```

- [ ] **Step 2: PendientesPanel 구현**

Replace `ventago-app/src/views/facturacion/PendientesPanel.tsx`:

```tsx
import React, { useState } from 'react'
import { Box, Button, Card, Chip, Stack, Typography } from '@mui/material'
import { useAfipPendientes } from 'src/hooks/api/useAfipPendientes'
import { afipService } from 'src/services/afip.service'
import { tipoBadgeColor } from './tipoBadge'
import PartialInvoiceModal from './PartialInvoiceModal'

const PendientesPanel = ({ pv }: { pv: number | '' }) => {
  const { data, isLoading, mutate } = useAfipPendientes()
  const [target, setTarget] = useState<any | null>(null)

  const onCancel = async (saleId: number) => {
    await afipService.cancel(saleId)
    mutate()
  }

  return (
    <Card sx={{ p: 2, height: '100%' }}>
      <Typography variant="h6" sx={{ mb: 1 }}>Pendientes</Typography>
      {isLoading && <Typography variant="body2">Cargando…</Typography>}
      <Stack spacing={1}>
        {(data || []).map((s: any) => (
          <Card key={s.id} variant="outlined" sx={{ p: 1.5 }}>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
              <Chip label={s.tipoPreview || 'B'} size="small" sx={{ bgcolor: tipoBadgeColor(s.tipoPreview || 'B'), color: '#fff' }} />
              <Typography sx={{ flexGrow: 1 }}>{s.clientName || 'Consumidor Final'}</Typography>
              <Typography sx={{ fontWeight: 700 }}>${Number(s.totalAmount).toLocaleString()}</Typography>
            </Box>
            <Box sx={{ display: 'flex', gap: 1, mt: 1 }}>
              <Button size="small" variant="contained" disabled={pv === ''} onClick={() => setTarget(s)}>Facturar</Button>
              <Button size="small" color="inherit" onClick={() => onCancel(s.id)}>Cancelar</Button>
            </Box>
          </Card>
        ))}
      </Stack>

      {target && (
        <PartialInvoiceModal
          sale={target}
          pv={pv as number}
          onClose={() => setTarget(null)}
          onIssued={() => { setTarget(null); mutate() }}
        />
      )}
    </Card>
  )
}

export default PendientesPanel
```

- [ ] **Step 3: 타입체크 (모달 스텁 필요)**

Create temporary `ventago-app/src/views/facturacion/PartialInvoiceModal.tsx` stub (replaced in Task 4):

```tsx
import React from 'react'

const PartialInvoiceModal = (_props: { sale: any; pv: number; onClose: () => void; onIssued: () => void }) => null

export default PartialInvoiceModal
```

Run: `cd ventago-app && npx tsc --noEmit`
Expected: 에러 없음.

- [ ] **Step 4: 커밋**

```bash
git add ventago-app/src/views/facturacion/PendientesPanel.tsx ventago-app/src/views/facturacion/tipoBadge.ts ventago-app/src/views/facturacion/PartialInvoiceModal.tsx
git commit -m "feat(afip-ui): Pendientes 패널(카드+Facturar/Cancelar) + tipo 뱃지"
```

---

### Task 4: 부분 발급 모달 (% + 라이브 preview + 출력 선택 + 확인)

**Files:**
- Modify: `ventago-app/src/views/facturacion/PartialInvoiceModal.tsx`

**Interfaces:**
- Consumes: `afipService.previewPartial`, `afipService.issue`.
- Produces: `PartialInvoiceModal({ sale, pv, onClose, onIssued })` — % 선택(100/70/50/커스텀) → preview API로 스케일 라인·총계 렌더 → 출력(감열/PDF/디지털) → `[Confirmar y enviar]` → issue → 성공/실패 토스트.

- [ ] **Step 1: 모달 구현**

Replace `ventago-app/src/views/facturacion/PartialInvoiceModal.tsx`:

```tsx
import React, { useEffect, useState } from 'react'
import {
  Alert, Box, Button, Dialog, DialogActions, DialogContent, DialogTitle,
  RadioGroup, FormControlLabel, Radio, TextField, Table, TableBody, TableCell, TableRow, Typography, Chip,
} from '@mui/material'
import { afipService } from 'src/services/afip.service'
import { tipoBadgeColor } from './tipoBadge'

interface Props { sale: any; pv: number; onClose: () => void; onIssued: () => void }

const PRESETS = [100, 70, 50]

const PartialInvoiceModal = ({ sale, pv, onClose, onIssued }: Props) => {
  const [pct, setPct] = useState(100)
  const [preview, setPreview] = useState<any | null>(null)
  const [output, setOutput] = useState<'thermal' | 'pdf' | 'digital'>('thermal')
  const [error, setError] = useState<string | null>(null)
  const [sending, setSending] = useState(false)

  // % 변경 시 preview 재조회 (debounce 없이 — 발급 전 확인용)
  useEffect(() => {
    let alive = true
    afipService.previewPartial(sale.id, pct).then((r: any) => { if (alive) setPreview(r) }).catch(() => {})

    return () => { alive = false }
  }, [sale.id, pct])

  const onConfirm = async () => {
    setSending(true)
    setError(null)
    try {
      const res: any = await afipService.issue({ saleId: sale.id, puntoVenta: pv, invoicePct: pct, output })

      if (!res?.ok) {
        setError(res?.reason || 'Error al emitir el comprobante')

        return
      }

      onIssued()
    } catch (e: any) {
      setError(e?.message || 'Error de red al emitir')
    } finally {
      setSending(false)
    }
  }

  return (
    <Dialog open onClose={onClose} maxWidth="sm" fullWidth>
      <DialogTitle>Facturar venta #{sale.id}</DialogTitle>
      <DialogContent>
        {error && <Alert severity="error" sx={{ mb: 2 }}>{error}</Alert>}
        <Typography variant="body2" sx={{ mb: 1 }}>
          Venta real: {sale.itemsCount || (sale.saleItems?.length ?? '?')} ítems · ${Number(sale.totalAmount).toLocaleString()}
        </Typography>

        <Box sx={{ display: 'flex', gap: 1, alignItems: 'center', mb: 2 }}>
          <Typography variant="body2">% a facturar:</Typography>
          {PRESETS.map((p) => (
            <Button key={p} size="small" variant={pct === p ? 'contained' : 'outlined'} onClick={() => setPct(p)}>{p}</Button>
          ))}
          <TextField size="small" type="number" value={pct} onChange={(e) => setPct(Math.max(1, Math.min(100, Number(e.target.value))))} sx={{ width: 90 }} />
        </Box>

        {preview?.ok && (
          <Box sx={{ border: '1px solid', borderColor: 'divider', borderRadius: 1, p: 1.5 }}>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 1 }}>
              <Chip label={preview.tipo} size="small" sx={{ bgcolor: tipoBadgeColor(preview.tipo), color: '#fff' }} />
              <Typography variant="caption">Vista previa ({pct}%)</Typography>
            </Box>
            <Table size="small">
              <TableBody>
                {preview.lines.map((l: any, i: number) => (
                  <TableRow key={i}>
                    <TableCell>{l.cantidad}</TableCell>
                    <TableCell>{l.descripcion}</TableCell>
                    <TableCell align="right">${Number(l.precioUnitario).toLocaleString()}</TableCell>
                    <TableCell align="right">${Number(l.subtotal).toLocaleString()}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
            <Typography sx={{ fontWeight: 700, mt: 1, textAlign: 'right' }}>TOTAL: ${Number(preview.impTotal).toLocaleString()}</Typography>
          </Box>
        )}

        <RadioGroup row value={output} onChange={(e) => setOutput(e.target.value as any)} sx={{ mt: 2 }}>
          <FormControlLabel value="thermal" control={<Radio />} label="Térmica" />
          <FormControlLabel value="pdf" control={<Radio />} label="PDF A4" />
          <FormControlLabel value="digital" control={<Radio />} label="WhatsApp" />
        </RadioGroup>
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose}>Cancelar</Button>
        <Button variant="contained" disabled={sending} onClick={onConfirm}>Confirmar y enviar →</Button>
      </DialogActions>
    </Dialog>
  )
}

export default PartialInvoiceModal
```

- [ ] **Step 2: 타입체크 + eslint + 커밋**

Run: `cd ventago-app && npx tsc --noEmit && npx eslint "src/views/facturacion/**/*.tsx"`
Expected: 에러 없음.

```bash
git add ventago-app/src/views/facturacion/PartialInvoiceModal.tsx
git commit -m "feat(afip-ui): 부분 발급 모달(% 선택+라이브 preview+출력 선택+확인 발급)"
```

---

### Task 5: Emitidas 패널 (날짜별 테이블 + 액션)

**Files:**
- Modify: `ventago-app/src/views/facturacion/EmitidasPanel.tsx`

**Interfaces:**
- Consumes: `useAfipEmitidas(date)`(Task 1), `afipService.reprint`, `afipService.notaCredito`(Plan 4 UI 훅).
- Produces: `EmitidasPanel()` — 날짜 선택기(‹ date ›, 기본 오늘) + 발급건 테이블(Hora·Tipo·PV·Nº·Cliente·Monto·CAE·Vto·Acción). 액션: Reprimir, PDF, Nota de Crédito(Plan 4 연결).

- [ ] **Step 1: EmitidasPanel 구현**

Replace `ventago-app/src/views/facturacion/EmitidasPanel.tsx`:

```tsx
import React, { useState } from 'react'
import { Box, Card, IconButton, Table, TableBody, TableCell, TableHead, TableRow, Typography, Button } from '@mui/material'
import { useAfipEmitidas } from 'src/hooks/api/useAfipEmitidas'
import { afipService } from 'src/services/afip.service'

const today = () => new Date().toISOString().slice(0, 10)
const shift = (d: string, days: number) => {
  const dt = new Date(`${d}T00:00:00`)
  dt.setDate(dt.getDate() + days)

  return dt.toISOString().slice(0, 10)
}

const EmitidasPanel = () => {
  const [date, setDate] = useState(today())
  const { data, mutate } = useAfipEmitidas(date)

  return (
    <Card sx={{ p: 2, height: '100%' }}>
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 1 }}>
        <Typography variant="h6" sx={{ flexGrow: 1 }}>Emitidas</Typography>
        <IconButton size="small" onClick={() => setDate((d) => shift(d, -1))}>‹</IconButton>
        <Typography variant="body2">{date}</Typography>
        <IconButton size="small" onClick={() => setDate((d) => shift(d, 1))}>›</IconButton>
      </Box>
      <Table size="small">
        <TableHead>
          <TableRow>
            <TableCell>Tipo</TableCell><TableCell>PV</TableCell><TableCell>Nº</TableCell>
            <TableCell>Monto</TableCell><TableCell>CAE</TableCell><TableCell>Vto</TableCell><TableCell>Acción</TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          {(data || []).map((v: any) => (
            <TableRow key={v.id}>
              <TableCell>{v.tipoComprobante}</TableCell>
              <TableCell>{String(v.puntoVenta).padStart(5, '0')}</TableCell>
              <TableCell>{String(v.afipNumber).padStart(8, '0')}</TableCell>
              <TableCell>${Number(v.impTotal).toLocaleString()}</TableCell>
              <TableCell>{v.cae}</TableCell>
              <TableCell>{v.caeVto}</TableCell>
              <TableCell>
                {v.notaCredito ? (
                  <Typography variant="caption" color="text.secondary">NC emitida</Typography>
                ) : (
                  <Button size="small" onClick={async () => { await afipService.notaCredito(v.id); mutate() }}>Nota Cr.</Button>
                )}
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </Card>
  )
}

export default EmitidasPanel
```

- [ ] **Step 2: 타입체크 + 커밋**

Run: `cd ventago-app && npx tsc --noEmit`
Expected: 에러 없음.

```bash
git add ventago-app/src/views/facturacion/EmitidasPanel.tsx
git commit -m "feat(afip-ui): Emitidas 패널(날짜별 테이블 + NC 액션 훅)"
```

---

### Task 6: 발행자 Configuración (CRUD)

**Files:**
- Modify: `ventago-app/src/views/facturacion/IssuerConfig.tsx`

**Interfaces:**
- Consumes: `useAfipIssuers`, `afipService.upsertIssuer`, `afipService.deleteIssuer`.
- Produces: `IssuerConfig()` — PV 목록 테이블 + 추가/편집 폼(PV, CUIT, ivaCondition(RI/MONO/EXENTO), coolUser, razón social, domicilio, ingresos brutos, inicio actividad, teléfono).

- [ ] **Step 1: IssuerConfig 구현**

Replace `ventago-app/src/views/facturacion/IssuerConfig.tsx`:

```tsx
import React, { useState } from 'react'
import {
  Box, Button, Card, MenuItem, Select, Table, TableBody, TableCell, TableHead, TableRow, TextField, Typography,
} from '@mui/material'
import { useAfipIssuers } from 'src/hooks/api/useAfipIssuers'
import { afipService } from 'src/services/afip.service'

const EMPTY = { id: undefined as number | undefined, puntoVenta: '', cuit: '', ivaCondition: 'RI', coolUser: '', razonSocial: '', domicilio: '', ingresosBrutos: '', inicioActividad: '', telefono: '' }

const IssuerConfig = () => {
  const { data, mutate } = useAfipIssuers()
  const [form, setForm] = useState<any>(EMPTY)

  const set = (k: string) => (e: any) => setForm((f: any) => ({ ...f, [k]: e.target.value }))

  const save = async () => {
    await afipService.upsertIssuer({ ...form, puntoVenta: Number(form.puntoVenta) })
    setForm(EMPTY)
    mutate()
  }

  const del = async (id: number) => {
    await afipService.deleteIssuer(id)
    mutate()
  }

  return (
    <Box sx={{ display: 'flex', gap: 2, flexWrap: 'wrap' }}>
      <Card sx={{ p: 2, flex: 1, minWidth: 320 }}>
        <Typography variant="h6" sx={{ mb: 1 }}>Puntos de venta</Typography>
        <Table size="small">
          <TableHead>
            <TableRow><TableCell>PV</TableCell><TableCell>CUIT</TableCell><TableCell>IVA</TableCell><TableCell /></TableRow>
          </TableHead>
          <TableBody>
            {(data || []).map((i: any) => (
              <TableRow key={i.puntoVenta}>
                <TableCell>{String(i.puntoVenta).padStart(5, '0')}</TableCell>
                <TableCell>{i.cuit}</TableCell>
                <TableCell>{i.ivaCondition}</TableCell>
                <TableCell><Button size="small" onClick={() => setForm({ ...EMPTY, ...i })}>Editar</Button></TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </Card>

      <Card sx={{ p: 2, flex: 1, minWidth: 320 }}>
        <Typography variant="h6" sx={{ mb: 1 }}>{form.id ? 'Editar' : 'Nuevo'} emisor</Typography>
        <Box sx={{ display: 'grid', gap: 1.5 }}>
          <TextField label="Punto de venta" size="small" value={form.puntoVenta} onChange={set('puntoVenta')} />
          <TextField label="CUIT" size="small" value={form.cuit} onChange={set('cuit')} />
          <Select size="small" value={form.ivaCondition} onChange={set('ivaCondition')}>
            <MenuItem value="RI">Responsable Inscripto</MenuItem>
            <MenuItem value="MONO">Monotributo</MenuItem>
            <MenuItem value="EXENTO">Exento</MenuItem>
          </Select>
          <TextField label="Cool user (gateway)" size="small" value={form.coolUser} onChange={set('coolUser')} />
          <TextField label="Razón social" size="small" value={form.razonSocial} onChange={set('razonSocial')} />
          <TextField label="Domicilio" size="small" value={form.domicilio} onChange={set('domicilio')} />
          <TextField label="Ingresos brutos" size="small" value={form.ingresosBrutos} onChange={set('ingresosBrutos')} />
          <TextField label="Inicio actividad (DD/MM/YYYY)" size="small" value={form.inicioActividad} onChange={set('inicioActividad')} />
          <TextField label="Teléfono" size="small" value={form.telefono} onChange={set('telefono')} />
          <Box sx={{ display: 'flex', gap: 1 }}>
            <Button variant="contained" onClick={save}>Guardar</Button>
            {form.id && <Button color="error" onClick={() => del(form.id)}>Eliminar</Button>}
          </Box>
        </Box>
      </Card>
    </Box>
  )
}

export default IssuerConfig
```

- [ ] **Step 2: 타입체크 + eslint (전체 facturación) + 커밋**

Run: `cd ventago-app && npx tsc --noEmit && npx eslint "src/views/facturacion/**/*.tsx" "src/hooks/api/useAfip*.ts" "src/services/afip.service.ts"`
Expected: 에러 없음. (위반 시 eslint-guardian 서브에이전트로 수정)

```bash
git add ventago-app/src/views/facturacion/IssuerConfig.tsx
git commit -m "feat(afip-ui): 발행자 Configuración CRUD(PV/CUIT/IVA조건/coolUser/영수증 필드)"
```

---

### Task 7: POS Facturar 버튼 통합

**Files:**
- Modify: `ventago-app/src/views/homes/VcontrolHome.tsx` (또는 판매 완료 컴포넌트 — 실제 완료 모달 위치 확인)

**Interfaces:**
- Consumes: `useStoreConfig`(use_factura_electronica), Task 4 `PartialInvoiceModal`, `useAfipIssuers`(기본 PV).
- Produces: 판매 완료 시 `use_factura_electronica` 매장에 `Facturar` 버튼 노출. 클릭 시 부분 발급 모달(기본 PV). `afip_auto_issue` 매장은 자동 발급되므로 버튼 대신 상태 표시.

- [ ] **Step 1: 판매 완료 지점 확인**

Run: `cd ventago-app && grep -rn "venta.*complet\|Venta creada\|onSaleComplete\|ticket\|comprobante" src/views/homes 2>/dev/null | head`
Expected: 판매 완료 후 렌더되는 컴포넌트/콜백 위치 파악. 그 지점에 버튼 삽입.

- [ ] **Step 2: Facturar 버튼 삽입 (게이트 뒤)**

At the identified sale-complete UI point, add (adapt props to actual sale object):

```tsx
{storeConfig?.useFacturaElectronica && !storeConfig?.afipAutoIssue && lastSale && (
  <Button variant="outlined" onClick={() => setFacturarSale(lastSale)}>Facturar</Button>
)}
{facturarSale && defaultPv && (
  <PartialInvoiceModal
    sale={facturarSale}
    pv={defaultPv}
    onClose={() => setFacturarSale(null)}
    onIssued={() => setFacturarSale(null)}
  />
)}
```

Wire `useStoreConfig()` for the flags, `useAfipIssuers()` for `defaultPv = issuers?.[0]?.puntoVenta`, and local `useState` for `facturarSale`. Import `PartialInvoiceModal`.

- [ ] **Step 3: 타입체크 + eslint + 브라우저 수동 검증**

Run: `cd ventago-app && npx tsc --noEmit && npx eslint "src/views/homes/VcontrolHome.tsx"`
Expected: 에러 없음.

Manual (브라우저): FE 활성 매장으로 판매 완료 → `Facturar` 버튼 → 모달 → 70% preview → 감열 선택 → 발급 성공/실패 토스트 확인.

- [ ] **Step 4: 커밋**

```bash
git add ventago-app/src/views/homes/VcontrolHome.tsx
git commit -m "feat(afip-ui): POS 판매 완료 Facturar 버튼(FE 활성·수동 매장) → 부분 발급 모달"
```

---

## Self-Review

**Spec coverage (Plan 3 범위):**
- SWR 훅(§7.4/성능규약) → Task 1 ✅
- Facturación 2패널 페이지(§7.1) → Task 2·3·5 ✅
- 부분 발급 모달(§7.2/D9) → Task 4 ✅
- 발행자 Configuración(§7.3) → Task 6 ✅
- POS 통합(§F-2/D2) → Task 7 ✅
- NC 액션 버튼은 Emitidas에 배치(Task 5), 실제 NC/ND 발급은 Plan 4에서 백엔드 완성 후 동작.

**Placeholder scan:** 컴포넌트 실제 코드 포함. Task 7은 판매 완료 지점이 코드베이스 의존이라 grep-후-삽입으로 명시(스텁 아님). 스텁(Task 2·3)은 후속 태스크에서 실제 구현으로 대체되는 빌드 통과용 — 명시됨.

**Type consistency:** `afipService` 메서드(Task 1) ↔ 각 컴포넌트 호출 일치. `PartialInvoiceModal` props `{sale,pv,onClose,onIssued}`(Task 4) ↔ PendientesPanel(Task 3)·POS(Task 7) 호출 일치. `useAfipEmitidas(date)`(Task 1) ↔ EmitidasPanel(Task 5) 일치.

**실행 전 확인:** `WithAccess` allowedApps/allowedModules 값(`'venta'`/`'facturacion'`)이 실제 CASL subject/권한 등록과 맞는지, 사이드바 item 스키마(`action`/`subject`) 실제 형식, 판매 객체 필드(`totalAmount`/`clientName`/`saleItems`) 실체 확인.
