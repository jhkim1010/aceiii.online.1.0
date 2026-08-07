# 73 후속 4 — 그날 입고 정의 통일 + Nuevos productos 저장 경로 정리 (새 세션용)

앞선 문서: `73-NEXT.md`, `73-NEXT-2.md`, `73-NEXT-3.md`. 이 문서는 **2026-08-07 오전~오후** 작업분.

---

## 0. 먼저 읽을 것

- jest: `NODE_OPTIONS=--max-old-space-size=2048 npx jest --maxWorkers=1 --workerIdleMemoryLimit=800MB`
- 마이그레이션은 로컬 5432 + 운영 5434 **양쪽** 적용.
- **CODEX 자문은 상시 절차다** (사용자 지시). `codex exec --sandbox read-only "..."`.
  ★ 프롬프트에 경로를 쓸 때 **`api-ventago/migrations/...` 처럼 전체 경로**로. 리포 루트에
  `migrations/`·`src/` 가 없어서 CODEX 가 헤매다 시간을 버린 적이 있다.
  ★ 실측값(DOM 측정·DB 쿼리 결과)을 프롬프트에 넣어라. 추측만 주면 추측이 돌아온다.
  ★ **CODEX 지적도 근거까지 대조하라** — 맞는 항목도 근거가 틀릴 때가 있다(아래 §5).
- GitHub Actions 는 **정상**이다(73-NEXT-3 의 "장애" 기술은 오류였다).

---

## 1. ★ 지금 열려 있는 문제 — 통합 view 의 우측 상세 패널

**사용자 신고**: 통합 view 에서 COLLAR 가 150 인 건 맞는데, 우측 상세는 한 지점 것만 보여준다.

**DB 실측 (2026-08-07, 제품 2545001 `[ACCESORIOS] COLLAR`)**
```
coolsistema : ingreso 120 · anulado 0 · net 33   (correccion −87)
HELGUERA    : ingreso  30 · anulado 0 · net 77   (correccion +47)
```
- 통합 view `HOY+ = +150` = **ingreso 합**(120+30) → 사용자 확인상 **맞는 값**
- 우측 상세가 보여준 **30** = HELGUERA 한 지점의 **ingreso**
- 그 지점의 **net 은 77** 이다 — 정정 +47 이 반영 안 됐다

즉 우측 패널은 (a) 한 지점만 보여주고 (b) `net` 이 아니라 `ingreso` 를 보여주는 것으로 보인다.

**다음 세션 시작점**
1. 우측 상세 패널이 쓰는 엔드포인트 확인 — **통합 view 화면**이지 `Nuevos productos` 가 아니다
2. 그 값이 `ingreso` 인지 `net` 인지, 지점 스코프가 의도인지 확정
3. `HOY+`(전 지점 ingreso)와 상세(한 지점)의 **의미 차이를 화면에 드러낼지** 결정

★ 내가 처음에 "150 이 틀렸다(net 합 110)"고 했는데 **사용자가 정정했다**. HOY+ 는 원시 입고
합이 맞다. 지표마다 정정 반영 여부가 다를 수 있으니 **고치기 전에 각 컬럼의 의미부터 확정**할 것.

---

## 2. 오늘 배포된 것

api #634, front #561~#573 — 전부 SUCCESS + 컨테이너 재생성 확인.

### 2-A. "그날 입고" 정의를 정본 뷰 하나로 (api #634)

정의가 **7곳**에 복제돼 있었고, 읽기와 쓰기가 **같은 틀린 식을 공유**해 자기일관적으로 틀렸다.
→ 화면 1 / 원장 3, 사용자가 3 을 다시 넣으면 5. 조용히 부풀어 오르는 유형.

- `migrations/2026-08-07-daily-ingreso-include-correccion.sql` (로컬 5432 + 운영 5434 적용 완료)
  - `v_product_branch_daily_ingreso.net` 에 `note LIKE 'correccion ingreso%'` 를 signed 로 추가
  - `v_stock_dia` 를 정본 뷰 JOIN 으로 교체. `store_id/branch_id` 는 stocks 비정규화 컬럼 대신
    `ProductBranch→branches` 에서 끌어와 (pb,날짜) 1:1 을 구조적으로 보장
- `productStock.service.ts`: `getDailyIngresoByPb()` / `lockProductBranches()` 공용 헬퍼.
  읽기 2곳 + `correctTodayStocks` 기준선 + `editMadreVariants` ①② 가 전부 정본 net 사용
- `editMadreVariants` 는 **트랜잭션이 아예 없었다** → 하나로 묶음
- 정정·취소 경로에 `ProductBranch ... ORDER BY id FOR UPDATE`
- **보안(선재 결함)**: `editMadreVariants` 가 body 의 `branchIds`/`variantId` 를 전혀 검증하지 않아
  자기 매장 부모 하나만 알면 **타 매장 재고를 쓸 수 있었다**. 형제 엔드포인트의 가드를 적용

