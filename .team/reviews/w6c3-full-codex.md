codex
## 결론

**지금 구조를 버릴 필요는 없다.** 선언을 근거별로 나누고 하나의 실행 계획으로 합치는 방향은 맞다.

하지만 **현재 `RestorePlan`을 실행기 계약으로 간주해서는 안 된다.** 지금은 “정책을 설명하는 컴파일 결과”이지, 재현 가능하고 복구 가능한 실행 명세가 아니다. 실행기를 붙이기 전에 다음 네 가지는 반드시 구조적으로 보강해야 한다.

1. 우선순위 해석을 없애고, 다중 주장 시 기본적으로 빌드 실패
2. 입력의 타입·필수 컬럼·중첩 자식 소속 검증
3. 트리거의 실제 집행 계획과 선택적 억제 메커니즘
4. `EXECUTING` lease/heartbeat와 크래시 복구 규약

현재 잠금은 그대로 유지하는 것이 맞다.

---

# 주요 발견

[CRITICAL] [store-restore-plan.ts](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/store/store-restore-plan.ts:351) — 실행기가 소비할 계획에 입력·목적지·스키마·트리거가 결합되어 있지 않다

문제: `RestorePlan`에는 `mode`, 테이블, 제약 정책, 공지만 있다. 어떤 업로드 바이트, 어떤 스키마 버전, 어떤 가입 신청, 어떤 행 집합을 검토한 계획인지 타입상 증명할 수 없다.

근거:

```ts
export interface RestorePlan {
  mode: RestoreMode;
  tables: TableRestorePlan[];
  excludedTables: { table: string; why: string }[];
  constraintPolicies: ConstraintPolicy[];
  notices: string[];
}
```

DB 테이블에는 이미 `id`, `content_sha256`, `registration_id`, `schema_fingerprint`, `expires_at`, 실패 정보가 있다. 따라서 “전부 없는 것”은 아니다. 문제는 이 정보와 `RestorePlan`이 하나의 불변 실행 계약으로 결합되지 않았다는 것이다.

수정: 실행 전용 스냅샷을 별도로 만든다.

```ts
interface ExecutableRestorePlan {
  planVersion: number;
  planId: string;
  mode: 'CLONE';
  contentSha256: string;
  schemaFingerprint: string;
  registrationId: number;
  requestedByUserId: number;
  expiresAt: string;
  rowCounts: Record<string, number>;
  tablePlans: TableRestorePlan[];
  triggerPlan: TriggerExecutionPlan;
  scopeProofs: ScopeProof[];
  constraintPolicies: ConstraintPolicy[];
}
```

DB에 전체 계획 JSON을 저장하거나, 실행 시 동일 파일·동일 해시·동일 스키마로 재생성한 뒤 저장된 계획 해시와 일치하는 경우만 실행해야 한다.

---

[CRITICAL] [store-restore-triggers.ts](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/store/store-restore-triggers.ts:24) — 트리거 분류는 있지만 선택적 억제를 집행할 방법이 정의되지 않았다

문제: `audit_row_change`만 억제하면서 34개 테넌트 가드는 계속 실행해야 한다. PostgreSQL의 일반적인 `session_replication_role` 또는 테이블 단위 trigger disable은 보호 트리거까지 끌 수 있다.

근거:

```ts
audit_row_change: { handling: 'SUPPRESS', ... }
tenant_chk_child_parent_same_store: { handling: 'MUST_RUN', ... }
```

현재 `RestorePlan`에는 트리거 계획 자체가 없다. 실행기가 임의 방식으로 `SUPPRESS`를 구현하면 가장 중요한 DB 방어선을 같이 비활성화할 가능성이 있다.

수정: 실행기 전에 억제 방식부터 확정해야 한다. 권장 방식은 `audit_row_change()` 내부에서 트랜잭션 로컬 설정값을 확인하는 것이다.

```sql
SET LOCAL app.restore_mode = 'on';
```

감사 트리거만 이 설정을 보고 return하고, 테넌트 가드는 그대로 실행한다. 이를 위한 함수 변경은 새 마이그레이션으로 해야 한다. 또한 실제 트리거 58개를 테이블·이벤트별 `TriggerExecutionPlan`으로 계획에 포함해야 한다.

---

[HIGH] [store-restore-input.ts](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/store/store-restore-input.ts:289) — 중첩 판매 자식의 형식과 부모 소속이 검증되지 않는다

문제 1: `items` 같은 자식 키가 배열이 아니면 판매 행 정규화에서는 무조건 건너뛰고, 수집 단계에서도 조용히 무시한다. 데이터 유실인데 거부가 발생하지 않는다.

문제 2: 평탄화하면서 어느 부모 판매 안에 있던 자식인지 잃는다. 이후 자식의 업로드 `sale_id`만 신뢰하면:

- 원본 부모와 다른 판매로 붙일 수 있음
- `sale_id` 누락 또는 타입 오류를 늦게 발견함
- 같은 원본 ID가 잘못 중복되면 부모-자식 대응이 모호함

근거:

```ts
if (table === 'sales' && SALE_CHILD_KEYS[k]) continue;
```

