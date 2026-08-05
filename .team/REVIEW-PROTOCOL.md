# cmux team 협업 프로토콜 — Claude Code(구현) ↔ codex(보안 검토)

역할 경계는 [`AGENTS.md`](../AGENTS.md) 가 정의한다. 이 문서는 **두 에이전트가 어디서 만나는지**만 정한다.

## 원칙

| | Claude Code | codex |
|---|---|---|
| 코드 수정 | **한다** | 하지 않는다 (보고서만) |
| 커밋·push | 한다 | 하지 않는다 |
| 마이그레이션 | 새 파일 작성·적용 | 초안 제안만, 기존 파일 수정 금지 |
| 운영 DB | 조회 허용(CLAUDE.md 규칙) | **접속 금지** |
| 최종 판단 | **한다** — 검토 지적의 수용/반박을 결정 | 하지 않는다 |

**codex 의 지적은 입력이지 명령이 아니다.** Claude 는 각 지적에 대해 수용하거나 근거를 대고 반박한다.
반박도 기록으로 남긴다 — 다음 검토에서 같은 지적이 반복되는 것을 막는다.

## 디렉터리 규약

```
.team/
├── config.json              # 모델 설정 (추적됨)
├── REVIEW-PROTOCOL.md       # 이 문서
├── tasks/NNN-<slug>/
│   └── task.md              # 구현 태스크 정의 (Claude 가 집행)
└── reviews/
    ├── NNN-codex.md         # codex 검토 보고서 (codex 가 생성)
    └── NNN-resolution.md    # 지적별 수용/반박 결정 (Claude 가 생성)
```

`reviews/` 는 추적한다 — 무엇을 왜 수용/반박했는지가 다음 phase 의 근거가 된다.

## 흐름

```
1. Claude   구현 → 커밋 (아직 push 안 함)
2. Claude   scripts/codex-review.sh --task NNN   ← 변경 diff 를 codex 에 넘긴다
3. codex    .team/reviews/NNN-codex.md 생성 (AGENTS.md 보고 형식)
4. Claude   지적별 판단 → .team/reviews/NNN-resolution.md
              - 수용 → 수정 커밋
              - 반박 → 근거 기록 (코드 그대로)
5. Claude   CRITICAL/HIGH 가 모두 해소·반박된 뒤에만 push
```

**게이트:** `CRITICAL` 또는 `HIGH` 가 미해소 상태로 남아 있으면 push 하지 않는다.
`MEDIUM`/`LOW` 는 resolution 에 기록만 하고 넘어갈 수 있다.

## 검토 입력에서 제외하는 것

`scripts/codex-review.sh` 가 diff 를 만들 때 아래를 제외한다. codex 가 값을 보지 못하게 하는 것이 목적이다.

- `.env`, `.env.*` (AGENTS.md 금지 항목)
- `*.pem`, `*.key`, `id_*`
- `package-lock.json`, `node_modules/` (노이즈)

## 실행

```bash
# 태스크 단위 검토 — main 대비 현재 브랜치 diff
scripts/codex-review.sh --task 001

# 워킹트리 검토 — 커밋 전 빠른 점검
scripts/codex-review.sh --working

# 특정 경로만
scripts/codex-review.sh --task 002 --paths api-ventago/src/app/products
```

cmux team 으로 병렬 실행할 때:

```bash
cmux claude-teams     # 구현 측 (기존 .team/tasks 집행)
cmux codex-teams      # 검토 측
```

> **codex 미설치 상태면 `cmux codex-teams` 가 `codex not found in PATH` 로 실패한다.**
> `npm i -g @openai/codex` 후 `codex login` 을 한 번 거쳐야 한다.

## 검토 대상 우선순위 (이 저장소 기준)

AGENTS.md 의 일반 기준 위에, 이 프로젝트에서 실제로 사고가 났던 지점을 얹는다.

1. **쓰기 경로의 트랜잭션 누락** — 여러 모델을 순차 호출하며 `transaction` 인자를 빠뜨리면 그 문장만 별도 커밋돼 부분 저장이 된다 (Phase 64 결함 2·3·4)
2. **`stocks` 원장 규약** — append-only. UPDATE/DELETE 금지, 조회·기록은 `product_branch_id` 기준 (`product_id` 컬럼은 없다)
3. **테넌트 경계** — 사용자가 준 `branchId`/`variantId`/`storeId` 를 소유권 확인 없이 쓰는 경로 (Phase 69 CR-02 유형)
4. **fail-open** — 권한·역할 판정에 실패했을 때 *더 주는* 분기 (Phase 65 W6 6-2 유형)
5. **트랜잭션 안 외부 I/O** — HTTP·프린터·소켓 호출은 커밋 후에 (pool 고갈)
