# PEDIDO #7 — 「cambios de comandos」

| 항목 | 내용 |
|---|---|
| 매장 · 지점 | NOIX (store 19) · NOIX |
| 요청자 · 일시 | SAMUEL CHON · 2026-10-05 09:39 (AR) |
| 분류 | **개선** (POS 단축키 재배치) — 기능 결함은 아님 |
| 접수 답장 | 자동 발송됨 |

## 요청 원문
1. «sacar el f7 como ticket sin precio, no lo necesito y cambiarlo de nuevo a selección de vendedores»
   → F7 의 「가격 없는 티켓」을 빼고, **다시** 판매원 선택으로 되돌려 달라.
2. «agregar el f8 como para sacar ticket temporal»
   → F8 로 「임시 티켓」을 뽑게 해 달라.

## 현재 동작 (코드 근거)

| 키 | 지금 하는 일 | 근거 |
|---|---|---|
| **F6** | Imprimir Temp — 카트 내용으로 임시 티켓 출력(판매 생성 안 함) | `ProductList.tsx:2890-2894` → `sendTempTicket(false)` · `shortcuts.ts:82` |
| **F7** | Temp s/ precio — 같은 임시 티켓을 **가격 없이** | `ProductList.tsx:2896-2900` → `sendTempTicket(true)` · `shortcuts.ts:83` · 버튼 `ProductList.tsx:3299` |
| **F8** | 「Vendedor」 입력칸으로 포커스 | `ProductList.tsx:2603-2610` · `shortcuts.ts:50` · 입력칸 placeholder `InfoClient.tsx:1001, 1096` |

- 임시 티켓의 실체: print-agent 가 맨 위에 **「PRESUPUESTO TEMPORAL」** 배너를 찍는다
  (`print-agent/src/formatter.js:1187`, `ticketType: 'temp'`). `hidePrices=true` 면 단가·합계를 뺀다(`formatter.js:930-960`).
- 매뉴얼(`api-ventago/manuales/manual_ventas.md:136, 158-159`)과 F1 목록(`shortcuts.ts`)이 위 표와 같다.
  `__tests__/pos-shortcuts-sync.spec.ts` 가 코드↔F1 목록↔매뉴얼 세 곳 일치를 강제한다.

## F7 이 언제·왜 바뀌었나
- **2026-10-01** 두 커밋으로 바뀌었다 (ventago-app):
  - `e5621413` 17:59 «F6 = Imprimir Temp (F7 sigue siendo Vendedor)»
  - `4a2fc2f5` 18:07 «F7 = Temp s/ precio; «Vendedor» pasa a F8 — F6·F7 quedan juntos para los tickets provisorios»
- 이유: 코드 주석 `ProductList.tsx:2604` 「F6·F7 을 나란히 인쇄용으로 쓴다(**사용자 결정**)」,
  `HANDOFF-2026-10-01.md:23`. **다른 매장의 요청이 아니었다** — `support_requests` 전체(운영, 2026-10-05 조회)에
  F6/F7 인쇄를 요청한 항목은 없다. 내부(사장님) 결정으로 넣은 배치다.
- NOIX 는 이 변경을 통보받지 못한 것으로 보인다: 이틀 뒤 들어온 **PEDIDO #3 항목 9**(2026-10-03 01:52 UTC)가
  여전히 «**f7** sale lista de vendedores, se tiene que poder buscar…» 라고 썼다. 그 항목은 `69f3d135`(10-03)에서
  판매원 검색으로 해결했지만 **키는 F8 인 채로** 닫혔다. 매장 손에는 「F7 = 판매원」이 익어 있다.

## 매장별인가, 전역인가
- **전역이다.** 단축키는 `useHotkeys(...)` 상수(`ProductList.tsx`)와 정적 목록(`shortcuts.ts`)뿐이고
  `store_configs` 나 api 에 단축키 설정은 없다(`api-ventago/src` 에 hotkey/atajo 설정 0건).
  → NOIX 를 위해 바꾸면 **모든 매장의 POS 가 같이 바뀐다.**
- 다른 매장 영향은 작다(운영 실측, 최근 7일 판매): NOIX 외에 실사용 판매는 coolsistema 19 · ACE 7 · Cielo 2 · Charo 1.
  (Shaple 128,841건·NOIX 10-04 14,650건은 레거시 임포트 뭉치 — 분 단위 1~10개로 몰려 있음.)
  F6/F7 배치 자체가 10-01 에 생긴 지 4일이라 다른 매장에 굳은 습관도 없다.