그리고:

```ts
if (Array.isArray(child)) {
  for (const row of child as unknown[]) collected.push(row);
}
```

배열이 아닌 자식에 대한 rejection이 없고, `collected`에는 부모 정보가 없다.

수정: 중첩 자식은 수집하면서 부모의 정규화된 원본 ID를 강제로 주입해야 한다.

```ts
{
  row: normalizedChild,
  sourceParent: {
    table: 'sales',
    sourceId: normalizedSale.id,
  }
}
```

자식이 자체 `sale_id`도 제공한다면 부모 ID와 일치해야 한다. 다르면 `CHILD_PARENT_MISMATCH`, 배열이 아니면 `NESTED_CHILD_NOT_ARRAY`로 거부한다.

---

[HIGH] [store-restore-input.ts](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/store/store-restore-input.ts:204) — 컬럼 이름만 검증하고 값 계약을 검증하지 않는다

문제: 현재 허용목록은 `{컬럼 이름}`만 제한한다. 다음 값들도 통과한다.

- 숫자 ID 자리에 객체·배열·부동소수·범위 초과 정수
- `NOT NULL` 컬럼의 `null`
- boolean 자리에 문자열
- 잘못된 timestamp
- JSON이 아닌 형태가 필요한 컬럼
- 필수 컬럼 누락

실행기가 DB 캐스트에 맡기면 실패 위치가 행 중간까지 늦어지고, 일부 값은 PostgreSQL의 암시적 변환으로 예상치 않게 받아들여질 수 있다.

수정: 카탈로그를 `type/notNull`만이 아니라 default/generated/identity 정보까지 확장하고, 정규화 단계에서 행별 타입·nullability·필수성 검사를 끝내야 한다. 특히 모든 원본 ID와 FK는 `Number.isSafeInteger(value) && value > 0` 또는 명시된 UUID 규칙을 강제해야 한다.

---

[HIGH] [store-restore-input.ts](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/store/store-restore-input.ts:248) — 필수 테이블이 파일에 실제로 존재하는지 검증하지 않는다

문제: 주석은 “없음과 빈 배열을 구분한다”고 하지만, 최종적으로 누락 테이블을 거부하지 않는다. 허용된 일부 키만 가진 부분 백업도 `rejections=[]`이 될 수 있다.

수정: 계획 생성 전에 세 집합을 정확히 비교해야 한다.

- 기대되는 포함 테이블
- 명시적으로 제외한 테이블
- 업로드에 실제로 존재한 테이블

누락은 `MISSING_TABLE`, 제외 테이블이 들어오면 `EXCLUDED_TABLE_PRESENT`로 거부한다. 행 수 0은 정상적인 “존재하지만 비어 있음”으로 유지한다.

---

[HIGH] [store-restore-plan-state.ts](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/store/store-restore-plan-state.ts:36) — `EXECUTING`은 terminal도 아니고 복구 가능한 상태도 아니다

문제: 현재 프로세스가 죽으면 영구 `EXECUTING`이 된다. 이는 fail-closed이기는 하지만 안전한 상태 기계라기보다 영구 운영 장애 상태다.

수정: `EXECUTING → PLANNED`를 사람이 직접 허용해서는 안 된다. 대신 lease 기반 선점이 필요하다.

필수 필드:

- `execution_token`
- `claimed_at`
- `lease_expires_at`
- `heartbeat_at`
- `attempt_no`

복구자는 lease 만료 후 다음을 확인한다.

1. 목적지 매장 또는 복원 감사 레코드가 존재하면 재실행 금지
2. DB 작업이 단일 트랜잭션이고 외부 부작용이 없었음이 증명되면 새 token으로 재선점
3. 결과가 불명확하면 `RECOVERY_REQUIRED` 같은 별도 상태로 보내 수동 조정

`FAILED → PLANNED` 금지는 유지해야 한다. stale `EXECUTING` 복구는 일반 재시도와 다른 전이여야 한다.

---

[MEDIUM] [store-restore-plan.spec.ts](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/store/store-restore-plan.spec.ts:126) — “충돌 시 빌드 실패”가 아니라 알려진 충돌을 허용목록으로 유지한다

현재 실제 다중 주장은 두 개다.

1. `branch_agents.socket_id`: 운영 상태 + unlinked
2. `restaurant_tables.current_sale_id`: 운영 상태 + FK

둘 다 최종적으로 `null`이라는 같은 결과다. 즉 이 둘에 우선순위는 필요하지 않다.

수정:

- `resolveColumn()`이 후보 action들을 먼저 모두 수집
- 후보가 0개면 `COPY`
- 후보가 1개면 채택
- 후보가 2개 이상이면 action의 구조적 동등성을 확인
- 동일 action이면 여러 근거를 함께 보존
- 다르면 빌드 실패

```ts
source: string
```

대신:

```ts
sources: readonly PolicySource[]
```

로 바꾸는 편이 정확하다.

따라서 `GENERATED_ID → timestamp → ...` 같은 절차적 우선순위는 제거하는 것이 좋다. 특히 `id`와 timestamp도 선언 카탈로그와 충돌 여부를 동일한 후보 수집 과정에서 검사해야 한다.

