# 핸드오프 2026-09-28 — Phase 96 Notas · 비밀 nota · 기본 가격 레벨 · 운영 정리

> 앞 문서: `HANDOFF-2026-09-27-c-onboarding-productos-descripcion.md`
> 현재 HEAD: api `ec1e99e6` · app `1a583a81` (전부 push · 빌드 SUCCESS · 컨테이너 재생성 확인)

## 1. 운영에 나간 것

| 내용 | 커밋(최종) | Jenkins |
|---|---|---|
| **Phase 96 Notas** — 사이드바 Herramientas › Notas. 전체/개인 대상, 2칸 Bandeja, Entendido, 반응 5종, 1단 답글, 수정 이력, 보관, 고정, 만료(Vencidas), 사진·PDF 첨부(인증 경로 `/nota-adjuntos/:id`), 검색, 사이드바 배지·토스트(POS 는 배지만) | api `45eff50b` app `b5a2ca52`→`97e20c4d` | api #985 front #839·#840 |
| 계산원에게 「Todos」가 켜져 보이던 것 — 서버가 목록 응답에 `canSendToAll`(notas-enviar-todos/**create**) 을 내려준다 | api `eae27de3` app `14bb268f` | api #986 front #841 |
| **비밀 nota (96-11)** — nota 별 암호(bcrypt), 잠금 해제 증표 HMAC(`x-nota-unlock` 헤더, ≤5분, JWT_SECRET_KEY 파생), 5회 실패 15분 잠금(DB), CODEX 7건 반영 | api `ab04e238` app `75f7cdf3` | api #987 front #842 |
| **Mi perfil** — Sucursales 표·Integraciones(AFIP) 카드 제거 | app `0872695a` | front #842 |
| **Nivel de precio predeterminado** — Configuración › Ventas 카드, `PUT /store-config/:id/default-price-type`(같은 매장·활성만), POS 초기 레벨. 이후 사용자 보고로 3회 수정: 수동 선택 유지(`96d7fcfc`), 검색 목록·스캔도 같은 판정 `levelFor`(`a5caf566`), 카드 「Precio base」 표시(`836fd0e0`), 드롭다운이 첫 카탈로그 상품이 아닌 선택 상품·기본값 기준(`1a583a81`) | api `be264afa` app `1a583a81` | api #989 front #843~#847 |
| 매장 백업 선언 — Notas 8표 EXCLUDED(D-05: 백업은 admin 이 받는다), `store_exchange_rates`·`terminal_printers` 포함, 기준선 재생성, 복원 대상 171→173 | api `4247371b` `ec1e99e6` | api #989 |

사용자 확인: **기본 가격 레벨 「잘 된다」**(2026-09-28). Notas·비밀 nota·Mi perfil 은 브라우저 확인 결과를 아직 못 들음.

## 2. 운영 DB 변경 (전부 승인 후 적용 · 로컬 5432 동일)
- `2026-09-28-a-notas-tablas.sql` — 7표, 복합 FK `(nota_id, store_id)`, 검증은 **정의(pg_get_constraintdef)로**
- `2026-09-28-b-notas-permisos.sql` — module `notas`(herramientas, auxiliary), `ver-notas` 132 · `notas-enviar-todos` 20(admin). 예행(ROLLBACK) 후 적용
- `2026-09-28-c-notas-secretas.sql` — `notas.is_secret/secret_hash` + CHECK(NOT VALID→VALIDATE) + `nota_unlock_attempts`
- `2026-09-28-d-store-config-default-price-type.sql` — `store_configs.default_price_type_id` + FK SET NULL
- 데이터: NOIX Terminal 52 → 에이전트 「caja」(20) 배정, 「caja1」(21) 삭제(사용자 지시)

## 3. 조사만 한 것 (보고함)
- **stock_balances 드리프트** — 0행. DUM-PROD-01 은 원장=잔액(-1). 대신 **분류 칸이 틀림**: 판매 원장이 `type` 없이 음수로 써서(08-10 이후 894행) `total_venta`=0 → 재고 보고서가 「SIN_MOVIMIENTO」·Últ.venta 낡음. 취소 복원(`anulacion sale_id=`)은 ingreso 로 부풀려짐. `production`·`devolucion` 은 어느 칸에도 없음. **미해결 — 사용자 결정 대기**(트리거 분류 수정 + 575행 재계산, 운영 DDL/DML).
- **NOIX 판매 #268 미출력** — 서버는 `targeted:true agentLabel:"caja"` 로 전달(응답 61B), 그 시각 caja 연결 중·Redis 어댑터 정상 → **매장 PC 에이전트/프린터 쪽**. 매장에 테스트 인쇄·재인쇄 요청함(결과 미확인). caja 는 10:33~10:58 7회 재연결 — 불안정.
- **새 매장 권한** — 템플릿이 모든 역할에 모든 function 행을 주되 admin 만 CRUD, 나머지 read. 설계대로. (Notas 「Todos」 표시 결함만 고침)
- **Guía de configuración 안 됨(Charo)** — 서버 요청 0건. 배포 중 로그인한 stale HTML 로 판단, Cmd+Shift+R 요청(결과 미확인).

## 4. 남은 일 / 알려진 위험
- **재고 분류 칸 수정**(§3) — 결정 필요.
- 비밀 nota: 커밋 직후 연결이 끊기면 재시도로 nota/답글 중복 가능 — Idempotency-Key 없음(범위 밖으로 둠).
- Notas `unreadSummary()` 는 2,000건 상한에서 고정 nota 복구 없이 축소(의도적 보류).
- 기본 가격 레벨: 가격 레벨 목록 SWR 캐시 5분 — 그 사이 비활성화된 기본 레벨로 시작할 수 있음(CODEX P2, 미수정).
- 96-10 Task 4(브라우저 7단계 확인) 미완 — `.planning/phases/96-notas-compartidas-del-local/96-10-PLAN.md`.
- `minio.controller.ts` 기존 eslint 오류 9건(이번 phase 와 무관, 원본에도 있음).
- 이전 핸드오프 §2 목업 결정(온보딩, Código Vista 설명 탭 제안)·§4 항목 여전히 열림.

## 5. 교훈
- **실행 서브에이전트는 「Do NOT push」를 무시했다**(96-08 → front #838). CLAUDE.md push 규칙이 이긴다 — 프롬프트에 「오케스트레이터가 대신 집행, push 하면 장애」처럼 **덮는 이유**를 적을 것(메모리 저장).
- 「원래 있던 실패」라며 게이트를 건너뛴 것이 **실은 내가 만든 누락**이었다(Notas 표 백업 미선언). SKIP_VERIFY 사유는 직접 재현해 볼 것.
- `git add A B C` 목록에서 파일 하나가 빠져도 커밋은 된다 — 커밋 후 `git status` 로 남은 M 을 확인(`4247371b` 에 .ts 누락).
- 기본값을 바꿀 수 있게 하면 **「항상 PRECIO 1」에 기대던 곳이 전부 드러난다** — 선택 경로·스캔·검색 표시·드롭다운 목록 네 곳이 각자 판정하고 있었다. 한 함수(`levelFor`)로 모을 것.
- MUI Select 는 값 `''` 를 「선택 없음」으로 그린다 — 센티넬은 비어 있지 않은 문자열로.
- 거절된 도구 호출도 **이미 실행됐을 수 있다** — 다시 하기 전에 파일 상태를 볼 것.
- CODEX 수동 검토는 **파일 1~2개 + 700자 이내 프롬프트**로 쪼개면 돈다. 훅은 시험용 가짜 암호를 비밀로 오탐해 건너뛴다.

## 6. 다음 세션 시작점
1. Notas·비밀 nota·Mi perfil 브라우저 확인 결과 듣기 → 96-10 Task 4 닫고 phase 96 검증(`/gsd-verify-work 96`).
2. 재고 분류 칸(§3) 진행 여부 결정.
3. NOIX 프린터 재인쇄 결과 확인.
