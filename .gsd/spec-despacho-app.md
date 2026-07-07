# SPEC: Despacho App — 창고 준비(picking) 모바일/데스크톱 앱

생성일: 2026-07-07

## 목표

venta online 주문이 **preparing** 상태로 넘어오면 창고 직원이 (1) 무엇을 어떻게 준비할지(picking list) 보고,
(2) 준비 후 **"Listo para despacho"** 로 쉽게 넘기는 소형 앱. Windows + Android 지원, Mac Android 에뮬레이터로 검증,
사이드바 Herramientas(Download) 페이지에서 설치본 배포.

## 확정된 결정 (사용자)

- **인증**: 창고 기기 전용 토큰 (BranchAgent 패턴 — 매장 바인딩 apiKey, 개인계정/세션충돌 없음)
- **기능(MVP)**: Picking 체크리스트 + "Listo" 버튼(필수) · 준비 사진 첨부(MinIO) · 새 주문 실시간 알림(Socket.io)  → 바코드 스캔은 제외
- **대상 주문**: 매장 전체 preparing
- **플랫폼**: Windows + Android (Flutter 단일 코드베이스; iOS 아님)
- **배포**: Herramientas > Download 페이지 카드 + GitHub Actions CI 빌드(zebra-agent 방식 계승)
- **검증**: Mac Android 에뮬레이터 (+ 개발 중 macOS 데스크톱 임시 실행 가능)

## 기술 스택

- **앱**: Flutter (stable) + Riverpod(상태) + dio(HTTP) + socket_io_client(실시간) + image_picker(사진) + flutter_secure_storage(토큰). null safety 준수, dart style.
- **백엔드**: NestJS + Sequelize (신규 despacho 기기 인증 + 기기 스코프 목록/사진 엔드포인트). PostgreSQL pool 재사용(신규 풀 X).
- **배포**: `warehouse-agent-*.yml` GitHub Actions (Android APK + Windows exe). Herramientas 페이지 다운로드 카드.

## 백엔드 현황 (재사용)

이미 존재하여 그대로 쓰는 것:
- 상태 흐름: `pending→confirmed→preparing→(mark-ready=Listo)→shipped→delivered`
- `PATCH /online-orders/:id/prepare` (→preparing), `PATCH /online-orders/:id/mark-ready` (preparedAt set = Listo) — **userId/userName optional** → 기기 신원 주입 가능
- `GET /online-orders/board` / `/board/:branchId` — 카드, `GET /online-orders/:id` — 항목 상세
- online_order_items: `productName / size / color / quantity` (picking 표시에 충분)
- Socket.io print 게이트웨이 패턴(BranchAgent isOnline/socketId) — despacho 네임스페이스에 재사용

## 태스크 (Phase 분리)

### Phase 1 — Flutter MVP 스캐폴드 (이번 턴)
- [ ] T1-1: `despacho-app/` Flutter 프로젝트(pubspec, main, config, secure storage)
- [ ] T1-2: 모델(OnlineOrder, OrderItem) + dio ApiService(baseUrl/token 주입, 에러 핸들링)
- [ ] T1-3: Riverpod providers(auth/orders)
- [ ] T1-4: 로그인 화면(초기: baseUrl + 토큰 수동 입력 → 조기 테스트 가능 / 이후 기기 apiKey)
- [ ] T1-5: preparing 목록 화면(당김 새로고침)
- [ ] T1-6: 상세 화면 — picking 체크리스트 + "Listo para despacho"(mark-ready 호출)

### Phase 2 — 백엔드 기기 인증 + 기기 스코프 API
- [ ] T2-1: `despacho_devices` 테이블(store_id, branch_id nullable, label, api_key UNIQUE, is_active, last_seen_at) + 마이그레이션(끝에 `ALTER OWNER TO coolsistema`)
- [ ] T2-2: `POST /despacho/auth` — apiKey 검증 → 스코프 JWT(role=despacho, storeId) 발급 (경량, pool 단일 read)
- [ ] T2-3: `GET /despacho/orders` — 매장 전체 preparing(항목 포함), 기기 JWT 가드
- [ ] T2-4: mark-ready/prepare 를 기기 JWT 로 호출 가능하게 가드/신원 매핑(userName=기기 label)

### Phase 3 — 사진 첨부 + 실시간
- [ ] T3-1: `POST /despacho/orders/:id/photo` — MinIO 업로드(MinioService 재사용) + 주문 metadata 링크
- [ ] T3-2: image_picker 로 촬영/선택 → 업로드 UI
- [ ] T3-3: Socket.io despacho 네임스페이스 — preparing 신규 진입 push → 목록 자동 갱신

### Phase 4 — 배포/설치
- [ ] T4-1: GitHub Actions `build-warehouse-agent.yml` (Android APK + Windows exe, 태그 자동 증가)
- [ ] T4-2: Herramientas Download 페이지에 카드 추가(기존 print/zebra 카드 패턴)
- [ ] T4-3: 앱 자동 업데이트(선택 — 기존 agent auto-update 방식 재사용)

### 검증
- [ ] V-1: Mac Android 에뮬레이터 `flutter run` — 로그인→목록→상세→Listo 왕복
- [ ] V-2: `flutter analyze` 0 이슈, dart format
- [ ] V-3: pool 안전(신규 백엔드 쿼리 단일 read, release 불필요 재확인)

## 완료 기준

- Android 에뮬레이터에서 preparing 목록 표시 → 항목 체크 → "Listo para despacho" → 보드에서 Listo 로 이동 확인
- Windows/Android 설치본이 Herramientas Download 에서 내려받아짐
- 기기 토큰만으로 로그인(개인 계정/웹 세션 무관), pool 낭비 없음

## 금지사항 / 주의

- 운영 세션 보안(active_sessions/terminal_devices/branch_ip_registries) 로직 건드리지 않음 — 기기 인증은 별도 경량 경로
- 신규 테이블 마이그레이션 끝에 `ALTER OWNER TO coolsistema` 필수(운영 권한 500 방지)
- markReady/prepare 는 기존 서비스 재사용(status 전이/mirror sale 로직 변경 금지)
- MinIO 는 MinioModule/MinioService 재사용(신규 클라이언트 X)
