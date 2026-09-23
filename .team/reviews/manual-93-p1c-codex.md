Reading additional input from stdin...
OpenAI Codex v0.146.0
--------
workdir: /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
model: gpt-5.6-sol
provider: openai
approval: never
sandbox: read-only
reasoning effort: none
reasoning summaries: none
session id: 01a0cf8e-dc8f-7190-8576-b733dfc5d6e0
--------
user
Revisá este cambio de un ERP multi-tenant (NestJS + Sequelize, frontend Next.js). Es el punto P1-c del Phase 93.

PROBLEMA QUE SE INTENTA CERRAR (verificado en el código):
`PUT /role-functions/bulk-actions/:roleId` guarda "estado final": todo functionId que NO venga
en el payload se BORRA (role-function.service.ts, bloque `staleIds`). Si la pantalla guarda con
la lista cargada a medias, se revocan permisos en masa. Hasta ahora lo único que lo evitaba era
una línea en el front (`if (!loaded || loadError) return;`); el servidor no se defendía solo.
En Phase 93 se va a rehacer esa pantalla, así que esa línea desaparece.

SOLUCIÓN ELEGIDA POR EL USUARIO (de 3 opciones): el cliente declara cuántas funciones va a
revocar (`expectedRemovals`) y el servidor lo contrasta con su propio cálculo; si difiere, 409.
Es fase EXPAND: si no viene el campo, se comporta como antes (hay un segundo cliente,
la app Flutter `tienda-admin-app`, que todavía no lo manda).

DATOS MEDIDOS: role_functions sin ninguna acción = 0 filas (local 14.296 / prod 16.806),
así que cliente y servidor cuentan el mismo conjunto.

BUSCO ESPECÍFICAMENTE:
1. ¿Hay alguna forma de que este guard rechace un guardado legítimo (falso 409)? Concurrencia,
   funciones que el usuario no ve, roles globales (store_id IS NULL), etc.
2. ¿Hay alguna forma de que NO atrape el caso que dice atrapar?
3. ¿La unidad de conteo (funciones que pierden el permiso entero, no pares acción) es la correcta?
   ¿Puede una carga parcial provocar borrado de ACCIONES sin disparar el guard?
4. ¿El manejo de null/undefined/valores no enteros deja algún fail-open?
5. ¿El orden (validar ANTES de borrar, dentro de la transacción) es correcto?
No repitas lo que ya está bien. Señalá defectos concretos con archivo y línea.

DIFF:diff --git a/src/app/role/role-function/role-function.controller.spec.ts b/src/app/role/role-function/role-function.controller.spec.ts
index 29d876c9..bdcb45c1 100644
--- a/src/app/role/role-function/role-function.controller.spec.ts
+++ b/src/app/role/role-function/role-function.controller.spec.ts
@@ -68,13 +68,36 @@ describe('RoleFunctionController', () => {
 
       await controller.bulkUpdateActions(3, user, body);
 
-      // ★ 마지막 인자는 **요청자**의 id 다 — 감사에 "누가 바꿨나" 로 남는다.
+      // ★ 4번째 인자는 **요청자**의 id 다 — 감사에 "누가 바꿨나" 로 남는다.
       //   안 넘기면 user_id 가 NULL(미귀속)이 된다.
+      // ★ 5번째는 선언한 회수 건수(P1-c). 안 보낸 요청이면 undefined 그대로 간다.
       expect(service.bulkUpdateRoleFunctionActions).toHaveBeenCalledWith(
         3,
         10,
         body.data,
         42,
+        undefined,
+      );
+    });
+
+    // [Phase 93 · P1-c] 컨트롤러가 이 값을 **그대로 넘겨야** 계약이 성립한다.
+    // 서비스에만 판정을 넣고 컨트롤러가 값을 버리� succeeded in 5545ms:
2026-09-23 15:37:18.775 xcodebuild[14735:3452060]  DVTFilePathFSEvents: Failed to start fs event stream.
2026-09-23 15:37:18.958 xcodebuild[14735:3452059] [MT] DVTDeveloperPaths: Failed to get length of DARWIN_USER_CACHE_DIR from confstr(3), error = Error Domain=NSPOSIXErrorDomain Code=5 "Input/output error". Using NSCachesDirectory instead.
git: warning: confstr() failed with code 5: couldn't get path of DARWIN_USER_TEMP_DIR; using /tmp instead
git: error: couldn't create cache file '/tmp/xcrun_db-eFCoVoH8' (errno=Operation not permitted)
2026-09-23 15:37:19.417 xcodebuild[14743:3452089]  DVTFilePathFSEvents: Failed to start fs event stream.
2026-09-23 15:37:19.506 xcodebuild[14743:3452088] [MT] DVTDeveloperPaths: Failed to get length of DARWIN_USER_CACHE_DIR from confstr(3), error = Error Domain=NSPOSIXErrorDomain Code=5 "Input/output error". Using NSCachesDirectory instead.
 M .claude/hooks/.gsd-snapshot.json
 M .planning/STATE.md
 m api-ventago
 m ventago-app
?? ".planning/ANALISIS-2026-09-17-legacy-vcontrolgrid2-\352\262\251\354\260\250\353\266\204\354\204\235.md"
?? .planning/GUIA-miguel-acceso-servidor2.md
?? ".planning/PLAN-2026-09-16-\354\204\234\353\262\204-\353\266\204\353\246\254\354\231\200-\354\213\240\352\267\234-\354\235\264\354\240\204.md"
?? .planning/SETUP-2026-08-26-servidor2-74.208.60.137.md
?? .team/reviews/.manual-89-diseno.prompt
?? .team/reviews/.manual-money.prompt
?? .team/reviews/auto-.-c44b566.md
?? .team/reviews/auto-api-ventago-0100d26.md
?? .team/reviews/auto-api-ventago-06a888ff_ventago-app-afbcbf3.md
?? .team/reviews/auto-api-ventago-0748b9a2.md
?? .team/reviews/auto-api-ventago-1058cc89.md
?? .team/reviews/auto-api-ventago-1152e1f6.md
?? .team/reviews/auto-api-ventago-18ba95a.md
?? .team/reviews/auto-api-ventago-1a3bcf9.md
?? .team/reviews/auto-api-ventago-21ee29d.md
?? .team/reviews/auto-api-ventago-25f0ecb0.md
?? .team/reviews/auto-api-ventago-282c86d6.md
?? .team/reviews/auto-api-ventago-29480476.md
?? .team/reviews/auto-api-ventago-3504e05.md
?? .team/reviews/auto-api-ventago-35b0727.md
?? .team/reviews/auto-api-ventago-3635b207_ventago-app-375d3f2.md
?? .team/reviews/auto-api-ventago-425a17d.md
?? .team/reviews/auto-api-ventago-4a17657.md
?? .team/reviews/auto-api-ventago-4ec4109.md
?? .team/reviews/auto-api-ventago-50459e81.md
?? .team/reviews/auto-api-ventago-55f92a09.md
?? .team/reviews/auto-api-ventago-580f24a9.md
?? .team/reviews/auto-api-ventago-597bdd21.md
?? .team/reviews/auto-api-ventago-59c7cc5.md
?? .team/reviews/auto-api-ventago-632c6780.md
?? .team/reviews/auto-api-ventago-64564cd6.md
?? .team/reviews/auto-api-ventago-668b650.md
?? .team/reviews/auto-api-ventago-66c67888.md
?? .team/reviews/auto-api-ventago-6a9d579_ventago-app-c98f001.md
?? .team/reviews/auto-api-ventago-6b66516.md
?? .team/reviews/auto-api-ventago-6ee2d011.md
?? .team/reviews/auto-api-ventago-6f0a8f4.md
?? .team/reviews/auto-api-ventago-754af978.md
?? .team/reviews/auto-api-ventago-7731d9bd.md
?? .team/reviews/auto-api-ventago-773e6240.md
?? .team/reviews/auto-api-ventago-777e9de.md
?? .team/reviews/auto-api-ventago-77b88753.md
?? .team/reviews/auto-api-ventago-7fc0a74.md
?? .team/reviews/auto-api-ventago-833aacf2.md
?? .team/reviews/auto-api-ventago-853b72ab.md
?? .team/reviews/auto-api-ventago-857ace55.md
?? .team/reviews/auto-api-ventago-94d8502.md
?? .team/reviews/auto-api-ventago-9eba587.md
?? .team/reviews/auto-api-ventago-9f759f15.md
?? .team/reviews/auto-api-ventago-a306d98.md
?? .team/reviews/auto-api-ventago-a3529d83.md
?? .team/reviews/auto-api-ventago-a36e84f_ventago-app-3cb66fe.md
?? .team/reviews/auto-api-ventago-a4543fb.md
?? .team/reviews/auto-api-ventago-aa2dc54.md
?? .team/reviews/auto-api-ventago-b3d65374_ventago-app-30b1b95.md
?? .team/reviews/auto-api-ventago-b4f34a9a_ventago-app-9573e76.md
?? .team/reviews/auto-api-ventago-bfa7695.md
?? .team/reviews/auto-api-ventago-c02b018.md
?? .team/reviews/auto-api-ventago-c0585fac.md
?? .team/reviews/auto-api-ventago-c0da8ce3.md
?? .team/reviews/auto-api-ventago-c325b48.md
?? .team/reviews/auto-api-ventago-d4d1f715.md
?? .team/reviews/auto-api-ventago-d5b36a0.md
?? .team/reviews/auto-api-ventago-d7f3d10.md
?? .team/reviews/auto-api-ventago-dc80c95.md
?? .team/reviews/auto-api-ventago-dce04cb.md
?? .team/reviews/auto-api-ventago-de4a318f.md
?? .team/reviews/auto-api-ventago-df2ce772.md
?? .team/reviews/auto-api-ventago-e09c69a.md
?? .team/reviews/auto-api-ventago-ea8b563f.md
?? .team/reviews/auto-api-ventago-eb118343.md
?? .team/reviews/auto-api-ventago-f00005c_ventago-app-72564f4.md
?? .team/reviews/auto-api-ventago-f0380fd.md
?? .team/reviews/auto-api-ventago-f30b2ff5.md
?? .team/reviews/auto-api-ventago-f36b3633.md
?? .team/reviews/auto-api-ventago-f45d4ce.md
?? .team/reviews/auto-api-ventago-f770585f.md
?? .team/reviews/auto-api-ventago-fb8b4f6f.md
?? .team/reviews/auto-manual-89-root-bcc975f..694041e_api-ventago-1152e1f6..2c7201a2_ventago-app-fe69bdc..5931ca9.md
?? .team/reviews/auto-root-08c4868_api-ventago-adfe292e.md
?? .team/reviews/auto-root-09a7240_api-ventago-1c9d7abd_ventago-app-8aab1a3.md
?? .team/reviews/auto-root-19ec460_ventago-app-fe69bdc.md
?? .team/reviews/auto-root-22c651d_api-ventago-b4d9ad8.md
?? .team/reviews/auto-root-2a9328a_api-ventago-3138dc48.md
?? .team/reviews/auto-root-33dbd94_api-ventago-3840f54f.md
?? .team/reviews/auto-root-378f116.md
?? .team/reviews/auto-root-3fec244_ventago-app-57d99ec.md
?? .team/reviews/auto-root-411425a.md
?? .team/reviews/auto-root-42ebfa8.md
?? .team/reviews/auto-root-432a75a_api-ventago-0da64b9c.md
?? .team/reviews/auto-root-47a50a0_api-ventago-62f2988.md
?? .team/reviews/auto-root-4854608.md
?? .team/reviews/auto-root-4d715b0.md
?? .team/reviews/auto-root-521a4cf_api-ventago-d1eaa8b6.md
?? .team/reviews/auto-root-5386cbd_api-ventago-7eda8f6e.md
?? .team/reviews/auto-root-5457333.md
?? .team/reviews/auto-root-55e1704_api-ventago-670810d8.md
?? .team/reviews/auto-root-58ff2f0_ventago-app-c14b7c3.md
?? .team/reviews/auto-root-5bfcdc2_ventago-app-964a64f.md
?? .team/reviews/auto-root-5c51654_api-ventago-7058340.md
?? .team/reviews/auto-root-5de413f_api-ventago-7d74ca88.md
?? .team/reviews/auto-root-5e21236_ventago-app-89843d4.md
?? .team/reviews/auto-root-6028fde.md
?? .team/reviews/auto-root-626e9d8_api-ventago-66ad6c9d.md
?? .team/reviews/auto-root-63a228b.md
?? .team/reviews/auto-root-63b6671_api-ventago-94fb796.md
?? .team/reviews/auto-root-68a0f48.md
?? .team/reviews/auto-root-697b267.md
?? .team/reviews/auto-root-6bb77cb_api-ventago-66d3a16b.md
?? .team/reviews/auto-root-6bdfdcb_ventago-app-55ad5d7.md
?? .team/reviews/auto-root-6d486bb_ventago-app-2288179.md
?? .team/reviews/auto-root-6f3fafb_api-ventago-6ce906a_ventago-app-36cdff4.md
?? .team/reviews/auto-root-721fb49_api-ventago-fee04b3f_ventago-app-1443ce1.md
?? .team/reviews/auto-root-73f151f_api-ventago-4a73ab7.md
?? .team/reviews/auto-root-75ba1db_api-ventago-dbd8e417.md
?? .team/reviews/auto-root-7887027.md
?? .team/reviews/auto-root-7e534c9.md
?? .team/reviews/auto-root-7ffa413_api-ventago-b1a5caf_ventago-app-9591702.md
?? .team/reviews/auto-root-8138b91_api-ventago-f8f5c55.md
?? .team/reviews/auto-root-82b4d8c_ventago-app-86e66dd.md
?? .team/reviews/auto-root-83e89ab_ventago-app-3e7aae8.md
?? .team/reviews/auto-root-840bc21.md
?? .team/reviews/auto-root-8dba188_api-ventago-91779fd.md
?? .team/reviews/auto-root-8f898a8.md
?? .team/reviews/auto-root-90589fa_api-ventago-2039a599_ventago-app-d3c93bc.md
?? .team/reviews/auto-root-98313e8_api-ventago-04b7df2.md
?? .team/reviews/auto-root-9bfb6c0.md
?? .team/reviews/auto-root-9d9d384_api-ventago-36838e02.md
?? .team/reviews/auto-root-a111972.md
?? .team/reviews/auto-root-a518fa4_api-ventago-70301b2f.md
?? .team/reviews/auto-root-ab3d9b4_ventago-app-aa9bbb2.md
?? .team/reviews/auto-root-ac27be6_api-ventago-02627644.md
?? .team/reviews/auto-root-b0482ed.md
?? .team/reviews/auto-root-b0ffdc0_api-ventago-14b62419_ventago-app-2127d6e.md
?? .team/reviews/auto-root-b3a0fdf.md
?? .team/reviews/auto-root-b5dc3a9_api-ventago-b92e599d.md
?? .team/reviews/auto-root-b6d5267.md
?? .team/reviews/auto-root-babdf1f.md
?? .team/reviews/auto-root-bbf6d1f_api-ventago-cc15268.md
?? .team/reviews/auto-root-bcc975f.md
?? .team/reviews/auto-root-cbd2c33.md
?? .team/reviews/auto-root-cbecb15_api-ventago-f0c2510c.md
?? .team/reviews/auto-root-cd1aa02.md
?? .team/reviews/auto-root-cdb6d94_api-ventago-b0233b6.md
?? .team/reviews/auto-root-d002590.md
?? .team/reviews/auto-root-d176110_api-ventago-ca25e19.md
?? .team/reviews/auto-root-d178e3d.md
?? .team/reviews/auto-root-d386412_api-ventago-39c3ffb.md
?? .team/reviews/auto-root-d71925e_ventago-app-54e6247.md
?? .team/reviews/auto-root-d914335_api-ventago-2a0fe93f_ventago-app-f9a295b.md
?? .team/reviews/auto-root-de35c1c_api-ventago-c6eb194d_ventago-app-cf8c9e0.md
?? .team/reviews/auto-root-e3a69e0.md
?? .team/reviews/auto-root-e5db900_api-ventago-1fac5fac_ventago-app-231278b.md
?? .team/reviews/auto-root-e73dfed.md
?? .team/reviews/auto-root-ebf072e.md
?? .team/reviews/auto-root-edbc743_api-ventago-2622468.md
?? .team/reviews/auto-root-f2c0b38_ventago-app-c354ba0.md
?? .team/reviews/auto-root-f6ba6ea_api-ventago-2522635.md
?? .team/reviews/auto-root-f952fbb_api-ventago-b9bcfa58.md
?? .team/reviews/auto-root-fe36fb9_api-ventago-c5a709f.md
?? .team/reviews/auto-ventago-app-0f2ff49.md
?? .team/reviews/auto-ventago-app-3219faf.md
?? .team/reviews/auto-ventago-app-3cc1782.md
?? .team/reviews/auto-ventago-app-6a877d5.md
?? .team/reviews/auto-ventago-app-88c7b7c.md
?? .team/reviews/auto-ventago-app-908bd19.md
?? .team/reviews/auto-ventago-app-b0da036.md
?? .team/reviews/auto-ventago-app-b80335b.md
?? .team/reviews/auto-ventago-app-df9dbbe.md
?? .team/reviews/auto-ventago-app-e2bf728.md
?? .team/reviews/auto-ventago-app-fa9e8fc.md
?? .team/reviews/commit-32744e5c-codex.md
?? .team/reviews/manual-57-F1F5-282c86d6.md
?? .team/reviews/manual-57-F3b-F6-833aacf2.md
?? .team/reviews/manual-89-diseno.md
?? .team/reviews/manual-91-05-dp-front-r2.md
?? .team/reviews/manual-91-05-dp-front.md
?? .team/reviews/manual-93-p1c-codex.md
?? .team/reviews/manual-comanda-e9cf727_c9a9850.md
?? .team/reviews/manual-contract-onboarding-bee7279.md
?? .team/reviews/manual-manuales-06b806d5.md
?? .team/reviews/manual-money-double-52b14e3.md
?? .team/reviews/manual-p2-caja-fuerte-c628bfb.md
?? .team/reviews/manual-phase93-codex.md
?? .team/reviews/manual-pos-footer-f340eaf.md
?? .team/reviews/manual-precio-codex.md
?? .team/reviews/phase86-partial-upload-codex-2026-08-25.md
?? .team/reviews/phase88-codex.md
?? .team/reviews/phase88-w1w2-codex-prompt.md
?? .team/reviews/phase88-w1w2-codex.md
?? "Claude outputs/"
?? legacy-query-mcp.zip
?? legacy-query-mcp/
?? "manuales/ACE III Online \354\213\234\354\212\244\355\205\234 \354\264\210\352\270\260 \354\205\213\354\227\205\355\225\230\352\270\260.docx"
?? "manuales/ACE III Online \354\213\234\354\212\244\355\205\234 \354\264\210\352\270\260 \354\205\213\354\227\205\355\225\230\352\270\260.pdf"
?? scripts/pg-lan-access.sh
?? scripts/server2-setup.sh
git: warning: confstr() failed with code 5: couldn't get path of DARWIN_USER_TEMP_DIR; using /tmp instead
git: error: couldn't create cache file '/tmp/xcrun_db-vutq9ysH' (errno=Operation not permitted)
2026-09-23 15:37:20.465 xcodebuild[14757:3452142]  DVTFilePathFSEvents: Failed to start fs event stream.
2026-09-23 15:37:20.555 xcodebuild[14757:3452141] [MT] DVTDeveloperPaths: Failed to get length of DARWIN_USER_CACHE_DIR from confstr(3), error = Error Domain=NSPOSIXErrorDomain Code=5 "Input/output error". Using NSCachesDirectory instead.
git: warning: confstr() failed with code 5: couldn't get path of DARWIN_USER_TEMP_DIR; using /tmp instead
git: error: couldn't create cache file '/tmp/xcrun_db-2vZ2kUfq' (errno=Operation not permitted)
2026-09-23 15:37:20.965 xcodebuild[14763:3452159]  DVTFilePathFSEvents: Failed to start fs event stream.
2026-09-23 15:37:21.055 xcodebuild[14763:3452158] [MT] DVTDeveloperPaths: Failed to get length of DARWIN_USER_CACHE_DIR from confstr(3), error = Error Domain=NSPOSIXErrorDomain Code=5 "Input/output error". Using NSCachesDirectory instead.
 .claude/hooks/.gsd-snapshot.json |  2 +-
 .planning/STATE.md               | 10 +++++-----
 api-ventago                      |  0
 ventago-app                      |  0
 4 files changed, 6 insertions(+), 6 deletions(-)
