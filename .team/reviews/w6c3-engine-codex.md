codex
## 결론

`CLONE` 전용 엔진은 지금 열어도 되는 방향입니다. 다만 아래 세 가지는 설계를 바꿔야 합니다.

1. `plan → execute` 2단계는 유지하되, execute가 파일을 다시 받으면 안 됩니다. 서버가 계획한 정확한 업로드 객체를 보관하고 `planId`가 그것을 가리켜야 합니다.
2. F6은 전체 테이블 감사 쿼리가 아니라, 복원 엔진의 필수 ID 매핑 원장을 임시 테이블로 만들고 그 행만 증명해야 합니다. ID 범위는 쓰면 안 됩니다.
3. F7은 “placeholder + 비활성”만으로 열면 안 됩니다. 모든 소비자가 비활성 상태를 동일하게 해석하도록 먼저 고쳐야 합니다. 현재 커머스 UI는 행 존재만으로 “연결됨”을 표시합니다.

---

## 1. F1 — 2단계 API가 맞나?

맞습니다. 한 번 호출로 줄이는 것에 반대합니다.

복원은 수 MB JSON 파싱, 스키마 검증, 행 수 산출, 폐기·정규화 내역 확인이 필요한 고위험 작업입니다. superadmin이 실제 변경 전에 계획서를 보는 단계는 가치가 있습니다.

다만 API 모양은 이렇게 잡는 편이 안전합니다.

```text
POST /store/restore/uploads
  multipart file
  → uploadId

POST /store/restore/plan
  { uploadId, mode: "CLONE", registrationId? }
  → { planId, summary, warnings, expiresAt }

POST /store/restore/execute
  { planId }
  → 결과
```

execute에는 `file`, `mode`, `destination`을 다시 받지 않는 것이 핵심입니다. `mode`까지 plan에 고정해야 합니다. execute에서 바꿀 수 있으면 plan으로 검토한 작업과 실제 작업이 달라집니다.

### 상태 저장 위치

- 업로드 원본: MinIO의 임시·비공개 객체
- 계획 메타데이터: DB
- 메모리 저장: 반대

PM2 4워커 환경에서 메모리에 두면 plan과 execute가 다른 워커에 배정되거나 재시작되는 순간 사라집니다.

DB 계획 레코드에는 최소한 다음이 필요합니다.

```text
id
upload_object_key
content_sha256
mode
source_store_id
requested_by_user_id
registration_id 또는 clone_creation_context
status: PLANNED | EXECUTING | SUCCEEDED | FAILED | EXPIRED
schema_fingerprint
summary_json
created_at
expires_at
executed_at
result_store_id
```

execute 시작 시 `SELECT ... FOR UPDATE` 또는 원자적 상태 변경으로 `PLANNED → EXECUTING`을 한 번만 허용해야 합니다. `planId` 재실행과 이중 클릭을 막는 장치입니다.

### “CLONE은 destination을 받지 않는다”의 수정

기존 `storeId`를 받지 않는다는 의미라면 맞습니다. 하지만 가입 신청 화면에서 실행한다면 서버는 새 매장의 생성 근거를 알아야 합니다.

따라서 `registrationId` 같은 서버 권위의 생성 컨텍스트는 plan 단계에서 받아야 합니다. 백업의 `store.name`, owner group, 대표자, 구독 상태를 그대로 새 매장 정체성으로 쓰면 안 됩니다. 서버가 가입 신청 레코드와 현재 superadmin 권한에서 새 매장 필드를 확정해야 합니다.

현재 엔드포인트가 파일 전체를 그대로 받는 사실은 [store.controller.ts](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/store/store.controller.ts:111)에서 확인됩니다.

### 업로드 방식

수 MB라도 JSON body로 기술적으로 처리할 수는 있지만, 복원 파일은 multipart 스트리밍으로 바꾸는 것을 권합니다.

- 요청 본문 크기 상한
- 압축 해제 후 크기 상한
- 테이블별·전체 행 수 상한
- JSON 중첩 깊이 상한
- 업로드 SHA-256 서버 계산
- TTL 후 임시 객체 삭제
- 계획·실행 사용자 동일성 확인

`coverage` 해시는 파일이 주장하는 값을 믿어서는 안 됩니다. 서버가 업로드 바이트와 정규화된 실제 내용에서 다시 계산해야 합니다.

---

## 2. F4 — 단일 트랜잭션과 stocks 트리거

1만 행이면 단일 트랜잭션이 맞습니다. CLONE의 원자성 이점이 더 큽니다.

다만 현재처럼 ORM `create()`를 1만 번 순차 실행하는 것은 반대합니다. `role_function_actions` 4,415행이면 해당 테이블 하나만으로도 약 4,415번 왕복합니다. 테이블별로 적절한 크기의 bulk insert를 사용하고 `RETURNING`으로 ID 매핑을 만들어야 합니다.

### stocks 트리거

`trg_stock_balances_apply`는 각 `stocks` INSERT마다 다음 작업을 합니다.

- `ProductBranch`와 `products` 조인
- `stock_balances`에 `INSERT ... ON CONFLICT DO UPDATE`

