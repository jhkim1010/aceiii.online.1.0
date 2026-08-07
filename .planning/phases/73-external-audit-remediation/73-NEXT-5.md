# 73 후속 5 — 재고 Cockpit 매트릭스의 지점 스코프 (새 세션용)

앞선 문서: `73-NEXT.md` ~ `73-NEXT-4.md`. 이 문서는 **2026-08-07 오후** 작업분.

---

## 0. 먼저 읽을 것

- jest: `NODE_OPTIONS=--max-old-space-size=2048 npx jest --maxWorkers=1 --workerIdleMemoryLimit=800MB`
- 마이그레이션은 로컬 5432 + 운영 5434 **양쪽** 적용. (이번 작업엔 마이그레이션 없음 — 코드만.)
- **CODEX 자문은 상시 절차다.** 이번에도 실제 결함을 하나 잡아냈다(§1-D).
  ★ **CODEX 에 `git diff` 를 시키지 마라.** 리포 루트에서 `git diff -- api-ventago/...` 는
    아무것도 안 나온다 — `api-ventago`/`ventago-app` 은 **gitlink(중첩 리포)** 라 루트 diff 에
    파일 단위 변경이 안 잡힌다. 각 리포에서 diff 를 떠서 **프롬프트에 인라인**으로 넣어라.
    (이걸 몰라서 CODEX 세션 두 개를 20분 넘게 헛돌렸다.)
  ★ `codex exec ... | tail -N` 로 파이프하면 **끝날 때까지 출력이 하나도 안 보인다.**
    파일로 리다이렉트하고 중간에 읽어라.
- **Jenkins 빌드 번호는 `nextBuildNumber - 1` 이 "이전 빌드"가 아니다.** push 직후엔 이미
  내 빌드가 번호를 받아 돌고 있다. 번호로 추측하지 말고 **로그에서 커밋 SHA 를 grep** 해라
  (`grep -l <sha> /var/lib/jenkins/jobs/<job>/builds/*/log`). 나는 이걸 착각해서
  "오지 않을 다음 빌드"를 10분 기다렸다 — 감시 루프가 **부재에서 침묵**하는 그 유형이다.

---

## 1. 이번에 고친 것 — 통합 보기에서 매트릭스가 한 지점만 보여주던 문제

배포: **api #635 / front #574** 둘 다 SUCCESS + 컨테이너 재생성 + 배포 번들에 코드 존재 확인.

### 1-A. 화면 지도 (다음 사람이 헤매지 않도록)

"통합 view 의 우측 상세 패널" = `reportes` > **Stocks Cockpit**.
`ventago-app/src/views/reports/stocks/StocksCockpitBody.tsx` 가 4패널 레이아웃을 조립한다.

```
┌───────────────────────────────────────┐
│ Panel A  지점 요약 (클릭 = 지점 선택,  │  selectedBranchId = null 이 "통합/전체"
│          '전체' 행 클릭 = null)        │
├──────────────────────┬────────────────┤
│                      │ Panel C  ←★    │  선택 제품의 색상×talle 매트릭스
│  Panel B  제품 목록   ├────────────────┤  GET /reports/stocks-cockpit/matrix
│  (Hoy+/Hoy− 컬럼)     │ Panel D        │  선택 셀 수동 재고 조정
│  GET .../items       │                │  POST /reports/stocks-cockpit/adjust
└──────────────────────┴────────────────┘
```

### 1-B. 진단 — SQL 이 아니라 JS 였다

`api-ventago/src/app/reports/reportsStocksCockpit.service.ts` `getMatrix()`:
SQL 의 `GROUP BY` 에 `pb.id` 가 있어 **(variant, product_branch) 당 1행**이 나온다.
`branchId=null` 이면 한 셀에 지점 수만큼 행이 온다. 그런데 매트릭스 빌드 루프가
`matrix[color][talle] = {...}` 로 **덮어써서** 마지막 행 하나만 남았다.

같은 화면의 Panel B(`getItems`)는 `GROUP BY p.id, ...` 라 pb 가 없어 **전 지점을 합산**한다.
그래서 위아래가 서로 다른 값을 말하고 있었다.

**운영 실측 (제품 262 = SKU 2545001 `[ACCESORIOS] COLLAR`, store 6):**

