# Design: QR 출퇴근 통제 (Fichaje / Asistencia) — Phase 37-06

생성일: 2026-07-11
소속 Phase: **37 — Mobile Sales Shell** (신규 Wave 37-06 로 편입, 전체 흐름 연속성 유지)
선행: Phase 37 (vendedor Flutter 앱 + `mobile-sales-app/` + `MobileSessionGuard`), `Sellers` 테이블(`linked_user_id`/`branch_id`/`store_id`)

---

## 목표

caja 컴퓨터에 표시된 **매일 바뀌는 단일 QR 코드**(날짜·매장·지점)를 모바일 앱이 스캔하고, **role 로 동작이 갈린다**:
- **vendedor**: 출근/퇴근 시각 기록(자동토글). 출근 전·퇴근 후·caja 마감 후 전면 작업 불능. 소속 지점(BranchScope) 자료만 조회·판매. 크로스 지점 출근 지원. Reportaje 월 총근무시간 집계.
- **revendedor**: 매장에 물리적으로 방문해 그 매장 QR 을 스캔하면 해당 매장 판매권 획득(영구, 관리자 취소 전까지). Phase 24 관리자 승인 + QR 물리 확인 둘 다 필요.
QR 은 Windows/macOS 데스크톱 caja 에서만 생성·표시(핸드폰 불가).

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
| QR 생성 플랫폼 | **Windows/macOS 데스크톱 전용** | 핸드폰(caja 권한자 포함) 생성 불가. desktop active_session + UA 판정 |
| vendedor 게이트 | **출근 전 전 작업면 차단** | 열린 세션 없으면 카탈로그·스톡·판매 전부 `NOT_CLOCKED_IN` |
| 퇴근 누락 | **caja 마감 시 강제 종료** | 관리자 caja cierre → 지점 열린 세션 강제 salida + vendedor 완전 불능 |
| revendedor 판매권 | **매장 승인 QR(영구) + Phase 24 승인** | 물리 방문 스캔 1회 영구 판매권. 관리자 승인과 둘 다 필요. 단일 QR role 라우팅 |

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

## 데이터 모델 — 신규 테이블 `reseller_store_qr_auth` (revendedor 매장 판매권)

revendedor 가 매장에 물리적으로 가서 승인 QR 을 스캔한 사실을 영구 기록. 매장별 판매권 게이트.

| 컬럼 | 타입 | Null | 비고 |
|---|---|---|---|
| `id` | serial | NOT NULL | PK |
| `reseller_user_id` | integer | NOT NULL | FK `users.id` — revendedor 계정 |
| `store_id` | integer | NOT NULL | FK `stores.id` — 판매권 대상 매장(QR 의 store) |
| `branch_id` | integer | NULL | FK `branch.id` — 스캔한 지점(증빙) |
| `authorized_at` | timestamptz | NOT NULL | 최초 스캔 시각 |
| `revoked_at` | timestamptz | NULL | 관리자 취소 시각(NULL = 유효) |
| `revoked_by` | integer | NULL | FK `users.id` |
| `created_at`/`updated_at` | timestamptz | NOT NULL | |

인덱스: `CREATE UNIQUE INDEX ON reseller_store_qr_auth (reseller_user_id, store_id);` — 매장당 1행, 재스캔 idempotent.
유효기간: **영구** — `revoked_at IS NULL` 이면 유효. 관리자 취소로만 해제.
운영 5434 owner→coolsistema + 시퀀스 owner 이전.

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
   - **플랫폼 가드 (Windows/macOS 데스크톱 전용, 핸드폰 차단)**: caja 권한 유저라도 모바일에서 QR 생성 불가.
     - 1차 방어(구조적): QR 생성은 데스크톱 `active_sessions` 토큰 필수. 모바일 앱은 별도 `mobile_sessions`(Phase 37) 를 쓰므로 폰은 이 엔드포인트에 애초에 도달 못 함.
     - 2차 방어(명시적): 요청 User-Agent 플랫폼 판정 → Windows / macOS 아니면(Android/iOS/모바일 브라우저) `PLATFORM_NOT_ALLOWED` 403. 모바일 UA 패턴(Mobi/Android/iPhone/iPad) 거부.
   - 반환 `{ payload: string(딥링크), date, storeId, branchId, refreshAt(자정 store TZ) }`
