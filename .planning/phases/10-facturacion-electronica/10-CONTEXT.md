# Phase 10: Facturación Electrónica (AFIP) - Context

**Gathered:** 2026-04-06
**Status:** Ready for planning
**Source:** Conversation-derived + analysis of `/Users/marcoskim/Dropbox/cpp/afip-connector`

<domain>
## Phase Boundary

Argentina AFIP 전자세금계산서(factura electrónica) 발행 기능을 Ventago에 통합.
사용자는 POS에서 판매 완료 후 즉시 CAE 부여 세금계산서를 발행하고, PDF+QR을 인쇄/이메일/보관할 수 있어야 한다.

**핵심 발견: 기존 프로젝트 분석**
`Dropbox/cpp/afip-connector` 는 이름이 cpp 폴더에 있을 뿐 실제로는 **Java Spring Boot 1.5 프로젝트**.

구조 요약:
- `com.coolsistema.facture` (Spring Boot + JPA + Freemarker + PostgreSQL 직접 연결)
- **AFIP WS 직접 호출 안 함** — `https://invoice.coolsistema.com/api` (manager.coolsistema.com) 를 호출하는 얇은 REST 클라이언트
- 즉 WSAA/WSFE의 무거운 부분(.p12 서명, TA 캐시, WSDL, CAE SOAP)은 **이미 별도 서비스에 운영 중**
- 이 Java 앱은 레거시 POS의 `fistmpcab/fistmp` 테이블을 JPA로 읽어 → `AfipVoucherRequest` DTO로 변환 → 중간 릴레이에 POST → CAE 수신 → Freemarker로 PDF 템플릿 렌더링

**핵심 컴포넌트 매핑 (Java → Ventago 이식):**

| Java 프로젝트 (afip-connector) | Ventago 이식 위치 | 비고 |
|-------------------------------|-------------------|------|
| `CoolsistemaConnector` (REST 클라이언트) | `api-ventago/src/app/facturacion/afip-relay.service.ts` | **재사용 핵심** — URL/payload 동일 |
| `AfipService.processInvoice` | `facturacion.service.ts` `emitInvoice()` | 비즈니스 로직 포팅 |
| `AfipVoucherRequest` DTO | `dto/afip-voucher-request.dto.ts` | 필드 그대로 복사 |
| `InvoiceType/IVA/DocumentType/ProductType` enums | `common/afip.constants.ts` | 상수 그대로 |
| `DataQRCodeTransformer` (AFIP QR v1) | `services/afip-qr.service.ts` | JSON→base64url→URL |
| Freemarker `.ftl` 템플릿 | HBS 또는 Puppeteer HTML | PDF 생성 엔진 교체 |
| `fistmpcab` JPA 엔티티 | **불필요** — Ventago는 자체 `sales/sale_items` 사용 | Sale → Invoice 매핑만 필요 |
| `ParametersRepository` (cuit, sucursal 등) | Store/Branch 테이블 + store_fiscal_config | 이미 대부분 존재 |
| `@Scheduled` (cron 껍데기만) | 사용 안 함 | 이벤트 드리븐 |

**중간 릴레이(`invoice.coolsistema.com`) 전략:**
- **결정 필요**: ⓐ 기존 릴레이 서비스를 계속 사용 vs ⓑ Node.js에서 AFIP WSAA/WSFE 직접 호출
- **추천: ⓐ 기존 릴레이 재사용** — 증명된 프로덕션 서비스, 인증서 관리 이미 됨, pool 절약, 개발 속도 최우선
- ⓑ 는 장기적으로 고려 (Phase 11 등)

</domain>

<decisions>
## Initial Decisions (TBD — 사용자 확인 필요)

### 전략 결정 (proposal, 승인 대기)
- **D1**: 릴레이 재사용 — 기존 `manager.coolsistema.com/api` 그대로 호출 (Axios)
- **D2**: 인증서/TA 관리는 릴레이에 위임 (Ventago는 storeId + cuit + sucursal만 전달)
- **D3**: Store에 `fiscal_config` 1:1 관계 추가 — cuit, puntoVenta, condIva, invoiceTypeDefault, relayClientId
- **D4**: Sale → Invoice 변환은 **동기 호출** (POS에서 "Facturar" 버튼 누르면 바로 CAE 요청, 평균 2-4초 대기)
- **D5**: 실패 시 자동 재시도 3회 + 실패 상태 `ERROR_AFIP` 로 Sale 마킹, superadmin 알림
- **D6**: PDF 생성은 **Puppeteer + HTML 템플릿** (Freemarker 대체)
- **D7**: QR 코드는 AFIP 사양 v1 JSON → base64url → `https://www.afip.gob.ar/fe/qr/?p=...` URL
- **D8**: Contingencia 모드 — 릴레이 응답 없으면 Sale을 `PENDIENTE_AFIP` 로 마킹 → cron이 5분마다 재처리

