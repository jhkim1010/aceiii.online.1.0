# 73 후속 6 — 세 번째 재고 정의 제거 (새 세션용)

앞선 문서: `73-NEXT.md` ~ `73-NEXT-5.md`, `73-PROPOSAL-inventory-leaf.md`.
이 문서는 **2026-08-08** 작업분.

---

## 0. 먼저 읽을 것 (73-NEXT-5 §0 에 더해)

- jest: `NODE_OPTIONS=--max-old-space-size=2048 npx jest --maxWorkers=1 --workerIdleMemoryLimit=800MB`
- ★ **`grep` 이 `reportsStocksCockpit.service.ts` 를 바이너리로 판정한다.** `file` 이 `data`
  라고 답한다 — `grep -a` 를 안 쓰면 **매치가 하나도 안 나온다**. 나는 이걸로 "그 상수가
  파일에 없다"고 잘못 결론 낼 뻔했다. 이 리포에서 grep 이 조용히 0건이면 `-a` 를 먼저 의심해라.
- ★ **리포지토리 루트에 Flutter 앱이 둘 더 있다** (`tienda-admin-app`, `mobile-sales-app`).
  둘 다 `/api/reports/*` 를 직접 호출한다. **웹 화면을 지운다고 엔드포인트가 고아가 되지 않는다.**
  삭제 전 `grep -rn '<엔드포인트>' .` 를 **리포 전체**에 돌려라 (§2 가 이걸로 뒤집혔다).

---

## 1. 무엇을 했나 — 재고 숫자의 세 번째 정의를 없앴다

배포: **front #576 / api #645** 둘 다 SUCCESS + 컨테이너 재생성 + 배포 번들 확인.

발단은 사용자 신고: "`/reportes/stocks/` 에 또 다른 재고 리포트가 있다. Stock −2, Ratio 115%."

### 1-A. 화면 지도 (또 헤매지 않도록)

`/reportes/stocks` 는 **사이드바로는 도달하지 않는다.** 사이드바 Reportes 는 `/reportes-v2`
(reports-v2 셸 → Stocks Cockpit)로 간다. 그런데 `/reportes` 가 `/reportes/stocks` 로
리다이렉트하고 있어서, **주소로 들어오면 레거시 표, 사이드바로 들어오면 Cockpit** 이었다.
두 입구가 서로 다른 화면에 도착했다.

| 경로 | 종전 | 지금 |
|---|---|---|
| 사이드바 Reportes | `/reportes-v2` → Cockpit | 그대로 |
| `/reportes` | → `/reportes/stocks` (레거시 표) | → `/reportes-v2` |
| `/reportes/stocks` | 레거시 표 "Reporte de ventas" | → `/reportes-v2/stocks` |

### 1-B. Ratio 115% / Stock −2 는 **데이터가 맞았다**

이상 행 8개를 전수 분해했더니 adjust 오염이 아니라 **전부 `type=NULL` 실제 판매**였다.

| 매장 | SKU | 지점 | Ingreso | Venta | Stock |
|---|---|---|---|---|---|
| 6 | `251432001035030/036030/037030` | 6 | 13 | 15 | −2 |
| 6 | `251532001` | 6 | 1 | 36 | −35 |
| 9 | `25193442001-V` / `25194645001-V` | 14/15 | 0 | 1 | −1 |
| 9 | `25193444001` / `25194850001-V` | 14/15 | 0 | 10 | −10 |

`store_configs.allow_sale_without_stock` 이 매장 6·9·15 **전부 `true`** 다 → 음수 재고는
**의도된 동작**이다. 코드로 고칠 것이 없다. 실물과 맞추려면 Panel D 실사 보정(Offset)이 경로다.
**사용자 승인 하에 손대지 않았다.**

★ 교훈: "이상해 보이는 숫자"의 절반은 정의 문제고 절반은 데이터다. **먼저 분해해서 어느 쪽인지
가른 다음** 고쳐라. 여기서는 분해가 "정의는 틀렸지만 이 8행은 데이터가 맞다"로 갈랐다.

### 1-C. 진짜 문제 — 세 번째 정의

`reportsStocks.service.ts` 는 부호만 보고 셌다:

```
TIngreso = SUM(stock) WHERE stock > 0     -- 전 type
TVenta   = SUM(-stock) WHERE stock < 0    -- 전 type
```

→ 예약(`suspend` hold/release)·지점 이동(`transfer`)·입고 취소(`adjust`
`'anulacion ingreso%'`)가 통째로 "입고"·"판매"로 섞였다.

**운영 실측 (정본과의 차이):**

| 매장 | 행 | Ingreso 다른 행 | Venta 다른 행 | 과다 계상 |
|---|---|---|---|---|
| 6 | 196 | **86** | **90** | Ingreso +678 / Venta +767 |
| 9 | 26 | 3 | 4 | +53 / +124 |
| 15 | 20 | 4 | 4 | +756 / +420 |

`Stock`(SReal)만 원장 raw SUM 이라 원래 일치했다.

