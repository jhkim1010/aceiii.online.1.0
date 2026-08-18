# 핸드오프 — 2026-08-17 (표 밀도 · WIP · 재고 조정 안전화 · Enviado 보고서)

`HANDOFF-2026-08-16-contabilidad-anulaciones.md` 를 이어받았다.

한 줄 요약: **화면이 스스로 무엇을 재는지 말하게 만든 하루.** 표 밀도를 한 곳으로 모으고,
생산 중 물량을 노출하고, 재고 조정의 경합을 없앴고, 배송 보고서를 만들다가
**"운송사 연동이 없는데 배달 완료를 어떻게 아느냐"** 는 사용자 질문에 설계를 다시 세웠다.

---

## 배포 (전부 빌드 성공 + 컨테이너 재생성 + 응답 확인)

| 커밋 | 내용 | 빌드 |
|---|---|---|
| api `8f7c2cb` | Reservado 결제수단 비활성 (마이그레이션) | #714 |
| app `199130d` | Caja Fuerte 행 30px | #633 |
| app `696896e` | 판매 목록 Reservado 열 제거 | #634 |
| app `c693102` | **표 행 높이 30px 통일** (Phase 79 W1) | #635 |
| app `a6f4dbd` | 표 밀도 — CODEX B1·B2·sizeSmall 반영 | #636 |
| app `f6d1ad9` | Códigos madres 자동 높이 + 배너 1줄 | #637 |
| app `657fc1e` | **스톡 보고서 깜빡임 제거** + 칼럼 안내 삭제 | #638 |
| app `d8ad20c` `b45c351` | 색상 빈 행 · 리사이저 하한 · Sucursales 3열 | #639 |
| app `4dec41a` | **MercadoPago 를 X Banco 에서 분리** (열 + 필터) | #640 (수동) |
| app `85c2489` | talle 빈 칸 + 제목 줄 통합 | #641 |
| app `f6e7aec` | MP 항상 선택 가능 (분할 결제) | #642 |
| api `9b1e779` → **`d08a771`** | Phase 80 W1 (WIP 서버) → **부팅 실패 hotfix** | #715 → #716 |
| app `be98f10` | Phase 80 W2 (WIP 2열) | #643 |
| app `bdf7b1f` `19a869f` | F2 비활성 사유 툴팁 · Facturar 버튼 제거 | #645 |
| api `63ee2f5` + app `037172c` | **합산 뷰 조정 차단 + 권한 admin·gerente** | #718 / #646 |
| api `99ed25d` + app `ba182ac` | **조정 경합 제거** + Panel C 응답 역전 방어 | #719 / #647 |
| api `4708a79` + app `dc1367a` | Phase 81 (매트릭스 인라인 일괄 수정) | #720 / #648 |
| api `96130a1` + app `8c50acf` | **Phase 82 (Enviado 보고서)** | #721 / #649 |

마이그레이션 4건 — 전부 **운영(5434)·로컬(5432) 양쪽 적용 확인**:
`Reservado 결제수단 비활성` · `functions 181 reporte-stock-wip` ·
`stock_adjust_batches + stocks.adjust_batch_id` · `functions 182 reporte-enviado`

---

## ★ 오늘 낸 사고 — API 35분 중단

