# Phase 101 — 준비 메모 (2026-10-08)

**사용자 요청 (2026-10-08):** 「고객이 넘겨주는 토큰 값을 가지고 사용자가 허용하는 기능을 접근해서 기술지원을 할 수 있게」
— 매장이 토큰을 만들 때 **어떤 기능을 열어줄지 고르고**, 지원 담당자는 그 토큰으로 **그 기능에만** 들어간다.

결정은 아직 하지 않았다. 아래는 현재 코드와의 대조 + 열린 결정이다.

---

## 1. 이미 있는 장치 — 세 개다 (네 번째를 만들지 말 것)

| 장치 | 무엇을 하나 | 범위 제한 | 실제로 접근을 묶는가 |
|---|---|---|---|
| **Token de soporte** (`support-token/`, 화면 `views/soporte/TokenSoporteView.tsx` · `pages/admin/soporte-remoto.tsx`) | 매장 admin 이 5분짜리 토큰 생성(월 무료 한도) → CoolSistema 직원이 `/support-token/validate` | 없음 | **아니다.** validate 는 `storeId`·매장명을 돌려주고 `used` 로 표시할 뿐이다. 이후 접근은 superadmin 의 **act-as(`X-Store-Id`)** 로 하는데 act-as 는 토큰 유무를 보지 않는다 → 토큰은 지금 **의식(儀式)** 이다 |
| **원격 지원 세션** (`support/`, Phase 41) | 고객이 요청 → UUID 15분 → 지원자가 화면 보기(socket) | 보기 전용 | 세션 단위로 묶임 |
| **에이전트 접근 코드** (`agente/` + `common/tenant/agent-grant.ts`, 테이블 `support_access_grants`) | 매장이 코드 발급 → agent@app 이 `canjear` → 요청마다 `X-Agent-Grant` 로 그 매장 | **scope** 배열(`cert` · `usuarios_terminales` · `legacy`), 만료, 철회, 매 요청 감사 이벤트(실패 시 쓰기 거부) | **그렇다.** 핸들러 메타데이터(`@AgentScope(x)`)가 경계. 표시 없는 핸들러는 403 |

⇒ 요청의 뼈대(「매장이 고른 기능만」)는 **에이전트 접근 코드가 이미 구현하고 있다.** 부족한 것은:
1. **alcance가 3개뿐**이고 핸들러 23개에만 붙어 있다 (cert 6 · legacy 15 · usuarios_terminales 2). 일반 기술지원(상품·가격·재고·판매 조회·카하·설정·프린터…)은 열 수 없다.
2. 사용자가 **agent@app 하나**다 — 사람(지원 담당자)별로 누가 했는지 구분이 안 된다.
3. **Token de soporte 와 접근 코드가 갈라져 있다** — 매장 입장에서 「지원용 코드」가 두 종류. 하나는 아무것도 묶지 않는다.

## 2. 설계 쟁점 (가드·테넌트 규칙에서 나오는 것)

- **경계는 URL 이 아니라 핸들러 메타데이터** (2026-10-02 codex) — 새 alcance도 같은 방식. 화면 메뉴 숨김은 보안 경계가 아니다([[frontend-flag-is-not-a-security-boundary]]).
- **읽기/쓰기 분리**: 같은 기능이라도 「조회만」과 「수정」을 따로 열 수 있어야 하는가. 판매·카하·재고는 돈·원장이라 쓰기는 별도 동의가 자연스럽다.
- **alcance ↔ 권한 함수(functions/role_functions) 매핑**: 이미 화면 권한 체계(역할·기능 슬러그)가 있다. alcance를 새로 나열하지 말고 **기존 기능 슬러그 묶음을 고르게** 하면 단일 출처가 된다 — 단 가드 계약과 맞물리는지 실측 필요([[permission-rows-are-not-power]]).
- **사람 단위 신원**: 담당자 개인 계정 + 매장 grant 인지, agent@app 공용인지.
- **테넌트 격리 절대** — grant 의 storeId 로만. `X-Store-Id` 와 동시 사용 금지(현재 400) 유지.
- **@Public / 크론 / 소켓 경로**는 메타데이터 가드를 안 지난다 — 열어줄 기능 목록에 들어가면 안 된다([[public-routes-disable-tenant-guard]] · [[controller-enumeration-misses-cron-paths]]).
- **감사**: 매 요청 이벤트는 이미 남는다. 매장이 「누가 언제 무엇을 했나」를 보는 화면(Acceso de Ventago 탭)에 alcance·쓰기 여부를 같이 보여줄 것.
- **매장 쪽 UX**: 토큰 생성 시 체크박스로 기능 선택 + 유효시간 + 즉시 철회. 고객이 WhatsApp/전화로 코드를 불러주는 흐름(Phase 100 과 연결).

## 3. Phase 100 과의 관계

Phase 100(AI 고객센터)의 「읽기 전용 진단」은 **이 phase 의 grant 위에서** 돌아야 한다 — 매장이 허용한 범위 밖을 AI 가 조회하면 안 된다. 101 이 100 의 진단 단계보다 먼저다.

## 4. 열린 결정 (discuss-phase)

- **D-1** Token de soporte 를 접근 코드로 통합(구 토큰 폐기)할지, 둘 다 둘지.
- **D-2** alcance의 단위: 새 목록(예: productos · precios · stock · ventas · caja · config · impresoras · usuarios · afip · legacy) vs 기존 기능 슬러그 묶음.
- **D-3** 읽기/쓰기 분리 여부와 기본값(기본 = 읽기만?).
- **D-4** 지원자 신원: 개인 계정별 grant vs agent@app 공용.
- **D-5** 유효시간 기본값·최대값, 동시에 여러 grant 허용 여부.
- **D-6** 매장이 보는 감사 화면의 범위(요청 단위 vs 요약).
- **D-7** 1차 범위: 어떤 기능부터 여는가(가장 자주 오는 Pedidos 유형 기준).