즉 stocks N행에 대해 대략 N번의 부모 조회와 N번의 잔액 upsert가 추가됩니다. 하지만 제공한 실측은 55행이므로 현재 규모에서는 단일 트랜잭션을 포기할 이유가 아닙니다. 55행이면 병목 가능성은 낮습니다.

오히려 확인할 것은 다음입니다.

- `stock_balances` 자체는 복원하지 않고 파생 상태로 다시 만들어지는가
- stocks가 원본 순서와 무관하게 누계 결과를 동일하게 만드는가
- `ProductBranch.id` remap이 먼저 완료됐는가
- 트리거가 요구하는 `store_id`, `branch_id`, `operation_date`가 올바르게 정규화되는가

트리거 구현은 [2026-08-08-stock-balances-traspaso.sql](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/migrations/2026-08-08-stock-balances-traspaso.sql:37)에 있습니다.

### MinIO 객체 복사

트랜잭션 안에서 복사하면 안 됩니다.

권장 순서는 다음입니다.

1. plan 단계 또는 execute의 DB 트랜잭션 시작 전에 필요한 객체를 검증한다.
2. 복사가 필요하면 충돌하지 않는 최종 객체 키로 미리 복사한다.
3. 복사가 모두 성공한 뒤 DB 트랜잭션을 시작한다.
4. DB에는 이미 존재하는 객체 키만 기록한다.
5. DB 롤백 시 미사용 객체를 비동기 정리 대상으로 기록한다.

MinIO는 DB와 원자적으로 커밋할 수 없으므로 “고아 객체는 생길 수 있지만 DB가 없는 객체를 참조하지는 않는다” 쪽으로 실패 방향을 잡아야 합니다.

가능하다면 객체가 불변이고 접근권한이 매장 경로와 무관한 경우에는 content-addressed key를 공유하는 편이 복사보다 안전합니다. 반대로 키 자체가 테넌트 권한 경계라면 반드시 새 키로 복사해야 합니다.

---

## 3. F6 — 역방향 소유 증명을 새 행으로 한정하는 방법

ID 범위 방식에는 반대합니다.

시퀀스에는 동시 INSERT, 롤백으로 인한 구멍, 트리거 생성 행이 섞일 수 있습니다. `id BETWEEN 시작 AND 끝`은 남의 행을 포함하거나 복원 행을 누락할 수 있습니다.

가장 안전한 방법은 이미 REMAP에 필요한 원장을 트랜잭션 임시 테이블로 승격하는 것입니다.

```text
restore_rows
  table_name
  old_pk
  new_pk
  disposition/source kind
```

PK가 항상 정수 하나라는 보장이 없다면 `old_pk/new_pk`를 JSONB 형태로 표현하거나 테이블별 typed temp table을 만들어야 합니다.

안전 조건은 다음과 같습니다.

- 모든 INSERT는 `RETURNING`으로 새 PK를 받는다.
- 입력으로 받아들인 각 행마다 원장 1건이 있어야 한다.
- 테이블별 `accepted_input_count = inserted_count = ledger_count`를 검사한다.
- `(table_name, old_pk)`와 `(table_name, new_pk)`에 유일성을 둔다.
- FK remap도 이 원장만 통한다.
- 커밋 전 소유 증명도 이 원장의 `new_pk`만 대상으로 한다.
- 엔진 외부의 INSERT 경로를 트랜잭션 안에서 호출하지 않는다.

그다음 FK 카탈로그에서 목적지 매장으로 향하는 경로를 구성하고, 각 `new_pk`에 대해 다음을 검사합니다.

- 목적지 `store_id`에 도달하는 경로가 존재한다.
- 다른 `store_id`에 도달하는 경로가 없다.
- `KEEP_GLOBAL` 간선은 소유 증명 경로에서 제외하되 별도의 PUBLIC/OWNER_GROUP 검사를 통과했다.
- 원장에 기록된 새 행 전체가 검사 결과에 나타났다.

이렇게 하면 전 테이블 전체 스캔이 아니라 최대 약 1만 개 새 PK에 대한 인덱스 조인이 됩니다. 임시 테이블에도 `(table_name, new_pk)` 인덱스를 두면 됩니다.

“원장이 틀리면 감사도 헛돈다”는 우려는 맞습니다. 그래서 원장을 단순 감사 보조자료가 아니라 INSERT 성공과 FK remap의 유일한 근거로 만들어야 합니다. 입력 수·`RETURNING` 수·원장 수의 삼중 일치가 없으면 롤백해야 합니다.

---

## 4. F7 — 존재하지만 못 쓰는 행 vs 없는 행

현재 구조에서는 테이블별 답이 다릅니다. “모두 placeholder”도, “모두 제외”도 반대합니다.

### mp_accounts

`mp_accounts`는 행을 보존하되 확실히 disconnected 상태로 만드는 편이 낫습니다.

- `disconnected_at = now()`
- `external_pos_id = NULL`
- `expires_at = NULL`
- access/refresh token은 암호화 서비스가 생성한 유효 형식의 무작위 폐기값
- 가능하면 장기적으로 `credential_state = 'reauth_required'`를 명시적으로 추가

