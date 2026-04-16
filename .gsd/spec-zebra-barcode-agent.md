# SPEC: VentaGO Zebra Barcode Agent
생성일: 2026-04-16

## 목표
Zebra 라벨 프린터에 ZPL II 명령을 TCP Raw Socket으로 직접 전송하는 Electron 데스크탑 에이전트를 만든다.
기존 print-agent(영수증)와 동일한 아키텍처 패턴을 따르되, HTML→PNG 렌더링 단계를 완전히 제거하여 훨씬 단순한 파이프라인으로 구성한다.

---

## 배경 및 컨텍스트

### 기존 print-agent 구조 (참조)
```
WebSocket ← print_invoice / print_fiscal / print_temp
    ↓
formatter.js   → HTML 문자열 생성
    ↓
renderer-engine.js → Electron offscreen BrowserWindow → PNG Buffer
    ↓
printer.js     → ESC/POS 래스터 명령 → TCP 9100 → 감열 프린터
```

### ZPL 에이전트 구조 (새로 만들 것)
```
WebSocket ← print_barcode
    ↓
zpl-formatter.js   → ZPL II 문자열 생성 (렌더러 불필요)
    ↓
zebra-printer.js   → TCP Raw Socket → 포트 9100 → Zebra 프린터
```

### 핵심 단순화 포인트
- Electron BrowserWindow / offscreen 렌더러 → **완전 불필요**
- `escpos`, `escpos-network`, `escpos-usb` npm 패키지 → **불필요**
- ZPL은 텍스트 문자열이므로 `net.Socket`으로 직접 TCP 전송
- `electron-store` + `socket.io-client` 만 의존성으로 충분

### 기존 백엔드 활용 포인트
- 인증: 기존 `branch_printer_configs.api_key` 그대로 재사용
- WebSocket 네임스페이스: `/print-agent` 동일 사용 (단, 새 이벤트 `print_barcode` 추가)
- 브랜치 룸: `branch:{id}` 룸 그대로 사용
- `BranchPrinterConfig` 모델: `printerInfo` JSONB에 zebra 설정 추가 가능

---

## 기술 스택
- **언어/프레임워크**: Electron 28 + Node.js (기존 print-agent와 동일 버전)
- **프린터 통신**: Node.js `net` 모듈 (내장) — TCP Raw Socket 포트 9100
- **ZPL 생성**: 순수 문자열 템플릿 (npm 패키지 불필요)
- **설정 저장**: `electron-store` ^8
- **WebSocket**: `socket.io-client` ^4
- **바코드 타입**: Code 128 (`^BC`), EAN-13 (`^BE`), QR Code (`^BQ`)
- **빌드**: `electron-builder` (기존 GitHub Actions CI 재사용)
- **ESLint**: 기존 print-agent와 동일 규칙 적용

---

## 디렉토리 구조 (새로 생성)
```
ACE_online_1.0/
└── zebra-agent/           ← 새 폴더 (print-agent와 나란히)
    ├── main.js            ← Electron 메인 프로세스
    ├── preload.js         ← IPC 브릿지
    ├── package.json
    ├── renderer/
    │   ├── index.html     ← 메인 UI (상태 + 로그)
    │   ├── setup-wizard.html
    │   └── assets/
    │       └── style.css
    └── src/
        ├── zpl-formatter.js    ← 상품 데이터 → ZPL 문자열
        ├── zebra-printer.js    ← TCP Raw Socket 전송
        └── printer-discovery.js ← 네트워크 스캔 (포트 9100)
```

---

## ZPL 포맷 설계

### 라벨 규격 (기본값, 설정 가능)
- 용지 크기: 50mm × 30mm (상품 라벨 표준)
- 해상도: 203dpi (Zebra GK420d, ZD421 등 보급형 기준)
- 픽셀 환산: 50mm = 400dot, 30mm = 236dot

### ZPL 기본 구조
```
^XA                         (라벨 시작)
^PW400                      (용지 폭 400dot = 50mm)
^LL236                      (라벨 길이 236dot = 30mm)
^CI28                       (UTF-8 인코딩)

^FO20,10^A0N,28,28^FD{상품명}^FS        (상품명 텍스트)
^FO20,45^A0N,20,20^FD{가격}^FS          (가격 텍스트)
^FO20,75^BY2^BCN,60,Y,N,N^FD{바코드값}^FS  (Code128 바코드)
^FO20,145^A0N,18,18^FD{매장명}^FS       (매장명 텍스트)

^XZ                         (라벨 종료)
```

