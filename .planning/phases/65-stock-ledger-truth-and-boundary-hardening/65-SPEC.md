# Phase 65: 재고 원장 단일 진실 · 테넌트/감사 경계 · 장애 감지 — Specification

**Created:** 2026-07-29
**Source:** `docs/VentaGo_현황진단서_20260729.pdf` (Phase 64 이후 재평가) + `65-CONTEXT.md` 코드 재검증
**Scope:** Wave 1 ~ Wave 9 (결함 9건)
**Requirements:** 9 locked (R1~R9, 결함 번호와 1:1)

## Goal

재고 잔액을 **하나의 진실**로 수렴시키고, 그것이 틀어졌을 때 **시스템이 스스로 발견**하게 만든다.
동시에 Phase 64 가 판매 경로에만 적용한 매장 경계를 **감사·사용자 관리 경로까지** 확장하고,
장애가 났을 때 **누군가 전화하기 전에 알 수 있는** 최소 감지 장치를 넣는다.

Phase 64 가 **쓰기 경로의 원자성·멱등성**을 확립했다면, Phase 65 는 그 위에
**상태의 정확성(재고)·접근의 경계(테넌트)·운영의 가시성(감지)** 세 축을 얹는다. 신규 기능 0, 전부 무회귀 교정.

## Background

Phase 64 는 성공했다 — 판매 멱등, 취소·보류·생산 원자화, outbox lease 가 코드·유닛·동시성·부하까지 검증되고 운영에 반영됐다.
그러나 재고에 대해서는 **선언과 적용 범위가 어긋났다**:

- W7 은 "`stocks` 는 append-only" 를 규약으로 확립하고 grep 게이트를 통과했지만,
  그 게이트는 `stocks.service.ts` **한 파일만** 검사했다. 다른 파일 9곳이 여전히 원장을 UPDATE/DELETE 한다.
- W7 이 도입한 **보정 행 자체가** `type='ajuste'` 라는 모델 정의 밖 값을 쓰는 바람에,
  재고 코크핏이 보정 행을 정상 입고·판매로 집계한다. 고치려고 넣은 장치가 리포트를 오염시키고 있다.
- 가장 자주 쓰이는 재고 경로인 **이동(movido)·폐기(fallado)** 는 원장만 쓰고 `products.stock` 캐시를 갱신하지 않는다.
  1건마다 캐시와 원장이 영구히 벌어진다.
- 그리고 이 모든 것을 **탐지할 장치가 없다**. 재고 관련 크론이 0건이고, 문서에 적힌 유일한 대조 SQL 은
  예약 행을 걸러내지 않아 예약이 있는 상품을 전부 드리프트로 오탐한다.

경계 쪽도 절반만 닫혔다. 판매·식당주문은 막았지만 **감사로그는 요청자 정보조차 받지 않고**,
**사용자 수정은 대상의 소속 매장을 확인하지 않으며 오히려 매장 이동을 허용**한다.
감사로그 경로의 실패 처리가 차단이 아니라 **전체 공개**라는 점이 특히 위험하다.

운영 쪽은 2026-07-25 에 재부팅 후 2시간 다운을 **아무도 몰랐던** 사고가 이미 있었다.
현재 유일한 알람이 "요청이 500을 냈을 때"이므로, 프로세스가 죽으면 알림도 함께 죽는다.

## Requirements

각 요구사항 = 결함 1건. **Current** = 현행 동작(검증됨), **Target** = 목표, **Acceptance** = 완료 판정.

---

### R1. 이동유형 표준화 (결함 1) — Wave 1

- **Current:** 모델 union 은 `'sale' | 'adjust' | 'suspend'`(`stocks.model.ts:15`)인데 실제 기록값은
  `'ajuste'`(`stocks.service.ts:151`, Phase 64 보정 행)와 `'produccion'`(`work-order.service.ts:209`/`:232`)이 추가로 존재한다.
  코크핏 리포트는 `type NOT IN ('adjust','suspend')` 로만 필터하므로(`reportsStocksCockpit.service.ts:476/479/723/726`)
  **보정 행과 생산 행이 정상 입고·판매로 집계된다.**
