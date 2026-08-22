Reading additional input from stdin...
2026-08-22T02:09:17.267951Z ERROR codex_models_manager::cache: failed to load models cache: missing field `base_instructions` at line 95 column 5
OpenAI Codex v0.146.0
--------
workdir: /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
model: gpt-5.6-sol
provider: openai
approval: never
sandbox: read-only
reasoning effort: none
reasoning summaries: none
session id: 01a0273a-c327-7020-a911-0823ab21c4e3
--------
user
설계 자문이다. **코드 탐색을 최소화하라. 넓은 grep 금지.**

읽을 것: `.planning/QUESTION-2026-08-22-b-복원엔진-설계.md` 하나면 충분하다.
필요하면 `api-ventago/src/app/store/store-backup-scopes.ts` 만 추가로 열어라.

문서의 수치는 운영 DB 실측이다. 재검증하지 말고 그대로 받아들여라.

사용자 지시: "다른 매장 데이터가 섞이는 일이 절대 있어서는 안 된다."
답은 "고치는 방법" 이 아니라 **"재발이 불가능해지는 구조"** 여야 한다.

「묻는 것」 6개에 **전부** 답하라. 한국어. 각 질문마다 결론 먼저, 근거는 짧게.
E1~E6 에 반대할 것이 있으면 분명히 반대하고 대안을 제시하라.
길게 쓰지 말고 6개 전부 답하는 것을 우선하라.
warning: `--dangerously-bypass-hook-trust` is enabled. Enabled hooks may run without review for this invocation.
warning: `--dangerously-bypass-hook-trust` is enabled. Enabled hooks may run without review for this invocation.
hook: SessionStart
hook: SessionStart
hook: SessionStart
hook: SessionStart Failed
hook: SessionStart Failed
hook: SessionStart Completed
hook: UserPromptSubmit
hook: UserPromptSubmit Completed
codex
지정하신 설계 문서만 읽고, 6개 질문에 결론 우선으로 답하겠습니다. 필요할 때에만 허용된 스코프 파일을 추가 확인하겠습니다.
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse Failed
hook: PreToolUse Completed
hook: PreToolUse Completed
exec
/bin/zsh -lc "sed -n '1,260p' .planning/QUESTION-2026-08-22-b-복원엔진-설계.md" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 0ms:
# W6-C3 복원 엔진 설계 — codex 자문 요청 (2026-08-22)

앞선 자문(`.team/reviews/w6-restore-tenant-resolution.md`)에서 네가 정한 선을 지켜 설계했다.
**짓기 전에** 본다 — 오늘 내 설계가 두 번(계약을 파일에 맡김 / 부채를 초록으로 셈) 반려됐다.

## 지금까지 배포된 것 (전제)

- **W6-C0**: 복원은 서버 상수(`RESTORE_ENGINE_STATUS='blocked'`)로 **무조건 거부**된다.
  파일이 무엇을 주장하든 상관없다. 잠금은 엔진을 실제로 고치는 커밋으로만 풀린다.
- **W6-C1**: 전 테이블(216) 을 `tenant`(187) / `global`(29) 로 분류하는 기준선 +
  6갈래 선언(SIMPLE / CUSTOM / PENDING / EXCLUDED / CROSS_TENANT / GLOBAL). 미분류면 빌드 실패.
- **W6-C2**: 백업 **119 → 152 테이블**. 관계로만 닿는 33개를 선언 쿼리로 담는다.
  소유자는 `COALESCE` 우선순위로 **하나로 확정**한다(OR 로 묶었더니 2행이 두 매장에 실렸다).
- **W6-D**: 백업이 MinIO 객체의 실재를 확인하고 `coverage.assets` 로 말한다.

## 실측 (2026-08-22 운영)

