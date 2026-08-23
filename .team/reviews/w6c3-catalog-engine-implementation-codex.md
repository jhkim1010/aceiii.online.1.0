# codex 검토 — W6-C3 ③④ 카탈로그 복원 실행기 구현 (2026-08-23)

판정: **수정 필요.** 설계 수용사항(다른 id 의 자연키 점유 → BLOCKED, `prices` PK-only,
집행 트랜잭션 안 재판정, 모든 스냅샷 UNIQUE 검사, 3값 `sku_serials` 최댓값,
선점/복구/결과 기록 분리)은 실제 경로에 연결돼 있다. 그러나 아래 HIGH 2건과
MEDIUM 2건이 새로 확인됐다.

## [HIGH] api-ventago/src/app/store/store-restore-catalog.engine.ts:787 — `GREATEST(last_value, max(id))`가 동시 `nextval()`과 원자적이지 않아 시퀀스를 뒤로 당길 수 있다

  문제: `last_value`를 읽고 `setval`을 실행하는 사이에 일반 INSERT가 `nextval()`을
  호출할 수 있다. 예를 들어 읽은 값이 2000인데 동시 INSERT가 2001을 발급받은 뒤
  이 문장이 `setval(..., 2000, true)`를 실행하면 다음 호출도 2001을 발급한다.
  advisory lock은 일반 상품 생성 경로가 공유하지 않으므로 이 경합을 막지 않는다.
  시퀀스가 비트랜잭션이라는 설명과 실행 시점을 마지막으로 옮긴 것만으로는 해결되지 않는다.

  근거:

  ```ts
  SELECT setval($1,
            GREATEST(
              (SELECT last_value FROM ${row.seq}),
              (SELECT COALESCE(MAX(id), 0) FROM ${q(table)})
            ), true)
  ```

  수정: 해당 시퀀스에 대해 `nextval`과 보정이 직렬화되는 방식을 사용해야 한다.
  가장 단순한 안전안은 복원 트랜잭션에서 각 대상 시퀀스를 `ACCESS EXCLUSIVE`로 잠근
  뒤 `last_value`/`MAX(id)`/`setval`을 수행하는 것이다. 운영 PG 버전에서 실제
  `nextval`과 잠금 호환성을 동시성 통합 테스트로 확인하라. 일반 쓰기 경로가 같은
  advisory lock을 공유하도록 바꾸는 방법도 가능하지만 적용 범위가 더 넓다.

## [HIGH] api-ventago/src/app/store/store-restore-catalog.service.ts:368 — 복구가 커밋된 뒤 기록 실패를 `FAILED`로 덮어쓴다

  문제: 복구 트랜잭션은 366행에서 이미 커밋된다. 그 뒤 `SUCCEEDED` UPDATE 또는
  요약 감사 INSERT가 실패하면 같은 `catch`가 계획을 `FAILED`로 기록한다. 결과적으로
  데이터는 복원됐는데 제어 원장은 실패라고 말하고, 감사 요약도 없을 수 있다.
  이는 3분할 설계의 취지와 달리 "실패한 집행이 어디까지 갔는지 모르는" 상태를 만든다.

  근거:

  ```ts
  const plan = await this.sequelize.transaction(/* 복구 — 여기서 커밋 */);
  await this.sequelize.query(`UPDATE ... SET status='SUCCEEDED' ...`);
  await this.writeSummaryAudit(...);
  ...
  catch (err) {
    await this.sequelize.query(`UPDATE ... SET status='FAILED' ...`);
  }
  ```

  수정: 복구 실패만 `FAILED`로 전이시키고, 복구 커밋 이후의 결과 기록은 별도 오류
  경계로 분리하라. `SUCCEEDED` 상태 변경과 요약 감사 INSERT는 하나의 짧은 트랜잭션으로
  묶는 편이 낫다. 그 트랜잭션이 실패하면 `FAILED`로 바꾸지 말고 `EXECUTING` 또는
  별도 `COMMITTED_PENDING_RECORD` 상태에 남겨 운영자가 커밋 여부를 조정할 수 있게 하라.