git: warning: confstr() failed with code 5: couldn't get path of DARWIN_USER_TEMP_DIR; using /tmp instead
git: error: couldn't create cache file '/tmp/xcrun_db-nLr5k5ff' (errno=Operation not permitted)
2026-09-23 15:37:22.279 xcodebuild[14972:3452941]  DVTFilePathFSEvents: Failed to start fs event stream.
2026-09-23 15:37:22.370 xcodebuild[14972:3452940] [MT] DVTDeveloperPaths: Failed to get length of DARWIN_USER_CACHE_DIR from confstr(3), error = Error Domain=NSPOSIXErrorDomain Code=5 "Input/output error". Using NSCachesDirectory instead.
git: warning: confstr() failed with code 5: couldn't get path of DARWIN_USER_TEMP_DIR; using /tmp instead
git: error: couldn't create cache file '/tmp/xcrun_db-L4gDfaSo' (errno=Operation not permitted)
2026-09-23 15:37:22.801 xcodebuild[15008:3453060]  DVTFilePathFSEvents: Failed to start fhook: SessionStart
hook: SessionStart
hook: SessionStart
hook: SessionStart Failed
hook: SessionStart Failed
hook: SessionStart Completed
hook: UserPromptSubmit
hook: UserPromptSubmit Completed
codex
요청하신 5가지 실패 모드만 좁혀서 검토하겠습니다. 먼저 협업 프로토콜과 실제 서비스·화면의 주변 코드(특히 `diff.removed` 계산, 테넌트/글로벌 역할 조회 범위, 트랜잭션)를 대조한 뒤, 결함이 확인된 항목만 파일·줄번호와 함께 보고하겠습니다.
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse Failed
hook: PreToolUse Completed
hook: PreToolUse Completed
exec
/bin/zsh -lc "sed -n '1,240p' .team/REVIEW-PROTOCOL.md && sed -n '120,270p' src/app/role/role-function/role-fhook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse Failed
hook: PreToolUse Completed
hook: PreToolUse Completed
hook: PreToolUse Failed
hook: PreToolUse Completed
hook: PreToolUse Completed
hook: PreToolUse Failed
hook: PreToolUse Completed
hook: PreToolUse Completed
exec
/bin/zsh -lc "sed -n '1,240p' .team/reviews/manual-93-p1c-codex.md" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 0ms:
Reading additional input from stdin...
OpenAI Codex v0.146.0
--------
workdir: /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
model: gpt-5.6-sol
provider: openai
approval: never
sandbox: read-only
reasoning effort: none
reasoning summaries: none
session id: 01a0cf8e-dc8f-7190-8576-b733dfc5d6e0
--------
user
Revisá este cambio de un ERP multi-tenant (NestJS + Sequelize, frontend Next.js). Es el punto P1-c del Phase 93.

PROBLEMA QUE SE INTENTA CERRAR (verificado en el código):
`PUT /role-functions/bulk-actions/:roleId` guarda "estado final": todo functionId que NO venga
en el payload se BORRA (role-function.service.ts, bloque `staleIds`). Si la pantalla guarda con
la lista cargada a medias, se revocan permisos en masa. Hasta ahora lo único que lo evitaba era
una línea en el front (`if (!loaded || loadError) return;`); el servidor no se defendía solo.
En Phase 93 se va a rehacer esa pantalla, así que esa línea desaparece.

SOLUCIÓN ELEGIDA POR EL USUARIO (de 3 opciones): el cliente declara cuántas funciones va a
revocar (`expectedRemovals`) y el servidor lo contrasta con su propio cálculo; si difiere, 409.
Es fase EXPAND: si no viene el campo, se comporta como antes (hay un segundo cliente,
la app Flutter `tienda-admin-app`, que todavía no lo manda).

DATOS MEDIDOS: role_functions sin ninguna acción = 0 filas (local 14.296 / prod 16.806),
así que cliente y servidor cuentan el mismo conjunto.

BUSCO ESPECÍFICAMENTE:
1. ¿Hay alguna forma de que este guard rechace un guardado legítimo (falso 409)? Concurrencia,
   funciones que el usuario no ve, roles globales (store_id IS NULL), etc.
2. ¿Hay alguna forma de que NO atrape el caso que dice atrapar?
3. ¿La unidad de conteo (funciones que pierden el permiso entero, no pares acción) es la correcta?
   ¿Puede una carga parcial provocar borrado de ACCIONES sin disparar el guard?
4. ¿El manejo de null/undefined/valores no enteros deja algún fail-open?
5. ¿El orden (validar ANTES de borrar, dentro de la transacción) es correcto?
No repitas lo que ya está bien. Señalá defectos concretos con archivo y línea.

