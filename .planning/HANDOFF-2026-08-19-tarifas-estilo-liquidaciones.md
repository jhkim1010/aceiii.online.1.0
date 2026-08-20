# 핸드오프 — 2026-08-19 · 공임 단가 스타일 축 + 정산 복구

`HANDOFF-2026-08-18-c-recovery-queue.md` 를 이어받았다.

한 줄 요약: **눌러보기 전까지는 아무것도 고쳐진 게 아니었다.**
정산 500 은 결함이 **3겹**이었고, 하나를 고칠 때마다 다음이 드러났다.

---

## ★ 오늘 가장 중요한 것 — "고쳤다" 를 언제 말할 수 있나

정산 초안 생성이 500 이었다. 원인을 찾아 고치고, 빌드 성공·컨테이너 healthy·
엔드포인트 401·DB 메커니즘 양방향 검증까지 마치고 **"고쳤다" 고 보고했다.**

그리고 화면에서 눌러보니 **여전히 500** 이었다. 그 뒤로 두 겹이 더 나왔다.

| # | 화면에 보인 것 | 진짜 원인 |
|---|---|---|
| 1 | 500 `current transaction is aborted` | `FOR UPDATE` + 테넌트 훅이 주입한 OUTER JOIN |
| 2 | 500 `relation ... does not exist` | `talleres_subcon_deliveries` 조인 — **어디에도 없는 테이블** |
| 3 | 404 `Settlement no encontrado` | 커밋 **전에** 트랜잭션 밖으로 재조회 → throw → **전체 롤백** |

★ 3번이 제일 고약했다. 로그에는 `신규 DRAFT id=1 생성` / `COMMIT 완료` 가 찍히는데
DB 는 비어 있었다 — 그 로그가 트랜잭션 콜백 **안**이라 실제 커밋 전에 찍힌 것이다.
증상(404)만 보면 원인을 짐작할 수 없다.

**교훈: 배포·라우팅·단위검증은 "배선 검증" 이 아니다. 화면에서 한 번 돌기 전에는
완료로 말하지 않는다.** 이 리포의 기존 메모(`build-pass-is-not-wired`)가 그대로 맞았다.

---

## ★ 가려진 첫 오류는 PG 로그에 있다

앱 로그의 `current transaction is aborted` 는 **원인이 아니라 증상**이다. 진짜 첫 실패는
앱에 안 남을 수 있다. `/var/log/postgresql/postgresql-18-ventago18.log` 를 먼저 본다.

```
21:57:40.017 ERROR: FOR UPDATE cannot be applied to the nullable side of an outer join   ← 진짜
21:57:40.148 ERROR: current transaction is aborted, ...                                  ← 앱이 본 것
```

`logging_collector=off` 라 journalctl 에는 없다. 파일을 직접 봐야 한다.

---

## 배포 (전부 SUCCESS)

| 커밋/빌드 | 내용 |
|---|---|
| api #744 | Jenkins 스모크 **부팅 대기가 고장**나 있던 것 |
| api #745 | 색상 재등록 500 (Trello #272) |
| api #746 | 복구 큐 500 — `operator is not unique: date + unknown` |
| api #747 / front #662 | `x-client-route` — 실패 로그에 화면 위치 |
| api #748 / front #663 | Stocks Valor $0 → 지점별 당일 매출, 공임 단가 스타일 축 |
| api #749·#751·#752 | 정산 500 3겹 |
| api #750 / front #664 | Tarifas 옷별 단가 편집 UI |

마이그레이션 2건 — 로컬(5432)·운영(5434) **양쪽 적용 확인**.

---

## 만든 것

### 공임 단가에 스타일(옷) 축

`talleres_vendor_etapas.style_product_id` → `products(id)` (**마드레**). NULL = 기본단가.
해석은 `getRateAt` 한 곳: 스타일 전용 → 없으면 기본단가.

- ★ `NULLS NOT DISTINCT` 유니크가 이 설계의 핵심이다. PG 는 UNIQUE 에서 NULL 을 서로
  다르게 보므로 없으면 **기본단가가 여러 개** 활성이 되고 폴백이 비결정적이 된다.
- ★ `setRate` 의 활성행 마감 스코프에 스타일을 넣었다. 빠뜨리면 스타일 단가를 넣는
  순간 **기본단가가 마감**돼 다른 모든 옷의 단가가 조용히 사라진다. spec 이 지킨다.
