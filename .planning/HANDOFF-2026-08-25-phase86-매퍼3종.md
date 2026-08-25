# 핸드오프 — 2026-08-25 · Phase 86 TASK-3′ 매퍼 3종 완료 ★

`HANDOFF-2026-08-24-phase86-스트리밍-하네스.md` 에서 이어짐.

---

## ★★ 이 세션의 한 줄

**SPEC 이 적어 둔 전제가 매퍼마다 하나씩 무너졌다. 셋 다 실측이 뒤집었고,
그때마다 "그럼 어디로 가야 하나" 를 사용자와 정한 뒤에 지었다.**

---

## 배포 (전부 SUCCESS · 운영 반영 완료)

```
5048512  판매 매퍼 — precio 는 줄 합계다
02ef2c0  판매 매퍼 codex 지적 9건                    #811 FAILURE → 원인은 아래 ★
3cd69dc  dist/main.js 가 사라져 컨테이너가 못 떴다    #812 SUCCESS
30f96a3  결제수단 매퍼                                #813 SUCCESS
69124c8  팩투라 매퍼 + legacy_facturas 마이그레이션   #814 SUCCESS

운영 DB   2026-08-24-phase86-legacy-facturas.sql  (로컬 5432 + 운영 5434 양쪽)
운영 nginx client_max_body_size — 아래 ★★
```

---

## ★★ 배포가 멈춰 있었다 (지난 세션부터)

`#810`(지난 세션의 `765169c` 하네스 커밋)이 **실패해 있었고 아무도 못 봤다.**
운영은 `#809` 이후 아무것도 안 받고 있었다. 지난 핸드오프의 "배포 전부 SUCCESS" 는
그 빌드에 대해 틀렸다.

원인: `src/**/*.itest.ts` 가 `test/itest/harness.ts`(= `src` 밖)를 import 하자
TypeScript 가 rootDir 을 저장소 루트로 넓혀 산출물이 **`dist/main.js` →
`dist/src/main.js`** 로 밀렸다. `pm2` 가 `dist/main.js` 를 실행하므로 컨테이너가
조용히 못 떴다. `nest build` 는 **성공**했고 tsc·단위·실DB 검사도 전부 통과했다 —
전부 `src/` 에서 돌기 때문이다. #800 의 `.txt` 미복사와 같은 부류다.

→ `tsconfig.build.json` 에 `**/*itest.ts` 제외 + `assert-runtime-assets.js` 가
  **진입점 존재**를 확인한다(경로는 `ecosystem.config.js` 에서 읽는다).
  대조군 재현 확인: 제외를 되돌리면 `✗ 진입점이 없다: dist/main.js`.

**교훈이 기억에 있다**: `src-importing-outside-src-breaks-dist.md`

---

## ★★ 업로드 상한은 층이 셋이었다 (운영이 1MB 였다)

앱 상수를 65MB 로 올려 배포했는데 **운영은 1MB 도 413** 이었다.
`newapi.coolsistema.com.conf` 에 `client_max_body_size` 가 **아예 없어**
nginx 기본값 1m 이 걸렸다. nginx 는 인증보다 먼저 막으므로 앱 로그에 안 남는다.

적용(사용자 승인):
```nginx
client_max_body_size 25m;          # 도메인 기본값 (앱 최대 선언이 20MB)
location /api/legacy-import/ {
    client_max_body_size 70m;
    proxy_read_timeout 600s;       # preview 가 65MB 를 pg_restore 로 푼다
    proxy_send_timeout 600s;       # 안 올리면 "올라는 가는데 항상 504"
    ...
}
```
실측 확인: 26·64MB → legacy-import 401 / 그 외 413. 71MB → 둘 다 413.
백업 `/root/newapi.coolsistema.com.conf.bak-20260824`.

★ **남은 것**: `shared-folders`·`minio`·`products`·`tryon` 은 앱 쪽 업로드 상한이
  **없다**. 지금은 이 25m 이 유일한 한계다. 별건으로 판단 필요.

**교훈이 기억에 있다**: `upload-limit-has-three-layers.md`

---

## ① 판매 매퍼 — `precio` 는 줄 합계다

