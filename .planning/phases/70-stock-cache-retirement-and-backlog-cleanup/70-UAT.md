---
phase: 70-stock-cache-retirement-and-backlog-cleanup
plan: 07 (단일 프로세스 계획 S5)
status: complete — Trello 카드 이동만 미실행(접근 수단 없음, 상태는 기록됨)
date: 2026-08-04
---

# 70-07 UAT — 운영 검증

환경: 운영 https://app.coolsistema.com (admin@cool, store 6 coolsistema), Playwright.
2차 실행에서 사용자 승인을 받아 **쓰기 항목까지 전부 수행**했다.

---

## T1 — 불변식 (PASS)

| 지표 | 로컬 5432 | 운영 5434 |
|---|---|---|
| `v_stock_balance_drift` | 0 | **0** (쓰기 테스트 후 재확인도 0) |
| `v_stock_tenant_leak` | 0 | **0** |

## T2 — 배포 확인 (PASS)

| Job | 빌드 | 결과 |
|---|---|---|
| api-new-coolsistema | **#603** | SUCCESS |
| front-coolsistema | **#531** | SUCCESS |

컨테이너 재생성 확인. Phase 70 커밋 전부 `origin/main` 조상
(api `ba22ff7 eb31895 3e7c8f7 e5e7d76 aa93aae c0bfe06 a1c0fbd 2aafc0d`,
app `e5bb72a 400e9cb 7105226 fd951a4 c3dd121 c3d4995 461ff5e`).

## T3 — 화면 검증 (전 항목 PASS)

