# Design: QR 출퇴근 통제 (Fichaje / Asistencia) — Phase 37-06

생성일: 2026-07-11
소속 Phase: **37 — Mobile Sales Shell** (신규 Wave 37-06 로 편입, 전체 흐름 연속성 유지)
선행: Phase 37 (vendedor Flutter 앱 + `mobile-sales-app/` + `MobileSessionGuard`), `Sellers` 테이블(`linked_user_id`/`branch_id`/`store_id`)

---

## 목표

판매원(vendedor)이 매장 caja 컴퓨터에 표시된 **매일 바뀌는 QR 코드**를 모바일 앱으로 스캔해 **출근/퇴근 시각을 시스템에 기록**한다. QR 에는 날짜·매장·지점 정보가 담기며 caja 에서만 생성·표시된다. 한 판매원이 같은 매장의 다른 지점으로 출근하는 크로스 지점 근무를 지원한다. Reportaje 에서 판매원별 이번 달 총 근무시간을 집계한다.

## 배경

- Phase 37 로 vendedor 듀얼모드 Flutter 앱 이미 구축(코드+API UAT 완료). 본 기능은 그 앱에 "출퇴근 등록" 진입점을 추가하는 확장.
- `mobile-sales-app/lib/features/scanner/` 가 이미 존재(Phase 38 D-14 재고조회 QR 스캔) → 카메라/QR 파싱 인프라 재사용.
- `Sellers` 테이블에 `linked_user_id`(앱 로그인 유저), `branch_id`, `store_id` 존재 → 귀속 처리 가능.
- `stores.timezone` 존재(default `America/Bogota`) → 날짜 경계 판정에 사용.
- 출퇴근 전용 테이블 없음 → 신규 생성.

## 확정된 결정 (사용자 승인 2026-07-11)

| 결정 | 선택 | 근거 |
|---|---|---|
| 출퇴근 판정 | **단일 스캔 자동토글** | 열린 세션 없으면 entrada, 있으면 salida. 스캔 1번, 오조작 최소 |
| QR 보안 | **서명된 일일 공용코드 HMAC** | HMAC(secret, store+branch+date). 종일 유효(모니터 상시 노출). 테이블 불필요. + vendedor.store_id == QR.store_id 강제 |
| 근무시간 계산 | **세션 합산** | 하루 여러 in/out 각각 세션, 월 총시간 = 마감 세션 합 |
| 누락 보정 | **관리자 수동 수정 허용** | Reportaje 에서 열린/오류 세션 수정, audit(adjusted_by) 기록 |

## 데이터 모델 — 신규 테이블 `seller_attendance`

세션 행 방식(한 근무 = 한 행, entrada 시 open, salida 시 close).

| 컬럼 | 타입 | Null | 비고 |
|---|---|---|---|
| `id` | serial | NOT NULL | PK |
| `seller_id` | integer | NOT NULL | FK `Sellers.id` — 귀속 대상 |
| `store_id` | integer | NOT NULL | FK `stores.id` |
| `branch_id` | integer | NOT NULL | FK `branch.id` — **QR 지점 = 실제 출근한 곳** |
| `user_id` | integer | NULL | FK `users.id` — 앱 로그인 유저(linked_user_id) |
| `check_in_at` | timestamptz | NOT NULL | 출근 |
| `check_out_at` | timestamptz | NULL | NULL = 열린 세션(미퇴근) |
| `source` | varchar(16) | NOT NULL default `'qr'` | 향후 수동입력 등 확장 |
| `adjusted_by` | integer | NULL | FK `users.id` — 수동보정 관리자 |
| `adjusted_at` | timestamptz | NULL | 보정 시각 |
| `note` | text | NULL | 보정 사유 |
| `created_at` | timestamptz | NOT NULL | |
| `updated_at` | timestamptz | NOT NULL | |

