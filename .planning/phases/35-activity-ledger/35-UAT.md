# Phase 35 UAT — Activity Ledger 검증

**Created:** 2026-05-22
**Verifier:** junghokim10@gmail.com
**Scope:** Phase 35-A (U1..U14 + 회귀 U9b/U12b) + Phase 35-B (U15..U19) + Backfill (U20..U22)
**Status:** awaiting_user_validation

---

## 사전 조건 (Pre-conditions)

- [x] Phase 35 Plans 01-08 모두 완료 (commit 됨, summary 8개 생성)
- [x] 로컬 PG18 (`localhost:5432/ventago`) 에 `phase35-activity-ledger.sql` 적용 완료 (3 컬럼 / 1 CHECK / 2 FK / 3 INDEX 검증됨)
- [x] 로컬 PG18 에 `phase35-stock-movement-permission.sql` 적용 완료 (function + role_functions 11행)
- [ ] api-ventago 빌드 + ESLint 통과 (각 plan 의 summary 에서 확인 가능)
- [ ] 로컬 dev 환경 (`npm run dev:api` + `dev:app`) 실행 중 — **현재 미실행** (cURL 의존 검증은 pending)

**환경 메모:** Docker 가 없으므로 로컬 호스트 PG18 직접 접속. 운영은 PG10 — 본 UAT 는 dev 환경 한정. 운영 적용은 별도 RUNBOOK 으로 분리.

---

## 자동 검증 스크립트 결과

**스크립트:** `api-ventago/test/phase35-uat.sh`
**실행 환경:** PG18 (localhost:5432/ventago, owner marcoskim) — api-ventago 미실행
**실행 시각:** 2026-05-22 (Plan 09 Task 2 실행 시)

**Summary: PASS 21 / FAIL 0 / SKIP 1** — exit code 0

```text
=== Phase 35 UAT 자동 검증 ===
  PG: marcoskim@localhost:5432/ventago
  API: http://localhost:5002/api (JWT NOT SET → cURL SKIP)
  Repo: /Users/marcoskim/Trabajos_Programming/ACE_online_1.0

U1: sales 신규 컬럼 + 트랜잭션 무결성 (스키마 레벨)
  [PASS] sales 3 신규 컬럼 존재 (activity_type/origin_branch_id/target_branch_id)
  [PASS] CHECK 제약 chk_sales_activity_type 적용
  [PASS] FK 제약 2개 (origin/target → branches)
  [PASS] 3 신규 인덱스 (idx_sales_activity_date + 2 partial)
U4/U5: activity_type 필터 분리 가능 (CHECK 제약으로 invalid 값 차단)
  [PASS] 모든 activity_type 값 유효 (sale/movido/fallado)
  [PASS] activity_type NULL 행 0개
U9: stock.movement permission_slug 등록
  [PASS] stock.movement function 등록 (1행)
  [PASS] stock.movement 최소 1 role 매핑 (실제 11 rows)
  [PASS] 5 종 role (admin/superadmin/store_owner/store_admin/gerente) 모두 매핑
U9b: 기존 사용자 자동 부여 (마이그레이션 user_functions INSERT)
  [PASS] user_functions 마이그레이션 실행됨 (실제 자동 부여 0 user grants — 0 도 정상: 최근 90일 sale 활동 없음)
U12b: dailyNumber 단조 보장 — activityType 필터 코드 적용 확인
  [PASS] sales-create.service.ts 에 activityType='sale' 필터 적용 (5 matches, expected >= 2)
  [PASS] online-order-sales-mirror activityType=SALE filter (4 matches)
U12 (matrix): reports/dashboards 의 activity_type='sale' 필터 적용
  [PASS] 모든 7 핵심 service 가 activity_type 필터 코드 포함 (Plan 03 회귀)
U3/U4/U5/U11 (인프라): Resumen 테이블 컴포넌트 + SWR 훅 존재
  [PASS] SalesResumenTable.tsx 존재 (ventago-app/src/views/sales/list/components/SalesResumenTable.tsx)
  [PASS] useDailySalesStats.ts SWR 훅 존재
U15/U16/U19 (인프라): PanelB_ItemTable 의 MOV+/MOV-/FAL 컬럼 + navigate
  [PASS] PanelB ItemTable 에 MOV+/MOV-/FAL 컬럼 참조 (18 hits)
  [PASS] PanelB cell click navigate 코드 존재 (Plan 07 Task 2)
U20: backfill dry-run 인프라 (SQL + shell + DDL)
  [PASS] backfill SQL 파일 존재 (phase35-backfill-movidos-to-sales.sql)
  [PASS] dry-run 쉘 실행 가능 (phase35-backfill-dry-run.sh)
  [PASS] backfill_failures 테이블 존재 (Plan 08 dry-run 적용됨)
  [PASS] stocks.backfill_processed_sale_id 컬럼 존재 (idempotent guard)
U9/U9b (cURL smoke): api-ventago 가용성 + POST /stocks/movement 응답 코드
  [SKIP] api-ventago 미실행 (http://localhost:5002/api/health → connect refused) — cURL 의존 검증 SKIP (U9/U9b/U10)

=== 자동 검증 요약 ===
  PASS: 21
  FAIL: 0
  SKIP: 1

OK 자동 검증 FAIL 0 — 매뉴얼 검증 단계 진행 가능 (35-UAT.md)
```

