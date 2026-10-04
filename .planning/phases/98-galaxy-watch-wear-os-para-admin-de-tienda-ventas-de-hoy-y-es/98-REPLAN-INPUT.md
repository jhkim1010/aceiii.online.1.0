# Phase 98 — 재계획 입력 (2026-10-04)

98-01(페어링)은 완료·운영 DDL 적용·CODEX 수정 완료(api `2d9e706e`, 미push). 화면이 v2 로 확장되어
**98-02 ~ 98-07 을 다시 계획한다.** 결정은 `98-CONTEXT.md` D-08 ~ D-14, 화면은 `98-mockup-v2.html/.png`.

## 1. 레거시 「Resumen del día」 계산 (참고 — 정의는 D-12 가 우선)

원천: `~/TrabajoProgramming/flutter_aguila` → `POST /api/resumen_del_dia` → `~/TrabajoProgramming/node_js_svr_ace3/src/routes/resumen_del_dia.js:9-476`.
레거시 DB 는 Buenos Aires 타임존 세션, 「오늘」은 POS 가 쓴 `date` 컬럼 동등 비교. 지점별 GROUP BY 후 앱이 합산.

| 지표 | 레거시 SQL 요지 | Ventago 결정 (D-12) |
|---|---|---|
| 판매 건수/합계 | vcodes COUNT(*), SUM(tpago); b_cancelado·borrado 제외, clientenombre NOT LIKE '%CAJA%' | 취소 제외 판매 헤더, 지점은 `sales.branch_id` |
| 결제수단 | SUM(tefectivo / tcredito(=cuenta corriente) / tbanco(카드 포함) / tfavor); treservado(seña) 카드 없음 → 네 카드 합 ≠ 총액 | 현금·은행·외상·Favor **각각 따로** |
| 벌수 | SUM(cntropas) 헤더 값 | sale_items 수량 합(취소 제외) |
| 마지막 판매 | MAX(hora) varchar | max(판매 시각), 매장 타임존 HH:mm |
| 지출 | gastos COUNT/SUM(costo), DATE(fecha), borrado 제외 | expenses 오늘(지점별) |
| 할인 | vdetalle codigo1='de' 줄 COUNT/SUM(precio), 판매당 1줄, 음수 | 할인 있는 **판매 수** + 할인 합 |
| 입고 | ingresos COUNT(줄)/SUM(cant3), 지점 간 이동(bmovido) 포함 | **매입 + 공방 수령만** (조정·이동 제외) |
| 전표(월) | fventas tipofactura별 SUM(monto), Total = 전표+ND − NC, IVA = 총액×21/121 일괄, cae 확인 없음, CURRENT_DATE 의 달 | **CAE 있는 전표만, NC 차감 순액**, 종류별 + **전표에 저장된 실제 IVA**, 매장 타임존의 이번 달 |

레거시 결함(따라 하지 말 것): CAJA 이름 필터가 NULL 손님명 판매까지 제외 · 지점 표 모드의 월 전표는 항상 $0 ·
월/일 fventas 가 선택 날짜를 무시.

## 2. CODEX 설계 자문 (반영 대상)

1. **단일 `GET /watch/resumen`** 유지. 서버 내부는 섹션별 집계·캐시 후 합성. **지점별 반복 쿼리 금지** — 테이블별 1회 조건부 집계 + `GROUP BY branch_id` (N+1 금지, p95 ≤ 300ms).
2. **섹션별 `status` / `asOf` / `periodStart` / `periodEnd`** — 한 섹션(예: 전표) 실패가 Hoy·Cajas 를 막지 않는 부분 응답. 실패 섹션은 「계산 안 됨」으로, 낡은 값을 최신처럼 보이지 않게.
3. **IVA 는 저장된 세액**을 권위값으로(일괄 21/121 금지).
4. **인증·현재 admin·매장 소유권 확인 → 그 다음 캐시.** 캐시 키 = store + branch|all + timezone + schemaVersion. 오늘 캐시와 월 전표 캐시는 분리.
5. **지표별 권위 시각·상태를 명시**하고 자정 직전/직후·자정 이후 취소·지연 CAE 경계 시험.
6. 카하 목록 상한: 닫힌 카하는 소계만, 열린/미마감은 상한.
7. 토큰 피해 범위 축소 → D-14.

## 3. 98-01 에서 넘어온 할 일

- **워치 가드(98-02)**: 매 요청마다 `watch_devices.store_id = users.store_id`(현재 매장) + 현재 admin(store-filtered) 재확인 → 불일치 401. poll 직후 권한 회수 경합(CODEX P1, ms 단위 창)은 **이 가드가 첫 요청에서 막는 것**으로 닫는다 — 이 시나리오를 가드 시험에 명시.
- `listDevices` 가 권한 상실 시 `[]`(200) 을 돌려준다 → claim 과 같은 **403** 으로 (CODEX P3).
- 페어링 엔드포인트와 resumen 은 **함께 배포**(api push 는 98-02 마지막).
- 운영 DB 노출·스테이징은 영구 제외(메모리 infra-two-items-permanently-dropped).

## 4. 그대로인 것

- 98-03(워치 데이터 계층): DTO 에 v2 필드 추가, 섹션별 status 처리.
- 98-05(휴대폰 Relojes): 「위 버튼 두 번 누르기 → Ventago Admin」 설정 안내 1줄 추가(D-10).
- 98-07(Play): 서명 키는 이미 있다 — `~/android-keys/upload-keystore.jks` (5개 Flutter 앱 공용, root `c8f4ad6`). 워치 앱도 같은 키·`com.coolsistema.tienda_admin_app`(D-02).
