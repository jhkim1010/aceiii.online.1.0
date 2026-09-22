# 핸드오프 2026-09-21 — POS 단축키 · ws 매장 전자영수증 개통 · 반품

앞 핸드오프: `HANDOFF-2026-09-20-phase57-게이트웨이이탈-완료와-남은-사용자작업.md`
동작 목업: `.planning/mockups/pos-atajos-pgup-pgdn.html`

---

## 0. 한 줄

**오늘 한 것은 전부 운영에 나가 있다.** 남은 것은 아래 §5 두 건(A·B)이고,
**POS 판매는 막고 있지 않다** — 2026-09-21 재확인(§6-7).

| | 빌드 | 결과 |
|---|---|---|
| api | #921 · **#922** · #923 | #922 만 **FAILURE**(부팅) → #923 에서 수정 · SUCCESS |
| front | #750 · #751 · #752 · #753 | 전부 SUCCESS |

최종 리비전: api `1c9d7abd` · app `aa9bbb2` · root `847dffe`.

---

## 1. POS 결제 단축키 (사용자 결정 · 배포 완료)

| 키 | 하는 일 |
|---|---|
| `PgUp` | 결제 100% **외상**(credito) |
| `PgDn` | 결제 100% **은행**(banco) |
| `F9` | 결제 100% **현금** — 되돌리는 키(조건 **없음**) |
| `Ctrl+F9` | 결제 모달(종전 F9) |
| `Ctrl+F12` | 판매 확정 + 발급 화면을 **100% 로** 연다(비율 칸 없음) |
| `Ctrl+E` | **Devolver Ropas** 토글 |

판정은 `ventago-app/src/views/homes/utils/pago-rapido.ts` **하나**가 한다(순수 함수 + 시험).

★ **다시 제안하지 말 것** (이미 묻고 답을 받았다):
- 레거시 문서에 `Credito, RePg` / `Debito, AvPag` 로 적혀 있어 **레거시의 PgDn 은
  Débito** 였다. 그 사실을 알린 뒤 **「은행으로 놔둬줘」** 로 확정됐다.
- 맨 `F12` 는 걸지 않는다 — Chrome/Windows 개발자도구라 페이지가 막을 수 없고,
  둘 다 걸면 개발자도구와 발급 화면이 동시에 뜬다. `Ctrl+D` 도 같은 이유로 피했다
  (북마크 추가) → `Ctrl+E`.
- `Ctrl+F12` 는 **확인 없이 쏘지 않는다.** 한때 `autoEmitir` 로 무인 발급을 만들었다가
  사용자 결정으로 걷어냈다. `f12-factura-100.spec.ts` 가 그 경로의 **부재**를 센다.
- store 9 의 안 쓰는 은행 수단(id 37)은 **그대로 둔다** → 그 매장은 PgDn 이 모달을
  연다(은행이 2개로 세어진다). 의도된 동작이다.

---

## 2. ws 매장 전자영수증 개통 (배포 완료)

**운영 14개 매장 중 12개가 `ws` 이고, 그 매장들은 지금까지 발행자를 아예 만들 수
없었다** — 즉 전자영수증을 못 쓰고 있었다. 2026-09-05 가드가 막고 있었고, 그 이유
(ws 는 `getLastVoucher()` 가 항상 null → 이중발급 대조 불가)는 여전히 유효하다.

→ **해제하지 않고 조건부로 열었다**: **cool-invoice 에 등록된 CUIT** 이면 통과.
「확인된 연동」이 허가증이다.

- 화면: CUIT 11자리 → 게이트웨이 조회 → 등록됐으면 **지점 선택기**(번호 — 이름 — PV).
  이미 다른 지점이 쓰는 sucursal 은 **비활성**으로 그린다.
- 고른 지점의 `point` 로 `puntoVenta` 를, 서버가 `coolUser` 를 저장한다.
  **설정 때만 묻고 계속 사용한다**(사용자 결정).
- ★★ **fail-closed**: 게이트웨이에 못 물어보면(`desconocido`) **막는다.**

### 게이트웨이 계약 (실측 2026-09-21, 운영에 직접 조회)
```
GET https://manager.coolsistema.com/api/data/header/cuit/{cuit}/{sucursal}
  등록  → 200 + JSON (isActive · coolUser · branchs[].point · 연락처)
  미등록 → 200 + null          ← 오류가 아니라 「없다」는 답
```
★ **경로의 `{sucursal}` 은 답을 바꾸지 않는다**(1·2·9·0 동일) — CUIT 하나가 판정한다.
  옛 코드가 `(CUIT, sucursal)` 로 캐시하고 「invoiceSucursal 없으면 스킵」 했던
  전제는 **틀렸다.**

