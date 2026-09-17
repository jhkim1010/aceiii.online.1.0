---
phase: 89-qr-public-product-page
verified: 2026-09-17T13:11:01Z
status: human_needed
score: 13/13 automatable must-haves verified
overrides_applied: 0
requirements_traceability_note: >
  REQUIREMENTS.md 에 REQ-01~REQ-08 항목이 존재하지 않는다(실측 확인, grep 0건).
  Phase 89 산문 섹션(공개 상품 페이지 · 라벨 QR 도착지 복구 · reseller 신청 경로 ·
  리드 수집 · 다중 테넌트 노출 통제) 기준으로 판정했다. 이것은 추적표 등록 누락이며
  구현 결함이 아니다 — 별도 권고로 아래에 기록.
human_verification:
  - test: "매장에 붙어 있는 실물 라벨을 폰 카메라로 찍어 계정 없이 페이지가 열리는지 확인"
    expected: "308→200 리다이렉트로 페이지가 열리고 로그인 화면으로 튕기지 않는다"
    why_human: "실물 인쇄물·카메라 스캔은 코드로 증명할 수 없다. 자동화로는 URL이 비로그인 200으로 열리는 것까지만 확인 가능(89-UAT.md 기록됨)"
  - test: "Configuración에서 qr_precio_publico 토글을 켠 뒤 같은 라벨을 다시 찍어 매장·지점·사진·가격이 라벨과 일치하는지(다르면 병기, 같으면 병기 없음) 확인"
    expected: "가격이 그 가격유형의 현재 가격으로 보이고, printed_price와 다를 때만 「라벨 표기 $X — 가격이 변경됐습니다」가 병기된다. 같으면 아무 문구도 없다"
    why_human: "화면을 눈으로 보고 병기 문구의 유무를 판단하는 것은 사람만 가능. 운영 store 6 설정이 현재 꺼짐(false) 상태라 토글부터 켜야 한다"
  - test: "상세 화면 하단 두 CTA(reseller 신청, /register?ref= 가입)를 끝까지 눌러 각각 실제 화면·제출 완료에 도달하는지, 이탈 받이(연락처만 남기기)도 제출되는지 확인"
    expected: "reseller 신청 제출 후 reseller.resellers에 행 생성, /register?ref=cool 프리필 확인, 이탈 받이 제출 후 ventago_leads에 행 생성 — 막다른 CTA 없음"
    why_human: "실제 제출 완료와 후속 화면 도달은 사람이 끝까지 눌러야 확인된다. 자동화로는 정적 도착지 대조(check-cta-destinos.sh, 통과 확인됨)와 400 검증 응답까지만 확인 가능"
---

# Phase 89: 상품 QR → 공개 상품 페이지 + 두 갈래 CTA Verification Report

**Phase Goal:** 매장에 온 아무나(계정 없이, 앱 없이) 라벨의 QR 을 찍으면 어느 매장 · 어느 지점 · 무슨 상품인지
사진과 가격으로 보이는 페이지가 열린다. 그 페이지 끝에서 두 갈래로 보낸다 — ① reseller 신청, ② Ventago 잠재고객 수집.

**Verified:** 2026-09-17T13:11:01Z
**Status:** human_needed
**Re-verification:** No — initial verification

---

## Deployment Context (오케스트레이터 사전 확인, 2026-09-17 실측 — 본 검증이 재확인하지 않고 인용)

- `https://app.coolsistema.com/m/stock?s=6&p=1` → 200 (배포 전 404)
- `https://newapi.coolsistema.com/api/public/qr-stock/6/1` → 200, `mode:"shop_redirect"` (store 6 = qr_precio_publico=false + slug='cool')
- `POST /api/public/ventago-leads {}` → 400 (검증 동작)
- Jenkins `api-new-coolsistema` #905 SUCCESS · `front-coolsistema` #741 SUCCESS, 컨테이너 재생성 확인
- 운영 로그 `does not exist` 0건
- 운영 13개 매장 전부 `qr_precio_publico=false`(기본 꺼짐, 의도된 배포 안전값)

이 검증(verifier)은 위 실측을 재실행하지 않고, 코드 · 로컬/운영 DB 스키마 · 테스트 실행 · 정적 대조 스크립트로
**독립적으로** 위 주장을 뒷받침하는 근거를 확보했다(아래).

---

## Goal Achievement

### Observable Truths (12개 plan must_haves 를 병합·대표화)

