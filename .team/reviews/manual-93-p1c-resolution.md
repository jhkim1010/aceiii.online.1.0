# 판단 기록 — Phase 93 P1-c 저장 계약 (2026-09-23)

검토 보고서: `.team/reviews/manual-93-p1c-codex.md`
대상: `api-ventago/src/app/role/role-function/*`, `ventago-app/.../RolePermissionsDrawer.tsx`

| # | 심각도 | 지적 | 판단 |
|---|---|---|---|
| 1 | **HIGH** | 동시 저장 두 건이 모두 검사를 통과해 합쳐서 더 많이 회수할 수 있다 | **수용 — 고침** |
| 2 | MEDIUM | 액션 수준 부분 로드는 guard 를 전혀 발동시키지 않는다 | **수용(부분)** — 주석 정정 + 후속 조건 명시, 계약은 유지 |
| 3 | MEDIUM | 명시적 `null` 이 검증을 우회한다. HTTP 에서 `NaN` → `null` 이 된다 | **수용 — 고침** |

---

## 1 (HIGH) — 수용. 잠금이 없으면 「선언한 회수 수」가 의미를 잃는다.

codex 의 예가 정확하다. 초기 `{A,B,C}` 에서
· 요청1 `{A,C}` / `expectedRemovals=1` · 요청2 `{A,B}` / `expectedRemovals=1`
둘이 같은 기준을 읽으면 **각자 1건으로 통과**하고 서로 다른 행을 지운다 → 결과 `{A}`,
총 2건 회수, 409 없음. READ COMMITTED 에서 성립한다.

고침: `assertRoleBelongsToStore(roleId, storeId, transaction?)` 가 트랜잭션을 받으면
그 `roles` 행을 `FOR UPDATE` 로 잠근다. `bulkUpdateRoleFunctionActions` 는
**기준 상태를 읽기 전에** 이 잠금을 잡는다.

★ **자매 경로에도 같이 걸었다** — `updateFunctionsForRole()` 은 역할 권한을 통째로
  지우고 다시 만든다. 한쪽만 잠그면 직렬화가 성립하지 않는다.
  (같은 형태의 지적을 인스턴스가 아니라 **부류로** 처리한다.)

시험: 「잠금 호출이 `transaction` + `lock:'UPDATE'` 로 있는가」와
**「그 호출이 기준 조회보다 먼저인가」**(`invocationCallOrder`) 둘 다 단언한다 —
순서를 안 재면 잠금을 뒤로 옮겨도 통과한다.

⤷ **남은 것**: codex 가 권한 동시 요청 통합시험을 권했다. 목 기반으로는 진짜 직렬화를
  못 잰다(실 DB 두 커넥션이 필요). 지금은 「잠금을 건다 + 순서가 맞다」까지만 잰다.

## 2 (MEDIUM) — 지적이 맞다. 내 주석이 사실이 아니었다.

내가 「액션 제거는 부분 로드로 발생하지 않는다」고 적었는데, 그것은 **지금
`RolePermissionsDrawer` 가 항상 CRUD 4개를 보내기 때문**이지 계약이 보장하는 바가 아니다.
엔드포인트는 액션 수준에서도 「최종 상태 교체」다.

코드는 바꾸지 않았다 — 지금 재현되는 경로가 없고, 액션 단위 계약을 지금 바꾸면
Flutter 클라이언트까지 함께 움직여야 한다. 대신 **주석에 조건을 못 박았다**:
Phase 93 ④액션 UI 가 「서버에서 받은 액션 집합을 편집」하게 되는 순간
`expectedActionRemovals`(또는 상태 버전)가 필요하다 — **그 화면을 만들기 전에 이 자리를 다시 볼 것.**

## 3 (MEDIUM) — 수용. `null` 을 거절한다.

하위 호환은 **필드 부재**에만 준다. `JSON.stringify({x: NaN}) === '{"x":null}'` 이므로
새 클라이언트의 계산 오류가 실제로 `null` 을 만든다 — 그것을 「안 보냄」으로 읽으면
방어가 조용히 풀린다.

★ 이 변경이 **타입 오류를 드러냈다**(`TS18047 'expectedRemovals' is possibly null`).
  그리고 그 오류는 **jest 가 「5 passed」로 통과처럼 보이는 모습**으로 나타났다 —
  suite 2개가 컴파일에 실패해 조용히 빠진 것이다. 종료코드로 재지 않았으면 놓쳤다.

---

## 최종 검증

- jest **35/35** (3 suites) · tsc 0 · eslint 내 추가 줄 0
- 돌연변이 **7건 전부 사망**
  · 1차: 대조 판정 제거 · 컨트롤러가 값 버림 · null 을 0 으로 취급 · 정수 검증 제거
  · 2차(codex 대응): 트랜잭션 잠금 제거 · 잠금을 기준 조회 뒤로 이동 · null 재통과
  ※ 2차는 「suite 컴파일 실패 0」을 함께 확인했다 — 컴파일이 깨져 실패한 것을
    «돌연변이 사망» 으로 오독하지 않기 위해서다.

## 확인해 둔 전제

- `role_functions` 중 액션 0개인 행: 로컬 14,296건·운영 16,806건 모두 **0건**
  → 클라이언트의 `diff.removed` 와 서버의 `staleIds.length` 가 같은 집합을 센다.
- 두 번째 클라이언트 **Flutter `tienda-admin-app`** 은 아직 이 필드를 안 보낸다
  (`usuarios_repository.dart:374`). expand 단계라 종전대로 동작하지만
  **거기서는 이 보호가 없다.** 적용하려면 `permissions_editor_screen.dart` 에
  원본 스냅샷이 필요하다(지금은 안 들고 있다).