```
sum(precio)         = 1,645,328,317   ← tpago 합 1,644,814,500 과 일치
sum(precio × cant1) = 6,243,329,415   ← 3.8배. 착각하면 매출이 이렇게 된다
```
단가는 `preuni`(없으면 `precio/cant1`, 54,141행). 연결 키는 **`vcode = vcode1`**
(ACE 자신의 뷰 둘이 그 키를 쓴다. `ref_id_vcode` 는 default 0 이라 71행이 오결합).

품목 없는 3,225건 중 3,224건은 매출이 아니라 **카하 시재금**이었다
(`clientenombre='CAJA'`·아침 8시대·둥근 수·합 8,533,710). CierreZ 588 과 함께 제외.

취소 플래그는 **둘**(`borrado` 4,691 · `b_cancelado` 279). 하나만 보면 279건이 샌다.

`daily_number` 는 vcode 의 5자리 접미(사용자 결정). "끝의 숫자" 로 뽑으면
`-Caja1` 이 `-00001` 과 충돌해 3,171행이 깨진다 → `-(\d{5})$` 로 정확히 5자리일 때만.

### codex 지적 9건 — "막는다고 적어 놓고 안 막던 것"

정산이 로그일 뿐이었다 → **throw**. `leido` 가 축소된 집합이었다 → 원본에서 센다.
품목 감사가 예상치만 셌다 → `sale_items` 를 실제로 센다. 소유 증명이 0행에서
통과했다 → **개수 일치를 먼저** 본다. 지점 INNER JOIN → LEFT JOIN.
못 읽는/빈 숫자가 0 으로 들어갔다 → 거부. 캐스트가 판정보다 먼저 도는 자리 셋
(`sucursal::int` in JOIN · 최종 `::bigint` · 날짜 `AND`) → 전부 CASE 안으로.

★ **PG 는 `AND` 의 좌→우 평가를 보장하지 않는다.** 대조군으로 실제 재현했다
  (`integer out of range` · `bigint out of range`). 순서를 강제하는 것은 `CASE` 뿐이다.
★ `2026-02-31` 은 정규식을 통과하고 `::date` 도 `to_date` 도 **던진다**.
  → `make_date(y,m,1)+(일-1)` 의 달이 원래 달과 같은지로 판정(캐스트 없음).

**검증**: 실백업 147,825건 · 품목 782,561 · 매출 1,642,515,629 전부 ACE 와 일치.

---

## ② 결제수단 매퍼 — 결제행은 `vtags` 가 아니라 헤더 버킷이다

SPEC v3 는 "vtags + cuentas" 라고 적었지만 그러면 147,825건 중 **12,131건만**
결제수단을 갖는다(현금 11.3억이 아예 없다). 헤더 버킷 5개
(`tefectivo`/`tcredito`/`tbanco`/`treservado`/`tfavor`)가 **147,825건 전부에서
tpago 와 정확히 일치**한다(반올림 드리프트 0).

→ 버킷이 결제행, `vtags` 는 은행분의 계좌 상세. 은행 나머지는 '은행(상세없음)'
  (사용자 결정). vtags 가 tbanco 보다 큰 2건에서는 **음수**가 된다 — 그래야 합이 맞는다.

### ★★ `cuentas` 는 공유 카탈로그다 (사용자가 짚었다)

가리키는 곳이 **셋인데 FK 는 하나뿐**이다:
`vtags.ref_id_cuenta`(제약 없음) · `cobtags.ref_id_cuenta`(제약 있음, serpenti 0행) ·
`online_ventas.cuenta_nombre`(**이름 문자열로**). FK 카탈로그로만 보면 하나만 보인다.
`payment_methods` 에는 유일 제약이 **없어서** 매퍼마다 만들면 같은 계좌가 두세 번 생긴다.
→ 여기서 한 번 만들고 `legacy_entity_maps(entity='payment_method')` 에 남긴다.
  **뒤의 매퍼(외상 수금·온라인)는 그 매핑을 읽어 재사용할 것.**

매장 기본값(`Efectivo`·`MercadoPago`)은 `(store_id, slug)` 로 찾아 재사용한다.

정산은 **금액 항등식**이다: 모든 legacy 판매에서 `Σ amount = sales.total_amount`.

★ `sale_payment_methods` 에는 **테넌트 트리거가 없다**(`sale_items` 와 다르다).
  임포트 밖의 일반 판매 경로에도 해당하는 구멍 — 별건으로 판단 필요.