## [MEDIUM] api-ventago/src/app/store/store-restore-catalog.engine.ts:393 — 백업 파일 내부의 PK/UNIQUE 중복을 계획이 검사하지 않는다

  문제: `decideTable`은 목적지 DB 점유만 조회한다. 백업 안에서 두 행이 같은 PK를
  가지거나 서로 다른 PK로 같은 UNIQUE 튜플을 가지면 둘 다 `INSERT`로 계획된다.
  계획은 `executable: true`를 반환하지만 집행은 INSERT의 23505에서 롤백되고 계획은
  소모된다. "모든 UNIQUE 검사"가 목적지 점유에는 구현됐지만 입력 행 상호 간에는
  빠져 있다.

  근거:

  ```ts
  const found = await run(`SELECT ... FROM ${q(table)} WHERE ${where}`, bind);
  ...
  return rows.map((row) => decideRow(/* DB에서 찾은 점유만 전달 */));
  ```

  수정: DB 조회 전에 테이블별 PK 튜플과 적용되는 각 UNIQUE 튜플을 백업 행끼리
  그룹화하라. 같은 키가 둘 이상이면 서로 완전히 같은 중복 행인지에 관계없이 입력을
  명시적으로 거부하거나 BLOCKED로 표시해야 한다. 부분 인덱스와 NULL-distinct 규칙은
  현재 `uniqueKeyApplies()`를 그대로 재사용할 수 있다.

## [MEDIUM] api-ventago/src/app/store/store-restore-catalog.service.ts:126 — 스키마 fingerprint가 판정 근거인 UNIQUE/FK를 포함하지 않는다

  문제: fingerprint는 범위 컬럼의 `type`과 `notNull`만 해시한다. rolling deploy 중
  계획을 만든 워커와 집행 워커가 다른 UNIQUE/FK 카탈로그 스냅샷을 가진 경우에도
  `SCHEMA_CHANGED`가 걸리지 않는다. 집행은 새 워커의 같은 함수로 재판정하므로 DB
  안전성은 유지되지만, 사용자가 검토한 계획과 집행 판정 근거가 같다는 보장은 깨진다.

  근거:

  ```ts
  this.columns
    .filter((c) => scope.has(c.table))
    .map((c) => `${c.table}.${c.column}:${c.type}:${c.notNull}`)
  ```

  수정: 범위 컬럼의 generated/serverGenerated 정보, 파싱된 PK/UNIQUE 정의,
  범위 내 FK 간선, outbound 규칙과 엔진 판정 버전을 canonical serialization하여 함께
  해시하라.

## 요청 항목별 확인

1. **SQL 인용/바인드:** 백업 값은 bind된다. 테이블/컬럼은 `tableOrder`, 컬럼·UNIQUE
   카탈로그, 서버 상수에서만 오며 `q()`의 단순 식별자 검증도 거친다. `GLOBAL_REF_TABLES`
   역시 서버 상수다. `${row.seq}`만 직접 삽입되지만 `pg_get_serial_sequence()`가 낸
   서버 카탈로그 식별자이므로 현재 요청 입력을 통한 SQL 주입 경로는 확인되지 않았다.
   `${storeId}`와 actor GUC도 `Number(...)` 이후 값이라 문자열 주입은 되지 않는다.
2. **NULL·부분 인덱스·자기 점유:** 현재 스냅샷의 부분 인덱스
   `products_store_slug_uniq WHERE slug IS NOT NULL`과 일반 PG NULL-distinct 의미는
   반영됐다. 같은 PK가 있으면 UNIQUE 판정보다 먼저 SKIP/BLOCKED가 반환되므로 자기
   점유 오탐도 없다. 다만 위 MEDIUM처럼 백업 내부 중복은 빠졌다.
3. **트랜잭션/잠금:** 복원 쓰기는 단일 트랜잭션이고 BLOCKED 후 throw로 선행 INSERT도
   롤백된다. 계획 선점은 조건부 UPDATE로 분리됐고 매장 advisory xact lock도 집행에
   연결됐다. 시퀀스만 위 HIGH 동시성 결함이 남는다.
4. **계획/집행 공통 코드:** 둘 다 `runCatalogRestore()`를 호출하며 `dryRun`만 다르다.
   집행은 저장 객체의 SHA-256을 확인하고 같은 파서·범위·판정 함수를 다시 탄다.
   다만 fingerprint 누락 때문에 서로 다른 배포 워커 사이의 판정 의존성 동일성은
   완전하지 않다.

## 검증

- 정적 대조: 실제 diff 파일, UNIQUE/컬럼/FK 스냅샷, 계획 상태 기계 확인
- 단위 테스트: `store-restore-catalog.spec.ts`, `store-restore-plan-state.spec.ts`,
  `store-restore-contract.spec.ts` — **68개 통과**
- 운영 DB에는 연결하지 않았다.
