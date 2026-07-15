# 판매원 앱 — 내 근무시간(Mis horas) 전용 화면

날짜: 2026-07-15
상태: 설계 승인됨, 구현 대기

## 목표

판매원이 자기 폰에서 **이번 달 일자별 근무시간 + 총계 + 받은 vale(adelanto) 총액**을 확인한다.
하루 행을 탭하면 그날 세부 출퇴근 기록(입/출 시각)을 본다.

현재는 홈 화면 상단에 `Trabajado este mes` 배너(월 총초만)가 전부다. 일자별 내역·세부 기록·vale 총액을 볼 방법이 없다.

## 범위

**포함**
- 신규 API 1개: `GET /mobile/attendance/month?month=YYYY-MM`
- 신규 앱 화면: `/mis-horas` (일자별 목록 + 하단 총계 + vale 총액)
- 일 행 탭 → 바텀시트(그날 세션 목록)
- 좌우 화살표 월 이동 (이번 달까지)
- 홈 아바타 탭 → 팝업 메뉴 (Mis horas / Adelanto / Salir)

**제외 (YAGNI)**
- vale 요청/내역 화면 — 기존 `/adelanto`(Phase B6) 그대로 유지. 신규 화면은 **총액만** 표시
- 근무시간 수정 요청 — 보정은 관리자 전용(D2 잠금)
- CSV/PDF 내보내기
- 급여 금액 계산 — SPEC D3 잠금(근무시간 + 가불 차감만)

## 결정 사항 (확정)

| 항목 | 결정 | 이유 |
|---|---|---|
| vale 집계 기준 | `payroll_period` + `status='approved'` | 웹 관리자 Horas 탭 차감 열(`summaryByMonth`)과 동일 수치. 판매원/관리자가 같은 숫자를 봐야 분쟁 없음 |
| 일 상세 진입 | 한 번 탭 → 바텀시트 | 폰 표준 제스처. 더블탭은 발견성 낮고 접근성 도구와 충돌 |
| 월 범위 | 좌우 화살표로 월 이동 | 백엔드 `month` 파라미터 이미 존재 — 앱 헤더 1줄 추가 수준 |
| 열린 세션(근무중) | 현재까지 경과 포함 + `● trabajando` 표시 | 판매원 체감과 일치. 퇴근하면 웹 수치와 자동 일치 |
| 진입점 | 홈 아바타 탭 → 팝업 메뉴 | 헤더 아이콘 0개. 항목 늘어도 안 붐빔 |
| API 형태 | 전용 엔드포인트 1개, `days[]`에 세션 동봉 | 화면 진입 1회 호출. 바텀시트가 네트워크 없이 즉시 열림 |

## 아키텍처

### 백엔드 (api-ventago)

**신규 엔드포인트** — 기존 `MobileAttendanceController` (`src/app/mobile/attendance/`)에 추가:

```
GET /mobile/attendance/month?month=YYYY-MM
Guard: AuthGuard('jwt')  (기존 /summary 와 동일)
```

응답:
```jsonc
{
  "month": "2026-07",
  "totalSeconds": 547200,
  "openCount": 1,
  "days": [
    {
      "date": "2026-07-15",
      "seconds": 28800,
      "open": true,
      "sessions": [
        { "id": 91, "in": "2026-07-15T11:02:11.000Z", "out": "2026-07-15T15:05:00.000Z",
          "inLocal": "08:02", "outLocal": "12:05", "seconds": 14569 },
        { "id": 94, "in": "2026-07-15T16:01:00.000Z", "out": null,
          "inLocal": "13:01", "outLocal": null, "seconds": 14231 }
      ]
    }
  ],
  "adelanto": { "totalApproved": 45000, "count": 2 }
}
```

- `days`는 날짜 **내림차순**(최근 먼저). 근무 없는 날은 행 자체가 없음
- `sessions[].in/out`은 ISO(UTC) 원본. `inLocal`/`outLocal`은 **매장 TZ 기준 `HH:mm`** — 앱이 TZ 재계산하지 않도록 서버가 내려준다(폰 TZ가 매장과 다를 수 있음). 열린 세션은 `out`/`outLocal` 모두 `null`
- `days[].date`도 매장 TZ 기준 `YYYY-MM-DD`
- `totalSeconds` = `days[].seconds` 합 (열린 세션 경과 포함)

**`AttendanceService.sellerMonthDetail(userId, month)`** 신규:

1. `Sellers.findOne({ where: { linkedUserId: userId } })` → 없으면 빈 응답
   (`{ month, totalSeconds: 0, openCount: 0, days: [], adelanto: { totalApproved: 0, count: 0 } }`)
   — 403 아님. 기존 `sellerMonthSummary` 계약과 일치
