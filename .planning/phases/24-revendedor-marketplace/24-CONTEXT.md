# Phase 24: Revendedor Marketplace — 중개형 (Commission-based) Context

**Gathered:** 2026-04-20
**Status:** Ready for planning
**Mode:** Greenfield extension — 기존 `revendedor/` + `marketplace/` 모듈 확장 + 신규 `reseller` 스키마 도입

<domain>
## Phase Boundary

100개+ Tienda의 상품을 Revendedor가 **주문 중개(커미션) 방식**으로 영업·판매하는 마켓플레이스 구축. Revendedor는 재고 리스크를 지지 않고, 통합 카탈로그에서 상품을 검색해 **최소가 하한선 + 자유 마진** 규칙으로 견적을 만들고 고객에게 제시한다. Tienda가 주문을 확정/출고하며, 플랫폼은 수수료를 차감한 뒤 정산한다. **도매가·권장소비자가·브랜드 정보를 모두 공개**하는 공동 브랜딩(co-branding) 모델.

핵심 책임:
1. Revendedor 가입/검증(CUIT/RUT/RFC) + 관리자 승인 워크플로우
2. Tienda ↔ Revendedor 연결 승인 + 매장별 공유 정책(카테고리/상품 필터, 수수료율, 재고 홀드 시간)
3. 통합 카탈로그(Materialized View) + 카테고리 통합 검색 + 가격 비교 뷰
4. 견적 생성 시 **N분(기본 30분) 재고 홀드** → 고객 수락 시 주문 확정
5. 주문 상태머신(pending_tienda → confirmed → preparing → shipped → delivered → completed) + 상태 이력 로그
6. 수수료 계산 + 정산 주기 배치 + 지급 내역
7. Revendedor Flutter 앱 (로그인/가입/카탈로그/견적/주문/정산)

기존 `api-ventago/src/app/revendedor/` (auth/products/purchase/strategies/guards) + `marketplace/` (marketplace-config/product-visibility/public-products/public-purchase) 모듈을 재사용·확장한다.

</domain>

<decisions>
## Implementation Decisions

### 비즈니스 모델
- **D-01:** 주문 중개형(커미션) 모델 — Revendedor는 재고 리스크 없음. 플랫폼이 주문 흐름·정산·분쟁 처리 담당
- **D-02:** 최소가(wholesale) 하한선 + 자유 마진 구조. `final_price ≥ wholesale_price * (1 + min_markup_pct/100)` 서버 검증 필수
- **D-03:** 도매가(wholesale_price) + 권장소비자가(suggested_price) + 브랜드(Tienda) 정보 모두 Revendedor에게 공개 (화이트라벨 아님)
- **D-04:** 플랫폼 수수료는 **Tienda별 정책**(`tienda_sharing_policy.commission_pct`)이 기본값, Revendedor-Tienda 링크별 `custom_commission_pct` override 허용

### 결제 흐름
- **D-05:** (결정 필요) Tienda 직접 수령(고객 → Tienda → 정산 시 커미션 분배) vs 플랫폼 에스크로(고객 → 플랫폼 → 분배). 남미 규제·PSP 연동 비용 고려. **기본 방향: Tienda 직접 수령** → Phase 내 결제 부분은 "pending / paid / settled" 상태 기록만 하고, 실제 PSP 연동은 별도 phase로 분리
- **D-06:** 정산 주기 기본값: 주 1회 (금요일 기준). Tienda별 설정 가능 (향후)

### DB 스키마
- **D-07:** 신규 `reseller` 스키마 생성 — 기존 `public` 스키마는 읽기 전용 뷰로만 참조하여 영향 범위 최소화
- **D-08:** 핵심 테이블 7개 — `resellers`, `tienda_sharing_policy`, `reseller_tienda_link`, `quotes`, `quote_items`, `orders`, `order_status_log`
- **D-09:** 견적(quotes)에 `expires_at` 타임스탬프 + 부분 인덱스(`WHERE status='active'`)로 만료 스캔 효율화
- **D-10:** 주문 상태머신은 DB CHECK 제약으로 enum-like 열거 — 마이그레이션 시 `chk_order_status` 추가
- **D-11:** 상태 전이마다 `order_status_log`에 from/to/changed_by/note 기록 (분쟁 대비 감사 추적)

### 통합 카탈로그
- **D-12:** `reseller.catalog_unified` Materialized View — `productos` × `stock` × `tiendas` × `tienda_sharing_policy` JOIN
- **D-13:** 5~10분 주기 `REFRESH MATERIALIZED VIEW CONCURRENTLY` (pg_cron 또는 NestJS `@Cron`)
- **D-14:** `allowed_categories` / `excluded_products` 필터를 MV 레벨에 적용하여 런타임 필터링 비용 절감
- **D-15:** 인덱스: `(product_id, tienda_id)` UNIQUE + `categoria_id WHERE has_stock=true` 부분 인덱스 + `tienda_id`

