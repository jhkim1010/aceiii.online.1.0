# SPEC: vendedor 앱 인증 전환 (기기 key + Seller-operario PIN)
생성일: 2026-07-09

## 목표
mobile-sales-app 로그인을 despacho 모델(기기 apiKey + operario PIN)로 교체한다. operario 는 기존 Sellers 를 재사용하고(PIN 추가), Ventas 설정에서 지점 바인딩 기기(dispositivos)와 키를 발급/관리한다. Phase 37 "Usuario+PIN"(users.mobile_pin + mobile_sessions + fingerprint) 로그인 경로는 은퇴시킨다.

## 배경 및 컨텍스트
- **현재 앱 인증(교체 대상)**: `users.mobile_pin` + `mobile_sessions` + device fingerprint. 엔드포인트 `POST /mobile/auth/login`(Usuario+PIN), `GET /mobile/me`, `POST /mobile/auth/set-pin`. 앱: `mobile-sales-app/lib/features/auth/*`, `core/network/dio_client.dart`(Authorization + x-mobile-session-token).
- **재활용 템플릿(despacho)**:
  - 백엔드: `api-ventago/src/app/despacho/` — `despacho-device.model.ts`(store 바인딩, apiKey UNIQUE, underscored), `despacho-device.guard.ts`(x-device-key → req.despachoDevice, lastSeenAt fire-and-forget, 단일 indexed read), `despacho.service.ts`(createDevice/listDevices/setActive, createOperario/listOperarios/verifyOperario, `generateApiKey()=dsp_+randomBytes(24).hex`, PIN 4~6자리 bcrypt(10)), `despacho.controller.ts`(admin JWT 기기관리 + DeviceGuard 앱 엔드포인트).
  - 마이그레이션: `despacho-devices.sql`, `despacho-operarios.sql` — SERIAL, UNIQUE index, `DO $$ ... ALTER TABLE ... OWNER TO coolsistema` (role 존재 시).
  - 프론트: `ventago-app/src/views/ventas-online/components/DispositivosModal.tsx`(생성/복사/토글 UI, `/despacho/devices`).
  - 모바일: `despacho-app/lib/` — `config.dart`(release=prod URL, debug=10.0.2.2/localhost), `services/api_service.dart`(x-device-key + x-operario 헤더), `screens/login_screen.dart`(기기 토큰 입력), `screens/operario_login_screen.dart`(이름 그리드 → PIN 검증).
- **Sellers(operario 로 재사용)**: `api-ventago/src/app/sellers/` — 모델 `Sellers`(name,lastName,document,phone,isActive,storeId,branchId,linkedUserId; "로그인 불가, 판매 태그용"). 서비스 `findAllByStore(storeId,branchId,excludeAdmins)` 지점 필터 지원. 컨트롤러 `/sellers` CRUD(@Auth). 프론트 등록폼 `views/config/ventas/sellers/list/components/ModalSeller.tsx`(Nombre/Apellido/Sucursal/**Documento**/**Teléfono**), 목록 `SellersList.tsx`, config 탭 `ConfigurationSalesView.tsx`, 페이지 `pages/configuracion/ventas/index.tsx`.
- **판매 흐름(중요)**: `POST /mobile/sales` 는 **보류(comanda) 생성만**(D-13, Caja/매상 무영향) → box/terminal 불필요. `MobileCreateSaleDto` 이미 `sellerId` 보유. 서버가 scope(storeId+branchId)+sellerId 로 보류 생성. 즉 **지점 바인딩 + operario(seller)Id 만으로 충분**.
- **DB 네이밍**: sequelize `underscored: true` 전역 → 모델 camelCase = DB snake_case. `Sellers` 테이블명은 PascalCase 이므로 SQL 에서 **큰따옴표 필수**(`"Sellers"`). 신규 테이블은 despacho 처럼 snake_case + underscored 모델.

## 기술 스택
- 백엔드: NestJS 11 + Sequelize(sequelize-typescript), PostgreSQL(로컬 PG15 Docker `dbpostgres` / 운영 PG10 host, role `coolsistema`). bcrypt.
- 프론트: Next.js 13 pages router + MUI 5 + apiConnector(SWR/axios).
- 모바일: Flutter(Riverpod, go_router, dio, flutter_secure_storage). `mobile-sales-app`.
- DB pool: Sequelize 풀 min=10/max=80 (database.module.ts) — 신규 커넥션 남용 금지, 가드는 단일 indexed read.
- ESLint: newline-before-return, lines-around-comment, no-unused-vars 엄격(warning=build fail).

