# 배달 판매 VentaVista 표시 + DeliveryBoard 이력 조회 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** VentaVista(/ventas)에서 배달 판매의 Vendedor=canal 라벨·Cliente=등록 고객명을 표시하고, DeliveryBoard에 종료 상태 배달을 날짜 범위로 읽기전용 조회하는 Historial 보기를 추가한다.

**Architecture:** 백엔드는 Sale↔RestaurantDelivery 모델 association을 추가하지 않고, ventas 조회 결과에 `restaurant_deliveries`를 batch SELECT로 enrichment하여 `delivery` 객체를 붙인다(목록·단건 공용). 이력은 신규 `GET /restaurant-delivery/history/:branchId` 라우트가 종료 상태(`liquidado/conciliacion/cancelado`)를 날짜 범위로 조회한다. 프론트는 DataConfig 렌더러 분기 + DeliveryBoard Tablero/Historial 토글로 표시한다.

**Tech Stack:** NestJS 11 + Sequelize(raw query, `QueryTypes.SELECT`, storeId 스코프) / Next.js 13 + MUI 5 + SWR / jest(백엔드·프론트 ts-jest)

**저장소 주의:** 백엔드 변경은 `api-ventago/` repo, 프론트 변경은 `ventago-app/` repo에 각각 커밋(3-repo 워크스페이스, gitlink). 커밋 시 해당 디렉터리에서 git 실행.

**회귀 제약:** 공유 경로(VentaVista 목록/단건)는 `source='delivery'` 분기에서만 동작 변경 → 소매(pos) 판매 무회귀. ESLint Warning=빌드 에러이므로 `newline-before-return`/`lines-around-comment` 준수.

---

## File Structure

**api-ventago (백엔드)**
- `src/app/sales/sales.service.ts` — `attachDeliveryMeta` 헬퍼 추가, `findFilteredByStore`·`findOne`에서 호출 (Task 1)
- `src/app/sales/sales.service.spec.ts` — enrichment 단위 테스트 (Task 1)
- `src/app/restaurant-delivery/restaurant-delivery.service.ts` — `getHistory` 추가 (Task 5)
- `src/app/restaurant-delivery/restaurant-delivery.controller.ts` — `GET history/:branchId` 라우트 (Task 5)
- `src/app/restaurant-delivery/restaurant-delivery.service.spec.ts` — getHistory 단위 테스트 (Task 5)

**ventago-app (프론트)**
- `src/configs/deliveryLabels.ts` — canal/상태 라벨 공용 헬퍼 (Task 2, 신규)
- `src/__tests__/deliveryLabels.spec.ts` — 헬퍼 단위 테스트 (Task 2, 신규)
- `src/views/sales/list/components/DataConfig.tsx` — Vendedor/Cliente 렌더러 분기 (Task 3)
- `src/views/sales/list/components/SaleDetailPanel.tsx` — Delivery 정보 블록 (Task 4)
- `src/hooks/api/useDeliveryHistory.ts` — 이력 SWR 훅 (Task 6, 신규)
- `src/views/restaurante/DeliveryBoard.tsx` — Tablero/Historial 토글 + 날짜 필터 + 이력 렌더 (Task 7)

**DDL:** 없음 (기존 `restaurant_deliveries`/`sales` 컬럼만 사용).

---

## Part A — VentaVista 배달 판매 표시

### Task 1: 백엔드 — ventas 조회에 delivery 메타 enrichment

**Files:**
- Modify: `api-ventago/src/app/sales/sales.service.ts` (import 1줄, 헬퍼 메서드, `findFilteredByStore`·`findOne` 호출)
- Test: `api-ventago/src/app/sales/sales.service.spec.ts`

데이터 계약 — 각 sale row에 부착되는 `delivery` 객체(비배달 sale은 `null`):
```
{ canal: string, customerName: string|null, customerPhone: string|null,
  address: string|null, status: string, repartidorId: number|null }
```

- [ ] **Step 1: 실패 테스트 작성**

`sales.service.spec.ts` 맨 아래 `describe` 블록 추가. 기존 `beforeEach`의 `saleModel` mock에 `sequelize.query`가 필요하므로 이 describe는 자체 service 인스턴스를 구성한다.