- 테넌트 트리거를 확장해 타 매장 제품에 단가를 거는 구멍도 막았다.

### ★ 처음에 `style_code`(문자열)로 만들었다가 되돌렸다

그 값을 채우는 곳이 **어디에도 없었다** — `products` 에 컬럼 자체가 없고
`talleres_lotes.style_code` 는 운영 전 건이 비어 있었다. 그대로 뒀으면
"만들었지만 영원히 0건" 이 됐다.

반면 스타일 정체성은 **마드레/이호로 이미 유지되고 있었다**(store 6: 마드레 18 / 이호 191).
FK 라 대소문자·공백 정규화 사고 계열도 통째로 사라진다.
마이그레이션 2개를 순서대로 남겼다(`2026-08-19-*`, `2026-08-19b-*`).

**교훈: 새 축을 만들기 전에 "그 값을 누가 채우나" 를 먼저 확인한다.**
`normalizeStyleCode` 를 쓰게 된 것 자체가 잘못된 키를 골랐다는 신호였다.

### Cost Sheet 의 임의 공방 선택 (별건, 기존 결함)

`buildCmtSnapshot` 이 `etapaId` 만으로 `findOne` 해서 `effective_from DESC` 첫 행을 썼다.
한 공정을 여러 공방이 맡으면 **어느 단가가 뽑힐지 사실상 임의**였다 —
운영 `corte` 는 활성 3건($1.000 vs $2.000)이라 원가가 **2배까지** 달라졌다.

이제 후보를 전부 읽고 규칙으로 고른다: 스타일 전용 → 유일한 기본단가 →
둘 이상이면 고르지 않고 `MULTIPLE_VENDORS`(화면 `TALLER SIN ASIGNAR`).
**틀린 숫자보다 빈 숫자가 낫다.**

### Stocks Panel A — Valor $0 → 당일 매출

`stock × products.price_orig` 였는데 운영 367개 중 `price_orig > 0` 인 행이 **0개**.
평가액을 살리는 대신 지점별 당일 매출로 교체(사용자 결정).
`activity_type='sale'` 필터 + `ACCOUNTING_SALE_STATUSES` + **매장 타임존** 기준.
0원일 때 마지막 판매일을 덧붙여 "고장" 과 "오늘 아직 안 팔림" 을 구분한다.

### `x-client-route`

실패한 요청 헤더에 화면 경로를 실어 기존 ExceptionFilter 로그에 함께 남긴다.
별도 수집 엔드포인트를 만들지 않아 **중복 수집·루프·폭주가 원천적으로 없고**,
401 처럼 토큰이 사라지는 경우도 자동으로 남는다(CODEX 권고).
배포 직후 바로 값을 냈고 그것이 정산 500 을 잡는 단서가 됐다.

---

## ★ 내가 만들 뻔한 결함

QC 공제 집계가 `talleres_vendor_etapas` 를 그냥 조인하고 있었다. 스타일 축을 넣으면서
`(vendor, etapa)` 에 활성 행이 여러 개 생길 수 있게 됐고 — 실제로 `lee × corte` 가 2행 —
그대로 뒀으면 **공제가 행 수만큼 부풀** 뻔했다. `LATERAL` 로 한 행만 고르되
규칙을 `getRateAt` 과 같게 맞췄다.

**새 축을 추가하면 그 테이블을 조인하는 곳을 전부 다시 본다.**

---

## 화면에서 확인한 것 (cmux 브라우저)

- **Tarifas**: `lee × corte` 에 `CAMPERA DE PAÑO` 전용 $3.500 등록 → 매트릭스에 `$2,000 +1`.
  DB 확인: 기본단가(id 1)의 `effective_to` 가 **여전히 NULL = 활성**. 위험했던 결함 없음 확정.
- **정산**: `Liquidación #2 · Borrador · lee · 08-01~08-20` 생성, DB 에 영속.

로그인은 사용자가 해줘야 한다(비밀번호 입력은 못 함). cmux 브라우저가 편하다:
`cmux browser open <url>` → `cmux browser --surface surface:N eval|click|screenshot`.
MUI Select 는 `.MuiSelect-select`, Autocomplete 는 `.MuiAutocomplete-popupIndicator` 를 클릭해야 열린다.

---

## Trello 상태

**이미 고쳐졌는데 카드만 안 옮겨진 것 4건** — `Hechos Semanales` 로 옮겨야 한다:

| 카드 | 수정 |
|---|---|
| #261 `bklfCOX3` Agregar a 2 sucursales | `e5e7d76` 2026-08-03 |
| #267 `06TCj16i` Ventas suspendidas | `d87bcc0` 2026-08-13 |
| #268 `mx1zWga5` factura electronica | `9116b67` 2026-08-14 |
| #272 `CLFnzcnT` reingreso de colores | 오늘 (api #745) |

★ 분류는 `git log --all | grep <카드ID>` 로 한 번에 된다 — **커밋 메시지에 카드 ID 를
적어두면** 다음 사람이 5초 만에 안다. 오늘 #272 커밋에는 못 적었다(다음엔 적을 것).

**Trello 쓰기 권한이 없다** — `TrelloMoveCard failed: User not authorized`. 읽기만 된다.

### 남은 오류 카드 8건 (미조사)
`#253` Codigo Vista · `#257` Pasar a pdf · `#259` Cargar varios productos ·
`#262` Articulos eliminar o mod · `#263` Productos → Dashboard · `#265` Cambiar sucursal ·
`#266` Productos · `#271` Stock tienda

★ `#263`·`#271` 은 어제 서버 로그에 흔적이 없어 원인을 못 찾았다. 이제
**`x-client-route` 가 배포됐으니 재현만 하면** 어느 화면의 어떤 API 인지 로그에 남는다.

---

## 다음

1. **Tarifas 실사용 확인** — `CAMPERA DE PAÑO` 의 Cost Sheet 를 열면 CORTE 가 $3.500 으로
   채워지는지. (지금 `corte` 는 기본단가가 2개라 다른 스타일은 `TALLER SIN ASIGNAR`)
2. **`corte` 의 활성 기본단가 2개 정리** — ruth $1.000 / lee $2.000. 하나로 줄이거나
   스타일별로 지정해야 Cost Sheet 가 숫자를 낸다. **영업 결정이라 사용자 몫.**
3. **Trello 8건** — 위 순서로.
4. 정산 라인이 실제로 찍히는지 보려면 그 기간에 **수령(recepción)이 있는 공방**으로 만들어야 한다.
   오늘 만든 건 lee 라 0줄이었다.

### 알려진 미해결 (이전 핸드오프에서 이월)
- ★ **D6 — QC `REWORK` 가 불량 수량을 이중 계상한다.** 손실 귀속까지 오염시킨다.
- **W5** 자재 원장 권위(`OPENING_BALANCE`) — `mes_materials` id 5,6,7,11,13,15,17
- **W6** `talleres_settlements.store_id` — ★ **오늘 정산이 처음 생겼다(1건).**
  "0건인 지금이 유일한 기회" 라던 창이 닫히기 시작했다. 하려면 지금.
- **W7** `Acciones pendientes` 화면 통합
- `products.routing_template` 이 213개 중 1개만 채워져 있다 — 옷별 공정 경로가 사실상 없다.

### 형제 테이블에 남은 같은 결함
`(name, store_id)` UNIQUE + 소프트삭제 조합이 `categories`(잔존 2) / `subcategories`(2) /
`suppliers`(1) / `sizes` / `seasons` / `origins` 에 동일하게 있다. colors 에서 패턴을
확정했으니(재활성화 + 409 매핑 + 정규화) 옮기면 된다.

---

## 작업 방식 — 이번에 걸린 것

- ★ **"고쳤다" 는 화면에서 한 번 돌린 뒤에만 말한다.** 오늘 이것 때문에 두 번 정정했다.
- ★ **가려진 첫 오류는 PG 로그에.** 앱 로그의 `transaction is aborted` 는 증상이다.
- ★ **새 축을 만들기 전에 "누가 그 값을 채우나" 를 확인한다.** 안 하면 영원히 0건이다.
- ★ **새 축을 추가하면 그 테이블을 조인하는 곳을 전부 다시 본다.** 행이 늘면 합계가 부푼다.
- ★ **커밋 메시지에 Trello 카드 ID 를 적는다.** 분류가 grep 한 번으로 끝난다.
- CODEX 자문이 이번에도 값을 했다 — `buildCmtSnapshot` 이 주석과 달리 `getRateAt` 을
  안 부른다는 지적, `NULLS NOT DISTINCT`, 별도 수집 엔드포인트를 만들지 말라는 권고.
  다만 CODEX 가 낸 `sale_date`·인덱스 주장은 **직접 대조해서** 맞는지 확인했다.
