# 73 후속 3 — POS/상품 화면 수정 + 하루 한마디 완료 (새 세션용)

앞선 문서: `73-NEXT.md`, `73-NEXT-2.md`. 이 문서는 2026-08-06 밤 ~ 08-07 새벽 작업분.

---

## 0. 먼저 읽을 것

- jest: `NODE_OPTIONS=--max-old-space-size=2048 npx jest --maxWorkers=1 --workerIdleMemoryLimit=800MB`
- 마이그레이션은 로컬 5432 + 운영 5434 **양쪽** 적용. `./.planning/intel/db-schema.regen.sh` 로 레퍼런스 갱신.
- ssh-agent 가 비면 운영 서버 접속이 끊긴다 → `ssh-add --apple-load-keychain`. push 는 HTTPS 로 우회 가능.
- ~~GitHub Actions major_outage~~ → **정정(2026-08-07)**: Actions 는 operational 이다.
  08-05 이후 실행이 없던 건 장애가 아니라 **태그를 안 밀어서**였다. print-agent v1.2.1 은
  정상 빌드·배포됐다(§7). jest CI 도 막혀 있지 않으니 실제로 돌려보고 판단할 것.

---

## 1. ✅ 해결됨 (2026-08-07 오후, commit `cb28007`, api #634 SUCCESS)

**증상이었던 것**: `Nuevos productos` 에서 1 → 3 으로 고치고 `Modificar` 를 눌러도
화면과 `Historial del día` 가 계속 **1**. 원장은 3 으로 정확했다.

**실제 원인은 더 넓었다** — "그날 입고" 정의가 **7곳**에 복제돼 있었다.
정본 뷰 `v_product_branch_daily_ingreso.net` 이 `note LIKE 'anulacion ingreso%'` 만
반영하고 정정 행(`correccion ingreso%`)을 빼먹은 것이 뿌리.

★ 읽기(`inventory-by-date*`)와 쓰기 기준선(`correctTodayStocks`)이 **같은 틀린 식을 공유**해
자기일관적으로 틀렸다. 두 곳이 똑같이 틀리면 서로 검증이 안 되므로 조용하다.
사용자가 3 을 다시 넣으면 기준선이 또 1 이라 재고가 5 가 됐다.

**고친 것 (전부 배포 완료)**

DB — 로컬 5432 + 운영 5434 양쪽 적용, `migrations/2026-08-07-daily-ingreso-include-correccion.sql`
- canonical `net` 에 `correccion ingreso%` 를 signed 로 추가
- `v_stock_dia` 가 같은 식을 복제하던 것을 정본 뷰 JOIN 으로 교체.
  `store_id/branch_id` 는 stocks 비정규화 컬럼 대신 `ProductBranch→branches` 에서 끌어와
  (pb,날짜) 1:1 을 구조적으로 보장한다 (그룹 분할 시 net 이중 계상 방지)
- `CREATE OR REPLACE` 라 의존 뷰 `v_stock_sucursal_variante` 무영향

앱 — `productStock.service.ts`
- `getDailyIngresoByPb()` / `lockProductBranches()` 공용 헬퍼. **여기 말고 다른 데서 재계산 금지**
- 읽기 2곳 + `correctTodayStocks` 기준선 + `editMadreVariants` ①② 가 전부 정본 net 사용
- `editMadreVariants` 는 트랜잭션이 **아예 없었다** → 하나로 묶음
- 정정·취소 경로에 `ProductBranch ... ORDER BY id FOR UPDATE` 추가

보안(선재 결함, 같이 고침)
- `editMadreVariants` 가 body 의 `branchIds`/`variantId` 를 전혀 검증하지 않아
  자기 매장 부모 하나만 알면 **타 매장 variant·지점의 재고를 쓸 수 있었다**.
  형제 엔드포인트 `correctTodayStocks` 가 Phase 69-03 에 막은 가드를 그대로 적용.

**검증**: 운영 net pb274=3 / pb275=4 / pb255=81(변형309 — 기존 오답 80), drift=0, leak=0.
정의 변경으로 값이 바뀐 그룹 3개(전부 당일 UAT 테스트 제품). 새 정의에서 net<0 그룹 4개 =
현행과 동일 → **취소 멱등성 회귀 없음**. 회귀 테스트 11건 추가, products+stocks 146 green.
컨테이너 재생성 + healthy 확인.