| 항목 | 값 |
|---|---|
| 복원해야 할 테이블 | **152** |
| public 스키마 FK | **419** |
| **순환 FK 묶음** | **4** — `stores↔users(+branches)` · `sales↔online_orders` · `sales↔restaurant_tables` · `talleres_envios↔recepciones↔rework_orders` |
| 최대 테이블 | `store_clients` 3,791행 · `role_function_actions` 40,557행(전 매장) |
| 마스킹된 NOT NULL 컬럼 | 6 (`mp_accounts.access_token/refresh_token`, `commerce_channels.channel_key/secret`, `wp_channels.channel_key/secret`) |

## 내가 제안하는 설계

### E1. 매니페스트가 권위, 카탈로그는 검증자 (네 지적 수용)
런타임 `information_schema` 자동 판정 없음. **선언**이 정한다:
- 테이블 순서(레벨) — 손으로 선언하고, **DB 카탈로그로 "선언 순서가 FK 를 위배하지 않는지" 검증**
- FK 컬럼별 처리 — `REMAP` / `KEEP_GLOBAL` / `CLEAR` / `REJECT`.
  **미선언 FK 가 하나라도 있으면 spec 실패** (복원 대상 152 테이블의 모든 FK 컬럼)

### E2. 모드별 실행기 분리 (네 지적 수용)
- `CLONE` — 새 매장 생성, PK 재매핑, 외부 자격증명 제거, 전역 참조 재검증
- `IN_PLACE_RECOVERY` — 같은 매장, ID 보존, 기존 행과의 충돌 통제, `stocks` 는 반대 부호 보정 행
공유는 **계획기·검증기**만. 백업 파일에 `backupPurpose` + 스키마 버전.

### E3. 순환은 2단계 삽입
순환을 닫는 FK 컬럼(예: `sales.online_order_id`)을 **NULL 로 넣고**, 양쪽이 다 생긴 뒤 UPDATE.
그 컬럼은 매니페스트에 `DEFERRED` 로 선언하고, **UPDATE 를 빠뜨리면 커밋 전 검사가 잡는다.**

### E4. 커밋 전 전수 불변식 (매니페스트에서 자동 생성)
`OWNERSHIP`/`TENANT_REFERENCE` 로 선언된 모든 FK 에 대해
`자식.store 소유자 <> 부모.store 소유자` 인 행을 센다. **1행이라도 나오면 롤백.**
사람이 SQL 목록을 관리하지 않는다.

### E5. 입력 검증 (네 지적 수용)
허용 컬럼 목록(테이블별) · 미지 테이블/컬럼 거부 · 형식 버전 · 행 수 · coverage hash.
`backupData: any` + `...fields` 를 없앤다.

### E6. 자격증명은 모드별 `REAUTH`/`REJECT`/`CLEAR`
마스킹된 NOT NULL 6개는 `CLONE` 에서 **그 테이블을 통째로 건너뛴다**(재인증 대상).
건너뛴 사실을 결과에 명시한다.

## 묻는 것

1. **E1 의 "순서를 손으로 선언하고 카탈로그로 검증" 이 맞나?** 152개 순서를 손으로 쓰는 것이
   현실적인가, 아니면 카탈로그에서 위상 정렬하고 **순환만** 손으로 선언하는 게 나은가?
   (후자는 "자동 판정" 에 가까워 네가 반대한 쪽인데, 순서는 의미가 아니라 **제약**이라
   카탈로그가 권위여도 되지 않나?)
2. **E3 의 2단계 삽입에서 놓치기 쉬운 것은?** 특히 UPDATE 를 빠뜨렸을 때
   커밋 전 검사가 정말 잡는가 — NULL 은 FK 검사를 통과한다.
3. **E4 의 불변식을 어떻게 표현해야 152 테이블에 자동 생성되나?**
   `store_id` 컬럼이 없는 테이블이 대부분이라 "자식의 소유자" 를 구하려면
   백업 때 쓴 소유 경로(`store-backup-scopes.ts`)를 재사용해야 할 것 같은데,
   **백업 경로와 복원 검증 경로가 같은 선언에서 나오는 것**이 옳은가 위험한가?
   (같으면 한쪽이 틀렸을 때 둘 다 틀린다.)