---

[MEDIUM] [store-restore-plan.ts](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/store/store-restore-plan.ts:204) — 컬럼명이 `id`라는 이유만으로 시퀀스 PK라고 판단한다

문제:

```ts
if (entry.column === 'id') {
  return { kind: 'GENERATED_ID' };
}
```

컬럼 카탈로그에는 PK 여부, identity/sequence/default 정보가 없다. 현재 스키마에서 우연히 전부 맞더라도 스키마 변경 시 일반 `id` 컬럼이나 서버 생성 UUID가 추가되면 잘못 처리한다.

수정: PK·default·identity 정보를 카탈로그 스냅샷에 포함하고 그 사실에서 `GENERATED_ID`를 유도해야 한다. UUID 서버 생성과 sequence 생성도 action을 구분하는 편이 안전하다.

---

[MEDIUM] [store-restore-triggers.ts](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/store/store-restore-triggers.ts:131) — billing trigger 선언이 CLONE 포함 정책과 모순된다

`billing_invoices`, `billing_payments`, `billing_payment_submissions`는 모두 CLONE 제외다. 그런데 `trg_billing_invoice_payment_status`는 `MUST_RUN_TARGET_EXCLUDED`로 되어 있다.

CLONE에서는 발화원인 payment 자체가 삽입되지 않으므로 실제 결론은 `NOT_REACHED`여야 한다. 현재 테스트는 함수가 실재하는지만 보고, 해당 모드에서 source table이 포함되는지는 검사하지 않는다.

수정: 트리거 처리를 전역 함수 단위가 아니라 최소한 `(mode, table, event, function)` 기준의 유도 결과로 만들고, 제외된 source table의 트리거는 `NOT_REACHED`로 계산해야 한다.

---

# 8개 질문에 대한 답

## 1. 여섯 파일 분리는 옳은가?

**옳다. 유지하라.** 근거의 권위가 다르다.

- FK: FK 카탈로그
- unlinked reference: 도메인 판정
- UNIQUE: 제약/인덱스 카탈로그
- 운영 상태: 런타임 의미
- 트리거: 트리거 카탈로그
- 입력 키: 백업 직렬화 형식

잘못된 부분은 분리가 아니라 **합성 방식**이다. 지금처럼 우선순위가 하나를 “이기게” 하면 패배한 선언이 남는다.

새 절단선은 다음이 적절하다.

1. `RowInclusionPolicy`
2. `ColumnTransformPolicy`
3. `ConstraintValidationPolicy`
4. `TriggerExecutionPolicy`
5. `ExecutionBinding`
6. `RecoveryPolicy`

그리고 마지막에 `compileRestorePlan()`이 후보를 모아 모순을 거부하도록 한다.

## 2. `resolveColumn()` 우선순위는 방어 가능한가?

장기적으로는 방어하기 어렵다.

현재 검사상 다중 주장 컬럼은 정확히 두 개이며, 둘 다 같은 결과다. 따라서 **결과를 바꾸는 합법적 우선순위 쌍은 현재 0개**다.

`restaurant_tables.current_sale_id`도 양쪽이 `null`이므로 action 우선순위가 필요한 것이 아니라, “운영 상태 묶음에서 나온 추가 근거”가 필요한 것이다.

결론: **“겹치면 기본 실패, 구조적으로 같은 action만 복수 근거로 허용”으로 바꾸는 것이 낫다.**

## 3. 아직 남은 모순은?

확인된 것은 다음이다.

- billing payment trigger가 CLONE에서는 도달 불가능한데 `MUST_RUN_TARGET_EXCLUDED`
- `source: string`은 동일 action의 복수 근거를 표현하지 못함
- `id` 생성 정책이 PK 카탈로그가 아니라 이름에 의존
- timestamp COPY가 다른 후보보다 먼저 반환되어, 향후 운영 상태 선언과 충돌해도 현 충돌 검사 범위 밖에서 조용히 이길 수 있음
- “테이블 존재를 보존한다”는 입력 주석과 실제 누락 허용 동작이 불일치
- 중첩 자식은 잘못된 형식이어도 조용히 버림

추가로 반드시 세어야 할 전수 조건:

- 포함 테이블의 모든 NOT NULL/no-default 컬럼이 `COPY/RESET/REMAP/REGENERATE/SERVER_IDENTITY` 중 하나로 공급되는가
- 모든 `GENERATED_ID`가 실제 PK + 서버 default/identity인가
- 모든 `REMAP target`에 ID 원장이 생성되는가
- 모든 FK `refColumn`이 실제 ID 원장의 key 형식과 일치하는가
- 제외 테이블을 참조하는 포함 테이블의 FK가 하나도 남지 않는가
- row filter로 부모를 뺄 때 포함된 자식이 고아가 되지 않는가
- 트리거의 쓰기 대상과 복원 포함 테이블이 이중 반영되지 않는가
- constraint policy가 실제 변환 후의 모든 UNIQUE 인덱스를 다루는가

## 4. 실행기 전에 계획에 무엇이 반드시 필요한가?

DB에 이미 있는 항목과 아직 없는 항목을 구분해야 한다.