**SKIP 사유:** api-ventago 가 미실행 (Docker 미설치 환경, dev 환경에 NestJS process 부재). cURL 의존 검증 U9/U9b/U10 은 사용자가 `npm run dev:api` 후 `API_JWT=<token> ./api-ventago/test/phase35-uat.sh` 로 재실행하여 보충.

---

## Phase 35-A 검증 (U1..U14)

### U1: 신규 movido 등록 → sales + sale_items + stocks 단일 트랜잭션 INSERT

**카테고리:** auto-pass-partial + manual UI

**자동 검증 (스크립트):**
- sales 3 신규 컬럼 (`activity_type`, `origin_branch_id`, `target_branch_id`) 존재 — PASS
- `chk_sales_activity_type` CHECK 제약 적용 — PASS
- 3 인덱스 (`idx_sales_activity_date`, `idx_sales_origin_branch`, `idx_sales_target_branch`) 존재 — PASS

**매뉴얼 절차 (UI 등록 + DB 검증):**
1. POS 화면 (`http://localhost:3050/nueva-venta`) 진입.
2. 상품 2개 카트 담기.
3. "Movimientos" 체크박스 활성, target sucursal 선택.
4. "Registrar Movimiento" 클릭 → 성공 toast 확인.
5. DB 검증:
   ```bash
   psql -h localhost -p 5432 -U $USER -d ventago -c "
   SELECT s.id, s.activity_type, s.origin_branch_id, s.target_branch_id,
          (SELECT COUNT(*) FROM sale_items WHERE sale_id=s.id) AS items
   FROM sales s
   WHERE activity_type='movido'
   ORDER BY s.id DESC LIMIT 1;"
   ```

**기대:** sales 1행 (activity_type='movido', origin/target 모두 NOT NULL) + sale_items 2행. 부분 실패 시 모두 ROLLBACK 되어 row 0개.

**결과:** [ ] PASS / [ ] FAIL

---

### U2: ventaVista 리스트 영역에 movido 표시

**카테고리:** manual UI

**절차:**
1. `http://localhost:3050/ventas` 진입.
2. U1 에서 등록한 movido 행을 리스트 상단에서 찾는다.

**기대:**
- Tipo 컬럼에 `[MOV]` chip (blue tint, light blue background).
- Cliente 컬럼에 `JEFE → SALA` 라우트 (origin → target 지점명).
- 행 배경 light blue (`#E3F2FD`) + 좌측 4px border (`#1976D2`) — FullTable 의 `getRowSx` prop 으로 적용됨 (Plan 35-05 Task 2).
- Total / Descuento / Métodos de pago 컬럼은 `—` 표시.

**결과:** [ ] PASS / [ ] FAIL

