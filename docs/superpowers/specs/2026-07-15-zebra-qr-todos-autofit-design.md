# 설계: Zebra QR — 전체 SKU 검색 / 일괄 출력 / QR 확대

날짜: 2026-07-15
대상: `api-ventago/src/app/print/`, `zebra-agent/`
선행 설계: `docs/superpowers/specs/2026-07-09-zebra-qr-batch-delta-design.md` (Phase 38 — 델타 출력)

## 목표

사용자 요청 3건:

1. **(4)** QR 출력 대상을 "최근 변경분(델타)"만이 아니라 **전체 SKU 를 이름/SKU 로 검색**해서 고를 수 있게.
2. **(5)** **QR 코드 크기 확대.**
3. **(6)** **전체 SKU 를 1~2장씩 일괄 출력.**

## 배경 — 탐색 결과 (2026-07-15)

- **(4)와 (6)은 사실상 같은 변경이다.** `PrintService.getPendingQrDelta()` 는 이미 매장의 parent 상품 전체(limit 5000)를 읽어 in-memory 조인으로 NUEVO/CAMBIO/동일을 판정하고, **"동일"만 결과에서 버린다.** 버리지 않고 `IGUAL` 상태로 함께 반환하고 이름/SKU 필터를 붙이면 전체 검색과 일괄 출력이 동시에 풀린다. 신규 테이블·신규 WS 이벤트 불필요.
- **기존 `products:search` (`searchProductsForAgent`) 는 재사용 불가.** 바코드 탭 전용이며 `qrUrl`/`priceLabel`/`status` 를 만들지 않고, `isParent: false`(variant/단품)를 대상으로 한다. QR 라벨은 반대로 `isParent: true`(codigo madre) 가 대상이다.
- **QR 이 작은 진짜 원인은 `qrModule` 이 아니라 `splitRatio: 0.25` 다.** 50mm 라벨 = 400 dot(203dpi), 좌패널 = 100 dot. 딥링크 URL(≈50 byte)은 ECC Q 에서 QR version 5 = **37 모듈** → module 4 면 148 dot 로 **이미 좌패널 100 dot 를 넘겨 텍스트를 침범한다.** `qrModule` 만 올리면 침범이 심해질 뿐이다.
- 라벨 **높이(25mm = 200 dot)가 QR 크기의 실질 상한**이다. `floor((200-20)/37) = 4` → 현재 module 4 는 이미 높이 한계값이다. 자동맞춤만으로는 커지지 않는다.

## 확정 결정

| # | 결정 | 근거 |
|---|------|------|
| D-1 | QR 탭 = **`[Cambios | Todos]` 세그먼트 + 이름/SKU 검색칸** | 기존 델타 워크플로 보존(회귀 0) + 전체 검색 추가 |
| D-2 | 전체 모드는 **`IGUAL` 상태를 목록에 표시** | 이미 출력한 라벨도 재출력 가능해야 (6) 일괄 출력이 성립 |
| D-3 | 검색 필터는 **DB where 의 `iLike`** (인메모리 필터 아님) | 5000행 읽고 버리면 pool·메모리 낭비 |
| D-4 | QR 크기 = **자동맞춤 + 사용자 상한** (`#qr-module` = cap) | 바코드 `moduleWidth` 와 동일 패턴. SKU/URL 길이가 매장마다 달라 사용자 설정이 권위 |
| D-5 | **`splitRatio` 폐기** — QR 실측 폭에서 splitX 역산 | 두 값을 따로 두면 잘못된 조합에서 QR 이 텍스트를 덮음 |
| D-6 | QR 폭 **하드 캡 = region 의 55%** | 텍스트에 최소 45% 보장 → 침범 구조적 불가 |
| D-7 | **ECC Q → M** (`^FDQA,` → `^FDMA,`) | 50byte URL 이 v5(37모듈) → v4(33모듈). 같은 높이에서 module 4→5 = **약 25% 확대** |
| D-8 | 일괄 출력 = **상한 없음, 100건 초과 시 확인 배너** | 항목별 `sendZpl` 이라 부분 실패 안전은 이미 확보(D-11, Phase 38) |
| D-9 | URL 단축 / 라벨 높이 변경 **안 함** | 웹 리다이렉트 라우트 추가 + 구 라벨 호환 부담. 용지 교체 부담 |