결제 resolver는 `disconnectedAt: null`인 행만 선택하므로 비활성 행은 일반 결제 경로에서 제외됩니다. 근거는 [mp-account-resolver.service.ts](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/mercadopago/mp-account-resolver.service.ts:15)입니다.

행 보존의 장점은 `mp_wallets`, `mp_payment_intents` 등의 FK와 과거 감사 관계를 잃지 않고, 재-OAuth 시 기존 행을 갱신할 수 있다는 점입니다.

다만 `findByPk()`로 직접 계정을 읽는 모든 결제·웹훅 경로도 `disconnectedAt`을 검사하는지 별도 전수검사가 필요합니다. 하나라도 검사하지 않으면 placeholder 복호화 또는 외부 호출까지 갈 수 있습니다.

### commerce_channels / wp_channels

행은 보존하되 다음처럼 만들어야 합니다.

- `is_active = false`
- `channel_key`, `secret`은 원본 유지 금지; 새 무작위 값으로 회전
- 외부 토큰과 consumer credentials 제거
- `external_meta`에서 OAuth 토큰·설치 식별자 제거
- `last_received_at`, `last_pushed_at` 초기화

그런데 현재 UI는 `isActive`가 아니라 배열 길이만 보고 “연결됨”으로 표시합니다. [IntegracionesHubView.tsx](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/ventago-app/src/views/configuracion/integraciones/IntegracionesHubView.tsx:106)에서 `wpChannels.length > 0`, `tnChannels.length > 0`을 사용합니다.

따라서 F7은 다음 조건 전에는 열면 안 됩니다.

- 모든 서버 소비자가 `is_active=false`를 제외
- UI가 행 존재가 아닌 활성·자격증명 상태를 표시
- 웹훅 인증이 복제 전 secret으로 성공하지 않음
- 재연동이 기존 비활성 행을 안전하게 갱신하거나 교체
- “재인증 필요”가 명시적으로 표시됨

즉 현재 선택은 “없는 행”이 아니라 “관계는 보존하되 실행 가능성은 제거한 행”입니다. 하지만 소비자 게이트 수정이 같은 배포에 포함되어야 합니다.

---

## 5. F8/F9 — CLONE만 먼저 열어도 되나?

찬성합니다. 둘 다 완성될 때까지 잠글 필요는 없습니다.

실사용자가 superadmin 가입 신청 화면이고 실제 요구가 새 매장 생성이라면 CLONE은 독립적으로 가치가 있습니다. `IN_PLACE_RECOVERY`는 시간 경계, T 이후 데이터 충돌, 삭제·대체 정책, 외부 시스템 재조정이 없으므로 계속 막아야 합니다.

다만 상태 타입은 모드를 명확히 표현해야 합니다.

```ts
type RestoreEngineStatus = 'blocked' | 'clone_only' | 'enabled';
```

그리고 라우트·서비스 양쪽에서 mode를 검사해야 합니다. 프론트에서 숨기는 것만으로는 부족합니다.

테스트에는 최소한 다음이 필요합니다.

- `clone_only + CLONE`만 통과
- `clone_only + IN_PLACE_RECOVERY` 거부
- execute 요청에서 mode 덮어쓰기 불가
- 기존 `storeId`를 목적지로 지정할 수 없음
- plan이 다른 superadmin에게 재사용되지 않음
- plan 중복 실행 불가

---

## 6. OPERATIONAL_STATE_RESETS가 하나뿐이어도 되나?

현재 정보만으로 “하나뿐이 맞다”고 확정하면 안 됩니다. 추가 감사가 필요합니다.

다만 세션·토큰·기기 바인딩은 이미 백업 제외 정책에 들어 있습니다. `active_sessions`, `mobile_sessions`, `support_tokens`, `terminal_devices`, `branch_ip_registries` 등이 별도 제외 대상으로 선언돼 있습니다. 따라서 이들은 `OPERATIONAL_STATE_RESETS`에 추가할 대상이 아니라 “아예 복제하지 않는 일시 상태”입니다.

152개 테이블을 다음 네 종류로 나눠야 합니다.

1. `PRESERVE_HISTORY`: 판매, 결제, 원장, 감사 사실
2. `RESET_RUNTIME_STATE`: 설정 행은 필요하지만 현재 실행 상태는 초기화
3. `REAUTH_REQUIRED`: 관계·설정은 보존하지만 외부 권한 제거
4. `EXCLUDE_EPHEMERAL`: 세션, 토큰, 기기 바인딩, 작업 큐 등 아예 복제하지 않음

찾는 신호는 “status + FK”만으로 부족합니다. 다음을 함께 검색해야 합니다.

- `current_*_id`, `active_*_id`, `open_*_id`, `locked_by`, `assigned_*`
- `status`와 `opened_at/closed_at/completed_at/disconnected_at` 조합
- 서비스에서 두 개 이상의 컬럼을 한 UPDATE로 전환하는 코드
- cron/worker가 `pending`, `running`, `retry`를 조회하는 테이블
- 외부 시스템 식별자, webhook secret, OAuth token
- 세션·기기·printer/agent/socket 바인딩
- “현재 잔액/현재 점유/현재 처리자”처럼 과거 원장에서 다시 계산되는 파생 행
- 복제 직후 worker가 자동으로 집어갈 수 있는 상태