이미 DB에 있음:

- planId
- 만료
- content SHA-256
- registration ID
- destination store ID
- schema fingerprint
- failure code/message
- summary JSON

실행기 전에 반드시 결합되어야 함:

- content hash
- schema fingerprint
- registration ID 및 서버 정체성 값
- 예상/실제 테이블별 행 수
- 트리거 집행 계획
- OWNER_GROUP scope 증명 결과 또는 재검증 명령
- 전체 실행 계획의 version/hash
- 감사 레코드 규약
- 구조화된 영향 요약
- 실패 코드 taxonomy
- 만료와 actor binding

실행기와 함께 성장해도 되는 것:

- 사람이 보는 메시지 표현
- 통계성 세부 지표
- 예상 소요 시간
- UI용 상세 설명

즉 전부가 같은 시점에 완성될 필요는 없지만, **실행 결과의 안전성·재현성·책임 추적에 관여하는 필드는 실행기보다 먼저** 있어야 한다.

## 5. 입력 검증기의 세 질문

### (가) `DERIVED_ROW_KEYS` 폐기

현재 네 항목은 실제 VIRTUAL이고 원본 테이블이 따로 있으므로 버리는 판단은 방어 가능하다.

다만 “모델에 VIRTUAL이다”만으로는 충분하지 않다. 반드시 다음도 증명해야 한다.

- 복원 대상 원본 테이블/컬럼에서 재생성 가능
- 이 값만이 가진 정보가 없음
- VIRTUAL getter가 외부 상태를 읽지 않음

그리고 버린 수량을 계획 요약에 기록해야 한다.

### (나) 타입 미검증

위험하다. 실행기 전에 반드시 추가해야 한다. 특히 ID/FK, nullability, boolean, timestamps, enum, numeric precision을 DB INSERT 전에 검증해야 한다.

### (다) 중첩 sales 평탄화

현재 방식은 불충분하다. 부모 컨텍스트를 보존하고 자식 `sale_id`를 부모 원본 ID로 강제해야 한다. 업로드 자식 값과 부모가 다르면 거부해야 한다.

## 6. 상태 기계의 구멍

구멍이 맞다. 영구 `EXECUTING`은 fail-closed이지만 운영 가능한 설계는 아니다.

- `FAILED → PLANNED` 금지: 옳음
- stale `EXECUTING`의 무조건 재시도: 위험
- lease + heartbeat + 결과 조정 후 재선점: 필요

복원 DB 변경은 반드시 하나의 트랜잭션이어야 하고, 그 트랜잭션 안에서 HTTP/MinIO/소켓 등 외부 I/O를 하면 안 된다. 파일 검증과 로드는 선점 전에 끝내고, 감사 성공 기록까지 DB 트랜잭션 경계 안에서 정합성을 맞춰야 한다.

## 7. 첫 실제 CLONE에서 가장 먼저 깨질 자리

가장 먼저 구현 단계에서 막힐 곳은 **트리거 억제**다. `audit_row_change`만 끄고 테넌트 가드는 유지하는 일반적인 세션 스위치가 현재 없다.

그것을 임시로 무시하고 실행하면 다음 순서가 유력하다.

1. 타입/필수 컬럼 미검증으로 첫 INSERT 또는 cast 실패
2. 중첩 sales 자식의 `sale_id` 매핑·부모 대응 오류
3. GENERATED_ID 원장 누락 또는 target별 원장 불완전
4. 트리거가 백업 값을 덮어쓰거나 감사 로그 대량 생성
5. 제외/row-filter 부모 때문에 자식 REMAP 실패
6. 크래시 후 영구 `EXECUTING`

따라서 “실행기를 붙이면 데이터 중간에서 처음 죽을 자리”는 입력 형태에 따라 달라지지만, **설계상 첫 확정 블로커는 트리거 집행 메커니즘 부재**다.

## 8. 놓친 것

가장 큰 누락은 네 가지다.

- 계획 자체의 버전과 해시: 코드 배포 사이에 같은 DB 계획을 다른 정책으로 해석하면 안 됨
- row provenance: 각 정규화 행이 업로드의 어느 위치에서 왔는지 보존해야 실패를 정확히 보고하고 부모 소속을 증명할 수 있음
- ID 원장 완전성 계약: 테이블별 예상 source ID 수, 생성된 mapping 수, 중복 source ID, 미사용 mapping을 커밋 전에 비교해야 함
- 복원 후 불변식 검사의 구체적 목록: 단순히 “테넌트 검사”가 아니라 쿼리 ID, 기대값 0, 실패 코드가 계획에 있어야 함

최종 판단은 다음과 같다.

> **현재 구조를 버리지 마라. 하지만 현재 계획 위에 실행기를 바로 짓지도 마라.**  
> 우선순위 없는 정책 컴파일러, 엄격한 typed input, 선택적 트리거 집행, lease 기반 상태 기계를 먼저 완성한 뒤 실행기를 연결해야 한다. `RESTORE_ENGINE_STATUS='blocked'`는 그때까지 유지하는 것이 맞다.
hook: Stop
hook: Stop
hook: Stop Failed
hook: Stop Completed
tokens used
80,672
## 결론