### D-7 근거 — QR byte capacity (byte mode)

| version | 모듈 | ECC Q | ECC M |
|---|---|---|---|
| 3 | 29 | 32 | 42 |
| 4 | 33 | 46 | **62** |
| 5 | 37 | **60** | 84 |

URL `https://ventago.coolsistema.com/m/stock?s=9&p=12345` ≈ 50 byte
→ ECC Q: v5 = 37 모듈, `floor(180/37)` = module **4**
→ ECC M: v4 = 33 모듈, `floor(180/33)` = module **5** (+25%)

ECC M 은 복원력 25%→15%. 라벨 오염·접힘 자국에 약해진다. 매장 라벨은 실내 부착이라 수용.

## 컴포넌트 설계

### 1. 백엔드 — `print.service.ts`

`getPendingQrDelta(branchId, priceTypeId)` → `getQrItems(branchId, priceTypeId, opts)`:

```ts
async getQrItems(
  branchId: number,
  priceTypeId: number,
  opts?: { scope?: 'delta' | 'all'; q?: string },
): Promise<Array<{
  productId: number; code: string; name: string;
  price: number; priceLabel: string;
  status: 'NUEVO' | 'CAMBIO' | 'IGUAL';
  oldName?: string; oldPrice?: number; qrUrl: string;
}>>
```

- 기본 `scope='delta'` → **현행과 완전 동일한 결과** (IGUAL 제외). 회귀 0.
- `scope='all'` → 동일 항목을 `status:'IGUAL'` 로 push.
- `q` 가 2자 이상이면 상품 조회 where 에 추가:
  ```ts
  ...(q.length >= 2 ? { [Op.or]: [
    { sku:  { [Op.iLike]: `%${q}%` } },
    { name: { [Op.iLike]: `%${q}%` } },
  ] } : {}),
  ```
  2자 미만은 필터 없음(전체) — `searchProductsForAgent` 의 "2자 미만 = 빈 배열" 과 의미가 다르다. 여기서는 검색칸이 선택 사항이고 비우면 전체가 정상 동작이기 때문.
- 쿼리 수 불변(Branch 1 + products 1 + prices 1 + qr_log 1 + priceType 1 = 5 SELECT), N+1 없음, limit 5000 유지.
- 기존 이름 `getPendingQrDelta` 는 남기지 않는다. 호출자는 게이트웨이 1곳뿐 — 확인 후 전량 치환.

### 2. 백엔드 — `print.gateway.ts`

```ts
@SubscribeMessage('get_qr_pending')
async handleGetQrPending(client, payload: { priceTypeId?: number; scope?: string; q?: string })
```

- `branchId = client.data?.branchId` — **payload 의 branch/store 는 계속 무시** (D-6, IDOR 안전 불변).
- `scope` 는 `'all'` 일 때만 all, 그 외 전부 `'delta'` (화이트리스트). 구 에이전트가 `scope` 미전송 → `delta` → 하위호환.
- `q` 는 `String(payload?.q || '').trim()`, 200자 초과 절단.

### 3. zebra-agent — `src/zpl-formatter.js`

신규 순수 함수 (export):

```js
const QR_ECC_M_CAPACITY = [ /* [version, modules, maxBytes] */
  [1,21,14],[2,25,26],[3,29,42],[4,33,62],[5,37,84],
  [6,41,106],[7,45,122],[8,49,152],[9,53,180],[10,57,213],
];

// URL byte 길이 → QR 모듈 수 (ECC M). 용량 초과(213byte 초과) → 최대치 57 반환.
function qrModuleCount(byteLen) { ... }

// 사용자 상한(cap) + 높이/폭 제약에서 실효 magnification 산출.
function effectiveQrModule(qrUrl, cap, heightDots, regionDots) {
  const modules = qrModuleCount(utf8Len(qrUrl));
  const capped  = Math.max(1, Math.min(MAX_QR_MODULE, cap || 6));
  const byHeight = Math.floor((heightDots - 2 * MARGIN) / modules);
  const byWidth  = Math.floor((regionDots * QR_WIDTH_CAP - MARGIN) / modules);
  return Math.max(1, Math.min(capped, byHeight, byWidth));
}
```