| | stock | h_ingreso |
|---|---|---|
| coolsistema (pb 212) | 3 | 130 |
| HELGUERA (pb 293) | 77 | 30 |
| **Panel B (합산)** | **80** | **160** |
| Panel C (수정 전, 마지막 행) | 77 | 30 |
| **Panel C (수정 후)** | **80** | **160** |

★ 73-NEXT-4 의 추정 두 개가 틀렸다:
- "우측 상세" 는 Historial drawer 가 아니라 Panel C 다.
- 30 은 "net 대신 ingreso 를 보여줘서"가 아니라 **한 지점 값이라서** 30 이었다.
  정정(`correccion ingreso%`)은 `type='adjust'` 라 `STOCK_FLOW_EXCLUDE_SQL` 에 걸려
  Hoy+ 집계에서 **애초에 제외**된다 — Panel B 도 마찬가지다.

### 1-C. ★ 표시 결함을 쓰기 결함으로 바꿀 뻔한 지점

`adjustStock` 은 `theoretical` 을 **그 pb 하나의** `SUM(stocks)` 로 **다시 계산**한다.
Panel D 가 화면에 보여주는 `Teórico` 는 프론트의 셀 값이다.

지금(수정 전)은 셀이 한 지점 값만 보여줘서 **우연히 자기일관적**이었다.
표시만 합산으로 고치고 `productBranchId` 를 그대로 뒀다면 —
사용자가 전 지점 합계(80)를 보고 "실제 재고 80" 을 입력 → 백엔드는 HELGUERA 기준(77)으로
diff 를 계산 → **+3 이 HELGUERA 한 지점에 들어간다.** 조용히 틀리는 쓰기다.

그래서 **기여 행이 딱 하나일 때만** `productBranchId` 를 확정하고, 그 외에는 `0`(조정 불가)으로
내보낸다. Panel D 는 그런 셀에 **저장 폼을 아예 내주지 않는다.**

### 1-D. CODEX 교정

> `branchCount = byBranch.length` 는 지점 수가 아니라 **행 수**다. 같은 지점의 중복 PB 행이
> "2개 지점"으로 둔갑한다.

맞는 지적이다. 세는 대상이 다르다 → `distinct branchId` 로 분리했다.
다만 **조정 대상 유일성은 여전히 행 수로 판정**한다 — 지점이 하나여도 PB 행이 둘이면
대상은 정해지지 않기 때문이다.

★ 근거 대조 (memory: "CODEX 지적도 근거까지 대조하라"): 운영 실측 결과
`(product_id, branch_id)` 중복 PB **0건**, 같은 부모 안 `(color_id, size_id)` 중복 활성 variant
**0건**. 즉 **지금은 재현되지 않는다** — 세는 값이 애초에 다르므로 넣은 방어다.

CODEX 의 **배포 순서** 조언도 채택했다: **백엔드 먼저**.
구 프론트 + 신 백엔드 = 다중 지점 셀이 빈 셀로 보여 기능만 일시 저하되고 **쓰기는 막힌다**(fail-closed).
반대 순서는 조정 폼이 열린 채로 남는다. (내 최초 판단은 프론트 먼저였다 — 틀렸다.)

### 1-E. 바뀐 파일

| 파일 | 내용 |
|---|---|
| `api-ventago/.../reportsStocksCockpit.service.ts` | `getMatrix` 합산 + `branchCount`/`byBranch`/`branches` |
| `api-ventago/.../reportsStocksCockpit.matrix.spec.ts` | 신규. 회귀 5건 |
| `ventago-app/.../panels/PanelC_ColorMatrix.tsx` | 빈 셀 판정 교체 + 스코프 칩 + 지점별 툴팁 |
| `ventago-app/.../panels/PanelD_StockAdjust.tsx` | 다중 지점 셀 쓰기 차단 + 초기화 키 보정 |

프론트에는 **구 백엔드 폴백**이 있다(`branchCount` 없으면 `productBranchId > 0 ? 1 : 0`).
백엔드가 안정되면 걷어내도 된다 — 다만 급하지 않다.

★ 참고: `ProductBranch_product_id_branch_id_key` 가 `(product_id, branch_id)` UNIQUE 다.
즉 "같은 지점에 PB 행 둘" 은 **제약으로 불가능**하다 — 데이터에 없는 게 아니라 만들 수 없다.
그래도 `branchCount`(distinct 지점)와 조정 대상 유일성(행 수)을 분리해 둔 건, 세는 대상이
애초에 다르기 때문이다.