2. `const tz = await this.storeTimezone(seller.storeId)` — 기존 private 메서드 재사용(같은 서비스 내). 매장마다 다름(Buenos_Aires / Bogota)
3. 세션 조회 SQL — **매장 TZ 기준** 일자 그룹핑:

```sql
SELECT sa.id,
       sa.check_in_at,
       sa.check_out_at,
       ((sa.check_in_at AT TIME ZONE :tz)::date)::text AS local_date,
       to_char(sa.check_in_at AT TIME ZONE :tz, 'HH24:MI') AS in_local,
       to_char(sa.check_out_at AT TIME ZONE :tz, 'HH24:MI') AS out_local,  -- NULL 이면 NULL
       EXTRACT(EPOCH FROM (COALESCE(sa.check_out_at, now()) - sa.check_in_at))::int AS seconds
  FROM seller_attendance sa
 WHERE sa.seller_id = :sellerId
   AND sa.check_in_at >= (:monthStart::timestamp AT TIME ZONE :tz)
   AND sa.check_in_at <  ((:monthStart::timestamp + INTERVAL '1 month') AT TIME ZONE :tz)
 ORDER BY sa.check_in_at DESC
```

4. JS에서 `local_date`로 그룹핑 → `days[]` 구성. `open = check_out_at IS NULL`
5. `adelanto` = `AdelantoService.sellerMonthApprovedTotal(seller.id, month)`

**TZ 처리 주의 (기존 버그 반복 금지)**

`check_in_at`은 `timestamptz`. 기존 `sellerMonthSummary` / `listSessions`는 `check_in_at >= :monthStart::date`로 비교하는데, 이 `date` 리터럴은 **DB 세션 TimeZone** 기준으로 timestamptz 캐스팅된다 — 매장 TZ가 아니다. 매장 TZ와 DB 세션 TZ가 다르면 월 경계 근처 punch가 잘못된 월에 잡힌다.

신규 경로는 `AT TIME ZONE :tz`로 명시 변환한다. **기존 메서드는 이번 작업에서 건드리지 않는다** (관리자 리포트 회귀 위험 — 별도 이슈로 분리).

**`AdelantoService.sellerMonthApprovedTotal(sellerId, month)`** 신규:

```
SELECT COALESCE(SUM(amount), 0), COUNT(*)
  FROM seller_adelantos
 WHERE seller_id = :sellerId
   AND status = 'approved'
   AND payroll_period = :month
```

`amount`는 `numeric(12,2)` → JS `Number` 변환 명시. 기존 `summaryByMonth`와 동일 기준(`payroll_period` + `approved`).

**격리**: `seller_id`는 요청자의 JWT `userId` → `linkedUserId` 로만 도출. 클라이언트가 sellerId를 보내지 않으므로 IDOR 불가.

**성능**: `idx_seller_attendance_store_checkin (store_id, check_in_at)` 존재. 쿼리가 `seller_id` 선행이라 이 인덱스는 부분적으로만 도움 — 한 달 데이터가 판매원당 최대 ~100행이고 `seller_attendance` 전체가 작아 seq scan도 100ms 미만. **인덱스 추가 없이 시작**, slow query 로그에 뜨면 `(seller_id, check_in_at)` 추가.

**스키마 변경: 없음.** 마이그레이션 불필요 → 로컬/운영 DB 동시 적용 이슈 없음.

### 앱 (mobile-sales-app)

기존 `features/attendance/` 구조를 따른다.

**`data/attendance_dto.dart`** — 추가 (기존 `AttendanceSummary`는 홈 배너용으로 유지):
- `MonthDetail { month, totalSeconds, openCount, days, adelanto }`
- `DayHours { date, seconds, open, sessions }`
- `WorkSession { id, inAt, outAt, seconds }`
- `AdelantoTotal { totalApproved, count }`

**`data/attendance_repository.dart`** — `getMonthDetail(String month)` 추가. 기존 `_toApiException` 재사용.

**`providers/attendance_provider.dart`** — 추가:
- `selectedMonthProvider` — `StateProvider<String>`, 기본 = 이번 달
- `monthDetailProvider` — `FutureProvider.autoDispose.family<MonthDetail, String>`

기존 `monthSummaryProvider`(홈 배너)는 무변경.

**`views/my_hours_screen.dart`** — 신규. 라우트 `/mis-horas` (`app_router.dart`).

```
┌────────────────────────────┐
│  ‹    julio 2026      ›    │
├────────────────────────────┤
│ mar 15   8h 02m ● trabajando│
│ lun 14   9h 15m            │
│ vie 11   8h 30m            │
├────────────────────────────┤
│ Total            152h 10m  │
│ Vale (adelanto)   $45.000  │
└────────────────────────────┘
```

