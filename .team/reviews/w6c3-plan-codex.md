codex
결론부터 말하면, 방향은 맞지만 이 상태로 다음 조각에 넘어가는 것은 반대합니다. 먼저 세 가지를 고쳐야 합니다.

1. UNIQUE를 컬럼 행동 우선순위에서 분리해야 합니다.
2. `audit_logs`는 CLONE 대상에서 제외해야 합니다.
3. `NEVER_FROM_BACKUP`의 `COPY` 반환을 별도 행동으로 바꿔야 합니다.

## 핵심 지적

[HIGH] [store-restore-plan.ts](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/store/store-restore-plan.ts:152) — 백업에서 절대 읽지 않는 컬럼이 `COPY`로 계획된다

문제: `id`, `created_at`, `updated_at`을 “생략 대상”이라고 선언했지만 실행기가 보는 행동은 `COPY`입니다. `ColumnAction.COPY`의 계약은 “백업 값을 그대로 넣는다”입니다. 실행기가 `source` 문자열까지 해석하지 않는 한 원본 PK·시각을 INSERT하게 됩니다.

근거:

```ts
if (NEVER_FROM_BACKUP.has(entry.column)) {
  return at({ kind: 'COPY' }, 'NEVER_FROM_BACKUP(생략 대상)');
}
```

수정: 최소한 `GENERATED_ID`와 `DB_DEFAULT` 또는 `OMIT` 행동을 별도로 만드십시오. `id`와 timestamps도 의미가 다릅니다.

- `id` → `GENERATED_ID`, 반드시 `RETURNING`과 ID 원장 연결
- `created_at`/`updated_at` → 정책을 명시적으로 선택
  - 역사 보존이면 `COPY`
  - 복제 생성시각이면 `DB_DEFAULT`
- “행동은 COPY지만 source가 생략을 뜻한다”는 이중 계약은 금지해야 합니다.

---

[HIGH] [store-restore-plan.ts](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/store/store-restore-plan.ts:245) — NOT NULL 다형 참조를 `CLEAR`로 만들기 때문에 `audit_logs` 복원이 실패한다

문제: `audit_logs.entity_id`는 `NOT NULL`인데 `POLYMORPHIC → CLEAR`입니다. 실행 시 INSERT가 실패합니다.

근거: [store-restore-columns.txt](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/store/store-restore-columns.txt:94)

```text
audit_logs.entity_id : integer NOT NULL
```

수정: `audit_logs`를 CLONE에서 통째로 제외하십시오. 이유는 단순한 NOT NULL 문제가 아닙니다.

- entity 링크를 정확히 재매핑할 수 없음
- 그대로 두면 새 매장에서 원본/무관 행을 가리킴
- 비우는 것도 불가능
- `old_values`/`new_values`에도 원본 ID·PII가 있을 수 있음
- 복제 자체가 새 감사 이벤트를 만들면 과거 감사와 새 감사가 혼재함

`audit_logs`는 원본 백업 아카이브에는 남겨도 되지만 새 매장의 운영 DB로 복제할 데이터는 아닙니다.

---

[HIGH] [store-restore-plan.spec.ts](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/store/store-restore-plan.spec.ts:65) — UNIQUE 인덱스 정책을 컬럼 행동으로 평탄화하면 FK/테넌트 변환을 덮어쓸 수 있다

문제: UNIQUE는 인덱스·식·조건 단위 정책인데 정규식으로 참여 컬럼 모두에 동일 행동을 부여합니다. 앞으로 `(store_id, external_code)` 같은 인덱스에 `REJECT`가 붙으면 `store_id`의 목적지 변환까지 REJECT가 덮어쓸 수 있습니다.

또한 한 컬럼이 여러 UNIQUE 인덱스에 참여하면 `Map.set()`의 마지막 정책이 조용히 이깁니다.

수정: 두 층으로 분리해야 합니다.

```ts
columnActions: ResolvedColumn[]
constraintPolicies: ResolvedUniquePolicy[]
```

