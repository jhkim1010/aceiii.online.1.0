---
phase: 11
plan: 04
subsystem: backend+frontend+packaging
tags: [nestjs, websocket, sequelize, electron-builder, print-agent, branch-printer-config]
requires: [11-03]
provides:
  - BranchPrinterConfig 모델 + branch_printer_configs 테이블
  - PrintService.emitPrintInvoice / emitFiscalReceipt (fire-and-forget)
  - PrintGateway /print-agent 네임스페이스 + API Key 인증
  - GET/POST /print/config/:branchId REST 엔드포인트
  - PrinterConfigTab 프론트 UI (30초 폴링 + API Key 관리 + 설치 가이드)
  - electron-builder Windows NSIS / macOS DMG 패키징 설정
affects: [api-ventago/src/app/print, ventago-app/src/views/branches, ventago-app/src/pages/sucursales, print-agent/package.json]
tech-stack:
  added: [@nestjs/websockets PrintGateway, electron-builder NSIS+DMG configuration]
  patterns: [fire-and-forget WebSocket emit, single SELECT validateApiKey, JSONB socketId tracking, 30s polling without WebSocket on frontend]
key-files:
  created:
    - api-ventago/src/app/print/branch-printer-config.model.ts
    - api-ventago/src/app/print/print.service.ts
    - api-ventago/src/app/print/print.gateway.ts
    - api-ventago/src/app/print/print.controller.ts
    - api-ventago/src/app/print/print.module.ts
    - ventago-app/src/views/branches/components/printer/PrinterConfigTab.tsx
    - ventago-app/src/pages/sucursales/[id]/impresora.tsx
  modified:
    - api-ventago/src/app.module.ts
    - print-agent/package.json
decisions:
  - branch_printer_configs 별도 테이블 도입 — 기존 branches.api_key 컬럼은 레거시 sales-create 경로에 남겨두고 점진적 마이그레이션
  - 마이그레이션 파일 대신 Sequelize 모델 + sync 의존 — 프로젝트가 sync({alter:false}) 패턴 사용 중
  - 30s 폴링 (REST) 채택 — 관리자 화면 전용이라 WebSocket 오버헤드 불필요, pool 낭비 최소화
  - PrintGateway에 forwardRef로 PrintService 주입 — 양방향 의존(서비스가 게이트웨이의 server.emit 사용) 해소
  - emitFiscalReceipt 메서드는 완전 구현하되 호출처(facturacion.service.ts)는 Phase 10 미구현으로 TODO 표시
metrics:
  duration: 20min
  completed: 2026-04-07
---

# Phase 11 Plan 04: 백엔드 PrintService + 프론트 설정 UI + 패키징 Summary

Wave 4는 Wave 1-3에서 구축한 print-agent (Electron 데스크탑 앱)를 백엔드/프론트와 묶고 배포 가능한 인스톨러로 패키징하는 단계.

## What Was Built

### 1. NestJS PrintModule (`api-ventago/src/app/print/`)

**`branch-printer-config.model.ts`** — Sequelize 모델
- 테이블 `branch_printer_configs` (snake_case 자동 매핑)
- `branchId` UNIQUE FK → branches
- `apiKey` VARCHAR(64) UNIQUE, 기본값 `vg_pr_<uuid32>`
- `isOnline`, `lastSeenAt`, `printerInfo JSONB`

**`print.service.ts`**
- `emitPrintInvoice(branchId, data)` — fire-and-forget, room `branch:{id}`
- `emitFiscalReceipt(branchId, data)` — Phase 10 (AFIP) wiring 대기 중 (TODO 코멘트)
- `validateApiKey(apiKey)` — 단일 SELECT
- `getOrCreateConfig(branchId)` — 자동 생성
- `regenerateApiKey(branchId)`
- `setOnline / setOfflineBySocketId` — JSONB raw query 1회

**`print.gateway.ts`** — Socket.io 게이트웨이
- 네임스페이스 `/print-agent`
- `handleConnection`: handshake.auth.token API Key 검증 → 실패 시 즉시 disconnect
- 성공 시 `branch:{id}` room 자동 등록
- `agent_online`, `print_ack`, `register_api_key` (Wave 3 호환) 핸들러

