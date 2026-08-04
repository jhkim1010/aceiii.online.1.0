---
phase: 70-stock-cache-retirement-and-backlog-cleanup
plan: 07 (단일 프로세스 계획 S5)
status: complete — Trello 이동만 미실행(접근 수단 없음)
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

## T5 — Trello 정리 (미실행 — 접근 수단 없음)

통과 카드(fXUDii66 / 30zWO5C8 / diACgk5B / bklfCOX3 / LNBmJ2ZI / uyBUKfBM / zTHHD941)를
**Hechos Semanales 로 이동**해야 한다(아카이브·삭제 금지).

이번 세션에서는 이동하지 못했다: Chrome 확장 미연결(`Browser extension is not connected`),
Trello API 토큰도 저장돼 있지 않다. 사용자가 직접 이동하거나 토큰을 제공하면 처리 가능하다.

## 테스트 데이터 처리

`ZZ TEST UAT 7007` (마드레 333 / 변형 334, SKU 263702)

- 재고 **0** (입고 후 전량 보정 상쇄)
- `is_published_shop` / `allow_revendedor` / `publish_marketplace` **전부 false** 로 내림
- **삭제 불가** — 원장 4행이 남아 `STOCK` blocker 가 걸린다(append-only 규약상 정상)
- `is_active` 는 `true` 로 남았다. `POST /products/update-status` 로 `deactivated` 시도 시
  **403 `No tienes permiso para operar sobre datos de otra tienda`** 가 났다.
  store 6 상품이고 요청자도 store 6 이라 **이 403 자체가 별도 조사 대상**이다(후속 과제)
