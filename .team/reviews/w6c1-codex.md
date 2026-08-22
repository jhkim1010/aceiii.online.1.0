Reading additional input from stdin...
2026-08-22T01:20:32.022250Z ERROR codex_models_manager::cache: failed to load models cache: missing field `base_instructions` at line 95 column 5
OpenAI Codex v0.146.0
--------
workdir: /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
model: gpt-5.6-sol
provider: openai
approval: never
sandbox: read-only
reasoning effort: none
reasoning summaries: none
session id: 01a0270e-1ffa-7742-b0b3-7e9c36698324
--------
user
AGENTS.md 의 보안 검토자 역할을 따르라. **넓은 탐색은 하지 마라.**

검토 대상은 `.team/reviews/w6c1-diff.txt` 하나다. **이 파일만 읽어라.**
(루트 git diff 는 서브모듈 수정 파일을 못 본다.)

배경 — 이것은 `.team/reviews/w6-restore-tenant-resolution.md` 의 **Stage 1** 이다.
네가 준 지적을 수용해 만든 것이다:
- "권위는 FK 폐포가 아니라 전 테이블 매니페스트여야 한다" → 전 테이블(216개)을
  tenant/global 로 분류하는 기준선 + 5갈래 선언(SIMPLE/CUSTOM/PENDING/EXCLUDED/CROSS_TENANT/GLOBAL)
- 종전에는 감시가 두 겹인데 **두 겹 다 `store_id` 문자열을 봐서 같은 맹점을 공유**했다.
  이제 ①인벤토리는 관계 도달을 쓰고, ②마이그레이션 컷오프는 **조건을 아예 없앴다**
  (새로 만든 테이블은 매장 것이든 아니든 반드시 분류돼야 한다).
- 매장 데이터인데 FK 가 0개라 관계로 안 잡히던 talleres 4개(전부 0행)에 FK 를 추가했다.

확인해 달라:
1. **분류가 틀린 것이 있는가.** 특히 PENDING(담아야 함) 과 EXCLUDED(안 담음) 와
   CROSS_TENANT(여러 매장 공유) 의 경계. 내가 CROSS_TENANT 로 뺀 6개가 맞나?
2. **PENDING 이라는 세 번째 자리**가 옳은 설계인가? (CUSTOM 에 넣으면 "담고 있다" 는
   거짓말, EXCLUDED 에 넣으면 "안 담기로 했다" 는 거짓말이라 만들었다)
3. 이 감시가 **거짓 통과**할 수 있는 경로가 남아 있는가? 새 테이블·새 컬럼·기준선
   재생성 누락·형식 변경 등.
4. 마이그레이션(FK 4개 추가)에 문제가 있는가? 이미 운영에 적용했다.
5. 내가 놓친 것.

한국어. 심각도 표기. 이상 없으면 "이상 없음" 이라고 분명히 써라.
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
지정하신 범위대로 `.team/reviews/w6c1-diff.txt`만 읽고, 그 안의 근거만으로 분류·감시·FK 마이그레이션을 검토하겠습니다. 다른 파일이나 Git 상태는 조회하지 않겠습니다.
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse Failed
hook: PreToolUse Completed
hook: PreToolUse Completed
exec
/bin/zsh -lc "sed -n '1,240p' .team/reviews/w6c1-diff.txt" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 0ms:
===== api-ventago diff (인벤토리 데이터파일 제외 — 216줄 분류표라 노이즈) =====
diff --git a/scripts/regen-store-backup-inventory.sh b/scripts/regen-store-backup-inventory.sh
index 7a78adf..6b08559 100755
--- a/scripts/regen-store-backup-inventory.sh
+++ b/scripts/regen-store-backup-inventory.sh
@@ -1,9 +1,26 @@
 #!/usr/bin/env bash
-# [Phase 85 W6-A] 매장 백업 커버리지 기준선 재생성.
+# [Phase 85 W6-A / W6-C1] 매장 백업 커버리지 기준선 재생성.
 #
-# `store_id` 를 가진 **실제 테이블**(뷰 제외) 목록을 DB 에서 다시 읽어
+# `public` 스키마의 **모든 실테이블**(뷰 제외)을 `tenant` / `global` 로 분류해
 # `src/app/store/store-backup-inventory.txt` 를 갱신한다.
 #
+# ★★ W6-C1 에서 판정 기준이 바뀌었다 (2026-08-22).
+#   종전에는 **`store_id` 컬럼이 있는 테이블만** 셌다. 그런데 소유권의 권위는
+#   컬럼이 아니라 **관계**다. 관계로만 매장에 닿는 테이블 42개가
+#   백업에도 없고 제외 선언도 없이 조용히 빠져 있었다 —
+#   `role_function_actions`(40,557행) · `user_roles` · `online_order_items` 등.
+#   spec 의 마이그레이션 컷오프도 같은 `store_id` 조건을 봤기 때문에
+#   **감시가 두 겹인데 두 겹이 같은 맹점을 공유**했고, 16/16 초록이었다.
+#
+#   이제 테넌트 판정 = (`store_id` 컬럼 보유) ∪ (`stores` 로부터의 FK 도달).
+#   그리고 **폐포 밖 테이블도 전부 출력**한다 — 분류를 강제하기 위해서다.
+#   목록에 없으면 숨을 수 있으므로 **모든 테이블이 목록에 있어야** 한다.
+#
+# ★ 한계: FK 제약이 없는 테이블은 관계로도 안 잡힌다(실측 `talleres_deliveries` ·
+#   `talleres_payments` · `talleres_material_issues` · `talleres_defects`).
+#   그래서 `global` 로 나온 것도 **사람이 선언**해야 하고, 그 선언이 사실과
+#   다르면 그 자리에 이유를 적게 한다.
+#
 # ★ 언제 돌리는가: **마이그레이션으로 테이블을 추가한 뒤.**
 #   안 돌리면 커버리지 spec 이 새 테이블을 모르므로 조용히 통과한다 —
 #   바로 그 침묵이 W6-A 를 만든 이유이므로, 여기서 같은 구멍을 만들지 않는다.
@@ -19,15 +36,39 @@ set -euo pipefail
 OUT="$(cd "$(dirname "$0")/.." && pwd)/src/app/store/store-backup-inventory.txt"
 TARGET="${PGTARGET:-local}"
 
-SQL="SELECT c.relname
-       FROM pg_class c
-       JOIN pg_namespace n ON n.oid = c.relnamespace
-       JOIN information_schema.columns col
-         ON col.table_name = c.relname
-        AND col.table_schema = 'public'
-        AND col.column_name = 'store_id'
-      WHERE n.nspname = 'public' AND c.relkind = 'r'
-      ORDER BY 1"
+# 테넌트 폐포: stores 자신 + store_id 컬럼 보유 테이블에서 출발해 FK 를 자식 방향으로 따라간다.
+# depth 상한 20 은 순환 방어다 (UNION 이 이미 중복을 접지만 명시적으로 둔다).
+SQL="WITH RECURSIVE fk AS (
+        SELECT con.conrelid AS src, con.confrelid AS ref
+          FROM pg_constraint con
+          JOIN pg_class c ON c.oid = con.conrelid
+          JOIN pg_namespace n ON n.oid = c.relnamespace
+         WHERE con.contype = 'f' AND n.nspname = 'public'
+           AND con.conrelid <> con.confrelid
+      ),
+      seed AS (
+        SELECT c.oid
+          FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
+         WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relname = 'stores'
+        UNION
+        SELECT c.oid
+          FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
+          JOIN information_schema.columns col
+            ON col.table_schema = 'public' AND col.table_name = c.relname
+           AND col.column_name = 'store_id'
+         WHERE n.nspname = 'public' AND c.relkind = 'r'
+      ),
+      reach AS (
+        SELECT oid, 0 AS depth FROM seed
+        UNION
+        SELECT fk.src, r.depth + 1 FROM fk JOIN reach r ON fk.ref = r.oid
+         WHERE r.depth < 20
+      )
+      SELECT CASE WHEN c.oid IN (SELECT oid FROM reach) THEN 'tenant' ELSE 'global' END
+             || ':' || c.relname
+        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
+       WHERE n.nspname = 'public' AND c.relkind = 'r'
+       ORDER BY c.relname"
 
 case "$TARGET" in
   local) TABLES=$(psql -p 5432 -d ventago -tAc "$SQL") ; SRC="로컬 Mac PG18 ventago (5432)" ;;
@@ -39,17 +80,23 @@ esac
 # ★ 빈 결과를 그대로 쓰지 않는다. 접속 실패가 "테이블이 하나도 없다" 로 둔갑하면
 #   커버리지 spec 이 **아무것도 검사하지 않으면서 통과**한다. 0건은 항상 오류다.
 COUNT=$(printf '%s\n' "$TABLES" | grep -c . || true)
-if [ "$COUNT" -lt 50 ]; then
-  echo "✗ store_id 테이블이 ${COUNT}개로 나왔다 — 접속 실패를 의심한다. 파일을 안 바꾼다." >&2
+TENANTS=$(printf '%s\n' "$TABLES" | grep -c '^tenant:' || true)
+if [ "$COUNT" -lt 150 ] || [ "$TENANTS" -lt 100 ]; then
+  echo "✗ 테이블 ${COUNT}개(테넌트 ${TENANTS}개)로 나왔다 — 접속 실패를 의심한다. 파일을 안 바꾼다." >&2
   exit 1
 fi
 
 {
-  echo "# [Phase 85 W6-A] store_id 를 가진 **실제 테이블** 목록 (뷰 제외)."
+  echo "# [Phase 85 W6-A / W6-C1] public 스키마의 **모든 실테이블** 분류 (뷰 제외)."
+  echo "#"
+  echo "# 형식: tenant:<테이블>  또는  global:<테이블>"
+  echo "#   tenant = store_id 컬럼이 있거나, stores 에서 FK 로 도달한다"
+  echo "#   global = 위 어느 쪽도 아니다 (전역 참조 / 시스템 / 레거시)"
   echo "#"
   echo "# 이 파일은 store-backup-coverage.spec.ts 의 기준선이다."
-  echo "# 여기 있는 테이블은 반드시 SIMPLE_STORE_TABLES / CUSTOM_HANDLED_TABLES /"
-  echo "# EXCLUDED_TABLES 중 한 곳에 있어야 한다. 없으면 빌드가 깨진다."
+  echo "# tenant 는 SIMPLE_STORE_TABLES / CUSTOM_HANDLED_TABLES / EXCLUDED_TABLES 중"
+  echo "# 한 곳에, global 은 GLOBAL_TABLES 에 **이유와 함께** 있어야 한다."
+  echo "# 어느 쪽도 아니면 빌드가 깨진다 — 조용히 빠지는 테이블을 없애는 것이 목적이다."
   echo "#"
   echo "# 재생성: scripts/regen-store-backup-inventory.sh"
   echo "# 생성 기준: ${SRC} $(date -u +%Y-%m-%dT%H:%M:%SZ)"
@@ -57,7 +104,7 @@ fi
   printf '%s\n' "$TABLES" | grep -v '^$'
 } > "$OUT"
 
-echo "✓ ${OUT} 갱신 (${COUNT}개)"
+echo "✓ ${OUT} 갱신 (전체 ${COUNT}개 / 테넌트 ${TENANTS}개)"
 
 # ── 민감 컬럼 인벤토리 ──────────────────────────────────────────────────────
 # ★ 패턴을 여기 복사해 두지 않는다. store-backup-coverage.ts 의
