# Phase 73 후속 — 테스트 부채 정리 + 집계 이전 (새 세션용)

이 문서 하나만 읽으면 바로 이어갈 수 있게 쓴 것이다.
직전 작업(외부 점검 8건 대응)은 `73-HANDOFF.md` 참조 — **전부 배포 검증까지 끝났다.**

---

## 0. ★ 시작 전에 — 기계가 얼지 않게

**jest 를 그냥 `npx jest` 로 돌리지 마라.** 메모리 20GB 를 넘겨 기계가 통째로 얼었다.

원인: 기본값은 워커를 코어 수만큼 띄우는데, **각 워커가 134개 suite 의 Sequelize 모델
상태를 누적**한다. 워커 하나가 2GB 힙으로도 OOM 이 나므로 코어 수만큼 곱해진다.

```bash
# 전체 — 이 조합이어야 0 failed 가 나온다 (약 11분)
NODE_OPTIONS=--max-old-space-size=2048 npx jest --maxWorkers=1 --workerIdleMemoryLimit=800MB

# 일부만
NODE_OPTIONS=--max-old-space-size=2048 npx jest src/app/<dir> --maxWorkers=1 --workerIdleMemoryLimit=800MB
```

주의 (전부 실제로 겪었다):
- **`--runInBand` 는 답이 아니다.** 워커는 하나지만 누적은 그대로라 **오히려 OOM 이 난다.**
- **`--workerIdleMemoryLimit` 을 400MB 로 낮추면** 워커가 계속 재시작돼 134 suite 가 전부 실패.
- **`--maxWorkers=2` 는 매 실행마다 1~2 suite 가 SIGTERM 으로 죽는다.** 죽는 대상이 실행할
  때마다 바뀌므로(특정 suite 결함이 아님) 초록/빨강이 랜덤해진다. jest 의 idle-limit 워커
  재시작이 suite 실행 중에 걸리는 경합이다. **1 워커면 완전히 사라진다.**
- **`--workerIdleMemoryLimit` 을 아예 빼면 더 나쁘다** (2 워커 기준 6 suite 가 47초 만에
  하드 OOM). 이 옵션은 장식이 아니라 필수다.

무거운 명령(jest / nest build / next build)은 **하나씩** 돌린다. 동시에 돌리지 마라.

## 0-1. push 는 SSH 가 없어도 된다

`ssh-agent` 가 비어 있으면 `git push origin` 이 막힌다. 그런데 `gh` 가 keyring 에 repo
스코프 토큰을 갖고 있으므로 remote 설정을 바꾸지 않고 **이번 push 만 HTTPS URL** 로 보내면 된다:

```bash
git push https://github.com/jhkim1010/<repo>.git main
```

단, **운영 서버(Jenkins 확인)는 여전히 SSH 가 필요하다** — 그건 GitHub 토큰과 무관하다:
```
! ssh-add --apple-use-keychain ~/.ssh/id_ed25519
```

---

## 1. 지금 상태

| 저장소 | HEAD | 배포 |
|---|---|---|
| root | `ea1225d` | — |
| api-ventago | `47a4afe` | Jenkins api #619 |
| ventago-app | `132121d` | Jenkins front #539 SUCCESS (커밋 대조 확인) |

**tsc 오류 0건. 134 suite 중 133 통과 / 1 skip / 0 실패 (1148 테스트).**
남은 1 skip 은 `reportsSalesCockpit` — 실 DB 통합 테스트라 자격증명 없으면 건너뛴다(아래 2절).

---

## 2. 작업 A — 남은 실패 10 suite 정리 ✅ 완료 (2026-08-06, 커밋 `47a4afe` / `cbfb246`)

10 suite 전부 초록으로 만들었다. **9건은 "테스트가 낡음", 1건은 진짜 회귀였다.**

### ★ 진짜 회귀 1건 — 별도 커밋 `cbfb246`

