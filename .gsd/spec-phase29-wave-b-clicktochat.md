# SPEC: Phase 29 — Wave B · WhatsApp Click-to-Chat
생성일: 2026-05-12
작성자: Claude (GSD 워크플로우)
대상 사용자: 마르코스 (Marcos.J.Kim)

---

## 목표

Ventago 의 ClienteVista 메뉴 안에서, 손님 한 명에 대한 [WhatsApp 보내기] 버튼 클릭 → **매장 대표자(admin) 의 WhatsApp 번호 신원**으로 표시되는 `wa.me` Click-to-Chat 링크가 새 탭으로 열리는 시스템을 구현한다. 외부 API 비용 0, Meta 차단 위험 0, 발송 로그를 DB 에 적재한다.

---

## 배경 및 컨텍스트

### 현재 시스템 상태 (2026-05-12 확인)

| 항목 | 상태 |
|---|---|
| `clients.phone` | ✅ 존재 (VARCHAR 255, 자유 형식) |
| `users.phone` 또는 `users.whatsapp_phone` | ❌ **존재하지 않음** (DTO 에만 phone 있음, 모델/DB 미존재) |
| `stores.representative_user_id` | ❌ 존재하지 않음 (`adminUser` HasOne 관계는 있으나 명시적 대표자 지정 불가) |
| `Store.adminUser` Sequelize 관계 | ✅ 존재 (`@HasOne(() => Users, { foreignKey: 'storeId', as: 'adminUser' })`) |
| WhatsApp 관련 라이브러리 | ❌ 미설치 (`twilio`, `whatsapp` 등 0건) |
| Winston 로그 | ✅ `logs/combined-YYYY-MM-DD.log` 일별 로테이션 |
| ESLint 규약 | ✅ Warning 도 빌드 에러 처리 — 빈 줄 / lines-around-comment / no-unused-vars 주의 |
| 모노레포 | ✅ npm workspaces — 패키지는 루트 `node_modules/` 호이스팅 |

### 운영 제약사항 (CLAUDE.md 발췌)

- **PostgreSQL pool max=50, 변경 금지** — 쿼리 효율로 해결
- **운영 PG10 호스트 설치** (Docker 아님) — 로컬 dev 는 PG15 Docker
- **마이그레이션 SQL** 은 `api-ventago/migrations/` 에 파일 커밋 + 운영 서버에서 직접 실행
- **운영 4매장**: CART(3), coolsistema(6), genius(8), ACE(9)
- **Sequelize underscored:true 전역** — 모델 camelCase ↔ DB snake_case
- **slow query 100ms+ 즉시 최적화**

### Wave B 범위 한정

이 SPEC 은 **Day 1 작업 + 후속 Day 2~3 작업까지 포함**한다.
다음 항목은 명시적으로 **이번 Wave 에서 제외**:
- Meta Cloud API 자동 발송 (Wave C 로 분리 — 별도 SPEC)
- 발송 후 ROI attribution 자동 계산 (Wave A 의 RFM 완성 후 별도 작업)
- 손님 응답 자동 수신 (Click-to-Chat 은 단방향 deep link 라 본질적으로 불가)
- Cliente 360 페이지 신설 (별도 SPEC: `spec-phase29-wave-a-cliente360.md`)

---

## 기술 스택

- **언어/프레임워크**: NestJS 11 + TypeScript (백엔드), Next.js 13 Pages Router + React 18 + MUI 5 (프론트)
- **DB**: PostgreSQL 15 (로컬 dev Docker `dbpostgres`) / PostgreSQL 10 (운영 호스트, pgbouncer 5432 프록시)
- **ORM**: Sequelize + sequelize-typescript (`underscored: true`)
- **HTTP 인증**: JWT + `x-session-token` 헤더 (SessionGuard)
- **신규 의존성**:
  - `libphonenumber-js@^1.10.0` — 전화번호 정규화 (E.164)
  - (백엔드 + 프론트엔드 양쪽 모두 사용 가능, 약 145KB)
- **ESLint 설정 파일**: `api-ventago/.eslintrc.js` (npm script `lint`)
- **로그 파일**: `api-ventago/logs/combined-2026-05-12.log` 확인 후 수정

---

## 데이터 모델 변경

