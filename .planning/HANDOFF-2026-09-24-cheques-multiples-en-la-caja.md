# 핸드오프 2026-09-23 (심야) — 다음 일: **카하에 수표 여러 장**

다음 세션은 §2 부터 바로 구현에 들어가면 된다. **조사는 이미 끝났다** — §3 에 실측을 적어 뒀다.

목업(합의본, 보드 4·5): https://claude.ai/artifact/DR3KvFZxFFCEY7nuvFoSsc

---

## 1. 배포 상태 — 이 세션은 전부 나갔다

| Jenkins | 커밋 | 결과 |
|---|---|---|
| api **#943** | `f9df18a4` | SUCCESS — **Phase 93 P1-e**. 운영 DB 마이그레이션도 적용 완료 |
| front **#780** | `b2b32067` | SUCCESS |
| front **#781** | `3a83cb51` | SUCCESS + 컨테이너 재생성 확인 (Envío 인라인) |

→ **이 세션의 배포는 전부 끝났다.** 확인할 빌드 없이 §2 부터 시작하면 된다.

★ Jenkins 백엔드 잡은 **`api-new-coolsistema`**. `api-coolsistema` 는 **cool-invoice 의 이미지**다
  (컨테이너 `apicoolsistema`, 5011→5010). CLAUDE.md 는 이번에 고쳤다.

---

## 2. ★ 다음 작업 — 수표 여러 장 (미착수, 설계 합의됨)

> 「천만원을 가져가는 손님이 1개의 수표로 처리하지 않을거야.. 여러개의 수표로
>  처리할 경우도 생각해야 해」 — 사용자, 2026-09-23

### 합의된 동작 (목업 보드 4·5)

- cheque 줄의 **금액칸은 읽기 전용**이고 수표들의 **합계**를 보여준다.
  손으로 친 숫자가 종이와 다르면 몇 주 뒤 카하 차액으로 나타난다.
- 줄 아래에 **각 수표 요약**(번호·은행·만기·금액) + 각각 ✕. 지우면 합계가 따라 내려간다.
- 「+ Cheque」가 **기존 대화상자**를 연다. 그 상자는 **닫히지 않는다** —
  「Agregar」 하면 목록에 쌓이고 칸이 비워져 다음 장을 바로 친다.
- 부족액 경고는 **알릴 뿐 막지 않는다**(일부 수표 + 일부 현금이 정상). 판정은 F2.

### 구현 순서 (4단계)

1. **`ponerMontoEnLista` 에 cheque 예외** — 지금은 수단당 한 줄로 dedupe 한다.
   cheque 만 N줄을 허용해야 한다. ★ 이 함수는 `derramarResto`·`repartirCambioDeTotal`
   이 전부 통과하므로 **그 세 곳의 시험을 같이 봐야 한다**(`src/__tests__/pago-inline.spec.ts`, 63개).
2. **대화상자에 수표별 금액 칸 + 누적 목록** — `PaymentSummaryModal.tsx` 의
   `chequeForm`(939~985행 근처). 지금은 줄 금액을 물려받는다(한 장 가정).
3. **인라인 줄** — `PagoInline.tsx`: 읽기전용 합계 · 요약 목록 · 「+ Cheque」.
   지금은 `motivoPorDatosQueFaltan` 가 cheque 를 막고 있다(§3 참조) — **그 차단을 푸는 것이
   이 단계의 마지막**이지 처음이 아니다. 풀어 놓고 폼이 없으면 다시 막다른 길이 된다.
4. **`ProductList.tsx:1731`** — `...(p.cheque ? { cheque: p.cheque } : {})` 는 이미 있다.
   줄마다 `cheque` 를 들고 있게만 하면 된다.

---

## 3. ★★ 이미 조사해서 확인한 것 (다시 파지 말 것)

