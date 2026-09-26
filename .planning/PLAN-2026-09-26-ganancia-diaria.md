# Ganancia del día — 설계 (2026-09-26) · ✅ 구현·배포 2026-09-27

> **결정(2026-09-27):** ① 판매 시점 스냅샷 `sale_items.unit_cost` ② 지출 = expenses 전체
> ③ Reportes › Finanzas 「Ganancia」, 권한 `reporte-ganancia`(계획서의 `ver-ganancia` 대신
> 기존 reporte-* 규칙을 따랐다 — 메뉴 시드 불필요).
> 구현: api b0499049(스냅샷 훅) · 61c43e38(GET /reports/ganancia) · app 447af255.
> 발생주의(외상 판매는 판 날), 반품(devuelto)은 원장 favor_in/payment_in + 서랍
> 「Devolución #ID — reintegro en efectivo」 로 환불액을 읽는다.
> ⚠️ 운영에 원가 입력 상품이 아직 0개 — 그 전까지 전 판매가 「Ventas sin costo」로 뜬다.

> 사용자: 「원가를 기록했으니 하루 판매와 지출 내역을 보면 그날 얼마의 ganancia 를 얻었는지 계산…
> 퍼미션에서 볼 수 있는가 없는가를 제어」

## 공식

    Ganancia = Ventas netas − Costo de lo vendido (CMV) − Gastos
             = (판매 − 취소 역분개) − Σ(판매 수량 × 판매 시점 원가) − 그날 지출

## ★ 핵심 결정 1 — 원가는 **판매 시점에 스냅샷**해야 한다 (권장)

원가는 오늘(2026-09-26) 처음 생겼고 앞으로 바뀐다(USD 는 환율마다). 계산할 때마다 **현재 원가**를
쓰면 지난달 이익이 오늘 환율로 다시 계산된다 — 마감한 달의 숫자가 움직인다(보고서 규약 위반).

- `sale_items` 에 `unit_cost` (ARS, 판매 시점 원가 × 판매 시점 환율) 컬럼 추가(expand, nullable).
- 판매 생성 경로 **전부**에서 채운다: POS(`sales-create.service processSaleItems`), 온라인 주문,
  레스토랑, 교환(반품 줄은 음수 수량 → 원가도 되돌아옴), 취소 역분개(원본의 unit_cost 를 그대로).
  ⤷ 원가는 madre 에 있다 — 자식 변형 판매는 `parent_id` 의 원가를 쓴다.
- `unit_cost` 가 NULL 인 줄(원가 없는 상품, 오늘 이전 판매) = **「원가 미상」** 으로 따로 센다.
  0 으로 접으면 이익이 부풀려진다 → 화면에 「원가 없는 판매 $X (N건)」를 따로 보인다.

## 핵심 결정 2 — 지출에 무엇을 넣나

`expenses`(Gastos) 의 그날 합계. 카하 `retiro`·금고 이체는 **지출이 아니다**(돈의 이동).
세금·자산 구매 등 분류가 있으면 제외 여부를 정해야 한다.

## 핵심 결정 3 — 어디에, 어떤 단위로

- 권장: Reportes 에 「Ganancia」 화면 — 날짜 범위 · 지점 필터 · 일별 표
  (Ventas · CMV · Margen bruto % · Gastos · Ganancia · 원가 미상).
- 매장 타임존 기준 날짜(메모리 db-is-utc-so-today-needs-store-timezone).
- 판매 지점은 `sales.branch_id`(CLAUDE.md), 취소는 원본 지점(`saleBranchSql`).

## 권한

새 기능 `ver-ganancia`(모듈 reportes 또는 precios) — **라우트 가드**(`@FunctionGuard('ver-ganancia','read')`)
+ 메뉴 노출. `ver-costo-producto` 와 별개(이익은 보되 상품별 원가는 못 보는 역할이 가능하도록).
기본 부여: admin 계열만(원가 권한과 같은 방식의 시드 마이그레이션, 운영 적용은 승인 후).

## 작업 순서 (새 세션 권장)

1. 결정 1~3 확정
2. 마이그레이션: `sale_items.unit_cost` (+ 권한 시드)
3. 판매 생성 경로 전수(메모리 sale-creation-has-two-unattended-print-paths 처럼 경로가 여럿이다 —
   `SaleItem.create`/`bulkCreate` 를 grep 해 **전부** 채운다) + 역분개
4. 집계 API(한 번의 SQL, store_id 필수) + 화면 + 권한
5. 스테이징 검증 → 운영(승인)