### print_barcode 이벤트 페이로드 설계
```json
{
  "branchId": 1,
  "items": [
    {
      "name": "Coca Cola 500ml",
      "price": 1500,
      "barcode": "7790895000107",
      "barcodeType": "EAN13",
      "qty": 3
    }
  ],
  "store": {
    "name": "VENTAGO TEST"
  },
  "label": {
    "width": 400,
    "height": 236,
    "copies": 1
  }
}
```
→ `items[].qty` 만큼 라벨을 반복 출력 (예: qty=3이면 동일 라벨 3장 출력)

---

## 태스크 목록

### Phase 1 — 프로젝트 뼈대
- [ ] TASK-01: `zebra-agent/package.json` 생성 — 의존성: electron-store, socket.io-client, electron, electron-builder
- [ ] TASK-02: `zebra-agent/src/zpl-formatter.js` — 상품 데이터 → ZPL 문자열 생성 함수
- [ ] TASK-03: `zebra-agent/src/zebra-printer.js` — TCP Raw Socket으로 ZPL 전송 (net.Socket)
- [ ] TASK-04: `zebra-agent/src/printer-discovery.js` — 서브넷 9100 포트 스캔 (기존 것 복사+경량화)

### Phase 2 — Electron 메인 프로세스
- [ ] TASK-05: `zebra-agent/main.js` — 트레이, 창 관리, electron-store, IPC 핸들러
- [ ] TASK-06: `zebra-agent/preload.js` — IPC 브릿지 (기존과 거의 동일, barcode 관련 추가)
- [ ] TASK-07: WebSocket 연결 로직 (initWebSocket) — `print_barcode` 이벤트 핸들러 포함
- [ ] TASK-08: 테스트 출력 함수 (`printTest`) — 샘플 ZPL로 라벨 1장 출력

### Phase 3 — 렌더러 UI
- [ ] TASK-09: `renderer/assets/style.css` — 기존 print-agent CSS 기반 (색상만 변경)
- [ ] TASK-10: `renderer/setup-wizard.html` — 초기 설정 (서버 URL, API Key, Zebra IP/포트)
- [ ] TASK-11: `renderer/index.html` — 메인 UI (연결상태, 프로파일, 로그, 라벨 설정)

### Phase 4 — 백엔드 확장 (NestJS)
- [ ] TASK-12: `print.service.ts`에 `emitPrintBarcode()` 메서드 추가
- [ ] TASK-13: `print.controller.ts`에 `POST /print/barcode` 엔드포인트 추가
- [ ] TASK-14: 프론트엔드 — 상품 목록에서 "Imprimir etiqueta" 버튼 + 라벨 수량 다이얼로그

### Phase 5 — 빌드 & 배포
- [ ] TASK-15: `zebra-agent/package.json` electron-builder 설정 (win nsis + mac dmg)
- [ ] TASK-16: `.github/workflows/build-zebra-agent.yml` GitHub Actions CI 추가
- [ ] TASK-17: ESLint 최종 검증 (오류 0개)
- [ ] TASK-18: `zebra-agent/RELEASE.md` 작성

---

## 완료 기준
- Zebra 프린터(TCP 9100)에 ZPL 라벨이 정상 출력됨
- 서버에서 `print_barcode` 이벤트 emit 시 자동 수신 후 출력
- Code 128, EAN-13, QR Code 3가지 바코드 타입 지원
- 연결 끊김 시 자동 재연결 (기존 print-agent와 동일)
- ESLint 오류 0개
- Windows + macOS 빌드 성공

---

## 금지사항 / 주의사항
- `escpos`, `escpos-network`, `escpos-usb` 패키지 사용 금지 (ZPL에 불필요)
- Electron BrowserWindow offscreen 렌더링 사용 금지 (ZPL은 텍스트라 불필요)
- TCP 연결 후 반드시 `socket.destroy()` 또는 `socket.end()` 호출 (연결 누수 방지)
- Pool 개념은 없지만 TCP 소켓은 요청마다 새로 생성 후 완료 즉시 닫기 (상태 유지 불필요)
- `net.Socket` 에러 핸들링 필수 (`error`, `timeout` 이벤트 모두 처리)
- ZPL 문자열에 `^CI28` 포함 필수 (UTF-8 인코딩 선언, 한글/특수문자 깨짐 방지)
- 기존 `print-agent` 폴더는 절대 수정하지 않음

---

## 구현 순서 (의존성 고려)
1. TASK-01 → 02 → 03 → 04 (src/ 먼저)
2. TASK-05 → 06 → 07 → 08 (main 프로세스)
3. TASK-09 → 10 → 11 (렌더러)
4. TASK-12 → 13 → 14 (백엔드 + 프론트)
5. TASK-15 → 16 → 17 → 18 (빌드/배포)

Phase 1~3 완료 후 로컬 테스트 (`electron .`), 통과 시 Phase 4 진행 권장.
