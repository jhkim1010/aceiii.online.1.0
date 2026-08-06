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

## 3. ★ 다음 작업 B — jest 를 CI 에 넣기 (이제 넣을 수 있다)

지금 Jenkins 는 `nest build` (SWC) 만 돌린다. **jest 는 파이프라인에 없다.**
그래서 spec 4개가 0건 실행되는 상태로 #609~#617 이 전부 초록이었다.

A 가 끝나 **0 failed** 가 됐으므로 이제 넣어도 빨간불이 아니다. 넣을 때:

1. **메모리 옵션을 반드시 함께 넣는다** — 0절 참조. 특히 `--maxWorkers=1`.
   2 워커면 매 실행마다 랜덤한 suite 가 SIGTERM 으로 죽어 **CI 가 간헐 실패**한다.
   (CI 머신은 코어가 더 많아 기본값이면 더 심하다.)
2. 전체 실행이 **약 11분**이다. 빌드 시간이 그만큼 늘어난다 —
   PR 단계에서만 돌릴지, 배포 파이프라인에도 넣을지 결정 필요.
3. `reportsSalesCockpit` 은 CI 에 DB 자격증명이 없으면 자동 skip 된다(의도된 동작).
   CI 로그에 위 경고가 찍히는지 확인할 것.

---

## 4. 다음 작업 C — 일일 통계를 서버측 집계로

`DailySalesStats` 가 `/sales/all` 을 `pageSize=9999` 로 불러 **브라우저에서** 집계한다.
`/sales/all` 은 연관 8개(Store/Clients/SaleItem→Product/SalePaymentMethod→PaymentMethod,
Option/SaleDiscount/Users/Seller/Terminal)를 eager load 하므로 JOIN 행이 곱해진다.

**즉시 위험은 막아뒀다** — 서버가 `truncated` 를 내려주고(상한 도달 시 경고 로그),
프론트가 "집계 불완전" 경고를 띄운다. 조용한 오답만은 안 난다.

**근본 해결이 예상보다 저렴할 수 있다 — `GET /sales/daily-stats` 가 이미 존재한다.**
(`sales.controller.ts` 의 `getDailyStats`, Phase 35 ventaVista Resumen 용.)
다음 세션에서 **먼저 확인할 것**: 그 엔드포인트가 `DailySalesStats` 가 필요로 하는 항목을
얼마나 덮는가. 필요한 것은 전부 SQL `GROUP BY` 로 표현 가능하다:
상태별 건수 / 매출·할인·운송 합계 / 품목 수량 합계 / 결제수단별 금액 /
레거시 버킷(efectivo·credito·banco·mercadopago·otro) / ledger(credito·senia·favor·efectivo·
tarjeta·transferencia·mercadopago).

★ 옮길 때 **기존 화면 숫자와 반드시 대조**한다. 집계가 틀리면 조용히 틀린다.

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

## 6. 측정 못 한 것

운영 일일 판매량. SSH 가 끊겨 있어 못 쟀다. C 의 우선순위 판단에 쓰인다:
```bash
ssh jhkim-server "sudo -u postgres psql -p 5434 -d ventago -c \
  \"SELECT date_trunc('day',sale_date)::date d, count(*) FROM sales \
    WHERE sale_date > now()-interval '30 days' GROUP BY 1 ORDER BY 2 DESC LIMIT 5;\""
```
하루 최대 건수가 `BULK_MAX_PAGE_SIZE`(10000)에 얼마나 가까운지가 핵심이다.
