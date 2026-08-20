# 핸드오프 — 2026-08-19 (b) · 정산 store_id + 다섯 번째 껍질

`HANDOFF-2026-08-19-tarifas-estilo-liquidaciones.md` 를 이어받았다.

한 줄 요약: **정산 화면 하나에 결함이 다섯 겹이었고, 오늘 남은 두 겹이 드러났다.**
둘 다 컴파일러가 볼 수 없는 층이라 코드가 아니라 **강제 지점**으로 막았다.

---

## ★ 오늘 가장 중요한 것 — 실행된 적 없는 코드는 검증된 적이 없다

어제 핸드오프의 교훈("화면에서 눌러보기 전엔 고친 게 아니다")이 한 칸 더 갔다.
**한 번 통과했다고 그 뒤가 검증된 것은 아니다.**

| # | 화면에 보인 것 | 진짜 원인 | 발견 |
|---|---|---|---|
| 1 | 500 `transaction is aborted` | `FOR UPDATE` + 테넌트 OUTER JOIN | 어제 |
| 2 | 500 `relation does not exist` | `talleres_subcon_deliveries` — 없는 테이블 | 어제 |
| 3 | 404 `Settlement no encontrado` | 커밋 **전** 재조회 → throw → 전체 롤백 | 어제 |
| 4 | 500 `transaction is aborted` | **시퀀스 권한 누락** | 오늘 |
| 5 | 버튼 무반응 | **`pdfkit` default import** | 오늘 |

★ 4·5번은 **앞의 셋이 고쳐지기 전까지 도달조차 못 하던 코드**다. 정산 라인이 한 번도
삽입된 적이 없어서 시퀀스 권한 결함은 "존재할 수 없는 것처럼" 보였고, PDF 는 정산이
생겨야 누를 수 있었다.

**목록이 떴다고 생성이 되는 게 아니고, 생성이 됐다고 그 다음 버튼이 되는 게 아니다.**
오래 죽어 있던 경로를 고칠 때는 그 경로가 만드는 후속 동작을 **전부** 눌러 본다.

---

## 배포 (전부 SUCCESS)

| 빌드 | 내용 |
|---|---|
| api #753 | 정산 `store_id` (Phase 84 W6) |
| api #755 | `pdfkit` default import + **빌드 게이트 추가** |
| front #665 | Tarifas 미배정 칸 편집 허용 |

마이그레이션 2건 — 로컬(5432)·운영(5434) **양쪽 적용·대조 확인**.

---

## 만든 것

### 1. `talleres_settlements.store_id` — 매장 경계를 컬럼으로 (Phase 84 W6)

지금까지 이 테이블은 `store_id` 가 없어, 격리를 앱 훅이 `subcon_order|vendor` 부모를
**OUTER JOIN 으로 주입**해서 대신했다. **그 조인이 어제 500 의 뿌리였다.**
컬럼이 생기면 `policy.guarded=true` 가 되고 파생 주입은 `if (policy.guarded) return;`
로 건너뛴다 — 즉 **원인 자체가 사라진다.**

DB:
- `store_id NOT NULL` + FK. 백필 **전에** 무결성 검사(귀속 불가·부모 소실·두 부모 매장
  불일치)를 돌리고 걸리면 트랜잭션째 중단. `COALESCE` 만 쓰면 모순을 vendor 쪽으로
  덮어써서 **숨긴다**(CODEX [HIGH]).
- `CHECK ((vendor_id IS NOT NULL) <> (subcon_order_id IS NOT NULL))` — 두 FK 가 nullable
  인 것만으로는 상호배타가 보장되지 않았다(CODEX [HIGH]). 운영 실측 위반 0건.
- 테넌트 트리거 3개. 그중 `lines → settlement` 은 **부모에 store_id 가 없어 지금까지 걸 수
  없던 검사**다.

코드:
- `lockSettlement` 의 "id 찾고 → 가드 우회해 PK 로 잠그기" 2단계 우회 제거 → `storeId` 를
  **필수 인자**로 받는 단일 잠금 조회.
