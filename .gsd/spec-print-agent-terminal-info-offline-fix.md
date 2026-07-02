# SPEC: print-agent 접속 시 터미널 정보 기록 + Auto ImpTiq agent_offline 오류 수정
생성일: 2026-07-02

## 목표
1. print-agent 접속(WebSocket 인증 성공) 시 매핑된 터미널 정보를 Winston 로그 파일에 기록한다.
2. Auto ImpTiq 판매 시 에이전트가 실제로 연결돼 있는데도 `agent_offline` 오류가 나는 버그를 수정한다.

## 배경 및 컨텍스트 (원인 분석)

### 로그 확인 결과 (combined-2026-07-02.log)
- error 로그 없음. PrintGateway 접속 로그가 **로그 파일에 전혀 남지 않음** — gateway 가 `console.log` 만 사용해 Winston 파일로 안 감. (→ 목표 1과 직결)

### agent_offline 원인 3가지 (복합)

**원인 A — `/print/temp` 의 online 판정이 "지점의 첫 thermal 행" 고정**
`print.controller.ts` `printTemp()` → `getOrCreateConfig(branchId)` = `findOrCreate({ branchId, agentType:'thermal' })` → **ORDER 없이 첫 행**을 반환.
지점에 thermal 에이전트가 2개 이상이면(로컬 DB branch 1: id=1, id=2) 실제 연결된 에이전트가 아닌 오래된 offline 행을 보고 `agent_offline` 반환.
반면 프론트 체크박스는 `/print/agents/:branchId` 목록에서 **하나라도 online 이면 ON** → 판정 기준 불일치.

**원인 B — 프론트 branchId 해석 순서 불일치**
- 체크박스 상태 조회: `user.branchId || cashRegister.box.branchId` (ProductList.tsx L239)
- 출력 요청 branchId: `cashRegister.box.branchId || ... || user.branchId` (L1085-1089) — **우선순위 반대**
→ 체크박스는 A지점 기준 online, 실제 출력은 B지점으로 전송 가능.

**원인 C — 서버 재시작 후 is_online 스테일**
서버 kill 시 handleDisconnect 미실행 → is_online 이 과거 값 그대로. 로컬 DB agent id=5 는 last_seen 2026-06-25 인데 is_online=true (스테일 true), 반대로 스테일 false 도 발생 가능.

### DB 현재 상태 (로컬 PG18)
| id | branch | label | is_online | last_seen |
|----|--------|-------|-----------|-----------|
| 1 | 1 | Comandera Principal (key ...0153) | false | 06-05 |
| 2 | 1 | Comandera 2 | false | - |
| 5 | 12 | helguera | **true (스테일)** | 06-25 |

※ 스크린샷 에이전트(key ...0153)는 "PB comandera" 라벨 → 로컬 라벨과 다름 = **운영 서버에 접속 중**일 가능성. 코드 수정과 별개로 환경 불일치(에이전트→운영, 판매→로컬) 여부는 사용자 확인 필요.

## 기술 스택
- Node.js (NestJS 11), Sequelize — pool 은 Sequelize 관리 (raw connect/release 없음, update/findAll 단일 쿼리만 사용 → pool 안전)
- ESLint: api-ventago, ventago-app 각각 설정 존재 (`newline-before-return`, `lines-around-comment` 주의)

## 태스크 목록
- [ ] TASK-1: PrintGateway 에 Nest `Logger`(Winston 연동) 도입 — 접속 성공/실패/해제 시 agentId, label, branch, store, **매핑 터미널 목록**을 로그 파일에 기록 — 파일: `api-ventago/src/app/print/print.gateway.ts`
- [ ] TASK-2: `PrintService.hasOnlineThermalAgent(branchId)` 추가 (단일 COUNT SELECT) + `onModuleInit` 스테일 리셋 (단일 UPDATE: is_online=true → false, socket_id=null) — 파일: `api-ventago/src/app/print/print.service.ts`
- [ ] TASK-3: `POST /print/temp` 의 offline 판정을 `hasOnlineThermalAgent` 로 교체 (지점 내 하나라도 online 이면 emit) — 파일: `api-ventago/src/app/print/print.controller.ts`
- [ ] TASK-4: 프론트 branchId 해석 통일 — 출력 payload 도 checkbox 와 동일한 `currentBranchId` 사용 — 파일: `ventago-app/src/views/homes/components/ProductList/ProductList.tsx`
- [ ] TASK-5: ESLint 검증 (api-ventago + ventago-app 수정 파일)
- [ ] TASK-6: PostgreSQL pool 안전 점검 (신규 쿼리 2개: COUNT SELECT, bootstrap UPDATE — 모두 단발 쿼리)

## 완료 기준
- ESLint 오류 0개
- 에이전트 접속 시 combined 로그 파일에 터미널 정보 포함 기록
- 지점 내 online thermal 이 1개라도 있으면 /print/temp 성공
- 서버 재시작 직후 스테일 is_online 제거

## 금지사항 / 주의사항
- branch_agents 스키마 변경(신규 컬럼) 없음 — 마이그레이션 불필요
- pool max=80 설정 변경 금지
- 기존 agent_info emit 구조 유지 (print-agent 앱 호환)
