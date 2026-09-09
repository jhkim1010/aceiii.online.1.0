# Ventago Edge Sync Agent (Phase 58)

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
Stop-ScheduledTask  -TaskName VentagoEdgeAgent   # 중지
Start-ScheduledTask -TaskName VentagoEdgeAgent   # 시작
Get-ScheduledTaskInfo -TaskName VentagoEdgeAgent # 마지막 실행 결과
```

## 설치 — 수동 (macOS / Linux / 스크립트를 못 쓸 때)

1. **PostgreSQL 14+** 설치 (macOS: `brew install postgresql@16`)
2. `createdb ventago_edge`
3. `cd edge-agent && npm install`
4. Ventago 에서 edge 에이전트 생성 → `apiKey` 복사
   (또는 `POST /print/agents { "branchId": <지점ID>, "agentType": "edge", "label": "Edge Sync" }`)
5. `config.example.json` → `config.json` 복사 후 `agentKey`·`localDb` 수정
6. `npm start` — 확인: `http://localhost:5010/api/health` → `{"ok":true,"cloudOnline":true}`

★ 수동 설치는 **자동 재시작이 없다.** `pm2`·`systemd`·`launchd` 중 하나로 직접 걸어야 한다.

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