**`print.controller.ts`** — JWT 보호 REST
- `GET /print/config/:branchId` → `{ apiKey, isOnline, lastSeenAt }`
- `POST /print/config/:branchId/regenerate-key` → `{ apiKey }`

**`print.module.ts`** — `app.module.ts`에 등록 완료

### 2. 프론트 PrinterConfigTab

**`PrinterConfigTab.tsx`** — 단일 컴포넌트, 3개 카드
- **에이전트 상태**: Chip(green/grey) + 마지막 접속 표시 (`hace N minutos`), 30초 폴링
- **API Key**: TextField 읽기전용 + 클립보드 복사 + Regenerar 버튼 (확인 다이얼로그)
- **설치 가이드**: 다운로드 버튼(추후 wiring) + 서버 URL/API Key 자동 채워진 코드블록

**`pages/sucursales/[id]/impresora.tsx`** — 라우트 신설
- 기존 `sucursales/index.tsx`는 `BranchList` 1뷰만 렌더링하고 동적 ID 라우팅 없었음 → 별도 페이지 신설
- `WithAccess` 가드 (`admin` app, `sucursales` module)

### 3. electron-builder 패키징 (`print-agent/package.json`)

- `appId: com.coolsistema.ventago-print`
- `asar: true` 소스 보호
- Windows NSIS oneClick installer (x64) — `build/VentaGO Print Agent Setup 1.0.0.exe`
- macOS DMG (x64 + arm64)
- `directories.output: build`
- `files`: main.js, preload.js, renderer/**, src/**, package.json

## Phase 10 (AFIP) Dependency Gap

**emitFiscalReceipt 호출처가 없음.** Phase 10이 아직 실행되지 않아 `facturacion.service.ts`가 존재하지 않거나 미완성. 대응:

1. PrintService.emitFiscalReceipt 메서드는 완전 구현됨 (자체 동작 가능)
2. 코드 내 TODO 코멘트: "Phase 10: facturacion.service.ts emitirFactura() 성공 후 호출 wiring 필요"
3. Phase 10 실행 시 단순히 `printService.emitFiscalReceipt(branchId, { ...invoiceData, afip: { tipo, puntoVenta, numero, cae, vtoCae, qrUrl } })` 한 줄 추가만 필요

`deferred-items.md`에는 별도 기록하지 않음 — TODO 주석과 본 SUMMARY의 본 섹션이 추적 지점.

## Sales-side print_invoice — 기존 경로 유지

`sales-create.service.ts::sendToprinters()`가 이미 `branch.apiKey` (legacy 컬럼) + `WebsocketService.emitToApiKey()` 경로로 `print_invoice`를 emit 중. 이 경로가 동작 중이라 신규 PrintGateway 경로로 전환하지 않았음. 두 경로가 공존하며 점진 마이그레이션 가능:

- **레거시:** `branches.api_key` → 메인 WebSocket gateway → 기존 print-agent
- **신규:** `branch_printer_configs.api_key` → `/print-agent` namespace → 신규 PrintGateway

신규 print-agent가 `/print-agent` 네임스페이스로 연결할 때만 신규 경로 사용. Wave 3 print-agent main.js는 `/realtime` 네임스페이스를 사용 중이므로 운영 진입 전 `/print-agent`로 전환하거나 게이트웨이 별칭이 필요할 수 있음 (다음 패치 후보).

## Plan vs Implementation 차이점

1. **마이그레이션 파일 미작성** — 프로젝트가 `sync({alter:false})` 자동 동기화 패턴 사용. 별도 migrations 디렉토리 없음. 모델만 추가하면 onModuleInit에서 자동 생성. (Rule 3 — 환경 적합성)
2. **JSONB unique 제약 raw SQL 미실행** — sequelize-typescript의 `unique:true` 데코레이터로 처리.
3. **`gen_random_uuid()` PG 함수 대신 Node `crypto.randomUUID()`** — 모델 defaultValue 함수 사용. pgcrypto extension 의존성 회피.
4. **지점 상세 페이지 탭 대신 별도 라우트** — 기존 `sucursales/index.tsx`가 BranchList만 렌더링 (동적 ID 페이지 부재). 탭 통합 대신 `[id]/impresora.tsx` 페이지 신설.
5. **다운로드 버튼 disabled** — `.exe`/`.dmg` 빌드 산출물 호스팅 인프라가 없음. 빌드 후 정적 파일 서빙 결정 필요 (다음 작업).

## Deviations from Plan

**[Rule 3 — Environment fit]** Sequelize 마이그레이션 파일 작성 대신 모델만 추가. 프로젝트 표준 패턴(sync 자동 동기화)을 따름.

**[Rule 2 — Critical]** `print.module.ts`를 `app.module.ts`에 등록 (플랜에 명시 없으나 NestJS 모듈 활성화에 필수).

**[Phase Dependency]** emitFiscalReceipt 호출처는 Phase 10 미실행으로 SKIP. 메서드는 완전 구현. SUMMARY에 의존 갭 명시.

## Known Stubs

- **PrinterConfigTab의 다운로드 버튼** — `disabled` 상태. `.exe`/`.dmg` 빌드 후 호스팅 URL 설정 필요. UI는 디자인대로 표시되며, 사용자는 다음 단계 (실 배포)에서 URL이 wiring될 것임을 시각적으로 인지함.
- **emitFiscalReceipt 호출처** — Phase 10 실행 시 `facturacion.service.ts`에서 한 줄 추가로 해소.
- **`/print-agent` vs `/realtime` 네임스페이스** — Wave 3 print-agent는 `/realtime`을 사용. 운영 전환 시 namespace 일치 필요.

## 완료 기준 검증

- [x] `branch_printer_configs` 모델/테이블 정의 (snake_case)
- [x] PrintGateway `/print-agent` namespace + handshake API Key 인증
- [x] `agent_online` → setOnline + room 등록
- [x] PrintService.emitPrintInvoice fire-and-forget 메서드
- [x] PrintService.emitFiscalReceipt 완전 구현 (호출처는 Phase 10 의존)
- [x] 프론트 PrinterConfigTab API Key 표시 + 복사 + 재발급
- [x] 30초 폴링 온라인 상태 표시
- [x] 설치 가이드 (서버 URL + API Key 자동 채워진 코드블록)
- [x] electron-builder package.json win/mac 설정 완성
- [ ] 실제 `.exe` / `.dmg` 빌드 실행 — 빌드 환경(Windows/macOS) 필요, 본 plan 범위 외
- [ ] E2E: 판매 → 출력 — 운영 전환(`/print-agent` namespace) 후 검증

## Commits

| Repo         | Hash    | Message |
|--------------|---------|---------|
| api-ventago  | 6f1df4a | feat(11-04): add PrintModule with BranchPrinterConfig + WebSocket gateway |
| ventago-app  | 0d85a1f | feat(11-04): add PrinterConfigTab UI with API Key + status polling |
| print-agent  | 1329d5f | chore(11-04): finalize electron-builder config for win/mac packaging |

## Self-Check: PASSED

- api-ventago/src/app/print/branch-printer-config.model.ts — FOUND
- api-ventago/src/app/print/print.service.ts — FOUND
- api-ventago/src/app/print/print.gateway.ts — FOUND
- api-ventago/src/app/print/print.controller.ts — FOUND
- api-ventago/src/app/print/print.module.ts — FOUND
- api-ventago/src/app.module.ts (PrintModule registered) — FOUND
- ventago-app/src/views/branches/components/printer/PrinterConfigTab.tsx — FOUND
- ventago-app/src/pages/sucursales/[id]/impresora.tsx — FOUND
- print-agent/package.json (electron-builder config) — FOUND
- commit 6f1df4a (api-ventago) — FOUND
- commit 0d85a1f (ventago-app) — FOUND
- commit 1329d5f (print-agent) — FOUND
