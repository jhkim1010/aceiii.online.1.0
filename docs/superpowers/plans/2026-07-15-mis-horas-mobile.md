# Mis horas (판매원 앱 본인 근무시간) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 판매원이 폰에서 이번 달 일자별 근무시간 + 총계 + 받은 vale(adelanto) 총액을 보고, 하루를 탭하면 그날 출퇴근 세부 기록을 확인한다.

**Architecture:** 백엔드에 전용 엔드포인트 `GET /mobile/attendance/month` 1개를 추가한다. `MobileAttendanceController`가 `AttendanceService`(근무시간)와 `AdelantoService`(vale)를 `Promise.all`로 합성한다 — 서비스 간 직접 호출 없음. 세션을 `days[]`에 동봉해 앱은 화면 진입 시 1회만 호출하고, 바텀시트는 네트워크 없이 연다. 앱은 기존 `features/attendance/` 구조를 따라 DTO/Repository/Provider/View를 추가하고, 홈 아바타를 팝업 메뉴로 바꾼다.

**Tech Stack:** NestJS 11 + Sequelize(raw query) + PostgreSQL 18 / Flutter + Riverpod + go_router + Dio

**Spec:** `docs/superpowers/specs/2026-07-15-mis-horas-mobile-design.md`

## Global Constraints

- **스키마 변경 금지.** 이 기능은 마이그레이션이 없다. 새 테이블/컬럼/인덱스를 만들지 않는다.
- **기존 메서드 수정 금지.** `sellerMonthSummary`, `listSessions`, `report`는 건드리지 않는다 (관리자 리포트 회귀 위험). 신규 메서드만 추가한다.
- **TZ:** 일자 그룹핑·시각 표시는 반드시 **매장 TZ**(`stores.timezone`, 매장마다 다름 — `America/Argentina/Buenos_Aires` / `America/Bogota` 공존) 기준. SQL에서 `AT TIME ZONE :tz`로 변환한다. 앱에서 TZ를 재계산하지 않는다.
- **vale 집계 기준:** `payroll_period = :month AND status = 'approved'`. `requested_at` 아님.
- **판매원 미연결 유저(admin 등):** 예외를 던지지 않고 빈 결과를 반환한다 (기존 `sellerMonthSummary` / `listOwn` 계약).
- **IDOR:** 클라이언트는 `sellerId`를 보내지 않는다. JWT `userId` → `Sellers.linkedUserId`로만 도출한다.
- 주석은 한국어, 함수/변수명은 영어.
- 백엔드 커밋 = `api-ventago` repo, 앱 커밋 = `mobile-sales-app` repo (nested repo — 별도 push 필요).

---

## File Structure

**api-ventago**
- Modify: `src/app/attendance/attendance.service.ts` — `sellerMonthDetail()` 추가
- Modify: `src/app/attendance/attendance.service.spec.ts` — `sellerMonthDetail` 테스트 추가
- Modify: `src/app/adelanto/adelanto.service.ts` — `monthApprovedTotalForUser()` 추가
- Create: `src/app/adelanto/adelanto.service.spec.ts` — 신규 메서드 테스트
- Modify: `src/app/mobile/attendance/mobile-attendance.controller.ts` — `GET month` 라우트 + 두 서비스 합성
- Modify: `src/app/mobile/mobile.module.ts` — `AdelantoModule` import 추가

**mobile-sales-app**
- Modify: `lib/features/attendance/data/attendance_dto.dart` — `MonthDetail`/`DayHours`/`WorkSession`/`AdelantoTotal`
- Modify: `lib/features/attendance/data/attendance_repository.dart` — `getMonthDetail()`
- Modify: `lib/features/attendance/providers/attendance_provider.dart` — `selectedMonthProvider`/`monthDetailProvider`
- Create: `lib/features/attendance/views/my_hours_screen.dart` — 화면 + 바텀시트
- Modify: `lib/router/app_router.dart` — `/mis-horas` 라우트
- Modify: `lib/features/home/views/home_screen.dart` — 아바타 팝업 메뉴
- Create: `test/my_hours_test.dart` — DTO 파싱 테스트

---

## Task 1: `AttendanceService.sellerMonthDetail` — 매장 TZ 일자별 집계

**Files:**
- Modify: `api-ventago/src/app/attendance/attendance.service.ts`
- Test: `api-ventago/src/app/attendance/attendance.service.spec.ts`

**Interfaces:**
- Consumes: 기존 private `storeTimezone(storeId)`, `this.sellerModel`, `this.sequelize`
- Produces:
  ```ts
  type WorkSessionRow = { id: number; in: string; out: string | null;
                          inLocal: string; outLocal: string | null; seconds: number };
  type DayHours = { date: string; seconds: number; open: boolean; sessions: WorkSessionRow[] };
  type MonthDetail = { month: string; totalSeconds: number; openCount: number; days: DayHours[] };

  async sellerMonthDetail(userId: number, month: string): Promise<MonthDetail>
  ```

- [ ] **Step 1: 기존 spec 파일의 mock 구조를 확인**

`attendance.service.spec.ts`는 positional mock 패턴이다. 파일 상단(1–45행)을 읽어 `sellerModel`, `sequelize`, `storeModel` mock이 어떻게 주입되는지 확인한다. 특히 `sequelize.query`가 어떻게 스텁되는지(기존 `reportRows` 변수) 확인한다.

Run: `sed -n '1,80p' src/app/attendance/attendance.service.spec.ts`

- [ ] **Step 2: 실패하는 테스트를 작성**

`attendance.service.spec.ts`의 `describe('AttendanceService', ...)` 안에 추가한다.

**이 테스트가 검증하는 것**: `sequelize.query`를 목으로 막고 **JS 쪽 그룹핑/합산/정렬/빈 결과 계약**만 본다.
**검증하지 못하는 것**: SQL의 TZ 변환 의미 — 목은 준 행을 그대로 돌려주므로 `AT TIME ZONE`이 틀려도 통과한다. 마지막 테스트는 SQL 문자열에 `AT TIME ZONE`과 바인딩이 들어갔는지만 확인하는 얕은 가드다. **실제 TZ 동작은 Step 6에서 DB로 검증한다.**

