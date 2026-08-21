# Phase 85 W5 blue/green — codex 검토와 판단

- 대상 커밋: `api-ventago 37a85ab` (blue/green 권한 경계 + 리허설)
- 검토: `codex review --commit 37a85ab` · 2026-08-21
- 판단자: Claude Code

> **검토 경로 메모.** 루트에서 `codex-review.sh --working` 을 돌리면 서브모듈의 **수정된
> 추적 파일을 못 본다**(신규 파일만 걸린다 — 2026-08-21 핸드오프에 기록됨). 이번에는
> `codex exec` 에 diff 를 직접 넘겨 봤으나 40분간 출력 없이 멈췄다. 결국 **서브모듈에서
> 커밋한 뒤 `codex review --commit <sha>` 를 api-ventago 안에서 실행**해서 받았다.
> → 서브모듈 변경은 이 경로가 가장 확실하다.

---

## 지적 1건 — 수용

| ID | 지적 | 판단 |
|---|---|---|
| P2 | reload 실패 시 새 설정 파일이 남는다 (`ventago-switch-upstream.sh:79-82`) | **수용 — 고침 `d18aeb5`** |

### 근거 재확인

되돌리기 코드가 **두 벌**이었다.

```bash
# nginx -t 실패 분기 — 백업 없으면 지운다
if [ -f "$BACKUP" ]; then cp -f "$BACKUP" "$CONF"; else rm -f "$CONF"; fi

# reload 실패 분기 — 지우지 않는다  ← 여기
[ -f "$BACKUP" ] && cp -f "$BACKUP" "$CONF"
```

`$CONF` 가 **처음부터 없던 환경**(새 환경의 첫 전환)에서는 백업이 만들어지지 않는다.
그 상태로 reload 가 실패하면 스크립트는 "설정을 되돌린다" 고 **보고하면서** 새 설정을
디스크에 남긴다. 당장은 reload 가 안 됐으니 무해해 보이지만, **다음 nginx 재시작 때
그 upstream 이 살아나** 아무도 전환한 적 없는 포트로 트래픽이 간다.

★ 이 저장소의 반복 패턴이다 — **같은 일을 하는 코드가 두 곳에 있으면 반드시 한쪽만
고쳐진다.** `rollback()` 하나로 합쳤다.

### 스테이징 재현·검증

| | 결과 |
|---|---|
| 전제 만들기 | `conf` 와 `.bak` 을 **둘 다** 치우고 `/run/nginx.pid` 를 가려 reload 실패 유도 |
| 수정 전 | conf 가 `5013` 인 채로 남음 — **결함 재현** |
| 수정 후 | `exit=4` + 파일 없음 = 원래 상태 복원 ✓ |

★ **첫 시험은 전제가 틀려서 엉뚱한 분기를 검증할 뻔했다.** 이전 실행이 남긴 `.bak` 이
있어 `rm` 분기가 아니라 `cp` 분기를 탔고, 그 `.bak` 내용(5013)이 그대로 나오는 바람에
"수정이 안 먹었다" 로 보였다. **되돌리기 시험은 백업 부재를 먼저 확인해야 한다.**

---

## codex 가 짚지 않았지만 확인한 것

| 항목 | 확인 결과 |
|---|---|
| NOPASSWD 헬퍼 인자 우회 | 허용 밖 포트(`8080`) · 경로 주입(`../../etc/nginx`) · 명령 주입(`5012; rm -rf /tmp/x`) **전부 exit 2**. 경로는 스크립트 안에 박혀 있어 jenkins 가 지정할 수 없다 |
| jenkins 권한 상한 | "미리 정한 두 포트 중 하나를 가리키게 한다" 뿐. 임의 nginx 설정 쓰기·reload 는 열지 않았다 |
| 엉뚱한 컨테이너 종료 | `docker ps --filter publish=5002` 는 `api_ventago` 만 잡는다. `api_staging` 은 5002 를 **expose 만** 하고 publish 하지 않아 안 걸린다(실측) |
| 볼륨 | 전부 bind mount — compose project 를 갈라도 데이터가 끊기지 않는다(named volume 이었으면 project 접두사가 붙어 갈라졌다) |
| 전환 사실 확인 | 전환 후 upstream 파일을 **다시 읽어** 대조. 안 바뀌었으면 옛 컨테이너를 죽이지 않고 멈춘다 |

---

## 별건으로 발견 (W5 밖, 기록만)

- `/etc/sudoers.d/jhkim-bot: bad permissions, should be mode 0440` — **sudo 가 이 파일을
  통째로 무시하고 있다.** 그 파일이 주려던 권한은 지금 효력이 없다. 언제부터인지 미확인.
- `nginx.conf:64` 가 `include /etc/nginx/sites-enabled/*;` — 확장자 필터가 없어
  `*.bak` 들이 **실제로 로드된다**(`conflicting server name ... ignored` 경고의 정체).
  `newapi.coolsistema.com.conf.pre-bluegreen.bak` 안에는 `proxy_pass http://127.0.0.1:5002`
  가 하드코딩돼 있다 — 지금은 알파벳 순으로 정본이 이기지만, blue/green 이 5003 에 가 있는
  상태에서 순서가 바뀌면 트래픽이 upstream 을 우회한다. minio·deploy 에도 같은 형태 3개.