4. **`IN_PLACE_RECOVERY` 에서 "T 이후 생긴 행" 을 어떻게 다루나?**
   사용자 결정: 판매·현금은 되돌리지 않고, `stocks` 는 반대 부호 보정 행.
   그러면 상품·가격·설정만 되돌리는데, **T 이후 팔린 상품**을 T 시점 상태로 되돌리면
   판매와 어긋난다. 이 경계를 어디에 그어야 하나?
5. **40,557행 규모에서 단일 트랜잭션이 맞나?** 한 매장분은 5,243행이지만
   300매장이면 커진다. 트랜잭션을 쪼개면 부분 복원이 되는데, 쪼개지 않으면 잠금이 길다.
6. 내가 놓친 것.

한국어. 결론 먼저. 반대할 것은 분명히 반대하라. **6개 전부 답하는 것을 우선하라.**

hook: PostToolUse
hook: PostToolUse
hook: PostToolUse Failed
hook: PostToolUse Completed
codex
3번의 “동일 선언 재사용” 위험을 정확히 판단하기 위해, 허용된 스코프 선언 파일만 추가 확인하겠습니다.
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse Failed
hook: PreToolUse Completed
hook: PreToolUse Completed
exec
/bin/zsh -lc "sed -n '1,280p' api-ventago/src/app/store/store-backup-scopes.ts" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 0ms:
// [Phase 85 W6-C2] **매장에 속하지만 `store_id` 컬럼이 없는 테이블을 어떻게 뽑는가.**
//
// ★ 왜 선언으로 두나: W6-B 에서 손으로 쓴 쿼리 13개를 목록 하나로 합쳤더니
//   "새 테이블은 목록에 한 줄" 이 됐다. 여기도 같다 — 쿼리를 서비스 코드에
//   흩어 두면 어느 테이블이 어떤 근거로 뽑히는지 아무도 못 센다.
//
// ★★ **소유권의 권위는 관계다.** 비정규화된 컬럼이 아니라 FK 를 따라간다.
//   (`stocks` 를 `store_id` 로 뽑았다가 codex 에게 지적받은 것과 같은 원칙이고,
//    W6-C1 에서 인벤토리 자체도 그렇게 바꿨다.)
//
// ★★★ **소유 FK 가 nullable 이면 그 행은 조인에서 조용히 사라진다.**
//   이건 가정이 아니라 실측이다 — 2026-08-22 운영에서 `venta_suspendida_items` 는
//   54행 중 **51행(94%)이 `venta_suspendida_id` 가 NULL** 이었다
//   (`ON DELETE SET NULL` 로 부모가 사라진 뒤 남은 행들).
//   부모만 보고 뽑았으면 **3행만 담고 아무도 몰랐다.**
//   W6-B 에서 `products.category_id` 가 NULL 이라 상품 34개를 놓친 것과 같은 형태다.
//
//   → 그래서 **소유 FK 가 nullable 인 테이블은 경로를 여러 개 둔다.**
//     행이 빠져나갈 수 있는 자리가 정확히 거기이기 때문이다.
//
// ★★★★ 다만 여러 경로를 `OR` 로 묶으면 **소유자가 둘이 된다.**
//   실측(2026-08-22): `venta_suspendida_items` 2행은 부모 보류판매가 매장 3,
//   상품이 매장 8 이다. `OR` 로 뽑으면 그 2행이 **두 매장 백업에 모두 실린다** —
//   교차 매장 혼입을 막으려다 백업이 스스로 만드는 꼴이다.
//   → **`COALESCE` 로 우선순위를 정해 소유자를 하나로 확정한다.**
//     첫 경로가 소유의 근거이고, 뒤는 그것이 사라졌을 때의 차선이다.
//
// ★ 근거가 없는 행은 **추측해서 귀속하지 않는다.** 위 51행 중 3행은 부모도 상품도
//   없어 어느 매장 것인지 알 방법이 없다. 틀린 지목은 "모른다" 보다 나쁘다.
//   그런 행은 `scripts/check-tenant-orphans.sh` 가 세어 보여 준다.

