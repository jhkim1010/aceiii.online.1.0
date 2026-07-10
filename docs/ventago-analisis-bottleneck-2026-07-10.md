# ventago DB 병목 + 프론트엔드 리렌더 분석 리포트 (2026-07-10, 로컬 환경)

분석 대상: 로컬 Mac PG 18.3 `ventago` DB (165 테이블, FK 305개, 인덱스 442개) + `api-ventago` 마지막 로그(combined-2026-07-09) + `ventago-app` 레이아웃/사이드바 소스.

---

## 1층 — 표면 문제 (로그와 실측에서 보이는 것)

### 1-1. 쿼리별 적정 실행시간 기준

| 쿼리 유형 | 적정 기준 | 현재 로거 기준과의 관계 |
|---|---|---|
| POS 단건 조회/쓰기 (PK, 인덱스 lookup) | **< 10ms** | — |
| 목록/검색 (페이지네이션 포함) | **< 100ms** | SlowQuery `warn` 기준과 일치 |
| 집계 리포트 | **< 500ms** | SlowQuery 🔴 기준과 일치 |
| 배치/백필/마이그레이션 | < 5s | — |
| 절대 상한 (안전밸브) | **statement_timeout 30s** | 현재 **0(무제한)** — 미설정 ★ |

로컬은 데이터가 소량(sales 101행, products 483행, stocks 961행)이므로 **사실상 모든 쿼리가 10ms 미만이어야 정상**입니다. 그 이상 걸리면 쿼리 자체가 아니라 락·구조 문제입니다.

### 1-2. 기준 초과 지점 (마지막 로그 combined-2026-07-09 실측)

| 시각 | 쿼리 | 실행시간 | 기준 대비 |
|---|---|---|---|
| 16:52:26~16:58:49 | `sync_outbox` SELECT ×5 | **11.4s / 83.9s / 86.8s / 87.7s / 157.4s** | 🔴 1,574배 초과 |
| 16:50:55 | information_schema (sync introspection) | 3.9s | 🔴 |
| 16:50:55 | `user_functions` ALTER | 2.9s | (DDL) |
| 16:50:55 | `sales` COUNT (daily_number 백필 체크) | 1.2s | 🔴 매 부팅 실행 |
| 16:50:55 | `knowledge_documents` 전량 SELECT | 836ms | 🔴 content 대용량 컬럼 포함 |

---

## 2층 — 구조적 원인

### 2-1. ★ sync_outbox 157초의 진범 = 쿼리가 아니라 "부팅 DDL 폭풍의 락 대기"

결정적 증거 3가지:

1. **로컬 `sync_outbox` 테이블은 현재 0행(빈 테이블)** 인데 SELECT가 157초 걸렸습니다.
2. 지금 동일 쿼리를 EXPLAIN ANALYZE로 실측하면 **0.08ms** (sync_outbox_due_idx 정상 사용).
3. 로그 타임라인: 16:50분에 **1,525줄의 DDL 폭풍**(ALTER TABLE / ADD FOREIGN KEY / DROP CONSTRAINT 연쇄 — `sequelize.sync()` 부팅 introspection + FK 재적용)이 지나간 직후부터 outbox SELECT가 연쇄로 83~157초 블로킹. 그동안 pool은 `size=2 using=1 waiting=0` — **pool 고갈이 아니라 PG 서버 쪽 락 대기**입니다.

즉, `SyncService.onModuleInit()`의 `sequelize.sync()`가 ALTER/ADD FK로 ACCESS EXCLUSIVE 락을 잡는 동안, Outbox cron이 이미 돌기 시작해 SELECT가 락 뒤에 줄을 서고, tick은 "이전 tick 실행 중"으로 계속 스킵된 것입니다. **쿼리 튜닝으로는 못 고치고, 부팅 순서/락 타임아웃으로 고쳐야 합니다.**

### 2-2. 운영 규모에서 폭발할 인덱스 누락 (로컬에선 증상 없음)

FK 컬럼인데 인덱스가 없는 핵심 지점 — 지금은 수백 행이라 seq scan도 1ms지만, 운영에서 수십만 행이 되면 조회마다 수백 ms로 직행합니다:

| 테이블 | 무인덱스 FK 컬럼 | 위험도 |
|---|---|---|
| **sale_items** | **sale_id, product_id** | ★★★ 판매 상세 조회의 핵심 경로 — 매 판매 조회마다 전체 스캔 |
| **prices** | **product_id, price_type_id** | ★★★ 가격 조회 조인 필수 경로 |
| **sales** | client_id, user_id, seller_id | ★★ 고객별/판매원별 조회 |
| store_clients | store_id | ★★ |
| global_clients | province_id, created_by_store_id | ★ |
| products | category_id, supplier_id, color_id, size_id, season_id, parent_id, origin_id | ★★ 필터 검색 |
| users | store_id, branch_id | ★ |
| role_functions | branch_id, function_id | ★ 권한 로딩 |