우선 확인할 후보는 다음입니다.

- `campaign_recipients`의 pending/retry 상태
- `client_imports`, `code_imports`의 running/pending 상태
- `cash_registers`의 열린 세션
- `rider_settlements`의 open 상태
- `commerce_channels`, `wp_channels`, `mp_accounts`
- store integration 상태
- 프린터·에이전트·기기 연결 상태

반대로 `sales.status`, `online_orders.status`, `billing_*`, `box_settlements` 등은 과거 사실 또는 정산 권위일 수 있으므로 이름만 보고 초기화하면 안 됩니다. 각 상태를 소비하는 서비스의 “다음 행동”을 확인해야 합니다.

가장 강한 감사 질문은 이것입니다.

> 새 매장이 생성된 직후 cron, worker, POS 또는 외부 webhook이 이 행을 “지금 처리해야 할 일”로 인식하는가?

그렇다면 RESET, REAUTH 또는 EXCLUDE 후보입니다.

---

## 7. 추가로 놓친 것

### [HIGH] plan이 생성할 새 매장의 정체성이 아직 명확하지 않음

파일의 `store` 행을 새 매장 생성의 권위로 쓰면 안 됩니다. 가입 신청의 owner group, 대표자, 이메일, 구독·앱 상태와 plan을 결합해야 합니다. `registrationId`를 plan에 고정하고 execute 시 다시 현재 상태를 확인하십시오.

### [HIGH] 런타임 대조 범위가 FK만이면 부족함

`store-restore-columns.txt`에는 이름만이 아니라 최소한 다음이 포함돼야 합니다.

- 타입과 길이
- nullable
- default
- identity/generated
- PK
- unique/check constraint
- 복원에 영향을 주는 trigger

FK 351개가 같아도 컬럼 타입, NOT NULL, generated column 또는 트리거가 바뀌면 계획과 실행이 달라질 수 있습니다. 정규화된 전체 restore-schema fingerprint를 비교하는 편이 안전합니다.

### [HIGH] 전역 UNIQUE 충돌 정책

현재 코드도 users의 전역 email/username 충돌을 특별 처리합니다. 152개 테이블에는 외부 키, slug, code, webhook key 등 추가적인 전역 또는 잘못 범위화된 UNIQUE가 있을 수 있습니다.

plan 단계에서 모든 UNIQUE 제약을 분류해야 합니다.

- 새 값으로 재발급
- 원본 유지 가능
- 충돌 시 거부
- 매장 범위 UNIQUE라 store remap 후 허용

### [HIGH] 트리거 부작용

복원 INSERT가 감사 트리거, 알림, 큐 생성, 파생 원장 등을 실행할 수 있습니다. 트리거를 무조건 비활성화하면 제약 보호까지 잃으므로 반대합니다. 각 트리거를 다음으로 분류해야 합니다.

- 반드시 실행
- 실행 후 파생 테이블은 복원 제외
- 복원 컨텍스트에서 안전하게 억제
- 외부 부작용 때문에 복원 전용 경로 필요

### [MEDIUM] advisory lock만으로 중복 실행은 해결되지 않음

새 store ID는 생성 전에는 없습니다. plan 단위 잠금 또는 DB 상태 전이가 먼저 필요합니다. store INSERT 후에는 새 store ID 잠금을 잡을 수 있지만, 중복 execute 방지는 `plan.status` 원자적 전이가 담당해야 합니다.

### [MEDIUM] 실패·재시도·감사

최종 결과에는 최소한 다음을 남겨야 합니다.

- 누가, 어떤 plan을 실행했는가
- 원본 해시
- 생성된 store ID
- 테이블별 입력/삽입/초기화/제외 행 수
- 실패 단계와 안전하게 마스킹된 사유
- MinIO 고아 객체 정리 상태

백업 행의 원문이나 자격증명을 로그에 남겨서는 안 됩니다.

---

최종 판단은 다음과 같습니다.

- F1: 찬성. DB plan + MinIO 임시 업로드로 구현하고 execute는 `planId`만 받기
- F2: 찬성. 다만 컬럼 이름뿐 아니라 타입·제약·트리거 fingerprint까지 확대
- F3: 찬성. plan 중복 방지는 별도 DB 상태 전이 필요
- F4: 찬성. bulk insert 필수, 외부 I/O는 트랜잭션 전에 완료
- F5: 찬성. DEFERRED 원장을 전체 ID remap/삽입 원장으로 확대
- F6: 찬성. ID 범위 금지, 임시 원장 기반으로 새 행만 검사
- F7: 조건부 찬성. 행 보존이 낫지만 모든 소비자 게이트 수정 전에는 반대
- F8/F9: 찬성. `clone_only`로 먼저 개방 가능
- 운영 상태: `restaurant_tables` 하나로 확정하지 말고 4분류 감사를 한 번 더 수행해야 함
hook: Stop
hook: Stop
hook: Stop Failed
hook: Stop Completed
tokens used
89,782
## 결론

