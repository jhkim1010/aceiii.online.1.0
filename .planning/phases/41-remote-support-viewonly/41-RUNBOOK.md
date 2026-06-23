# Phase 41 — Soporte Remoto Embebido (rrweb + 커서 공유) — RUNBOOK

**작성:** 2026-06-18
**범위:** DB 마이그레이션 적용 / 배포 순서 / 보안 체크리스트 / 롤백 / 운영 검증

---

## 1. 구성 요소 요약

| 레이어 | 산출물 |
|--------|--------|
| DB | `migrations/41-01-support-sessions.sql` (support_sessions), `41-02-support-view-permission.sql` (support.view 슬러그) |
| 백엔드 | `src/app/support/` — model / service / gateway(`/support`) / controller / module + `app.module.ts` 등록 |
| 프론트(고객) | `src/hooks/useRemoteSupport.ts`, `src/components/support/RemoteSupportLayer.tsx` (`_app.tsx` 마운트) |
| 프론트(지원팀) | `src/pages/soporte/index.tsx` (대시보드), `src/pages/soporte/visor.tsx` (라이브 뷰어) |
| 사이드바 | `src/navigation/vertical/index.ts` — "Soporte" 항목(`/soporte`, 권한 role) |
| 라이브러리 | `rrweb`, `@rrweb/types`, `rrweb-player` (ventago-app) |

---

## 2. 배포 순서 (운영 PG10 — Docker 아님, 호스트 psql)

> 마이그레이션은 **raw SQL 수동 적용**(자동 push 아님). 멱등(2회 실행 안전).

```bash
# 1) DB 백업(권장)
ssh jhkim-server "sudo -u postgres pg_dump -d ventago -t support_sessions" > /tmp/ss_backup.sql 2>/dev/null || true

# 2) 41-01 — support_sessions 테이블
ssh jhkim-server "sudo -u postgres psql -d ventago -v ON_ERROR_STOP=1" < api-ventago/migrations/41-01-support-sessions.sql

# 3) 41-02 — support.view 권한 슬러그
ssh jhkim-server "sudo -u postgres psql -d ventago -v ON_ERROR_STOP=1" < api-ventago/migrations/41-02-support-view-permission.sql

# 4) 검증
ssh jhkim-server "sudo -u postgres psql -d ventago -c \"SELECT to_regclass('public.support_sessions');\""
ssh jhkim-server "sudo -u postgres psql -d ventago -c \"SELECT id, permission_slug FROM functions WHERE permission_slug='support.view';\""
```

PG10/PG15/PG18 호환: SERIAL / TIMESTAMPTZ / JSONB / UUID 컬럼타입만 사용(확장 의존 0).

### 백엔드/프론트 배포
- 백엔드: `cd api-ventago && docker compose build && docker compose up -d` (Jenkins `api-coolsistema`)
- 프론트: Jenkins `front-coolsistema` (`docker compose build` → `npm run build`)
- 신규 `/support` Socket.io 네임스페이스는 기존 서버(5002) 위에서 동작 — **추가 포트/방화벽 변경 불필요**.

---

## 3. 권한 부여 (R-1)

- privileged role(`super_admin`/`superadmin`/`admin`/`store_owner`/`store_admin`)은 **자동 통과** (별도 부여 불필요).
- 전담 지원 직원(관리자 권한 없이 뷰어만 허용)에게는 `support.view` 함수를 해당 role 의 `role_functions` 에 부여:
  ```sql
  -- 예: role_id=R 에 support.view(read) 부여 (운영 확인 후 실행)
  -- functions.id 확인 → role_functions / role_function_actions 에 INSERT (기존 RBAC 부여 UI 사용 권장)
  ```

---

## 4. 보안 체크리스트 (R-1 ~ R-6)

