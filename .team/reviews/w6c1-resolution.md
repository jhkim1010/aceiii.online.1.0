# Stage 1 (W6-C1) codex 검토 — 수용/반박 (2026-08-22)

원본: `.team/reviews/w6c1-codex.md` · diff: `.team/reviews/w6c1-diff.txt`

| # | 심각도 | 지적 | 결정 |
|---|---|---|---|
| 1 | HIGH | `PENDING` 이 있어도 커버리지가 전부 초록 — "분류됨" 과 "백업 가능" 이 같은 신호 | **수용** |
| 2 | HIGH | `ALTER TABLE` 로 기존 global 테이블이 매장 것이 되면 두 감시 모두 통과 | **수용** |
| 3 | MEDIUM | `CROSS_TENANT` 6개 중 2개는 경계가 성립 안 함 | **수용, 실측 후 재분류** |
| 4 | LOW | 재귀 CTE 의 `UNION` 이 순환을 못 접는다 (`depth` 때문) | **수용** |
| 5 | LOW | FK 마이그레이션 멱등 검사가 이름만 본다 | **수용(검증만)** |

---

## 1 [HIGH] — 부채를 초록으로 세고 있었다

`PENDING_BACKUP_TABLES` 를 만들어 "무엇이 아직 안 담기는지" 를 선언했는데,
커버리지 spec 이 그것도 "선언됨" 으로 세어 **전부 통과**했다.
즉 `role_function_actions`(40,557행)·금전함 이력이 백업에 하나도 없는데
테스트는 초록이고, 화면은 "Backup y Eliminar" 를 그대로 실행했다.

★ codex 표현이 정확하다 — **"분류됨" 과 "백업 가능" 을 같은 초록 신호로 만들면 안 된다.**

**한 것**: 파괴적 경로를 막았다.
- `deleteStoreCascade()` 가 **미담김 테이블이 남아 있으면 거부**한다. 삭제 경로가
  둘(`DELETE :id/purge`, `DELETE :id`)이라 **서비스에서** 막았다 — 한 곳만 고치면
  나머지 하나가 조용히 열린다.
- ★ 확인을 "예" 한 마디로 받지 않는다. **호출자가 자기가 본 개수를 되돌려 보내야** 한다.
  그 사이 목록이 늘었다면 사용자는 늘어난 것을 못 본 것이므로 다시 막는다.
  (판정만으론 구속력이 없다 — 본 원본 상태가 같이 와야 한다.)
- 프론트는 **방금 내려받은 백업 JSON 의 `coverage.pending.length`** 를 보낸다.
  못 읽으면 보내지 않는다 → 서버가 fail-closed 로 막는다.
- 성공 토스트도 고쳤다: "Backup descargado" → "backup parcial (no restaurable)".

**반박(부분)**: codex 는 "백업 완전성 검사는 PENDING 이 있으면 실패" 도 제안했다.
채택하지 않는다 — 그러면 W6-C2 가 끝날 때까지 **CI 가 영구히 빨갛다.**
빨간 CI 는 곧 무시되는 CI 다. 대신 **파괴적 경로를 막아** 실제 피해를 차단하고,
부채는 `coverage.pending` 과 이 목록으로 보이게 둔다.

## 2 [HIGH] — 기존 테이블의 재분류 누락

②는 `CREATE TABLE` 만 봤다. 이미 `global` 로 분류된 테이블에
`ALTER TABLE ... ADD COLUMN store_id` 나 테넌트 부모로의 FK 를 붙이면
①(재생성 안 하면 옛 분류 유지)·②(CREATE 아님)·선언이 **서로 맞아 셋 다 통과**한다.

**한 것**: ③ 검사 추가 — 컷오프 이후 마이그레이션이 `GLOBAL_TABLES` 의 테이블에
`store_id` 를 더하거나 FK 를 붙이면 **실패**한다. 해소는 기준선 재생성 후
분류를 옮기거나, 여전히 global 이면 *왜 그런지*를 이유에 적는 것이다.

## 3 [MEDIUM] — 분류 경계, 실측으로 확정

운영에서 직접 셌다:

| 테이블 | 실측 | 결정 |
|---|---|---|
| `global_clients` | **19행이 2개 이상 매장에 참조됨** | CROSS_TENANT 유지 (근거 보강) |
| `global_categories` | 소유자 범위 컬럼 **없음**(전 매장 공용), 현재 공유 0건 | CROSS_TENANT 유지 — 복제하면 카탈로그가 갈라진다 |
| `pending_registrations` | 7행. `password_hash`·`token`·DNI 키 보유 | **GLOBAL 로 이동** (아직 매장이 아니고 자격증명이다) |
| `revendedor_categories` | 0행. 양끝이 플랫폼 소속 | **GLOBAL 로 이동** |

★ 두 테이블은 폐포상 `tenant` 인데 사람이 `global` 로 정한 것이다.
  **매니페스트가 권위**이므로 교정은 허용하되 **조용히는 안 된다** —
  `폐포_교정` 목록에 명시하게 했고, 목록에 없는 교정이 생기면 테스트가 깨진다.

## 4 [LOW] — 재귀 CTE

`reach` 가 `(oid, depth)` 라 같은 테이블도 depth 가 다르면 다른 행이었다.
`UNION` 이 중복을 못 접으니 순환 방어를 `depth < 20` 이 떠맡았고,
**20단계를 넘는 사슬은 global 로 오분류**된다. `oid` 하나만 남겨 고정점까지 수렴하게 했다.
(재생성 결과는 187/29 로 동일 — 현재 스키마에 20단계 사슬은 없었다.)

## 5 [LOW] — FK 멱등 검사

이미 운영 적용 후 `pg_get_constraintdef()` 로 네 제약의 **실제 정의**를 확인했다:
```
talleres_defects         FOREIGN KEY (subcon_delivery_id)   REFERENCES talleres_deliveries(id)
talleres_deliveries      FOREIGN KEY (subcon_order_id)      REFERENCES talleres_orders(id)
talleres_material_issues FOREIGN KEY (subcon_order_id)      REFERENCES talleres_orders(id)
talleres_payments        FOREIGN KEY (subcon_settlement_id) REFERENCES talleres_settlements(id)
```
이름뿐 아니라 컬럼·참조 대상까지 의도와 일치한다.

## 검증 — 대조군

| 대조군 | 결과 |
|---|---|
| 선언에서 `role_function_actions` 제거 | 1건 실패 |
| 기준선을 옛 형식으로 되돌림 | 4건 실패 |
| `GLOBAL` 에서 `provinces` 제거 | 1건 실패 |
| **`PENDING` 을 비움** (가드 무력화 시도) | **5건 실패** |
| **폐포 교정을 몰래 추가** | **2건 실패** |
| 원복 | **20/20 통과** |
