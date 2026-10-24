# Ventago Guardia — servidor local de la sucursal (Phase 58)

> 화면·설치 프로그램에 보이는 이름은 **Guardia** (2026-10-16 사용자 결정). 내부 이름(폴더 `edge-agent`,
> DB `agent_type='edge'`, `/api/edge/*`, `ventago_edge` DB)은 그대로 둔다 — 바꿔도 보이는 차이가 없다.

지점 PC 에 설치되어 인터넷 단절 시에도 장사를 지속시키는 오프라인-퍼스트 에이전트.
Wave A 범위: 참조데이터 pull 동기화 + 재고 스냅샷 + 오프라인 조회 API.

## 설치 — Windows (권장: 스크립트 사용)

★ **이것은 설치 프로그램(.exe)이 아니다.** print-agent·zebra-agent 는 Electron 앱이라
`.exe`/`.dmg` 로 포장되지만, edge 는 **로컬 PostgreSQL 이 필요한 Node 서비스**다.
Node·PG 를 번들한 인스톨러는 별도 작업이고, 그전까지는 이 스크립트가 나머지를 다 한다.

```powershell
# PowerShell 을 **관리자 권한**으로 열고, edge-agent 폴더에서
Set-ExecutionPolicy -Scope Process Bypass -Force
.\install.ps1
```

스크립트가 하는 일 (6단계):

| 단계 | 내용 |
|---|---|
| 1 | 요구사항 확인 — Node ≥18, PostgreSQL. **없으면 설치하지 않고** 무엇이 없는지·어디서 받는지 알려주고 멈춘다 |
| 2 | 로컬 DB `ventago_edge` 생성 (이미 있으면 **건드리지 않는다** — 미러와 outbox 가 보존된다) |
| 3 | `npm install --omit=dev` |
| 4 | `config.json` 작성 (agentKey 를 물어본다) + **파일 권한 제한** — 이 파일에 PG 비밀번호와 agentKey 가 들어간다 |
| 5 | ★ **자동 시작 등록** — Windows 시작 시 실행, 죽으면 1분마다 재시도 |
| 6 | 실행 후 `/api/health` 확인 |

★★ 5단계가 핵심이다. **이게 없으면 재부팅 후 에이전트가 스스로 안 올라온다** —
파일럿(coolsistema)이 2026-07-20 이후 꺼져 있던 이유가 바로 이것이다.

**agentKey 받는 법**: Ventago 화면에서 `Sucursales → Impresoras` 로 가서 그 지점에
`agentType='edge'` 에이전트를 추가하고 발급된 `apiKey` 를 복사한다.

다시 돌려도 안전하다(멱등). 설정만 새로 쓰려면 `.\install.ps1 -Reconfigurar`.

**운영 명령**
```powershell
Stop-ScheduledTask  -TaskName VentagoGuardia   # 중지
Start-ScheduledTask -TaskName VentagoGuardia   # 시작
Get-ScheduledTaskInfo -TaskName VentagoGuardia # 마지막 실행 결과
```

## 설치 — macOS (스크립트, 2026-10-24)

Windows 의 `install.ps1` 과 같은 6단계를 `install-mac.sh` 가 한다. Node·PostgreSQL 은 **설치하지 않는다**
(없으면 무엇이 없는지·`brew` 명령을 알려주고 멈춘다). 다시 돌려도 안전하다(멱등).

```bash
cd edge-agent
./install-mac.sh                    # 설치 / 재실행
./install-mac.sh --reconfigurar     # config.json 다시 쓰기
./install-mac.sh --solo-plist /tmp/x  # plist 만 만들어 본다 (시스템은 안 건드림)
./install-mac.sh --desinstalar      # LaunchAgent 제거 (DB·config.json 은 그대로)
```

| 단계 | 내용 |
|---|---|
| 1 | Node ≥18 · PostgreSQL(brew `postgresql@NN` 은 keg-only 라 경로를 찾아 PATH 에 붙인다) |
| 2 | `ventago_edge` 가 **없을 때만** 생성 |
| 3 | `npm install --omit=dev` |
| 4 | `config.json` 작성 (agentKey 질문) + `chmod 600` |
| 5 | **LaunchAgent** `~/Library/LaunchAgents/com.ventago.guardia.plist` — RunAtLoad + KeepAlive, ThrottleInterval 60초(Windows 의 1분 재시도와 같음), stdout/stderr → `logs/launchd.*.log` |
| 6 | 실행 후 `/api/health` 확인 |

★ LaunchAgent 는 **사용자 로그인 시** 뜬다(로그인 없이 부팅만으로 뜨는 LaunchDaemon 이 아니다).
  매장 Mac 은 자동 로그인을 켜 두는 것을 전제로 한다.

**운영 명령 (macOS)**
```bash
launchctl bootout   gui/$(id -u)/com.ventago.guardia                          # 중지
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.ventago.guardia.plist  # 시작
launchctl kickstart -k gui/$(id -u)/com.ventago.guardia                       # 재시작
launchctl print gui/$(id -u)/com.ventago.guardia | head -30                   # 상태
tail -f logs/edge-agent-$(date +%F).log                                       # 로그
```

## 업데이트 — 웹에서 확인 후 Guardia 가 스스로 (2026-10-24)

목업: `.planning/mockups/2026-10-24-guardia-actualizacion/`. **혼자서 업데이트하지 않는다** —
Sucursales › Impresoras 에서 권한 있는 사람(superadmin·매장 admin)이 「Actualizar…」를 누르고 확인해야 한다.

