# 핸드오프 2026-09-23 (오후) — 가격 계약 · ESC · 다음은 티켓 통일

다음 세션은 **§1(티켓 통일)** 부터 시작한다. 사용자가 그렇게 지시했다.
§2~§4 는 배포까지 끝났고, §5 가 남은 일이다.

---

## 1. ★ 다음 작업 — 티켓 출력 두 종류를 통일한다 (사용자 지시, 미착수)

사용자 지시(사진 2장과 함께):
> 「매장 이름이 나오면서 출력하는 내용이 달라.. 이건 통일해 줘야 해.
>  **매장 이름은 나오지 말게 해줘. 절대로..**
>  날자와 시각이 나오는거 아주 좋아. **F2 를 눌렀을 때도 그렇게 출력**되게 해줘.」

### 사용자가 보여 준 두 티켓 (store 19 NOIX 에서 실물 출력)

| | F2 출력 | 「티켓 다시 출력」 |
|---|---|---|
| 머리 | `Venta # 6 — 23/09/2026 12:21:29` **한 줄** | `DOCUMENTO NO VÁLIDO COMO FACTURA` → **`NOIX`** → `MORON 3258` → `CUIT: 20337391916` → `Copia (1) : # Ticket-000006` |
| 날짜·시각 | 머리줄에 **인라인** | **`Fecha` / `Hora` 라벨 행** ← 사용자가 이 형태를 원한다 |
| 그 밖 | Vendedor · Cliente | Fecha · Hora · Vendedor · Cliente |
| 꼬리 | `¡Gracias por su compra!` + `Conserve este comprobante` | `★ ¡Gracias x elegirnos! ★` + `Cambios solo por falla de fábrica · Lun-Vie` |

### 내가 찾아 둔 것 (여기서 이어받으면 된다)

**둘은 서로 다른 함수다** — `print-agent/src/formatter.js`

| 티켓 | 함수 | 호출부 |
|---|---|---|
| F2 | `formatTempTicketHtml` (**:838**) | `src/index.js:78` |
| 다시 출력 | `formatInvoiceHtml` (**:325**) | `src/print-pipeline.js:37` |

- 꼬리 문구: temp 쪽 **:1194·:1199** / invoice 쪽 **:420**
- **매장 이름·주소·CUIT 가 나오는 자리 — 정확히 네 줄**
  · HTML: `formatter.js:694`(주소) · `:696`(CUIT) — 이름은 그 위 `store-name`
  · 텍스트/ESC-POS(`formatInvoice`, :798): **:805**(주소) · **:806**(CUIT)
  ⤷ `data.store { name, address, cuit, phone? }` 가 입력이다(:186 주석).
- `formatInvoice`(:798)는 **텍스트 폴백 경로**다. HTML 만 고치면 이쪽이 남는다.

### ★★ 손대기 전에 반드시 할 것

1. **인쇄 경로를 전수로 센다.** 메모리 `sale-creation-has-two-unattended-print-paths`:
   「판매 생성엔 무인 인쇄 경로가 **둘**이다 — `printTicket` 만 막으면 **AFIP 자동 발급
   출력**이 남는다.」 ⤷ 통일 대상이 2개가 아니라 **3개 이상**일 수 있다. 먼저 세라.
2. **「중복 인쇄는 결단코 금지」**(상시 지시). 경로를 합치다 같은 티켓이 두 번 나가면 안 된다.
   모호하면 안 보낸다.
3. **print-agent 는 Electron 앱**이다. api·app 처럼 push 하면 끝이 아니라
   **태그 push → GitHub Actions 빌드 → 사용자가 재설치**해야 반영된다(`push-both.sh` 가
   태그를 자동 증가시킨다). 배포 경로가 다르다는 것을 사용자에게 먼저 알릴 것.
4. 스모크 시험이 문구를 고정하고 있다 — `print-agent/test/offline-ticket.smoke.js:25` 가
   `'NO FISCAL — DOCUMENTO NO VÁLIDO COMO FACTURA'` 를 단언한다. 문구를 바꾸면 같이 고친다.
5. `api-ventago/src/app/print/footer-callsites.spec.ts:18` 이 `['Gracias por su compra',
   '@mitienda']` 를 본다 — 꼬리 문구를 통일하면 이 spec 도 대상이다.

★ **매장 이름을 지우는 것이 「빈 줄을 남기는 것」이 되지 않게 할 것.** 열감지 프린터는
  종이를 먹는다. 줄을 지우면 그만큼 레이아웃이 위로 올라오는지 실제 출력으로 확인해야 한다.

---

## 2. 배포 완료 — 가격 계약 1·2단계

근거: `.planning/PLAN-2026-09-23-precio1-como-precio-base.md` (codex 자문 반영)

**사용자가 보고한 증상**: store 19 에서 「productos nuevos 에서 제품을 새로 생성할 때
precio base 가 안 보인다」.

**원인**: `precio1` 이 **두 군데에 저장**된다 —
`code-import.service.ts:857` 이 `products.price` 에, `:982` 가 `prices(PRECIO 1)` 행에.
그 중복을 프론트가 흡수하면서(`price-types.ts:12`) **「Precio base」 라벨을 `PRECIO 1` 로
덮어썼다.** 박스가 사라진 게 아니라 **제목이 바뀐 것**이었다.

| 커밋 | 내용 | Jenkins |
|---|---|---|
| api `05941848` | 기준가의 원천을 `products.price` 하나로 (`menu-price.util.ts`) | #938 SUCCESS |
| app `0ec2d3b` | 식당 `pickMenuPrice` 도 같은 규칙으로 (**짝**) | #774 SUCCESS |
| app `22007f2` | 「Precio base」 라벨 고정 + 이름 판정 좁힘 | 〃 |

