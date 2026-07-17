# Revendedor 온보딩 + 읽기 전용 카탈로그 앱 (Path B) — Design

작성일: 2026-07-17
상태: 설계 확정 (Execute 미착수). Brainstorming 승인 완료 → writing-plans 대기.

## 0. 배경 / 문제

`mobile-sales-app` 의 revendedor 모드는 스텁 3개(`revendedor_home` / `store_selector_screen` / `quote_screen`)로 "Próximamente — requiere Phase 24" placeholder 만 렌더한다. Phase 24(중개형 마켓플레이스)는 2026-07-17 삭제됨. 그러나 Phase 24 슬라이스로 병합된 `reseller` 백엔드 모듈(Plan A: auth/catalog/recommendation/geo + `reseller` 스키마)은 유지된다.

이 설계는 그 병합 백엔드를 활용해 revendedor 앱을 **읽기 전용 MVP** 로 완성하고, 그 앞단에 **외부 가입자 온보딩(가입·서류·관리자 승인)** 을 붙인다.

## 1. 확정 결정 (Locked)

- **D-B1 신원 = 외부 가입자 `reseller.resellers`** (Path B). `users` 역할이 아님. 로그인 = `POST /reseller/auth/login`, JWT `{ sub, type:'reseller' }`. vendedor 의 `/mobile/*` realm 과 완전 분리.
- **D-B2 로그인 식별자 = `{id}@app`** — 합성 이메일. `{id}` = 등록 시 document(DNI). `reseller.resellers.email` 에 `<document>@app` 저장. 앱 로그인 화면에서 `id@app` + 암호.
- **D-B3 온보딩 = 가입 → 서류 제출 → 관리자 승인 → 판매권 부여 → 로그인 개방**. 승인 전엔 로그인 불가(`status != 'approved'` → 401).
- **D-B4 서류 저장 = 신규 테이블 `reseller.reseller_documents`** (감사·재제출 이력). MinIO 저장.
- **D-B5 관리자 심사 = ventago-app 웹 admin (superadmin 섹션)**. 기존 admin 인프라 + MinIO 이미지 프리뷰 재사용.
- **D-B6 판매/견적(pedido)은 이번 범위 제외** — 병합 백엔드에 판매 엔드포인트 없음. 후속 슬라이스.
- **D-B7 vendedor(`/mobile/*`) 경로 무변경** — 회귀 절대 금지 (공유 경로 안 건드림).

## 2. 신원 모델 (혼동 방지)

revendedor 관련 3개 개념이 코드에 공존한다. 본 설계는 **오직 #3** 만 사용:

| # | 소스 | 정체 | 본 설계 |
|---|------|------|---------|
| 1 | `revendedores` 테이블 | 구 재판매 포털 (레거시) | 사용 안 함 |
| 2 | `users.role='revendedor'` | owner 내 N매장 내부 사용자 (`/mobile` MultiStoreScope, 현재 백엔드 차단) | 사용 안 함 |
| 3 | `reseller.resellers` | 외부 가입 재판매자 (자체 document/email/password, 매장별 승인) | **✅ 사용** |