★ 이 과정에 CODEX 자문을 받았다. CODEX 가 짚어 실제로 고친 것: `v_stock_dia` 복제,
신규 PB 가 락에서 빠지는 구멍, `editMadreVariants` IDOR. **반증된 지적도 있었다** —
"음수 `type NULL` 행 397건이 구 정정 코드의 잔재"라는 주장은 틀렸다. 그건
`sales-create.service.ts:1274` 가 판매 차감을 type 없이 음수로 기록하는 것이고,
입고 집계에서 빠지는 게 정확하다. **외부 지적은 근거까지 대조할 것.**

---

## 2. 오늘 배포된 것 (front #544~#560, api #626~#627 — 전부 SUCCESS + 컨테이너 재생성 확인)

### 2-A. 로그인 하루 한마디 (73-18) — 완료
- 격언 **3,456행** 적재. 로컬 5432 + 운영 5434 양쪽. `migrations/2026-08-06-daily-quotes-seed-full.sql`
  - 성경 1,000 × 3언어 (es=RV1909 / en=KJV / ko=개역성경 — 전부 퍼블릭 도메인)
  - 철학 152 × 3언어 (고전 저자, **직접 번역** — `translation='Traducción propia'`)
  - **세 언어가 같은 절을 같은 seq 로** 갖는다 → 언어를 바꿔도 그 날 문구가 같다
- 기본값 `philosophical` (2026-08-06 결정). 운영 8개 매장 승급, coolsistema 는 `biblical` 유지.
- Preferencias › **Pantalla de ingreso** 탭에서 출처·언어 변경 + 오늘 문구 미리보기.

★ **`daily_quotes` 행을 지우거나 `is_active=false` 로 끄면 seq 에 구멍이 나 그 날 격언이 안 나온다.**
재부여 SQL 은 마이그레이션 파일 주석에 있다.

★ 설정은 **그 단말의 다음 로그인부터** 반영된다(로그인 화면은 인증 전이라 매장을 서버에 못 묻는다.
로그인 후 받은 설정을 localStorage `ventago.frasePref` 에 적어두는 구조 — `utils/frase-pref.ts`).

### 2-B. 버그 수정 — 전부 같은 유형이었다
> **"작업 대상을 두 곳이 따로 들고 있으면 언젠가 갈라진다."** 오늘 이 유형으로 4건이 나왔다.

| 증상 | 원인 | 수정 |
|---|---|---|
| Códigos madres 의 `Precio base` 가 2번째 가격 레벨을 표시 | 기본가는 `products.price` 인데 `prices` 배열만 뒤지다 실패 시 `prices[0]` 으로 폴백 | `row.price` 1순위. **`prices[0]` 폴백 제거** — 못 찾으면 `—` |
| POS 카트에서 3번째 줄을 골라도 1번째 줄 수량이 바뀜 | `activeParentId`(제품 id)로 찾아 `findIndex` 가 늘 첫 줄 반환 | `activeRowIndex`(줄 index) 도입. 색칠·편집이 같은 값을 쓴다 |
| Nuevos productos 에서 옛 제품으로 저장됨 | `product` vs `editingMadre` 두 출처, 저장은 `editingMadre` 우선 | 우측 목록 선택 시 `editingMadre` 해제 |
| 정정 시 403 "La variante no pertenece a este código madre" | `originalStocks` 가 제품 전환 후에도 남아 남의 variant.id 매칭 | 전환 시 초기화 + 각 행에 `parentId` 각인 + `handleEdit` 에서 검증 |

마지막 건은 **내가 만든 회귀**였다(저장 후 폼 유지로 바꾸면서 드러남).

### 2-C. 저장 후 폼 유지 (2026-08-07 사용자 결정)
저장 경로가 4개인데 그중 3개를 "다른 제품을 고를 때까지 유지"로 통일했다:

| 경로 | 동작 |
|---|---|
| `doSubmit` (기존 제품에 재고 추가) | **유지** |
| `doEdit` (정정) | **유지** |
| `handleMadreSave` (좌측 패널 변형 편집) | **유지** |
| 신규 제품 생성 | **비움** — Trello diACgk5B 유지. 되돌리지 말 것 |

★ 유지하면 **한 번 더 누를 때 중복 가산 위험**이 생긴다. 그래서 저장 직후
`reloadStocksAfterSave()` 가 서버에서 다시 읽어 `mode` 를 `edit` 으로 올린다. 이게 핵심이다.

### 2-D. UI
- 사이드바 그룹 클릭 시 바로 이동 (`menuRegistry.ts` 의 `defaultPath`). `directPath` 와 다르다 —
  `directPath` 는 부메뉴를 없앤다.
- 선택 행 색: codigo madre 노랑(`#FFF3C4`), POS 손님/카트 크림(`#FFF8E1`) + 골드 좌측 바.
  ★ AG Grid 는 행 스타일을 캐시한다 → 콜백 변경 시 `redrawRows()` 명시 호출 필요.