`createVariantsBatch` 가 **같은 요청 안에 동일 (sizeId, colorId) 조합이 두 번 오면
같은 SKU 로 두 번 INSERT** 해 `uq_products_sku_store`(UNIQUE(sku, store_id), 운영에서 확인)
위반으로 **배치 전체가 500** 이 됐다.

원인: N+1 리팩터가 "반복마다 findOne" → "루프 밖 일괄 findAll" 로 바뀌면서 직전 반복이
만든 variant 를 다시 조회할 길이 사라졌는데, 생성 후 `existingMap` 등록이 함께 빠졌다.
`existingMap.set(...)` 한 줄로 복구.

**이게 이 작업을 한 이유 그 자체다.** "동일 조합 2번 전달해도 에러 없음" 테스트가 정확히
이걸 지키고 있었는데, 낡아서 안 도는 동안 회귀가 조용히 들어왔다.

### 실행조차 안 되던 것 2건

| suite | 원인 |
|---|---|
| `backfill-clients-to-global` | jest `rootDir` 이 `src` 인데 spec 이 `scripts/` 를 import → ts-jest OOM → **0건 실행**. **AppModule 탓이 아니다** — 순수 함수 하나만 있는 파일을 rootDir 밖에 두고 import 해도 똑같이 죽는 것을 실험으로 확인. 헬퍼를 `src/app/shared/clients-sync/*.helpers.ts` 로 옮기고 `scripts/` 진입점이 거기서 import. → 8건 실행 |
| `whatsapp/click-to-chat` | 테스트 모듈에 `AfipVoucher`/`PdfTokenService` 프로바이더 없음 → 서비스가 생성조차 안 돼 6건 동시 사망 |

### 구현 진화 미반영 — 목 대상 교체

`role-function`(단일 트랜잭션+bulkCreate 배치) / `user-function`(bulkCreate 배치) /
`products.service`(findByPk 루프 → 일괄 findAll) /
`productStock`(Color·Size 는 findAll 일괄, ProductBranch 는 findOrCreate).

### 의도된 동작 변경인데 기대값이 낡음 — **근거를 확인하고** 기대값만 갱신

- `stocks`: `'ajuste'` → `'adjust'` (Phase 65 W1 개명, 소비처도 `'adjust'`)
- `outbox`: `create` 옵션에 `ignoreDuplicates` (PG `ON CONFLICT DO NOTHING` —
  sequelize `insertQuery` 가 실제로 지원함을 소스에서 확인. **타입만 보고 무시된다고 넘기지 말 것**)
- `rest-gateway`: `dni` 문자열 → 숫자 (`bb8da10` AFIP 10015 대응)
- `productStock`: 두 축 모두 Único 면 SKU 에 `-V` 접미사 (부모와 SKU 충돌 회피)
- `productStock`: ProductBranch 0건은 예외가 아니라 **"첫 입고" 정상 경로**(Trello bklfCOX3)
  → 대신 진짜 rollback 을 검증하는 테스트로 교체
- `products.service`: 지점 컨텍스트 없는 stock 은 기록 안 함. 옛 테스트는
  `product_id`(**미존재 컬럼**) INSERT 를 기대했는데 **그게 고아 행을 만든 결함 그 자체**였다

### 복구하며 빠져 있던 검사를 추가 (이번에도 이게 남는 소득이었다)

- AFIP 10015 불변식(DocNro 무효 → DocTipo 99) — 정작 그 수정에 테스트가 없었다
- `updateProductsStatus` attributes 에 `storeId` 포함 (빠지면 **전 매장 403**, Phase 70 S5)
- role/user-function 의 `storeId` 스코프 + **모든 쓰기가 같은 트랜잭션을 타는지**

### `reportsSalesCockpit` 은 왜 skip 인가