`CLONE` 전용 엔진은 지금 열어도 되는 방향입니다. 다만 아래 세 가지는 설계를 바꿔야 합니다.

1. `plan → execute` 2단계는 유지하되, execute가 파일을 다시 받으면 안 됩니다. 서버가 계획한 정확한 업로드 객체를 보관하고 `planId`가 그것을 가리켜야 합니다.
2. F6은 전체 테이블 감사 쿼리가 아니라, 복원 엔진의 필수 ID 매핑 원장을 임시 테이블로 만들고 그 행만 증명해야 합니다. ID 범위는 쓰면 안 됩니다.
3. F7은 “placeholder + 비활성”만으로 열면 안 됩니다. 모든 소비자가 비활성 상태를 동일하게 해석하도록 먼저 고쳐야 합니다. 현재 커머스 UI는 행 존재만으로 “연결됨”을 표시합니다.

---

## 1. F1 — 2단계 API가 맞나?

맞습니다. 한 번 호출로 줄이는 것에 반대합니다.

복원은 수 MB JSON 파싱, 스키마 검증, 행 수 산출, 폐기·정규화 내역 확인이 필요한 고위험 작업입니다. superadmin이 실제 변경 전에 계획서를 보는 단계는 가치가 있습니다.

다만 API 모양은 이렇게 잡는 편이 안전합니다.

```text
POST /store/restore/uploads
  multipart file
  → uploadId

POST /store/restore/plan
  { uploadId, mode: "CLONE", registrationId? }
  → { planId, summary, warnings, expiresAt }

POST /store/restore/execute
  { planId }
  → 결과
```

execute에는 `file`, `mode`, `destination`을 다시 받지 않는 것이 핵심입니다. `mode`까지 plan에 고정해야 합니다. execute에서 바꿀 수 있으면 plan으로 검토한 작업과 실제 작업이 달라집니다.

### 상태 저장 위치

- 업로드 원본: MinIO의 임시·비공개 객체
- 계획 메타데이터: DB
- 메모리 저장: 반대

PM2 4워커 환경에서 메모리에 두면 plan과 execute가 다른 워커에 배정되거나 재시작되는 순간 사라집니다.

DB 계획 레코드에는 최소한 다음이 필요합니다.

```text
id
upload_object_key
content_sha256
mode
source_store_id
requested_by_user_id
registration_id 또는 clone_creation_context
status: PLANNED | EXECUTING | SUCCEEDED | FAILED | EXPIRED
schema_fingerprint
summary_json
created_at
expires_at
executed_at
result_store_id
```

execute 시작 시 `SELECT ... FOR UPDATE` 또는 원자적 상태 변경으로 `PLANNED → EXECUTING`을 한 번만 허용해야 합니다. `planId` 재실행과 이중 클릭을 막는 장치입니다.

### “CLONE은 destination을 받지 않는다”의 수정

기존 `storeId`를 받지 않는다는 의미라면 맞습니다. 하지만 가입 신청 화면에서 실행한다면 서버는 새 매장의 생성 근거를 알아야 합니다.

따라서 `registrationId` 같은 서버 권위의 생성 컨텍스트는 plan 단계에서 받아야 합니다. 백업의 `store.name`, owner group, 대표자, 구독 상태를 그대로 새 매장 정체성으로 쓰면 안 됩니다. 서버가 가입 신청 레코드와 현재 superadmin 권한에서 새 매장 필드를 확정해야 합니다.

현재 엔드포인트가 파일 전체를 그대로 받는 사실은 [store.controller.ts](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/store/store.controller.ts:111)에서 확인됩니다.

### 업로드 방식

수 MB라도 JSON body로 기술적으로 처리할 수는 있지만, 복원 파일은 multipart 스트리밍으로 바꾸는 것을 권합니다.

- 요청 본문 크기 상한
- 압축 해제 후 크기 상한
- 테이블별·전체 행 수 상한
- JSON 중첩 깊이 상한
- 업로드 SHA-256 서버 계산
- TTL 후 임시 객체 삭제
- 계획·실행 사용자 동일성 확인

`coverage` 해시는 파일이 주장하는 값을 믿어서는 안 됩니다. 서버가 업로드 바이트와 정규화된 실제 내용에서 다시 계산해야 합니다.

---

## 2. F4 — 단일 트랜잭션과 stocks 트리거

1만 행이면 단일 트랜잭션이 맞습니다. CLONE의 원자성 이점이 더 큽니다.

다만 현재처럼 ORM `create()`를 1만 번 순차 실행하는 것은 반대합니다. `role_function_actions` 4,415행이면 해당 테이블 하나만으로도 약 4,415번 왕복합니다. 테이블별로 적절한 크기의 bulk insert를 사용하고 `RETURNING`으로 ID 매핑을 만들어야 합니다.

### stocks 트리거

`trg_stock_balances_apply`는 각 `stocks` INSERT마다 다음 작업을 합니다.

- `ProductBranch`와 `products` 조인
- `stock_balances`에 `INSERT ... ON CONFLICT DO UPDATE`