- **Target:**
  1. union 을 실제 도메인에 맞게 확정한다: `'sale' | 'adjust' | 'suspend' | 'production'`.
     보정 행은 `'adjust'` 로 통일(스페인어 `'ajuste'` 제거), 생산은 `'production'` 으로 표준화.
  2. 기록부 3곳(`stocks.service.ts:151`, `work-order.service.ts:209`, `:232`)을 새 값으로 교체.
  3. 기존 행 백필 — `'ajuste' → 'adjust'`, `'produccion' → 'production'`. **되돌리기 어려우므로 사전 측정 + 승인.**
  4. 리포트 필터를 의미 기준으로 교정: 입고·판매(salidas) 집계는 `'adjust'`·`'suspend'`·`'production'` 을 제외하고,
     생산 물량은 별도 컬럼으로 노출한다(기존 `reservados` 컬럼과 같은 방식).
  5. 타입 안전성 확보 — `type` 값을 상수/enum 으로 중앙화해 문자열 리터럴 직접 사용을 없앤다.
- **Acceptance:** union 밖 `type` 을 기록하는 코드 0건(grep 게이트). DB 에 union 밖 값 0행.
  코크핏의 입고·판매 합계가 보정·생산 행을 포함하지 않음(백필 전후 값 비교로 확인).

### R2. 원장 불변 전면 적용 (결함 2) — Wave 2

- **Current:** `stocks` 를 UPDATE/DELETE 하는 코드가 9곳 잔존 —
  `productStock.service.ts:622/629/914/1493`(destroy), `:401/:483/:727`(update),
  `products.service.ts:431`(update), `subcon-material-issue.service.ts:59`(update).
  `:914` 는 활성 라우트(`products.controller.ts:414`)에 물려 있다.
- **Target:**
  1. 9곳 전부를 `stocks.service.ts:125-165` 의 `adjust()` 패턴으로 교체 —
     원본 `FOR UPDATE` 락 + **반대 부호 보정 행 INSERT** + `products.stock` 동시 조정, 단일 트랜잭션.
     `note` 에 `mov#{id} / user#{id} / 사유` 기록.
  2. 절대값 덮어쓰기(`:401`/`:483`/`:727`) 는 **목표값 − 현재 원장합** 델타를 계산해 보정 행으로 표현.
  3. 기존 라우트·응답 형태는 유지(하위호환). 프런트 변경 0을 목표로 한다.
  4. **DB 계층 안전망** — `stocks` 에 UPDATE/DELETE 를 막는 트리거를 추가한다(보정 행 INSERT 는 허용).
     규약이 코드 리뷰에만 의존하지 않게 한다. *마이그레이션 1건.*
- **Acceptance:** 전 저장소에서 `stocks` 대상 destroy/update 0건(grep 게이트, `stocks.service.ts` 스코프 아님).
  트리거 적용 후 임의 UPDATE 시도가 실패. 기존 라우트 회귀 0(유닛 + 수동 스모크).

### R3. 캐시 갱신 누락 봉합 (결함 3) — Wave 3

- **Current:** 원장만 쓰고 `products.stock` 을 갱신하지 않는 경로 —
  movido/fallado(`stocks.service.ts:368`/`:402`), 외주 로트 입고(`productStock.service.ts:89`),
  변형 일괄 생성(`:265-333`, 자식 `stock` 필드 자체가 없음).
  게다가 부모 집계(`:358-372`)가 **원장 합이 아니라 자식 캐시 합**이라 오차가 부모로 전파된다.
- **Target:**
  1. 위 3개 경로가 **같은 트랜잭션 안에서** `products.stock` 을 증감하도록 수정.
     예약(`suspend`)은 현행대로 캐시를 건드리지 않는다 — 이것은 의도된 설계다(R4 에서 정의로 고정).
  2. `createVariantsBatch` 의 자식 상품 생성 시 `stock` 초기값을 명시.
  3. `updateMotherStock` 을 **원장 합 기준**으로 전환. 자식 캐시 합에 의존하지 않는다.
  4. 헬퍼는 `transaction` 을 필수 인자로 받아 누락을 컴파일 타임에 막는다(CLAUDE.md 규약).
- **Acceptance:** 이동 1건 실행 후 `products.stock` = 해당 상품 원장 합(예약 제외). 실패 주입 시 원장·캐시가 함께 롤백.
  로트 입고 후 POS 판매 검증에 즉시 반영됨. 신규 변형 상품의 캐시가 0에서 출발하지 않음.

### R4. 가용재고 정의 단일화 (결함 4) — Wave 4

