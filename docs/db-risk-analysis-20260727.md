# Ventago 운영 DB 위험 분석 리포트 (2026-07-27)

대상: 운영 PG18 `ventago` (srv803182:5434, read-only 진단). 현재 28MB / sales 98건 — **초기 단계이므로 "지금 느린 것"이 아니라 "데이터가 쌓이면 터질 구조"를 찾는 데 집중**함.
※ 업로드된 dump 파일은 0바이트(업로드 실패)였고, 서버의 실제 백업(1.3MB)은 무결성 검증 통과 상태였음.

---

## 1. 다층 분석

### 표면 문제 (이미 관측된 증상)
- `daily_number` 중복 **이미 5건 발생**: store 6 (2026-07-07 ×2, 07-22), store 9 (05-19, 06-01)
- `products.stock` ↔ `stocks` 원장 불일치 다수: 예) id 27 "CAMPERA rojo/36" → product_stock **-1** vs 원장합 **+10**
- `active_sessions` 조회 227회 전부 seq scan (인덱스 0회 사용)
- FK 인덱스 누락 **179건** (전 스키마)

### 구조적 원인
1. **채번이 read-then-write**: `SELECT daily_number ... WHERE DATE(sale_date AT TIME ZONE tz) = 오늘` 후 MAX+1 방식 → 두 터미널 동시 결제 시 같은 번호 발급(중복 5건의 원인). 게다가 `DATE()` 감싼 조건은 인덱스를 못 타는(non-sargable) 형태 — 판매 2만 건이면 매 결제마다 풀스캔.
2. **재고가 절대값 덮어쓰기**: `UPDATE products SET stock=$1` (24,305회 관측) — 읽고-계산해서-덮어쓰는 패턴이라 동시 판매 시 한쪽 갱신이 유실됨(lost update). 원장(stocks)과 캐시(products.stock)가 갈라진 이유.
3. **세션 유일성이 앱 로직에만 의존**: `active_sessions`에 UNIQUE(user_id)가 실제로는 없음(설계 문서와 불일치). 동시 로그인 race 시 세션 2개 생성 가능 + user_id 인덱스 부재로 로그인마다 seq scan.
4. **복구 지점(RPO)이 24시간**: 백업은 일 1회 dump뿐, `archive_mode=off` → 디스크 장애 시 최대 하루치 판매 데이터 소실.
5. **안전벨트 미착용**: `statement_timeout=0`, `idle_in_transaction_session_timeout=0` → 트랜잭션 하나가 pgbouncer server pool(ventago pool_size=50)을 무기한 점유 가능. `log_min_duration_statement=-1` → PG 레벨 slow query 감지 없음.

### 근본 본질
동시성 제어를 **DB 제약이 아닌 애플리케이션 코드에 맡긴 구조**. 터미널 1~2대일 때는 코드 순서가 곧 직렬화라 문제가 안 보이지만, 다지점·다터미널·3,000터미널 목표(Phase 63)에서는 "DB가 강제하지 않는 규칙은 반드시 깨진다". 이미 5건의 중복과 재고 드리프트가 그 증거. 해법의 방향은 하나 — 유일성·정합성·순번은 DB가 원자적으로 보장하게 옮기는 것.

---

## 2. 발견 사항 상세

### A. 충돌/데이터 정합성 (증거 있음 — 최우선)

| # | 문제 | 증거 | 수정안 |
|---|------|------|--------|
| A1 | daily_number 중복 | 5건 실재 | **counter 테이블 채번**: `daily_counters(store_id, branch_id, day, last_number)` + `INSERT ... ON CONFLICT DO UPDATE SET last_number=last_number+1 RETURNING` — 원자적, O(1), race 불가. MAX+1 쿼리 자체가 사라져 non-sargable 문제도 함께 해결 |
| A2 | products.stock 드리프트 | -1 vs +10 등 다수 | ① 코드에서 `stock = stock ± delta` 상대 증감으로 변경(원자적) ② 야간 재계산 잡: 원장합으로 products.stock 보정 ③ 판매 차단은 하지 않음(음수 재고 허용 정책 유지) |
| A3 | active_sessions UNIQUE(user_id) 부재 | 스키마 확인 | `CREATE UNIQUE INDEX` (현재 중복 0건이라 즉시 적용 가능) — 중복 로그인 차단을 DB가 최종 보장 |