인덱스:
- `CREATE UNIQUE INDEX ON seller_attendance (seller_id) WHERE check_out_at IS NULL;` — 판매원당 열린 세션 최대 1개 보장 + 즉시 조회
- `CREATE INDEX ON seller_attendance (store_id, check_in_at);` — 월별 리포트

**운영 5434**: 마이그레이션 SQL 끝에 role 존재체크 DO 블록으로 `ALTER TABLE seller_attendance OWNER TO coolsistema` + `ALTER SEQUENCE seller_attendance_id_seq OWNER TO coolsistema`.

월 총시간 계산: `SUM(check_out_at - check_in_at)` — 마감 세션만(열린 세션 제외, 리포트에 경고 표시).

## QR 토큰 — HMAC 일일 공용코드

- QR 내용 = 딥링크 `/m/fichaje?s={storeId}&b={branchId}&d={yyyy-mm-dd}&t={token}` (`/m/stock` 딥링크 패턴 재사용)
- `token = base64url( HMAC_SHA256(APP_SECRET, "${storeId}:${branchId}:${yyyy-mm-dd}") )`
- `APP_SECRET` = 서버 환경변수(신규). 유출 시 QR 위조 가능하므로 기존 JWT secret 과 분리 권장.
- 서버 검증(punch 시): 전달된 s/b/d 로 HMAC 재계산 → `t` 와 일치 확인 + `d == 오늘`(해당 store `timezone` 기준) + 유예(당일만; 자정 직후 grace 는 열린 세션 salida 로직이 흡수). 어제 QR → `QR_EXPIRED` 400.
- 별도 nonce 테이블 없음. 종일 재사용 = 요구사항(보조 모니터 상시 노출).

## 백엔드 — 신규 모듈 `api-ventago/src/app/attendance/`

파일: `attendance.module.ts`, `attendance.service.ts`, `attendance.controller.ts`, `models/seller-attendance.model.ts`.

엔드포인트:
1. `GET /attendance/qr?branchId=` — caja 생성용.
   - 가드: JWT + **desktop active_session(SessionGuard)** = caja 컴에서만. branchId 는 요청 유저 store 소속 검증.
   - 반환 `{ payload: string(딥링크), date, storeId, branchId, refreshAt(자정 store TZ) }`
2. `POST /attendance/punch` — 모바일.
   - 가드: `MobileSessionGuard` + role=vendedor.
   - body `{ s, b, d, t }`
   - 로직:
     1. HMAC + date 검증 (실패 → `QR_EXPIRED` / `QR_INVALID`)
     2. seller = `Sellers.findOne({ linked_user_id: currentUser.id })` (없으면 `NOT_A_SELLER` 403)
     3. **가드: `s`(QR.store_id) === `seller.store_id`** 아니면 `QR_OTHER_STORE` 403. (branch 다른 건 허용 = 크로스 지점)
     4. 열린 세션 조회(`seller_id`, `check_out_at IS NULL`):
        - 없음 → INSERT entrada (`check_in_at=now`, `branch_id=b`) → `action:'in'`
        - 있음 → 마지막 스캔이 60초 이내면 멱등 무시(더블탭 방지, 직전 action 반환); 아니면 UPDATE `check_out_at=now` → `action:'out'`
     5. 반환 `{ action, at, branchName, todayWorkedSeconds }`
3. `GET /attendance/report?month=YYYY-MM&branchId=(optional)` — 웹 리포트, admin 권한.
   - 판매원별 `SUM(마감 세션 duration)`, 세션수, 열린(미마감) 세션 수 반환. store_id 격리.
4. `PATCH /attendance/:id` — 관리자 수동보정.
   - body `{ checkInAt?, checkOutAt?, note }` → `adjusted_by=currentUser.id`, `adjusted_at=now`. store_id 소유권 검증(IDOR 가드).

캐시: 리포트는 무거우면 `MemoryCacheService` 30초 TTL. punch/qr 는 캐시 없음.

## 프론트엔드 — POS 웹 (ventago-app)

