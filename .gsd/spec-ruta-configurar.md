# SPEC: Ruta de proceso — Configurar / Editar

생성일: 2026-04-23

## 목표

Cut Ticket 발급 시 각 etapa에 vendor(taller)를 할당할 수 있는 다이얼로그를 추가하고, 발급 후에도 cut_date 설정 전까지는 routing을 수정할 수 있는 "Editar ruta" 버튼을 제공한다. cut_date가 설정되면 matriz와 동일한 방식으로 immutable 잠금. 기존 Envío/Recepción 플로우에는 영향 없음.

## 배경 및 컨텍스트

- 현재 `CutTicketEmptyState.tsx`는 `POST /talleres/lotes/:id/cut-ticket`을 빈 body `{}`로 호출 → 모든 routing이 In-house(vendor=null)
- 백엔드 `generateCutTicket(body)`는 이미 `vendorAssignments?: Array<{etapaId, vendorId: number|null}>` 받도록 설계됨 → 프론트만 전달하면 됨
- `buildRoutingPath(storeId, vendorAssignments, tx)` 이미 구현됨 — 재사용
- `RoutingFlow.tsx`는 순수 시각화. 편집 UI 없음
- 기존 잠금 선례: `size-color-matrix` PATCH 엔드포인트 + `SizeColorMatrixEditor readOnly={!!cutTicket.meta!.cutDate}` 패턴

## 기술 스택

- 백엔드: NestJS 11 + Sequelize + PG
- 프론트: Next.js 13 + MUI 5 + SWR + react-hot-toast
- DB 스키마 변경 없음

## 태스크 목록

- [ ] TASK-21: SPEC 작성 (현재 문서)
- [ ] TASK-22: `LoteService.updateRoutingPath(loteId, storeId, assignments)` 추가
  - cut_date 가드 — 있으면 BadRequestException ("Ruta bloqueada: el corte ya inició")
  - `buildRoutingPath(storeId, assignments, tx)` 재사용
  - `lote.routingPath = newRouting; await lote.save({ transaction: tx });`
  - 캐시 무효화 (기존 size-color-matrix 패턴 참고)
- [ ] TASK-23: `PATCH /talleres/lotes/:id/routing` 엔드포인트 (lote.controller.ts)
  - body: `{ vendorAssignments: Array<{etapaId: number; vendorId: number|null}> }`
  - Auth(admin, superadmin, gerente)
- [ ] TASK-24: `RutaConfigDialog.tsx` 신규
  - Props: `open, onClose, loteId, mode('create'|'edit'), initialAssignments, etapas, onSaved`
  - 각 etapa에 대해 Select/Autocomplete: In-house + 매장 vendor 목록
  - "Configurar y Generar"(create) / "Guardar cambios"(edit) 버튼
  - create 모드: `POST /talleres/lotes/:id/cut-ticket` with `{ vendorAssignments }`
  - edit 모드: `PATCH /talleres/lotes/:id/routing` with `{ vendorAssignments }`
- [ ] TASK-25: `CutTicketEmptyState.tsx` 수정
  - "Generar Cut Ticket" 클릭 → 바로 POST 하지 말고 `RutaConfigDialog`를 create 모드로 오픈
  - etapas는 `useTalleresEtapas()`에서 활성만 필터링
  - 다이얼로그의 `onSaved(response)` → 기존 `onGenerated(response)` 그대로 호출
- [ ] TASK-26: `RoutingFlow.tsx` 수정
  - Props에 `loteId?, cutDate?: string|null, onEdited?: () => void` 추가
  - cut_date 없음 → 우상단 "Editar ruta" 버튼 → RutaConfigDialog edit 모드
  - cut_date 있음 → "Bloqueada" 배지 (matriz와 톤 맞추기)
- [ ] TASK-26b: `CutTicketTab.tsx`에서 RoutingFlow 호출 시 새 props 전달 + mutate 연결
- [ ] TASK-27: ESLint 검증

## 상세 구현

### 백엔드 `updateRoutingPath` 스켈레톤

```typescript
async updateRoutingPath(
  loteId: number,
  storeId: number,
  assignments: Array<{ etapaId: number; vendorId: number | null }>,
): Promise<RoutingPath> {
  return this.sequelize.transaction(async (tx) => {
    const lote = await this.loteModel.findOne({
      where: { id: loteId, storeId },
      transaction: tx,
    });
    if (!lote) throw new NotFoundException(`Lote #${loteId} no encontrado`);
    if (!lote.cutTicketNumber) {
      throw new BadRequestException('El Cut Ticket aún no fue generado');
    }
    if (lote.cutDate) {
      throw new BadRequestException(
        'Ruta bloqueada: el corte ya inició — la ruta no puede modificarse',
      );
    }

    const newRouting = await this.buildRoutingPath(storeId, assignments, tx);
    lote.routingPath = newRouting;
    await lote.save({ transaction: tx });

    tx.afterCommit(() => {
      this.cacheService.delByPrefix(`talleres:cut-ticket:${storeId}:`);
    });

    return newRouting;
  });
}
```

### 프론트 `RutaConfigDialog` 사용 패턴

```tsx
<RutaConfigDialog
  open={dialogOpen}
  mode="create"  // or "edit"
  loteId={loteId}
  etapas={activeEtapas}  // [{id, name, order}]
  vendors={vendorList}  // [{id, name}]
  initialAssignments={routing?.map(r => ({etapaId: r.etapaId, vendorId: r.vendorId})) ?? []}
  onClose={() => setDialogOpen(false)}
  onSaved={handleSaved}
/>
```

### RoutingFlow 잠금 UI

- cutDate === null → `<Button onClick={openEdit}>Editar ruta</Button>`
- cutDate !== null → `<Chip label={\`Bloqueada (corte iniciado ${cutDate})\`} />` + Card opacity 0.7

## 완료 기준

- [ ] 새 Lote에서 CT 발급 시 RutaConfigDialog가 먼저 뜸
- [ ] 각 etapa에 vendor를 선택하거나 "In-house" 유지 가능
- [ ] 발급 후 routing_path가 선택된 vendor로 저장됨
- [ ] 발급된 CT(cut_date=null)에서 "Editar ruta" 버튼으로 routing 수정 가능
- [ ] cut_date가 설정된 CT에서는 "Editar ruta" 숨김, "Bloqueada" 배지 표시
- [ ] 백엔드 cut_date 가드 동작 (이미 잠긴 CT에 PATCH 시 400)
- [ ] 기존 Envío/Recepción 플로우 동작 변화 없음
- [ ] ESLint 0 에러 (제 추가 영역)

## 금지사항 / 주의사항

- 기존 `generateCutTicket`의 다른 파라미터(styleCode, season, initialMatrix) 동작 변경 금지
- `buildRoutingPath`의 시그니처 변경 금지 — 이미 `isActive: true` 필터 들어가 있음
- cache invalidation 키 형식 유지 (`talleres:cut-ticket:${storeId}:`)
- PostgreSQL pool: 모든 쿼리 기존 tx 재사용, `lote.save({ transaction: tx })` 필수
- 주석 한국어, 함수/변수명 영어
- Spanish 사용자 메시지: toast / exception
- RutaConfigDialog는 Autocomplete 대신 Select 사용 (vendor 목록이 매장당 수십 개 이하, 간단)
