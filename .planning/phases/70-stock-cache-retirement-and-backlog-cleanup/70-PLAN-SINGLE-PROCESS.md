# Phase 70 — 단일 프로세스 실행 계획 (2026-08-04 재작성)

cmux-team(Master/Conductor/Agent 4-tier) 실행을 중단하고, **이 세션 한 프로세스에서 순차 실행**하도록
남은 작업을 다시 짠 문서다. 기존 `70-NN-PLAN.md` 의 목표·제약은 그대로 유효하며, 이 문서는
**실행 순서·검증 주체·게이트**만 교체한다.

읽어야 할 것: 이 문서 + `70-CONTEXT.md` + `70-BASELINE.md`. `70-RESUME.md` 는 이 문서를 가리키도록 갱신됨.

---

## 1. 왜 팀 실행을 접는가 (사실 기록)

태스크 16건 중 **성공 3건 / 초안 3건 / 중단 10건**. 중단 10건은 전부 인프라 사유다.

| 중단 사유 | 건수 | 태스크 |
|---|---|---|
| `resume_no_session_id` (재개 시 세션 ID 유실) | 5 | 001, 003, 007, 012, 013, 015 |
| `disconnect_timeout` (Conductor 연결 끊김) | 3 | 010, 011, 016 |
| autocompact 폭주 | 1 | 002 |

같은 태스크(70-01b)가 **4번 배정돼 4번 다 산출물 0** 이었다(010→013→015→016). 코드 문제가 아니라
Conductor 수명 문제이므로, 재시도해도 같은 자리에서 죽는다. 실제로 성과가 난 3건(005/008/014)도
결국 사람이 push·머지를 마무리했다.

→ **판단: 남은 작업량(5스텝)은 팀 오케스트레이션 오버헤드보다 작다. 단일 프로세스가 빠르다.**

---

## 2. 현재 진짜 상태 (2026-08-04 03:21 기준, 검증 완료)

| Plan | 상태 | 근거 |
|---|---|---|
| 70-01 재고 읽기 전환 | **완료·배포됨** | api `ba22ff7` → main, Jenkins #599 SUCCESS |
| 70-01b 잔여 읽기 경로 5곳 | **미착수** ← 70-06 전제조건 | 팀 4회 실패. 아래 S2 |
| 70-02 브랜치 정리 | **미착수** | 아래 S1 (팀 잔재 포함해 범위 확대) |
| 70-03 코드 수정·삭제 UI | **완료·배포됨** | app `e5bb72a`, front #529 SUCCESS |
| 70-03 후속(백엔드 하드닝) | **미착수** | `.team/tasks/009-70-03-fk/task.md`. 아래 S4 |
| 70-04 리포트 PDF | **완료·배포됨** | api `eb31895`+`3e7c8f7` / app `7105226`+`fd951a4` |
| 70-05 폼 리셋 | **완료·배포됨** | app `400e9cb` |
| Trello bklfCOX3 2번째 지점 입고 | **완료·배포됨** | api `e5e7d76` / app `c3dd121` (Phase 70 범위 밖 끼어든 건) |
| 70-06 트리거 폐기 | **미착수** (승인 게이트) | 아래 S3 |
| 70-07 UAT | **미착수** | 아래 S5 |

운영 반영: api `api_ventago` 03:19:22 재생성 / front `ventagoapp` 03:20:41 재생성. 미push 커밋 **0**.

---

## 3. 단일 프로세스 실행 규칙 (팀 규칙 대체)

팀 체제의 역할 분리가 사라지므로, 그것이 담보하던 것을 검증 절차로 대체한다.

| 팀 체제 | 단일 프로세스 대체 |
|---|---|
| Agent 작업 → Inspector 검수 GO/NO-GO | 스텝마다 **자기검증 체크리스트**(아래) 전부 통과해야 커밋 |
| worktree 격리 | 저장소별 `phase70/<스텝>` 브랜치 → 검증 후 `main` ff-merge |
| "push 는 Master 가" | **내가 즉시 push + Jenkins 빌드 성공 + 컨테이너 재생성까지 확인** (CLAUDE.md 상시 규칙) |
| 태스크 파일(`.team/tasks/`) | 이 문서의 스텝 + 스텝별 `70-NN-SUMMARY.md` |

### 스텝별 자기검증 체크리스트 (하나라도 실패면 커밋 금지)