- [x] **R-1 뷰어 인증**: 뷰어 join/대시보드는 JWT + `support.view`(또는 privileged role) 서버 강제. UUID 유출돼도 무권한자 접속 불가. (`SupportGateway.viewer:join` → `SupportService.canView`, `SupportController.listActive`)
- [x] **R-2 세션 만료**: 생성 후 15분(`expires_at`) + 게이트웨이 `setTimeout` 이중화. 만료 시 `status=expired` + 양측 `session:expired` emit.
- [x] **R-3 고객 가시성**: 고객 화면 상단 진행 배너 + [Finalizar] 상시 노출(`RemoteSupportLayer`). 명시 요청 전 record 시작 안 함.
- [x] **R-4 민감정보 마스킹**: rrweb `maskAllInputs:true` + `blockClass:'rr-block'` + `maskTextClass:'rr-mask'`. **결제 QR / 비밀번호 / AES 키 화면 요소에 `className="rr-block"` 부여 필요(후속 점검).**
- [x] **R-5 동시 뷰어 1명**: `viewerByUuid` Map 으로 강제(2번째 뷰어 거부).
- [x] **R-6 store-scope**: 세션 store ≠ 뷰어 store 면 join 거부(`activateSession` 크로스테넌트 가드). 컨트롤러도 store 스코프.
- [x] **보기 전용**: 지원팀→고객 입력/제어 경로 없음. `cursor:move`는 **좌표 표시 전용**(클릭/키 입력 relay 0).
- [x] **pool 안전**: `pool.connect()` 0회 — Sequelize 싱글턴 모델 + `sequelize.query()`(자동 release)만 사용.

### ⚠ 배포 전 필수 후속 작업 (R-4 마스킹 적용 대상)
다음 화면 요소에 `className="rr-block"`(완전 차단) 또는 `rr-mask`(텍스트 마스킹) 부여 점검:
- MercadoPago QR / 결제 모달 (`src/views/mercadopago/**`)
- AES 키 / 토큰 표시 (`/admin/generar-token` 등)
- 비밀번호 입력은 `maskAllInputs:true`로 기본 마스킹되나, 노출 영역(평문 표시)이 있으면 `rr-block` 추가.

---

## 5. 운영 사용 흐름

1. 고객: 우하단 "Solicitar Soporte"(생명구조 아이콘) FAB 클릭 → 진행 배너 표시 + UUID 발급.
2. 고객이 지원팀에 UUID 전달(전화/채팅).
3. 지원팀: 사이드바 "Soporte" → 대시보드에서 세션 확인 또는 "Abrir visor" → UUID 입력 → "Conectar".
4. 지원팀 화면에 고객 DOM 실시간 재생. 마우스 이동 → 고객 화면에 **빨간 "Soporte" 커서** 표시.
5. 양측 모두 [Finalizar]로 종료. 미종료 시 15분 자동 만료.

---

## 6. 운영 검증 (배포 후)

```bash
# 최신 로그 — pool 경고/대기 0 유지 확인(필수 규칙)
ssh jhkim-server "docker logs --tail 50 api_ventago 2>&1 | grep -i 'DatabasePool\|SupportGateway\|error'"

# 세션 생성/만료 동작
ssh jhkim-server "sudo -u postgres psql -d ventago -c \"SELECT status, count(*) FROM support_sessions GROUP BY status;\""
```

검증 포인트: `[DatabasePool] ... waiting=0` 유지, `[SupportGateway] CONNECT/AUTH OK` 로그, 만료 세션 `status=expired` 전이.

---

## 7. 롤백

```bash
# 백엔드/프론트: 직전 이미지로 재배포(Jenkins 이전 빌드 redeploy)

# DB(필요 시) — 테이블/권한 제거. FK CASCADE 주의(세션 메타만 삭제, 타 테이블 영향 0).
ssh jhkim-server "sudo -u postgres psql -d ventago -c 'DROP TABLE IF EXISTS support_sessions;'"
ssh jhkim-server "sudo -u postgres psql -d ventago -c \"DELETE FROM functions WHERE permission_slug='support.view';\""
```

> support_sessions 는 신규 테이블이라 제거해도 기존 소매/식당/배달 흐름에 영향 0 (회귀-0).

---

## 8. Open Questions 상태

- Q1 뷰어 권한 매핑 → **RESOLVED**: `support.view` 슬러그 + privileged role 통과(R-1).
- Q2 rrweb 이벤트 DB 영속화 → **휘발성 릴레이만**(DB 영속화 X — pool/스토리지 0). 감사 필요 시 후속 phase.
- Q3 운영 `/support` CORS/방화벽 → 기존 5002 서버 재사용, `cors:{origin:'*'}` (print/restaurant 게이트웨이 동일). 추가 인프라 변경 불필요.