```ts
describe('sellerMonthDetail', () => {
  // raw SQL 이 돌려주는 행 모양 (local_date 는 매장 TZ 로 이미 변환된 값)
  function row(over: any = {}) {
    return {
      id: over.id ?? 1,
      check_in_at: over.check_in_at ?? new Date('2026-07-15T11:02:00Z'),
      check_out_at: over.check_out_at ?? new Date('2026-07-15T15:05:00Z'),
      local_date: over.local_date ?? '2026-07-15',
      in_local: over.in_local ?? '08:02',
      out_local: over.out_local ?? '12:05',
      seconds: over.seconds ?? 14580,
    };
  }

  it('점심으로 나뉜 세션 2개를 하루 1행으로 합산한다 (점심 제외)', async () => {
    sellerModel.findOne.mockResolvedValue({ id: 7, storeId: 6 });
    storeModel.findByPk.mockResolvedValue({ timezone: TZ });
    sequelize.query.mockResolvedValue([
      row({ id: 1, local_date: '2026-07-15', in_local: '08:00', out_local: '12:00', seconds: 14400 }),
      row({ id: 2, local_date: '2026-07-15', in_local: '13:00', out_local: '18:00', seconds: 18000 }),
    ]);

    const res = await service.sellerMonthDetail(16, '2026-07');

    expect(res.days).toHaveLength(1);
    expect(res.days[0].date).toBe('2026-07-15');
    // 점심(12:00~13:00) 은 세션 밖이라 자동 제외 — 4h + 5h = 9h
    expect(res.days[0].seconds).toBe(32400);
    expect(res.days[0].sessions).toHaveLength(2);
    expect(res.totalSeconds).toBe(32400);
  });

  it('열린 세션은 open=true 이고 경과 초가 포함된다', async () => {
    sellerModel.findOne.mockResolvedValue({ id: 7, storeId: 6 });
    storeModel.findByPk.mockResolvedValue({ timezone: TZ });
    sequelize.query.mockResolvedValue([
      row({ id: 3, check_out_at: null, out_local: null, seconds: 3600 }),
    ]);

    const res = await service.sellerMonthDetail(16, '2026-07');

    expect(res.days[0].open).toBe(true);
    expect(res.days[0].sessions[0].out).toBeNull();
    expect(res.days[0].sessions[0].outLocal).toBeNull();
    expect(res.days[0].seconds).toBe(3600);
    expect(res.openCount).toBe(1);
  });

  it('days 는 날짜 내림차순 (최근 먼저)', async () => {
    sellerModel.findOne.mockResolvedValue({ id: 7, storeId: 6 });
    storeModel.findByPk.mockResolvedValue({ timezone: TZ });
    sequelize.query.mockResolvedValue([
      row({ id: 1, local_date: '2026-07-11', seconds: 100 }),
      row({ id: 2, local_date: '2026-07-15', seconds: 200 }),
      row({ id: 3, local_date: '2026-07-14', seconds: 300 }),
    ]);

    const res = await service.sellerMonthDetail(16, '2026-07');

    expect(res.days.map((d: any) => d.date)).toEqual(['2026-07-15', '2026-07-14', '2026-07-11']);
    expect(res.totalSeconds).toBe(600);
  });

  it('판매원 미연결 유저는 빈 결과 (throw 안 함)', async () => {
    sellerModel.findOne.mockResolvedValue(null);

    const res = await service.sellerMonthDetail(999, '2026-07');

    expect(res).toEqual({ month: '2026-07', totalSeconds: 0, openCount: 0, days: [] });
    expect(sequelize.query).not.toHaveBeenCalled();
  });

  it('매장 TZ 와 월 경계를 SQL 에 바인딩한다', async () => {
    sellerModel.findOne.mockResolvedValue({ id: 7, storeId: 6 });
    storeModel.findByPk.mockResolvedValue({ timezone: TZ });
    sequelize.query.mockResolvedValue([]);

    await service.sellerMonthDetail(16, '2026-07');

    const [sql, opts] = sequelize.query.mock.calls[0];
    // 일자 그룹핑이 매장 TZ 기준이어야 한다 (DB 세션 TZ 아님)
    expect(sql).toContain('AT TIME ZONE');
    expect(opts.replacements).toMatchObject({ sellerId: 7, tz: TZ, monthStart: '2026-07-01' });
  });
});
```

- [ ] **Step 3: 테스트를 돌려 실패를 확인**

Run: `cd api-ventago && npx jest src/app/attendance/attendance.service.spec.ts -t sellerMonthDetail`
Expected: FAIL — `service.sellerMonthDetail is not a function`

- [ ] **Step 4: `sellerMonthDetail` 구현**

`attendance.service.ts`의 `sellerMonthSummary` 메서드 **바로 아래**에 추가한다 (기존 메서드는 수정하지 않는다).

```ts
  // ── 판매원 본인 월 근무시간 상세 (모바일 앱 /mobile/attendance/month) ──
  // sellerMonthSummary 는 총계만 준다. 이쪽은 일자별 + 세션 목록까지.
  // 일자 그룹핑은 매장 TZ 기준(AT TIME ZONE) — timestamptz 를 DB 세션 TZ 로
  // 비교하면 월/일 경계 punch 가 엉뚱한 날에 잡힌다.
  async sellerMonthDetail(
    userId: number,
    month: string,
  ): Promise<{
    month: string;
    totalSeconds: number;
    openCount: number;
    days: Array<{
      date: string;
      seconds: number;
      open: boolean;
      sessions: Array<{
        id: number;
        in: string;
        out: string | null;
        inLocal: string;
        outLocal: string | null;
        seconds: number;
      }>;
    }>;
  }> {
    const seller = await this.sellerModel.findOne({
      where: { linkedUserId: userId },
    });
    if (!seller) {
      // 판매원 미연결(admin 등) → 에러 대신 빈 결과 (sellerMonthSummary 와 동일 계약)
      return { month, totalSeconds: 0, openCount: 0, days: [] };
    }

    const tz = await this.storeTimezone(seller.storeId);
    const monthStart = `${month}-01`;

    const rows = await this.sequelize.query<{
      id: number;
      check_in_at: Date;
      check_out_at: Date | null;
      local_date: string;
      in_local: string;
      out_local: string | null;
      seconds: number;
    }>(
      `SELECT sa.id,
              sa.check_in_at,
              sa.check_out_at,
              ((sa.check_in_at AT TIME ZONE :tz)::date)::text AS local_date,
              to_char(sa.check_in_at AT TIME ZONE :tz, 'HH24:MI') AS in_local,
              to_char(sa.check_out_at AT TIME ZONE :tz, 'HH24:MI') AS out_local,
              EXTRACT(EPOCH FROM (COALESCE(sa.check_out_at, now()) - sa.check_in_at))::int AS seconds
         FROM seller_attendance sa
        WHERE sa.seller_id = :sellerId
          AND sa.check_in_at >= (:monthStart::timestamp AT TIME ZONE :tz)
          AND sa.check_in_at <  ((:monthStart::timestamp + INTERVAL '1 month') AT TIME ZONE :tz)
        ORDER BY sa.check_in_at DESC`,
      {
        replacements: { sellerId: seller.id, tz, monthStart },
        type: QueryTypes.SELECT,
      },
    );

    // local_date 기준 그룹핑 (rows 는 이미 check_in_at DESC)
    const byDate = new Map<
      string,
      {
        date: string;
        seconds: number;
        open: boolean;
        sessions: Array<{
          id: number;
          in: string;
          out: string | null;
          inLocal: string;
          outLocal: string | null;
          seconds: number;
        }>;
      }
    >();

    let openCount = 0;

    for (const r of rows) {
      const isOpen = r.check_out_at === null;
      if (isOpen) {
        openCount += 1;
      }

      const secs = Number(r.seconds) || 0;
      let day = byDate.get(r.local_date);
      if (!day) {
        day = { date: r.local_date, seconds: 0, open: false, sessions: [] };
        byDate.set(r.local_date, day);
      }
      day.seconds += secs;
      day.open = day.open || isOpen;
      day.sessions.push({
        id: r.id,
        in: r.check_in_at.toISOString(),
        out: r.check_out_at ? r.check_out_at.toISOString() : null,
        inLocal: r.in_local,
        outLocal: r.out_local,
        seconds: secs,
      });
    }

    const days = Array.from(byDate.values()).sort((a, b) =>
      b.date.localeCompare(a.date),
    );
    const totalSeconds = days.reduce((sum, d) => sum + d.seconds, 0);

    return { month, totalSeconds, openCount, days };
  }
```