```typescript
import { SaleSource } from './sales.model';

describe('SalesService — attachDeliveryMeta (배달 메타 enrichment)', () => {
  function makeService(queryRows: any[]) {
    const saleModel: any = {
      findAll: jest.fn(),
      findByPk: jest.fn(),
      sequelize: { query: jest.fn().mockResolvedValue(queryRows) },
    };
    const svc = new SalesService(
      saleModel,
      { destroy: jest.fn() },
      { destroy: jest.fn() },
      { destroy: jest.fn() },
      { destroy: jest.fn() },
      { resolveStoresForOwnerGroup: jest.fn() },
    );

    return { svc, saleModel };
  }

  // setDataValue 를 캡처하는 가짜 sale row
  function fakeSale(id: number, source: string) {
    const store: Record<string, any> = {};

    return {
      id,
      source,
      storeId: 3,
      setDataValue: jest.fn((k: string, v: any) => { store[k] = v; }),
      _store: store,
    };
  }

  it('배달 sale 에 delivery 메타를 부착하고 비배달 sale 은 null', async () => {
    const deliverySale = fakeSale(555, SaleSource.DELIVERY);
    const posSale = fakeSale(556, 'pos');
    const { svc, saleModel } = makeService([
      {
        saleId: 555,
        canal: 'whatsapp',
        customerName: 'Juan Pérez',
        customerPhone: '099',
        address: 'Av 1',
        status: 'liquidado',
        repartidorId: 7,
      },
    ]);

    await (svc as any).attachDeliveryMeta([deliverySale, posSale], 3);

    expect(deliverySale._store.delivery).toEqual({
      canal: 'whatsapp',
      customerName: 'Juan Pérez',
      customerPhone: '099',
      address: 'Av 1',
      status: 'liquidado',
      repartidorId: 7,
    });
    expect(posSale._store.delivery).toBeNull();
    // storeId 스코프 + saleIds 전달 검증
    expect(saleModel.sequelize.query).toHaveBeenCalledWith(
      expect.stringContaining('FROM restaurant_deliveries'),
      expect.objectContaining({
        replacements: { storeId: 3, saleIds: [555] },
      }),
    );
  });

  it('배달 sale 이 없으면 쿼리를 실행하지 않는다', async () => {
    const posSale = fakeSale(556, 'pos');
    const { svc, saleModel } = makeService([]);

    await (svc as any).attachDeliveryMeta([posSale], 3);

    expect(saleModel.sequelize.query).not.toHaveBeenCalled();
    expect(posSale._store.delivery).toBeNull();
  });
});
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd api-ventago && npx jest src/app/sales/sales.service.spec.ts -t "attachDeliveryMeta"`
Expected: FAIL — `svc.attachDeliveryMeta is not a function`

- [ ] **Step 3: import 에 SaleSource 추가**

`sales.service.ts` 3번째 줄 수정:
```typescript
import { Sale, SaleStatus, SaleActivityType, SaleSource } from './sales.model';
```

- [ ] **Step 4: attachDeliveryMeta 헬퍼 구현**

`sales.service.ts` 클래스 내부(`findFilteredByStore` 메서드 바로 위 등 적절한 위치)에 추가:
```typescript
  // 배달 sale(source='delivery')에 restaurant_deliveries 메타를 batch SELECT 로 부착.
  // VentaVista 목록/단건 공용. storeId 스코프(IDOR 가드). 비배달 sale 은 delivery=null.
  // Sale↔RestaurantDelivery 모델 association 미사용(모듈 결합/순환 import 회피) — 페이지당 +1 쿼리.
  private async attachDeliveryMeta(
    sales: Sale[],
    storeId: number,
  ): Promise<void> {
    if (!sales || sales.length === 0) {
      return;
    }

    // 모든 row 에 기본 null 부착(프론트가 row.delivery 존재를 가정)
    for (const s of sales) {
      (s as any).setDataValue('delivery', null);
    }

    const deliverySaleIds = sales
      .filter((s) => (s as any).source === SaleSource.DELIVERY)
      .map((s) => s.id);
    if (deliverySaleIds.length === 0) {
      return;
    }

    const rows: Array<{
      saleId: number;
      canal: string;
      customerName: string | null;
      customerPhone: string | null;
      address: string | null;
      status: string;
      repartidorId: number | null;
    }> = await this.saleModel.sequelize!.query(
      `SELECT sale_id        AS "saleId",
              canal,
              customer_name  AS "customerName",
              customer_phone AS "customerPhone",
              address,
              status,
              repartidor_id  AS "repartidorId"
         FROM restaurant_deliveries
        WHERE store_id = :storeId
          AND sale_id IN (:saleIds)`,
      {
        replacements: { storeId, saleIds: deliverySaleIds },
        type: QueryTypes.SELECT,
      },
    );

    const bySale = new Map<number, any>();
    for (const r of rows) {
      bySale.set(Number(r.saleId), {
        canal: r.canal,
        customerName: r.customerName ?? null,
        customerPhone: r.customerPhone ?? null,
        address: r.address ?? null,
        status: r.status,
        repartidorId: r.repartidorId ?? null,
      });
    }

    for (const s of sales) {
      const meta = bySale.get(s.id);
      if (meta) {
        (s as any).setDataValue('delivery', meta);
      }
    }
  }
```

- [ ] **Step 5: findFilteredByStore 에서 호출**

`sales.service.ts` `findFilteredByStore` 끝(현재 `return this.saleModel.findAndCountAll({...})`, 약 524–530줄) 교체:
```typescript
    const result = await this.saleModel.findAndCountAll({
      where: whereClause,
      include: includeClause,
      offset: page * pageSize,
      limit: pageSize,
      order: [['id', 'DESC']],
    });

    // VentaVista 배달 표시 — delivery sale 에 canal/customerName 등 메타 부착
    await this.attachDeliveryMeta(result.rows, storeId);

    return result;
```

- [ ] **Step 6: findOne 단건에서도 호출**

`sales.service.ts` `findOne(id)` 메서드의 `return sale;` 직전에 추가(메서드가 sale 존재 시 반환하는 지점). 단건은 storeId 파라미터가 없으므로 `sale.storeId` 사용:
```typescript
    // VentaVista 우측 패널(SaleDetailPanel) 배달 메타 표시
    if (sale) {
      await this.attachDeliveryMeta([sale], (sale as any).storeId);
    }

    return sale;
```
> 주석: `findOne` 의 기존 반환 직전 한 곳에만 삽입. `setDataValue` 는 Sequelize 인스턴스 메서드이므로 mock 외 실제 인스턴스에서 정상 동작하며 `.toJSON()` 직렬화에 포함된다.

