# 65-W6 — 감사·사용자 매장 경계 (R6) 잔존 여부 검증 키트

작성: 2026-08-05
목적: Phase 65 W6 의 4개 항목이 **Phase 67/68/69 를 거치며 이미 닫혔는지, 아직 열려 있는지**를 코드로 확정한다.
성격: **읽기 전용 감사.** 이 문서 단계에서는 코드를 고치지 않는다. 결과에 따라 잔존분만 별도 phase 로 분할한다.

> **왜 재확인이 필요한가**
> W6 는 진단서(2026-07-29) 기준으로 작성됐다. 그 뒤 Phase 67(직접 `store_id` 하드 블록) · 68(파생 스코프) ·
> 69(`TENANT_DERIVED_MODE=enforce` 승격 + fail-closed)가 들어갔다. `AuditLog`/`User` 가 훅 대상이면
> **컨트롤러 코드가 그대로여도 ORM 계층에서 이미 막혀 있을 수** 있다. 반대로 훅은 *어떤 매장 것을 주느냐*를
> 좁힐 뿐, "역할 판정 실패 시 전체 반환" 같은 **컨트롤러의 fail-open 분기 자체**는 못 없앤다.
> 그래서 **두 계층을 각각** 확인한다.

---

## 0. 선행 — 저장소 확보

이 검증은 `api-ventago` 소스가 있어야 한다. 현재 작업 폴더에는 gitlink 만 있고 내용이 없다(0 파일).

```bash
cd /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
git clone https://github.com/jhkim1010/api-ventago.git api-ventago
git -C api-ventago checkout 0625429      # 루트가 가리키는 커밋 (= 운영 배포분)
```

`ventago-app` 도 필요하면 동일하게 (`461ff5e`). 두 저장소 모두 **private** 이라 GitHub 자격증명이 필요하다.

---

## 1. 검증 항목과 판정 기준

각 항목은 **CLOSED**(이미 닫힘) / **OPEN**(잔존) / **PARTIAL**(한 계층만) 중 하나로 판정한다.

### 6-1 · `GET /auditlog/entity/:type/:id` — 대상 엔티티 store 스코프 검증

- 진단 근거: `audit-log.controller.ts:37-42` — `@GetUser()` 없이 `entityType`+`entityId` 로만 조회
- **OPEN 조건:** 핸들러 시그니처에 요청자(`@GetUser`/`@Req`)가 없고, 서비스도 `storeId` 를 안 받는다
- **CLOSED 조건:** 요청자 store 로 대상 엔티티 소유를 대조하거나, `AuditLog` 가 훅 enforce 대상이라 ORM 이 타 매장 행을 반환하지 못한다

```bash
cd api-ventago
sed -n '1,80p' src/app/audit-log/audit-log.controller.ts
grep -rn "getLogsByEntity\|entityType" src/app/audit-log/audit-log.service.ts | head -20
```

### 6-2 · `GET /audit-log/store` — fail-open 제거 (**가장 위험**)

- 진단 근거: `audit-log.controller.ts:50-53` — 역할 배열이 비면 `getAllLogs(page, size, {})` 로 **전 매장 반환**
- 이건 "덜 준다"가 아니라 **판정 실패 시 더 준다** — 권한 없는 사용자가 오히려 전체를 받는다
- **OPEN 조건:** 역할 배열이 비었을 때의 분기가 예외(403)가 아니라 필터 없는 조회로 떨어진다
- **CLOSED 조건:** 빈 역할 → `ForbiddenException`

```bash
sed -n '40,75p' src/app/audit-log/audit-log.controller.ts
grep -rn "getAllLogs" src/app/audit-log/ | head
```

### 6-3 · `adminUpdateUser` / `remove` — 대상 유저 매장 대조

- 진단 근거: `users.service.ts:299` `findByPk(id)` 에 storeId 대조 없음 / `:322` `dto.storeId` 로 **타 매장 이동 가능**
- **OPEN 조건:** 대상 조회가 `findByPk(id)` 단독이고, `dto.storeId` 를 superadmin 여부와 무관하게 반영
- **CLOSED 조건:** 요청자 스코프와 불일치 시 403, `dto.storeId` 반영은 superadmin 전용
- ★ `User` 는 `store_id` 를 가진 직접 모델 → **Phase 67 훅 대상일 가능성이 높다.** 훅이 `findByPk` 까지 막는지
  (`beforeFind` 주입 범위) 반드시 확인할 것. 훅이 잡으면 CLOSED, 훅이 primary-key 조회를 예외 처리하면 OPEN.

```bash
grep -n "adminUpdateUser" -A 40 src/app/users/users.service.ts | head -60
grep -rn "User\b" src/common/tenant/tenant-scope.registry.ts | head
grep -rn "findByPk\|beforeFind" src/common/tenant/tenant-hooks.ts | head -20
```

### 6-4 · `approve()` 자가 승인 차단

- 진단 근거: `approval.service.ts:168-203` — `approverId !== requestedBy` 검사 없음 → maker-checker 미성립
- **OPEN 조건:** 승인자와 요청자 동일성 검사가 없다
- **CLOSED 조건:** 동일하면 거부(+ `approver_role_slug` 대조)
- 테넌트 훅으로는 절대 못 닫히는 항목 — **훅과 무관하게 코드로만 판정**

```bash
grep -n "approve" -A 45 src/app/**/approval.service.ts | head -70
```

### 6-5 · 회귀 spec 존재 여부

Phase 69 가 `npm run test:tenant` 20종을 남겼다. 그중 **감사로그·사용자 관리·자가승인** 케이스가 포함되는지 확인한다.
없으면 6-1~6-4 가 코드로 닫혀 있어도 **고정되지 않은 상태**(회귀 가능)로 본다.