/**
 * 테이블 → 그 매장의 행만 뽑는 SQL.
 *
 * 규칙:
 *   - 반드시 `:storeId` 를 바인딩한다 (문자열 결합 금지)
 *   - 별칭 `t` 가 대상 테이블이고 `SELECT t.*` 로 뽑는다 (컬럼을 손으로 안 적는다 —
 *     컬럼이 늘면 자동으로 따라간다)
 *   - 소유 FK 가 nullable 이면 `LEFT JOIN` + `OR` 로 **다른 경로도** 본다
 */
export const TENANT_SCOPE_QUERIES: Readonly<Record<string, string>> = {
  // ── 권한 ────────────────────────────────────────────────────────────────
  // role_function_id 는 nullable(운영 NULL 0건)이지만 다른 경로가 없다.
  // NULL 행이 생기면 어느 역할의 액션인지 알 방법이 자체적으로 없으므로
  // orphan 점검 스크립트가 잡는다.
  role_function_actions: `
    SELECT t.* FROM role_function_actions t
      JOIN role_functions rf ON t.role_function_id = rf.id
     WHERE rf.store_id = :storeId`,

  user_function_actions: `
    SELECT t.* FROM user_function_actions t
      JOIN user_functions uf ON t.user_function_id = uf.id
     WHERE uf.store_id = :storeId`,

  // user_id 가 nullable → role 경로를 **차선**으로 둔다(사용자가 소유자다).
  user_roles: `
    SELECT t.* FROM user_roles t
      LEFT JOIN users u ON t.user_id = u.id
      LEFT JOIN roles r ON t.role_id = r.id
     WHERE COALESCE(u.store_id, r.store_id) = :storeId`,

  user_branches: `
    SELECT t.* FROM user_branches t
      JOIN users u ON t.user_id = u.id
     WHERE u.store_id = :storeId`,

  // ── 금전 ────────────────────────────────────────────────────────────────
  // cash_register_id 가 nullable → 터미널·사용자를 **차선**으로 둔다.
  box_operations: `
    SELECT t.* FROM box_operations t
      LEFT JOIN cash_registers cr ON t.cash_register_id = cr.id
      LEFT JOIN terminals te ON t.terminal_id = te.id
      LEFT JOIN users u ON t.user_id = u.id
     WHERE COALESCE(cr.store_id, te.store_id, u.store_id) = :storeId`,

  caja_fuerte_operations: `
    SELECT t.* FROM caja_fuerte_operations t
      JOIN caja_fuertes cf ON t.caja_fuerte_id = cf.id
     WHERE cf.store_id = :storeId`,

  // box_id 가 nullable(ON DELETE SET NULL) → 사용자를 **차선**으로 둔다.
  movements: `
    SELECT t.* FROM movements t
      LEFT JOIN boxes b ON t.box_id = b.id
      LEFT JOIN users u ON t.user_id = u.id
     WHERE COALESCE(b.store_id, u.store_id) = :storeId`,

  // ── 온라인 주문 ──────────────────────────────────────────────────────────
  online_order_items: `
    SELECT t.* FROM online_order_items t
      JOIN online_orders oo ON t.online_order_id = oo.id
     WHERE oo.store_id = :storeId`,

  online_returns: `
    SELECT t.* FROM online_returns t
      JOIN online_orders oo ON t.online_order_id = oo.id
     WHERE oo.store_id = :storeId`,

  // ── 보류 판매 ────────────────────────────────────────────────────────────
  // ★ venta_suspendida_id 가 nullable 이고 **운영 54행 중 51행이 실제로 NULL** 이다.
  //   부모만 보면 3행만 담긴다. 상품 경로를 반드시 함께 본다.
  venta_suspendida_items: `
    SELECT t.* FROM venta_suspendida_items t
      LEFT JOIN ventas_suspendidas vs ON t.venta_suspendida_id = vs.id
      LEFT JOIN products p ON t.product_id = p.id
     WHERE COALESCE(vs.store_id, p.store_id) = :storeId`,

  venta_suspendida_discounts: `
    SELECT t.* FROM venta_suspendida_discounts t
      JOIN ventas_suspendidas vs ON t.venta_suspendida_id = vs.id
     WHERE vs.store_id = :storeId`,

  venta_suspendida_recharges: `
    SELECT t.* FROM venta_suspendida_recharges t
      JOIN ventas_suspendidas vs ON t.venta_suspendida_id = vs.id
     WHERE vs.store_id = :storeId`,

  discount_reasons: `
    SELECT t.* FROM discount_reasons t
      JOIN sales s ON t.sale_id = s.id
     WHERE s.store_id = :storeId`,

  // ── 상품·할인 매핑 ───────────────────────────────────────────────────────
  product_subcategories: `
    SELECT t.* FROM product_subcategories t
      JOIN products p ON t.product_id = p.id
     WHERE p.store_id = :storeId`,

  product_discounts: `
    SELECT t.* FROM product_discounts t
      LEFT JOIN discounts d ON t.discount_id = d.id
      LEFT JOIN products p ON t.product_id = p.id
     WHERE COALESCE(d.store_id, p.store_id) = :storeId`,

  // discount_id 가 nullable → 소분류를 **차선**으로 둔다.
  subcategory_discounts: `
    SELECT t.* FROM subcategory_discounts t
      LEFT JOIN discounts d ON t.discount_id = d.id
      LEFT JOIN subcategories sc ON t.subcategory_id = sc.id
     WHERE COALESCE(d.store_id, sc.store_id) = :storeId`,

  payment_methods_discounts: `
    SELECT t.* FROM payment_methods_discounts t
      LEFT JOIN discounts d ON t.discount_id = d.id
      LEFT JOIN payment_methods pm ON t.payment_method_id = pm.id
     WHERE COALESCE(d.store_id, pm.store_id) = :storeId`,

  payment_methods_options: `
    SELECT t.* FROM payment_methods_options t
      JOIN payment_methods pm ON t.payment_method_id = pm.id
     WHERE pm.store_id = :storeId`,

  // ── 지점 설정·장비 ───────────────────────────────────────────────────────
  branch_price_types_disabled: `
    SELECT t.* FROM branch_price_types_disabled t
      JOIN branches b ON t.branch_id = b.id
     WHERE b.store_id = :storeId`,

  branch_printer_configs: `
    SELECT t.* FROM branch_printer_configs t
      JOIN branches b ON t.branch_id = b.id
     WHERE b.store_id = :storeId`,

  // ★ api_key 는 REDACTED_COLUMNS 가 지운다. 복제된 매장은 재등록해야 한다.
  branch_agents: `
    SELECT t.* FROM branch_agents t
      JOIN branches b ON t.branch_id = b.id
     WHERE b.store_id = :storeId`,

  // ── 지출·외주·기타 ───────────────────────────────────────────────────────
  expense_cheques: `
    SELECT t.* FROM expense_cheques t
      JOIN expenses e ON t.expense_id = e.id
     WHERE e.store_id = :storeId`,

  talleres_vendor_etapas: `
    SELECT t.* FROM talleres_vendor_etapas t
      JOIN talleres_vendors tv ON t.vendor_id = tv.id
     WHERE tv.store_id = :storeId`,

  talleres_envio_materiales: `
    SELECT t.* FROM talleres_envio_materiales t
      JOIN talleres_envios te ON t.envio_id = te.id
     WHERE te.store_id = :storeId`,

  // 2단계: defects → deliveries → orders
  talleres_defects: `
    SELECT t.* FROM talleres_defects t
      JOIN talleres_deliveries td ON t.subcon_delivery_id = td.id
      JOIN talleres_orders too ON td.subcon_order_id = too.id
     WHERE too.store_id = :storeId`,

  talleres_material_issues: `
    SELECT t.* FROM talleres_material_issues t
      JOIN talleres_orders too ON t.subcon_order_id = too.id
     WHERE too.store_id = :storeId`,

  shared_folder_role_access: `
    SELECT t.* FROM shared_folder_role_access t
      LEFT JOIN shared_folders sf ON t.shared_folder_id = sf.id
      LEFT JOIN roles r ON t.role_id = r.id
     WHERE COALESCE(sf.store_id, r.store_id) = :storeId`,

  rider_settlement_items: `
    SELECT t.* FROM rider_settlement_items t
      JOIN rider_settlements rs ON t.settlement_id = rs.id
     WHERE rs.store_id = :storeId`,

  campaign_recipients: `
    SELECT t.* FROM campaign_recipients t
      JOIN campaigns c ON t.campaign_id = c.id
     WHERE c.store_id = :storeId`,

  // ── MercadoPago ─────────────────────────────────────────────────────────
  //   백업에는 담는다. 복원에서 모드별로 가른다(복제는 활성 원장으로 되살리지 않는다).
  mp_movements: `
    SELECT t.* FROM mp_movements t
      JOIN mp_wallets mw ON t.mp_wallet_id = mw.id
     WHERE mw.store_id = :storeId`,

  mp_transfers: `
    SELECT t.* FROM mp_transfers t
      JOIN mp_wallets mw ON t.mp_wallet_id = mw.id
     WHERE mw.store_id = :storeId`,

  mp_refunds: `
    SELECT t.* FROM mp_refunds t
      JOIN sales s ON t.sale_id = s.id
     WHERE s.store_id = :storeId`,

  mp_refund_attempts: `
    SELECT t.* FROM mp_refund_attempts t
      JOIN sales s ON t.sale_id = s.id
     WHERE s.store_id = :storeId`,
};

