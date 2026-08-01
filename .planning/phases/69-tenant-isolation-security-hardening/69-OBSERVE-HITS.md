# 69-07 — 파생 스코프 observe 히트 수집 & enforce 승격 증거

**작성:** 2026-08-01
**대상:** `TENANT_DERIVED_MODE` (`api-ventago/src/common/tenant/tenant-scope.registry.ts`)
**결론:** 운영 enforce 가동 중 · 코드 기본값도 `observe` → `enforce` 승격 완료

---

## 1. 승격 시점의 실제 상태 (측정 결과)

플랜 69-07 은 "observe 로그를 최소 1영업일 모아 호출부를 특정한 뒤 승격" 을 전제했다.
실제로는 **승격이 로그 수집보다 먼저 운영에 적용돼 있었다.** 사실을 그대로 기록한다.

| 항목 | 실측값 | 확인 방법 |
|---|---|---|
| 운영 `.env` | `TENANT_DERIVED_MODE=enforce` | `grep TENANT /var/lib/jenkins/workspace/api-new-coolsistema/.env` (62행) |
| `.env` 수정 시각 | 2026-08-01 21:55:33 UTC | `stat -c '%y'` |
| 컨테이너 재생성 | 2026-08-01 22:45~22:46 UTC | `docker ps` (Up 5 minutes), 부팅 로그 22:46:02 |
| 컨테이너 주입 확인 | `TENANT_DERIVED_MODE=enforce` | `docker inspect api_ventago --format '{{range .Config.Env}}...'` |
| 부팅 로그 | `[TenantGuard] 격리 훅 설치 완료 — mode=enforce 보호모델=114 (글로벌행 허용 8) 제외=30 \| 파생스코프 derivedMode=enforce 대상=39` | `docker exec api_ventago grep TenantGuard logs/combined-2026-08-01.log` |
| enforce 가동 후 error | **0건** (`[error]` 0, `error-2026-08-01.log` 0바이트) | 동일 로그 |
| 격리 누수 경고 | **1건** — `Branch 조회 결과에 store=undefined 행 포함 (허용=[6]) — include/raw 경로 점검 필요` | 동일 로그 |

## 2. observe 히트 전수 — 수집 불가 사유와 대체 증거

**수집 불가:** 운영 로그는 컨테이너 내부 `logs/combined-*.log` 에만 남고 **컨테이너 재생성 시 소실**된다
(호스트 `/var/lib/jenkins/workspace/api-new-coolsistema/logs` 는 2026-04-15 이후 비활성). 69-06 배포(파생 규칙 40개 확장)
이후 enforce 전환까지의 observe 구간 로그는 이미 유실됐고, 현재는 enforce 라 observe 라인이 원천적으로 나오지 않는다.

**대체 증거 — 정적 전수 검증.** observe 로그의 목적은 "enforce 시 INNER JOIN 이 끼워질 호출부가 실제로 성립하는가" 확인이다.
같은 질문을 association 레벨에서 전수로 답했다(`api-ventago/check-derived-assoc.js`, 69-06 산출):

```
$ DERIVED_NAMES="<DERIVED_SCOPE 키 40개>" node check-derived-assoc.js
RESULT 검사=46개 규칙 / 모델=41
BAD:
BranchPrinterConfig: 모델 없음
```

- **46개 파생 규칙 중 45개**가 실제 Sequelize association(2단계 `through` 포함)으로 해석됨 → enforce 시 JOIN 주입이 성립한다.
- 유일한 미해석 `BranchPrinterConfig` 는 **어느 모듈에서도 `SequelizeModule.forFeature` 에 등록되지 않은 사문 모델**이다
  (`src/app/print/branch-printer-config.model.ts` 를 import 하는 코드 0건 — 프린터 인증은 `BranchAgent` 로 대체됨).
  등록되지 않으므로 훅도 설치되지 않고, 규칙은 **no-op**이다.
- 이 1건이 **레지스트리 40개 vs 부팅 로그 `대상=39`** 의 차이와 정확히 일치한다 → 부팅 로그가 정적 검증을 교차 확인해 준다.

## 3. 단위 검증

```
$ npx jest src/common/tenant
PASS src/common/tenant/tenant-hooks.spec.ts
PASS src/common/tenant/tenant-derived.spec.ts
Tests: 13 passed, 13 total
```

`tenant-derived.spec.ts` 는 observe/enforce/off 세 모드를 각각 명시 지정해 검증하므로 기본값 변경의 영향을 받지 않는다.

## 4. 승격 내용

- `resolveDerivedMode()` 기본값 `'observe'` → `'enforce'` (분기도 반전: 명시 `observe`/`off` 만 하향)
- `.env.example` 에 `TENANT_GUARD_MODE` / `TENANT_DERIVED_MODE` 문서화 (기존 미기재)
- **탈출구 유지:** 회귀 발생 시 재배포 없이 운영 `.env` 에 `TENANT_DERIVED_MODE=observe` → `docker compose up -d --force-recreate`

## 5. 잔여 리스크 (감시 대상)

1. **소킹 부족.** enforce 실가동 관측 창이 짧다(재생성 22:46 기준). 69-10 UAT 에서 화면·API 순회로 보완하고,
   이후 며칠간 `grep '격리 누수\|derived'` 로 확인한다. enforce 회귀는 **에러가 아니라 빈 목록**으로 나타나므로 로그만으로는 안 잡힌다.
2. **`격리 누수 감지: Branch ... store=undefined`** 1건 — `include`/`raw` 경로에서 store 판별 불가 행이 섞였다는 경고.
   차단이 아니라 관측 로그이며 enforce 승격과 독립적이다. 재현 빈도를 계속 관찰한다.
3. **미결 모델 6개** (`QrPrintLog`, `UserRole`, `RoleFunctionAction`, `PaymentMethodsOption`, `SubconSettlement`, `SubconPayment`)
   는 엔진 보강(`allowGlobalRows` / `anyOf`)이 필요해 Phase 69 범위 밖으로 defer — `deferred-items.md` 참조.
   이 6개는 파생 스코프 미등록 상태라 enforce 여부와 무관하게 **현재 격리 사각지대로 남는다.**