실 DB 통합 테스트다. `DATABASE_PASSWORD` 없으면 모듈 부팅부터 죽어 8건이 빨간불이 된다
(코드 결함이 아닌데도). 자격증명 있을 때만 돌게 했고, **skip 임을 경고 로그로 남긴다** —
조용히 통과시키면 "테스트가 있는데 안 돈다"는 착시가 그대로 생기기 때문이다.
로컬에서 돌리려면: `DATABASE_PASSWORD=... npx jest reportsSalesCockpit`.

---

## 3. 작업 B — jest 를 CI 에 ✅ 완료 (커밋 `45717d8`) — 단, **Jenkins 가 아니라 GitHub Actions**

`.github/workflows/api-tests.yml` — push(main) + PR 에서 전체 suite 실행.

### ★ Docker 빌드 안에서 돌리는 방식은 시도했다가 철회했다 (다시 하지 말 것)

먼저 Dockerfile builder 스테이지에 넣었다(`5f1e548`). 배포를 막을 수 있는 지점이
build 뿐이라 게이트로는 이상적이었다. **그런데 실제로 돌리니 못 쓴다.**

Jenkins 는 **운영 서버(srv803182) 위에서** 돈다. 그 박스 실측:
- **swap 0**, 실제 free 1.6GB (나머지는 캐시)
- 같은 박스에서 **운영 PostgreSQL 이 프로세스당 3GB**, Jenkins(java) 1.9GB, mongod 1.2GB