- [ ] **Step 5: 테스트를 돌려 통과를 확인**

Run: `cd api-ventago && npx jest src/app/attendance/attendance.service.spec.ts -t sellerMonthDetail`
Expected: PASS — 5 tests

- [ ] **Step 6: SQL 의 TZ 의미를 실제 DB 로 검증**

위 단위 테스트는 `sequelize.query`를 목으로 막으므로 **SQL 자체는 전혀 검증하지 못한다** — 목은 준 행을 그대로 돌려줄 뿐이다. TZ 변환이 맞는지는 실제 PG로 확인해야 한다.

Run:
```bash
psql -p 5432 -d ventago -X -q <<'SQL'
-- 일자 귀속: Buenos_Aires(UTC-3) 자정 경계
WITH tz AS (SELECT 'America/Argentina/Buenos_Aires'::text AS t),
sample(id, check_in_at, check_out_at) AS (VALUES
  (1, '2026-07-14T03:30:00Z'::timestamptz, '2026-07-14T07:30:00Z'::timestamptz),
  (2, '2026-07-14T02:30:00Z'::timestamptz, NULL::timestamptz)
)
SELECT s.id,
       ((s.check_in_at AT TIME ZONE tz.t)::date)::text AS local_date,
       to_char(s.check_in_at AT TIME ZONE tz.t, 'HH24:MI') AS in_local,
       to_char(s.check_out_at AT TIME ZONE tz.t, 'HH24:MI') AS out_local
  FROM sample s, tz;

-- 월 경계
SELECT ('2026-07-01T02:30:00Z'::timestamptz >= ('2026-07-01'::timestamp AT TIME ZONE 'America/Argentina/Buenos_Aires')) AS jun30_2330_local_included,
       ('2026-07-01T03:30:00Z'::timestamptz >= ('2026-07-01'::timestamp AT TIME ZONE 'America/Argentina/Buenos_Aires')) AS jul01_0030_local_included;
SQL
```

Expected (2026-07-15 로컬 PG18 에서 실측 확인됨):
```
 id | local_date | in_local | out_local
----+------------+----------+-----------
  1 | 2026-07-14 | 00:30    | 04:30
  2 | 2026-07-13 | 23:30    |          <- 전날로 귀속 + out NULL 유지

 jun30_2330_local_included | jul01_0030_local_included
---------------------------+---------------------------
 f                         | t
```

현지 자정 직전(23:30) punch가 **전날**로 귀속되고, 현지 6/30 23:30이 7월 조회에서 **제외**되면 통과다. 값이 다르면 `AT TIME ZONE` 방향이 뒤집힌 것이니 구현을 고친다.

- [ ] **Step 7: 기존 attendance 테스트 전체가 여전히 통과하는지 확인 (회귀 없음)**

Run: `cd api-ventago && npx jest src/app/attendance/attendance.service.spec.ts`
Expected: PASS — 기존 테스트 포함 전부

- [ ] **Step 8: 커밋**

```bash
cd api-ventago
git add src/app/attendance/attendance.service.ts src/app/attendance/attendance.service.spec.ts
git commit -m "feat(attendance): sellerMonthDetail — 매장 TZ 기준 일자별 근무시간 + 세션"
```

---

## Task 2: `AdelantoService.monthApprovedTotalForUser` — vale 월 합계

**Files:**
- Modify: `api-ventago/src/app/adelanto/adelanto.service.ts`
- Test: `api-ventago/src/app/adelanto/adelanto.service.spec.ts` (신규 파일)

**Interfaces:**
- Consumes: 기존 `this.adelantoModel`(`SellerAdelanto`), `this.sellerModel`(`Seller`)
- Produces:
  ```ts
  async monthApprovedTotalForUser(userId: number, month: string):
    Promise<{ totalApproved: number; count: number }>
  ```

- [ ] **Step 1: 실패하는 테스트를 작성**

신규 파일 `src/app/adelanto/adelanto.service.spec.ts`:

```ts
// src/app/adelanto/adelanto.service.spec.ts
//
// AdelantoService.monthApprovedTotalForUser — payroll_period 기준 승인 가불 월 합계.
// jest 목은 본질적으로 any 라 no-unsafe-* 규칙을 이 파일에 한해 해제 (기존 spec 관행).
/* eslint-disable @typescript-eslint/no-unsafe-assignment, @typescript-eslint/no-unsafe-member-access, @typescript-eslint/no-unsafe-call, @typescript-eslint/no-unsafe-return, @typescript-eslint/no-unsafe-argument */

import { AdelantoService } from './adelanto.service';

describe('AdelantoService.monthApprovedTotalForUser', () => {
  let service: AdelantoService;
  let adelantoModel: any;
  let sellerModel: any;

  beforeEach(() => {
    adelantoModel = { findAll: jest.fn() };
    sellerModel = { findOne: jest.fn() };
    service = new AdelantoService(adelantoModel, sellerModel);
  });

  it('payroll_period + approved 로 필터해 합계를 낸다', async () => {
    sellerModel.findOne.mockResolvedValue({ id: 7 });
    // numeric(12,2) 는 드라이버가 문자열로 준다
    adelantoModel.findAll.mockResolvedValue([
      { amount: '30000.00' },
      { amount: '15000.00' },
    ]);

    const res = await service.monthApprovedTotalForUser(16, '2026-07');

    expect(res).toEqual({ totalApproved: 45000, count: 2 });

    const where = adelantoModel.findAll.mock.calls[0][0].where;
    expect(where).toMatchObject({
      sellerId: 7,
      status: 'approved',
      payrollPeriod: '2026-07',
    });
    // 요청일 기준이 아님을 명시 검증 (차감월 기준이어야 웹 관리자 수치와 일치)
    expect(where).not.toHaveProperty('requestedAt');
  });

  it('가불 없으면 0', async () => {
    sellerModel.findOne.mockResolvedValue({ id: 7 });
    adelantoModel.findAll.mockResolvedValue([]);

    const res = await service.monthApprovedTotalForUser(16, '2026-07');

    expect(res).toEqual({ totalApproved: 0, count: 0 });
  });

  it('판매원 미연결 유저는 0 (throw 안 함)', async () => {
    sellerModel.findOne.mockResolvedValue(null);

    const res = await service.monthApprovedTotalForUser(999, '2026-07');

    expect(res).toEqual({ totalApproved: 0, count: 0 });
    expect(adelantoModel.findAll).not.toHaveBeenCalled();
  });
});
```

