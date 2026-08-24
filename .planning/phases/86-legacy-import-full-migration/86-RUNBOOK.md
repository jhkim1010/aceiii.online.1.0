---
phase: 86-legacy-import-full-migration
type: runbook
created: 2026-08-20
branch: feature/phase86-legacy-import-full
autonomous: true
gate: tools/phase86/gate.sh
---

# Phase 86 — 자율 실행 RUNBOOK (cmux)

이 문서는 **에이전트가 사람 개입 없이 Phase 86 을 끝까지 완성하기 위한 실행 규약**이다.
설계는 `86-SPEC.md`, 검토 판단은 `.team/reviews/phase86-spec-resolution.md` 를 따른다.

---

## 1. 루프

```
while true:
    tools/phase86/gate.sh          # 판정
    exit 0 → 다음 wave 로 / 전부 끝났으면 §6 종료 절차
    exit 1 → 출력에서 실패 게이트와 원인을 읽는다
             → 원인이 되는 파일을 고친다
             → 같은 게이트만 다시 돌린다 (gate.sh wN)
             → 통과하면 gate.sh 전체를 다시 돌린다 (회귀 확인)
```

**핵심 규칙: 판정은 게이트가 한다.** "된 것 같다" 로 다음 단계에 가지 않는다.
게이트가 없는 작업은 완료로 표시할 수 없다 — 게이트를 먼저 만든다.

---

## 2. Wave 정의

각 wave 의 `게이트` 가 통과해야 다음으로 간다. `must_haves` 는 게이트가 검사하는 **의미**다.

### w1 — 마이그레이션 ✅ 완료 (2026-08-20)

| | |
|---|---|
| 대상 | `api-ventago/migrations/2026-08-20-phase86-*.sql` (M1~M7) |
| 게이트 | `tools/phase86/gate.sh w1` |
| 상태 | **통과** — 7개 적용 + 동작 12건 + 멱등 확인 |

`must_haves`
- M5 적용 후 `sales.source='legacy'` 가 들어가고 미지의 값은 23514 로 막힌다
- `legacy_entity_maps` 가 `DONE` + `ventago_id IS NULL` 조합을 거부한다
- 리스는 살아있으면 재획득이 막히고, **만료되면 자동으로 풀린다**(워커 사망 복구)
- 전체 재실행이 무해하다

### w2 — PGDMP 스트리밍 리더 (TASK-2b) ★ 다른 모든 wave 의 전제

| | |
|---|---|
| 대상 | `api-ventago/src/app/legacy-import/dump-converter.service.ts`, `tools/phase86/` |
| 참조 | `tools/phase86/ace-dump-reader.py` — 이미 동작하는 Python 레퍼런스 구현 |
| 게이트 | `tools/phase86/verify-dump-reader.js` (이 wave 에서 함께 만든다) |

`must_haves`
- plain / gzip / custom(`PGDMP`) / tar **4경로 전부** 동작. 부분 이식 금지 — tar 경로가 죽는다
- `codigos_tmp` 블록을 **디코드하지 않는다** (kandente4 기준 244MB / 3,105,051행)
- 전체 파일을 문자열로 올리지 않는다 — 테이블 블록 단위 스트리밍
- 피크 RSS 가 **512MB 미만** (운영 서버는 swap 0, free 1.6GB, 같은 박스에 운영 Postgres)
- `Dockerfile` 에서 `postgresql-client` 제거 후에도 4경로가 전부 동작

> 이 wave 가 끝나기 전에는 업로드 상한을 **25MB 로 동결**한다. 200MB 는 리더와 한 몸이다.

### w3 — 매퍼 · 잡 러너

| | |
|---|---|
| 대상 | `ace-mapping.ts`, `legacy-import.service.ts`, `legacy-import.controller.ts`, `sql-parser.service.ts` |
| 게이트 | `tools/phase86/verify-w3.js` |

`must_haves`
- 엔티티 선택(§4)대로만 처리한다. 의존 항목이 빠지면 **시작 전에 거부**한다
- 동시 실행은 리스로 막는다 — **advisory lock 금지**(pgbouncer transaction pooling)
- 트랜잭션은 INSERT 배치만 감싼다. **파싱·변환은 트랜잭션 밖**
- 한 트랜잭션이 60초를 넘지 않는다(`idle_in_transaction_session_timeout`)
- 워커 커넥션은 동시 1개
- `PENDING` → `DONE` 2단계로 쓰고, 재개 시 `PENDING` 을 정리한다
- `sales` 헤더와 `sale_items` 는 **한 트랜잭션**
- `GET /legacy-import/jobs/:id` 가 `job.storeId !== user.storeId` 면 **403**
- 임시 비밀번호가 로그·에러·소켓 페이로드에 나타나지 않는다

### w4 — E2E 임포트 + 정합성

| | |
|---|---|
| 대상 | 더미 매장 `kandente4-test` + `kandente4_20260812_160643.backup` |
| 게이트 | `tools/phase86/verify-w4.js` — SPEC §6 V1~V16 |

`must_haves` (특히 놓치기 쉬운 것)
- **V3**: `vcodes.borrado=true` 건이 전부 `'Anulado'` 이고 매출 집계에서 빠진다
- **V6**: `stock_balances.total_ingreso` 가 기준선 합계와 일치한다 (drift 로는 못 잡는다)
- **V12**: legacy 판매를 취소해도 **재고가 늘지 않는다**
- **V11**: 잡을 중간에 죽인 뒤 재개한 결과가 무중단과 같다
- **V10**: 같은 파일 재임포트 시 신규 생성 0건