상수: `MARGIN = 10`, `GAP = 12`, `QR_WIDTH_CAP = 0.55`, `MAX_QR_MODULE = 10`.

`utf8Len` 은 `TextEncoder` 기반으로 구현한다 — `Buffer` 는 renderer(브라우저 컨텍스트)에 없고, 프리뷰가 같은 함수를 써야 실물과 어긋나지 않는다.

`renderQrBlock` 변경:
- `splitRatio` 인자 제거. `qrModule` 은 cap 으로 받아 `effectiveQrModule` 로 실효값 산출.
- **좌표 정의 (기존 splitX 의 gap 이중계상 제거):**
  - QR 우측 끝 `qrRight = MARGIN + modules * module`
  - 텍스트 시작 `textX = qrRight + GAP`
  - 텍스트 폭 `availW = region - textX - MARGIN`
  - 50x25 실측: modules 33, module 5 → qrRight 175, textX 187, availW 203 (텍스트 ≈ 50%)
- `^BQN,2,${module}^FDMA,${sanitize(qrUrl)}^FS` — **ECC Q→M**.

`formatQrLabel` 기본값: `qrModule: 4 → 6` (상한이므로 올려도 높이 제약이 실제값을 결정), `splitRatio` 제거.

**알려진 수용 사항 — quiet zone.** ZPL `^BQ` 는 quiet zone 을 자동 추가하지 않는다. `MARGIN = 10` dot 은 module 5 기준 **2 모듈**로, QR 규격 권장(4 모듈)에 못 미친다. 현행(module 4 → 2.5 모듈)도 동일 조건이며 실제 스캔이 동작 중이므로 변경하지 않는다. **UAT 에서 스캔 실패가 나오면 `MARGIN` 을 `4 * module` 로 올리는 것이 1차 대응**이며, 이 경우 QR 은 다시 module 4 로 내려간다(확대 효과 상쇄).

### 4. zebra-agent — `main.js`

- `ipcMain.handle('qr:fetchPending', (_e, priceTypeId))` → `('qr:fetch', (_e, { priceTypeId, scope, q }))`
- `emitWithAck('get_qr_pending', { priceTypeId, scope, q })`, timeout 10000 유지.
- `qr:print` 는 변경 없음 — layout 에서 `splitRatio` 만 자연 소멸.

### 5. zebra-agent — `preload.js`

`qrFetchPending: (priceTypeId) => ...` → `qrFetch: (args) => ipcRenderer.invoke('qr:fetch', args)`

### 6. zebra-agent — `renderer/index.html`

- `#qr-buscar` 라벨 `Buscar cambios` → `Buscar`. 왼쪽에 세그먼트 `[ Cambios | Todos ]` (`#qr-scope-delta` / `#qr-scope-all`, 기본 Cambios), 그 옆 검색 input `#qr-query` (placeholder `nombre / SKU`).
- 검색칸은 **Todos 모드에서만 활성** (Cambios 모드에서는 disabled — 델타는 전량 검토가 목적).
- Estado 칩: `NUEVO`(green) / `CAMBIO`(gold) / **`IGUAL`(muted)** 추가.
- `#qr-module` — label `Tamaño QR (máx)`, `max` 4 → **10**, 기본 6, tooltip `El alto de la etiqueta puede reducirlo automáticamente`.
- **`#qr-split-ratio` 입력 제거** + `QR_DEFAULT_LAYOUT`/`readQrLayout` 에서 삭제.
- 프리뷰(`renderQrPreview`): `splitRatio * 100` 대신 `qrModuleCount`/`effectiveQrModule` 과 **동일한 계산**으로 `qrRight`/`textX` 를 산출해 반영. 프리뷰와 실물이 어긋나면 안 된다. renderer 는 `zpl-formatter.js` 를 import 할 수 없으므로(현행 preview 도 `drawBarcode` 로직을 미러링 중) 같은 상수·공식을 복제하되, **테스트가 두 구현의 일치를 검증**한다: `qr-label.test.js` 에 실측 케이스(50byte/cap 6 → module 5, qrRight 175, textX 187)를 두고 renderer 쪽 상수는 코드 리뷰로 대조.
- 출력 전 확인: 선택 N > 100 이면 배너 `⚠ N etiquetas seleccionadas (doble = 2N). ¿Imprimir todo?` + `[Cancelar] [Imprimir]`. 100 이하는 현행처럼 바로 출력.