## 「ticket temporal」 은 무엇인가 — 후보

| 후보 | 지금 있는가 | 근거 | 가능성 |
|---|---|---|---|
| **A. Imprimir Temp (현 F6)** — 판매 생성 없이 카트를 「PRESUPUESTO TEMPORAL」 티켓으로 출력 | 있음 | `sendTempTicket(false)` · `formatter.js:1187` · 버튼 「Imprimir Temp (F6)」 | **가장 높음** — 이름(Temp)·배너(TEMPORAL)가 그대로 맞는다. 매장이 F6 이 있는 걸 모르는 듯 |
| B. Suspender (Ctrl+S) — 판매 보류 | 있음 | `ProductList.tsx:1599 handleSuspend`, 출력 없음 | 낮음 — 종이가 안 나온다 |
| C. 독립 견적서(번호·유효기간·판매 전환) | **없음** | `ANALISIS-2026-09-17-legacy-vcontrolgrid2-격차분석.md:42` (레거시 F5 «Sacar Presupuesto») | 중간 — 레거시 습관일 수 있음. 그렇다면 신규 기능(L) |
| D. Alt+T 마지막 판매 재인쇄 | 있음 | `ProductList.tsx:2695` | 낮음 — 「temporal」 이 아님 |
| E. Tab = 임시 고객 번호 | 있음 | `shortcuts.ts:51` | 낮음 — 티켓이 아님 |

→ **권고 해석: A(현 F6 의 Imprimir Temp 를 F8 에서도).** 단, **매장 확인 필요**(아래 질문).

## 제안

### 권고안 1 — F7 = Vendedor 복귀 · F8 = Imprimir Temp · F6 유지(같은 기능)
| 키 | 변경 후 |
|---|---|
| F6 | Imprimir Temp (그대로 — 10-01 결정 보존, 이미 익힌 사람이 있어도 안 깨짐) |
| **F7** | **Vendedor** 칸으로 포커스 (10-01 이전으로 복귀) |
| **F8** | **Imprimir Temp** (F6 과 같은 `sendTempTicket(false)`) |
| Temp s/ precio | **단축키만 제거, 버튼은 남김** — 다른 매장이 쓸 수 있는 기능(Phase 73-17)이고 버튼은 해가 없다 |

작업 내용(app 만):
1. `ProductList.tsx` — `useHotkeys('f7')` 를 Vendedor 포커스로, `useHotkeys('f6,f8')` 로 Imprimir Temp.
   **둘 다 `if (event.repeat) return;` 추가** — 지금 F6/F7 에 없다(Alt+T 만 있음, `ProductList.tsx:2700`).
   키를 누르고 있으면 임시 티켓이 여러 장 나온다 → [중복 인쇄 금지] 상시 지시에 걸린다. 이번에 같이 막는다.
2. `shortcuts.ts` — F1 목록: Cliente 「F7 — Ir al campo «Vendedor»」, Factura y ticket 「F8 / F6 — Imprimir Temp」, F7 Temp s/ precio 줄 삭제.
3. `InfoClient.tsx:1001, 1096` placeholder 「Vendedor (F7)」 · `ProductList.tsx:3280-3300` 버튼 라벨 「Imprimir Temp (F8)」·「Temp s/ precio」(키 표기 제거).
4. 매뉴얼 `manual_ventas.md:136, 158-159` (api 저장소 — 문서만) + `pos-shortcuts-sync.spec.ts:146` 주석 · `InvoiceAditional.tsx:95-96` 낡은 주석 정리.
5. Novedades(Alt+F1)에 「Atajos: F7 = Vendedor, F8 = Imprimir Temp」 한 줄 — 단축키는 알려 주지 않으면 없는 것이다(`shortcuts.ts:3-5`).

### 대안 B — F6 를 비우고 F8 로만
F6 을 해제. 키가 하나 줄어 단순하지만, 10-01 이후 F6 을 익힌 사람(있다면)이 조용히 안 된다. 이득이 작아 비권고.

### 대안 C — 매장별 단축키 설정
`store_configs` 에 키맵을 두고 매장마다 다르게. 지금 실사용 매장이 사실상 NOIX 하나라 과한 범위(L). 다른 매장이
다른 배치를 요구하면 그때 검토.

## 범위 밖
- 「ticket temporal」 이 **C(번호 있는 독립 견적서)** 로 확인되면 → 별도 신규 기능 pedido 로 분리(L).
- PEDIDO #3 항목 3 「ctrl+f12 para imprimir solo factura y que no sea el 100%」 — 미완, 이 건과 무관(별도 처리).
- Temp s/ precio 버튼 자체 숨김(매장별 설정 필요) — 요청은 「필요 없다」 일 뿐 해가 없으므로 손대지 않는다.