**지금 구조를 버릴 필요는 없다.** 선언을 근거별로 나누고 하나의 실행 계획으로 합치는 방향은 맞다.

하지만 **현재 `RestorePlan`을 실행기 계약으로 간주해서는 안 된다.** 지금은 “정책을 설명하는 컴파일 결과”이지, 재현 가능하고 복구 가능한 실행 명세가 아니다. 실행기를 붙이기 전에 다음 네 가지는 반드시 구조적으로 보강해야 한다.

1. 우선순위 해석을 없애고, 다중 주장 시 기본적으로 빌드 실패
2. 입력의 타입·필수 컬럼·중첩 자식 소속 검증
3. 트리거의 실제 집행 계획과 선택적 억제 메커니즘
4. `EXECUTING` lease/heartbeat와 크래시 복구 규약

현재 잠금은 그대로 유지하는 것이 맞다.

---

# 주요 발견

[CRITICAL] [store-restore-plan.ts](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/store/store-restore-plan.ts:351) — 실행기가 소비할 계획에 입력·목적지·스키마·트리거가 결합되어 있지 않다

문제: `RestorePlan`에는 `mode`, 테이블, 제약 정책, 공지만 있다. 어떤 업로드 바이트, 어떤 스키마 버전, 어떤 가입 신청, 어떤 행 집합을 검토한 계획인지 타입상 증명할 수 없다.

근거:

```ts
export interface RestorePlan {
  mode: RestoreMode;
  tables: TableRestorePlan[];
  excludedTables: { table: string; why: string }[];
  constraintPolicies: ConstraintPolicy[];
  notices: string[];
}
```

DB 테이블에는 이미 `id`, `content_sha256`, `registration_id`, `schema_fingerprint`, `expires_at`, 실패 정보가 있다. 따라서 “전부 없는 것”은 아니다. 문제는 이 정보와 `RestorePlan`이 하나의 불변 실행 계약으로 결합되지 않았다는 것이다.

수정: 실행 전용 스냅샷을 별도로 만든다.

```ts
interface ExecutableRestorePlan {
  planVersion: number;
  planId: string;
  mode: 'CLONE';
  contentSha256: string;
  schemaFingerprint: string;
  registrationId: number;
  requestedByUserId: number;
  expiresAt: string;
  rowCounts: Record<string, number>;
  tablePlans: TableRestorePlan[];
  triggerPlan: TriggerExecutionPlan;
  scopeProofs: ScopeProof[];
  constraintPolicies: ConstraintPolicy[];
}
```

DB에 전체 계획 JSON을 저장하거나, 실행 시 동일 파일·동일 해시·동일 스키마로 재생성한 뒤 저장된 계획 해시와 일치하는 경우만 실행해야 한다.

---

[CRITICAL] [store-restore-triggers.ts](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/store/store-restore-triggers.ts:24) — 트리거 분류는 있지만 선택적 억제를 집행할 방법이 정의되지 않았다

문제: `audit_row_change`만 억제하면서 34개 테넌트 가드는 계속 실행해야 한다. PostgreSQL의 일반적인 `session_replication_role` 또는 테이블 단위 trigger disable은 보호 트리거까지 끌 수 있다.

근거:

```ts
audit_row_change: { handling: 'SUPPRESS', ... }
tenant_chk_child_parent_same_store: { handling: 'MUST_RUN', ... }
```

현재 `RestorePlan`에는 트리거 계획 자체가 없다. 실행기가 임의 방식으로 `SUPPRESS`를 구현하면 가장 중요한 DB 방어선을 같이 비활성화할 가능성이 있다.

수정: 실행기 전에 억제 방식부터 확정해야 한다. 권장 방식은 `audit_row_change()` 내부에서 트랜잭션 로컬 설정값을 확인하는 것이다.

```sql
SET LOCAL app.restore_mode = 'on';
```

감사 트리거만 이 설정을 보고 return하고, 테넌트 가드는 그대로 실행한다. 이를 위한 함수 변경은 새 마이그레이션으로 해야 한다. 또한 실제 트리거 58개를 테이블·이벤트별 `TriggerExecutionPlan`으로 계획에 포함해야 한다.

---

[HIGH] [store-restore-input.ts](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/store/store-restore-input.ts:289) — 중첩 판매 자식의 형식과 부모 소속이 검증되지 않는다

문제 1: `items` 같은 자식 키가 배열이 아니면 판매 행 정규화에서는 무조건 건너뛰고, 수집 단계에서도 조용히 무시한다. 데이터 유실인데 거부가 발생하지 않는다.

문제 2: 평탄화하면서 어느 부모 판매 안에 있던 자식인지 잃는다. 이후 자식의 업로드 `sale_id`만 신뢰하면:

- 원본 부모와 다른 판매로 붙일 수 있음
- `sale_id` 누락 또는 타입 오류를 늦게 발견함
- 같은 원본 ID가 잘못 중복되면 부모-자식 대응이 모호함

근거:

```ts
if (table === 'sales' && SALE_CHILD_KEYS[k]) continue;
```