### 2-B. Nuevos productos 저장 경로 정리 (front #569~#571)

**증상**: EDITANDO 상태에서 HELGUERA 수량을 10 으로 바꿔 저장했는데 무시됐다.

원인 두 개가 겹쳤다:
1. 저장 분기가 두 곳 — `BasicDataCard` 가 `onSubmit={mode==='edit' ? handleEdit : handleSubmit}` 로
   `handleSubmit` 의 `editingMadre` 우선 분기를 **통째로 우회**했다.
   ★ `handleMadreSave` 는 저장 성공마다 `reloadStocksAfterSave` → `setMode('edit')` 를 하므로
     **한 번만 저장해도** 다음 저장부터 잘못된 경로로 간다.
2. 그 경로(`handleEdit`)는 기준선이 비면 "변경 없음"으로 보고했다.
   `handleMadreClick` 이 `originalStocks` 를 비우고(313행) 같은 함수가 `prevBranchIdRef` 를
   현재 지점으로 맞춰 재조회까지 막는다 → 지점을 안 바꾸면 기준선이 빈 채로 남는다

**수정**: 저장 분기를 `handleSubmit` 한 곳으로. 기준선 0건인데 수량을 입력했으면 에러로 알림
(비교 불가와 변경 없음을 같은 결과로 처리하면 입력이 조용히 버려진다).

### 2-C. 상태 단일화 (front #570~#571)

- **기준선**: `stock-baseline.ts` 신설. 3곳 복제 제거.
  ★ CODEX 가 HIGH 로 잡은 것: 중복 `(color,size)` 처리가 셋 다 달랐다
  (교차곱·선착순 / Map·후착순 / 배열·중복허용). 소비자 `handleEdit` 이 `find()` 로 첫 건을
  쓰므로 **유일 + 선착순**으로 통일했다.
- **편집 대상 id**: `targetParentId` 파생값 하나로. 조회·검증·저장이 전부 이것만 읽는다.
  ★ CODEX 교정: 출처는 `editingMadre.parentId` 가 아니라 **`product.id`** 여야 한다 —
    저장 대상은 언제나 화면이 보여주는 제품이어야 한다.
  ★ CODEX 교정: `product.parentId` 를 "화면 전용 플래그"로 단정한 건 틀렸다. 신규 생성 payload 가
    `...cleanProduct` 를 펼치므로 **서버에는 진짜 FK 로 나간다**. 소비자도 `BasicDataCard` 에 있다
    (가격타입 동기화, 자동 SKU 재생성 차단) → 필드는 두고 **id 로 읽는 것만** 없앴다.

### 2-D. UI (front #561~#568, #573)

- talle 그리드: `tableLayout:'fixed'` + `minWidth` (컬럼 늘어도 찌그러지지 않고 스크롤)
  ★ 진짜 원인은 auto 레이아웃 — 헤더 talle Select 의 min-content 가 120.8px 이라
    셀 `width:56` 이 무시됐다. 실측 상자간격 56.8px → **2px**
- 전역 테마(`@core/theme/overrides/select.ts:5`)가 모든 Select 에 `minWidth:'6rem !important'`(96px).
  56/110px 컬럼에서 Select 가 셀 밖으로 나가 **헤더 라벨 32.4px 밀림 / 색깔 Select 가 첫 수량칸
  17px 침범(겹쳐 보임)**. → Table sx 한 곳에 스코프해 해제(개별 패치는 두더지잡기)
- 색 컬럼 110→135px (`VERDE MILITAR` 13자 수용). **공짜다** — 남는 폭은 spacer 가 먹고 있었다
- print-agent **v1.2.1** 배포. v1.1.1 태그가 `hidePrices` 커밋보다 8일 앞서 **바이너리에 기능이
  없었다**. 다운로드 페이지도 v1.0.8 을 가리키고 있었다 → 둘 다 정정

### 2-E. #573 — **아직 브라우저 미검증**

- 정정 확인창 제거 → 결과를 **5초 토스트**로 (`AMARILLO/L 30 → 10 · …`)
  ★ `doEdit` 이 diff 를 **인자로 받도록** 바꿨다. 상태에서 읽으면 계산 직후 호출 시
    React 가 아직 반영 안 한 이전 값을 쓴다. Dialog JSX 87줄 + 상태 4개 제거