### 마이그레이션 1: `users.whatsapp_phone` 컬럼 추가

```sql
-- api-ventago/migrations/2026-05-12-phase29b-users-whatsapp.sql
ALTER TABLE users
  ADD COLUMN whatsapp_phone VARCHAR(30);

COMMENT ON COLUMN users.whatsapp_phone IS
  'E.164 형식 (+5491145678901). Click-to-Chat 발송자 신원 표시용.
   매장 admin/gerente 만 채움. NULL 이면 해당 사용자는 대표자로 지정 불가.
   본인 동의 후에만 입력. 퇴직 시 NULL 처리.';
```

### 마이그레이션 2: `stores.representative_user_id` 컬럼 추가

```sql
-- api-ventago/migrations/2026-05-12-phase29b-stores-representative.sql
ALTER TABLE stores
  ADD COLUMN representative_user_id INTEGER;

ALTER TABLE stores
  ADD CONSTRAINT fk_stores_representative_user
  FOREIGN KEY (representative_user_id) REFERENCES users(id)
  ON DELETE SET NULL;

COMMENT ON COLUMN stores.representative_user_id IS
  '매장 WhatsApp 발송 대표자. NULL 이면 [WhatsApp 보내기] 버튼 비활성화.
   admin 역할 + whatsapp_phone NOT NULL 인 사용자만 지정 가능.';

CREATE INDEX idx_stores_representative_user ON stores(representative_user_id);
```

### 마이그레이션 3: `whatsapp_messages` 발송 로그 테이블 신설

```sql
-- api-ventago/migrations/2026-05-12-phase29b-whatsapp-messages.sql
CREATE TABLE whatsapp_messages (
  id                     SERIAL PRIMARY KEY,
  store_id               INTEGER NOT NULL,
  client_id              INTEGER,
  phone                  VARCHAR(30) NOT NULL,
  template_key           VARCHAR(60),
  body                   TEXT NOT NULL,
  provider               VARCHAR(20) NOT NULL DEFAULT 'click_to_chat',
  status                 VARCHAR(20) NOT NULL,
  sent_by_user_id        INTEGER,
  representative_user_id INTEGER,
  link_url               TEXT,
  error_message          TEXT,
  created_at             TIMESTAMP NOT NULL DEFAULT now(),
  updated_at             TIMESTAMP NOT NULL DEFAULT now(),

  CONSTRAINT fk_wa_msg_store         FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE,
  CONSTRAINT fk_wa_msg_client        FOREIGN KEY (client_id) REFERENCES clients(id) ON DELETE SET NULL,
  CONSTRAINT fk_wa_msg_sender        FOREIGN KEY (sent_by_user_id) REFERENCES users(id) ON DELETE SET NULL,
  CONSTRAINT fk_wa_msg_representative FOREIGN KEY (representative_user_id) REFERENCES users(id) ON DELETE SET NULL
);

CREATE INDEX idx_wa_msg_store_created    ON whatsapp_messages(store_id, created_at DESC);
CREATE INDEX idx_wa_msg_client_created   ON whatsapp_messages(client_id, created_at DESC);
CREATE INDEX idx_wa_msg_template_created ON whatsapp_messages(template_key, created_at DESC);

COMMENT ON TABLE  whatsapp_messages       IS 'Phase 29 Wave B — WhatsApp Click-to-Chat 발송 로그.';
COMMENT ON COLUMN whatsapp_messages.status IS
  'link_generated | dismissed | error. Click-to-Chat 은 발송 보장 없음(운영자가 wa.me 새 탭에서 [전송] 누르는지 시스템 확인 불가) — link_generated 가 최종 상태.';
COMMENT ON COLUMN whatsapp_messages.provider IS
  'click_to_chat (Wave B) | cloud_api (Wave C 예정).';
```

### Sequelize 모델 변경

1. `users.model.ts` — `whatsappPhone` 컬럼 추가 (DataType.STRING(30), allowNull: true)
2. `store.model.ts` — `representativeUserId` FK 컬럼 + `representative` BelongsTo 관계 추가
3. 신규 모델: `api-ventago/src/app/whatsapp/whatsapp-message.model.ts`

---

## 백엔드 모듈 구조

