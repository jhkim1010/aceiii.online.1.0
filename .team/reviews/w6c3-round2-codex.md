codex
## 결론

1. 우선순위는 전부 없애도 된다. 다만 `COPY`를 없애는 게 아니라, **암묵적 fallback COPY를 없애야 한다.**
2. 감사 트리거 억제는 `audit_row_change()` 내부의 `SET LOCAL` 판정이 가장 안전하다. 함수 변경은 실행기보다 먼저 배포해도 되지만, 실행기와 같은 릴리스 묶음이 더 낫다.
3. 단일 DB 트랜잭션이 정말 끝까지 하나라면 lease 자체가 필요 없을 수 있다. 상태 선점이 별도 커밋이라면 제안한 `lease_expires_at` 하나로 충분하되, 자동 `FAILED` 조건과 수동 복구 절차를 더 엄밀히 해야 한다.
4. 트리거 선언은 함수 단위로 유지하고, 실제 처리 결과는 `(mode, table, event, function)` 인스턴스로 유도하는 것이 맞다.
5. 배포 순서는 정책 컴파일러 → typed input → 트리거 계획 유도 → 실행 계약 결합 → 필요한 마이그레이션 → 잠긴 실행기 → 잠금 해제다.
6. 내가 놓친 수치는 더 있다. 특히 테넌트 가드는 34개가 아니라 현재 카탈로그 기준 **35개**다. 1라운드의 “정확히 두 개” 표현은 명백한 오답이었다.

---

## 1. 우선순위를 전부 없애도 되나?

된다. 경계는 다음과 같다.

- 정책 우선순위: 제거
- `COPY` action: 유지
- 아무 근거 없는 기본 fallback: 제거

즉 후보 생성기는 모든 컬럼에 대해 최소 하나의 근거를 만들어야 한다.

```text
스키마에서 생성되는 후보
  PK/identity/default       → GENERATED_ID 또는 SERVER_GENERATED
  FK                       → REMAP/CLEAR/KEEP_GLOBAL/DEFERRED
  timestamp 정책           → COPY
  일반 scalar/JSON 컬럼    → COPY
  generated column         → OMIT
  store identity           → SERVER_IDENTITY

도메인 선언이 추가하는 후보
  운영 상태                → RESET
  자격증명                 → REGENERATE
  unlinked reference       → REMAP/CLEAR/...
```

여기서 일반 컬럼의 `COPY`도 “후보 0개라서 복사”가 아니다. 다음과 같은 **카탈로그 기반 정책이 만든 명시적 후보**다.

```ts
{
  action: { kind: 'COPY' },
  source: 'SCHEMA_PLAIN_VALUE_COLUMN'
}
```

최종 규칙은 이렇게 잡는 것이 적절하다.

```text
후보 0개    → 빌드 실패: UNCLASSIFIED_COLUMN
후보 1개    → 채택
후보 2개+   → 구조적으로 동일하면 sources 병합
              다르면 빌드 실패: CONFLICTING_COLUMN_POLICIES
```

따라서 1,255개를 손으로 선언할 필요가 없다. 대신 “평범한 복사 가능 컬럼”의 정의를 카탈로그로 생성한다. 그 정의에는 적어도 다음이 필요하다.

- PK 여부
- identity/generated 여부
- default 존재 여부
- FK 여부
- 타입
- nullability

이렇게 해야 새 컬럼이 추가됐을 때도 단순히 이름이 알려졌다는 이유로 복사되지 않는다. 카탈로그 분류가 불가능한 새 형태면 빌드가 깨진다.

그리고 `id`와 timestamp도 같은 후보 수집기에 넣는 것이 맞다. 단, `column === 'id'`가 아니라 실제 PK/identity/default 사실에서 유도해야 한다.

---

## 2. 트리거 억제와 운영 함수 변경

### (가) 지금 바꿀 것인가?

내 권고는 다음과 같다.

- 설계와 마이그레이션 초안: 지금 확정
- 운영 적용: 실행기가 들어가는 릴리스와 함께
- 적용 순서: 트리거 함수 변경 먼저 → 잠긴 실행기 배포 → 검증 → 기능 잠금 해제

지금 미리 운영에 적용해도 일반 요청의 동작은 바뀌지 않는다. 설정값이 없는 모든 기존 요청은 기존 경로로 간다. 하지만 실행기가 아직 없다면 즉시 얻는 이익도 없다.

따라서 별도 선행 배포보다는 **같은 릴리스 안에서 실행기보다 먼저 적용되는 backward-compatible 마이그레이션**이 가장 합리적이다.