## 설계 결정 (확정)
- D1. Phase 37 users.mobile_pin/mobile_sessions 로그인 **교체**(은퇴). 테이블/컬럼은 즉시 DROP 하지 않고 코드 경로만 은퇴(롤백 여지).
- D2. 기기 = **지점(branch) 바인딩**. `vendedor_devices.branch_id`(+ store_id 캐시).
- D3. operario = 기존 **Sellers 재사용** + `pin_hash`,`pin_updated_at`. ModalSeller 에서 Documento/Teléfono 제거(컬럼 보존), PIN 추가.
- D4. operario 식별은 despacho 처럼 헤더 방식: 요청에 `x-device-key`(기기) + `x-seller-id`(operario). 무거운 mobile_sessions 세션테이블 대신 경량. (선택) verify 응답에 단기 서명 토큰 추가는 후속.

## 태스크 목록

### A. DB 마이그레이션 (api-ventago/migrations/)
- [ ] TASK-A1: `sellers-add-pin.sql` — `ALTER TABLE "Sellers" ADD COLUMN IF NOT EXISTS pin_hash VARCHAR(100) NULL, ADD COLUMN IF NOT EXISTS pin_updated_at TIMESTAMPTZ NULL;` (PG10/PG15 호환, idempotent)
- [ ] TASK-A2: `vendedor-devices.sql` — despacho-devices.sql 미러. `vendedor_devices`(id SERIAL PK, store_id FK stores, branch_id FK 지점 테이블, label VARCHAR(120) NOT NULL, api_key VARCHAR(80) NOT NULL, is_active BOOLEAN DEFAULT TRUE, last_seen_at, created_at, updated_at). UNIQUE index api_key, index (branch_id). 끝에 `DO $$ ... ALTER TABLE vendedor_devices OWNER TO coolsistema` (role 존재 시). ※지점 테이블 실제 이름/PK 확인(branch.model.ts, db-schema-tables.md).

### B. 백엔드 (api-ventago/src/app/)
- [ ] TASK-B1: `sellers/vendedor-device.model.ts` — DespachoDevice 미러 + branchId 컬럼.
- [ ] TASK-B2: `sellers/vendedor-device.guard.ts` — DespachoDeviceGuard 미러. x-device-key → req.vendedorDevice={id,storeId,branchId,label}. lastSeenAt fire-and-forget.
- [ ] TASK-B3: `sellers.service.ts` 확장 — createDevice(storeId,branchId,label)/listDevices(storeId,branchId?)/setDeviceActive; `generateApiKey()=vnd_+randomBytes(24).hex`; setPin(sellerId,pin) bcrypt(10) + pin 4~6 digit 검증; listOperarios(branchId)(pin 제외); verifyOperario(branchId,sellerId,pin). create/update 에 pin 처리(선택). InjectModel(VendedorDevice) 추가.
- [ ] TASK-B4: `sellers.controller.ts` 확장 — admin(@Auth) 기기관리 `POST/GET/PUT /sellers/devices`; DeviceGuard `GET /sellers/operarios`, `POST /sellers/operarios/verify`. create/update DTO 에 optional pin.
- [ ] TASK-B5: `sellers.module.ts` — SequelizeModule.forFeature([Seller, VendedorDevice]) + guard provider + bcrypt.
- [ ] TASK-B6: `create-seller.dto.ts`/`update-seller.dto.ts` — pin?(4~6 digit) 추가, document/phone optional 유지.
- [ ] TASK-B7: 앱 데이터 엔드포인트 device-key 전환 — catalog/stock/sales 를 VendedorDeviceGuard + x-seller-id 로 인증하도록 배선. 방식: MobileCatalog/Stock/Sales **서비스는 재사용**하고 scope 를 device(storeId+branchId)+sellerId 로 build 하는 얇은 컨트롤러(신규 `/vendedor/*` 또는 기존 mobile 컨트롤러 가드 스왑). MobileScopeGuard/JWT 경로 은퇴. (실행 시 최소 침습안 선택 — 신규 vendedor 컨트롤러 권장)
- [ ] TASK-B8: mobile 모듈 auth 은퇴 정리 — `/mobile/auth/*` 라우팅 비활성/제거 여부 결정(참조 남기고 주석 은퇴). set-pin 은 Sellers PIN 으로 대체됨.

