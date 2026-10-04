# Phase 98 — Galaxy Watch(Wear OS) 매장 admin 앱 · 제안서 (2026-10-04)

> 상태: **제안** — 아래 「결정 필요」 4건을 사용자가 정한 뒤 `/gsd:plan-phase 98` 로 상세 계획.
> 목업: `98-mockup.html` / `98-mockup.png`

## 1. 목표

매장 admin 이 손목에서 **오늘 매출**과 **카하 현황**을 본다. 앱을 열면 바로 최신값,
워치 페이스(Tile·컴플리케이션)에서는 몇 분 단위로 갱신된 값을 본다. **읽기 전용** —
워치에서는 아무것도 바꾸지 않는다.

사용자 결정(2026-10-04): 플랫폼 = **Galaxy Watch(Wear OS)**, 정보 = **오늘 매출 + 카하 현황**,
방식 = **B(워치 전용 앱)**.

## 2. 현재 상태 (근거)

| 항목 | 사실 | 근거 |
|---|---|---|
| 휴대폰 admin 앱 | Flutter `tienda-admin-app` (`com.coolsistema.tienda_admin_app`), APK 를 Dropbox 로 배포 | `tienda-admin-app/build-apk.sh` |
| 인증 | `/auth/login` → JWT **6시간**. 지문 없이 로그인하면 ActiveSession 을 안 만든다(웹 세션 안 끊김) | `api-ventago/src/app/auth/auth.service.ts:636` |
| 장기 토큰 | `admin_device_tokens`(90일 sliding·30일 유휴·회수) — **superadmin·agent 전용** | `admin-device-token.service.ts:52` |
| 카하 현황 | `GET /cash-register/overview` — **서랍(box) 단위**, 잔액·열림·담당자·미마감, 매장 타임존, 지점 스코프를 서버가 JWT 로 계산 | `cashRegister.service.ts:1569` |
| 오늘 매출 | `GET /dashboards/sales/summary` — ★ 「오늘」을 **서버 자정(UTC)** 으로 자른다 | `salesDashboards.service.ts:45` |
| FCM | `mobile_sessions.fcm_token` 컬럼만 있고 발송 코드 없음 | `mobile/models/mobile-session.model.ts:54` |

★ **부수 발견**: `dashboards/sales/summary` 의 `today.setHours(0,0,0,0)` 는 컨테이너가 UTC 라
  아르헨티나 21:00 부터 「오늘 매출」이 0 으로 리셋된다(메모리 db-is-utc-so-today-needs-store-timezone).
  휴대폰 앱·웹 대시보드도 같은 숫자를 쓴다. 워치는 이 엔드포인트를 쓰지 않고 매장 타임존으로 새로 계산한다.
  기존 엔드포인트 수정은 별도 결정.

## 3. 설계

### 3-1. 워치 앱 기술 — **Kotlin + Jetpack Compose for Wear OS** (권장)

| | Kotlin/Compose (권장) | Flutter on Wear OS |
|---|---|---|
| 원형 화면·회전 베젤 | Wear Compose 기본 지원 | 패키지로 일부 |
| **Tile·컴플리케이션** | 공식 API | **불가**(결국 네이티브 필요) |
| 배터리·백그라운드 갱신 | WorkManager·Tile freshness | 제약 큼 |
| 기존 코드 재사용 | 없음(화면 2개라 작다) | 일부 |

화면이 2개뿐이라 재사용 이득이 작고, 손목에서 가장 많이 볼 곳(Tile)이 Flutter 로는 안 된다.

위치: 모노레포 새 디렉터리 `wear-admin-app/`. applicationId 는 휴대폰 앱과 **같은 값**
(`com.coolsistema.tienda_admin_app`) — Play 에서 「휴대폰 앱의 워치 버전」으로 묶이고,
나중에 Data Layer 를 쓸 여지도 남긴다.

### 3-2. 인증 — **코드 페어링 + 워치 전용 읽기 토큰** (권장)

워치에서 비밀번호를 칠 수 없다. 6시간 JWT 는 하루도 못 버틴다.

1. 워치 첫 실행 → 서버에서 **8자리 코드** 발급(5분 만료) → 화면에 표시
2. admin 이 휴대폰 앱(또는 웹) 「Relojes vinculados」에 코드 입력 → 서버가 **그 사용자·매장**에 결속
3. 워치가 폴링으로 **워치 토큰** 수령 → 이후 이 토큰만 사용

워치 토큰의 성질 (기기 토큰 72-03 의 4성질을 그대로):
- **범위**: `GET /watch/resumen` **하나만**. 다른 모든 라우트에서 401. JWT 가 아니라 별도 가드.
- **회전·만료**: 90일 sliding · 30일 유휴. **회수**: 휴대폰 앱/웹 목록에서 한 번에.
- 권한은 매 요청 시 **현재 사용자 상태**로 다시 판정 — 사용자가 정지·역할 회수되면 즉시 끊긴다.
- 지점 스코프: gerente 는 자기 지점만(overview 의 `resolveAllowedBranchIds` 재사용).
- 토큰은 헤더로만(URL 금지 — 메모리 capability-in-url-is-a-log-leak). 코드 시도는 rate limit.

새 테이블 `watch_devices`(user_id, store_id, token_hash, code_hash, code_expires_at, paired_at,
last_seen_at, revoked_at, model). `admin_device_tokens` 를 넓히지 않는 이유: 그 토큰은
「전체 API 를 여는 열쇠」이고 이것은 「한 엔드포인트만 여는 열쇠」라 섞으면 범위가 넓어진다.