| # | Truth | Status | Evidence |
|---|---|---|---|
| 1 | 로컬(5432)·운영(5434) 양쪽에 `store_configs.qr_precio_publico`(NOT NULL DEFAULT false), `ventago_leads`(owner=coolsistema), `uq_prices_product_price_type`(NULLS NOT DISTINCT) 가 적용돼 있다 | ✓ VERIFIED | `psql -p 5432`/`ssh jhkim-server psql -p 5434` 직접 조회로 3건 전부 확인. 운영 `ventago_leads` tableowner=coolsistema, 인덱스 정의 `NULLS NOT DISTINCT` 확인 |
| 2 | 이미지 파일명 모지바케(114건 중 60건, 실행 시점 재조사 35건) 원인이 근거와 함께 하나로(ⓑ 업로드시 깨진 이름) 좁혀졌고, 이 plan 은 쓰기를 하지 않았다 | ✓ VERIFIED | `89-DIAGNOSIS-imagenes.md`: raw_hit 35/35, fix_hit 0, missing 0 — 판정 ⓑ. `diagnose-image-names.js` grep 결과 `statObject`만 호출, UPDATE/INSERT/putObject 없음 |
| 3 | 매장 admin 이 Configuración에서 QR 가격 토글을 찾아 켤 수 있고, 문구가 「가격 숨김」이 아니라 「상세 딥링크 허용」으로 읽힌다 | ✓ VERIFIED | `storeConfig.model.ts:222` field 매핑, `storeConfig.controller.ts:122` FLAG_FIELDS 등록, `StoreConfigContext.tsx` 배선, `pages/configuracion/index.tsx:64` HUB_TABS 등록(`key:'qr'`), `QrConfigView.tsx` 문구 "Si está apagado... el QR lleva al catálogo" — 가격 숨김이 아닌 딥링크 통제로 읽힘 |
| 4 | `GET /public/qr-stock/:storeId/:productId` 가 인증 없이 응답하고, 다른 매장 상품은 404(존재 노출 없음), 가격/재고/원가/SKU 노출 규칙을 지킨다 | ✓ VERIFIED | `qr-public.controller.ts` `@Public()`, `qr-public.service.ts` SQL 조건(`p.store_id=$2`), `qr-public.dto.ts` 필드 계약. `qr-public.service.spec.ts` 23개 테스트 전부 통과(대조군 T6·T8·T14·T22 포함, `env -u NODE_OPTIONS npx jest` 직접 실행 exit 0) |
| 5 | 가격 주 표시는 그 가격유형의 현재 가격이고, `printed_price`와 다를 때만 `precioEtiqueta`가 채워진다(같으면 null) | ✓ VERIFIED | `qr-public.service.ts` `mismoMonto()` 비교 후 `precioEtiqueta = 같으면 null : 다르면 printed_price`. spec T17·T18·T19(센타보 경계) 통과 |
| 6 | 신/구 라벨 구분(`labelMatch`: exact-label/latest-print/none)이 응답에 실린다 | ✓ VERIFIED | spec T11·T12·T13 통과. `QrProductView.tsx`가 `labelMatch==='latest-print'`일 때 "Según la última impresión..." 문구 렌더 |
| 7 | 새 인쇄 QR에 `&b=`·`&pt=`가 실리고, 없는 기존 라벨도 그대로 동작한다 | ✓ VERIFIED | `print.service.ts:214-218` `buildQrUrl` 옵션 파라미터, 두 조립 지점(`buildQrPayload`·delta 조회) 모두 branchId/priceTypeId 전달. `print.service.qr.spec.ts` 통과 |
| 8 | 계정 없이 `/m/stock/?s=&p=`가 열리고(authGuard=false), 매장·지점·사진·가격이 보이며 사진 없음/닫힘/목록전환 4상태가 빈 화면이 아니다 | ✓ VERIFIED | `pages/m/stock/index.tsx` `authGuard=false`, raw fetch(apiConnector 미사용). `QrProductView.tsx` 370줄 — closed/shop_redirect/detail(사진있음·Sin foto)/loading/invalid/notfound/error 전 분기 렌더 확인. 운영 curl 200 (오케스트레이터 사전 확인) |
| 9 | CTA① reseller 신청이 QR 매장 하나로 고정되고(매장 선택 UI 없음), 무인증 업로드가 크기(5MB)·개수(3)·MIME 으로 제한되며 실패 시 MinIO 고아 파일이 안 남는다 | ✓ VERIFIED | `ResellerApplyForm.tsx` storeId prop 고정, 매장 선택 UI 없음. `reseller-auth.controller.ts` `limits:{fileSize,files:3}`+`fileFilter` MIME 화이트리스트. `reseller-auth.service.ts` register() 업로드+해싱+트랜잭션을 하나의 try/catch로 묶어 실패 시 `Promise.allSettled` 로 업로드분 전체 삭제(89-09 P1 수정 확인). `reseller-auth.service.spec.ts` cleanup 케이스 통과 |
| 10 | CTA② 주 도착지는 `/register?ref={apodo}`이고 blur 검증을 그대로 거치며, 해석 안 되면 빈 값(폴백 없음), 기존 가입 흐름은 안 바뀐다 | ✓ VERIFIED | `RegisterForm.tsx:206-217` `useRouter`+`router.query.ref` 1회 `useEffect`, `setValue`+`checkReferralApodo()` 직접 호출(blur 재사용), `ref` 없으면 `return`(빈값 유지). `?ref=` 없는 기존 흐름 코드 미변경 |
| 11 | 이탈 받이 `POST /public/ventago-leads`가 무인증 저장하고, 텔레그램 실패해도 201이며, 알림 결과가 `notify_status`에 남는다. `sourceProductId`가 프론트에서도 전송된다 | ✓ VERIFIED | `leads.service.ts` DB 저장 후 `sendTelegramMessageDetailed().then().catch()`로 응답 분리, `notifyStatus` 업데이트. `VentagoLeadForm.tsx`가 `sourceProductId: productId` 전송. `leads-public.controller.spec.ts` 통과 |
| 12 | 두 CTA + 이탈 받이 + 관리자 승인 화면, 총 5개 도착지 존재가 검사로 못박혀 있고 대조군이 실제로 실패한다 | ✓ VERIFIED | `scripts/check-cta-destinos.sh` 직접 실행 — [1]~[5] 전부 짝 확인, 대조군(`public/no-existe-jamas`) 0건, exit 0 |
| 13 | 테넌트 격리가 실DB에서 확인되고(mock 아님), 각 방어에 대조군이 있으며, 마이그레이션 배포 게이트가 통과한다 | ✓ VERIFIED | `verificar-qr-public-tenant.sh` 로컬 실DB 직접 실행: 판1(상품 테넌트, 방어=0행/대조군=1행 이상), 판2(교차 테넌트 0건), 판3(closed 342개 매장) — exit 0. `verificar-esquema-phase89.sh` 8개 항목 전부 [OK], exit 0 |

