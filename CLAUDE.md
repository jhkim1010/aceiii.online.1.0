# Ventago — POS/ERP 시스템 개발 가이드

## 프로젝트 개요

다점포 소매업 대상 POS/ERP 시스템. 재고·판매·재무·생산·외주 관리를 포함한 종합 업무 플랫폼.

- **운영 URL**: https://newapi.coolsistema.com/api (API), https://app.coolsistema.com (프론트)
- **운영 서버**: srv803182 (IP: 62.72.7.245, 포트 5002)
- **배포**: Jenkins CI/CD → Docker
- **저장소 구조**: npm workspaces 모노레포

```
ACE_online_1.0/
├── api-ventago/     # NestJS 백엔드 (포트 5002)
├── ventago-app/     # Next.js 프론트엔드 (포트 5001 docker / 3050 dev)
├── print-agent/     # 열감지(comandera) 프린터 에이전트 (Electron)
└── zebra-agent/     # Zebra 바코드 라벨 에이전트 (Electron)
```

---

## 기술 스택

### 백엔드 (api-ventago)
- **Framework**: NestJS 11 + TypeScript
- **ORM**: Sequelize + sequelize-typescript (`underscored: true` 전역 설정 → DB 컬럼은 snake_case)
- **DB**: PostgreSQL 18, DB명 `ventago` — 로컬 Mac 5432 / 운영 srv803182 5434 (둘 다 **호스트 OS 설치**, Docker 아님). 상세는 「DB 마이그레이션 적용 규칙」
- **인증**: JWT (Passport)
- **파일 저장**: MinIO (S3 호환, MinioService/MinioModule로 공유)
- **실시간**: Socket.io
- **로깅**: Winston (nest-winston)
- **스케줄링**: @nestjs/schedule

### 프론트엔드 (ventago-app)
- **Framework**: Next.js 13 (Pages Router) + React 18
- **UI**: Material-UI (MUI) 5
- **상태관리**: Redux Toolkit
- **폼**: React Hook Form + Yup
- **HTTP**: Axios (`src/services/api.service.ts`의 `apiConnector`)
- **데이터 캐시**: SWR (`src/hooks/api/` — 5분 dedup)
- **인가**: CASL (Attribute-based ACL)
- **분석**: PostHog

