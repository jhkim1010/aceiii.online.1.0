# Phase 50 — CoolPay (자체 결제·자금관리 시스템) (CONTEXT)

> **유형**: 신규 제품/플랫폼 (확장 로드맵 방향 ③) — **장기·고난도(규제)**
> **선행**: 공개몰(shop-mvp) + 결제 추상화(`PaymentProvider`, Phase 의 MP Checkout) 운영·검증
> **관련 문서**: `future proyect/00-expansion-strategy-roadmap.md`(방향 ③)
> **작성일**: 2026-06-29
> **번호 주의**: 46=Shopify / 47=Empretienda / 48=WC통일 / 49=AI Try-On 사용 중 → CoolPay = **50**.
> **성격**: 본 문서는 *기획/준비* 문서다. 이 phase 는 코드보다 **규제·법무·자본·컴플라이언스**가 선행이며, 착수 자체가 go/no-go 게이트를 가진다.

---

## 1. 왜 이 phase 인가 (다층 분석)

- **표면 문제**: "MercadoPago 가 자금을 직접 굴리듯, CoolPay 로 우리도 자금을 보관·정산·이체하고 싶다."
- **구조적 원인**: MP 가 자금을 "직접 관리"하는 근거는 코드가 아니라 **규제 자격(BCRA 등록 PSP/PSPCP)** 이다. 타인의 자금을 보관·정산·이체하는 순간 소프트웨어 문제가 아니라 **금융 라이선스·자본금·AML/KYC·감사·정보보고 의무**의 문제가 된다.
- **근본 본질**: CoolPay 의 본질은 "결제 화면"이 아니라 **신뢰를 법적으로 보증하는 라이선스드 금융기관이 되는 것**이다. 기술 난이도(★★)보다 규제·컴플라이언스·자본 난이도(★★★★★)가 압도적이다. → 전략은 **"라이선스 없이 갈 수 있는 데까지 먼저, 가치가 검증되면 라이선스로 진입"** 하는 *단계적 우회*다.

## 2. 규제 현실 (아르헨티나, 2026 — 법무 재검증 필수)

> ⚠️ 아래는 2026-06 기준 공개정보 요약. 실제 착수 전 **BCRA PSP 전문 로펌**(예: Marval, Allende & Brea) 의 최신 자문으로 재검증할 것.

- BCRA 는 2026-05-06 **Comunicación "A" 8432** 로 PSP(Proveedores de Servicios de Pago) 체계를 강화하고 **"PSPCP como Servicio"**(타사 인터페이스를 통해 결제계좌를 제공하는 형태) 범주를 신설 — *정확히 CoolPay 같은 모델을 겨냥*.
- 등록 시: **지분 10%↑ 보유자·실질지배자·임원 전원**의 범죄경력·진술서 제출, AML 체계, 정보보고(régimen informativo) 의무.
- 등록 후 영업개시 기한 6→12개월 연장, 기등록 PSP 는 90일 내 적응.
- 결론: **타인 자금을 직접 보관·정산하려면 PSP/PSPCP 등록은 회피 불가.**

### 출처 (재검증용)
- BCRA Registro de PSP: https://www.bcra.gob.ar/en/registry-of-payment-service-providers-psps/
- BCRA Texto ordenado PSP (A 8287): https://www.bcra.gob.ar/archivos/Pdfs/Texord/t-snp-psp.pdf
- Allende & Brea (2026-05): https://allende.com/fintech/el-banco-central-introduce-nuevas-regulaciones-sobre-proveedores-de-servicios-de-pago-05-14-2026/
- Abogados.com.ar — PSPCP como Servicio

## 3. 단계적 우회 전략 (핵심)

| Stage | 내용 | 자금 커스터디 | 라이선스 | 비고 |
|---|---|---|---|---|
| **0** | MP Split/Marketplace 분할정산 + 자체 원장(read) | **MP 가 보관** | 불필요 | "자금관리" 경험 80%를 무자격 제공. 이미 MP OAuth Split 코드 보유 |
| **1** | 멀티 PSP 어그리게이터(결제 라우터) | **라이선스드 PSP 가 보관** | 불필요(주의) | 원장·정산·수수료는 자체, 자금은 외부 PSP |
| **2** | 자체 지갑/잔액(PSPCP) | **CoolPay 가 보관** | **PSPCP 등록 필수** | 진짜 자체 자금관리. 법무·자본·AML 선결 |

**원칙**: Stage 0 → 거래량·가치 검증 → (go/no-go) → Stage 1 → (go/no-go) → Stage 2. *코드부터 짜고 법무를 나중에 보는 순서가 최대 함정.*

## 4. 이미 보유한 자산 (맨땅 아님)

- **MercadoPago 풀스택**: OAuth(**마켓플레이스/split 결제**), QR, Wallet, Transfer, Webhook, Refund, Payment Intents (`api-ventago/src/app/mercadopago/`). → Stage 0/1 의 결정적 토대.
- **`PaymentProvider` 추상화** (`api-ventago/src/app/payments/`): 이미 결제를 어댑터 뒤에 둠 → CoolPay 는 "또 하나의 provider". (메모리: project_expansion_sequencing)
- **online_orders / payments 흐름**: 주문·결제 상태가 구조화됨.

## 5. 지금 하지 말 것 (명시)

- 자체 지갑/잔액 보관 로직, 정산 엔진의 *실자금* 이동
- PSPCP/PSP 라이선스 신청·자본 준비 (가치 검증 전)
- AML/KYC 풀구현 (Stage 2 직전까지는 데이터 모델 *설계만*)
- 이유: 라이선스 없이 잔액 보관 = 규제 위반 소지. 미리 만들면 리스크만 지고 쓰지도 못함.

## 6. 리스크

- **규제 리스크(최상)**: 무자격 자금보관. → Stage 0/1 로 회피, Stage 2 는 라이선스 후.
- **자본 리스크**: PSPCP 자본·임원요건. → 법무 선상담.
- **정합성 리스크**: 돈 관련 코드의 멱등성·이중기입 누락. → append-only 원장 + 멱등키 무관용.
- **신뢰 리스크**: 장애 시 자금 분쟁. → 관측성·정산 대사(reconciliation) 필수.
