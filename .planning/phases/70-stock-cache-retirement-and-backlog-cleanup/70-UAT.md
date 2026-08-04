---
phase: 70-stock-cache-retirement-and-backlog-cleanup
plan: 07 (단일 프로세스 계획 S5)
status: partial — 쓰기 필요 항목 미실행, Trello 이동 대기
date: 2026-08-04
---

# 70-07 UAT — 운영 검증

환경: 운영 https://app.coolsistema.com (admin@cool, store 6 coolsistema), Playwright.
**운영 데이터에 쓰기를 남기는 항목은 실행하지 않았다** — 아래 「미실행」 참조.

---

## T1 — 불변식 (PASS)

| 지표 | 로컬 5432 | 운영 5434 |
|---|---|---|
| `v_stock_balance_drift` | 0 | **0** |
| `v_stock_tenant_leak` | 0 | **0** |

## T2 — 배포 확인 (PASS)

| Job | 빌드 | 결과 |
|---|---|---|
| api-new-coolsistema | **#603** | SUCCESS |
| front-coolsistema | **#530** | SUCCESS |

컨테이너 재생성 확인(`api_ventago` healthy / `ventagoapp`). Phase 70 커밋 전부 `origin/main` 조상 확인
(`git merge-base --is-ancestor`): api `ba22ff7 eb31895 3e7c8f7 e5e7d76 aa93aae c0bfe06 a1c0fbd 2aafc0d`,
app `e5bb72a 400e9cb 7105226 fd951a4 c3dd121 c3d4995`.

## T3 — 화면 검증

| 카드 | 항목 | 결과 |
|---|---|---|
| [Articulos fXUDii66](https://trello.com/c/fXUDii66) | Códigos madres 목록에 수정·삭제 액션 | **PASS** — 목록에 삭제 아이콘 열 표시, 동작 확인 |
| [Pasar a pdf 30zWO5C8](https://trello.com/c/30zWO5C8) | PDF 버튼 실동작 | **PASS** — `stocks-items-20260804-145851.pdf` 실제 다운로드됨 |
| [Pasar a pdf 30zWO5C8](https://trello.com/c/30zWO5C8) | 확대 90/100/110/125% 오버플로 | **미실행** — 실제 브라우저 줌 필요 |
| [Codigo Vista zTHHD941](https://trello.com/c/zTHHD941) | CÓDIGO 컬럼 표시 | **PASS** — 코드 값 정상 표시(2542001·263701·251637002 …) |
| [Cargar varios diACgk5B](https://trello.com/c/diACgk5B) | 저장 후 폼 리셋 | **미실행** — 상품 저장(쓰기) 필요 |
| [Agregar a 2 sucursales bklfCOX3](https://trello.com/c/bklfCOX3) | 같은 날 2번째 지점 입고 | **미실행** — 입고 생성(쓰기) 필요 |
| [Eliminar un ingreso LNBmJ2ZI](https://trello.com/c/LNBmJ2ZI) | 연속 5회 삭제 멱등 | **미실행** — 입고 생성·삭제(쓰기) 필요 |
| [Sucursal uyBUKfBM](https://trello.com/c/uyBUKfBM) | 지점 전환 유지 | **미실행** — 세션 전환·재로그인 필요 |

### 추가 검증 — S4 삭제 영향 점검 (PASS, 이번 Phase 신규)

`[ABRIGOS/CHINA] 바추카`(251637001) 삭제 시도 → 대화상자가 서버 판정을 그대로 표시:

- 🔴 blockers 4건: 변형 6개 / 판매 항목 1건 / 재고 이동 1건 / taller 로테 1건
- 🟡 warning 1건: **보류 판매 3건** — 종전에 프론트가 판정할 수 없던 바로 그 항목
- **Eliminar 버튼 비활성**, 메시지 전부 스페인어

종전이라면 여기서 PG 영문 FK 에러가 그대로 노출됐다.

## T4 — 회귀 확인

| 항목 | 결과 |
|---|---|
| Stock Vistas 4탭 숫자 정합 | **PASS** — 변형합 2969 = 마드레합 2969 = 지점합 2969, 스냅샷합 = 원장합 2969 |
| 재고 리포트 전수 | Stocks / Stock Vistas / Ingreso / Corregido / Movidos / Rotación Temporada **전부 200** |
| `allowSaleWithoutStock` 매장 판매 | **코드 기준 PASS** — 운영 9개 매장 전부 `true`. 이번 Phase 에서 새 차단 코드를 넣지 않았다(70-01b 의 revendedor 가드는 출처만 이관, 판정식 불변). **실제 판매 시도는 미실행(쓰기)** |
| 견적·온라인 티켓 고객명 | **미실행** — 티켓 출력(쓰기/프린터) 필요 |

## ★ UAT 중 발견·수정한 결함 (Phase 70 무관, 기존 버그)

**`GET /api/reports/fallados-cockpit` 500** — `column si.product_branch_id does not exist`
(`reportsFalladosCockpit.service.ts:143`).

`sale_items` 는 상품을 `product_id` 로 직접 참조한다. 이 쿼리만 `ProductBranch` 경유로
존재하지 않는 컬럼을 조인했다. 다른 코크핏(`reportsSalesCockpit` / `reportsProductsCockpit`)은
이미 `si.product_id` 직결을 쓰고 있었다.

- 수정: api-ventago `2aafc0d` → Jenkins **#603 SUCCESS**
- 전수 검색 결과 같은 패턴은 이 1건뿐
- 수정 SQL 로컬 5432 + 운영 5434 양쪽 실행 검증
- **재확인: 500 → 200**

## T5 — Trello 정리 (미실행)

통과 카드(fXUDii66 / 30zWO5C8 / zTHHD941)를 **Hechos Semanales 로 이동**해야 한다. 아카이브·삭제 금지.
이번 세션에서는 이동하지 않았다.

---

## 미실행 사유 정리

운영 데이터에 실제 레코드를 남기는 항목은 사용자 승인 없이 실행하지 않았다
(`final-test` 스킬 규약: 판매·입고는 명시 요청 시에만, **판매는 삭제 불가**).

승인해 주시면 다음을 이어서 실행한다:
1. 테스트 상품으로 폼 리셋(diACgk5B) — 상품 1건 생성
2. 같은 날 2번째 지점 입고(bklfCOX3) — 입고 2건 생성
3. 입고 삭제 연속 5회 멱등(LNBmJ2ZI) — 위 입고 사용
4. 지점 전환 유지(uyBUKfBM) — 세션 전환 + 재로그인
5. PDF 버튼 확대율 4단계(30zWO5C8)
6. Trello 카드 3건 Hechos Semanales 이동
