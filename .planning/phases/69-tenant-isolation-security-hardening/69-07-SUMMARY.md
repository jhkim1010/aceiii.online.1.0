---
phase: 69-tenant-isolation-security-hardening
plan: 07
subsystem: api
tags: [nestjs, sequelize, multi-tenant, derived-scope, enforce]

# Dependency graph
requires:
  - phase: 69-06
    provides: "파생 스코프 규칙 40개 확장 + 다중 부모(through) 지원 — 승격 대상이 되는 규칙 집합"
  - phase: 68
    provides: "파생 스코프 엔진(injectDerived / buildDerivedInclude) 과 observe 모드"
provides:
  - "TENANT_DERIVED_MODE 기본값 enforce — 명시 observe/off 만 하향"
  - ".env.example 에 테넌트 격리 env 2종 문서화 (기존 미기재)"
  - "파생 규칙 46건 association 전수 검증 결과 + enforce 가동 실측 증거"
affects: [69-09, 69-10]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "보안 기본값은 안전한 쪽으로 두고, 완화만 명시 env 로 — 설정 유실이 방어막을 끄면 안 된다"
    - "컨테이너 로그는 재생성 시 소실 → 소급 로그 수집이 불가능한 증거는 정적 전수 검증으로 대체"

key-files:
  created:
    - .planning/phases/69-tenant-isolation-security-hardening/69-OBSERVE-HITS.md
    - api-ventago/check-derived-assoc.js
  modified:
    - api-ventago/src/common/tenant/tenant-scope.registry.ts
    - api-ventago/.env.example
    - .planning/phases/69-tenant-isolation-security-hardening/deferred-items.md
---

# 69-07 — 파생 스코프 기본값 enforce 승격 (R4)

## 문제

Phase 68 파생 스코프는 기본값이 `observe`(로그만)라 **방어막이 아니었다.** 69-06 이 규칙을 40개로 넓히고
다중 부모를 지원하게 만들었지만, 기본값이 그대로면 새 환경(로컬·신규 배포)은 여전히 무방비다.

## 계획 대비 실제 — 승격이 측정보다 먼저 일어나 있었다

플랜은 "observe 로그 1영업일 수집 → 호출부 정리 → 승인 → 승격" 순서를 전제했다.
확인해 보니 **운영 `.env` 에 `TENANT_DERIVED_MODE=enforce` 가 이미 들어가 있었다**(2026-08-01 21:55 UTC, 컨테이너 22:46 재생성).
즉 승격은 이미 운영에서 실행 중이었고, 남은 것은 코드 기본값을 현실에 맞추는 일이었다.

observe 구간 로그는 **회수 불가**다 — 로그는 컨테이너 내부에만 남고 재생성 시 소실되며, 호스트 로그 디렉터리는 2026-04-15 이후 비활성이다.
사용자 결정: **enforce 유지 + 코드 기본값도 승격.**

## 무엇을 했나

**1) 기본값 반전** — `resolveDerivedMode()` 의 `?? 'observe'` → `?? 'enforce'`, 분기도 뒤집어 명시 `observe`/`off` 만 하향한다.
**2) env 문서화** — `.env.example` 에 `TENANT_GUARD_MODE` / `TENANT_DERIVED_MODE` 를 의미·기본값과 함께 추가(둘 다 기존에 미기재였다).
**3) 증거 문서** — `69-OBSERVE-HITS.md`. 로그 수집 불가 사유와 대체 증거를 명시.
**4) 미결 6개 defer** — 사용자 결정에 따라 `deferred-items.md` 에 표로 기록(엔진 보강 필요 사유 포함).

## 검증

| 검증 | 결과 |
|---|---|
| `npx jest src/common/tenant` | 13 passed (observe/enforce/off 명시 지정 스펙이라 기본값 변경 무영향) |
| `npx nest build` | exit 0 |
| `node dist/main.js` (env 없음) | `derivedMode=enforce 대상=39` — 기본값만으로 enforce 가동 확인 |
| `check-derived-assoc.js` 전수 | 46개 규칙 중 45개 association 해석 성공 |
| 운영 부팅 로그 | `mode=enforce 보호모델=114 ... derivedMode=enforce 대상=39` |
| 운영 error | 0건 (`error-2026-08-01.log` 0바이트) |

정적 검증의 유일한 미해석 `BranchPrinterConfig` 는 어느 모듈에도 등록되지 않은 사문 모델이라 훅 자체가 설치되지 않는다.
레지스트리 40 − 사문 1 = 부팅 로그 `대상=39` 로 정적 검증과 런타임이 교차 확인된다.

## 남은 것

- **소킹이 짧다.** enforce 회귀는 에러가 아니라 **빈 목록**으로 나타나므로 로그만으로 안 잡힌다 → 69-10 UAT 에서 화면·API 순회로 보완.
- **미결 6개**(`QrPrintLog`/`UserRole`/`RoleFunctionAction`/`PaymentMethodsOption`/`SubconSettlement`/`SubconPayment`)는
  여전히 파생 스코프 미등록 = 사각지대. 별도 phase.
- 운영 경고 1건 `격리 누수 감지: Branch ... store=undefined` — enforce 와 독립적인 관측 로그, 재현 빈도 관찰 중.

## 계획 대비 차이

- 플랜 산출물 중 `69-OBSERVE-HITS.md` 는 "히트 전수 목록" 이 아니라 **"수집 불가 사유 + 정적 전수 검증"** 으로 채웠다. 로그가 실재하지 않는데 목록을 지어낼 수는 없다.
- 승인 게이트는 플랜대로 지켰다 — 다만 대상이 "승격할까?" 가 아니라 "이미 켜진 승격을 유지할까?" 였다.

## Commits

- `b1147b5` (api-ventago) — feat(security): 파생 스코프 기본값 enforce 승격 (69-07/R4)