| 확인한 것 | 근거 |
|---|---|
| **`cheques` 테이블이 이미 있다** — number·bank·due_date·amount·`sale_id`·type·status·holder_name·holder_cuit | `\d cheques`, 로컬·운영 동일 |
| **백엔드가 결제줄 하나당 수표 하나를 만든다** — 줄이 N개면 수표도 N개, 같은 트랜잭션 | `sales-create.service.ts:2578` 이 `Promise.all(map(...))` 안에 있다 |
| **대화상자 6개 필드가 이미 있다** — banco·número·tipo(común/diferido)·fecha·titular·CUIT, 검증 포함 | `PaymentSummaryModal.tsx:139-141, 540-558` |
| **막고 있는 건 프론트뿐** | 위 셋의 조합 |

⤷ 즉 **새로 만들 것은 「수표별 금액」과 「목록/합계」뿐**이다. 테이블도 엔드포인트도 폼도 있다.

### 내가 만들었다가 막아 둔 것

인라인 콤보가 `cheque`·`senia`·`favor`·`internet_pedido` 를 고르게 해 놨는데, 이들은 추가
데이터가 필요해 F2 에서 **서버가 거절했다**(막다른 길). `motivoPorDatosQueFaltan`
(`pago-inline.ts`)이 이유와 함께 막는다. 실측한 요구사항:

```
cheque           cheque.{number,bank}   sales-create.service.ts:2578
senia            applySeniaSaleId       :3466
favor            storeClientId          :3453
internet_pedido  판매가 아니라 pedido online
```

---

## 4. 이 세션에 끝난 것

### Phase 93 P1-e — **0단계 5/5 완료**

운영에 **열려 있던 인가 구멍**이었다. `isAllowed()` 의 `if (!fn) return true` 때문에
`@FunctionGuard` 가 요구하는 98개 slug 중 **3개가 카탈로그에 없어** 고객 병합과 대량
상품 임포트가 **JWT 만 있으면 전원 통과**였다. 오류도 로그도 없었다.

- 마이그레이션 `2026-09-23-phase93-p1e-seed-3-slugs-faltantes.sql` — **로컬·운영 적용 완료**
  (운영 3 functions + 108 role_functions + 108 actions). 부여 대상은 사용자 결정대로
  **`admin`·`store_admin`·`store_owner`** 뿐, 액션도 가드가 요구하는 하나씩만.
- `isAllowed()` → **fail-closed**, 막을 때 slug 를 말한다.
- 부팅 점검(`onModuleInit`)이 빠진 slug 를 로그에 외친다. **부팅을 죽이지는 않는다** —
  시드 하나 빠졌다고 API 가 안 뜨면 그게 더 큰 사고다.

★ 되돌리려면 **데이터도 같이** 되돌려야 한다. 코드만 되돌리면 다시 전원 통과가 된다.
★ `DB에 function이 없으면 통과` 시험이 `toBe(true)` 로 **구멍을 의도된 동작으로 못 박고
  있었다.** 뒤집고 대조군을 붙였다.

### POS

| 커밋 | 내용 |
|---|---|
| `04c1fef3` | descuento·recargo 칩 중복 제거 + 세 줄 → 한 줄 |
| `e052cede` | 「Listo para generar」 줄 제거(오른쪽 ✓ Completo 가 대신) · Subtotal +50% |
| `06011354` | 인라인 콤보의 막다른 길 차단 (§3) |
| `b2b32067` | 「Ventas Online」 → **「Control de Envíos」** (3개 언어·제목·breadcrumb·아이콘). 경로 `/ventas-online` 은 그대로 — 저장된 링크와 `envio_manager` 홈라우트가 깨지는데 얻는 게 없다 |
| `3a83cb51` | **Envío 인라인 체크 + F2 분기** |

#### Envío 의 확정 규칙