---

## 1-bis. 'Hoy +' 정의를 정본 뷰 net 으로 (api #636)

사용자 요청: **"adjust 행이 오늘 합계에 포함되게 고쳐줘."**

### 무엇이 문제였나

Cockpit 의 `Hoy +` 는 stocks 를 직접 세면서 `STOCK_FLOW_EXCLUDE_SQL` 로 `type='adjust'` 를
통째로 뺐다. 정정 행은 `type='adjust'` + `note 'correccion ingreso%'` 라 전부 걸러졌다 →
그날 입고를 3→1 로 정정해도 화면은 3 을 계속 보여준다.

**더 나쁜 건, 같은 데이터를 읽는 StockVistas 리포트는 이미 정정을 반영하고 있었다**
(`v_stock_sucursal_variante` → `v_stock_dia.ingreso_neto` → 정본 뷰 `net`).
두 리포트가 같은 날 같은 제품에 다른 값을 말하고 있었다:

| COLLAR (262), 2026-08-07 | coolsistema | HELGUERA | 합 |
|---|---|---|---|
| StockVistas `Ingreso hoy` | 33 | 77 | 110 |
| Cockpit `Hoy +` (수정 전) | 130 | 30 | 160 |
| **Cockpit `Hoy +` (수정 후)** | **33** | **77** | **110** |

### 결정 (사용자 선택)

`Hoy +` = `v_product_branch_daily_ingreso.net`
= `ingreso` − `anulacion ingreso%` + `correccion ingreso%`, **`operation_date` 기준**.

전체 `type='adjust'` 를 더하지 **않는다**. 마이그레이션 주석 그대로 — `ajuste manual`·
code-import 보정은 "그날 재고 변화"이지 "그날 입고량의 수정"이 아니다.
(실측: 전체 adjust 62행 중 화이트리스트 밖은 7행 — `correccion duplicados` 4, 수기 3.)

### ★ 남은 비대칭 — 다음 사람이 알아야 할 것

**`Hoy −`(h_venta)는 일부러 안 고쳤다.** 정본의 `venta` 는 `type='sale'` 만 세는데
**POS 판매 차감은 `type=NULL` 음수**라(§5), 그대로 가져오면 POS 판매가 통째로 사라진다.

그 결과 **`Hoy +` 는 `operation_date`, `Hoy −` 는 `created_at`** 기준이 됐다.
자정·백데이트 경계에서 둘이 **다른 영업일**을 가리킬 수 있다(CODEX 지적).
실측: 최근 30일 `type=NULL` 음수 283행 중 **53행(19%)** 이 `operation_date ≠ created_at::date`.
→ 후속 통일 대상. 통일하려면 §5 의 "type 라벨링 분기" 를 먼저 정리해야 한다.

### 구현 주의

**LEFT JOIN 이 아니라 correlated subquery 다.** 메인 쿼리가 `stocks` 를 LEFT JOIN 해
pb 당 행이 부풀어 있어서, 뷰를 join 하면 같은 `net` 이 그 수만큼 복제돼 이중 계상된다.
(`v_stock_dia` 마이그레이션에서 이미 한 번 밟은 함정이다.)

pb 스코프는 `rowsJoin` + `childStatusFilter` 와 **글자 단위로 같은 모집단**이어야 한다 —
다르면 같은 행의 `Stock` 과 `Hoy +` 가 서로 다른 모집단을 세게 된다.

### 검증 (전부 운영에서 읽기 전용 실행)

- Panel B 110 / Panel C 지점별 33·77 → StockVistas 와 일치. `r_stock` 80 불변(이중 계상 없음)
- variant 뷰 경로(`pbh.product_id = p.id`)도 110
- **실제 GROUP BY(`p.store_id` 없음)로 실행해 함수 종속성 통과 확인** — `p.id` 가 PK 라 유효.
  (내 첫 perf 테스트는 GROUP BY 에 `p.store_id` 를 넣어 이걸 못 잡을 뻔했다.)
- `EXPLAIN ANALYZE` 1.5~1.8ms (`h_ingreso` 정렬 포함). `idx_stocks_pb_opdate` /
  `idx_stocks_store_date` 가 오늘 행만 훑는다