### 재고 홀드 (견적 유효 시간)
- **D-16:** 견적 생성 시 `tienda_sharing_policy.reserve_minutes`(기본 30분) 동안 재고를 논리적으로 홀드. 실제 재고 차감은 주문 확정 시점
- **D-17:** 홀드 만료는 cron (분당 스캔) — `UPDATE quotes SET status='expired' WHERE status='active' AND expires_at < NOW()`
- **D-18:** 동일 상품에 대한 복수 활성 견적 존재 허용 — 실제 재고 충돌은 주문 확정(`pending_tienda` → `confirmed`) 시 재확인. 부족 시 Tienda가 거절 가능

### Node.js / NestJS Pool 안전
- **D-19:** 기존 Sequelize 전역 pool(max=50) 재사용. `reseller` 스키마 모델은 Sequelize 레벨에서 `schema: 'reseller'` 옵션으로 매핑
- **D-20:** 트랜잭션은 `sequelize.transaction()` 패턴. `FOR UPDATE` 락은 재고/정산 확정 시에만 사용
- **D-21:** Raw SQL 사용 시(`MV refresh`, `bulk update`) 반드시 `try/finally`에서 connection release 확인

### Flutter 앱
- **D-22:** 독립 Flutter 앱(`revendedor-app/`) 신규 생성. Phase 17(`portal-de-talleres`) 구조를 템플릿으로 차용 — Dio + Riverpod + secure storage + JWT 리프레시
- **D-23:** 최소 화면: 로그인/가입(서류 업로드), 홈 대시보드, 카테고리 브라우저, 상품 상세(Tienda별 가격/재고 비교 + 마진 계산기), 견적 작성(유효시간 표시), 주문 관리, 정산 내역, 프로필
- **D-24:** 상태관리 — Tienda 목록/카테고리 캐시는 `AsyncNotifierProvider`, 견적 작성은 `NotifierProvider`

### 관리자 화면
- **D-25:** 기존 Ventago 프론트(ventago-app)에 `revendedor-admin` 섹션 추가 — Revendedor 목록/승인, Tienda 공유 정책 편집, Tienda-Revendedor 링크 승인, 주문 모니터링, 정산 대시보드
- **D-26:** 권한은 Phase 14 CASL — `function_slug: 'revendedor_admin'` 신규 추가, CRUD 액션 기반 접근 제어

### Claude's Discretion
- 카테고리 통합 검색 UI의 필터 UX 세부사항
- 마진 계산기 컴포넌트의 입력 방식(퍼센트 vs 절대금액 vs 슬라이더)
- Tienda별 정책 편집 화면의 구체 레이아웃
- 정산 배치의 실행 시간(권장: 토요일 02:00 local)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### 기존 구현 (백엔드)
- `api-ventago/src/app/revendedor/revendedor.module.ts` — 기존 Revendedor 모듈 (확장 대상)
- `api-ventago/src/app/revendedor/revendedor.model.ts` — 기존 Revendedor 모델
- `api-ventago/src/app/revendedor/auth/` — JWT 인증 기반 (reseller 앱 JWT로 재사용)
- `api-ventago/src/app/revendedor/products/` — 기존 상품 노출 API
- `api-ventago/src/app/revendedor/purchase/` — 기존 구매 로직 (quote/order 전환 대상)
- `api-ventago/src/app/revendedor/guards/` — 가드 패턴 참고
- `api-ventago/src/app/marketplace/marketplace-config/` — 매장 공유 정책 참고
- `api-ventago/src/app/marketplace/product-visibility/` — 상품 가시성 정책 (reseller 정책과 통합 여부 결정)
- `api-ventago/src/app/marketplace/public-products/` — 공개 상품 조회 (MV와 역할 구분 필요)

### 연관 모듈
- `api-ventago/src/app/auth/auth.service.ts` — /me 엔드포인트, Phase 14 permissions 맵
- `api-ventago/src/app/store/store.model.ts` — Store 모델 (storeId → tiendaId 매핑)
- `api-ventago/src/app/products/products.model.ts` — Product 모델 (wholesale/suggested price 필드 확인)
- `api-ventago/src/app/products/stock/` — 재고 서비스 (홀드 로직 연동점)

### Flutter 앱 템플릿 (Phase 17)
- `portal-talleres-app/` — Dio + Riverpod + secure storage 구조 참조
- `.planning/phases/17-portal-de-talleres-aviso/17-03-PLAN.md` — Flutter 프로젝트 생성 + core infra 플랜 참고
- `.planning/phases/17-portal-de-talleres-aviso/17-04-PLAN.md` — 리스트/상세/다이얼로그 패턴 참고

### 프론트엔드 관리자 UI
- `ventago-app/src/pages/admin/` — 관리자 페이지 구조
- `ventago-app/src/configs/acl.ts` — CASL ability 빌더
- `ventago-app/src/navigation/vertical/index.ts` — 사이드바 권한 기반 숨김
- `ventago-app/src/services/api.service.ts` — apiConnector 사용 규약