---

### U3: Resumen 테이블 — MOV+ / MOV− 셀 정확

**카테고리:** manual UI + DB cross-check

**절차:**
1. `/ventas` 진입 → KPI strip 위치에 Resumen 테이블 (8 컬럼) 노출 확인.
2. origin 지점의 MOV− 셀과 target 지점의 MOV+ 셀 값 비교.
3. DB 교차 검증:
   ```bash
   psql -h localhost -p 5432 -U $USER -d ventago -c "
   SELECT origin_branch_id, target_branch_id, COUNT(*) AS sales_count,
          (SELECT SUM(quantity) FROM sale_items si WHERE si.sale_id IN (SELECT id FROM sales s2 WHERE s2.origin_branch_id=s.origin_branch_id AND s2.target_branch_id=s.target_branch_id AND s2.activity_type='movido' AND DATE(s2.sale_date)=CURRENT_DATE)) AS qty_sum
   FROM sales s
   WHERE activity_type='movido' AND DATE(sale_date)=CURRENT_DATE
   GROUP BY origin_branch_id, target_branch_id;"
   ```

**기대:**
- MOV+ 셀에 들어온 prendas 수 표시 (예: +2).
- MOV− 셀에 나간 prendas 수 표시 (예: −2).
- Σ TOTAL 행에서 `MOV+ === MOV−` (같은 store 내 이동이므로 무게중심 동일).

**결과:** [ ] PASS / [ ] FAIL

---

### U4: KPI 의 prendas 카운트 — movido 등록 후 변하지 않음

**카테고리:** manual UI regression

**절차:**
1. movido 등록 **전** Resumen 테이블의 PRENDAS 칸 수치 기록 (각 지점 + TOTAL).
2. movido 등록 (U1) 수행.
3. `/ventas` 새로고침 → PRENDAS 칸 수치 비교.

**기대:** PRENDAS 수치 **변화 없음** — `activity_type='sale'` 만 집계 (Plan 03 의 13개 service 필터 적용).

**결과:** [ ] PASS / [ ] FAIL

---

### U5: KPI 총매출 금액 — movido 등록 후 변하지 않음

**카테고리:** manual UI regression

**절차:** U4 와 동일하되 Resumen 의 VENTAS 금액 비교.

**기대:** VENTAS 금액 변화 없음 (movido 는 매출 sum 에 포함되지 않음).

**결과:** [ ] PASS / [ ] FAIL

---

### U6: Resumen 행 클릭 → URL `?branch=X` + chip

**카테고리:** manual UI

**절차:**
1. Resumen 테이블의 JEFE (혹은 본인 지점) 행 클릭.
2. URL bar 와 화면 상단 chip strip 확인.

**기대:**
- URL: `/ventas?originBranchId=N&branchLabel=JEFE&activityType=all` (또는 동등 query — Plan 05 Task 1 의 URL 동기화 결과).
- chip: `[JEFE ✕]` 표시.
- 리스트가 JEFE origin 의 모든 활동 (sale + movido + fallado) 표시.

**결과:** [ ] PASS / [ ] FAIL

---

### U7: Resumen 셀 클릭 → 2개 chip + URL

**카테고리:** manual UI

**절차:** SALA·MOV+ 셀 (target=SALA, direction=in) 클릭.

**기대:**
- URL: `/ventas?targetBranchId=N&branchLabel=SALA&activityType=movido&direction=in`.
- chip 2개: `[SALA ✕]` `[MOV+ ✕]`.
- 리스트가 SALA target movido 만 표시.

**결과:** [ ] PASS / [ ] FAIL

---

### U8: chip X 클릭 → URL 제거 + 필터 해제

**카테고리:** manual UI

**절차:** U7 상태에서 `[SALA ✕]` 의 X 클릭.

**기대:**
- URL 에서 `branchLabel` / `targetBranchId` 가 제거됨.
- 리스트의 sucursal 필터 해제, 활동 분류 chip (MOV+) 만 남음.

**결과:** [ ] PASS / [ ] FAIL

---