그리고:

```ts
if (Array.isArray(child)) {
  for (const row of child as unknown[]) collected.push(row);
}
```

배열이 아닌 자식에 대한 rejection이 없고, `collected`에는 부모 정보가 없다.

수정: 중첩 자식은 수집하면서 부모의 정규화된 원본 ID를 강제로 주입해야 한다.

```ts
{
  row: normalizedChild,
  sourceParent: {
    table: 'sales',
    sourceId: normalizedSale.id,
  }
}
```

자식이 자체 `sale_id`도 제공한다면 부모 ID와 일치해야 한다. 다르면 `CHILD_PARENT_MISMATCH`, 배열이 아니면 `NESTED_CHILD_NOT_ARRAY`로 거부한다.

---

[HIGH] [store-restore-input.ts](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/store/store-restore-input.ts:204) — 컬럼 이름만 검증하고 값 계약을 검증하지 않는다

문제: 현재 허용목록은 `{컬럼 이름}`만 제한한다. 다음 값들도 통과한다.

- 숫자 ID 자리에 객체·배열·부동소수·범위 초과 정수
- `NOT NULL` 컬럼의 `null`
- boolean 자리에 문자열
- 잘못된 timestamp
- JSON이 아닌 형태가 필요한 컬럼
- 필수 컬럼 누락

실행기가 DB 캐스트에 맡기면 실패 위치가 행 중간까지 늦어지고, 일부 값은 PostgreSQL의 암시적 변환으로 예상치 않게 받아들여질 수 있다.

수정: 카탈로그를 `type/notNull`만이 아니라 default/generated/identity 정보까지 확장하고, 정규화 단계에서 행별 타입·nullability·필수성 검사를 끝내야 한다. 특히 모든 원본 ID와 FK는 `Number.isSafeInteger(value) && value > 0` 또는 명시된 UUID 규칙을 강제해야 한다.

---

[HIGH] [store-restore-input.ts](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/store/store-restore-input.ts:248) — 필수 테이블이 파일에 실제로 존재하는지 검증하지 않는다

문제: 주석은 “없음과 빈 배열을 구분한다”고 하지만, 최종적으로 누락 테이블을 거부하지 않는다. 허용된 일부 키만 가진 부분 백업도 `rejections=[]`이 될 수 있다.

수정: 계획 생성 전에 세 집합을 정확히 비교해야 한다.

- 기대되는 포함 테이블
- 명시적으로 제외한 테이블
- 업로드에 실제로 존재한 테이블

누락은 `MISSING_TABLE`, 제외 테이블이 들어오면 `EXCLUDED_TABLE_PRESENT`로 거부한다. 행 수 0은 정상적인 “존재하지만 비어 있음”으로 유지한다.

---

[HIGH] [store-restore-plan-state.ts](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/store/store-restore-plan-state.ts:36) — `EXECUTING`은 terminal도 아니고 복구 가능한 상태도 아니다

문제: 현재 프로세스가 죽으면 영구 `EXECUTING`이 된다. 이는 fail-closed이기는 하지만 안전한 상태 기계라기보다 영구 운영 장애 상태다.

수정: `EXECUTING → PLANNED`를 사람이 직접 허용해서는 안 된다. 대신 lease 기반 선점이 필요하다.

필수 필드:

- `execution_token`
- `claimed_at`
- `lease_expires_at`
- `heartbeat_at`
- `attempt_no`

복구자는 lease 만료 후 다음을 확인한다.

1. 목적지 매장 또는 복원 감사 레코드가 존재하면 재실행 금지
2. DB 작업이 단일 트랜잭션이고 외부 부작용이 없었음이 증명되면 새 token으로 재선점
3. 결과가 불명확하면 `RECOVERY_REQUIRED` 같은 별도 상태로 보내 수동 조정

`FAILED → PLANNED` 금지는 유지해야 한다. stale `EXECUTING` 복구는 일반 재시도와 다른 전이여야 한다.

---

[MEDIUM] [store-restore-plan.spec.ts](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/store/store-restore-plan.spec.ts:126) — “충돌 시 빌드 실패”가 아니라 알려진 충돌을 허용목록으로 유지한다

현재 실제 다중 주장은 두 개다.

1. `branch_agents.socket_id`: 운영 상태 + unlinked
2. `restaurant_tables.current_sale_id`: 운영 상태 + FK

둘 다 최종적으로 `null`이라는 같은 결과다. 즉 이 둘에 우선순위는 필요하지 않다.

수정:

- `resolveColumn()`이 후보 action들을 먼저 모두 수집
- 후보가 0개면 `COPY`
- 후보가 1개면 채택
- 후보가 2개 이상이면 action의 구조적 동등성을 확인
- 동일 action이면 여러 근거를 함께 보존
- 다르면 빌드 실패

```ts
source: string
```

대신:

```ts
sources: readonly PolicySource[]
```

로 바꾸는 편이 정확하다.

따라서 `GENERATED_ID → timestamp → ...` 같은 절차적 우선순위는 제거하는 것이 좋다. 특히 `id`와 timestamp도 선언 카탈로그와 충돌 여부를 동일한 후보 수집 과정에서 검사해야 한다.

