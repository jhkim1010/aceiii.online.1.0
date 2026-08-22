# W6-C3 ② 복원 엔진 본체 — codex 자문 요청 (2026-08-22)

1단계(FK 매니페스트)는 네 지적 4건을 반영해 배포했다(`.team/reviews/w6c3-manifest-resolution.md`).
**엔진 본체를 짓기 전에** 다시 본다. 오늘 하루에만 내 설계가 6번 반려됐고,
그중 `restaurant_tables.current_sale_id` 는 **운영 데이터로 실증된 실제 사고 경로**였다.

---

## 지금 있는 것 (전제)

| | 상태 |
|---|---|
| `RESTORE_ENGINE_STATUS = 'blocked'` | 서버 상수. 복원은 무조건 거부 |
| `store-restore-manifest.ts` | FK 351개 처리 확정. 순서는 카탈로그에서 위상 정렬 |
| `store-restore-fk-catalog.txt` | 운영 FK 기준선 351줄 (커밋됨) |
| `OPERATIONAL_STATE_RESETS` | 운영 상태 정규화 (지금은 `restaurant_tables` 하나) |
| `DeferredFkEntry` / `unresolvedDeferred()` | 원장 **타입과 판정 함수만**. 집행은 없음 |
| `resolveKeepGlobalValue()` | owner_group 게이트. 모르면 던진다 |
| `check-tenant-ownership.sh` | 카탈로그에서만 소유를 역유도하는 감사기 (엔진 밖) |

---

## ★ 현재 배선 (실측 — 여기가 문제의 출발점이다)

```ts
// store.controller.ts
@Post('restore')
@Auth(ValidRoles.superadmin)
async restoreStore(@Body() body: any) {
  return this.storeService.restoreStoreFromBackup(body);
}
```

```tsx
// ventago-app RegistrationList.tsx
const data = JSON.parse(await file.text());
if (!data.store || !data.storeId) { /* 파일이 자기를 검증한다 */ }
await apiConnector.post('/store/restore', data);   // ← 파일 전체가 곧 요청 본문
```

**즉 지금은 목적지 매장을 고를 자리가 아예 없다.** 네가 "가장 큰 누락" 이라고 한
"목적지 `storeId` 를 서버가 확정한다" 를 지키려면 **API 모양 자체를 바꿔야 한다.**

## 실측 (운영 2026-08-22, 매장 9 = ACE)

| | 행 |
|---|---:|
| `role_function_actions` | 4,415 |
| `store_clients` | 3,771 |
| `stocks` | 55 |
| `products` | 36 |
| `sales` / `sale_items` | 22 / 25 |

한 매장 복제는 **1만 행 안팎**이다. 전체 `role_function_actions` 40,557 중 4,415 가 한 매장분.

---

## 내가 제안하는 설계

### F1. API 를 둘로 가른다 — 목적지는 요청이 정하고, 서버가 확정한다

```
POST /store/restore/plan     { file }                  → 계획서(무엇을 몇 행, 무엇을 버림)
POST /store/restore/execute  { planId, mode, destination? }
```

- `mode: 'CLONE'` → `destination` 을 **받지 않는다.** 서버가 새 매장을 만들고 그 ID 를 쓴다.
- `mode: 'IN_PLACE_RECOVERY'` → `destination.storeId` 를 **요청에서** 받되,
  파일의 `storeId` 와 **일치할 때만** 허용한다(같은 매장 복구이므로).
- 어느 경우에도 **파일의 `storeId` 를 목적지로 쓰지 않는다.**
- `planId` 는 서버가 계획 단계에서 발급하고 파일 내용 해시를 묶어 둔다
  (계획을 본 파일과 집행할 파일이 같아야 한다).

### F2. 입력 검증 — 허용 목록 기반, `any` 제거

- 테이블별 **허용 컬럼 목록**을 FK 카탈로그와 같은 방식으로 커밋(`store-restore-columns.txt`)
- 미지 테이블 / 미지 컬럼 → **거부**(무시 아님)
- 형식 버전 · 행 수 · `coverage` 해시 검증
- `backupData: any` 와 `...fields` 를 없앤다

### F3. 잠금과 대조

```
BEGIN
  SELECT pg_advisory_xact_lock(RESTORE_LOCK_NS, <destination storeId>)
  런타임 카탈로그를 읽어 스냅샷과 **정규화 비교** → 다르면 ROLLBACK
  ... 첫 쓰기 ...
```

- 네 지적대로 **잠금 획득 후 첫 쓰기 전**에 대조한다
- 이 저장소 관례대로 namespace 상수를 첫 키로 고정한다
  (`pg_advisory_xact_lock(int4,int4)` 키 공간이 앱 전체 공유라 도메인 값 두 개는 위험)

### F4. 단일 트랜잭션

1만 행이면 단일 트랜잭션으로 간다. 쪼개면 부분 복원이 남는데,
**부분 복원이 남는 것이 잠금이 긴 것보다 나쁘다.** `CLONE` 은 새 매장이라
기존 행과의 경합도 없다.

### F5. DEFERRED 집행