2. `POST /attendance/punch` — 모바일 **단일 QR, role 라우팅**.
   - 가드: `MobileSessionGuard` (vendedor + revendedor 공통).
   - body `{ s, b, d, t }`
   - 공통: HMAC + date 검증 (실패 → `QR_EXPIRED` / `QR_INVALID`). date freshness 는 revendedor 도 강제 = 그날 매장에 실제 있었음을 보장.
   - **role=vendedor → 출퇴근 세션 토글:**
     1. seller = `Sellers.findOne({ linked_user_id: currentUser.id })` (없으면 `NOT_A_SELLER` 403)
     2. **가드: `s`(QR.store_id) === `seller.store_id`** 아니면 `QR_OTHER_STORE` 403. (branch 다른 건 허용 = 크로스 지점)
     3. 열린 세션 조회(`seller_id`, `check_out_at IS NULL`):
        - 없음 → INSERT entrada (`check_in_at=now`, `branch_id=b`) → `action:'in'`
        - 있음 → 마지막 스캔 60초 이내면 멱등 무시(더블탭 방지); 아니면 UPDATE `check_out_at=now` → `action:'out'`
     4. 반환 `{ action:'in'|'out', at, branchName, todayWorkedSeconds }`
   - **role=revendedor → 매장 판매권 등록(영구, idempotent):**
     1. **가드: revendedor 가 Phase 24 관리자 승인 링크(`reseller_tienda_link`)를 가진 매장**만 허용. 없으면 `RESELLER_NOT_APPROVED` 403 (관리자 승인 + QR 둘 다 필요).
     2. `reseller_store_qr_auth` upsert (`reseller_user_id=currentUser.id`, `store_id=s`, `branch_id=b`, `authorized_at=now`). 이미 있으면(재스캔) `authorized_at` 유지, 멱등.
     3. 반환 `{ action:'store_authorized', storeId, storeName }`
3. `GET /attendance/report?month=YYYY-MM&branchId=(optional)` — 웹 리포트, admin 권한.
   - 판매원별 `SUM(마감 세션 duration)`, 세션수, 열린(미마감) 세션 수 반환. store_id 격리.
4. `PATCH /attendance/:id` — 관리자 수동보정.
   - body `{ checkInAt?, checkOutAt?, note }` → `adjusted_by=currentUser.id`, `adjusted_at=now`. store_id 소유권 검증(IDOR 가드).
5. `DELETE /attendance/reseller-auth/:id` (또는 `PATCH revoke`) — 관리자 revendedor 매장 판매권 취소 → `revoked_at=now`, `revoked_by`. store_id 소유권 검증.

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

- 신규 feature `lib/features/attendance/` — 기존 `scanner/` 카메라·QR 파싱 재사용. 단일 QR, role 로 UI 분기.
- **vendedor**: 홈 버튼 "Fichar entrada/salida". 스캔 → `POST /attendance/punch`:
  - `action:'in'` → "Entrada registrada 08:32"
  - `action:'out'` → "Salida registrada 17:05 · Hoy 8h 33m"
  - 에러 토스트(QR_EXPIRED="Pedí el QR de hoy", QR_OTHER_STORE="QR de otra tienda").
- **revendedor**: 매장 미승인 시 카탈로그 진입 차단 + "Escaneá el QR de la tienda para habilitar" → 스캔 → `POST /attendance/punch`:
  - `action:'store_authorized'` → "Tienda {name} habilitada" → 그 매장 카탈로그 개방.
  - 에러 토스트(RESELLER_NOT_APPROVED="Tienda no aprobada por admin", QR_EXPIRED).

## 출근 게이트 — 스캔 전 작업 차단 (vendedor 전용)

QR 을 찍기 전(= 열린 `seller_attendance` 세션 없음)에는 vendedor 가 판매 기록·스톡 확인·카탈로그 열람을 **전부** 할 수 없다.