DIFF:diff --git a/src/app/role/role-function/role-function.controller.spec.ts b/src/app/role/role-function/role-function.controller.spec.ts
index 29d876c9..bdcb45c1 100644
--- a/src/app/role/role-function/role-function.controller.spec.ts
+++ b/src/app/role/role-function/role-function.controller.spec.ts
@@ -68,13 +68,36 @@ describe('RoleFunctionController', () => {
 
       await controller.bulkUpdateActions(3, user, body);
 
-      // ★ 마지막 인자는 **요청자**의 id 다 — 감사에 "누가 바꿨나" 로 남는다.
+      // ★ 4번째 인자는 **요청자**의 id 다 — 감사에 "누가 바꿨나" 로 남는다.
       //   안 넘기면 user_id 가 NULL(미귀속)이 된다.
+      // ★ 5번째는 선언한 회수 건수(P1-c). 안 보낸 요청이면 undefined 그대로 간다.
       expect(service.bulkUpdateRoleFunctionActions).toHaveBeenCalledWith(
         3,
         10,
         body.data,
         42,
+        undefined,
+      );
+    });
+
+    // [Phase 93 · P1-c] 컨트롤러가 이 값을 **그대로 넘겨야** 계약이 성립한다.
+    // 서비스에만 판정을 넣고 컨트롤러가 값을 버리� succeeded in 5545ms:
2026-09-23 15:37:18.775 xcodebuild[14735:3452060]  DVTFilePathFSEvents: Failed to start fs event stream.
2026-09-23 15:37:18.958 xcodebuild[14735:3452059] [MT] DVTDeveloperPaths: Failed to get length of DARWIN_USER_CACHE_DIR from confstr(3), error = Error Domain=NSPOSIXErrorDomain Code=5 "Input/output error". Using NSCachesDirectory instead.
git: warning: confstr() failed with code 5: couldn't get path of DARWIN_USER_TEMP_DIR; using /tmp instead
git: errohook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse Failed
hook: PreToolUse Completed
hook: PreToolUse Completed
exec
/bin/zsh -lc "rg --files | rg 'role-function\\.(service|controller)(\\.spec)?\\.ts"'$|RolePermissionsDrawer'"\\.tsx"'$|CLAUDE'"\\.md"'$'"'" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 0ms:
CLAUDE.md
api-ventago/src/app/role/role-function/role-function.service.spec.ts
api-ventago/src/app/role/role-function/role-function.service.ts
api-ventago/src/app/role/role-function/role-function.controller.ts
api-ventago/src/app/role/role-function/role-function.controller.spec.ts
ventago-app/src/views/users/roles/RolePermissionsDrawer.tsx

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
/bin/zsh -lc "nl -ba api-ventago/src/app/role/role-function/role-function.service.ts | sed -n '1,300p'; nl -ba ventago-app/src/views/users/roles/RolePermissionsDrawer.tsx | sed -n '1,260p'; nl -ba api-ventago/src/app/role/role-function/role-function.controller.ts | sed -n '1,120p'; rg -n \"bulkUpdateRoleFunctionActions|bulk-actions|RolePermissionsDrawer|diff\\.removed|removed:\" api-ventago/src ventago-app/src" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 0ms:
     1	import {
     2	  BadRequestException,
     3	  ConflictException,
     4	  ForbiddenException,
     5	  Injectable,
     6	} from '@nestjs/common';
     7	import { InjectModel } from '@nestjs/sequelize';
     8	import { Op } from 'sequelize';
     9	import { RoleFunction } from './role-function.model';
    10	import { RoleFunctionAction } from './role-function-action.model';
    11	import { Role } from '../role.model';
    12	import { CrudService } from 'src/common/crud/crud.service';
    13	import { PermissionCacheService } from 'src/app/permissions/permission-cache.service';
    14	import { MemoryCacheService } from 'src/common/cache/memory-cache.service';
    15	import { PERM_CACHE_PREFIX } from 'src/app/auth/perm-cache-key';
    16	import { auditedWrite } from 'src/common/audit/audited-write';
    17	import { setAuditActor } from 'src/common/audit/audit-actor';
    18	import { Transaction } from 'sequelize';
    19	
    20	// CRUD 액션 목록 상수
    21	const CRUD_ACTIONS = ['create', 'read', 'update', 'delete'] as const;
    22	
    23	@Injectable()
    24	export class RoleFunctionService extends CrudService<RoleFunction> {
    25	  constructor(
    26	    @InjectModel(RoleFunction)
    27	    private readonly roleFunctionModel: typeof RoleFunction,
    28	    @InjectModel(RoleFunctionAction)
    29	    private readonly roleFunctionActionModel: typeof RoleFunctionAction,
    30	    @InjectModel(Role)
    31	    private readonly roleModel: typeof Role,
    32	    private readonly permissionCacheService: PermissionCacheService,
    33	    // [Wave 1] FunctionPermissionGuard 판정 캐시(perm:*) 무효화용
    34	    private readonly memoryCache: MemoryCacheService,
    35	  ) {
    36	    super(roleFunctionModel);
    37	  }
    38	
    39	  /**
    40	   * 이 역할이 이 매장 것인지 확인한다. 아니면 **거절**한다.
    41	   *
    42	   * ★ 전역 역할(`store_id IS NULL` — superadmin/admin/gerente/vendedor 씨앗 4개)은
    43	   *   어느 매장도 편집 대상으로 삼을 수 없다. 그것을 고치면 **전 매장에 번진다.**
    44	   * ★ `storeId` 가 없는 호출(superadmin 등)도 거절한다 — 무엇을 고칠지 모르는 상태에서
    45	   *   쓰기를 허용하면 대상이 불분명한 채로 행이 생긴다. 대상 매장을 명시해야 한다.
    46	   */
    47	  private async assertRoleBelongsToStore(roleId: number, storeId: number) {
    48	    if (!storeId) {
    49	      throw new ForbiddenException(
    50	        'No se puede editar permisos sin indicar la tienda.',
    51	      );
    52	    }
    53	
    54	    const role = await this.roleModel.findOne({
    55	      where: { id: roleId, storeId },
    56	      attributes: ['id'],
    57	    });
    58	
    59	    if (!role) {
    60	      throw new ForbiddenException('Ese rol no pertenece a esta tienda.');
    61	    }
    62	  }
    63	
    64	  async getFunctionsByRoleAndStore(roleId: number, storeId: number) {
    65	    return this.roleFunctionModel.findAll({
    66	      where: { roleId, storeId },
    67	      include: ['function', { model: RoleFunctionAction }],
    68	    });
    69	  }
    70	
    71	  // 새 RoleFunction 생성과 동시에 4개 CRUD 액션 자동 생성
    72	  async createWithActions(
    73	    roleId: number,
    74	    storeId: number,
    75	    functionId: number,
    76	    // 호출자가 트랜잭션을 열었으면 **반드시** 넘긴다 — 안 넘기면 이 문장만
    77	    // 별도 커넥션에서 커밋돼 부분 저장이 된다.
    78	    transaction?: Transaction,
    79	  ): Promise<RoleFunction> {
    80	    const roleFunction = await this.roleFunctionModel.create(
    81	      { roleId, functionId, storeId },
    82	      { transaction },
    83	    );
    84	
    85	    // 4개 CRUD 액션 일괄 생성 (중복 시 무시)
    86	    await Promise.all(
    87	      CRUD_ACTIONS.map((action) =>
    88	        this.roleFunctionActionModel.findOrCreate({
    89	          where: { roleFunctionId: roleFunction.id, action },
    90	          defaults: { roleFunctionId: roleFunction.id, action },
    91	          transaction,
    92	        }),
    93	      ),
    94	    );
    95	
    96	    return roleFunction;
    97	  }
    98	
    99	  // 특정 RoleFunction의 액션 목록을 교체 (기존 삭제 후 새로 생성)
   100	  async updateActionsForRoleFunction(
   101	    roleFunctionId: number,
   102	    actions: string[],
   103	    // [타임캡슐] **요청자**의 id.
   104	    actorUserId?: number,
   105	  ) {
   106	    const validActions = ['create', 'read', 'update', 'delete'];
   107	    const filtered = actions.filter((a) => validActions.includes(a));
   108	
   109	    const sequelize = this.roleFunctionModel.sequelize;
   110	    if (!sequelize) {
   111	      throw new Error('Sequelize 인스턴스를 찾을 수 없습니다');
   112	    }
   113	
   114	    // ★ destroy 후 create 인데 트랜잭션이 없었다 — create 가 실패하면
   115	    //   **그 기능의 권한이 통째로 사라진 채** 남고, 감사에는 "삭제" 만 정상 변경처럼 남는다.
   116	    return await auditedWrite(
   117	      sequelize as any,
   118	      actorUserId,
   119	      async (transaction) => {
   120	        await RoleFunctionAction.destroy({
   121	          where: { roleFunctionId },
   122	          transaction,
   123	        });
   124	
   125	        return await Promise.all(
   126	          filtered.map((action) =>
   127	            RoleFunctionAction.create(
   128	              { roleFunctionId, action },
   129	              { transaction },
   130	            ),
   131	          ),
   132	        );
   133	      },
   134	    );
   135	  }
   136	
   137	  // 역할의 모든 function-action을 한 번에 업데이트
   138	  //
   139	  // [2026-07-28 성능] 종전 구현은 항목마다 순차 await 였다 — 175개 기능 × (DELETE + 최대 4 INSERT)
   140	  // ≈ 900회 왕복이라 저장이 수십 초 걸리고 모바일 앱의 15s 타임아웃에 걸려 실패했다
   141	  // (서버 로그에 PUT 자체가 안 남던 이유 = 클라이언트가 먼저 끊음).
   142	  // 배치 + 단일 트랜잭션으로 왕복을 5회 수준까지 줄인다.
   143	  async bulkUpdateRoleFunctionActions(
   144	    roleId: number,
   145	    storeId: number,
   146	    data: Array<{ functionId: number; actions: string[] }>,
   147	    // [타임캡슐] **요청자**의 id.
   148	    actorUserId?: number,
   149	    // ★★ [Phase 93 · P1-c] 호출자가 **의도한 회수 건수**. 아래에서 서버 계산과 대조한다.
   150	    expectedRemovals?: number | null,
   151	  ) {
   152	    const validActions = CRUD_ACTIONS as readonly string[];
   153	
   154	    // ★★ [Phase 93 · P1] roleId 가 **이 매장의 역할인지** 먼저 확인한다.
   155	    //
   156	    // 종전에는 `storeId` 만 로그인 사용자에게서 받고 `roleId` 는 URL 을 그대로 믿었다.
   157	    // 그래서 남의 매장 roleId 를 넣으면 (남의 roleId, 내 storeId) 조합의 role_functions
   158	    // 행이 만들어졌다 — 소스 전체에 `roles.store_id = storeId` 검사가 **0건**이었다.
   159	    //
   160	    // ★ 검사는 **쓰기 직전 한 곳**에 둔다. 컨트롤러에 두면 다른 호출부가 생겼을 때
   161	    //   조용히 우회된다(가드가 여럿이면 엉뚱한 가드로 통과한다).
   162	    await this.assertRoleBelongsToStore(roleId, storeId);
   163	
   164	    const sequelize = this.roleFunctionModel.sequelize;
   165	    if (!sequelize) {
   166	      throw new Error('Sequelize 인스턴스를 찾을 수 없습니다');
   167	    }
   168	
   169	    // 트랜잭션 안에서는 외부 I/O 를 하지 않는다 (캐시 무효화는 커밋 후).
   170	    await sequelize.transaction(async (transaction) => {
   171	      // ★ 이 경로는 트랜잭션이 이미 있었다 — 행위자만 걸면 된다.
   172	      await setAuditActor(sequelize, transaction, actorUserId);
   173	
   174	      const existingRFs = await this.roleFunctionModel.findAll({
   175	        where: { roleId, storeId },
   176	        transaction,
   177	      });
   178	      const existingMap = new Map(existingRFs.map((rf) => [rf.functionId, rf]));
   179	      const dataFnIds = new Set(data.map((d) => d.functionId));
   180	
   181	      // 1) 없어진 기능의 role_function 일괄 삭제 (action 은 FK cascade)
   182	      const staleIds = existingRFs
   183	        .filter((rf) => !dataFnIds.has(rf.functionId))
   184	        .map((rf) => rf.id);
   185	
   186	      // ★★ [Phase 93 · P1-c] **부재를 삭제로 읽기 전에, 그것이 의도인지 확인한다.**
   187	      //
   188	      // 이 경로는 「최종 상태 교체」다 — payload 에 없는 기능은 **전부 지운다.**
   189	      // 그래서 화면이 목록을 **덜 받은 채** 저장하면 그만큼 권한이 사라진다.
   190	      // 지금까지 이것을 막은 것은 프론트의 `if (!loaded || loadError) return;` 한 줄뿐이고,
   191	      // **서버는 스스로 막지 않았다.** 화면을 새로 만들면(5·6단계) 그 한 줄은 사라진다.
   192	      //
   193	      // 막는 방법: 호출자가 「이번에 N개를 회수한다」를 같이 보내고, 서버가 자기 계산과
   194	      // 대조한다. 부분 로드는 «회수 0» 을 보내는데 서버는 다수를 계산하므로 **정확히 그
   195	      // 순간에 걸린다.** 임계값도 비율도 없다 — 의도와 결과가 다르면 거절이다.
   196	      //
   197	      // ★ 세는 단위는 **통째로 권한을 잃는 기능의 수**다(액션 쌍이 아니다).
   198	      //   액션 제거는 payload 에 **있는** 기능에만 일어나므로(아래 `targetIds` 참조)
   199	      //   부분 로드로는 발생하지 않는다. 위험한 수량은 이것 하나다.
   200	      //
   201	      // ★ expand 단계다 — 안 보내는 옛 클라이언트는 종전대로 통과시킨다.
   202	      //   보냈는데 틀리면 거절한다(보내고도 무시하면 계약이 없는 것과 같다).
   203	      if (expectedRemovals !== undefined && expectedRemovals !== null) {
   204	        if (!Number.isInteger(expectedRemovals) || expectedRemovals < 0) {
   205	          throw new BadRequestException(
   206	            `expectedRemovals 는 0 이상의 정수여야 합니다 (받은 값: ${String(
   207	              expectedRemovals,
   208	            )})`,
   209	          );
   210	        }
   211	        if (staleIds.length !== expectedRemovals) {
   212	          throw new ConflictException(
   213	            `권한 회수 건수가 요청과 다릅니다 — 요청은 ${expectedRemovals}건을 의도했는데 ` +
   214	              `서버는 ${staleIds.length}건을 회수하게 됩니다. ` +
   215	              `화면이 권한 목록을 전부 읽지 못한 상태일 수 있습니다. ` +
   216	              `다시 불러온 뒤 저장해 주세요.`,
   217	          );
   218	        }
   219	      }
   220	
   221	      if (staleIds.length > 0) {
   222	        await this.roleFunctionActionModel.destroy({
   223	          where: { roleFunctionId: { [Op.in]: staleIds } },
   224	          transaction,
   225	        });
   226	        await this.roleFunctionModel.destroy({
   227	          where: { id: { [Op.in]: staleIds } },
   228	          transaction,
   229	        });
   230	      }
   231	
   232	      // 2) 신규 기능의 role_function 일괄 생성
   233	      const missing = data.filter((d) => !existingMap.has(d.functionId));
   234	      if (missing.length > 0) {
   235	        const createdRFs = await this.roleFunctionModel.bulkCreate(
   236	          missing.map((d) => ({
   237	            roleId,
   238	            functionId: d.functionId,
   239	            storeId,
   240	          })) as any[],
   241	          { transaction, returning: true },
   242	        );
   243	        for (const rf of createdRFs) {
   244	          existingMap.set(rf.functionId, rf);
   245	        }
   246	      }
   247	
   248	      // 3) 액션은 **차이만** 쓴다.
   249	      //
   250	      // ★ 종전에는 대상 전체를 지우고 전체를 다시 넣었다. 그래도 결과는 같지만,
   251	      //   감사 트리거가 붙은 뒤로는 그 방식이 **"아무것도 안 바뀐 저장" 에도
   252	      //   삭제 640 + 생성 640 = 1,280개의 감사 행**을 만든다(스테이징 실측).
   253	      //   운영 audit_logs 전체가 890행인데 **한 번 저장이 그보다 많다.**
   254	      //   그러면 "누가 언제 권한을 바꿨나" 를 물었을 때 진짜 변경이
   255	      //   무변경 churn 에 묻혀 **감사가 감사 구실을 못 한다.**
   256	      //
   257	      //   ★★ 이것은 레거시 `codigos_tmp` 가 244MB 가 된 것과 **같은 형태**다 —
   258	      //   안 바뀐 것을 계속 적는 것. 그 문제를 지적해 놓고 같은 구조를 만들 뻔했다.
   259	      //   (codex 자문: "delete-all/create-all 대신 diff 로 감사 노이즈와 잠금을 줄여라")
   260	      //
   261	      //   덤으로 잠금 보유 시간도 준다 — 실측 165ms → 변경분만큼으로.
   262	      const targetIds = data
   263	        .map((d) => existingMap.get(d.functionId)?.id)
   264	        .filter((id): id is number => typeof id === 'number');
   265	
   266	      // 지금 DB 에 있는 (roleFunctionId, action) 쌍 → 그 행의 id 를 같이 들고 있는다.
   267	      // ★ id 를 들고 있어야 **삭제를 한 번에** 묶을 수 있다 —
   268	      //   쌍마다 destroy 를 부르면 640개 해제 시 왕복이 1회에서 640회로 는다(N+1).
   269	      //   이 경로는 이미 "900회 왕복 → 모바일 15s 타임아웃" 이력이 있다(codex 지적 P1).
   270	      const currentPairs = new Map<string, number>();
   271	      if (targetIds.length > 0) {
   272	        const current = await this.roleFunctionActionModel.findAll({
   273	          where: { roleFunctionId: { [Op.in]: targetIds } },
   274	          attributes: ['id', 'roleFunctionId', 'action'],
   275	          transaction,
   276	        });
   277	        for (const row of current) {
   278	          currentPairs.set(`${row.roleFunctionId}:${row.action}`, row.id);
   279	        }
   280	      }
   281	
   282	      // 있어야 할 쌍
   283	      const wantedPairs = new Set<string>();
   284	      const wantedRows: Array<{ roleFunctionId: number; action: string }> = [];
   285	      for (const item of data) {
   286	        const rf = existingMap.get(item.functionId);
   287	        if (!rf) {
   288	          continue;
   289	        }
   290	        for (const action of item.actions) {
   291	          if (!validActions.includes(action)) {
   292	            continue;
   293	          }
   294	          const key = `${rf.id}:${action}`;
   295	          if (wantedPairs.has(key)) {
   296	            continue; // 요청 안의 중복
   297	          }
   298	          wantedPairs.add(key);
   299	          wantedRows.push({ roleFunctionId: rf.id, action });
   300	        }
     1	// ============================================================================
     2	// 역할별 권한 편집 Drawer — 기능(Función) 단위 스위치 방식 (2026-07-28 재설계)
     3	//
     4	// 정책: function 이름이 이미 동사이므로 "기능을 줄지 말지"로 통제하고,
     5	// 부여한 기능에는 4개 액션(create/read/update/delete)을 모두 넣는다.
     6	// (migrations/2026-07-28-reseed-role-permissions.sql 과 동일 정책)
     7	//
     8	// 안전 규칙:
     9	// - 로드 실패 시 Guardar 비활성 — 빈 상태로 저장하면 역할 권한 전체가 삭제됨
    10	// - 역할 전환 시 로컬 상태 즉시 초기화 (useRoleFunctions 훅에서 보장)
    11	// - 변경 사항이 있을 때만 저장 가능, diff(+N/−N)를 푸터에 표시
    12	// ============================================================================
    13	import { useState, useEffect, useMemo, useCallback } from 'react';
    14	import Drawer from '@mui/material/Drawer';
    15	import Box from '@mui/material/Box';
    16	import Typography from '@mui/material/Typography';
    17	import IconButton from '@mui/material/IconButton';
    18	import Switch from '@mui/material/Switch';
    19	import Checkbox from '@mui/material/Checkbox';
    20	import TextField from '@mui/material/TextField';
    21	import InputAdornment from '@mui/material/InputAdornment';
    22	import Button from '@mui/material/Button';
    23	import Chip from '@mui/material/Chip';
    24	import Alert from '@mui/material/Alert';
    25	import CircularProgress from '@mui/material/CircularProgress';
    26	import Accordion from '@mui/material/Accordion';
    27	import AccordionSummary from '@mui/material/AccordionSummary';
    28	import AccordionDetails from '@mui/material/AccordionDetails';
    29	import Tooltip from '@mui/material/Tooltip';
    30	import toast from 'react-hot-toast';
    31	import Icon from 'src/@core/components/icon';
    32	import apiConnector from 'src/services/api.service';
    33	import { useFunctionsStructure } from './hooks/useFunctions';
    34	import { useRoleFunctions } from './hooks/useRoleFunctions';
    35	
    36	const ALL_ACTIONS = ['create', 'read', 'update', 'delete'];
    37	
    38	interface RoleInfo {
    39	  id: number;
    40	  title: string;
    41	  totalUsers?: number;
    42	}
    43	
    44	interface Props {
    45	  open: boolean;
    46	  onClose: () => void;
    47	  role?: RoleInfo;
    48	}
    49	
    50	const RolePermissionsDrawer = ({ open, onClose, role }: Props) => {
    51	  const { structure, loading: structureLoading } = useFunctionsStructure();
    52	  const {
    53	    roleFunctionData,
    54	    loading: roleLoading,
    55	    error: loadError,
    56	    loaded,
    57	    refetch
    58	  } = useRoleFunctions(open ? role?.id : undefined);
    59	
    60	  // 활성화된 functionId 집합 (편집 중 상태)
    61	  const [enabledIds, setEnabledIds] = useState<Set<number>>(new Set());
    62	
    63	  // 서버 원본 (diff 계산용)
    64	  const [originalIds, setOriginalIds] = useState<Set<number>>(new Set());
    65	  const [search, setSearch] = useState('');
    66	  const [saving, setSaving] = useState(false);
    67	
    68	  // 서버 데이터 로드 완료 시에만 편집 상태 초기화 — stale/빈 상태로 덮어쓰기 방지
    69	  useEffect(() => {
    70	    if (!loaded) return;
    71	    const ids = new Set(roleFunctionData.map(rf => rf.functionId));
    72	    setEnabledIds(new Set(ids));
    73	    setOriginalIds(ids);
    74	  }, [loaded, roleFunctionData]);
    75	
    76	  // Drawer 를 열 때마다 검색어 초기화
    77	  useEffect(() => {
    78	    if (open) setSearch('');
    79	  }, [open]);
    80	
    81	  // 검색 필터가 적용된 구조 (App > Módulo > Función)
    82	  const filteredStructure = useMemo(() => {
    83	    const raw = Array.isArray(structure) ? structure : [];
    84	
    85	    // 기능이 0개인 빈 모듈/앱은 제외 — 조절할 항목이 없어 혼란만 준다
    86	    const apps = raw
    87	      .map((app: any) => ({
    88	        ...app,
    89	        modules: (app.modules || []).filter((m: any) => (m.functions || []).length > 0)
    90	      }))
    91	      .filter((app: any) => app.modules.length > 0);
    92	
    93	    const term = search.trim().toLowerCase();
    94	    if (!term) return apps;
    95	
    96	    return apps
    97	      .map((app: any) => ({
    98	        ...app,
    99	        modules: (app.modules || [])
   100	          .map((mod: any) => ({
   101	            ...mod,
   102	            functions: (mod.functions || []).filter(
   103	              (fn: any) =>
   104	                (fn.name || '').toLowerCase().includes(term) ||
   105	                (fn.description || '').toLowerCase().includes(term) ||
   106	                (mod.name || '').toLowerCase().includes(term)
   107	            )
   108	          }))
   109	          .filter((mod: any) => mod.functions.length > 0)
   110	      }))
   111	      .filter((app: any) => app.modules.length > 0);
   112	  }, [structure, search]);
   113	
   114	  // diff 계산: 추가/제거된 기능 수
   115	  const diff = useMemo(() => {
   116	    let added = 0;
   117	    let removed = 0;
   118	    enabledIds.forEach(id => {
   119	      if (!originalIds.has(id)) added += 1;
   120	    });
   121	    originalIds.forEach(id => {
   122	      if (!enabledIds.has(id)) removed += 1;
   123	    });
   124	
   125	    return { added, removed, changed: added + removed };
   126	  }, [enabledIds, originalIds]);
   127	
   128	  const toggleFunction = useCallback((fnId: number) => {
   129	    setEnabledIds(prev => {
   130	      const next = new Set(prev);
   131	      if (next.has(fnId)) next.delete(fnId);
   132	      else next.add(fnId);
   133	
   134	      return next;
   135	    });
   136	  }, []);
   137	
   138	  // 모듈 단위 전체 토글
   139	  const toggleModule = useCallback((mod: any, enable: boolean) => {
   140	    setEnabledIds(prev => {
   141	      const next = new Set(prev);
   142	      (mod.functions || []).forEach((fn: any) => {
   143	        if (enable) next.add(fn.id);
   144	        else next.delete(fn.id);
   145	      });
   146	
   147	      return next;
   148	    });
   149	  }, []);
   150	
   151	  const handleSave = async () => {
   152	    if (!role?.id || loadError || !loaded) return;
   153	    setSaving(true);
   154	    try {
   155	      // 정책: 활성 기능마다 4개 액션 전부 부여 (가드가 요구하는 액션이 기능마다 다름)
   156	      const data = Array.from(enabledIds).map(functionId => ({
   157	        functionId,
   158	        actions: [...ALL_ACTIONS]
   159	      }));
   160	      // ★ [Phase 93 · P1-c] 이 저장이 **회수하려는 기능 수**를 같이 보낸다.
   161	      //   이 엔드포인트는 「최종 상태 교체」라 payload 에 없는 기능을 전부 지운다 —
   162	      //   목록을 덜 읽은 채 저장하면 그만큼 권한이 사라진다. 서버가 자기 계산과
   163	      //   대조해 다르면 409 로 거절하므로, 그때는 «부재» 가 «삭제» 로 읽히지 않는다.
   164	      //   (`diff.removed` 는 원래 상태 대비라 화면이 이미 갖고 있던 값이다.)
   165	      await apiConnector.put(`/role-functions/bulk-actions/${role.id}`, {
   166	        data,
   167	        expectedRemovals: diff.removed,
   168	      });
   169	      toast.success(`Permisos de "${role.title}" guardados (${enabledIds.size} funciones).`);
   170	      refetch();
   171	      onClose();
   172	    } catch (err: any) {
   173	      const msg = err?.response?.data?.message || err?.message || 'Error al guardar los permisos.';
   174	      toast.error(Array.isArray(msg) ? msg.join(', ') : msg);
   175	    } finally {
   176	      setSaving(false);
   177	    }
   178	  };
   179	
   180	  const handleCancel = () => {
   181	    // 편집 내용 폐기 후 서버 원본으로 복원
   182	    setEnabledIds(new Set(originalIds));
   183	    onClose();
   184	  };
   185	
   186	  const isLoading = structureLoading || roleLoading;
   187	
   188	  return (
   189	    <Drawer
   190	      anchor='right'
   191	      open={open}
   192	      onClose={handleCancel}
   193	      PaperProps={{ sx: { width: { xs: '100%', sm: 520 }, display: 'flex', flexDirection: 'column' } }}
   194	    >
   195	      {/* 헤더 */}
   196	      <Box sx={{ p: 4, pb: 3, borderBottom: theme => `1px solid ${theme.palette.divider}` }}>
   197	        <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
   198	          <Typography variant='h5'>Permisos del Rol</Typography>
   199	          <IconButton size='small' onClick={handleCancel}>
   200	            <Icon icon='tabler:x' />
   201	          </IconButton>
   202	        </Box>
   203	        <Box sx={{ mt: 1, display: 'flex', alignItems: 'center', gap: 2 }}>
   204	          <Chip label={role?.title || ''} color='primary' size='small' />
   205	          <Typography variant='body2' sx={{ color: 'text.secondary' }}>
   206	            {role?.totalUsers ?? 0} usuarios con este rol
   207	          </Typography>
   208	        </Box>
   209	        <TextField
   210	          fullWidth
   211	          size='small'
   212	          sx={{ mt: 3 }}
   213	          placeholder='Buscar función o módulo...'
   214	          value={search}
   215	          onChange={e => setSearch(e.target.value)}
   216	          InputProps={{
   217	            startAdornment: (
   218	              <InputAdornment position='start'>
   219	                <Icon icon='tabler:search' fontSize={18} />
   220	              </InputAdornment>
   221	            )
   222	          }}
   223	        />
   224	      </Box>
   225	
   226	      {/* 본문 */}
   227	      <Box sx={{ flex: 1, overflowY: 'auto', p: 3 }}>
   228	        {isLoading && (
   229	          <Box sx={{ display: 'flex', justifyContent: 'center', mt: 8 }}>
   230	            <CircularProgress />
   231	    hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse Failed
hook: PreToolUse Completed
hook: PreToolUse Completed
hook: PreToolUse Failed
hook: PreToolUse Completed
hook: PreToolUse Completed
hook: PreToolUse Failed
hook: PreToolUse Completed
hook: PreToolUse Completed
exec
/bin/zsh -lc "nl -ba src/views/users/roles/RolePermissionsDrawer.tsx | sed -n '1,250p'" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/ventago-app
exec
/bin/zsh -lc "nl -ba src/app/role/role-function/role-function.service.ts | sed -n '120,330p'; nl -ba src/app/role/role-function/role-function.controller.ts | sed -n '1,110p'" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago
exec
/bin/zsh -lc "rg -n \"getFunctionsByRoleAndStore|bulkUpdateRoleFunctionActions|RoleFunction|storeId|store_id\" src/app/role -g '*.ts'" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago
 succeeded in 0ms:
     1	// ============================================================================
     2	// 역할별 권한 편집 Drawer — 기능(Función) 단위 스위치 방식 (2026-07-28 재설계)
     3	//
     4	// 정책: function 이름이 이미 동사이므로 "기능을 줄지 말지"로 통제하고,
     5	// 부여한 기능에는 4개 액션(create/read/update/delete)을 모두 넣는다.
     6	// (migrations/2026-07-28-reseed-role-permissions.sql 과 동일 정책)
     7	//
     8	// 안전 규칙:
     9	// - 로드 실패 시 Guardar 비활성 — 빈 상태로 저장하면 역할 권한 전체가 삭제됨
    10	// - 역할 전환 시 로컬 상태 즉시 초기화 (useRoleFunctions 훅에서 보장)
    11	// - 변경 사항이 있을 때만 저장 가능, diff(+N/−N)를 푸터에 표시
    12	// ============================================================================
    13	import { useState, useEffect, useMemo, useCallback } from 'react';
    14	import Drawer from '@mui/material/Drawer';
    15	import Box from '@mui/material/Box';
    16	import Typography from '@mui/material/Typography';
    17	import IconButton from '@mui/material/IconButton';
    18	import Switch from '@mui/material/Switch';
    19	import Checkbox from '@mui/material/Checkbox';
    20	import TextField from '@mui/material/TextField';
    21	import InputAdornment from '@mui/material/InputAdornment';
    22	import Button from '@mui/material/Button';
    23	import Chip from '@mui/material/Chip';
    24	import Alert from '@mui/material/Alert';
    25	import CircularProgress from '@mui/material/CircularProgress';
    26	import Accordion from '@mui/material/Accordion';
    27	import AccordionSummary from '@mui/material/AccordionSummary';
    28	import AccordionDetails from '@mui/material/AccordionDetails';
    29	import Tooltip from '@mui/material/Tooltip';
    30	import toast from 'react-hot-toast';
    31	import Icon from 'src/@core/components/icon';
    32	import apiConnector from 'src/services/api.service';
    33	import { useFunctionsStructure } from './hooks/useFunctions';
    34	import { useRoleFunctions } from './hooks/useRoleFunctions';
    35	
    36	const ALL_ACTIONS = ['create', 'read', 'update', 'delete'];
    37	
    38	interface RoleInfo {
    39	  id: number;
    40	  title: string;
    41	  totalUsers?: number;
    42	}
    43	
    44	interface Props {
    45	  open: boolean;
    46	  onClose: () => void;
    47	  role?: RoleInfo;
    48	}
    49	
    50	const RolePermissionsDrawer = ({ open, onClose, role }: Props) => {
    51	  const { structure, loading: structureLoading } = useFunctionsStructure();
    52	  const {
    53	    roleFunctionData,
    54	    loading: roleLoading,
    55	    error: loadError,
    56	    loaded,
    57	    refetch
    58	  } = useRoleFunctions(open ? role?.id : undefined);
    59	
    60	  // 활성화된 functionId 집합 (편집 중 상태)
    61	  const [enabledIds, setEnabledIds] = useState<Set<number>>(new Set());
    62	
    63	  // 서버 원본 (diff 계산용)
    64	  const [originalIds, setOriginalIds] = useState<Set<number>>(new Set());
    65	  const [search, setSearch] = useState('');
    66	  const [saving, setSaving] = useState(false);
    67	
    68	  // 서버 데이터 로드 완료 시에만 편집 상태 초기화 — stale/빈 상태로 덮어쓰기 방지
    69	  useEffect(() => {
    70	    if (!loaded) return;
    71	    const ids = new Set(roleFunctionData.map(rf => rf.functionId));
    72	    setEnabledIds(new Set(ids));
    73	    setOriginalIds(ids);
    74	  }, [loaded, roleFunctionData]);
    75	
    76	  // Drawer 를 열 때마다 검색어 초기화
    77	  useEffect(() => {
    78	    if (open) setSearch('');
    79	  }, [open]);
    80	
    81	  // 검색 필터가 적용된 구조 (App > Módulo > Función)
    82	  const filteredStructure = useMemo(() => {
    83	    const raw = Array.isArray(structure) ? structure : [];
    84	
    85	    // 기능이 0개인 빈 모듈/앱은 제외 — 조절할 항목이 없어 혼란만 준다
    86	    const apps = raw
    87	      .map((app: any) => ({
    88	        ...app,
    89	        modules: (app.modules || []).filter((m: any) => (m.functions || []).length > 0)
    90	      }))
    91	      .filter((app: any) => app.modules.length > 0);
    92	
    93	    const term = search.trim().toLowerCase();
    94	    if (!term) return apps;
    95	
    96	    return apps
    97	      .map((app: any) => ({
    98	        ...app,
    99	        modules: (app.modules || [])
   100	          .map((mod: any) => ({
   101	            ...mod,
   102	            functions: (mod.functions || []).filter(
   103	              (fn: any) =>
   104	                (fn.name || '').toLowerCase().includes(term) ||
   105	                (fn.description || '').toLowerCase().includes(term) ||
   106	                (mod.name || '').toLowerCase().includes(term)
   107	            )
   108	          }))
   109	          .filter((mod: any) => mod.functions.length > 0)
   110	      }))
   111	      .filter((app: any) => app.modules.length > 0);
   112	  }, [structure, search]);
   113	
   114	  // diff 계산: 추가/제거된 기능 수
   115	  const diff = useMemo(() => {
   116	    let added = 0;
   117	    let removed = 0;
   118	    enabledIds.forEach(id => {
   119	      if (!originalIds.has(id)) added += 1;
   120	    });
   121	    originalIds.forEach(id => {
   122	      if (!enabledIds.has(id)) removed += 1;
   123	    });
   124	
   125	    return { added, removed, changed: added + removed };
   126	  }, [enabledIds, originalIds]);
   127	
   128	  const toggleFunction = useCallback((fnId: number) => {
   129	    setEnabledIds(prev => {
   130	      const next = new Set(prev);
   131	      if (next.has(fnId)) next.delete(fnId);
   132	      else next.add(fnId);
   133	
   134	      return next;
   135	    });
   136	  }, []);
   137	
   138	  // 모듈 단위 전체 토글
   139	  const toggleModule = useCallback((mod: any, enable: boolean) => {
   140	    setEnabledIds(prev => {
   141	      const next = new Set(prev);
   142	      (mod.functions || []).forEach((fn: any) => {
   143	        if (enable) next.add(fn.id);
   144	        else next.delete(fn.id);
   145	      });
   146	
   147	      return next;
   148	    });
   149	  }, []);
   150	
   151	  const handleSave = async () => {
   152	    if (!role?.id || loadError || !loaded) return;
   153	    setSaving(true);
   154	    try {
   155	      // 정책: 활성 기능마다 4개 액션 전부 부여 (가드가 요구하는 액션이 기능마다 다름)
   156	      const data = Array.from(enabledIds).map(functionId => ({
   157	        functionId,
   158	        actions: [...ALL_ACTIONS]
   159	      }));
   160	      // ★ [Phase 93 · P1-c] 이 저장이 **회수하려는 기능 수**를 같이 보낸다.
   161	      //   이 엔드포인트는 「최종 상태 교체」라 payload 에 없는 기능을 전부 지운다 —
   162	      //   목록을 덜 읽은 채 저장하면 그만큼 권한이 사라진다. 서버가 자기 계산과
   163	      //   대조해 다르면 409 로 거절하므로, 그때는 «부재» 가 «삭제» 로 읽히지 않는다.
   164	      //   (`diff.removed` 는 원래 상태 대비라 화면이 이미 갖고 있던 값이다.)
   165	      await apiConnector.put(`/role-functions/bulk-actions/${role.id}`, {
   166	        data,
   167	        expectedRemovals: diff.removed,
   168	      });
   169	      toast.success(`Permisos de "${role.title}" guardados (${enabledIds.size} funciones).`);
   170	      refetch();
   171	      onClose();
   172	    } catch (err: any) {
   173	      const msg = err?.response?.data?.message || err?.message || 'Error al guardar los permisos.';
   174	      toast.error(Array.isArray(msg) ? msg.join(', ') : msg);
   175	    } finally {
   176	      setSaving(false);
   177	    }
   178	  };
   179	
   180	  const handleCancel = () => {
   181	    // 편집 내용 폐기 후 서버 원본으로 복원
   182	    setEnabledIds(new Set(originalIds));
   183	    onClose();
   184	  };
   185	
   186	  const isLoading = structureLoading || roleLoading;
   187	
   188	  return (
   189	    <Drawer
   190	      anchor='right'
   191	      open={open}
   192	      onClose={handleCancel}
   193	      PaperProps={{ sx: { width: { xs: '100%', sm: 520 }, display: 'flex', flexDirection: 'column' } }}
   194	    >
   195	      {/* 헤더 */}
   196	      <Box sx={{ p: 4, pb: 3, borderBottom: theme => `1px solid ${theme.palette.divider}` }}>
   197	        <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
   198	          <Typography variant='h5'>Permisos del Rol</Typography>
   199	          <IconButton size='small' onClick={handleCancel}>
   200	            <Icon icon='tabler:x' />
   201	          </IconButton>
   202	        </Box>
   203	        <Box sx={{ mt: 1, display: 'flex', alignItems: 'center', gap: 2 }}>
   204	          <Chip label={role?.title || ''} color='primary' size='small' />
   205	          <Typography variant='body2' sx={{ color: 'text.secondary' }}>
   206	            {role?.totalUsers ?? 0} usuarios con este rol
   207	          </Typography>
   208	        </Box>
   209	        <TextField
   210	          fullWidth
   211	          size='small'
   212	   hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse Failed
hook: PreToolUse Completed
hook: PreToolUse Completed
exec
/bin/zsh -lc "nl -ba api-ventago/src/app/role/role-function/role-function.service.ts | sed -n '280,410p'; nl -ba ventago-app/src/views/users/roles/hooks/useRoleFunctions.ts | sed -n '1,240p'; nl -ba api-ventago/src/app/role/role-function/role-function.model.ts | sed -n '1,200p'; nl -ba api-ventago/src/app/role/role-function/role-function-action.model.ts | sed -n '1,180p'; rg -n \"role_functions|role_function_actions\" api-ventago/src/database api-ventago/migrations api-ventago/src --glob '*migration*' --glob '*.sql' --glob '*.ts' | head -200" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 0ms:
   280	      }
   281	
   282	      // 있어야 할 쌍
   283	      const wantedPairs = new Set<string>();
   284	      const wantedRows: Array<{ roleFunctionId: number; action: string }> = [];
   285	      for (const item of data) {
   286	        const rf = existingMap.get(item.functionId);
   287	        if (!rf) {
   288	          continue;
   289	        }
   290	        for (const action of item.actions) {
   291	          if (!validActions.includes(action)) {
   292	            continue;
   293	          }
   294	          const key = `${rf.id}:${action}`;
   295	          if (wantedPairs.has(key)) {
   296	            continue; // 요청 안의 중복
   297	          }
   298	          wantedPairs.add(key);
   299	          wantedRows.push({ roleFunctionId: rf.id, action });
   300	        }
   301	      }
   302	
   303	      // 빼야 할 것만 — **한 번의 쿼리로** 지운다.
   304	      const removeIds = [...currentPairs.entries()]
   305	        .filter(([key]) => !wantedPairs.has(key))
   306	        .map(([, id]) => id);
   307	      if (removeIds.length > 0) {
   308	        await this.roleFunctionActionModel.destroy({
   309	          where: { id: { [Op.in]: removeIds } },
   310	          transaction,
   311	        });
   312	      }
   313	
   314	      // 없는 것만 만든다
   315	      const toAdd = wantedRows.filter(
   316	        (r) => !currentPairs.has(`${r.roleFunctionId}:${r.action}`),
   317	      );
   318	      if (toAdd.length > 0) {
   319	        await this.roleFunctionActionModel.bulkCreate(toAdd as any[], {
   320	          transaction,
   321	          ignoreDuplicates: true,
   322	        });
   323	      }
   324	    });
   325	
   326	    // [Wave 1] 역할 권한 변경 — 가드 판정 캐시 전체 무효화 (역할→유저 매핑 역추적 대신 안전 전체 삭제)
   327	    // [Phase 65 D8-1] 인메모리 캐시 purge 를 먼저 수행한다. 아래 DB 캐시 무효화가
   328	    // 실패해 throw 하면 이 줄이 실행되지 않아 낡은 판정 캐시가 남기 때문이다.
   329	    this.memoryCache.delByPrefix(PERM_CACHE_PREFIX);
   330	
   331	    // [Phase 33.1 D2-FIX] role_functions / role_function_actions 변경 후 영향 user 의 cache invalidate
   332	    // [Phase 65 D8-1] 무효화 실패는 삼키지 않는다 — 권한 변경 API 가 성공 응답을 주면 안 된다.
   333	    await this.permissionCacheService.invalidateRole(roleId);
   334	  }
   335	
   336	  async updateFunctionsForRole(
   337	    roleId: number,
   338	    storeId: number,
   339	    functionIds: number[],
   340	    // [타임캡슐] **요청자**의 id.
   341	    actorUserId?: number,
   342	  ) {
   343	    // ★★ [Phase 93 · P1 · codex 검토] `bulk-actions` 에만 소유권 검사를 넣었더니
   344	    //   **같은 목적의 다른 쓰기 경로가 그대로 뚫려 있었다.** `PUT /role-functions` 는
   345	    //   본문의 `roleId` 를 검증 없이 여기로 넘긴다 — 남의 매장 roleId 로
   346	    //   `(남의 role_id, 내 store_id)` 행을 만들 수 있었다.
   347	    //
   348	    // ⤷ 교훈: 경계를 한 곳에만 세우면 **우회로가 남는다.** 이 서비스의 쓰기 진입점은
   349	    //   둘뿐이고(`updateFunctionsForRole` · `bulkUpdateRoleFunctionActions`),
   350	    //   이제 **둘 다** 이 검사를 지난다. 아래 spec 이 그 짝을 기계로 센다.
   351	    await this.assertRoleBelongsToStore(roleId, storeId);
   352	
   353	    const sequelize = this.roleFunctionModel.sequelize;
   354	    if (!sequelize) {
   355	      throw new Error('Sequelize 인스턴스를 찾을 수 없습니다');
   356	    }
   357	
   358	    // ★ 역할의 권한을 **전부 지우고 다시 만드는** 절차인데 트랜잭션이 없었다.
   359	    //   생성이 실패하면 **그 역할의 권한이 통째로 사라진 채** 남는다(codex 지적 P1).
   360	    const created = await auditedWrite(
   361	      sequelize as any,
   362	      actorUserId,
   363	      async (transaction) => {
   364	        await this.roleFunctionModel.destroy({
   365	          where: { roleId, storeId },
   366	          transaction,
   367	        });
   368	
   369	        // 각 function에 대해 RoleFunction + 4개 CRUD 액션 함께 생성
   370	        return await Promise.all(
   371	          functionIds.map((fid) =>
   372	            this.createWithActions(roleId, storeId, fid, transaction),
   373	          ),
   374	        );
   375	      },
   376	    );
   377	
   378	    // [Wave 1] 역할 권한 교체 — 가드 판정 캐시 전체 무효화 (커밋 후)
   379	    this.memoryCache.delByPrefix(PERM_CACHE_PREFIX);
   380	
   381	    return created;
   382	  }
   383	}
     1	import { useState, useEffect, useCallback } from 'react';
     2	import apiConnector from 'src/services/api.service';
     3	
     4	// 역할별 Function + CRUD 액션 데이터 타입
     5	export interface RoleFunctionData {
     6	  functionId: number;
     7	  actions: string[];
     8	}
     9	
    10	export const useRoleFunctions = (roleId?: number) => {
    11	  const [roleFunctionData, setRoleFunctionData] = useState<RoleFunctionData[]>([]);
    12	  const [loading, setLoading] = useState(false);
    13	
    14	  // 로드 실패 여부 — 실패 상태에서 저장하면 권한 전체가 삭제되므로 호출측에서 반드시 차단
    15	  const [error, setError] = useState(false);
    16	
    17	  // 로드 완료 여부 — stale 데이터로 초기화하는 것을 방지 (역할 전환 시)
    18	  const [loaded, setLoaded] = useState(false);
    19	
    20	  const fetchData = useCallback(async (id: number) => {
    21	    setLoading(true);
    22	    setError(false);
    23	    try {
    24	      const result: any = await apiConnector.get(`/role-functions/${id}`);
    25	
    26	      // 응답: [{ id, roleId, functionId, roleFunctionActions: [{ action: 'create' }, ...] }]
    27	      const mapped: RoleFunctionData[] = (result || []).map((rf: any) => ({
    28	        functionId: rf.functionId,
    29	        actions: (rf.roleFunctionActions || []).map((rfa: any) => rfa.action)
    30	      }));
    31	      setRoleFunctionData(mapped);
    32	      setLoaded(true);
    33	    } catch {
    34	      setRoleFunctionData([]);
    35	      setError(true);
    36	      setLoaded(false);
    37	    } finally {
    38	      setLoading(false);
    39	    }
    40	  }, []);
    41	
    42	  useEffect(() => {
    43	    // 역할이 바뀌면 이전 역할의 데이터를 즉시 비움 — stale state 로 잘못 저장되는 사고 방지
    44	    setRoleFunctionData([]);
    45	    setLoaded(false);
    46	    setError(false);
    47	    if (!roleId) return;
    48	    fetchData(roleId);
    49	  }, [roleId, fetchData]);
    50	
    51	  const refetch = useCallback(() => {
    52	    if (roleId) fetchData(roleId);
    53	  }, [roleId, fetchData]);
    54	
    55	  return { roleFunctionData, loading, error, loaded, refetch };
    56	};
     1	import {
     2	  Table,
     3	  Model,
     4	  Column,
     5	  DataType,
     6	  ForeignKey,
     7	  PrimaryKey,
     8	  AutoIncrement,
     9	  BelongsTo,
    10	  HasMany,
    11	} from 'sequelize-typescript';
    12	import { Functions } from 'src/app/functions/functions.model';
    13	import { Role } from 'src/app/role/role.model';
    14	import { Branch } from 'src/app/branch/branch.model';
    15	import { RoleFunctionAction } from './role-function-action.model';
    16	
    17	@Table({ timestamps: true })
    18	export class RoleFunction extends Model {
    19	  @PrimaryKey
    20	  @AutoIncrement
    21	  @Column(DataType.INTEGER)
    22	  id: number;
    23	
    24	  @ForeignKey(() => Role)
    25	  @Column(DataType.INTEGER)
    26	  roleId: number;
    27	
    28	  @ForeignKey(() => Functions)
    29	  @Column(DataType.INTEGER)
    30	  functionId: number;
    31	
    32	  @Column(DataType.INTEGER)
    33	  storeId: number;
    34	
    35	  // Phase29: 지점 스코프 (NULL = 매장 전체 적용, 값 있으면 해당 지점만)
    36	  @ForeignKey(() => Branch)
    37	  @Column({ type: DataType.INTEGER, allowNull: true })
    38	  branchId: number | null;
    39	
    40	  @BelongsTo(() => Role)
    41	  role: Role;
    42	
    43	  @BelongsTo(() => Functions)
    44	  function: Functions;
    45	
    46	  @BelongsTo(() => Branch, { foreignKey: 'branchId', onDelete: 'CASCADE' })
    47	  branch: Branch;
    48	
    49	  // CRUD 액션 단위 권한 목록
    50	  @HasMany(() => RoleFunctionAction)
    51	  roleFunctionActions: RoleFunctionAction[];
    52	}
     1	import {
     2	  Table,
     3	  Model,
     4	  Column,
     5	  DataType,
     6	  ForeignKey,
     7	  PrimaryKey,
     8	  AutoIncrement,
     9	  BelongsTo,
    10	} from 'sequelize-typescript';
    11	import { RoleFunction } from './role-function.model';
    12	
    13	// 역할-기능 CRUD 액션 권한 테이블 (role_function_id + action 복합 UNIQUE 제약)
    14	@Table({
    15	  timestamps: true,
    16	  indexes: [
    17	    {
    18	      unique: true,
    19	      fields: ['role_function_id', 'action'],
    20	      name: 'role_function_actions_rf_action_unique',
    21	    },
    22	  ],
    23	})
    24	export class RoleFunctionAction extends Model {
    25	  @PrimaryKey
    26	  @AutoIncrement
    27	  @Column(DataType.INTEGER)
    28	  id: number;
    29	
    30	  // 연결된 RoleFunction의 ID
    31	  @ForeignKey(() => RoleFunction)
    32	  @Column(DataType.INTEGER)
    33	  roleFunctionId: number;
    34	
    35	  // 허용된 액션: 'create' | 'read' | 'update' | 'delete'
    36	  @Column(DataType.STRING(20))
    37	  action: string;
    38	
    39	  @BelongsTo(() => RoleFunction)
    40	  roleFunction: RoleFunction;
    41	}
api-ventago/src/database/migrations/remove-fabrica-app.sql:19:    -- 3. fabrica 모듈의 functions 제거 (role_function_actions, role_functions, user_function_actions, user_functions 포함)
api-ventago/src/database/migrations/remove-fabrica-app.sql:20:    DELETE FROM role_function_actions WHERE role_function_id IN (
api-ventago/src/database/migrations/remove-fabrica-app.sql:21:      SELECT rf.id FROM role_functions rf
api-ventago/src/database/migrations/remove-fabrica-app.sql:32:    DELETE FROM role_functions WHERE function_id IN (
api-ventago/src/common/tenant/tenant-scope.registry.ts:21: *   role_functions 24 / store_error_log 23 / payment_methods 13 / roles 4 /
api-ventago/src/common/tenant/tenant-scope.registry.ts:34:  'role_functions',
api-ventago/src/common/tenant/tenant-scope.registry.ts:53:  'role_functions_bak_20260728',
api-ventago/src/common/tenant/tenant-scope.registry.ts:54:  'role_functions_bak_20260728_orig',
api-ventago/migrations/2026-07-30-tenant-store-id-not-null.sql:22:--   NULL 행 실제 보유 → 제외: role_functions 24 / store_error_log 23 /
api-ventago/migrations/phase36-stock-movement-actions-backfill.sql:1:-- Phase 36 — stock.movement role_function_actions 보강
api-ventago/migrations/phase36-stock-movement-actions-backfill.sql:3:-- 목적: Phase 35 Plan 02 마이그레이션이 role_functions 만 INSERT 하고
api-ventago/migrations/phase36-stock-movement-actions-backfill.sql:4:--       role_function_actions 매핑이 누락되어 admin UI 권한 매트릭스가
api-ventago/migrations/phase36-stock-movement-actions-backfill.sql:7:-- 본 마이그레이션: 기존 role_functions(function_id=149, slug='stock.movement')
api-ventago/migrations/phase36-stock-movement-actions-backfill.sql:11:--             role_function_actions_rf_action_unique UNIQUE 제약 활용.
api-ventago/migrations/phase36-stock-movement-actions-backfill.sql:29:-- 보강: 모든 role_functions(function_id=149) × 4 actions CROSS JOIN INSERT
api-ventago/migrations/phase36-stock-movement-actions-backfill.sql:30:INSERT INTO role_function_actions (role_function_id, action, created_at, updated_at)
api-ventago/migrations/phase36-stock-movement-actions-backfill.sql:32:FROM role_functions rf
api-ventago/migrations/phase36-stock-movement-actions-backfill.sql:44:  FROM role_function_actions rfa
api-ventago/migrations/phase36-stock-movement-actions-backfill.sql:45:  JOIN role_functions rf ON rf.id = rfa.role_function_id
api-ventago/migrations/phase36-stock-movement-actions-backfill.sql:48:  SELECT COUNT(*) * 4 INTO expected FROM role_functions WHERE function_id = 149;
api-ventago/migrations/phase36-stock-movement-actions-backfill.sql:50:  RAISE NOTICE 'role_function_actions for stock.movement: total=% expected=%', total, expected;
api-ventago/migrations/2026-07-28-reseed-role-permissions-by-slug.sql:22:DROP TABLE IF EXISTS role_functions_bak_slug_20260728;
api-ventago/migrations/2026-07-28-reseed-role-permissions-by-slug.sql:23:DROP TABLE IF EXISTS role_function_actions_bak_slug_20260728;
api-ventago/migrations/2026-07-28-reseed-role-permissions-by-slug.sql:24:CREATE TABLE role_functions_bak_slug_20260728 AS SELECT * FROM role_functions;
api-ventago/migrations/2026-07-28-reseed-role-permissions-by-slug.sql:25:CREATE TABLE role_function_actions_bak_slug_20260728 AS SELECT * FROM role_function_actions;
api-ventago/migrations/2026-07-28-reseed-role-permissions-by-slug.sql:696:DELETE FROM role_function_actions
api-ventago/migrations/2026-07-28-reseed-role-permissions-by-slug.sql:697: WHERE role_function_id IN (SELECT id FROM role_functions
api-ventago/migrations/2026-07-28-reseed-role-permissions-by-slug.sql:699:DELETE FROM role_functions
api-ventago/migrations/2026-07-28-reseed-role-permissions-by-slug.sql:702:-- 6) 재부여 — role_functions
api-ventago/migrations/2026-07-28-reseed-role-permissions-by-slug.sql:703:INSERT INTO role_functions(role_id, function_id, store_id, created_at, updated_at)
api-ventago/migrations/2026-07-28-reseed-role-permissions-by-slug.sql:709:INSERT INTO role_function_actions(role_function_id, action, created_at, updated_at)
api-ventago/migrations/2026-07-28-reseed-role-permissions-by-slug.sql:711:FROM role_functions rf
api-ventago/migrations/2026-07-28-reseed-role-permissions-by-slug.sql:721:LEFT JOIN role_functions rf ON rf.role_id = r.id
api-ventago/migrations/2026-07-28-reseed-role-permissions-by-slug.sql:722:LEFT JOIN role_function_actions rfa ON rfa.role_function_id = rf.id
api-ventago/migrations/2026-07-28-reseed-role-permissions-by-slug.sql:730:--   DELETE FROM role_function_actions;
api-ventago/migrations/2026-07-28-reseed-role-permissions-by-slug.sql:731:--   DELETE FROM role_functions;
api-ventago/migrations/2026-07-28-reseed-role-permissions-by-slug.sql:732:--   INSERT INTO role_functions SELECT * FROM role_functions_bak_slug_20260728;
api-ventago/migrations/2026-07-28-reseed-role-permissions-by-slug.sql:733:--   INSERT INTO role_function_actions SELECT * FROM role_function_actions_bak_slug_20260728;
api-ventago/src/app/store/store-restore-unlinked-refs.ts:10://   `role_functions.store_id`(11,790행) · `roles.store_id` · `stocks.store_id` ·
api-ventago/src/app/store/store-restore-unlinked-refs.ts:163:  'role_functions.store_id': {
api-ventago/src/app/store/store-restore-unlinked-refs.ts:173:    why: '역할의 매장. role_functions.store_id 와 짝이다.',
api-ventago/src/app/store/store-restore-unlinked-refs.ts:233:    why: '개인 권한의 매장. role_functions.store_id 와 같은 이유.',
api-ventago/src/app/store/store-restore-plan.spec.ts:248:    //   (`role_functions.store_id` 11,790행이 여기 있다.)
api-ventago/src/app/store/store-restore-input.ts:65:  //   2026-08-22 실측: 한 매장 최대 테이블이 `role_function_actions` 4,415행,
api-ventago/src/app/store/store-backup-coverage.ts:6://   store_clients(고객 선수금 3,791행) · role_functions(권한 11,790행) ·
api-ventago/src/app/store/store-backup-coverage.ts:65:  'role_functions', // ★ 없으면 복원된 매장의 역할이 아무 기능도 못 한다
api-ventago/src/app/store/store-backup-coverage.ts:216:  role_function_actions:
api-ventago/src/app/store/store-backup-coverage.ts:217:    '운영 40,557행. 권한 판정은 role_functions × role_function_actions 를 조인한다 — ' +
api-ventago/src/app/store/store-backup-coverage.ts:220:    '개인 권한의 액션. role_function_actions 와 같은 이유.',
api-ventago/src/app/store/store-backup-coverage.ts:403:    '파생 캐시. 권한 원본(user_functions·role_functions)에서 재계산된다. ' +
api-ventago/src/app/store/store-backup-coverage.ts:496:  functions: '권한 기능 카탈로그. 매장별 부여는 role_functions 가 갖는다.',
api-ventago/src/app/store/store-backup-coverage.ts:538:  role_permissions: '레거시 권한 모델. 운영 0행. role_functions 가 현행이다.',
api-ventago/src/app/store/store-backup-coverage.ts:548:  /_bak(_|$)/, // 수동 스냅샷 (role_functions_bak_20260728 등)
api-ventago/migrations/2026-08-21-audit-triggers-price-name-permissions.sql:15:--     prices · products · roles · role_functions · role_function_actions
api-ventago/migrations/2026-08-21-audit-triggers-price-name-permissions.sql:18:--     `role_functions × role_function_actions` 를 조인하고, 실측 행 수는
api-ventago/migrations/2026-08-21-audit-triggers-price-name-permissions.sql:142:DROP TRIGGER IF EXISTS trg_audit_role_functions ON role_functions;
api-ventago/migrations/2026-08-21-audit-triggers-price-name-permissions.sql:143:CREATE TRIGGER trg_audit_role_functions
api-ventago/migrations/2026-08-21-audit-triggers-price-name-permissions.sql:144:  AFTER INSERT OR UPDATE OR DELETE ON role_functions
api-ventago/migrations/2026-08-21-audit-triggers-price-name-permissions.sql:147:-- store_id 가 없는 테이블 → 부모(role_functions)에서 찾는다.
api-ventago/migrations/2026-08-21-audit-triggers-price-name-permissions.sql:148:-- ★ 부모의 store_id 자체가 NULL 일 수 있다(실측: role_functions 8,890행 중 24행).
api-ventago/migrations/2026-08-21-audit-triggers-price-name-permissions.sql:150:DROP TRIGGER IF EXISTS trg_audit_role_function_actions ON role_function_actions;
api-ventago/migrations/2026-08-21-audit-triggers-price-name-permissions.sql:151:CREATE TRIGGER trg_audit_role_function_actions
api-ventago/migrations/2026-08-21-audit-triggers-price-name-permissions.sql:152:  AFTER INSERT OR UPDATE OR DELETE ON role_function_actions
api-ventago/migrations/2026-08-21-audit-triggers-price-name-permissions.sql:154:    audit_row_change('role_function_action', 'role_functions', 'role_function_id');
api-ventago/migrations/33.1-cleanup-orphan-role-functions.sql:1:-- Phase 33.1 cleanup: orphan role_functions 정리
api-ventago/migrations/33.1-cleanup-orphan-role-functions.sql:10:--   role_function_actions 가 0건인 role_functions row.
api-ventago/migrations/33.1-cleanup-orphan-role-functions.sql:26:\echo '=== 1) Orphan role_functions 목록 ==='
api-ventago/migrations/33.1-cleanup-orphan-role-functions.sql:34:FROM role_functions rf
api-ventago/migrations/33.1-cleanup-orphan-role-functions.sql:38:  SELECT DISTINCT role_function_id FROM role_function_actions
api-ventago/migrations/33.1-cleanup-orphan-role-functions.sql:47:FROM role_functions rf
api-ventago/migrations/33.1-cleanup-orphan-role-functions.sql:49:  SELECT DISTINCT role_function_id FROM role_function_actions
api-ventago/migrations/33.1-cleanup-orphan-role-functions.sql:54:DELETE FROM role_functions
api-ventago/migrations/33.1-cleanup-orphan-role-functions.sql:56:  SELECT DISTINCT role_function_id FROM role_function_actions
api-ventago/migrations/33.1-cleanup-orphan-role-functions.sql:68:FROM role_functions
api-ventago/migrations/33.1-cleanup-orphan-role-functions.sql:70:  SELECT DISTINCT role_function_id FROM role_function_actions
api-ventago/migrations/perf-role-functions-unique-index.sql:1:-- Perf: 신규 매장 등록 시 role_functions 시딩을 findOrCreate(루프) → bulkCreate(ON CONFLICT DO NOTHING)
api-ventago/migrations/perf-role-functions-unique-index.sql:9:-- role_function_actions(role_function_id, action) 은 이미 UNIQUE(role_function_actions_rf_action_unique) 보유.
api-ventago/migrations/perf-role-functions-unique-index.sql:13:--   SELECT count(*) FROM (SELECT role_id, function_id, store_id FROM role_functions
api-ventago/migrations/perf-role-functions-unique-index.sql:16:CREATE UNIQUE INDEX IF NOT EXISTS role_functions_role_fn_store_unique
api-ventago/migrations/perf-role-functions-unique-index.sql:17:  ON role_functions (role_id, function_id, store_id);
api-ventago/src/app/store/store-restore-identity.spec.ts:304:  //   `role_functions.store_id` 만 11,790행이고, 그대로 복사하면 복제 매장의
api-ventago/src/app/store/store-restore-contract.spec.ts:58:      tables: { role_function_actions: [{ id: 1 }] },
api-ventago/src/app/store/store-restore-contract.spec.ts:130:      tables: { role_function_actions: [{ id: 1 }], user_roles: [] },
api-ventago/src/app/store/store-restore-contract.spec.ts:133:    // user_roles 는 비어 있으므로 빠지고, role_function_actions 만 잡혀야 한다.
api-ventago/src/app/store/store-restore-contract.spec.ts:134:    expect(unsupportedContentKeys(b)).toEqual(['role_function_actions']);
api-ventago/src/app/store/store-backup-coverage.spec.ts:5://   store_clients(고객 선수금) · role_functions(권한) · credit_ledger(외상 원장) ·
api-ventago/migrations/phase37-beta-mobile-access-data.sql:3:-- 매트릭스 노출/권한 체크에는 role_functions + role_function_actions(action) 가 모두 필요.
api-ventago/migrations/phase37-beta-mobile-access-data.sql:22:-- (1a) role_functions — vendedor(store 6) 에 mobile.access function 부여
api-ventago/migrations/phase37-beta-mobile-access-data.sql:23:INSERT INTO role_functions (role_id, function_id, store_id, created_at, updated_at)
api-ventago/migrations/phase37-beta-mobile-access-data.sql:30:    SELECT 1 FROM role_functions rf
api-ventago/migrations/phase37-beta-mobile-access-data.sql:34:-- (1b) role_function_actions — action='read' (모바일 접근 허용 표식)
api-ventago/migrations/phase37-beta-mobile-access-data.sql:35:INSERT INTO role_function_actions (role_function_id, action, created_at, updated_at)
api-ventago/migrations/phase37-beta-mobile-access-data.sql:37:FROM role_functions rf
api-ventago/migrations/phase37-beta-mobile-access-data.sql:43:    SELECT 1 FROM role_function_actions rfa
api-ventago/migrations/phase37-beta-mobile-access-data.sql:51:--   FROM role_functions rf
api-ventago/migrations/phase37-beta-mobile-access-data.sql:54:--   JOIN role_function_actions rfa ON rfa.role_function_id = rf.id
api-ventago/migrations/2026-07-28-reseed-role-permissions.sql:18:DROP TABLE IF EXISTS role_functions_bak_20260728;
api-ventago/migrations/2026-07-28-reseed-role-permissions.sql:19:DROP TABLE IF EXISTS role_function_actions_bak_20260728;
api-ventago/migrations/2026-07-28-reseed-role-permissions.sql:20:CREATE TABLE role_functions_bak_20260728 AS SELECT * FROM role_functions;
api-ventago/migrations/2026-07-28-reseed-role-permissions.sql:21:CREATE TABLE role_function_actions_bak_20260728 AS SELECT * FROM role_function_actions;
api-ventago/migrations/2026-07-28-reseed-role-permissions.sql:37:DELETE FROM role_function_actions
api-ventago/migrations/2026-07-28-reseed-role-permissions.sql:38: WHERE role_function_id IN (SELECT id FROM role_functions
api-ventago/migrations/2026-07-28-reseed-role-permissions.sql:40:DELETE FROM role_functions
api-ventago/migrations/2026-07-28-reseed-role-permissions.sql:43:-- 5) 재부여 — role_functions
api-ventago/migrations/2026-07-28-reseed-role-permissions.sql:44:INSERT INTO role_functions(role_id, function_id, store_id, created_at, updated_at)
api-ventago/migrations/2026-07-28-reseed-role-permissions.sql:50:INSERT INTO role_function_actions(role_function_id, action, created_at, updated_at)
api-ventago/migrations/2026-07-28-reseed-role-permissions.sql:52:FROM role_functions rf
api-ventago/migrations/2026-07-28-reseed-role-permissions.sql:62:LEFT JOIN role_functions rf ON rf.role_id = r.id
api-ventago/migrations/2026-07-28-reseed-role-permissions.sql:63:LEFT JOIN role_function_actions rfa ON rfa.role_function_id = rf.id
api-ventago/migrations/2026-07-28-reseed-role-permissions.sql:71:--   DELETE FROM role_function_actions;
api-ventago/migrations/2026-07-28-reseed-role-permissions.sql:72:--   DELETE FROM role_functions;
api-ventago/migrations/2026-07-28-reseed-role-permissions.sql:73:--   INSERT INTO role_functions SELECT * FROM role_functions_bak_20260728;
api-ventago/migrations/2026-07-28-reseed-role-permissions.sql:74:--   INSERT INTO role_function_actions SELECT * FROM role_function_actions_bak_20260728;
api-ventago/src/app/store/store-backup-scopes.ts:46:  role_function_actions: `
api-ventago/src/app/store/store-backup-scopes.ts:47:    SELECT t.* FROM role_function_actions t
api-ventago/src/app/store/store-backup-scopes.ts:48:      JOIN role_functions rf ON t.role_function_id = rf.id
api-ventago/src/app/store/storeTemplate.service.ts:638:   * Phase 29 — role_functions 보수적 시드
api-ventago/src/app/store/storeTemplate.service.ts:647:   * 처리합니다. role_functions 단위에서는 "접근 가능 / 불가" 만 결정.
api-ventago/src/app/store/storeTemplate.service.ts:684:    // 멱등성: role_functions(role_id,function_id,store_id) UNIQUE(마이그레이션 perf-role-functions-unique-index)
api-ventago/src/app/store/storeTemplate.service.ts:685:    //         + role_function_actions(role_function_id,action) 기존 UNIQUE 로 보장.
api-ventago/src/app/store/storeTemplate.service.ts:688:    // 1) role_functions 일괄 생성 (ignoreDuplicates → ON CONFLICT DO NOTHING)
api-ventago/src/app/store/storeTemplate.service.ts:701:    // 2) 보장된 role_functions 재조회 — 액션 시드용 id 확보 (신규+기존 모두)
api-ventago/src/app/store/storeTemplate.service.ts:711:    // 3) role_function_actions 일괄 생성 (full=CRUD, 그 외=read-only; 기존 UNIQUE 로 멱등)
api-ventago/src/app/store/storeTemplate.service.ts:729:        `role_functions=${rfRows.length} actions=${actionRows.length} ` +
api-ventago/src/app/store/store-restore-triggers.spec.ts:176:      'role_function_actions',
api-ventago/src/app/store/store-restore-triggers.spec.ts:177:      'role_functions',
api-ventago/src/app/store/store-restore-manifest.ts:209:  'role_functions.function_id': {
api-ventago/src/app/store/store-restore-manifest.ts:212:    why: '권한 기능 카탈로그. 매장별 부여는 role_functions 행 자체가 갖는다.',
api-ventago/src/app/store/store-restore-manifest.ts:217:    why: 'role_functions.function_id 와 같음.',
api-ventago/src/app/store/store.service.ts:878:    //   role_function_actions 40,557행 · user_roles · 금전함 이력 등. 즉 지금
api-ventago/src/app/store/store.service.ts:1150:        `DELETE FROM role_function_actions WHERE role_function_id IN (SELECT id FROM role_functions WHERE role_id IN (SELECT id FROM roles WHERE store_id = :storeId))`,
api-ventago/src/app/store/store.service.ts:1153:        `DELETE FROM role_functions WHERE role_id IN (SELECT id FROM roles WHERE store_id = :storeId)`,
api-ventago/src/app/store/store.service.ts:1580:        //   백업에도 제외 선언에도 없이 빠져 있었다(role_function_actions 40,557행 등).
api-ventago/src/app/store/store-restore-triggers.ts:19://     roles 10 + role_functions 1,109 + role_function_actions 4,415 +
api-ventago/src/app/store/store-restore-triggers.ts:154:      '가짜 감사 로그**를 만든다(role_function_actions 4,415 + role_functions 1,109 + …). ' +
api-ventago/src/app/store/store-purge-guard.spec.ts:69:    setPending(['role_function_actions', 'user_roles']);
api-ventago/src/app/store/store-purge-guard.spec.ts:80:    setPending(['role_function_actions', 'user_roles', 'movements']);
api-ventago/src/app/store/store-purge-guard.spec.ts:93:    setPending(['role_function_actions', 'user_roles']);
api-ventago/src/app/store/store-purge-guard.spec.ts:108:      'role_function_actions',
api-ventago/src/app/store/store-purge-guard.spec.ts:114:    setPending(['role_function_actions', 'user_roles']);
api-ventago/migrations/41-02-support-view-permission.sql:6:--       → role_functions 부여 → PermissionGuard 1-query 검사).
api-ventago/migrations/phase35-stock-movement-permission.sql:88:  --    role_functions(role_id, function_id, store_id, branch_id) 매핑 —
api-ventago/migrations/phase35-stock-movement-permission.sql:93:  INSERT INTO role_functions (role_id, function_id, store_id, branch_id, created_at, updated_at)
api-ventago/migrations/phase35-stock-movement-permission.sql:98:      SELECT 1 FROM role_functions rf
api-ventago/migrations/phase35-stock-movement-permission.sql:106:  RAISE NOTICE 'Phase 35: stock.movement role_functions 신규 부여 = % 행 (재실행 시 0)', role_grant_count;
api-ventago/migrations/phase35-stock-movement-permission.sql:162:-- JOIN role_functions rf ON rf.function_id = f.id
api-ventago/migrations/2026-07-28-functions-slug-uniqueness.sql:42:INSERT INTO role_functions(role_id, function_id, store_id, created_at, updated_at)
api-ventago/migrations/2026-07-28-functions-slug-uniqueness.sql:44:FROM role_functions rf
api-ventago/migrations/2026-07-28-functions-slug-uniqueness.sql:52:  SELECT 1 FROM role_functions x
api-ventago/migrations/2026-07-28-functions-slug-uniqueness.sql:56:DELETE FROM role_function_actions
api-ventago/migrations/2026-07-28-functions-slug-uniqueness.sql:58:   SELECT id FROM role_functions WHERE function_id IN (SELECT id FROM dup_kill));
api-ventago/migrations/2026-07-28-functions-slug-uniqueness.sql:62:DELETE FROM role_functions WHERE function_id IN (SELECT id FROM dup_kill);
api-ventago/migrations/2026-07-28-functions-slug-uniqueness.sql:66:-- 남은 행에 액션 보강 (이관으로 새로 생긴 role_functions)
api-ventago/migrations/2026-07-28-functions-slug-uniqueness.sql:67:INSERT INTO role_function_actions(role_function_id, action, created_at, updated_at)
api-ventago/migrations/2026-07-28-functions-slug-uniqueness.sql:69:FROM role_functions rf
api-ventago/migrations/2026-07-28-functions-slug-uniqueness.sql:72:  SELECT 1 FROM role_function_actions rfa
api-ventago/migrations/2026-07-28-functions-slug-uniqueness.sql:138:--   ※ 단 A 단계에서 삭제된 role_functions 는 복구되지 않는다.
api-ventago/migrations/2026-07-28-functions-slug-uniqueness.sql:139:--     필요하면 role_functions_bak_slug_20260728 (reseed 마이그레이션 백업) 참조.
api-ventago/migrations/phase30-role-functions-dedupe.sql:2:-- Phase 30 #1 — role_functions / role_function_actions 중복 정리
api-ventago/migrations/phase30-role-functions-dedupe.sql:6:--       (또는 발생할 수 있는) role_functions 중복 row 정리
api-ventago/migrations/phase30-role-functions-dedupe.sql:15:--   3) role_function_actions 도 cascade 정리
api-ventago/migrations/phase30-role-functions-dedupe.sql:26:\echo '=== role_functions 중복 분석 (DRY RUN) ==='
api-ventago/migrations/phase30-role-functions-dedupe.sql:30:  FROM role_functions
api-ventago/migrations/phase30-role-functions-dedupe.sql:45:  FROM role_functions
api-ventago/migrations/phase30-role-functions-dedupe.sql:60:-- -- 1) 중복 role_function_actions 정리 (cascade로 같이 삭제될 row 미리)
api-ventago/migrations/phase30-role-functions-dedupe.sql:61:-- DELETE FROM role_function_actions
api-ventago/migrations/phase30-role-functions-dedupe.sql:63:--   SELECT id FROM role_functions rf
api-ventago/migrations/phase30-role-functions-dedupe.sql:65:--     SELECT min(id) FROM role_functions
api-ventago/migrations/phase30-role-functions-dedupe.sql:70:-- -- 2) 중복 role_functions 정리 (각 그룹의 최초 row 만 보존)
api-ventago/migrations/phase30-role-functions-dedupe.sql:71:-- DELETE FROM role_functions
api-ventago/migrations/phase30-role-functions-dedupe.sql:73:--   SELECT min(id) FROM role_functions
api-ventago/migrations/phase30-role-functions-dedupe.sql:84:\echo '=== cleanup 후 매장별 role_functions row 수 ==='
api-ventago/migrations/phase30-role-functions-dedupe.sql:92:    SELECT 1 FROM role_function_actions rfa WHERE rfa.role_function_id = rf.id
api-ventago/migrations/phase30-role-functions-dedupe.sql:96:LEFT JOIN role_functions rf ON rf.role_id = r.id AND rf.store_id = s.id
api-ventago/migrations/phase31-perf-add-missing-indexes.sql:10:--      2) role_functions: (role_id, store_id) 권한 체크 — 모든 인증 API 요청마다 실행
api-ventago/migrations/phase31-perf-add-missing-indexes.sql:18:--   - 모든 API 권한 체크의 role_functions seq_scan 제거
api-ventago/migrations/phase31-perf-add-missing-indexes.sql:30:-- 예상 실행시간: < 5초 (각 테이블 row 수 작음 — prices 255, role_functions 1478, cash_registers 83)
api-ventago/migrations/phase31-perf-add-missing-indexes.sql:34:--   DROP INDEX CONCURRENTLY IF EXISTS idx_role_functions_role_store;
api-ventago/migrations/phase31-perf-add-missing-indexes.sql:47:-- 2) role_functions : (role_id, store_id) 복합 인덱스
api-ventago/migrations/phase31-perf-add-missing-indexes.sql:49:CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_role_functions_role_store
api-ventago/migrations/phase31-perf-add-missing-indexes.sql:50:  ON role_functions (role_id, store_id);
api-ventago/migrations/phase31-perf-add-missing-indexes.sql:59:--   WHERE schemaname='public' AND tablename IN ('prices','role_functions','cash_registers')
api-ventago/migrations/phase31-perf-add-missing-indexes.sql:67:--     role_functions | idx_role_functions_role_store
api-ventago/migrations/phase31-perf-add-missing-indexes.sql:68:--     role_functions | role_functions_pkey
api-ventago/migrations/phase31-perf-analyze-core-tables.sql:28:ANALYZE role_functions;
api-ventago/migrations/phase31-perf-analyze-core-tables.sql:40:--   WHERE relname IN ('stores','sales','users','cash_registers','role_functions','prices',
api-ventago/migrations/phase30-existing-stores-roles-backfill.sql:11:--   3) role_functions / role_function_actions 도 신규 role 에 conservative seed
api-ventago/migrations/phase30-existing-stores-roles-backfill.sql:47:-- 2. 신규 role 에 role_functions 백필 — conservative seed
api-ventago/migrations/phase30-existing-stores-roles-backfill.sql:53:INSERT INTO role_functions (role_id, function_id, store_id, created_at, updated_at)
api-ventago/migrations/phase30-existing-stores-roles-backfill.sql:61:    SELECT 1 FROM role_functions rf
api-ventago/migrations/phase30-existing-stores-roles-backfill.sql:66:INSERT INTO role_functions (role_id, function_id, store_id, created_at, updated_at)
api-ventago/migrations/phase30-existing-stores-roles-backfill.sql:74:    SELECT 1 FROM role_functions rf
api-ventago/migrations/phase30-existing-stores-roles-backfill.sql:79:-- 3. role_function_actions 백필
api-ventago/migrations/phase30-existing-stores-roles-backfill.sql:83:INSERT INTO role_function_actions (role_function_id, action, created_at, updated_at)
api-ventago/migrations/phase30-existing-stores-roles-backfill.sql:86:FROM role_functions rf
api-ventago/migrations/phase30-existing-stores-roles-backfill.sql:94:    SELECT 1 FROM role_function_actions rfa
api-ventago/migrations/phase30-existing-stores-roles-backfill.sql:99:INSERT INTO role_function_actions (role_function_id, action, created_at, updated_at)
api-ventago/migrations/phase30-existing-stores-roles-backfill.sql:102:FROM role_functions rf
api-ventago/migrations/phase30-existing-stores-roles-backfill.sql:110:    SELECT 1 FROM role_function_actions rfa
api-ventago/migrations/phase30-existing-stores-roles-backfill.sql:115:INSERT INTO role_function_actions (role_function_id, action, created_at, updated_at)

hook: PostToolUse
hook: PostToolUse
hook: PostToolUse Failed
hook: PostToolUse Completed
codex
[HIGH] [role-function.service.ts:174](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/role/role-function/role-function.service.ts:174) — 동시 저장 두 건이 모두 검사를 통과한 뒤 서로의 권한을 추가로 회수할 수 있음

  문제: `existingRFs` 조회와 `staleIds` 검증은 트랜잭션 안에 있지만, 같은 역할에 대한 쓰기를 직렬화하는 잠금은 없다. PostgreSQL 기본 `READ COMMITTED`에서는 두 트랜잭션이 같은 초기 상태를 읽고 각각 `expectedRemovals`와 일치할 수 있다.

  예를 들어 최초 권한이 `{A,B,C}`일 때:

  - 요청 1: `{A,C}`, `expectedRemovals=1`
  - 요청 2: `{A,B}`, `expectedRemovals=1`

  두 요청이 동시에 기존 상태를 읽으면 각각 1건으로 검증을 통과하고 B와 C를 따로 삭제한다. 최종 상태는 `{A}`이며, 어느 요청도 선언하지 않은 총 2건의 회수가 발생하지만 409는 없다.

  근거:

  ```ts
  const existingRFs = await this.roleFunctionModel.findAll({
    where: { roleId, storeId },
    transaction,
  });
  // ...
  if (staleIds.length !== expectedRemovals) {
    throw new ConflictException(...);
  }
  ```

  수정: 소유권 확인과 기준 상태 조회를 같은 트랜잭션으로 옮기고, 해당 `roles` 행을 `FOR UPDATE`로 잠근 뒤 계산해야 한다. 동일 역할을 변경하는 `updateFunctionsForRole()` 등 다른 쓰기 경로도 같은 잠금 규약을 사용해야 실제로 직렬화된다. 동시에 두 요청을 실행해 하나만 성공하고 다른 하나는 409가 되는 통합 테스트가 필요하다.

[MEDIUM] [role-function.service.ts:303](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/role/role-function/role-function.service.ts:303) — 액션 목록의 부분 로드는 guard를 전혀 발동시키지 않고 액션을 삭제함

  문제: 현재 guard가 세는 단위는 “payload에서 완전히 빠진 기능”뿐이다. 기능 자체는 포함됐지만 그 기능의 `actions`가 부분 로드된 경우, `staleIds.length`는 0이라 `expectedRemovals: 0` 검사를 통과하고 누락된 액션은 삭제된다.

  근거:

  ```ts
  const staleIds = existingRFs
    .filter((rf) => !dataFnIds.has(rf.functionId))
    .map((rf) => rf.id);

  const removeIds = [...currentPairs.entries()]
    .filter(([key]) => !wantedPairs.has(key))
    .map(([, id]) => id);
  ```

  현재 `RolePermissionsDrawer`는 활성 기능마다 항상 CRUD 4개를 보내므로 이 화면에서는 재현되지 않는다. 그러나 엔드포인트 계약은 여전히 액션별 최종 상태 교체이며, 향후 Phase 93 화면이 서버에서 받은 액션 목록을 보존·편집한다면 동일한 부분 로드 사고가 액션 수준에서 발생한다. 코드의 “부분 로드로는 발생하지 않는다”는 주석도 일반적으로 성립하지 않는다.

  수정: 새 화면이 계속 무조건 4개 액션을 생성한다는 계약을 명시적으로 유지하거나, 액션 편집을 지원한다면 `expectedActionRemovals` 또는 서버 상태 버전/ETag까지 비교해야 한다.

[MEDIUM] [role-function.service.ts:203](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/role/role-function/role-function.service.ts:203) — 명시적인 `null`이 검증을 우회하며, HTTP에서 `NaN`도 `null`로 변환될 수 있음

  문제: expand 요구사항은 필드가 “오지 않은” 구형 요청의 호환성이다. 하지만 현재는 필드가 명시적으로 `null`이어도 미전송으로 처리한다. 새 클라이언트의 계산 오류가 `null`을 만들면 삭제 방어가 조용히 해제된다. 또한 JavaScript의 `JSON.stringify({ expectedRemovals: NaN })` 결과는 `null`이므로, 서비스 단위 테스트의 `NaN` 400 검증은 실제 HTTP 경로를 대표하지 않는다.

  근거:

  ```ts
  if (expectedRemovals !== undefined && expectedRemovals !== null) {
    if (!Number.isInteger(expectedRemovals) || expectedRemovals < 0) {
      throw new BadRequestException(...);
    }
  }
  ```

  수정: 하위 호환은 속성 부재/`undefined`에만 적용하고, 명시적 `null`은 400으로 거절해야 한다. DTO와 런타임 검증을 추가하고 실제 HTTP 요청으로 `null`, 문자열, 소수 테스트를 수행하는 것이 안전하다.

그 외 질문하신 범위에서는 글로벌 역할은 기존 소유권 검사에서 거절되고, 화면에 표시되지 않는 기능도 GET 결과의 `originalIds`에 남아 payload로 다시 전송되므로 그 자체로 인한 거짓 409은 확인되지 않았습니다. 다른 관리자가 먼저 상태를 변경해 발생하는 409는 오래된 기준 상태의 저장을 막는 정상적인 낙관적 충돌입니다. 삭제 전에 트랜잭션 내부에서 검증하는 현재 순서 자체도 올바릅니다.
hook: Stop
hook: Stop
hook: Stop Failed
hook: Stop Completed
tokens used
50,148
[HIGH] [role-function.service.ts:174](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/role/role-function/role-function.service.ts:174) — 동시 저장 두 건이 모두 검사를 통과한 뒤 서로의 권한을 추가로 회수할 수 있음

  문제: `existingRFs` 조회와 `staleIds` 검증은 트랜잭션 안에 있지만, 같은 역할에 대한 쓰기를 직렬화하는 잠금은 없다. PostgreSQL 기본 `READ COMMITTED`에서는 두 트랜잭션이 같은 초기 상태를 읽고 각각 `expectedRemovals`와 일치할 수 있다.

  예를 들어 최초 권한이 `{A,B,C}`일 때:

  - 요청 1: `{A,C}`, `expectedRemovals=1`
  - 요청 2: `{A,B}`, `expectedRemovals=1`

  두 요청이 동시에 기존 상태를 읽으면 각각 1건으로 검증을 통과하고 B와 C를 따로 삭제한다. 최종 상태는 `{A}`이며, 어느 요청도 선언하지 않은 총 2건의 회수가 발생하지만 409는 없다.

  근거:

  ```ts
  const existingRFs = await this.roleFunctionModel.findAll({
    where: { roleId, storeId },
    transaction,
  });
  // ...
  if (staleIds.length !== expectedRemovals) {
    throw new ConflictException(...);
  }
  ```

  수정: 소유권 확인과 기준 상태 조회를 같은 트랜잭션으로 옮기고, 해당 `roles` 행을 `FOR UPDATE`로 잠근 뒤 계산해야 한다. 동일 역할을 변경하는 `updateFunctionsForRole()` 등 다른 쓰기 경로도 같은 잠금 규약을 사용해야 실제로 직렬화된다. 동시에 두 요청을 실행해 하나만 성공하고 다른 하나는 409가 되는 통합 테스트가 필요하다.

[MEDIUM] [role-function.service.ts:303](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/role/role-function/role-function.service.ts:303) — 액션 목록의 부분 로드는 guard를 전혀 발동시키지 않고 액션을 삭제함

  문제: 현재 guard가 세는 단위는 “payload에서 완전히 빠진 기능”뿐이다. 기능 자체는 포함됐지만 그 기능의 `actions`가 부분 로드된 경우, `staleIds.length`는 0이라 `expectedRemovals: 0` 검사를 통과하고 누락된 액션은 삭제된다.

  근거:

  ```ts
  const staleIds = existingRFs
    .filter((rf) => !dataFnIds.has(rf.functionId))
    .map((rf) => rf.id);

  const removeIds = [...currentPairs.entries()]
    .filter(([key]) => !wantedPairs.has(key))
    .map(([, id]) => id);
  ```

  현재 `RolePermissionsDrawer`는 활성 기능마다 항상 CRUD 4개를 보내므로 이 화면에서는 재현되지 않는다. 그러나 엔드포인트 계약은 여전히 액션별 최종 상태 교체이며, 향후 Phase 93 화면이 서버에서 받은 액션 목록을 보존·편집한다면 동일한 부분 로드 사고가 액션 수준에서 발생한다. 코드의 “부분 로드로는 발생하지 않는다”는 주석도 일반적으로 성립하지 않는다.

  수정: 새 화면이 계속 무조건 4개 액션을 생성한다는 계약을 명시적으로 유지하거나, 액션 편집을 지원한다면 `expectedActionRemovals` 또는 서버 상태 버전/ETag까지 비교해야 한다.

[MEDIUM] [role-function.service.ts:203](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/role/role-function/role-function.service.ts:203) — 명시적인 `null`이 검증을 우회하며, HTTP에서 `NaN`도 `null`로 변환될 수 있음

  문제: expand 요구사항은 필드가 “오지 않은” 구형 요청의 호환성이다. 하지만 현재는 필드가 명시적으로 `null`이어도 미전송으로 처리한다. 새 클라이언트의 계산 오류가 `null`을 만들면 삭제 방어가 조용히 해제된다. 또한 JavaScript의 `JSON.stringify({ expectedRemovals: NaN })` 결과는 `null`이므로, 서비스 단위 테스트의 `NaN` 400 검증은 실제 HTTP 경로를 대표하지 않는다.

  근거:

  ```ts
  if (expectedRemovals !== undefined && expectedRemovals !== null) {
    if (!Number.isInteger(expectedRemovals) || expectedRemovals < 0) {
      throw new BadRequestException(...);
    }
  }
  ```

  수정: 하위 호환은 속성 부재/`undefined`에만 적용하고, 명시적 `null`은 400으로 거절해야 한다. DTO와 런타임 검증을 추가하고 실제 HTTP 요청으로 `null`, 문자열, 소수 테스트를 수행하는 것이 안전하다.

그 외 질문하신 범위에서는 글로벌 역할은 기존 소유권 검사에서 거절되고, 화면에 표시되지 않는 기능도 GET 결과의 `originalIds`에 남아 payload로 다시 전송되므로 그 자체로 인한 거짓 409은 확인되지 않았습니다. 다른 관리자가 먼저 상태를 변경해 발생하는 409는 오래된 기준 상태의 저장을 막는 정상적인 낙관적 충돌입니다. 삭제 전에 트랜잭션 내부에서 검증하는 현재 순서 자체도 올바릅니다.
