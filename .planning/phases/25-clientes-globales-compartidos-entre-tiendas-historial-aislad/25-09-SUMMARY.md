---
phase: 25-clientes-globales-compartidos-entre-tiendas-historial-aislad
plan: 09
subsystem: validators
tags: [validator, dni, cuit, mod11, afip, tdd]

requires: []
provides:
  - api-ventago/src/app/client-import/validators/cuit.validator.ts (isValidCuit + normalizeCuit)
  - api-ventago/src/app/client-import/validators/dni.validator.ts (isValidDni + normalizeDni)
affects:
  - Plan 25-07 promote service (CUIT/DNI 검증에 사용)
  - Plan 25-10+ ClientImportService (CSV/Excel 행 검증)

key-files:
  created:
    - api-ventago/src/app/client-import/validators/cuit.validator.ts
    - api-ventago/src/app/client-import/validators/dni.validator.ts
    - api-ventago/src/app/client-import/validators/cuit.validator.spec.ts
    - api-ventago/src/app/client-import/validators/dni.validator.spec.ts

key-decisions:
  - "Pitfall 5 적용: calc==10 인 CUIT 명시적 거부 (AFIP 발행 안 함)"
  - "normalize 함수 분리: 비숫자 strip 로직을 재사용 가능하게 export"
  - "정규식 strict: ^\\d{7,8}$ DNI / ^\\d{11}$ CUIT — 길이 검증 후 mod11"
  - "Plan 25-07 의 인라인 validator 가 동일 알고리즘이므로 향후 import 로 교체 가능 (subsequent refactor commit)"

requirements-completed:
  - REQ-25-14
  - D1-02

duration: 10min
completed: 2026-04-26
---

# Phase 25 Plan 09: CUIT + DNI Server-side Validators

CUIT (mod 11 + AFIP Pitfall 5) + DNI (7-8 digits regex) validator 모듈 신규 작성. Plan 25-07/10+ 가 import 해서 사용.

## Files Created

| 파일 | 내용 |
|---|---|
| `cuit.validator.ts` | `CUIT_WEIGHTS = [5,4,3,2,7,6,5,4,3,2]`, `isValidCuit`, `normalizeCuit` |
| `dni.validator.ts` | `^\\d{7,8}$` 정규식, `isValidDni`, `normalizeDni` |
| `cuit.validator.spec.ts` | 12+ 시나리오: valid (개인/법인), invalid 체크 디지트, calc==10 거부, 길이 edge, null 안전 |
| `dni.validator.spec.ts` | 7+ 시나리오: 7/8 자리 valid, 6/9 자리 invalid, dotted/spaced AR 형식, null 안전 |

## Verified

- ✅ `tsc --noEmit` 에러 0건
- ✅ ESLint (validators 단독) 에러 0건
- ⏳ Jest 단위 테스트는 호스트에서 `npm test -- --testPathPattern=cuit.validator.spec` / `dni.validator.spec` 실행 권장

## Pitfall 5 검증 케이스

테스트 입력: `'20000000012'`
- digits: 2,0,0,0,0,0,0,0,0,1
- weighted sum: 2*5 + 1*2 = 12
- rem: 12 % 11 = 1
- calc: 11 - 1 = 10 → **invalid (AFIP 발행 안 함)**

## Next Phase Readiness

- **Plan 25-07 promote**: validators import 후 사용 ✅
- **Plan 25-10+ client-import**: CSV/Excel 행마다 호출 ✅

## Self-Check: PASSED

- [x] cuit.validator.ts 존재, isValidCuit + normalizeCuit export
- [x] dni.validator.ts 존재, isValidDni + normalizeDni export
- [x] CUIT_WEIGHTS = [5,4,3,2,7,6,5,4,3,2] 명시
- [x] calc === 10 → return false 분기 존재
- [x] DNI 정규식 ^\d{7,8}$ 사용
- [x] tsc 에러 0건

---
*Completed: 2026-04-26*