- 신규 `RequireAttendanceGuard` (백엔드) 를 vendedor 대상 작업 엔드포인트에 적용:
  - `GET /mobile/catalog`, `GET /mobile/stock/:id`, `POST /mobile/sales`
  - 로직: role=vendedor 이고 열린 세션(check_out_at IS NULL) 없으면 `NOT_CLOCKED_IN` 403.
  - **role=revendedor 는 이 가드 통과(출퇴근 무관) — 대신 `RequireStoreAuthGuard`(매장 승인 QR) 적용, 아래 참조.** vendedor 는 퇴근(salida)·caja 마감 후 열린 세션 없음 → 다시 차단 = 근무 중일 때만 작업 가능.
  - 캐시: 요청당 1회 세션 조회(가벼움). punch 직후 캐시 무효화 불필요(세션 조회는 실시간).
- 면제 엔드포인트: `/mobile/me`, `/attendance/*`(fichaje 자체), 홈.
- Flutter 앱: 열린 세션 없으면 홈에 "Fichá tu entrada para empezar" + fichaje 버튼만 노출, Catálogo/스캐너/판매 진입 비활성. `/mobile/me` 응답에 `clockedIn: bool` + `openSince` 포함해 앱이 게이트 상태 즉시 판정(라운드트립 절약).

## revendedor 처리 — 매장 승인 QR (사용자 결정 2026-07-11, 이전 "면제" 안 폐기)

revendedor 는 매장에 **물리적으로 한 번 방문해 그 매장의 승인 QR 을 스캔**해야 해당 매장 카탈로그 판매권을 얻는다. 근무시간(출퇴근 세션) 통제는 아니지만, 매장별 판매권은 물리 확인 게이트를 통과해야 한다.

- **판매권 = Phase 24 관리자 승인(`reseller_tienda_link`) AND `reseller_store_qr_auth`(QR 물리 확인) 둘 다** 있어야 성립. 매장주가 누가 자기 상품을 파는지 물리적으로 확인.
- 유효기간 **영구** — 한 번 스캔하면 관리자 취소(`revoked_at`) 전까지 유지. 재방문 불필요, 재스캔은 멱등.
- 신규 `RequireStoreAuthGuard` — revendedor 가 매장 S 카탈로그/견적/주문 접근 시 유효한 `reseller_store_qr_auth`(revoked_at IS NULL) 없으면 `STORE_NOT_AUTHORIZED` 403 → 앱이 "이 매장은 방문·승인 QR 스캔 필요" 안내.
- revendedor 는 vendedor 의 `RequireAttendanceGuard`(일일 출근) 대상 아님 — 매장 판매권은 영구라 매일 스캔 불필요. 두 게이트는 role 별로 분리.
- **활성화 시점**: revendedor 모드는 Phase 24(reseller marketplace) 게이트. 37-06 에서 QR punch 의 role 라우팅 + `reseller_store_qr_auth` 테이블·승인 로직을 구축하되, `RequireStoreAuthGuard` 강제는 revendedor 카탈로그 엔드포인트(Phase 24 Wave)와 함께 활성. 37-06 단독 실행 시 vendedor 출퇴근이 실동작 부분.

## caja cierre = 강제 완전 불능 (퇴근 누락 처리)

관리자가 지점의 **caja(cash_register)를 마감(cierre)하는 순간**, 그 지점의 열린 `seller_attendance` 세션을 전부 강제 종료한다.

- 훅: caja 마감 로직(box / control-de-caja 모듈의 `cash_registers.closing_time` set 지점)에서, 같은 branch 의 `check_out_at IS NULL` 세션 → `check_out_at = 마감시각`, `source='caja_cierre'`, `note='auto: caja cerrada'`. 같은 트랜잭션 내 실행.
- 결과: 마감 후 열린 세션 0 → 해당 vendedor 는 `RequireAttendanceGuard` 로 **완전 불능**(판매·스톡·카탈로그 전부 차단). 다음 영업일 caja 오픈 + 새 QR 스캔해야 재개.
- 퇴근 누락(salida 안 찍음)이 caja 마감으로 자동 정리 → 미마감 세션이 리포트에 무한 누적 안 됨. 마감시각 = 근무 종료로 간주(관리자가 필요 시 `PATCH` 로 보정).
- 소매/식당 caja 마감 경로 공통 적용(단, 열린 세션 없으면 no-op → 무회귀).

## vendedor 매장/지점 스코프 (기존 Phase 37 재확인)

