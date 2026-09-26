# 핸드오프 2026-09-26 (c) — 원가·환율 · 에이전트 API Key · 권한

> 다음 세션은 **§5 남은 일**부터. 오늘 나간 것은 전부 운영 배포·빌드 확인까지 끝났다.
> ★ 이 세션에서 **화면을 브라우저로 직접 확인하지 못했다**(Chrome 연결 불안정·터널 이동 차단).
>   서버는 스테이징 실요청으로 검증했다. 첫 작업으로 운영 화면 3곳을 눌러 볼 것(§6).

## 1. 오늘 운영에 나간 것 (배포 순서)

| # | 내용 | api | app | Jenkins |
|---|---|---|---|---|
| 1 | 교환(cambio) — 13:03 예약 배포 | `71ea26d8` | `ec96e393`·`1f2e2171` | api #970 · front #815 |
| 2 | print-agent 단일 실행 잠금 → **v1.2.6** (자동 업데이트 피드 1.2.6) | — | — | GH Actions |
| 3 | 에이전트별 API Key 복사 칼럼 · 쓰기 권한 가드 | `b3ce2588`·`c99d7441` | `946619a7`·`94085459` | #971 · #816 |
| 4 | 지점 단위 키 경로 `/print/config/:branchId` 삭제 · codex P3 | `9804e923` | `c35fafb7` | #972 · #817 |
| 5 | **원가 ARS/USD → 기준가 · 달러 환율** (+codex 수정) | `2c74beec`·`a0ad2fc6` | `f16c2f26`·`22b9852d` | #973 · #818 |
| 6 | 권한 **「Ver costo original de producto」** (`ver-costo-producto`) | `9e616ae0`·`c64aafa8` | `7dbd0b83` | #974 · #819 |

루트 포인터 최종: `9e7b42c`.

**운영 DB 에 적용한 마이그레이션 (사용자 승인)**
- `2026-09-26-costo-usd-cotizacion.sql` — `products.cost/cost_currency/markup_pct`(nullable) + `store_exchange_rates`
- `2026-09-26-b-permiso-ver-costo.sql` — function 1 · role_functions 18 · actions 18 (admin·store_admin·store_owner 에 read)
- 두 파일 모두 로컬(5432)·스테이징에도 적용됨. intel 카탈로그 재생성 커밋됨.

## 2. 원가·환율 기능 요지

- 공식: `precio base = costo × (USD 면 환율) × (1 + markup/100)` → 환율 행의 반올림(단위·↑/≈)
  - api `src/app/products/costo/costo-precio.ts` ↔ app `src/utils/costo-precio.ts` **두 벌**, 두 spec 이 같은 케이스 고정
- **가격 쓰기는 전부 `bulkUpdatePrices`** — 자식 전파·이력·30분 되돌리기. 내부 전용 `meta.bases/inTx/summaryExtra`
  (메모리 `cost-driven-price-goes-through-bulk-update`). 되돌리기는 원가도 복구(`restaurarCosto`).
- API `/cotizacion`: `actual`(세션) · `historial`(가격 권한 read) · `POST`(저장만) · `impacto` · `aplicar`
  (트랜잭션 안 FOR UPDATE 로 원가 변경 감지 → 409) · `PUT productos/:id/costo`(madre 만, 자식 400)
- 화면: Productos nuevos 「Costo → Precio base」 한 칸(편집 모드에서 환율이 바뀌어도 **자동으로 가격을 안 바꾼다**,
  「Usar $X」 제안) · Configuración › Productos 「Cotización del dólar」 카드 · CodigoVista 「Costo」 열 토글 + 「Dólar (N)」
- 환율은 **수동 입력만**(BNA·블루 자동 조회 미구현). 운영에 **아직 환율 0건** — 매장이 한 번 넣어야 USD 원가가 계산된다.
- 권한 `ver-costo-producto`: 없으면 서버가 응답에서 원가 필드 제거(`quitarCosto`), 원가 쓰기 403/무시. 화면도 숨김.

## 3. 에이전트 API Key / print-agent

- Agentes 표 「API Key」 칼럼: 클릭 = 서버에서 받아 복사(`POST /print/agents/:id/key`, `editar-terminal` + 감사 로그,
  키는 로그에 안 남김). 생성 직후 키 다이얼로그. Sucursales 🔑 버튼 삭제.