- 레지스트리에서 `SubconSettlement` 제거, `SubconPayment` 2단계→1단계.
  `anyOf` 규칙을 쓰는 모델은 이제 **없다**(엔진은 남겨 뒀다).

★ 부수적으로 **실제 구멍 2개**를 막았다:
- `confirm/cancel/markPaid/findByIdWithLines` 의 격리 검사가 `if (s.vendorId != null)`
  안에 있어, **order 기반 정산(vendorId NULL)은 검사를 통째로 빠져나갔다.**
- `findFiltered` 가 매장 조건을 `SubconOrder` LEFT JOIN 에 걸고 있었다. **LEFT JOIN 의
  where 는 부모를 못 거른다** — order 없는 정산이 전 매장 노출됐다(G6).

### 2. 시퀀스 권한 (네 번째 껍질)

```
ERROR: permission denied for sequence talleres_settlement_lines_id_seq
```
테이블을 만들 때 `GRANT ... ON TABLE` 은 했는데 **시퀀스를 빠뜨렸다.** CLAUDE.md 가
경고하는 그 형태다 — `ALTER TABLE OWNER` 는 시퀀스 owner 를 안 옮긴다.
형제 `talleres_settlements` 는 owner 가 coolsistema 라 멀쩡했고, 그 비대칭이 안 보였다.

실측: **DB 전체에서 coolsistema 가 못 닿는 관계는 이 시퀀스 하나뿐**이었다.

★ 마이그레이션에 **전체 시퀀스 검증 블록**을 넣었다 — 앞으로 시퀀스 권한을 빠뜨린
마이그레이션은 실패한다. (검사 CTE 는 `MATERIALIZED` 로 고정. 아니면 PG 가 `relkind`
필터보다 `has_sequence_privilege()` 를 먼저 평가해 `"Sellers" is not a sequence` 로
죽는다 — 실제로 죽었다.)

### 3. `pdfkit` default import (다섯 번째 껍질)

```
TypeError: pdfkit_1.default is not a constructor
```
`esModuleInterop` 이 없어 `import X from 'pdfkit'` 가 `pdfkit_1.default` 로 컴파일된다.
`allowSyntheticDefaultImports: true` 가 **타입 오류만** 지운다 — tsc·nest build 전부 통과.

★ **이 저장소에서 네 번째다.** 나머지 셋은 이미 고쳐져 있었고 **셋 다 주석까지 남겨 뒀는데**
네 번째가 또 들어왔다: `reports/reportsPdf.service.ts` · `afip/pdf/a4-generator.ts` ·
`lotes/cut-ticket-pdf.service.ts`.

**주석은 강제 지점이 아니다.** `scripts/verify-default-imports.js` 를 Dockerfile builder
단계에 넣었다(기존 `verify-models.js` 옆). dist 의 `X_1.default` 참조를 찾아 그 패키지를
**실제로 require** 해서 default 존재를 확인한다 — 문자열 패턴이 아니라 런타임 판정이라
새 패키지가 들어와도 안 뚫린다. 0.2초. 수정 전 dist 로 돌려 **실제 위반을 잡는 것까지 확인**했다.

### 4. Tarifas 매트릭스 — 미배정 칸도 편집 가능

`—` 는 "단가를 넣을 수 없다"가 아니라 **"아직 배정 행이 없다"** 였다. 그리고 서버의
`setRate` 는 배정 유무와 무관하게 `vendor_etapas` 행을 만든다 — **백엔드는 처음부터
됐고 UI 만 막고 있었다.** 없는 제약을 UI 가 발명한 셈이다.

세 상태의 시각적 구분은 유지한다(`—` / `Sin tarifa` / `$1,000`). 패널 상단에
"등록하면 자동으로 배정됩니다" 를 띄운다 — 함께 일어나는 일을 숨기지 않는다.

---

## Phase 85 실측 (E 절 채움)