- [ ] **Step 2: 테스트를 돌려 실패를 확인**

Run: `cd api-ventago && npx jest src/app/adelanto/adelanto.service.spec.ts`
Expected: FAIL — `service.monthApprovedTotalForUser is not a function`

- [ ] **Step 3: `monthApprovedTotalForUser` 구현**

`adelanto.service.ts`의 `listOwn` 메서드 **바로 아래**에 추가한다.

```ts
  // 판매원 앱: 본인 월 승인 가불 합계 (Mis horas 화면 하단 'Vale').
  // 기준 = payroll_period(관리자가 승인 시 지정한 차감월) + approved.
  // 웹 관리자 Horas 탭 차감 열(summaryByMonth)과 같은 기준이라 수치가 일치한다.
  async monthApprovedTotalForUser(
    userId: number,
    month: string,
  ): Promise<{ totalApproved: number; count: number }> {
    const seller = await this.sellerModel.findOne({
      where: { linkedUserId: userId },
    });
    if (!seller) {
      // 판매원 미연결(admin 등) → 빈 합계 (listOwn 과 동일 계약)
      return { totalApproved: 0, count: 0 };
    }

    const rows = await this.adelantoModel.findAll({
      attributes: ['amount'],
      where: {
        sellerId: seller.id,
        status: 'approved',
        payrollPeriod: month,
      },
      raw: true,
    });

    // amount 는 numeric(12,2) → 드라이버가 문자열로 반환하므로 명시 변환
    const totalApproved = rows.reduce(
      (sum, r) => sum + (Number((r as unknown as { amount: string }).amount) || 0),
      0,
    );

    return { totalApproved, count: rows.length };
  }
```

- [ ] **Step 4: 테스트를 돌려 통과를 확인**

Run: `cd api-ventago && npx jest src/app/adelanto/adelanto.service.spec.ts`
Expected: PASS — 3 tests

- [ ] **Step 5: 커밋**

```bash
cd api-ventago
git add src/app/adelanto/adelanto.service.ts src/app/adelanto/adelanto.service.spec.ts
git commit -m "feat(adelanto): monthApprovedTotalForUser — payroll_period 기준 본인 월 합계"
```

---

## Task 3: `GET /mobile/attendance/month` 엔드포인트

**Files:**
- Modify: `api-ventago/src/app/mobile/attendance/mobile-attendance.controller.ts`
- Modify: `api-ventago/src/app/mobile/mobile.module.ts:70-80` (imports 배열)

**Interfaces:**
- Consumes: `AttendanceService.sellerMonthDetail(userId, month)` (Task 1), `AdelantoService.monthApprovedTotalForUser(userId, month)` (Task 2)
- Produces: `GET /mobile/attendance/month?month=YYYY-MM` →
  ```jsonc
  { month, totalSeconds, openCount, days: [...], adelanto: { totalApproved, count } }
  ```

- [ ] **Step 1: `MobileModule`에 `AdelantoModule` import 추가**

`src/app/mobile/mobile.module.ts` — import 문 추가 (`AttendanceModule` import 줄 아래):

```ts
// Mis horas: 근무시간 응답에 vale 합계 합성 (AdelantoModule 은 Mobile/Attendance 를
// import 하지 않으므로 순환 없음 — forwardRef 불필요).
import { AdelantoModule } from '../adelanto/adelanto.module';
```

그리고 `imports` 배열에서 `forwardRef(() => AttendanceModule),` 바로 아래에 추가:

```ts
    AdelantoModule,
```

- [ ] **Step 2: 컨트롤러에 `month` 라우트 추가**

`src/app/mobile/attendance/mobile-attendance.controller.ts` 전체를 아래로 교체한다:

```ts
// 판매원 앱 본인 근무시간 — GET /mobile/attendance/summary?month (홈 배너, 총계만)
//                          GET /mobile/attendance/month?month   (Mis horas 화면, 일자별+세션+vale)
// 인증: AuthGuard('jwt'). req.user.id → linked seller.
// 미연결 유저는 서비스가 빈 결과를 반환한다(에러 아님).
import {
  BadRequestException,
  Controller,
  Get,
  Query,
  Req,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import type { Request } from 'express';
import { AttendanceService } from '../../attendance/attendance.service';
import { AdelantoService } from '../../adelanto/adelanto.service';

@Controller('mobile/attendance')
@UseGuards(AuthGuard('jwt'))
export class MobileAttendanceController {
  constructor(
    private readonly attendance: AttendanceService,
    private readonly adelanto: AdelantoService,
  ) {}

  @Get('summary')
  async summary(
    @Req() req: Request & { user?: { id?: number } },
    @Query('month') month?: string,
  ) {
    const userId = Number(req.user?.id);

    return this.attendance.sellerMonthSummary(userId, this.parseMonth(month));
  }

  // Mis horas 화면 — 일자별 근무시간 + 세션 + 승인 가불 합계를 1회 호출로.
  // 근무시간(AttendanceService)과 가불(AdelantoService)은 서로 모르는 채로
  // 여기서 합성한다 — 서비스 간 결합을 만들지 않기 위함.
  @Get('month')
  async month(
    @Req() req: Request & { user?: { id?: number } },
    @Query('month') month?: string,
  ) {
    const userId = Number(req.user?.id);
    const m = this.parseMonth(month);

    const [hours, adelanto] = await Promise.all([
      this.attendance.sellerMonthDetail(userId, m),
      this.adelanto.monthApprovedTotalForUser(userId, m),
    ]);

    return { ...hours, adelanto };
  }

  // month(YYYY-MM) 검증 — 형식이 틀리면 400
  private parseMonth(month?: string): string {
    if (!month || !/^\d{4}-\d{2}$/.test(month)) {
      throw new BadRequestException('month(YYYY-MM) requerido');
    }

    return month;
  }
}
```