hook: PostToolUse
hook: PostToolUse
hook: PostToolUse Failed
hook: PostToolUse Completed
codex
1. E1 — 카탈로그 위상 정렬이 맞다

152개 순서를 손으로 선언하는 E1에는 반대한다. FK 카탈로그는 여기서 “의미 판정자”가 아니라 실제 DB 제약의 권위다.

- 카탈로그로 DAG를 위상 정렬한다.
- 순환 묶음과 순환 해소 전략만 매니페스트에 선언한다.
- 스키마 버전·FK 집합이 매니페스트와 다르면 즉시 거부한다.
- 같은 레벨의 실행 순서만 고정 정렬해 재현성을 보장한다.

즉, 소유권은 선언이 정하고 삽입 순서는 DB 제약에서 계산해야 한다.

2. E3 — FK 검사만으로는 절대 잡히지 않는다

E3의 “커밋 전 검사가 잡는다”는 조건부로만 맞다. NULL은 정상 값일 수도 있으므로 단순 FK/NOT NULL 검사로는 누락을 판별할 수 없다.

각 DEFERRED 값마다 다음을 보존해야 한다.

- 원본이 NULL이었는지
- 원본 FK 값
- 재매핑 대상 ID
- UPDATE 완료 여부

커밋 전에는 `원본 non-NULL인데 미해결`, `매핑 없음`, `UPDATE 대상 행 수 불일치`, `대상 매장 불일치`를 모두 0건으로 확인해야 한다. 또한 순환 컬럼이 NOT NULL이면 NULL 삽입 방식은 불가능하므로 DEFERRABLE FK 또는 스테이징 테이블 방식이 필요하다.