- **Current:** 같은 "재고"를 계산하는 SQL 이 최소 4벌이고 `is_active`/`type` 필터가 서로 다르다 —
  `reportsStocksCockpit.service.ts:575`, `reportsAlertas.service.ts:74-89`,
  `productStock.service.ts:1185-1192`(**`is_active` 필터 없음**), `offline-sync/table-registry.ts:191-195`.
  ATP 개념·함수 없음.
- **Target:**
  1. 세 값을 명시적으로 정의하고 문서화한다:
     - **현재고(on-hand)** = `products.stock` (물리 재고, 예약 미반영)
     - **예약(reserved)** = 원장의 `type='suspend'` 합의 절대값
     - **가용(available)** = 현재고 − 예약
  2. 단일 계산 함수/뷰를 만들고 위 4개 경로를 전부 그것으로 수렴시킨다.
     `is_active` 필터 정책도 한 곳에서 결정한다.
  3. `GET /products/:id/live-stock` 의 `is_active` 누락을 교정.
  4. 기존 응답 필드명·의미는 유지하되, 값이 달라지는 경우 **어느 화면이 영향받는지 사전에 목록화**한다.
- **Acceptance:** 재고 수량을 계산하는 SQL 이 단일 출처를 경유. 같은 상품·지점에 대해 4개 경로가 같은 값을 반환.
  변경 전후 값 차이가 있는 경우 원인이 설명 가능(필터 교정 때문임을 확인).

### R5. 정합성 대조·보정 자동화 (결함 5) — Wave 5

- **Current:** 재고 관련 크론 0건. 대조 수단은 문서의 수동 SQL 뿐이고,
  **그 SQL 은 `type='suspend'` 예약 행을 제외하지 않아 예약이 있는 상품을 전부 드리프트로 오탐한다**
  (`docs/db-risk-analysis-20260727.md:88-92`).
  같은 문서가 "드리프트 실재"를 실측 기록하고 야간 보정 잡을 계획했으나 미구현.
- **Target:**
  1. **정확한 대조 쿼리** — R4 의 정의를 사용해 예약분을 제외하고 `products.stock` vs 원장 합을 비교.
  2. **야간 대조 크론** — `mp-wallet-reconcile.cron.ts:27-65` 패턴 이식.
     탐지 → 로그 → 임계 초과 시 알람. **자동 보정은 기본 OFF**(설정 플래그), 초기에는 탐지만 한다.
     *잘못된 자동 보정은 잘못된 수동 보정보다 위험하다.*
  3. **1회 백필** — 착수 전 읽기 전용 측정으로 영향 규모 확정 → 승인 → 보정 행 방식으로 정정(원장 파괴 금지).
  4. **진단 API 노출** — `GET /api/diagnostics/stock-drift`(superadmin). 기존 diagnostics 3종과 같은 형태.
  5. **Centro de Control 연동** — 드리프트 건수를 `infraestructura` 위젯에 추가(예외함이 이미 존재하므로 위젯 추가만).
- **Acceptance:** 백필 후 드리프트 0건. 이후 야간 크론이 지속 0 을 보고.
  의도적으로 드리프트를 만든 테스트에서 크론이 탐지하고 알람이 발생. 진단 API 가 건수·상세를 반환.

### R6. 감사·사용자 매장 경계 (결함 6·7) — Wave 6

- **Current:**
  - `audit-log.controller.ts:37-42` — `@GetUser()` 없이 entityType+entityId 로만 조회.
  - `audit-log.controller.ts:50-53` — 역할 배열이 비면 `getAllLogs(page, size, {})` 로 **전 매장 반환**.
  - `users.service.ts:299` — `findByPk(id)`, storeId 대조 없음. `:322` — `dto.storeId` 로 **타 매장 이동 가능**.
  - `approval.service.ts:168-203` — `approve()` 에 자가 승인 차단 없음 → maker-checker 미성립.
- **Target:**
  1. 감사로그 두 라우트에 요청자 store 스코프 강제. **fail-open 제거** — 역할 판정 실패는 `403` 이지 전체 공개가 아니다.
     superadmin 은 기존 방식(`?storeId=` 파라미터)으로 명시 지정.
  2. `adminUpdateUser`/`remove` 진입 시 대상 유저의 `storeId` 를 요청자 스코프와 대조, 불일치 403.
  3. `dto.storeId` 반영을 **superadmin 전용**으로 제한. 일반 admin 의 매장 이동 시도는 400.
  4. `approve()` 에 `approverId !== requestedBy` 검사 추가(+ `approver_role_slug` 대조).
  5. **회귀 테스트로 고정** — 타 매장 리소스 접근 시 403 을 확인하는 spec 을 남긴다.
     Phase 64 W7 이 판매 경로에 한 것과 같은 수준.
