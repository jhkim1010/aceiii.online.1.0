# 74 — Tesorería 허브 재설계 (새 세션용 핸드오프)

작성 2026-08-10. **설계는 사용자와 확정됐고, CODEX 감수도 끝났다. 본체만 만들면 된다.**
앞선 맥락: `.planning/phases/73-external-audit-remediation/73-NEXT-7.md` (재고/리포트 — 별개 주제)

---

## 0. 먼저 읽을 것

- ★ **`user.roles` 는 slug 문자열 배열**이다(`['admin']`). 객체가 아니다.
  역할 집합은 **`ventago-app/src/configs/roles.ts` 단일 출처** — `isPrivilegedRole()` /
  `isSupervisorRole()` 를 쓴다. 이름을 다시 적으면 `store_owner`·`store_admin` 이
  화면에서만 빠진다(그 파일 주석이 이 사고를 경고한다. 나도 한 번 밟았다).
- ★ **프런트 가림은 UX 일 뿐이다.** 권한 경계는 백엔드가 JWT 의 store/branch 로
  계산해야 한다. 클라이언트가 보낸 branchId 를 믿으면 안 된다.
- ★ 커밋 전 `npx eslint <파일>` — 프런트는 **warning 도 빌드를 막는다**.

---

## 1. 사용자 요구 (원문 취지)

> "컴팩트한 스타일을 좋아한다. 정보가 너저분하게 널려 있는 건 원하지 않는다."

- `Estado de Caja` 하나에서 **지점별 카하 마지막 상태**(돈 얼마, 수표 몇 장)를 보고,
  각 옆의 `Ver detalle` 로 registro 로 내려간다.
- **Caja Fuerte 마지막 상태**도 같은 화면에. 출금 버튼 + `Ver detalle`(날짜별 집계).
- 공간이 되면 **수표**도 같은 탭에.

---

## 2. 확정된 설계 — 허브 + 드릴다운

지금 `Estado / Registros / Cheques` 는 **형제 탭**인데 실제로는 개요→상세 관계다.
그래서 "왜 3개인가"에 답이 없다. (2026-07-28 커밋 `da4ceb2` 가 기존 3개 페이지를
탭으로 감싼 것일 뿐, 정보 구조를 설계한 게 아니다.)

**CODEX 판단도 같다:** "허브가 더 낫다. 수표가 0행이고 Registros 는 조사·감사용이며
Estado 가 첫 질문을 대표하므로 형제 탭의 근거가 약하다."

```
┌─ Caja Fuerte ────────────────────────────────────────────┐
│ coolsistema  $11.931.544  [Retirar] [Ver detalle]        │
│ HELGUERA             $0                                   │
└──────────────────────────────────────────────────────────┘
┌─ Cajas ──────────────────────────────────────────────────┐
│ coolsistema                                 수표 3장 $X   │  ← 지점 헤더
│   Caja 1     $12.000   Abierta 09/08  ⚠+7  [Ver detalle] │
│   JuanaCaja $773.900   Abierta 07/08  ⚠+4  [Ver detalle] │
│ HELGUERA                                    수표 —        │
│   Caja HELGUERA  $0    Cerrada 23/04       [Ver detalle] │
└──────────────────────────────────────────────────────────┘
```

### 확정 사항 (사용자 승인)

| 항목 | 결정 | 이유 |
|---|---|---|
| 묶는 단위 | **지점 헤더 + 그 밑에 서랍(caja)별** | 지점으로 합치면 어느 서랍이 미마감인지 사라진다. coolsistema 에 카하 2개 |
| 수표 위치 | **지점 헤더에만** | `cheques` 에 `cash_register_id` 가 **없다**. `branch_id` 뿐이라 카하별로 쪼갤 근거가 DB 에 없다 |
| 수표 표시 | 0행이면 접어서 한 줄 | 현재 **전 매장 0행**(미사용). 자리를 미리 잡으면 컴팩트 취지와 반대 |
| 마지막 상태 정의 | 열린 세션 있으면 그것, 없으면 마지막 마감 | |
| 출금 버튼 이름 | `Retirar` (중립) | 출금 경로가 하나뿐이라 용도로 이름을 박으면 다른 목적 출금의 이력이 실제와 어긋난다 |
| 출금 용도 구분 | **사유(Motivo) 프리셋 칩** | 이미 구현·배포됨. `Retiro del propietario` / `Depósito bancario` / `Pago a proveedor` / `Gasto` |
| 기존 딥링크 | `/control-de-caja`, `/cheques`, `/caja-fuerte` **유지** | 허브가 상세를 대체할 필요 없다 |

### 허브에 넣지 말 것 (CODEX)

> "모든 기능을 한 화면에 펼친다" 가 아니다. 허브는 **요약과 즉시 필요한 액션만**.
> 세션별 operations · 과거 마감 · 금고 개별 이력 · 수표 목록/편집은 **드릴다운**.