### w5 — Stock & Reports 회귀 (Phase 종료 조건)

| | |
|---|---|
| 대상 | `tools/phase86-report-smoke.ts` (또는 `tools/phase86/verify-w5.js`) |
| 게이트 | SPEC §6.2 R1~R17 |

`must_haves`
- 각 항목마다 ① HTTP 200 ② 비어 있지 않음 ③ 합계가 원장·ACE 원본과 일치 ④ export xlsx 가 열린다
- **R12**: legacy 데이터가 없는 fallados/movidos/reservado/corregido 가 **빈 상태에서 500 이 아니다**
- **R11**: cheque-estado 가 0행에서 정상 빈 응답

### w6 — 품질

`must_haves`: 변경 파일 ESLint 0, `tsc --noEmit` 통과, api/app 빌드 통과.

---

## 3. 불변 제약 (매 반복에서 지킨다)

`86-SPEC.md §8` 이 원본이다. 자율 루프에서 특히 어기기 쉬운 것:

| 제약 | 어기면 |
|---|---|
| `stocks` UPDATE/DELETE 금지 | `trg_stocks_immutable` 이 막는다 |
| `stocks` 는 **리프** product_branch 에만 | madre 로 가면 **트랜잭션 전체 abort** |
| `stocks.product_id` 컬럼 없음 — `product_branch_id` 만 | 컬럼 없음 에러 |
| 새 `stocks.type` 값 도입 금지 | drift 는 안 깨지고 `total_*` 만 **조용히** 틀어진다 |
| `sales.status`/`source` 는 enum 상수만 | `status` 에 CHECK 가 없어 오타가 조용히 저장되고 취소분이 매출로 잡힌다 |
| advisory lock 금지 | pgbouncer transaction pooling 에서 락이 떠돈다 |
| 트랜잭션 안 외부 I/O 금지 | pool 고갈 |
| `products.stock` 참조 금지 | Phase 70-06 에서 강등됨 |

---

## 4. 실패 대응 규칙

1. **같은 게이트가 같은 이유로 2회 연속 실패하면 접근을 바꾼다.** 같은 수정을 3번 시도하지 않는다.
2. 원인이 저장소 밖(라이브러리·런타임)일 때는 검증된 최신 방법을 웹에서 찾아 적용한다.
3. **게이트를 느슨하게 만들어 통과시키지 않는다.** 게이트 수정은 그 자체로 사람 승인 대상이다(§5).
4. 실패가 SPEC 의 설계 결함에서 왔다면 코드가 아니라 **SPEC 을 고치고 그 사실을 기록**한다
   (`.team/reviews/phase86-spec-resolution.md` 에 추가).
5. 진행 상황은 `cmux log` / `cmux set-progress` 로 남긴다.

---

## 5. ★ 반드시 멈추고 사람 승인을 받는 경우

자율 루프는 아래를 **절대 스스로 하지 않는다.**

- 운영 DB(srv803182:5434)에 대한 **모든 쓰기** — DDL·DML 무관. 조회는 허용
- **마이그레이션의 운영 적용** — 로컬 검증이 끝나도 승인 없이는 안 한다
- `git push` — 이 세션은 GitHub 접근이 막혀 있고, push 는 Jenkins 배포를 촉발한다
- 서비스 재시작(`docker restart`, `systemctl`), 파괴적 명령(`rm`, `kill`)
- **게이트 기준 자체의 완화**
- 마이그레이션 파일의 **사후 수정** — 이미 적용된 파일은 고치지 않고 새 파일로 추가한다
- 임시 비밀번호·시크릿을 파일이나 로그로 출력하는 변경

멈출 때는 **무엇을 왜 하려 했는지 + 영향 범위(예상 row 수 포함)** 를 함께 보고한다.

---

## 6. 종료 절차

`gate.sh` 가 ALL GREEN 이면:

1. `.team/reviews/` 에 결과 요약
2. `scripts/codex-review.sh --task 86` 실행 → 지적별 판단을 `.team/reviews/86-resolution.md`
   (codex 미설치/미인증이면 **검토 미실시임을 명시**하고 멈춰 사람에게 확인받는다. 조용히 건너뛰지 않는다)
3. 변경 파일만 선별 스테이징 → commit
4. **push 와 운영 마이그레이션 적용은 사람 승인 후** (§5)
5. Phase 86 완료 정의(`86-SPEC.md §10`) 6개 항목 대조

---

## 7. 환경 메모

| | |
|---|---|
| 검증 DB | 샌드박스 PG18 — `tools/phase86/pgup.sh`, 소켓 `/tmp/pg86`, 포트 `55432`, user `postgres` |
| PG 바이너리 | `npm i @embedded-postgres/linux-arm64@18.4.0-beta.17` (arm64는 `--force` 필요) |
| ★ 주의 | bash 호출마다 프로세스가 죽는다 — **모든 호출 앞에 `tools/phase86/pgup.sh`** |
| 백업 파일 | `aceiii_2.0_backups/kandente4_20260812_160643.backup` (56MB). 나머지 11개 매장은 Dropbox 온라인 전용(0바이트) |
| 덤프 리더 | `tools/phase86/ace-dump-reader.py` — `ddl` / `count` / `head` 모드 |
| pg_restore | **없다.** 설치 불가(root 없음, apt 차단). 리더로 대체한다 |
| 네트워크 | npm 만 열림. GitHub·OpenAI·apt 차단 |
