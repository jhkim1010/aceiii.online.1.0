# 74 — Tesorería 허브: 본체 구현 완료 (2026-08-10)

`74-HANDOFF.md` 의 §3(만들어야 할 것)을 전부 만들어 배포했다.
**다음 세션은 이 파일 § "남은 것" 부터 본다.** 설계 근거·자동마감 금액 규칙은
여전히 `74-HANDOFF.md` 가 원본이다.

| | 커밋 | Jenkins |
|---|---|---|
| api-ventago | `702278c` | api-new-coolsistema **#654 SUCCESS** |
| ventago-app | `b7331e2` | front-coolsistema **#584 SUCCESS** |

컨테이너 재생성 확인(`api_ventago` healthy / `ventagoapp` up), 라우트 3개 모두
`RouterExplorer` 로그에 매핑 확인, 미인증 요청은 401(404 아님).

---

## 1. 만든 것

### 3-A `GET /cash-register/overview` ✅

`cashRegister.service.getTesoreriaOverview(user)` — 서랍 단위 단일 SQL.

- `scoped_boxes` → `LEFT JOIN LATERAL` 로 서랍마다 대표 세션 1개
  (`(closing_time IS NULL) DESC, date DESC, start_time DESC NULLS LAST, id DESC`)
- 같은 LATERAL 안의 `count(*) FILTER (WHERE closing_time IS NULL) OVER ()` 로 그 서랍의
  미마감 **전체** 개수 (윈도우는 ORDER BY/LIMIT 이전에 계산된다 — CODEX 확인)
- `box_operations` 합계 LATERAL 로 잔액까지 한 쿼리에
- 응답에 `today`(매장 타임존) 동봉 → 프런트가 UTC 로 "오늘"을 계산하지 않는다
- 지점 스코프는 JWT 기준. `deleted_at` 은 **없다** — `boxes.is_deleted` 를 쓴다(핸드오프 §3-A ★ 해소)

★ **`= ANY(:branchIds)` 를 쓰면 안 된다.** Sequelize 의 `:name` 치환은 배열을 배열
리터럴이 아니라 **콤마 목록**으로 펼쳐서 `ANY(1,2)` 가 된다 → 문법 오류.
`IN (:branchIds)` 를 쓴다. 초안에 이 결함이 있었고 family 스위트가 잡았다.

### 3-B `GET /cheques/summary-by-branch` ✅

지점별 `EN_CARTERA` 집계. 필드명이 `porVencer7d` 가 아니라 **`urgente`** 다 —
"7일 내 만기 **+ 이미 지난 것**" 을 함께 센다. 기한이 지난 수표가 가장 급한데 빼면
화면에서 사라지므로, 집계를 좁히는 대신 이름을 사실에 맞췄다.
만기 기준일은 `CURRENT_DATE`(DB 세션 TZ) 가 아니라 **매장 타임존 날짜**를 바인딩한다.

### 3-C `GET /caja-fuerte/:id/daily` ✅

날짜별 `ingreso`/`retiro`/`neto`/`count`. 버킷도 **기간 하한도** 매장 타임존 달력 기준
(`NOW() - N*24h` 로 자르면 `days=1` 이 "오늘"이 아니라 "최근 24시간"이 되어 버킷이 갈린다).

### 3-D 프런트 허브 ✅

`BoxResume` = 2블록. `CajaFuerteSummaryCard`(지점당 한 줄) + `CajasOverviewCard`.
`AllCajasOverview` 는 **삭제**했다(편집 대상이 두 곳에 남으면 갈라진다).

- `Ver detalle` 은 **인라인 확장**(`BoxInlineDetail`)이다. 페이지 이동이 아니다 —
  `/control-de-caja/detalle/:id` 는 `control-de-cajas` 모듈로 막혀 있어 그쪽으로만 보내면
  그 모듈이 없는 vendedor 가 **자기 카하 마감·movimiento 를 통째로 잃는다.**
- 내 서랍은 처음 진입 시 자동으로 펼쳐진다(작업대이므로). 내 서랍이 **바뀌었을 때만** 다시 펼친다.
- 남의 서랍은 `readOnly` — 마감/movimiento 버튼이 없다.
- `excludeBoxId` 는 사라졌다(핸드오프 §5 ★ 함정 해소).

---

## 2. 권한 누수 정리 (허브가 노출면을 넓혀서 같이 닫았다)