## 영향
| 축 | 내용 |
|---|---|
| api | **없음** (매뉴얼 md 수정만 — AI 지식 문서이므로 api 배포에 실림) |
| app | `ProductList.tsx` · `shortcuts.ts` · `InfoClient.tsx` · 주석 2곳 · spec 주석 |
| DB 마이그레이션 | 없음 |
| 다른 매장 | 전역 변경. 실사용이 미미하고 10-01 배치가 4일짜리라 영향 작음. Novedades 로 공지 |
| 위험 | ① F8 은 지금 「Vendedor」 — 10-01 이후 F8 로 판매원을 고르던 사람이 누르면 **임시 티켓이 나간다**(판매·재고 영향 없음, 종이 1장). 매장 확인 후 배포로 완화 ② 인쇄 경로 자체는 기존 `/print/temp` 그대로(새 경로 없음) — 중복 방지는 repeat 가드로 오히려 강화 ③ 매뉴얼·F1·코드 불일치는 sync spec 이 잡는다 |

## 규모
**S** — 앱 파일 3개 + 문서. 질문 답이 A 로 오면 반나절 이내.

## 검증 방법
1. `pos-shortcuts-sync.spec.ts` 통과(코드↔F1↔매뉴얼) + **대조군**: F1 목록에서 F8 줄을 빼면 실패하는지.
2. 운영 빌드에서 cmux 로 키 검증 — `cmux press` 는 조합키를 못 보내므로 SKU 입력칸에서
   `KeyboardEvent('keydown',{key:'F7',code:'F7'})` dispatch → `document.activeElement.id === 'input-vendedor'`.
   F8 dispatch → `/print/temp` 요청 1건(네트워크 로그). `repeat:true` 로 다시 보내 **요청 0건 추가** 확인.
3. F7 로 Temp s/ precio 가 **안** 나가는지(요청 0건), 버튼 클릭은 여전히 `hidePrices:true` 로 나가는지.
4. NOIX 매장에서 F8 → 「PRESUPUESTO TEMPORAL」 티켓 실물 1장 확인(매장 협조).

## 매장에 확인할 질문 (스페인어)
1. Con «ticket temporal», ¿te referís al ticket que hoy sale con **F6 / botón «Imprimir Temp»**
   (arriba dice «PRESUPUESTO TEMPORAL», con precios y total, y **no** genera la venta)?
2. ¿O necesitás otra cosa — por ejemplo un presupuesto con **número y fecha de validez** que después se pueda
   convertir en venta, o dejar la venta **suspendida** (Ctrl+S) e imprimir algo?
3. ¿Está bien que F6 siga haciendo lo mismo que F8, o preferís que F6 no haga nada?

## 답장 초안 (스페인어 — 미발송)
> ¡Hola Samuel! Gracias por el pedido.
>
> Te contamos cómo lo vamos a dejar:
> - **F7** vuelve a ser **Vendedor** (va directo al campo para buscar el vendedor tipeando).
> - **F8** va a imprimir el **ticket temporal**: el mismo que hoy sale con el botón «Imprimir Temp»
>   (dice «PRESUPUESTO TEMPORAL», lleva precios y total, y **no** genera la venta).
> - El ticket **sin precio** deja de tener atajo; si algún día lo necesitás, queda el botón «Temp s/ precio».
>
> Antes de hacerlo, confirmanos una cosa: ¿el «ticket temporal» que necesitás es ese de «Imprimir Temp»?
> Si es otra cosa (por ejemplo un presupuesto con número para después convertirlo en venta), contanos y lo vemos.
>
> ¡Saludos!

---
## 사용자 확인 (2026-10-05)
- 「단축키들은 공용이지.」 — POS 단축키는 **의도적으로 전 매장 공통**이다. 매장별 설정을 만들지 않는다.
  이 요청을 반영하면 모든 매장의 F7·F8 이 함께 바뀌며, 그것이 정상이다(매뉴얼·안내도 전 매장 기준).
- **실행 중 키맵 변경 (2026-10-05, 작업 도중)**: 사용자가 권고안 1(F8=Imprimir Temp)을 뒤집고
  다음으로 확정 — 「F6 = Imprimir ticket temporal(그대로, 유일한 임시 티켓 키) · F7 = 판매원 선택
  (그대로 복귀) · F8 = ticket SIN PRECIO(오늘 F7 이 하던 일)」. 아래 구현 결과는 **이 최종 키맵** 기준이다.