1. `cd api-ventago && npx tsc --noEmit -p tsconfig.build.json` → 에러 0
   (전체 `tsconfig.json` 은 `*.spec.ts` 기존 에러 16건이 뜬다. 빌드 대상은 `tsconfig.build.json` 쪽이다)
2. `cd api-ventago && npx nest build` → 성공
3. 프론트 변경 시 `cd ventago-app && npx eslint <변경파일>` → **error 0** (`react-hooks/exhaustive-deps` warning 은 허용)
4. 프론트 변경 시 `npm run build` → 성공
5. 변경한 파일의 jest 스위트를 **변경 전/후 각각 실행해 실패 수 비교** → 신규 실패 0
   기준선: 전체 15 스위트 / 33 테스트가 **이미** 실패(`70-BASELINE.md`). 기존 실패를 고치는 건 범위 밖
6. DB 를 건드렸으면 로컬 5432 에서 `SELECT count(*) FROM v_stock_balance_drift;` = 0,
   `SELECT count(*) FROM v_stock_tenant_leak;` = 0

### 실행 환경 (CONTEXT 기술은 낡음 — 이게 최신)

- Mac 로컬에서 직접 실행. `agent-runner` 는 존재하지 않으니 찾지 말 것
- 로컬 DB: `psql -p 5432 -d ventago` (DDL 가능). 단 이 세션에서 psql 직접 실행이 막히면
  `postgres-ventago` MCP 는 read-only 이므로 **DDL 원라이너를 사용자에게 전달**하고 그 사실을 명시
- 운영 DB: `ssh jhkim-server "sudo -u postgres psql -p 5434 -d ventago ..."` — SELECT 는 승인 불필요, DDL/DML 은 승인 필수
- 컨텍스트 압축 대비: **스텝 하나 끝나면 즉시 SUMMARY 를 파일로 남긴다.** 세션이 잘려도 이 문서 + SUMMARY 로 재개 가능

### 불변 준수사항 (Phase 70 전체 공통)

- `stocks` 는 append-only. UPDATE/DELETE 금지, 역부호 보정행으로 상쇄
- `stocks` 키는 `product_branch_id`. **`product_id` 컬럼 없음** (`stock_balances` 에는 있음)
- 재고 마이너스는 `store_configs.allowSaleWithoutStock=true` 매장에서 **정상 동작**. 새 차단 코드 금지
- 락 순서는 `productId` 오름차순 고정
- `store_id` 는 클라이언트 값 불신, 인증 주체에서 도출
- DB 스키마는 추측 금지 — `.planning/intel/db-schema-tables.md` 참조

---

## 4. 실행 순서

```
S1 정리 (저위험, 먼저)  →  S2 70-01b  →  S3 70-06 [승인 게이트]  →  24h 관찰
                                                        ↘ 관찰 기간에 S4 병행
                                                                      ↘  S5 70-07 UAT
```

---

### S1 — 팀 잔재 + 브랜치 정리 (70-02 확장)

70-02 원안 10개에 **cmux-team 이 남긴 잔재**를 더한다. 트리가 더러우면 이후 스텝에서
"이건 뭐지" 를 계속 다시 확인하게 된다.

**S1-a. cmux-team 중지** — daemon PID `3091` (`bun .../cmux-team/manager/main.ts start`).
`.team/team.json` 은 manager=running / conductor surface:7=broken, surface:8=reserved.
→ daemon 종료 후 `.team/task-state.json` 의 draft 3건(004·006·009)을 이 문서로 이관했음을 journal 에 기록.
`.team/` 디렉터리 자체는 **삭제하지 않는다** (실패 기록이 재발 방지 근거).
⚠️ 프로세스 종료는 사용자 확인 후 실행.

**S1-b. worktree 7개 prune** — 전부 죽은 태스크 소유:
`task-001-1785751889` / `task-003-1785738563` / `task-003-1785755414` / `task-005-1785738533` /
`task-012-1785777398` / `task-013-1785777424` / `task-015-1785806410`
→ 각 worktree 에 **미커밋 변경이 없는지 확인한 뒤** `git worktree remove` → `git worktree prune`.
`/tmp/wt_root` (locked, detached `c9ce3e7`) 는 소유 불명 → **건드리지 않고 보고만** 한다.

