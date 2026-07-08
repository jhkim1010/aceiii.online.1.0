# PLAN: [Phase 44.1-P2] despacho 단계 되돌리기(취소)
확정일: 2026-07-08 · SPEC: `spec-despacho-revert.md` · **전제: P1(`plan-recognition-at-ship.md`) 완료**

## 확정 스코프 (P1 모델: 매출인식=ship)
- **1계단씩만** 되돌림.
- 재무 무관 3구간: preparando→nuevo, listo→preparando, **entregado→en_transito**.
- 재무 역처리 1구간(완납만): **en_transito→listo(un-ship)**. 외상 발송(shipSaldo>0)은 차단.
- 스키마/마이그레이션 없음(metadata JSON). runStatusTx 단일 tx 재사용 → 신규 connect 0.

## 되돌리기 매핑 (구현 기준, P1 모델)
| from status | 조건 | to status | sideEffect | 재무 |
|---|---|---|---|---|
| PREPARING | preparedAt==null (=preparando) | CONFIRMED | metadata.preparingAt 삭제; actor 'confirmed' | 무관 |
| PREPARING | preparedAt!=null (=listo) | PREPARING | preparedAt=null; actor 'preparing' | 무관 |
| DELIVERED | (=entregado) | SHIPPED | deliveredAt=null; actor 'shipped'; setRevertedActor | 무관 |
| SHIPPED | metadata.shipSaldo==0 (완납) | PREPARING | **un-ship**(TASK-1B); to listo(preparedAt 유지) | 역처리 |
| SHIPPED | metadata.shipSaldo>0 (외상) | — | BadRequest "외상으로 발송된 건은 되돌릴 수 없습니다. 취소(cancelar)를 사용하세요." | — |
| CONFIRMED/PENDING | (=nuevo) | — | BadRequest "이미 첫 단계입니다." | — |
| CANCELLED/RETURNED/CLOSED | — | — | BadRequest "이 상태는 되돌릴 수 없습니다." | — |

성공 케이스: commit 후 `emitCard` + `metadata.stageActors.reverted={userId,name,at,from,to}` 감사.

주의: SHIPPED→PREPARING 되돌림의 목적지는 **listo**(preparedAt 유지) — ship 직전이 listo 였으므로. preparedAt 이 null 이면 now 로 보정.

---

## 태스크

### TASK-1 · revertOrder 라우팅 + 재무 무관 구간
`api-ventago/src/app/online-orders/online-orders.service.ts`
- `async revertOrder(storeId, id, userId?, userName?): Promise<OnlineOrder>` 추가.
- findById 로 status/preparedAt/metadata.shipSaldo 읽어 라우팅:
  - SHIPPED & `Number(metadata?.shipSaldo ?? 0) > 0` → `throw BadRequest('외상으로 발송된 건은 되돌릴 수 없습니다. 취소(cancelar)를 사용하세요.')`
  - SHIPPED & shipSaldo==0 → **TASK-1B**(from `[SHIPPED]`, to `PREPARING`, SERIALIZABLE)
  - DELIVERED → from `[DELIVERED]` to `SHIPPED`, sideEffect: `order.deliveredAt=null; setStageActor(order,'shipped',...); setRevertedActor(...)` · **재무 무관**
  - PREPARING & preparedAt==null → from `[PREPARING]` to `CONFIRMED`; sideEffect: metadata.preparingAt 삭제; actor 'confirmed'
  - PREPARING & preparedAt!=null → from `[PREPARING]` to `PREPARING`; sideEffect: preparedAt=null; actor 'preparing'
  - PENDING/CONFIRMED → BadRequest '이미 첫 단계입니다.'
  - CANCELLED/RETURNED/CLOSED → BadRequest '이 상태는 되돌릴 수 없습니다.'
- `setRevertedActor(order, from, to, userId?, name?)` 헬퍼 추가(metadata.stageActors.reverted).
- post-commit emitCard 후 return.
- 확인 완료: runStatusTx(2694) from==to 허용 → listo→preparando(PREPARING→PREPARING) 소경로 불필요.