`mobile-auth.service` 의 revendedor 분기(`Modo revendedor aún no habilitado` throw)와 `mobile-catalog` 의 `REVENDEDOR_NOT_IMPLEMENTED` 는 **그대로 둔다**(#2 경로, 미사용).

## 3. 백엔드 변경 (`api-ventago/src/app/reseller/`)

### 3.1 스키마 마이그레이션 (신규 SQL, 로컬 5432 + 운영 5434 동시)

```sql
-- resellers 심사 상태
ALTER TABLE reseller.resellers
  ADD COLUMN IF NOT EXISTS status VARCHAR(16) NOT NULL DEFAULT 'pending_review';
-- CHECK: pending_review | approved | rejected
ALTER TABLE reseller.resellers
  ADD CONSTRAINT chk_reseller_status
  CHECK (status IN ('pending_review','approved','rejected'));

-- 서류 (감사/재제출 이력)
CREATE TABLE IF NOT EXISTS reseller.reseller_documents (
  id           SERIAL PRIMARY KEY,
  reseller_id  INTEGER NOT NULL REFERENCES reseller.resellers(id) ON DELETE CASCADE,
  doc_type     VARCHAR(24) NOT NULL,     -- 'dni_photo' | 'residence_cert' | 'selfie'
  file_name    VARCHAR(255) NOT NULL,    -- MinIO object name
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_doc_type CHECK (doc_type IN ('dni_photo','residence_cert','selfie'))
);
CREATE INDEX IF NOT EXISTS idx_reseller_docs_reseller ON reseller.reseller_documents(reseller_id);

-- 심사 메타 (거부 사유/심사자)
ALTER TABLE reseller.resellers
  ADD COLUMN IF NOT EXISTS reviewed_by INTEGER,
  ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS reject_reason VARCHAR(300);
```

마이그레이션 끝에 owner→coolsistema DO 블록(테이블+시퀀스). `reseller` 스키마 전체 소유권 확인.

### 3.2 엔드포인트

**신규:**
- `POST /reseller/auth/register` (공개, multipart) — 필드: `name`, `phone`, `document`, `password`, `storeIds[]`(판매 희망 매장), + 이미지 3종(`dniPhoto`, `residenceCert`, `selfie`).
  - 트랜잭션: `resellers`(email=`{document}@app`, password=bcrypt, status=`pending_review`, is_active=false) INSERT → 이미지 3종 MinIO 업로드 후 `reseller_documents` INSERT → `storeIds` 각각 `reseller_tienda_link`(status=`pending`) UPSERT.
  - document/email 중복 시 409.
- `GET /admin/resellers?status=pending_review` (superadmin) — 목록 + 서류 URL(`{API_HOST}/minio/{fileName}`) + 희망 매장.
- `PATCH /admin/resellers/:id/approve` (superadmin) — body: `storeIds[]`(승인할 매장, 부분 승인 허용). `resellers.status=approved, is_active=true, reviewed_by, reviewed_at` + 해당 `reseller_tienda_link.status=approved`. IDOR/권한 가드(superadmin only).
- `PATCH /admin/resellers/:id/reject` — `status=rejected, reject_reason`.

**변경:**
- `reseller-auth.service.login` — 기존 `is_active`/password 검증에 **`status='approved'` 게이트 추가**. 미승인 시 401 `RESELLER_NOT_APPROVED`.
- `reseller-auth` `GET /me` — 반환에 **승인된 매장 목록** 포함(`reseller_tienda_link` status=approved JOIN stores → `[{storeId, storeName}]`). store selector 소스.
- `reseller-catalog.service.catalog` — 이미 `reseller.id` 스코프. **`reseller_tienda_link.status='approved'` 필터 확인/보강**(pending 매장 상품 노출 금지).

### 3.3 Pool / 성능
- register = INSERT 소수 + MinIO 업로드(외부 I/O, DB 커넥션 점유 최소화 — 업로드 후 DB write). catalog/me = 인덱스 조회. 전역 Sequelize pool 재사용, raw SQL 경로 release 보장.

## 4. 관리자 승인 콘솔 (ventago-app 웹, superadmin)

- 신규 페이지 `pages/admin/revendedores` (superadmin 게이트).
- pending 목록 테이블: nombre / document / phone / 희망매장 / 제출일.
- 상세 drawer: 서류 3종 이미지 프리뷰(`next/Image`, MinIO URL) + 매장별 승인 체크박스 + 승인/거부 버튼(거부 사유 입력).
- API: `apiConnector.get('/admin/resellers?...')`, `apiConnector.put('/admin/resellers/:id/approve', {storeIds})`.
- 에러 = 인라인 Alert + 글로벌 토스트(프로젝트 규약).
- ESLint 규약 준수(newline-before-return, lines-around-comment). SWR 로 목록 캐시.

## 5. 앱 (`mobile-sales-app`)

### 5.1 온보딩
- **로그인 화면**: `hacer nueva tienda` 옆에 **"Quiero registrarme como revendedor"** 진입.
- **가입 스크린**: 폼(nombre/teléfono/id/암호) + 이미지 3종 업로드(`image_picker` + multipart) + 판매 희망 매장 선택(공개 매장 목록 조회 필요 — `GET /reseller/public/stores` 또는 기존 공개 매장 API 재사용). 제출 → `POST /reseller/auth/register`.
- **심사중 화면**: 가입 후 "Pendiente de revisión" 안내 + 로그인 화면 복귀.

### 5.2 읽기 MVP (스텁 대체)
- `revendedor_home.dart`: 지역 추천제품(`GET /reseller/recommendations`) 리스트 + GPS 지역감지(`POST /reseller/detect-province`, 위치 권한). 추천 카드 탭 → 카탈로그 상세.
- `store_selector_screen.dart`: `/reseller/auth/me` 의 승인 매장 목록 → 매장 선택/전체.
- `catalog` (신규 or `quote_screen` 대체): 검색-리스트(D-14, QR 아님) + canonical category 필터(`GET /reseller/canonical-categories`) + `GET /reseller/catalog`. 카드 = name/sku/price/storeName/inStock. 페이지네이션.
- 인증: `reseller-jwt` 토큰 secure storage 저장. Dio 인터셉터로 `Authorization: Bearer`. scope_provider 는 vendedor 전용 유지, revendedor 는 별도 reseller session provider 신규.

### 5.3 라우팅
- 로그인 응답 `type:'reseller'` → `/revendedor/home`. `MultiStoreScope`(#2) 경로는 미사용이므로 라우터의 revendedor 분기를 reseller session 기준으로 교체(단, vendedor `/home` 분기 무변경).

## 6. 데이터 플로우

```
[가입] 앱 register form ─multipart→ POST /reseller/auth/register
   → resellers(pending) + reseller_documents(MinIO) + reseller_tienda_link(pending)
[심사] 웹 admin GET /admin/resellers?pending → 서류 프리뷰
   → PATCH approve{storeIds} → resellers.approved + links.approved
[로그인] 앱 {id}@app+pw → POST /reseller/auth/login (status=approved 게이트) → reseller JWT
[열람] GET /reseller/auth/me(승인매장) / GET /reseller/catalog(승인매장 스코프)
        / GET /reseller/recommendations / POST /reseller/detect-province
```

## 7. 에러 / 엣지
- 미승인 로그인 → 401 `RESELLER_NOT_APPROVED` (앱: "En revisión / rechazado" 분기 메시지).
- document 중복 가입 → 409 (앱 인라인).
- 부분 매장 승인 → 승인된 매장만 catalog 노출.
- 거부 후 재제출 → 새 `reseller_documents` 행(이력 보존), status=pending_review 복귀.
- MinIO 업로드 실패 → register 트랜잭션 롤백(고아 reseller 방지).
- 위치 권한 거부 → GPS 없이 수동 provincia 선택 폴백.

## 8. 테스트
- 백엔드 Jest: register 트랜잭션(성공/이미지실패 롤백/중복 409), login status 게이트(pending→401, approved→200), /me 승인매장만, catalog approved 스코프.
- 앱 flutter test: register form 검증, reseller session provider, catalog 페이지네이션.
- 회귀: vendedor `/mobile/*` 로그인/카탈로그/판매 무영향(별도 realm) — 명시 확인.

## 9. 마이그레이션 규칙
- 3.1 SQL → `api-ventago/migrations/2026-07-17-reseller-onboarding.sql`. 로컬 5432(사용자 실행) + 운영 5434(SSH) **동시 적용**. owner→coolsistema DO 블록 필수.

## 10. 범위 분해 (waves → writing-plans 입력)
1. **BE-온보딩**: 마이그레이션 + register(MinIO 트랜잭션) + login status게이트 + /me 승인매장 + catalog approved 필터 + Jest.
2. **웹-승인콘솔**: superadmin `/admin/resellers` 목록/서류뷰/승인·거부·매장권부여 + API.
3. **앱-온보딩**: 로그인 진입 + 가입폼(이미지3업로드) + 심사중 화면 + reseller session/Dio.
4. **앱-읽기MVP**: home(추천+GPS) / store selector / catalog 검색-리스트.

## 11. 범위 밖 (후속)
- 판매/견적/주문(pedido) = 보류(Caja-neutral) 생성 — 신규 백엔드 필요 (D-B6).
- reseller 실적/정산, FCM 알림, ventago-admin-app 이관.

## 12. 미해결/가정
- 판매 희망 매장 목록 조회용 공개 API: 기존 공개 매장 엔드포인트 재사용 가능한지 Plan 단계에서 확인(없으면 `GET /reseller/public/stores` 최소 추가).
- `{id}@app` 충돌(동일 document 재가입) 정책: document UNIQUE 로 1차 차단.