- [ ] **Step 7: 테스트 통과 확인**

Run: `cd api-ventago && npx jest src/app/sales/sales.service.spec.ts`
Expected: PASS (신규 2건 + 기존 케이스 유지)

- [ ] **Step 8: 빌드 확인**

Run: `cd api-ventago && npm run build`
Expected: 성공 (tsc/SWC 에러 없음)

- [ ] **Step 9: 커밋**

```bash
cd api-ventago
git add src/app/sales/sales.service.ts src/app/sales/sales.service.spec.ts
git commit -m "feat(delivery): VentaVista 배달 sale 에 canal/고객명 메타 enrichment

목록(findFilteredByStore)+단건(findOne) 조회 결과에 restaurant_deliveries
batch SELECT(storeId 스코프) 로 delivery 메타 부착. 비배달 sale 은 null.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: 프론트 — canal/상태 라벨 공용 헬퍼

**Files:**
- Create: `ventago-app/src/configs/deliveryLabels.ts`
- Test: `ventago-app/src/__tests__/deliveryLabels.spec.ts`

- [ ] **Step 1: 실패 테스트 작성**

`ventago-app/src/__tests__/deliveryLabels.spec.ts`:
```typescript
import { canalLabel, deliveryStatusLabel } from 'src/configs/deliveryLabels'

describe('deliveryLabels', () => {
  it('canalLabel — 알려진 canal 은 표시 라벨로 변환', () => {
    expect(canalLabel('whatsapp')).toBe('WhatsApp')
    expect(canalLabel('telefono')).toBe('Teléfono')
    expect(canalLabel('app')).toBe('App')
    expect(canalLabel('otro')).toBe('Otro')
  })

  it('canalLabel — 미지정/미지의 값은 Delivery 폴백', () => {
    expect(canalLabel(undefined)).toBe('Delivery')
    expect(canalLabel(null)).toBe('Delivery')
    expect(canalLabel('xyz')).toBe('Delivery')
  })

  it('deliveryStatusLabel — 종료 상태 라벨', () => {
    expect(deliveryStatusLabel('liquidado')).toBe('Liquidado')
    expect(deliveryStatusLabel('conciliacion')).toBe('Conciliación')
    expect(deliveryStatusLabel('cancelado')).toBe('Cancelado')
  })
})
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd ventago-app && npx jest src/__tests__/deliveryLabels.spec.ts`
Expected: FAIL — 모듈을 찾을 수 없음

- [ ] **Step 3: 헬퍼 구현**

`ventago-app/src/configs/deliveryLabels.ts`:
```typescript
// 배달 canal/상태 표시 라벨 — VentaVista(DataConfig) + DeliveryBoard Historial 공용.

export const DELIVERY_CANAL_LABELS: Record<string, string> = {
  whatsapp: 'WhatsApp',
  telefono: 'Teléfono',
  app: 'App',
  otro: 'Otro',
}

// canal 코드 → 표시 라벨. 미지정/미지의 값은 'Delivery' 폴백.
export const canalLabel = (canal?: string | null): string =>
  (canal && DELIVERY_CANAL_LABELS[canal]) || 'Delivery'

export const DELIVERY_STATUS_LABELS: Record<string, string> = {
  nuevo: 'Nuevo',
  en_cocina: 'En cocina',
  listo: 'Listo',
  en_camino: 'En camino',
  entregado: 'Entregado',
  por_cobrar: 'Por cobrar',
  conciliacion: 'Conciliación',
  liquidado: 'Liquidado',
  cancelado: 'Cancelado',
}

// 상태 코드 → 표시 라벨. 미지의 값은 원문 반환.
export const deliveryStatusLabel = (status?: string | null): string =>
  (status && DELIVERY_STATUS_LABELS[status]) || status || '—'