- 컬럼 행동: `REMAP`, `DESTINATION_STORE`, `CLEAR`, `REGENERATE` 등
- 제약 정책: `PRECHECK_REJECT`, `SERVER_IDENTITY`, `REGENERATE_MEMBER`, `TENANT_SCOPED`
- UNIQUE 사전검사는 변환된 최종 튜플 전체를 대상으로 수행
- 동일 컬럼이 여러 정책에 들어가면 덮어쓰지 말고 조합 검증

## 1. 우선순위 7단계

현재 3번 UNIQUE가 5번 FK보다 앞서는 것은 반대합니다.

더 정확히는 UNIQUE와 FK 중 어느 것이 이기는지를 정하면 안 됩니다. 둘은 같은 축이 아닙니다.

- FK 정책은 “이 값이 무엇으로 변환되는가”
- UNIQUE 정책은 “변환된 결과가 제약을 충족하는가, 충돌하면 무엇을 하는가”

따라서 FK이면서 UNIQUE인 컬럼은 합법적인 공존입니다. 예를 들어 테넌트 범위 UNIQUE의 `store_id`는 반드시 목적지 매장으로 바뀌어야 하며, 그 후 복합키 충돌을 검사해야 합니다.

권장 순서는 컬럼 변환만 놓고 보면:

1. 테이블 제외/행 제외
2. 서버 정체성·생성 컬럼
3. 운영 상태 RESET
4. 자격증명 REGENERATE
5. DEFERRED
6. FK/unlinked 참조 처리
7. 일반 COPY

그 뒤 별도 단계로 UNIQUE/CHECK/NOT NULL/범위 검증을 실행하십시오.

겹치는 선언도 “우선순위로 해결”하기보다 다음 중 하나여야 합니다.

- 서로 다른 축이라 함께 적용
- 같은 축이면 동일한 정규화 결과임을 구조적으로 증명
- 그렇지 않으면 빌드 실패

## 2. `DESTINATION_STORE`

모든 진짜 테넌트 소유권 `store_id`를 `DESTINATION_STORE` 한 길로 합치는 편이 낫습니다.

FK 유무는 스키마 품질 차이일 뿐, 복원 의미는 동일합니다. `stores` 원장을 거쳐 목적지 ID를 얻도록 하면 다음 위험이 생깁니다.

- 원장 생성 순서/누락에 따라 핵심 테넌트 경계가 좌우됨
- FK 있는 테이블과 없는 테이블이 서로 다른 실행 분기를 탐
- 결과 검증도 두 종류가 필요함

권장 계약:

```ts
store_id owned by restored tenant → DESTINATION_STORE
```

그리고 실행 후에는 모든 복원 행에 대해 `store_id = destinationStoreId`를 역검증하십시오.

단, 이름만 `store_id`인 전역·플랫폼 테이블까지 무조건 적용하면 안 됩니다. “컬럼명 기반”이 아니라 소유권 매니페스트 기준이어야 합니다.

`branch_id`는 목적지 branch가 여러 개이므로 계속 `REMAP → branches`가 맞습니다.

## 3. `POLYMORPHIC → CLEAR`

반대합니다. `audit_logs`를 통째로 제외하십시오.

현재 선택지는 실제로 다음 둘뿐입니다.

- `COPY`: 다른 엔티티를 가리킬 수 있어 의미가 거짓
- `CLEAR`: NOT NULL 위반

라벨 정규화와 대상 테이블별 원장을 완성하기 전까지 행 단위 복원은 안전하지 않습니다. 감사 로그는 원본 백업 파일/복원 감사 메타데이터에서 조회하게 하고, 복제 매장 운영 데이터에는 넣지 않는 것이 맞습니다.

향후 다형 참조를 지원한다면 `POLYMORPHIC` 자체가 행동이어야 합니다. resolver가 “모름”을 임의로 `CLEAR`로 낮추면 안 됩니다.

## 4. plan에 아직 필요한 것

행 수·해시·스키마 지문 외에도 다음이 필요합니다.