### U9: 권한 없는 사용자 → POST 403

**카테고리:** auto-pending (api-ventago 미실행 환경에서는 cURL 불가) + manual cURL

**자동 검증 가능 부분 (스크립트):**
- `stock.movement` permission_slug 가 functions 테이블에 등록 — PASS
- 5+ role 에 매핑 — PASS

**매뉴얼 절차 (cURL):**
```bash
# stock.movement 권한 없는 user (예: vendedor 신규 계정) 의 JWT
TOKEN_NO_PERM="..."  # 사전 준비

curl -X POST -H "Authorization: Bearer $TOKEN_NO_PERM" -H "Content-Type: application/json" \
  -d '{"type":"movido","originBranchId":1,"targetBranchId":2,"items":[{"productId":1,"quantity":1}]}' \
  http://localhost:5002/api/stocks/movement -v 2>&1 | grep "HTTP/"
```

**기대:** `HTTP/1.1 403 Forbidden`.

**결과:** [ ] PASS / [ ] FAIL / [ ] pending (api-ventago not running)

---

### U9b: 비-privileged 사용자 + stock.movement 권한 + 자기 지점 origin → 200 (회귀)

**카테고리:** manual cURL (PermissionGuard 회귀 검증)

**절차:**
```bash
# user.branchId = 1, body.originBranchId = 1 (자기 지점)
# user 는 vendedor role + user_functions(stock.movement) 직접 부여
TOKEN_VENDEDOR_B1="..."

curl -X POST -H "Authorization: Bearer $TOKEN_VENDEDOR_B1" -H "Content-Type: application/json" \
  -d '{"type":"movido","originBranchId":1,"targetBranchId":2,"items":[{"productId":1,"quantity":1}]}' \
  http://localhost:5002/api/stocks/movement -v 2>&1 | grep "HTTP/\|saleId"
```

**기대:** `HTTP/1.1 200 OK` + 응답 body 에 `saleId` 포함.

**중요:** Warning 1 회귀 검증 — `InjectBranchIdFromOriginGuard` 가 `body.branchId = body.originBranchId` 사전 주입하여 PermissionGuard 통과 보장 (Plan 02 Task 3).

**결과:** [ ] PASS / [ ] FAIL / [ ] pending (api-ventago not running)

---

### U10: 다른 지점 origin → branch 제약 위반 403

**카테고리:** manual cURL

**절차:**
```bash
# user.branchId = 1, origin=3 (다른 지점) 시도
curl -X POST -H "Authorization: Bearer $TOKEN_BRANCH1" -H "Content-Type: application/json" \
  -d '{"type":"movido","originBranchId":3,"targetBranchId":4,"items":[{"productId":1,"quantity":1}]}' \
  http://localhost:5002/api/stocks/movement -v 2>&1 | grep "HTTP/\|message"
```

**기대:** `HTTP/1.1 403 Forbidden` + 에러 메시지 "No tiene permiso para registrar movimientos entre estas sucursales" (또는 동등).

**결과:** [ ] PASS / [ ] FAIL / [ ] pending (api-ventago not running)

---

### U11: 단일 지점 사용자 ventaVista → Resumen TOTAL 행 숨김

**카테고리:** manual UI

**절차:**
1. 단일 지점 매장 (예: 매장 ID 6 coolsistema 가 1개 지점인 경우) 사용자 로그인.
2. `/ventas` 진입 → Resumen 테이블에 `perBranch.length === 1` 인지 확인.

**기대:** Σ TOTAL 행 표시되지 않음 (Plan 04 의 `SalesResumenTable` 의 TOTAL 조건 `perBranch.length > 1` 일 때만 노출).

**결과:** [ ] PASS / [ ] FAIL

---

### U12: 기존 매출 보고서 — movido 등록 후 수치 변화 없음

**카테고리:** manual UI regression

**절차:**
1. `/reportes/ventas` 진입, 매출 수치 (총매출/평균/할인 등) 기록.
2. U1 에서 movido 등록.
3. `/reportes/ventas` 새로고침, 수치 비교.