- **Acceptance:** 타 매장 감사로그·사용자에 대한 조회/수정/삭제가 403. 역할 없는 사용자가 전체 로그를 받지 못함.
  자기 요청 자가승인 차단. 기존 정상 흐름(자기 매장 내) 회귀 0.

### R7. 자격증명 위생 (결함 8) — Wave 7

- **Current:** `PGPASSWORD` 가 평문으로 들어 있고 git 추적 상태인 마이그레이션 파일 **10개**.
  `env.config.ts:15-16` 에 DB password / jwtSecretKey 하드코딩 폴백.
  `common/crypto/email-secret.ts:24` 는 `JWT_SECRET_KEY` 미설정 시 **고정 문자열로 실제 암복호가 동작**한다.
- **Target:**
  1. 10개 파일에서 자격증명 제거(적용 명령은 환경변수 참조 형태로 재작성).
  2. **해당 DB 계정 비밀번호 회전.** 접속 주체(앱·pgbouncer·백업 크론·Jenkins·운영자)를 사전 목록화하고 순서를 정한 뒤 실행.
     *되돌리기 어려움 — 별도 승인.*
  3. 시크릿 폴백 리터럴 제거 — 미설정 시 **부팅 실패**로 전환. 조용히 약한 기본값으로 동작하지 않게 한다.
  4. git 이력에 남은 값은 회전으로 무력화한다(이력 재작성은 범위 밖).
- **Acceptance:** 저장소 내 평문 자격증명 0건(스캔 게이트). 시크릿 미설정 시 부팅이 실패.
  회전 후 모든 접속 주체 정상 동작 확인.

### R8. 장애 감지 최소셋 (결함 9) — Wave 8

- **Current:** 헬스체크 라우트 0건, 컨테이너 healthcheck 없음, 외부 uptime 감시 없음,
  `enableShutdownHooks()` 호출 0건. 유일한 알람인 Telegram 500 알림은 **프로세스가 죽으면 함께 멈춘다**.
  2026-07-25 재부팅 후 2시간 다운을 놓친 이력 존재.
- **Target:**
  1. **`GET /health`** — 인증 없이(또는 최소 보호로) DB·Redis 연결을 확인하는 경량 엔드포인트.
     pool 을 소모하지 않도록 주의(가벼운 쿼리 1회 + 짧은 캐시).
  2. **컨테이너 healthcheck** — `docker-compose.yml` API 서비스에 추가. 실패 시 재시작이 동작하도록.
  3. **외부 uptime 감시** — 외부에서 `/health` 를 주기 확인하고 실패 시 Telegram 알림.
     *"알림을 보내는 주체가 죽으면 알림도 죽는다" 문제를 외부에서 끊는다.*
  4. **`app.enableShutdownHooks()`** 추가 + SIGTERM 시 in-flight 드레이닝.
     `database.module.ts:266` 의 pool 정리가 실제로 트리거되게 한다.
  5. 알람 임계 최소 2종 추가 — pool waiting > 0 지속, outbox `processing` lease 초과.
     (Centro de Control 의 `infraestructura` 위젯 확장으로 처리 — 신규 인프라 도입 없음.)
- **Acceptance:** 프로세스/DB 다운 → **60초 내** 알림 수신(실제로 중단시켜 확인).
  SIGTERM 시 진행 중 요청이 정상 완료되고 pool 이 정리됨(로그로 확인). `/health` 가 pool 을 잠식하지 않음.

### R9. Phase 64 마감 + 문서 동기화 (부수) — Wave 9

- **Current:** Phase 64 W10 미완. 브라우저 UAT 12건 전부 미실행.
  `.planning/ROADMAP.md`(0/10 표기)·`STATE.md`(2026-07-24 정지)·`intel/`(2026-06-25)·
  `DATABASE_SCHEMA.md`(Stocks 3컬럼)·`CLAUDE.md`(pool min=10/max=80) 이 모두 코드와 어긋나 있다.