- `planId`, 계획 버전, 생성시각, 만료시각
- 업로드 객체 ID와 원본 SHA-256
- 목적지 `storeId`, 가입 신청/등록 ID, owner group
- 계획 생성자와 실행 권한 주체
- 테이블별 `INCLUDE / EXCLUDE / ROW_FILTER`
- 예상 입력 행 수, 예상 INSERT 행 수, 예상 제외 행 수
- PK 생성 방식과 ID 원장 종류
- 트리거 정책: `MUST_RUN / SUPPRESS / REPLACE`
- UNIQUE 정책을 포함한 제약 단위 사전검사
- `KEEP_GLOBAL` 대상의 scope 증명 결과
- RESET/CLEAR/REGENERATE 건수
- unresolved 항목 0건 증명
- 최대 파일 크기, 테이블별/전체 행 수 상한
- 실행 당시 스키마 지문 재검증 조건
- 계획 상태 전이와 실패 코드
- 결과 감사 레코드 형식

특히 현재 계획에는 트리거 선언이 합쳐지지 않았습니다. 설명은 “네 벌을 합친다”고 하지만 실제 `RestorePlan`에는 트리거 집행 계획이 없습니다. 실행기가 별도로 트리거 파일을 다시 읽으면 “검토한 계획만 실행한다”는 원칙이 깨집니다.

## 5. 다음 조각 순서

제시한 순서에서 ②의 엔드포인트 배선은 뒤로 미루는 것이 맞습니다.

권장 순서:

1. 입력 파서와 검증기
2. 완전한 순수 plan 생성기
3. DB 계획 테이블 및 원자적 상태 전이
4. 실행기와 커밋 전 증명
5. 업로드/plan/execute 엔드포인트 배선
6. 실패 주입·재실행·동시 실행 통합 테스트
7. `clone_only` 개방

DB 계획 테이블을 먼저 만드는 것은 괜찮지만, 공개 엔드포인트를 먼저 배선하는 것은 반대합니다. 실행기 없이 upload/plan만 열어도 임시 객체 누적, 저장공간 DoS, 만료 청소, 권한 경계 같은 운영 표면이 생깁니다.

`RESTORE_ENGINE_STATUS='blocked'`는 마지막 통합 검증까지 유지해야 합니다.

## 6. 범위 질문

### 가. `box_settlements`: 포함

포함해야 합니다. 크론이 `box_settlements.settled_through`를 기준선으로 삼으므로 제외하면 복제된 과거 `cash_registers`가 전부 미정산으로 인식될 수 있습니다. 그 결과 새 정산과 금고 이체가 만들어집니다.

다만 반드시 함께 복제·검증할 것:

- `boxes`
- 관련 `cash_registers`
- `caja_fuerte_operation_id`가 가리키는 원장
- 구간 중복 exclusion constraint
- 테이블별 입력/원장/INSERT 행 수 일치

### 나. `billing_invoices`: 제외

새 매장은 원본 매장의 플랫폼 청구서·납부·AFIP 발행 사실을 물려받으면 안 됩니다. 그것은 매장 영업 이력이 아니라 플랫폼과 원본 법적/계약 주체 사이의 채권·세무 문서입니다.

`billing_invoices`만 빼지 말고 다음 종속 그래프를 함께 제외해야 합니다.

- `billing_invoices`
- `billing_payments`
- `billing_payment_submissions`
- 그 밖 invoice/payment를 부모로 갖는 테이블

필요하다면 원본 아카이브로만 보존하십시오.

### 다. `store_notices`: 제외

플랫폼이 원본 매장에 보낸 공지는 새 매장에 재전달하면 안 됩니다. 특히 `read_at IS NULL`이면 새 매장 접속 즉시 과거 공지가 현재 공지처럼 노출됩니다.

fan-out `campaign_id`도 원본 수신자 집합의 상관관계이므로 일부 행만 새 매장으로 옮기면 관리 콘솔의 발송/읽음 통계 의미까지 왜곡됩니다.

## 7. 추가로 놓친 것