추가 발견:
- **중복 인덱스**: `products_sku_store_id` ≡ `uq_products_sku_store` (동일 정의 2개) — 하나 제거로 쓰기 오버헤드 절감.
- **ANALYZE 미실행**: 전 테이블 `n_live_tup=0` — 로컬 플래너가 통계 없이 동작 중. `vacuumdb --analyze-only -d ventago` 1회 실행 필요.
- FK가 테이블당 2개씩 잡힌 것들(sales→branches 등)은 서로 다른 컬럼(origin/target)이라 **정상**임을 확인했습니다.

### 2-3. Pool 낭비 지점 (선호 원칙 관련)

- `pool.min: 10` — 유휴 시에도 인스턴스당 커넥션 10개 상시 점유. 트래픽 10명 규모에서는 **min 2~3이면 충분**하고, 로그상 실사용은 `using=1`입니다.
- `pool.max: 80` + 코드 주석 "PG max_connections=300" — 실측 **100**입니다(로컬·운영 동일). 2인스턴스 복귀 시 160>100 초과 위험(기존 메모리의 잠복위험 A 재확인).

### 2-4. 프론트엔드 — 깜빡임/불필요 리렌더 지점

말씀하신 "사이드바가 이유 없이 다시 그려진다"와 "화면 깜빡임"의 실체를 소스에서 확인했습니다:

**⓪ 라우트 전환 스켈레톤 즉시 교체 (화면 깜빡임의 주범)**
`_app.tsx` — `routeChangeStart` 즉시 현재 페이지를 언마운트하고 `PageTransitionSkeleton`으로 교체합니다. 100~300ms짜리 빠른 전환에서도 무조건 `컨텐츠→스켈레톤→컨텐츠` 2회 화면 교체 = 깜빡임. NProgress 바와 로딩 표시도 이중입니다. → 200ms 지연 스켈레톤 패턴으로 해결 (상세는 Phase 55 SPEC).

**① SidebarFooter의 1초 시계 (가장 큰 낭비, 확정)**
`SidebarFooter.tsx:42` — `setInterval(() => setNow(DateTime.now()), 1000)`. **매초** 풋터 전체(매장 로고, 지점 배지, 유저 정보, Tooltip, 그리고 마운트된 모달 3개: SelectBoxTerminalModal / ModalCashRegister / BranchSwitchModal)가 리렌더됩니다. 모달의 `onClose={() => ...}` 인라인 함수도 매초 새로 생성되어 닫혀 있는 모달까지 매초 다시 그립니다. 아무 조작 없이도 앱이 초당 1회 사이드바 하단을 다시 그리는 중입니다.

**② VerticalNavGroup의 라우트 변경 연쇄 setState**
`VerticalNavGroup.tsx:130~145` — `useEffect([router.asPath])`가 **그룹마다** 무조건 `setGroupActive([...groupActive])` + `setCurrentActiveGroup([...])`을 호출합니다. 내용이 같아도 새 배열 참조라 부모(Navigation) state가 바뀌고, **그룹 수만큼(≈6회) 전체 nav 트리 리렌더가 연쇄**됩니다. 페이지 한 번 이동에 사이드바가 6번+ 다시 그려지는 구조입니다.

**③ VerticalLayout의 toggleNavVisibility 비메모이즈 → memo(Navigation) 무력화**
`VerticalLayout.tsx:90` — `const toggleNavVisibility = () => setNavVisible(!navVisible)` 이 매 렌더 새 함수라서 `Navigation`의 `memo()`가 항상 깨집니다. 라우트 전환 시 `_app`의 `isRouteChanging`이 true→false로 2번 토글되고, UserLayout의 state(모달, occupiedTerminals 등)가 바뀔 때마다 사이드바 전체가 따라 그려집니다.

보조 지점: Navigation의 `navMenuContentProps = {...props, ...}` 매 렌더 새 객체 → afterContent(SidebarFooter) 재호출 / `darkTheme = useMemo([settings])` — settings 객체 identity 변경마다 `createTheme` 재실행(비용 큼) / UserLayout 122행 `settings.layout = 'vertical'` 직접 변이(안티패턴) / `branchOptions` 매 렌더 새 배열.

---

## 3층 — 근본 본질

세 문제는 뿌리가 같습니다: **"작을 때는 공짜였던 것들이 규모에 비례해 비용을 청구한다."**

- DB: 로컬 수백 행에서는 인덱스 없는 seq scan도, 부팅 DDL도 티가 안 납니다. 병목의 본질은 Little's Law — 대기열 길이 = 도착률 × 체류시간. 157초짜리 체류시간 하나가 pool 전체를 인질로 잡습니다. 커넥션 수를 늘리는 건 해법이 아니고, **체류시간(느린 쿼리·락 대기)을 죽이는 것**이 해법입니다.
- 프론트: React의 본질은 "참조가 바뀌면 다시 그린다"입니다. 매초 새 Date, 매 렌더 새 배열/함수/객체 — 값은 같아도 참조가 바뀌면 React에게는 전부 "변경"입니다. 최적화의 본질은 memo 남발이 아니라 **참조 안정성(referential stability)의 규율**입니다.
- 그리고 관측 없이는 둘 다 못 잡습니다. 이번에도 SlowQuery 로거가 있었기에 157초를 발견했습니다(pg_stat_statements는 여전히 미설치).