### G5 경계를 다시 그었다 — 「언제 묻는가」
폐기한 `resolvePvAndCoolUser` 의 잘못은 **발급할 때마다** 물어 soap 매장의 PV 를
남이 정하게 한 것이다(결번 사고). ws 는 발급 자체를 게이트웨이가 하므로 그쪽
번호가 권위다. → **설정 때 묻는 것은 허용 · 발급 경로에서 묻는 것은 금지.**
`gateway-desacople.spec.ts` 가 발급 파일 5개에서 호출 0건을 센다.

---

## 3. 지점별 CUIT·sucursal (배포 완료)

구조는 이미 지점별이었다(`uq_afip_issuer_store_branch`). 막히던 자리는
**`uq_afip_issuer_cuit_pv (cuit, punto_venta)` 가 전역**이라, 두 지점이 같은 CUIT 의
같은 sucursal 을 고르면 둘째 저장이 DB 제약에 걸려 거친 오류로 튀던 것이다.
→ 저장 전에 막고 **무엇을 하면 되는지** 말한다(다른 sucursal / 발행자 공유).

---

## 4. 반품 · códigos madre (배포 완료)

**Devolver Ropas** — 종전에는 `checked={false}` + 빈 `onChange` 인 **자리표시**라
어느 매장에서도 안 켜졌다. 이제 `Ctrl+E`/체크박스로 켜지고, 담은 물건이 **재고로
돌아간다**(`+qty`, 금액 0, NC 없음).
★ 부호가 `fallado` 와 **반대**다 — -qty 로 두면 반품마다 재고가 두 번 빠진다.
★ 손실과 **분리**: 재고유형 `devolucion`(≠writeoff) · 활동분류 `devuelto`(≠fallado).
★ 세 모드(fallados·movidos·devueltos)는 상호 배타 — 겹치면 부호가 갈린다.

마이그레이션 `2026-09-21-sales-activity-devuelto.sql` — **운영(5434)·로컬(5432)
양쪽 적용 완료**(영향 행 0).

**códigos madre 항상 켜짐** — 그리고 이것이 사용자가 보고한
「NOIX 에서 SKU 를 눌러도 제품이 안 나온다」의 **진짜 원인**이었다:
`setShowParentsState(!!(useColor || useSize))` 가 매장 설정을 보고 **자동으로 껐고**,
그러면 자식 상품만 조회된다. NOIX(19)·ACE(9) 는 `use_color=f, use_size=f` 이고
NOIX 는 활성 157개 중 **부모 153 · 자식 4** 라 목록에 4개만 떴다.
→ 상수 `true` 로 고정. **체크박스는 화면에서 지웠다**(사용자 지시 — 「그냥 정한
것이면 보여줄 필요도 없다」). 끌 수 없는 컨트롤을 그리면 고를 수 있는 선택지로
읽힌다. `codigos-madre-siempre.spec.ts` 가 그 **부재**를 센다(되살리면 죽는 것 확인).

---

## 5. ★ 남은 것

| | 내용 | 상태 |
|---|---|---|
| **A** | **`ProductBranch` 행이 없는 활성 상품 76개**(9개 매장 · 부모 74 · 단품 2). 막는 곳은 **Zebra 라벨 인쇄 한 곳**뿐이다 — `products.service.ts:1116 getProductsForPrintCodes` 가 `{ association: 'branches', required: true }` 로 걸어 404 `No se encontraron productos para la sucursal`. 원인: `products.service.ts:134 create()` 가 PB 를 안 만든다(지점 컨텍스트가 없다). 단품은 입고 때 `asegurarProductBranch` 가 만들어 주지만 **마드레는 재고가 안 붙어 영영 안 생긴다.** 일괄 임포트(`code-import.service.ts:473·494·519`)는 부모에도 부르므로 같은 매장에 두 부류가 공존한다 | 미착수 |
| **B** | **CODEX P2 — CUIT 귀속 검사에 잠금이 없다.** 조회와 저장 사이가 비어, 두 매장이 동시에 같은 CUIT 을 저장하면 양쪽이 통과한다. 고치려면 쓰기 경로 셋을 한 트랜잭션으로 모으고 `pg_advisory_xact_lock` | 미착수 (`src/app/afip` 에 `pg_advisory` 0건 — 2026-09-21 확인) |
| C | 로컬 dev 서버가 3050 에 떠 있다(`next dev`). 지난 세션이 남긴 **운영 빌드(`next start`)를 dev 로 되돌린 상태** — 그 빌드는 `NODE_ENV=production` 이라 **운영 API 를 바라봤다** | 참고 |