- `CLEAR`/`RESET(null)`/`DEFERRED`가 NOT NULL 컬럼에 적용되는 모든 경우를 전수 검사해야 합니다. `audit_logs.entity_id`가 이미 반례입니다.
- nullable FK의 `required: false`가 “입력값이 NULL일 수 있음”인지 “매핑 실패를 허용함”인지 모호합니다. 입력값이 non-null인데 매핑이 없으면 nullable 컬럼이라도 실패해야 합니다.
- `DEFERRED_FK_COLUMNS`에 실제 FK edge가 없을 때 현재 자기 테이블로 fallback합니다. 이는 실패해야 합니다.
- “모든 컬럼이 해석된다” 검사는 기본 `COPY` 때문에 미선언 컬럼도 항상 통과합니다. 이는 완전성 검사라기보다 총함수 검사입니다. 위험군(`*_id`, 토큰/secret/key, 상태 컬럼, UNIQUE 참여 컬럼)은 기본 COPY 금지 검사가 별도로 필요합니다.
- 충돌 검사에서 `RESET` 값이 `undefined`이면 선언을 놓칩니다. `in` 또는 own-property 검사로 통일해야 합니다.
- UNIQUE 정의를 `RegExp(\bcolumn\b)`로 파싱하지 마십시오. 표현식 인덱스, quoted identifier, 함수, cast에서 오판할 수 있습니다. 카탈로그에서 인덱스 컬럼/식 구조를 별도로 추출해야 합니다.
- 계획의 `notices`는 문자열만으로는 집행 계약이 아닙니다. 구조화된 영향 요약과 별도 렌더링이 필요합니다.
- 행 제외가 필요한 `seller_attendance` 같은 `RESET_UNRESOLVED`가 하나라도 있으면 plan 생성 자체를 거부해야 합니다.
- 트리거 SUPPRESS가 세션/커넥션 설정이라면 pool 재사용 후 상태가 남지 않도록 반드시 트랜잭션 로컬 설정 또는 `finally` 복구가 필요합니다.

최종 판정은 “코어의 분리 방향은 승인, 다음 조각 진행 전 HIGH 3건 수정 필요”입니다. 특히 UNIQUE를 컬럼 행동으로 유지하는 설계와 `audit_logs CLEAR`는 그대로 진행하면 안 됩니다.
hook: Stop
hook: Stop
hook: Stop Failed
hook: Stop Completed
tokens used
122,559
결론부터 말하면, 방향은 맞지만 이 상태로 다음 조각에 넘어가는 것은 반대합니다. 먼저 세 가지를 고쳐야 합니다.

1. UNIQUE를 컬럼 행동 우선순위에서 분리해야 합니다.
2. `audit_logs`는 CLONE 대상에서 제외해야 합니다.
3. `NEVER_FROM_BACKUP`의 `COPY` 반환을 별도 행동으로 바꿔야 합니다.

## 핵심 지적

[HIGH] [store-restore-plan.ts](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/store/store-restore-plan.ts:152) — 백업에서 절대 읽지 않는 컬럼이 `COPY`로 계획된다

문제: `id`, `created_at`, `updated_at`을 “생략 대상”이라고 선언했지만 실행기가 보는 행동은 `COPY`입니다. `ColumnAction.COPY`의 계약은 “백업 값을 그대로 넣는다”입니다. 실행기가 `source` 문자열까지 해석하지 않는 한 원본 PK·시각을 INSERT하게 됩니다.

근거:

```ts
if (NEVER_FROM_BACKUP.has(entry.column)) {
  return at({ kind: 'COPY' }, 'NEVER_FROM_BACKUP(생략 대상)');
}
```

수정: 최소한 `GENERATED_ID`와 `DB_DEFAULT` 또는 `OMIT` 행동을 별도로 만드십시오. `id`와 timestamps도 의미가 다릅니다.

- `id` → `GENERATED_ID`, 반드시 `RETURNING`과 ID 원장 연결
- `created_at`/`updated_at` → 정책을 명시적으로 선택
  - 역사 보존이면 `COPY`
  - 복제 생성시각이면 `DB_DEFAULT`
- “행동은 COPY지만 source가 생략을 뜻한다”는 이중 계약은 금지해야 합니다.

---

[HIGH] [store-restore-plan.ts](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/store/store-restore-plan.ts:245) — NOT NULL 다형 참조를 `CLEAR`로 만들기 때문에 `audit_logs` 복원이 실패한다

