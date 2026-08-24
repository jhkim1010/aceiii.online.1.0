---
phase: 86-legacy-import-full-migration
type: spec
version: 3
supersedes: 86-SPEC.md (v2, 2026-08-20)
created: 2026-08-24
status: CONFIRMED — 사용자 결정 반영 완료
---

# Phase 86 v3 — 레거시 임포트 재설계

## 0. 왜 v3 인가

v2 는 **kandente4 한 매장**의 백업만 보고 썼다. 다른 매장(`serpenti`)을 실제로
복원해 재 보니 **전제 두 개가 무너졌고**, 그 위에 서 있던 TASK-2b 의 정당화도
함께 무너졌다. v2 는 참고로 남기되 아래가 권위다.

> **v2 를 그대로 구현했으면 생겼을 일**: `codigos_tmp` 블록만 건너뛰는 스트리밍
> 리더를 만들고 "이제 200MB 가능" 이라고 판단했을 것이다. serpenti 에서는
> 그 표가 5.4% 뿐이라 **아무것도 해결되지 않는다.**

---

## 1. 실측 (2026-08-24, `serpenti_20260813_214412.backup` → 로컬 PG18 복원)

67 테이블. 행 수:

```
vdetalle      782,575     codigos        11,805     online_ventas   4,859
codigos_tmp   298,098     cobranzacab    11,804     afip_factura    3,516
vcodes        151,637     gastos          9,263     corregidos      2,470
logs          128,014     todocodigos     7,741     cheques            78
ingresos       97,047     creditoventas   5,776     cobdetalles        63
fdetalles      40,849     vtags          12,563     gasto_info          0
fventas        20,750     logs(alerta=t)  4,587     crddetalle          0
clientes       16,408     usuarios            2     sucursal 종류       2
```

`screendetails2_id` (재고 뷰): **9,397행** — `stock>0` 3,357 / `stock<0` **1,699**

★ kandente4 와 규모가 다르다: `vdetalle` 41,407 → **782,575**.
  **매장별 편차가 설계 전제가 되어선 안 된다.**

### 팽창률 (백업 23개)

**x5.35 ~ x5.93.** 164MB 백업 → **877.8MB**.

---

## 2. 무너진 전제 둘

### ① "`codigos_tmp` 가 백업 용량의 대부분" (v2 §2.3 F1)

serpenti: 전체 SQL 260.2MB → `codigos_tmp` 제외 **246.1MB (94.6% 잔존)**.
그 표는 **5.4%** 뿐이고 부피는 `vdetalle` 782,575행이다.

→ **TASK-2b 를 "TOC 블록 건너뛰기" 로 구현하면 목표를 달성하지 못한다.**

### ② 재고를 `stockrep`(365일 롤링)으로 뽑는다 (v2 §2.2, D1)

**사용자 결정: `screendetails2_id` 뷰, 전 기간.**

| 뷰 | 창 | 계산 |
|---|---|---|
| `stockrep` (v2) | `(now - fecha) < 365` | 입고 − 판매 + 보정 |
| **`screendetails2_id`** (v3) | **없음 — 전 기간** | `(입고 + 보정) − 판매 − 예약` |

`screendetails2_id` 는 `bfallado`/`bmovido` 품목을 제외하고 `id_codigo`(PK)+`sucursal`
기준이다. 전 기간이 VentaGO(영구 잔액)와도 맞는다 —
v2 가 스스로 적었던 "롤링 창은 임포트 시점에만 의미가 있다" 는 모순이 사라진다.

★ 이름 주의: `screen_details_id` 가 아니라 **`screendetails2_id`**.
  ACE 에는 `screendetails*` 뷰가 12개 있다.
★ 다른 이름 정정: `gasto_infos` → `gasto_info`, `crddetalles` → `crddetalle`.

---

## 3. 사용자 결정 (2026-08-24)

| # | 결정 |
|---|---|
| 1 | 그룹 A/B/C 구조와 **업무 단위 원자 묶음** 채택 |
| 2 | `ingresos` 는 **참조용** — 재고를 움직이지 않는다 |
| 3 | **음수 재고는 0 으로 클램프** |
| 4 | 한 매장 자료가 다른 매장을 오염시키지 않을 것 (강조) |