```
api-ventago/src/app/whatsapp/
├── whatsapp.module.ts
├── whatsapp.controller.ts
├── whatsapp-message.model.ts
├── services/
│   ├── click-to-chat.service.ts          # 핵심: 링크 생성 + 로그 적재
│   └── phone-normalizer.service.ts       # E.164 정규화 (libphonenumber-js)
├── templates/
│   └── template-registry.ts              # 5개 템플릿 정의 + 변수 치환
└── dto/
    └── click-to-chat.dto.ts              # 요청/응답 DTO
```

### 신규 API 엔드포인트

| Method | Path | 설명 | 권한 |
|---|---|---|---|
| `POST` | `/whatsapp/click-to-chat` | 매장 대표자 신원으로 wa.me 링크 생성 + 로그 적재 | admin/gerente/vendedor (Auth) |
| `GET` | `/whatsapp/messages?clientId=:id` | 손님별 발송 이력 조회 | admin/gerente/vendedor (Auth) |
| `GET` | `/whatsapp/templates` | 5개 템플릿 목록 + 변수 스키마 | admin/gerente/vendedor (Auth) |
| `PUT` | `/users/me/whatsapp-phone` | 본인 WhatsApp 번호 등록/삭제 (동의 절차) | self |
| `PUT` | `/stores/:id/representative` | 매장 대표자 지정 (admin 역할 + whatsapp_phone 보유자만) | admin/superadmin |

### POST `/whatsapp/click-to-chat` 요청/응답

**요청 Body:**
```json
{
  "clientId": 42,
  "templateKey": "birthday_greeting",
  "variables": { "promoCode": "CUMPLE-2026" }
}
```

**응답 200:**
```json
{
  "url": "https://wa.me/5491145678901?text=...",
  "representative": {
    "userId": 7,
    "name": "Juan Pérez",
    "whatsappPhone": "+5491145678901"
  },
  "client": {
    "id": 42,
    "fullname": "María Rodríguez",
    "phone": "+5491198765432"
  },
  "logId": 1234
}
```

**응답 400 (대표자 미설정):**
```json
{
  "statusCode": 400,
  "errorCode": "REPRESENTATIVE_NOT_SET",
  "message": "매장 WhatsApp 대표자가 설정되지 않았습니다. 설정 페이지에서 admin 1명을 지정해주세요."
}
```

**응답 400 (손님 전화번호 무효):**
```json
{
  "statusCode": 400,
  "errorCode": "INVALID_CLIENT_PHONE",
  "message": "손님의 전화번호가 유효하지 않습니다 (E.164 정규화 실패)."
}
```

---

## 프론트엔드 변경 (Day 2~3 — 이 SPEC 에 포함, Day 1 은 백엔드 + DB 만)

```
ventago-app/src/
├── views/cliente-vista/
│   └── ClienteVistaView.tsx              # [WhatsApp] 버튼 추가 (행 액션)
├── views/whatsapp/
│   ├── WhatsAppSendDialog.tsx            # 템플릿 선택 + 발송자 안내 모달
│   └── WhatsAppHistory.tsx               # 손님별 발송 이력
├── hooks/api/
│   ├── useWhatsAppTemplates.ts           # SWR 훅 — 템플릿 목록 (60분 dedup)
│   └── useWhatsAppHistory.ts             # SWR 훅 — 발송 이력 (5분 dedup)
└── views/configuracion/
    └── WhatsAppRepresentativeCard.tsx    # 매장 대표자 지정 UI
```

---

## 5개 템플릿 (Day 1 은 백엔드 등록만, 프론트 노출은 Day 2)

| key | 카테고리 | 변수 | 예시 |
|---|---|---|---|
| `birthday_greeting` | 마케팅 | fullname, promoCode | "¡Feliz cumpleaños {{fullname}}! Código: {{promoCode}}" |
| `credit_reminder` | 운영 | fullname, deuda, dueDate | "Hola {{fullname}}, saldo pendiente: ${{deuda}}..." |
| `inactive_winback_60d` | 마케팅 | fullname, lastVisitDate | "{{fullname}}, hace tiempo que no te vemos..." |
| `new_product_announce` | 마케팅 | fullname, productName | "¡Hola {{fullname}}! Llegó {{productName}}..." |
| `receipt_resend` | 운영 | fullname, saleId, total, date | "Aquí está tu comprobante de la venta del {{date}}..." |

