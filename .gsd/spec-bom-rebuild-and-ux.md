# SPEC: BOM 재빌드 + Cut Ticket BOM UX 개선
생성일: 2026-07-03

## 목표
BOM 미등록 상태로 발급된 cut ticket 을 사후 복구할 수 있게 하고,
BOM 등록 경로(Cost Sheet)를 UX 상 cut ticket 앞에 배치한다.

## 배경 및 컨텍스트
- `generateCutTicket` 은 발급 시점에 `buildBomSnapshot` 으로 BOM 을 동결하고
  `consumeMaterialsFromBom` 으로 자재를 차감한다 (STEP-6.5, 같은 tx).
- 활성 BOM 이 없으면 빈 스냅샷으로 발급되고, 재호출은 멱등(기존 반환)이라 소급 반영 불가.
- BomTable 빈 상태 문구가 "Wave 10 에서 확장 예정" — Wave 10 은 이미 완료(2026-04-22), 문구 stale.
- 탭 순서: cut-ticket 이 cost-sheet 앞에 있어 BOM 등록을 건너뛰기 쉬움.

## 기술 스택
- NestJS 11 + Sequelize (managed transaction — pool release 자동, connection 낭비 없음)
- Next.js 13 + MUI 5, SWR (`useCutTicket`)
- ESLint: newline-before-return / lines-around-comment / no-unused-vars 주의

## 태스크 목록 (완료 2026-07-03 — 사용자 추가 요청으로 TASK-5 는 라벨 "Cost Sheet (BOM)" + Lotes 앞 배치로 확장)
- [x] TASK-1: `lote.service.ts` — `rebuildBomSnapshot(loteId, storeId, user)` 추가
  - 가드: cutTicketNumber 필수(400), 기존 bomSnapshot 이 비어있을 때만 허용(400 — 중복 자재 차감 방지)
  - `buildBomSnapshot` 재실행 → 여전히 비면 400 (활성 BOM 없음 안내)
  - `lote.update({ bomSnapshot })` + `consumeMaterialsFromBom` (같은 tx)
  - afterCommit 캐시 무효화 `talleres:cut-ticket:{storeId}:`
  - cutDate 가 있어도 허용 (차감 누락 복구 목적 — CT-2026-001 케이스)
- [ ] TASK-2: `lote.controller.ts` — `POST :id/cut-ticket/rebuild-bom` (admin/superadmin/gerente)
- [ ] TASK-3: `BomTable.tsx` — 빈 상태 문구 교체 + "Recargar BOM" 버튼 (optional props: loteId, onRebuilt)
- [ ] TASK-4: `CutTicketTab.tsx` — BomTable 에 loteId/onRebuilt(mutate) 전달
- [ ] TASK-5: `constants.ts` — TALLERES_TABS 순서: cost-sheet 를 cut-ticket 앞으로
- [ ] TASK-6: ESLint 검증 (사용자 Mac 전달 필요 시 명령 제공)

## 완료 기준
- ESLint 오류 0개
- BOM 없는 발급 티켓에서 버튼 클릭 → Cost Sheet 에 등록된 BOM 이 스냅샷+자재차감 반영
- 이미 BOM 스냅샷이 있는 티켓에서 재빌드 호출 시 400 (중복 차감 없음)

## 금지사항 / 주의사항
- generateCutTicket 기존 로직/멱등성 변경 금지
- pool: Sequelize managed tx 만 사용 (수동 connection 금지)
- 기존 bomSnapshot 이 비어있지 않으면 절대 재차감하지 않는다