반드시 설정값을 문자열 진리값으로 넓게 해석하지 말고 정확히 비교해야 한다.

```sql
IF current_setting('ventago.restore_mode', true) = 'on' THEN
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END IF;
```

가능하면 설정 이름도 현재 사용 중인 `ventago.actor_user_id`와 같은 namespace인 `ventago.restore_mode`가 자연스럽다.

### (나) 매 행 `current_setting()` 비용

현재 규모에서는 문제로 볼 근거가 없다.

- 호출 대상은 7개 테이블뿐이다.
- `current_setting(..., true)`는 DB 조회나 테이블 접근이 아니다.
- 기존 함수는 어차피 매 행 `to_jsonb`, 비교, 부모 조회 가능성, `audit_logs INSERT`를 수행한다.
- 설정 조회 비용은 감사 INSERT 및 인덱스 갱신 비용보다 훨씬 작을 가능성이 높다.

다만 정확한 비율은 벤치마크 없이 단정하면 안 된다. 5,652행 정도를 대상으로 설정 판정 전후 `EXPLAIN (ANALYZE, BUFFERS)` 또는 반복 INSERT로 확인하면 충분하다. 성능상 우려 때문에 더 위험한 DDL 방식을 택할 이유는 없다.

### (다) 특정 트리거만 DISABLE 하는 대안

기술적으로는 가능하고 트랜잭션 안에서도 되돌릴 수 있다.

```sql
BEGIN;
ALTER TABLE products DISABLE TRIGGER trg_audit_products;
-- restore
ALTER TABLE products ENABLE TRIGGER trg_audit_products;
COMMIT;
```

하지만 권하지 않는다.

- `ALTER TABLE ... DISABLE/ENABLE TRIGGER`는 해당 테이블에 `SHARE ROW EXCLUSIVE` 잠금을 잡는다.
- 이는 일반적인 동시 쓰기와 충돌한다.
- 복원 트랜잭션 전체 동안 7개 핵심 테이블의 트리거 상태와 잠금을 다뤄야 한다.
- 함수 내부 분기는 해당 복원 트랜잭션에만 영향을 주지만, trigger disable은 테이블 메타데이터를 바꾸는 방식이다.
- 테이블 소유자 권한도 필요하다. 내부 constraint trigger까지 끄는 경우에는 superuser 요구가 추가되지만, 이름으로 지정한 사용자 감사 트리거만 다루더라도 운영 DDL이라는 점은 남는다.