- 테이블별 삽입 루프에서 DEFERRED 컬럼은 NULL 로 넣고 **원장에 기록**
  (`originalValue` 는 백업 행의 값 — NULL 이면 NULL 로 기록)
- 전 테이블 삽입 후 원장을 돌며 UPDATE, `applied=true`
- 커밋 전 `unresolvedDeferred()` 가 **0건**이어야 한다

### F6. 커밋 전 역방향 소유 증명

`check-tenant-ownership.sh` 의 논리를 엔진 안에서 **목적지 매장에 대해서만** 돌린다.
카탈로그 FK 만으로 소유를 역유도하고, 새로 만든 행 중
"목적지 매장에 안 닿는 것" 과 "두 매장에 걸친 것" 이 0 이어야 한다.
백업 SQL(`store-backup-scopes.ts`)을 **재사용하지 않는다**(E4).

### F7. 자격증명 — "재인증 필요" 행

마스킹된 NOT NULL 6개(`mp_accounts.access_token/refresh_token`,
`commerce_channels.channel_key/secret`, `wp_channels.channel_key/secret`)는
`CLONE` 에서 **비밀만 placeholder 로 넣고 비활성 상태**로 만든다.
네가 "통째로 건너뛰면 설정과 자식 관계까지 잃는다" 고 한 것을 반영한 것이다.

### F8. `IN_PLACE_RECOVERY` 는 이번에 안 만든다

`CLONE` 만 먼저 열고 `IN_PLACE_RECOVERY` 는 잠근 채 둔다.
이유: "T 이후 사실이 참조했는가" 경계가 아직 설계되지 않았고,
같은 매장에 쓰는 것은 되돌릴 수 없다.

### F9. 잠금 해제는 CLONE 에 한정

`RESTORE_ENGINE_STATUS` 를 `'clone_only'` 로 바꾸고,
`IN_PLACE_RECOVERY` 요청은 계속 거부한다.

---

## 묻는 것

1. **F1 의 2단계 API(plan → execute)가 맞나?** 아니면 한 번의 호출로 하되
   목적지만 서버가 정하게 하는 편이 나은가? `planId` 를 서버에 들고 있으면
   상태가 생기는데, 그 상태를 어디에 두어야 하나(메모리 / DB / 아예 안 둠)?
   ★ 지금 프론트는 **파일 전체를 JSON body 로** 보낸다. 1만 행이면 수 MB 다.
     이것도 같이 바꿔야 하나(multipart 업로드 → 서버 디스크/MinIO)?

2. **F4 의 단일 트랜잭션이 맞나?** 1만 행 INSERT 를 한 트랜잭션에 넣으면
   `CLONE` 대상은 새 매장이라 경합이 없지만, **`stocks` 의 트리거**
   (`trg_stock_balances_apply`)가 행마다 돈다. 이게 문제가 되나?
   그리고 이 저장소 규약은 "트랜잭션 안 외부 I/O 금지" 인데
   복원 중 MinIO 객체 복사는 어디서 해야 하나?

3. **F6 의 역방향 증명을 트랜잭션 안에서 어떻게 도나?**
   감사 스크립트는 전 테이블을 훑는 무거운 쿼리다. 커밋 전에 그걸 돌리면
   잠금이 길어진다. **새로 만든 행만** 대상으로 좁히는 방법이 있나
   (ID 범위? 임시 테이블에 기록?), 아니면 좁히는 것 자체가 위험한가
   ("새로 만든 행 목록" 이 틀리면 검사가 통째로 헛돈다)?

4. **F7 이 오히려 위험하지 않나?** 비활성 "재인증 필요" 행을 만들면
   `mp_accounts` 가 존재하므로 화면상 "연동됨" 으로 보일 수 있고,
   그 상태로 결제를 시도하면 어디서 실패하는지가 문제다.
   차라리 그 테이블만 빼는 게 나은가 — 네가 지난번엔 반대했는데,
   **"존재하지만 못 쓰는 것" 과 "없는 것" 중 어느 쪽이 덜 위험한가?**

5. **F8/F9 처럼 `CLONE` 만 먼저 여는 것이 맞나?**
   아니면 둘 다 될 때까지 잠가 두는 편이 나은가?
   ★ 실제 용도를 생각하면 지금 복원 버튼을 쓰는 곳은 superadmin 의
     **가입 신청 화면**(RegistrationList)이다 — 즉 실사용은 CLONE 쪽이다.

6. **`OPERATIONAL_STATE_RESETS` 가 `restaurant_tables` 하나뿐인 게 맞나?**
   너는 "현재 상태 vs 과거 사실" 구분을 짚었는데, 152개 중 같은 성질을 가진
   테이블을 내가 더 놓쳤을 수 있다. 어떤 신호로 찾아야 하나
   (상태 컬럼 + FK 가 짝을 이루는 패턴? 아니면 다른 기준)?

7. 내가 놓친 것.

한국어. 결론 먼저. 반대할 것은 분명히 반대하라. **7개 전부 답하는 것을 우선하라.**
저장소를 직접 읽어도 된다 — `api-ventago/src/app/store/` 에 1단계 결과물이 다 있다.