**기대:** 매출/평균/할인 등 모든 수치 동일 — Plan 03 의 reports/dashboards/mirror 7+ service 에 `activity_type='sale'` 필터 적용 회귀.

**결과:** [ ] PASS / [ ] FAIL

---

### U12b: dailyNumber 단조 보장 — movido 가 sale 번호 잠식하지 않음 (회귀)

**카테고리:** auto-pass (코드 grep) + manual end-to-end

**자동 검증 (스크립트):**
- `api-ventago/src/app/sales/sales-create.service.ts` 에 `activityType.*SALE` 또는 `activity_type.*sale` grep 2회 이상 매칭 — PASS

**매뉴얼 절차:**
1. 오늘 마지막 sale 의 dailyNumber 기록 (예: 12).
   ```bash
   psql -h localhost -p 5432 -U $USER -d ventago -c "
   SELECT id, activity_type, daily_number FROM sales
   WHERE store_id=9 AND DATE(sale_date AT TIME ZONE 'America/Bogota') = CURRENT_DATE
   ORDER BY id DESC LIMIT 5;"
   ```
2. movido 등록 (U1).
3. 신규 sale 등록 (POS 일반 판매) → 그 sale 의 dailyNumber 확인.

**기대:** 신규 sale 의 `dailyNumber === 13` (마지막 sale + 1) — movido / fallado 는 dailyNumber 잠식 안함.

**중요:** Plan 03 Task 1 STEP B 의 `sales-create.service.ts` L188/L379 의 `lastSaleToday` 쿼리에 `activityType='sale'` 필터 회귀 검증.

**결과:** [ ] PASS / [ ] FAIL

---

### U13: fallado 등록 흐름 — 동일

**카테고리:** manual UI

**절차:** U1-U3 의 movido 대신 fallado.

**기대:**
- DB: `sales(activity_type='fallado', origin_branch_id IS NOT NULL, target_branch_id IS NULL)`.
- 리스트: `[FAL]` chip (red tint, light red background `#FFEBEE`) + Cliente `FAL · JEFE` + 좌측 4px border (`#D32F2F`).
- Resumen: FAL 셀에 prendas 수.

**결과:** [ ] PASS / [ ] FAIL

---

### U14: Resumen movBalance 알람

**카테고리:** manual data injection + UI

**절차:** 데이터 정합성 인위적 깨뜨림 (movido sale 의 sale_items 일부 삭제) 후 새로고침.

```bash
# 데이터 백업 후 ONLY DEV
psql -h localhost -p 5432 -U $USER -d ventago -c "BEGIN; DELETE FROM sale_items WHERE sale_id IN (SELECT id FROM sales WHERE activity_type='movido' ORDER BY id DESC LIMIT 1); -- 확인 후 COMMIT 또는 ROLLBACK"
```

**기대:** Σ TOTAL 행 MOV+/MOV− 셀에 ⚠ 아이콘 + tooltip "동일 store 내 이동인데 IN/OUT 합이 다릅니다".

**복원:** 테스트 후 ROLLBACK (BEGIN 트랜잭션 유지 시) 또는 별도 테스트 sale 삭제 (운영에는 절대 적용 금지).

**결과:** [ ] PASS / [ ] FAIL

---

## Phase 35-B 검증 (U15..U19)

### U15: Stock Cockpit MOV+/MOV−/FAL 컬럼 표시 + 정확

**카테고리:** manual UI + DB cross-check

