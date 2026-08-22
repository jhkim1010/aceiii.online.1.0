# W6-C3 전체 재검토 — codex 자문 요청 (2026-08-22)

**개별 지적이 아니라 구조를 다시 봐 달라.** 사용자 지시가 "다시 완벽하게 재조정" 이다.
지금까지 네 지적을 건건이 수용해 왔는데, 그렇게 쌓인 결과가 **전체로도 옳은지**는
아직 아무도 안 봤다. 리팩터가 필요하면 분명히 말하라.

★ 저장소를 직접 읽어라. 전부 `api-ventago/src/app/store/` 에 있다.

---

## 지금 있는 것 (전부 배포됨 · 복원은 `RESTORE_ENGINE_STATUS='blocked'`)

| 파일 | 줄 | 무엇 |
|---|---:|---|
| `store-restore-contract.ts` | 193 | 서버 상수 잠금. 파일이 무엇을 주장하든 거부 |
| `store-restore-manifest.ts` | 822 | FK 처리 · 삽입 순서 · 순환 · 운영상태 되돌림 · 행 필터 · CLONE 제외 · 자기참조 전략 |
| `store-restore-unlinked-refs.ts` | 669 | **FK 제약이 없는** 참조 90개의 처리 |
| `store-restore-identity.ts` | 249 | UNIQUE 정책 + 마스킹 NOT NULL 재발급 |
| `store-restore-triggers.ts` | 232 | 복원 중 트리거 58개 처리 |
| `store-restore-plan.ts` | 486 | 위 다섯을 **컬럼 하나의 답**으로 합침 + 계획 생성 |
| `store-restore-input.ts` | 314 | 업로드 파일 허용목록 검증 |
| `store-backup-keys.ts` | 170 | 백업 JSON 키 ↔ 테이블 |
| `store-restore-plan-state.ts` | 132 | 계획 상태 기계 (PLANNED→EXECUTING 원자적 선점) |

기준선 파일: FK 351 · UNIQUE 235 · 컬럼 1,826 · 트리거 58 · FK없는참조 90 · 인벤토리 223
운영 DB: `store_restore_plans` 테이블 적용됨(0행)
테스트: store + migrations **254개 통과**

---

## 이번 세션에서 네가 지적해 내가 고친 것 (누적)

E1 순서는 카탈로그에서 유도 / E3 DEFERRED 원장 / E4 검증 근거 분리 /
`restaurant_tables.current_sale_id` 는 운영상태 / owner_group 판별 공용체 /
전 스키마 인벤토리 / 중복 FK DISTINCT / `id`→`GENERATED_ID` /
`audit_logs` CLONE 제외 / UNIQUE 를 제약 축으로 분리 / DEFERRED fallback 금지 /
`RESET_UNRESOLVED` 면 계획 거부 / billing·store_notices 제외 / 엔드포인트를 뒤로

**그리고 내가 만든 전수 검사가 내 결함을 더 잡았다:**
NOT NULL 에 비우기 지시 3건(둘은 내가 그날 만든 선언) ·
`mp_*` 두 선언이 서로 다른 말 · VIRTUAL 컬럼이라 **진짜 백업 파일을 거부**할 뻔 ·
대조군이 **세 번 통과**해 검사를 다시 지음

---

## 묻는 것 — 구조를 다시 보라

### 1. **선언을 여섯 파일로 나눈 것이 지금도 옳은가?**
근거가 다르니 나누라는 것은 네 E4 지적이었다. 그런데 지금
`resolveColumn()` 이 우선순위 7단계로 그것을 다시 합친다.
**나누고 다시 합치는 구조 자체가 문제인가?**
합치는 순서를 사람이 읽고 검증할 수 있나, 아니면 다른 절단선이 있나?

### 2. **`resolveColumn()` 의 우선순위가 방어 가능한가?**
UNIQUE 를 제약 축으로 뺀 뒤 남은 순서:
`GENERATED_ID` → 시각 → 운영상태 → 자격증명 → `SERVER_IDENTITY` → DEFERRED → FK → unlinked → COPY.
**이 중 순서가 바뀌면 결과가 달라지는 쌍이 실제로 몇 개인가?**
1개(`restaurant_tables.current_sale_id`)뿐이라면 우선순위 대신
**"겹치면 빌드 실패" 로 바꾸는 게 낫지 않나?**

### 3. **선언들 사이에 아직 남은 모순이 있나?**
전수 검사를 여러 개 만들었지만 내가 **생각해 낸 형태만** 검사한다.
카탈로그로 셀 수 있는데 내가 아직 안 센 모순이 있나?

### 4. **계획이 실행기에 넘길 만큼 완결됐나?**
네가 준 목록 중 아직 없는 것: planId·만료·해시·목적지·가입신청 ID·
예상 행 수·**트리거 집행 계획**·scope 증명·실패코드·감사 레코드·구조화된 영향 요약.
**이 중 실행기를 짓기 전에 반드시 있어야 하는 것은 무엇인가?**
전부 있어야 하나, 아니면 실행기와 함께 자라도 되는 것이 있나?

### 5. **입력 검증기에 아직 위험한 것이 있나?**
특히 (가) `DERIVED_ROW_KEYS` 로 **버리는** 것이 정말 안전한가
(나) camelCase↔snake_case 정규화가 값의 **타입**은 안 본다
(다) 중첩 `sales` 자식을 평평하게 만들면서 **부모-자식 대응이 끊긴다**
    (지금은 자식 행의 `sale_id` 로만 이어진다 — 원본 ID 인데 REMAP 대상이다)

### 6. **상태 기계에 구멍이 있나?**
`EXECUTING` 에서 프로세스가 죽으면 그 계획은 **영원히 EXECUTING** 이다.
`FAILED → PLANNED` 를 막았으니 되살릴 길도 없다.
그게 의도한 fail-closed 인가, 아니면 운영이 막히는 자리인가?

### 7. **첫 실제 `CLONE` 에서 무엇이 먼저 깨질 것 같나?**
지금 상태로 실행기만 붙여 돌린다고 가정하고, **가장 먼저 죽을 자리**를 짚어라.

### 8. 내가 놓친 것.

한국어. 결론 먼저. **리팩터가 필요하면 "지금 구조를 버려라" 라고 분명히 말하라.**
8개 전부 답하는 것을 우선하라.