문제: `audit_logs.entity_id`는 `NOT NULL`인데 `POLYMORPHIC → CLEAR`입니다. 실행 시 INSERT가 실패합니다.

근거: [store-restore-columns.txt](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/store/store-restore-columns.txt:94)

```text
audit_logs.entity_id : integer NOT NULL
```

수정: `audit_logs`를 CLONE에서 통째로 제외하십시오. 이유는 단순한 NOT NULL 문제가 아닙니다.

- entity 링크를 정확히 재매핑할 수 없음
- 그대로 두면 새 매장에서 원본/무관 행을 가리킴
- 비우는 것도 불가능
- `old_values`/`new_values`에도 원본 ID·PII가 있을 수 있음
- 복제 자체가 새 감사 이벤트를 만들면 과거 감사와 새 감사가 혼재함

`audit_logs`는 원본 백업 아카이브에는 남겨도 되지만 새 매장의 운영 DB로 복제할 데이터는 아닙니다.

---

[HIGH] [store-restore-plan.spec.ts](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/store/store-restore-plan.spec.ts:65) — UNIQUE 인덱스 정책을 컬럼 행동으로 평탄화하면 FK/테넌트 변환을 덮어쓸 수 있다

문제: UNIQUE는 인덱스·식·조건 단위 정책인데 정규식으로 참여 컬럼 모두에 동일 행동을 부여합니다. 앞으로 `(store_id, external_code)` 같은 인덱스에 `REJECT`가 붙으면 `store_id`의 목적지 변환까지 REJECT가 덮어쓸 수 있습니다.

또한 한 컬럼이 여러 UNIQUE 인덱스에 참여하면 `Map.set()`의 마지막 정책이 조용히 이깁니다.

수정: 두 층으로 분리해야 합니다.

```ts
columnActions: ResolvedColumn[]
constraintPolicies: ResolvedUniquePolicy[]
```

- 컬럼 행동: `REMAP`, `DESTINATION_STORE`, `CLEAR`, `REGENERATE` 등
- 제약 정책: `PRECHECK_REJECT`, `SERVER_IDENTITY`, `REGENERATE_MEMBER`, `TENANT_SCOPED`
- UNIQUE 사전검사는 변환된 최종 튜플 전체를 대상으로 수행
- 동일 컬럼이 여러 정책에 들어가면 덮어쓰지 말고 조합 검증

## 1. 우선순위 7단계

현재 3번 UNIQUE가 5번 FK보다 앞서는 것은 반대합니다.

더 정확히는 UNIQUE와 FK 중 어느 것이 이기는지를 정하면 안 됩니다. 둘은 같은 축이 아닙니다.

- FK 정책은 “이 값이 무엇으로 변환되는가”
- UNIQUE 정책은 “변환된 결과가 제약을 충족하는가, 충돌하면 무엇을 하는가”

따라서 FK이면서 UNIQUE인 컬럼은 합법적인 공존입니다. 예를 들어 테넌트 범위 UNIQUE의 `store_id`는 반드시 목적지 매장으로 바뀌어야 하며, 그 후 복합키 충돌을 검사해야 합니다.

권장 순서는 컬럼 변환만 놓고 보면:

1. 테이블 제외/행 제외
2. 서버 정체성·생성 컬럼
3. 운영 상태 RESET
4. 자격증명 REGENERATE
5. DEFERRED
6. FK/unlinked 참조 처리
7. 일반 COPY

그 뒤 별도 단계로 UNIQUE/CHECK/NOT NULL/범위 검증을 실행하십시오.

겹치는 선언도 “우선순위로 해결”하기보다 다음 중 하나여야 합니다.

- 서로 다른 축이라 함께 적용
- 같은 축이면 동일한 정규화 결과임을 구조적으로 증명
- 그렇지 않으면 빌드 실패

## 2. `DESTINATION_STORE`

모든 진짜 테넌트 소유권 `store_id`를 `DESTINATION_STORE` 한 길로 합치는 편이 낫습니다.

