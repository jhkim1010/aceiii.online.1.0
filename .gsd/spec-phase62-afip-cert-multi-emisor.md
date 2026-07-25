# SPEC: Phase 62 — AFIP Certificado 관리 (superadmin) + Multi-Emisor (1지점 2 CUIT)
생성일: 2026-07-24
상태: PLAN (사용자 승인 대기)
Mockup: `mockups/afip-certificados-superadmin-mockup.html` (4탭 — 승인된 디자인 기준)

## 목표
Phase 59 SOAP 직접 발행을 전 매장으로 확산하기 위해 ① superadmin에서 매장별
certificado digital 수명주기(CSR 생성→업로드→검증→테스트→활성화→만료알림)를 관리하고,
② 1개 지점에서 2개 이상 CUIT(emisor)를 교대 사용하는 매장을 지원한다.

## 배경 및 컨텍스트
- 인증서 진실 = 디스크: `AFIP_CERTS_DIR/<slug>/{cert,key,.lastTokens}` (slug = coolUser || cuit).
  `.lastTokens`는 cool-invoice 게이트웨이와 공유 — **레이아웃 변경 금지** (alreadyAuthenticated 상호조정).
- provider 선택: `store_configs.afip_provider`('soap'만 직접) + `afip_production` 토글. store 6 라이브.
- `afip_issuers`: storeId/branchId(non-unique — 이미 지점당 N행 가능)/puntoVenta/cuit/coolUser/
  invoiceType/ivaCondition/razonSocial…. 단 `loadIssuerByBranch()`가 `findOne` — 다중 행 시 임의 1행 반환(버그 요인).
- NC/ND: `afip_vouchers`에 원본 발행 정보 저장됨 → NC는 원본 emisor 상속 (Phase 59 확정 설계).
- superadmin 웹 = ventago-app `/admin` + api `admin-console` 모듈 (modFacturaElectronica 노출 중).
- 로그(2026-07-24): error 0건, pool size=2 waiting=0 — 깨끗한 기반.

## 기술 스택
- 백엔드: NestJS 11 + Sequelize (underscored) / node-forge(이미 WSAA 서명에 사용) / MinIO 미사용(인증서는 디스크)
- DB: PostgreSQL 18 (로컬 5432 / 운영 5434, pgbouncer 경유). pool min=10 max=80 — 변경 없음
- 프론트: Next.js 13 + MUI 5, `apiConnector`, SWR
- ESLint: 루트 설정, Warning=빌드 실패 (newline-before-return / lines-around-comment / no-unused-vars)

## 확정 설계 결정 (D)
- **D-62-1 인증서 저장**: 파일=디스크 유지(게이트웨이 호환), DB엔 메타만 —
  신규 `afip_certificates`(issuer_id FK, cert_cn, cert_serial, not_before, not_after,
  key_fingerprint, is_active, uploaded_by, created_at). 갱신 시 새 행 + 구행 is_active=false (이력 보존).
- **D-62-2 CSR 서버 생성**: private key는 서버에서 생성·보관, 절대 반출 금지.
  고객은 CSR만 다운로드 → ARCA WSASS 업로드 → .crt 회수 업로드. 업로드 시 key↔cert 매칭 검증.
- **D-62-3 만료 알림**: 일일 cron(@nestjs/schedule)이 `afip_certificates` 메타만 조회(ARCA 호출 X)
  → 30/15/7일 전 Telegram(`store.telegramChatId` 재사용). 단일 쿼리, pool 무부담.
- **D-62-4 선택 모드**: 지점별 `afip_issuer_mode` = 'manual'(기본·권장) | 'terminal' | 'alternate' | 'ratio'.
  ratio는 `afip_issuer_ratio`(JSONB, {issuerId: pct}). terminal 모드는 `terminals.afip_issuer_id` FK.
- **D-62-5 하드룰 (모드 무관)**:
  ① Factura A 요청 시 RI emisor만 허용 — Monotributo emisor 자동 배제 + 프론트 칩 disable
  ② NC/ND는 원본 voucher의 emisor 상속 고정 — 선택 UI 없음
  ③ emisor별 PV 독립 채번 — 혼합 금지 (기존 (cuit,pv,tipo) 뮤텍스 그대로 유효)
- **D-62-6 발급 API**: issue DTO에 `issuerId?` 추가(옵션). 미지정 시 모드별 해석.
  백엔드는 issuerId가 해당 판매의 store/branch 소속인지 반드시 검증 (타 매장 emisor 발급 차단).

## 태스크 목록

### Wave A — DB 마이그레이션 (1파일)
- [ ] TASK-A1: `api-ventago/migrations/2026-07-24-afip-cert-multi-emisor.sql` 작성 —
      ① `afip_certificates` 신규 ② `afip_issuers.is_default BOOLEAN NOT NULL DEFAULT false`
      ③ `branches.afip_issuer_mode VARCHAR(10) NOT NULL DEFAULT 'manual'` + `afip_issuer_ratio JSONB`
      ④ `terminals.afip_issuer_id INT NULL REFERENCES afip_issuers(id)`
      ⑤ 말미 owner DO 블록: 신규 테이블+시퀀스 `OWNER TO coolsistema` (role 존재체크)
- [ ] TASK-A2: 운영(5434) 적용 — SQL+영향 보여주고 **사용자 동의 후** `--single-transaction` 실행.
      로컬(5432)은 사용자 Mac psql 명령 전달. 양쪽 스키마 대조 + `db-schema.regen.sh`

