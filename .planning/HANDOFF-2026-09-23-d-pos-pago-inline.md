# 핸드오프 2026-09-23 (밤) — POS 하단 재설계 · Phase 93 0단계 4/5

다음 세션은 **§1(잔금 자동 이월)** 부터. 규칙은 확정됐고 구현만 남았다.

---

## 1. ★ 다음 작업 — 잔금을 다음 줄로 자동 이월 (사용자 지시, 미착수)

> 「총금액이 20000원인데 내가 현금을 10000원으로 하면 나머지 금액은 자동으로 은행으로
>  가게 해줘. 그리고 은행을 0으로 하면 잔금을 4번째 줄 mercado pago로 채워주고..」

### 확정된 규칙 (사용자가 1번 선택)

> **어떤 줄을 고치면, 잔금은 「그 아래 **쓸 수 있는** 첫 줄」로 자동으로 들어간다.**
> **쓸 수 없는 줄은 건너뛴다.**

「쓸 수 없다」의 판정은 **새로 만들지 말 것** — 이미 있다:
`src/views/homes/utils/pago-rapido.ts` 의 `pagoRapidoCredito/Banco/Efectivo` 가
`aplicar | elegir | bloqueado` 를 돌려준다. 예: 고객을 안 고르면 **Crédito 는 bloqueado**.

⤷ 그래서 기본 순서(1 Efectivo · 2 Crédito · 3 Banco · 4 MercadoPago)에서
  고객이 없으면 Efectivo 편집 → 잔금은 Crédito 를 건너뛰고 **Banco** 로 간다.
  사용자가 든 두 예가 이 규칙 하나로 모두 맞는다.

### 손대기 전에

- 이월 로직은 **`src/views/homes/utils/pago-inline.ts` 에 순수 함수로** 넣는다.
  거기 이미 `ponerMontoEnLista` 가 있고 시험이 붙어 있다(`src/__tests__/pago-inline.spec.ts`).
  컴포넌트 안에 두면 POS 절반을 띄우지 않고는 시험할 수 없다.
- 시험에 **반드시** 넣을 것: 이월이 **총액을 넘지 않는다** · 잔금이 음수면(초과결제)
  이월하지 않는다 · 쓸 수 있는 줄이 없으면 **아무 데도 안 넣는다**(조용히 마지막 줄에
  밀어넣지 말 것) · 대조군으로 「정상 이월이 실제로 일어난다」.
- ★ 이월이 **사용자가 방금 고친 줄을 다시 건드리면 안 된다** — 무한 루프가 된다.

---

## 2. 끝난 일 — POS 하단 재설계 (커밋 2개, **push 대기**)

목업(합의본): https://claude.ai/artifact/QT5B1ucTmvDcHDY4No1EQ4

구형 VControlGrid2 레이아웃을 따라 재배치했다.

```
┌─ PAGO ──────────────────────────┐  Subtotal        15.000
│ ● Efectivo (F9)  $[ ] Resto ✕   │  Descuentos +
│ ● [Crédito ▾]    $[ ] Resto ✕   │  Recargos   +
│ ● [Banco ▾]      $[ ] Resto ✕   │  Transporte $[ ]
│ ● [Mercadopago ▾]$[ ] Resto ✕ ▣ │  ─────────────────
│ + Otros métodos…                │  Total          15.000
│ ✓ Listo (F2)      Pagado 15.000 │
└─────────────────────────────────┘
```

| 커밋 (ventago-app) | 내용 |
|---|---|
| `589ee86` | 캐하 「Pago」 인라인 4행 + 오른쪽 Subtotal→조정→Total 순서 |
| `2dce94c` | **AutoEfectivo 가 수동 입력을 되돌리던 것** 수정 |

### 설계에서 지킨 것

- **상태는 안 옮기고 「그리는 자리」만 옮겼다.** `InvoiceAditional` 이 여전히
  Descuentos/Recargos/Transporte·**단축키**(Ctrl+F9·F9·Re Pág·Av Pág)·결제 모달의
  주인이고, 오른쪽 상자 안에 `ajustes` prop 으로 렌더된다.
  쪼갰으면 **단축키가 두 번 등록**됐다. 컨텍스트로 올린 건 `paymentModalOpen` 하나뿐.
- 결제수단 목록은 `usePaymentMethods`(SWR 5분)로 통일 — 두 화면이 요청 하나를 공유.
- **4종을 가정하지 않는다.** 운영 실측: 13개 매장이 efectivo+tarjeta-debito+mercadopago,
  store 9 는 은행이 **둘**, store 6·17 은 efectivo 하나뿐. `banco`·`credito` 는
  전역 세트(store_id NULL)에서 오고 `GET /payment-methods` 가 둘을 합쳐 준다.
- 슬롯 구성은 **이 기기에만** 기억(`localStorage`, 사용자가 (a) 선택).

### ★ 브라우저로 실측해 잡은 결함

`AutoEfectivo` 가 「결제수단 1개면 금액을 총액으로 강제」해서, 15.000 판매에 현금
10.000 을 넣으면 **말없이 15.000 으로 되돌아갔다.** 인라인 편집에서는 곧 부분 금액
입력 불가다. 「지금 금액이 **직전 총액과 같을 때만**(=자동으로 맞춰져 있던 값일 때만)
따라간다」로 바꿨다.

