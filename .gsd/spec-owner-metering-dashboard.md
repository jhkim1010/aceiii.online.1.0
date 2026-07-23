# SPEC: 플랫폼 주인 사용량 계측·과금 대시보드 (superadmin 앱)
생성일: 2026-07-22  (spec-store-billing / spec-cobros 대체 — 대상=사용량 metering 확정)

## 목표
superadmin 앱(주인+아내 전용)에서 각 매장의 **사용량 지표**를 매장·기간별로 집계해 보여주고,
그에 따라 매월 청구서를 자동 생성·수납 관리한다. ★소매 외상(credit_ledger) 무관.

## 관심 지표 → 데이터 소스 맵 (실측 확인)
1. 판매 건수         → sales(store_id, created_at/sale_date, status). count/기간.
2. 터미널 수         → terminals(store_id, is_deleted, status). count.
3. 지점 수           → branches(store_id). count.
4. fac. electrónica  → afip_vouchers(store_id, created_at). 발급 count/기간. (설정=afip_issuers)
5. WhatsApp          → whatsapp_messages(store_id, status, created_at). 전송 count/기간.
6. WP 싱크           → commerce_channels(store_id, platform='woocommerce', is_active, last_pushed_at).
7. TiendaNube        → commerce_channels(store_id, platform='tiendanube', is_active).
8. 판매원 앱 접속 수 → vendedor_devices(store_id, is_active, last_seen_at). 활성 기기 count. (+mobile_sessions 활성세션)
9. AI 가상피팅(VTO)  → vto_generations(store_id, status='success', created_at). ★이미 계측+과금 배포됨(vto_settings 단가 $200, /vto/admin/usage).
10.revendedor 판매액 → ⚠️미확정: sales.seller_id=users, revendedores(store_id 無)·reseller_store_qr_auth. 귀속 방식 조사/결정 필요.

## 재사용 (이미 있는 것)
- ★VTO metering 이 이 기능의 템플릿: vto_generations(append-only) + vto_settings(superadmin 단가) + /vto/admin/usage(매장별 집계) + front /admin/vto. → 동일 패턴을 나머지 지표로 확장.
- subscription_config: base 60k / extra_branch 40k / extra_terminal 20k / 통합 애드온 단가(fac.elec 30k, zebra 10k, talleres/materia 50k, wp/ml/tn 50k, signo 70k). currency ARS.

## 제안 아키텍처
- 신규 `metering` 모듈(NestJS, superadmin 전용, read-only 집계):
  - MeteringService.getStoreUsage(period): 매장별 위 지표 집계 — 단일/소수 raw SELECT(pool 안전, VTO 방식).
  - GET /metering/summary?period, GET /metering/stores/:id?period.
- 가격 모델(신규 `billing_prices` 또는 subscription_config 확장): 지표별 과금 방식 지정
  - 고정: base + (지점-포함)×extra_branch + (터미널-포함)×extra_terminal + 활성모듈(fac.elec/WhatsApp/WP/TN/판매원앱) 정액.
  - 종량: 판매건×?, afip건×?, whatsapp건×?, VTO건×단가(기존).
  - revendedor: 판매액 × %(수수료) 또는 정액.
- 청구: store_billing_invoices(store,period,항목별 금액,total,status pending) + store_billing_payments(method incl. mercadopago). 매월 자동 생성(멱등, pending). 앱에서 검토·수납.
- 앱: 매장별 카드(지표 브레이크다운+이번달 청구액) + 기간 셀렉터 + 상단 KPI(총 청구/총 수령/미납) + 수납 등록.

## 결정 필요 (★사용자 — 계획 확정용)
1. **과금 방식 per 지표**: 각 지표를 (a)고정 정액 (b)건당 종량 (c)%수수료 중 무엇으로? 단가는?
   - 예: base 6만/월 + 터미널 초과 2만 + fac.elec 켠 매장 3만 + VTO 건당 200 + revendedor 판매의 X% ...
2. **기본 플랜 포함 지점/터미널 수** (config 에 included_branches/terminals 신설, 기본 1).
3. revendedor 판매 귀속 방식 — 어떤 판매가 "revendedor 통한" 것인지 정의(소스 조사 필요).
4. 청구 생성일·시작월·enabled 토글.

## 단계 (제안)
- Phase A(측정만): metering 집계 엔드포인트 + 앱 대시보드(과금 없이 지표만 먼저 눈으로 확인) — 저위험, 빠름.
- Phase B(과금): 가격모델+청구서 자동생성+수납. (Phase A 로 숫자 검증 후)

## 금지/주의
- credit_ledger/store_clients 미사용. 운영 매출계 → 자동청구 pending 만. metering 은 read-only(pool 안전). VTO 기존 로직 건드리지 말고 집계에 포함만.
