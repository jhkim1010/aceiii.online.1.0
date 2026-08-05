워킹트리 검토에서 신규 파일이 누락되고, 일부 일반적인 자격증명 형식이 리댁션되지 않아 핵심 보안 검토 흐름을 신뢰할 수 없습니다. 큰 diff를 명령행 인자로 전달하는 방식도 정상적인 규모의 작업에서 실행 실패를 유발할 수 있습니다.

Full review comments:

- [P1] 추적되지 않은 신규 파일도 워킹트리 검토에 포함하세요 — /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/scripts/codex-review.sh:74-74
  `--working` 사용 시 `git diff HEAD`는 추적 중인 파일만 보여주므로, 새 엔드포인트나 마이그레이션처럼 아직 `git add`하지 않은 파일은 검토에서 완전히 누락됩니다. 신규 파일만 존재하면 스크립트가 "검토할 변경이 없습니다"라고 잘못 종료하여 커밋 전 보안 검토를 우회할 수 있으므로, untracked 파일도 별도로 수집해 diff에 포함해야 합니다.

- [P1] 따옴표 없는 비밀번호도 전송 전에 차단하세요 — /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/scripts/codex-review.sh:90-93
  `password: secret123` 같은 YAML/설정 형식은 현재 치환 규칙과 fail-closed 검사 모두 따옴표를 요구하므로 원문 그대로 Codex에 전송되고 dry-run 프롬프트에도 기록됩니다. 이는 저장소의 자격증명 유출 금지 규칙([AGENTS.md:41-44](../AGENTS.md#L41-L44))과 스크립트가 표방한 fail-closed 동작을 위반하므로, 따옴표 없는 값도 리댁션하거나 잔존 검사에서 중단해야 합니다.

- [P2] 큰 diff를 명령행 인자 대신 표준 입력으로 전달하세요 — /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/scripts/codex-review.sh:137-137
  전체 diff가 포함된 `PROMPT`를 단일 명령행 인자로 전달하면 큰 작업에서는 운영체제의 `ARG_MAX`를 초과해 `codex exec`가 실행조차 되지 않습니다. 이 스크립트는 수십 KB 이상의 diff를 명시적으로 고려하고 있으므로, 프롬프트를 표준 입력이나 임시 파일로 전달해야 대규모 검토가 안정적으로 동작합니다.
