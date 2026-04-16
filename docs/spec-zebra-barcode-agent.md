# SPEC: VentaGO Zebra Barcode Agent (옵션 B — branch_agents 통합 테이블)
생성일: 2026-04-16

## 목표
Zebra 라벨 프린터에 ZPL II 명령을 TCP Raw Socket으로 직접 전송하는 독립 Electron 데스크탑 에이전트를 만든다.
한 지점에서 여러 대의 comandera térmica + zebra 를 혼용 운용할 수 있도록,
기존 `branch_printer_configs` (branchId UNIQUE 제약) 를 폐기하고
`branch_agents` 통합 테이블로 교체한다.

---

## 배경 및 컨텍스트

### 기존 구조의 한계
```
branch_printer_configs
  - branchId  UNIQUE  ← 지점당 에이전트 1개만 허용 → 다중 프린터 불가
  - apiKey
  - isOnline
  - printerInfo (JSONB)
```

### 새 구조 (branch_agents)
```
branch_agents
  - id          PK (SERIAL)
  - branchId    FK → branches (NOT UNIQUE → 지점당 N개 허용)
  - agentType   VARCHAR(20): 'thermal' | 'zebra'
  - label       VARCHAR(100): 'Comandera Cocina', 'Zebra Almacén' 등
  - apiKey      VARCHAR(64) UNIQUE
  - printerConfig  JSONB    (type, host, port, vendorId, productId 등)
  - isOnline    BOOLEAN DEFAULT false
  - lastSeenAt  TIMESTAMP
  - socketId    VARCHAR(64)   ← 연결된 소켓 ID (disconnect 처리용)
  - createdAt, updatedAt
```

### 영향 범위
| 계층 | 파일 | 변경 내용 |
|------|------|-----------|
| DB | (마이그레이션) | `branch_agents` 테이블 신설, `branch_printer_configs` 데이터 이전 후 폐기 |
| 백엔드 모델 | `branch-agent.model.ts` (신규) | 새 Sequelize 모델 |
| 백엔드 서비스 | `print.service.ts` | `BranchPrinterConfig` → `BranchAgent` 교체 |
| 백엔드 게이트웨이 | `print.gateway.ts` | 동일 인증 로직, 모델만 교체 |
| 백엔드 컨트롤러 | `print.controller.ts` | 에이전트 목록/생성/삭제 API 추가 |
| 프론트엔드 | `PrinterConfigTab.tsx`, `impresora.tsx` | 다중 에이전트 UI로 개편 |
| 새 앱 | `zebra-agent/` | Electron ZPL 에이전트 (신규) |

---

## 기술 스택

### zebra-agent (새 Electron 앱)
- **Electron**: 28 (기존 print-agent와 동일)
- **프린터 통신**: Node.js `net` 모듈 (내장) — TCP Raw Socket 포트 9100
- **ZPL 생성**: 순수 문자열 템플릿 (npm 패키지 불필요)
- **설정 저장**: `electron-store` ^8
- **WebSocket**: `socket.io-client` ^4
- **의존성**: `electron-store`, `socket.io-client` 두 개만 (escpos 계열 전혀 없음)
- **빌드**: `electron-builder` (GitHub Actions CI)

### 백엔드 (api-ventago)
- **ORM**: Sequelize + sequelize-typescript (underscored: true)
- **DB**: PostgreSQL 15
- **sync**: `alter: false, force: false` → 마이그레이션은 raw SQL로 직접 실행

---

## 디렉토리 구조

### zebra-agent (신규)
```
ACE_online_1.0/
├── print-agent/           ← 기존 (건드리지 않음)
└── zebra-agent/           ← 새로 생성
    ├── main.js
    ├── preload.js
    ├── package.json
    ├── RELEASE.md
    ├── renderer/
    │   ├── index.html
    │   ├── setup-wizard.html
    │   └── assets/
    │       └── style.css
    └── src/
        ├── zpl-formatter.js       ← 상품 데이터 → ZPL 문자열
        ├── zebra-printer.js       ← TCP Raw Socket 전송
        └── printer-discovery.js  ← 서브넷 9100 포트 스캔
```

### 백엔드 변경 파일
```
api-ventago/src/app/print/
├── branch-agent.model.ts          ← 신규 (BranchAgent Sequelize 모델)
├── branch-printer-config.model.ts ← 폐기 예정 (마이그레이션 후 삭제)
├── print.gateway.ts               ← 수정 (모델 교체)
├── print.service.ts               ← 수정 (모델 교체 + 에이전트 CRUD)
├── print.module.ts                ← 수정 (모델 등록 교체)
└── print.controller.ts            ← 수정 (에이전트 목록/생성/삭제/바코드 emit 추가)
```