- 체크는 Efectivo 줄 오른쪽(구 「Resto」 자리). **아무것도 안 연다.**
- 고객이 없으면 커서가 **CUIT/DNI 칸**으로(리스트 아님). 체크는 그대로 유지, 주소는 안 묻는다.
- **F2 가 갈림길** — 체크하면 버튼이 「Generar y enviar (F2)」가 되고 `EnvioRegistroModal` 을 연다.
- `EnvioRegistroModal` 은 **복사하지 않고 `ProductList` 에 마운트**했다. 두 경로가 주문을
  만들면 서로 다르게 만든다.
- `envioChecked` 는 `SaleProductsContext` 로 올렸다. 모달 지역 상태였고 **열 때마다
  리셋**됐다 — 체크가 밖에 있으니 그대로 뒀으면 결제창 열 때마다 지워졌다.

★ 부수로 고친 것: **CUIT/DNI 칸에 id 가 없었다.** `CLIENTE_DOC_INPUT_ID` 를
  `focus-pos.ts`(코드·수량 id 가 사는 곳)에 추가했다.

---

## 5. 이 세션에서 드러난 「조용히 죽어 있던」 것

### `input-sku` id 가 DOM 에 없었다 (고침, `f15f1468`)

`id="input-sku"` 가 `renderInput` 의 TextField 에 있었는데 MUI 가 `params.inputProps.id`
(`:r9:`)로 덮는다. `getElementById('input-sku')` 가 **계속 null** 이었고 `?.` 가 삼켰다 —
할인 적용 후 코드칸 복귀, tmp 모드 탈출 복귀가 **전부 죽어 있었다.**
→ `<Autocomplete id={SKU_INPUT_ID}>` 로 이동. 메모리 `mui-autocomplete-id-shadows-textfield-id`.

★ **MUI 로 감싼 입력에 id 로 포커스를 옮긴다면 브라우저에서 `getElementById` 를 직접 쳐 볼 것.**

### `codex exec` 가 긴 프롬프트에서 조용히 죽는다

**exit 0 · 빈 출력.** 이 세션에서 3번 낭비했다. 메모리 `codex-exec-dies-silently-on-big-prompt`.
쓰는 법: 짧은 프롬프트로 **읽을 파일을 지시**, `-o <파일>`, `< /dev/null`.
검토 기록: `.team/reviews/manual-pos-{derrame,atajos}-{codex,resolution}.md`.

---

## 6. 검증·도구 메모

- 이 세션 마지막 기준 `tsc 0` · `eslint 0`(exit code) · **jest 688/688** (app) · 132/132 (api auth)
- 돌연변이 누계 **24개 전부 사망**, 대조군 매번 통과
- **`cmux press` 는 웹뷰에 안 닿는다**(Tab·PageUp·F9 등) → `KeyboardEvent` 를 dispatch 할 것
- 버튼은 **텍스트로 정확히 지목**할 것. 넓은 선택자(`button.MuiButton-outlined`)로 눌렀다가
  관리자 승인 모달을 띄웠다
- 커밋 게이트가 `git add X && git commit` 을 **거부**한다(add 이전 index 를 보기 때문).
  add 를 먼저 따로 실행할 것

---

## 7. 미결

1. **수표 여러 장** (§2) — 다음 일
2. 같은 이름 descuento 를 **말없이 거부**하는 것 → 이유를 보여 주기
   (`InvoiceAditional.tsx` 의 `discounts.some(d => d.name === ...) return`)
3. **Phase 93 1~7단계** — 사용자가 「끝까지」 승인했다. 계획서
   `.planning/phases/93-permisos-4-niveles/93-PLAN.md`. 0단계만 끝난 상태다.
   ★ ROADMAP 2185행의 93 항목이 「(계획만)」으로 낡았다
4. `.planning/PLAN-2026-09-16-서버-분리…` 는 미커밋 파일 — Jenkins 잡 이름 수정이
   워킹트리에만 있다

## 8. 환경

- 3050 = `npm run dev`, 5002 = 로컬 API(`DATABASE_NAME=ventago DATABASE_PORT=5432`)
- 더미 계정 4개 비밀번호 `Dummy1234`(로컬 전용). **로그인은 사용자가 한다.**
