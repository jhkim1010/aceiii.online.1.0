# SPEC: [Phase 44.1-P2] despacho 단계 되돌리기(취소)
생성일: 2026-07-08 · **전제: P1(`spec-recognition-at-ship.md`) 완료 후** — 매출인식=ship 모델 기준

## 목표
실수로 다음 단계로 보낸 배송(envío) 주문을 이전 단계로 되돌리는 기능을 백엔드 + venta online 웹 보드 + despacho Flutter 앱 3곳에 추가한다.

## 배경 및 컨텍스트 (P1 적용 후 모델)
- 단계(columnKey): nuevo → preparando → listo → en_transito → entregado
- 상태(status): pending/confirmed(nuevo) → preparing(preparando; preparedAt=null) → preparing(listo; preparedAt!=null) → shipped(en_transito) → delivered(entregado)
- **재고**: product.stock 은 주문 생성(pending) 시 이미 차감(`holdStock`, line 104). nuevo~entregado 내내 빠진 상태 유지.
- **판매확정 시점(P1 이후)**: `shipOrder`(en_transito) — commitSale(ledger suspend→sale) + createMirror(Ventas sale) + sale_credit(shipSaldo>0). entregado 는 deliveredAt 만.
- 공유 헬퍼: `runStatusTx(storeId,id,fromStatuses[],toStatus,sideEffect,isolation?)` — FOR UPDATE 락 + from→to 검증 + 단일 tx(pool 안전) + commit 후 findById 반환. `setStageActor`(감사). despacho 앱은 `/despacho/*`(기기토큰+x-operario) → onlineOrdersService 위임.

## 결정 확정 (2026-07-08, 최종 — P1 모델 기준)
- **1계단씩만 되돌림**.
- 인식이 ship 으로 이동했으므로 **재무 경계는 이제 en_transito↔listo(발송/발송취소)**. entregado↔en_transito 는 재무 무관.
- **entregado→en_transito 되돌리기: 재무 무관** — deliveredAt=null + actor 'shipped'. mirror/재고 무변경(ship 에서 만든 것 유지). ← 사용자 주목적(배송완료 실수정정)이 완전히 깔끔.
- **en_transito→listo 되돌리기(un-ship): 판매확정 역처리 지점**. 완납건만 허용, 외상건 차단.
  - **완납(shipSaldo==0)**: un-commit(ledger sale→suspend, product.stock 무변경) + nullifyMirror(mirrorSaleId=null) + shipSaldo/mirror 흔적 metadata 정리 + paymentStatus 복원. helper 재사용.
  - **외상(shipSaldo>0)**: **차단**(BadRequest) — sale_credit 상쇄 movementType 부재(payment_in/writeoff/adjustment 부적합), cancel 도 미역기입. 억지 역기입 금지 → cancelar 유도.

## 되돌리기 매핑(1계단씩, P1 모델)
| 현재 columnKey | 되돌림 대상 | status 전이 | sideEffect |
|---|---|---|---|
| preparando | nuevo | preparing→confirmed | metadata.preparingAt 제거, actor 'confirmed' · **재무 무관** |
| listo | preparando | preparing→preparing | preparedAt=null, actor 'preparing' · **재무 무관** |
| en_transito (shipSaldo==0) | listo | shipped→preparing | **un-commit**: reverseSale 상당(ledger sale→suspend) — 아래 TASK-1B; nullifyMirror(mirrorSaleId=null); shipped/dispatchedAt=null; shipSaldo·mirror metadata 정리; paymentStatus 복원; actor 'ready' |
| en_transito (shipSaldo>0) | **차단** | — | BadRequest "외상으로 발송된 건은 되돌릴 수 없습니다. 취소(cancelar)를 사용하세요." |
| entregado | en_transito | delivered→shipped | deliveredAt=null; actor 'shipped' · **재무 무관** |
| nuevo | (없음) | — | BadRequest "이미 첫 단계" |
| cerrado/cancelled/returned | (불가) | — | BadRequest |

모든 되돌림은 commit 후 emitCard 로 보드 실시간 반영 + metadata.stageActors.reverted 감사 기록.

