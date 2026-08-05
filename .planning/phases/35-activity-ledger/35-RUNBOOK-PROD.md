# Phase 35 운영 적용 RUNBOOK (PG10)

**Target:** 운영 서버 srv803182 (62.72.7.245) / PostgreSQL 10 / ventago DB
**작성:** 2026-06-11 (Phase 36 Plan 02)
**Pre-conditions:** 사용자 0명 시간대 (UTC 확인) / 운영자 SSH 접근 (`jhkim-server`)
**Estimated downtime:** 0분 (DDL 은 idempotent INSERT/ALTER 위주, Docker 롤링 재배포)

> ⚠️ **선행 의존:** 본 RUNBOOK 은 Phase 35 hotfix(`de8d0ae`) + Phase 36.1 회귀 hotfix(`f3ade81`)
> 코드가 운영 빌드에 포함됨을 전제. 두 commit 모두 git 에 존재 확인됨(2026-06-11).
> Phase 37 모바일 코드는 본 게이트 해제 후 별도 배포.

---

## Section 0: 사전 점검 (10분)

### 0.1 운영 DB 백업 (필수)
```bash
ssh jhkim-server "sudo -u postgres pg_dump ventago -Fc -f /tmp/ventago-pre-phase35-$(date +%Y%m%d-%H%M%S).dump"
ssh jhkim-server "ls -lh /tmp/ventago-pre-phase35-*.dump | tail -1"
```
실패 시: 백업 미생성이면 **중단**. 디스크 여유 확인 후 재시도.

### 0.2 운영 서비스 헬스 체크
```bash
ssh jhkim-server "curl -s -o /dev/null -w '%{http_code}\n' https://newapi.coolsistema.com/api"
ssh jhkim-server "docker ps --filter name=api_ventago --format '{{.Status}}'"
```

### 0.3 활성 세션 0명 확인
```bash
ssh jhkim-server "sudo -u postgres psql -d ventago -c 'SELECT COUNT(*) FROM active_sessions;'"
# 예상: 0 (또는 본 운영자 자신만 1)
```

### 0.4 사용자 승인
"운영 적용 시작합니다. 진행해도 됩니까?" — 사용자 confirm 후 다음 단계.

---

## Section 1: 마이그레이션 SQL 적용 순서 (5분)

> 모두 idempotent. 각 단계 `ON_ERROR_STOP=1` 로 실패 시 즉시 중단.

### 1.1 Phase 35 base schema (이미 적용됐으면 IF NOT EXISTS 로 no-op)
```bash
ssh jhkim-server "sudo -u postgres psql -d ventago -v ON_ERROR_STOP=1" < api-ventago/migrations/phase35-activity-ledger.sql
```

### 1.2 stock.movement permission 등록
```bash
ssh jhkim-server "sudo -u postgres psql -d ventago -v ON_ERROR_STOP=1" < api-ventago/migrations/phase35-stock-movement-permission.sql
```

### 1.3 Phase 36 role_function_actions 보강 (Plan 01 산출물)
```bash
ssh jhkim-server "sudo -u postgres psql -d ventago -v ON_ERROR_STOP=1" < api-ventago/migrations/phase36-stock-movement-actions-backfill.sql
```
> precheck: function_id=149 가 stock.movement 가 아니면 EXCEPTION 으로 안전 중단.
> 운영 function id 가 149 가 아니면 SQL 의 149 를 운영 값으로 치환 후 재실행.

### 1.4 마이그레이션 검증
```bash
ssh jhkim-server "sudo -u postgres psql -d ventago -c \"
  SELECT COUNT(*) FROM information_schema.columns WHERE table_name='sales' AND column_name IN ('activity_type','origin_branch_id','target_branch_id');\""
# 예상: 3

ssh jhkim-server "sudo -u postgres psql -d ventago -c \"
  SELECT COUNT(*) FROM role_function_actions rfa JOIN role_functions rf ON rf.id=rfa.role_function_id WHERE rf.function_id=149;\""
# 예상: (운영 role_functions 수) × 4. 예: 12 role_functions → 48.
```

