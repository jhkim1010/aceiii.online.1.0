# Ventago Edge Sync Agent (Phase 58)

지점 PC 에 설치되어 인터넷 단절 시에도 장사를 지속시키는 오프라인-퍼스트 에이전트.
Wave A 범위: 참조데이터 pull 동기화 + 재고 스냅샷 + 오프라인 조회 API.

## 설치 (지점 PC — 파일럿: coolsistema)

1. **PostgreSQL 16+ 설치** (Windows: EDB 인스톨러 / macOS: `brew install postgresql@16`)
2. **로컬 DB 생성**
   ```bash
   createdb ventago_edge
   ```
3. **의존성 설치** (인터넷 필요 — 최초 1회)
   ```bash
   cd edge-agent && npm install
   ```
4. **에이전트 등록** — Ventago 관리자 화면(또는 API)에서 지점에 edge 에이전트 생성:
   ```
   POST /print/agents { "branchId": <지점ID>, "agentType": "edge", "label": "Edge Sync" }
   ```
   응답의 `apiKey` 를 복사.
5. **설정** — `config.example.json` 을 `config.json` 으로 복사 후 `agentKey`, `localDb` 수정.
6. **실행**
   ```bash
   npm start            # 기본 (debug 로그)
   ```
   확인: `http://localhost:5010/api/health` → `{"ok":true, "cloudOnline":true}`

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