```bash
grep -rn "auditlog\|audit-log\|adminUpdateUser\|approve" test/tenant/ src/**/*tenant*.spec.ts 2>/dev/null | head -20
cat package.json | grep -n "test:tenant"
```

---

## 2. 결과 (검증 완료 2026-08-05, 대상 `api-ventago@0625429` = 운영 배포분)

### ★ 선결론 — W6 는 이미 구현·배포돼 있었다. 문서에만 기록이 없었다.

`c23ab35` **2026-07-29** — `fix(security): Phase 65 W6 — 감사로그 store 스코프 강제(fail-open 제거)·사용자
수정/삭제 매장 경계·storeId 이동 superadmin 전용·승인 자가승인 차단` (5 파일 +138/−16).
`git merge-base --is-ancestor c23ab35 0625429` → **YES**, 운영 배포분에 포함.

즉 진단서(2026-07-29) 대응이 **같은 날 코드로 들어갔는데** ROADMAP·STATE 는 Phase 65 를 "plan 미분할·실행
미착수" 로 유지했다. 계획 문서만 보고 "W6 미착수 = 취약" 으로 판단하면 틀린다.

### 항목별 판정

| # | 항목 | 컨트롤러/서비스 계층 | 테넌트 훅 계층 | 판정 | 근거 |
|---|---|---|---|---|---|
| 6-1 | auditlog entity 스코프 | `resolveStoreScope()` 로 요청자 store 강제, 서비스가 `where.storeId` 적용 | Phase 67 훅 대상(`AuditLog.storeId` 보유) | **CLOSED** | `audit-log.controller.ts:73-88`, `audit-log.service.ts:214-221` |
| 6-2 | audit-log/store fail-open | 빈 역할 → 전체 반환 분기 제거. `scope == null` 은 **superadmin + storeId 미지정** 일 때만 성립 | 상동 | **CLOSED** | `audit-log.controller.ts:93-101`, `:27-46` |
| 6-3 | adminUpdateUser / remove | update: 컨트롤러가 `actor` 전달 → 타 매장 403, `dto.storeId` 변경은 superadmin 전용(400). remove: 컨트롤러에서 `user.storeId ≠ actor.storeId` 403 | `Users` 도 storeId 보유 모델 | **CLOSED** | `users.service.ts:302-334`, `users.controller.ts:138-143`, `users.controller.ts:182-192` |
| 6-4 | 자가승인 차단 | `requestedBy === approverId` → `ForbiddenException`. **단 `approver_role_slug` 대조는 없음** | (해당 없음) | **PARTIAL** | `approval.service.ts:190-196` / 미이행: `approval-threshold.model.ts:65` |
| 6-5 | 회귀 spec 고정 | `test:tenant` 스위트에 **W6 케이스 0건** — Phase 69 R1~R7 만 커버 | (해당 없음) | **OPEN** | `test/tenant/cross-tenant.tenant-spec.ts` (describe R1~R7), grep 결과 audit/users/approve 0 hit |

**판정 요약: CLOSED 3 · PARTIAL 1 · OPEN 1**

### 잔존분 상세

**6-4 잔여 — 승인 임계값의 역할 게이트가 집행되지 않는다**

`approval_thresholds.approver_role_slug` 는 모델에 있고(`approval-threshold.model.ts:65`) 매장 생성 시
`branch_manager` / `store_admin` / `store_owner` 로 시드된다(`storeTemplate.service.ts:785-833`).
그런데 **읽는 곳이 없다** — `approve()` 는 자가승인만 막고, 컨트롤러는 `@Permission('approval.approve','update')`
하나로 끝난다(`approval.controller.ts:116-128`). 결과적으로 `approval.approve` 권한만 있으면
`store_owner` 승인이 필요한 요청도 `branch_manager` 가 승인할 수 있다. maker-checker 는 성립하나
**승인 등급(SoD)은 미성립**.

**6-5 잔여 — 회귀가 고정돼 있지 않다**

6-1~6-4 가 코드로 닫혀 있어도 스위트가 없으니 리팩터 한 번에 조용히 풀릴 수 있다. 실제로 6-2 의 fail-open 은
`if` 분기 하나를 되돌리면 재발한다. Phase 69 가 R1~R7 을 20종으로 고정해둔 것과 대비된다.

---

## 3. 후속 (확정)

W6 를 통째로 새 phase 로 만들 이유는 없다. 남은 것은 **6-4 역할 게이트 1건 + 6-5 회귀 spec 1건**이고,
둘 다 작다. 이걸 **W7(자격증명 위생)** 과 묶는 것이 맞다 — W7 은 미착수가 확실하고(평문 비밀번호 저장소
19곳+ 잔존, 비밀번호 회전 미실행) 실제 노출 규모도 W6 잔존분보다 크다.

권장 구성 — 보안 마감 phase:
1. `approver_role_slug` 집행 + 승인 등급 회귀 spec (6-4)
2. W6 회귀 spec 을 `test:tenant` 에 편입 — 감사로그 2라우트 · 사용자 수정/삭제 · 자가승인 (6-5)
3. W7-1/2/4 저장소 평문 자격증명 제거 + 부팅 시 시크릿 미설정 실패 + 스캔 게이트
4. W7-3 **DB 계정 비밀번호 회전** — 파괴적, 단독 배포 창 + 사용자 승인 + 주체 목록(앱·pgbouncer·백업 크론
   03:17·Jenkins·운영자 `.pgpass`·`venpsql`) 선행

문서 정리도 같이 해야 한다: ROADMAP·STATE 의 Phase 65 서술이 `c23ab35` 를 반영하지 않아
**이미 배포된 보안 교정을 미착수로 표시**하고 있다.