// Historial 상태칩 색상 (MUI Chip color prop).
export const deliveryStatusColor = (
  status?: string | null,
): 'success' | 'info' | 'default' => {
  if (status === 'liquidado') {
    return 'success'
  }
  if (status === 'conciliacion') {
    return 'info'
  }

  return 'default'
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd ventago-app && npx jest src/__tests__/deliveryLabels.spec.ts`
Expected: PASS

- [ ] **Step 5: 커밋**

```bash
cd ventago-app
git add src/configs/deliveryLabels.ts src/__tests__/deliveryLabels.spec.ts
git commit -m "feat(delivery): canal/상태 표시 라벨 공용 헬퍼

VentaVista + DeliveryBoard Historial 공용 canalLabel/deliveryStatusLabel.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: 프론트 — VentaVista Vendedor/Cliente 렌더러 분기

**Files:**
- Modify: `ventago-app/src/views/sales/list/components/DataConfig.tsx` (import + `renderClienteOrRoute` + Vendedor 컬럼 renderCell)

- [ ] **Step 1: canalLabel import 추가**

`DataConfig.tsx` 상단 import 블록(5번째 줄 `import * as yup` 아래)에 추가:
```typescript
import { canalLabel } from 'src/configs/deliveryLabels'
```

- [ ] **Step 2: Cliente 렌더러에 배달 분기 추가**

`renderClienteOrRoute`(약 84–123줄)의 마지막 `// sale: 기존 cliente 이름` 블록을 교체. 배달 sale이면 등록 고객명 우선:
```typescript
  // 배달 sale: restaurant_deliveries 등록 고객명 (백엔드 enrichment 의 row.delivery)
  if (row?.source === 'delivery') {
    return (
      <Typography
        variant="body2"
        sx={{ fontWeight: 600, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}
      >
        {row?.delivery?.customerName || 'Cliente Indefinido'}
      </Typography>
    )
  }

  // sale: 기존 cliente 이름
  return (
    <Typography
      variant="body2"
      sx={{ fontWeight: 600, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}
    >
      {row?.client?.fullname || row?.storeClient?.fullname || 'Cliente Indefinido'}
    </Typography>
  )
```

- [ ] **Step 3: Vendedor 컬럼 renderCell 에 배달 분기 추가**

Vendedor 컬럼(약 228–239줄)의 `renderCell` 교체:
```typescript
      field: 'seller',
      headerName: 'Vendedor',
      renderCell: (params: GridRenderCellParams) => (
        <Typography variant="body2">
          {params.row.source === 'delivery'
            ? canalLabel(params.row.delivery?.canal)
            : params.row.seller?.name || '—'}
        </Typography>
      ),
```

- [ ] **Step 4: lint 확인 (eslint-guardian)**

eslint-guardian 에이전트를 호출해 `DataConfig.tsx` 변경분의 `newline-before-return`/`lines-around-comment`/`no-unused-vars` 위반을 점검·수정한다.

- [ ] **Step 5: 커밋**

```bash
cd ventago-app
git add src/views/sales/list/components/DataConfig.tsx
git commit -m "feat(delivery): VentaVista 목록 Vendedor=canal / Cliente=배달 고객명

source='delivery' 행만 분기 — 소매(pos) 렌더 무변경(회귀 0).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: 프론트 — SaleDetailPanel Delivery 정보 블록

**Files:**
- Modify: `ventago-app/src/views/sales/list/components/SaleDetailPanel.tsx` (import + 렌더 블록)

> 배경: 패널은 `GET /sales/:id` 응답(`sales`)을 그대로 쓴다. Task 1 Step 6로 단건도 `delivery` 가 부착되므로 `sales.delivery` 를 사용한다.

- [ ] **Step 1: import 추가**

`SaleDetailPanel.tsx` 상단 import 들 아래에 추가:
```typescript
import { Chip } from "@mui/material";
import { canalLabel } from "src/configs/deliveryLabels";
```
> 주석: 기존 `@mui/material` import 줄에 `Chip` 이 이미 있으면 중복 추가하지 말 것(현재 import 줄은 `Box, CircularProgress, Grid, Typography, Divider, Card, CardContent, IconButton`이므로 Chip 없음 → 별도 줄 추가 가능).

- [ ] **Step 2: ClientInfo 아래에 Delivery 블록 렌더**

`SaleDetailPanel.tsx`에서 `<ClientInfo client={sales.client} />`(약 120줄) 바로 아래에 추가:
```tsx
              {sales.delivery && (
                <Card variant="outlined" sx={{ mt: 1 }}>
                  <CardContent sx={{ py: 1.5 }}>
                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 0.5 }}>
                      <Icon icon="mdi:moped" />
                      <Typography variant="subtitle2" sx={{ fontWeight: 700 }}>
                        Delivery
                      </Typography>
                      <Chip size="small" label={canalLabel(sales.delivery.canal)} />
                    </Box>
                    <Typography variant="body2">
                      Cliente: {sales.delivery.customerName || 'Cliente Indefinido'}
                    </Typography>
                    {sales.delivery.customerPhone && (
                      <Typography variant="body2" color="text.secondary">
                        Tel: {sales.delivery.customerPhone}
                      </Typography>
                    )}
                    {sales.delivery.address && (
                      <Typography variant="body2" color="text.secondary">
                        Dirección: {sales.delivery.address}
                      </Typography>
                    )}
                  </CardContent>
                </Card>
              )}
```
> 주석: `Icon` 은 이 파일 상단에서 이미 `@iconify/react`로 import 되어 있음(재import 금지).

- [ ] **Step 3: lint 확인 (eslint-guardian)**

eslint-guardian 에이전트로 `SaleDetailPanel.tsx` 변경분 점검·수정.

- [ ] **Step 4: 커밋**

```bash
cd ventago-app
git add src/views/sales/list/components/SaleDetailPanel.tsx
git commit -m "feat(delivery): VentaVista 상세 패널에 Delivery 정보 블록

sales.delivery(단건 enrichment) 존재 시 canal/고객명/전화/주소 표시.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Part B — DeliveryBoard Historial

### Task 5: 백엔드 — getHistory 서비스 + 라우트

**Files:**
- Modify: `api-ventago/src/app/restaurant-delivery/restaurant-delivery.service.ts` (`getHistory` 메서드)
- Modify: `api-ventago/src/app/restaurant-delivery/restaurant-delivery.controller.ts` (`GET history/:branchId`)
- Test: `api-ventago/src/app/restaurant-delivery/restaurant-delivery.service.spec.ts`

데이터 계약 — 카드 배열(getBoard 형태 + `settledAt`):
```
{ id, saleId, orderNo, status, tipo, canal, paymentMode, customerName,
  customerPhone, address, repartidorId, externalRef, total, orderedAt,
  deliveredAt, settledAt }
```

- [ ] **Step 1: 실패 테스트 작성**