- 에이전트 생성·삭제·수정·재발급에 서버 권한 가드(종전엔 역할 0개도 가능했다).
- **NOIX(store 19, branch 28)** 키 두 개(#20 caja · #21 caja1) **변경 없음** — md5 지문 `236fd2c9144a` / `4265317425d9`.
  ⚠️ NOIX 는 터미널–comandera 매핑 0건 + 에이전트 2대 → 둘이 동시에 켜지면 영수증 `ambiguous_target` 로 안 나간다.
  사용자에게 알렸고 조치(매핑 지정 또는 1대 삭제)는 **미결**.
- print-agent v1.2.6: 한 PC 두 번 실행 방지(zebra-agent 와 동일).

## 4. 목업 (승인됨, 일부 미구현)

- `.planning/sketches/impresoras-clave-por-agente.html` — 에이전트 카드(키 복사·터미널 칩·footer)
- `.planning/sketches/venta-selector-impresora.html` — **1 터미널 : N 프린터**, Venta 에서 프린터 선택
- `.planning/sketches/agentes-columna-api-key.html` — ✅ 구현됨
- `.planning/sketches/producto-costo-usd.html` v2 — ✅ 구현됨

## 5. 남은 일 / 결정 대기

1. **Ganancia(일일 이익)** — 설계 `.planning/PLAN-2026-09-26-ganancia-diaria.md`. 사용자 결정 3개 대기:
   ① 판매 시점 원가 스냅샷(`sale_items.unit_cost`, 권장) ② 지출 범위 ③ 화면 위치. 권한 `ver-ganancia` 별도.
2. **1 터미널 : N 프린터 + Venta 프린터 선택** (목업 승인, 미구현) — 연결 테이블, 지점 간 인쇄 가드(`print.service.ts:996`)
   를 「같은 매장 + 명시 연결」로 완화, 선택 유지 범위(세션/1건)·Zebra 적용 여부·재인쇄 목록 범위 결정 대기.
3. **교환 판매 취소·수정** — 설계 `.planning/PLAN-2026-09-26-cambio-anulacion-modificacion.md`. 결정 D1~D3 대기(질문했으나 답 없음).
4. **Phase 95 멀티테넌트** — W0(평일 로그로 격리 경보 확인)부터.
5. 원가 대량 적용 성능: `bulkUpdatePrices` 가 행마다 쿼리(N+1). 운영 대량(수백 상품×변형)은 미측정.
6. 핸드오프 (b) 의 잔여(스테이징 상시화 `stage.coolsistema.com`, 현금 환불 권한 통일 등) 그대로.

## 6. 첫 확인 (운영 화면)

- Productos nuevos: 원가 ARS/USD 한 줄, 계산 캡션, 저장 후 편집 불러오기
- Configuración › Productos: 환율 카드 → 「Cambiar」 → 미리보기 → 저장
- CodigoVista: 「Costo」 토글, madre 행 선택 후 원가 수정 → 가격·자식 반영·되돌리기 스낵바
- Agentes: API Key 칼럼 클릭 복사, 역할별로 원가가 숨는지(admin 외 계정)

## 7. 스테이징 · 로컬 상태

- 로컬: `ssh -N -L 15432` 터널 · API :5002(→ventago_staging, `CRON_ENABLED=false`, 로그 `/private/tmp/claude-501/stgapi.out`) ·
  `next dev :3050` · gate-proxy :8088 · cloudflared — **아직 떠 있다.**
- 스테이징 DB 에 남긴 것(지우지 않는다): 계정 `stg.sinrol@dummy.test`(역할 0, store 6) · 상품 `STGCOSTO1`(id 6561) ·
  환율 3행 · 가격 배치 여러 건 · 상품 364 원가(USD 12,5·80%) · 에이전트 15 키 재발급됨(스테이징만).
- 스테이징 터널은 쿼리당 ~330ms — 자식 50개 madre 원가 저장이 80초 걸린다(행 걸림 아님).

## 8. 이번 세션의 교훈

- `@Audit` 는 응답 전체를 `new_values` 에 저장한다 → **비밀을 돌려주는 라우트에 쓰면 audit_logs 에 평문**. 직접 기록할 것.
- 컨트롤러가 item 을 그대로 서비스에 넘기면 새 필드가 HTTP 로 주입된다 → 내부 전용 값은 `meta` 로.
- 운영 로그 대조군: nginx 기본 access.log 에는 API 트래픽이 없다(vhost 는 `minio_acces.log`). 0건이면 대조군부터.
- prettier 를 기존 spec 파일 전체에 돌리면 무관한 줄이 「추가된 줄」이 되어 커밋 게이트가 막는다 — 새 파일에만.
- `git add … && git commit`, 명령 안의 `grep -a` 도 훅이 `commit -a` 로 오인한다 — 커밋은 단독 명령으로.