### 1-D. 표 자체의 결함 4개 (정의와 무관, 함께 사라졌다)

1. **row id 중복** — 백엔드는 (제품×지점) 1행씩 주는데 `id = productId`. AG Grid
   `getRowId` 가 그 id 를 읽는다 → **매장 6 에서 67행이 중복 id**. 선택·합계가 엉킨다.
   지점 컬럼이 없어 같은 SKU 가 여러 줄인 이유를 화면에서 알 수도 없었다.
2. **필터 전부 무동작** — 프론트는 `startDate/endDate/isParent` 를 보내는데 서비스는
   `filter`·`storeId` 만 읽었다.
3. **상세 모달이 항상 빈 표** — `columnsDetail` 이 `productCode`/`productDescription` 을
   읽는데 백엔드는 `code`/`description` 을 준다. 게다가 `activity_type` 을 안 걸러
   **movido 를 판매로** 셌다(매장 6 에 40장).
4. 비활성 제품 2건 포함 / `Últ. ingreso` 가 UTC `created_at`(operation_date 와 다른 날 45행).

---

## 2. ★ 계획이 뒤집힌 지점 — 백엔드는 못 지운다

사용자 승인은 "(가) 폐기" 였고 나도 백엔드까지 지울 생각이었다. 리포 전체 grep 에서 나왔다:

```
tienda-admin-app/lib/features/reportes/reportes_repository.dart:230
  Future<List<StockRow>> getStocks(int s) => _list('stocks-report', ...)
```

**Flutter 관리자 앱이 `/reports/stocks-report` 를 쓴다.** 읽는 필드는 `code` / `description` /
`SReal` / `TVenta` 뿐이고 `storeId` 만 보낸다(`branchId` 없음).
화면은 `Vendidos {tVenta}` + `{sReal}` 을 카드로 뿌린다 — 즉 **그 앱도 과다 계상된
`TVenta` 를 보고 있었다.**

→ 엔드포인트를 **지우는 대신 정본으로 옮겼다.** 앱 릴리스 없이 숫자가 고쳐진다.

부수 효과 (앱에서 개선):
- 집계 단위 (제품×지점) → **제품**. 종전엔 같은 SKU 가 지점 수만큼 카드로 뜨는데
  지점을 알려주는 필드가 없었다. "N productos" 카운트도 이제 맞다.
- `status != 'deactivated'` 필터가 생겨 비활성 제품이 빠진다.

---

## 3. 바뀐 것

| 파일 | 내용 |
|---|---|
| `api-ventago/.../reportsStocks.service.ts` | 자체 SQL 전면 삭제 → Cockpit `getItems` 위임 + 페이징 |
| `api-ventago/.../reportsStocks.service.spec.ts` | 신규. 9건 |
| `api-ventago/.../reportsStocksCockpit.service.ts` | `p.description` 가산 (GROUP BY 불변) |
| `api-ventago/.../reports.controller.ts` | `product-stock-summary` 삭제 |
| `ventago-app/src/pages/reportes/index.tsx` | → `/reportes-v2` |
| `ventago-app/src/pages/reportes/stocks/index.tsx` | → `/reportes-v2/stocks` |
| `ventago-app/src/views/reports/stocks/` | 레거시 7파일 삭제, `stocksParams.ts` 신설 |
| `ventago-app/.../StocksCockpitBody.tsx` | Excel 내려받기 이전 |

### `p.description` 가산이 안전한 이유

`GROUP BY p.id, p.sku, p.name, cat.name, p.price` 에 `p.id`(PK)가 있어 PG 가 함수 종속성으로
허용한다. **GROUP BY 를 늘리지 않았으므로 그룹 수도 집계값도 바뀌지 않는다.**
운영에서 실제 GROUP BY 그대로 실행해 확인했다 (73-NEXT-5 §3 함정 10 을 반복하지 않았다).

### Excel 은 없어지지 않았다

Cockpit 에는 PDF 만 있었다. 폐기 화면의 Excel 을 `StocksCockpitBody` 로 옮겼다 —
필터 전달은 PDF 경로와 **글자 단위로 같은 병합 순서**(`params` → `storeId` → `branchId` →
`sortBy/sortDir`)다. 셸(`ReportActionsContext`)이 이미 `hasExcel` 을 지원한다.

---

## 4. ★ CODEX [HIGH] — 내 첫 구현이 조용한 절단을 만들었다

첫 구현은 `getItemsForExport` 를 재사용했다. 그건 **PDF 용**이라 `pageSize` 가
`PDF_MAX_ROWS + 1 = 2001` 로 고정돼 있다.

> PDF 경로는 2001번째 행으로 절단 **여부를 판정**하고 2000행만 인쇄한다. 그런데 Excel·Flutter
> 경로는 2001행을 **그대로 성공 응답**으로 내보낸다. 서버 `warn` 은 사용자에게 안 보인다.

맞는 지적이다. 잘린 목록은 화면에서 "전부"로 읽힌다.