## 데이터 흐름

```
renderer  [Todos] + q="camisa" + priceType
  → qrFetch({ priceTypeId, scope:'all', q:'camisa' })
  → main.js emitWithAck('get_qr_pending', {...})
  → gateway: branchId = client.data.branchId (payload 무시)
  → service.getQrItems(branchId, priceTypeId, { scope:'all', q:'camisa' })
      products where storeId + isParent + active + (sku|name iLike %camisa%)
      + prices + qr_print_log + priceType  → in-memory 조인
  → items[{ status: NUEVO|CAMBIO|IGUAL, qrUrl, ... }]
  → 테이블 렌더 → 전체 선택 → (N>100 확인) → qrPrint({items, layout, mode})
  → 항목별 formatQrLabel → sendZpl → 성공분만 mark_qr_printed
```

## 에러 핸들링

- 기존 인라인 배너(`#qr-status`) 재사용. 검색 0건 → `Sin resultados para "<q>"`.
- 미연결/타임아웃/`PRICE_TYPE_REQUIRED` → 현행 메시지 유지.
- `qrModuleCount` 용량 초과(URL 213byte 초과) → 최대 57 모듈 반환 → `effectiveQrModule` 이 module 1 로 수렴. 딥링크가 이 길이에 도달할 수 없으므로 방어용.

## 테스트 전략

**`zebra-agent/test/qr-label.test.js` (Jest, 순수 함수)**
- `qrModuleCount`: 경계값 (14/15, 62/63, 213/214) → 21/25, 33/37, 57
- `effectiveQrModule`: 높이 제약이 cap 을 이길 때 / 폭 55% 캡이 이길 때 / cap 이 이길 때
- ECC: 생성 ZPL 이 `^FDMA,` 를 포함하고 `^FDQA,` 를 포함하지 않음
- splitX 역산: QR 우측 끝 < 텍스트 `^FO` x좌표 (침범 불가 회귀 테스트)
- 50x25 실측: URL 50byte + cap 6 → module **5** (Q 시절 4에서 확대됨)

**`api-ventago` service 유닛**
- `scope` 미지정 = 기존 델타 결과와 동일 (IGUAL 없음) — **회귀 가드**
- `scope:'all'` → IGUAL 포함, 개수 = 전체 parent 수
- `q` 2자 이상 → where 에 `Op.or(sku,name)` 포함 / 1자 → 필터 없음
- gateway: `payload.scope='../../'` 같은 임의값 → `delta` 로 폴백

**수동 UAT (Electron)** — 자동화 불가:
1. Todos + 검색 → 목록에 IGUAL 표시
2. 전체 선택 → 100 초과 확인 배너 → 출력
3. **실물 라벨 QR 스캔 성공 확인** (ECC M + quiet zone 2모듈 검증 — 이 설계의 최대 리스크)
4. 프리뷰와 실물 레이아웃 일치

## 범위 외 (YAGNI)

- 딥링크 URL 단축 및 웹 리다이렉트 라우트 (D-9)
- 라벨 용지 높이 변경 (D-9)
- `qr_print_log` 스키마 변경 — **없음.** IGUAL 재출력 시 `markQrPrinted` 가 동일 값을 upsert → 무해
- 바코드 탭(`products:search`) 변경 없음
- 검색 결과 페이지네이션 (limit 5000 로 충분)

## 의존성

- 백엔드 배포 = **Jenkins 수동** (`api-new-coolsistema`). git push 자동배포 없음.
- zebra-agent = 태그 push → GitHub Actions `build-zebra-agent.yml`.
- **배포 순서 무관** — 구 에이전트는 `scope` 미전송 → 서버가 `delta` 폴백. 신 에이전트 + 구 서버는 `scope` 를 무시당해 Todos 가 델타처럼 동작(오작동 아님, 기능 미노출).

## 마이그레이션/배포 노트

- **DB 마이그레이션 없음.** 로컬/운영 스키마 변경 0.
- 사용자 기존 `labelLayouts` 에 남은 `splitRatio` 값은 읽히지 않고 방치된다(무해). 별도 정리 마이그레이션 없음.