★ **codex 가 1건 짚었는데 세어 보니 5개 파일**이었다(계획서 §5-bis 에 표).
  그중 **POS 판매 화면**(`ProductsInputs.tsx`)이 자체 복사본으로 `/precio/i` 를 쓰고 있었고
  주석은 「백엔드와 동일」이라 적혀 있었다 → 공용 헬퍼 import 로 통합.
  ⏳ **보류**: CodigoVistaView `:480`(정렬)·`:712`(그 정렬에 기댄 baseIdx)·`:1425`,
  BranchPriceTypesCard `:80·81·240`. 정렬과 인덱스가 **짝이라 함께 옮겨야** 하고,
  판정만 좁히면 CodigoVista 열 순서가 바뀐다. **화면을 열어 재기 전에는 건드리지 말 것.**

★ 실측으로 안전을 확인했다: 식당 기능을 쓰는 매장은 **10·11 둘뿐**이고 그 둘은
  `prices` 행이 0개라 이미 `products.price` 로 떨어진다. 값 변화 없음.

---

## 3. 배포 완료 — ESC 확인 창 (app `c9726da`, front #774)

사용자 보고: 「판매 중 ESC 를 누르면 그냥 아무 말 없이 다 지워버린다.」

★ **확인 장치는 이미 있었고 배포도 돼 있었다**(`69e0912`, 2026-09-22).
  원인은 판정이 아니라 **낡은 클로저**였다:

  `react-hotkeys-hook@5` 의 `dist/index.js`
  ```js
  const u = <deps>, l = useCallback(r, u ?? []), f = useRef(l);
  u ? f.current = l : f.current = r;   // deps 주면 굳고, 안 주면 매 렌더 갱신
  ```
  ESC 핸들러가 `[suspendedSaleId]` 만 deps 로 줘서 `products`(카트)가 **초기 빈 배열로
  굳어** 있었다 → `shouldConfirmClear({products: []})` = false → 조용히 삭제.

  ⤷ **deps 배열을 없앴다.** 같은 파일의 보류판매 ESC 핸들러는 원래 deps 를 안 줘서 정상이었다 —
    두 핸들러의 차이가 그대로 증상의 차이였다.

---

## 4. 배포 완료 — Phase 93 선행 결함 (api `40f1bd79` #938, `28b5d95f` #939)

- **P1-a** 로그인 백필이 권한 회수를 되돌리던 것 정지 (`auth.service.ts`)
- **P1-b** `roleId` 매장 소유권 검사 — bulk 경로 + **우회로**(`PUT /role-functions`)
  ★ codex 가 우회로를 P1 으로 잡았다. 「경계를 한 곳에만 세우면 우회로가 남는다.」
    `tenant-guard-coverage.spec.ts` 가 **컨트롤러에서 진입점을 뽑아** 기계로 센다.

Phase 93 상태와 설계 판단은 `.planning/phases/93-permisos-4-niveles/93-PLAN.md`.
목업 2개: 권한 계층 `DPJdfbTmLnMhjd7mfnKnMq` · 편집 화면 `8vAr5Jhx5BembFZYqZA4j4`

---

## 5. 남은 일

| 순위 | 일 | 상태 |
|---|---|---|
| **1** | **티켓 통일** (§1) | 사용자 지시, 미착수 |
| 2 | 가격 **4~6단계** — `ensurePriceTypes` 슬롯별 보장 · `pre1` prices 행 쓰기 제거 · `pBase` 정책 분리 · `legacy_price_schema` fail-closed | 3단계까지 완료 |
| 3 | Phase 93 **0번 남은 셋** — P1-c 저장 계약 · P1-d 마이그레이션 캐시 절차 · P1-e fail-open | UI 만들기 전까지는 급하지 않다 |
| 4 | Phase 93 **1~7번** | 미착수 |

★ **가격 3단계는 DB 까지 적용 끝났다** — `price_types.legacy_slot`(nullable, 2~5,
  `(store_id, legacy_slot)` 부분 UNIQUE). 로컬 5432 · 운영 5434 **양쪽 적용**, 스키마 대조 일치,
  값이 바뀐 행 0. 커밋 `e50659eb` 는 **아직 push 안 했다.**

---

## 6. 이번 세션의 환경 변경 (되돌릴 수 있음)

★ **3050 을 운영 빌드 → `npm run dev` 로 바꿨다.** 더미 계정이 로컬 DB 에만 있는데
  `constants.tsx` 는 `NODE_ENV === 'development'` 일 때만 `localhost:5002` 를 보기 때문이다.
  되돌리려면 `npx next build && npx next start -p 3050`.

★ **브라우저에서 fetch/XHR 을 가로채 로컬 API 로 돌리는 방법은 안 통했다** —
  로그인 제출 때 **페이지가 완전히 리로드**되어 주입한 패치가 매번 사라진다.
  (메모리 `cmux-needs-production-build-for-this-app` 의 방식이 여기선 안 맞는다.)

★ 로그인은 `perm.admin@dummy.test` / `Dummy1234` 로 성공. 로그인 API 필드는
  `email` 이 아니라 **`emailOrUsername`** 이다(`signIn-auth.dto.ts:5`).

★ 카하 모달이 다시 떴지만 **누르지 않았다** — `cash_registers` id 341 이 이미 열려 있었고
  (box 20, 같은 사용자), 새로고침하니 앱이 인식했다. 눌렀으면 **중복 세션**이 생겼을 것이다.

---

## 7. push 대기

| 저장소 | 커밋 |
|---|---|
| api-ventago | `e50659eb` (legacy_slot 마이그레이션 — **DB 는 이미 적용됨**) |
| root | `4ffa2d7` (포인터 + 계획 문서 2건) |

app 은 push 완료(`c9726da`).
