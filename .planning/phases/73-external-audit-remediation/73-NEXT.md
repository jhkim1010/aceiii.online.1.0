# Phase 73 후속 — 테스트 부채 정리 + 집계 이전 (새 세션용)

이 문서 하나만 읽으면 바로 이어갈 수 있게 쓴 것이다.
직전 작업(외부 점검 8건 대응)은 `73-HANDOFF.md` 참조 — **전부 배포 검증까지 끝났다.**

---

## 0. ★ 시작 전에 — 기계가 얼지 않게

**jest 를 그냥 `npx jest` 로 돌리지 마라.** 메모리 20GB 를 넘겨 기계가 통째로 얼었다.

원인: 기본값은 워커를 코어 수만큼 띄우는데, **각 워커가 134개 suite 의 Sequelize 모델
상태를 누적**한다. 워커 하나가 2GB 힙으로도 OOM 이 나므로 코어 수만큼 곱해진다.

```bash
# 전체 (총 2~3GB, 약 6분)
NODE_OPTIONS=--max-old-space-size=2048 npx jest --maxWorkers=2 --workerIdleMemoryLimit=1200MB

# 일부만
NODE_OPTIONS=--max-old-space-size=2048 npx jest src/app/<dir> --maxWorkers=1 --workerIdleMemoryLimit=1200MB
```

주의 두 가지 (둘 다 실제로 겪었다):
- **`--runInBand` 는 답이 아니다.** 워커는 하나지만 누적은 그대로라 **오히려 OOM 이 난다.**
  여러 폴더를 한 번에 지정하면 특히 그렇다.
- **`--workerIdleMemoryLimit` 을 낮게(400MB) 잡으면 워커가 계속 재시작돼 134 suite 가 전부
  실패한다.** 1200MB 가 적정선이었다.

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
| api-ventago | `edfc781` | Jenkins api #618 SUCCESS (커밋 대조 확인) |
| ventago-app | `132121d` | Jenkins front #539 SUCCESS (커밋 대조 확인) |

**tsc 오류 0건. 134 suite 전부 실행됨(1136 테스트).**
현재 실패: **10 suite / 약 43 테스트** — 전부 이 작업 이전부터 있던 것이며,
내 변경을 stash 하고 돌려도 동일하게 실패함을 확인했다.

---

## 2. ★ 다음 작업 A — 남은 실패 10 suite 정리

### 이미 확인한 것 (원인 규명 완료 — 전부 "코드는 정상, 테스트가 낡음")

| suite | 실패 | 원인 |
|---|---|---|
| `whatsapp/services/click-to-chat` | 6 | `Nest can't resolve dependencies ... AfipVoucherRepository at index [3]` — 서비스에 생성자 의존성이 추가됐는데 **테스트 모듈만 미갱신**. 서비스가 생성조차 안 돼 6건이 한꺼번에 죽는다. |
| `stocks/stocks.service` | 1 | 기대 `type: 'ajuste'` vs 실제 `type: 'adjust'`. **의도된 개명**이다 — `stocks.model.ts:15` "구 'ajuste' 표기 통일", `stocks.service.ts:142` "[Phase 65 W1]". 소비처(`reportsStocksCockpit`)도 이미 `'adjust'` 로 조회한다. **핵심 불변식(반대 부호 보정 행 추가 + 원본 미변경)은 통과한다.** |

### 아직 원인 미확인 (8 suite)

```
app/role/role-function/role-function.service.spec.ts      (4건 — 이름만 확인)
app/products/products.service.spec.ts
app/products/productStock.service.spec.ts
app/reports/reportsSalesCockpit.spec.ts
app/users/user-function/user-function.service.spec.ts
app/integrations/core/outbox.service.spec.ts
app/afip/providers/rest-gateway.provider.spec.ts
app/shared/clients-sync/backfill-clients-to-global.spec.ts
```

**추정하지 말 것.** 앞의 둘이 "테스트가 낡음"이었다고 나머지도 그렇다는 보장은 없다.
`productStock` / `reports` 는 **재고·매출 숫자**를 다루므로 진짜 회귀일 가능성을 배제할 수 없다.
각각 실패 메시지를 직접 읽고 아래 둘 중 하나로 분류한다:
- **테스트가 낡음** → 고친다(아래 레시피)
- **코드가 틀림** → 그건 버그다. 별도로 다룬다.

### 이번에 4개를 복구하며 쓴 레시피 (같은 부류면 그대로 적용)

원인은 전부 "서비스는 진화했는데 spec 이 그 이전에 멈춤"이었다. 흔한 형태 4가지:

1. **생성자/메서드 인자 추가** — `Expected N arguments, but got N-1`.
   예: Phase 67 이 `storeId`/`@GetUser` 를 추가했다. 스텁 인자를 채운다.
2. **모델 목에 새 메서드 없음** — `X is not a function` / `Model not initialized`.
   예: 일괄 처리로 바뀌며 `findAll`/`bulkCreate` 가 필요해졌다.
3. **조회 방식 변경** — `findByPk` → `findOne({ where: 스코프, lock })`.
   목 대상 자체를 바꿔야 한다.
4. **전체 객체 비교가 필드 추가로 깨짐** — `toHaveBeenCalledWith({...})` 를
   `expect.objectContaining({...})` 로 바꾼다. 그 테스트가 **지키려는 것**만 남긴다.

**복구하면서 빠져 있던 검사를 넣을 기회다.** 이번에 실제로 그랬다 —
`GET /sales/:id` 의 매장 경계 검사(Phase 67 이 "타 매장 판매 상세가 노출됐다"며 넣은 것)에
정작 테스트가 없어서 추가했고, 보류판매 삭제가 `where: { id, storeId }` 인지도 고정했다.

### 왜 하는가 (지우지 않기로 한 이유)

"있는데 안 도는 테스트"는 없느니만 못한 착시를 만든다. 그리고 **낡은 테스트는 진짜 회귀도
못 잡는다** — 73-06 에서 재고 원장 코드를 재작성할 때 되돌아볼 테스트가 없었던 게 그 예다.

---

## 3. 다음 작업 B — jest 를 CI 에 넣기

지금 Jenkins 는 `nest build` (SWC) 만 돌린다. **jest 는 파이프라인에 없다.**
그래서 spec 4개가 0건 실행되는 상태로 #609~#617 이 전부 초록이었다.

A(10 suite 정리)가 끝나야 넣을 수 있다 — 지금 넣으면 바로 빨간불이다.
넣을 때 위 0절의 메모리 옵션을 **반드시** 함께 넣는다(CI 머신도 같은 이유로 죽는다).

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