---

## Section 2: Backfill 실행 (15분)

### 2.1 dry-run
```bash
./api-ventago/migrations/phase35-backfill-dry-run.sh prod
```

### 2.2 dry-run 결과 검증
- `backfilled_rows` = movido + fallado 그룹 수
- `failure_rows` = 0 또는 < 5% (실패는 `backfill_failures` 기록)
- failure_rows 가 5% 초과면 **중단** 후 원인 분석.

### 2.3 사용자 승인 후 실제 commit
```bash
ssh jhkim-server "sudo -u postgres psql -d ventago -v ON_ERROR_STOP=1" < api-ventago/migrations/phase35-backfill-movidos-to-sales.sql
```

### 2.4 backfill 결과 검증
```bash
ssh jhkim-server "sudo -u postgres psql -d ventago -c \"SELECT activity_type, COUNT(*) FROM sales GROUP BY activity_type;\""
# 예상: sale 기존 동일 + movido/fallado 신규
ssh jhkim-server "sudo -u postgres psql -d ventago -c \"SELECT COUNT(*) FROM backfill_failures;\""
# 예상: 0 또는 < 5%
```

### 2.5 REG-2 데이터 정합 (movido/fallado dailyNumber=0 강제)
Phase 36.1 `f3ade81` 가 신규 INSERT 의 dailyNumber=0 을 보장하나, backfill/legacy 행 보정:
```bash
ssh jhkim-server "sudo -u postgres psql -d ventago -c \"
  UPDATE sales SET daily_number = 0 WHERE activity_type IN ('movido','fallado') AND daily_number != 0;\""
```

---

## Section 3: Hotfix 코드 배포 (20분)

운영 빌드에 포함되어야 할 commit:
- **api-ventago:** `de8d0ae` (Phase 35 hotfix 5건) + `f3ade81` (Phase 36.1 REG-1 branch 필터 + REG-2 dailyNumber)
- **ventago-app:** `0151df5` (tab title + multi-branch admin fallback) + `d215bbb` (VentaVista Movidos/Fallados 체크박스)

### 3.1 / 3.2 빌드 + 배포 (Jenkins CI 자동 — 수동 docker 아님)
운영 배포는 **Jenkins CI/CD 가 전담**한다. 이미지는 Jenkins 워크스페이스에서 로컬 빌드되며
레지스트리 pull 이 아니다. main push 시 자동 트리거:
- api-ventago main push → Jenkins `api-coolsistema` job → 빌드 + `docker compose up -d` (컨테이너 `api_ventago`, workdir `/var/lib/jenkins/workspace/api-new-coolsistema`)
- ventago-app main push → Jenkins `front-coolsistema` job → 빌드 + 배포 (컨테이너 `ventagoapp`, workdir `/var/lib/jenkins/workspace/front-coolsistema`)

빌드 상태는 Jenkins UI 또는 `ssh jhkim-server "docker ps --filter name=api_ventago --format '{{.Status}}'"` 로 확인.

### 3.3 (선택) 수동 재배포 — Jenkins 미경유 긴급 시에만
```bash
ssh jhkim-server "cd /var/lib/jenkins/workspace/api-new-coolsistema && docker compose up -d --build"
ssh jhkim-server "cd /var/lib/jenkins/workspace/front-coolsistema && docker compose up -d --build"
```
> 정상 경로는 Jenkins 자동 빌드. 위 명령은 CI 장애 시 fallback (이미지 로컬 빌드).

### 3.4 헬스 체크
```bash
ssh jhkim-server "curl -s -o /dev/null -w '%{http_code}\n' https://newapi.coolsistema.com/api"
ssh jhkim-server "curl -s -o /dev/null -w '%{http_code}\n' https://app.coolsistema.com"
ssh jhkim-server "docker logs api_ventago 2>&1 | grep -iE 'error|fatal' | grep -vi 'MpTokenRefresh' | tail"
```

---

## Section 4: 회귀 검증 (10분)