### B. 300ms 지연 예상 경로 (성장 시 악화)

| # | 경로 | 현재 | 성장 시 | 수정안 |
|---|------|------|---------|--------|
| B1 | 채번 쿼리 (결제마다 실행, 20,889회 관측) | 0.3ms | sales 수십만 건이면 수백 ms — **결제 전체를 블로킹** | A1로 근본 해결 |
| B2 | FK 인덱스 누락 179건 | 무증상 | JOIN·CASCADE DELETE·상세조회 선형 악화 | 핫패스 ~30개만 선별 적용 (`migrations/2026-07-27-hot-fk-indexes.sql`) |
| B3 | active_sessions seq scan (모든 API 요청·로그인 경로) | 무증상 | 세션 수백 개 + 요청당 1회면 즉시 병목 | A3의 unique 인덱스가 겸용 |
| B4 | sale_payment_methods(sale_id) 인덱스 부재 | 감사쿼리 546ms 실측 | 환불·상세조회·정산 전반 | B2에 포함 |
| B5 | role_function_actions 조회 154,400회 (권한 체크) | 0.0ms | 호출량 자체가 문제 | MemoryCacheService 60s TTL 캐시 적용 (백엔드 규약대로) |

### C. 데이터 상실 위험

| # | 문제 | 수정안 |
|---|------|--------|
| C1 | RPO 24h (일 1회 dump, WAL 아카이브 없음) | 단기: dump를 **시간별**로 (1.3MB라 비용 무시 가능, cron `17 * * * *` + retention 조정). 중기: pgBackRest WAL 아카이빙 → RPO 분 단위 |
| C2 | 복원 리허설 없음 | 월 1회 임시 DB에 `pg_restore` 리허설 (백업은 복원해봐야 백업임) |
| C3 | timeout 미설정 → pool 고갈 = 서비스 정지 | `ALTER ROLE coolsistema SET statement_timeout='30s'` + `ALTER SYSTEM SET idle_in_transaction_session_timeout='60s'` (장기 작업용 role은 예외) |
| C4 | slow query 무감지 | `ALTER SYSTEM SET log_min_duration_statement=100` + reload — 100ms 규약과 일치 |

### D. 경미/정리 대상
- `_phase26_cat_map`: PK 없는 잔재 테이블 → 확인 후 DROP 권장
- pgbouncer: ventago `pool_size=50`, transaction mode — 현재 적정. 2호기 증설 시에도 server 측은 50으로 캡되므로 안전하나, `SHOW POOLS`의 `cl_waiting` 모니터링 항목에 추가할 것
- 시퀀스 고갈: 최대 last_value 23,886 (int4) — 수년간 무위험
- pg_stat_statements에 staging(k6 2만 건) 통계가 섞여 있음 — 클러스터 공유이므로 해석 시 주의

---

## 3. 지금 당장 실행할 단계별 액션 플랜

1. **[오늘, 승인 후 5분]** `api-ventago/migrations/2026-07-27-hot-fk-indexes.sql` 적용 — 로컬(5432) + 운영(5434) 동시. 28MB라 즉시 완료. A3·B2·B3·B4 해소.
2. **[오늘, 승인 후 2분]** C3·C4 설정 3종 (reload만, 재시작 불필요).
3. **[이번 주, GSD]** A1 채번 리팩터: `daily_counters` 테이블 + sales-create 서비스 수정 + **코드 배포 후** 향후분 unique 인덱스 활성화(마이그레이션 파일 하단 주석 참조 — 순서 엄수).
4. **[이번 주, GSD]** A2 재고 상대 증감 수정 + 야간 보정 잡 + 기존 드리프트 1회 백필.
5. **[다음 주]** C1 시간별 백업 전환 + C2 복원 리허설 1회 + B5 권한 캐시.

## 4. 빠지기 쉬운 함정 3가지