- 테스트 10건 (matrix 6 + **getItems 4 — 종전에 커버가 없었다**)

프론트 변경 없음 — 라벨(`Hoy +` / `H+`)은 그대로 두고 값의 정의만 바꿨다.

---

## 1-quinquies. Offset 은 사람이 넣은 값만 (api #638)

사용자: **"수동으로 스톡을 조정한 적이 없는데 왜 Offset 에 값이 있나. 이 값은 시스템이
자동 계산해서는 안 되고 100% 인간이 조정해야 하는 값이다."**

맞는 지적이었다. 원장이 immutable(`trg_stocks_immutable`)이라 **시스템도** 정정을
`type='adjust'` 보정 행 추가로 기록한다. 종전 Offset 식은
`type='adjust' AND note !~ '^(movido|fallado)'` 라 그걸 통째로 담았다.

실측 — 전 기간 `adjust` 62행:

| note 접두어 | 행 | net | 누가 |
|---|---|---|---|
| `anulacion ingreso` | 28 | −578 | **시스템** (입고 취소) |
| `correccion ingreso` | 27 | −51 | **시스템** (수량 정정) |
| `correccion duplicados` | 4 | +336 | 사람 (1회성 수기) |
| (NULL) | 2 | 0 | 사람 (Panel D) |
| `1 para comandera de oficina` | 1 | −71 | 사람 (Panel D) |

**55/62 가 시스템 행.** 매장 6 의 Offset −209 는 전부 시스템이었다 → 수정 후 **0**.

### 수정 두 개는 한 쌍이다

1. **Offset** 에서 시스템 note 접두어를 전부 제외. 쓰기 경로를 전수 조사해 목록화
   (`stocks.model.ts` 의 `SYSTEM_ADJUST_NOTE_PREFIXES`).
   ★ CODEX 가 두 개를 더 찾아줬다 — `stocks.service.ts` 의 `'ajuste de mov#'`(이동 되돌리기),
     `code-import.service.ts` 의 `'import '`(목표 절대값 보정). **운영엔 0건이지만 열린 구멍**이었다.
   → 남는 것은 Panel D(사용자 메모 또는 NULL) 뿐 = 앱의 유일한 사람 경로.
2. 그 55행이 빠지면 항등식이 깨지므로 **Ingreso 가 흡수**한다.
   `Ingreso` = raw 양수 합 → **정본 뷰 net 의 전 기간 합**.
   사용자 정의("총 들어온 갯수")와도 맞다 — 취소·정정된 몫은 실제로 들어온 물량이 아니다.
   부수 효과: **`Hoy +` 가 곧 `Ingreso` 의 오늘치**가 된다(같은 식, 날짜 술어만 다름).

덤으로 `% Venta` 의 분모가 raw 양수 합을 **따로 인라인**하고 있어 Ingreso 와 어긋날 참이었다
→ 같은 식으로 통일.

### 검증

- 항등식 `Stock = Ingreso + Offset − Venta + MOV+ − MOV− − Reservado`
  → store 6 의 127개 제품 **위반 0건**
- Offset: store 6 −209 → **0** / store 9 −71 유지 / store 15 −84 → +336
- 예: `251529001` Ingreso 380→200, Offset −180→0, **Stock 179 불변**
- `EXPLAIN ANALYZE` 3.9ms. 테스트 27건(reports) + products 포함 166건 green

### ★ 남은 한계 (CODEX [HIGH] — 별도 판단 필요)

**note 는 약한 식별자다.** 사람이 우연히 같은 접두어로 메모를 쓰면 Offset 에서 빠지고,
새 시스템 경로가 접두어를 안 맞추면 다시 샌다.
근본 해법은 `stocks` 에 명시적 **`source` 컬럼**을 두는 것이다(스키마 변경).

**쓰기 경로를 추가할 때 `SYSTEM_ADJUST_NOTE_PREFIXES` 를 같이 늘려라.** 안 그러면 그 값이
조용히 "사람이 한 조정"으로 화면에 뜬다.

또한 `type='production'`/`'writeoff'` 행이 생기면 항등식에 해당 항이 없어 깨진다(운영 0건).

---

## 1-quater. 컬럼 의미 전수 대조 + 날짜 경계 수정 (api #637)

사용자: "지금 view 의 내용이 아주 이상해" + 각 컬럼의 의도된 의미를 명시.