---

[MEDIUM] [store-restore-plan.ts](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/store/store-restore-plan.ts:204) — 컬럼명이 `id`라는 이유만으로 시퀀스 PK라고 판단한다

문제:

```ts
if (entry.column === 'id') {
  return { kind: 'GENERATED_ID' };
}
```

컬럼 카탈로그에는 PK 여부, identity/sequence/default 정보가 없다. 현재 스키마에서 우연히 전부 맞더라도 스키마 변경 시 일반 `id` 컬럼이나 서버 생성 UUID가 추가되면 잘못 처리한다.

수정: PK·default·identity 정보를 카탈로그 스냅샷에 포함하고 그 사실에서 `GENERATED_ID`를 유도해야 한다. UUID 서버 생성과 sequence 생성도 action을 구분하는 편이 안전하다.

---

[MEDIUM] [store-restore-triggers.ts](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/store/store-restore-triggers.ts:131) — billing trigger 선언이 CLONE 포함 정책과 모순된다

`billing_invoices`, `billing_payments`, `billing_payment_submissions`는 모두 CLONE 제외다. 그런데 `trg_billing_invoice_payment_status`는 `MUST_RUN_TARGET_EXCLUDED`로 되어 있다.

CLONE에서는 발화원인 payment 자체가 삽입되지 않으므로 실제 결론은 `NOT_REACHED`여야 한다. 현재 테스트는 함수가 실재하는지만 보고, 해당 모드에서 source table이 포함되는지는 검사하지 않는다.

수정: 트리거 처리를 전역 함수 단위가 아니라 최소한 `(mode, table, event, function)` 기준의 유도 결과로 만들고, 제외된 source table의 트리거는 `NOT_REACHED`로 계산해야 한다.

---

# 8개 질문에 대한 답

## 1. 여섯 파일 분리는 옳은가?

**옳다. 유지하라.** 근거의 권위가 다르다.

- FK: FK 카탈로그
- unlinked reference: 도메인 판정
- UNIQUE: 제약/인덱스 카탈로그
- 운영 상태: 런타임 의미
- 트리거: 트리거 카탈로그
- 입력 키: 백업 직렬화 형식

잘못된 부분은 분리가 아니라 **합성 방식**이다. 지금처럼 우선순위가 하나를 “이기게” 하면 패배한 선언이 남는다.

새 절단선은 다음이 적절하다.

1. `RowInclusionPolicy`
2. `ColumnTransformPolicy`
3. `ConstraintValidationPolicy`
4. `TriggerExecutionPolicy`
5. `ExecutionBinding`
6. `RecoveryPolicy`

그리고 마지막에 `compileRestorePlan()`이 후보를 모아 모순을 거부하도록 한다.

## 2. `resolveColumn()` 우선순위는 방어 가능한가?

장기적으로는 방어하기 어렵다.

현재 검사상 다중 주장 컬럼은 정확히 두 개이며, 둘 다 같은 결과다. 따라서 **결과를 바꾸는 합법적 우선순위 쌍은 현재 0개**다.

`restaurant_tables.current_sale_id`도 양쪽이 `null`이므로 action 우선순위가 필요한 것이 아니라, “운영 상태 묶음에서 나온 추가 근거”가 필요한 것이다.

결론: **“겹치면 기본 실패, 구조적으로 같은 action만 복수 근거로 허용”으로 바꾸는 것이 낫다.**

## 3. 아직 남은 모순은?

확인된 것은 다음이다.

- billing payment trigger가 CLONE에서는 도달 불가능한데 `MUST_RUN_TARGET_EXCLUDED`
- `source: string`은 동일 action의 복수 근거를 표현하지 못함
- `id` 생성 정책이 PK 카탈로그가 아니라 이름에 의존
- timestamp COPY가 다른 후보보다 먼저 반환되어, 향후 운영 상태 선언과 충돌해도 현 충돌 검사 범위 밖에서 조용히 이길 수 있음
- “테이블 존재를 보존한다”는 입력 주석과 실제 누락 허용 동작이 불일치
- 중첩 자식은 잘못된 형식이어도 조용히 버림

추가로 반드시 세어야 할 전수 조건:

- 포함 테이블의 모든 NOT NULL/no-default 컬럼이 `COPY/RESET/REMAP/REGENERATE/SERVER_IDENTITY` 중 하나로 공급되는가
- 모든 `GENERATED_ID`가 실제 PK + 서버 default/identity인가
- 모든 `REMAP target`에 ID 원장이 생성되는가
- 모든 FK `refColumn`이 실제 ID 원장의 key 형식과 일치하는가
- 제외 테이블을 참조하는 포함 테이블의 FK가 하나도 남지 않는가
- row filter로 부모를 뺄 때 포함된 자식이 고아가 되지 않는가
- 트리거의 쓰기 대상과 복원 포함 테이블이 이중 반영되지 않는가
- constraint policy가 실제 변환 후의 모든 UNIQUE 인덱스를 다루는가

## 4. 실행기 전에 계획에 무엇이 반드시 필요한가?