3. E4 — 같은 소유 선언을 양쪽의 유일한 근거로 쓰면 안 된다

백업과 복원 검증이 같은 SQL을 공유하는 것은 공통 원인 실패를 만든다. 현재 `COALESCE` 우선순위가 틀리면 백업과 검증이 함께 틀린 결과를 “정상”으로 판정할 수 있다.

권장 구조는 다음과 같다.

- 하나의 소유권 그래프에서 백업 선택기와 복원 검증기를 별도 생성·구현한다.
- 복원 검증은 백업 SQL 재실행이 아니라, 복원된 행에서 목적지 매장까지의 관계 폐쇄를 역방향으로 증명한다.
- 장기적으로 모든 tenant 행에 불변 `store_id`를 두고 `(store_id, parent_id)` 복합 FK로 같은 매장 부모만 참조하게 해야 한다.

마지막 DB 제약까지 도입해야 “검사가 잘 잡는다”가 아니라 “다른 매장 참조를 저장할 수 없다”가 된다.

4. IN_PLACE_RECOVERY — T 이후 거래가 참조한 의미는 되돌리면 안 된다

경계는 “설정/마스터”가 아니라 “T 이후 사실이 참조했는가”로 그어야 한다.

- 판매·현금·주문·재고 원장은 보존한다.
- 재고는 제안대로 삭제/덮어쓰기 대신 보정 원장을 추가한다.
- T 이후 판매가 참조한 상품 ID, 세율, 단위, 가격 의미는 과거 상태로 덮어쓰지 않는다.
- 상품·가격 변경은 버전/유효기간 방식으로 새 버전을 만들거나, 충돌 시 복원을 거부한다.
- 삭제 대상도 실제 삭제 대신 비활성화·tombstone 처리한다.