- POS 목록 3개(카트/고객/보류) 행·헤더 높이 **30 통일**.
- `Tallas y Colores` 재고 표시를 입력칸 **왼쪽**으로 (행 높이 절감). 지점 3개 이상 매장은
  라벨이 길어져 가로 스크롤이 생길 수 있다 — 실사용 확인 필요.
- 이름 없는 신규 제품 생성 차단 (운영 사고 대응, 아래 §3).

---

## 3. 처리 완료 — 운영 사고 데이터

2026-08-07 02:51 에 이름이 빈 제품이 생성됐다(`Producto "[ABRIGOS] " creado`, id=335 sku=263703,
지점16 재고 20). 원인은 저장 후 폼이 비워진 걸 모르고 지점만 바꿔 다시 저장한 것.

- 재발 방지: 이름 없으면 생성 차단 + color/talle 표 위에 현재 대상 **상시 표시**
  (제품 있으면 초록 이름표, 없으면 주황 "Ningún producto cargado")
- 데이터: 335/336 및 딸린 행 전부 삭제 완료(2026-08-07). 참조 13개 테이블 0행 확인 후 진행.
  `stocks` 는 append-only 라 `SET LOCAL ventago.stocks_maintenance = 'on'` 으로 우회.
  삭제 후 `v_stock_balance_drift` = 0, `v_stock_tenant_leak` = 0 확인.

---

## 4. 브라우저 실제 검증 결과 (2026-08-07, 운영)

**통과**:
- 한 지점에 1개 저장 → 다른 지점으로 바로 전환 → 2개 저장 → **같은 제품에 들어감**(새 제품 안 생김)
- 이어서 지점A 1→3 정정 → 지점B 2→4 정정 → **403 없이 각 지점 기준선으로 정확히 적용**
- 저장 후 제품 유지, 지점 전환 시 그 지점 수량으로 갱신, 버튼 `Guardar`↔`Modificar` 자동 전환
- 변경 없이 저장 → 원장에 아무것도 안 쓰임(중복 가산 없음)
- Precio base $22.000, 선택 행 강조 1줄만, 카트에서 방금 추가한 줄이 선택됨

**미검증**:
- 같은 제품이 카트에 **두 줄**인 경우(가격 종류 변경에 관리자 인증이 필요해 재현 못 함).
  메커니즘(`activeRowIndex`)은 공유하므로 통과 가능성이 높지만 확인은 안 됐다.
- 로그인 격언 화면(로그아웃이 필요해 안 했다)

**남긴 테스트 데이터**: 제품 **263702 (ZZ TEST UAT 7007)** 오늘 입고 지점6=3, 지점16=4.
테스트 제품이라 방치해도 무해. 정리하려면 0으로 정정.

---

## 5. 이월 — 계속 막혀 있는 것

- **§1 결제수단 % 실사용 확인**: 운영에서 판매 한 건으로 Recargo 가 판매상세·영수증에 찍히고
  상태가 Pagado 인지. 사람이 해야 한다.
- ~~**§2 print-agent 릴리스**~~ → ✅ **v1.2.1 배포 완료 (2026-08-07)**. 아래 §7 참조.
- **§4 jest CI**: `gh workflow run api-tests.yml --repo jhkim1010/api-ventago --ref main`
  초록 확인 전까지 완료로 적지 말 것.
- **package-lock 불일치**: `npm ci` 불가, `npm install` 사용(Dockerfile 과 동일).
- **0원 식당 판매 3건** (매장 11 "Asado"): 의도적 미보정.

---

## 6. §1 수정에서 남긴 것 (급하지 않음)

- **`todayHasEntries` 의 의미가 바뀌었다**: `size>0` → `net>0 인 variant 존재`.
  입고가 전부 취소된 날은 이제 `add` 모드가 된다(구 동작은 취소된 원본 수량을 기준선으로
  삼아 net 을 음수로 만들었다 — 새 동작이 맞다). 이름이 실제 의미와 어긋나므로
  언젠가 `hasPositiveNetIngreso` 류로 바꾸는 게 낫다. 지금 바꾸면 프론트 동시 수정 필요.
- **음수 net 을 화면에 클램프 없이 노출한다.** 일부러 그렇게 뒀다 — 클램프하면 화면과
  쓰기 기준선이 또 갈라진다(이번 결함의 원인). 다만 입력칸에 회색 음수가 뜨는 UX 는 약하다.
  경고 표시를 붙이는 게 낫다. 운영에 net<0 그룹 4개 존재(수정 전과 동일, 신규 아님).