PostgreSQL도 개별 트리거 disable을 지원하지만, 이 작업이 `SHARE ROW EXCLUSIVE` 잠금을 취한다고 명시한다. [PostgreSQL ALTER TABLE 문서](https://www.postgresql.org/docs/current/sql-altertable.html)

따라서 순위는 다음과 같다.

1. `SET LOCAL` + 감사 함수 내부 early return
2. 별도의 restore-aware 감사 함수 구조
3. 개별 `DISABLE TRIGGER`
4. `DISABLE TRIGGER USER/ALL` 또는 `session_replication_role` — 사용하지 않음

---

## 3. lease/heartbeat는 과한가?

내 1라운드 제안은 현재 조건에는 과했다.

가장 먼저 정해야 할 것은 **`EXECUTING` 선점이 복원 데이터와 같은 트랜잭션에 들어가는가**다.

### 경우 A: 모든 것이 하나의 DB 트랜잭션

```text
BEGIN
  PLANNED → EXECUTING
  목적지 매장 및 전체 데이터 INSERT
  EXECUTING → SUCCEEDED
COMMIT
```

프로세스가 죽으면 전체가 rollback되므로 커밋된 `EXECUTING`이 남지 않는다. 동시 실행도 조건부 UPDATE의 행 잠금으로 직렬화된다.

이 구조라면 lease, heartbeat, token은 필요 없다.

단, 다음 조건이 모두 충족돼야 한다.

- 업로드 다운로드·압축 해제·파싱은 트랜잭션 밖
- 외부 HTTP/MinIO/소켓 작업은 트랜잭션 밖
- 트랜잭션 안에는 PostgreSQL 작업만 존재
- 성공 상태 갱신도 같은 트랜잭션
- 복원 완료 후 감사·객체 삭제 같은 외부 부작용은 커밋 후 별도 처리

### 경우 B: `EXECUTING` 선점을 먼저 커밋

이 경우에는 사용자가 제안한 최소 모델이 합리적이다.

- `lease_expires_at` 하나 추가
- heartbeat 없음
- 재선점 없음
- 만료 후 새 계획만 허용
- 목적지 매장 부재 확인
- `FAILED(LEASE_EXPIRED)`로 종결

다만 “만료 + 목적지 매장 부재”만으로 자동 `FAILED` 처리하려면 다음을 보장해야 한다.

1. 모든 복원 쓰기가 하나의 트랜잭션이었다.
2. 목적지 매장이 그 트랜잭션에서 가장 먼저 생성된다.
3. 복원 중 외부 부작용이 없다.
4. `destination_store_id`가 상태 선점 시점에는 아직 없더라도, 생성 직후 계획 행에 같은 트랜잭션으로 기록된다.
5. 복원이 목적지 매장 외의 전역 테이블을 수정하지 않는다.

구체적으로 깨지는 경우는 다음이다.

- 데이터 트랜잭션은 커밋됐지만 `SUCCEEDED` 상태 갱신 전에 프로세스가 죽음  
  → 목적지 존재로 자동 FAILED는 막히지만 영구 `EXECUTING`이 된다.
- 목적지 생성 전에 전역 레코드나 외부 객체를 만들고 죽음  
  → 목적지는 없지만 부작용은 남아 있어 `FAILED` 판정이 거짓이 된다.
- 목적지 생성이 별도 트랜잭션인데 이후 복원이 실패  
  → 목적지는 존재하지만 내용은 불완전하다.
- 오래 걸리는 정상 복원이 lease를 넘김  
  → 복원 트랜잭션이 아직 살아 있는데 복구자가 만료로 판단할 수 있다.

재선점이 없다면 마지막 경우도 데이터 중복으로 이어지지는 않지만 잘못된 상태 판정은 가능하다. 그래서 자동 만료 처리 쿼리는 해당 복원 트랜잭션과 동시에 실행될 수 없게 해야 한다.

최소 권고는 다음이다.

- 가능하면 경우 A를 택해 lease를 제거
- 경우 B라면 `lease_expires_at`만 사용
- 자동 재선점 없음
- `execution_token`, `heartbeat_at`, `attempt_no`, `RECOVERY_REQUIRED` 없음
- 목적지가 있으면 자동 전이하지 않고 수동 조사
- 목적지가 없고 원자적 DB 작업·외부 부작용 없음이 구조적으로 보장될 때만 `FAILED(LEASE_EXPIRED)`

---

## 4. billing 트리거 모순을 유도로 바꾸는 방식

제안한 방식이 맞다.

함수 단위 선언은 “이 함수의 의미”를 담고, 실제 도달 가능성과 최종 처리는 trigger catalog 인스턴스에서 유도하면 된다.

```text
FunctionPolicy
  audit_row_change
    semantic: USER_ACTIVITY_AUDIT
    defaultHandling: SUPPRESS

  trg_billing_invoice_payment_status
    semantic: DERIVED_BILLING_STATE
    defaultHandling: MUST_RUN_TARGET_EXCLUDED
```

그 후 다음 입력으로 실제 계획을 만든다.

```text
(mode, source table, event, function)
+ mode별 포함/제외 테이블
+ 실행기가 그 테이블에 수행하는 INSERT/UPDATE/DELETE
+ 함수 정책
```

예를 들어:

```text
CLONE
billing_payments
INSERT
trg_billing_invoice_payment_status
```

`billing_payments`가 CLONE 제외이므로 결과는 `NOT_REACHED`다.

이 구조의 장점은 34줄을 58줄로 손 복제하지 않는다는 데 있다. 58개 결과는 카탈로그에서 자동 생성되는 실행 산출물이어야 한다.

다만 함수 단위 선언만으로 부족한 예외는 허용해야 한다. 같은 함수라도 다음에 따라 의미가 달라질 수 있기 때문이다.

- `TG_ARGV`
- source table
- event
- BEFORE/AFTER
- 대상 테이블 포함 여부

따라서 구조는 `function default + instance override`가 가장 안전하다. 현재 `audit_row_change`처럼 일관된 것은 override가 필요 없고, 예외가 생길 때만 구체적인 `(table, event, function)` override를 둔다.

---

## 5. 한 번에 하나씩 배포 가능한 순서

### 1. 우선순위 없는 정책 컴파일러

- 후보 전수 수집
- 암묵적 fallback 제거
- 카탈로그 기반 일반 `COPY`
- 구조적 동등성 검사
- 복수 `sources`
- 1,826개 전수 invariant 테스트

DB 변경 없음. 단독 배포 가능하다.

### 2. typed input 및 구조 검증

- 타입, nullability, required/default/generated 검증
- 필수 테이블 존재 검증
- 중첩 자식 배열 검증
- 부모-자식 소속 보존
- row count 생성

1번과 논리적으로 독립이다. 다만 실행기는 1·2 모두를 전제로 해야 한다.

### 3. 트리거 실행 계획 유도

- 함수 단위 의미 선언 유지
- 카탈로그 58개 인스턴스 자동 확장
- 모드별 테이블 포함 여부와 event 도달 가능성 계산
- `NOT_REACHED` 자동 유도
- 미분류 trigger instance 빌드 실패

아직 DB 변경 없이 배포 가능하다.

### 4. 실행 계약 결합

이 단계는 1라운드 CRITICAL이라 빠지면 안 된다.

- plan ID
- content SHA-256
- schema fingerprint
- registration/requester
- row counts
- compiled column plan
- trigger execution plan
- plan version/hash

실행기가 “검토된 바로 그 입력과 계획”만 소비하게 한다.

### 5. 상태 모델 최소화 결정

먼저 같은 트랜잭션 모델을 확정한다.

- 같은 트랜잭션이면 lease 추가하지 않음
- 선점 선커밋이 불가피하면 `lease_expires_at`만 추가하는 새 마이그레이션

마이그레이션 승인이 필요한 첫 지점이다.

### 6. 감사 트리거 억제 마이그레이션

- `audit_row_change()`에 transaction-local early return 추가
- 기존 일반 쓰기 회귀 테스트
- restore setting이 있을 때 감사 INSERT가 생기지 않는 테스트
- tenant guard가 계속 동작하는 통합 테스트

실행기와 같은 릴리스에 넣되 실행기보다 먼저 적용한다.

### 7. 실행기를 잠긴 상태로 배포

- `RESTORE_ENGINE_STATUS='blocked'` 유지
- 실제 plan/hash 재검증
- 단일 트랜잭션
- `SET LOCAL ventago.restore_mode='on'`
- 선택된 트리거 계획과 실제 카탈로그 대조
- 실패 시 전체 rollback

### 8. 운영 검증 후 잠금 해제

정책 컴파일러와 typed input은 서로 독립이다. 하지만 실행 계약은 둘의 산출물을 묶으므로 1·2 이후여야 한다. 트리거 함수 변경은 실행기보다 먼저 존재해야 한다.

---

## 6. 내가 1라운드에서 놓친 것

명확히 세 가지다.

### 첫째: 다중 주장 컬럼 수

내가 `DEFERRED_FK_COLUMNS`와 FK 카탈로그의 중복을 후보로 세지 않았다.

정정:

```text
다중 주장: 12
DEFERRED + FK: 10
RESET + UNLINK: 1
RESET + FK: 1
서로 다른 결과: 0
```

“정확히 두 개”라는 표현은 틀렸다. 결론만 우연히 유지됐다.

### 둘째: 테넌트 트리거 수

현재 카탈로그 58행을 다시 세면:

```text
전체 trigger instance: 58
고유 함수: 22
tenant_chk_* instance: 35
audit_row_change instance: 7
```

따라서 내가 인용한 “34개 테넌트 가드”도 하나 부족하다. 파일 상단 주석의 34를 검산 없이 받아썼다.

더구나 trigger catalog 자체의 머리말에는 “24개”라고 적혀 있어, 현재 저장소 안에 `24`, `34`, 실측 `35`가 동시에 존재한다. 숫자를 주석에 고정하지 말고 테스트에서 계산해 출력하는 편이 맞다.

### 셋째: 운영 실측 숫자의 증거 수준

`5,652행`, `151행`, `97%`는 코드 주석에 기록된 운영 실측값을 인용한 것이지, 내가 운영 DB에서 독립 재현한 값이 아니다. 나는 운영 DB 접속이 금지되어 있다.

따라서 1라운드에서는 다음처럼 표시했어야 정확했다.

> 저장소에 기록된 매장 9 실측 기준 5,652행 대 151행이며, 운영 재확인은 필요하다.

수치 자체가 틀렸다는 증거는 없지만, 내가 직접 검증한 사실처럼 쓴 것은 잘못이다.

추가로 현재 작업 트리에는 `ResolvedColumn.source`를 `sources`로 바꾸기 시작했지만 `at()`이 아직 `source`를 반환하는 중간 상태가 보인다. 이는 1라운드 당시 결함이 아니라 후속 편집 중인 상태로 보이지만, 다음 커밋 전 타입 검사에서 반드시 정리돼야 한다.

최종적으로 1라운드의 방향은 유지하되, **lease 요구는 축소**하고, **기본 COPY는 카탈로그 생성 후보로 명시화**하며, **트리거 선언은 함수 단위·실행 결과는 인스턴스 단위 유도**로 정리하는 것이 가장 작은 안전 설계다.
hook: Stop
hook: Stop
hook: Stop Failed
hook: Stop Completed
tokens used
56,061
## 결론

1. 우선순위는 전부 없애도 된다. 다만 `COPY`를 없애는 게 아니라, **암묵적 fallback COPY를 없애야 한다.**
2. 감사 트리거 억제는 `audit_row_change()` 내부의 `SET LOCAL` 판정이 가장 안전하다. 함수 변경은 실행기보다 먼저 배포해도 되지만, 실행기와 같은 릴리스 묶음이 더 낫다.
3. 단일 DB 트랜잭션이 정말 끝까지 하나라면 lease 자체가 필요 없을 수 있다. 상태 선점이 별도 커밋이라면 제안한 `lease_expires_at` 하나로 충분하되, 자동 `FAILED` 조건과 수동 복구 절차를 더 엄밀히 해야 한다.
4. 트리거 선언은 함수 단위로 유지하고, 실제 처리 결과는 `(mode, table, event, function)` 인스턴스로 유도하는 것이 맞다.
5. 배포 순서는 정책 컴파일러 → typed input → 트리거 계획 유도 → 실행 계약 결합 → 필요한 마이그레이션 → 잠긴 실행기 → 잠금 해제다.
6. 내가 놓친 수치는 더 있다. 특히 테넌트 가드는 34개가 아니라 현재 카탈로그 기준 **35개**다. 1라운드의 “정확히 두 개” 표현은 명백한 오답이었다.

---

## 1. 우선순위를 전부 없애도 되나?

된다. 경계는 다음과 같다.

- 정책 우선순위: 제거
- `COPY` action: 유지
- 아무 근거 없는 기본 fallback: 제거

즉 후보 생성기는 모든 컬럼에 대해 최소 하나의 근거를 만들어야 한다.

```text
스키마에서 생성되는 후보
  PK/identity/default       → GENERATED_ID 또는 SERVER_GENERATED
  FK                       → REMAP/CLEAR/KEEP_GLOBAL/DEFERRED
  timestamp 정책           → COPY
  일반 scalar/JSON 컬럼    → COPY
  generated column         → OMIT
  store identity           → SERVER_IDENTITY

도메인 선언이 추가하는 후보
  운영 상태                → RESET
  자격증명                 → REGENERATE
  unlinked reference       → REMAP/CLEAR/...
```

여기서 일반 컬럼의 `COPY`도 “후보 0개라서 복사”가 아니다. 다음과 같은 **카탈로그 기반 정책이 만든 명시적 후보**다.

```ts
{
  action: { kind: 'COPY' },
  source: 'SCHEMA_PLAIN_VALUE_COLUMN'
}
```

최종 규칙은 이렇게 잡는 것이 적절하다.

```text
후보 0개    → 빌드 실패: UNCLASSIFIED_COLUMN
후보 1개    → 채택
후보 2개+   → 구조적으로 동일하면 sources 병합
              다르면 빌드 실패: CONFLICTING_COLUMN_POLICIES
```

따라서 1,255개를 손으로 선언할 필요가 없다. 대신 “평범한 복사 가능 컬럼”의 정의를 카탈로그로 생성한다. 그 정의에는 적어도 다음이 필요하다.

- PK 여부
- identity/generated 여부
- default 존재 여부
- FK 여부
- 타입
- nullability

이렇게 해야 새 컬럼이 추가됐을 때도 단순히 이름이 알려졌다는 이유로 복사되지 않는다. 카탈로그 분류가 불가능한 새 형태면 빌드가 깨진다.

그리고 `id`와 timestamp도 같은 후보 수집기에 넣는 것이 맞다. 단, `column === 'id'`가 아니라 실제 PK/identity/default 사실에서 유도해야 한다.

---

## 2. 트리거 억제와 운영 함수 변경

### (가) 지금 바꿀 것인가?

내 권고는 다음과 같다.

- 설계와 마이그레이션 초안: 지금 확정
- 운영 적용: 실행기가 들어가는 릴리스와 함께
- 적용 순서: 트리거 함수 변경 먼저 → 잠긴 실행기 배포 → 검증 → 기능 잠금 해제

지금 미리 운영에 적용해도 일반 요청의 동작은 바뀌지 않는다. 설정값이 없는 모든 기존 요청은 기존 경로로 간다. 하지만 실행기가 아직 없다면 즉시 얻는 이익도 없다.

따라서 별도 선행 배포보다는 **같은 릴리스 안에서 실행기보다 먼저 적용되는 backward-compatible 마이그레이션**이 가장 합리적이다.

반드시 설정값을 문자열 진리값으로 넓게 해석하지 말고 정확히 비교해야 한다.

```sql
IF current_setting('ventago.restore_mode', true) = 'on' THEN
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END IF;
```

가능하면 설정 이름도 현재 사용 중인 `ventago.actor_user_id`와 같은 namespace인 `ventago.restore_mode`가 자연스럽다.

### (나) 매 행 `current_setting()` 비용

현재 규모에서는 문제로 볼 근거가 없다.

- 호출 대상은 7개 테이블뿐이다.
- `current_setting(..., true)`는 DB 조회나 테이블 접근이 아니다.
- 기존 함수는 어차피 매 행 `to_jsonb`, 비교, 부모 조회 가능성, `audit_logs INSERT`를 수행한다.
- 설정 조회 비용은 감사 INSERT 및 인덱스 갱신 비용보다 훨씬 작을 가능성이 높다.

다만 정확한 비율은 벤치마크 없이 단정하면 안 된다. 5,652행 정도를 대상으로 설정 판정 전후 `EXPLAIN (ANALYZE, BUFFERS)` 또는 반복 INSERT로 확인하면 충분하다. 성능상 우려 때문에 더 위험한 DDL 방식을 택할 이유는 없다.

### (다) 특정 트리거만 DISABLE 하는 대안

기술적으로는 가능하고 트랜잭션 안에서도 되돌릴 수 있다.

```sql
BEGIN;
ALTER TABLE products DISABLE TRIGGER trg_audit_products;
-- restore
ALTER TABLE products ENABLE TRIGGER trg_audit_products;
COMMIT;
```

하지만 권하지 않는다.

- `ALTER TABLE ... DISABLE/ENABLE TRIGGER`는 해당 테이블에 `SHARE ROW EXCLUSIVE` 잠금을 잡는다.
- 이는 일반적인 동시 쓰기와 충돌한다.
- 복원 트랜잭션 전체 동안 7개 핵심 테이블의 트리거 상태와 잠금을 다뤄야 한다.
- 함수 내부 분기는 해당 복원 트랜잭션에만 영향을 주지만, trigger disable은 테이블 메타데이터를 바꾸는 방식이다.
- 테이블 소유자 권한도 필요하다. 내부 constraint trigger까지 끄는 경우에는 superuser 요구가 추가되지만, 이름으로 지정한 사용자 감사 트리거만 다루더라도 운영 DDL이라는 점은 남는다.

PostgreSQL도 개별 트리거 disable을 지원하지만, 이 작업이 `SHARE ROW EXCLUSIVE` 잠금을 취한다고 명시한다. [PostgreSQL ALTER TABLE 문서](https://www.postgresql.org/docs/current/sql-altertable.html)

따라서 순위는 다음과 같다.

1. `SET LOCAL` + 감사 함수 내부 early return
2. 별도의 restore-aware 감사 함수 구조
3. 개별 `DISABLE TRIGGER`
4. `DISABLE TRIGGER USER/ALL` 또는 `session_replication_role` — 사용하지 않음

---

## 3. lease/heartbeat는 과한가?

내 1라운드 제안은 현재 조건에는 과했다.

가장 먼저 정해야 할 것은 **`EXECUTING` 선점이 복원 데이터와 같은 트랜잭션에 들어가는가**다.

### 경우 A: 모든 것이 하나의 DB 트랜잭션

```text
BEGIN
  PLANNED → EXECUTING
  목적지 매장 및 전체 데이터 INSERT
  EXECUTING → SUCCEEDED
COMMIT
```

프로세스가 죽으면 전체가 rollback되므로 커밋된 `EXECUTING`이 남지 않는다. 동시 실행도 조건부 UPDATE의 행 잠금으로 직렬화된다.

이 구조라면 lease, heartbeat, token은 필요 없다.

단, 다음 조건이 모두 충족돼야 한다.

- 업로드 다운로드·압축 해제·파싱은 트랜잭션 밖
- 외부 HTTP/MinIO/소켓 작업은 트랜잭션 밖
- 트랜잭션 안에는 PostgreSQL 작업만 존재
- 성공 상태 갱신도 같은 트랜잭션
- 복원 완료 후 감사·객체 삭제 같은 외부 부작용은 커밋 후 별도 처리

### 경우 B: `EXECUTING` 선점을 먼저 커밋

이 경우에는 사용자가 제안한 최소 모델이 합리적이다.

- `lease_expires_at` 하나 추가
- heartbeat 없음
- 재선점 없음
- 만료 후 새 계획만 허용
- 목적지 매장 부재 확인
- `FAILED(LEASE_EXPIRED)`로 종결

다만 “만료 + 목적지 매장 부재”만으로 자동 `FAILED` 처리하려면 다음을 보장해야 한다.

1. 모든 복원 쓰기가 하나의 트랜잭션이었다.
2. 목적지 매장이 그 트랜잭션에서 가장 먼저 생성된다.
3. 복원 중 외부 부작용이 없다.
4. `destination_store_id`가 상태 선점 시점에는 아직 없더라도, 생성 직후 계획 행에 같은 트랜잭션으로 기록된다.
5. 복원이 목적지 매장 외의 전역 테이블을 수정하지 않는다.

구체적으로 깨지는 경우는 다음이다.

- 데이터 트랜잭션은 커밋됐지만 `SUCCEEDED` 상태 갱신 전에 프로세스가 죽음  
  → 목적지 존재로 자동 FAILED는 막히지만 영구 `EXECUTING`이 된다.
- 목적지 생성 전에 전역 레코드나 외부 객체를 만들고 죽음  
  → 목적지는 없지만 부작용은 남아 있어 `FAILED` 판정이 거짓이 된다.
- 목적지 생성이 별도 트랜잭션인데 이후 복원이 실패  
  → 목적지는 존재하지만 내용은 불완전하다.
- 오래 걸리는 정상 복원이 lease를 넘김  
  → 복원 트랜잭션이 아직 살아 있는데 복구자가 만료로 판단할 수 있다.

재선점이 없다면 마지막 경우도 데이터 중복으로 이어지지는 않지만 잘못된 상태 판정은 가능하다. 그래서 자동 만료 처리 쿼리는 해당 복원 트랜잭션과 동시에 실행될 수 없게 해야 한다.

최소 권고는 다음이다.

- 가능하면 경우 A를 택해 lease를 제거
- 경우 B라면 `lease_expires_at`만 사용
- 자동 재선점 없음
- `execution_token`, `heartbeat_at`, `attempt_no`, `RECOVERY_REQUIRED` 없음
- 목적지가 있으면 자동 전이하지 않고 수동 조사
- 목적지가 없고 원자적 DB 작업·외부 부작용 없음이 구조적으로 보장될 때만 `FAILED(LEASE_EXPIRED)`

---

## 4. billing 트리거 모순을 유도로 바꾸는 방식

제안한 방식이 맞다.

함수 단위 선언은 “이 함수의 의미”를 담고, 실제 도달 가능성과 최종 처리는 trigger catalog 인스턴스에서 유도하면 된다.

```text
FunctionPolicy
  audit_row_change
    semantic: USER_ACTIVITY_AUDIT
    defaultHandling: SUPPRESS

  trg_billing_invoice_payment_status
    semantic: DERIVED_BILLING_STATE
    defaultHandling: MUST_RUN_TARGET_EXCLUDED
```

그 후 다음 입력으로 실제 계획을 만든다.

```text
(mode, source table, event, function)
+ mode별 포함/제외 테이블
+ 실행기가 그 테이블에 수행하는 INSERT/UPDATE/DELETE
+ 함수 정책
```

예를 들어:

```text
CLONE
billing_payments
INSERT
trg_billing_invoice_payment_status
```

`billing_payments`가 CLONE 제외이므로 결과는 `NOT_REACHED`다.

이 구조의 장점은 34줄을 58줄로 손 복제하지 않는다는 데 있다. 58개 결과는 카탈로그에서 자동 생성되는 실행 산출물이어야 한다.

다만 함수 단위 선언만으로 부족한 예외는 허용해야 한다. 같은 함수라도 다음에 따라 의미가 달라질 수 있기 때문이다.

- `TG_ARGV`
- source table
- event
- BEFORE/AFTER
- 대상 테이블 포함 여부

따라서 구조는 `function default + instance override`가 가장 안전하다. 현재 `audit_row_change`처럼 일관된 것은 override가 필요 없고, 예외가 생길 때만 구체적인 `(table, event, function)` override를 둔다.

---

## 5. 한 번에 하나씩 배포 가능한 순서

### 1. 우선순위 없는 정책 컴파일러

- 후보 전수 수집
- 암묵적 fallback 제거
- 카탈로그 기반 일반 `COPY`
- 구조적 동등성 검사
- 복수 `sources`
- 1,826개 전수 invariant 테스트

DB 변경 없음. 단독 배포 가능하다.

### 2. typed input 및 구조 검증

- 타입, nullability, required/default/generated 검증
- 필수 테이블 존재 검증
- 중첩 자식 배열 검증
- 부모-자식 소속 보존
- row count 생성

1번과 논리적으로 독립이다. 다만 실행기는 1·2 모두를 전제로 해야 한다.

### 3. 트리거 실행 계획 유도

- 함수 단위 의미 선언 유지
- 카탈로그 58개 인스턴스 자동 확장
- 모드별 테이블 포함 여부와 event 도달 가능성 계산
- `NOT_REACHED` 자동 유도
- 미분류 trigger instance 빌드 실패

아직 DB 변경 없이 배포 가능하다.

### 4. 실행 계약 결합

이 단계는 1라운드 CRITICAL이라 빠지면 안 된다.

- plan ID
- content SHA-256
- schema fingerprint
- registration/requester
- row counts
- compiled column plan
- trigger execution plan
- plan version/hash

실행기가 “검토된 바로 그 입력과 계획”만 소비하게 한다.

### 5. 상태 모델 최소화 결정

먼저 같은 트랜잭션 모델을 확정한다.

- 같은 트랜잭션이면 lease 추가하지 않음
- 선점 선커밋이 불가피하면 `lease_expires_at`만 추가하는 새 마이그레이션

마이그레이션 승인이 필요한 첫 지점이다.

### 6. 감사 트리거 억제 마이그레이션

- `audit_row_change()`에 transaction-local early return 추가
- 기존 일반 쓰기 회귀 테스트
- restore setting이 있을 때 감사 INSERT가 생기지 않는 테스트
- tenant guard가 계속 동작하는 통합 테스트

실행기와 같은 릴리스에 넣되 실행기보다 먼저 적용한다.

### 7. 실행기를 잠긴 상태로 배포

- `RESTORE_ENGINE_STATUS='blocked'` 유지
- 실제 plan/hash 재검증
- 단일 트랜잭션
- `SET LOCAL ventago.restore_mode='on'`
- 선택된 트리거 계획과 실제 카탈로그 대조
- 실패 시 전체 rollback

### 8. 운영 검증 후 잠금 해제

정책 컴파일러와 typed input은 서로 독립이다. 하지만 실행 계약은 둘의 산출물을 묶으므로 1·2 이후여야 한다. 트리거 함수 변경은 실행기보다 먼저 존재해야 한다.

---

## 6. 내가 1라운드에서 놓친 것

명확히 세 가지다.

### 첫째: 다중 주장 컬럼 수

내가 `DEFERRED_FK_COLUMNS`와 FK 카탈로그의 중복을 후보로 세지 않았다.

정정:

```text
다중 주장: 12
DEFERRED + FK: 10
RESET + UNLINK: 1
RESET + FK: 1
서로 다른 결과: 0
```

“정확히 두 개”라는 표현은 틀렸다. 결론만 우연히 유지됐다.

### 둘째: 테넌트 트리거 수

현재 카탈로그 58행을 다시 세면:

```text
전체 trigger instance: 58
고유 함수: 22
tenant_chk_* instance: 35
audit_row_change instance: 7
```

따라서 내가 인용한 “34개 테넌트 가드”도 하나 부족하다. 파일 상단 주석의 34를 검산 없이 받아썼다.

더구나 trigger catalog 자체의 머리말에는 “24개”라고 적혀 있어, 현재 저장소 안에 `24`, `34`, 실측 `35`가 동시에 존재한다. 숫자를 주석에 고정하지 말고 테스트에서 계산해 출력하는 편이 맞다.

### 셋째: 운영 실측 숫자의 증거 수준

`5,652행`, `151행`, `97%`는 코드 주석에 기록된 운영 실측값을 인용한 것이지, 내가 운영 DB에서 독립 재현한 값이 아니다. 나는 운영 DB 접속이 금지되어 있다.

따라서 1라운드에서는 다음처럼 표시했어야 정확했다.

> 저장소에 기록된 매장 9 실측 기준 5,652행 대 151행이며, 운영 재확인은 필요하다.

수치 자체가 틀렸다는 증거는 없지만, 내가 직접 검증한 사실처럼 쓴 것은 잘못이다.

추가로 현재 작업 트리에는 `ResolvedColumn.source`를 `sources`로 바꾸기 시작했지만 `at()`이 아직 `source`를 반환하는 중간 상태가 보인다. 이는 1라운드 당시 결함이 아니라 후속 편집 중인 상태로 보이지만, 다음 커밋 전 타입 검사에서 반드시 정리돼야 한다.

최종적으로 1라운드의 방향은 유지하되, **lease 요구는 축소**하고, **기본 COPY는 카탈로그 생성 후보로 명시화**하며, **트리거 선언은 함수 단위·실행 결과는 인스턴스 단위 유도**로 정리하는 것이 가장 작은 안전 설계다.
CODEX_EXIT=0