즉 stocks N행에 대해 대략 N번의 부모 조회와 N번의 잔액 upsert가 추가됩니다. 하지만 제공한 실측은 55행이므로 현재 규모에서는 단일 트랜잭션을 포기할 이유가 아닙니다. 55행이면 병목 가능성은 낮습니다.

오히려 확인할 것은 다음입니다.

- `stock_balances` 자체는 복원하지 않고 파생 상태로 다시 만들어지는가
- stocks가 원본 순서와 무관하게 누계 결과를 동일하게 만드는가
- `ProductBranch.id` remap이 먼저 완료됐는가
- 트리거가 요구하는 `store_id`, `branch_id`, `operation_date`가 올바르게 정규화되는가

트리거 구현은 [2026-08-08-stock-balances-traspaso.sql](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/migrations/2026-08-08-stock-balances-traspaso.sql:37)에 있습니다.

### MinIO 객체 복사

트랜잭션 안에서 복사하면 안 됩니다.

권장 순서는 다음입니다.

1. plan 단계 또는 execute의 DB 트랜잭션 시작 전에 필요한 객체를 검증한다.
2. 복사가 필요하면 충돌하지 않는 최종 객체 키로 미리 복사한다.
3. 복사가 모두 성공한 뒤 DB 트랜잭션을 시작한다.
4. DB에는 이미 존재하는 객체 키만 기록한다.
5. DB 롤백 시 미사용 객체를 비동기 정리 대상으로 기록한다.

MinIO는 DB와 원자적으로 커밋할 수 없으므로 “고아 객체는 생길 수 있지만 DB가 없는 객체를 참조하지는 않는다” 쪽으로 실패 방향을 잡아야 합니다.

가능하다면 객체가 불변이고 접근권한이 매장 경로와 무관한 경우에는 content-addressed key를 공유하는 편이 복사보다 안전합니다. 반대로 키 자체가 테넌트 권한 경계라면 반드시 새 키로 복사해야 합니다.

---

## 3. F6 — 역방향 소유 증명을 새 행으로 한정하는 방법

ID 범위 방식에는 반대합니다.

시퀀스에는 동시 INSERT, 롤백으로 인한 구멍, 트리거 생성 행이 섞일 수 있습니다. `id BETWEEN 시작 AND 끝`은 남의 행을 포함하거나 복원 행을 누락할 수 있습니다.

가장 안전한 방법은 이미 REMAP에 필요한 원장을 트랜잭션 임시 테이블로 승격하는 것입니다.

```text
restore_rows
  table_name
  old_pk
  new_pk
  disposition/source kind
```

PK가 항상 정수 하나라는 보장이 없다면 `old_pk/new_pk`를 JSONB 형태로 표현하거나 테이블별 typed temp table을 만들어야 합니다.

안전 조건은 다음과 같습니다.

- 모든 INSERT는 `RETURNING`으로 새 PK를 받는다.
- 입력으로 받아들인 각 행마다 원장 1건이 있어야 한다.
- 테이블별 `accepted_input_count = inserted_count = ledger_count`를 검사한다.
- `(table_name, old_pk)`와 `(table_name, new_pk)`에 유일성을 둔다.
- FK remap도 이 원장만 통한다.
- 커밋 전 소유 증명도 이 원장의 `new_pk`만 대상으로 한다.
- 엔진 외부의 INSERT 경로를 트랜잭션 안에서 호출하지 않는다.

그다음 FK 카탈로그에서 목적지 매장으로 향하는 경로를 구성하고, 각 `new_pk`에 대해 다음을 검사합니다.

- 목적지 `store_id`에 도달하는 경로가 존재한다.
- 다른 `store_id`에 도달하는 경로가 없다.
- `KEEP_GLOBAL` 간선은 소유 증명 경로에서 제외하되 별도의 PUBLIC/OWNER_GROUP 검사를 통과했다.
- 원장에 기록된 새 행 전체가 검사 결과에 나타났다.

이렇게 하면 전 테이블 전체 스캔이 아니라 최대 약 1만 개 새 PK에 대한 인덱스 조인이 됩니다. 임시 테이블에도 `(table_name, new_pk)` 인덱스를 두면 됩니다.

“원장이 틀리면 감사도 헛돈다”는 우려는 맞습니다. 그래서 원장을 단순 감사 보조자료가 아니라 INSERT 성공과 FK remap의 유일한 근거로 만들어야 합니다. 입력 수·`RETURNING` 수·원장 수의 삼중 일치가 없으면 롤백해야 합니다.

---

## 4. F7 — 존재하지만 못 쓰는 행 vs 없는 행

현재 구조에서는 테이블별 답이 다릅니다. “모두 placeholder”도, “모두 제외”도 반대합니다.

### mp_accounts

`mp_accounts`는 행을 보존하되 확실히 disconnected 상태로 만드는 편이 낫습니다.

- `disconnected_at = now()`
- `external_pos_id = NULL`
- `expires_at = NULL`
- access/refresh token은 암호화 서비스가 생성한 유효 형식의 무작위 폐기값
- 가능하면 장기적으로 `credential_state = 'reauth_required'`를 명시적으로 추가