### ★ 3번은 codex 권고와 반대다 — 기록해 둔다

codex: *"`screendetails2_id` 를 진실로 택했으면 0 클램프는 그 정의를 위반한다.
음수는 품절·미입고 판매·재고 결손을 나타낸다."*

사용자는 그것을 듣고 **0 을 선택했다.** 그대로 따른다. 단 **정보를 지우지는 않는다**:

- 저장값은 0 (또는 원장 행을 만들지 않음)
- **클램프된 건수와 품목 목록은 preview·결과·다운로드로 노출**
- 결과 화면이 "1,699건이 0 으로 저장됐다" 를 말한다

즉 **값은 사용자 결정을 따르고, 사실은 감추지 않는다.**

---

## 4. 그룹과 선택 단위

**선택은 원시 테이블이 아니라 업무 단위다** (codex HIGH).
테이블 단위로 고르게 하면 `vcodes` 만 넣고 `vdetalle` 를 빼는 조합이 가능해져
**품목 없는 판매**가 생긴다.

### A 그룹 — 항상, 선택 불가

| 단위 | 구성 |
|---|---|
| 상품과 카탈로그 | `codigos` · `todocodigos` · `tipos` · `color` · `origenes` · `empresas` |
| 고객과 판매원 | `clientes` · `vendedores` · `provincias` · `transportes` |

### B 그룹 — 업무 단위 선택 (★ = 원자적, 함께 들어간다)

| 단위 | 구성 | 선행 |
|---|---|---|
| 재고 초기값 | **뷰 `screendetails2_id`** (입력: `ingresos`·`vdetalle`·`corregidos`) | 상품, 지점 |
| 판매 | ★`vcodes` + ★`vdetalle` | — |
| 결제수단 | ★`vtags` + `cuentas` | 판매 |
| 팩투라·CAE | ★`fventas` + ★`fdetalles` + `afip_factura` | 판매 |
| 외상 | ★`creditoventas` + ★`crddetalle` + `cobranzacab` + `cobdetalles` + `cheques` | 판매, 고객 |
| 온라인 판매 | ★`online_ventas` | 판매, 고객 |
| 입고 이력 | ★`ingresos` | 상품 |
| 비용 | ★`gastos` + ★`gasto_info` | 사용자, 지점 |
| 시즌 | ★`temporadas` | — |

**규칙**: 자식을 고르면 조상이 자동으로 켜진다. 부모를 끄면 그것을 필요로 하는
것도 함께 꺼진다(반쪽 상태 금지). 부모 선택이 자식을 강제하지는 않는다.

### C 그룹

| 단위 | 구성 |
|---|---|
| 알림 | `logs WHERE alerta = true` (128,014 중 **4,587**) |

---

## 5. 오염 방지 — 8겹

사용자가 강조한 항목이다. **한 축이라도 요청값에 의존하면 그 축은 없는 것이다.**

| # | 축 | 내용 |
|---|---|---|
| 1 | 목적지 고정 | 모든 INSERT 의 `store_id` 는 **서버가** 넣는다. 파일의 값은 읽지도 않는다 |
| 2 | 매핑 키에 매장 | `legacy_entity_maps(store_id, entity, legacy_id)` UNIQUE — ACE id 는 매장마다 겹친다. 매장을 키에서 빼면 **두 매장이 서로의 id 를 덮는다** |
| 3 | 지점 소속 확인 | ACE `sucursal`(serpenti 2종) → `branch_id` 는 **그 지점이 목적지 매장의 것인지 DB 로 확인**한 뒤에만. FK 만으로는 못 막는다 |
| 4 | 지점 매핑 스냅샷 | 잡 시작 시 **불변으로 고정**. 실행 중 지점이 바뀌어도 일부 행만 다른 지점으로 가면 안 된다 |
| 5 | 원본 namespace | 같은 매장에 **다른 ACE 데이터셋**이 섞이지 않게. 동일 namespace 동시 실행 차단 |
| 6 | 배치마다 소유 증명 | **최종 검사만으로는 부족.** 매 배치 커밋 **전**에 확인 |
| 7 | 배치 조인으로 | 행별 확인 금지 — `vdetalle` 782,575행에서 N+1 이 된다 |
| 8 | 리스 | 매장별 `legacy_import_leases` (advisory lock 금지 — pgbouncer transaction pooling) |