---

## ZPL 포맷 설계

### 라벨 규격 (기본값, 설정 화면에서 변경 가능)
- 용지 크기: 50mm × 30mm
- 해상도: 203dpi
- 픽셀 환산: 50mm = 400dot, 30mm = 236dot

### ZPL 템플릿 (Code 128 예시)
```
^XA
^PW400
^LL236
^CI28
^FO20,10^A0N,28,28^FD{상품명}^FS
^FO20,45^A0N,22,22^FD${가격}^FS
^FO20,80^BY2^BCN,60,Y,N,N^FD{바코드값}^FS
^FO20,160^A0N,18,18^FD{매장명}^FS
^XZ
```

### WebSocket 이벤트 페이로드 (`print_barcode`)
```json
{
  "agentId": 3,
  "items": [
    {
      "name": "Coca Cola 500ml",
      "price": 1500,
      "barcode": "7790895000107",
      "barcodeType": "CODE128",
      "qty": 3
    }
  ],
  "store": { "name": "VENTAGO TEST" },
  "label": { "width": 400, "height": 236, "copies": 1 }
}
```
- `agentId`: 특정 zebra 에이전트 지정 (없으면 지점 전체 broadcast)
- `items[].qty`: 해당 수량만큼 동일 라벨 반복 출력
- `barcodeType`: `CODE128` | `EAN13` | `QR`

---

## DB 마이그레이션 전략

### 순서 (운영 서버 안전 적용)
```sql
-- 1. 새 테이블 생성
CREATE TABLE branch_agents (
  id             SERIAL PRIMARY KEY,
  branch_id      INTEGER NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  agent_type     VARCHAR(20) NOT NULL DEFAULT 'thermal',
  label          VARCHAR(100) NOT NULL DEFAULT 'Agente de Impresión',
  api_key        VARCHAR(64) NOT NULL UNIQUE,
  printer_config JSONB,
  is_online      BOOLEAN NOT NULL DEFAULT false,
  last_seen_at   TIMESTAMP WITH TIME ZONE,
  socket_id      VARCHAR(64),
  created_at     TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_branch_agents_branch_id ON branch_agents(branch_id);
CREATE INDEX idx_branch_agents_api_key   ON branch_agents(api_key);

-- 2. 기존 데이터 이전 (branch_printer_configs → branch_agents)
INSERT INTO branch_agents (branch_id, agent_type, label, api_key, printer_config, is_online, last_seen_at, created_at, updated_at)
SELECT
  branch_id,
  'thermal',
  'Comandera Principal',
  api_key,
  printer_info,
  false,           -- 재연결 시 다시 online
  last_seen_at,
  created_at,
  updated_at
FROM branch_printer_configs;

-- 3. 검증 후 기존 테이블 폐기 (별도 작업, 백엔드 배포 완료 후)
-- DROP TABLE branch_printer_configs;
```

---

## 태스크 목록

### Phase 0 — DB 마이그레이션 (백엔드 배포 전 선행)
- [ ] TASK-00: `branch_agents` 테이블 생성 + 데이터 이전 SQL 실행 (Docker exec)
- [ ] TASK-01: 마이그레이션 결과 검증 (SELECT COUNT 비교)

### Phase 1 — 백엔드 모델/서비스 교체
- [ ] TASK-02: `branch-agent.model.ts` 신규 생성 (BranchAgent Sequelize 모델)
- [ ] TASK-03: `print.service.ts` 교체 — BranchAgent 기반으로 전면 재작성
  - `validateApiKey(apiKey)` → BranchAgent 반환
  - `getOrCreateAgent(branchId, agentType, label)` 추가
  - `listAgents(branchId)` 추가
  - `deleteAgent(id)` 추가
  - `emitPrintInvoice()`, `emitPrintTemp()`, `emitPrintBarcode()` 유지
  - `setOnline()`, `setOfflineBySocketId()` 유지
