# SPEC: CT 발급 Etapa 가드 + Etapa order 자동 부여

생성일: 2026-04-23

## 목표

두 가지 사용성/안전성 개선:

1. **CT 발급 시 활성 Etapa가 0개면 명확한 에러로 차단** — 이번에 CT-2026-007이 routing_path=[]로 저장된 근본 원인을 재발 방지. 사용자에게 "Registrá primero las etapas de producción"이라는 한국어 대신 스페인어 메시지를 반환하여 프론트 toast로 자동 표시.
2. **EtapasTab에서 Etapa 생성 시 order를 비워두면 자동으로 다음 순번 부여** — 현재 기본값 0으로 쌓여서 여러 etapa가 order=0 동률이 되는 문제 해결 (실제 coolsistema에 `corte(0), lavadero(0)` 동률 발견).

## 배경 및 컨텍스트

### 발견된 운영 DB 사실 (2026-04-23 조사)
- CT-2026-007 (store_id=6, coolsistema) → routing_path=[] (빈 배열)
- 그 시점에 store_id=6의 talleres_etapas 0개 → 현재는 6개 (5개 활성 + 1개 비활성)
- 현재 활성 etapa 중 `corte(0)`과 `lavadero(0)`가 order 동률 상태 → 자동 부여였으면 1,2,...가 나왔을 것

### 관련 파일
- 백엔드 가드: `api-ventago/src/app/subcon/lotes/lote.service.ts` (라인 246~, `generateCutTicket`)
- 백엔드 routing: 같은 파일 라인 543~ (`buildRoutingPath`) — 이번 기회에 `isActive: true` 필터 추가
- 백엔드 Etapa create: `api-ventago/src/app/subcon/etapas/etapa.service.ts` (CrudService.create를 override)
- 프론트 CT 발급: `ventago-app/src/views/talleres/cut-ticket/components/CutTicketEmptyState.tsx` (이미 `err.response.data.message` toast 처리 있음 → 수정 불필요)
- 프론트 Etapa Dialog: `ventago-app/src/views/talleres/tabs/EtapasTab.tsx` — Order 필드에 placeholder/helperText 안내 추가

## 기술 스택

- 백엔드: NestJS 11 + Sequelize + PG15 (Docker local) / PG10 (운영 host)
- 프론트: Next.js 13 + MUI 5
- DB 스키마 변경 없음

## 태스크 목록

- [x] TASK-12: SPEC 작성 (현재 문서)
- [ ] TASK-13: `generateCutTicket` 가드 추가 — STEP-4b 직전에 활성 Etapa count 조회, 0이면 `BadRequestException('No hay etapas de producción activas. Registrá las etapas antes de generar el Cut Ticket.')`
- [ ] TASK-13a: `buildRoutingPath`의 `where: { storeId }` → `where: { storeId, isActive: true }` 추가 (비활성 공정은 routing에서 제외)
- [ ] TASK-14: `EtapaService.create` override — `order`가 `undefined`, `null`, 또는 `0`일 때 `MAX(order) + 1` 자동 부여. storeId 범위로 한정. 트랜잭션/락 불필요 (low contention).
- [ ] TASK-15a: EtapasTab Dialog Order 필드에 `placeholder="Automático"` + `helperText="Dejá vacío para asignar automáticamente el siguiente número"` 추가
- [ ] TASK-15b: 신규 생성 모드일 때 `handleOpenCreate`에서 `order: 0`을 그대로 두되, 저장 직전 `handleSave`에서 0이면 body에서 제거(또는 null 전달) — 백엔드가 자동 부여하도록
- [ ] TASK-16: ESLint 프론트 + 백엔드 (제 변경 영역만)
- [ ] TASK-16b: 리뷰 리포트

## 상세 구현

### 1) `generateCutTicket` 가드 (lote.service.ts:386 근처)

STEP-4a(BOM) 직전 또는 직후, STEP-4b(buildRoutingPath) 호출 **앞**에 추가:

```typescript
// STEP-4 pre-check: 활성 Etapa가 1개 이상 있어야 CT 발급 가능
const activeEtapaCount = await this.etapaModel.count({
  where: { storeId, isActive: true },
  transaction: tx,
});
if (activeEtapaCount === 0) {
  this.logger.warn(`[generateCutTicket] STEP-4pre 활성 etapa 0개 — 발급 차단 store=${storeId}`);
  throw new BadRequestException(
    'No hay etapas de producción activas. Registrá las etapas antes de generar el Cut Ticket.'
  );
}
```

`BadRequestException` import 확인 필요 (`@nestjs/common`).

### 2) `buildRoutingPath` isActive 필터 (라인 552)

```typescript
const etapas = await this.etapaModel.findAll({
  where: { storeId, isActive: true },  // ← isActive 추가
  order: [['order', 'ASC']],
  transaction: tx,
});
```

효과: 비활성 etapa가 새로운 CT의 routing에 포함되지 않음. 기존 CT는 영향 없음(스냅샷이라서).

### 3) `EtapaService.create` override (etapa.service.ts)

```typescript
async create(data: any): Promise<Etapa> {
  // order가 명시적으로 양수로 들어온 게 아니면 자동 부여
  const explicitOrder = typeof data?.order === 'number' && data.order > 0;
  if (!explicitOrder && data?.storeId) {
    const maxOrder: number = (await this.etapaModel.max('order', {
      where: { storeId: data.storeId },
    })) as number | null ?? 0;
    data = { ...data, order: Number(maxOrder) + 1 };
  }

  return this.etapaModel.create(data);
}
```

이유: 기존 CrudService.create는 단순 model.create. 순번 로직은 domain specific이라 Etapa에만 override.

### 4) 프론트 Dialog 힌트 (EtapasTab.tsx)

```tsx
<TextField
  margin='dense'
  label='Orden'
  type='number'
  fullWidth
  value={formData.order}
  onChange={e => setFormData({ ...formData, order: Number(e.target.value) })}
  placeholder='Automático'
  helperText='Dejá vacío o 0 para asignar automáticamente el siguiente número'
/>
```

`handleSave`에서 payload 구성 시 order가 0이면 포함하지 않음(또는 null로):
```typescript
const payload: any = {
  name: trimmedName,
  isActive: formData.isActive,
};
if (Number(formData.order) > 0) {
  payload.order = Number(formData.order);
}
```

## 완료 기준

- [ ] 활성 Etapa 0개 매장에서 CT 발급 시도 → 400 + 스페인어 메시지 → 프론트 toast
- [ ] CT-2026-007처럼 routing_path=[]인 기존 CT는 영향 없음 (가드는 발급 시점에만 체크)
- [ ] 새 Etapa 생성 시 order 비우거나 0 입력 → 백엔드에서 `max(order)+1`로 저장됨
- [ ] 명시적으로 order=5 입력 → 그대로 5로 저장
- [ ] buildRoutingPath가 isActive=false etapa를 제외 (새 CT에만 반영)
- [ ] ESLint 프론트 0개, 백엔드 제 변경 영역 0개
- [ ] 기존 테스트 깨지지 않음 (TypeScript 컴파일)

## 금지사항 / 주의사항

- 이미 저장된 CT들의 routing_path 일괄 수정 금지 (immutable 설계 존중)
- PostgreSQL pool 낭비 금지: count/max 쿼리는 1회만, 기존 tx 재사용
- CrudService 공통 로직 건드리지 않음 (etapa만 override)
- 주석은 한국어, 함수/변수명은 영어
- BadRequestException 메시지는 한국어가 아닌 **스페인어** (사용자 화면용)
