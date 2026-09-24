# 핸드오프 2026-09-24-b — Phase 93 **4단계까지 완료** · Detalle del pedido

다음 세션은 **§4 부터** 읽으면 된다. 다음 일은 **Phase 93 5단계(메뉴 UI)** 이고,
그 앞에 **push 안 된 커밋 2개**가 있다(§2).

---

## 1. 이 세션에 배포된 것 — 전부 SUCCESS

| Jenkins | 커밋 | 내용 |
|---|---|---|
| api **#946** · front **#784** | `2a65be6f` / `a1620592` | Phase 93 4단계 — 은퇴 역할 인식 제거 |
| api **#947** · front **#785** | `f43b43d5` / `17cf6e02` | 권한 서술 정정 · MP 경고 토스트 |
| front **#786** | `665c1df1` | Detalle del pedido 상품 매트릭스 |

전부 컨테이너 재생성 확인. `newapi/api/health` 200 · `app.coolsistema.com` 200.

**마이그레이션** `2026-09-24-phase93-p4-borrar-roles-viejos.sql` —
**운영(5434)·로컬(5432) 양쪽 COMMIT 완료.** 둘 다 ROLLBACK 시험 선행.

| 지운 것 | 운영 | 로컬 |
|---|---|---|
| `roles` (구 slug 3종) | **48** | 42 |
| `role_functions` | **8,155** | 7,067 |
| `role_function_actions` (CASCADE) | **25,813** | 23,645 |

백업 표 3개가 남아 있다 — `roles_retirados_bak_20260924` ·
`role_functions_retirados_bak_20260924` · `role_function_actions_retirados_bak_20260924`.
**테스트로 만든 것이므로 지우지 않는다.**

---

## 2. ★ push 안 된 커밋 2개 — 짝이다, 함께 나가야 한다

| 저장소 | 커밋 | 내용 |
|---|---|---|
| api | `888da88d` | 주문 상세가 품목의 **`madreId`** 를 같이 준다 |
| app | `7901c3c5` | 매트릭스를 **madre 기준**으로 묶는다 (이름은 폴백) |

**어느 쪽이 먼저 배포돼도 안전하다** — 새 api + 옛 화면이면 `madreId` 가 무시되고
(종전 동작), 옛 api + 새 화면이면 이름 폴백이 돈다. 그래도 같이 내보내는 것이 맞다.

검증 끝: api tsc·jest 6 suite 81건 / app tsc·eslint·jest 64 suite 741건 ·
`npm run build` exit 0. **CODEX 자문은 아직 안 받았다** (§5).

---

## 3. Phase 93 — **0~4단계 완료**

계획서: `.planning/phases/93-permisos-4-niveles/93-PLAN.md`

| 단계 | 상태 |
|---|---|
| 0 선행 결함 5건 | ✅ #943 |
| 1 구 역할 생성 중단 (expand) | ✅ #944 |
| 2 역할 데이터 이전 (migrate) | ✅ 양쪽 DB |
| 3 관찰 | ✅ **깨끗** — 아래 |
| 4 contract | ✅ #946/#784 + 마이그레이션 |
| **5 ①메뉴 → ②부메뉴 → ③기능 UI** | ⏳ **다음** |
| 6 ④액션 UI (컨트롤 179개) | 미착수 |
| 7 스페인어화 · 가짜 임계값 탭 제거 | 미착수 |

### 3단계 관찰 결과 (실측)

- 경과 **11시간 38분** > 로그인 토큰 최대 수명 **6시간**(`auth.service.ts:740`)
- `/auth/me` 는 역할을 **DB 에서 다시 읽는다**(`roles_local`) → 구 slug 이월 없음
- 403 **0건** · 500 **0건** · `[perm]` 거부 **0건**
- ★ 이전된 계정이 **실제로 일했다** — store 19 `admin@noix` 가 이전 후 19:24 에 판매

### 4단계에서 지운 것 (코드)

alias(`user-role.guard`) · `PRIVILEGED`(permission.guard) · `PRIVILEGED_ROLES`
(branch-scope.guard) · `ALL_BRANCH_ROLES` · `ADMIN_ROLES` · `ELEVATED_ROLE_SLUGS` ·
`SETUP_GUIDE_ROLES` · `BACKFILL_FULL_ROLES` · `FULL_ACCESS_ROLES` · `PREFERENCIA` ·
`rol-administrador` 폴백 · `REVERT_OTHERS_ROLE_SLUGS` · `hasAdminRole` ·
`EXCLUDED_SELLER_ROLE_SLUGS` · stocks `privilegedRoles` · support `PRIVILEGED_ROLES` ·
프런트 `roles.ts` 4개 집합 · `UserDetail` ROLE_OPTIONS · `MatrixGrid` ROLE_ORDER 등.