### Wave B — 백엔드: 인증서 수명주기 (admin-console 확장)
- [ ] TASK-B1: `AfipCertificate` 모델 + afip.module 등록 — 파일: `afip/models/afip-certificate.model.ts`
- [ ] TASK-B2: `AfipCertService` — CSR 생성(node-forge, key는 `AFIP_CERTS_DIR/<slug>/key`에 0600 저장),
      cert 업로드 파싱(X.509 CN/serial/유효기간)+key fingerprint 매칭 검증+디스크 저장+메타 upsert.
      파일 I/O 중 DB 커넥션 미점유 (파싱 후 단발 쿼리) — 파일: `afip/afip-cert.service.ts`
- [ ] TASK-B3: superadmin 엔드포인트 (admin-console guard) —
      GET 목록(issuer+cert 메타 join, 단일 쿼리) / POST `:issuerId/csr` / POST `:issuerId/certificate`(multipart) /
      POST `:issuerId/test`(WSAA login→FEDummy→FEParamGetPtosVenta→FECompUltimoAutorizado, homo/prod 파라미터,
      외부 SOAP 호출 동안 pool 미점유) / PUT provider·production 토글 — 파일: `admin-console` controller/service
- [ ] TASK-B4: 만료 cron + Telegram 알림 (D-62-3) — 파일: `afip/afip-cert-expiry.cron.ts`

### Wave C — 백엔드: multi-emisor 해석
- [ ] TASK-C1: `AfipIssuerService.loadIssuerByBranch` → `listIssuersByBranch`(findAll) +
      `resolveIssuerForSale(storeId, branchId, terminalId, {issuerId?, needsFacturaA?})` —
      모드별 해석(manual: issuerId 필수/기본값, terminal: FK, alternate: 마지막 발급 반대,
      ratio: 월누계 비교 1쿼리) + D-62-5① RI 필터 + D-62-6 소속 검증. 기존 단일 emisor 매장은
      행 1개 → 무조건 그 행 (동작 불변 보장)
- [ ] TASK-C2: issue DTO/controller/sales-create 경로에 `issuerId` 전파. NC/ND 서비스는
      원본 voucher emisor 상속 확인(변경 없으면 no-op 검증만) — 파일: afip.controller, dto, sales-create.service
- [ ] TASK-C3: 판매/Libro IVA 보고서에 emisor(cuit) 필터 파라미터 추가 (기존 쿼리 WHERE 확장, 신규 쿼리 금지)

### Wave D — 프론트: superadmin Certificados 페이지
- [ ] TASK-D1: `/admin/facturacion` 페이지 (dynamic import, ssr:false) — 목록 탭: KPI 4개 +
      emisor 테이블(상태 배지 Vigente/Por vencer/Vencido/Sin cert/Gateway) — mockup 탭① 기준
- [ ] TASK-D2: 5단계 wizard 다이얼로그 (datos→CSR 다운로드→cert 드래그업로드→test 콘솔→활성화) — mockup 탭②
- [ ] TASK-D3: 지점 multi-emisor 설정 UI (emisor 카드 + 모드 라디오 4종 + ratio 슬라이더) — mockup 탭③

### Wave E — 프론트: POS F10 emisor 선택
- [ ] TASK-E1: F10 모달 상단 emisor 칩 (지점 emisor 2개 이상일 때만 렌더 — 기존 매장 UI 불변).
      터미널별 마지막 선택 localStorage 기억, Monotributo 선택 시 Fac C 자동 전환,
      Factura A 시 비-RI 칩 disable — mockup 탭④ 기준. 파일: PartialInvoiceModal 계열
- [ ] TASK-E2: 오프라인 가드(useOfflineStatus)와 공존 확인 — F10 차단 로직 무변경

### Wave F — 검증
- [ ] TASK-F1: ESLint 실행 (api + app, 수정 파일 전체) — 오류 0개
- [ ] TASK-F2: jest — **러너 잡으로 실행** (device VM 금지/OOM): issuer 해석 모드 4종 + RI 필터 +
      소속 검증 + cert 파싱/매칭 단위테스트
- [ ] TASK-F3: homo 스모크 — 신규 wizard로 테스트 인증서 1건 등록→test 4단계 통과 확인
- [ ] TASK-F4: 로그 재확인 (error-*.log 신규 에러 0건, pool waiting=0 유지)

## 완료 기준
- ESLint 오류 0개, jest(러너) green
- 마이그레이션 로컬 5432 + 운영 5434 양쪽 적용·스키마 대조 일치, 신규 테이블 owner=coolsistema
- 단일 emisor 기존 매장(3·6·8·9): 동작·API 응답 완전 불변 (회귀 0)
- 2 emisor 지점: F10 칩 선택 → 각 CUIT의 PV로 독립 채번 발급 (homo 검증)
- 만료 30일 미만 인증서 존재 시 Telegram 알림 발송 확인

## 금지사항 / 주의사항
- ★ 인증서 폴더 레이아웃/`.lastTokens` 스키마 변경 금지 — 게이트웨이 상호조정 파괴됨
- ★ 이중발급 가드(뮤텍스+ambiguous 회복) 로직 수정 금지 — 경로만 추가
- private key를 API 응답/로그에 절대 노출 금지. CSR 다운로드만 허용
- NC/ND emisor 선택 UI 만들지 말 것 (D-62-5②)
- 운영 DDL·서비스 재시작은 사용자 확인 후. 운영 DB 쓰기는 classifier 하드블록 → ssh 원라이너 전달
- pool 설정(min10/max80) 변경 금지. 신규 쿼리는 전부 단발성(트랜잭션 장기 점유 금지)
- device VM에서 jest 금지 (OOM) — agent-runner 잡 사용
- 개발은 로컬 Mac에서 진행 + push (2026-07-23 워크플로우 규칙)