diff --git a/src/app/store/store-backup-coverage.spec.ts b/src/app/store/store-backup-coverage.spec.ts
index de5ca1b..54b5e16 100644
--- a/src/app/store/store-backup-coverage.spec.ts
+++ b/src/app/store/store-backup-coverage.spec.ts
@@ -21,6 +21,9 @@ import {
   SIMPLE_STORE_TABLES,
   CUSTOM_HANDLED_TABLES,
   EXCLUDED_TABLES,
+  PENDING_BACKUP_TABLES,
+  CROSS_TENANT_TABLES,
+  GLOBAL_TABLES,
   REDACTED_COLUMNS,
   REVIEWED_SAFE_COLUMNS,
   looksSensitive,
@@ -34,23 +37,56 @@ const MIGRATIONS_DIR = path.join(__dirname, '..', '..', '..', 'migrations');
 /** 이 날짜 이후 마이그레이션부터 ②를 강제한다. 소급하지 않는다 — ①이 그 몫이다. */
 const CUTOFF = '2026-08-21';
 
-function declaredTables(): Map<string, string> {
+/** 매장에 속하는 테이블의 선언 자리 (담김 / 부채 / 제외). */
+function tenantDeclarations(): Map<string, string> {
   const m = new Map<string, string>();
   for (const t of SIMPLE_STORE_TABLES) m.set(t, 'SIMPLE_STORE_TABLES');
   for (const t of Object.keys(CUSTOM_HANDLED_TABLES))
     m.set(t, 'CUSTOM_HANDLED_TABLES');
+  for (const t of Object.keys(PENDING_BACKUP_TABLES))
+    m.set(t, 'PENDING_BACKUP_TABLES');
   for (const t of Object.keys(EXCLUDED_TABLES)) m.set(t, 'EXCLUDED_TABLES');
+  for (const t of Object.keys(CROSS_TENANT_TABLES))
+    m.set(t, 'CROSS_TENANT_TABLES');
 
   return m;
 }
 
-function readInventory(): string[] {
-  const raw = fs.readFileSync(INVENTORY, 'utf8');
+/** 매장 것이 아닌 테이블의 선언 자리. */
+function globalDeclarations(): Map<string, string> {
+  const m = new Map<string, string>();
+  for (const t of Object.keys(GLOBAL_TABLES)) m.set(t, 'GLOBAL_TABLES');
 
-  return raw
-    .split('\n')
-    .map((l) => l.trim())
-    .filter((l) => l && !l.startsWith('#'));
+  return m;
+}
+
+/**
+ * 기준선을 `tenant` / `global` 로 나눠 읽는다.
+ *
+ * ★ [W6-C1] 형식이 바뀌었다: `tenant:<테이블>` / `global:<테이블>`.
+ *   종전에는 `store_id` 컬럼을 가진 테이블 이름만 한 줄씩 있었는데,
+ *   그 기준이 관계로만 매장에 닿는 테이블 42개를 못 봤다.
+ */
+function readInventory(): { tenant: string[]; global: string[] } {
+  const out = { tenant: [] as string[], global: [] as string[] };
+  for (const line of fs.readFileSync(INVENTORY, 'utf8').split('\n')) {
+    const l = line.trim();
+    if (!l || l.startsWith('#')) continue;
+    const at = l.indexOf(':');
+
+    // ★ 옛 형식(분류 없는 이름만)을 조용히 넘기지 않는다. 넘기면 재생성을
+    //   잊은 기준선이 **아무것도 검사하지 않으면서 통과**한다.
+    expect(at).toBeGreaterThan(0);
+
+    const cls = l.slice(0, at);
+    const table = l.slice(at + 1);
+    expect(['tenant', 'global']).toContain(cls);
+    if (isIgnoredTable(table)) continue;
+    if (cls === 'tenant') out.tenant.push(table);
+    else out.global.push(table);
+  }
+
+  return out;
 }
 
 describe('[W6-A] 매장 백업 커버리지', () => {
@@ -58,20 +94,48 @@ describe('[W6-A] 매장 백업 커버리지', () => {
   it('인벤토리가 비어 있지 않다 (빈 기준선은 아무것도 검사하지 않으면서 통과한다)', () => {
     // ★ 이 검사가 먼저인 이유: 파일이 비면 아래 검사가 전부 **0건을 순회하며 통과**한다.
     //   "수집 0건은 위반 0건이 아니다" — 이 저장소가 이미 당한 형태다.
-    expect(readInventory().length).toBeGreaterThan(50);
+    const inv = readInventory();
+    expect(inv.tenant.length).toBeGreaterThan(100);
+    expect(inv.global.length).toBeGreaterThan(5);
   });
 
-  it('store_id 를 가진 모든 테이블이 담기거나, 이유와 함께 제외돼 있다', () => {
-    const declared = declaredTables();
-    const missing = readInventory()
-      .filter((t) => !isIgnoredTable(t))
-      .filter((t) => !declared.has(t));
+  it('★ 매장에 속하는 모든 테이블이 다섯 갈래 중 하나에 선언돼 있다', () => {
+    // ★ [W6-C1] 판정 기준이 `store_id` 컬럼에서 **관계 도달**로 바뀌었다.
+    //   종전 기준은 관계로만 닿는 42개를 못 봤고, 마이그레이션 컷오프도 같은
+    //   `store_id` 조건을 봤기 때문에 **감시 두 겹이 같은 맹점을 공유**했다.
+    const declared = tenantDeclarations();
+    const missing = readInventory().tenant.filter((t) => !declared.has(t));
 
-    expect({ 선언되지_않은_테이블: missing }).toEqual({
-      선언되지_않은_테이블: [],
+    expect({ 선언되지_않은_매장테이블: missing }).toEqual({
+      선언되지_않은_매장테이블: [],
     });
   });
 
+  it('★ 매장 것이 아닌 테이블도 전부 이유와 함께 선언돼 있다', () => {
+    // 여기가 없으면 "폐포 밖" 이 곧 "검사 밖" 이 된다 — 새 테이블이 숨을 자리가 생긴다.
+    const declared = globalDeclarations();
+    const missing = readInventory().global.filter((t) => !declared.has(t));
+
+    expect({ 선언되지_않은_전역테이블: missing }).toEqual({
+      선언되지_않은_전역테이블: [],
+    });
+  });
+
+  it('부채·교차매장·전역 선언에 전부 이유가 적혀 있다', () => {
+    const 이유없음: string[] = [];

hook: PostToolUse
hook: PostToolUse
hook: PostToolUse Failed
hook: PostToolUse Completed
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse Failed
hook: PreToolUse Completed
hook: PreToolUse Completed
exec
/bin/zsh -lc "sed -n '241,480p' .team/reviews/w6c1-diff.txt" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 0ms:
+    for (const [name, map] of [
+      ['PENDING_BACKUP_TABLES', PENDING_BACKUP_TABLES],
+      ['CROSS_TENANT_TABLES', CROSS_TENANT_TABLES],
+      ['GLOBAL_TABLES', GLOBAL_TABLES],
+    ] as const) {
+      for (const [t, reason] of Object.entries(map)) {
+        if (!reason || reason.trim().length < 10) 이유없음.push(`${name}.${t}`);
+      }
+    }
+
+    expect({ 이유가_없는_선언: 이유없음 }).toEqual({ 이유가_없는_선언: [] });
+  });
+
   it('제외에는 전부 이유가 적혀 있다', () => {
     const 이유없음 = Object.entries(EXCLUDED_TABLES)
       .filter(([, reason]) => !reason || reason.trim().length < 10)
@@ -89,7 +153,10 @@ describe('[W6-A] 매장 백업 커버리지', () => {
 
     for (const t of SIMPLE_STORE_TABLES) add(t, 'SIMPLE');
     for (const t of Object.keys(CUSTOM_HANDLED_TABLES)) add(t, 'CUSTOM');
+    for (const t of Object.keys(PENDING_BACKUP_TABLES)) add(t, 'PENDING');
     for (const t of Object.keys(EXCLUDED_TABLES)) add(t, 'EXCLUDED');
+    for (const t of Object.keys(CROSS_TENANT_TABLES)) add(t, 'CROSS_TENANT');
+    for (const t of Object.keys(GLOBAL_TABLES)) add(t, 'GLOBAL');
 
     const 중복 = [...seen.entries()]
       .filter(([, wheres]) => wheres.length > 1)
@@ -100,13 +167,19 @@ describe('[W6-A] 매장 백업 커버리지', () => {
   });
 
   it('선언에 인벤토리에 없는 유령 테이블이 없다', () => {
-    const inventory = new Set(readInventory());
-    // CUSTOM 에는 store_id 가 없어 조인으로 도달하는 테이블이 들어 있다 —
-    // 그것들은 인벤토리에 없는 것이 정상이므로 SIMPLE 과 EXCLUDED 만 본다.
+    // ★ [W6-C1] 기준선이 이제 **모든 실테이블**을 싣는다. 따라서 어느 목록에
+    //   있든 인벤토리에 있어야 한다 — 종전에는 CUSTOM 을 면제했는데, 그 면제가
+    //   "인벤토리에 없어도 되는 자리" 를 만들었다.
+    const inv = readInventory();
+    const inventory = new Set([...inv.tenant, ...inv.global]);
     const 유령 = [
       ...SIMPLE_STORE_TABLES,
+      ...Object.keys(CUSTOM_HANDLED_TABLES),
+      ...Object.keys(PENDING_BACKUP_TABLES),
       ...Object.keys(EXCLUDED_TABLES),
-    ].filter((t) => !inventory.has(t));
+      ...Object.keys(CROSS_TENANT_TABLES),
+      ...Object.keys(GLOBAL_TABLES),
+    ].filter((t) => !isIgnoredTable(t) && !inventory.has(t));
 
     expect({ 인벤토리에_없는_선언: 유령 }).toEqual({
       인벤토리에_없는_선언: [],
@@ -114,12 +187,22 @@ describe('[W6-A] 매장 백업 커버리지', () => {
   });
 
   // ── ② 마이그레이션 컷오프 ──────────────────────────────────────────────────
-  it('컷오프 이후 마이그레이션이 만든 store_id 테이블이 전부 선언돼 있다', () => {
+  it('★ 컷오프 이후 마이그레이션이 만든 **모든** 테이블이 선언돼 있다', () => {
+    // ★★ [W6-C1] 종전에는 본문에 `store_id` 가 있을 때만 검사했다.
+    //   그런데 ①(인벤토리)도 같은 `store_id` 기준이었다 —
+    //   **감시가 두 겹인데 두 겹이 같은 맹점을 공유**했고, 그래서
+    //   관계로만 매장에 닿는 테이블 42개가 양쪽을 조용히 통과했다.
+    //   이제 조건을 **없앤다**: 새로 만든 테이블은 매장 것이든 아니든
+    //   여섯 갈래 중 하나로 분류해야 한다. 분류가 부담이 아니라,
+    //   분류하지 않아도 되는 자리가 있는 것이 결함이었다.
     if (!fs.existsSync(MIGRATIONS_DIR)) {
       throw new Error(`migrations 디렉터리가 없다: ${MIGRATIONS_DIR}`);
     }
 
-    const declared = declaredTables();
+    const declared = new Map([
+      ...tenantDeclarations(),
+      ...globalDeclarations(),
+    ]);
     const 누락: string[] = [];
 
     const files = fs
@@ -140,19 +223,6 @@ describe('[W6-A] 매장 백업 커버리지', () => {
       while ((m = re.exec(code)) !== null) {
         const name = m[1].replace(/^public\./, '').replace(/"/g, '');
 
-        // 괄호 균형으로 본문을 잘라 store_id 유무를 본다.
-        let depth = 0;
-        let j = re.lastIndex - 1;
-        const start = j;
-        for (; j < code.length; j++) {
-          if (code[j] === '(') depth++;
-          else if (code[j] === ')') {
-            depth--;
-            if (depth === 0) break;
-          }
-        }
-        const body = code.slice(start, j);
-        if (!/\bstore_id\b/.test(body)) continue;
         if (isIgnoredTable(name)) continue;
         if (declared.has(name)) continue;
 
diff --git a/src/app/store/store-backup-coverage.ts b/src/app/store/store-backup-coverage.ts
index d5d1187..4efab29 100644
--- a/src/app/store/store-backup-coverage.ts
+++ b/src/app/store/store-backup-coverage.ts
@@ -223,6 +223,177 @@ export const EXCLUDED_TABLES: Readonly<Record<string, string>> = {
   code_imports:
     '코드 임포트 실행 이력. 결과물(제품·바코드)은 각 테이블에 남으므로 이력 자체는 복원 대상이 아니다.',
   legacy_imports: '임포트 잡 상태 — 진행 중 상태를 되살릴 이유가 없다.',
+  // ── [W6-C1] 관계로만 매장에 닿아 종전 기준선이 못 보던 것들 ────────────────
+  //   기준선이 `store_id` 컬럼을 소유권 권위로 써서 42개가 조용히 빠져 있었다.
+  mobile_sessions:
+    '모바일 세션. active_sessions 와 같은 이유 — 복원해도 유효하지 않고 토큰이 실린다.',
+  admin_device_tokens:
+    '관리자앱 기기 토큰. terminal_devices·vendedor_devices 와 같은 이유 — 자격증명이다.',
+  user_permission_cache:
+    '파생 캐시. 권한 원본(user_functions·role_functions)에서 재계산된다. ' +
+    '복원하면 낡은 권한이 되살아나므로 담지 않는다 — 커밋 후 재생성이 옳다.',
+  qr_print_log: 'QR 출력 이력. 진단용이며 복원해도 의미가 없다.',
+  client_access_audits:
+    '고객정보 접근 감사 로그. ★ "복원하지 않음" 과 "보존하지 않음" 은 다르다 — ' +
+    '보존은 별도 아카이브의 일이고, 신규 매장의 활성 데이터로 되살릴 것은 아니다.',
+};
+/**
+ * [Phase 85 W6-C1] **담기로 했지만 아직 안 담기는** 테이블.
+ *
+ * ★ 왜 이 목록이 따로 있나: 이것들을 `CUSTOM_HANDLED_TABLES` 에 넣으면 선언이
+ *   거짓말을 한다("전용 처리로 담고 있다" — 아니다). `EXCLUDED_TABLES` 에 넣으면
+ *   판단이 끝난 것처럼 읽힌다("안 담기로 했다" — 그것도 아니다).
+ *   **부채는 부채로 보여야 한다.** 그래서 세 번째 자리를 만들었다.
+ *
+ * ★ 이 목록은 백업 JSON 의 `coverage.pending` 으로 **파일 자신이 말한다.**
+ *   그러지 않으면 백업을 여는 사람이 완전하다고 믿는다 — W6 을 만든 바로 그 결함이다.
+ *
+ * 값은 **왜 담아야 하는지**다. 담기 시작하면 여기서 빼고 CUSTOM 으로 옮긴다.
+ */
+export const PENDING_BACKUP_TABLES: Readonly<Record<string, string>> = {
+  // ── 권한: 없으면 복원된 매장의 역할이 무력해진다 ──────────────────────────
+  role_function_actions:
+    '운영 40,557행. 권한 판정은 role_functions × role_function_actions 를 조인한다 — ' +
+    '부모만 담으면 "읽기만" 과 "삭제 가능" 의 구분이 통째로 사라진다.',
+  user_function_actions:
+    '개인 권한의 액션. role_function_actions 와 같은 이유.',
+  user_roles: '사용자↔역할 매핑. 빠지면 복원된 사용자에게 역할이 하나도 없다.',
+  user_branches: '사용자가 어느 지점에 접근하는지. 빠지면 지점 전환이 막힌다.',
+
+  // ── 금전: 회계 이력 ──────────────────────────────────────────────────────
+  box_operations: '금전함 조작 이력. 카하 정산 구간을 정하는 근거가 된다.',
+  caja_fuerte_operations: '금고 입출금 이력. 금고 잔액의 유일한 근거다.',
+  movements: '금전함 사이의 현금 이동. 카하 잔액 계산에 들어간다.',
+
+  // ── 판매·주문의 자식 행 ──────────────────────────────────────────────────
+  online_order_items:
+    '온라인 주문 품목. 주문만 담고 품목을 빼면 주문이 빈 껍데기가 된다.',
+  online_returns:
+    '온라인 반품. 주문의 자식이라 online_orders 만 담으면 반품 이력이 사라진다.',
+  venta_suspendida_items:
+    '보류 판매 품목. ventas_suspendidas 만 담으면 보류 건이 빈 껍데기가 된다.',
+  venta_suspendida_discounts: '보류 판매에 걸린 할인. 금액 재계산의 근거다.',
+  venta_suspendida_recharges: '보류 판매에 걸린 추가금. 금액 재계산의 근거다.',
+  discount_reasons: '판매 할인의 사유 기록. 할인 감사·분쟁의 근거가 된다.',
+
+  // ── 상품·가격·할인 매핑 ──────────────────────────────────────────────────
+  product_subcategories:
+    '상품↔소분류 매핑. 빠지면 복원된 상품이 분류 없이 뜬다.',
+  product_discounts:
+    '어느 상품에 할인이 걸렸는지. 빠지면 할인이 아무 데도 안 걸린다.',
+  subcategory_discounts:
+    '어느 소분류에 할인이 걸렸는지. product_discounts 와 같은 이유.',
+  payment_methods_discounts:
+    '결제수단별 할인·할증. 판매 금액 계산에 직접 들어간다.',
+  payment_methods_options:
+    '결제수단 옵션(분할 등). sale_payment_methods.option_id 가 이걸 가리킨다 — ' +
+    '빼면 복원된 판매의 결제 옵션이 남의 매장 행을 가리킨다.',
+
+  // ── 지점 설정·장비 ───────────────────────────────────────────────────────
+  branch_price_types_disabled:
+    '지점별로 끈 가격유형. 빠지면 복원된 지점에서 꺼 둔 가격이 다시 보인다.',
+  branch_printer_configs:
+    '지점 프린터 설정. 복원 후 출력이 안 되면 이것이 빠진 것이다.',
+  branch_agents:
+    '프린터 에이전트. terminals.thermal_agent_id/zebra_agent_id 가 가리킨다. ' +
+    '★ 설정은 담되 api_key 는 마스킹하고 에이전트 신원은 **재등록 대상**이다 — ' +
+    '복제된 매장이 원본의 자격증명을 재사용하면 안 된다(codex, 2026-08-22).',
+
+  // ── 지출·외주·기타 ───────────────────────────────────────────────────────
+  expense_cheques:
+    '지출과 수표의 연결. 빠지면 수표가 어느 지출인지 못 되짚는다.',
+  talleres_vendor_etapas:
+    '공방이 어느 공정을 맡는지. 빠지면 외주 발주가 대상을 잃는다.',
+  talleres_envio_materiales: '공방 발송에 딸린 자재. 반환 대조의 근거다.',
+  talleres_defects: '외주 불량과 차감액. 공방 정산 금액에 직접 들어간다.',
+  talleres_material_issues: '외주로 내보낸 자재. 손실 판정의 근거가 된다.',
+  shared_folder_role_access:
+    '공유 폴더의 역할별 접근 권한. 빠지면 복원 후 아무도 못 연다.',
+  rider_settlement_items: '배달원 정산의 개별 항목. 정산 금액의 근거다.',
+  campaign_recipients:
+    '캠페인 수신자. ★ 단순 이력인지 **발송 대기 상태**인지 확인이 필요하다 — ' +
+    '대기 상태가 섞여 있으면 복원이 재발송을 일으킨다(codex, 2026-08-22).',
+
+  // ── MercadoPago 지갑 계열 ────────────────────────────────────────────────
+  //   ★ 테이블 단위 분류로 부족하다. 모드마다 답이 다르다(codex, 2026-08-22):
+  //     복제(clone)      → 외부 결제 식별자를 복제할 수 없으므로 활성 원장으로 복원 금지
+  //     재해복구(restore) → 회계 원장이므로 포함해야 한다
+  //   지금은 **백업에는 담고**, 복원 쪽에서 모드별로 가른다.
+  mp_movements: 'MP 지갑 입출금. 가상 카하 잔액의 근거다. 모드별 정책 필요.',
+  mp_transfers: 'MP 지갑 → 카하 이체. 현금 흐름의 일부다. 모드별 정책 필요.',
+  mp_refunds: 'MP 환불 기록. 판매 취소와 짝을 이룬다. 모드별 정책 필요.',
+  mp_refund_attempts: 'MP 환불 시도 이력. 실패 원인 추적용. 모드별 정책 필요.',
+};
+
+/**
+ * [Phase 85 W6-C1] **여러 매장이 함께 쓰는** 테이블. 한 매장의 것이 아니다.
+ *
+ * ★ 관계로는 `stores` 에 닿는다(`created_by_store_id` 등). 하지만 그건
+ *   **"누가 처음 만들었나"** 이지 **"누구 것인가"** 가 아니다.
+ *   FK 도달을 그대로 소유권으로 읽으면 여기서 틀린다 — 내가 실제로 틀렸고
+ *   codex 가 잡았다(2026-08-22).
+ *
+ * 복원은 이 테이블들을 **만들지도 지우지도 않는다.** 참조하는 FK 는
+ * `KEEP_GLOBAL` 로 다룬다. 새 ID 로 복제하면 전역 레지스트리가 매장 수만큼 불어나고,
+ * 원 ID 를 유지하면 새 매장이 남의 매장 행을 가리킨다 — 둘 다 틀렸다.
+ */
+export const CROSS_TENANT_TABLES: Readonly<Record<string, string>> = {
+  global_clients:
+    '매장 공통 고객 레지스트리(운영 3,773행). created_by_store_id 는 최초 생성자일 뿐이다. ' +
+    '★ owner_group_id 범위로 공유되므로, 복원 시 대상 매장이 같은 소유자 그룹인지 ' +
+    '검사해야 한다 — 다른 그룹이면 KEEP 도 복제도 안 된다(codex, 2026-08-22).',
+  global_categories: '전역 카테고리 레지스트리. global_clients 와 같은 이유.',
+  global_subcategories: '전역 소분류 레지스트리. 같은 이유.',
+  pending_registrations:
+    '가입 대기 큐. referrer_store_id 는 추천인이지 소유자가 아니다.',
+  referral_credits:
+    '추천 크레딧. referrer_store_id 와 referred_store_id 로 **두 매장에 걸쳐 있다** — ' +
+    '어느 한 매장의 백업에 담을 수 없다.',
+  revendedor_categories:
+    '재판매자↔전역 카테고리 매핑. 재판매자는 매장 소유가 아니다.',
+};
+
+/**
+ * [Phase 85 W6-C1] 매장과 무관한 테이블 — 전역 참조 / 시스템 / 레거시.
+ *
+ * ★ 왜 이것까지 선언하나: 기준선이 **모든 테이블**을 싣기 때문이다.
+ *   "목록에 없으면 검사도 없다" 를 없애는 것이 W6-C1 의 목적이다.
+ *   여기 없는 테이블이 새로 생기면 빌드가 깨지고, 그때 사람이 분류한다.

hook: PostToolUse
hook: PostToolUse
hook: PostToolUse Failed
hook: PostToolUse Completed
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse Failed
hook: PreToolUse Completed
hook: PreToolUse Completed
exec
/bin/zsh -lc "sed -n '481,720p' .team/reviews/w6c1-diff.txt" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 0ms:
+ */
+export const GLOBAL_TABLES: Readonly<Record<string, string>> = {
+  // 전역 참조 데이터 — 모든 매장이 같은 행을 읽는다.
+  provinces: '아르헨티나 주 목록. 전역 참조.',
+  nations: '국가 목록. 전역 참조.',
+  apps: '앱(모듈) 카탈로그. store_apps 가 매장별 활성화를 갖는다.',
+  functions: '권한 기능 카탈로그. 매장별 부여는 role_functions 가 갖는다.',
+  modules: '기능 모듈 카탈로그. 전역 정의이며 매장별 값이 없다.',
+  permissions: '레거시 권한 카탈로그. 매장별 부여가 아니라 전역 정의다.',
+  daily_quotes: '환율/시세 일별 값. 전역이다.',
+  subscription_config: '구독 요금 설정. 플랫폼 전역.',
+
+  // 플랫폼 운영 — 매장 데이터가 아니다.
+  cron_leases: '크론 리더 선출 lease. 런타임 상태.',
+  app_boot_flags: '부팅 플래그. 런타임 상태.',
+  slow_query_log: '느린 쿼리 진단 로그.',
+  backfill_failures: '백필 실패 기록. 운영 진단용.',
+  verification_codes: '인증 코드(가입·복구). 단명하며 매장 소유가 아니다.',
+  vto_settings: 'VTO 전역 설정.',
+  revendedores: '재판매자 마스터. 매장이 아니라 플랫폼에 속한다.',
+
+  // 레거시 — 사용되지 않는다(운영 실측 0행). 지우기 전까지 분류만 해 둔다.
+  _phase26_cat_map: '레거시 Phase 26 카테고리 매핑. 운영 0행.',
+  category_discounts:
+    '레거시 할인 매핑. 운영 0행. subcategory_discounts 로 대체됨.',
+  product_categories:
+    '레거시 상품↔카테고리. 운영 0행. products.category_id 가 현행이다.',
+  product_variants: '레거시 변형. 운영 0행. ProductBranch 가 현행이다.',
+  variants: '레거시 변형. 운영 0행.',
+  variant_types: '레거시 변형 종류. 운영 0행.',
+  role_permissions: '레거시 권한 모델. 운영 0행. role_functions 가 현행이다.',
+  role_permission_functions: '레거시 권한 모델. 운영 0행.',
+  user_permissions: '레거시 권한 모델. 운영 0행. user_functions 가 현행이다.',
+  user_permission_functions: '레거시 권한 모델. 운영 0행.',
+  stock_cache_backfill_20260729: '2026-07-29 재고 캐시 백필 작업 테이블.',
 };
 
 /** 인벤토리에서 무시하는 이름 패턴 — 뷰와 임시 스냅샷. */
diff --git a/src/app/store/store.service.ts b/src/app/store/store.service.ts
index 82b7a72..7031142 100644
--- a/src/app/store/store.service.ts
+++ b/src/app/store/store.service.ts
@@ -38,6 +38,8 @@ import { syntheticEmail } from '../users/synthetic-email';
 import {
   SIMPLE_STORE_TABLES,
   EXCLUDED_TABLES,
+  PENDING_BACKUP_TABLES,
+  CROSS_TENANT_TABLES,
   LEGACY_JSON_KEYS,
   redactBackupRows,
 } from './store-backup-coverage';
@@ -1361,6 +1363,15 @@ export class StoreService extends CrudService<Store> {
         simpleTables: SIMPLE_STORE_TABLES.length,
         excluded: Object.keys(EXCLUDED_TABLES),
         excludedReasons: EXCLUDED_TABLES,
+        // ★ [W6-C1] **아직 안 담기는 것을 파일이 스스로 말한다.**
+        //   기준선을 관계 기반으로 바꾸니 매장에 속하는 테이블 42개가
+        //   백업에도 제외 선언에도 없이 빠져 있었다(role_function_actions 40,557행 등).
+        //   담는 작업은 W6-C2 지만, 그 전에 **이 파일이 완전하지 않다는 사실**은
+        //   지금 말해야 한다 — 완전한 줄 알고 매장을 지우는 것이 W6 의 출발점이었다.
+        pending: Object.keys(PENDING_BACKUP_TABLES),
+        pendingReasons: PENDING_BACKUP_TABLES,
+        // 여러 매장이 공유하므로 한 매장의 백업에 담을 수 없는 것들.
+        crossTenant: Object.keys(CROSS_TENANT_TABLES),
         // ★ 담기로 선언했는데 **읽지 못한** 테이블. 보통은 비어 있어야 한다.
         //   비어 있지 않다면 스키마가 선언보다 뒤처졌다는 뜻이다.
         unreadable,

===== 신규: migrations/2026-08-22-w6-talleres-missing-fks.sql =====
-- [Phase 85 W6-C1] talleres 4개 테이블에 **빠져 있던 FK 제약**을 추가한다.
--
-- ★ 왜 필요한가:
--   W6-C1 에서 매장 백업의 기준선을 "`store_id` 컬럼 보유" 에서
--   "`stores` 로부터의 FK 도달 폐포" 로 바꿨다. 소유권의 권위는 컬럼이 아니라
--   관계이기 때문이다(2026-08-21 codex 지적을 인벤토리에도 적용).
--
--   그런데 아래 4개는 **FK 제약이 하나도 없다.** 컬럼(`subcon_order_id` 등)은 있는데
--   DB 가 그 관계를 모른다. 그래서 관계 기반 분류가 이들을 `global`(매장과 무관)로
--   **오분류**한다 — 실제로는 매장 데이터이고, 둘은 이미 백업 대상으로 선언돼 있다.
--
--   즉 **그래프가 거짓말을 하고 있고, 우리는 그 그래프를 권위로 삼으려 한다.**
--   그래프를 사실에 맞추는 것이 옳은 순서다.
--
-- ★ 안전성 (2026-08-22 운영 실측):
--   네 테이블 모두 **0행**이고 고아 참조도 **0건**이다.
--   빈 테이블의 FK 추가는 전수 검사할 행이 없어 즉시 끝난다.
--
-- w4-exempt: 대상이 전부 0행이라 잠금 보유 시간이 사실상 없다. NOT VALID → VALIDATE
--            2단계는 검사할 기존 행이 있을 때 의미가 있는데 여기서는 해당 없다.
--            (그래도 lock_timeout 은 건다 — 앞선 장기 트랜잭션에 끌려가지 않기 위해.)

SET lock_timeout = '5s';

-- talleres_deliveries.subcon_order_id → talleres_orders.id
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname = 'fk_talleres_deliveries_order'
       AND conrelid = 'talleres_deliveries'::regclass
  ) THEN
    ALTER TABLE talleres_deliveries
      ADD CONSTRAINT fk_talleres_deliveries_order
      FOREIGN KEY (subcon_order_id) REFERENCES talleres_orders(id);
  END IF;
END $$;

-- talleres_payments.subcon_settlement_id → talleres_settlements.id
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname = 'fk_talleres_payments_settlement'
       AND conrelid = 'talleres_payments'::regclass
  ) THEN
    ALTER TABLE talleres_payments
      ADD CONSTRAINT fk_talleres_payments_settlement
      FOREIGN KEY (subcon_settlement_id) REFERENCES talleres_settlements(id);
  END IF;
END $$;

-- talleres_material_issues.subcon_order_id → talleres_orders.id
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname = 'fk_talleres_material_issues_order'
       AND conrelid = 'talleres_material_issues'::regclass
  ) THEN
    ALTER TABLE talleres_material_issues
      ADD CONSTRAINT fk_talleres_material_issues_order
      FOREIGN KEY (subcon_order_id) REFERENCES talleres_orders(id);
  END IF;
END $$;

-- talleres_defects.subcon_delivery_id → talleres_deliveries.id
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname = 'fk_talleres_defects_delivery'
       AND conrelid = 'talleres_defects'::regclass
  ) THEN
    ALTER TABLE talleres_defects
      ADD CONSTRAINT fk_talleres_defects_delivery
      FOREIGN KEY (subcon_delivery_id) REFERENCES talleres_deliveries(id);
  END IF;
END $$;

-- 검증:
--   SELECT conrelid::regclass AS tabla, conname
--     FROM pg_constraint
--    WHERE contype = 'f'
--      AND conrelid IN ('talleres_deliveries'::regclass, 'talleres_payments'::regclass,
--                       'talleres_material_issues'::regclass, 'talleres_defects'::regclass)
--    ORDER BY 1, 2;
--   -- 결과 4행이어야 한다.
--
-- 되돌리기:
--   ALTER TABLE talleres_deliveries      DROP CONSTRAINT fk_talleres_deliveries_order;
--   ALTER TABLE talleres_payments        DROP CONSTRAINT fk_talleres_payments_settlement;
--   ALTER TABLE talleres_material_issues DROP CONSTRAINT fk_talleres_material_issues_order;
--   ALTER TABLE talleres_defects         DROP CONSTRAINT fk_talleres_defects_delivery;

===== 기준선 요약 (전체 216: tenant 187 / global 29) =====
187
29

hook: PostToolUse
hook: PostToolUse
hook: PostToolUse Failed
hook: PostToolUse Completed
codex
핵심 감시 경로에서 `CREATE TABLE`이 아닌 스키마 변화가 기준선을 우회할 수 있는지, 그리고 선언과 실제 분류가 서로 검증되는지를 중심으로 확인했습니다. 이제 같은 파일의 줄번호만 붙여 보고서를 정리하겠습니다.
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse Failed
hook: PreToolUse Completed
hook: PreToolUse Completed
exec
/bin/zsh -lc "nl -ba .team/reviews/w6c1-diff.txt | sed -n '35,230p;300,570p'" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 0ms:
    35	@@ -19,15 +36,39 @@ set -euo pipefail
    36	 OUT="$(cd "$(dirname "$0")/.." && pwd)/src/app/store/store-backup-inventory.txt"
    37	 TARGET="${PGTARGET:-local}"
    38	 
    39	-SQL="SELECT c.relname
    40	-       FROM pg_class c
    41	-       JOIN pg_namespace n ON n.oid = c.relnamespace
    42	-       JOIN information_schema.columns col
    43	-         ON col.table_name = c.relname
    44	-        AND col.table_schema = 'public'
    45	-        AND col.column_name = 'store_id'
    46	-      WHERE n.nspname = 'public' AND c.relkind = 'r'
    47	-      ORDER BY 1"
    48	+# 테넌트 폐포: stores 자신 + store_id 컬럼 보유 테이블에서 출발해 FK 를 자식 방향으로 따라간다.
    49	+# depth 상한 20 은 순환 방어다 (UNION 이 이미 중복을 접지만 명시적으로 둔다).
    50	+SQL="WITH RECURSIVE fk AS (
    51	+        SELECT con.conrelid AS src, con.confrelid AS ref
    52	+          FROM pg_constraint con
    53	+          JOIN pg_class c ON c.oid = con.conrelid
    54	+          JOIN pg_namespace n ON n.oid = c.relnamespace
    55	+         WHERE con.contype = 'f' AND n.nspname = 'public'
    56	+           AND con.conrelid <> con.confrelid
    57	+      ),
    58	+      seed AS (
    59	+        SELECT c.oid
    60	+          FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    61	+         WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relname = 'stores'
    62	+        UNION
    63	+        SELECT c.oid
    64	+          FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    65	+          JOIN information_schema.columns col
    66	+            ON col.table_schema = 'public' AND col.table_name = c.relname
    67	+           AND col.column_name = 'store_id'
    68	+         WHERE n.nspname = 'public' AND c.relkind = 'r'
    69	+      ),
    70	+      reach AS (
    71	+        SELECT oid, 0 AS depth FROM seed
    72	+        UNION
    73	+        SELECT fk.src, r.depth + 1 FROM fk JOIN reach r ON fk.ref = r.oid
    74	+         WHERE r.depth < 20
    75	+      )
    76	+      SELECT CASE WHEN c.oid IN (SELECT oid FROM reach) THEN 'tenant' ELSE 'global' END
    77	+             || ':' || c.relname
    78	+        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    79	+       WHERE n.nspname = 'public' AND c.relkind = 'r'
    80	+       ORDER BY c.relname"
    81	 
    82	 case "$TARGET" in
    83	   local) TABLES=$(psql -p 5432 -d ventago -tAc "$SQL") ; SRC="로컬 Mac PG18 ventago (5432)" ;;
    84	@@ -39,17 +80,23 @@ esac
    85	 # ★ 빈 결과를 그대로 쓰지 않는다. 접속 실패가 "테이블이 하나도 없다" 로 둔갑하면
    86	 #   커버리지 spec 이 **아무것도 검사하지 않으면서 통과**한다. 0건은 항상 오류다.
    87	 COUNT=$(printf '%s\n' "$TABLES" | grep -c . || true)
    88	-if [ "$COUNT" -lt 50 ]; then
    89	-  echo "✗ store_id 테이블이 ${COUNT}개로 나왔다 — 접속 실패를 의심한다. 파일을 안 바꾼다." >&2
    90	+TENANTS=$(printf '%s\n' "$TABLES" | grep -c '^tenant:' || true)
    91	+if [ "$COUNT" -lt 150 ] || [ "$TENANTS" -lt 100 ]; then
    92	+  echo "✗ 테이블 ${COUNT}개(테넌트 ${TENANTS}개)로 나왔다 — 접속 실패를 의심한다. 파일을 안 바꾼다." >&2
    93	   exit 1
    94	 fi
    95	 
    96	 {
    97	-  echo "# [Phase 85 W6-A] store_id 를 가진 **실제 테이블** 목록 (뷰 제외)."
    98	+  echo "# [Phase 85 W6-A / W6-C1] public 스키마의 **모든 실테이블** 분류 (뷰 제외)."
    99	+  echo "#"
   100	+  echo "# 형식: tenant:<테이블>  또는  global:<테이블>"
   101	+  echo "#   tenant = store_id 컬럼이 있거나, stores 에서 FK 로 도달한다"
   102	+  echo "#   global = 위 어느 쪽도 아니다 (전역 참조 / 시스템 / 레거시)"
   103	   echo "#"
   104	   echo "# 이 파일은 store-backup-coverage.spec.ts 의 기준선이다."
   105	-  echo "# 여기 있는 테이블은 반드시 SIMPLE_STORE_TABLES / CUSTOM_HANDLED_TABLES /"
   106	-  echo "# EXCLUDED_TABLES 중 한 곳에 있어야 한다. 없으면 빌드가 깨진다."
   107	+  echo "# tenant 는 SIMPLE_STORE_TABLES / CUSTOM_HANDLED_TABLES / EXCLUDED_TABLES 중"
   108	+  echo "# 한 곳에, global 은 GLOBAL_TABLES 에 **이유와 함께** 있어야 한다."
   109	+  echo "# 어느 쪽도 아니면 빌드가 깨진다 — 조용히 빠지는 테이블을 없애는 것이 목적이다."
   110	   echo "#"
   111	   echo "# 재생성: scripts/regen-store-backup-inventory.sh"
   112	   echo "# 생성 기준: ${SRC} $(date -u +%Y-%m-%dT%H:%M:%SZ)"
   113	@@ -57,7 +104,7 @@ fi
   114	   printf '%s\n' "$TABLES" | grep -v '^$'
   115	 } > "$OUT"
   116	 
   117	-echo "✓ ${OUT} 갱신 (${COUNT}개)"
   118	+echo "✓ ${OUT} 갱신 (전체 ${COUNT}개 / 테넌트 ${TENANTS}개)"
   119	 
   120	 # ── 민감 컬럼 인벤토리 ──────────────────────────────────────────────────────
   121	 # ★ 패턴을 여기 복사해 두지 않는다. store-backup-coverage.ts 의
   122	diff --git a/src/app/store/store-backup-coverage.spec.ts b/src/app/store/store-backup-coverage.spec.ts
   123	index de5ca1b..54b5e16 100644
   124	--- a/src/app/store/store-backup-coverage.spec.ts
   125	+++ b/src/app/store/store-backup-coverage.spec.ts
   126	@@ -21,6 +21,9 @@ import {
   127	   SIMPLE_STORE_TABLES,
   128	   CUSTOM_HANDLED_TABLES,
   129	   EXCLUDED_TABLES,
   130	+  PENDING_BACKUP_TABLES,
   131	+  CROSS_TENANT_TABLES,
   132	+  GLOBAL_TABLES,
   133	   REDACTED_COLUMNS,
   134	   REVIEWED_SAFE_COLUMNS,
   135	   looksSensitive,
   136	@@ -34,23 +37,56 @@ const MIGRATIONS_DIR = path.join(__dirname, '..', '..', '..', 'migrations');
   137	 /** 이 날짜 이후 마이그레이션부터 ②를 강제한다. 소급하지 않는다 — ①이 그 몫이다. */
   138	 const CUTOFF = '2026-08-21';
   139	 
   140	-function declaredTables(): Map<string, string> {
   141	+/** 매장에 속하는 테이블의 선언 자리 (담김 / 부채 / 제외). */
   142	+function tenantDeclarations(): Map<string, string> {
   143	   const m = new Map<string, string>();
   144	   for (const t of SIMPLE_STORE_TABLES) m.set(t, 'SIMPLE_STORE_TABLES');
   145	   for (const t of Object.keys(CUSTOM_HANDLED_TABLES))
   146	     m.set(t, 'CUSTOM_HANDLED_TABLES');
   147	+  for (const t of Object.keys(PENDING_BACKUP_TABLES))
   148	+    m.set(t, 'PENDING_BACKUP_TABLES');
   149	   for (const t of Object.keys(EXCLUDED_TABLES)) m.set(t, 'EXCLUDED_TABLES');
   150	+  for (const t of Object.keys(CROSS_TENANT_TABLES))
   151	+    m.set(t, 'CROSS_TENANT_TABLES');
   152	 
   153	   return m;
   154	 }
   155	 
   156	-function readInventory(): string[] {
   157	-  const raw = fs.readFileSync(INVENTORY, 'utf8');
   158	+/** 매장 것이 아닌 테이블의 선언 자리. */
   159	+function globalDeclarations(): Map<string, string> {
   160	+  const m = new Map<string, string>();
   161	+  for (const t of Object.keys(GLOBAL_TABLES)) m.set(t, 'GLOBAL_TABLES');
   162	 
   163	-  return raw
   164	-    .split('\n')
   165	-    .map((l) => l.trim())
   166	-    .filter((l) => l && !l.startsWith('#'));
   167	+  return m;
   168	+}
   169	+
   170	+/**
   171	+ * 기준선을 `tenant` / `global` 로 나눠 읽는다.
   172	+ *
   173	+ * ★ [W6-C1] 형식이 바뀌었다: `tenant:<테이블>` / `global:<테이블>`.
   174	+ *   종전에는 `store_id` 컬럼을 가진 테이블 이름만 한 줄씩 있었는데,
   175	+ *   그 기준이 관계로만 매장에 닿는 테이블 42개를 못 봤다.
   176	+ */
   177	+function readInventory(): { tenant: string[]; global: string[] } {
   178	+  const out = { tenant: [] as string[], global: [] as string[] };
   179	+  for (const line of fs.readFileSync(INVENTORY, 'utf8').split('\n')) {
   180	+    const l = line.trim();
   181	+    if (!l || l.startsWith('#')) continue;
   182	+    const at = l.indexOf(':');
   183	+
   184	+    // ★ 옛 형식(분류 없는 이름만)을 조용히 넘기지 않는다. 넘기면 재생성을
   185	+    //   잊은 기준선이 **아무것도 검사하지 않으면서 통과**한다.
   186	+    expect(at).toBeGreaterThan(0);
   187	+
   188	+    const cls = l.slice(0, at);
   189	+    const table = l.slice(at + 1);
   190	+    expect(['tenant', 'global']).toContain(cls);
   191	+    if (isIgnoredTable(table)) continue;
   192	+    if (cls === 'tenant') out.tenant.push(table);
   193	+    else out.global.push(table);
   194	+  }
   195	+
   196	+  return out;
   197	 }
   198	 
   199	 describe('[W6-A] 매장 백업 커버리지', () => {
   200	@@ -58,20 +94,48 @@ describe('[W6-A] 매장 백업 커버리지', () => {
   201	   it('인벤토리가 비어 있지 않다 (빈 기준선은 아무것도 검사하지 않으면서 통과한다)', () => {
   202	     // ★ 이 검사가 먼저인 이유: 파일이 비면 아래 검사가 전부 **0건을 순회하며 통과**한다.
   203	     //   "수집 0건은 위반 0건이 아니다" — 이 저장소가 이미 당한 형태다.
   204	-    expect(readInventory().length).toBeGreaterThan(50);
   205	+    const inv = readInventory();
   206	+    expect(inv.tenant.length).toBeGreaterThan(100);
   207	+    expect(inv.global.length).toBeGreaterThan(5);
   208	   });
   209	 
   210	-  it('store_id 를 가진 모든 테이블이 담기거나, 이유와 함께 제외돼 있다', () => {
   211	-    const declared = declaredTables();
   212	-    const missing = readInventory()
   213	-      .filter((t) => !isIgnoredTable(t))
   214	-      .filter((t) => !declared.has(t));
   215	+  it('★ 매장에 속하는 모든 테이블이 다섯 갈래 중 하나에 선언돼 있다', () => {
   216	+    // ★ [W6-C1] 판정 기준이 `store_id` 컬럼에서 **관계 도달**로 바뀌었다.
   217	+    //   종전 기준은 관계로만 닿는 42개를 못 봤고, 마이그레이션 컷오프도 같은
   218	+    //   `store_id` 조건을 봤기 때문에 **감시 두 겹이 같은 맹점을 공유**했다.
   219	+    const declared = tenantDeclarations();
   220	+    const missing = readInventory().tenant.filter((t) => !declared.has(t));
   221	 
   222	-    expect({ 선언되지_않은_테이블: missing }).toEqual({
   223	-      선언되지_않은_테이블: [],
   224	+    expect({ 선언되지_않은_매장테이블: missing }).toEqual({
   225	+      선언되지_않은_매장테이블: [],
   226	     });
   227	   });
   228	 
   229	+  it('★ 매장 것이 아닌 테이블도 전부 이유와 함께 선언돼 있다', () => {
   230	+    // 여기가 없으면 "폐포 밖" 이 곧 "검사 밖" 이 된다 — 새 테이블이 숨을 자리가 생긴다.
   300	+    //   **감시가 두 겹인데 두 겹이 같은 맹점을 공유**했고, 그래서
   301	+    //   관계로만 매장에 닿는 테이블 42개가 양쪽을 조용히 통과했다.
   302	+    //   이제 조건을 **없앤다**: 새로 만든 테이블은 매장 것이든 아니든
   303	+    //   여섯 갈래 중 하나로 분류해야 한다. 분류가 부담이 아니라,
   304	+    //   분류하지 않아도 되는 자리가 있는 것이 결함이었다.
   305	     if (!fs.existsSync(MIGRATIONS_DIR)) {
   306	       throw new Error(`migrations 디렉터리가 없다: ${MIGRATIONS_DIR}`);
   307	     }
   308	 
   309	-    const declared = declaredTables();
   310	+    const declared = new Map([
   311	+      ...tenantDeclarations(),
   312	+      ...globalDeclarations(),
   313	+    ]);
   314	     const 누락: string[] = [];
   315	 
   316	     const files = fs
   317	@@ -140,19 +223,6 @@ describe('[W6-A] 매장 백업 커버리지', () => {
   318	       while ((m = re.exec(code)) !== null) {
   319	         const name = m[1].replace(/^public\./, '').replace(/"/g, '');
   320	 
   321	-        // 괄호 균형으로 본문을 잘라 store_id 유무를 본다.
   322	-        let depth = 0;
   323	-        let j = re.lastIndex - 1;
   324	-        const start = j;
   325	-        for (; j < code.length; j++) {
   326	-          if (code[j] === '(') depth++;
   327	-          else if (code[j] === ')') {
   328	-            depth--;
   329	-            if (depth === 0) break;
   330	-          }
   331	-        }
   332	-        const body = code.slice(start, j);
   333	-        if (!/\bstore_id\b/.test(body)) continue;
   334	         if (isIgnoredTable(name)) continue;
   335	         if (declared.has(name)) continue;
   336	 
   337	diff --git a/src/app/store/store-backup-coverage.ts b/src/app/store/store-backup-coverage.ts
   338	index d5d1187..4efab29 100644
   339	--- a/src/app/store/store-backup-coverage.ts
   340	+++ b/src/app/store/store-backup-coverage.ts
   341	@@ -223,6 +223,177 @@ export const EXCLUDED_TABLES: Readonly<Record<string, string>> = {
   342	   code_imports:
   343	     '코드 임포트 실행 이력. 결과물(제품·바코드)은 각 테이블에 남으므로 이력 자체는 복원 대상이 아니다.',
   344	   legacy_imports: '임포트 잡 상태 — 진행 중 상태를 되살릴 이유가 없다.',
   345	+  // ── [W6-C1] 관계로만 매장에 닿아 종전 기준선이 못 보던 것들 ────────────────
   346	+  //   기준선이 `store_id` 컬럼을 소유권 권위로 써서 42개가 조용히 빠져 있었다.
   347	+  mobile_sessions:
   348	+    '모바일 세션. active_sessions 와 같은 이유 — 복원해도 유효하지 않고 토큰이 실린다.',
   349	+  admin_device_tokens:
   350	+    '관리자앱 기기 토큰. terminal_devices·vendedor_devices 와 같은 이유 — 자격증명이다.',
   351	+  user_permission_cache:
   352	+    '파생 캐시. 권한 원본(user_functions·role_functions)에서 재계산된다. ' +
   353	+    '복원하면 낡은 권한이 되살아나므로 담지 않는다 — 커밋 후 재생성이 옳다.',
   354	+  qr_print_log: 'QR 출력 이력. 진단용이며 복원해도 의미가 없다.',
   355	+  client_access_audits:
   356	+    '고객정보 접근 감사 로그. ★ "복원하지 않음" 과 "보존하지 않음" 은 다르다 — ' +
   357	+    '보존은 별도 아카이브의 일이고, 신규 매장의 활성 데이터로 되살릴 것은 아니다.',
   358	+};
   359	+/**
   360	+ * [Phase 85 W6-C1] **담기로 했지만 아직 안 담기는** 테이블.
   361	+ *
   362	+ * ★ 왜 이 목록이 따로 있나: 이것들을 `CUSTOM_HANDLED_TABLES` 에 넣으면 선언이
   363	+ *   거짓말을 한다("전용 처리로 담고 있다" — 아니다). `EXCLUDED_TABLES` 에 넣으면
   364	+ *   판단이 끝난 것처럼 읽힌다("안 담기로 했다" — 그것도 아니다).
   365	+ *   **부채는 부채로 보여야 한다.** 그래서 세 번째 자리를 만들었다.
   366	+ *
   367	+ * ★ 이 목록은 백업 JSON 의 `coverage.pending` 으로 **파일 자신이 말한다.**
   368	+ *   그러지 않으면 백업을 여는 사람이 완전하다고 믿는다 — W6 을 만든 바로 그 결함이다.
   369	+ *
   370	+ * 값은 **왜 담아야 하는지**다. 담기 시작하면 여기서 빼고 CUSTOM 으로 옮긴다.
   371	+ */
   372	+export const PENDING_BACKUP_TABLES: Readonly<Record<string, string>> = {
   373	+  // ── 권한: 없으면 복원된 매장의 역할이 무력해진다 ──────────────────────────
   374	+  role_function_actions:
   375	+    '운영 40,557행. 권한 판정은 role_functions × role_function_actions 를 조인한다 — ' +
   376	+    '부모만 담으면 "읽기만" 과 "삭제 가능" 의 구분이 통째로 사라진다.',
   377	+  user_function_actions:
   378	+    '개인 권한의 액션. role_function_actions 와 같은 이유.',
   379	+  user_roles: '사용자↔역할 매핑. 빠지면 복원된 사용자에게 역할이 하나도 없다.',
   380	+  user_branches: '사용자가 어느 지점에 접근하는지. 빠지면 지점 전환이 막힌다.',
   381	+
   382	+  // ── 금전: 회계 이력 ──────────────────────────────────────────────────────
   383	+  box_operations: '금전함 조작 이력. 카하 정산 구간을 정하는 근거가 된다.',
   384	+  caja_fuerte_operations: '금고 입출금 이력. 금고 잔액의 유일한 근거다.',
   385	+  movements: '금전함 사이의 현금 이동. 카하 잔액 계산에 들어간다.',
   386	+
   387	+  // ── 판매·주문의 자식 행 ──────────────────────────────────────────────────
   388	+  online_order_items:
   389	+    '온라인 주문 품목. 주문만 담고 품목을 빼면 주문이 빈 껍데기가 된다.',
   390	+  online_returns:
   391	+    '온라인 반품. 주문의 자식이라 online_orders 만 담으면 반품 이력이 사라진다.',
   392	+  venta_suspendida_items:
   393	+    '보류 판매 품목. ventas_suspendidas 만 담으면 보류 건이 빈 껍데기가 된다.',
   394	+  venta_suspendida_discounts: '보류 판매에 걸린 할인. 금액 재계산의 근거다.',
   395	+  venta_suspendida_recharges: '보류 판매에 걸린 추가금. 금액 재계산의 근거다.',
   396	+  discount_reasons: '판매 할인의 사유 기록. 할인 감사·분쟁의 근거가 된다.',
   397	+
   398	+  // ── 상품·가격·할인 매핑 ──────────────────────────────────────────────────
   399	+  product_subcategories:
   400	+    '상품↔소분류 매핑. 빠지면 복원된 상품이 분류 없이 뜬다.',
   401	+  product_discounts:
   402	+    '어느 상품에 할인이 걸렸는지. 빠지면 할인이 아무 데도 안 걸린다.',
   403	+  subcategory_discounts:
   404	+    '어느 소분류에 할인이 걸렸는지. product_discounts 와 같은 이유.',
   405	+  payment_methods_discounts:
   406	+    '결제수단별 할인·할증. 판매 금액 계산에 직접 들어간다.',
   407	+  payment_methods_options:
   408	+    '결제수단 옵션(분할 등). sale_payment_methods.option_id 가 이걸 가리킨다 — ' +
   409	+    '빼면 복원된 판매의 결제 옵션이 남의 매장 행을 가리킨다.',
   410	+
   411	+  // ── 지점 설정·장비 ───────────────────────────────────────────────────────
   412	+  branch_price_types_disabled:
   413	+    '지점별로 끈 가격유형. 빠지면 복원된 지점에서 꺼 둔 가격이 다시 보인다.',
   414	+  branch_printer_configs:
   415	+    '지점 프린터 설정. 복원 후 출력이 안 되면 이것이 빠진 것이다.',
   416	+  branch_agents:
   417	+    '프린터 에이전트. terminals.thermal_agent_id/zebra_agent_id 가 가리킨다. ' +
   418	+    '★ 설정은 담되 api_key 는 마스킹하고 에이전트 신원은 **재등록 대상**이다 — ' +
   419	+    '복제된 매장이 원본의 자격증명을 재사용하면 안 된다(codex, 2026-08-22).',
   420	+
   421	+  // ── 지출·외주·기타 ───────────────────────────────────────────────────────
   422	+  expense_cheques:
   423	+    '지출과 수표의 연결. 빠지면 수표가 어느 지출인지 못 되짚는다.',
   424	+  talleres_vendor_etapas:
   425	+    '공방이 어느 공정을 맡는지. 빠지면 외주 발주가 대상을 잃는다.',
   426	+  talleres_envio_materiales: '공방 발송에 딸린 자재. 반환 대조의 근거다.',
   427	+  talleres_defects: '외주 불량과 차감액. 공방 정산 금액에 직접 들어간다.',
   428	+  talleres_material_issues: '외주로 내보낸 자재. 손실 판정의 근거가 된다.',
   429	+  shared_folder_role_access:
   430	+    '공유 폴더의 역할별 접근 권한. 빠지면 복원 후 아무도 못 연다.',
   431	+  rider_settlement_items: '배달원 정산의 개별 항목. 정산 금액의 근거다.',
   432	+  campaign_recipients:
   433	+    '캠페인 수신자. ★ 단순 이력인지 **발송 대기 상태**인지 확인이 필요하다 — ' +
   434	+    '대기 상태가 섞여 있으면 복원이 재발송을 일으킨다(codex, 2026-08-22).',
   435	+
   436	+  // ── MercadoPago 지갑 계열 ────────────────────────────────────────────────
   437	+  //   ★ 테이블 단위 분류로 부족하다. 모드마다 답이 다르다(codex, 2026-08-22):
   438	+  //     복제(clone)      → 외부 결제 식별자를 복제할 수 없으므로 활성 원장으로 복원 금지
   439	+  //     재해복구(restore) → 회계 원장이므로 포함해야 한다
   440	+  //   지금은 **백업에는 담고**, 복원 쪽에서 모드별로 가른다.
   441	+  mp_movements: 'MP 지갑 입출금. 가상 카하 잔액의 근거다. 모드별 정책 필요.',
   442	+  mp_transfers: 'MP 지갑 → 카하 이체. 현금 흐름의 일부다. 모드별 정책 필요.',
   443	+  mp_refunds: 'MP 환불 기록. 판매 취소와 짝을 이룬다. 모드별 정책 필요.',
   444	+  mp_refund_attempts: 'MP 환불 시도 이력. 실패 원인 추적용. 모드별 정책 필요.',
   445	+};
   446	+
   447	+/**
   448	+ * [Phase 85 W6-C1] **여러 매장이 함께 쓰는** 테이블. 한 매장의 것이 아니다.
   449	+ *
   450	+ * ★ 관계로는 `stores` 에 닿는다(`created_by_store_id` 등). 하지만 그건
   451	+ *   **"누가 처음 만들었나"** 이지 **"누구 것인가"** 가 아니다.
   452	+ *   FK 도달을 그대로 소유권으로 읽으면 여기서 틀린다 — 내가 실제로 틀렸고
   453	+ *   codex 가 잡았다(2026-08-22).
   454	+ *
   455	+ * 복원은 이 테이블들을 **만들지도 지우지도 않는다.** 참조하는 FK 는
   456	+ * `KEEP_GLOBAL` 로 다룬다. 새 ID 로 복제하면 전역 레지스트리가 매장 수만큼 불어나고,
   457	+ * 원 ID 를 유지하면 새 매장이 남의 매장 행을 가리킨다 — 둘 다 틀렸다.
   458	+ */
   459	+export const CROSS_TENANT_TABLES: Readonly<Record<string, string>> = {
   460	+  global_clients:
   461	+    '매장 공통 고객 레지스트리(운영 3,773행). created_by_store_id 는 최초 생성자일 뿐이다. ' +
   462	+    '★ owner_group_id 범위로 공유되므로, 복원 시 대상 매장이 같은 소유자 그룹인지 ' +
   463	+    '검사해야 한다 — 다른 그룹이면 KEEP 도 복제도 안 된다(codex, 2026-08-22).',
   464	+  global_categories: '전역 카테고리 레지스트리. global_clients 와 같은 이유.',
   465	+  global_subcategories: '전역 소분류 레지스트리. 같은 이유.',
   466	+  pending_registrations:
   467	+    '가입 대기 큐. referrer_store_id 는 추천인이지 소유자가 아니다.',
   468	+  referral_credits:
   469	+    '추천 크레딧. referrer_store_id 와 referred_store_id 로 **두 매장에 걸쳐 있다** — ' +
   470	+    '어느 한 매장의 백업에 담을 수 없다.',
   471	+  revendedor_categories:
   472	+    '재판매자↔전역 카테고리 매핑. 재판매자는 매장 소유가 아니다.',
   473	+};
   474	+
   475	+/**
   476	+ * [Phase 85 W6-C1] 매장과 무관한 테이블 — 전역 참조 / 시스템 / 레거시.
   477	+ *
   478	+ * ★ 왜 이것까지 선언하나: 기준선이 **모든 테이블**을 싣기 때문이다.
   479	+ *   "목록에 없으면 검사도 없다" 를 없애는 것이 W6-C1 의 목적이다.
   480	+ *   여기 없는 테이블이 새로 생기면 빌드가 깨지고, 그때 사람이 분류한다.
   481	+ */
   482	+export const GLOBAL_TABLES: Readonly<Record<string, string>> = {
   483	+  // 전역 참조 데이터 — 모든 매장이 같은 행을 읽는다.
   484	+  provinces: '아르헨티나 주 목록. 전역 참조.',
   485	+  nations: '국가 목록. 전역 참조.',
   486	+  apps: '앱(모듈) 카탈로그. store_apps 가 매장별 활성화를 갖는다.',
   487	+  functions: '권한 기능 카탈로그. 매장별 부여는 role_functions 가 갖는다.',
   488	+  modules: '기능 모듈 카탈로그. 전역 정의이며 매장별 값이 없다.',
   489	+  permissions: '레거시 권한 카탈로그. 매장별 부여가 아니라 전역 정의다.',
   490	+  daily_quotes: '환율/시세 일별 값. 전역이다.',
   491	+  subscription_config: '구독 요금 설정. 플랫폼 전역.',
   492	+
   493	+  // 플랫폼 운영 — 매장 데이터가 아니다.
   494	+  cron_leases: '크론 리더 선출 lease. 런타임 상태.',
   495	+  app_boot_flags: '부팅 플래그. 런타임 상태.',
   496	+  slow_query_log: '느린 쿼리 진단 로그.',
   497	+  backfill_failures: '백필 실패 기록. 운영 진단용.',
   498	+  verification_codes: '인증 코드(가입·복구). 단명하며 매장 소유가 아니다.',
   499	+  vto_settings: 'VTO 전역 설정.',
   500	+  revendedores: '재판매자 마스터. 매장이 아니라 플랫폼에 속한다.',
   501	+
   502	+  // 레거시 — 사용되지 않는다(운영 실측 0행). 지우기 전까지 분류만 해 둔다.
   503	+  _phase26_cat_map: '레거시 Phase 26 카테고리 매핑. 운영 0행.',
   504	+  category_discounts:
   505	+    '레거시 할인 매핑. 운영 0행. subcategory_discounts 로 대체됨.',
   506	+  product_categories:
   507	+    '레거시 상품↔카테고리. 운영 0행. products.category_id 가 현행이다.',
   508	+  product_variants: '레거시 변형. 운영 0행. ProductBranch 가 현행이다.',
   509	+  variants: '레거시 변형. 운영 0행.',
   510	+  variant_types: '레거시 변형 종류. 운영 0행.',
   511	+  role_permissions: '레거시 권한 모델. 운영 0행. role_functions 가 현행이다.',
   512	+  role_permission_functions: '레거시 권한 모델. 운영 0행.',
   513	+  user_permissions: '레거시 권한 모델. 운영 0행. user_functions 가 현행이다.',
   514	+  user_permission_functions: '레거시 권한 모델. 운영 0행.',
   515	+  stock_cache_backfill_20260729: '2026-07-29 재고 캐시 백필 작업 테이블.',
   516	 };
   517	 
   518	 /** 인벤토리에서 무시하는 이름 패턴 — 뷰와 임시 스냅샷. */
   519	diff --git a/src/app/store/store.service.ts b/src/app/store/store.service.ts
   520	index 82b7a72..7031142 100644
   521	--- a/src/app/store/store.service.ts
   522	+++ b/src/app/store/store.service.ts
   523	@@ -38,6 +38,8 @@ import { syntheticEmail } from '../users/synthetic-email';
   524	 import {
   525	   SIMPLE_STORE_TABLES,
   526	   EXCLUDED_TABLES,
   527	+  PENDING_BACKUP_TABLES,
   528	+  CROSS_TENANT_TABLES,
   529	   LEGACY_JSON_KEYS,
   530	   redactBackupRows,
   531	 } from './store-backup-coverage';
   532	@@ -1361,6 +1363,15 @@ export class StoreService extends CrudService<Store> {
   533	         simpleTables: SIMPLE_STORE_TABLES.length,
   534	         excluded: Object.keys(EXCLUDED_TABLES),
   535	         excludedReasons: EXCLUDED_TABLES,
   536	+        // ★ [W6-C1] **아직 안 담기는 것을 파일이 스스로 말한다.**
   537	+        //   기준선을 관계 기반으로 바꾸니 매장에 속하는 테이블 42개가
   538	+        //   백업에도 제외 선언에도 없이 빠져 있었다(role_function_actions 40,557행 등).
   539	+        //   담는 작업은 W6-C2 지만, 그 전에 **이 파일이 완전하지 않다는 사실**은
   540	+        //   지금 말해야 한다 — 완전한 줄 알고 매장을 지우는 것이 W6 의 출발점이었다.
   541	+        pending: Object.keys(PENDING_BACKUP_TABLES),
   542	+        pendingReasons: PENDING_BACKUP_TABLES,
   543	+        // 여러 매장이 공유하므로 한 매장의 백업에 담을 수 없는 것들.
   544	+        crossTenant: Object.keys(CROSS_TENANT_TABLES),
   545	         // ★ 담기로 선언했는데 **읽지 못한** 테이블. 보통은 비어 있어야 한다.
   546	         //   비어 있지 않다면 스키마가 선언보다 뒤처졌다는 뜻이다.
   547	         unreadable,
   548	
   549	===== 신규: migrations/2026-08-22-w6-talleres-missing-fks.sql =====
   550	-- [Phase 85 W6-C1] talleres 4개 테이블에 **빠져 있던 FK 제약**을 추가한다.
   551	--
   552	-- ★ 왜 필요한가:
   553	--   W6-C1 에서 매장 백업의 기준선을 "`store_id` 컬럼 보유" 에서
   554	--   "`stores` 로부터의 FK 도달 폐포" 로 바꿨다. 소유권의 권위는 컬럼이 아니라
   555	--   관계이기 때문이다(2026-08-21 codex 지적을 인벤토리에도 적용).
   556	--
   557	--   그런데 아래 4개는 **FK 제약이 하나도 없다.** 컬럼(`subcon_order_id` 등)은 있는데
   558	--   DB 가 그 관계를 모른다. 그래서 관계 기반 분류가 이들을 `global`(매장과 무관)로
   559	--   **오분류**한다 — 실제로는 매장 데이터이고, 둘은 이미 백업 대상으로 선언돼 있다.
   560	--
   561	--   즉 **그래프가 거짓말을 하고 있고, 우리는 그 그래프를 권위로 삼으려 한다.**
   562	--   그래프를 사실에 맞추는 것이 옳은 순서다.
   563	--
   564	-- ★ 안전성 (2026-08-22 운영 실측):
   565	--   네 테이블 모두 **0행**이고 고아 참조도 **0건**이다.
   566	--   빈 테이블의 FK 추가는 전수 검사할 행이 없어 즉시 끝난다.
   567	--
   568	-- w4-exempt: 대상이 전부 0행이라 잠금 보유 시간이 사실상 없다. NOT VALID → VALIDATE
   569	--            2단계는 검사할 기존 행이 있을 때 의미가 있는데 여기서는 해당 없다.
   570	--            (그래도 lock_timeout 은 건다 — 앞선 장기 트랜잭션에 끌려가지 않기 위해.)

hook: PostToolUse
hook: PostToolUse
hook: PostToolUse Failed
hook: PostToolUse Completed
codex
[HIGH] [.team/reviews/w6c1-diff.txt:215](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/.team/reviews/w6c1-diff.txt:215) — `PENDING` 테이블이 있어도 “모든 테이블이 처리됐다”는 커버리지 검사가 통과한다

  문제: `PENDING_BACKUP_TABLES`를 다른 완료 상태와 동일한 선언으로 취급합니다. 따라서 `role_function_actions`, 금전 이력 등 필수 데이터가 실제 백업에 하나도 없어도 전체 테스트가 초록입니다. JSON에 `coverage.pending`을 기록하는 것은 좋은 고지이지만, 운영자가 이를 확인하지 않고 삭제·복원을 진행하는 것을 막지는 않습니다.

  근거:
  ```ts
  const declared = tenantDeclarations();
  const missing = readInventory().tenant.filter((t) => !declared.has(t));
  ```
  그리고 `tenantDeclarations()`가 `PENDING_BACKUP_TABLES`도 `declared`에 넣습니다.

  수정: `PENDING`이라는 세 번째 자리는 설계상 옳습니다. 다만 다음 상태를 분리해야 합니다.

  - 분류 완전성 검사: `PENDING`도 허용
  - 백업 완전성/운영 준비 검사: `PENDING`이 하나라도 있으면 실패
  - 실제 삭제·복원 경로: `coverage.pending.length > 0`이면 명시적인 강제 승인 없이는 중단

  즉 `PENDING`은 유지하되, “분류됨”과 “백업 가능”을 같은 초록 신호로 만들면 안 됩니다.

[HIGH] [.team/reviews/w6c1-diff.txt:297](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/.team/reviews/w6c1-diff.txt:297) — 기존 테이블의 소유권 변경은 두 감시를 모두 거짓 통과할 수 있다

  문제: 마이그레이션 감시는 `CREATE TABLE`만 검사합니다. 기존 `GLOBAL_TABLES` 테이블에 `store_id` 컬럼이나 테넌트 부모 FK를 `ALTER TABLE`로 추가하면:

  1. 저장된 인벤토리를 재생성하지 않아도 기존 `global:` 분류가 남고,
  2. 마이그레이션 컷오프는 `CREATE TABLE`이 아니므로 보지 않으며,
  3. 기존 `GLOBAL_TABLES` 선언과 오래된 인벤토리가 서로 일치해 테스트가 통과합니다.

  새 테이블 누락은 강화됐지만, 새 컬럼·새 FK에 의한 기존 테이블 재분류 누락은 남았습니다.

  근거: 컷오프 검사는 `while ((m = re.exec(code)) !== null)`로 새 테이블명만 처리하며, 인벤토리와 현재 DB 구조를 CI에서 직접 비교하는 검사는 제시되지 않았습니다.

  수정: 컷오프 이후 마이그레이션에서 최소한 다음 변경도 탐지해 해당 테이블의 인벤토리 재생성을 강제해야 합니다.

  - `ALTER TABLE ... ADD COLUMN store_id`
  - `ALTER TABLE ... ADD CONSTRAINT ... FOREIGN KEY`
  - FK 삭제·변경
  - 테이블 rename/drop

  가장 강한 방법은 CI용 스키마 DB에서 재생성한 인벤토리를 커밋된 기준선과 `diff`하는 것입니다. 정규식 감시는 보조 장치로 두는 편이 안전합니다.

[MEDIUM] [.team/reviews/w6c1-diff.txt:466](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/.team/reviews/w6c1-diff.txt:466) — `CROSS_TENANT` 6개 중 2개는 제시된 이유만으로 경계가 성립하지 않는다 — 확인 필요

  문제: `CROSS_TENANT`의 정의는 “여러 매장이 공유하고, 참조 ID를 `KEEP_GLOBAL`로 유지해야 하는 데이터”입니다. 그러나 아래 두 테이블의 이유는 단지 매장 소유가 아니라는 사실만 설명합니다.

  근거:
  ```ts
  pending_registrations:
    '가입 대기 큐. referrer_store_id 는 추천인이지 소유자가 아니다.'

  revendedor_categories:
    '재판매자↔전역 카테고리 매핑. 재판매자는 매장 소유가 아니다.'
  ```

  `pending_registrations`는 단명 워크플로 상태이므로 `EXCLUDED` 또는 플랫폼 운영 `GLOBAL`일 가능성이 높습니다. `revendedor_categories`는 설명대로라면 매장과 무관한 전역 매핑이므로 `GLOBAL`에 더 가깝습니다. “FK 폐포의 tenant 판정을 사람이 교정한다”는 이유만으로 모두 `CROSS_TENANT`에 넣으면 `GLOBAL`과 의미가 겹칩니다.

  수정: 각 테이블에 대해 “여러 매장이 실제로 동일 행을 참조하는가”와 “복원 데이터가 그 ID를 유지해야 하는가”를 확인하십시오. 둘 중 하나라도 아니면:

  - 플랫폼 전역 마스터/매핑 → `GLOBAL`
  - 복원할 필요 없는 임시 상태 → `EXCLUDED`
  - 여러 매장 데이터가 한 행에 결합됨 → `CROSS_TENANT`

  `global_clients`와 `referral_credits`는 현재 이유만으로도 `CROSS_TENANT`가 타당합니다. `global_categories`와 `global_subcategories`는 `global_clients`처럼 실제 `owner_group_id` 공유 범위를 이유에 명시해야 확정할 수 있습니다.

[LOW] [.team/reviews/w6c1-diff.txt:48](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/.team/reviews/w6c1-diff.txt:48) — 재귀 CTE의 `UNION`은 현재 형태에서 순환을 제거하지 않는다

  문제: 주석은 `UNION`이 중복을 접는다고 하지만 행이 `(oid, depth)`이므로 같은 테이블도 depth가 다르면 별도 행입니다. 실제 순환 방어는 오직 depth 20 제한입니다. 20단계를 넘는 FK 사슬은 `global`로 오분류될 수 있습니다.

  근거:
  ```sql
  reach AS (
    SELECT oid, 0 AS depth FROM seed
    UNION
    SELECT fk.src, r.depth + 1 ...
    WHERE r.depth < 20
  )
  ```

  수정: `reach`의 재귀 결과를 `oid` 하나로 구성하고 `UNION`의 중복 제거로 고정점까지 탐색하십시오. 깊이 제한을 유지하려면 별도 path/visited 배열로 순환을 막고, 상한 도달 자체를 오류로 처리해야 합니다. 현재 216개 스키마에서 실제 20단계 사슬이 있는지는 확인 필요입니다.

[LOW] [.team/reviews/w6c1-diff.txt:572](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/.team/reviews/w6c1-diff.txt:572) — FK 마이그레이션의 멱등 검사가 제약 이름만 확인한다

  문제: 같은 이름의 잘못된 FK가 이미 존재하면 마이그레이션이 성공한 것처럼 건너뜁니다. 하단 검증 쿼리도 이름과 테이블만 출력하므로 대상 컬럼·참조 테이블이 맞는지 검증하지 못합니다.

  근거:
  ```sql
  WHERE conname = 'fk_talleres_deliveries_order'
    AND conrelid = 'talleres_deliveries'::regclass
  ```

  수정: 이미 운영에 적용됐다면 제약을 다시 변경할 필요는 없습니다. 대신 `pg_get_constraintdef(oid)` 또는 `conkey/confkey/confrelid`를 조회해 네 FK의 실제 정의를 한 번 확인하십시오. 네 테이블이 적용 당시 모두 0행이었다는 전제에서는 잠금·기존 데이터 검증 측면의 문제는 없습니다.

종합 판단:

- `PENDING` 자리는 옳습니다. 다만 “분류 완료” 상태이지 “백업 완료” 상태가 아니므로 별도의 실패 게이트가 필요합니다.
- 새 테이블 감시는 크게 개선됐지만, `ALTER TABLE`을 통한 새 `store_id`·FK·소유권 변경이 가장 큰 잔여 거짓 통과 경로입니다.
- FK 4개 추가 자체는 제시된 0행 실측 조건에서는 이상 없습니다. 적용 후 정의 확인만 권합니다.
- 216개 기준선 본문이 이 검토 파일에서 제외되었으므로 개별 216개 분류 전체의 정확성은 확인할 수 없습니다. 요청 범위를 지키기 위해 다른 파일은 읽지 않았습니다.
hook: Stop
hook: Stop
hook: Stop Failed
hook: Stop Completed
tokens used
39,272
[HIGH] [.team/reviews/w6c1-diff.txt:215](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/.team/reviews/w6c1-diff.txt:215) — `PENDING` 테이블이 있어도 “모든 테이블이 처리됐다”는 커버리지 검사가 통과한다

  문제: `PENDING_BACKUP_TABLES`를 다른 완료 상태와 동일한 선언으로 취급합니다. 따라서 `role_function_actions`, 금전 이력 등 필수 데이터가 실제 백업에 하나도 없어도 전체 테스트가 초록입니다. JSON에 `coverage.pending`을 기록하는 것은 좋은 고지이지만, 운영자가 이를 확인하지 않고 삭제·복원을 진행하는 것을 막지는 않습니다.

  근거:
  ```ts
  const declared = tenantDeclarations();
  const missing = readInventory().tenant.filter((t) => !declared.has(t));
  ```
  그리고 `tenantDeclarations()`가 `PENDING_BACKUP_TABLES`도 `declared`에 넣습니다.

  수정: `PENDING`이라는 세 번째 자리는 설계상 옳습니다. 다만 다음 상태를 분리해야 합니다.

  - 분류 완전성 검사: `PENDING`도 허용
  - 백업 완전성/운영 준비 검사: `PENDING`이 하나라도 있으면 실패
  - 실제 삭제·복원 경로: `coverage.pending.length > 0`이면 명시적인 강제 승인 없이는 중단

  즉 `PENDING`은 유지하되, “분류됨”과 “백업 가능”을 같은 초록 신호로 만들면 안 됩니다.

[HIGH] [.team/reviews/w6c1-diff.txt:297](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/.team/reviews/w6c1-diff.txt:297) — 기존 테이블의 소유권 변경은 두 감시를 모두 거짓 통과할 수 있다

  문제: 마이그레이션 감시는 `CREATE TABLE`만 검사합니다. 기존 `GLOBAL_TABLES` 테이블에 `store_id` 컬럼이나 테넌트 부모 FK를 `ALTER TABLE`로 추가하면:

  1. 저장된 인벤토리를 재생성하지 않아도 기존 `global:` 분류가 남고,
  2. 마이그레이션 컷오프는 `CREATE TABLE`이 아니므로 보지 않으며,
  3. 기존 `GLOBAL_TABLES` 선언과 오래된 인벤토리가 서로 일치해 테스트가 통과합니다.

  새 테이블 누락은 강화됐지만, 새 컬럼·새 FK에 의한 기존 테이블 재분류 누락은 남았습니다.

  근거: 컷오프 검사는 `while ((m = re.exec(code)) !== null)`로 새 테이블명만 처리하며, 인벤토리와 현재 DB 구조를 CI에서 직접 비교하는 검사는 제시되지 않았습니다.

  수정: 컷오프 이후 마이그레이션에서 최소한 다음 변경도 탐지해 해당 테이블의 인벤토리 재생성을 강제해야 합니다.

  - `ALTER TABLE ... ADD COLUMN store_id`
  - `ALTER TABLE ... ADD CONSTRAINT ... FOREIGN KEY`
  - FK 삭제·변경
  - 테이블 rename/drop

  가장 강한 방법은 CI용 스키마 DB에서 재생성한 인벤토리를 커밋된 기준선과 `diff`하는 것입니다. 정규식 감시는 보조 장치로 두는 편이 안전합니다.

[MEDIUM] [.team/reviews/w6c1-diff.txt:466](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/.team/reviews/w6c1-diff.txt:466) — `CROSS_TENANT` 6개 중 2개는 제시된 이유만으로 경계가 성립하지 않는다 — 확인 필요

  문제: `CROSS_TENANT`의 정의는 “여러 매장이 공유하고, 참조 ID를 `KEEP_GLOBAL`로 유지해야 하는 데이터”입니다. 그러나 아래 두 테이블의 이유는 단지 매장 소유가 아니라는 사실만 설명합니다.

  근거:
  ```ts
  pending_registrations:
    '가입 대기 큐. referrer_store_id 는 추천인이지 소유자가 아니다.'

  revendedor_categories:
    '재판매자↔전역 카테고리 매핑. 재판매자는 매장 소유가 아니다.'
  ```

  `pending_registrations`는 단명 워크플로 상태이므로 `EXCLUDED` 또는 플랫폼 운영 `GLOBAL`일 가능성이 높습니다. `revendedor_categories`는 설명대로라면 매장과 무관한 전역 매핑이므로 `GLOBAL`에 더 가깝습니다. “FK 폐포의 tenant 판정을 사람이 교정한다”는 이유만으로 모두 `CROSS_TENANT`에 넣으면 `GLOBAL`과 의미가 겹칩니다.

  수정: 각 테이블에 대해 “여러 매장이 실제로 동일 행을 참조하는가”와 “복원 데이터가 그 ID를 유지해야 하는가”를 확인하십시오. 둘 중 하나라도 아니면:

  - 플랫폼 전역 마스터/매핑 → `GLOBAL`
  - 복원할 필요 없는 임시 상태 → `EXCLUDED`
  - 여러 매장 데이터가 한 행에 결합됨 → `CROSS_TENANT`

  `global_clients`와 `referral_credits`는 현재 이유만으로도 `CROSS_TENANT`가 타당합니다. `global_categories`와 `global_subcategories`는 `global_clients`처럼 실제 `owner_group_id` 공유 범위를 이유에 명시해야 확정할 수 있습니다.

[LOW] [.team/reviews/w6c1-diff.txt:48](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/.team/reviews/w6c1-diff.txt:48) — 재귀 CTE의 `UNION`은 현재 형태에서 순환을 제거하지 않는다

  문제: 주석은 `UNION`이 중복을 접는다고 하지만 행이 `(oid, depth)`이므로 같은 테이블도 depth가 다르면 별도 행입니다. 실제 순환 방어는 오직 depth 20 제한입니다. 20단계를 넘는 FK 사슬은 `global`로 오분류될 수 있습니다.

  근거:
  ```sql
  reach AS (
    SELECT oid, 0 AS depth FROM seed
    UNION
    SELECT fk.src, r.depth + 1 ...
    WHERE r.depth < 20
  )
  ```

  수정: `reach`의 재귀 결과를 `oid` 하나로 구성하고 `UNION`의 중복 제거로 고정점까지 탐색하십시오. 깊이 제한을 유지하려면 별도 path/visited 배열로 순환을 막고, 상한 도달 자체를 오류로 처리해야 합니다. 현재 216개 스키마에서 실제 20단계 사슬이 있는지는 확인 필요입니다.

[LOW] [.team/reviews/w6c1-diff.txt:572](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/.team/reviews/w6c1-diff.txt:572) — FK 마이그레이션의 멱등 검사가 제약 이름만 확인한다

  문제: 같은 이름의 잘못된 FK가 이미 존재하면 마이그레이션이 성공한 것처럼 건너뜁니다. 하단 검증 쿼리도 이름과 테이블만 출력하므로 대상 컬럼·참조 테이블이 맞는지 검증하지 못합니다.

  근거:
  ```sql
  WHERE conname = 'fk_talleres_deliveries_order'
    AND conrelid = 'talleres_deliveries'::regclass
  ```

  수정: 이미 운영에 적용됐다면 제약을 다시 변경할 필요는 없습니다. 대신 `pg_get_constraintdef(oid)` 또는 `conkey/confkey/confrelid`를 조회해 네 FK의 실제 정의를 한 번 확인하십시오. 네 테이블이 적용 당시 모두 0행이었다는 전제에서는 잠금·기존 데이터 검증 측면의 문제는 없습니다.

종합 판단:

- `PENDING` 자리는 옳습니다. 다만 “분류 완료” 상태이지 “백업 완료” 상태가 아니므로 별도의 실패 게이트가 필요합니다.
- 새 테이블 감시는 크게 개선됐지만, `ALTER TABLE`을 통한 새 `store_id`·FK·소유권 변경이 가장 큰 잔여 거짓 통과 경로입니다.
- FK 4개 추가 자체는 제시된 0행 실측 조건에서는 이상 없습니다. 적용 후 정의 확인만 권합니다.
- 216개 기준선 본문이 이 검토 파일에서 제외되었으므로 개별 216개 분류 전체의 정확성은 확인할 수 없습니다. 요청 범위를 지키기 위해 다른 파일은 읽지 않았습니다.