---

## 6. 스트리밍 — TASK-2b 재정의

**"블록 건너뛰기" 가 아니라 "끝까지 스트리밍 + staging".**

```
업로드(diskStorage, 버퍼 금지)
  → pg_restore -f <tmpfile>            (파일로 두고 읽지 않는다)
  → createReadStream + 줄 단위 파싱     (허용된 COPY 블록만)
  → **staging 테이블**                  (뷰 계산이 여기서 일어난다)
  → 고정된 screendetails2_id 계산 SQL
  → 검증된 배치 INSERT (500행)
```

★ **staging 이 필수인 이유** (codex): `screendetails2_id` 는 **뷰**라 덤프에 데이터가
  없다. 계산하려면 입력 테이블(`ingresos`·`vdetalle`·`corregidos`·`codigos`)이
  실제로 있어야 한다. 파싱만으로는 불가능하다.

★ ACE 덤프는 `COPY ... FROM stdin` 형식이라 **물리적 줄 = 행**이다
  (값 안의 개행은 `\n` 이스케이프). 그래서 줄 단위 스트리밍이 성립한다.

★ 임시파일: 잡별 전용 디렉터리 · 예측 불가 이름 · 소유자 전용 권한 ·
  성공/실패/취소 **모든 경로에서 정리**. 디스크 quota + 동시 업로드 제한.
  164MB → 877.8MB 이므로 원본+변환본+staging 이 순간 수 GB 를 쓴다.

### 현재 상한 (v3 시점)

`MAX_FILE_BYTES` **65MB** · `MAX_DECOMPRESSED_BYTES` **400MB**
(65 × 5.93 ≈ 386MB). Node 문자열 상한 **512MB** 가 현 구조의 천장.
`upload-limits.spec.ts` 가 이 쌍을 묶는다. 스트리밍 완성 후 재계산한다.

---

## 7. 건수 표시

**"읽은 것" 과 "넣은 것" 은 다르다.** 읽은 수만 보여 주면 다 된 것으로 읽힌다.

테이블(=업무 단위)마다: `leído / insertado / duplicado / filtrado / rechazado`
+ 사유별 집계. 잡 완료 조건은 **정산이 맞을 때**:

```
읽음 = 삽입 + 중복 + 필터 + 거부      (단위마다 전부)
```

★ 거부 원문을 전부 저장하지 않는다 — PII·용량. **사유별 합계 + 제한된 샘플**.
★ 진행률은 **배치 커밋 성공 후에만** 증가시킨다.

---

## 8. v2 에서 폐기되는 것

| v2 | v3 |
|---|---|
| `stockrep` · 365일 롤링 창 | **`screendetails2_id` · 전 기간** |
| `codigos_tmp` 블록 스킵으로 200MB | **끝까지 스트리밍 + staging** |
| "기준선 합계 = `total_ingreso`" 검증 | 음수 클램프가 있으므로 재정의 필요 |
| 원시 테이블 단위 선택 | **업무 단위 원자 묶음** |
| 음수 0 클램프 (v2) → 보존 (codex) | **0 클램프** (사용자 결정) + 건수 노출 |

---

## 9. 남은 확인

1. 뷰 정의가 **매장마다 다를 수 있다** — 업로드된 `screendetails2_id` 정의의 해시를
   지원 목록과 대조하고, 모르는 정의는 **추정하지 말고 차단**
2. `borrado IS NOT TRUE` 와 `borrado = false` 는 **NULL 처리가 다르다** — 원본 뷰를
   정확히 재현할 것
3. 합계는 staging 에서 `bigint/numeric` 으로, VentaGO 컬럼 범위 검사 후 변환
4. 배치 재시도: deadlock · `40001` · lock timeout 은 배치 단위 제한 재시도
5. 덤프 출처 검증: PG 버전 · ACE 스키마 fingerprint · 필수 컬럼을 preview 에서

## 10. UI

목업: https://claude.ai/code/artifact/ffd90b56-f17e-49ec-91d7-1708069a3468
(다크 네이비+골드 단일 테마, 의존성 자동 선택, 결과 원장, 클램프 건수 노출)