## 구현 결과 (2026-10-05)

### 최종 키맵
| 키 | 동작 | 비고 |
|---|---|---|
| **F6** | Imprimir Temp (`sendTempTicket(false)`) | 변경 없음 |
| **F7** | Vendedor 입력칸 포커스 | 2026-10-01 이전으로 복귀(옛 F8) |
| **F8** | Temp s/ precio (`sendTempTicket(true)`) | 옛 F7 |

F6·F8 모두 `event.repeat` 가드 추가(누르고 있어도 티켓 1장만 — [중복 인쇄 금지] 상시 지시).
Temp s/ precio 버튼은 계속 존재, 라벨만 「(F8)」로 갱신.

### 변경 파일
**ventago-app** (커밋 `f0be7c7a`):
- `src/views/homes/components/ProductList/ProductList.tsx` — `useHotkeys('f7', …)` → Vendedor,
  `useHotkeys('f6', …)`/`useHotkeys('f8', …)` 분리 호출 + `event.repeat` 가드, 버튼 라벨, 관련 주석 5곳 정리
- `src/views/homes/utils/shortcuts.ts` — F1 도움말 단일 출처 갱신(F7=Vendedor, F8=Temp s/ precio)
- `src/views/homes/utils/pos-hotkey-actions.ts` **(신규)** — F6/F7/F8 키→액션 순수 테이블(단일 출처),
  `shortcuts.ts` 의 `declaredHotkeys()` 와 대조
- `src/__tests__/pos-hotkey-actions.spec.ts` **(신규)** — F7=vendedor · F8=ticket-temporal-sin-precio ·
  F6=ticket-temporal, 키 중복 없음, 도움말 목록과의 교차 검증. 돌연변이 시험(F8 액션을 고의로 틀리게
  바꿔 실패 확인 → 원복, 커밋 전)
- `src/__tests__/pos-shortcuts-sync.spec.ts` — 주석 갱신(코드 변경 없음, 기존 가드가 그대로 통과)
- `src/views/homes/components/InfoClient.tsx` — placeholder 「Vendedor (F8)」→「Vendedor (F7)」 2곳
- `src/views/homes/components/SellerPicker.tsx` — 낡은 F8 주석 정리
- `src/views/homes/utils/seller-search.ts` — 낡은 F8 주석 정리
- `src/views/homes/components/ProductList/components/InvoiceAditional.tsx` — 낡은 단축키 배치 요약 주석 전체 갱신
- `src/configs/novedades.ts` — Alt+F1 공지 1건 추가(대상: cajero + encargados)

**api-ventago** (커밋 `fd367cee`):
- `manuales/manual_ventas.md` §11 — F7/F8 행 갱신(AI 지식 문서, api 배포에 실림)

**루트 포인터**: `8c4bcb3`(app) · `e9076ce`(api)

### 검증
- `unset NODE_OPTIONS; npx tsc --noEmit -p tsconfig.json` — exit 0
- `npx eslint <변경 파일 9개>` — exit 0, 0 errors / 6 warnings(기존 exhaustive-deps, 이번 변경과 무관)
- jest(`pos-hotkey-actions.spec.ts` · `pos-shortcuts-sync.spec.ts` · `novedades.spec.ts`) — 23/23 통과
- 돌연변이: `pos-hotkey-actions.ts` 의 F8 액션을 `'vendedor'` 로 바꿔 재실행 → 의도대로 1건 실패
  (`F8 = ticket temporal sin precio`), 원복 후 재확인 통과
- **브라우저 시각 검증은 하지 않았다** — :3050 에 기존 dev 서버가 떠 있어 `next build` 생략,
  로그인·카트·카하 오픈이 필요한 E2E 흐름까지는 이번 범위/시간에서 하지 않음

### 배포
- 운영 활성 사용자(최근 15분, push 직전 측정): **0명** → 즉시 push 진행(시각 10:12 ART, 주간이지만
  ≤5명 규칙 충족)
- ventago-app push → Jenkins `front-coolsistema` 빌드 **#968 SUCCESS** (SHA `f0be7c7a` 확인)
- api-ventago push → Jenkins `api-new-coolsistema` 빌드 **#1081 SUCCESS** (SHA `fd367cee` 확인)
- 컨테이너 재생성 확인: `ventagoapp` Up 26s · `api_ventago` Up 2m (healthy)
- 매장 답장·완료 처리는 하지 않음(오케스트레이터가 사용자에게 먼저 확인)