### 4.1 ventaVista 활동 분류
- `/ventas` → Resumen 테이블 8 컬럼 (SUCURSAL · VENTAS · PRENDAS · DESC · MOV+ · MOV− · FAL · NETO)
- 행 클릭 → `?originBranchId=X` + chip [지점명 ✕] / 셀 클릭 → 2 chip
- toolbar Movidos/Fallados 체크박스 토글 → activityType filter sync
- **REG-1 검증:** admin user(branch_id=NULL) 가 등록한 정상 sale 이 branch chip 필터에서 노출됨

### 4.2 Stock Cockpit MOV+/MOV−/FAL + OFFSET
- `/reportes/stocks` → PanelB ItemTable 의 MOV+ / MOV− / FAL 컬럼
- 임의 product 의 OFFSET = 0 (movido/fallado 흡수 안 됨)
- 등식: INGRESO − VENTA + MOV+ − MOV− − FAL + OFFSET = STOCK

### 4.3 권한 매트릭스
- `/configuracion/permisos` 탭 1 → "stock.movement" 행의 role 들에 ✓ 표시 (Plan 01 보강 효과)

### 4.4 cURL POST /stocks/movement
```bash
TOKEN=...  # 운영 권한 보유 JWT
curl -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"type":"movido","originBranchId":1,"targetBranchId":2,"items":[{"productId":N,"quantity":1}]}' \
  https://newapi.coolsistema.com/api/stocks/movement
# 예상: HTTP 200 + {"saleId": NNN, "success": true}
```

---

## Section 5: 롤백 절차 (긴급 시)

### 5.1 코드 롤백 (Jenkins 재빌드)
정상 롤백 = 문제 commit revert 후 main push → Jenkins 가 이전 상태로 재빌드/재배포:
```bash
# api-ventago / ventago-app 각 repo 에서
git revert <bad_commit> && git push   # → Jenkins 자동 재배포
```
긴급(CI 장애) 시 워크스페이스에서 직전 커밋 체크아웃 후 수동 재빌드:
```bash
ssh jhkim-server "cd /var/lib/jenkins/workspace/api-new-coolsistema && git checkout <PREV_SHA> && docker compose up -d --build"
ssh jhkim-server "cd /var/lib/jenkins/workspace/front-coolsistema && git checkout <PREV_SHA> && docker compose up -d --build"
```

### 5.2 마이그레이션 데이터 ROLLBACK (DDL 컬럼은 유지)
```bash
ssh jhkim-server "sudo -u postgres psql -d ventago -c \"
  DELETE FROM sale_items WHERE sale_id IN (SELECT id FROM sales WHERE notes LIKE '[Backfill Phase 35]%');
  DELETE FROM sales WHERE notes LIKE '[Backfill Phase 35]%';\""
```
> ⚠️ role_function_actions 보강분 롤백은 권장하지 않음 (Phase 35 시점 기존 행과 구분 불가).
> 권한 롤백이 필요하면 백업(0.1)에서 role_function_actions 만 선별 복원.

### 5.3 pg_dump 복원 (최후 수단 — 다운타임 발생)
```bash
ssh jhkim-server "sudo -u postgres createdb ventago_restore"
ssh jhkim-server "sudo -u postgres pg_restore -d ventago_restore /tmp/ventago-pre-phase35-*.dump"
# 검증 후 swap (운영 다운타임). 최후 수단.
```

---

## Sign-off

사용자 검증(Section 4) 완료 시:
1. `.planning/STATE.md` 의 Phase 35 status → complete
2. Phase 36 status → complete
3. Phase 37 모바일 코드 운영 배포 게이트 해제 (별도 push)

**적용 전제 체크리스트:**
- [ ] 사용자 0명 시간대
- [ ] 운영 DB 백업 (0.1)
- [ ] Phase 35 hotfix(de8d0ae) + Phase 36.1(f3ade81) 코드가 운영 빌드에 포함
- [ ] 각 마이그레이션 단계 사용자 확인 (CLAUDE.md DDL/DML 규칙)
- [ ] dry-run failure < 5%