### Invoice Types (Locked by AFIP)
- **INVOICE_A** — 상대가 IVA Responsable Inscripto
- **INVOICE_B** — 상대가 Consumidor Final / Monotributo
- **INVOICE_C** — Monotributo/Exento 발행자
- **INVOICE_E** — 수출용 (cliente exterior)
- **INVOICE_M** — 관찰된 A (limit 초과)
- Credit Note: type + 3 (예: NC-B = type 8)

### Phase Boundary
- **포함**: Factura 발행 + CAE 수신 + QR/PDF 생성 + 보고서 연동 + 저장
- **제외** (향후 phase):
  - AFIP WS 직접 호출 (릴레이 의존 유지)
  - Libro IVA 생성 (Phase 12?)
  - ARCA/ARBA 등 지방세
  - Retenciones/percepciones
  - Notas de débito
  - Comprobantes asociados UI (모델은 있음)

</decisions>

<data>
## Data Model (신규/변경)

### 신규 테이블

**`store_fiscal_configs`** (Store 1:1)
```sql
CREATE TABLE store_fiscal_configs (
  id SERIAL PRIMARY KEY,
  store_id INT NOT NULL UNIQUE REFERENCES stores(id),
  cuit BIGINT NOT NULL,                          -- 사업자번호
  razon_social VARCHAR(200) NOT NULL,
  cond_iva VARCHAR(20) NOT NULL,                 -- 'RI', 'MONOTRIBUTO', 'EXENTO'
  punto_venta INT NOT NULL,                      -- AFIP pto de venta (1~99999)
  invoice_type_default VARCHAR(1) NOT NULL,      -- 'A' | 'B' | 'C' | 'M' | 'E'
  relay_client_id VARCHAR(50),                   -- coolsistema relay client id
  relay_enabled BOOLEAN DEFAULT true,
  prod BOOLEAN DEFAULT false,                    -- homologación vs prod
  start_activities_date DATE,                    -- ingresos brutos
  ingresos_brutos VARCHAR(50),
  domicilio_comercial TEXT,
  logo_fiscal_url VARCHAR(200),
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);
```

**`invoices`** (발행된 comprobante 1건 = 1 row)
```sql
CREATE TABLE invoices (
  id SERIAL PRIMARY KEY,
  store_id INT NOT NULL REFERENCES stores(id),
  branch_id INT REFERENCES branches(id),
  sale_id INT REFERENCES sales(id),               -- 원 판매 (null 가능 = 수동 발행)
  invoice_type VARCHAR(2) NOT NULL,               -- 'A','B','C','M','E','NCA','NCB','NCC'
  punto_venta INT NOT NULL,
  numero BIGINT NOT NULL,                         -- AFIP이 할당한 번호
  fecha DATE NOT NULL,
  cuit_emisor BIGINT NOT NULL,
  doc_tipo INT NOT NULL,                          -- DocumentType
  doc_nro VARCHAR(20),
  cliente_nombre VARCHAR(200),
  cliente_domicilio VARCHAR(200),
  cond_iva_cliente VARCHAR(20),
  neto NUMERIC(14,2) NOT NULL,
  iva NUMERIC(14,2) NOT NULL,
  iva_porcentaje NUMERIC(5,2) NOT NULL,
  total NUMERIC(14,2) NOT NULL,
  moneda VARCHAR(3) DEFAULT 'PES',
  cotizacion NUMERIC(10,4) DEFAULT 1,
  cae VARCHAR(20),
  cae_vencimiento DATE,
  status VARCHAR(20) NOT NULL,                    -- 'PENDIENTE','OK','ERROR','CANCELADO'
  error_message TEXT,
  qr_data TEXT,                                   -- base64url JSON
  pdf_url VARCHAR(200),                           -- MinIO 저장 경로
  associated_voucher_id INT REFERENCES invoices(id), -- NC 용
  retries INT DEFAULT 0,
  relayed_at TIMESTAMP,                           -- 릴레이 POST 시각
  caed_at TIMESTAMP,                              -- CAE 수신 시각
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(store_id, punto_venta, invoice_type, numero)
);
CREATE INDEX idx_invoices_sale ON invoices(sale_id);
CREATE INDEX idx_invoices_status ON invoices(status) WHERE status IN ('PENDIENTE','ERROR');
CREATE INDEX idx_invoices_store_fecha ON invoices(store_id, fecha);
```

