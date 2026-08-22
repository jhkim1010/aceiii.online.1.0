# W6-C3 전체 재검토 — codex 2라운드 대화 결과 (2026-08-22)

원본: `.team/reviews/w6c3-full-codex.md`(1R) · `.team/reviews/w6c3-round2-codex.md`(2R)
질문: `QUESTION-...-f-w6c3-전체재검토.md` · `QUESTION-...-g-w6c3-2라운드.md`

## codex 결론

> **"현재 구조를 버리지 마라. 하지만 현재 계획 위에 실행기를 바로 짓지도 마라."**

선언을 근거별로 나눈 것은 옳다(근거의 권위가 각각 다르다). 잘못된 것은
**분리가 아니라 합성 방식**이었다.

---

## ★ 대화에서 **내가 codex 를 고친 것**

1R 에서 codex 는 "다중 주장 컬럼은 정확히 두 개" 라고 했다. 전 컬럼 1,826개를
실측했더니 **12개**였다 — `DEFERRED_FK_COLUMNS` 와 FK 카탈로그가 같은 컬럼을
둘 다 주장하는 10개를 안 셌다.

**결론은 같지만 더 강해졌다: 결과가 달라지는 우선순위 쌍이 0개.**
즉 7단계 사다리가 **아무것도 결정하고 있지 않았다.**

2R 에서 codex 는 테넌트 가드 수도 스스로 정정했다(34 → **35**).
내 문장 세 곳도 34·24·24 로 갈라져 있었다.

---

## 적용한 것

### ① 우선순위 **전부 제거** → 정책 컴파일러
```
후보 0개   → UnclassifiedColumnError (빌드 실패)
후보 1개   → 채택
후보 2개+  → 구조적으로 같으면 sources 병합, 다르면 ConflictingColumnPolicyError
```
`source: string` → `sources: string[]`. 이긴 쪽만 남고 진 쪽이 사라지던 것을 고쳤다.

★ 바꾸자마자 **실제 불일치를 잡았다**: `branch_agents.socket_id` 를
한쪽은 `RESET(null)`, 다른 쪽은 `CLEAR` 라고 했다 — 뜻은 같은데 **어휘가 둘**이었다.
→ "비운다" 는 이름을 하나로 합쳤다.

### ② 암묵적 fallback COPY 제거 (codex 2R)
"아무도 주장 안 하면 복사" 는 새 컬럼이 생겼을 때 **이름이 알려졌다는 이유만으로
조용히 복사**한다. → `SCHEMA_PLAIN_VALUE_COLUMN` 후보를 카탈로그에서 명시적으로 만든다.
**1,255개를 손으로 적을 필요는 없다** — 카탈로그가 "평범한 값 컬럼" 을 정의한다.

### ③ 그 엄격함이 찾은 진짜 결함
`stores.slug_canonical` 은 **`GENERATED ALWAYS AS`** 컬럼이라 INSERT 할 수 없는데
내가 `SERVER_IDENTITY`("서버가 값을 골라 쓴다")로 선언해 뒀다.
→ `OMIT` 액션 신설, 카탈로그의 `GENERATED` 표시에서 유도.

### ④ `id` 판정을 이름 → 카탈로그 사실로
두 번 좁혀야 했다: 단순 `default` 는 복사 못 할 이유가 아니고(13개 오탐),
**복합 PK 의 자연키**(`talleres_cut_ticket_counters.year`)도 복사 대상이다.

### ⑤ 숫자를 문장에 박지 않는다
재생성 스크립트가 세어 헤더에 쓰고, spec 은 `> 20` 대신 **정확히 35** 를 못 박는다.
느슨한 하한은 "0개면 헛돈다" 만 막을 뿐 **드리프트를 못 막는다.**

---

## 아직 안 한 것 — codex 가 정한 배포 순서

```
1. 우선순위 없는 정책 컴파일러      ✅ 이번에
2. typed input (타입·필수·중첩 소속)  ← 다음
3. 트리거 실행 계획 유도
4. 실행 계약 결합 (plan hash·해시·행수·트리거계획)
5. 상태 모델 최소화 결정            ← 마이그레이션 승인 지점
6. 감사 트리거 억제 마이그레이션    ← 승인 지점
7. 실행기를 **잠긴 채로** 배포 → 검증 → 잠금 해제
```

### 2번 typed input 에서 할 것 (codex 1R HIGH)
- 타입·nullability·required 검증 (지금은 **컬럼 이름만** 본다)
- ID/FK 는 `Number.isSafeInteger(v) && v > 0` 강제
- **필수 테이블 존재** 검증 — 지금은 부분 백업도 `rejections=[]` 가 된다
- 중첩 `sales` 자식: 배열 아니면 `NESTED_CHILD_NOT_ARRAY`,
  부모 원본 ID 를 **주입**하고 자식의 `sale_id` 와 다르면 `CHILD_PARENT_MISMATCH`

### 5·6번 판단 (codex 2R)
- **경우 A(전부 한 트랜잭션)면 lease 자체가 불필요하다.** 프로세스가 죽으면
  전체가 롤백되므로 커밋된 `EXECUTING` 이 남지 않는다.
  조건: 업로드 다운로드·파싱·MinIO 는 트랜잭션 **밖**, 성공 상태 갱신도 **같은** 트랜잭션.
- 트리거 억제는 `SET LOCAL ventago.restore_mode='on'` + 감사 함수 early return 이 1순위.
  `ALTER TABLE ... DISABLE TRIGGER` 는 `SHARE ROW EXCLUSIVE` 잠금이라 **권하지 않는다**.
  `current_setting(...,true)` 비용은 감사 INSERT 비용보다 훨씬 작다(단, 벤치마크 필요).
- 트리거 선언은 **함수 단위로 유지**하고 `(mode, table, event, function)` 은 **유도**한다.
  58줄을 손으로 복제하지 않는다. `function default + instance override`.

### codex 1R 이 남긴 미해결 (2번 이후로 이월)
`billing` 트리거가 CLONE 에서 `NOT_REACHED` 여야 하는데 `MUST_RUN_TARGET_EXCLUDED` /
row provenance / ID 원장 완전성 계약 / 복원 후 불변식의 구체적 쿼리 목록 /
`DERIVED_ROW_KEYS` 로 버린 수량을 계획 요약에 기록