| 경로 | 종전 | 지금 |
|---|---|---|
| `GET /cash-register/:id/resume` | `findByPk(id)` — 인증만 되면 **남의 매장** 세션 잔액을 읽었다 | 매장 + 지점 스코프 |
| `POST /cash-register/close/:id` | id 만으로 마감 — 남의 매장 카하를 닫을 수 있었다 | 같은 스코프. 시스템 경로(터미널 삭제)는 `closeCashRegisterInternal` 로 분리 |
| `GET /caja-fuerte/:id/daily` | (신규) | 매장 + **지점** 스코프 |
| `GET /box-operation` | — | Phase 67 에서 이미 닫혀 있었다 |

`src/common/tenant/branch-scope.util.ts` 가 지점 스코프 **단일 출처**다.
`branches` 로 조인해 매장 소속까지 확인하므로, 호출부가 `store_id` 조건을 빠뜨려도
남의 매장 지점 id 가 새지 않는다. **새 조회 엔드포인트는 반드시 이걸 쓴다.**

---

## 3. 검증

`test/family/tesoreria-{overview,cheques,caja-fuerte-daily}.family-spec.ts` — **실 PG, 16건**
(`BEGIN … ROLLBACK`, 조회 전용이라 `joinReads: true`).

```bash
npx jest --config ./test/family/jest-family.json --runInBand --testPathPattern tesoreria
```

덮은 것: 서랍 단위 행 / 대표 세션 선택(열린 것 우선 — **더 최근 마감이 있어도**) /
잔액이 대표 세션 것만 / stalePrevious / 세션 없는 서랍은 `saldo: null` / 지점 스코프 /
fail-closed / 삭제된 서랍 제외 / 매장 타임존 today / **상세 IDOR(타 매장 + 타 지점)**.

프런트: `npx tsc --noEmit` + `npx eslint`(warning 도 빌드 차단) 통과.

---

## 4. 남은 것

### 4-A function slug 분리 (CODEX HIGH, **DB 시드 필요**)

권한을 role 이름이 아니라 function slug 로 나눠야 한다:
`ver-estado-tesoreria` / `ver-caja-fuerte` / `retirar-caja-fuerte` / `ver-cheques`.

지금은 **기존 slug 두 개**로 게이팅한다:
- `ver-cajas` 있으면 → 전체 목록
- 없고 `ver-resumen-de-su-caja` 만 있으면 → **자기 서랍 한 줄만** (`ownOnly`)

★ 하나로 합치지 마라. `accountant` 는 `ver-resumen-de-su-caja` 는 있고 `ver-cajas` 는
없다 — 합치면 그 역할이 화면을 통째로 잃는다.

### 4-B `GET /caja-fuerte/store` 는 여전히 admin/superadmin 전용

감독자(gerente)에게 금고를 열려면 **백엔드부터** 열어야 하고, 그때 지점 스코프를
넣어야 한다(`branch-scope.util` 사용). 프런트의 `isPrivilegedRole` 게이트는 그 다음에 넓힌다.

### 4-C 자동마감 금액 규칙 — **아직 실전 확인 안 됨**

다음에 Caja 1 을 열 때 "7 cajas anteriores cerradas" 토스트가 뜨고 금고로 **488.000 만**
가는지 확인할 것. 580.000 이 가면 초기금 제외 규칙이 안 먹은 것이다.
(규칙 근거는 `74-HANDOFF.md` §6 — 사용자가 직접 정했다. 임의로 바꾸지 않는다.)

### 4-D 성능 — 지금은 조치 불필요 (근거 기록)

CODEX 가 인덱스 추가를 권했으나 운영 실측이 작다: `cash_registers` 205행 /
서랍 14개 / 서랍당 최대 60행, `box_operations` 183행, `caja_fuerte_operations` 74행.
필요한 인덱스는 이미 있다 — `idx_cash_registers_store_box`,
`idx_box_operations_cash_register_id`, `idx_cfo_caja_fuerte`.
서랍당 수천 행 규모가 되면 그때 `cash_registers(box_id) WHERE closing_time IS NULL`
부분 인덱스를 검토한다.

허브 첫 로딩 요청 수: overview + cheques + resume = **3개**, 자기 서랍 자동 펼침까지
포함하면 5개. 종전은 열린 세션 수만큼(N+1). pool 압박을 측정한다면 이 5개가 기준이다.