- [ ] **Step 3: 타입 체크 + 빌드 확인**

Run: `cd api-ventago && npx tsc --noEmit`
Expected: 에러 없음 (종료 코드 0)

- [ ] **Step 4: 앱 부팅으로 모듈 순환/주입 오류가 없는지 확인**

Run: `cd api-ventago && timeout 60 npm run start:dev 2>&1 | head -40`
Expected: `Nest application successfully started` 출력. `Nest can't resolve dependencies` / `Circular dependency` 오류가 없어야 한다.
확인 후 Ctrl+C.

- [ ] **Step 5: 실제 호출로 응답 형태 확인**

로컬 API가 뜬 상태에서 판매원 계정(store 6: `venta1`)으로 로그인해 JWT를 얻고 호출한다.

```bash
# 1) 로그인 (필드명은 emailOrUsername — 기존 계약)
TOKEN=$(curl -s -X POST http://localhost:5002/api/mobile/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"emailOrUsername":"venta1","password":"<비밀번호>"}' | jq -r '.accessToken')

# 2) Mis horas 데이터
curl -s "http://localhost:5002/api/mobile/attendance/month?month=2026-07" \
  -H "Authorization: Bearer $TOKEN" | jq
```

Expected: `{ month, totalSeconds, openCount, days: [...], adelanto: { totalApproved, count } }`.
근무 이력이 없으면 `days: []`, `totalSeconds: 0` — 정상이다.

- [ ] **Step 6: 커밋**

```bash
cd api-ventago
git add src/app/mobile/attendance/mobile-attendance.controller.ts src/app/mobile/mobile.module.ts
git commit -m "feat(mobile): GET /mobile/attendance/month — 일자별 근무시간 + vale 합계 합성"
```

---

## Task 4: 앱 DTO + Repository

**Files:**
- Modify: `mobile-sales-app/lib/features/attendance/data/attendance_dto.dart`
- Modify: `mobile-sales-app/lib/features/attendance/data/attendance_repository.dart`
- Test: `mobile-sales-app/test/my_hours_test.dart` (신규)

**Interfaces:**
- Consumes: `GET /mobile/attendance/month` 응답 (Task 3)
- Produces:
  ```dart
  class MonthDetail { String month; int totalSeconds; int openCount;
                      List<DayHours> days; AdelantoTotal adelanto; }
  class DayHours { String date; int seconds; bool open; List<WorkSession> sessions; }
  class WorkSession { int id; String inLocal; String? outLocal; int seconds; }
  class AdelantoTotal { num totalApproved; int count; }
  Future<MonthDetail> AttendanceRepository.getMonthDetail(String month)
  ```
  주의: `WorkSession`은 `inLocal`/`outLocal`(매장 TZ `HH:mm` 문자열)만 쓴다. UTC `in`/`out`은 파싱하지 않는다 — 폰 TZ로 재계산하면 매장 TZ와 어긋난다.

- [ ] **Step 1: 실패하는 테스트를 작성**

신규 파일 `test/my_hours_test.dart`:

```dart
// MonthDetail DTO 파싱 — GET /mobile/attendance/month 응답 계약.
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_sales_app/features/attendance/data/attendance_dto.dart';

void main() {
  group('MonthDetail.fromJson', () {
    test('일자별 + 세션 + vale 를 파싱한다', () {
      final json = {
        'month': '2026-07',
        'totalSeconds': 32400,
        'openCount': 1,
        'days': [
          {
            'date': '2026-07-15',
            'seconds': 32400,
            'open': true,
            'sessions': [
              {
                'id': 91,
                'in': '2026-07-15T11:02:11.000Z',
                'out': '2026-07-15T15:05:00.000Z',
                'inLocal': '08:02',
                'outLocal': '12:05',
                'seconds': 14569,
              },
              {
                'id': 94,
                'in': '2026-07-15T16:01:00.000Z',
                'out': null,
                'inLocal': '13:01',
                'outLocal': null,
                'seconds': 17831,
              },
            ],
          },
        ],
        'adelanto': {'totalApproved': 45000, 'count': 2},
      };

      final d = MonthDetail.fromJson(json);

      expect(d.month, '2026-07');
      expect(d.totalSeconds, 32400);
      expect(d.openCount, 1);
      expect(d.days, hasLength(1));
      expect(d.days[0].date, '2026-07-15');
      expect(d.days[0].open, isTrue);
      expect(d.days[0].sessions, hasLength(2));
      // 매장 TZ 문자열을 그대로 쓴다 (폰 TZ 재계산 금지)
      expect(d.days[0].sessions[0].inLocal, '08:02');
      expect(d.days[0].sessions[0].outLocal, '12:05');
      expect(d.days[0].sessions[1].outLocal, isNull);
      expect(d.adelanto.totalApproved, 45000);
      expect(d.adelanto.count, 2);
    });

    test('빈 응답(판매원 미연결/이력 없음)도 파싱된다', () {
      final d = MonthDetail.fromJson({
        'month': '2026-07',
        'totalSeconds': 0,
        'openCount': 0,
        'days': [],
        'adelanto': {'totalApproved': 0, 'count': 0},
      });

      expect(d.days, isEmpty);
      expect(d.totalSeconds, 0);
      expect(d.adelanto.totalApproved, 0);
    });

    test('adelanto 키 누락 시에도 크래시 없이 0', () {
      final d = MonthDetail.fromJson({
        'month': '2026-07',
        'totalSeconds': 0,
        'openCount': 0,
        'days': [],
      });

      expect(d.adelanto.totalApproved, 0);
      expect(d.adelanto.count, 0);
    });
  });

  group('DayHours.hhmm', () {
    test('초를 8h 02m 로 포맷', () {
      const d = DayHours(date: '2026-07-15', seconds: 28920, open: false, sessions: []);
      expect(d.hhmm, '8h 02m');
    });

    test('0초는 0h 00m', () {
      const d = DayHours(date: '2026-07-15', seconds: 0, open: false, sessions: []);
      expect(d.hhmm, '0h 00m');
    });

    test('100시간 넘어도 시간 자릿수 유지', () {
      const d = DayHours(date: '2026-07-15', seconds: 547260, open: false, sessions: []);
      expect(d.hhmm, '152h 01m');
    });
  });
}
```

- [ ] **Step 2: 테스트를 돌려 실패를 확인**