`restaurant-delivery.service.spec.ts` 맨 아래 `describe` 추가. 기존 `build()` 헬퍼가 `makeSequelize()`(query mock 포함)로 service를 구성하므로 그대로 재사용:
```typescript
describe('getHistory', () => {
  it('종료 상태 + 날짜 범위로 storeId 스코프 조회 후 카드 매핑', async () => {
    const { service, sequelize } = build();
    sequelize.query.mockResolvedValueOnce([
      {
        id: 9,
        saleId: 555,
        status: 'liquidado',
        tipo: 'delivery',
        canal: 'whatsapp',
        paymentMode: 'efectivo',
        customerName: 'Juan',
        customerPhone: '099',
        address: 'Av 1',
        repartidorId: 7,
        externalRef: null,
        orderedAt: '2026-06-18T10:00:00Z',
        deliveredAt: '2026-06-18T11:00:00Z',
        settledAt: '2026-06-18T12:00:00Z',
        total: 1500,
        dailyNumber: 42,
      },
    ]);

    const result = await service.getHistory(3, 2, '2026-06-18', '2026-06-19');

    expect(result).toHaveLength(1);
    expect(result[0]).toMatchObject({
      id: 9,
      orderNo: 42,
      status: 'liquidado',
      total: 1500,
      settledAt: '2026-06-18T12:00:00Z',
    });
    // storeId/branchId/from/to 스코프 전달 검증
    expect(sequelize.query).toHaveBeenCalledWith(
      expect.stringContaining("status IN ('liquidado','conciliacion','cancelado')"),
      expect.objectContaining({
        replacements: { storeId: 3, branchId: 2, from: '2026-06-18', to: '2026-06-19' },
      }),
    );
  });
});
```
> 주석: 기존 `build()` 가 `{ service, sequelize, ... }` 형태를 반환하지 않으면, 파일 상단 `build()` 의 `return` 객체에 `sequelize` 가 포함돼 있는지 확인하고 없으면 그 반환에 `sequelize` 를 추가한다(반환에 이미 존재 시 그대로 사용).

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd api-ventago && npx jest src/app/restaurant-delivery/restaurant-delivery.service.spec.ts -t "getHistory"`
Expected: FAIL — `service.getHistory is not a function`

- [ ] **Step 3: getHistory 구현**

`restaurant-delivery.service.ts` `getOrderDetail` 메서드 아래에 추가:
```typescript
  // ── 이력 조회 (Historial) ──
  // 종료 상태(liquidado/conciliacion/cancelado)를 날짜 범위로 조회. getBoard 와 같은 카드 shape + settledAt.
  // 날짜 범위 필수(unbounded scan 방지) — from 이상, to 미만(exclusive). storeId 스코프(IDOR).
  async getHistory(
    storeId: number,
    branchId: number,
    from: string,
    to: string,
  ): Promise<any[]> {
    if (!from || !to) {
      throw new BadRequestException('Rango de fechas requerido (from/to)');
    }

    const rows: any[] = await this.sequelize.query(
      `
      SELECT rd.id,
             rd.sale_id        AS "saleId",
             rd.status,
             rd.tipo,
             rd.canal,
             rd.payment_mode   AS "paymentMode",
             rd.customer_name  AS "customerName",
             rd.customer_phone AS "customerPhone",
             rd.address,
             rd.repartidor_id  AS "repartidorId",
             rd.external_ref   AS "externalRef",
             rd.ordered_at     AS "orderedAt",
             rd.delivered_at   AS "deliveredAt",
             rd.settled_at     AS "settledAt",
             COALESCE(s.total_amount, 0) AS "total",
             s.daily_number    AS "dailyNumber"
      FROM restaurant_deliveries rd
      LEFT JOIN sales s ON s.id = rd.sale_id
      WHERE rd.store_id = :storeId
        AND rd.branch_id = :branchId
        AND rd.status IN ('liquidado','conciliacion','cancelado')
        AND rd.ordered_at >= :from
        AND rd.ordered_at < :to
      ORDER BY rd.ordered_at DESC
      `,
      {
        replacements: { storeId, branchId, from, to },
        type: QueryTypes.SELECT,
      },
    );

    return rows.map((r) => ({
      id: r.id,
      saleId: r.saleId,
      orderNo: r.dailyNumber ?? r.id,
      status: r.status,
      tipo: r.tipo,
      canal: r.canal,
      paymentMode: r.paymentMode,
      customerName: r.customerName ?? null,
      customerPhone: r.customerPhone ?? null,
      address: r.address ?? null,
      repartidorId: r.repartidorId ?? null,
      externalRef: r.externalRef ?? null,
      total: Number(r.total) || 0,
      orderedAt: r.orderedAt ?? null,
      deliveredAt: r.deliveredAt ?? null,
      settledAt: r.settledAt ?? null,
    }));
  }
```
> 주석: `BadRequestException` 은 이 파일 상단에서 이미 import 됨. `QueryTypes`·`this.sequelize` 도 getBoard 에서 사용 중이라 그대로 사용 가능.

- [ ] **Step 4: 컨트롤러 라우트 추가**

`restaurant-delivery.controller.ts` `board/:branchId` 라우트(약 44–49줄) 바로 아래에 추가(`:id` 경로보다 위 — NestJS 우선순위):
```typescript
  // 이력 조회 — 종료 상태 배달, 날짜 범위(from/to). board 와 같이 :id 앞에 배치.
  @Get('history/:branchId')
  @Auth()
  async history(
    @Param('branchId') branchId: string,
    @Query('from') from: string,
    @Query('to') to: string,
    @GetUser() user: any,
  ) {
    return this.service.getHistory(user.storeId, +branchId, from, to);
  }