**절차:**
1. `/reportes/stocks` 진입.
2. PanelB_ItemTable 컬럼에 MOV+ / MOV− / FAL (VENTA 와 STOCK 사이) 노출 확인.
3. 한 product 의 MOV+/MOV−/FAL 수치를 DB 와 교차 검증:
   ```bash
   psql -h localhost -p 5432 -U $USER -d ventago -c "
   SELECT p.sku,
          (SELECT SUM(si.quantity) FROM sale_items si JOIN sales smv ON smv.id=si.sale_id
           WHERE si.product_id=p.id AND smv.activity_type='movido' AND smv.target_branch_id=1) AS mov_in,
          (SELECT SUM(si.quantity) FROM sale_items si JOIN sales smv ON smv.id=si.sale_id
           WHERE si.product_id=p.id AND smv.activity_type='movido' AND smv.origin_branch_id=1) AS mov_out,
          (SELECT SUM(si.quantity) FROM sale_items si JOIN sales smv ON smv.id=si.sale_id
           WHERE si.product_id=p.id AND smv.activity_type='fallado' AND smv.origin_branch_id=1) AS fal
   FROM products p WHERE p.id=:productId;"
   ```

**기대:** 화면 수치 == DB 수치.

**결과:** [ ] PASS / [ ] FAIL

---

### U16: OFFSET 컬럼 — Phase 35-A 적용 후 movido 는 OFFSET 에 안 들어감

**카테고리:** manual UI regression

**절차:**
1. 새로운 movido 등록 (Phase 35 백엔드 적용 후, U1 으로 등록).
2. Stock Cockpit 의 해당 product OFFSET 컬럼 값 변동 없음 확인.

**기대:** OFFSET 값 변동 없음 — sales 가 1급 처리되므로 stocks(type='adjust') 의 OFFSET 집계는 별개로 유지 (Plan 07 Task 1 의 OFFSET 보존 결정).

**결과:** [ ] PASS / [ ] FAIL

---

### U17: STOCK 등식 검증

**카테고리:** manual spot check

**절차:** 한 product 의 `STOCK = INGRESO − VENTA + MOV+ − MOV− − FAL + OFFSET` 수동 spot check.

**기대:** 등식 성립 (±0). 미세한 round-off 는 허용 (단, 큰 차이 시 데이터 정합성 오류).

**결과:** [ ] PASS / [ ] FAIL

---

### U18: MOV+ 셀 hover → tooltip 최근 5건 (DEFERRED)

**상태:** ❌ **DEFERRED — Phase 35-C/36 후보**

**Defer 사유:**
- 별도 endpoint (`/sales/by-product-recent?productId=X&type=movido&limit=5`) 필요
- 또는 N+1 query 부담 (각 row 마다 lazy fetch)
- Phase 35-A 의 한정된 context budget 으로 무리

**후속 phase 후보:** Phase 35-C 또는 Phase 36 (Stock Cockpit Phase B 확장)

**결과:** [x] N/A DEFERRED — 35-SPEC.md UAT 섹션의 U18 마커 + Plan 07 SUMMARY 의 deferred 표기 참조

---

### U19: MOV+ 셀 click → ventaVista navigate (구현 완료)

**상태:** ✅ **Plan 35-07 Task 2 에서 구현됨**

**카테고리:** manual UI verification

**절차:**
1. `/reportes/stocks` 진입.
2. PanelB_ItemTable 의 MOV+ 셀 (값 > 0) 클릭.
3. URL 변경 + ventaVista navigate 확인.

**기대:**
- URL: `/ventas?productId=X&activityType=movido&direction=in`.
- ventaVista 의 chip strip 에 `[MOV+]` chip 표시 (Plan 35-05 의 URL → state sync).
- 리스트가 해당 product 의 movido in 만 표시 (productId 필터는 Plan 05 client-side 또는 backend 확장 — productId 필터링은 후속 phase 가능).

**FAL 셀 click:** `/ventas?productId=X&activityType=fallado` navigate.
**MOV− 셀 click:** `/ventas?productId=X&activityType=movido&direction=out` navigate.

**결과:** [ ] PASS / [ ] FAIL

---

## Backfill 검증 (U20..U22)

### U20: backfill dry-run — sales 생성 수가 stocks 그룹 수와 일치

**카테고리:** auto-pass (인프라) + manual dry-run 실행

**자동 검증 (스크립트):**
- `phase35-backfill-movidos-to-sales.sql` 파일 존재 — PASS
- `phase35-backfill-dry-run.sh` 실행 가능 (executable bit) — PASS
- `backfill_failures` 테이블 / `stocks.backfill_processed_sale_id` 컬럼은 backfill 첫 실행 시 자동 생성

