---
phase: 89-qr-public-product-page
plan: 05
subsystem: api
tags: [nestjs, sequelize, public-endpoint, telegram, tenant-isolation, leads]

# Dependency graph
requires:
  - phase: 89-01
    provides: "ventago_leads 신규 테이블 (로컬 5432 + 운영 5434 적용 완료)"
  - phase: 89-04
    provides: "PUBLIC_LEAD_THROTTLE 상수 (throttle.constants.ts)"
provides:
  - "POST /public/ventago-leads — 인증 없는 CTA② 이탈 받이 리드 수집 엔드포인트"
  - "Lead 모델(ventago_leads) — 모든 @Column 에 명시적 type"
  - "LeadsService.create() — sourceProductId 소유 재검증 + 텔레그램 통지 결과 기록 패턴"
affects: [89-08, 89-09]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "@Public() 라우트에서 클라이언트 제출 storeId 를 SQL 로 재검증(실재·활성) — 확정 사실로 승격하지 않고 그 이상을 주장하지 않는다"
    - "커밋 뒤 fire-and-forget 통지 결과를 .then()/.catch() 로 별도 update 하여 침묵 실패를 없앤다(sendTelegramMessageDetailed 직접 사용, notifyTelegram 래퍼 미사용)"

key-files:
  created:
    - api-ventago/src/app/leads/lead.model.ts
    - api-ventago/src/app/leads/dto/create-lead.dto.ts
    - api-ventago/src/app/leads/leads.service.ts
    - api-ventago/src/app/leads/leads-public.controller.ts
    - api-ventago/src/app/leads/leads.module.ts
    - api-ventago/src/app/leads/leads-public.controller.spec.ts
  modified:
    - api-ventago/src/app.module.ts

key-decisions:
  - "sourceProductId 와 storeId 가 어긋나면 storeId 를 상품 쪽으로 고치지 않고 productId 를 버린다(덜 주장하는 쪽을 택함) — plan 지시 그대로"
  - "Test 10(D-2, @Column type 강제)은 Lead.rawAttributes 가 addModels() 이전이라 비어 있어 스킵 사유를 spec 안에 남기고, 실제 강제는 verify-models.js(빌드 산출물 로딩, 199개 모델 확인)로 충족"

patterns-established:
  - "리드/공개폼류 서비스: 저장 먼저 커밋 → 통지는 await 없이 .then()/.catch() 로 결과만 기록, 응답 코드는 절대 안 바꾼다"

requirements-completed: [REQ-05]

# Metrics
duration: 45min
completed: 2026-09-17
---

# Phase 89 Plan 05: CTA② 이탈 받이 — Ventago 리드 수집 API Summary

**`POST /public/ventago-leads` 신설 — 인증 없이 리드를 저장하고, `sourceProductId` 소유를 재검증하며, 텔레그램 통지 결과(sent/failed/unconfigured)를 `notify_status`/`notified_at` 에 남겨 실패가 흔적 없이 사라지지 않게 한다**

## Performance

- **Duration:** 약 45분
- **Started:** 2026-09-17
- **Completed:** 2026-09-17
- **Tasks:** 3/3 완료
- **Files modified:** 7 (신규 6 · 수정 1)