---

## 지금 당장 실행할 단계별 액션 플랜

**Step 1 — 안전밸브 (5분, 로컬 즉시 / 운영은 점검창)**
```sql
ALTER DATABASE ventago SET statement_timeout = '30s';
ALTER DATABASE ventago SET lock_timeout = '10s';
ALTER DATABASE ventago SET idle_in_transaction_session_timeout = '60s';
```
lock_timeout 10s가 있었다면 157초 사건은 10초 만에 에러로 드러나 즉시 원인을 알 수 있었습니다.

**Step 2 — 부팅 순서 수정 (30분)**: Outbox cron 첫 tick을 `SyncService.onModuleInit()` 완료 후로 지연(앱 부트스트랩 완료 이벤트 또는 초기 지연 60s). + `backfillDailyNumbers`의 COUNT는 완료 후 플래그(테이블/설정값)로 스킵.

**Step 3 — 로컬 통계 + 인덱스 (10분)**
```bash
vacuumdb --analyze-only -d ventago -p 5433   # 로컬 포트에 맞게
```
```sql
-- 핵심 4개부터 (로컬 검증 후 운영은 CONCURRENTLY + 점검창)
CREATE INDEX idx_sale_items_sale_id    ON sale_items (sale_id);
CREATE INDEX idx_sale_items_product_id ON sale_items (product_id);
CREATE INDEX idx_prices_product_id     ON prices (product_id, price_type_id);
CREATE INDEX idx_sales_client_id       ON sales (client_id) WHERE client_id IS NOT NULL;
-- 2차: sales(user_id), sales(seller_id), store_clients(store_id), users(store_id, branch_id)
DROP INDEX products_sku_store_id;  -- uq_products_sku_store 와 중복
```

**Step 4 — pool 재조정 (5분)**: `min: 10 → 2`, max=80 유지하되 주석의 "PG 300"을 "100"으로 수정. 2인스턴스 복귀 전 재배분 필수(기존 메모리 위험 A).

**Step 5 — 사이드바 리렌더 3종 수정 (반나절, GSD 1 Wave 권장)**
1. `SidebarClock` 컴포넌트로 시계 분리(시계만 매초 리렌더) + 모달 3개를 `open && <Modal/>` 조건부 마운트로 전환.
2. `VerticalNavGroup` effect에 가드: 멤버십이 실제로 바뀔 때만 setState.
3. `VerticalLayout`의 `toggleNavVisibility`를 `useCallback`으로 고정 → `memo(Navigation)` 부활. + `settings.layout` 직접 변이 제거.

**Step 6 — 검증**: React DevTools Profiler로 (a) 유휴 상태 1분간 사이드바 리렌더 횟수 = 시계 컴포넌트만, (b) 라우트 전환 1회당 nav 트리 리렌더 ≤ 2회 확인. DB는 다음 부팅 로그에서 SlowQuery 🔴 소멸 확인.

---

## 빠지기 쉬운 함정 3가지

1. **"로컬에서 빠르니 나중에"** — 인덱스 누락은 로컬에서 영원히 증상이 없습니다. 운영 데이터가 임계점을 넘는 날 갑자기 페이지 전체가 느려지고, 그날은 이미 고객이 보고 있는 날입니다.
2. **운영 인덱스를 그냥 CREATE INDEX로** — 락으로 서비스가 멈춥니다. 반드시 `CREATE INDEX CONCURRENTLY` + 새 객체는 `ALTER ... OWNER TO coolsistema`(기존 교훈: owner 누락 시 500).
3. **memo/useCallback 남발로 대응** — 리렌더 최적화를 전부 memo로 덮으면 deps 하나 어긋날 때 stale UI 버그가 됩니다. 순서는 ① 원인(시계·연쇄 setState) 제거 → ② 참조 안정화 → ③ 그래도 남으면 memo. 특히 `settings.layout` 직접 변이를 남겨둔 채 memo를 늘리면 화면이 안 갱신되는 역방향 버그가 납니다.

---

## 점검 포인트

- **1주 후**: 부팅 로그에서 sync_outbox 🔴 소멸 + tick 스킵 반복 소멸 확인. 로컬 인덱스 4종 적용 + EXPLAIN 재확인. Profiler로 사이드바 유휴 리렌더 0 확인.
- **1개월 후**: 운영(PG18:5434)에 CONCURRENTLY 인덱스 적용 + pg_stat_statements 설치(점검창, 관측 제안서 Phase0-1 겸행). SlowQuery warn 건수 주간 추이 비교.
- **3개월 후**: k6 부하(100/500 VU)에서 p95 응답 확인 — 목록 <100ms, 리포트 <500ms 기준 충족 여부. pool min=2 축소 후 cold start 이슈 없는지 확인.

---

*근거 데이터: 로컬 PG 18.3 실측 (pg_stat_user_tables, pg_indexes, pg_constraint, EXPLAIN ANALYZE), api-ventago/logs/combined-2026-07-09.log, ventago-app 소스 9개 파일 정독.*