### 3-3. API — `GET /watch/resumen` (한 번에 다)

```jsonc
{
  "tienda": "NOIX", "hoy": "2026-10-04", "zona": "America/Argentina/Buenos_Aires",
  "actualizado": "2026-10-04T14:32:10-03:00",
  "ventas": {
    "total": 1284500, "tickets": 87,
    "ayerMismaHora": 1102300,           // 「어제 이 시각까지」 — 하루 전체와 비교하면 오전엔 늘 마이너스
    "porSucursal": [{ "id": 3, "nombre": "Centro", "total": 842000, "tickets": 55 }]
  },
  "cajas": {
    "abiertas": 3, "total": 4, "efectivoEnCajas": 412300,
    "lista": [{ "box": "Caja 1", "sucursal": "Centro", "abierta": true,
                "desde": "08:58", "usuario": "Israel", "saldo": 182300, "pendientesAnteriores": 0 }]
  }
}
```
- 매출: `sales.branch_id` 기준 · `activity_type='sale'` · **매장 타임존의 오늘** · 취소 제외.
- 카하: `getTesoreriaOverview` 를 **그대로** 호출(잔액 공식 복제 금지 — 메모리 caja-balance-formula-duplicated-9-places).
- 캐시: 매장·스코프별 30초(MemoryCacheService). 워치가 수백 개여도 DB 부하는 매장당 30초 1회.

### 3-4. 워치 화면 (목업 참조)

1. **페어링** — 코드 크게 + 「Abrí la app Ventago Admin › Relojes」
2. **Ventas hoy** — 총액 · 어제 같은 시각 대비 ▲▼% · 티켓 수 · 아래로 돌리면 지점별
3. **Cajas** — 「3/4 abiertas」 + 서랍 목록(●열림/○닫힘, 잔액, 담당자). 지난 날 미마감은 ⚠
4. **Tile** — 매출 총액 + 열린 카하 수(가로 스와이프로 접근)
5. **컴플리케이션** — 워치 페이스에 「$1,28M」 짧은 값

갱신: 앱 열면 즉시 · Tile 15분(시스템 최소) · 오프라인이면 마지막 값 + 「hace 12 min」.

### 3-5. 휴대폰 앱(tienda-admin-app) — 「Relojes vinculados」

코드 입력 · 연결된 워치 목록(모델·마지막 접속) · 회수. 웹(`/configuracion`)에도 같은 화면을 둘지는 결정 필요.

## 4. 웨이브

| W | 내용 | 대상 | 규모 |
|---|---|---|---|
| W1 | `watch_devices` 마이그레이션(로컬+운영) · 페어링 3엔드포인트 · 워치 토큰 가드 · `/watch/resumen` · jest(범위·회수·스코프·타임존 돌연변이) | api | M |
| W2 | 「Relojes vinculados」 화면 | tienda-admin-app (+웹 선택) | S |
| W3 | Wear OS 앱: 페어링 · Ventas · Cajas · 오프라인 표시 | wear-admin-app (신규) | M |
| W4 | Tile + 컴플리케이션 | wear-admin-app | S–M |
| W5 | 배포(서명·Play 또는 사이드로드 안내) · 실기기 검증 | — | S |

의존: W1 → (W2 ∥ W3) → W4 → W5. API 는 워치가 없어도 무해하게 먼저 배포 가능(새 라우트만 추가).

## 5. 영향·위험

- **DB**: 새 테이블 1개(트래픽 없음 → 잠금 문제 없음). owner/시퀀스 coolsistema 이전 필수.
- **다른 매장**: 없음(새 라우트·새 테이블만). 기존 대시보드 「오늘」 버그는 별건으로 둔다.
- **보안**: 새 장기 자격증명이 생긴다 → 범위를 엔드포인트 1개로 못 박는 것이 핵심. 분실 워치는 회수로 끝.
- **빌드 환경**: Android SDK 는 `/opt/homebrew/share/android-commandlinetools` 에 있음. Wear OS 에뮬레이터 이미지 설치 필요.
  GitHub Actions 는 결제 문제로 안 돎(메모리) → 로컬 빌드.

## 6. 결정 필요 (사용자)

1. **배포 방식** — Wear OS 는 APK 를 워치에 직접 넣기가 어렵다(워치 개발자 옵션 + ADB 무선 디버깅).
   - (권장) **Google Play 내부 테스트 트랙** — 매장 admin 은 Play 에서 워치에 설치. Play 개발자 계정(US$25 1회) 필요. 계정이 있습니까?
   - 대안: 사이드로드 — 우리가 매장마다 직접 설치해 준다(소수 매장이면 가능, 업데이트도 손으로).
2. **누가 볼 수 있나** — admin 만 / admin + gerente(자기 지점만).
3. **페어링 코드 입력 위치** — 휴대폰 앱만 / 웹 Configuración 도.
4. **금액 표시** — 워치 화면이 작다. 「$1.284.500」 전체 / 「$1,28 M」 축약(컴플리케이션은 축약 필수).

## 7. 검증

- api: jest — 워치 토큰으로 다른 라우트 401 · 회수 즉시 401 · 정지 사용자 401 · gerente 타지점 0 ·
  타임존 경계(21:00~24:00 AR) 매출이 「오늘」에 남는지 · **돌연변이**로 각 가드를 지워 실패 확인.
- 워치: Wear OS 라운드 에뮬레이터 → 실기기 Galaxy Watch. 비행기 모드에서 마지막 값 표시.
- 실데이터: 운영 매장 하나로 `/watch/resumen` 값과 웹 Tesorería·판매 목록 합계를 대조.