★ 사용자가 **ARCA 작업**(전용 인증서·전용 PV)은 여전히 대기 중이다 —
`GUIA-2026-09-19-afip-certificado-propio-y-pv.md`. 인증서 `CN=CNCOOLSISTEMA2024`
만료 **2026-10-20**(D-29).

---

## 6. 이번 세션에 뒤집힌 전제 (다음 세션이 또 속지 않도록)

1. ★★★ **빌드가 통과해도 부팅은 죽는다.** `constructor(http: AxiosInstance = axios)` —
   **기본값은 Nest DI 를 막아 주지 않는다.** 인터페이스는 `design:paramtypes` 에
   `Object` 로 남아 provider 를 찾다 실패한다. tsc·jest·docker 빌드 **전부 통과**하고
   green 스모크만 90초 무응답으로 죽었다(#922). blue/green 이 green 을 버려 운영은 무사.
   → `@Optional()`. `arranque-nest.spec.ts` 가 못 박았다.
   **확인은 추측이 아니라 `dist/main` 을 직접 띄워서** 했다(대조군 포함).
2. **가드가 있어도 안 돌 수 있다.** `assertCuitDeEstaTienda` 는 Phase 67 격리 훅이
   `beforeFind` 를 좁혀 **한 번도 발화하지 않았다.** 단위 시험은 가짜 모델이라 통과했다 —
   **통과는 지켜짐이 아니다.** → `TenantContext.runSystem` 으로 명시적으로 넘는다.
3. **DTO 에 없는 칸은 조용히 사라진다.** `invoiceSucursal` 이 `ValidationPipe(whitelist)`
   에 걸려 서버에 닿은 적이 없었다(운영 2행이 전부 NULL 인 이유).
4. **「범위를 넓히면 노출도 넓어진다」가 또 나왔다.** CUIT 조회 입구가 남의 매장 id·PV·
   공유플래그를 줬다 — 거절 문구는 저장할 때만 나오는데 **조회는 아무 CUIT 이나 찍어
   볼 수 있다.** 일반 admin 에게는 「겹치는가」 하나만 준다.
5. **자리표시가 기능처럼 보인다.** Devolver 체크박스는 라벨만 있었고, 사용자가 운영에서
   눌러 보고서야 드러났다. **마운트됨 ≠ 도달 가능.**
6. **시험이 낱말을 세고 있었다.** 「autoEmitir 를 걷어냈다」는 **주석**에 걸려 실패했고,
   정규식이 넓어 `onClose` 에서 지워도 `onIssued` 에 걸려 통과했다. 둘 다 돌연변이가
   잡았다 — **주석을 걷어내고 코드를 세라.**
7. ★★ **「PB 가 없으면 POS 에서 안 보이고 못 판다」 → 틀렸다** (2026-09-21 재검).
   목록을 만드는 `findByParentFlag`(`productStock.service.ts:1650`)는 **어느 분기도
   `ProductBranch` 를 조인하지 않는다** — 부모 목록은 `parent_id IS NULL` + `store_id`
   + status 뿐이고, `branchId` 는 **재고 숫자를 고를 때만** 쓴다(필터 아님).
   실증: PB 가 없는 그 4가족 중 둘이 **오늘 실제로 거래됐다**
   (554 → 판매 220번 18:40 · 558 → `online_order:14:hold` 18:22).
   「NOIX 에서 제품이 안 나온다」의 원인은 §4 의 códigos madre 자동 꺼짐이 **전부**였다.
   → 남은 영향은 라벨 인쇄뿐이라 §5-A 를 그 범위로 좁혔다.
8. **「결제 금액 소수 정규화 5곳」은 2026-09-10 에 끝나 있었다**(`c02b0185` 외 3커밋,
   운영 리비전 `1c9d7abd` 의 조상). 실제 저장 경로는 5곳이 아니라 **8곳**이고 7곳이
   정규화돼 있다 — 나머지 하나(`store.service.ts:2153`)는 **복원 경로**라 백업 값을
   그대로 옮기는 것이 맞다. 지키는 시험은 `sales-create-payment-boundary.spec.ts`(7건).
   ⤷ 2026-09-20 에도 같은 확인을 했다. **이월 목록은 낡는다 — 코드로 먼저 확인할 것.**

---

## 7. 검증 상태

api `src/app/afip` **62 suites / 913 tests** · `stocks`+`sales` 19/334 ·
app **40 suites / 492 tests**. tsc·eslint 0. 새 시험은 전부 **돌연변이로 죽는 것을
확인**했다(부호 뒤집기 · 가드 인자 제거 · `pctFijo={false}` · 거절 문구에 id 되살리기 등).