따라서 IN_PLACE_RECOVERY는 전체 시점 복원이 아니라, 명시적으로 허용된 비거래 설정의 선택적 복구여야 한다.

5. 트랜잭션 — 매장 하나당 단일 트랜잭션이 맞다

한 매장 5,243행 규모라면 원자성이 잠금 비용보다 중요하다. 300매장을 하나의 트랜잭션으로 묶는 설계에는 반대한다.

- 매장별 독립 작업·독립 트랜잭션
- 해당 매장 복원 advisory lock
- 복원 중 해당 매장의 쓰기 차단
- 스테이징 적재 후 짧은 최종 적용
- 실패 시 그 매장 전체 롤백

매장 간 부분 완료는 허용할 수 있지만, 한 매장 내부의 부분 복원은 허용하면 안 된다.

6. 놓친 것 — DB 수준 tenant 경계와 입력의 대상 결박

가장 큰 누락은 엔진 검사보다 아래에 있는 강제 장치다. 복원 세션의 목적지 `storeId`를 서버가 확정하고, 입력 파일의 매장 ID로 대체할 수 없게 해야 한다. 가능하면 RLS 또는 복합 tenant FK로 다른 매장 행의 INSERT/UPDATE 자체를 DB가 거부해야 한다.

추가로 E6은 수정이 필요하다. 자격증명 테이블 전체를 건너뛰면 비밀이 아닌 설정과 자식 관계까지 유실될 수 있다. 비밀은 별도 저장소로 분리하고, 복제 시에는 비활성 “재인증 필요” 행을 생성하는 편이 안전하다. 매니페스트도 단순 hash가 아니라 서명 또는 신뢰된 서버 메타데이터와 결박해야 변조를 막을 수 있다.
hook: Stop
hook: Stop
hook: Stop Failed
hook: Stop Completed
tokens used
21,736
1. E1 — 카탈로그 위상 정렬이 맞다

152개 순서를 손으로 선언하는 E1에는 반대한다. FK 카탈로그는 여기서 “의미 판정자”가 아니라 실제 DB 제약의 권위다.

- 카탈로그로 DAG를 위상 정렬한다.
- 순환 묶음과 순환 해소 전략만 매니페스트에 선언한다.
- 스키마 버전·FK 집합이 매니페스트와 다르면 즉시 거부한다.
- 같은 레벨의 실행 순서만 고정 정렬해 재현성을 보장한다.

즉, 소유권은 선언이 정하고 삽입 순서는 DB 제약에서 계산해야 한다.

2. E3 — FK 검사만으로는 절대 잡히지 않는다

E3의 “커밋 전 검사가 잡는다”는 조건부로만 맞다. NULL은 정상 값일 수도 있으므로 단순 FK/NOT NULL 검사로는 누락을 판별할 수 없다.

각 DEFERRED 값마다 다음을 보존해야 한다.