**S1-c. 태스크 브랜치 삭제** — `git branch -d` (강제 `-D` 금지):
- root: `task-001-1785751889/task`, `task-003-1785738563/task`, `task-003-1785755414/task`,
  `task-005-1785738533/task`, `task-007-1785755216/task`, `task-012-1785777398/task`,
  `task-013-1785777424/task`, `task-015-1785806410/task`
- api-ventago: `task-003-70-04`, `task-010-1785773023/api`, `task-012-70-04`,
  `task-013-1785777424/api`, `task-015-1785806410/api`
- ventago-app: `task-003-70-04`, `task-012-70-04`
- 3 저장소: `fix/trello-6a6e43fb` (main 에 ff-merge 완료 → 삭제 가능)

**S1-d. 70-02 원안 10개** — 삭제 직전 재검증 필수:
```bash
git fetch --all --prune
git log --oneline origin/main..<branch>    # 0줄이어야 삭제
```
한 줄이라도 나오면 **그 브랜치는 건드리지 않고 보고**한다.
`split/mobile-sales-app` 은 `origin/main` 과 공통 조상이 없으므로 **태그 백업 push 성공 확인 후에만** `-D` 허용.

| 저장소 | 브랜치 | 위치 |
|---|---|---|
| root | `split/mobile-sales-app` | 로컬 (태그 후 삭제) |
| root | `feature/phase58-offline-sync` | origin |
| api-ventago | `backup/phase57-df122c7` | 로컬 |
| api-ventago | `security/global-jwt-guard` | 로컬+origin |
| api-ventago | `feat/revendedor-zona` / `feat/sku-serial` / `feature/phase58-offline-sync` | origin |
| ventago-app | `_probe_branch` | 로컬 |
| ventago-app | `feat/sku-serial` / `feature/phase58-offline-sync` | origin |

> ⚠️ `feat/sku-serial` 삭제 주의 — 메모상 "SKU serial 재설계 필요, 기존 7태스크 미푸시" 건이다.
> origin 에 있으므로 삭제 전 **태그 백업**(`archive/feat-sku-serial`)을 남기고 지운다. 원안에는 없던 안전장치다.

**완료 조건**: `70-02-SUMMARY.md` 에 브랜치별 처분·백업 태그 표. 3 저장소 `git status` 클린.
**위험**: 낮음. 코드 변경 0.

---

### S2 — 70-01b: 잔여 `products.stock` 읽기 경로 5곳 이관 (70-06 전제조건)

**이걸 안 하고 S3 을 하면 운영에서 재고가 그 시점에 얼어붙는다.** 팀이 4번 실패한 바로 그 작업.

2026-08-04 재확인 결과 5곳 전부 그대로 남아 있다:

| 파일 | 행 | 성격 | 이관 방향 |
|---|---|---|---|
| `shop-public/shop-catalog.service.ts` | 98·132·151·173 | 공개 카탈로그 재고 표시 + `showOutOfStock=false` 일 때 `COALESCE(p.stock,0) > 0` 필터 | 매장 전체 공개 카탈로그 = 전 지점 합 → `v_stock_total_variante.available` |
| `revendedor/purchase/revendedor-purchase.service.ts` | 192·194 | ★ 구매 차단 가드 `product.stock < item.quantity` | 지점 특정 가능하면 `stock_balances`, 아니면 합계 뷰. **`allowSaleWithoutStock` 취급 확인 필요** |
| `revendedor/products/revendedor-products.service.ts` | 173·237 | `inStock: p.stock > 0` 표시 | 동일 |
| `code-import/code-import.service.ts` | 794 | `Number(found.stock ?? 0)` 를 import 후 재고 기준선으로 사용 | 기준선 의미 확인 후 이관 |
| `sales/sales.service.ts` | 335·599·789·940 | 판매 조회 응답 attributes 에 `'stock'` 통과 | **먼저 프론트가 이 값을 재고로 쓰는지 확인** → 쓰면 이관, 안 쓰면 attributes 에서 제거 |

**선행 확인 2건 (코드 수정 전에 답부터 낼 것)**
- `sales.service` 의 `'stock'` 을 `ventago-app` 이 실제로 소비하는가 → `grep -rn "\.stock" ventago-app/src` 로 판정
- revendedor 구매 가드가 `allowSaleWithoutStock=true` 매장에서 어떻게 동작해야 하는가
  → 소매 판매와 같은 규칙이면 매장 설정을 존중해야 한다. 다르면 **사용자 결정 필요**