**끝단 검증(로컬, store 6)**: Efectivo 7.500 + Banco 7.500 → F2 →
`sales.id=5171439` total 15.000 · `sale_payment_methods` 2줄(Efectivo 7.500 ·
Banco 7.500) · 합계 일치. **DB 로 대조**했다.

### 검증 수치
`tsc 0` · `eslint 0 error` · `jest 15/15`(`pago-inline.spec.ts`) ·
**돌연변이 3/3 사망**(0원이 줄을 남김 · 중복 필터 제거 · 입력 정제 제거)

---

## 3. 오늘 배포된 것

| | |
|---|---|
| print-agent **v1.2.4** | 티켓 통일(매장명 제거·Fecha/Hora·꼬리·배너·제목) + `Color Único × Talle Única` 표 제거. GH Actions success, 자동 업데이트 채널 `latest.yml` = 1.2.4 |
| app (Jenkins front **#775**) | 티켓에 판매 시각 전달(`SaleReviewPanel`·`EnvioTimeline`) |
| api (Jenkins **#942**) | Phase 93 **P1-c**(저장 계약) · **P1-d**(perm-cache 마이그레이션 규약) |

★ **Jenkins 잡 이름**: 실제는 **`api-new-coolsistema`** 다. CLAUDE.md 에는
  `api-coolsistema` 로 적혀 있어 감시 스크립트가 **빈 값으로 조용히** 돌았다. 문서 수정 필요.

---

## 4. Phase 93 — 0단계 4/5

| | 항목 | 상태 |
|---|---|---|
| P1-a | 로그인 백필 정지 | ✅ 배포 |
| P1-b | `roleId` 매장 소유권 | ✅ 배포 |
| P1-c | 저장 계약(`expectedRemovals` → 409) | ✅ 배포 |
| P1-d | 마이그레이션 `-- perm-cache:` 강제 | ✅ 배포 |
| **P1-e** | `isAllowed()` fail-open | ⏸ **사용자 결정 대기** |

### ★★ P1-e — 운영에 살아 있는 인가 구멍이다 (Phase 준비가 아니라 지금 열려 있다)

코드가 `@FunctionGuard` 로 요구하는 slug 99개 중 **3개가 카탈로그(`functions`)에 없다.**
없으면 `isAllowed()` 가 **통과**시킨다(`function-permission.service.ts` 의 `if (!fn) return true`).

| slug | 엔드포인트 | 현재 |
|---|---|---|
| `manage-clients` | `POST /clients/:id/promote` · `POST /clients/merge` | **JWT 만 있으면 전원 통과** |
| `manage-codigo-import` | `POST /code-import` (대량 상품 임포트) | 〃 |
| `view-codigo-import-history` | `GET /code-import/history` | 〃 |

역할 가드가 **하나도 없다**(로컬·운영 동일). `enviar-campana` 도 목록에 잡히지만
그건 **주석 안**이라 실제 가드가 아니다.

**순서가 중요하다 — ①→②**
1. 3개 slug 를 `functions` 에 시드하고 **역할에 부여**(시드만 하면 그 순간 fail-closed 로
   뒤집혀 아무도 못 쓴다). **어느 역할에 줄지가 미결** — 내 권고는 **admin 계열만**
   (`admin`·`store_admin`·`super_admin`·`superadmin`·`store_owner`). 고객 병합과 대량
   임포트는 되돌리기 어렵다.
2. fail-closed 전환 + 부팅 시 **모든 `@FunctionGuard` slug 가 카탈로그에 있는지 단언**.
   그래야 이런 누락이 배포 시점에 드러난다. 지금은 조용히 통과라 아무도 모른다.

### 1~7단계
전부 미착수. 계획서 `.planning/phases/93-permisos-4-niveles/93-PLAN.md`.
★ ROADMAP 2185행의 93 항목이 **「(계획만)」으로 낡았다** — P1-a~d 는 배포됐다.
★ 목업 링크가 셋으로 갈라져 있다(ROADMAP `BTnotmcsJBvFLwm6VvCNNP` /
  핸드오프 `DPJdfbTmLnMhjd7mfnKnMq`·`8vAr5Jhx5BembFZYqZA4j4`). 어느 게 최신인지 확인 필요.

---

## 5. 미결 (사용자 답변 대기)

1. **P1-e 역할 부여 대상** (§4)
2. **Flutter `tienda-admin-app`** 은 아직 `expectedRemovals` 를 안 보낸다
   (`usuarios_repository.dart:374`) → 거기엔 P1-c 보호가 없다. expand 단계라 동작은 정상.
3. **액션 수준 부분 로드**는 P1-c guard 가 못 잡는다. 지금 재현 경로는 없지만
   **Phase 93 ④액션 UI 를 만들 때** 같이 처리해야 한다(서비스 주석에 조건으로 박아 뒀다).

## 6. 환경

- 3050 = `npm run dev`, 5002 = 로컬 API(`DATABASE_NAME=ventago DATABASE_PORT=5432`).
- **dev 번들로도 cmux 브라우저가 정상 동작했다** — 메모리 `cmux-needs-production-build-for-this-app`
  의 「운영 빌드여야 한다」는 이번엔 해당 없었다. 운영 빌드는 돌고 있는 dev 서버를 깨뜨리니
  먼저 dev 로 시도할 것.
- 더미 계정 4개 비밀번호 `Dummy1234`(로컬 전용). 화면 검증은 `cmux browser --surface N`.
  ★ 로그인은 사용자가 해야 한다(비밀번호 입력은 내가 하지 않는다).