결제 resolver는 `disconnectedAt: null`인 행만 선택하므로 비활성 행은 일반 결제 경로에서 제외됩니다. 근거는 [mp-account-resolver.service.ts](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/mercadopago/mp-account-resolver.service.ts:15)입니다.

행 보존의 장점은 `mp_wallets`, `mp_payment_intents` 등의 FK와 과거 감사 관계를 잃지 않고, 재-OAuth 시 기존 행을 갱신할 수 있다는 점입니다.

다만 `findByPk()`로 직접 계정을 읽는 모든 결제·웹훅 경로도 `disconnectedAt`을 검사하는지 별도 전수검사가 필요합니다. 하나라도 검사하지 않으면 placeholder 복호화 또는 외부 호출까지 갈 수 있습니다.

### commerce_channels / wp_channels

행은 보존하되 다음처럼 만들어야 합니다.

- `is_active = false`
- `channel_key`, `secret`은 원본 유지 금지; 새 무작위 값으로 회전
- 외부 토큰과 consumer credentials 제거
- `external_meta`에서 OAuth 토큰·설치 식별자 제거
- `last_received_at`, `last_pushed_at` 초기화

그런데 현재 UI는 `isActive`가 아니라 배열 길이만 보고 “연결됨”으로 표시합니다. [IntegracionesHubView.tsx](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/ventago-app/src/views/configuracion/integraciones/IntegracionesHubView.tsx:106)에서 `wpChannels.length > 0`, `tnChannels.length > 0`을 사용합니다.

따라서 F7은 다음 조건 전에는 열면 안 됩니다.

- 모든 서버 소비자가 `is_active=false`를 제외
- UI가 행 존재가 아닌 활성·자격증명 상태를 표시
- 웹훅 인증이 복제 전 secret으로 성공하지 않음
- 재연동이 기존 비활성 행을 안전하게 갱신하거나 교체
- “재인증 필요”가 명시적으로 표시됨

즉 현재 선택은 “없는 행”이 아니라 “관계는 보존하되 실행 가능성은 제거한 행”입니다. 하지만 소비자 게이트 수정이 같은 배포에 포함되어야 합니다.

---

## 5. F8/F9 — CLONE만 먼저 열어도 되나?

찬성합니다. 둘 다 완성될 때까지 잠글 필요는 없습니다.

실사용자가 superadmin 가입 신청 화면이고 실제 요구가 새 매장 생성이라면 CLONE은 독립적으로 가치가 있습니다. `IN_PLACE_RECOVERY`는 시간 경계, T 이후 데이터 충돌, 삭제·대체 정책, 외부 시스템 재조정이 없으므로 계속 막아야 합니다.

다만 상태 타입은 모드를 명확히 표현해야 합니다.

```ts
type RestoreEngineStatus = 'blocked' | 'clone_only' | 'enabled';
```

그리고 라우트·서비스 양쪽에서 mode를 검사해야 합니다. 프론트에서 숨기는 것만으로는 부족합니다.

테스트에는 최소한 다음이 필요합니다.

- `clone_only + CLONE`만 통과
- `clone_only + IN_PLACE_RECOVERY` 거부
- execute 요청에서 mode 덮어쓰기 불가
- 기존 `storeId`를 목적지로 지정할 수 없음
- plan이 다른 superadmin에게 재사용되지 않음
- plan 중복 실행 불가

---

## 6. OPERATIONAL_STATE_RESETS가 하나뿐이어도 되나?

현재 정보만으로 “하나뿐이 맞다”고 확정하면 안 됩니다. 추가 감사가 필요합니다.

다만 세션·토큰·기기 바인딩은 이미 백업 제외 정책에 들어 있습니다. `active_sessions`, `mobile_sessions`, `support_tokens`, `terminal_devices`, `branch_ip_registries` 등이 별도 제외 대상으로 선언돼 있습니다. 따라서 이들은 `OPERATIONAL_STATE_RESETS`에 추가할 대상이 아니라 “아예 복제하지 않는 일시 상태”입니다.

152개 테이블을 다음 네 종류로 나눠야 합니다.

1. `PRESERVE_HISTORY`: 판매, 결제, 원장, 감사 사실
2. `RESET_RUNTIME_STATE`: 설정 행은 필요하지만 현재 실행 상태는 초기화
3. `REAUTH_REQUIRED`: 관계·설정은 보존하지만 외부 권한 제거
4. `EXCLUDE_EPHEMERAL`: 세션, 토큰, 기기 바인딩, 작업 큐 등 아예 복제하지 않음

찾는 신호는 “status + FK”만으로 부족합니다. 다음을 함께 검색해야 합니다.

- `current_*_id`, `active_*_id`, `open_*_id`, `locked_by`, `assigned_*`
- `status`와 `opened_at/closed_at/completed_at/disconnected_at` 조합
- 서비스에서 두 개 이상의 컬럼을 한 UPDATE로 전환하는 코드
- cron/worker가 `pending`, `running`, `retry`를 조회하는 테이블
- 외부 시스템 식별자, webhook secret, OAuth token
- 세션·기기·printer/agent/socket 바인딩
- “현재 잔액/현재 점유/현재 처리자”처럼 과거 원장에서 다시 계산되는 파생 행
- 복제 직후 worker가 자동으로 집어갈 수 있는 상태