1. **unique 인덱스를 코드보다 먼저 넣는 것** — daily_number unique를 지금 걸면 MAX+1 race가 "중복 저장" 대신 "결제 실패(23505)"로 바뀐다. 반드시 counter 채번 코드 배포 → 그 다음 unique. (마이그레이션에 주석 처리해 둔 이유)
2. **179건 전부 인덱스 걸기** — 참조 테이블(sizes, seasons 등)까지 다 걸면 쓰기 비용·유지비만 증가. 핫패스 ~30개로 충분하고, 나머지는 idx_scan 통계를 보고 추가.
3. **statement_timeout 전역 일괄 적용** — legacy import, 캠페인 발송, 백업 같은 장기 작업이 끊긴다. role 단위(coolsistema 30s)로 걸고 장기작업은 세션에서 `SET LOCAL statement_timeout=0`.

## 5. 점검 포인트

**1주 후**: 신규 daily_number 중복 0건 확인 / pg_stat_statements에서 mean_exec_time>100ms 쿼리 목록 재확인 / active_sessions idx_scan > 0 확인.
```sql
SELECT store_id, sale_date::date, daily_number, count(*) FROM sales
WHERE sale_date >= now()-interval '7 days' AND daily_number IS NOT NULL
GROUP BY 1,2,3 HAVING count(*)>1;
```
**1개월 후**: stock 드리프트 0건 유지 확인(아래 쿼리) / 신규 인덱스 idx_scan 사용률 / 시간별 백업 파일 존재+크기 추이.
```sql
SELECT p.id, p.stock, COALESCE(sum(st.stock),0) ledger FROM products p
LEFT JOIN "ProductBranch" pb ON pb.product_id=p.id
LEFT JOIN stocks st ON st.product_branch_id=pb.id AND st.is_active
GROUP BY p.id, p.stock HAVING p.stock <> COALESCE(sum(st.stock),0);
```
**3개월 후**: DB 크기·테이블 성장률 / pgbouncer `cl_waiting` 피크 / staging k6 재실행으로 P95 ≤ 300ms 재검증 / pgBackRest 도입 여부 결정.

---

## 6. [추가] 타 AI 분석 교차 검증 (2026-07-27, 운영 DB 실측)

타 AI의 dump 기반 분석 9개 항목을 운영 DB에서 전수 실측 검증한 결과.