| 항목 | 실측 | 판정 |
|---|---|---|
| `stocks` | **1,740행 / 536 kB** | ★ **W4 파티셔닝 보류** |
| 최대 테이블 | `role_function_actions` 3,645행 / **9 MB** | C-3 대상 선정이 틀렸다 |
| `TENANT_DERIVED_MODE` | `enforce` | ✅ A-1 종결 |
| `SHOP_DB_ISOLATED` | **미선언** → 공개몰 15→5 자동 축소 | ⚠️ |
| `cl_waiting` 7일 피크 | **1** (sv_active 최대 10 / pool 50) | 커넥션은 병목 아님 |

- **W4 착수 트리거를 수치로 못 박았다**: `stocks` 500만 행 / 5 GB / 주 50만 행 증가.
- C-3 의 "3억 행" 은 300매장 투영이고 현재와 **다섯 자릿수** 차이다.
- 권한 테이블이 매장 배수로 먼저 커진다(4매장 `role_functions` 11,790행 → 300매장 약 88만 행).
- ★ 이 표 전체가 **4매장 트래픽**이다. "여유가 있다"가 아니라 **"아직 아무도 안 쓴다"** 의 증거다.

---

## 화면에서 확인한 것 (cmux 브라우저)

로그인 세션이 살아 있어 로그인은 불필요했다. `cmux browser open <url>` →
`cmux browser --surface surface:N eval|click|screenshot`.

- **정산 목록** — 500 없이 표시(`findFiltered` 최상위 `storeId`)
- **초안 생성** — `Liquidación #4 · Isra test · 08-01~08-20 · 라인 1건 (6 × $1,500 = $9,000)`
  생성·영속. `store_id=6`, lines 트리거 통과.
- **상세** — 드로어 정상(`findByIdWithLines`)
- **`Confirmar`** — 사용자가 직접 눌러 `CONFIRMED` 전이 성공(201, 30ms)
- **PDF** — `200 / blob / 1,871 bytes`, 서버 로그 `PDF 완료 bytes=1871`
- **Tarifas** — `—` 셀 42개 전부 클릭 가능, `maria × corte` 패널에 안내 표시 확인

★ 브라우저 조작 요령: `.MuiDrawer-root` 는 **사이드바도 잡힌다** — 내용으로 걸러야 한다.
MUI Select 는 `.MuiSelect-select`, Autocomplete 는 `.MuiAutocomplete-popupIndicator`.
`<input type=date>` 는 native setter 로 값을 넣고 `input` 이벤트를 직접 발생시켜야 React 가 읽는다.

★ **드로어·모달은 닫힘을 기다린 뒤 다음 것을 연다.** 닫자마자 다음 칸을 누르면 MUI 가
전환 애니메이션 동안 **이전 패널을 그대로 마운트해 둔다** — 그 상태로 읽으면 이전 내용을
새 것으로 착각한다. 실제로 이것 때문에 정상 동작을 결함으로 한 번 잘못 보고했다.
`wait --function "!...some(d=>d.textContent.includes('제목'))"` 로 사라짐을 먼저 확인할 것.
**화면 검증도 같은 종류의 함정을 갖는다 — 무엇을 읽고 있는지 확인해야 한다.**

---

## ★ 운영에 남겨 둔 검증용 데이터 (지우지 말 것)

사용자 지시로 **그대로 둔다.** 지우자고 제안하지도 않는다.

| 무엇 | 어디 | 살아 있으면 생기는 영향 |
|---|---|---|
| `talleres_vendor_etapas` id=10 — `Isra test × lavadero` **$1** (2026-08-20~, 활성) | 운영 5434 | 그 공방·공정의 **다음 정산에 $1 이 실제로 적용**된다. 지금 lavadero 발송·수령이 없어 라인은 안 생긴다. |
| `talleres_settlements` id=4 — `Isra test` 08-01~08-20, **CONFIRMED**, net $9,000 | 운영 5434 | 외상 잔액 `TOTAL PENDIENTE` 에 $9,000 으로 잡힌다. CONFIRMED 라 그 기간 초안 재생성이 막힌다(INV-1). |
| `talleres_settlement_lines` id=1 — 정산 4, 6 × $1,500 | 운영 5434 | 위 정산의 근거 행. |
| `talleres_settlements` id=2 — `lee` 08-01~08-20, DRAFT, $0 | 운영 5434 | 어제 만든 것. 라인 0건. |