**Score:** 13/13 자동 검증 가능한 must-haves 전부 VERIFIED. 나머지는 성격상 실물 스캔·눈으로 보는 판단이 필요해 human_verification 으로 분리(아래).

### Phase 성공 판정 3건 (89-CONTEXT.md 기준) — 자동화 한계

`89-UAT.md`가 이미 이 구분을 명시적으로 기록했다:

| # | 성공 판정 | 자동 확인 결과 | 남은 것 |
|---|---|---|---|
| 1 | 실물 라벨 스캔, 계정 없이 열림 | `curl -L` → 200(리다이렉트 뒤) 확인됨. authGuard=false 코드 확인됨 | 실제 폰 카메라 스캔은 사람만 가능 |
| 2 | 매장·지점·사진·가격 표시, 라벨과 일치(다르면 병기) | 서비스 로직·23개 단위 테스트·필드 계약 확인됨. 운영 store 6 설정이 현재 꺼짐(qr_precio_publico=false) | 토글을 켜고 화면을 눈으로 봐야 병기 문구 유무 판정 가능 |
| 3 | 두 CTA 끝까지 눌러 도달 | 정적 도착지 대조 통과(check-cta-destinos.sh), 백엔드 화이트리스트/방어 코드 확인됨 | 실제 제출 완료·DB 행 생성은 사람이 끝까지 눌러야 확인 |