Phase 80 W1 배포(#715) 후 운영 API 가 부팅하지 못했다.
```
UnknownDependenciesException: FunctionPermissionGuard → FunctionPermissionService
PM2: exited with code [1] → 재시작 루프
```
원인: 권한 판정 로직을 `FunctionPermissionService` 로 빼면서 provider 를 `AuthModule` 에만
등록했다. 그 가드는 `@FunctionGuard` 로 **앱 전역 여러 모듈**에서 붙고, **가드의 의존성은
그 가드를 쓰는 각 모듈의 인젝터에서 해석된다.**
→ `MemoryCacheModule(@Global)` 로 옮겨 복구(`d08a771`, #716).

**빌드·tsc·유닛테스트가 전부 통과했다.** DI 해석은 런타임 부팅에만 드러난다.
컨테이너가 `(unhealthy)` 였는데 `Up` 만 보고 넘어갔다.
→ **이후 모든 API 배포는 `/api/health` 200 까지 확인**하고 있다. 이 절차를 유지할 것.

---

## Phase 79 — 표 행 높이 30px 통일

`src/configs/table-density.ts` 가 단일 출처. `FullTable` 기본값 하나로 **76개 화면**,
MUI 테마 `MuiTableCell.sizeSmall` 하나로 **104개 표**가 따라온다.

★ 내가 처음에 틀린 것 둘 (CODEX 가 잡음):
1. `.ag-cell` 전체에 버튼 압축을 걸어 **액션이 아닌 열의 버튼까지 24px** 로 줄였다 —
   터치로 쓰는 POS 보조 목록(`DraftAndDebtors`)의 타깃이 실제로 작아졌다.
   → `.ag-cell-action` 으로 좁히고 28×28 고정 박스.
2. "상수 하나면 전부 정확히 30px" 이라는 규약이 **거짓**이다. AG Grid 는 강제 높이,
   MUI 는 최소 높이다. → `TABLE_DENSITY` 정책 객체 + 파일 상단에 계열별 표로 명시.

★ 앱의 `<Table>` **113개 중 104개가 `size='small'`** 이었다. 처음 바꾼 `MuiTableBody`
패딩은 sizeSmall 을 제외해서 **9개에만 닿았다.** 지금은 `sizeSmall` 에 `height: 30` +
패딩 4px(높이는 최소값처럼 동작 → 편집 행·2줄 셀은 자동 확장).

**남은 것**: W2 시각 확인(액션 열·2줄 셀 잘림, POS 터치 오탭).

---

## Phase 80 — 생산 중(WIP) 수량·ETA (Stocks 리포트)

`En producción` / `Listo aprox.` 2열. 권한 `reporte-stock-wip`(functions **181**).

CODEX 가 초안에서 **Blocker 6건**을 잡았다:
- `열린 envío pending 합`은 **공정 사이 대기 수량을 놓친다** → 총량은
  `total_quantity − stocked_quantity`, 그 합은 부분집합(`inWorkshopQty`)
- 로트당 "현재 공정" 하나는 **분할 발송·rework 에서 성립 안 함** → cohort 단위
- `max(due_date)` 는 완성예정일이 아니다 → **최종 공정만**, penúltima 는 다음 이정표
- 엔드포인트 단일 guard 로는 **필드가 응답에 그대로 실린다** → **필드 단위 차단**
  (권한 없으면 키 자체 없음 · 정렬 403 · export 제외 · `isAllowedStrict` fail-closed)
- 균등 분배 결정적 규칙(`base`+나머지를 `branch_id ASC` 앞쪽) · 매장 경계 넘지 않음
- madre/leaf 모집단은 `groupLeafIds` 재사용 (그래서 **correlated subquery** 로 구현 —
  원장 조인에 의한 복제 경로가 구조적으로 없다)

★ 사용자 결정: 지점 **균등 분배**(내 권고와 다름) → 필드명·화면에 추정임을 못박음
(`estimatedBranchWipQty` · `allocationMethod` · 값마다 `≈`).

---

## 재고 조정 안전화 (Phase 80·81 사이, CODEX 검토 2회)

사용자 지적: *"전 지점 합산 화면에서 재고를 수정하는 건 비논리적"*.

- 종전 가드는 `productBranchId <= 0`(대상 모호)만 봤다 → **한 지점에만 재고가 있는 제품은
  합산 화면에서도 통과**했다. 이제 **화면 맥락**(`branchId === null`)으로도 막고,
  **서버가 `branchId` 를 받아 `pb.branch_id` 와 대조**한다(구버전·Flutter·직접 호출 방어)
- 권한을 **admin·gerente** 로 (종전엔 `reporte-stocks:read` 만 있으면 원장을 고칠 수 있었다)
- 대상 PB 가 없으면 `NotFound` — 종전엔 매장 사용자에게 **"다른 매장 권한 없음"** 이라는
  틀린 사유가 갔고 superadmin 은 **FK 오류까지** 도달했다.
  ★ 기존 spec 이 그 잘못된 403 을 정상으로 고정하고 있어 기대값을 정정했다
- **경합 제거**: 이론값 조회와 INSERT 가 분리돼 있어 두 사람이 동시에 8 로 맞추면 재고가 6 이
  됐다 → 한 트랜잭션 + `pg_advisory_xact_lock(80, pbId)`
- ★ **`on_hand` 이 아니라 `available`** 을 읽는다. 운영 439 PB 중 **44건**이 정확히
  `reservado` 만큼 다르다. 화면 `r_stock` 과 일치하는 것은 `available`(drift 0행)

---

## Phase 81 — 매트릭스 인라인 일괄 수정 (Editar → Confirmar)

핵심은 편집 UI 가 아니라 **`expectedStock` 대조**다. 절대값만 보내면 화면을 연 뒤의
판매를 조정이 되돌린다(화면 10 → 8 입력 → 그 사이 판매 −2 → 서버가 `+1` 기록).
→ 락 후 대조, 하나라도 어긋나면 **409 + 충돌 목록, 원장에 0행**.

- 검증과 쓰기를 섞지 않는다(전부 통과 후에만 INSERT) · 락 순서 `product_id, pb_id` 오름차순
- `stock_adjust_batches` + `stocks.adjust_batch_id` 로 한 실사를 묶음 · Idempotency-Key
- 회귀 14건 + **변이 테스트 2건**(기준값 대조·락 정렬을 지우면 해당 테스트만 실패)
- ★ Panel D 는 **제거하지 않고 숨김** — 단일 셀 note·이론값이 거기에만 있다

---

## Phase 82 — Enviado (Online Venta) Control ★ 오늘의 핵심 교훈

Mockup: https://claude.ai/code/artifact/eec55483-c567-4fb3-889d-75a26059a103

### ★ 사용자 질문이 설계를 뒤집었다
> *"모든 transporte 회사의 API 와 연결이 안 될 텐데 어떻게 배달이 완료되었는지 확인하지?"*

코드 확인 결과 **운송사 연동이 없다.** `delivered_at` 은 `deliverOrder()` 가 찍는
**사람이 누른 시각**이다(`by=${userName}`). 그대로 OTD 를 헤드라인으로 썼다면
**운송사 성과가 아니라 클릭 습관**을 발표할 뻔했다. 안 누른 주문은 영원히 `En tránsito` 에
남아 금액을 부풀린다.

→ **주 KPI 를 `Sin confirmar` 로** (시스템이 쓰는 `shipped_at` 만으로 계산되는 유일한 값).
  OTD 는 `Entregas confirmadas a tiempo` 로 이름을 바꾸고 **"확인 시각 기준" 각주**.
  **확인율**을 품질 KPI 로. 직원 확인 시 **도착일 입력**(늦게 눌러도 지연이 부풀지 않게).

### CODEX 가 잡은 것
- ★ **`dispatched_at → shipped_at` 은 구간이 아니다** — `shipOrder()` 가 같은 줄에서 둘 다
  찍는다(`online-orders.service.ts:1023-1024`). 내 mockup 의 4구간 바는 **항상 0인 칸**을
  만들 뻔했다 → **3구간**
- 기간 코호트 미정의 → `shipped_at` 반개방 + `excluidos` 표기
- **발송 후 취소가 `En tránsito` 에 남음**(재고는 이미 역분개) → 제외 + 별도 탭
- 타임존: 컬럼에 함수 금지(현지→UTC 경계 변환)

### 운영 첫 실행에서 나온 것
```
Confirmado→Preparado 12.15일 ⚠   Preparado→Enviado 5.39일   Enviado→Confirmado 3.38일
```
**가장 느린 구간이 운송사가 아니라 우리 쪽이다.** Despacho 보드로는 안 보이는 숫자.

Reservado 는 `hidden` 플래그 + `isVisibleReport()` 로 **목록·검색·최근·즐겨찾기 네 경로**
에서 숨김. 코드·권한은 남김 → **직접 URL 은 열린다**(= 메뉴에서만 숨김, 문서화된 결정).

---

## 다음에 할 것

### 실행 대기
1. **Phase 83 (고객 배달 확인 링크)** — 계획 완료, 미착수.
   `/entrega/:token` 공개 페이지 + WhatsApp 통지 + `delivered_confirmed_by/at` +
   `En disputa`. ★ 사용자 원안의 *"직원 확인 → 고객이 OK"* 마지막 단계는 **뺐다**
   (고객이 첫 번째를 안 눌렀으면 두 번째도 안 눌러 주문이 계속 열린다).
   직원 확인은 즉시 종결 + 통지만(침묵=동의). **자동 확인 금지** — 레거시 폴백
   (`mirrorSaleId == null`)이 매출·외상을 만든다.
2. **Jenkins 폴링 5분** — 두 job 의 `config.xml` 에 `SCMTrigger` 를 넣고 재시작해
   **적용까지 완료**했다(`scm-polling.log` 로 동작 확인). 백업 `config.xml.bak-20260817`.
   ※ 오늘 GitHub 웹훅이 **2시간 반 침묵**해 빌드가 조용히 누락됐다(수동 트리거로 해결).

### 사람이 화면으로 확인할 것
- **Phase 79 W2** — 액션 열·2줄 셀 잘림, POS 터치 오탭
- **Phase 81 W2** — variation 여러 개 수정 → `Confirmar` 1회, 다른 창에서 판매 후 **409** 경고
- **Phase 82** — Reservado 사라짐(즐겨찾기 포함) · `Sin confirmar` 0건 문구 ·
  운송사 소표본 회색 칩 · **권한 `Reporte Enviado`(182) 부여 필요**
- **재고 조정 권한 축소** — 실제로 조정하던 담당자가 vendedor 였다면 이제 403 이다

### 이월 (앞 핸드오프에서)
- `approveReturn` 이 카하를 조정하지 않음 / 부분 환불 품목 역분개
- 판매 수정 중 프로모션 재평가 (과다청구 가능)
- Historial 묶음 표시(`replaces_sale_id`) · 판매 158 유령 현금 52.000 · 실사 큐 13개 서랍

---

## 작업 방식 — 이번에 걸린 것

- ★ **컨테이너 "Up" 은 배포 성공이 아니다.** `(unhealthy)` 를 놓쳐 35분을 잃었다.
  API 는 `/api/health` 200 까지가 배포 완료다.
- ★ **DI 배선은 빌드가 잡지 못한다.** tsc·유닛테스트가 다 통과한 채로 운영이 죽었다.
- ★ **"이 화면이 무엇을 재는가" 를 먼저 확인할 것.** Enviado 보고서는 코드를 다 짜고 나서
  사용자 질문 한 줄에 전제가 무너질 뻔했다. 지표를 만들기 전에 **그 값을 누가 쓰는지**
  코드에서 확인한다(`by=${userName}` 이 답이었다).
- ★ **CODEX 는 내가 못 본 것을 잡는다.** 오늘 4번 돌렸고 매번 Blocker 가 나왔다.
  특히 "내 mockup 의 구간이 실제로는 존재하지 않는다" 는 코드를 읽어야만 나오는 지적이었다.
- **기존 테스트가 잘못된 동작을 고정하고 있을 수 있다.** adjust spec 이 틀린 403 을
  정상으로 박아두고 있었다 — 고칠 때 기대값도 함께 정정해야 한다.
- **변이 테스트로 확인할 것.** 가드를 지웠을 때 해당 테스트가 실제로 죽는지 봐야
  "통과만 하는 테스트" 를 피한다.