Run: `cd mobile-sales-app && flutter test test/my_hours_test.dart`
Expected: FAIL — `MonthDetail` 정의 없음(컴파일 에러)

- [ ] **Step 3: DTO 추가**

`lib/features/attendance/data/attendance_dto.dart` **파일 끝에** 추가한다 (기존 `AttendanceSummary`는 홈 배너용으로 유지 — 수정하지 않는다).

```dart
// 초 → "8h 02m" (분은 2자리 0 패딩, 시간은 자릿수 제한 없음)
String _formatHhmm(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;

  return '${h}h ${m.toString().padLeft(2, '0')}m';
}

// 한 근무 세션 (GET /mobile/attendance/month → days[].sessions[]).
// inLocal/outLocal 은 매장 TZ 기준 'HH:mm' — 서버가 계산해 내려준다.
// 폰 TZ 가 매장과 다를 수 있으므로 앱에서 UTC 를 재변환하지 않는다.
@immutable
class WorkSession {
  final int id;
  final String inLocal;
  final String? outLocal;
  final int seconds;

  const WorkSession({
    required this.id,
    required this.inLocal,
    this.outLocal,
    required this.seconds,
  });

  bool get open => outLocal == null;
  String get hhmm => _formatHhmm(seconds);

  factory WorkSession.fromJson(Map<String, dynamic> json) => WorkSession(
        id: (json['id'] as num?)?.toInt() ?? 0,
        inLocal: json['inLocal'] as String? ?? '',
        outLocal: json['outLocal'] as String?,
        seconds: (json['seconds'] as num?)?.toInt() ?? 0,
      );
}

// 하루치 근무 (세션 합산). date 는 매장 TZ 기준 YYYY-MM-DD.
@immutable
class DayHours {
  final String date;
  final int seconds;
  final bool open;
  final List<WorkSession> sessions;

  const DayHours({
    required this.date,
    required this.seconds,
    required this.open,
    required this.sessions,
  });

  String get hhmm => _formatHhmm(seconds);

  factory DayHours.fromJson(Map<String, dynamic> json) => DayHours(
        date: json['date'] as String? ?? '',
        seconds: (json['seconds'] as num?)?.toInt() ?? 0,
        open: json['open'] as bool? ?? false,
        sessions: ((json['sessions'] as List<dynamic>?) ?? [])
            .map((e) => WorkSession.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// 승인 가불 월 합계 (payroll_period 기준).
@immutable
class AdelantoTotal {
  final num totalApproved;
  final int count;

  const AdelantoTotal({required this.totalApproved, required this.count});

  factory AdelantoTotal.fromJson(Map<String, dynamic>? json) => AdelantoTotal(
        totalApproved: (json?['totalApproved'] as num?) ?? 0,
        count: (json?['count'] as num?)?.toInt() ?? 0,
      );
}

// 월 근무 상세 (GET /mobile/attendance/month?month=YYYY-MM).
@immutable
class MonthDetail {
  final String month;
  final int totalSeconds;
  final int openCount;
  final List<DayHours> days;
  final AdelantoTotal adelanto;

  const MonthDetail({
    required this.month,
    required this.totalSeconds,
    required this.openCount,
    required this.days,
    required this.adelanto,
  });

  String get totalHhmm => _formatHhmm(totalSeconds);

  factory MonthDetail.fromJson(Map<String, dynamic> json) => MonthDetail(
        month: json['month'] as String? ?? '',
        totalSeconds: (json['totalSeconds'] as num?)?.toInt() ?? 0,
        openCount: (json['openCount'] as num?)?.toInt() ?? 0,
        days: ((json['days'] as List<dynamic>?) ?? [])
            .map((e) => DayHours.fromJson(e as Map<String, dynamic>))
            .toList(),
        adelanto: AdelantoTotal.fromJson(json['adelanto'] as Map<String, dynamic>?),
      );
}
```

- [ ] **Step 4: Repository 메서드 추가**

`lib/features/attendance/data/attendance_repository.dart` — `getMonthSummary` 아래, `_toApiException` 위에 추가:

```dart
  // 본인 월 근무 상세 — GET /mobile/attendance/month?month=YYYY-MM.
  // 일자별 + 세션 + vale 합계를 1회 호출로 받는다(바텀시트는 추가 호출 없음).
  Future<MonthDetail> getMonthDetail(String month) async {
    try {
      final response = await _client.dio.get(
        '/mobile/attendance/month',
        queryParameters: {'month': month},
      );

      return MonthDetail.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }
```

- [ ] **Step 5: 테스트를 돌려 통과를 확인**

Run: `cd mobile-sales-app && flutter test test/my_hours_test.dart`
Expected: PASS — 6 tests

- [ ] **Step 6: 정적 분석**

Run: `cd mobile-sales-app && flutter analyze lib/features/attendance test/my_hours_test.dart`
Expected: `No issues found!`

- [ ] **Step 7: 커밋**

```bash
cd mobile-sales-app
git add lib/features/attendance/data/attendance_dto.dart lib/features/attendance/data/attendance_repository.dart test/my_hours_test.dart
git commit -m "feat(attendance): MonthDetail DTO + getMonthDetail — 일자별 근무시간 계약"
```

---

## Task 5: Provider + Mis horas 화면 + 라우트

**Files:**
- Modify: `mobile-sales-app/lib/features/attendance/providers/attendance_provider.dart`
- Create: `mobile-sales-app/lib/features/attendance/views/my_hours_screen.dart`
- Modify: `mobile-sales-app/lib/router/app_router.dart`

**Interfaces:**
- Consumes: `MonthDetail`/`DayHours`/`WorkSession` (Task 4), `attendanceRepositoryProvider.getMonthDetail` (Task 4), `formatMoney` (`core/format/money.dart`), `AppColors` (`core/theme/app_theme.dart`)
- Produces:
  ```dart
  final selectedMonthProvider = StateProvider<String>(...);        // 'YYYY-MM'
  final monthDetailProvider = FutureProvider.autoDispose.family<MonthDetail, String>(...);
  String currentMonthKey();                                        // 이번 달 'YYYY-MM'
  class MyHoursScreen extends ConsumerWidget                       // 라우트 '/mis-horas'
  ```

- [ ] **Step 1: Provider 추가**

`lib/features/attendance/providers/attendance_provider.dart` — 기존 `monthSummaryProvider`(홈 배너용)는 수정하지 않는다. 파일 상단 import에 `../data/attendance_dto.dart`가 이미 있는지 확인하고, `monthSummaryProvider` 아래에 추가:

```dart
// 이번 달 키 'YYYY-MM' (기기 로컬 기준 — 월 선택 초기값 용도)
String currentMonthKey() {
  final now = DateTime.now();

  return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
}

// Mis horas 화면에서 보고 있는 월. 좌우 화살표가 갱신한다.
final selectedMonthProvider = StateProvider<String>((ref) => currentMonthKey());

// 월 근무 상세 (일자별 + 세션 + vale). month 별로 캐시된다.
final monthDetailProvider =
    FutureProvider.autoDispose.family<MonthDetail, String>((ref, month) async {
  return ref.read(attendanceRepositoryProvider).getMonthDetail(month);
});
```

- [ ] **Step 2: Mis horas 화면 작성**

신규 파일 `lib/features/attendance/views/my_hours_screen.dart`:

```dart
// Mis horas (/mis-horas) — 본인 월 근무시간.
// 일자별 목록 + 하단 고정 총계/vale. 행 탭 → 그날 세션 바텀시트(네트워크 호출 없음).
// 월 이동은 좌우 화살표(이번 달까지). 시각/일자는 서버가 매장 TZ 로 계산해 내려준다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/format/money.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../data/attendance_dto.dart';
import '../providers/attendance_provider.dart';

// 'YYYY-MM' → 'julio 2026'
const _monthNames = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

String _monthLabel(String month) {
  final parts = month.split('-');
  if (parts.length != 2) return month;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (y == null || m == null || m < 1 || m > 12) return month;

  return '${_monthNames[m - 1]} $y';
}

// 'YYYY-MM' 에 delta 개월 더하기
String _shiftMonth(String month, int delta) {
  final parts = month.split('-');
  final y = int.parse(parts[0]);
  final m = int.parse(parts[1]);
  final base = DateTime(y, m + delta);

  return '${base.year.toString().padLeft(4, '0')}-${base.month.toString().padLeft(2, '0')}';
}

// 'YYYY-MM-DD' → 'mar 15'
const _dowNames = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];

String _dayLabel(String date) {
  final d = DateTime.tryParse(date);
  if (d == null) return date;

  return '${_dowNames[d.weekday - 1]} ${d.day}';
}

class MyHoursScreen extends ConsumerWidget {
  const MyHoursScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final detail = ref.watch(monthDetailProvider(month));
    // 미래 월 이동 차단 — 이번 달까지만
    final canGoNext = month.compareTo(currentMonthKey()) < 0;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        title: const Text('Mis horas'),
      ),
      body: Column(
        children: [
          // 월 선택
          Container(
            color: AppColors.navy,
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: () => ref.read(selectedMonthProvider.notifier).state =
                      _shiftMonth(month, -1),
                  icon: const Icon(Icons.chevron_left, color: Colors.white),
                  tooltip: 'Mes anterior',
                ),
                SizedBox(
                  width: 150,
                  child: Text(
                    _monthLabel(month),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.gold,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: canGoNext
                      ? () => ref.read(selectedMonthProvider.notifier).state =
                          _shiftMonth(month, 1)
                      : null,
                  icon: Icon(
                    Icons.chevron_right,
                    color: canGoNext ? Colors.white : Colors.white24,
                  ),
                  tooltip: 'Mes siguiente',
                ),
              ],
            ),
          ),
          Expanded(
            child: detail.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorState(
                message: e is ApiException ? e.message : 'Error de conexión',
                onRetry: () => ref.invalidate(monthDetailProvider(month)),
              ),
              data: (d) => d.days.isEmpty
                  ? const _EmptyState()
                  : ListView.separated(
                      itemCount: d.days.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, color: AppColors.line),
                      itemBuilder: (context, i) => _DayRow(day: d.days[i]),
                    ),
            ),
          ),
          // 하단 고정 총계 — 에러/로딩 시엔 숨김
          detail.maybeWhen(
            data: (d) => _TotalsBar(detail: d),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

// 하루 행 — 탭하면 그날 세션 바텀시트
class _DayRow extends StatelessWidget {
  final DayHours day;

  const _DayRow({required this.day});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: () => _showDaySessions(context, day),
      title: Text(
        _dayLabel(day.date),
        style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (day.open) ...[
            const Icon(Icons.circle, size: 8, color: AppColors.green),
            const SizedBox(width: 6),
            const Text(
              'trabajando',
              style: TextStyle(color: AppColors.green, fontSize: 12),
            ),
            const SizedBox(width: 10),
          ],
          Text(
            day.hhmm,
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 18, color: AppColors.muted),
        ],
      ),
    );
  }
}

// 그날 세부 기록 — days[] 에 이미 담겨온 세션을 그대로 표시(호출 없음)
void _showDaySessions(BuildContext context, DayHours day) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _dayLabel(day.date),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 12),
            ...day.sessions.map(
              (s) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      s.open ? '${s.inLocal} → en curso' : '${s.inLocal} → ${s.outLocal}',
                      style: TextStyle(
                        color: s.open ? AppColors.green : AppColors.ink,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      s.hhmm,
                      style: const TextStyle(color: AppColors.muted, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 24, color: AppColors.line),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total del día',
                  style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
                ),
                Text(
                  day.hhmm,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

// 하단 고정 — 총 근무시간 + 승인 vale 합계
class _TotalsBar extends StatelessWidget {
  final MonthDetail detail;

  const _TotalsBar({required this.detail});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.navy,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      child: Column(
        children: [
          _row('Total', detail.totalHhmm),
          const SizedBox(height: 6),
          _row('Vale (adelanto)', formatMoney(detail.adelanto.totalApproved)),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFFB9B9C6), fontSize: 14)),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.gold,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Sin registros', style: TextStyle(color: AppColors.muted)),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: const TextStyle(color: AppColors.red)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    );
  }
}
```

`FontFeature`는 `dart:ui`에 있다. `flutter analyze`가 미해결 심볼을 잡으면 파일 상단에 `import 'dart:ui' show FontFeature;`를 추가한다.

- [ ] **Step 3: 라우트 등록**

`lib/router/app_router.dart`:

import 추가 (`fichaje_scanner_sheet.dart` import 아래):

```dart
import '../features/attendance/views/my_hours_screen.dart';
```

`routes` 배열에서 `/adelanto` GoRoute 바로 아래에 추가:

```dart
      GoRoute(
        path: '/mis-horas',
        builder: (context, state) => const MyHoursScreen(),
      ),
```

- [ ] **Step 4: 정적 분석**

Run: `cd mobile-sales-app && flutter analyze lib/features/attendance lib/router`
Expected: `No issues found!`

- [ ] **Step 5: 기존 테스트 회귀 확인**

Run: `cd mobile-sales-app && flutter test`
Expected: 전부 PASS (기존 `fichaje_deeplink_test` / `scope_provider_test` / `variant_matrix_test` / `widget_test` 포함)

