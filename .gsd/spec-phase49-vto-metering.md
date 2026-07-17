# SPEC: Phase 49-M — Probar Virtual(VTO) 사용량 과금 미터링 + 매장별 on/off
생성일: 2026-07-16 · 상태: PLAN (실행 대기 — 세션 충돌 해소 후) · 트랙: Phase 49 (vendedor AI) 부속

## 목표
판매원 앱의 "Probar virtual"이 **성공적으로 생성될 때마다** 서버가 매장·기기·판매원 단위로 기록한다. 이 횟수는 SaaS 요금 청구 근거(성공 1회 = 과금 1회)이므로 **서버 측 append-only 원장**으로 관리한다. 매장 admin은 자기 매장 사용량 확인 + 기능 on/off, superadmin은 전 매장 사용량 확인.

## 요구사항 (사용자 원문 기준)
1. 성공 생성 건만 카운트 (실패/에러는 과금 제외 — 단 기록은 남겨 진단용)
2. 어느 매장 · 어느 핸드폰(기기) · 몇 번 — 3차원 추적
3. 매장 admin 페이지에서 자기 매장 횟수 확인
4. superadmin은 매장별 횟수 확인 (청구 근거)
5. 매장 admin이 VTO enable/disable → disable 시 판매원 앱에서 버튼 자체가 안 보임

## 설계

### D-1. 과금 원장 테이블 `vto_generations` (append-only)
| 컬럼 | 내용 |
|---|---|
| id, store_id, branch_id? | 매장 스코프 (필수) |
| user_id | 판매원 (mobile 세션의 유저) |
| device_fingerprint / mobile_session_id | 어느 핸드폰 (vendedor_devices / mobile_sessions 연계 — EXECUTE 시 실컬럼 확인) |
| product_id | 어떤 상품으로 생성했나 (분쟁 대응) |
| status | success / failed (과금은 success 만) |
| provider, provider_request_id | 'fashn' + 외부 요청 ID (청구 대사용) |
| latency_ms, error_message | 진단 |
| created_at | 시각 |
- 인덱스: (store_id, created_at) + partial WHERE status='success'
- **UPDATE/DELETE 금지** (과금 원장 — append-only). 월별 집계는 쿼리로.
- 마이그레이션: 로컬 5432 + 운영 5434 동시, OWNER TO coolsistema (테이블+시퀀스)

### D-2. 기록 시점 (서버가 진실)
Phase 49 VTO 생성 엔드포인트(FASHN 프록시)에서 **FASHN 성공 응답 확정 직후 INSERT** 후 결과 반환. 클라이언트 카운트 신뢰 금지. INSERT 는 pool 규칙 준수(트랜잭션 불요, 단건). 실패 건도 status='failed' 로 기록(과금 제외, 진단용).

### D-3. 매장별 토글
- `stores.vto_enabled` boolean DEFAULT false (allow_sale_without_stock 패턴 재사용 — EXECUTE 시 stores vs store_configs 실위치 확인)
- 서버 authority: disabled 매장의 생성 엔드포인트는 403 (버튼 숨김은 UX 보조 — 기존 원칙)
- `/mobile/me` 응답에 `vtoEnabled` 포함 → Flutter 앱이 Probar virtual 버튼 조건 렌더

### D-4. API (전부 기존 패턴 재사용)
| 엔드포인트 | 대상 | 내용 |
|---|---|---|
| GET /vto/usage?from=&to= | 매장 admin/gerente | 자기 매장: 총 성공 횟수 + 기기별·판매원별·일별 분해 (raw SELECT, LIMIT) |
| PATCH /vto/config | 매장 admin | { enabled } 토글 |
| GET /admin/vto/usage?month= | superadmin | 매장별 성공 횟수 집계 (admin-console 패턴) — 청구 근거 |
| (기존) POST /mobile/vto/... | vendedor | 생성 — disabled 시 403, 성공 시 원장 INSERT |

### D-5. 프론트
- **매장 admin**: Configuración 허브에 "Probador virtual (IA)" 섹션(Preferencias 또는 Operación 탭) — 이번 달 성공 횟수 카드 + 기기별/판매원별 테이블 + enable/disable 토글(확인 다이얼로그: "판매원 앱에서 버튼이 사라집니다")
- **superadmin**: /admin/tenants 콘솔에 "VTO (mes)" 열 추가 또는 /admin/vto 요약 — 매장×월 매트릭스
- (선택) Centro de Control 위젯: 이번 달 VTO 사용량 — Phase 57 control-center 에 후속 추가 가능

### D-6. 모바일 (mobile-sales-app, Flutter)
- /mobile/me 의 vtoEnabled=false → Probar virtual 버튼 미렌더 (Riverpod 상태)
- 403 응답 방어 처리 (토글이 세션 중 바뀐 경우 스낵바)

## 태스크 목록
- [ ] TASK-1 (api): 마이그레이션 — vto_generations + stores.vto_enabled (+owner)
- [ ] TASK-2 (api): VTO 생성 경로에 원장 INSERT + disabled 403 게이트 (Phase 49 엔드포인트 실위치 확인 후)
- [ ] TASK-3 (api): GET /vto/usage (매장) + PATCH /vto/config + GET /admin/vto/usage (superadmin)
- [ ] TASK-4 (front): Configuración 허브 VTO 섹션 (사용량+토글)
- [ ] TASK-5 (front): superadmin tenants 콘솔 VTO 열
- [ ] TASK-6 (mobile): /mobile/me vtoEnabled 소비 + 버튼 조건 렌더 + 403 방어
- [ ] TASK-7: 검증 — 러너 eslint/tsc + 성공/실패/disabled 3케이스 수동, 원장 append-only 확인

## 완료 기준
- 성공 생성 1회 = vto_generations success 1행 (기기·판매원·매장 식별 가능)
- 매장 admin 화면에서 월 사용량·기기별 분해 확인 가능, 토글 즉시 반영
- disabled 매장: 앱 버튼 미노출 + 서버 403 (이중 방어)
- superadmin 매장별 집계 = 청구 근거로 사용 가능 (provider_request_id 로 FASHN 인보이스와 대사 가능)

## 금지사항 / 주의
- 원장 UPDATE/DELETE 금지. 카운트는 서버만 (클라이언트 집계 신뢰 금지)
- 마이그레이션 양쪽 동시 + OWNER coolsistema. 운영 적용은 승인 게이트
- Phase 49 본체(FASHN 연동)가 미구현/타 세션 진행 중이면 TASK-2 는 그 엔드포인트 확정 후 — **api-ventago 세션 충돌 확인 후 EXECUTE**
- pool: 조회는 raw SELECT + 집계 인덱스, 신규 pool 금지