→ 500행씩 **페이지를 돌려 전량**을 모은다(순차 조회 — 병렬로 열면 커넥션을 그만큼 동시 점유).
하드 상한 20000 을 넘으면 성공 대신 `BadRequestException` 으로 **명시적 실패**한다.

★ 근거 대조 (memory: "CODEX 지적도 근거까지 대조하라"): 운영 실측 제품 수는
**최대 매장 128 / 전 매장 합 212**. 지금 터지는 문제는 아니고 **잠재 함정**이었다.
그래도 고친 이유는 "No silent caps" 가 이 프로젝트의 명시 규약이기 때문이다.

CODEX 가 확인해 준 것: Flutter 응답 계약 무파괴 / 함수 종속성 안전 / Excel·PDF 필터 일치 /
리다이렉트 루프 없음 / 삭제 잔여 참조 없음.

---

## 5. 검증

```
tsc(백엔드·프론트)      무에러
eslint(프론트 변경분)    exit 0
jest reports+products+stocks  183 green (신규 9건 포함)
운영 배포 번들          getItemsForExport 0건 / EXPORT_MAX_ROWS 존재 /
                       product-stock-summary 라우트 없음 / 기동 에러 0
운영 SQL                p.description 추가 쿼리 실제 GROUP BY 로 실행 확인
```

### ★ 덤 — 어제 고친 `Hoy +` 가 실전에서 검증됐다

오늘 매장 6 에 활동이 54행 있었다(사용자 테스트). 그중:

```
pb 343 (지점 16) SKU 251630001037043
  입고        +2065  type=NULL
  정정        −2045  type=adjust  note 'correccion ingreso 2026-08-08: 2065 -> 20'
  → v_product_branch_daily_ingreso.net = 20
```

**`Hoy +` 가 원입고 2065 가 아니라 정정 후 20 을 센다.** 73-NEXT-5 §1-bis 의 그 수정이다.
`source='manual_adjust'` 로 태깅된 Panel D 조정 행도 확인했다(§1-quinquies 의 그 경로).

---

## 6. 아직 브라우저 미검증 (사람이 해야 함)

1. **이번 작업**: `/reportes` 와 `/reportes/stocks` 를 주소창에 직접 쳐서 둘 다
   Cockpit 으로 가는지 (북마크·구 링크 회귀). 사이드바 Reportes 는 그대로인지.
2. **Excel**: Cockpit 상단 Excel 버튼이 보이는지 / 받은 파일의 Ingreso·Venta 가
   **화면 Panel B 와 같은지** (이번 통일의 요점).
3. **Flutter 관리자 앱** Reportes > Stocks: 같은 SKU 중복 카드가 사라졌는지 /
   `Vendidos` 가 줄었는지(예약·이동이 빠지므로).
4. 이월 (73-NEXT-5 §2): StockVistas 화면 렌더 / 다음 입고·판매 때 `Hoy +/−`,
   특히 **현지 21시 이후에도 오늘로 잡히는지**.

---

## 7. 다음 작업 — ~~그대로 남아 있다~~ → **§9 에서 완료**

- ~~**리포트를 `v_product_hijo` 위로 리팩터**~~ (`73-PROPOSAL-inventory-leaf.md` §11 끝).
  정확성이 아니라 **재발 방지**가 목적이다. 이번 작업으로 대상이 하나 줄었다
  (레거시 `getReportStockData` 가 사라져 `rowsJoin`/`productScope` 분기를 가진 곳은
  `reportsStocksCockpit.getItems` 하나다).
- **D (default variant 강제)** — 별도 phase (§10).

---

## 8. 이 코드베이스의 함정 (누적 — 73-NEXT-5 §3 의 10개에 더해)

11. **화면을 지우기 전에 리포 전체에서 엔드포인트를 grep 해라.** 이 리포에는 웹 말고도
    Flutter 앱이 둘 있고 같은 `/api/reports/*` 를 쓴다. "이 페이지의 백엔드"라는 말이
    성립하지 않는다. §2 에서 계획이 이걸로 뒤집혔다.
12. **PDF 용 상한을 전체 데이터 API 에 재사용하지 마라.** `getItemsForExport` 는 이름이
    범용처럼 보이지만 `PDF_MAX_ROWS+1` 이 박혀 있다. 인쇄물은 잘라도 되지만 Excel·API 는 안 된다.
13. **`grep` 이 0건이면 `-a` 를 의심해라.** 이 리포의 일부 소스를 `file` 이 `data` 로 판정해
    grep 이 조용히 아무것도 안 내놓는다.
14. **"이 숫자가 이상하다"를 정의 문제로 단정하지 마라.** 이번 8행은 분해해 보니 데이터가
    맞았고(`allowSaleWithoutStock=true`), 정의 문제는 **그 8행이 아닌 다른 176행**에 있었다.

---

## 9. [2026-08-08 오후] 리포트를 `v_product_hijo` 위로 — 완료 (api #646)

§7 에 "다음 작업"으로 적어둔 그것이다. 목적은 정확성이 아니라 **재발 방지**였고, 그건 지켰다
(값 차이 0). 대신 **행이 늘어난다** — 사용자 승인 후 진행했다.