`legacy-import.controller.ts` 의 `ADMIN_ROLES` **지역 복사본**은 가드에서 import 하도록
합쳤다 — 같은 파일 안에서 두 벌이 갈라질 뻔했다.

spec **9개를 뒤집었다**(「인식돼야 한다」→「인식되면 안 된다」). 뒤집으면서 대조군이
없어지지 않게 했다: 크기 하한(`> 3`, `size + 1`)은 집합이 줄면 깨지고 늘어도 틀리므로
**내용을 적는 단언**으로 바꿨다.

### 운영 현재 역할 분포 (2026-09-24)

`admin 19명 · vendedor 5 · gerente 3 · cashier 2 · inventory_clerk 1 · superadmin 1`
(역할 행: admin 17 · gerente 17 · cashier/accountant/inventory_clerk/viewer 각 16 ·
envio_manager 9 · vendedor 5 · superadmin 1)

---

## 4. ★ 다음 일 — Phase 93 5단계

계획서 「착수 순서」 5번. **①메뉴 → ②부메뉴 → ③기능** 3층을 권한 UI 로 세운다.
사이드바 14개 모델링 + aux 기능 시드, expand→migrate→contract 로 **전원이 메뉴를
잃는 구간 없이**.

착수 전에 계획서의 §1「측정된 사실」을 다시 읽을 것 — 특히:

- 액션 축은 운영에서 **100% 무의미**하다(전 역할이 4액션 보유). ④단계는
  「기존 설정 존중」의 대상이 없고, **UI 를 여는 순간 첫 저장이 곧 대규모 권한 회수**다.
- 컨트롤 **179개 : 기능 179개** — 1:1, 허수 0. 4칸을 항상 그리면 468칸 중 **302칸(65%)
  이 허수**다. 동사 1개뿐인 92개 중 68개가 읽기 전용이다.
- 179개 중 **95개만 API 를 바꾼다.** 나머지 84개는 메뉴 노출에만 영향한다 —
  화면이 그 차이를 표시해야 «껐는데 왜 되지»가 안 생긴다.

---

## 5. 이 세션에 새로 만든 것 — Detalle del pedido 「PARA PREPARAR」

Control de Envíos 에서 카드를 골라도 우측 패널은 **누가·언제**만 말하고 **무엇을**은
말하지 않았다. 준비하는 사람은 티켓을 뽑거나 VentaVista 로 건너가야 했다.

**위치**: Ticket/Recibo/Cancelar 버튼 **아래**, Nota·타임라인 **위** (사용자 선택).
**모양**: 상품별 **색 = 행 · 사이즈 = 열** 매트릭스 (사용자 선택).

### 이 기능이 기대는 사실 (전부 실측)

| 사실 | 값 |
|---|---|
| `online_order_items` 에 `size`·`color` 가 **이미 있다** | 64행 중 61행 |
| `sku` 는 **항상 비어 있다** | **0 / 64** → SKU 열을 만들지 않았다 |
| 한 주문이 같은 상품의 색·사이즈 **13줄**인 경우가 있다 | pedido 12 `MC BATIK` |
| `product_id` 는 부모가 **아니라 자식 변형** | `products 246` = `MC BATIK (BLANCO/S)` · parent 245 |
| 이름이 겹치는 madre | 전 매장 **8쌍**, 온라인 주문에 쓰인 것 1건(주문에 혼자) |

★★ **`productId` 로 묶으면 안 된다.** CODEX 가 P1 으로 「id 로 묶어라」고 했고 실측이
  뒤집었다 — 그렇게 하면 1×1 매트릭스가 13개 나와 **고치려던 상태로 돌아간다.**
  대신 서버가 `madreId` 를 계산해 붙이게 했다(§2 의 커밋 2개).

### 파일

- `ventago-app/src/views/ventas-online/components/agruparItemsDePedido.ts` — 순수 함수
- `ventago-app/src/__tests__/agrupar-items-de-pedido.spec.ts` — **20건**
- `ventago-app/src/views/ventas-online/components/ProductosAPreparar.tsx` — 렌더
- `ventago-app/src/views/ventas-online/components/EnvioTimeline.tsx` — 마운트 + 타입 확장
- `api-ventago/src/app/online-orders/online-orders.service.ts` — `mapaDeMadres`

