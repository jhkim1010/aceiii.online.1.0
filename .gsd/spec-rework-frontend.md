# SPEC: Rework (Wave 11) — 프론트 UI 전체 + envio 훅 연결

생성일: 2026-04-23
연속 세션 (범위 C 후반부)

## 목표

백엔드가 이미 완비된 Rework 기능을 사용자가 실제로 쓸 수 있게 프론트엔드 전체 구현.
- 불량 발견 시 Envíos 화면에서 "Rework" 버튼으로 재작업 지시
- CT 상세 화면에 활성 rework 표시
- Talleres 메뉴에 Reworks 전용 탭
- Recepción 생성으로 envio 상태 전환 시 ReworkOrder 상태 자동 동기화

## 범위

### 백엔드 보강 (1개 파일)
- `recepcion.service.ts`: envio 상태를 PARTIAL/COMPLETED 로 업데이트하는 지점에서 `reworkOrderService.syncStatusFromEnvio()` 호출 (envio 가 rework 로 생긴 경우만 영향)

### 프론트엔드 신규 (4개 파일) + 수정 (3개 파일)
1. `hooks/api/useReworkOrders.ts` — SWR 훅 (loteId 또는 status 필터)
2. `views/talleres/rework/ReworkDialog.tsx` — 생성 다이얼로그 (source envio 기준 target etapa/vendor/qty/defect)
3. `views/talleres/rework/RewokChip.tsx` — status 뱃지 (PENDING/IN_PROGRESS/COMPLETED/CANCELLED)
4. `views/talleres/tabs/ReworksTab.tsx` — 매장 전체 rework 목록 탭
5. `views/talleres/envios/talleres_EnviosListView.tsx` — "↻ Rework" 버튼 추가 (envio 행 액션)
6. `views/talleres/cut-ticket/components/RoutingFlow.tsx` — 하단에 "Rework activo" 섹션 (loteId 기준)
7. `views/talleres/components/constants.ts` + `TalleresMainView.tsx` — Reworks 탭 추가

## 기술적 결정

### ReworkDialog 입력 모델
```ts
{
  loteId: number (필수, env에서 주입)
  sourceEnvioId: number (필수, 버튼 클릭한 envio에서 주입)
  targetEtapaId: number (필수, routing에서 선택)
  targetVendorId: number | null (선택, 기존 vendor 목록에서)
  quantity: number (필수, sourceEnvio.rejectedQty 기본값)
  defectCodeId?: number | null
  reason?: string
}
```

### Trigger Points
- Envíos 리스트 행 액션에 "↻ Rework" 버튼 (rejectedQuantity > 0 아니어도 수동 생성 가능)
- 현재 RecepcionDialog 제출 성공 후 response.rejectedQuantity > 0 이면 자동으로 ReworkDialog 팝업 (UX 개선)

### routing 에서 target etapa 후보
- `cutTicket.routing` 전체가 후보. 단 해당 etapa 의 `vendorName` 도 기본값 힌트
- 보통 바로 직전 공정 (source envio 의 etapaId) 이 기본 선택값

### 상태 동기화
- envio.status 가 변하는 지점은 오직 `recepcion.service.ts:createRecepcion` (wave 6 이후 다른 흐름 없음)
- 여기서 `envio.update({ status })` 직후 `ReworkOrderService.syncStatusFromEnvio(envio.id, envio.status)` 호출
- 순환 의존 방지: ReworkOrderService 는 이미 subcon.module 안에 있으니 constructor 주입으로 해결

## 태스크

- [ ] TASK-35: SPEC (현재 문서)
- [ ] TASK-36: useReworkOrders SWR 훅
- [ ] TASK-37: recepcion.service 에서 ReworkOrderService 주입 + syncStatusFromEnvio 호출
- [ ] TASK-38: ReworkDialog + RewokChip 컴포넌트
- [ ] TASK-39: Envíos 리스트에 Rework 버튼 통합 (자동 팝업 포함)
- [ ] TASK-40: RoutingFlow 에 Rework activo 섹션
- [ ] TASK-41: ReworksTab + 탭 등록
- [ ] TASK-42: ESLint + 리뷰

## 완료 기준

- [ ] Envíos 리스트의 행에서 ↻ 버튼으로 ReworkDialog 오픈
- [ ] Recepcion 제출 후 rejectedQty > 0 이면 자동으로 ReworkDialog 팝업
- [ ] target etapa/vendor/quantity/defect 입력 후 저장 시 POST /talleres/rework-orders 호출
- [ ] 성공 toast + 관련 SWR 키 mutate (envios, cut-ticket, reworks)
- [ ] RoutingFlow 하단에 active reworks 목록 (vendor·etapa·qty·상태)
- [ ] Reworks 탭에서 매장 전체 rework 목록 조회 + 상태 필터 + 취소 버튼
- [ ] envio 상태가 COMPLETED 되면 연결된 ReworkOrder 도 자동 COMPLETED
- [ ] ESLint 0 에러

## 주의

- 이 세션에서는 In-house (vendorId=null) rework 는 backend 가 envio 를 만들지 않고 ReworkOrder 만 기록. UI 에서 "In-house" 선택 시 경고 표시
- CLAUDE.md pagination 50 제한 준수
- 스페인어 사용자 메시지
