# 핸드오프 2026-09-29 — 출력 견고화 · 가격 기록 1단계 · 권한 · 검색

> 앞 문서: `HANDOFF-2026-09-28-notas-precio-predeterminado.md`

## 1. 운영에 나간 것 (전부 빌드 성공 확인)
| 내용 | 커밋 | Jenkins |
|---|---|---|
| Notas 글자 +25% | app `03034d8b` | front #852 |
| Sucursales·Cajas 목록 순서 고정(id ASC) | api `e52d45ac` | api #991 |
| Venta 에서 다른 지점 comandera 연결(권한 or 관리자 승인) | api `6de116c3` app `1b04f5da` | #992 / #853 |
| 새 기능 풍선(novedades, admin·gerente) — `src/configs/novedades.ts` 에 항목 추가 | app `2dccf82c` | #854 |
| Caja fuerte 꺼진 지점은 금액 대신 «Desactivado» | app `960bb839` | #855 |
| verify-admin-credentials 매장 한정·열거 차단 | api `9d26b96a` | #994 |
| **배포 후 에이전트가 offline 으로 남던 결함**(NOIX 출력 불가 원인) — 리셋은 신호 없는 것만, 하트비트가 offline+socket NULL 행 복구 | api `8429e40c` | #995 |
| 가격 기록 1단계(sale_items 3컬럼, 증표, 보고서 API) | api `15307d8b` app `a5da14bd` | #996 / #856 |
| Impresoras 권한 CRUD 로 분리(ver-impresoras create/update/delete) | api `69f2f18e` | #998 |
| CodigoVista 검색: 대소문자·악센트·단어순서 무시 | app `d734ef2c` | #857 |

## 2. 운영 DB 변경 (승인 후 · 로컬 동일)
- `2026-09-29-a` 금고 7개 전액 retiro → 0 (ops 184–190, user 1)
- `2026-09-29-b` sale_items.price_type_id/list_price/price_authorized_by
- `2026-09-29-e` 역할별 terminal 권한 → ver-impresoras 로 복사(54 행)

## 3. 승인 대기
- **(c)** `2026-09-29-c-permiso-reporte-precios-fuera-de-lista.sql` — 미커밋 · 미적용. 적용 전엔 보고서가 403/메뉴 숨김.
- **(d)** `2026-09-29-d-print-jobs.sql` — 로컬(ventago, ventago_loadtest)만 적용. 운영 미적용 · 미커밋.

## 4. 진행 중: 출력 대기열 (print_jobs) — 코드 미작성
- 근거(로컬 부하 시험, `loadtest/print/`): 300매장 ~95건/s, 교란 없음 5,675건 분실 0 · **에이전트 5% 재접속 교란 시 163/5,545(2.94%) 분실**, 전부 `agent_offline` 거절(보내지도 않음). 중복 0.
- 설계: sendToprinters 가 refuse=agent_offline 이고 대상이 한 대로 정해지면(고른 프린터 → 터미널 기본 → 지점 1대) `print_jobs` 에 pending 저장(payload=invoiceData+printJobId, footer 는 전송 시 적용). 에이전트 접속(gateway handleConnection, setOnline 뒤)과 하트비트에서 `SELECT … FOR UPDATE SKIP LOCKED` 로 꺼내 sent 표시 → **커밋 후** emit. 15분 지나면 expired. 한 번도 emit 안 한 것만 넣으므로 중복 위험 없음.
- 백업 선언: `store-backup-coverage.ts` EXCLUDED_TABLES + `store-backup-inventory.txt` 에 `print_jobs` 추가 필요.
- 검증: 같은 교란 시험을 다시 돌려 분실 0 확인(대조군 = 위 2.94%).
- 시험 리그: `loadtest/print/{agent-sim.js,burst-print.js,analyze.js,seed-print-agents.sql}` · DB `ventago_loadtest`(로컬 5432, 더미 837–1136) · API 는 `API_PORT=5012 DATABASE_NAME=ventago_loadtest … node dist/main` (THROTTLE_* 완화). **loadtest/ 변경은 미커밋**(시드 가드에 ventago_loadtest 허용 추가 포함).

## 5. 알려진 위험 / 남은 일
- print-agent: 렌더 큐에 `.catch` 없음 → 한 번 실패하면 재시작 전까지 전부 실패. 인쇄 전 job 소비(at-most-once). 같은 프린터 동시 인쇄. **에이전트 릴리스 필요(태그 수동)**.
- 접속마다 `fetchSockets()` 전체 조회(배포 시 O(N²)). 출력 1건 DB 3–8쿼리가 판매 응답 경로 안.
- 카트 표 단가 칸은 승인 없이 편집 가능(1단계는 «SIN AUTORIZACIÓN» 으로 기록만). 증표는 12h·매장 단위 재사용 가능 — 2단계.
- 전 시스템 검색 대소문자 무시 작업: 에이전트가 조사·수정 중(미커밋).
- 재고 분류 칸 수정 · NOIX 재인쇄 결과 — 여전히 결정/확인 대기.