### 산수는 맞았다

`Stock = Ingreso + Offset − Venta + MOV+ − MOV− − Reservado`
→ store 6 전 제품, **전 지점 합계와 지점별 양쪽 모두 위반 0건**. 컬럼 식은 정확했다.

컬럼 출처 지도 (다음 사람이 헷갈리지 않도록):

| 컬럼 | 출처 |
|---|---|
| Ingreso / Venta | `stocks` 양수/음수, `type` 이 `adjust·suspend·production·transfer·writeoff` 아닌 것 |
| Reservado | `stocks` `type='suspend'` 의 음수 합 |
| Offset | `stocks` `type='adjust'` 중 note 가 movido/fallado 아닌 것 |
| MOV± | **`sales`/`sale_items` 의 `activity_type='movido'`** — 유일하게 stocks 가 아니다 |
| Stock | `stocks` 전체 SUM (원장 그대로) |
| Hoy + | 정본 뷰 `v_product_branch_daily_ingreso.net` |
| Hoy − | `stocks` 음수 (POS 는 `type=NULL`) |

★ movimiento 는 `stocks` 에 `type='transfer'` 로 기록된다(+43/−43, 매장 내 net 0).
  `type='adjust'` + note `^(movido|fallado)` 인 행은 **전 기간 0건**이다 — offset 식의 그 제외
  조건은 지금 아무 것도 안 거른다.

### 틀린 것은 날짜 경계였다

**DB TimeZone 이 `Etc/UTC`** 라 `created_at::date` 는 UTC 달력이다. 매장은 UTC−3 →
현지 21시 이후 영업이 UTC 로 이미 다음 날이다.

- `stocks` 1278행 중 **223행(17%)** 이 `created_at::date ≠ operation_date`
- 표본: `created_at 2026-08-07 01:02 UTC` / `operation_date 2026-08-06` (= 현지 8/6 21:02)
- **오늘 Hoy − 188 중 101(54%)이 어제(현지) 판매**였다. operation_date 기준은 87

수정: `h_venta` 의 날짜 술어를 `operation_date` 로, `u_fecha(Ú.Mov)` 를 `MAX(operation_date)` 로.
집계 대상은 안 건드렸다 — 정본 `v_stock_dia.venta` 는 `type='sale'` 만 세는데 POS 는 `type=NULL` 이다.

### ★ CODEX 가 잡은 것 — 내가 절반만 고쳤다

`operation_date` 로 옮기면서 **비교 대상은 `CURRENT_DATE`(UTC 달력)로 남겨뒀다.**
매장 기준 21시~자정에는 `CURRENT_DATE` 가 이미 내일 → 그 시간대 Hoy +/− 가 통째로 0.
실증: `TIMESTAMPTZ '2026-08-08 01:00+00'` → UTC 달력 `08-08` / 매장 영업일 `08-07`.
**그날 밤 현지 21시부터 실제로 깨질 상황이었다.**

→ `TODAY_SQL = (CURRENT_TIMESTAMP AT TIME ZONE :tz)::date` 한 곳으로 모으고 4개 술어가
전부 이것만 쓴다. `tz` 는 `stores.timezone` → 없으면 `DEFAULT_STORE_TZ`(기존 규약 재사용).
잘못된 IANA 이름은 `resolveStoreTz()` 가 걸러 폴백한다 — 안 걸러내면 `AT TIME ZONE` 이
리포트를 500 으로 만든다.

**교훈: 날짜 기준을 고칠 때는 컬럼과 비교값 양쪽을 같이 봐야 한다.**

### 남은 것 — 쓰기 경로 (별도 판단 필요)

`stocks.operation_date` 의 DB DEFAULT 가 `CURRENT_DATE`(UTC)다.
`productStock.service.ts:437` 은 UI 가 날짜를 안 보내면 그 기본값에 의존한다
(`...(date ? { operationDate: date } : {})`) → 현지 저녁 입고가 다음 날로 저장될 수 있다.
실측 오염량: UTC 00~04시 생성 행 중 미보정 **22행**(NULL 19 / suspend 2 / sale 1).
**쿼리만 고쳐서는 복구되지 않는다** — 쓰기 경로 수정 + 기존 데이터 점검이 함께 필요하다.

---