1. Guardia 는 모든 요청에 `x-agent-version`, manifest 에 `outbox`(미전송 오프라인 판매)·`idleSec`(마지막 오프라인 사용 후 초)을 보낸다.
2. 서버가 주문을 만들면 manifest 응답의 `updateOrder` 로 내려온다. 「Al cerrar la caja」 주문은 서버가
   **그 지점에 열린 caja 가 없을 때만** 내려준다(최대 3일, 「ahora」는 30분 후 만료).
3. Guardia 가 다시 확인: 클라우드 온라인 · outbox pending 0 · 오프라인 사용 후 5분 경과. 아니면 `esperando` 보고 후 다음 manifest 에 재확인.
4. 다운로드(https·`github.com/jhkim1010/ventago-downloads` 만) → **sha256 대조** → `.actualizacion/staging-<v>/` 에 풀고 `npm install --omit=dev`
   → 조건 재확인 → 항목별 rename 으로 교체(옛 것은 `.actualizacion/anterior/`) → 종료코드 75.
   교체 전 어떤 실패도 옛 버전 그대로 + 서버에 `error` 보고. 교체 도중 실패는 되돌린다.
5. `src/index.js`(supervisor)가 `src/main.js` 를 fork 해 두었다가 75 를 받으면 **즉시** 새 버전으로 다시 띄운다
   — Windows 작업 스케줄러·launchd 재시작에 기대지 않는다. 새 버전이 2분 안에 죽으면 `anterior` 로 되돌리고
   그 버전을 `fallidas` 에 적어 다시 받지 않는다.
6. **절대 안 건드림**: `config.json` · `logs/` · 로컬 DB `ventago_edge`.

★ Guardia 가 **못 보는 것**: 온라인 판매(브라우저→클라우드 직행)와 카트에 담는 중인 판매. caja 상태는 서버가 본다.
★ 0.2.0 이하는 이 기능이 없다 — **첫 0.3.0 은 손으로 설치**(스크립트 재실행)해야 그 다음부터 웹에서 된다.
★ 릴리스: `edge-agent/publicar-guardia.sh "notas"` (커밋된 HEAD 의 edge-agent 를 `git archive` → `guardia-<v>.tgz` 먼저, `version.json` 나중).

## 설치 — 수동 (Linux / 스크립트를 못 쓸 때)

1. **PostgreSQL 14+** 설치 (macOS: `brew install postgresql@16`)
2. `createdb ventago_edge`
3. `cd edge-agent && npm install`
4. Ventago 에서 edge 에이전트 생성 → `apiKey` 복사
   (또는 `POST /print/agents { "branchId": <지점ID>, "agentType": "edge", "label": "Edge Sync" }`)
5. `config.example.json` → `config.json` 복사 후 `agentKey`·`localDb` 수정
6. `npm start` — 확인: `http://localhost:5010/api/health` → `{"ok":true,"cloudOnline":true}`

★ 수동 설치는 **자동 재시작이 없다.** `pm2`·`systemd` 중 하나로 직접 걸어야 한다 (macOS 는 위 스크립트가 launchd 로 건다).

## 지금 할 수 있는 것 / 없는 것 (2026-09-09)

오프라인에서 **되는 것**: 상품 조회(`/api/offline/product-lookup`) · 판매 캡처
(`POST /api/offline/sales`) · 코만다/라벨 인쇄.

★★ **아직 안 되는 것**: 오프라인에서 화면의 **GET 요청은 전부 클라우드로 나가 실패한다**
(판매 목록·카하 상태 등). 「판매 한 바퀴」가 온전히 돌려면 계획의 **B 웨이브**(엣지에
클라우드와 같은 모양의 조회 API ≈10개)가 필요하다. 그래서 지금은 **파일럿 1대**로
검증하는 단계이고, 여러 지점에 배포할 시점이 아니다.
또한 **72시간 신선도 게이트(D)** 가 없어서, 오래 끊긴 미러로도 팔 수 있다 —
옛 가격이 나갈 수 있다는 뜻이다.

## 디버깅

- 로그 파일: `logs/edge-agent-YYYY-MM-DD.log` (콘솔과 동일 내용, 일자별)
- 동기화 상태: `GET /api/edge/status` — 테이블별 커서/행수/에러, outbox 현황
- 수동 동기화: `POST /api/edge/sync-now`
- 오프라인 조회 테스트: `GET /api/offline/product-lookup?q=<바코드>`
- 로그 레벨: config.json `logLevel` 또는 `EDGE_LOG_LEVEL=info npm start`

## 상태 전이 로그 읽는 법

- `>>> ONLINE (manifest ok)` — 클라우드 연결+인증 정상
- `>>> OFFLINE (probe fail #N)` — 단절 감지 (15초 간격 프로브)
- `agentKey UNAUTHORIZED` — 단절이 아니라 키 문제. config.json 확인.
- `[cycle#N] done — +X rows` — 증분 pull 결과. X=0 이면 변경 없음(정상).

## 아키텍처 메모

- 미러는 테이블별 DDL 복제가 아니라 **JSONB 제네릭 미러**(mirror_rows) — 서버 스키마가
  바뀌어도 edge 는 무중단.
- 재고는 stocks 원장을 복제하지 않고 서버 집계 스냅샷(mirror_stock)을 1분 주기 수신.
- hard delete 는 시간당 1회 `/offline-sync/ids` 대조로 prune.
- 커서는 서버가 준 값만 사용 — 지점 PC 시계가 틀려도 무관.
- 로컬 pool: max 5 / idle 30s (지점 PC 사양 고려, release 는 finally 보장).
