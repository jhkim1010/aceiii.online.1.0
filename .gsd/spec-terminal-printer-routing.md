# SPEC: 터미널별 프린터(comandera) 라우팅
생성일: 2026-07-02

## 목표
판매 티켓(/print/temp)이 지점 broadcast 가 아니라 **판매 터미널에 매핑된 thermal 에이전트로만** 출력되도록 한다.
예: 터미널 A,B → 프린터1, C → 프린터2 (지점 내 다중 comandera 중복 출력 제거).

## 배경
- 스키마/UI 는 이미 존재: `terminals.thermal_agent_id` FK + Impresora 관리 페이지 매핑 UI (Phase 13)
- 그러나 `/print/temp` 는 `branch:{branchId}` room broadcast → 지점 내 모든 online 에이전트가 동일 티켓 출력
- `cashRegister.terminalId` 가 `/cash-register/open` 응답에 포함되어 프론트에서 사용 가능
- barcode/QR 은 이미 agentId 타겟 emit 패턴 구현되어 있음 (참조 패턴)

## 태스크 목록
- [x] TASK-1: `PrintService.getTerminalThermalAgent(terminalId)` — Terminal→thermalAgent 단일 SELECT(include). `emitPrintTemp` 에 socketId 타겟 옵션 추가 — 파일: `print.service.ts`
- [x] TASK-2: `POST /print/temp` — body.terminalId 있고 매핑 존재 시: 해당 에이전트 isOnline/socketId 로 판정 + 타겟 emit. 매핑 없으면 기존 지점 단위 fallback — 파일: `print.controller.ts`
- [x] TASK-3: 프론트 두 출력 경로(payload)에 `terminalId: cashRegister?.terminalId` 추가 — 파일: `ProductList.tsx`
- [x] TASK-4: ESLint 검증 (양쪽) — 오류 0개

## 완료 기준
- 매핑된 터미널의 판매는 해당 에이전트에서만 출력
- 매핑 안 된 터미널/구버전 호출(EnvioTimeline 등)은 기존 동작(지점 broadcast) 유지
- ESLint 0개, 신규 쿼리는 단일 SELECT 1개 (pool 안전)

## 금지사항
- DB 스키마 변경 없음, print-agent 앱 수정 없음 (socketId 타겟 emit 은 서버측만으로 동작)