1. 전역 **Ctrl+V** 단축키 → 풀스크린 모달 `AttendanceQrOverlay`.
   - 현 터미널의 branch 로 `GET /attendance/qr` 조회 → 큰 QR 렌더(보조 모니터 대응, 고대비).
   - 자정(store TZ) 도달 시 자동 재조회. ESC 로 닫기.
   - 배치: 전역 키핸들러(레이아웃 레벨), 소매/식당 무관 공통.
2. Reportaje: 신규 페이지 `ventago-app/src/pages/reportes/asistencia/` (기존 `reportes/vendedor` 옆).
   - `next/dynamic(ssr:false)` 코드 스플리팅.
   - 표 = 판매원 | 이번달 총 근무시간(Hh Mm) | 세션수 | 미마감 경고(빨강 배지).
   - 월 선택기. 행 클릭 → 세션 상세 + 열린/오류 세션 수정 모달(`PATCH /attendance/:id`).
   - SWR 훅 `useAttendanceReport(month)`.

## 모바일 앱 (mobile-sales-app)

- 신규 feature `lib/features/attendance/` — 기존 `scanner/` 카메라·QR 파싱 재사용.
- 홈 화면 버튼 "Fichar entrada/salida" (vendedor role 일 때만 노출).
- 스캔 → 딥링크 `/m/fichaje?...` 파싱 → `POST /attendance/punch` → 결과 화면:
  - `action:'in'` → "Entrada registrada 08:32"
  - `action:'out'` → "Salida registrada 17:05 · Hoy 8h 33m"
  - 에러 → 인라인 Alert + 토스트(QR_EXPIRED="Pedí el QR de hoy", QR_OTHER_STORE="QR de otra tienda").

## 크로스 지점 처리

QR 가 branch 를 실어 옴 → punch 는 그 `branch_id` 로 기록. 판매원은 자기 매장(store) 내 어느 지점 QR 이든 출퇴근 가능. 리포트는 seller 기준 집계, 필요 시 branch 분해 표시.

## 마이그레이션

`api-ventago/migrations/37-06-seller-attendance.sql` — CREATE TABLE + 인덱스 2개 + owner DO 블록.
- 로컬 5432: 사용자가 Mac 에서 `psql -p 5432 -d ventago -f ...` 실행(샌드박스 미도달).
- 운영 5434: SSH `sudo -u postgres psql -p 5434 -d ventago -v ON_ERROR_STOP=1 --single-transaction -f ...` (사용자 확인 후).
- 양쪽 스키마 대조 확인. `.planning/intel/db-schema.regen.sh` 재생성.

## 엣지/보안

- 어제/위조 QR → 400 거부, 앱에 명확 안내.
- 타 매장 vendedor 스캔 → 403.
- 더블탭 즉시 in→out → 60초 멱등 가드.
- 퇴근 누락 → 열린 세션 잔류 → 리포트 빨강 경고 → admin 보정.
- store_id 멀티테넌트 격리 전 엔드포인트 강제.
- 소매/식당 판매 경로 무영향(신규 격리 모듈, 기존 테이블 alter 없음).

## 범위밖 (YAGNI)

GPS 위치검증, 지각/조퇴/초과근무 규칙, 급여 연동, 라이더·revendedor 출퇴근, 얼굴/생체 인증, 오프라인 큐잉.

## 성공 기준 (구현 후 TRUE 여야)

1. caja 웹에서 Ctrl+V → 오늘자 QR(store+branch+date) 풀스크린 표시, 자정 자동 갱신
2. vendedor 앱 스캔 → 첫 스캔 entrada, 다음 스캔 salida 자동토글 기록
3. 같은 매장 다른 지점 QR 로 출퇴근 가능(크로스 지점), 타 매장 QR 은 거부
4. 어제 QR/위조 QR 거부
5. Reportaje 에 판매원별 이번 달 총 근무시간 + 미마감 경고 표시
6. 관리자가 누락/오류 세션 수동 보정 가능(audit 기록)
7. 소매/식당 기존 판매 기능 무회귀