**`invoice_items`**
```sql
CREATE TABLE invoice_items (
  id SERIAL PRIMARY KEY,
  invoice_id INT NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
  sale_item_id INT REFERENCES sale_items(id),
  description VARCHAR(300) NOT NULL,
  quantity NUMERIC(12,3) NOT NULL,
  unit_price NUMERIC(14,4) NOT NULL,
  subtotal NUMERIC(14,2) NOT NULL,
  iva_porcentaje NUMERIC(5,2) NOT NULL,
  sort_order INT NOT NULL
);
```

### 변경 테이블
- `sales` 에 `invoice_id INT` 추가 (optional, 1:1)
- `sales.status` 에 `FACTURADO`, `PENDIENTE_AFIP`, `ERROR_AFIP` 값 허용

## 릴레이 프로토콜 (기존 afip-connector 에서 복사)

**Endpoint**: `POST https://invoice.coolsistema.com/api/invoice?prod=true&client={clientId}&cuit={cuit}`

**Request body** (`AfipVoucherRequest`):
```json
{
  "point": 3,
  "type": 6,           // InvoiceType 숫자
  "productType": 1,    // ProductType.PRODUCT/SERVICE/BOTH
  "documentType": 80,  // DocumentType.CUIT/DNI/CF 등
  "dni": "20312929695",
  "amount": 1210.00,   // total (iva 포함)
  "iva": 210.00,       // impuesto 금액
  "ivaType": 5,        // IVA.NATIONAL=21%, EXEMPT, CLIENT_EXTERIOR
  "creditNote": false,
  "asoc": null
}
```

**Response** (`AfipCaeResponse`):
```json
{
  "cae": "74012345678901",
  "caeVencimiento": "2026-04-16",
  "afipNumber": 1234,
  "error": null
}
```

## 기존 afip-connector 재사용 가치 평가

| 자산 | Ventago 이식 가치 | 방법 |
|------|-----------------|------|
| CoolsistemaConnector REST 호출 패턴 | ⭐⭐⭐⭐⭐ | Axios로 1:1 포팅 |
| AfipVoucherRequest/Response DTO | ⭐⭐⭐⭐⭐ | TypeScript interface로 복사 |
| InvoiceType/IVA/DocumentType enums | ⭐⭐⭐⭐⭐ | TS enum으로 복사 |
| AfipService.processInvoice 로직 (IVA 판별, NC 처리) | ⭐⭐⭐⭐ | 규칙 포팅 |
| DataQRCodeTransformer | ⭐⭐⭐⭐ | Node.js로 포팅 |
| Freemarker 템플릿 | ⭐⭐⭐ | HBS/HTML로 재작성 |
| JPA 엔티티 (fistmpcab 등) | ⭐ | 불필요 (스키마 다름) |
| `@Scheduled` 껍데기 | 0 | 주석처리된 상태 |
| Parameters 설정 저장 패턴 | ⭐⭐ | store_fiscal_configs로 재설계 |

</data>

<constraints>
## Constraints

- **릴레이 서비스 가용성**: `invoice.coolsistema.com` 의 uptime/성능에 의존. SLA 확인 필요
- **인증서 만료**: 릴레이 측 .p12 만료 주의 (연 1회 갱신, 알림 자동화 필요)
- **Homologación 환경**: dev에서는 `prod=false` 로 호출, 실 comprobante 발행 금지
- **Pool 절약**: Invoice 조회는 store_id + fecha 인덱스 활용, N+1 금지
- **원자성**: Sale → Invoice 생성은 단일 트랜잭션, CAE 실패 시 Invoice는 status=ERROR로 남기고 Sale은 PENDIENTE_AFIP
- **UI 블로킹 방지**: POS 화면에서 "Facturar" 클릭 시 로딩 오버레이 + 타임아웃 10초
- **동시성**: 같은 sale_id 에 대한 중복 발행 차단 (DB UNIQUE + 어드바이저리 락)
- **금액 정확도**: AFIP은 IVA 계산 오차 0.01 민감 — BigDecimal → decimal.js 또는 Prisma Decimal 사용
- **Timezone**: Store.timezone 기준으로 fecha 계산 (AR = America/Argentina/Buenos_Aires)
- **Multi-tenant**: 모든 쿼리 store_id 필수
- **Phase 6/8/9 와 경로 격리**: 신규 모듈 `api-ventago/src/app/facturacion/`, 신규 라우트 `pages/facturacion/`. 기존 `reports/facturacion/` 는 조회 전용이므로 읽기만 연동

</constraints>