치우는 시점은 사용자가 정한다.

---

## 다음

1. **`cancel` / `markPaid` 미확인.** 셋 다 `lockSettlement` 을 지나므로 `confirm` 통과로
   실질 검증됐다고 보지만, 눌러 본 것은 아니다.
2. **`corte` 활성 기본단가 2개 정리** (ruth $1.000 / lee $2.000) — **영업 결정, 사용자 몫.**
   정리 전에는 Cost Sheet 가 `TALLER SIN ASIGNAR` 로 비운다.
3. **legacy `/talleres/liquidaciones` 화면**이 `subconOrder.vendor.name` 만 읽어 vendor 기반
   정산의 Taller 가 항상 `—` 다. 지금은 **모든 정산이 vendor 기반**이라 사실상 항상 비어 있다.
   한 줄 수정(`row.vendor?.name` 폴백)이면 되지만 이 화면 자체가 중복이라 정리 여부부터 결정할 것.
4. **`SHOP_DB_ISOLATED` 선언 여부 결정** — 지금은 "격리 안 된 것으로 치고 좁혀 놓은" 상태다.
5. **Trello 8건** 미조사(`#253 #257 #259 #262 #263 #265 #266 #271`).
   `x-client-route` 가 배포됐으니 재현만 하면 어느 화면의 어떤 API 인지 로그에 남는다.
6. Phase 85 는 **W1(캐시 봉인)부터.** 실측이 이 순서를 바꾸지 않았다.

### 알려진 미해결 (이월)
- ★ **D6 — QC `REWORK` 가 불량 수량을 이중 계상한다.** 손실 귀속까지 오염시킨다.
- **W5** 자재 원장 권위(`OPENING_BALANCE`) — `mes_materials` id 5,6,7,11,13,15,17
- **W7** `Acciones pendientes` 화면 통합
- `talleres_settlements` 의 **DRAFT 중복 방지 장치가 없다.** `generateForPeriod` 의 INV-1
  조회는 잠금이 없어 동시 요청에 중복 DRAFT 가 생길 수 있다(CODEX 지적). 부분 유니크
  인덱스로 막을 수 있으나 23505 를 처리하지 않으면 새 500 이 되므로 함께 해야 한다.
- `products.routing_template` 이 213개 중 1개만 채워져 있다.
- 형제 테이블 소프트삭제 UNIQUE 문제: `categories`(2) / `subcategories`(2) / `suppliers`(1) /
  `sizes` / `seasons` / `origins`. colors 에서 패턴 확정됨(재활성화 + 409 매핑 + 정규화).

---

## 작업 방식 — 이번에 걸린 것

- ★ **실행된 적 없는 코드는 검증된 적이 없다.** 앞을 고칠 때마다 다음 겹이 나온다.
- ★ **가려진 첫 오류는 PG 로그에.** 오늘도 두 번 다 그랬다(`permission denied for sequence`,
  그리고 어제의 `FOR UPDATE`). `logging_collector=off` 라 journalctl 엔 없다 —
  `/var/log/postgresql/postgresql-18-ventago18.log` 를 직접 본다.
- ★ **주석은 강제 지점이 아니다.** 같은 결함이 주석 셋을 지나 네 번째로 들어왔다.
  규약을 지키게 하려면 **위반하면 실패하는 자리**에 둔다(빌드 게이트 / DB 트리거 / 필수 인자).
- ★ **CODEX 지적도 대조한다.** `CREATE INDEX CONCURRENTLY` 가 "프로젝트 규약" 이라는 주장은
  **틀렸다**(309개 중 12개만 사용). [HIGH] 2건은 맞았고 그대로 반영했다.
- ★ **spec 은 변이 검사까지.** 가드를 빼면 3건 전부 실패하는 것을 확인했다 — 안 하면
  엉뚱한 가드로 통과하는 spec 이 된다.