### 9-A. 무엇이 바뀌었나

종전 `getItems` 는 **다섯 곳이 각자 모집단을 정의**했다:
`rowsJoin` / `countJoin` / `childStatusFilter` / `productScope`(MOV±) / `pbScope`(Ingreso).
두 뷰는 FROM/JOIN 구조 자체가 달랐다. 그 불일치가 §1 의 ±40 버그였다.

이제 거래 가능 단위는 `v_product_hijo` 하나가 정의하고 **그룹 키만** 다르다:

```
variante  : h.hijo_id        cod.madre : h.family_id (= COALESCE(parent_id, id))
```

MOV±·Ingreso 도 같은 키로 같은 집합(`groupLeafIds`)을 읽는다 —
**"같아야 한다" 가 규약이 아니라 구조가 됐다.**

`v_product_hijo` 는 `NOT EXISTS` 를 품고 있어 상관 서브쿼리에서 행마다 재평가되면 비싸다
(cod.madre 11→22ms). `MATERIALIZED CTE` 로 한 번만 만들어 공유한다 — 정의는 여전히 뷰 한 곳이다.

`getMatrix`(Panel C)도 `p.parent_id` → `h.family_id`. 안 그러면 아래 새 행을 클릭했을 때
빈 매트릭스가 뜬다(죽은 행).

### 9-B. 행 집합 변화 — 단품이 cod.madre 에 나타난다

| 뷰 | 변화 |
|---|---|
| variante | 전 매장 **완전 동일** |
| cod.madre | **단품 6행 추가** (매장 6 +1, 8 +4, 9 +1). 사라지는 행 0 |

자식이 없는 제품은 자기 자신이 family 이므로 이제 이 뷰에도 나온다. 종전에는 `is_parent=true`
조건 때문에 통째로 빠져 합계가 실제보다 작았다 — **매장 8 은 5개 family 중 1개만 보고 있었다.**

추가되는 행: `251532001` JEAN 2 FLORES(6) / `25092026002023017` 외 CAMPERA ESTAMPADA 4종(8) /
`25193444001` RIBBON(9).

### 9-C. ★ CODEX [CRITICAL] — 리팩터의 전제가 실은 안 지켜지고 있었다

`COALESCE(parent_id, id)` 는 깊이 1 에서만 안전하고, 그건 어제 배포한
`trg_products_family_depth` 가 보장한다고 적어뒀다. **그 트리거가 `NEW.parent_id` 가 가리키는
부모만 봤다.** 로컬에서 두 경로가 실제로 통과하는 것을 재현했다:

```
① 자식 B 를 가진 A 에 UPDATE products SET parent_id = C WHERE id = A
   → C → A → B 깊이 2. B 의 family 는 A, A 의 family 는 C 로 갈라진다.
     게다가 A 도 C 도 v_product_hijo 에 안 나와 두 제품이 리포트에서 통째로 사라진다.
② 자식 B 를 가진 루트 A 에 UPDATE products SET store_id = 9 WHERE id = A
   → 부모 store 9 / 자식 store 6 크로스 매장.
```

동시성 구멍도 있었다 — 두 트랜잭션이 각자 `A.parent_id=B` / `B.parent_id=A` 를 쓰면 서로의
미커밋 변경을 못 봐 **순환**이 생긴다. 행 잠금은 잠그는 대상이 서로 달라 못 막는다.

수정(`2026-08-08-product-family-invariants-fix.sql`, **양쪽 DB 적용 완료**, prosrc md5 일치):
- ① 자식이 있는 행은 부모를 가질 수 없다 (재부착 경로 차단)
- ② 자식이 있는 행의 `store_id` 변경 차단
- 매장 단위 `pg_advisory_xact_lock` 으로 family 구조 변경 직렬화
- 탐지기 `v_product_family_violation` (항상 0행). 운영 기존 위반 **0건** → 데이터 보정 불필요