**등가성 근거**: `available == SUM(stocks.stock)` 이 로컬 642행 전수 일치 확인됨(70-01). 치환은 수치적으로 등가.
**완료 조건**: 위 체크리스트 1~6 + `70-01b-SUMMARY.md`. `grep -rn "p\.stock\|product\.stock\|products\.stock" api-ventago/src | grep -v spec | grep -v diagnostics` 결과가 **0줄**.
**위험**: 중. revendedor 구매 가드가 판매 차단 경로다 — 회귀 시 재판매자가 구매를 못 한다.

---

### S3 — 70-06: `trg_stocks_sync_product_cache` 폐기 [★ 승인 게이트]

Phase 70 의 핵심. 현행 트리거가 변형 판매마다 **마드레 부모 행을 UPDATE 로 잠근다** → 변형 20개의
판매가 부모 1행에서 직렬화. Phase 63(터미널 3,000대)이 정확히 여기서 막힌다.

**T0 게이트** — S2 의 grep 이 0줄인지 재확인. 아니면 중단.

**T1 경합 실측 (전 기준선)** — 원안은 `ventago_staging` + k6/pgbench 를 요구한다.
운영 내 스테이징 하네스(`loadtest/`, `api_staging:5012`)가 있으므로 이를 쓰되,
**시간이 부족하면 최소한 `pg_locks` 의 `products` 부모 행 대기 관측만이라도 전/후로 남긴다.**
수치 없이 "좋아졌다" 라고 쓰지 않는다 — 못 쟀으면 못 쟀다고 SUMMARY 에 적는다.

**T2 마이그레이션** `api-ventago/migrations/2026-08-03-retire-product-stock-cache.sql`
```sql
BEGIN;
DROP TRIGGER IF EXISTS trg_stocks_sync_product_cache ON stocks;
COMMENT ON COLUMN products.stock IS
  '[DEPRECADO 2026-08-03] Valor derivado. La verdad esta en stock_balances / v_stock_*. No leer en codigo nuevo.';
COMMIT;
```
- 컬럼 DROP 금지 / 함수 `stocks_sync_product_cache()` DROP 금지 (롤백 수단)
- 파일 하단에 **롤백 스크립트 + 원장 기준 `products.stock` 백필 쿼리**를 주석으로 동봉
- 적용 순서: **로컬 5432 먼저 → 검증 → 사용자 승인 → 운영 5434**
- 운영 적용은 `--single-transaction -v ON_ERROR_STOP=1`

**T3~T4** `diagnostics/stock-drift.service.ts` 의 주 지표를 캐시-원장 비교 → `v_stock_balance_drift` 로 교체.
`products.model.ts` 의 `stock` 속성에 deprecated 주석.

**T5 검증** 불변식 2종 0행 / 판매 1건 후 `stock_balances.available` 즉시 반영(트랜잭션+ROLLBACK) /
`pg_locks` 부모 행 대기 소멸 / **운영 배포 후 24시간 관찰**.

**게이트**: 운영 5434 적용 전 SQL 전문 + 예상 영향 행수를 제시하고 **사용자 승인**을 받는다.
**위험**: 높음. POS 판매 경로 직접 영향. 단 되돌릴 수 없는 단계는 없다(트리거 재생성 가능).

---

### S4 — 70-03 후속: 상품 삭제 백엔드 하드닝 (24h 관찰 기간에 병행)

출처: `.team/tasks/009-70-03-fk/task.md` (70-03 검수 minor). 대상은
`api-ventago/src/app/products/products.controller.ts` `deleteProduct` / `products.service.ts`.

| # | 항목 | 성격 |
|---|---|---|
| 1 | FK 거부가 PG 영문 원문(`insert or update on table ...`)으로 사용자에게 노출 → 스페인어 매핑 | **바로 수정 가능** |
| 2 | 마드레 삭제 시 자식이 고아가 됨 (`products.parent_id` = ON DELETE SET NULL). 현재 프론트는 경고만 | **제품 결정 필요**: "자식 있으면 거부" vs "자식 일괄 삭제 확인" |
| 3 | SKU 변경이 기존 자식 SKU 를 소급 갱신하지 않음 | **제품 결정 필요**: 의도인가 |
| 4 | `venta_suspendida_items.product_id` 가 SET NULL → 보류 판매 참조 끊김. 목록 API 에 정보가 없어 프론트 단독 판정 불가 | 백엔드 지원 필요 |