- 원본이 NULL이었는지
- 원본 FK 값
- 재매핑 대상 ID
- UPDATE 완료 여부

커밋 전에는 `원본 non-NULL인데 미해결`, `매핑 없음`, `UPDATE 대상 행 수 불일치`, `대상 매장 불일치`를 모두 0건으로 확인해야 한다. 또한 순환 컬럼이 NOT NULL이면 NULL 삽입 방식은 불가능하므로 DEFERRABLE FK 또는 스테이징 테이블 방식이 필요하다.

3. E4 — 같은 소유 선언을 양쪽의 유일한 근거로 쓰면 안 된다

백업과 복원 검증이 같은 SQL을 공유하는 것은 공통 원인 실패를 만든다. 현재 `COALESCE` 우선순위가 틀리면 백업과 검증이 함께 틀린 결과를 “정상”으로 판정할 수 있다.

권장 구조는 다음과 같다.

- 하나의 소유권 그래프에서 백업 선택기와 복원 검증기를 별도 생성·구현한다.
- 복원 검증은 백업 SQL 재실행이 아니라, 복원된 행에서 목적지 매장까지의 관계 폐쇄를 역방향으로 증명한다.
- 장기적으로 모든 tenant 행에 불변 `store_id`를 두고 `(store_id, parent_id)` 복합 FK로 같은 매장 부모만 참조하게 해야 한다.

마지막 DB 제약까지 도입해야 “검사가 잘 잡는다”가 아니라 “다른 매장 참조를 저장할 수 없다”가 된다.

4. IN_PLACE_RECOVERY — T 이후 거래가 참조한 의미는 되돌리면 안 된다

경계는 “설정/마스터”가 아니라 “T 이후 사실이 참조했는가”로 그어야 한다.

- 판매·현금·주문·재고 원장은 보존한다.
- 재고는 제안대로 삭제/덮어쓰기 대신 보정 원장을 추가한다.
- T 이후 판매가 참조한 상품 ID, 세율, 단위, 가격 의미는 과거 상태로 덮어쓰지 않는다.
- 상품·가격 변경은 버전/유효기간 방식으로 새 버전을 만들거나, 충돌 시 복원을 거부한다.
- 삭제 대상도 실제 삭제 대신 비활성화·tombstone 처리한다.

따라서 IN_PLACE_RECOVERY는 전체 시점 복원이 아니라, 명시적으로 허용된 비거래 설정의 선택적 복구여야 한다.

5. 트랜잭션 — 매장 하나당 단일 트랜잭션이 맞다

한 매장 5,243행 규모라면 원자성이 잠금 비용보다 중요하다. 300매장을 하나의 트랜잭션으로 묶는 설계에는 반대한다.

- 매장별 독립 작업·독립 트랜잭션
- 해당 매장 복원 advisory lock
- 복원 중 해당 매장의 쓰기 차단
- 스테이징 적재 후 짧은 최종 적용
- 실패 시 그 매장 전체 롤백

매장 간 부분 완료는 허용할 수 있지만, 한 매장 내부의 부분 복원은 허용하면 안 된다.

6. 놓친 것 — DB 수준 tenant 경계와 입력의 대상 결박

가장 큰 누락은 엔진 검사보다 아래에 있는 강제 장치다. 복원 세션의 목적지 `storeId`를 서버가 확정하고, 입력 파일의 매장 ID로 대체할 수 없게 해야 한다. 가능하면 RLS 또는 복합 tenant FK로 다른 매장 행의 INSERT/UPDATE 자체를 DB가 거부해야 한다.

추가로 E6은 수정이 필요하다. 자격증명 테이블 전체를 건너뛰면 비밀이 아닌 설정과 자식 관계까지 유실될 수 있다. 비밀은 별도 저장소로 분리하고, 복제 시에는 비활성 “재인증 필요” 행을 생성하는 편이 안전하다. 매니페스트도 단순 hash가 아니라 서명 또는 신뢰된 서버 메타데이터와 결박해야 변조를 막을 수 있다.