- [ ] TASK-04: `print.gateway.ts` 수정 — BranchAgent 기반 인증
- [ ] TASK-05: `print.module.ts` 수정 — 모델 등록 교체
- [ ] TASK-06: `print.controller.ts` 확장
  - `GET /print/agents/:branchId` — 에이전트 목록
  - `POST /print/agents` — 에이전트 생성
  - `DELETE /print/agents/:id` — 에이전트 삭제
  - `POST /print/agents/:id/regenerate-key` — API Key 재발급
  - `POST /print/barcode` — 바코드 출력 emit (신규)
  - 기존 `/print/config/:branchId` 하위 호환 유지 (→ thermal 타입 에이전트로 위임)

### Phase 2 — zebra-agent Electron 앱
- [ ] TASK-07: `zebra-agent/package.json` 생성 (의존성 최소화)
- [ ] TASK-08: `zebra-agent/src/zpl-formatter.js` — ZPL 문자열 생성
  - `formatBarcodeLabel(item, store, labelSize)` → ZPL 문자열
  - CODE128, EAN13, QR 3가지 타입 지원
- [ ] TASK-09: `zebra-agent/src/zebra-printer.js` — TCP Raw Socket 전송
  - `sendZpl(zplString, host, port)` → Promise
  - 연결 후 ZPL 전송 → `socket.end()` 보장 (누수 방지)
  - timeout, error 이벤트 핸들링 필수
- [ ] TASK-10: `zebra-agent/src/printer-discovery.js` — 서브넷 9100 스캔
- [ ] TASK-11: `zebra-agent/main.js` — 메인 프로세스
  - electron-store 설정 (agentType: 'zebra' 고정)
  - 트레이 + 창 관리
  - IPC 핸들러 (store, ws, printer, setup, profile)
  - `initWebSocket()` — `print_barcode` 이벤트 핸들러
  - `printTest()` — 샘플 ZPL 출력
- [ ] TASK-12: `zebra-agent/preload.js` — IPC 브릿지
- [ ] TASK-13: `zebra-agent/renderer/assets/style.css`
- [ ] TASK-14: `zebra-agent/renderer/setup-wizard.html` — 초기 설정 마법사
- [ ] TASK-15: `zebra-agent/renderer/index.html` — 메인 UI

### Phase 3 — 프론트엔드 UI 개편
- [ ] TASK-16: `PrinterConfigTab.tsx` — 다중 에이전트 목록 UI
  - thermal / zebra 구분 표시
  - 에이전트 추가 / 삭제 / API Key 재발급
- [ ] TASK-17: `impresora.tsx` — 지점 프린터 관리 페이지 개편

### Phase 4 — 빌드 & 배포
- [ ] TASK-18: `zebra-agent/package.json` electron-builder 설정
- [ ] TASK-19: `.github/workflows/build-zebra-agent.yml` CI 추가
- [ ] TASK-20: ESLint 최종 검증 (백엔드 + 프론트 + zebra-agent 모두)
- [ ] TASK-21: `zebra-agent/RELEASE.md` 작성

---

## 완료 기준
- 한 지점에 thermal 2대 + zebra 2대 동시 연결 가능
- `print_barcode` 이벤트 수신 시 ZPL 라벨 정상 출력
- CODE128, EAN13, QR 3가지 바코드 타입 지원
- 기존 print-agent (thermal) 동작 영향 없음
- ESLint 오류 0개
- Windows + macOS 빌드 성공

---

## 금지사항 / 주의사항
- **기존 `print-agent/` 폴더 절대 수정 금지**
- `escpos`, `escpos-network`, `escpos-usb` 패키지 사용 금지 (ZPL 에이전트에 불필요)
- Electron offscreen 렌더링 사용 금지 (ZPL은 텍스트)
- TCP 소켓은 요청마다 생성 → 완료 즉시 `socket.end()` 호출 필수 (누수 방지)
- `net.Socket` `error`, `timeout` 이벤트 핸들링 필수
- ZPL 문자열에 `^CI28` 포함 필수 (UTF-8, 한글/특수문자 대비)
- DB 마이그레이션: `branch_printer_configs` DROP은 백엔드 배포 + 검증 완료 후 별도 실행
- `socketId` 컬럼을 `branch_agents`에 두어 `setOfflineBySocketId` raw SQL 제거 가능

---

## 구현 순서
1. **TASK-00~01** — DB 마이그레이션 (가장 먼저)
2. **TASK-02~06** — 백엔드 교체 + 배포
3. **TASK-07~15** — zebra-agent 앱 구현
4. **TASK-16~17** — 프론트엔드 UI 개편
5. **TASK-18~21** — 빌드/배포