```
> 주석: `@Query` 가 이 컨트롤러에 import 돼 있는지 확인. 없으면 `@nestjs/common` import 에 `Query` 추가(payout/reconcile 라우트가 `@Query('branchId')` 를 쓰므로 이미 있음).

- [ ] **Step 5: 테스트 통과 확인**

Run: `cd api-ventago && npx jest src/app/restaurant-delivery/restaurant-delivery.service.spec.ts`
Expected: PASS (신규 getHistory + 기존 케이스 유지)

- [ ] **Step 6: 빌드 확인**

Run: `cd api-ventago && npm run build`
Expected: 성공

- [ ] **Step 7: 커밋**

```bash
cd api-ventago
git add src/app/restaurant-delivery/restaurant-delivery.service.ts \
        src/app/restaurant-delivery/restaurant-delivery.controller.ts \
        src/app/restaurant-delivery/restaurant-delivery.service.spec.ts
git commit -m "feat(delivery): 종료 상태 배달 이력 조회 GET history/:branchId

liquidado/conciliacion/cancelado + 날짜 범위(필수) storeId 스코프 조회.
getBoard 카드 shape + settledAt. 라이브 보드 쿼리 무변경.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: 프론트 — useDeliveryHistory SWR 훅

**Files:**
- Create: `ventago-app/src/hooks/api/useDeliveryHistory.ts`

- [ ] **Step 1: 훅 구현**

`ventago-app/src/hooks/api/useDeliveryHistory.ts`:
```typescript
import { useApi } from 'src/hooks/useApi'
import { DeliveryCard } from './useDeliveryBoard'

// Historial 카드 — board 카드 + settledAt(정산 시각).
export interface DeliveryHistoryCard extends DeliveryCard {
  settledAt: string | null
}

// 종료 상태 배달 이력 — branchId/from/to 모두 있어야 fetch. Socket push 없음(정적 이력).
// to 는 exclusive 이므로 호출부가 종료일+1일을 넘긴다.
export function useDeliveryHistory(
  branchId?: number,
  from?: string,
  to?: string,
) {
  const key =
    branchId && from && to
      ? `/restaurant-delivery/history/${branchId}?from=${from}&to=${to}`
      : null
  const { data, error, isLoading, mutate } = useApi<DeliveryHistoryCard[]>(key)

  return { history: data ?? [], error, isLoading, mutate }
}
```
> 주석: `DeliveryCard` 는 `useDeliveryBoard.ts` 에서 export 됨(확인된 export). 별도 `settledAt` 만 확장.

- [ ] **Step 2: 타입체크 확인**

Run: `cd ventago-app && npx tsc --noEmit`
Expected: 신규 파일 관련 에러 없음 (기존 무관 에러가 있으면 신규 파일 한정으로 확인)

- [ ] **Step 3: 커밋**

```bash
cd ventago-app
git add src/hooks/api/useDeliveryHistory.ts
git commit -m "feat(delivery): useDeliveryHistory SWR 훅

GET history/:branchId?from=&to= — 종료 상태 배달 이력(정적, 폴링 없음).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: 프론트 — DeliveryBoard Tablero/Historial 토글 + 이력 렌더

**Files:**
- Modify: `ventago-app/src/views/restaurante/DeliveryBoard.tsx`

- [ ] **Step 1: import 추가**

`DeliveryBoard.tsx` 상단 MUI/훅 import에 추가(기존 import 라인 구조에 맞춰 병합):
```typescript
import { ToggleButton, ToggleButtonGroup, TextField } from '@mui/material'
import { useDeliveryHistory } from 'src/hooks/api/useDeliveryHistory'
import { canalLabel, deliveryStatusLabel, deliveryStatusColor } from 'src/configs/deliveryLabels'
```
> 주석: `Box, Typography, Button, Alert, CircularProgress, Menu, MenuItem, Chip` 등 이미 import 된 것은 중복 추가 금지. `ToggleButton`/`ToggleButtonGroup`/`TextField` 만 신규.

- [ ] **Step 2: 뷰/날짜 state + 오늘 기본값 헬퍼 추가**

컴포넌트 본문에서 `const branchId = ...`(약 79줄) 아래에 추가:
```typescript
  // Tablero(라이브 칸반) / Historial(종료 상태 이력) 토글
  const [view, setView] = useState<'tablero' | 'historial'>('tablero')

  // 이력 날짜 범위(Desde/Hasta, inclusive UI). 기본 = 오늘.
  const todayStr = useMemo(() => new Date().toISOString().slice(0, 10), [])
  const [fromDate, setFromDate] = useState<string>(todayStr)
  const [toDate, setToDate] = useState<string>(todayStr)

  // 백엔드는 to exclusive 이므로 종료일+1일을 전달
  const toExclusive = useMemo(() => {
    const d = new Date(`${toDate}T00:00:00`)
    d.setDate(d.getDate() + 1)

    return d.toISOString().slice(0, 10)
  }, [toDate])

  // 이력은 Historial 탭일 때만 fetch (key=null 이면 SWR skip)
  const { history, isLoading: loadingHistory, error: historyError } =
    useDeliveryHistory(
      view === 'historial' ? branchId : undefined,
      fromDate,
      toExclusive,
    )