### C. 프론트엔드 (ventago-app/src/)
- [ ] TASK-C1: `views/config/ventas/sellers/list/components/ModalSeller.tsx` — Documento/Teléfono 필드 제거, **PIN**(4~6 digit, 숫자, 편집 시 빈값이면 유지) 필드 추가. SellerForm 타입/DataConfig defaults/onSubmit payload 수정.
- [ ] TASK-C2: `views/config/ventas/sellers/.../VendedorDispositivosModal.tsx` — DispositivosModal.tsx 클론, `/sellers/devices` 사용 + 지점 선택(branchId) 추가. SellersList/ConfigurationSalesView 에 "Dispositivos" 버튼으로 오픈.
- [ ] TASK-C3: SellersList 목록에서 PIN 설정 상태 표시(선택) + 라우팅/메뉴는 기존 config/ventas 그대로(신규 페이지 불필요, 모달 방식).

### D. 모바일 앱 (mobile-sales-app/lib/)
- [ ] TASK-D1: `core/config/api_config.dart` — despacho-app config.dart 처럼 debug=10.0.2.2/localhost, release=prod. 기기키/operario secure storage 키 추가.
- [ ] TASK-D2: `core/network/dio_client.dart` — Authorization/x-mobile-session-token 대신 x-device-key + x-seller-id 헤더 주입.
- [ ] TASK-D3: 로그인 재구성 — 기기키 입력/저장 화면 + operario(seller) 이름 그리드 → PIN 검증(`/sellers/operarios`, `/sellers/operarios/verify`). 기존 `features/auth/*`(auth_repository, scope_provider, login_screen) 교체. go_router redirect: 기기키 없음→기기등록, operario 없음→operario 로그인, 둘 다→home.
- [ ] TASK-D4: catalog/cart/product/stock repository 의 엔드포인트/스코프를 device 기반으로 갱신(판매 생성 시 sellerId=선택 operario). Usuario+PIN 관련 DTO/화면 제거.

### E. 검증
- [ ] TASK-E1: 백엔드 ESLint `npx eslint <변경파일> --fix` (0 오류)
- [ ] TASK-E2: 프론트 ESLint `npx eslint <변경파일> --fix` (0 오류, newline-before-return/lines-around-comment)
- [ ] TASK-E3: 모바일 `flutter analyze` (0 이슈), `dart format .`
- [ ] TASK-E4: PostgreSQL pool 점검 — 가드 단일 indexed read, 신규 커넥션 없음, 서비스는 sequelize model 사용(pool 자동)
- [ ] TASK-E5: 로컬 마이그레이션 적용(Docker `dbpostgres`) + 스키마 재생성 스크립트 갱신. 운영 적용은 **별도 SSH 수동단계**(ALTER OWNER 포함) — 승인 게이트.

## 완료 기준
- ESLint 오류 0(백/프론트), flutter analyze 0.
- 기기키 발급 → 앱 기기 로그인 → operario 이름+PIN → 카탈로그/재고/보류판매 생성까지 device-key 경로로 동작.
- 보류 판매에 sellerId(=operario) 귀속.
- Sellers 등록폼에 doc/tel 없음, PIN 있음.
- 신규 테이블 owner=coolsistema (운영 500 방지).
- Phase 37 Usuario+PIN 경로 은퇴(코드 경로 비활성), 테이블/컬럼 미삭제.

## 금지사항 / 주의사항
- `"Sellers"` 테이블은 큰따옴표(케이스 민감). document/phone 컬럼 DROP 금지(보존).
- users.mobile_pin/mobile_sessions 테이블 즉시 DROP 금지(롤백 여지, 후속 정리).
- 신규 테이블 `ALTER OWNER TO coolsistema` 누락 금지(운영 permission denied 500).
- 운영 PG10 문법(GENERATED AS IDENTITY 금지, SERIAL). pgcrypto 의존 금지.
- 운영 DB DDL/DML 은 사용자 확인 게이트(CLAUDE.md 규칙). 로컬 먼저.
- pool 낭비 금지: 가드는 단일 read, 요청마다 새 연결/새 Pool 금지.
- ESLint: return 위 빈 줄, 주석 위 빈 줄, 미사용 import 금지.
- 주석 한국어 / 함수·변수명 영어, 모든 async try/catch.