---

## ③ 팩투라 매퍼 — 판매에 붙일 키가 없다

```
fventas.ref_id_vcode     20,750건 중 20,748건이 0   ← default 0
fdetalles.ref_id_vcode   40,849건 중 40,833건이 0
afip_factura.vcode       '1','2','3'… 품목 수 (사용자 확인: 무의미)
(지점·날짜·금액) 휴리스틱  87%(18,059건) 후보 없음, 유일 매칭 7.8%
```
→ `sale_id` 는 NULL. 값이 하나라도 차면 커밋 전에 던진다.

`afip_vouchers` 로 못 간 이유: `sale_id`/`cae`/`punto_venta`/`afip_number` 가 전부
NOT NULL 인데 **CAE 는 3,409건뿐**이다. 나머지 17,341건(2015-04~2021-07)은
**구형 factura 기계** 시절이라 CAE 라는 개념 자체가 없었다(사용자 확인).
게다가 `reportsFacturacionCockpit` 이 네 곳에서 `JOIN sales` 를 해서,
`sale_id` 를 열면 **넣었는데 보고서에서 조용히 사라진다.**

→ `legacy_facturas` 신규(M8). `cae`/`punto_venta`/`afip_number` 를 nullable 로 둬
  **두 시대를 한 표에** 담는다. `afip_factura` 는 CAE 로 이어 붙인다(DISTINCT ON —
  중요한 건 복제가 아니라 **어느 행이 남는가의 결정성**).
  `fdetalles` 는 기존 `legacy_facturas_detalle` 로(legacy_id 는 PK 7컬럼 정렬의 row_number).

★ 관통 검사가 결함을 잡았다: `tipofactura` 가 빈 1행(id_fventa=1594, DNI·이름·금액
  9999 가 다 있는 실제 팩투라)을 걸러 20,749/20,750 이 됐다 → 원본 보관이므로 넣는다.

---

## ★★ 검사에 대한 이 세션의 교훈

**대조군을 돌릴 때마다 하나씩 나왔다.**

- 판매 매퍼: 5개 대조군 전부 재현 (가드가 실제로 지킨다)
- 팩투라: `DISTINCT ON` 대조군이 **통과했다** — `ON CONFLICT` 가 중복을 흡수해
  결과가 같았다. 즉 그 검사는 아무것도 안 지키고 있었다.
  → fixture 의 **물리적 순서를 뒤집어** "어느 행이 남는가" 를 재게 고쳤더니 물었다.
- SQL 주석 백틱 가드가 **파일 목록을 손으로 들고 있어** 새 매퍼 둘을 안 봤다.
  가드는 있는데 그 자리를 안 보는 상태였다 → 디렉터리를 훑도록 고침 + 목록이 비면
  실패하는 대조군 추가.

★ SQL 주석에 백틱을 쓰면 **TS 템플릿 리터럴이 그 자리에서 닫힌다.** 이 세션에서
  세 번 당했다. 이제 `sql-template.spec.ts` 가 막는다.

---

## ★ 다음 세션이 할 일 — 외상/예약 매퍼 (실측은 끝나 있다)

### 사용자 결정 (2026-08-25)

| # | 결정 |
|---|---|
| 1 | `crddetalle` 은 **안 쓴다** — 내용이 `ref_id_vcode` 로 이은 `vdetalle` 과 같다 |
| 2 | **예약(seña)은 envío 컨트롤로, 외상은 외상으로** |
| 3 | `creditoventas.borrado` = **완납/종료된 건** |

### 실측 (serpenti)

```
creditoventas 5,776 · borrado=t 2,718(47%) · vcode 가 vcodes 와 5,772 일치(99.93%)
  ★ 연결 키는 `creditoventas.vcode`(varchar) 다 — ref_id_vcode 도 같은 답을 낸다
  caso: 0,Res 3,715 · 0,DRes 1,073 · 0,C 590 · 0,P 165 · 0,DC 101 · FC 77
  판매의 treservado>0 이 4,813 / tcredito>0 이 633 → **대부분 예약이다**
  borrado=f 3,058: 외상 7,250,778 · 예약 66,681,084   ← 미결제 잔액은 이것뿐
  borrado=t 2,718: 외상   235,105 · 예약 58,120,662   ← 완납/종료
  DNI 가 clientes 에 있는 것 5,690 / 못 쓰는 DNI 59
cobranzacab 11,804 (수금: clientedni·tpago·fecha·vendedor)
cobtags 0행 · cobdetalles 63 · cheques 78
```