| # | 주장 | 판정 | 실측 근거 / 이 시스템에 맞는 결론 |
|---|------|------|--------------------------------|
| 1 | 재고 이력 합산이라 느려짐 → stock_balances 신설 + `quantity >= ?` 조건부 차감 | **절반만 채택** | 원장(stocks) 구조는 맞음(현재 pb당 최대 23행). 그러나 ①`products.stock`이 이미 잔액 캐시 역할 — 새 테이블 불필요, **원자적 상대 증감으로 고치는 게 정답**. ②`quantity >= ?` 재고 차단은 **이 시스템 정책 위반** — 음수 재고 허용(stores.allow_sale_without_stock=TRUE 기본, 소매 현장 재고 오차로 판매 거부 금지가 의도된 설계). 채택 시 매장 판매가 막히는 사고 발생. 지점별 잔액은 ProductBranch에 current_stock 컬럼 추가로 해결(신규 테이블 X) |
| 2 | 크로스 테넌트 연결을 DB가 차단 못함 | **채택 + 격상** | 이론이 아니라 **실재**: sale_items 10건(매장 3↔6↔8 교차), ProductBranch 3건(매장 3 상품↔매장 6 지점) 발견 — 초기 CAMPERA/Genérico 테스트 데이터로 추정되나 앱 검증 구멍의 증거. 단, 복합 FK 전면 도입은 Sequelize 정합 비용이 큼 → ①오염 13행 확인 후 정리 ②sales-create에 store 일치 가드 ③주간 감사 쿼리, 복합 FK는 ProductBranch부터 점진 적용. RLS는 **도입 금지** — pgbouncer transaction pooling에서 세션변수 RLS는 오히려 테넌트 누출 위험 + superadmin 크로스매장 기능 파손 |
| 3 | sales(store_id, sale_date) 인덱스 부족 | **채택** | 실측 확인 — (store_id, source, sale_date)뿐. 마이그레이션에 `idx_sales_store_date` 추가됨 |
| 4 | mes/talleres 인덱스 전무 | **채택(축소)** | mes_work_orders·mes_production_results·talleres_orders는 pkey뿐(실측). 제안 컬럼명도 실존 확인. 단 현재 트래픽 낮아 5개만 선별 추가 (talleres_envios/recepciones는 이미 인덱스 있음) |
| 5 | 권한 조회 slow (role_functions 218ms 등) | **방향 채택** | slow_query_log는 현재 0행(덤프 시점 스냅샷)이라 수치 재현 불가하나, pg_stat_statements가 동일 패턴 입증: Users 조회 44,231회·role_function_actions 154,400회. **user_permission_cache 테이블이 0행 = 만들어놓고 안 씀**. 요청단위 캐시+MemoryCacheService 60s가 정답 |
| 6 | password/token 컬럼 기본 조회 | **채택 (실측 확인)** | Users SELECT에 password 포함 44,231회, mp_accounts access_token/refresh_token 조회 확인. 수정: Users 모델 `defaultScope: { attributes: { exclude: ['password'] } }` + auth.service만 `scope('withPassword')`. mp_accounts 동일. 프론트 변경 불필요(응답 DTO에 원래 미포함) |
| 7 | TRUNCATE province_product_stats 잠금 | **저우선 채택** | 65회·평균 3.2ms 실측 — 현재 무해. reseller 포털 성장 시 staging 테이블+swap으로 전환 |
| 8 | products (sku,store_id) 중복 unique 인덱스 | **채택 (실측 확인)** | 제약 소유는 uq_products_sku_store → `products_sku_store_id` DROP 안전. 마이그레이션에 반영됨 |
| 9 | 금액 타입 혼재 | **채택(계획형)** | 실측: sales.total_amount/subtotal·prices.amount는 integer(peso 정수), sale_items.price/subtotal은 numeric(12,2), products.price는 numeric(10,2). AFIP 전자발행은 2자리 필요 → 장기적으로 numeric(14,2) 통일이 맞으나 전 코드 파급이 커서 별도 Phase로. 그전까지 amount_mismatch 감사 쿼리(546ms→인덱스 후 고속)를 야간 잡으로 상시화 |
| 10 | 풀 인스턴스당 5~10 권장 | **기각** | 일반론. 실환경은 pgbouncer transaction mode + ventago pool_size=50이 이미 캡 역할 — Sequelize 80은 클라이언트측 상한일 뿐. 기존 Phase 63 설계 유지 |

**타 AI가 놓친 것** (dump만 봐서): daily_number 중복 5건 실재, products.stock 드리프트 실재, active_sessions UNIQUE 부재, RPO 24h/timeout 미설정, 그리고 무엇보다 **음수 재고 허용이라는 업무 정책** — 이걸 모르면 #1의 차감 가드 같은 "정확해 보이는 오답"이 나옴.

### 최종 실행 순서 (통합)

1. **[즉시·승인 필요]** 마이그레이션 적용 (FK 인덱스 30개 + sales_store_date + mes/talleres 5개 + 중복 인덱스 DROP) — 로컬 5432 + 운영 5434
2. **[즉시·승인 필요]** 설정 3종: `log_min_duration_statement=100`, `idle_in_transaction_session_timeout='60s'`, `ALTER ROLE coolsistema SET statement_timeout='30s'`
3. **[GSD Wave 1 — 백엔드만, 프론트 무변경]** ① Users/mp_accounts 민감컬럼 defaultScope 제외 ② products.stock 상대 증감(`stock = stock ± delta`) ③ daily_counters 채번 테이블+서비스 ④ 권한 요청단위 캐시
4. **[GSD Wave 2 — 데이터 정리·승인 필요]** ① 크로스테넌트 13행 확인 후 정리 ② stock 드리프트 1회 백필 ③ 채번 코드 배포 후 daily_number unique 인덱스 활성화
5. **[GSD Wave 3]** ProductBranch.current_stock 컬럼(지점별 잔액 캐시) + store_id 컬럼/복합 FK — 이때만 프론트 영향 검토(재고 표시 훅), 야간 정합성 잡 상시화
6. **[운영]** 시간별 백업 전환 + 복원 리허설, 금액 타입 통일은 별도 Phase 등록
