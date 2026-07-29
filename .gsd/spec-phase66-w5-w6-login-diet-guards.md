# SPEC: Phase 66 W5(로그인 다이어트) + W6(확장 가드 소품 + 부하 재측정)
생성일: 2026-07-29

## 목표
/me 응답 55KB→<10KB 로 축소해 로그인 지속한도 60~70건/s → 100건/s 달성. 다중워커+Redis 미가용 가드와 반복 경고 억제. 심야 스테이징에서 로그인 100건/s + 판매 25건/s(Phase 65 무회귀) 재측정.

## 배경 (실측 근거)
- Phase 63 F-4: 로그인 병목 = CPU (bcrypt + 권한조립 + 55KB 직렬화, 그중 structure 47KB). 80건/s에서 p95 4.9s 붕괴.
- 3개 앱 /me 필드 전수 대조 (2026-07-29 조사):
  - 웹(ventago-app): structure 에서 실제 읽는 property = app{slug,name,color,modules} / module{slug,name,url,icon,isMain,isAuxiliary,functions} / function{slug} **뿐**. id/appId/moduleId/description/createdAt 등은 순수 낭비.
  - permissions 맵: 소비처 = reports-v2 2개 파일, 읽는 것은 `.read` 뿐.
  - superadmin 앱: name, roles 만 사용. tienda-admin 앱: accessToken,id,name,roles,storeId,storeName,aliasName,logoUrl. 둘 다 structure/permissions 미사용 (tienda-admin 은 별도 엔드포인트 사용).
  - mobile-sales-app 은 /mobile/me 별도 계약 — 무관.
- lazy 분리(structure 별도 엔드포인트)는 withAccess.tsx 의 즉시 unauthorized 리다이렉트(95개 페이지) 때문에 고위험 → **슬림화 우선, lazy 는 하지 않음** (66-PLAN 5-2 의 목표는 <10KB — 슬림화로 달성).

## 기술 스택
- NestJS 11 + Sequelize / Next.js 13 / Electron 28 / k6(스테이징 loadtest/)
- ESLint: 프론트 Warning=에러. 백엔드 pool: 워커당 max 20 고정 — 변경 금지.

## 진행 현황 (2026-07-29)
- TASK-1~11 완료 (코드). TASK-12 완료 (api eslint 무출력 + tsc --noEmit 0오류, 에이전트 node --check 통과).
- TASK-13: 샌드박스 GitHub 접근 불가 → 사용자 Mac ./push-both.sh 실행 필요 (또는 자동 push-both 대기).
- TASK-14/15: 예약 작업 `phase66-night-loadtest` (2026-07-30 02:30 ART) 등록 — 스테이징 재빌드→/me 실측→login 60/80/100→판매 25/s→verify-burst→결과 66-LOADTEST-RESULTS.md.
- permissions 축소는 "all-false 항목 제거"만 적용 (소비처 의미 무변) — read-only 필터링은 하지 않음.

## 태스크 목록

### W5-2: /me 슬림화 (백엔드 중심)
- [ ] TASK-1: auth.service.ts — structure 매핑 시 화이트리스트 projection 적용
      app: {slug,name,color,modules} / module: {slug,name,url,icon,isMain,isAuxiliary,functions} / function: {slug}
      superadmin 분기(getStructure 그대로 반환)에도 동일 projection. 캐시 키/TTL 유지.
- [ ] TASK-2: permissions 맵 축소 — 4 boolean → 실제 true 인 action 만 담은 압축형 유지 여부는 게이트 결정에 따름 (기본: read=true 인 slug 만 4-bool 유지 → 웹 무변경)
- [ ] TASK-3: 슬림 전후 실측 — 스테이징/로컬에서 /me 바이트 수 기록 (목표 <10KB)

### W5-3: 권한 조립 캐시
- [ ] TASK-4: auth.service.ts /me — permissions_map 빌드 결과를 MemoryCacheService 캐시
      키 `perm:me:{storeId}:{roleId}:{userId}` TTL 5분. 기존 delByPrefix('perm:') 무효화에 자동 편승.
      히트 시 3단계 병렬 쿼리 중 roleFunctionsForPerms/userFunctionsForPerms 2개 스킵.
- [ ] TASK-5: user-function/role-function 변경 경로가 모두 delByPrefix('perm:') 하는지 확인, 누락 보강.

### W5-4: 재접속 지터
- [ ] TASK-6: print-agent/main.js + zebra-agent/main.js — 부팅 자동 연결에만 무작위 0~30s 지연,
      reconnectionDelayMax 5000→30000, randomizationFactor 0.3→0.5. 수동 트리거(ws:reconnect 등)는 지연 없음.
- [ ] TASK-7: edge-agent pull/push/healthProbe setInterval 초기 위상 랜덤 오프셋.
- 웹은 제외 — 사람이 여는 페이지 로드는 자연 분산, 인위 지연은 UX 회귀.

### W6-1/6-2: 확장 가드 + 로그 억제
- [ ] TASK-8: common/health/adapter-status.ts (schema-status 패턴) + main.ts:71-75 —
      멀티워커(NODE_APP_INSTANCE 존재) && Redis 어댑터 미장착 → logger.error + health `redisAdapter:'off'` degraded.
- [ ] TASK-9: Redis 재연결 error 로그 스로틀(클라이언트당 60s 1회) — redis-io.adapter, memory-cache.service,
      redis-throttler.storage, print.service 4곳.
- [ ] TASK-10: sync.service.ts 스키마 검사 성공 로그 리더만 (schemaStatus 기록은 전 워커 유지).
- [ ] TASK-11: ecosystem.config.js env 에 WEB_CONCURRENCY:4 — database.module 커넥션 예산 계산이 1워커로 오인 중.
      (pool max 자체는 불변임을 database.module.ts 에서 확인 후 적용)

### 검증·배포·측정
- [ ] TASK-12: ESLint (api + 프론트 변경분) 0오류
- [ ] TASK-13: push → Jenkins 배포 (api). 에이전트 변경 → 릴리스 태그 빌드.
- [ ] TASK-14: 스테이징 최신화(api-staging 이미지 재빌드) 후 심야 부하: login-capacity 100건/s + pos 25건/s, watchdog 가드
- [ ] TASK-15: 결과 기록 — p95, 에러율, /me 크기, 저장 실패 0 확인

## 완료 기준
- /me < 10KB, 3개 앱 로그인·사이드바·권한 게이트 정상
- 로그인 100건/s p95 < 1s / 판매 25건/s 저장 실패 0 (Phase 65 무회귀)
- Redis 장애 시 로그 초당 5~6줄 → 분당 수줄
- ESLint 0오류, pool 설정 불변

## 금지사항
- structure lazy 분리 금지(이번 phase) — withAccess 리다이렉트 사고 위험
- pool min/max 변경 금지, 운영 DB 직격 부하 금지(ventago_staging 만)
- 트랜잭션 안 외부 I/O 금지 규약 유지