### 남은 것 / 안 한 것

- **브라우저로 눈으로 본 적 없다.** 이 앱은 렌더 테스트 도구(@testing-library)가
  **없고**, 화면 확인은 운영 빌드 + cmux 가 필요하다. `npm run build` 는 통과했다.
  25% 폭 다크 패널 안의 표라 **실제 모양은 사람이 봐야 안다.**
- `handlePrint`(`EnvioTimeline.tsx`)는 여전히 `size`·`color` 를 **티켓에 안 싣는다.**
  타입이 넓어졌으니 이제 넣을 수 있다. **손대지 않았다** — 인쇄물 변경은 별도 결정이다.
- `.env` 가 **스테이징**(`ventago_staging:15432`)을 가리킨다. 로컬 API 로 실제 응답을
  보려면 `DB_PORT=5432 DB_NAME=ventago` 로 덮어써야 한다.

---

## 6. 사용자 판단으로 **닫은** 것 — 다시 제안하지 말 것

**지점장의 레거시 임포트 접근은 위협이 아니다.**
2단계가 `branch_manager` 사용자를 `gerente` 로 옮겼는데 `gerente` 는 `ADMIN_ROLES`
안에 있다 → 그 1명이 레거시 임포트 권한을 얻었다. 내가 이것을 「권한 확대」로 보고했고,
사용자 판단(2026-09-24): **구버전 시스템에는 역할·권한이라는 개념 자체가 없어
임포트가 가져올 권한이 없다.** 집합을 다시 나누지 않는다.

⤷ 소스 세 곳의 서술을 「위험」에서 **사실**로 고쳤다(`f43b43d5`). 남긴 것은 둘:
  · 두 집합이 같아졌다는 **사실**(앞으로 가이드를 넓히면 임포트도 같이 넓어진다)
  · **방법** — 역할을 합칠 때 `role_functions` 만 대조하면 매트릭스 밖 하드코딩 집합의
    변화는 **보이지 않는다.** 이번엔 무해했을 뿐이다.

---

## 7. 여전히 미결 (사용자가 아직 정하지 않음)

1. **프로비저닝 경로 결함 2건** (codex, 전부터 있던 것)
   - `provisionStoreAndOwner` 전체가 **단일 트랜잭션이 아니다** → 중간 실패 시 매장·사용자가
     고아로 남고 재시도는 alias/email 중복에 걸려 복구 불가.
   - `POST /store/new`(superadmin 콘솔)는 역할만 시드하고 **관리자 사용자를 안 만든다** →
     관리자 0명 매장을 `success: true` 로 반환.
   ★ 2단계 검증이 실제로 그런 매장 3개를 찾아냈다(로컬 `ZZ-P86-*` 시험용이지만 형태가 같다).

2. **서버 수표 중복 거절** — 지금은 프론트 두 경로에서만 막는다.
   `(store, bank, number)` 유일성은 마이그레이션이 필요하다.

3. 같은 이름 descuento 를 말없이 거부 (`InvoiceAditional.tsx` 의 `discounts.some(...) return`)

---

## 8. 도구 메모 (이 세션에서 겪음)

- **`codex exec` 에 `-o` 를 주면 조용히 죽는다.** 이 세션에서 **2회** 그랬다(exit 0,
  출력 파일 없음). `-o` 를 빼고 **stdout 을 파일로 리다이렉트**하면 정상이다.
  그리고 **`git diff` 를 보게 하면 죽는다** — 프롬프트에 「git 명령을 실행하지 마라,
  아래 N개 파일만 `cat` 으로 읽어라」를 **명시**할 것. 파일 3~4개가 상한처럼 보인다.
- **`git add X && git commit` 은 훅이 거부한다** — add 를 먼저 따로 실행.
- **커밋 게이트가 출력을 안 낸다.** 이 세션 내내 조용했다 — tsc·eslint·jest 를
  **손으로 돌렸다.** 출력이 비면 「안 돈 것」이다.
- **시험 팩토리를 `it` 으로 이름 짓지 말 것.** jest 의 `it` 을 가려 「0 tests」로 돌고
  `--silent` 로는 초록처럼 보인다. 이 세션에서 실제로 당했다.
- **`--single-transaction` 없이** 마이그레이션을 돌렸다(파일 안에 `BEGIN`/`COMMIT`).
  `sed 's/^COMMIT;$/ROLLBACK;/'` 으로 먼저 돌려 행 수를 본다.