- **판매 차감이 `type=NULL` 음수로 기록된다** (`sales-create.service.ts:1274`).
  온라인 주문 경로는 `type='sale'` 을 쓰는데 POS 판매는 안 쓴다 — 라벨링이 갈라져 있다.
  집계 결과는 지금 맞지만(음수는 `ingreso` 필터에서 빠짐) 리포트에서 판매를 type 으로
  구분하려 하면 걸린다. 원장 전체를 건드리는 일이라 별도 작업으로.
- **note 접두어 기반 식별의 한계**: `anulacion ingreso` / `correccion ingreso` 문자열이
  SQL(뷰)과 TS(상수) 양쪽에 있다. `trg_stocks_immutable` 때문에 과거 행 재분류가 불가능해
  현재는 이게 유일한 소급 호환 식별자다. 신규 행부터 구조화 컬럼(`adjustment_kind`)을
  쓰고 과거만 접두어로 보는 방식이 장기 해법.

---

## 7. ✅ print-agent v1.2.1 배포 (2026-08-07)

선물/교환 티켓(`hidePrices`)이 **코드에는 있었는데 아무에게도 도달하지 않고 있었다.**
배선은 처음부터 정상이었다 — 문제는 릴리스가 두 겹으로 어긋난 것이었다.

| 계층 | 상태(수정 전) |
|---|---|
| `print-agent/src/formatter.js` | ✅ 구현돼 있었음 |
| `ProductList.tsx` `sendTempTicket(hidePrices)` | ✅ 전송하고 있었음 |
| `POST /print/temp` | ✅ `{...body}` 로 그대로 통과 (그래서 api-ventago 에 `hidePrices` 참조가 없는 게 정상) |
| **릴리스 바이너리** | ❌ 기능 없음 |
| **다운로드 페이지** | ❌ 더 오래된 걸 가리킴 |

**어긋난 두 지점**

1. 태그 `print-agent-v1.1.1` = 2026-07-29 14:39, `hidePrices` 커밋 `ed0734a` = 2026-08-06 17:49.
   → **태그가 기능보다 8일 앞서** 빌드된 바이너리에 기능이 없었다.
   (태그 시점 `formatter.js` 의 `hidePrices` 출현 = 0, 현재 = 5)
2. 다운로드 페이지 `releaseTag` 가 `print-agent-v1.0.8` 고정.
   → v1.1.1 을 빌드해도 사용자는 v1.0.8 을 받았다. v1.0.8 은 `hidePrices` 뿐 아니라
   **69-02 레거시 CLI handshake API Key 인증**(`799216c`)도 없다.

**핸드오프 §5 정정**: "GH Actions 장애로 빌드 불가" 는 더 이상 사실이 아니다.
Actions 는 operational 이었고, 08-05 이후 실행이 없던 건 장애가 아니라 **태그를 안 밀어서**였다.

**한 일**
- `print-agent/package.json` 1.1.0 → **1.2.1** (태그와 어긋난 채 방치돼 있었음)
- 태그 `print-agent-v1.2.1` push → GH Actions 빌드 SUCCESS
  → `jhkim1010/ventago-downloads` 에 exe / arm64.dmg / x64.dmg 3종 발행
- 다운로드 페이지 `releaseTag`·`releaseBase` → v1.2.1 (front #561 SUCCESS, 컨테이너 재생성)

**함께 나간 미출시분 3건**: `ed0734a` 선물 티켓 / `ab0bd2e` 호스트 참조 정정 /
`799216c` 레거시 CLI handshake API Key 인증(69-02)

**검증**
- 자산 3종 URL 전부 200
- `git show print-agent-v1.2.1:print-agent/src/formatter.js | grep -c hidePrices` = 5
- 운영 페이지가 `print-agent-v1.2.1` 을 내보냄 (app.coolsistema.com 확인)
- **자동 업데이트 피드** `print-agent-latest/latest.yml` = `version: 1.2.1` →
  기존 Windows 에이전트는 electron-updater 로 **자동 갱신**된다(재설치 불필요)

★ **다음에 print-agent 를 고치면 반드시 태그를 새로 밀 것.** CI 는 태그 시점 코드를
빌드하므로, 기존 태그를 재사용하거나 커밋 후 태그를 안 밀면 조용히 구버전이 나간다.
그리고 **다운로드 페이지 `releaseTag` 갱신을 빼먹지 말 것** — 빌드해도 아무도 못 받는다.

**미검증**: 실제 프린터로 선물 티켓을 뽑아 가격이 빠지는지는 사람이 확인해야 한다.
macOS 는 자동 업데이트 피드가 없어(Windows 전용 latest.yml) 수동 재설치가 필요하다.