전체 메시지 본문은 `template-registry.ts` 에 상수 객체로 정의. i18n 은 향후 작업.

---

## 태스크 목록

### Day 1 — 백엔드 + DB 기초 (이번 세션)

- [ ] **TASK-1**: 마이그레이션 SQL 3 개 작성 (PG10/PG15 호환)
  - 파일:
    - `api-ventago/migrations/2026-05-12-phase29b-users-whatsapp.sql`
    - `api-ventago/migrations/2026-05-12-phase29b-stores-representative.sql`
    - `api-ventago/migrations/2026-05-12-phase29b-whatsapp-messages.sql`

- [ ] **TASK-2**: `users.model.ts` 에 `whatsappPhone` 필드 추가
  - 파일: `api-ventago/src/app/users/users.model.ts`

- [ ] **TASK-3**: `store.model.ts` 에 `representativeUserId` + `representative` 관계 추가
  - 파일: `api-ventago/src/app/store/store.model.ts`

- [ ] **TASK-4**: `whatsapp-message.model.ts` 신규 작성
  - 파일: `api-ventago/src/app/whatsapp/whatsapp-message.model.ts`

- [ ] **TASK-5**: `phone-normalizer.service.ts` 작성 (E.164 정규화, libphonenumber-js)
  - 파일: `api-ventago/src/app/whatsapp/services/phone-normalizer.service.ts`
  - 의존성 추가: `npm install libphonenumber-js --workspace=api-ventago`

- [ ] **TASK-6**: `template-registry.ts` 작성 — 5개 템플릿 + 변수 치환
  - 파일: `api-ventago/src/app/whatsapp/templates/template-registry.ts`

- [ ] **TASK-7**: `click-to-chat.service.ts` 작성 — 핵심 로직
  - 파일: `api-ventago/src/app/whatsapp/services/click-to-chat.service.ts`

- [ ] **TASK-8**: `whatsapp.controller.ts` + `dto/click-to-chat.dto.ts` 작성
  - 파일:
    - `api-ventago/src/app/whatsapp/whatsapp.controller.ts`
    - `api-ventago/src/app/whatsapp/dto/click-to-chat.dto.ts`

- [ ] **TASK-9**: `whatsapp.module.ts` 작성 + `app.module.ts` 에 등록
  - 파일:
    - `api-ventago/src/app/whatsapp/whatsapp.module.ts`
    - `api-ventago/src/app/app.module.ts` (imports 추가)

- [ ] **TASK-10**: ESLint 검증 실행 — 신규/수정 파일 모두 통과
- [ ] **TASK-11**: PostgreSQL pool 안전 점검 — Sequelize transaction / connection 사용 패턴 검증

### Day 2 — 프론트엔드 통합 (다음 세션)

- [ ] **TASK-12**: `WhatsAppSendDialog.tsx` — 템플릿 선택 + 발송자 신원 안내 모달
- [ ] **TASK-13**: `useWhatsAppTemplates.ts`, `useWhatsAppHistory.ts` SWR 훅
- [ ] **TASK-14**: `ClienteVistaView.tsx` 의 DataGrid 행 액션에 [WhatsApp] 버튼 추가
- [ ] **TASK-15**: 매장 대표자 지정 UI (`WhatsAppRepresentativeCard.tsx`)

### Day 3 — 운영 셋업 + dogfood (다음 세션)

- [ ] **TASK-16**: 운영 DB 마이그레이션 SQL 3 개 실행 (사용자 확인 후)
- [ ] **TASK-17**: ACE 매장 representative_user_id 설정 + 마르코스님 본인 whatsapp_phone 입력
- [ ] **TASK-18**: 실제 손님 1명 대상 dogfood — wa.me 동작 확인
- [ ] **TASK-19**: 로그 파일 확인 — 새 에러 없는지 점검

---

## 완료 기준 (Day 1)