### TASK-1B · en_transito→listo un-ship (완납만) sideEffect
DELIVERED 아닌 **SHIPPED & shipSaldo==0** 케이스. P1 에서 ship 이 한 commitSale+createMirror 를 역처리(sale_credit 은 완납이라 없음):
1. **재고 un-commit**: `stockService.reverseSale(order, t)` + `stockService.holdStock(order, t)` → ledger sale +qty / suspend -qty(hold 복원), product.stock ±qty 상쇄 net 0. (ship/commitSale 의 정확한 역방향)
2. **판매 미러**: `order.mirrorSaleId` 있으면 `mirrorService.nullifyMirror(order, t)`(원본 NULLIFIED + 음수 역분개) 후 `order.mirrorSaleId = null`(re-ship 시 isNewMirror=true).
3. **외상**: 없음(shipSaldo==0 게이트).
4. **필드 초기화**: `shippedAt=null; dispatchedAt=null; stockReleasedAt=null`; metadata 에서 shipSaldo/shipSaldoStoreClientId/shipSaldoUserId 잔재 정리; `paymentStatus` 를 ship 이전(pending/partial)으로 복원 — ship 이 PAID 로 바꿨으면 되돌림; preparedAt 유지(null이면 now); `setStageActor(order,'ready',...)`; `setRevertedActor(order,'en_transito','listo',...)`.
5. runStatusTx 가 status=PREPARING 저장 + commit + emitCard.
- **re-ship 검증(UAT)**: un-ship 후 다시 발송 → mirrorSaleId=null → isNewMirror=true → 정상 재확정(재고 이중차감 0, sale_credit 완납이라 없음).
- UAT-A(Ventas 음수 sale) · UAT-B(완납금 mirror 상쇄, cobro 무변경).

### TASK-2 · online-orders.controller.ts — `PATCH :id/revert`
`@Patch(':id/revert')` — 기존 상태전이 핸들러의 가드·`@Audit`·`req.user` 패턴 모방 → `revertOrder(storeId,+id,req.user?.id,req.user?.name)`.

### TASK-3 · despacho.controller.ts — `PATCH orders/:id/revert`
`DespachoDeviceGuard`+`x-operario` → `despachoService.revert(storeId,+id,deviceLabel,operario)`.

### TASK-4 · despacho.service.ts — `revert` 위임
`revert(storeId,id,deviceLabel,operarioName?)` → `onlineOrdersService.revertOrder(storeId,id,undefined,operarioName ?? deviceLabel)`.

### TASK-5 · DespachoBoard.tsx — 되돌리기 버튼 + 확인
`ventago-app/src/views/ventas-online/DespachoBoard.tsx`
- revertable 컬럼(preparando/listo/en_transito/entregado)에 되돌리기 아이콘. nuevo 미노출.
- **en_transito 완납 카드**: 강한 경고("발송을 되돌리면 판매 기록이 역처리됩니다. 계속?"). 외상 발송(saldo>0) 카드는 버튼 비활성/숨김(백엔드도 차단). entregado/preparando/listo 는 일반 확인.
- 확인 → `PATCH /online-orders/:id/revert` → `mutate()`. 에러: 인라인 Alert + 글로벌 토스트.
- **ESLint**: return 위 빈 줄 / 주석 위 빈 줄 / no-unused-vars.

### TASK-6 · api_service.dart — `revert`
`despacho-app/lib/services/api_service.dart` — 기존 상태전이 패턴 그대로 `Future<void> revert(int id)` → `PATCH /despacho/orders/:id/revert`(기기토큰+x-operario). try/catch+rethrow.

### TASK-7 · despacho-app 화면 — 되돌리기 버튼
`despacho-app/lib/screens/` — revertable 단계 버튼 + 확인(en_transito 경고 강화, 외상건 숨김) → `api.revert(id)` → Riverpod invalidate. nuevo 숨김.

### TASK-8 · Lint/analyze (Mac 위임)
ventago-app eslint-guardian → 0. despacho-app `flutter analyze` → 0.

### TASK-9 · pool + 회귀
- revertOrder(1B 포함) runStatusTx 단일 tx 외 신규 connect 0(reverseSale/holdStock/nullifyMirror 모두 `t` 사용). pg-pool-doctor.
- ship/deliver/cancel 기존 경로 무변경(P2 는 revert 만 추가). 소매/식당 회귀 금지.

---

## 완료 기준
- 재무 무관 3구간(preparando→nuevo / listo→preparando / entregado→en_transito) 1계단 되돌리기 정상 + 웹/앱 실시간.
- **en_transito→listo 완납 un-ship** 정상: ledger sale→suspend(product.stock net 0) · mirror NULLIFIED · mirrorSaleId=null · paymentStatus 복원. re-ship 왕복 재고 이중차감 0.
- **외상 발송 en_transito**(shipSaldo>0) → 차단. 취소/반품/첫단계 → 차단.
- metadata.stageActors.reverted 감사. ESLint 0 · flutter analyze 0 · 신규 connect 0.
- UAT-A(Ventas 음수 sale) · UAT-B(완납금 mirror 상쇄) 확인.

## 금지/주의
- P1 미완료 시 착수 금지.
- ship/deliver/cancel 로직 변경 금지 — revert 헬퍼 재사용만(reverseSale/holdStock/nullifyMirror).
- 외상원장 무변경 — 외상 un-ship 차단으로 회피.
- product.stock 순변화 0. sale 삭제 금지(nullify만). `apiConnector.remove()`. lint 규약.

## 미해결
- 없음. (외상 un-ship 차단 → sale_credit 역기입 불필요. reverseSale+holdStock net 0 / nullifyMirror / runStatusTx from==to 전부 코드 검증 완료.)