우선 확인할 후보는 다음입니다.

- `campaign_recipients`의 pending/retry 상태
- `client_imports`, `code_imports`의 running/pending 상태
- `cash_registers`의 열린 세션
- `rider_settlements`의 open 상태
- `commerce_channels`, `wp_channels`, `mp_accounts`
- store integration 상태
- 프린터·에이전트·기기 연결 상태

반대로 `sales.status`, `online_orders.status`, `billing_*`, `box_settlements` 등은 과거 사실 또는 정산 권위일 수 있으므로 이름만 보고 초기화하면 안 됩니다. 각 상태를 소비하는 서비스의 “다음 행동”을 확인해야 합니다.

가장 강한 감사 질문은 이것입니다.

> 새 매장이 생성된 직후 cron, worker, POS 또는 외부 webhook이 이 행을 “지금 처리해야 할 일”로 인식하는가?

그렇다면 RESET, REAUTH 또는 EXCLUDE 후보입니다.

---

## 7. 추가로 놓친 것

### [HIGH] plan이 생성할 새 매장의 정체성이 아직 명확하지 않음

파일의 `store` 행을 새 매장 생성의 권위로 쓰면 안 됩니다. 가입 신청의 owner group, 대표자, 이메일, 구독·앱 상태와 plan을 결합해야 합니다. `registrationId`를 plan에 고정하고 execute 시 다시 현재 상태를 확인하십시오.

### [HIGH] 런타임 대조 범위가 FK만이면 부족함

`store-restore-columns.txt`에는 이름만이 아니라 최소한 다음이 포함돼야 합니다.

- 타입과 길이
- nullable
- default
- identity/generated
- PK
- unique/check constraint
- 복원에 영향을 주는 trigger

FK 351개가 같아도 컬럼 타입, NOT NULL, generated column 또는 트리거가 바뀌면 계획과 실행이 달라질 수 있습니다. 정규화된 전체 restore-schema fingerprint를 비교하는 편이 안전합니다.

### [HIGH] 전역 UNIQUE 충돌 정책

현재 코드도 users의 전역 email/username 충돌을 특별 처리합니다. 152개 테이블에는 외부 키, slug, code, webhook key 등 추가적인 전역 또는 잘못 범위화된 UNIQUE가 있을 수 있습니다.

plan 단계에서 모든 UNIQUE 제약을 분류해야 합니다.

- 새 값으로 재발급
- 원본 유지 가능
- 충돌 시 거부
- 매장 범위 UNIQUE라 store remap 후 허용

### [HIGH] 트리거 부작용

복원 INSERT가 감사 트리거, 알림, 큐 생성, 파생 원장 등을 실행할 수 있습니다. 트리거를 무조건 비활성화하면 제약 보호까지 잃으므로 반대합니다. 각 트리거를 다음으로 분류해야 합니다.

- 반드시 실행
- 실행 후 파생 테이블은 복원 제외
- 복원 컨텍스트에서 안전하게 억제
- 외부 부작용 때문에 복원 전용 경로 필요

### [MEDIUM] advisory lock만으로 중복 실행은 해결되지 않음

새 store ID는 생성 전에는 없습니다. plan 단위 잠금 또는 DB 상태 전이가 먼저 필요합니다. store INSERT 후에는 새 store ID 잠금을 잡을 수 있지만, 중복 execute 방지는 `plan.status` 원자적 전이가 담당해야 합니다.

### [MEDIUM] 실패·재시도·감사

최종 결과에는 최소한 다음을 남겨야 합니다.

- 누가, 어떤 plan을 실행했는가
- 원본 해시
- 생성된 store ID
- 테이블별 입력/삽입/초기화/제외 행 수
- 실패 단계와 안전하게 마스킹된 사유
- MinIO 고아 객체 정리 상태

백업 행의 원문이나 자격증명을 로그에 남겨서는 안 됩니다.

---

최종 판단은 다음과 같습니다.

- F1: 찬성. DB plan + MinIO 임시 업로드로 구현하고 execute는 `planId`만 받기
- F2: 찬성. 다만 컬럼 이름뿐 아니라 타입·제약·트리거 fingerprint까지 확대
- F3: 찬성. plan 중복 방지는 별도 DB 상태 전이 필요
- F4: 찬성. bulk insert 필수, 외부 I/O는 트랜잭션 전에 완료
- F5: 찬성. DEFERRED 원장을 전체 ID remap/삽입 원장으로 확대
- F6: 찬성. ID 범위 금지, 임시 원장 기반으로 새 행만 검사
- F7: 조건부 찬성. 행 보존이 낫지만 모든 소비자 게이트 수정 전에는 반대
- F8/F9: 찬성. `clone_only`로 먼저 개방 가능
- 운영 상태: `restaurant_tables` 하나로 확정하지 말고 4분류 감사를 한 번 더 수행해야 함
CODEX_EXIT=0