## Accomplishments
- `ventago_leads` 를 가리키는 `Lead` 모델 — 컬럼 9개 전부 명시적 `type`(운영 부팅 사망 전례 재발 방지)
- `LeadsService.create()` — 매장 실재·활성 확인(400 으로 응답, FK 500 방지) → `sourceProductId` 가 `dto.storeId` 소유가 아니면 조용히 `null` 로 버림(귀속을 부풀리지 않음) → 저장 → `sendTelegramMessageDetailed()` 결과를 `notify_status`/`notified_at` 에 기록
- 통지는 `await` 하지 않아 응답 코드를 절대 바꾸지 않지만, 결과를 버리는 `notifyTelegram()` 래퍼 대신 결과를 직접 받아 기록 — 「감시 장치가 부재에서 침묵한다」 반복 결함을 이 자리에서 막음
- `POST /public/ventago-leads` — `@Public() + @Throttle(PUBLIC_LEAD_THROTTLE)`(분당 5), 빈 body 에 404 가 아니라 400
- 시험 9건 통과 + 대조군 2건 수동 실증(통지 호출 제거 → Test1/7/8 적색, 결과기록 then/catch 제거 → Test2/7/8 적색이자 unhandled rejection 발생으로 더 강하게 확인)
- `nest build && node scripts/verify-models.js` — 199개 모델(신규 Lead 포함) 로딩 확인, D-2(@Column type 누락) 강제 통과

## Task Commits

각 Task 는 서브모듈(api-ventago) 커밋 → 슈퍼프로젝트 gitlink 포인터 커밋 순으로 원자적으로 커밋됨:

1. **Task 1: 모델 + DTO + 서비스(store_id 재검증 + 텔레그램)** - `79731201` (api-ventago, feat) + `dd44fad` (root, chore: submodule pointer)
2. **Task 2: 공개 컨트롤러 + 모듈 + app.module 등록** - `0c711b6e` (api-ventago, feat) + `87182a9` (root, chore: submodule pointer)
3. **Task 3: 리드 저장·알림·출처검증 시험(대조군 포함)** - `5a10ed82` (api-ventago, test) + `962ccea` (root, chore: submodule pointer)

**Plan metadata:** (이 커밋 — SUMMARY + STATE.md + ROADMAP.md)

## Files Created/Modified
- `api-ventago/src/app/leads/lead.model.ts` - `ventago_leads` 매핑 모델. 9개 컬럼 전부 명시적 `type`. `notifyStatus`/`notifiedAt` 포함
- `api-ventago/src/app/leads/dto/create-lead.dto.ts` - `CreateLeadDto` — `storeId` 필수, `sourceProductId`/`contactEmail`/`message` 옵셔널(null 통과 가능성을 서비스에서 재정규화)
- `api-ventago/src/app/leads/leads.service.ts` - `LeadsService.create()` — 매장 확인 → 출처 재검증 → 저장 → 통지 결과 기록(HTML 이스케이프 헬퍼 포함)
- `api-ventago/src/app/leads/leads-public.controller.ts` - `POST public/ventago-leads` — `@Public()+@Throttle(PUBLIC_LEAD_THROTTLE)`
- `api-ventago/src/app/leads/leads.module.ts` - `LeadsModule` — `SequelizeModule.forFeature([Lead])` + 컨트롤러/서비스 등록
- `api-ventago/src/app.module.ts` - `LeadsModule` import + `imports` 배열 등록(`PrintModule` 인근)
- `api-ventago/src/app/leads/leads-public.controller.spec.ts` - 시험 9건(Test 1-8, 10) + 라우트 메타데이터 시험

## Decisions Made
- **sourceProductId 불일치 시 storeId 를 고쳐주지 않음**: 클라이언트가 보낸 두 값(storeId·sourceProductId) 중 어느 쪽이 참인지 서버가 알 수 없으므로, 어긋나면 상품 귀속(`productId`)만 버리고 `storeId` 는 그대로 저장한다 — plan 이 지시한 「덜 주장하는 쪽을 택한다」 원칙을 그대로 따름.
- **Test 10 은 `Lead.rawAttributes` 검사 대신 스킵 사유를 spec 안에 남김**: unit spec 에서는 `sequelize.addModels()` 를 하지 않으므로 `rawAttributes` 가 비어 있다(plan 이 미리 예견한 상황). 대신 `nest build && node scripts/verify-models.js` 를 직접 돌려 199개 모델(Lead 포함) 로딩을 확인해 D-2 를 실질적으로 충족했다.

## Deviations from Plan