---

## 3. 만들어야 할 것

### 3-A. `GET /cash-register/overview` (백엔드, 핵심)

지금 `AllCajasOverview` 는 열린 세션마다 `/cash-register/:id/resume` 를 `Promise.all`
로 부른다 — **N+1**. 서랍 단위 단일 SQL 로 대체한다.

CODEX 권장 형태 (테이블·컬럼명은 실제에 맞춰 조정할 것):

```sql
WITH scoped_boxes AS (
  SELECT b.id, b.name, b.branch_id
  FROM boxes b
  JOIN branches br ON br.id = b.branch_id
  WHERE br.store_id = :store_id
    AND b.branch_id = ANY(:allowed_branch_ids)
),
chosen AS (                              -- 서랍마다 대표 세션 1개
  SELECT b.id AS box_id, b.name AS box_name, b.branch_id,
         cr.id AS cash_register_id, cr.date, cr.start_time,
         cr.closing_time, cr.initial_amount, cr.unclosed_count
  FROM scoped_boxes b
  LEFT JOIN LATERAL (
    SELECT r.*,
           count(*) FILTER (WHERE r.closing_time IS NULL) OVER () AS unclosed_count
    FROM cash_registers r
    WHERE r.box_id = b.id
    ORDER BY (r.closing_time IS NULL) DESC,   -- 열린 것 우선
             r.date DESC, r.start_time DESC NULLS LAST, r.id DESC
    LIMIT 1
  ) cr ON true
),
operation_totals AS (
  SELECT o.cash_register_id,
         COALESCE(SUM(CASE
           WHEN o.type IN ('venta','ingreso') THEN o.amount
           WHEN o.type IN ('gasto','retiro')  THEN -o.amount
           ELSE 0 END), 0) AS operation_balance
  FROM box_operations o
  JOIN chosen c ON c.cash_register_id = o.cash_register_id
  GROUP BY o.cash_register_id
)
SELECT ...   -- box + branch + 대표세션 + (initial_amount + operation_balance) AS saldo
```

★ **페이징 단위는 세션이 아니라 `box`** 다. 지금 프런트의 `pageSize: 50` 은
"서랍 50개"가 아니라 **열린 세션 50개**라, 한 서랍에 미마감이 몰리면 다른 서랍이
조용히 잘리고 `stalePrevious` 도 실제보다 작아진다(매장 6 은 이미 미마감 13건).
UI 에 누락 표시도 없다.

★ `deleted_at` 컬럼 유무는 **확인하고** 쓸 것 (CODEX 예시에 들어 있으나 미확인).

### 3-B. `GET /cheques/summary-by-branch` (백엔드, 작음)

`cheques.service.getSummary(storeId)` 가 이미 `GROUP BY status` 로 매장 전체를 준다.
여기에 `branch_id` 를 추가한 형태. 현재 데이터 0행이라 빈 응답이 정상.

### 3-C. `GET /caja-fuerte/:id/daily` (후속)

"날짜별로 얼마씩 모였는지" 용. 지금 API 는 개별 행만 준다. 데이터는 충분하다:

```
2026-08-09 ingreso  +2.193.100
2026-08-06 ingreso     +18.000
2026-08-01 retiro          −1
...
```

### 3-D. 프런트 `Estado de Caja` 허브

- `BoxResume` 를 재구성. 지금은 `CajaFuerteSummaryCard` + `AllCajasOverview` +
  `BoxSummaryCard`(내 카하 상세) + `BoxOperationCard` 4블록이다.
- 허브에서는 **내 카하도 목록의 한 줄**로 통일하고, 상세/액션은 드릴다운으로.
  (그러면 `excludeBoxId` 회피 로직 자체가 필요 없어진다 — 아래 §5 참조)

---

## 4. 오늘 배포된 것 (이어서 작업할 때 전제)

| 커밋 | 내용 |
|---|---|
| front `cc41216` | **출금 버튼이 아무에게도 안 보이던 버그** — `CajaFuerteView` 만 roles 를 객체로 취급(`r.slug`)해 항상 false. + Registros 카드에서 바로 출금 |
| front `6a72e8e` | 같은 카하 2번 노출 제거 시도 + Caja Fuerte 카드를 Registros → **Estado** 로 이동 |
| front `4d73891` | **CODEX 지적 반영**: 위 중복 제거가 무효였음(§5) + 역할 판정을 `isPrivilegedRole()` 로 |
| front `bd5f5d8` | `/caja-fuerte` 기본 지점을 **내 지점**으로 (DB 콜레이션 `C.UTF-8` 라 `HELGUERA` 가 이름순 1등 → 잔액 0 → 버튼 회색이었다) |
| api `b89d48d` / front `1f4c2fd` | **자동마감이 서랍의 미마감을 전부 닫는다** — §6 |

---