여기서 134 suite 를 돌리자 워커가 **SIGABRT(V8 OOM abort)** 로 연달아 죽었다(build #620).
`--maxWorkers=1` 로도 그랬고, 컨테이너 안에서는 suite 당 시간이 5초→25초로 늘었다.

**실패보다 위험이 더 문제다.** swap 이 없으므로 메모리 스파이크 시 OOM killer 가
**운영 Postgres 를 고를 수 있다.** CI 가 장애를 만드는 구조는 채택할 수 없다.
(#620 동안 운영 컨테이너는 무사했고 build 실패로 `up -d` 가 안 돌아 배포도 안 됐다 —
게이트 자체는 의도대로 동작했다. 방식이 이 서버에 안 맞았을 뿐이다.)

### 알고 넘어가는 한계 — 이건 **하드 게이트가 아니다**

GH Actions 는 Jenkins 배포를 **막지 못한다**(같은 push 에 독립 트리거).
빨간불은 "배포 후 통보"다. 하드 게이트를 원하면 **Jenkins 를 운영 서버 밖으로 빼는 것이
선행**돼야 한다. 그 전에는 어떤 방식이든 운영 메모리를 갉아먹는다.

### 부수 발견 — `package-lock.json` 이 어긋나 있다

axios/googleapis/nodemailer 등 **21개 의존성이 lock 에 없고**, 반대로 electron 같은
모노레포 잔재가 들어 있다. 그래서 `npm ci` 를 못 쓰고 `npm install` 을 쓴다
(Dockerfile 과 동일 — 즉 **운영 이미지도 매번 버전을 새로 해석**하고 있다는 뜻).
재현 가능한 빌드를 원하면 lock 재생성이 필요하지만 전이 의존성 버전이 바뀔 수 있어
별도 과제로 남긴다.

---

## 4. 작업 C — 일일 통계 서버측 집계 ✅ 완료 (커밋 `ce38044` / front `bd2869e`)

`GET /sales/daily-summary` 신설. `DailySalesStats` 가 그걸 쓰도록 전환했고
클라이언트 집계 루프(약 55줄)와 73-10 의 `truncated` 경고를 제거했다.

### 기존 `/sales/daily-stats` 로는 안 됐다 (핸드오프의 기대와 다름)

지점별 ventas/prendas/descuento 만 덮는다. 화면이 쓰는 **상태별 건수·결제수단별 금액·
레거시 5버킷·ledger 7종·transport 가 전부 없다.** 그래서 새 엔드포인트를 만들었다.

### 설계 판단 두 가지

1. **분류 로직을 SQL 로 번역하지 않았다.** `classifyPayment`/ledger 매핑을 SQL CASE·
   정규식으로 옮기면 악센트(créd/débi/depós)·대소문자에서 어긋나기 쉽고, 어긋나면
   **오류 없이 숫자만 조용히 달라진다.** 무거운 스캔만 SQL 에 맡기고 분류는
   `daily-summary.util.ts`(프론트에서 그대로 이식)에서 한다. 동치성 테스트 43건 첨부.
2. **ledger 건수는 판매 단위 DISTINCT 로 따로 구한다.** 결제수단별 count 를 더하면 안 된다 —
   한 판매에 'Tarjeta Visa'/'Tarjeta Master' 가 같이 있으면 둘 다 tarjeta 로 매핑되는데
   프론트는 1건으로 센다(slugSeen). 그래서 키 단위 `COUNT(DISTINCT sale_id)` 를 별도로 돌린다.

### 운영 데이터 대조 (핸드오프가 요구한 것) — 10개 항목 전부 일치

store 6 / 2026-07 전체(74건: 유효 72 + 취소 2, Anulado·Anulación 혼재)로
기존 클라이언트 집계 결과와 대조: 건수 72/2, 금액 9,997,600, 품목 535, 할인 0, 운송 0,
결제수단 5종, 버킷 5종, ledger 금액 4종 + **건수(credito 1 / efectivo 65 /
transferencia 1 / mercadopago 1 — DISTINCT 카운트까지 일치)**.

---

## 5. 미확정 — 사용자 결정 대기 (73-HANDOFF.md 에서 이월)

1. **기존 0원 식당 판매 3건** 보정 여부. 73-03 이후 신규는 정상 기록되지만 과거분은 0.00 이다.
   ```sql
   SELECT s.id, si.product_id, si.price, si.quantity
     FROM sales s JOIN sale_items si ON si.sale_id = s.id
    WHERE s.table_id IS NOT NULL;
   ```
2. **나머지 27개 컨트롤러의 pageSize 상한.** 유틸(`common/pagination/pagination.util.ts`)은
   있으나 sales·products·expenses 3곳에만 적용했다. **라우트별 호출부 확인이 선행돼야 한다** —
   상한을 잘못 잡으면 목록이 조용히 잘린다(실제 호출값: /sales/all 9999, /products/by-parent 1000).

## 6. 측정 완료 — 운영 일일 판매량 (C 의 전제였던 수치)

**하루 최대 12건이다** (store 6, 2026-07-22). 상위 8일: 12, 11, 9, 7, 5, 5, 4, 4.

`BULK_MAX_PAGE_SIZE` 는 10000 이다. **즉 절단 위험은 사실상 0 이었다** —
73-10 의 `truncated` 경고도, C 의 긴급성도 이 수치 앞에서는 과대평가였다.
C 를 한 실익은 절단 방지가 아니라 **연관 8개 eager load 로 JOIN 행이 곱해지던 것을
없앤 것**(전송량이 판매 건수와 무관해짐)이다. 그 자체로는 유효하지만,
"사장이 보는 매출이 조용히 틀린다" 는 시나리오는 현재 트래픽에서 일어나지 않았다.

★ 이 수치는 §5-2(나머지 27개 컨트롤러 pageSize 상한)의 우선순위에도 그대로 적용된다.
상한을 서두를 이유가 약하다 — 오히려 상한을 잘못 잡아 목록이 잘리는 쪽이 더 큰 위험이다.

원 측정 명령:
```bash
ssh jhkim-server "sudo -u postgres psql -p 5434 -d ventago -c \
  \"SELECT date_trunc('day',sale_date)::date d, count(*) FROM sales \
    WHERE sale_date > now()-interval '30 days' GROUP BY 1 ORDER BY 2 DESC LIMIT 5;\""
```
하루 최대 건수가 `BULK_MAX_PAGE_SIZE`(10000)에 얼마나 가까운지가 핵심이다.