### Required Artifacts (대표)

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `api-ventago/migrations/2026-09-16-phase89-*.sql` (3건) | 스키마 변경 | ✓ VERIFIED | 로컬 5432 + 운영 5434 양쪽 적용 확인 |
| `api-ventago/src/app/print/qr-public.{controller,service,dto}.ts` | 공개 QR API | ✓ VERIFIED | print.module.ts 컨트롤러 등록 확인, 23 tests pass |
| `api-ventago/src/app/leads/*` | 리드 수집 | ✓ VERIFIED | app.module.ts LeadsModule 등록 확인 |
| `api-ventago/src/app/reseller/auth/*` | reseller 신청 방어 3종 | ✓ VERIFIED | 화이트리스트·업로드제한·고아삭제 전부 코드 확인 |
| `ventago-app/src/pages/m/stock/index.tsx` + `views/m-stock/*` | 공개 페이지 6상태 | ✓ VERIFIED | authGuard=false, raw fetch, 6상태 렌더 |
| `ventago-app/src/views/register/components/RegisterForm.tsx` | ?ref= 프리필 | ✓ VERIFIED | useRouter + blur 재사용 |
| `scripts/check-cta-destinos.sh` | 막다른 CTA 방지 | ✓ VERIFIED | 직접 실행 exit 0, 대조군 포함 |
| `api-ventago/scripts/verificar-qr-public-tenant.sh` / `verificar-esquema-phase89.sh` | 실DB 검사·배포 게이트 | ✓ VERIFIED | 직접 실행 exit 0 양쪽 |

### Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| `qr-public.service.ts` | `qr_print_log` | 3키(product·branch·price_type) store_id 강제 조인 | ✓ WIRED | SQL 직접 확인, 실DB 대조군 스크립트로 재확인 |
| `qr-public.service.ts` | `store_configs.qr_precio_publico` | `COALESCE(c.qr_precio_publico, false)` | ✓ WIRED | 코드 확인 |
| `print.module.ts` | `QrPublicController` | controllers 배열 | ✓ WIRED | grep 확인 |
| `app.module.ts` | `LeadsModule` | imports 배열 | ✓ WIRED | grep 확인 |
| `QrConfigView.tsx` | `PUT /store-config/{id}/update-flag` | apiConnector.put | ✓ WIRED | 코드 확인 |
| `pages/configuracion/index.tsx` | `QrConfigView` | HUB_TABS `key:'qr'` | ✓ WIRED | grep 확인 |
| `ResellerApplyForm.tsx` | `POST /reseller/auth/register` | raw fetch + FormData | ✓ WIRED | 코드 + check-cta-destinos.sh |
| `VentagoLeadForm.tsx` | `POST /public/ventago-leads` | raw fetch + JSON, sourceProductId 포함 | ✓ WIRED | 코드 + check-cta-destinos.sh |
| `QrProductView.tsx` | `/register?ref={apodo}` | registerHref 조립(storeApodo null이면 ref 생략) | ✓ WIRED | 코드 확인 |
| `print.service.ts` `buildQrUrl` | QR 인쇄 URL | 2개 조립 지점 모두 `&b=`·`&pt=` | ✓ WIRED | grep 2곳 확인, 회귀 테스트 통과 |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|---|---|---|---|---|
| `QrProductView.tsx` | `data`(QrPublicDto) | `pages/m/stock/index.tsx` fetch → `GET /public/qr-stock/:s/:p` | 서버가 `products`/`prices`/`qr_print_log`/`stores`/`branches` 실 쿼리 결과 반환(하드코딩 아님) | ✓ FLOWING |
| `QrConfigView.tsx` | `qrPrecioPublico` | `StoreConfigContext` → `GET /store-config` | 실 DB 컬럼 값 | ✓ FLOWING |

### Requirements Coverage

| Requirement (ROADMAP 산문) | Status | Evidence |
|---|---|---|
| 공개 상품 페이지 | ✓ SATISFIED | `/m/stock` 6상태, 공개 API |
| 라벨 QR 도착지 복구 | ✓ SATISFIED | 운영 404→200 (오케스트레이터 실측), authGuard=false |
| reseller 신청 경로 | ✓ SATISFIED (실사용은 human 확인 대기) | 백엔드 방어 3종 + 프론트 폼 + 도착지 대조 통과 |
| 리드 수집 | ✓ SATISFIED (실사용은 human 확인 대기) | `ventago_leads` 저장 + notify_status |
| 다중 테넌트 노출 통제 | ✓ SATISFIED | 실DB 테넌트 격리 검사 exit 0, 응답 필드 계약(재고/원가/SKU 없음) 테스트 통과 |

**★ 권고 (블로커 아님):** `.planning/REQUIREMENTS.md`에 Phase 89 항목(REQ-01~08 또는 대응 ID)이
등록돼 있지 않다(실측 grep 0건). `requirements mark-complete`가 `not_found`로 끝난 것은
이 추적표 등록 누락 때문이며, 코드 미구현이 아니다. 다음 세션에서 REQUIREMENTS.md에
Phase 89 항목을 소급 등록할 것을 권고한다.

