> ★ 이 보고서는 **Phase 85 세션이 우연히 만든 것**이다 (2026-08-20 밤).
> `scripts/codex-review.sh --working` 이 워킹트리 전체를 보므로, 같은 워킹트리에 있던
> Phase 86 의 untracked 파일(`tools/phase86/`, `migrations/2026-08-20-phase86-*.sql`)이
> 검토 대상에 들어갔다. 지적은 **전부 Phase 86 것**이고 Phase 85 는 손대지 않았다.
> `working-codex.md` 는 다음 codex 실행마다 덮어써지므로 여기 복사해 남긴다.
>
> Phase 86 세션이 판단할 것 — 수용/반박은 그쪽에서 기록하십시오.

게이트가 미구현 작업을 성공으로 판정하고 반복 실행 및 서브모듈 변경 검증도 제대로 지원하지 않습니다. 또한 운영 판매 테이블의 CHECK 교체가 POS 쓰기를 장시간 차단할 수 있습니다.

Full review comments:

- [P1] 미구현 wave를 실패로 처리하세요 — /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/tools/phase86/gate.sh:69-73
  w2 검증 파일이 없을 때 주석의 규약과 달리 `FAIL`을 증가시키지 않아 `gate.sh all`이 w2~w5가 전부 미구현이어도 `ALL GREEN`으로 종료합니다. 이 종료 코드를 자율 루프의 유일한 판정 기준으로 사용하므로 구현이 누락된 상태를 완료로 오판합니다.

- [P1] 반복 실행 전에 샌드박스 스키마를 초기화하세요 — /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/tools/phase86/bootstrap-schema.sql:2-5
  첫 실행 후 동일한 PGDATA로 게이트를 다시 돌리면 bootstrap의 무조건 `CREATE TABLE`이 `relation already exists`로 실패하고, 뒤의 동작 검증도 고정 키 행을 다시 삽입해 unique violation을 냅니다. RUNBOOK의 수정-재실행 루프에서 두 번째 실행부터 정상 패치도 통과할 수 없으므로 별도 테스트 DB를 재생성하거나 스키마를 먼저 초기화해야 합니다.

- [P1] sales CHECK 검증 중 장시간 배타 잠금을 피하세요 — /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/migrations/2026-08-20-phase86-sales-source-legacy.sql:34-36
  운영의 누적 `sales` 테이블에서 이 `ADD CONSTRAINT CHECK`는 기존 행 전체를 검증하는 동안 강한 테이블 잠금을 잡아 POS 판매 INSERT/UPDATE를 막을 수 있습니다. 먼저 `NOT VALID`로 짧게 제약을 추가한 뒤 별도로 `VALIDATE CONSTRAINT`하는 방식으로 잠금 범위를 줄여야 합니다. 프로젝트도 POS 병목과 넓은 잠금을 장애로 취급합니다([AGENTS.md:42-52](../../AGENTS.md#L42-L52)).

- [P2] 서브모듈 내부 변경 파일을 직접 수집하세요 — /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/tools/phase86/gate.sh:92-94
  루트에서 실행한 `git diff --name-only`는 서브모듈 내부 파일 대신 `api-ventago` 한 항목만 반환하고, 루트 `git ls-files -o`도 서브모듈 안의 untracked 파일을 열거하지 않습니다. 따라서 현재와 같은 API 변경에서도 `API_FILES`가 비어 변경 파일 ESLint가 항상 건너뛰어지므로 각 서브모듈 안에서 diff/status를 수집해야 합니다.