**매뉴얼 절차 (dry-run 실행):**
```bash
./api-ventago/migrations/phase35-backfill-dry-run.sh dev
```
출력에서 `backfilled_rows` 와 stocks 의 distinct group 수 비교.

**기대:**
- movido(out) 그룹 수 == `sales(activity_type='movido')` INSERT 행 수 + `failed_rows`.
- fallado 그룹 수 == `sales(activity_type='fallado')` INSERT 행 수 + `failed_rows`.
- ROLLBACK 후 sales count 변화 없음.

**결과:** [ ] PASS / [ ] FAIL

---

### U21: backfill 실행 후 — 과거 ventaVista 에 movido 흔적 표시

**카테고리:** manual destructive (dev only — 운영 절대 실행 금지 in this UAT)

**절차** (조심: 실제 INSERT — dev 환경 한정):
```bash
# 1. dev DB 백업
pg_dump -h localhost -p 5432 -U $USER ventago > /tmp/ventago-pre-backfill.dump
# 2. backfill 실행 (실제 INSERT)
psql -h localhost -p 5432 -U $USER -d ventago -v ON_ERROR_STOP=1 -f api-ventago/migrations/phase35-backfill-movidos-to-sales.sql
# 3. ventaVista 진입, 과거 날짜 필터링 → backfilled movido 행 표시 확인
# 4. 복원 (필요 시):
#    psql -h localhost -p 5432 -U $USER -d ventago -c "DROP DATABASE ventago_backup_test"
#    pg_restore -h localhost -p 5432 -U $USER -d ventago --clean < /tmp/ventago-pre-backfill.dump
```

**기대:** 날짜 필터 + sucursal 필터로 backfill 된 movido 확인 가능. `sales.notes LIKE '[Backfill Phase 35]%'` prefix 로 식별 가능.

**결과:** [ ] PASS / [ ] FAIL

**중요:** 운영 backfill 실행은 본 UAT 범위 외. 35-RUNBOOK-PROD.md 별도 작성 후 사용자 승인 → 운영 적용.

---

### U22: backfill 후 매출 보고서 수치 변화 없음

**카테고리:** manual UI regression

**절차:** U21 실행 후 `/reportes/ventas` 진입, 매출 수치 비교 (사전 기록 vs 사후).

**기대:** 변화 없음 (`activityType='sale'` 필터 정상 작동 — Plan 03 의 13 service + reports 7+ 회귀).

**결과:** [ ] PASS / [ ] FAIL

---

## 종합 평가

- [ ] **Phase 35-A 14/14 통과** (U1..U14 + U9b + U12b 회귀) → ventaVista 운영 적용 가능
- [ ] **Phase 35-B 4/5 통과** (U15-U17, U19 — U18 은 DEFERRED) → Stock Cockpit Phase B 적용 가능
- [ ] **Backfill 3/3 통과** (U20..U22) → 운영 backfill PR 승인 가능
- [ ] **운영 PG10 마이그레이션 절차 별도 문서** (`.planning/phases/35-activity-ledger/35-RUNBOOK-PROD.md`) — Phase 35-UAT 통과 후 작성
- [ ] **U18 DEFERRED 항목** → 후속 phase 등록 (Phase 35-C / 36) — 사용자 결정 필요

**Sign-off:** 사용자 검증 완료 시 STATE.md 업데이트 + ROADMAP Phase 35 status → COMPLETE.

---

## 부록 A — 자동 검증 raw output

스크립트: `api-ventago/test/phase35-uat.sh` (PG18 localhost 대상)

실행 명령:
```bash
./api-ventago/test/phase35-uat.sh
```

(스크립트는 본 plan Task 2 에서 작성 + 실제 실행됨. raw output 은 본 파일 끝의 [실행 결과](#실행-결과) 섹션 참조.)

---

## 실행 결과

(plan 09 의 Task 2 실행 시 채워짐. PLACEHOLDER 가 실제 결과로 치환되어야 함.)