### Anti-Patterns Found

없음. 26개 수정 파일에 대해 TODO/FIXME/PLACEHOLDER/coming soon/not yet implemented 패턴 grep 0건.

### Test/Build Verification (직접 실행, 종료코드 기준)

```
$ env -u NODE_OPTIONS npx tsc --noEmit          (api-ventago)   → exit 0
$ env -u NODE_OPTIONS npx jest src/app/print src/app/leads src/app/reseller \
    src/app/store/config src/app/products/prices-unique.spec.ts \
    src/common/migrations --maxWorkers=1        (api-ventago)   → 23 suites / 181 tests passed, exit 0
$ env -u NODE_OPTIONS npx tsc --noEmit          (ventago-app)   → exit 0
$ env -u NODE_OPTIONS npx eslint <9개 변경 파일> (ventago-app)   → exit 0, 0 warnings
$ bash scripts/check-cta-destinos.sh                            → exit 0 (정적 대조, 대조군 포함)
$ PGTARGET=local bash api-ventago/scripts/verificar-qr-public-tenant.sh   → exit 0
$ PGTARGET=local bash api-ventago/scripts/verificar-esquema-phase89.sh   → 8/8 [OK], exit 0
```

### Known Accepted Risks (deferred-items.md 에 이미 기록됨 — 새 gap 아님)

이 검증에서 별도로 재확인했고, 코드가 문서 기술과 일치함을 확인했다. 사용자가 2026-09-17
"배포를 막지 않는다"고 이미 판단했으므로 아래는 gaps 가 아니라 참고 기록이다:

1. `leads.service.ts`의 텔레그램 통지가 fire-and-forget 이라 `notify_status='pending'`이
   프로세스 재시작과 겹치면 영구 정지할 수 있음 (코드 재확인: `void sendTelegramMessageDetailed(...).then().catch()` 구조 그대로).
2. `ventago_leads.store_id`가 `ON DELETE CASCADE` — 매장 삭제 시 중앙 리드 데이터 소실 위험
   (마이그레이션 재확인: `REFERENCES stores (id) ON DELETE CASCADE`).
3. `check-cta-destinos.sh`의 HTTP 게이트(옵션, `API=`/`APP=` 지정 시)가 404만 실패로 본다 —
   이번 검증은 정적 대조만 돌렸고(서버 미기동), 이 한계는 스크립트 주석에 그대로 남아 있음.
4. 이미지 모지바케 35건 — 진단만 완료, 수정은 범위 밖(89-02).
5. `referral_credits` 운영 0행 — 추천 가입이 승인까지 간 적이 없어 "추천하면 보상"을
   화면에 단정하지 않는 것으로 확인(`QrProductView.tsx` CTA② 문구에 보상 단정 없음).
6. CODEX 자동 훅이 phase 89 커밋 40건을 건너뛴 원인 미상 — 수동 codex 검토로 대체됨(기록 확인).

### Human Verification Required

VERIFICATION.md frontmatter의 `human_verification` 참조. 요약:

1. **실물 라벨 스캔** — 계정 없이 열리는지 폰 카메라로 직접 확인
2. **가격 병기 문구의 유무 판단** — 토글을 켠 뒤 화면을 눈으로 보고 라벨과 일치/불일치 병기가 올바른지
3. **두 CTA 끝까지 제출 완료** — reseller 신청·가입 프리필·이탈 받이 제출까지 실제로 눌러 DB 행 생성 확인

`89-UAT.md`에 이 세 항목을 위한 상세 순서(A~E, 21단계)가 이미 작성돼 있다 — 그대로 따라하면 된다.

### Gaps Summary

새로 발견된 gap 없음. 자동으로 검증 가능한 13개 must-have 전부 VERIFIED. 남은 3개 성공 판정은
성격상(실물 인쇄물 스캔, 화면 육안 판단, 끝까지 제출) 사람만 확인할 수 있고, 이는 89-UAT.md가
이미 정확히 같은 결론으로 기록해 두었다 — 이 검증이 독립적으로 코드·테스트·실DB 조회로
재확인한 결과도 같은 결론에 도달했다.

---

_Verified: 2026-09-17T13:11:01Z_
_Verifier: Claude (gsd-verifier)_