FK 유무는 스키마 품질 차이일 뿐, 복원 의미는 동일합니다. `stores` 원장을 거쳐 목적지 ID를 얻도록 하면 다음 위험이 생깁니다.

- 원장 생성 순서/누락에 따라 핵심 테넌트 경계가 좌우됨
- FK 있는 테이블과 없는 테이블이 서로 다른 실행 분기를 탐
- 결과 검증도 두 종류가 필요함

권장 계약:

```ts
store_id owned by restored tenant → DESTINATION_STORE
```

그리고 실행 후에는 모든 복원 행에 대해 `store_id = destinationStoreId`를 역검증하십시오.

단, 이름만 `store_id`인 전역·플랫폼 테이블까지 무조건 적용하면 안 됩니다. “컬럼명 기반”이 아니라 소유권 매니페스트 기준이어야 합니다.

`branch_id`는 목적지 branch가 여러 개이므로 계속 `REMAP → branches`가 맞습니다.

## 3. `POLYMORPHIC → CLEAR`

반대합니다. `audit_logs`를 통째로 제외하십시오.

현재 선택지는 실제로 다음 둘뿐입니다.

- `COPY`: 다른 엔티티를 가리킬 수 있어 의미가 거짓
- `CLEAR`: NOT NULL 위반

라벨 정규화와 대상 테이블별 원장을 완성하기 전까지 행 단위 복원은 안전하지 않습니다. 감사 로그는 원본 백업 파일/복원 감사 메타데이터에서 조회하게 하고, 복제 매장 운영 데이터에는 넣지 않는 것이 맞습니다.

향후 다형 참조를 지원한다면 `POLYMORPHIC` 자체가 행동이어야 합니다. resolver가 “모름”을 임의로 `CLEAR`로 낮추면 안 됩니다.

## 4. plan에 아직 필요한 것

행 수·해시·스키마 지문 외에도 다음이 필요합니다.

- `planId`, 계획 버전, 생성시각, 만료시각
- 업로드 객체 ID와 원본 SHA-256
- 목적지 `storeId`, 가입 신청/등록 ID, owner group
- 계획 생성자와 실행 권한 주체
- 테이블별 `INCLUDE / EXCLUDE / ROW_FILTER`
- 예상 입력 행 수, 예상 INSERT 행 수, 예상 제외 행 수
- PK 생성 방식과 ID 원장 종류
- 트리거 정책: `MUST_RUN / SUPPRESS / REPLACE`
- UNIQUE 정책을 포함한 제약 단위 사전검사
- `KEEP_GLOBAL` 대상의 scope 증명 결과
- RESET/CLEAR/REGENERATE 건수
- unresolved 항목 0건 증명
- 최대 파일 크기, 테이블별/전체 행 수 상한
- 실행 당시 스키마 지문 재검증 조건
- 계획 상태 전이와 실패 코드
- 결과 감사 레코드 형식

특히 현재 계획에는 트리거 선언이 합쳐지지 않았습니다. 설명은 “네 벌을 합친다”고 하지만 실제 `RestorePlan`에는 트리거 집행 계획이 없습니다. 실행기가 별도로 트리거 파일을 다시 읽으면 “검토한 계획만 실행한다”는 원칙이 깨집니다.

## 5. 다음 조각 순서

제시한 순서에서 ②의 엔드포인트 배선은 뒤로 미루는 것이 맞습니다.

권장 순서:

1. 입력 파서와 검증기
2. 완전한 순수 plan 생성기
3. DB 계획 테이블 및 원자적 상태 전이
4. 실행기와 커밋 전 증명
5. 업로드/plan/execute 엔드포인트 배선
6. 실패 주입·재실행·동시 실행 통합 테스트
7. `clone_only` 개방

DB 계획 테이블을 먼저 만드는 것은 괜찮지만, 공개 엔드포인트를 먼저 배선하는 것은 반대합니다. 실행기 없이 upload/plan만 열어도 임시 객체 누적, 저장공간 DoS, 만료 청소, 권한 경계 같은 운영 표면이 생깁니다.

`RESTORE_ENGINE_STATUS='blocked'`는 마지막 통합 검증까지 유지해야 합니다.