DB에 이미 있는 항목과 아직 없는 항목을 구분해야 한다.

이미 DB에 있음:

- planId
- 만료
- content SHA-256
- registration ID
- destination store ID
- schema fingerprint
- failure code/message
- summary JSON

실행기 전에 반드시 결합되어야 함:

- content hash
- schema fingerprint
- registration ID 및 서버 정체성 값
- 예상/실제 테이블별 행 수
- 트리거 집행 계획
- OWNER_GROUP scope 증명 결과 또는 재검증 명령
- 전체 실행 계획의 version/hash
- 감사 레코드 규약
- 구조화된 영향 요약
- 실패 코드 taxonomy
- 만료와 actor binding

실행기와 함께 성장해도 되는 것:

- 사람이 보는 메시지 표현
- 통계성 세부 지표
- 예상 소요 시간
- UI용 상세 설명

즉 전부가 같은 시점에 완성될 필요는 없지만, **실행 결과의 안전성·재현성·책임 추적에 관여하는 필드는 실행기보다 먼저** 있어야 한다.

## 5. 입력 검증기의 세 질문

### (가) `DERIVED_ROW_KEYS` 폐기

현재 네 항목은 실제 VIRTUAL이고 원본 테이블이 따로 있으므로 버리는 판단은 방어 가능하다.

다만 “모델에 VIRTUAL이다”만으로는 충분하지 않다. 반드시 다음도 증명해야 한다.

- 복원 대상 원본 테이블/컬럼에서 재생성 가능
- 이 값만이 가진 정보가 없음
- VIRTUAL getter가 외부 상태를 읽지 않음

그리고 버린 수량을 계획 요약에 기록해야 한다.

### (나) 타입 미검증

위험하다. 실행기 전에 반드시 추가해야 한다. 특히 ID/FK, nullability, boolean, timestamps, enum, numeric precision을 DB INSERT 전에 검증해야 한다.

### (다) 중첩 sales 평탄화

현재 방식은 불충분하다. 부모 컨텍스트를 보존하고 자식 `sale_id`를 부모 원본 ID로 강제해야 한다. 업로드 자식 값과 부모가 다르면 거부해야 한다.

## 6. 상태 기계의 구멍

구멍이 맞다. 영구 `EXECUTING`은 fail-closed이지만 운영 가능한 설계는 아니다.

- `FAILED → PLANNED` 금지: 옳음
- stale `EXECUTING`의 무조건 재시도: 위험
- lease + heartbeat + 결과 조정 후 재선점: 필요

복원 DB 변경은 반드시 하나의 트랜잭션이어야 하고, 그 트랜잭션 안에서 HTTP/MinIO/소켓 등 외부 I/O를 하면 안 된다. 파일 검증과 로드는 선점 전에 끝내고, 감사 성공 기록까지 DB 트랜잭션 경계 안에서 정합성을 맞춰야 한다.

## 7. 첫 실제 CLONE에서 가장 먼저 깨질 자리

가장 먼저 구현 단계에서 막힐 곳은 **트리거 억제**다. `audit_row_change`만 끄고 테넌트 가드는 유지하는 일반적인 세션 스위치가 현재 없다.

그것을 임시로 무시하고 실행하면 다음 순서가 유력하다.

1. 타입/필수 컬럼 미검증으로 첫 INSERT 또는 cast 실패
2. 중첩 sales 자식의 `sale_id` 매핑·부모 대응 오류
3. GENERATED_ID 원장 누락 또는 target별 원장 불완전
4. 트리거가 백업 값을 덮어쓰거나 감사 로그 대량 생성
5. 제외/row-filter 부모 때문에 자식 REMAP 실패
6. 크래시 후 영구 `EXECUTING`

따라서 “실행기를 붙이면 데이터 중간에서 처음 죽을 자리”는 입력 형태에 따라 달라지지만, **설계상 첫 확정 블로커는 트리거 집행 메커니즘 부재**다.

## 8. 놓친 것

가장 큰 누락은 네 가지다.

- 계획 자체의 버전과 해시: 코드 배포 사이에 같은 DB 계획을 다른 정책으로 해석하면 안 됨
- row provenance: 각 정규화 행이 업로드의 어느 위치에서 왔는지 보존해야 실패를 정확히 보고하고 부모 소속을 증명할 수 있음
- ID 원장 완전성 계약: 테이블별 예상 source ID 수, 생성된 mapping 수, 중복 source ID, 미사용 mapping을 커밋 전에 비교해야 함
- 복원 후 불변식 검사의 구체적 목록: 단순히 “테넌트 검사”가 아니라 쿼리 ID, 기대값 0, 실패 코드가 계획에 있어야 함

최종 판단은 다음과 같다.

> **현재 구조를 버리지 마라. 하지만 현재 계획 위에 실행기를 바로 짓지도 마라.**  
> 우선순위 없는 정책 컴파일러, 엄격한 typed input, 선택적 트리거 집행, lease 기반 상태 기계를 먼저 완성한 뒤 실행기를 연결해야 한다. `RESTORE_ENGINE_STATUS='blocked'`는 그때까지 유지하는 것이 맞다.
CODEX_EXIT=0