### 프린터 에이전트 (print-agent / zebra-agent)
- **Framework**: Electron 28
- **WebSocket**: socket.io-client (네임스페이스: `/print-agent`)
- **서버 URL 고정**: 운영 `http://62.72.7.245:5002/api`, 개발 `http://localhost:5002/api`
- **인증**: API Key (BranchAgent 테이블) — 서버 URL 입력 불필요, API Key만 입력
- **print-agent**: ESC/POS 열감지 프린터 (escpos 라이브러리, Network + USB)
- **zebra-agent**: ZPL II 바코드 라벨 (TCP Raw Socket 9100 + USB lp/PowerShell)
- **라벨 타입**: 50x25mm simple, 50x25mm doble, 100x25mm cartulina (좌우 복제)
- **UI 테마**: 다크 네이비 (#1a1a2e) + 골드 (#f5a623)

---

## 아키텍처 핵심 규칙

### DB 컬럼 네이밍
Sequelize `underscored: true` 설정으로 모델의 camelCase 속성이 DB snake_case 컬럼으로 자동 매핑됨.
- 모델: `logoUrl` → DB: `logo_url`
- 모델: `aliasName` → DB: `alias_name`
- **SQL 직접 실행 시 반드시 snake_case 사용**

### DB 스키마 reference (혼동 방지)
SQL/마이그레이션/raw query 작성 전 **반드시 다음 파일 참조** — 추측 X, 컬럼명 확인:
- `.planning/intel/db-schema-tables.md` — 133개 테이블의 모든 컬럼 (타입/NOT NULL/default)
- `.planning/intel/db-schema-fks.md` — 모든 외래 키 관계 (`src_table.src_col → fk_table.fk_col`)

스키마 변경 후 재생성:
```bash
./.planning/intel/db-schema.regen.sh   # local PG18 ventago DB → 두 파일 갱신
```
운영에도 같은 마이그레이션이 적용되므로 로컬 결과를 git commit 하면 됨.

자주 헷갈리는 컬럼명 (실수 방지):
- `sales` 테이블은 `branch_id` 없음 — 지점은 `user_id → users.branch_id` 경유
- `terminal_id` 만 직접 FK. `box`/`branch` 도달은 join 필요
- `sale_items` 의 promo 컬럼: `is_promo_free` / `promotion_id` / `promo_group_id`

### 멀티테넌트 구조
거의 모든 테이블에 `store_id` FK가 있어 매장 단위로 데이터 격리됨.

**계층 구조:** `Store → Branch(Sucursal) → Box(Caja) → Terminal` (1:N:N:N)
- 1개 매장에 여러 지점, 1개 지점에 여러 카하, 1개 카하에 여러 터미널 가능
- Branch 생성 시 기본 Box + Terminal 자동 생성 (`branch.service.ts`의 `createBranch`)
- 매장 최초 등록 시 기본 Branch/Box/Terminal 생성 (`storeTemplate.service.ts`의 `createStoreDefaults`)

### 프린터 에이전트 구조
```
branch_agents (지점당 N개 등록 가능)
  - branchId (NOT UNIQUE → 다중 프린터 허용)
  - agentType: 'thermal' | 'zebra'
  - label: 'Comandera Cocina', 'Zebra Almacén' 등
  - apiKey: UNIQUE (에이전트별 고유 인증 키)
  - isOnline, socketId, lastSeenAt

terminals (터미널별 에이전트 매핑)
  - thermalAgentId FK → branch_agents (어떤 comandera로 출력?)
  - zebraAgentId FK → branch_agents (어떤 zebra로 출력?)
```

### 파일 업로드 (MinIO)
- `MinioModule`을 해당 모듈의 `imports`에 추가
- `MinioService.uploadFile(file, fileName)` → `{ fileName }` 반환
- 프론트엔드 이미지 URL: `{API_HOST}/minio/{fileName}`
- 개발: `http://localhost:5002/api`, 운영: `https://newapi.coolsistema.com/api`

### API 서비스 (`api.service.ts`)
```typescript
apiConnector.get(path)           // GET
apiConnector.post(path, body)    // POST
apiConnector.put(path, body)     // PUT
apiConnector.remove(path)        // DELETE
apiConnector.sendFile(path, formData)  // POST multipart
apiConnector.putFile(path, formData)   // PUT multipart
```

### 인증 컨텍스트
- `useAuth()` 훅으로 `user` 객체 접근. user에는 `storeId`, `storeName`, `aliasName`, `logoUrl`, 권한 정보 포함.
- `AuthContext` + `BranchContext` 분리: `selectedBranchId`는 BranchContext에서 관리 (지점 전환 시 110+ 컴포넌트 불필요 리렌더 방지)
- auth 응답은 `api-ventago/src/app/auth/auth.service.ts`의 `/me` 엔드포인트에서 구성.

### 세션 & 터미널 보안 (`api-ventago/src/app/session/`)
중복 로그인 절대 차단 + 디바이스/IP 기반 부정 사용 방지 시스템.

**테이블 3개:**
- `active_sessions` — 유저당 1개만 존재 (UNIQUE userId). 새 로그인 시 기존 세션 삭제 → 기존 세션은 즉시 401 `SESSION_EXPIRED`
- `terminal_devices` — 브라우저 fingerprint ↔ 터미널 바인딩. 새 디바이스 접속 시 터미널 등록 강제
- `branch_ip_registries` — public IP ↔ 지점(sucursal) 매핑. 새 IP 접속 시 지점 등록 강제

**로그인 플로우:**
1. 자격 증명 검증 → 기존 ActiveSession 삭제 (중복 로그인 차단)
2. IP 확인 → 미등록 IP면 `requireBranchRegistration: true` 반환
3. Fingerprint 확인 → 미등록이면 `requireTerminalRegistration: true` 반환
4. 정상이면 `sessionToken` (UUID v4) 발급

**프론트엔드 연동:**
- `api.service.ts`: 모든 요청에 `x-session-token` 헤더 자동 주입
- `AuthContext.tsx`: 디바이스 fingerprint 수집, sessionToken 저장
- `LoginView.tsx`: Branch/Terminal 등록 모달, 세션만료 알림 (`?reason=session_expired`)
- `utils/device-fingerprint.ts`: 브라우저 특성 SHA-256 해시

**SessionGuard 적용:** `guards/session.guard.ts` — JWT 인증 후 추가로 sessionToken 검증. 필요한 컨트롤러에 `@UseGuards(SessionGuard)` 적용.

---

## 주요 모듈 맵

### 백엔드 모듈 위치
```
api-ventago/src/app/
├── auth/           # JWT 인증, 권한 가드
├── store/          # 매장 관리 (로고 업로드 포함)
├── branch/         # 지점 관리
├── users/          # 사용자, 역할, 권한
├── products/       # 상품, 카테고리, 재고
├── sales/          # 판매, 결제수단, 할인
├── expenses/       # 비용 관리
├── box/            # 금전함 운영
├── caja-fuerte/    # 금고 관리
├── production/     # 생산 관리 (BOM, 작업지시)
├── subcon/         # 외주 (납품업체, 발주, 검수, 정산)
├── print/          # 프린터 에이전트 관리 (BranchAgent, WebSocket 게이트웨이)
├── terminal/       # 터미널 관리 (에이전트 매핑 포함)
├── marketplace/    # 마켓플레이스
├── revendedor/     # 재판매자 포털
├── session/        # 세션 보안 (중복로그인 차단, 디바이스/IP 감지)
└── chat/           # AI 채팅 (Knowledge base)
```

### 프론트엔드 페이지 구조
```
ventago-app/src/pages/
├── nueva-venta/    # POS 판매 화면
├── ventas/         # 판매 내역
├── productos/      # 상품 관리
├── precios/        # 가격 관리
├── gastos/         # 비용 관리
├── caja/           # 금전함
├── caja-fuerte/    # 금고
├── control-de-caja/# 금전함 통제
├── sucursales/     # 지점 관리
│   └── [id]/impresora  # 에이전트(프린터) 관리 페이지
├── usuarios/       # 사용자 관리
├── talleres/       # 외주 관리
├── dashboards/     # 대시보드
├── reportes/       # 보고서
├── configuracion/  # 설정
├── herramientas/   # 도구 (다운로드 페이지)
└── admin/          # 관리자 (매장, 앱, 구독 등)
```

---

## 레이아웃 구조

### 사이드바
- `ventago-app/src/layouts/UserLayout.tsx` — 메인 레이아웃 진입점
- `ventago-app/src/@core/layouts/VerticalLayout.tsx` — 레이아웃 프레임
- `ventago-app/src/@core/layouts/components/vertical/navigation/index.tsx` — 네비게이션 (React.memo 적용)
- `ventago-app/src/layouts/components/vertical/SidebarFooter.tsx` — 사이드바 하단 (로고/매장명 + 시계)

### 사이드바 리렌더링 방지 (적용됨)
- `Navigation` 컴포넌트: `React.memo` 적용, `darkTheme`을 `useMemo`로 메모이제이션
- `UserLayout`: `navMenuBranding`, `navMenuAfterContent`, `appBarContent` 등을 `useCallback`/`useMemo`로 추출
- `VerticalLayout`: `{...props}` 스프레드 제거하고 명시적 props 전달

---

## 개발 환경

### 로컬 실행
```bash
# 전체 (백엔드 + 프론트 + print-agent + zebra-agent)
./dev.sh

# 개별 실행
npm run dev:api    # api-ventago
npm run dev:app    # ventago-app
npm run dev:print  # print-agent
npm run dev:zebra  # zebra-agent
```

### Push (전체 서브모듈 + 에이전트 빌드)
```bash
./push-both.sh
# api-ventago + ventago-app push
# print-agent / zebra-agent 변경 감지 → 태그 자동 증가 → CI 빌드 트리거
```

### Docker (운영서버)
```bash
# 백엔드
cd api-ventago && docker compose up -d

# 프론트엔드
cd ventago-app && docker compose build && docker compose up -d
```

### DB 접속
```bash
# 로컬 (Mac Homebrew PG18)
psql -p 5432 -d ventago -c 'SQL HERE'

# 운영 (srv803182 호스트 PG18 클러스터 ventago18)
ssh jhkim-server "sudo -u postgres psql -p 5434 -d ventago -c 'SQL HERE'"
```

---

## ESLint 규칙 (빌드 에러 방지)

이 프로젝트의 ESLint는 Warning도 에러로 처리되어 빌드를 막음.

| 규칙 | 대처 |
|------|------|
| `newline-before-return` | `return` 문 바로 위에 빈 줄 필요 |
| `lines-around-comment` | 주석(`//`) 바로 위에 빈 줄 필요 |
| `no-unused-vars` | import한 변수는 반드시 사용 |
| `react-hooks/exhaustive-deps` | Warning이므로 빌드는 통과하나 주의 필요 |

---

## npm workspaces 주의사항

모노레포(npm workspaces) 구조 때문에 패키지가 루트 `node_modules/`로 호이스팅됨.
- `next.config.js`에서 webpack alias 설정 시 `./node_modules/...` 하드코딩 금지
- **올바른 방법:** `path.dirname(require.resolve('패키지명/package.json'))` 사용
- 예: `apexcharts` alias → `apexcharts-clevision`으로 매핑 (차트 라이브러리)

---

## 배포 파이프라인

- **Jenkins** 빌드: `front-coolsistema` job (프론트), `api-coolsistema` job (백엔드)
- **GitHub Actions**: `build-print-agent.yml`, `build-zebra-agent.yml` — 태그 push 시 Windows/macOS 빌드
- 빌드 실패 시 로그 파일(`#NNN.txt`)을 분석해 에러 수정 후 push
- 프론트 빌드: `docker compose build` → `npm run build` (Next.js)
- 백엔드: NestJS SWC 빌드

---

## 성능 최적화 규약

### 300ms 타겟
모든 사이드바 메뉴 클릭 → 콘텐츠 렌더 완료까지 P95 ≤ 300ms.

### 프론트엔드 규약
- **코드 스플리팅 필수**: 새 페이지 추가 시 `next/dynamic(() => import('src/views/...'), { ssr: false })` 사용
- **SWR 캐시 사용**: 참조 데이터(sizes, colors, categories, price-types, seasons, origins, suppliers 등)는 `src/hooks/api/` SWR 훅 사용. 5분 dedup.
- **useEffect+apiConnector.get 금지 (참조 데이터)**: SWR 훅으로 교체 필수
- **순차 API 호출 금지**: 여러 API를 호출해야 하면 `Promise.all()` 사용
- **Context value 메모이제이션**: Provider value는 반드시 `useMemo`로 감싸기
- **React.memo**: 고트래픽 리스트 컴포넌트(ProductsList, SalesListView)에 적용
- **next/Image**: 이미지는 `<img>` 대신 `next/Image` 사용
- **Pagination**: pageSize 최대 50 (500 금지)
- **AG Grid 초기화**: `ensureAgGridInit()` (`src/components/table/ag-grid-init.ts`) 1회만 호출
- **표 밀도 (Phase 79)**: 행 높이는 `src/components/table/table-density.ts` 의 `TABLE_ROW_HEIGHT`(30px) 하나로 정한다.
  화면에서 `rowHeight` 를 직접 지정하지 않는다 — `FullTable` 기본값이 이 상수를 읽으므로 **아무것도 안 하면 맞는다.**
  AG Grid 를 직접 쓰거나(`AgGridReact`) 다른 표 라이브러리(react-arborist 등)를 쓰면 **상수를 import 해서** 넘긴다.
  MUI `<Table>` 계열은 `src/@core/theme/overrides/table.ts` 의 `MuiTableBody` 패딩이 같은 30px 를 만든다 —
  두 파일은 **같은 목표값을 공유하므로 한쪽만 바꾸면 갈라진다.**
  예외를 두어야 하면 그 자리에 **왜 다른지 주석 필수**(헤더 높이는 별개 — POS 목록은 30, 공용 기본값은 48).
  ★ 30px 행에서 액션 열의 기본 `IconButton`(40px)은 넘친다 — `FullTable` 이 셀 안 버튼을 압축하므로
  FullTable 밖에서 표를 만들 때만 `size="small"` + 20px 아이콘(=정확히 30px)을 쓸 것.

### 백엔드 규약
- **인메모리 캐시**: 참조 데이터 60초, 대시보드 30초 TTL. `MemoryCacheService` 사용
- **PostgreSQL pool**: 현재 설정 min=2, max=20 — **워커당** (api-ventago/src/database/database.module.ts, 2026-07-25 조정). PM2 4워커 기준 앱 전체 상한 = 4×20 = 80 클라이언트로 pgbouncer ventago pool_size=50 과 균형. 변경 시 pgbouncer pool_size + PG max_connections(200) 영향 검토 필수. 쿼리 효율로 우선 해결.
- **slow query**: 100ms 이상 쿼리는 즉시 최적화

### 쓰기 경로 규약 (Phase 64) ★
- **단일 트랜잭션 원칙**: 하나의 업무 동작(판매·취소·보류·생산 완료)이 만드는 모든 행은 하나의 트랜잭션에서 커밋한다. 여러 모델을 순차 호출하면서 `transaction` 인자를 빠뜨리면 그 문장만 별도 커넥션에서 커밋돼 **부분 저장**이 된다(Phase 64 결함 2·3·4의 원인). 헬퍼 함수는 `transaction` 을 **선택이 아닌 필수 인자**로 받아 누락을 컴파일 타임에 막는다.
- **`stocks` 는 append-only 원장**: 행을 UPDATE/DELETE 하지 않는다(`trg_stocks_immutable` 이 DB 에서 강제). 잘못된 이동은 **반대 부호 보정 행**으로 상쇄한다 — 잔액은 `trg_stock_balances_apply` 가 같은 트랜잭션에서 `stock_balances` 에 반영하므로 애플리케이션이 따로 맞출 캐시는 없다. 조회·기록은 항상 `product_branch_id` 기준 — **`product_id` 컬럼은 존재하지 않는다**(이 착각이 생산 완료 경로를 통째로 무력화시켰다).
- **재고 읽기는 `stock_balances`/뷰만 본다**: `products.stock` 은 Phase 70-06 에서 강등됐다(`trg_stocks_sync_product_cache` 폐기 — 마드레 부모행 잠금 제거). 컬럼은 롤백 여지로 남겨뒀을 뿐 **신규 읽기·쓰기 경로에서 참조 금지**. 지점별은 `stock_balances`, 전 지점 합은 `getAvailableByProduct()`. 대조 불변식은 `v_stock_balance_drift`(0행) / `v_stock_tenant_leak`(0행).
- **트랜잭션 안 외부 I/O 금지**: HTTP·프린터·소켓 호출은 커밋 후에 한다(커넥션 장기 점유 = pool 고갈). 반드시 일어나야 하는 후속 작업은 같은 트랜잭션에서 `sync_outbox` 에 INSERT 하고 워커가 집행한다.
- **커밋 후 = 성공**: 커밋 이후 단계(ledger·프린터·재조회)의 실패는 응답 코드를 바꾸지 않는다. 여기서 throw 하면 클라이언트가 재시도해 **같은 판매를 복제**한다. 판매 생성은 `Idempotency-Key` 헤더(선택)로 요청 단위 멱등을 지원한다.
- **경합 방어는 설정을 존중한다**: 재고 초과 판매 차단은 `store_configs.allowSaleWithoutStock` 이 `false` 인 매장에만 적용한다. 허용 매장은 음수 재고가 **의도된 동작**이므로 차단을 걸면 회귀다.
- **락 순서 고정**: 여러 상품 행을 잠그는 경로(판매·취소·생산)는 전부 `productId` 오름차순으로 잠근다. 순서가 다르면 교착이 난다.

### Docker 규약
- 멀티스테이지 빌드 필수 (builder → runner)
- 프론트: `npm start` (production), 백엔드: `node dist/main`
- volume mount `.:/app` 사용 금지 (dev 전용)

---

## SWR 훅 목록 (`src/hooks/api/`)

| 훅 | 엔드포인트 | 사용처 |
|---|---|---|
| `usePriceTypes` | `/price-types` | ProductsView, BasicDataCard |
| `useCategoriesByStore` | `/categories/by-store` | ProductsView, BasicDataCard |
| `useSizesByStore` | `/sizes/by-store` | ProductsView |
| `useColorsByStore` | `/colors/by-store` | ProductsView |
| `useSubcategoriesByStore` | `/subcategories/by-store` | ProductsView |
| `useSeasonsByStore` | `/seasons/by-store` | BasicDataCard |
| `useOriginsByStore` | `/origins/by-store` | BasicDataCard |
| `useSuppliersByStore` | `/suppliers/by-store` | BasicDataCard |
| `useBranchByStore` | `/branch/store/{storeId}` | SelectorBranch |
| `useTalleresEtapas` | `/talleres/etapas/all` | Talleres 5개 탭 |
| `useTalleresVendors` | `/talleres/vendors/all` | Talleres 3개 탭 |
| `useTalleresEnvios` | `/talleres/envios/all` | Talleres 3개 탭 |

---

## 최근 주요 개발 이력

| 날짜 | 작업 내용 |
|------|-----------|
| 2026-03-31 | 매장 로고 업로드 기능 (MinIO 저장, 사이드바 하단 표시) |
| 2026-03-31 | 사이드바 리렌더링 방지 (React.memo/useMemo) |
| 2026-03-31 | 세션 보안 시스템: 중복 로그인 차단, 디바이스/IP 감지 |
| 2026-04-15 | **[Phase 1 성능 최적화]** bundle-analyzer, route timing, Web Vitals, SWR 캐시, 코드 스플리팅, next/font, 스켈레톤 |
| 2026-04-16 | **[Phase 2 SWR 마이그레이션]** ProductsView, BasicDataCard, Talleres 5탭, useBranch, useSellers, useClients → SWR 전환 |
| 2026-04-16 | **[Phase 2 성능 추가]** swcMinify, tree-shaking, React.memo, next/Image, pageSize 500→50, AuthContext↔BranchContext 분리 |
| 2026-04-16 | **[Phase 13 Zebra Agent]** branch_agents 테이블, BranchAgent 모델/서비스/게이트웨이/컨트롤러 |
| 2026-04-16 | **[Phase 13]** zebra-agent Electron 앱 (ZPL, TCP 9100, USB, 3종 라벨, 프린터 탐색, 상품 선택/출력) |
| 2026-04-16 | **[Phase 13]** 프론트엔드: 다중 에이전트 관리 UI, 터미널-에이전트 매핑, "Imprimir x ZPL" 버튼 |
| 2026-04-16 | **[Phase 13]** print-agent: 다크 테마, USB 지원, 서버 URL 고정, agent_info 매장/지점 표시 |
| 2026-04-16 | **[Phase 13]** CI: build-zebra-agent.yml, push-both.sh 통합, dev.sh 통합 |

---

## 주의 사항
- front-end의 lint 오류에 특히 주의할 것
- `apiConnector.remove()` 사용 (`.delete()` 아님)
- **DB 마이그레이션은 기능 추가 시 로컬(Mac PG18:5432)과 운영(PG18:5434)에 항상 동시 적용** — 아래 「DB 마이그레이션 적용 규칙」 섹션 참조 (한쪽만 적용 금지)

---

## 디자인 규약 (auto-load skills)

신규 UI / 컴포넌트 / 페이지 작업 시 다음 skill 을 자동 참조:

- **Sketch findings (validated design decisions, theme, CSS patterns)** → `Skill("sketch-findings-ace-online")`
  - Theme: 다크 네이비 + 골드 + MP cyan + sandbox=warning gold
  - 영역별 reference: Configuración pages / Payment Modal QR / Sandbox indicator / Caja virtual wallet / Refund failure UX
  - MUI 5 컴포넌트와 1:1 매핑 가능한 클래스명 + React implementation sketches

---

## 운영 서버 직접 접근 규칙 (SSH / Postgres MCP)

`@aiondadotcom/mcp-ssh` MCP 를 통해 운영 서버(srv803182 / 62.72.7.245) 에 직접 SSH 접속 가능. 개발 속도를 위해 허용하되, 아래 규칙을 엄격 준수.

### Postgres 운영 DB 접근 (기본: Read-Only)

기본 허용 (사용자 확인 없이 실행 가능):
- `SELECT`, `SHOW`, `EXPLAIN`, `\d`, `\dt` 등 조회성 쿼리
- 성능 프로파일링 (pg_stat_*, pg_locks 조회)
- 스키마 검사 (information_schema 조회)

**반드시 사용자 확인 받고 실행 (destructive / 상태 변경 쿼리):**
- DDL: `CREATE`, `ALTER`, `DROP`, `TRUNCATE`
- DML 변경: `INSERT`, `UPDATE`, `DELETE`, `MERGE`, `UPSERT`
- 관리: `GRANT`, `REVOKE`, `VACUUM FULL`, `REINDEX`, `CLUSTER`
- 트랜잭션 제어: 사용자 의도가 분명한 수동 `BEGIN/COMMIT` 구조

### 실행 패턴

1. 조회성 쿼리 먼저 돌려 스키마/데이터 상태 파악
2. 변경성 SQL 은 생성 후 **SQL 내용 + 예상 영향 row 수** 사용자에게 보여주고 동의받기
3. 동의 후 실행 (가능하면 트랜잭션 + ROLLBACK 검증 후 COMMIT)
4. DDL 은 `api-ventago/migrations/` 에 SQL 파일 커밋 + 서버에서 실행 순서 유지

### SSH 명령 실행 규칙

- 조회 (`ls`, `cat`, `tail`, `docker logs`, `docker ps` 등) — 기본 허용
- 파일 쓰기 / 수정 (`echo >`, `sed -i`, `vim`) — 사용자 확인
- 서비스 제어 (`docker restart`, `docker stop`, `systemctl`) — 사용자 확인
- 파괴적 명령 (`rm`, `shutdown`, `kill`) — 명시적 사용자 지시 시에만

### 접속 정보 (참고)

- SSH host alias: `jhkim-server` (`~/.ssh/config`, IdentityFile: `~/.ssh/id_ed25519`)
- 운영 서버: srv803182 / 62.72.7.245
- **운영 Postgres 는 호스트 OS 에 설치** (Docker 아님) — PG18 클러스터 `ventago18` 포트 **5434**, 앱은 pgbouncer(5432) 경유
  - Docker 의 `postgresql-dbpostgres-1` (포트 54322) 은 별도 시스템(coolinvoice 등) — Ventago 아님
  - 구 PG10(5433) 은 롤백 안전망으로만 보존 — **조회·마이그레이션 모두 `-p 5434` 를 반드시 붙인다**
- 운영 DB 명: `ventago`, owner: `coolsistema`
- 접속 예 (조회):
  ```bash
  ssh jhkim-server "sudo -u postgres psql -p 5434 -d ventago -c 'SELECT id, name FROM stores ORDER BY id;'"
  ```
- 접속 예 (파일 실행, DDL 이므로 사용자 확인 필수):
  ```bash
  ssh jhkim-server "sudo -u postgres psql -p 5434 -d ventago -v ON_ERROR_STOP=1 --single-transaction" < api-ventago/migrations/<file>.sql
  ```
- 운영 매장: CART(3), coolsistema(6), genius(8), ACE(9)

---

## DB 마이그레이션 적용 규칙 (로컬 + 운영 동시) ★

**기능을 추가하면 마이그레이션은 항상 로컬과 운영에 동시 적용한다.** 한쪽만 적용하고 넘어가지 않는다.
한쪽만 적용해 dev-운영 스키마가 갈라지면 배포 후 500 (`relation does not exist` / `permission denied`) 사고로 이어진다 — shop-mvp·despacho·cheque·원단 이중단위 전례.

### 적용 대상 (2026-07-10 PG10→PG18 통일 컷오버 이후 현재값)
- **로컬** = Mac Homebrew **PostgreSQL 18**, 포트 **5432** (user: postgres / marcoskim). `postgres-ventago` MCP 가 이 로컬 PG 를 가리킴(운영 아님, read-only 조회용).
- **운영** = srv803182 호스트의 **PostgreSQL 18** 전용 클러스터 `ventago18`, 포트 **5434**. 앱은 pgbouncer(5432) → 5434 접속. (구 PG10 5433 은 롤백 안전망으로 당분간 보존하나 **신규 마이그레이션은 5434 에만** 적용.)

### 적용 방법
- **운영(5434)**: SSH → `sudo -u postgres psql -p 5434 -d ventago -v ON_ERROR_STOP=1 --single-transaction -f <file>.sql`.
  - **신규 테이블은 owner + 시퀀스를 coolsistema 로 반드시 이전** — 마이그레이션 SQL 끝에 role 존재체크 DO 블록으로 `ALTER TABLE/SEQUENCE ... OWNER TO coolsistema`. 누락 시 앱(coolsistema)이 permission denied 500. (`ALTER TABLE OWNER` 는 시퀀스 owner 를 안 옮기므로 `ALTER SEQUENCE ... OWNER` 별도 필수.)
- **로컬(5432)**: 이 클라우드 샌드박스는 Mac localhost DB 에 못 닿음 → 로컬 적용 SQL 명령을 사용자에게 전달해 Mac 에서 실행. 예: `psql -p 5432 -d ventago -f api-ventago/migrations/<file>.sql`. coolsistema role 이 로컬에 없으면 owner DO 블록은 자동 skip(무해).
- 적용 후 **양쪽 스키마 대조**로 확인. DDL SQL 파일은 `api-ventago/migrations/` 에 커밋.

### PG 버전 문법
- 이제 로컬·운영 모두 PG18 → 과거 PG10 제약(`GENERATED AS IDENTITY` 금지 등) 불필요. 기존 SQL 의 SERIAL 유지도 무방.

---

## 상시 규칙: push 와 마이그레이션은 Claude 가 직접 (2026-07-29) ★

- **push 까지 Claude 가 직접 수행한다.** 코드 수정 후 사용자에게 "push 해달라"고 넘기지 않는다. 변경 파일만 선별 스테이징(다른 WIP 오염 금지) → commit → `git push origin main` → Jenkins 자동 빌드까지 확인. `.git/index.lock` 이 막으면 `mv` 로 치운 후 진행.
- **push 후 빌드 결과를 반드시 확인한다.** Jenkins `lastFailedBuild` 가 이번 빌드면 로그(`/var/lib/jenkins/jobs/<job>/builds/<n>/log`)를 보고 즉시 수정 → 재push. "push 완료"는 빌드 성공 + 운영 컨테이너 재생성 확인까지를 의미한다.
- **DB 마이그레이션도 Claude 가 직접 실행한다.** 절차는 「DB 마이그레이션 적용 규칙 › 적용 방법」을 그대로 따른다. 양쪽(로컬 5432 + 운영 5434) 적용 확인 전에는 작업을 완료로 표시하지 않는다.
- 여전히 사용자 확인이 필요한 것: 운영 DML/DDL 실행 전 SQL+영향 row 승인, 서비스 재시작, 파괴적 명령. (승인 후 실행은 Claude 가 직접.)

---

## 개발 워크플로우: 로컬에서 개발 + push (2026-07-23 확정) ★

- 이 프로젝트 개발은 **사용자 컴퓨터(Mac)에서 로컬로 진행하고 GitHub 에 push** 하는 방식으로 한다. (클라우드 Cowork 세션에서 원격으로 하지 않는다.)
- 이유: 클라우드 세션은 Mac 파일에 "브리지"로 접속하는데, 이 브리지가 자주 끊기고(`not connected to the bridge`), `.git/index.lock` 제거 불가·커밋/스테이징 오류가 반복돼 작업이 막힌다. 로컬 실행이면 브리지가 없어 이 문제가 사라진다.
- 전환 방법(데스크톱 앱): 새 Cowork 작업 시작 시 우상단 **"Run this task"** 선택에서 **"On your computer"** 선택. 기본값은 Settings → Cowork 의 "Run new tasks in the cloud" 토글로 변경. (이 옵션은 데스크톱 앱 전용 — 웹/모바일에는 없음.)
- 배포 경로는 동일: 로컬에서 수정 → commit/push origin main → Jenkins 웹훅(api-new-coolsistema / front-coolsistema) → docker compose build && up.
- 주의: superadmin 앱(ventago-admin-app)의 Clientes 기능(소프트삭제·세션필터·할인·대시보드 카드 등)은 한동안 **워킹트리에만 있고 커밋 안 된 상태**였다 → 로컬 전환 후 commit/push 로 반드시 저장.

---

## cmux 진행 상황 표시 (장시간 작업 시)

```bash
cmux set-status build Running --icon bolt
cmux set-progress 0.5 --label "Migrating..."
cmux log "마이그레이션 완료" --level info
cmux notify --title "작업 완료" --body "리뷰 부탁드립니다"
```