## 6. 범위 질문

### 가. `box_settlements`: 포함

포함해야 합니다. 크론이 `box_settlements.settled_through`를 기준선으로 삼으므로 제외하면 복제된 과거 `cash_registers`가 전부 미정산으로 인식될 수 있습니다. 그 결과 새 정산과 금고 이체가 만들어집니다.

다만 반드시 함께 복제·검증할 것:

- `boxes`
- 관련 `cash_registers`
- `caja_fuerte_operation_id`가 가리키는 원장
- 구간 중복 exclusion constraint
- 테이블별 입력/원장/INSERT 행 수 일치

### 나. `billing_invoices`: 제외

새 매장은 원본 매장의 플랫폼 청구서·납부·AFIP 발행 사실을 물려받으면 안 됩니다. 그것은 매장 영업 이력이 아니라 플랫폼과 원본 법적/계약 주체 사이의 채권·세무 문서입니다.

`billing_invoices`만 빼지 말고 다음 종속 그래프를 함께 제외해야 합니다.

- `billing_invoices`
- `billing_payments`
- `billing_payment_submissions`
- 그 밖 invoice/payment를 부모로 갖는 테이블

필요하다면 원본 아카이브로만 보존하십시오.

### 다. `store_notices`: 제외

플랫폼이 원본 매장에 보낸 공지는 새 매장에 재전달하면 안 됩니다. 특히 `read_at IS NULL`이면 새 매장 접속 즉시 과거 공지가 현재 공지처럼 노출됩니다.

fan-out `campaign_id`도 원본 수신자 집합의 상관관계이므로 일부 행만 새 매장으로 옮기면 관리 콘솔의 발송/읽음 통계 의미까지 왜곡됩니다.

## 7. 추가로 놓친 것

- `CLEAR`/`RESET(null)`/`DEFERRED`가 NOT NULL 컬럼에 적용되는 모든 경우를 전수 검사해야 합니다. `audit_logs.entity_id`가 이미 반례입니다.
- nullable FK의 `required: false`가 “입력값이 NULL일 수 있음”인지 “매핑 실패를 허용함”인지 모호합니다. 입력값이 non-null인데 매핑이 없으면 nullable 컬럼이라도 실패해야 합니다.
- `DEFERRED_FK_COLUMNS`에 실제 FK edge가 없을 때 현재 자기 테이블로 fallback합니다. 이는 실패해야 합니다.
- “모든 컬럼이 해석된다” 검사는 기본 `COPY` 때문에 미선언 컬럼도 항상 통과합니다. 이는 완전성 검사라기보다 총함수 검사입니다. 위험군(`*_id`, 토큰/secret/key, 상태 컬럼, UNIQUE 참여 컬럼)은 기본 COPY 금지 검사가 별도로 필요합니다.
- 충돌 검사에서 `RESET` 값이 `undefined`이면 선언을 놓칩니다. `in` 또는 own-property 검사로 통일해야 합니다.
- UNIQUE 정의를 `RegExp(\bcolumn\b)`로 파싱하지 마십시오. 표현식 인덱스, quoted identifier, 함수, cast에서 오판할 수 있습니다. 카탈로그에서 인덱스 컬럼/식 구조를 별도로 추출해야 합니다.
- 계획의 `notices`는 문자열만으로는 집행 계약이 아닙니다. 구조화된 영향 요약과 별도 렌더링이 필요합니다.
- 행 제외가 필요한 `seller_attendance` 같은 `RESET_UNRESOLVED`가 하나라도 있으면 plan 생성 자체를 거부해야 합니다.
- 트리거 SUPPRESS가 세션/커넥션 설정이라면 pool 재사용 후 상태가 남지 않도록 반드시 트랜잭션 로컬 설정 또는 `finally` 복구가 필요합니다.

최종 판정은 “코어의 분리 방향은 승인, 다음 조각 진행 전 HIGH 3건 수정 필요”입니다. 특히 UNIQUE를 컬럼 행동으로 유지하는 설계와 `audit_logs CLEAR`는 그대로 진행하면 안 됩니다.
CODEX_EXIT=0
