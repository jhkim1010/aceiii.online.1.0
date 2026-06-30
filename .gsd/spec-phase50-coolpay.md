# SPEC: Phase 50 — CoolPay (자체 결제·자금관리) (포인터)

생성일: 2026-06-29

> 정식 기획 문서는 phase 폴더에 있습니다:
> - `.planning/phases/50-coolpay/50-CONTEXT.md` (왜·규제·단계전략·자산·금지·리스크)
> - `.planning/phases/50-coolpay/50-SPEC.md` (Wave 태스크·원장 스키마·결정 게이트)
>
> **번호 주의**: 46=Shopify / 47=Empretienda / 48=WC통일 / 49=AI Try-On 사용 → CoolPay = **50**.

## 요약

- **본질**: 코드가 아니라 **규제(BCRA PSP/PSPCP)·자본·컴플라이언스**가 핵심. 착수 전 법무 게이트(G0).
- **전략**: 단계적 우회 — Stage 0(MP Split, 자금=MP 보관, 무자격) → Stage 1(PSP 어그리게이터, 자금=외부 PSP) → Stage 2(PSPCP 등록 후 자체 잔액).
- **공통 기반**: 이중기입 **append-only 원장**(멱등키) — Wave 50-01.
- **자산**: 기존 MP Split/Wallet/Transfer + `PaymentProvider` 추상화(이미 존재).
- **지금 금지**: 무자격 자금보관, 라이선스/자본 선투입, AML 풀구현.
- **상태**: 전부 ⬜ (기획만 준비). 착수는 G0(법무 자문) 통과 후.