- [ ] ESLint 오류 0개 (모든 신규/수정 파일)
- [ ] TypeScript 컴파일 통과 (`nest build`)
- [ ] 마이그레이션 SQL 3개 — PG10 / PG15 양쪽 문법 호환 확인 (구문만, 로컬 실행은 사용자 동의 후)
- [ ] `click-to-chat.service.ts` 의 모든 async 함수에 try/catch
- [ ] PostgreSQL pool 체크리스트 (아래) 전부 통과
- [ ] 모든 신규 파일에 한국어 주석 + 영어 함수/변수명

### Day 2~3 완료 기준 (후속)
- [ ] 베타 매장 ACE 에서 실제 1건 발송 성공
- [ ] `whatsapp_messages` 테이블에 `status='link_generated'` row 정상 INSERT 확인
- [ ] 로그 파일에 신규 에러 없음

---

## PostgreSQL Pool 안전 체크리스트

1. **신규 쿼리는 모두 Sequelize 모델 메서드 사용** (pool.connect() raw 호출 금지)
   - `Model.findByPk()`, `Model.findOne()`, `Model.create()`
   - Sequelize 가 connection 자동 반환 → release 누락 위험 없음

2. **트랜잭션 사용 시**: `sequelize.transaction(async (t) => { ... })` 콜백 패턴 사용
   - 콜백 형식은 commit/rollback 자동 처리 → release 보장

3. **N+1 쿼리 방지**: `include` 옵션으로 JOIN
   - `Store.findByPk(storeId, { include: [{ association: 'representative' }] })`

4. **MemoryCache 활용**: 템플릿 목록(`/whatsapp/templates`)은 상수라 캐시 불필요. 다만 representative 정보는 매장당 1회 조회 후 60초 TTL 권장 (10번 클릭 = 1쿼리)

5. **에러 시에도 connection 반환**: try/catch + Sequelize 사용 시 자동 반환됨. raw query 절대 사용 금지.

---

## 금지사항 / 주의사항

### 절대 금지
- ❌ **Baileys / venom-bot / WPPConnect 등 비공식 WhatsApp 라이브러리 사용** (Meta 차단 위험)
- ❌ **사용자 전화번호 자유 입력 그대로 DB 저장** (반드시 E.164 정규화)
- ❌ **`pool.connect()` raw 호출** (Sequelize 사용 강제)
- ❌ **template body 에 사용자 입력 변수 직접 삽입** (반드시 `encodeURIComponent` 적용)
- ❌ **마이그레이션 SQL 운영 직접 실행** (사용자 동의 후에만 — CLAUDE.md 규약)

### 주의
- ⚠️ **CommonJS vs ESM**: `libphonenumber-js` 는 CommonJS — `import { parsePhoneNumber } from 'libphonenumber-js'` 정상 동작
- ⚠️ **PG10 호환 SQL**: `GENERATED AS IDENTITY` 사용 금지 → `SERIAL` 사용
- ⚠️ **ESLint `newline-before-return`**: `return` 위에 빈 줄 필수
- ⚠️ **ESLint `lines-around-comment`**: `//` 주석 위에 빈 줄 필수
- ⚠️ **Sequelize `underscored: true`**: 모델에 camelCase 로 선언 → DB 는 snake_case 자동 변환
- ⚠️ **개인정보 보호**: `users.whatsapp_phone` 은 본인만 조회/수정 가능 (superadmin 예외)
- ⚠️ **소켓 알림**: 발송 시 운영 다른 직원에게 socket.io 로 알림 줄 필요 있는지 검토 — 이번 SPEC 에서는 **미포함** (필요하면 별도 추가)

---

## 후속 작업 (이 SPEC 범위 외)

- Wave A: Cliente 360 페이지 (`spec-phase29-wave-a-cliente360.md` 별도 작성 예정)
- Wave C: Meta Cloud API 자동 발송 (생일 D-1 cron, 외상 D-3 자동 등)
- 손님 응답률 측정 — Click-to-Chat 한계 (수동 카운트 또는 Cloud API 전환 후 가능)
- ROI attribution (발송 후 30일 내 재방문 자동 집계) — RFM materialized view 완성 후

---

## 참고

- Mockup HTML: `docs/crm-wave-a-b-mockup.html` (탭 4·5·6)
- 이전 분석 대화: 2026-05-12 마르코스님 ↔ Claude
- CLAUDE.md 운영 규약: 운영 4매장, pool=50, 마이그레이션 사용자 동의