## un-ship(en_transito→listo, 완납) — UAT 게이트 (2건)
- **UAT-A(Ventas 음수 sale 노출)**: un-ship 시 원본 mirror NULLIFIED + 음수 역분개 sale 이 Ventas 에 남는다(append-only, 삭제 아님). 수용 여부 확인.
- **UAT-B(받은 돈/cobro)**: 완납이므로 결제금은 mirror 역분개로 상쇄, cobro/caja 이동 무변경(단계 정정이지 취소 아님). 실제 환불 필요 시 cancelar. 확인.

## 재고/product.stock 주의 (P1 모델)
- 어떤 되돌림도 product.stock 순변화 0 이어야 한다(생성 시 1회 차감, 되돌려도 주문은 유효 → 재고 계속 빠진 채). un-ship 의 un-commit = `reverseSale`(sale +qty, product.stock +qty) + `holdStock`(suspend -qty, product.stock -qty) → **product.stock ±qty 상쇄 net 0**, ledger 는 sale +qty / suspend -qty 로 hold 상태 복원. 즉 두 helper 조합이 정답(별도 경로 불필요). ship/commitSale(suspend +qty, sale -qty)의 정확한 역방향.

## 기술 스택
- 백엔드: NestJS + Sequelize + PostgreSQL(runStatusTx 단일 tx 재사용 → pool 안전)
- 웹: Next.js/React (DespachoBoard.tsx), MUI 확인 다이얼로그
- 앱: Flutter (Riverpod, Dio)
- ESLint: ventago-app 은 warning=error (newline-before-return / lines-around-comment 주의)

## 태스크 목록
- [ ] TASK-1: online-orders.service.ts — `revertOrder(storeId,id,userId?,userName?)` 추가 (runStatusTx 재사용, 매핑대로 분기, emitCard)
- [ ] TASK-2: online-orders.controller.ts — `@Patch(':id/revert')` (audit 데코레이터) 추가
- [ ] TASK-3: despacho.controller.ts — `@Patch('orders/:id/revert')` (DespachoDeviceGuard + x-operario) 추가
- [ ] TASK-4: despacho.service.ts — `revert(storeId,id,deviceLabel,operarioName?)` → onlineOrdersService.revertOrder 위임
- [ ] TASK-5: DespachoBoard.tsx — 되돌리기 아이콘 버튼(revertable 컬럼만) + 확인 다이얼로그 + PATCH /online-orders/:id/revert + mutate()
- [ ] TASK-6: despacho-app api_service.dart — `revert(int id)` 추가
- [ ] TASK-7: despacho-app 화면(order_detail/list) — 되돌리기 버튼 + 확인 다이얼로그 + 새로고침
- [ ] TASK-8: ESLint 검증(ventago-app) + flutter analyze(despacho-app) — Mac 위임
- [ ] TASK-9: PostgreSQL pool 점검(runStatusTx 재사용, 신규 connect 없음 확인)

## 완료 기준 (P1 모델)
- **P1 선행 완료**(매출인식=ship) 후 진행.
- 재무 무관 구간(preparando→nuevo / listo→preparando / **entregado→en_transito**) 되돌리기 정상 + 보드/앱 실시간 반영.
- **en_transito→listo(un-ship) 완납건**: un-commit(ledger sale→suspend, product.stock net 0) + nullifyMirror 정상. 외상건 차단. re-ship 왕복 시 정상 재확정(재고 이중차감 0).
- 취소/반품/첫단계 안전 차단. ESLint 0, flutter analyze 0, 신규 DB connect 0.

## 금지사항 / 주의사항
- P1 없이 P2 단독 진행 금지(인식시점 전제).
- 외상원장(credit ledger) 이 phase 무변경 — 외상 un-ship 은 차단으로 회피.
- product.stock 순변화 0 유지(reverseSale+holdStock 상쇄). sale 행 삭제 금지(nullify만).
- 운영 마이그레이션 불필요(스키마 변경 없음, metadata JSON).
- ventago-app lint: return 위 빈 줄 / 주석 위 빈 줄 준수.