vendedor 는 **소속 매장의 자기 지점 자료만 조회·판매** — Phase 37 `MobileScopeGuard`(BranchScope, `user_branches.branch_id IN (?)`)로 이미 강제됨. 37-06 신규 작업 아님. 출근 게이트는 이 스코프 위에 얹히는 추가 조건.

## 크로스 지점 처리 (vendedor 출퇴근)

출퇴근 QR 은 branch 를 실어 옴 → punch 는 그 `branch_id` 로 기록. vendedor 는 자기 매장(store) 내 어느 지점 QR 이든 출퇴근 가능(크로스 지점 근무). 리포트는 seller 기준 집계, 필요 시 branch 분해 표시. (판매 스코프 자체는 위 BranchScope 로 별도 제한 — 출퇴근 지점과 판매 지점은 개념 분리.)

## 마이그레이션

`api-ventago/migrations/37-06-seller-attendance.sql` — 2개 테이블(`seller_attendance` + `reseller_store_qr_auth`) CREATE + 인덱스(각 부분/유니크) + 양 테이블·시퀀스 owner DO 블록.
- 로컬 5432: 사용자가 Mac 에서 `psql -p 5432 -d ventago -f ...` 실행(샌드박스 미도달).
- 운영 5434: SSH `sudo -u postgres psql -p 5434 -d ventago -v ON_ERROR_STOP=1 --single-transaction -f ...` (사용자 확인 후).
- 양쪽 스키마 대조 확인. `.planning/intel/db-schema.regen.sh` 재생성.

## 엣지/보안

- 어제/위조 QR → 400 거부, 앱에 명확 안내.
- 타 매장 vendedor 스캔 → 403.
- 더블탭 즉시 in→out → 60초 멱등 가드.
- 퇴근 누락 → 열린 세션 잔류 → **caja 마감 시 강제 종료** + 리포트 경고 → admin 보정.
- caja 마감 후 vendedor 완전 불능(열린 세션 0).
- revendedor 매장 미승인 → 카탈로그 차단(`STORE_NOT_AUTHORIZED`). 관리자 미승인 매장 스캔 → `RESELLER_NOT_APPROVED`.
- store_id 멀티테넌트 격리 전 엔드포인트 강제.
- 소매/식당 판매 경로 무영향(신규 격리 모듈, 기존 테이블 alter 없음).

## 범위밖 (YAGNI)

GPS 위치검증, 지각/조퇴/초과근무 규칙, 급여 연동, 라이더 출퇴근, revendedor 근무시간(출퇴근 세션) 통제, revendedor 자가선언 세션, 얼굴/생체 인증, 오프라인 큐잉.

## 성공 기준 (구현 후 TRUE 여야)

1. caja 웹에서 Ctrl+V → 오늘자 QR(store+branch+date) 풀스크린 표시, 자정 자동 갱신. **QR 생성은 Windows/macOS 데스크톱에서만 가능 — 핸드폰(caja 권한자 포함) 은 `PLATFORM_NOT_ALLOWED` 거부**
2. vendedor 앱 스캔 → 첫 스캔 entrada, 다음 스캔 salida 자동토글 기록
2b. **vendedor 는 출근(열린 세션) 전 카탈로그·스톡·판매 전부 차단(`NOT_CLOCKED_IN`), 퇴근 후 다시 차단**
2c. **관리자가 caja 마감(cierre)하면 그 지점 열린 세션 강제 종료 + vendedor 완전 불능**
3. vendedor: 같은 매장 다른 지점 QR 로 출퇴근 가능(크로스 지점), 타 매장 QR 은 거부. 판매는 소속 지점(BranchScope) 자료만
4. 어제 QR/위조 QR 거부
5. Reportaje 에 판매원별 이번 달 총 근무시간 + 미마감 경고 표시
6. 관리자가 누락/오류 세션 수동 보정 가능(audit 기록)
7. **revendedor: Phase 24 관리자 승인 + 매장 방문 승인 QR 스캔 둘 다 있어야 그 매장 카탈로그 판매 가능. 승인은 영구(관리자 취소 전까지). 단일 QR role 라우팅**
8. 소매/식당 기존 판매 기능 무회귀