## 5. ★ CODEX 미해결 지적 (허브 만들 때 반드시 반영)

| 등급 | 지적 |
|---|---|
| MEDIUM | `pageSize: 50` 이 서랍이 아니라 **세션** 50개 → 조용한 잘림. §3-A |
| MEDIUM | `new Date().toISOString().slice(0,10)` 로 현지 날짜 비교 → **UTC 라 매장 타임존과 어긋난다**. 서버의 `getNowByTimezone(timezone)` 과 맞춰야 한다 |
| MEDIUM | 최초 로딩 때 전체 목록을 한 번 불필요하게 요청하고 **중복이 잠깐 보인다** (resume 이 늦게 와서 `excludeBoxId` 가 나중에 적용됨) → 허브에서 목록을 한 번만 읽으면 사라진다 |
| HIGH(구조) | 권한을 role 이름이 아니라 **function slug** 로 분리해야 한다: `ver-estado-tesoreria` / `ver-cajas` / `ver-resumen-de-su-caja` / `ver-caja-fuerte` / `retirar-caja-fuerte` / `ver-cheques`. **DB 시드가 필요해 별도 작업.** 지금은 `isPrivilegedRole()` 로 임시 통일 |
| — | 백엔드 `GET /caja-fuerte/store` 는 **admin/superadmin 전용**이다. 감독자(gerente)에게 금고를 열려면 **백엔드부터** 열어야 하고, 그때 **지점 스코프**를 넣어야 한다(남의 지점 금고가 보이면 안 된다) |

### ★ 내가 밟은 함정 — 반복하지 말 것

"같은 카하가 두 번 나온다"를 고칠 때 **세션 id 로 제외**했다. 그런데 한 서랍에
미마감 세션이 여러 개 쌓인다(Caja 1 에 8건). 현재 세션만 빼면 **그 다음 오래된 세션이
대표로 올라와** 같은 서랍이 여전히 두 번 나오고, 게다가 **지난 날짜 잔액을 현재인 것처럼**
보여준다 — 원래 문제보다 나빴다. → 반드시 **물리 서랍(boxId)** 단위로 다뤄라.

---

## 6. 자동마감 변경 (오늘 배포, api `b89d48d`)

종전: `findOne({ userId, closingTime: null, date < today })` — 자기 세션 **하나만**,
`order` 없어 비결정적, 카하 여는 순간에만 실행.
→ 서랍은 물리적으로 하나인데 사용자마다 세션이 생기므로 **백로그를 못 비운다.**
운영 실측: 매장 6 미마감 13건, Caja 1 하나에 8건(유저 5명).

**지금:** 그 **서랍**의 미마감을 오래된 것부터 **전부** 닫는다. 탐지도 `boxId` 를 받으면
서랍 기준(탐지만 userId 면 자기 미마감 없는 사람이 열 때 그냥 지나간다).

### ★ 금액 규칙 (사용자 결정 — 바꾸지 말 것)

**초기금은 이체하지 않고 실제 movements 만 정산한다.**

초기금은 같은 서랍의 같은 현금을 매일 다시 선언한 값이라 세션별로 합치면 **이중 계산**이다.
실측(Caja 1): 세션 8개 잔액 합 **580.000** 인데 재선언 초기금을 빼면 실제 현금은
**500.000** 수준. 전부 이체하면 금고가 80.000 부풀려진다.

→ 정산 대상은 `venta + ingreso − gasto − retiro` 뿐. `movNeto <= 0` 이면 이체 없이 닫기만
   한다(금고에 음수를 넣을 수 없고, 실사 부족은 사람 판단 몫).

기존 백로그 13건은 **마이그레이션으로 건드리지 않는다** — 다음에 그 서랍을 여는 순간
사람이 현금을 세면서 정리된다(사용자 결정).

**아직 실전 확인 안 됨**: 다음에 Caja 1 을 열 때 "7 cajas anteriores cerradas" 토스트가
뜨고 금고로 **488.000** 만 가는지 확인할 것. (580.000 이 가면 금액 규칙이 안 먹은 것이다.)

---

## 7. 검증 방법

- 프런트: `npx eslint <파일>` (warning 도 빌드 차단) + `npx tsc --noEmit`
- 백엔드: `npx tsc --noEmit -p tsconfig.json`.
  `src/app/cashRegister`·`caja-fuerte` 에는 **spec 이 0개**다 — 새 endpoint 를 만들면
  `test/family/` 하네스(실 PG)로 붙이는 것을 권한다. 조회 전용이면 `withOrmRollback(fn, { joinReads: true })`.
  ★ 쓰기 경로에서는 `joinReads` 를 켜지 마라 — `transaction` 인자 누락이 안 보인다.
- 배포 확인: Jenkins `api-new-coolsistema` / `front-coolsistema` → `Finished: SUCCESS` +
  커밋 SHA grep + 컨테이너 재생성.