## 1-ter. 배포 후 흰 화면 — 코드가 아니라 stale HTML 이었다 (front #575)

오늘 배포가 3회 나간 뒤 사용자가 신고: `Stock & Reportajes` 에서
**"Application error: a client-side exception has occurred"**.
사이드바는 멀쩡하고 콘텐츠 영역만 죽었다.

### 진단 (운영 실측)

| 확인 | 결과 |
|---|---|
| 서버가 주는 HTML 이 참조하는 청크 8개 | 전부 200 — **서버는 정상** |
| HTML 응답의 `Cache-Control` | **없음** (ETag 만) |
| 정적 청크 | `public, max-age=31536000, immutable` |
| `buildId` | 배포마다 바뀜 → 옛 해시 파일은 소멸 |

HTML 에 `Cache-Control` 이 없으면 브라우저가 **휴리스틱 캐싱**으로 옛 HTML 을 재검증 없이
쓴다. 그 HTML 은 이전 빌드의 청크 해시를 가리키고, 재배포로 그 파일들은 이미 없다 → 404 →
`next/dynamic(ssr:false)` 로드 실패 → 에러 바운더리.
**셸은 이미 로드돼 있어 사이드바만 남는 게 이 증상의 지문이다.**

★ 나는 처음에 직전에 만진 `PanelC_ColorMatrix` 를 의심했다. 틀렸다.
  "방금 내가 배포했으니 내 코드" 는 좋은 가설이지만 **증거가 아니다.**
  서버가 주는 HTML 의 청크가 전부 200 인 걸 확인한 순간 코드 가설은 죽는다.

### 수정

`next.config.js` `headers()` 에 HTML 전용 규칙 추가:

```js
{ source: '/((?!_next/static|_next/image).*)',
  headers: [{ key: 'Cache-Control', value: 'no-cache' }] }
```

- `no-store` 가 아니라 **`no-cache`** — "쓰기 전에 재검증"이라 ETag 로 304 를 받으면
  본문을 다시 안 받는다. `no-store` 는 매번 전송이라 낭비다.
- ★ **`/_next/static` 제외가 핵심.** 덮으면 모든 청크를 매 로드마다 재검증하게 된다.
  해시 파일명이라 `immutable` 이 맞다.

### 검증 (로컬 prod 빌드 + 운영 배포 후 각각)

```
/reportes/                → Cache-Control: no-cache
/_next/static/chunks/*.js → public, max-age=31536000, immutable   (불변)
/_next/static/css/*.css   → public, max-age=31536000, immutable   (불변)
If-None-Match 재검증       → 304, 0 bytes
보안 헤더(X-Frame/CSP 등)  → 그대로 적용
```

### 남은 주의

이 수정은 **사용자가 새 HTML 을 한 번 받은 뒤부터** 효과가 있다.
front #575 이전에 열려 있던 탭은 여전히 하드 리로드(Cmd+Shift+R)가 필요하다.
그 다음 배포부터는 자동이다.

---

## 2. 아직 브라우저 미검증 (사람이 해야 함)

1. **이번 작업**: `reportes` > Stocks 에서 Panel A 의 **'전체'** 를 고르고 COLLAR 를 선택 →
   Panel C 헤더에 `Todas las sucursales (N)` 칩이 뜨는지 / 셀 값이 Panel B 와 같은지
   (**Stock 80, Hoy+ 110**) / 셀에 마우스를 올리면 지점별 내역이 뜨는지 /
   그 셀을 클릭하면 Panel D 가 저장 폼 대신 "지점을 고르라"는 안내를 내는지.
   그리고 **지점을 하나 고르면** 종전처럼 조정이 되는지(회귀).
   ★ **StockVistas 리포트('Ingreso hoy')와 값이 같은지 나란히 확인** — 이번 통일의 요점이다.
2. **이월 (73-NEXT-4 §2-E)**: front #573 — 정정 확인창 없이 저장 + 5초 토스트 /
   저장 제품이 Historial 맨 위 크림색 / 사이드바 Admin → 대시보드 직행.

---

## 3. 이 코드베이스의 함정 (누적)

73-NEXT-4 §3 의 5개에 더해:

6. **집계 화면은 "한 화면 안에서 두 표가 다른 GROUP BY 를 쓴다"는 이유로 갈라진다.**
   Panel B 는 pb 없이, Panel C 는 pb 로 묶었다. 둘 다 SQL 은 맞았고 **JS 가 틀렸다.**
   같은 화면에 나란히 놓인 두 숫자는 **같은 스코프인지 화면이 스스로 말하게** 해야 한다
   (그래서 스코프 칩을 넣었다).
7. **표시를 고칠 때 그 값이 쓰기 경로의 입력이기도 한지 먼저 확인하라.** §1-C 가 그 사례다.
   읽기 값과 쓰기 대상이 같은 객체에 실려 다니면, 읽기를 고치는 순간 쓰기가 어긋난다.
8. **"이 지표가 틀렸다" 를 만나면 같은 값을 보여주는 다른 화면을 먼저 찾아라.**
   §1-bis 에서 StockVistas 는 이미 정답을 보여주고 있었다. 그걸 몰랐으면 Cockpit 에
   **세 번째 정의**를 새로 만들 뻔했다. 정본이 이미 있는지부터 확인한다.
9. **정본 뷰를 메인 쿼리에 LEFT JOIN 하지 마라.** 메인이 `stocks` 를 join 해 grain 이
   부풀어 있으면 뷰 행이 그만큼 복제돼 조용히 이중 계상된다. correlated subquery 로 읽어라.
   (이 함정은 `v_stock_dia` 마이그레이션 주석에도 이미 적혀 있었다 — 같은 실수를 두 번 할 뻔했다.)
10. **성능 테스트 쿼리를 실제 쿼리와 다르게 쓰면 검증이 아니다.** 나는 편의상 GROUP BY 에
    `p.store_id` 를 넣고 EXPLAIN 을 돌렸는데, 실제 쿼리엔 그게 없다. 함수 종속성 통과 여부를
    통째로 못 잡을 뻔했다. **실제 GROUP BY 그대로** 다시 돌려서 확인했다.

---

## 4. 이월 — 계속 막혀 있는 것 (73-NEXT-4 §4 그대로)

- **결제수단 % 실사용 확인**: 운영 판매 한 건으로 Recargo 가 영수증에 찍히는지. 사람이 해야 함
- **jest CI**: `gh workflow run api-tests.yml --repo jhkim1010/api-ventago --ref main` 초록 확인 전까지
  완료로 적지 말 것
- **package-lock 불일치**: `npm ci` 불가, `npm install` 사용
- **0원 식당 판매 3건** (매장 11 "Asado"): 의도적 미보정
- **print-agent macOS**: 자동 업데이트 피드(`latest.yml`)는 Windows 전용. mac 은 수동 재설치
- **선물 티켓 실물 출력 확인**: 코드·릴리스·배선은 확인. 실제 출력은 사람이 해야 함

---

## 5. 남은 구조적 위험 (73-NEXT-4 §5 그대로 — 손대지 않았다)

- `type IS NULL AND stock > 0` 복제가 `2026-08-02-stock-balances.sql:125,133,134` /
  `2026-08-02-stock-interface-views.sql:75,79` 에 남아 있다. **전부 정정을 반영해야 하는 건
  아니다** — 133/134 는 "최초/최종 입고일" 로 의미가 달라 보인다. 용도 확정 전엔 손대지 마라
- 같은 테마 Select 문제로 조용히 깨져 있을 화면: `SaleReviewPanel.tsx:395`(외부 폭 65px ←
  최소폭 96px 와 양립 불가), `VariantsStockVenta.tsx:259`(100px),
  `SizeColorMatrixEditor.tsx:155`(110px). 뒤 둘은 셀 padding 착각도 함께 갖고 있다
- `editingMadre` 슬림화 (`parentId`/`parentName` 미사용, `deletedColorIds` 미소비)
- ★ POS 판매 차감이 `type=NULL` 음수(`sales-create.service.ts:1274`)인데 온라인 주문은 `type='sale'`.
  **이것 때문에 `Hoy −` 를 정본 뷰로 못 옮겼다**(§1-bis) — `v_stock_dia.venta` 는 `type='sale'`
  만 세므로 그대로 쓰면 POS 판매가 사라진다. 라벨링을 통일하는 것이 `Hoy +/−` 날짜 기준
  비대칭을 없애는 선행 조건이다
- ~~HTML 문서에 `Cache-Control` 없음~~ → **해결됨 (front #575). §1-ter 참조 — 실제로 터졌다.**