→ **1·4 는 먼저 처리, 2·3 은 사용자에게 물어본 뒤 처리.** 답이 늦어도 1·4 는 막히지 않는다.

**완료 조건**: 체크리스트 1~5 + `70-03b-SUMMARY.md`.

---

### S5 — 70-07: UAT + Trello 정리

**T1 불변식** 운영 5434 + 로컬 5432 에서 `v_stock_balance_drift` / `v_stock_tenant_leak` = 0.
0이 아니면 `stock_balances.updated_at` 으로 어느 스텝에서 깨졌는지 좁힌다.

**T2 배포 확인** Jenkins 최신 빌드 SUCCESS + 컨테이너 재생성 + 각 커밋이 `origin/main` 조상인지
`git merge-base --is-ancestor` 로 확인.

**T3 화면 검증 (브라우저)**

| 카드 | 확인 항목 |
|---|---|
| [Articulos fXUDii66](https://trello.com/c/fXUDii66) | Códigos madres 목록 수정/삭제 액션 표시·동작. 권한 없는 역할엔 비표시 |
| [Pasar a pdf 30zWO5C8](https://trello.com/c/30zWO5C8) | 확대 **90/100/110/125%** 각각에서 PDF 버튼 보임 + 실제 PDF 다운로드 |
| [Cargar varios diACgk5B](https://trello.com/c/diACgk5B) | 저장 후 폼 리셋, 지점만 보존 |
| [Agregar a 2 sucursales bklfCOX3](https://trello.com/c/bklfCOX3) | 같은 날 2번째 지점 입고 성공 (이번 배포분) |
| [Eliminar un ingreso LNBmJ2ZI](https://trello.com/c/LNBmJ2ZI) | 입고 삭제 **연속 5회** 눌러도 추가 차감 없음(멱등) |
| [Sucursal uyBUKfBM](https://trello.com/c/uyBUKfBM) | 지점 전환 유지, 재로그인 후에도 유지 |
| [Codigo Vista zTHHD941](https://trello.com/c/zTHHD941) | 코드 칼럼 표시 + hover 전체 코드 |

**T4 회귀 확인 (안 고친 것)** 견적·온라인 티켓 고객명 출력 / `allowSaleWithoutStock=true` 매장의 재고 없는 판매가
**여전히 되는지**(차단되면 회귀) / Stock Vistas 4탭 숫자 정합(변형 합 = 마드레, 지점 합 = 통합).

**T5 Trello** 통과 카드를 **Hechos Semanales 로 이동**. 아카이브·삭제 금지.
**T6** `70-UAT.md` 에 항목별 통과/실패 + 근거. 애매하면 애매하다고 쓴다. 실패는 후속 Plan 등록.

---

## 5. 사용자 승인이 필요한 지점 (미리 모아둠)

| 시점 | 무엇 |
|---|---|
| S1-a | cmux-team daemon(PID 3091) 종료 |
| S1-d | `feat/sku-serial` 등 origin 브랜치 삭제 (태그 백업 후 진행 예정) |
| S2 | revendedor 구매 가드의 `allowSaleWithoutStock` 취급 규칙 |
| S3 | **운영 5434 마이그레이션 적용** (SQL 전문 + 영향 행수 제시 후) |
| S4 | 마드레 삭제 시 자식 처리 정책 / SKU 소급 갱신 여부 |

## 6. 이 계획이 팀 계획과 다른 점 요약

- 병렬 5 태스크 → **순차 5 스텝**. 의존(S2→S3)이 사실상 직렬이라 병렬 이득이 없었다
- worktree 격리 → 저장소별 단일 브랜치 후 ff-merge
- Inspector 검수 → 스텝별 자기검증 체크리스트 6항목
- "push 는 Master 가" → **각 스텝마다 즉시 push + Jenkins·컨테이너 확인**
- 팀 잔재(worktree 7 · 태스크 브랜치 15 · daemon)를 **S1 에 명시적 청소 항목으로 편입**
- 70-01b(팀 4회 실패분)를 정식 스텝으로 승격 — 70-06 의 하드 게이트임을 문서에 못박음