★ 근거 대조: CODEX 는 [HIGH] 로 "단품이 자식을 얻으면 **기존 거래 원장이 탈락**한다" 고 했다.
**절반만 맞다.** `productStock.service.ts:246` 의 전환 가드가 **잔량 ≠ 0 이면 자식 생성을 거부**한다
(api #639). 그래서 Stock 은 안 새고, 새는 것은 **과거 이력(Ingreso/Venta/MOV)** 뿐이다.
"10개 입고 → 10개 판매 → 잔량 0" 인 단품이 자식을 얻으면 그 10/10 이 화면에서 사라진다.

### 9-D. 검증 (전부 운영 읽기 전용)

옛/새 **실제 생성 SQL 을 각각 덤프**해 대조했다 — 손으로 쓴 쿼리로 하면 검증이 아니다(§8-10).

```
전 매장 × {variante, cod.madre} × {전 지점, 지점별} = 22조합 FULL OUTER JOIN
  사라진 행 0 / 값 차이 0   (13개 컬럼: r_stock t_ingreso t_venta reservados
                            stock_offset h_ingreso h_venta mov_in mov_out
                            fallados ratio u_fecha producidos)
  추가된 행 = 단품 6 (승인됨)
항등식 Stock = Ingreso + Offset − Venta + MOV+ − MOV− − Reservado
  → 22조합 전부 위반 0 (추가된 단품 행 포함)
getMatrix    잃는 셀 0 / 새 셀 6 (그 단품들, 각 1칸)
성능(pageSize 50, store 6)  variante 25.8→30.5ms / cod.madre 15.9→21ms
테스트 186 green
```

---

## 10. 남은 것 (우선순위 순)

1. **D phase** — Part 1 배포 완료, **Part 2 는 브랜치에 보류**. §16 참조.
2. **비활성 부모 + 활성 자식** (CODEX [MEDIUM]). 지금은 `p.status != 'deactivated'` 로
   family 전체가 cod.madre 에서 사라진다(종전 동작 유지). variante 에는 그 자식들이 계속 뜬다.
   **운영 실측 0건.** 현재 동작은 `[의도된 한계]` 테스트가 고정하고 있다.
3. ~~**Panel A 는 아직 자기 모집단을 쓴다**~~ → **완료 (api #648). §14 참조.**
4. **단품 → family 전환 시 과거 이력** (CODEX [HIGH], §9-C). 잔량은 앱 가드가 막지만
   과거 Ingreso/Venta/MOV 는 전환 순간 화면에서 사라진다.
   **운영 실측 해당 0건** — 단품 16개 중 이력 없음 10 / 잔량이 있어 가드가 막음 6 /
   **잔량 0 + 이력 있음 0**. 발생하려면 "입고 → 전량 판매 → 그 뒤 variant 추가" 순서가 필요하다.
   지금 동작은 `[알려진 결함]` 테스트가 고정하고 있다. → 1번(D)에서 같이 결정한다.
5. Flutter 관리자 앱 Reportes > Stocks 사람 확인 (§6-3).

~~PG 통합 테스트가 없다~~ → **완료 (api #647). §11 참조.**

---

## 11. [2026-08-08] PG 통합 테스트 — 완료 (api #647)

`test/family/` 19건. 실 PostgreSQL 대상, 전부 `BEGIN … ROLLBACK`(커밋 없음).
운영 DSN(`:5434`/`coolsistema.com`/`62.72.7.245`)이면 **모듈 로드 시점에 던진다.**

```bash
npm run test:family
```

| 파일 | 내용 |
|---|---|
| `invariants.family-spec.ts` | 트리거·CHECK·뷰 10건. 동시 A↔B 재부모화 포함 |
| `reports-population.family-spec.ts` | `getItems` 의 **실제 생성 SQL** 을 실 PG 에 던진다, 9건 |
| `helpers/db.ts` | 트랜잭션 래퍼 · `:name` 바인딩 · 픽스처(매장부터 새로 만든다) |

`reports-population` 은 서비스에 `tx.sequelize` 표면을 주입해 생성 SQL 그대로 실행한다 —
손으로 다시 쓴 쿼리로 검증하면 검증이 아니다(§8 함정 10).

### ★ 변이 검사로 실효성을 확인했다

**통과만으로는 증거가 아니다.** 두 방향으로 일부러 깨뜨려 봤다:

| 변이 | 결과 |
|---|---|
| `groupLeafIds` 의 키를 `hijo_id` 로 고정 (모집단 불일치 재도입) | reports **3건 실패** |
| 트리거를 `-fix` 이전 버전으로 되돌림 | invariants **④⑤⑩ 정확히 3건 실패** |

둘 다 원복 후 19/19 green. 로컬 DB 잔여물 0 확인.

### 함정

- **cold start 에 메모리를 많이 쓴다.** 기본 힙으로는 OOM 한다. `npm run test:family` 가
  `--max-old-space-size=6144 --runInBand` 를 이미 넣는다. 캐시가 따뜻해지면 가벼워진다.
  (기존 `test:tenant` 가 멀쩡히 도는 이유는 캐시가 이미 있어서였다 — 새 설정은 전부 이 벽을 만난다.)
- `stores.owner_group_id` 는 NOT NULL 인데 **`owner_groups` 테이블이 없다**(FK 도 없다).
  픽스처는 `MAX(owner_group_id)+1` 을 쓴다.
- 기본 `npm test`(`src/**/*.spec.ts`)에는 안 들어간다 — DB 없는 CI 를 깨지 않는다.

---

## 12. D phase 착수 전 결정사항 (사용자 제안에 대한 검토)

제안: "단품에 스톡이 있으면 Color Único hijo 를 만들어 그 스톡을 거기 할당한다."
방향은 맞다. 그런데 **원장 회계** 두 가지를 먼저 정해야 한다.

### 13-A. 받는 행을 어느 컬럼이 흡수하나 — 항등식이 걸린다

`Stock = Ingreso + Offset − Venta + MOV+ − MOV− − Reservado`

| 이관 행의 형태 | 결과 |
|---|---|
| `type=NULL` 양수 | Ingreso 로 잡힘 → **전환일에 `Hoy +` 가 튄다**(실입고 0인데 화면엔 입고) |
| `type='adjust'` + `source='migration_transfer'` | Ingreso 도 Offset 도 아님 → **항등식이 깨진다** |

73-PROPOSAL §12 중립화 때는 받는 쪽이 **아무도 안 읽는 madre PB** 라 이 문제가 없었다. 이번엔 받는 쪽을
리포트가 읽는다. → **항을 하나 만들어야 한다**(예: `Traspaso`). 제안서 「남은 한계」의
`production`/`writeoff` 구멍도 같은 종류이니 같이 닫는 게 낫다.

### 13-B. 음수 잔량

지금 막혀 있는 6건 중 **2건이 음수**다:

```
JEAN 2 FLORES (매장 6, 지점 6)   −35   원장 15행
RIBBON        (매장 9, 지점 14)  −10   원장  1행
```

Color Único 를 만들어 −35 를 넘기면 **새 SKU 가 태어나자마자 −35** 다. `allowSaleWithoutStock=true`
라 시스템상 합법이지만 사람 눈에는 사고로 보인다. 음수면 전환 전에 Panel D 실사 보정을
요구하는 편이 맞다고 본다.

### 13-C. ★ 6건 중 4건은 이 처방이 안 맞는다

```
매장 8   25092026002023017  CAMPERA ESTAMPADA (rojo / 36)    10
         25092026002023018  CAMPERA ESTAMPADA (verde / 36)   10
         25092026002024017  CAMPERA ESTAMPADA (rojo / 38)    10
         25092026002024018  CAMPERA ESTAMPADA (verde / 38)   10
```

이름에 이미 색상·사이즈가 있다 — **부모를 잃은 고아 variant** 다. 여기에 "Color Único"
자식을 붙이면 `CAMPERA ESTAMPADA (rojo / 36)` 밑에 `Color Único` 가 생긴다. 의미가 틀렸다.
올바른 처리는 진짜 madre 를 만들어 **그 밑으로 묶는 것**이고, 그건 재부모화 —
**지금 앱에 없는 경로**다(`parent_id` 는 variant 신규 생성 시에만 설정된다).

### 13-D. 정리

D phase 범위 = ① `Traspaso` 항 추가 ② 전환 트랜잭션(default hijo + 지점별 PB + 짝 보정행,
`allow_madre_stock` 우회, `source='migration_transfer'`) ③ 음수 잔량 정책
④ 고아 variant 재부모화 경로(별개 문제, 매장 8 의 4건).

---

## 13. 함정 추가 (§8 에 이어)

15. **`v_product_hijo` 같은 뷰를 상관 서브쿼리 안에서 쓰면 행마다 재평가된다.**
    `NOT EXISTS` 를 품은 뷰는 특히 비싸다. `MATERIALIZED CTE` 로 한 번만 만들어 공유해라 —
    단일 출처는 유지되고 비용만 사라진다.
16. **SQL 주석에 백틱을 쓰지 마라.** 이 코드베이스의 SQL 은 전부 템플릿 리터럴 안에 있어서
    주석 속 `` ` `` 가 문자열을 끊는다. tsc 가 엉뚱한 줄을 가리켜 원인을 찾기 어렵다.
17. **"제약이 보장한다" 를 적기 전에 그 제약을 실제로 깨 봐라.** §9-C 가 그 사례다.
    어제 내가 "깊이 1 은 트리거가 보장한다" 고 적었는데, 그 트리거는 한 방향만 봤다.
    로컬 트랜잭션 + ROLLBACK 이면 3분이면 확인된다.
18. **새 jest 설정은 cold start 에서 OOM 한다.** 기존 `test:tenant` 가 멀쩡히 도는 건
    캐시가 이미 있어서다. 새 설정을 만들면 `--max-old-space-size` 를 크게 주고
    `--runInBand` 로 시작해라. 이 벽에 20분을 썼는데 원인은 내 코드가 아니었다.
19. **테스트가 통과하는 것은 증거가 아니다 — 일부러 깨뜨려 봐라.** §11 의 변이 검사가
    없었으면 "19건 green" 이 무엇을 지키는지 말할 수 없었다. 회귀 테스트를 새로 쓰면
    그 회귀를 재현해 실패시키는 것까지가 한 세트다.

---

## 14. [2026-08-08] Panel A 모집단 단일화 — 완료 (api #648)

§10-3 항목. 값은 안 바뀐다(92조합 대조) — **재발 방지**가 목적이다.

### 14-A. 무엇이 문제였나

같은 화면의 Panel A(지점 요약·KPI)와 Panel B(제품 목록)가 모집단을 각자 정의했다:

```
Panel A : p.is_parent = false + p.status != 'deactivated'
          cod.madre 카운트는 COALESCE(p.parent_id, p.id) 를 **인라인으로 복제**
Panel B : v_product_hijo + family_id
```

값은 실측상 맞았지만 **실제로 어긋난 적이 있다** — Panel A 는 단품을 family 로 셌고
Panel B 는 `is_parent=true` 조건 때문에 단품을 통째로 안 보여줬다(§9 에서 닫았다).

### 14-B. 무엇을 했나

`LEAF_CTE` 를 클래스 상수로 올려 **getCockpit(summary/category/alert) · getStocks ·
getBranches · getItems · getMatrix** 가 전부 그것 하나를 읽게 했다.
리포트에서 `is_parent` 모집단 분기는 사라졌다(남은 것은 STOCKS-VENTA-DEBUG 진단 쿼리뿐).

### 14-C. ★ CODEX 지적 — 두 건은 맞았고, 한 건은 **틀렸다**

| 지적 | 판정 |
|---|---|
| [HIGH] `br.is_active` 를 `getBranches` 에서만 건다 → 비활성 지점 재고가 Panel B·KPI 엔 있고 Panel A 엔 없다 | **맞다.** 운영 비활성 지점 0건이지만 구조적 구멍. `BRANCH_JOIN` 공통 조각으로 전 Panel 적용 |
| [MEDIUM] cod.madre 카운트가 대표-제품 status 정책을 안 따른다 | **맞다.** `FILTER (WHERE fam.status <> 'deactivated')` 로 `getItems` 와 통일 |
| [MEDIUM] "KPI 합계" 테스트가 summary 대신 categories(LIMIT 10)를 본다 | **맞다.** 두 테스트로 분리 |
| [MEDIUM] "`ProductBranch` 에 매장 일치 제약이 없다" | ★ **틀렸다 — 아래** |

**증거 (교차 매장 PB 는 DB 가 이미 거부한다):**

```
① 트리거   trg_tenant_productbranch_store      [INSERT]
           trg_tenant_productbranch_store_upd  [UPDATE]
             → tenant_chk_productbranch_same_store()
② 함수 본문  IF v_prod_store <> v_branch_store THEN RAISE EXCEPTION 'TENANT_CROSS_STORE: ...'
③ 양쪽 DB  prosrc md5 = e5cc74d20adb64c7f840d2056235df08 (로컬 5432 = 운영 5434)
④ 실제 거부  ERROR: TENANT_CROSS_STORE: "ProductBranch".product_id=1085 (store 355)
                    가 branch_id=678 (store 356) 와 다른 매장입니다
⑤ 출처     api-ventago/migrations/2026-07-30-tenant-crossstore-triggers.sql
```

CODEX 는 **Sequelize 모델 파일만** 봤다. 모델에 제약이 없다는 말은 맞지만, 제약은
DB 트리거로 존재한다. 그래서 "교차 매장 PB 가 생기면…" 이라는 전제 자체가 성립하지 않는다.
테스트도 "리포트가 거른다" 가 아니라 **"DB 가 거부한다"** 로 고쳐 썼다.

★ 교훈: 외부 리뷰가 "제약이 없다" 고 하면 **모델이 아니라 DB 를 보고 확인해라.**
이 리포는 불변식을 상당 부분 트리거로 들고 있어서, 코드만 읽으면 항상 "없다" 로 보인다.

### 14-D. 부수 — 동률 tiebreaker

`alert`/`category`/`getStocks`/`getItems` 의 `ORDER BY` 에 결정적 키를 붙였다.
`getStocks`·`getItems` 는 **OFFSET 페이징**이라 불안정 정렬이면 페이지 경계에서 행이
겹치거나 샌다. 실제로 old↔new 비교에서 옛 alert 쿼리가 동률에서 매번 다른 행을 골랐다.

### 14-E. 검증

```
옛/새 실제 생성 SQL 8종 × 전 매장 × 지점스코프 = 92조합 EXCEPT ALL 양방향
  90조합 완전 일치
  나머지 2건(alert)은 옛 쿼리의 비결정적 동률 선택 → LIMIT 제거 후보집합 비교에서 차이 0
통합 테스트 29건 (panel-consistency 10건 신규)
변이 검사  skuCountExpr 을 leaf 단위로 → 1건 실패 / tiebreaker 제거 → 1건 실패
유닛 186 green / 배포 번들 is_parent 모집단 0건 / 기동 에러 0
```

★ **처음 쓴 3개 테스트가 공허하게 통과했다.** `branches.is_active` 에 기본값이 없어
픽스처의 지점이 NULL 이었고, Panel A 가 `is_active = true` 로 걸러 배열이 비었다 →
`for (const br of a.branches)` 가 한 번도 안 돌았다. `toHaveLength(2)` 가드로 막았다.
**루프로 검증하는 테스트는 루프가 돈다는 것부터 못박아야 한다.**

---

## 15. 함정 추가 (§13 에 이어)

20. **외부 리뷰가 "DB 제약이 없다" 고 하면 DB 를 직접 확인해라.** 이 리포는 불변식을
    상당 부분 트리거로 들고 있다(`tenant_chk_productbranch_same_store`,
    `trg_stocks_leaf_only`, `trg_stocks_immutable`, `products_family_depth_guard`).
    Sequelize 모델만 읽으면 전부 "없다" 로 보인다. §14-C 가 그 사례다.
21. **루프로 검증하는 테스트는 루프가 돈다는 것부터 못박아라.** 빈 배열이면 조용히 통과한다.
    §14-E 에서 3건이 그렇게 통과하고 있었다.
22. **`branches.is_active` 는 기본값이 없다(NULL 허용).** 지점을 만드는 픽스처·마이그레이션은
    명시해야 한다. 안 하면 Panel A 가 그 지점을 통째로 버린다.

---

## 16. [2026-08-08] D phase — Part 1 배포 / Part 2 보류

### 16-A. Part 1 — `Traspaso` 항 (api #649 / front #577, **배포됨**)

전환의 **전제조건**이다. 원장이 immutable 이라 "옮긴다" = 짝 보정행 두 개를 append 하는
것인데, 그 행들이 어느 컬럼에도 안 잡혔다:

| 후보 | 왜 안 되나 |
|---|---|
| Ingreso | 물리적 입고가 아니다 — 넣으면 **전환일에 `Hoy +` 가 튄다** |
| Venta | 판매가 아니다 |
| Offset | "Offset 은 100% 사람이 실사로 넣은 값" (사용자 규칙) |

→ 자기 항을 만들었다:

```
Stock = Ingreso + Offset + Traspaso − Venta + MOV+ − MOV− − Reservado
```

`MIGRATION_TRANSFER_SOURCE` 상수 · getItems 컬럼 · 정렬 화이트리스트 · PDF · Panel B 컬럼.

★ **오늘 데이터 무영향 확인**: 운영의 `migration_transfer` 5행은 전부 non-leaf PB 라
리포트가 안 읽는다(§12 중립화 때 madre PB 에 넣은 것). 전 매장 22조합 실측 —
`traspaso` 전부 0, 항등식 위반 0. 통합 31건(이관 시나리오 2건 신규),
변이(traspaso 를 0 고정) → 2건 실패로 실효성 확인.

### 16-B. Part 2 — 전환 트랜잭션 (**브랜치 `feat/73-d-default-variant-transfer`, 미배포**)

`transferBalanceToDefaultVariant()` — 한 트랜잭션:

1. 부모 행 `FOR UPDATE` (동시 전환 직렬화)
2. 지점별 잔량 집계 — **음수가 하나라도 있으면 거부**(실사 먼저)
3. `SET LOCAL ventago.allow_madre_stock='on'` (자식이 생기면 부모 PB 가 non-leaf)
4. Color Único / Talle Única `findOrCreate` → default variant
   (SKU = `parent.sku + '-V'` — **기존 배치 로직과 같은 규약**. 이미 있으면 재사용)
5. `isParent=true` 를 원장 이동과 **같은 트랜잭션에서**
6. 지점별 짝 보정행 (−N / +N, `source='migration_transfer'`)

유닛 40 green.

### 16-C. ★ 왜 배포하지 않았나

**서비스 → 실 DB 종단 테스트가 없다.** `test/family` 하네스는 raw pg 라 Sequelize 모델을
쓰는 서비스를 그대로 못 태운다. 지금 검증된 것은 ① 서비스 분기(유닛) ② 이관 원장이
**이미 있을 때** 리포트가 Traspaso 로 잡고 항등식이 닫히는 것(통합) 두 가지뿐이고,
**서비스가 그 원장을 올바르게 쓰는지**는 검증되지 않았다.

원장에 쓰는 경로를 종단 검증 없이 배포하지 않는다. 배포 전 할 일:

1. `test/family/helpers` 에 최소 Sequelize 인스턴스(Product/Stocks/Price)를 붙여
   `ProductStockService` 를 실제로 태우는 e2e 추가. 검증 항목:
   - 지점별 짝 보정행이 정확히 −N/+N 인가 (합 0)
   - default variant SKU/이름/color/size 가 규약대로인가
   - 음수 잔량이면 거부되고 **아무것도 안 남는가**(롤백)
   - 전환 후 리포트: family 합계 불변 · Traspaso 가 그만큼 · 항등식 0
   - 같은 부모에 두 번 태워도 SKU 충돌·이중 이관이 없는가
2. CODEX 자문
3. 운영 대상 6건 중 **4건(매장 8 CAMPERA)은 이 처방이 안 맞는다** — 고아 variant 라
   재부모화가 맞다(§12-C). 배포해도 그 4건은 안 풀린다는 것을 알고 있어야 한다.

---

## 17. 함정 추가 (§15 에 이어)

23. **`stocks.source` 는 INSERT 시점에만 넣을 수 있다.** `trg_stocks_immutable` 이 UPDATE 를
    막는다(맞는 동작). 테스트 픽스처도 INSERT 로 넣어야 한다.
24. **테스트의 UPDATE 에 스코프를 빠뜨리지 마라.** `UPDATE stocks SET ... WHERE stock = 3`
    을 썼다가 로컬 실데이터의 id=13 을 건드릴 뻔했다. 트리거가 막았고 롤백됐지만,
    막아준 게 트리거였다는 게 문제다.