### ★★★ 다음 세션이 **먼저 정해야** 할 것 (착수 전 확인 필요)

`createFromPos` 는 주문을 만들면서 **재고 hold 를 건다**
(`online-orders.service.ts` 의 `createFromPos` → "confirmed 로 시작 + 재고 hold").
legacy 판매는 재고를 안 움직이므로(재고 진실은 기준선 1회) **그 경로를 타면
재고가 이중으로 잡힌다.** 서비스를 부르지 말고 행을 직접 넣되:

1. `stock_held_at` 은 **NULL** 로 둘 것 (hold 없음)
2. `status` 매핑 — `borrado=t`(완납) → ? / `borrado=f` → ? (사용자 확인 필요)
3. `order_number` NOT NULL — 매장별 채번 방식 확인 필요
4. `channel` NOT NULL — 현 사용값: webshop·whatsapp·mercadolibre·instagram·other.
   legacy 예약에 무엇을 쓸지 확인 필요 (새 값이면 CHECK 확인)
5. `mirror_sale_id` 는 채울 수 있다 — `creditoventas.vcode` 로 판매를 찾을 수 있다

외상 쪽(`credit_ledger`)은 다른 위험이 있다:
- `bucket_after` 가 **러닝 잔액**이라 시간순 처리 필수 (creditoventas 청구 +
  cobranzacab 수금을 한 시간축에 놓아야 한다)
- `store_client_id` NOT NULL → clientes 임포트 선행 필수
- open 잔액 공식은 기억의 `credit-open-balance-formula.md` 를 그대로 따를 것
  (`favor_apply` 를 넣으면 두 번 빠진다. 쓰는 곳이 네 군데)

### 그 다음
온라인(`online_ventas` 4,859) · 입고(`ingresos` 97,047 → `legacy_ingresos`) ·
비용(`gastos` 9,263) · 시즌(`temporadas`) → TASK-4′ 잡 러너 → TASK-8′ 화면.

---

## 현재 검사 상태

```
itest 127/127 (실백업 관통 포함) · 단위 299/299 · tsc · build · 변경파일 lint 0
```

파일:
```
streaming/ace-sales.sql.ts      sales.mapper.ts      sales-mapper.itest.ts
streaming/ace-payments.sql.ts   payments.mapper.ts   payments-mapper.itest.ts
streaming/ace-facturas.sql.ts   facturas.mapper.ts   facturas-mapper.itest.ts
streaming/staging-columns.ts    sql-template.spec.ts sales-backup.itest.ts(실백업 관통)
migrations/2026-08-24-phase86-legacy-facturas.sql
```

## 이월 / 미해결

- **`sale_payment_methods` 에 테넌트 트리거가 없다** — 임포트 밖 경로도 해당
- **앱 쪽 업로드 상한이 없는 엔드포인트 4종** (shared-folders·minio·products·tryon)
- codex 미반영 2건: casoesp `%F%` 제외 여부(원장 보존이므로 포함이 맞다고 판단) ·
  품목 단위 legacy id(782,575행 매핑표는 비용이 이득을 넘는다)
- 스테이징이 30 테이블 뒤처져 있다 (200 vs 운영 230)
- `price_types.store_entity_id` 운영 18행 전부 NULL
- MP 후속 부채 MED 3건 · SPEC v3 §9 잔여 확인 · sudoers 0440 ·
  프론트 blue/green 없음 · POS 카탈로그 P95 376ms · 소켓 한도 0 · `/me` 11쿼리 미캐시

## 로컬 환경

- 로컬 `ventago`(5432) = 운영과 스키마 동일. itest 가 여기 붙는다
- `ace_probe` DB 에 serpenti 백업 전체 복원돼 있다 — **지우지 말 것**
  (원본이 옆에 있어야 관통 검증이 성립한다)
- `npm run test:itest` · 디버그 시 `P86_KEEP=1` 로 staging 을 남길 수 있다