```
> 주석: `useState`, `useMemo` 는 파일 상단에서 이미 import 됨(컴포넌트가 사용 중).

- [ ] **Step 3: 헤더에 토글 추가**

헤더 박스(약 213–223줄, 제목 "Delivery" + Nuevo pedido 버튼)에서 제목과 버튼 사이에 토글 삽입. 기존 헤더 블록을 다음으로 교체:
```tsx
      {/* 헤더 — 제목 + 뷰 토글 + Nuevo pedido 버튼 */}
      <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: 1, gap: 1 }}>
        <Typography sx={{ color: '#f4f4f8', fontWeight: 700, fontSize: 18 }}>Delivery</Typography>
        <ToggleButtonGroup
          size="small"
          exclusive
          value={view}
          onChange={(_e, v) => { if (v) setView(v) }}
          sx={{
            '& .MuiToggleButton-root': { color: '#9a9ab0', borderColor: 'rgba(255,255,255,0.15)' },
            '& .Mui-selected': { color: '#0f0f1e !important', bgcolor: '#f5a623 !important' },
          }}
        >
          <ToggleButton value="tablero">Tablero</ToggleButton>
          <ToggleButton value="historial">Historial</ToggleButton>
        </ToggleButtonGroup>
        <Button
          variant="contained"
          startIcon={<Icon icon="mdi:plus" />}
          onClick={() => { setEditCard(null); setModalOpen(true) }}
          sx={{ bgcolor: '#f5a623', color: '#0f0f1e', fontWeight: 700, '&:hover': { bgcolor: '#d98e0f' } }}
        >
          Nuevo pedido
        </Button>
      </Box>
```

- [ ] **Step 4: 칸반 영역을 view 분기로 감싸기**

kanban 컬럼 박스(약 239–262줄, `{/* kanban 컬럼 ... */}` 부터 닫는 `</Box>` 까지)를 다음으로 교체. Tablero는 기존 칸반 유지, Historial은 읽기전용 목록:
```tsx
      {/* Tablero — 기존 라이브 칸반 */}
      {view === 'tablero' && (
        <Box sx={{ display: 'flex', flex: 1, minHeight: 0, gap: 1.5, overflowX: 'auto' }}>
          {isLoading && (
            <Box sx={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <CircularProgress color="primary" />
            </Box>
          )}

          {!isLoading &&
            COLUMNS.map((col) => (
              <BoardColumn
                key={col.key}
                column={col}
                cards={cardsByStatus.get(col.key) ?? []}
                nowMs={nowMs}
                formatPrice={formatPrice}
                riderName={riderName}
                onAdvance={handleTransition}
                onAssign={openAssign}
                onEdit={openEdit}
                onAddOrder={col.key === 'nuevo' ? () => { setEditCard(null); setModalOpen(true) } : undefined}
              />
            ))}
        </Box>
      )}

      {/* Historial — 종료 상태 배달, 읽기전용 */}
      {view === 'historial' && (
        <Box sx={{ display: 'flex', flexDirection: 'column', flex: 1, minHeight: 0, gap: 1 }}>
          {/* 날짜 범위 필터 */}
          <Box sx={{ display: 'flex', gap: 1, alignItems: 'center' }}>
            <TextField
              type="date"
              size="small"
              label="Desde"
              InputLabelProps={{ shrink: true }}
              value={fromDate}
              onChange={(e) => setFromDate(e.target.value)}
            />
            <TextField
              type="date"
              size="small"
              label="Hasta"
              InputLabelProps={{ shrink: true }}
              value={toDate}
              onChange={(e) => setToDate(e.target.value)}
            />
          </Box>

          {historyError && (
            <Alert severity="error">No se pudo cargar el historial.</Alert>
          )}

          <Box sx={{ flex: 1, minHeight: 0, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 0.75 }}>
            {loadingHistory && (
              <Box sx={{ display: 'flex', justifyContent: 'center', py: 2 }}>
                <CircularProgress color="primary" />
              </Box>
            )}
            {!loadingHistory && history.length === 0 && (
              <Typography sx={{ color: '#9a9ab0', fontSize: 13, px: 0.5 }}>
                Sin pedidos en el rango seleccionado.
              </Typography>
            )}
            {!loadingHistory && history.map((h) => (
              <Box
                key={h.id}
                sx={{
                  bgcolor: '#1a1a2e',
                  border: '1px solid rgba(255,255,255,0.1)',
                  borderRadius: 1.5,
                  px: 1.25,
                  py: 0.75,
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'space-between',
                  gap: 1,
                }}
              >
                <Box sx={{ minWidth: 0 }}>
                  <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.75, flexWrap: 'wrap' }}>
                    <Typography sx={{ color: '#f4f4f8', fontWeight: 700, fontSize: 14 }}>
                      #{h.orderNo}
                    </Typography>
                    <Chip size="small" label={canalLabel(h.canal)} sx={{ height: 20, fontSize: 11 }} />
                    <Chip
                      size="small"
                      color={deliveryStatusColor(h.status)}
                      label={deliveryStatusLabel(h.status)}
                      sx={{ height: 20, fontSize: 11 }}
                    />
                  </Box>
                  <Typography sx={{ color: '#e0e0ec', fontSize: 13 }}>
                    {h.customerName || 'Cliente Indefinido'}
                    {h.customerPhone ? ` · ${h.customerPhone}` : ''}
                  </Typography>
                  {h.address && (
                    <Typography sx={{ color: '#9a9ab0', fontSize: 12 }}>{h.address}</Typography>
                  )}
                </Box>
                <Box sx={{ textAlign: 'right' }}>
                  <Typography sx={{ color: '#f5a623', fontWeight: 800, fontSize: 15, fontVariantNumeric: 'tabular-nums' }}>
                    {formatPrice(h.total)}
                  </Typography>
                  <Typography sx={{ color: '#9a9ab0', fontSize: 11 }}>
                    {h.paymentMode}
                  </Typography>
                </Box>
              </Box>
            ))}
          </Box>
        </Box>
      )}