- **Target:**
  1. Phase 64 브라우저 UAT 실행 및 결과 기록(멱등키 재시도, 취소, 보류, 생산 완료, generic 상품 판매, 식당 모드 주문).
  2. `.planning/intel/` 재생성(`db-schema.regen.sh`).
  3. ROADMAP·STATE 를 실제 상태로 동기화. Phase 63·64·65 반영.
  4. `DATABASE_SCHEMA.md` 의 Stocks 정의와 테이블 목록 갱신.
  5. `CLAUDE.md` pool 기술을 실제 값(min=2, max=20 × 4워커)으로 교정.
  6. 만료 멱등키 정리(`purgeExpired`) 를 기존 cron 태스크에 연결(Phase 64 W10 잔여, 신규 스케줄러 금지).
- **Acceptance:** 계획 문서와 코드 상태 일치. UAT 결과가 `65-VALIDATION.md` 에 기록됨.

---

## Wave 구성과 의존

```
W1(유형 표준화) → W2(원장 불변) → W3(캐시 봉합) → W4(가용재고 정의) → W5(대조·보정)
                                                                   ↑ 재고 계열은 선형
W6(경계) · W7(자격증명) · W8(감지)  ← 병렬 가능, 재고 계열과 독립
W9(마감·문서)  ← 마지막
```

- **재고 계열(W1~W5)은 선형이다.** W5 의 대조는 W1~W4 가 끝나야 의미 있는 값을 낸다.
  유형이 표준화되지 않으면 대조 쿼리가 다시 오탐하고, 캐시 갱신이 봉합되지 않으면 보정해도 다시 벌어진다.
- **W6·W7·W8 은 재고와 독립**이므로 병렬 진행 가능. 다만 W7(자격증명 회전)은 배포 중단 위험이 있어
  다른 Wave 의 배포와 겹치지 않는 창에서 단독 실행한다.
- **W9 는 마지막.** 앞의 결과를 문서에 반영해야 하므로.

## 완료 게이트 (Phase 65 전체)

| 지표 | 목표 |
|---|---|
| 원장-캐시 불일치 상품 수 | 백필 후 **0**, 이후 야간 크론에서 지속 0 (예약 제외 기준) |
| `stocks` destroy/update | 전 저장소 **0건** + DB 트리거로 강제 |
| 모델 union 밖 이동유형 | 코드 **0건**, DB **0행** |
| 재고 계산 SQL | 단일 출처 경유. 4개 경로가 동일 값 반환 |
| 크로스테넌트 접근 | 감사로그·사용자 경로에서 **403**, 회귀 테스트로 고정 |
| 저장소 내 평문 자격증명 | **0건** + 계정 회전 완료 |
| 장애 감지 시간 | 프로세스/DB 다운 → **60초 내** 알림 |
| 무회귀 | Phase 64 동시성 스위트 8종 통과 유지 · 부하 25건/s 재측정에서 저장 실패 0 · 코크핏 재고 수치 설명 가능 |

## 배포 후 관측 (2주)

| 지표 | 조회 | 기대 |
|---|---|---|
| 재고 드리프트 | 야간 크론 로그 / `GET /api/diagnostics/stock-drift` | 지속 0 |
| 이동유형 | `SELECT type, count(*) FROM stocks GROUP BY type` | union 값만 |
| 원장 파괴 시도 | 트리거 위반 로그 | 0건 (발생 시 누락된 호출부 존재) |
| 크로스테넌트 403 | API 로그 | 정상 업무에서 0, 시도 시 기록됨 |
| 헬스체크 | 외부 uptime 이력 | 가용성 측정 시작 (SLO 수립의 첫 데이터) |
| pool | 기동 로그 / 60초 모니터 | waiting 0 유지 |

## Open Questions (실행 전 확인 필요)

1. **자동 보정 정책** — R5 의 야간 크론이 드리프트를 발견했을 때 자동 보정할 것인가, 탐지만 할 것인가?
   *제안: 초기 최소 2주는 탐지만. 원인 분포를 본 뒤 자동 보정 여부를 결정.*
2. **`'produccion'` vs `'production'`** — 코드베이스가 스페인어·영어를 혼용한다.
   `type` 값의 표기 언어를 어느 쪽으로 통일할지 결정 필요. *제안: 영어(모델 union 이 이미 영어).*
3. **가용재고 정의 변경의 화면 영향** — R4 로 값이 달라지는 화면이 있다면 사용자에게 사전 고지가 필요한가?
4. **자격증명 회전 창** — 운영 중단 없이 가능한 시간대와 접속 주체 전체 목록.
5. **외부 uptime 감시 위치** — 서버 외부여야 의미가 있다. 어디에 둘 것인가(무료 서비스 / 별도 호스트 / 사장 개인 서버)?