- 저장한 제품을 Historial **맨 위 + 크림색(#FFF8E1)**. 페이지 슬라이스 **전에** 정렬한다
- 사이드바 Admin → `/dashboards/admin` 직행 (`menuRegistry.ts` 의 `defaultPath`)

**확인할 것**: 확인창 없이 저장되고 토스트가 5초 유지되는지 / 저장 제품이 맨 위 크림색인지 /
Admin 클릭이 대시보드로 가는지. 이상하면 **#573 커밋만 되돌리면 된다**(앞 건들과 커밋 분리됨).

---

## 3. 이 코드베이스의 함정 (반복해서 사고를 낸 것들)

1. **정의가 두 곳에 있으면 갈라진다.** 오늘만 이 유형으로 7건(백엔드 입고 정의) + 3건(프론트 기준선)
   + 3건(편집 대상 id) + 2건(저장 분기). ★ **읽기와 쓰기가 똑같이 틀리면 서로 검증이 안 돼
   사용자가 화면에서 발견할 때까지 조용하다.**
2. **불일치 탐지기가 있으면 그건 이미 갈라진 적이 있다는 기록이다.** 절대 어긋날 수 없다면
   아무도 그런 검사를 쓰지 않는다.
3. **셀 padding 으로 간격을 주지 마라.** `Table sx` 의 `'& .MuiTableCell-root':{padding:0}` 은
   자손 선택자(0,2,0)라 셀 자신의 sx(0,1,0)를 덮고, 테마(`overrides/table.ts:43,47`)는
   first/last-child 에 24px 을 박아 그마저 이긴다. **margin 을 써라.**
4. **재현 페이지로 검증할 때 실제 DOM 구조를 써라.** `<span>` 으로 흉내 냈다가 `<input>` 의
   고유 최소폭을 놓쳐 두 번 헛다리를 짚었다. 가능하면 **운영 화면 DOM 을 직접 측정**하라
   (쓰기 요청은 XHR 인터셉터로 차단하면 안전하다).
5. **"빌드 성공 = 사용자에게 도달"이 아니다.** print-agent 는 빌드도 성공하고 릴리스도 있었지만
   태그가 기능보다 앞서 있었고 다운로드 페이지는 더 옛 버전을 가리켰다.

---

## 4. 이월 — 계속 막혀 있는 것

- **결제수단 % 실사용 확인**: 운영에서 판매 한 건으로 Recargo 가 영수증에 찍히는지. 사람이 해야 함
- **jest CI**: `gh workflow run api-tests.yml --repo jhkim1010/api-ventago --ref main` 초록 확인 전까지
  완료로 적지 말 것
- **package-lock 불일치**: `npm ci` 불가, `npm install` 사용
- **0원 식당 판매 3건** (매장 11 "Asado"): 의도적 미보정
- **print-agent macOS**: 자동 업데이트 피드(`latest.yml`)는 **Windows 전용**. mac 은 수동 재설치
- **선물 티켓 실물 출력 확인**: 코드·릴리스·배선은 확인했지만 실제 프린터 출력은 사람이 해야 함

---

## 5. 남은 구조적 위험 (CODEX 지적, 이번 범위 밖)

- **`type IS NULL AND stock > 0` 복제가 아직 남아 있다** —
  `api-ventago/migrations/2026-08-02-stock-balances.sql:125,133,134`,
  `api-ventago/migrations/2026-08-02-stock-interface-views.sql:75,79`.
  ★ 다만 **전부 정정을 반영해야 하는 건 아니다.** `stock_balances` 의 133/134 행은
  "최초/최종 입고일" 로 의미가 달라 보인다 — **용도를 확정하기 전에 손대면 잔액 원장이 깨진다.**
- **같은 테마 Select 문제로 조용히 깨져 있을 화면**:
  `SaleReviewPanel.tsx:395`(외부 폭 **65px** ← 최소폭 96px 와 양립 불가),
  `VariantsStockVenta.tsx:259`(100px), `SizeColorMatrixEditor.tsx:155`(110px).
  뒤 둘은 **셀 padding 착각**도 함께 갖고 있다
- **`editingMadre` 슬림화**: `parentId`/`parentName` 은 이제 읽히지 않고, `deletedColorIds` 는
  초기화만 되고 소비되지 않는다(CODEX). 필드 제거는 `BasicDataCard` 포함 전수 정리 필요
- **POS 판매 차감이 `type=NULL` 음수**(`sales-create.service.ts:1274`)인데 온라인 주문은 `type='sale'` —
  라벨링이 갈라져 있다. 집계는 지금 맞지만 리포트에서 type 으로 구분하려 하면 걸린다
- **HTML 문서에 `Cache-Control` 이 없다**(정적 청크는 `immutable` 로 정상). 배포 반영이
  브라우저 캐시에 좌우될 수 있다. 고치려면 `/_next/static` 을 제외하는 매칭을 **prod 빌드로
  검증한 뒤** 올릴 것 — 잘못하면 모든 청크가 매번 재다운로드된다