| 카드 | 항목 | 결과 |
|---|---|---|
| [Articulos fXUDii66](https://trello.com/c/fXUDii66) | Códigos madres 수정·삭제 액션 | **PASS** — 액션 열 표시, 삭제 대화상자 동작 |
| [Pasar a pdf 30zWO5C8](https://trello.com/c/30zWO5C8) | PDF 버튼 실동작 | **PASS** — `stocks-items-20260804-145851.pdf` 실제 다운로드 |
| [Pasar a pdf 30zWO5C8](https://trello.com/c/30zWO5C8) | 확대 90/100/110/125% | **초기 FAIL → 수정 후 PASS** (아래 「발견·수정 2」) |
| [Codigo Vista zTHHD941](https://trello.com/c/zTHHD941) | CÓDIGO 컬럼 | **PASS** — 값 정상 표시 |
| [Cargar varios diACgk5B](https://trello.com/c/diACgk5B) | 저장 후 폼 리셋 | **PASS** — 아래 참조 |
| [Agregar a 2 sucursales bklfCOX3](https://trello.com/c/bklfCOX3) | 같은 날 2번째 지점 입고 | **PASS** — 아래 참조 |
| [Eliminar un ingreso LNBmJ2ZI](https://trello.com/c/LNBmJ2ZI) | 연속 5회 삭제 멱등 | **PASS** — 아래 참조 |
| [Sucursal uyBUKfBM](https://trello.com/c/uyBUKfBM) | 지점 전환 유지 | **PASS** — 아래 참조 |

### diACgk5B — 저장 후 폼 리셋

테스트 상품 `[ABRIGOS] ZZ TEST UAT 7007` 생성(가격 1000, coolsistema 재고 5).
DB 확인: 마드레 **333**(`263702`) + 변형 **334**(`263702-V`), 원장 1행(+5, branch 6, 2026-08-04).

저장 직후 폼 상태: NOMBRE `"[ABRIGOS] "` (입력값만 제거, 카테고리 접두 유지) / PRECIO 공백 /
수량 0 / **지점 선택 coolsistema 유지**. 확정된 정책과 일치.

### bklfCOX3 — 같은 날 2번째 지점 입고

같은 상품·같은 날짜(2026-08-04)에 HELGUERA(branch 16) 입고 3개 추가 → **성공**.

```
stocks: 1075 branch 6  +5
        1076 branch 16 +3
stock_balances: (334, 6) available 5 / (334, 16) available 3
```

종전 버그(`No hay cambios` 오판 / 대상 지점 비결정)면 여기서 실패했다.

### LNBmJ2ZI — 입고 삭제 멱등

`DELETE /api/products/stock-today/333?date=2026-08-04` **5회** 실행.

- 1회차(UI 휴지통): 역부호 보정 행 2건 추가 — `-5`(branch 6) / `-3`(branch 16),
  note `anulacion ingreso 2026-08-04 (madre#333)`. 잔량 0/0
- 2~5회차: 전부 `200 {"ok":true,"deleted":0}` — **원장 행 추가 없음**

최종: 원장 4행 / 순합 0 / 잔량 0·0. **추가 차감 없음 = 멱등**.
`stocks` append-only 규약도 지켜졌다(UPDATE/DELETE 없이 보정 행으로 상쇄).

### uyBUKfBM — 지점 전환 유지

coolsistema → HELGUERA 전환 후:

| 시점 | `/auth/me` branchId |
|---|---|
| 전환 직후 | 16 (HELGUERA) |
| 페이지 새로고침 후 | **16** |
| 로그아웃 → 재로그인 후 | **16** |

검증 후 원래 지점(coolsistema, branchId 6)·Terminal 1 로 **원복 완료**.

### 추가 — S4 삭제 영향 점검 (PASS, 이번 Phase 신규)

`[ABRIGOS/CHINA] 바추카`(251637001) 삭제 시도 → 서버 판정을 대화상자가 그대로 표시:

- 🔴 blockers 4건: 변형 6개 / 판매 항목 1건 / 재고 이동 1건 / taller 로테 1건
- 🟡 warning 1건: **보류 판매 3건** — 종전에 프론트가 판정할 수 없던 항목
- **Eliminar 버튼 비활성**, 메시지 전부 스페인어

테스트 상품 정리 시에도 정확히 동작: 마드레 333 → `VARIANTES 1` 차단,
변형 334 → `STOCK 4` 차단(원장 append-only 이므로 정상).

## T4 — 회귀 확인

| 항목 | 결과 |
|---|---|
| Stock Vistas 4탭 정합 | **PASS** — 변형합 2969 = 마드레합 2969 = 지점합 2969 = 원장합 2969 |
| 재고 리포트 전수 | Stocks / Stock Vistas / Ingreso / Corregido / Movidos / Rotación / **Fallados** 전부 200 |
| `allowSaleWithoutStock` | 운영 9개 매장 전부 `true`. 이번 Phase 에서 새 차단 코드 없음. 입고·삭제 경로에서 차단 발생 안 함 |
| 견적·온라인 티켓 고객명 | **미실행** — 티켓 실출력(프린터) 필요 |

---

## ★ UAT 중 발견·수정한 결함 2건

### 1. Fallados 코크핏 500 (Phase 70 무관, 기존 버그)

`GET /api/reports/fallados-cockpit` → `column si.product_branch_id does not exist`
(`reportsFalladosCockpit.service.ts:143`).

`sale_items` 는 `product_id` 로 상품을 직접 참조하는데 이 쿼리만 `ProductBranch` 경유로
없는 컬럼을 조인했다. 다른 코크핏은 이미 `si.product_id` 직결이었다.

- 수정 api-ventago `2aafc0d` → Jenkins **#603** → **재확인 500 → 200**
- 전수 검색 결과 같은 패턴은 이 1건뿐, 수정 SQL 은 로컬·운영 양쪽 실행 검증

### 2. 확대 125% 에서 우측 액션군(PDF/Excel) 잘림 — 카드 30zWO5C8 미완분

뷰포트 1536px(1920 화면 125% 확대 상당)에서 재현:
본문 `scrollWidth 1601 > clientWidth 1356`, 상위 `main` 이 `overflow-x: hidden`
→ PDF 버튼이 x=1637 로 **잘리고 가로 스크롤도 불가**.

원인: `ReportsShell` 의 grid 트랙 `'1fr'` 은 기본 `min-width: auto` 라 콘텐츠
min-content(≈1400px) 아래로 줄지 않는다. → `minmax(0, 1fr)` 로 교체.

- 수정 ventago-app `461ff5e` → Jenkins **#531**
- 배포 후 재측정: 1536px 에서 오버플로 해소(1356 = 1356), PDF 버튼 뷰포트 안. 1920px 회귀 없음

### 3. 상품 상태 일괄변경이 자기 매장에도 403 (Phase 70 무관, 기존 버그)

`POST /products/update-status` → 403 `No tienes permiso para operar sobre datos de otra tienda`.
운영 로그가 원인을 그대로 찍고 있었다:

```
[TenantGuard] Product.update 차단: 대상 store=undefined / 허용 store=[6]
```

`updateProductsStatus` 가 `attributes: ['id','status']` 로만 조회해 인스턴스의 `storeId` 가
`undefined` 였다. 테넌트 격리 훅은 인스턴스 `storeId` 로 쓰기를 판정하므로 **자기 매장 상품인데도**
차단됐다 — 전 매장에서 상태 일괄변경(활성/비활성/미게시)이 통째로 막혀 있었다.

- 수정: `attributes` 에 `storeId` 추가 → api-ventago `0625429` → Jenkins **#604**
- 검증: 배포 후 동일 호출 **403 → 201 `{"updated":2}`**
- 동일 패턴 전수 스캔(attributes 제한 조회 → 인스턴스 쓰기) 결과 **실제 결함은 이 1건**.
  후보 11건은 쓰기 경로가 attributes 제한 없이 조회하므로 오탐

## 70-06 야간 크론 오탐 여부 (사전 확인 PASS)

전환한 주 지표 기준 현재값 — 03:30 크론이 알람 없이 `drift 0 ✓` 로 끝난다:

| | 값 |
|---|---|
| `stock_balances` 총 행 | 232 |
| `v_stock_balance_drift` | **0** |
| drift 단위 합 | **0** |

내일 아침 확인할 것: `docker logs api_ventago | grep 'stock drift reconcile'` 에
`drift 0 ✓` 가 찍혔는지, 텔레그램 알람이 오지 않았는지.

## T5 — Trello 정리 (카드 이동 미실행 — 접근 수단 없음)

통과 카드(fXUDii66 / 30zWO5C8 / diACgk5B / bklfCOX3 / LNBmJ2ZI / uyBUKfBM / zTHHD941)를
**Hechos Semanales 로 이동**해야 한다(아카이브·삭제 금지).

**카드 이동은 하지 못했다** — Chrome 확장 미연결(`Browser extension is not connected`),
저장소·환경변수 어디에도 Trello API 토큰이 없다. 사용자가 직접 옮기거나 토큰을 주면 처리 가능하다.

대신 `triage-state.json` 에 UAT 결과와 이동 대기를 **기록해 뒀다**(다음 트리아지가 집어간다):

| 카드 | ID | 현재 리스트 | hechosPending |
|---|---|---|---|
| fXUDii66 Articulos | `6a6e4435…` | Stock Control Online | **true** |
| 30zWO5C8 Pasar a pdf | `6a6b9b70…` | Stock Control Online | **true** |
| zTHHD941 Codigo Vista | `6a635c22…` | Producto Control OnLine | **true** |
| diACgk5B Cargar varios | `6a6e417c…` | Producto Control OnLine | **true** |
| bklfCOX3 Agregar a 2 sucursales | `6a6e43fb…` | Producto Control OnLine | **true** |
| uyBUKfBM Sucursal | `6a6e3fca…` | 이미 Hechos Semanales | false |
| LNBmJ2ZI Eliminar un ingreso | `6a6e4289…` | 이미 Hechos Semanales | false |

7건 모두 `status: verified`, `uatVerifiedAt: 2026-08-04` 로 표시했다.

## 테스트 데이터 처리

`ZZ TEST UAT 7007` (마드레 333 / 변형 334, SKU 263702)

- 재고 **0** (입고 후 전량 보정 상쇄)
- `is_published_shop` / `allow_revendedor` / `publish_marketplace` **전부 false** 로 내림
- **삭제 불가** — 원장 4행이 남아 `STOCK` blocker 가 걸린다(append-only 규약상 정상)
- `status` = **`deactivated`** (= UI 표시 "Borrado"). 처음엔 403 으로 막혔는데, 그 403 이
  위 「발견·수정 3」의 실제 버그였고 수정·배포 후 `{"updated":2}` 로 정리 완료