None — plan 이 지시한 코드·구조·acceptance 기준 그대로 구현되고 전부 통과했다. lint 자동수정(prettier 포맷)만 2회 있었으나 로직 변경은 없다.

## Issues Encountered
- **로컬 curl 종단 시험에서 500** — 이미 떠 있던 로컬 dev API(`npm run dev:api`, PID 기존 실행분)가 `.env` 상 로컬 5432 `ventago` 가 아니라 SSH 터널 경유 `ventago_staging`(스테이징, 운영 복사본 아님)에 연결돼 있어 `ventago_leads` 테이블이 없어 500 이 났다. **이 phase 코드의 결함이 아니다** — 89-01 이 실제로 적용한 곳은 로컬 5432 `ventago` 이고(`psql -p 5432 -d ventago` 로 직접 확인, 1건 존재), 그 DB 를 가리키는 서버라면 정상 동작한다. `curl ... -d '{}'` → 400(빈 body 검증 실패, 404 아님) 은 정상 확인됨 — plan 의 `<verification>` 이 요구한 항목은 통과했다. 스테이징 DB 스키마 지연은 기존에 알려진 환경 특성(`MEMORY: staging-restore-lags-production-schema`)이라 이 plan 의 범위 밖.

## User Setup Required
None - 외부 서비스 설정 불필요. `TELEGRAM_BOT_TOKEN`/`TELEGRAM_CHAT_ID` 미설정 시 `notify_status='unconfigured'` 로 조용히 기록되고 저장은 그대로 성공한다.

## ★ 이 phase 가 닫지 않은 것 (plan 이 명시한 한계 — 해결했다고 쓰지 않음)

- **리드 조회 화면이 없다.** 받는 곳은 텔레그램 채널 하나뿐이고, 그것이 실패하면 다음 진단 쿼리로 DB 를 직접 봐야 안다:
  ```sql
  SELECT id, created_at, notify_status, contact_name FROM ventago_leads
   WHERE notify_status <> 'sent' ORDER BY id DESC;
  ```
  ROADMAP W5 가 경고한 「받는 곳이 없으면 수집은 사라진다」의 절반만 닫힌 상태다 — 후속 후보.
- **`store_id` 귀속의 신뢰 수준이 낮다.** QR 조회(GET)와 리드 제출(POST)은 독립 요청이고 서명된 컨텍스트를 전달하는 수단이 없다. 서버가 확인한 것은 「매장 실재·활성」과 「상품이 그 매장 것인가」뿐 — 그 이상을 주장하지 않는다. 서명된 컨텍스트 도입은 범위 밖(후속 후보).

## Next Phase Readiness
- 89-08(프론트 CTA② 화면)이 이 API 를 작은 보조 링크로 배선하면 된다. **배포 순서**: 이 API 를 프론트 폼(89-08)보다 먼저 배포 — 반대면 버튼이 404 를 받는다.
- 89-09(UAT)가 리드 조회 화면 부재 사실과 진단 쿼리를 알아야 한다.
- 블로커 없음.

---
*Phase: 89-qr-public-product-page*
*Completed: 2026-09-17*

## Self-Check: PASSED

- FOUND: api-ventago/src/app/leads/lead.model.ts
- FOUND: api-ventago/src/app/leads/dto/create-lead.dto.ts
- FOUND: api-ventago/src/app/leads/leads.service.ts
- FOUND: api-ventago/src/app/leads/leads-public.controller.ts
- FOUND: api-ventago/src/app/leads/leads.module.ts
- FOUND: api-ventago/src/app/leads/leads-public.controller.spec.ts
- FOUND: .planning/phases/89-qr-public-product-page/89-05-SUMMARY.md
- FOUND commit 79731201 (api-ventago submodule)
- FOUND commit 0c711b6e (api-ventago submodule)
- FOUND commit 5a10ed82 (api-ventago submodule)
- FOUND commit dd44fad (root)
- FOUND commit 87182a9 (root)
- FOUND commit 962ccea (root)