- [ ] **Step 6: 커밋**

```bash
cd mobile-sales-app
git add lib/features/attendance/providers/attendance_provider.dart lib/features/attendance/views/my_hours_screen.dart lib/router/app_router.dart
git commit -m "feat(attendance): Mis horas 화면 — 일자별 목록 + 총계 + 일 상세 바텀시트"
```

---

## Task 6: 홈 아바타 → 팝업 메뉴

**Files:**
- Modify: `mobile-sales-app/lib/features/home/views/home_screen.dart:40-96`

**Interfaces:**
- Consumes: `/mis-horas` 라우트 (Task 5), 기존 `/adelanto` 라우트, `scopeNotifierProvider.notifier.logout()`
- Produces: 없음 (UI 변경만)

- [ ] **Step 1: 현재 헤더 구조를 확인**

Run: `cd mobile-sales-app && sed -n '35,100p' lib/features/home/views/home_screen.dart`

`Row` 첫 자식이 `CircleAvatar`(radius 24, gold, 이름 첫 글자)이고, 그 뒤 `Expanded`(인사/매장/build) 다음에 `IconButton` 2개(`payments_outlined` → `/adelanto`, `logout`)가 있다. `go_router` import는 이미 있다.

- [ ] **Step 2: `CircleAvatar`를 `PopupMenuButton`으로 감싸고 IconButton 2개를 제거**

`Row`의 첫 자식 `CircleAvatar(...)` 전체를 아래로 교체한다 (아바타 모양은 그대로, 감싸기만 한다):

```dart
                  PopupMenuButton<String>(
                    tooltip: 'Menú',
                    color: AppColors.navy2,
                    onSelected: (value) {
                      switch (value) {
                        case 'hours':
                          context.push('/mis-horas');
                          break;
                        case 'adelanto':
                          context.push('/adelanto');
                          break;
                        case 'logout':
                          ref.read(scopeNotifierProvider.notifier).logout();
                          break;
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'hours',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.schedule, color: AppColors.gold),
                          title: Text('Mis horas', style: TextStyle(color: Colors.white)),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'adelanto',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.payments_outlined, color: AppColors.gold),
                          title: Text('Adelanto', style: TextStyle(color: Colors.white)),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'logout',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.logout, color: Color(0xFFB9B9C6)),
                          title: Text('Salir', style: TextStyle(color: Colors.white)),
                        ),
                      ),
                    ],
                    // 기존 아바타 그대로 — 모양 변경 없음, 탭 동작만 추가
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor: AppColors.gold,
                      child: Text(
                        name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
                        style: const TextStyle(
                          color: AppColors.navy2,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ),
```

그리고 `Expanded` 뒤의 `IconButton` 2개(`payments_outlined` → `/adelanto`, `logout`)를 **삭제**한다. `_MonthHoursCard` 배너는 그대로 둔다.

주의: `PopupMenuButton`의 `itemBuilder`는 `const` 리스트이므로 `onSelected`에서만 `ref`/`context`를 쓴다. 이 위젯은 `ConsumerWidget`의 `build` 안이라 `ref`가 스코프에 있다.

- [ ] **Step 3: 정적 분석 — 미사용 import 확인**

Run: `cd mobile-sales-app && flutter analyze lib/features/home`
Expected: `No issues found!`
(IconButton 제거로 미사용 import가 생기면 지운다.)

- [ ] **Step 4: 앱을 띄워 실제 동작 확인**

Run: `cd mobile-sales-app && flutter run -d macos`

판매원 계정(`venta1`)으로 로그인 후 확인:
1. 헤더에 아이콘 버튼이 없다 (아바타만)
2. 아바타 탭 → 메뉴 3개(Mis horas / Adelanto / Salir)
3. Mis horas → 일자별 목록 + 하단 Total/Vale
4. 하루 행 탭 → 바텀시트에 `08:02 → 12:05` 형태 세션
5. `‹` 로 지난달 이동, `›`는 이번 달에서 비활성
6. Adelanto → 기존 화면이 그대로 열린다 (회귀 없음)
7. Salir → 로그아웃

- [ ] **Step 5: 전체 테스트**

Run: `cd mobile-sales-app && flutter test`
Expected: 전부 PASS

- [ ] **Step 6: 커밋**

```bash
cd mobile-sales-app
git add lib/features/home/views/home_screen.dart
git commit -m "feat(home): 아바타 팝업 메뉴 — Mis horas / Adelanto / Salir"
```

---

## Task 7: 루트 repo 서브모듈 포인터 갱신

**Files:**
- Modify: `ACE_online_1.0` 루트 repo의 `api-ventago` / `mobile-sales-app` gitlink

**Interfaces:**
- Consumes: Task 1–6의 커밋
- Produces: 없음 (배포 준비)

- [ ] **Step 1: 두 repo가 커밋되었는지 확인**

Run: `cd api-ventago && git status --short && cd ../mobile-sales-app && git status --short`
Expected: 두 곳 모두 출력 없음(clean)

- [ ] **Step 2: 백엔드 테스트 + 타입 체크 최종 확인**

Run: `cd api-ventago && npx jest src/app/attendance src/app/adelanto && npx tsc --noEmit`
Expected: 전부 PASS, tsc 에러 0

- [ ] **Step 3: 루트에서 서브모듈 포인터 커밋**

```bash
cd /Users/marcoskim/Trabajos_Programming/ACE_online_1.0
git add api-ventago mobile-sales-app
git commit -m "chore: bump submodules — Mis horas (판매원 앱 본인 근무시간)"
```

- [ ] **Step 4: push는 사용자 확인 후**

`mobile-sales-app`은 nested private repo라 별도 push가 필요하다. 운영 배포는 **수동 Jenkins**(`api-new-coolsistema` job)이고 APK도 별도 빌드다. push/배포는 사용자에게 확인받고 진행한다.

---

## 배포 노트 (구현 후)

- **스키마 변경 없음** → 마이그레이션 불필요. 로컬/운영 DB 동시 적용 이슈 없음
- **구버전 앱 호환**: 신규 엔드포인트만 추가하고 `/mobile/attendance/summary`는 무변경 → 구버전 앱 정상 동작
- **배포 순서**: API 먼저(Jenkins) → APK 배포. 반대로 하면 신규 앱이 404를 받는다
- **UAT 필요**: 실제 근무 이력이 있는 판매원 계정(store 6 `israel`/`venta1`/`venta2`)으로 웹 관리자 Asistencia 화면의 월 합계와 앱 Total이 일치하는지 대조. 열린 세션이 있으면 앱이 더 큰 값을 보이는 게 정상(경과 포함)