### 프로젝트 컨벤션
- `.planning/codebase/CONVENTIONS.md` — 코딩 컨벤션
- `CLAUDE.md` — Sequelize `underscored: true` (DB snake_case), pool max=50, slow query 100ms 금지
- `~/.claude/CLAUDE.md` — PostgreSQL 안전 마이그레이션, pool 낭비 금지

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `revendedor/auth/` JWT Passport 전략 — reseller app JWT로 재사용
- `revendedor/products/` 기존 상품 필터링 로직 — MV 기반으로 교체 예정
- `marketplace-config` — Tienda 단위 공유 설정 패턴 확립됨 → `tienda_sharing_policy`로 확장
- Sequelize 트랜잭션 패턴 — 기존 `sales.service.ts`의 `sequelize.transaction()` 사용 참조
- `@nestjs/schedule` — `@Cron` 데코레이터로 MV refresh / quote expire 스캔 구현

### Established Patterns
- 모듈별 model/service/controller/dto 분리 구조
- `@UseGuards(JwtAuthGuard)` + `@CurrentUser()` 데코레이터 패턴
- Socket.io 네임스페이스 패턴 (`/print-agent`) → `/reseller` 추가 가능 (실시간 주문 알림)
- Store lifecycle guard (Phase 9) — SUSPENDED/ARCHIVED 매장은 reseller 노출 제외

### Integration Points
- `stores.lifecycle_state` — ACTIVE 매장만 `tienda_sharing_policy.is_active` 허용
- `users` 테이블의 store admin → Tienda 정책 편집 권한 소유자
- 기존 `productos` / `stock` 테이블 → MV 소스 데이터
- Phase 14 CASL → `revendedor_admin` function slug CRUD 액션
- Phase 21 Store Baseline Invariant → reseller 관련 기본 설정 자동 생성(공유 정책 초기값) 고려

### Potential Conflicts
- 기존 `revendedor/purchase/` 엔드포인트 — 직접 구매 흐름 → 견적/주문 흐름으로 마이그레이션 필요. 기존 엔드포인트 deprecate 경로 설계 필요
- `marketplace/product-visibility` vs `reseller.tienda_sharing_policy` — 역할 중복. 통합 또는 명확한 분리 결정 필요 (제안: marketplace는 공개 B2C, reseller는 B2B2C로 분리)

</code_context>

<specifics>
## Specific Ideas

- Wave 1 (2~3주): **기반 구축** — `reseller` 스키마 생성, `resellers` / `tienda_sharing_policy` / `reseller_tienda_link` 테이블 + 마이그레이션, 재판매자 가입/검증 API, 관리자 승인 화면
- Wave 2 (2~3주): **카탈로그** — `catalog_unified` Materialized View + refresh cron, 카테고리/검색/필터 API, Flutter 브라우저 화면, 마진 계산기 컴포넌트
- Wave 3 (3~4주): **주문 플로우** — `quotes` / `quote_items` / `orders` / `order_status_log` 테이블, 견적 생성 + 30분 홀드 로직, 주문 확정/상태머신, Tienda POS 측 주문 관리 탭 추가
- Wave 4 (2주): **정산** — 수수료 계산 배치, 정산 주기 cron(주 1회 금요일), Revendedor 앱 정산 내역 화면, Tienda 측 정산 대시보드
- Wave 5 (지속): **고도화** — 분쟁 처리 워크플로우, FCM 푸시 알림, Revendedor 실적 리포트, Tienda별 Revendedor 성과 대시보드

### 기술 포인트
- Materialized View refresh는 `CONCURRENTLY` 필수 (읽기 락 최소화)
- 견적 만료 스캔 cron은 `* * * * *` (1분 주기), 부분 인덱스 `WHERE status='active'`로 스캔 범위 제한
- 주문 확정 시 `FOR UPDATE` 락은 stock row만 — 전체 테이블 락 금지
- 정산 배치는 idempotent — 동일 기간 재실행 시 중복 지급 방지(`settled_at IS NULL` 조건)
- Flutter 앱은 Android/iOS 모두 빌드 대상. Dio interceptor에서 JWT 리프레시

### 보안
- 재판매자 CUIT/RUT/RFC 검증은 수동 승인(superadmin) + 문서 이미지 업로드(MinIO 저장)
- `reseller_id` vs `tienda_id` 권한 경계 엄격 분리 — Revendedor는 승인된 Tienda 상품만 조회, Tienda 유저는 자기 tienda_id 주문만 편집
- 주문 상태 변경 시 `changed_by` 필수 기록 (감사 추적)

</specifics>

<deferred>
## Deferred Ideas

- 플랫폼 에스크로 결제(Mercado Pago/Stripe/dLocal) — 별도 Phase 25로 분리
- Revendedor 성과 기반 자동 티어(Bronze/Silver/Gold)와 수수료율 차등
- AI 추천 상품(유사 카테고리/히트 상품) — Phase 3 AI 채팅과 연동
- 대량 주문(bulk) 일괄 견적 생성
- Revendedor ↔ 고객 직접 채팅(in-app messaging)
- 반품/교환 워크플로우
- 다중 통화 지원 (현재는 tienda 기준 로컬 통화)
- Revendedor 서브 계정(팀 운영) — 현재는 1인 Revendedor 가정

</deferred>

---

*Phase: 24-revendedor-marketplace*
*Context gathered: 2026-04-20*