```
> 주석: Historial은 상태 전이/편집/취소 버튼·핸들러를 전혀 포함하지 않음(읽기전용). 라이브 보드의 소켓/배차/모달 로직은 모두 변경 없이 유지.

- [ ] **Step 5: lint 확인 (eslint-guardian)**

eslint-guardian 에이전트로 `DeliveryBoard.tsx` 변경분의 `newline-before-return`/`lines-around-comment`/`no-unused-vars` 점검·수정.

- [ ] **Step 6: 빌드 확인**

Run: `cd ventago-app && npx tsc --noEmit`
Expected: 신규 변경 관련 에러 없음

- [ ] **Step 7: 커밋**

```bash
cd ventago-app
git add src/views/restaurante/DeliveryBoard.tsx
git commit -m "feat(delivery): DeliveryBoard Tablero/Historial 토글 + 이력 조회

Historial 탭 — 날짜 범위로 종료 상태 배달 읽기전용 목록.
라이브 칸반(6컬럼)+소켓 로직 무변경.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8: 통합 검증 + UAT

**Files:** (없음 — 검증/수정만)

- [ ] **Step 1: 백엔드 전체 테스트 + 빌드**

Run: `cd api-ventago && npx jest src/app/sales src/app/restaurant-delivery && npm run build`
Expected: 모든 테스트 PASS, 빌드 성공

- [ ] **Step 2: 프론트 테스트 + lint + 빌드**

Run: `cd ventago-app && npx jest src/__tests__/deliveryLabels.spec.ts && npm run lint`
Expected: 테스트 PASS, lint 0 error
(추가로 `npm run build` 로 Next.js 프로덕션 빌드 통과 확인)

- [ ] **Step 3: 로컬 실행 후 브라우저 UAT**

`./dev.sh` 실행 후(식당 모드 store 로그인), preview 도구로 확인:
1. WhatsApp 채널 배달 주문 생성 → En camino → Entregado → (현금) Por cobrar → Liquidación 등록
2. **VentaVista(/ventas)**: 해당 배달 행의 Vendedor=`WhatsApp`, Cliente=등록 고객명 표시 확인
3. 그 행 클릭 → 우측 패널에 **Delivery 블록**(canal/고객명/전화/주소) 표시 확인
4. **소매(pos) 판매** 행: Vendedor=판매원명, Cliente=고객명 — 기존대로(회귀 0) 확인
5. **DeliveryBoard**: `Historial` 토글 → 오늘 범위에 방금 liquidado 건 노출, 상태칩=Liquidado(green), 버튼 없음(읽기전용) 확인
6. 날짜 범위 변경 → 결과 갱신 확인
7. `Tablero` 토글 복귀 → 라이브 칸반 6컬럼·소켓 push 정상 확인

- [ ] **Step 4: 운영 배포 메모(실행은 사용자 승인 후)**

DDL 없음 → 마이그레이션 불필요. `./push-both.sh` 로 api-ventago + ventago-app push(코드 변경만). Jenkins 빌드 후 운영 반영. (배포는 사용자 지시 시 수행)

---

## Self-Review

**Spec coverage:**
- A 백엔드 enrichment(목록+단건) → Task 1 ✓
- A Vendedor=canal / Cliente=customerName(VentaVista 목록) → Task 3 ✓
- A 상세 드로어 Delivery 블록 → Task 4 ✓
- A canal 라벨 매핑 → Task 2 ✓
- B `GET history/:branchId`(종료 상태 + 날짜 범위 + storeId 스코프) → Task 5 ✓
- B useDeliveryHistory 훅 → Task 6 ✓
- B DeliveryBoard Tablero/Historial 토글 + 날짜 필터 + 읽기전용 → Task 7 ✓
- 회귀 안전(pos 무변경), pool 안전(페이지당 +1 쿼리), 멀티테넌트 storeId 스코프 → Task 1/5 구현에 반영 ✓
- 검증/UAT → Task 8 ✓

**Placeholder scan:** 모든 코드 스텝에 실제 코드 포함. "적절히 처리" 류 없음. ✓

**Type consistency:**
- 백엔드 `delivery` 객체 키(`canal/customerName/customerPhone/address/status/repartidorId`) — Task 1 부착, Task 3/4 사용 일치 ✓
- 이력 카드 키(`orderNo/status/canal/customerName/customerPhone/address/total/paymentMode/settledAt` 등) — Task 5 매핑, Task 6 타입(`DeliveryHistoryCard`), Task 7 렌더 일치 ✓
- 헬퍼 시그니처 `canalLabel/deliveryStatusLabel/deliveryStatusColor` — Task 2 정의, Task 3/4/7 사용 일치 ✓

**미세 가정(실행자 확인 포인트):**
- Task 5 Step 1: 기존 `build()` 반환에 `sequelize` 포함 여부 확인(없으면 추가).
- Task 1 Step 6: `findOne` 의 단일 반환 지점 확인 후 삽입.
- 각 프론트 파일 import 중복 방지(주석 명시).