- 행 탭 → `showModalBottomSheet`: `08:02 → 12:05 (4h 03m)` / `13:01 → en curso`
  세션이 `days[]`에 이미 있으므로 네트워크 호출 없음
- 하단 총계는 스크롤과 무관하게 고정
- 금액 포맷은 기존 `core/format/money.dart` 재사용
- 시각 포맷: UTC ISO → 로컬 표시. **폰 TZ가 아닌 매장 TZ 기준이어야 함** — 서버가 `days[].date`를 매장 TZ로 이미 계산했으므로, 세션 시각도 서버가 매장 TZ 기준 `HH:mm` 문자열을 함께 내려준다 (`sessions[].inLocal`, `outLocal`). 앱에서 TZ 재계산 금지(폰이 다른 TZ면 어긋남)

**`views/home_screen.dart`** — 헤더 수정:
- 아바타(`CircleAvatar`)를 `PopupMenuButton`으로 감쌈 → Mis horas / Adelanto / Salir
- 기존 `payments_outlined`·`logout` `IconButton` 2개 제거
- `_MonthHoursCard` 배너는 그대로 유지 (총액 요약)
- `/adelanto` 라우트·화면은 **무변경**

## 데이터 흐름

```
앱 /mis-horas 진입
  → monthDetailProvider(month)
  → GET /mobile/attendance/month?month=2026-07   (JWT)
      → AttendanceService.sellerMonthDetail(userId, month)
          → Sellers(linkedUserId) → seller.storeId
          → storeTimezone(storeId) → tz
          → seller_attendance 조회 (AT TIME ZONE tz) → days[] 그룹핑
          → AdelantoService.sellerMonthApprovedTotal(seller.id, month)
  → 화면 렌더 (목록 + 총계 + vale)
  → 행 탭 → 바텀시트 (이미 받은 sessions 사용, 호출 없음)
```

## 에러 / 엣지 케이스

| 상황 | 동작 |
|---|---|
| 판매원 미연결(admin 계정 등) | 빈 응답 → "Sin registros" 빈 상태. 에러 아님 (기존 `/summary` 계약 일치) |
| 근무 이력 0일 | 빈 목록 + Total `0h 00m` |
| 네트워크 실패 | 에러 상태 + 재시도 버튼 (기존 `ApiException` 매핑) |
| 세션 만료(401) | 기존 `sessionExpiredSignal` → `/login` 리다이렉트 (전역 처리) |
| 열린 세션 | `seconds` = `now - check_in_at`, `open: true`, `● trabajando` |
| 자정 넘긴 근무 | `check_in_at` 날짜에 귀속 (세션 1행 = 1근무). 총계엔 영향 없음 |
| 미래 월 | `›` 비활성 — 이번 달까지만 |
| `payroll_period` 미지정 승인건 | vale 총액에 미포함 (관리자가 차감월 지정해야 집계). 웹과 동일 동작 |

## 테스트

**백엔드** — `attendance.service.spec.ts` (기존 파일에 추가):
- 점심 분리 세션 2개(08–12, 13–18)가 **하루 1행**으로 합산, 점심 제외
- 열린 세션 → `open: true` + 경과 초 포함
- **TZ 경계**: 매장 TZ 자정 직전/직후 punch가 올바른 `local_date`로 귀속 (Buenos_Aires 기준 UTC-3 검증)
- 월 경계: 전월 말일/익월 1일 punch 제외
- seller 미연결 → 빈 응답 (throw 아님)
- `days` 내림차순 정렬

**adelanto**:
- `payroll_period` 기준 집계 (`requested_at` 아님을 명시 검증)
- `pending`/`rejected` 제외
- 타 판매원 건 미포함

**앱**: 기존 jest/flutter test 구성 따름. DTO 파싱 + 빈 상태 렌더.

## 배포

- 스키마 변경 없음 → 마이그레이션 없음
- api-ventago + mobile-sales-app 두 repo 커밋 (mobile-sales-app은 nested repo — 별도 push 필요)
- 운영 배포 = **수동 Jenkins** (`api-new-coolsistema` job). APK는 별도 빌드
- 구버전 앱 호환: 신규 엔드포인트만 추가, 기존 `/summary` 무변경 → 구버전 앱 정상 동작

## 미해결 / 후속

- 기존 `sellerMonthSummary` / `listSessions`의 TZ 미변환 문제 — 별도 이슈. 관리자 리포트 수치가 바뀌므로 독립 검증 필요
- 급여 금액(시급 × 시간 − vale) 계산은 SPEC D3에서 잠김 — 요구되면 별도 phase
