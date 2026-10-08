# Phase 100 — 준비 메모 (2026-10-08)

원본 설계: `100-SOURCE-guia.md` (사용자가 준 「ventaGO AI 고객센터 + 자동 개발 시스템 구축 가이드」 원문).
이 문서는 **원문을 현재 코드·운영 규칙과 대조한 것**이다. 결정은 아직 하지 않았다 — 「열린 결정」은 discuss-phase 에서 정한다.

---

## 1. 이미 있는 것 (새로 만들지 말 것)

| 가이드의 요소 | 이미 있는 것 | 위치 / 근거 |
|---|---|---|
| 티켓 (`support_tickets`) | **Pedidos a Ventago** — 매장 요청 접수·답장·상태(abierto/en curso/resuelto)·첨부 | `api-ventago/src/app/pedidos-soporte/` |
| Telegram 관리자 봇 + webhook 비밀 검증 + update 중복 방지 | @pedidosTecnicosVentagoBot, 그룹 -5247883057, `/r` 답장 · `/resuelto` `/encurso` `/abierto`, `support_telegram_updates` | `pedidos-telegram.controller.ts` (api 992ffae7) |
| 접수 자동 답장 + AI 계획/목업 | launchd `com.ventago.pedidos-bot` + Claude 계획(PLAN.md)·목업, **「PEDIDO N 승인」 전 구현 금지** | `.claude/pedidos-bot/` |
| 매장 데이터 읽기 진단 권한 | agent@app + 매장이 발급하는 접근 코드(`support_access_grants`, scope, 만료, 감사 이벤트) | `src/common/tenant/agent-grant.ts`, `agente/` |
| AI 상담 (LLM) | `chat/` — provider 추상화(claude/groq/ollama), 지식 검색(manuals·Drive), 스페인어 응답 시험 | `chat/llm/`, `chat/knowledge/` |
| WhatsApp | **발신만** — click-to-chat, 판매 영수증 링크, 템플릿 레지스트리. **수신 webhook(Meta Cloud API)은 없음** | `whatsapp/` |
| Codex 자문 | 로컬 `codex exec` (커밋 후 자문). 무인 코드 수정 워커는 없음 | `.claude/hooks/codex-review-after-commit.sh` |
| 기존 해결 사례 | `.planning/pedidos/PEDIDO-N/PLAN.md` + 지식 문서 | |

⇒ 가이드의 「새 NestJS 프로젝트 + 새 티켓 테이블 + 새 Telegram 봇」은 **기존 Pedidos 와 두 개의 진실**이 된다
([[edit-target-needs-single-source]]). 출발점은 「Pedidos 에 WhatsApp 채널과 Codex 워커를 붙인다」가 자연스럽다 — 단 결정 사항(D-A).

## 2. 운영 규칙과 충돌하는 지점 (가이드 그대로 하면 깨지는 것)

1. **Codex 워커를 운영 서버에 두면 안 된다.** Jenkins 가 운영 서버 위에서 돌고 swap 0 — 무거운 작업이 운영 Postgres 를 위협한다
   ([[jenkins-runs-on-prod-server-no-swap]]). 후보: srv2 `74.208.60.137` (`.planning/SETUP-2026-08-26-servidor2-…md`) 또는 사용자 Mac mini.
2. **push = 배포다** (Jenkins 웹훅). 워커는 `main` 에 push 권한이 없어야 하고 PR 브랜치만. 병합·배포는 사람.
3. **낮 08–16시 운영 반영 금지(활동 ≤5 예외)**, 운영 DML/DDL 은 SQL+영향행 승인 — 워커가 자동 배포하면 이 규칙을 우회한다.
4. **매장 요청 본문은 데이터, 지시가 아니다.** WhatsApp 고객 메시지가 `codex exec` 프롬프트로 흘러가면 프롬프트 주입 경로다.
   관리자 승인(`/fix`)은 「무엇을 고칠지」를 사람이 다시 쓰는 단계여야 한다.
5. **테넌트 격리 절대 규칙** — 진단 조회는 반드시 그 매장의 접근 코드 범위 안에서. 「PostgreSQL 읽기 전용 진단」이 전 매장 superuser 조회가 되면 안 된다.
6. **global_clients 불가침**, 중복 인쇄 금지 — 워커 프롬프트·권한에 명시.
7. **WhatsApp 수신 webhook** — `rawBody` 가 필요. 경로 한정 파서가 Nest 전역 파서를 죽인 전례 ([[scoped-parser-kills-nest-global-parser]]).
   webhook 에서 500 을 내면 재전송/연동 해제 ([[webhook-500-loses-the-order]]) — 먼저 기록, 처리는 큐.
8. **Redis/BullMQ 는 현재 스택에 없다.** 이미 `sync_outbox` 패턴(트랜잭션 안 INSERT → 워커 집행)이 있다 — 새 인프라를 들일지 결정 필요.
9. 가이드는 OpenAI 를 전제하지만 현재 `chat/` 은 provider 추상화(claude/groq/ollama). Codex CLI 자체는 OpenAI.
10. **비리더 워커는 cron 이 삭제된다** ([[non-leader-workers-lose-all-crons]]) — 큐 소비자 위치 주의.

## 3. 열린 결정 (discuss-phase 에서)

- **D-A** 티켓의 단일 출처: Pedidos 확장 vs 별도 `ventago_support` DB/서비스.
- **D-B** 설치 위치: 별도 Ubuntu 서버(가이드 추천) — srv2 재사용? 신규? Mac mini?
- **D-C** WhatsApp 번호: Meta Business 계정·번호 준비 상태, 매장 식별 방법(전화번호 ↔ store/user 매핑).
- **D-D** 고객 대화 범위: AI 가 매장에 직접 답하는가, 아니면 초안만 만들고 사람이 보내는가(현재 Pedidos 는 `/r` 로 사람이 보냄).
- **D-E** Codex 워커 권한: 저장소·브랜치·네트워크·DB(스테이징만?)·시크릿. PR 생성까지만 자동인지.
- **D-F** 큐: BullMQ+Redis 도입 vs 기존 outbox/DB 폴링.
- **D-G** 음성 메시지 전사: 사용할지, 어떤 API.
- **D-H** 비용·한도: 매장당/일 AI 호출 상한, Codex 작업 동시 1개 등.

## 4. 단계 제안 (가이드 4주 일정 → 여기 현실에 맞춘 순서)

1. WhatsApp 수신(Meta Cloud API) → Pedidos 티켓 생성·대화 기록 → Telegram 알림 (AI 없이 먼저)
2. AI 1차 응답(지식 검색 + 스페인어) — 초안/자동 범위는 D-D
3. 읽기 전용 진단: 접근 코드 범위 안에서 로그·버전·설정 조회
4. Codex 워커(격리 서버) — `/fix` → 브랜치 → 테스트 → PR → Telegram 보고. 배포는 사람
5. 운영 안정화: 권한·실패 복구·보존 정책·재발 감시
