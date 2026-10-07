Reading additional input from stdin...
2026-10-07T18:19:59.401283Z ERROR codex_models_manager::cache: failed to load models cache: missing field `base_instructions` at line 140 column 5
OpenAI Codex v0.146.0
--------
workdir: /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
model: gpt-5.6-sol
provider: openai
approval: never
sandbox: workspace-write [workdir, /tmp, $TMPDIR]
reasoning effort: none
reasoning summaries: none
session id: 01a11797-ffb5-7ba1-aff6-c0897a016e4a
--------
user
Revisá este diff de zebra-agent (ZPL, impresora 203dpi, etiqueta 50x25mm = 400 dots). El ZPL de prueba en modos de una cara usaba ^BY3 con Code128 '1234567890' (145 módulos = 435 dots) y se cortaba. Ahora se ajusta con effectiveModuleWidth (avail = width - x - 10, floor(avail/modules), min 1, max cap 3). Poliamida vertical (width 200) queda ^BY1. Buscá errores concretos, no estilo. Diff:
diff --git a/zebra-agent/src/zpl-formatter.js b/zebra-agent/src/zpl-formatter.js
index 8cfea42..17ea2b7 100644
--- a/zebra-agent/src/zpl-formatter.js
+++ b/zebra-agent/src/zpl-formatter.js
@@ -1077,14 +1077,14 @@ function zplADibujo(zpl) {
 function formatTestLabel(mode, { darkness = null, speed = null } = {}) {
   const doble = !!(mode && mode.duplicate && mode.halfWidth);
   const ancho = doble ? mode.width : 400;
-  // ★ [codex 041] en doble banda el código va achicado a su mitad, igual que `renderCopy`
-  //   (con ^BY3 mide 435 dots y la izquierda se metía en la etiqueta derecha)
-  const by = doble
-    ? effectiveModuleWidth({ x: 10, moduleWidth: 3 }, '1234567890', 'CODE128', 'N', {
-        width: mode.halfWidth,
-        height: mode.height || 200,
-      })
-    : 3;
+  // ★ [codex 041] el código se achica a su etiqueta, igual que `renderCopy`: con ^BY3 mide
+  //   435 dots. En doble banda la izquierda se metía en la derecha; en una cara (400 dots)
+  //   se cortaba el final (2026-10-07 «맞춰줘»). Nunca más ancho que los 400 de antes.
+  const region = doble ? mode.halfWidth : Math.min(400, (mode && mode.width) || 400);
+  const by = effectiveModuleWidth({ x: 10, moduleWidth: 3 }, '1234567890', 'CODE128', 'N', {
+    width: region,
+    height: (mode && mode.height) || 200,
+  });
   const copia = (dx) => [
     `^FO${10 + dx},5^A0N,22,22^FDVENTAGO ZEBRA TEST^FS`,
     `^FO${10 + dx},30^BY${by}^BCN,50,Y,N,N^FD1234567890^FS`,
diff --git a/zebra-agent/test/test-label.test.js b/zebra-agent/test/test-label.test.js
index 6484461..6f3b8e4 100644
--- a/zebra-agent/test/test-label.test.js
+++ b/zebra-agent/test/test-label.test.js
@@ -3,7 +3,7 @@
  * 실행: node test/test-label.test.js
  *
  *  - Modo Duplicado (doble banda): ^PW = ancho del modo y la prueba en las DOS etiquetas
- *  - los demás modos: exactamente el ZPL de antes (50×25, a la izquierda)
+ *  - los demás modos: el ZPL de antes, con el código achicado a su etiqueta
  */
 const assert = require('assert');
 const { formatTestLabel, resolveMode } = require('../src/zpl-formatter');
@@ -62,10 +62,23 @@ ok('doble banda: alto personalizado', formatTestLabel({ ...dup, height: 240 }, {
 const zCustom = formatTestLabel({ ...dup, width: 832, halfWidth: 416 }, {});
 ok('ancho personalizado: ^PW832 y la derecha en x = 426', zCustom.includes('^PW832') && zCustom.includes('^FO426,5'));
 
-// ── los demás modos: igual que antes ──
-for (const key of ['simple-face', 'doble-face', 'poliamida-vertical']) {
-  ok(`${key}: el mismo ZPL de antes`, formatTestLabel(resolveMode(key), {}) === ANTES(null, null));
+// ── los demás modos: igual que antes salvo el código, que ahora entra en la etiqueta ──
+const ANTES_BY2 = ANTES(null, null).replace('^BY3', '^BY2');
+for (const key of ['simple-face', 'doble-face']) {
+  const z = formatTestLabel(resolveMode(key), {});
+  ok(`${key}: el ZPL de antes con ^BY2`, z === ANTES_BY2);
+  const byK = Number(/\^BY(\d+)/.exec(z)[1]);
+  ok(`${key}: el código entra en 400 dots (^BY${byK})`, 10 + code128Modules('1234567890') * byK <= 400);
 }
+// poliamida (200 de ancho): el código se achica a lo que entra, nunca más ancho que antes
+const zPoli = formatTestLabel(resolveMode('poliamida-vertical'), {});
+const byPoli = Number(/\^BY(\d+)/.exec(zPoli)[1]);
+ok(`poliamida: ^BY${byPoli} → entra en 200`, 10 + code128Modules('1234567890') * byPoli <= 200);
+ok('poliamida: resto igual que antes', zPoli.replace(`^BY${byPoli}`, '^BY3') === ANTES(null, null));
+// una cara con ancho personalizado mayor: la prueba sigue en ^PW400, así que el código también
+ok('una cara ancha: el código sigue ajustado a 400', formatTestLabel({ ...resolveMode('simple-face'), width: 832 }, {}) === ANTES_BY2);
+// sin modo (por si acaso): como una cara
+ok('sin modo: como una cara', formatTestLabel(null, {}) === ANTES_BY2);
 
 // densidad y velocidad siguen entrando
 const conAjustes = formatTestLabel(resolveMode('simple-face'), { darkness: 15, speed: 4 });
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
제공된 diff만 보지 않고 `effectiveModuleWidth`, Code128 모듈 계산, 모드 정의, 테스트의 기준 ZPL까지 함께 대조해 실제 출력이 잘못되는 경로만 확인하겠습니다. 파일은 수정하지 않고 검토 결과만 보고하겠습니다.
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse Failed
hook: PreToolUse Completed
hook: PreToolUse Completed
exec
/bin/zsh -lc "sed -n '1,240p' .team/REVIEW-PROTOCOL.md && rg -n \"function effectiveModuleWidth|effectiveModuleWidth|function formatTestLabel|const ANTES|code128Modules|poliamida-vertical|simple-face|doble-face\" zebra-agent/src/zpl-formatter.js zebra-agent/test/test-label.test.js" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 0ms:
# cmux team 협업 프로토콜 — Claude Code(구현) ↔ codex(보안 검토)

역할 경계는 [`AGENTS.md`](../AGENTS.md) 가 정의한다. 이 문서는 **두 에이전트가 어디서 만나는지**만 정한다.

## 원칙

| | Claude Code | codex |
|---|---|---|
| 코드 수정 | **한다** | 하지 않는다 (보고서만) |
| 커밋·push | 한다 | 하지 않는다 |
| 마이그레이션 | 새 파일 작성·적용 | 초안 제안만, 기존 파일 수정 금지 |
| 운영 DB | 조회 허용(CLAUDE.md 규칙) | **접속 금지** |
| 최종 판단 | **한다** — 검토 지적의 수용/반박을 결정 | 하지 않는다 |

**codex 의 지적은 입력이지 명령이 아니다.** Claude 는 각 지적에 대해 수용하거나 근거를 대고 반박한다.
반박도 기록으로 남긴다 — 다음 검토에서 같은 지적이 반복되는 것을 막는다.

## 디렉터리 규약

```
.team/
├── config.json              # 모델 설정 (추적됨)
├── REVIEW-PROTOCOL.md       # 이 문서
├── tasks/NNN-<slug>/
│   └── task.md              # 구현 태스크 정의 (Claude 가 집행)
└── reviews/
    ├── NNN-codex.md         # codex 검토 보고서 (codex 가 생성)
    └── NNN-resolution.md    # 지적별 수용/반박 결정 (Claude 가 생성)
```

`reviews/` 는 추적한다 — 무엇을 왜 수용/반박했는지가 다음 phase 의 근거가 된다.

## 흐름

```
1. Claude   구현 → 커밋 (아직 push 안 함)
2. Claude   scripts/codex-review.sh --task NNN   ← 변경 diff 를 codex 에 넘긴다
3. codex    .team/reviews/NNN-codex.md 생성 (AGENTS.md 보고 형식)
4. Claude   지적별 판단 → .team/reviews/NNN-resolution.md
              - 수용 → 수정 커밋
              - 반박 → 근거 기록 (코드 그대로)
5. Claude   CRITICAL/HIGH 가 모두 해소·반박된 뒤에만 push
```

**게이트:** `CRITICAL` 또는 `HIGH` 가 미해소 상태로 남아 있으면 push 하지 않는다.
`MEDIUM`/`LOW` 는 resolution 에 기록만 하고 넘어갈 수 있다.

## 검토 입력에서 제외하는 것

`scripts/codex-review.sh` 가 diff 를 만들 때 아래를 제외한다. codex 가 값을 보지 못하게 하는 것이 목적이다.

- `.env`, `.env.*` (AGENTS.md 금지 항목)
- `*.pem`, `*.key`, `id_*`
- `package-lock.json`, `node_modules/` (노이즈)

## 실행

```bash
# 태스크 단위 검토 — main 대비 현재 브랜치 diff
scripts/codex-review.sh --task 001

# 워킹트리 검토 — 커밋 전 빠른 점검
scripts/codex-review.sh --working

# 특정 경로만
scripts/codex-review.sh --task 002 --paths api-ventago/src/app/products
```

cmux team 으로 병렬 실행할 때:

```bash
cmux claude-teams     # 구현 측 (기존 .team/tasks 집행)
cmux codex-teams      # 검토 측
```

> **codex 미설치 상태면 `cmux codex-teams` 가 `codex not found in PATH` 로 실패한다.**
> `npm i -g @openai/codex` 후 `codex login` 을 한 번 거쳐야 한다.

## 검토 대상 우선순위 (이 저장소 기준)

AGENTS.md 의 일반 기준 위에, 이 프로젝트에서 실제로 사고가 났던 지점을 얹는다.

1. **쓰기 경로의 트랜잭션 누락** — 여러 모델을 순차 호출하며 `transaction` 인자를 빠뜨리면 그 문장만 별도 커밋돼 부분 저장이 된다 (Phase 64 결함 2·3·4)
2. **`stocks` 원장 규약** — append-only. UPDATE/DELETE 금지, 조회·기록은 `product_branch_id` 기준 (`product_id` 컬럼은 없다)
3. **테넌트 경계** — 사용자가 준 `branchId`/`variantId`/`storeId` 를 소유권 확인 없이 쓰는 경로 (Phase 69 CR-02 유형)
4. **fail-open** — 권한·역할 판정에 실패했을 때 *더 주는* 분기 (Phase 65 W6 6-2 유형)
5. **트랜잭션 안 외부 I/O** — HTTP·프린터·소켓 호출은 커밋 후에 (pool 고갈)
zebra-agent/test/test-label.test.js:21:const ANTES = (d, v) =>
zebra-agent/test/test-label.test.js:52:const { code128Modules } = require('../src/zpl-formatter');
zebra-agent/test/test-label.test.js:55:  `doble banda: el código entra en su mitad (^BY${by} → ${10 + code128Modules('1234567890') * by} ≤ 400)`,
zebra-agent/test/test-label.test.js:56:  10 + code128Modules('1234567890') * by <= dup.halfWidth,
zebra-agent/test/test-label.test.js:66:const ANTES_BY2 = ANTES(null, null).replace('^BY3', '^BY2');
zebra-agent/test/test-label.test.js:67:for (const key of ['simple-face', 'doble-face']) {
zebra-agent/test/test-label.test.js:71:  ok(`${key}: el código entra en 400 dots (^BY${byK})`, 10 + code128Modules('1234567890') * byK <= 400);
zebra-agent/test/test-label.test.js:74:const zPoli = formatTestLabel(resolveMode('poliamida-vertical'), {});
zebra-agent/test/test-label.test.js:76:ok(`poliamida: ^BY${byPoli} → entra en 200`, 10 + code128Modules('1234567890') * byPoli <= 200);
zebra-agent/test/test-label.test.js:79:ok('una cara ancha: el código sigue ajustado a 400', formatTestLabel({ ...resolveMode('simple-face'), width: 832 }, {}) === ANTES_BY2);
zebra-agent/test/test-label.test.js:84:const conAjustes = formatTestLabel(resolveMode('simple-face'), { darkness: 15, speed: 4 });
zebra-agent/src/zpl-formatter.js:4: *   - simple-face:        50x25mm 단면
zebra-agent/src/zpl-formatter.js:5: *   - doble-face:         50x25mm 접이식 양면 배치
zebra-agent/src/zpl-formatter.js:7: *   - poliamida-vertical: 25x50mm 세로 리본 (텍스트/바코드 90° 회전)
zebra-agent/src/zpl-formatter.js:18:  'simple-face': {
zebra-agent/src/zpl-formatter.js:19:    key: 'simple-face',
zebra-agent/src/zpl-formatter.js:37:  'doble-face': {
zebra-agent/src/zpl-formatter.js:38:    key: 'doble-face',
zebra-agent/src/zpl-formatter.js:76:  'poliamida-vertical': {
zebra-agent/src/zpl-formatter.js:77:    key: 'poliamida-vertical',
zebra-agent/src/zpl-formatter.js:97:  '50x25-simple': 'simple-face',
zebra-agent/src/zpl-formatter.js:98:  '50x25-doble': 'doble-face',
zebra-agent/src/zpl-formatter.js:105: * @returns {Object} LABEL_MODES 항목 (fallback: simple-face)
zebra-agent/src/zpl-formatter.js:110:  return LABEL_MODES[normalized] || LABEL_MODES['simple-face'];
zebra-agent/src/zpl-formatter.js:167:function code128Modules(value) {
zebra-agent/src/zpl-formatter.js:222: * 기본 상한 6 을 쓴다 (effectiveModuleWidth 의 `bc.moduleWidth || 3` 과 동일 관례:
zebra-agent/src/zpl-formatter.js:253:function effectiveModuleWidth(bc, value, type, orientation, region) {
zebra-agent/src/zpl-formatter.js:260:  const modules = type === 'EAN13' ? 95 : code128Modules(value);
zebra-agent/src/zpl-formatter.js:285:  const mw = effectiveModuleWidth(bc, value, type, orientation, region);
zebra-agent/src/zpl-formatter.js:286:  const modules = type === 'EAN13' ? 95 : code128Modules(value);
zebra-agent/src/zpl-formatter.js:350:    const mw = effectiveModuleWidth(bc, barcodeValue, barcodeType, orientation, region);
zebra-agent/src/zpl-formatter.js:452:  const m = mode || LABEL_MODES['simple-face'];
zebra-agent/src/zpl-formatter.js:453:  const layout = m.layout || LABEL_MODES['simple-face'].layout;
zebra-agent/src/zpl-formatter.js:1077:function formatTestLabel(mode, { darkness = null, speed = null } = {}) {
zebra-agent/src/zpl-formatter.js:1084:  const by = effectiveModuleWidth({ x: 10, moduleWidth: 3 }, '1234567890', 'CODE128', 'N', {
zebra-agent/src/zpl-formatter.js:1121:  code128Modules,
zebra-agent/src/zpl-formatter.js:1122:  effectiveModuleWidth,

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
/bin/zsh -lc "sed -n '1,125p' zebra-agent/src/zpl-formatter.js; sed -n '145,310p' zebra-agent/src/zpl-formatter.js; sed -n '1040,1128p' zebra-agent/src/zpl-formatter.js; sed -n '1,115p' zebra-agent/test/test-label.test.js; git diff -- zebra-agent/src/zpl-formatter.js zebra-agent/test/test-label.test.js" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 0ms:
/**
 * 상품 데이터 → ZPL II 문자열 변환
 * 4종 출력 모드:
 *   - simple-face:        50x25mm 단면
 *   - doble-face:         50x25mm 접이식 양면 배치
 *   - modo-duplicado:     100x25mm 좌우 복제 (cartulina)
 *   - poliamida-vertical: 25x50mm 세로 리본 (텍스트/바코드 90° 회전)
 *
 * 요소별 위치/크기 커스텀 + 가격 0~3개 (priceCount) 지원.
 *
 * 203dpi 기준: 1mm ≈ 8dot
 *   50mm = 400dot, 25mm = 200dot, 100mm = 800dot
 */

// ── 출력 모드 프리셋 ─────────────────────────────────────────────────────
const LABEL_MODES = {
  // 50x25mm 단면
  'simple-face': {
    key: 'simple-face',
    name: 'Simple Face',
    description: '50 x 25mm — una cara',
    width: 400,
    height: 200,
    duplicate: false,
    orientation: 'N', // N = normal, R = 90° 회전
    layout: {
      priceCount: 1,
      name:    { x: 10, y: 5,   fontSize: 22 },
      barcode: { x: 10, y: 30,  height: 50, moduleWidth: 3 },
      price1:  { x: 10, y: 100, fontSize: 28, bold: true },
      price2:  { x: 10, y: 130, fontSize: 20, bold: false },
      price3:  { x: 10, y: 155, fontSize: 20, bold: false },
    },
  },

  // 50x25mm 양면 (doble face — 같은 크기, 다른 배치)
  'doble-face': {
    key: 'doble-face',
    name: 'Doble Face',
    description: '50 x 25mm — plegable',
    width: 400,
    height: 200,
    duplicate: false,
    orientation: 'N',
    layout: {
      priceCount: 1,
      name:    { x: 10, y: 5,   fontSize: 20 },
      barcode: { x: 120, y: 30, height: 45, moduleWidth: 3 },
      price1:  { x: 10, y: 30,  fontSize: 32, bold: true },
      price2:  { x: 10, y: 70,  fontSize: 18, bold: false },
      price3:  { x: 10, y: 95,  fontSize: 18, bold: false },
    },
  },

  // 100x25mm — 무조건 좌우 복제 (왼편 + 오른편 동일 내용)
  'modo-duplicado': {
    key: 'modo-duplicado',
    name: 'Modo Duplicado',
    description: '100 x 25mm — izq + der',
    width: 800,
    height: 200,
    duplicate: true,
    halfWidth: 400,
    orientation: 'N',
    layout: {
      priceCount: 1,
      name:    { x: 10, y: 5,   fontSize: 20 },
      barcode: { x: 10, y: 30,  height: 45, moduleWidth: 3 },
      price1:  { x: 10, y: 95,  fontSize: 26, bold: true },
      price2:  { x: 10, y: 125, fontSize: 18, bold: false },
      price3:  { x: 10, y: 150, fontSize: 18, bold: false },
    },
  },

  // 25x50mm 폴리아미다 세로 리본 — 모든 요소 90° 회전 출력
  'poliamida-vertical': {
    key: 'poliamida-vertical',
    name: 'Poliamida Vertical',
    description: '25 x 50mm — vertical',
    width: 200,
    height: 400,
    duplicate: false,
    orientation: 'R',
    layout: {
      priceCount: 1,
      name:    { x: 160, y: 10,  fontSize: 20 },
      barcode: { x: 60,  y: 10,  height: 45, moduleWidth: 3 },
      price1:  { x: 20,  y: 10,  fontSize: 24, bold: true },
      price2:  { x: 20,  y: 200, fontSize: 18, bold: false },
      price3:  { x: 20,  y: 300, fontSize: 18, bold: false },
    },
  },
};

// 구버전 프리셋 키 → 신규 모드 키 매핑 (설정 마이그레이션용)
const LEGACY_PRESET_ALIASES = {
  '50x25-simple': 'simple-face',
  '50x25-doble': 'doble-face',
  '100x25-cartulina': 'modo-duplicado',
};

/**
 * 모드 키 정규화 — 구버전 키도 신규 모드로 해석
 * @param {string} key
 * @returns {Object} LABEL_MODES 항목 (fallback: simple-face)
 */
function resolveMode(key) {
  const normalized = LEGACY_PRESET_ALIASES[key] || key;

  return LABEL_MODES[normalized] || LABEL_MODES['simple-face'];
}

// ── 바코드 타입별 ZPL 명령 (orientation 반영) ────────────────────────────
function barcodeZpl(type, x, y, value, h, mw, orientation) {
  const o = orientation === 'R' ? 'R' : 'N';

  switch (type) {
    case 'EAN13':
      return `^FO${x},${y}^BY${mw}^BE${o},${h},Y,N^FD${value}^FS`;
    case 'QR':
      // QR은 회전 개념 없음
      return `^FO${x},${y}^BQN,2,4^FDQA,${value}^FS`;
    case 'CODE128':
    default:
      return `^FO${x},${y}^BY${mw}^BC${o},${h},Y,N,N^FD${value}^FS`;
 * @param {string} text
 * @param {number} fs
 * @returns {number}
 */
function estTextWidth(text, fs) {
  return Math.ceil(String(text).length * fs * 0.55);
}

/**
 * nivel 라벨 폰트 크기 — 가격 폰트의 1/4 수준 (최소 12dot 가독성 보장)
 * @param {number} amountFs
 * @returns {number}
 */
function nivelFontSize(amountFs) {
  return Math.max(12, Math.round(amountFs / 4));
}

/**
 * CODE128 총 모듈 수 추정 — (문자수 + start/checksum) * 11 + stop 13
 * @param {string} value
 * @returns {number}
 */
function code128Modules(value) {
  return (String(value).length + 2) * 11 + 13;
}

// ZPL ^BY 가 받는 모듈 폭 범위 (1~10 dot)
const MAX_MODULE_WIDTH = 10;

// 스캐너가 안정적으로 읽는 최소 모듈 폭 (203dpi 기준 2dot = 0.25mm).
// 이 아래로 축소돼야 들어가는 SKU 는 라벨을 넓히거나 SKU 를 줄여야 한다.
const MIN_SCANNABLE_MODULE_WIDTH = 2;

// ── QR 자동맞춤 (2026-07-15 D-4/D-6/D-7) ──────────────────────────────────
// ZPL ^BQ 가 받는 magnification 범위 상한
const MAX_QR_MODULE = 10;
const QR_MARGIN = 10;   // 라벨 여백 (dot)
const QR_GAP = 12;      // QR 과 텍스트 사이 간격 (dot)
const QR_WIDTH_CAP = 0.55; // QR 이 쓸 수 있는 최대 폭 비율 → 텍스트에 45% 보장

// QR byte 용량표 (ECC M, byte mode) — [모듈수, 최대 byte]
// ECC Q(25% 복원) → M(15%) 으로 낮춰 같은 URL 을 더 낮은 version 에 담는다.
// 50byte 딥링크: Q 면 v5(37모듈), M 이면 v4(33모듈) → 같은 높이에서 약 25% 확대.
const QR_ECC_M_CAPACITY = [
  [21, 14], [25, 26], [29, 42], [33, 62], [37, 84],
  [41, 106], [45, 122], [49, 152], [53, 180], [57, 213],
];

/**
 * 문자열의 UTF-8 byte 길이.
 * Buffer 가 아니라 TextEncoder 를 쓴다 — renderer(브라우저 컨텍스트)의 프리뷰가
 * 같은 계산을 해야 실물과 어긋나지 않기 때문.
 * @param {string} s
 * @returns {number}
 */
function utf8Len(s) {
  return new TextEncoder().encode(String(s == null ? '' : s)).length;
}

/**
 * byte 길이 → QR 한 변의 모듈 수 (ECC M).
 * @param {number} byteLen
 * @returns {number} 21|25|29|33|37|41|45|49|53|57 (용량 초과 시 최대 57)
 */
function qrModuleCount(byteLen) {
  for (const [modules, cap] of QR_ECC_M_CAPACITY) {
    if (byteLen <= cap) return modules;
  }

  return QR_ECC_M_CAPACITY[QR_ECC_M_CAPACITY.length - 1][0];
}

/**
 * QR magnification 자동 조절 — 사용자 상한(cap) / 라벨 높이 / 폭 55% 캡의 최솟값.
 * 바코드 moduleWidth 와 같은 패턴: 사용자 설정은 "상한"이고 실물이 안 들어가면 줄인다.
 * 폭 캡 덕에 QR 이 이름/가격 영역을 구조적으로 침범할 수 없다.
 * cap 은 `cap || 6` 로 평가한다 — undefined 뿐 아니라 0 도 "미지정"으로 취급해
 * 기본 상한 6 을 쓴다 (effectiveModuleWidth 의 `bc.moduleWidth || 3` 과 동일 관례:
 * falsy 값 = "설정 안 함", 0 을 "상한 0(=사실상 출력 불가)"으로 해석하지 않는다).
 * 진짜로 0 을 상한으로 강제하고 싶다면 이 함수로는 불가능 — 의도된 제약이다.
 * @param {string} valor - QR 에 담을 문자열 (딥링크 또는 SKU)
 * @param {number} cap - 사용자 상한 (#qr-module). falsy(0 포함/undefined) 면 기본 6.
 * @param {number} heightDots - 라벨 높이 (dot)
 * @param {number} regionDots - 상품 1장 폭 (dot)
 * @returns {number} 적용할 magnification (1 이상)
 */
function effectiveQrModule(valor, cap, heightDots, regionDots) {
  const modules = qrModuleCount(utf8Len(valor));
  const capped = Math.max(1, Math.min(MAX_QR_MODULE, cap || 6));
  const byHeight = Math.floor((heightDots - 2 * QR_MARGIN) / modules);
  const byWidth = Math.floor((regionDots * QR_WIDTH_CAP - QR_MARGIN) / modules);

  return Math.max(1, Math.min(capped, byHeight, byWidth));
}

/**
 * 바코드 모듈 폭 자동 조절 (양방향) — 가용 폭에 맞춰 모듈 폭을 키우거나 줄인다.
 * moduleWidth 는 "원하는 폭 = 상한". SKU 가 짧아 폭이 남으면 상한까지 키우고,
 * 문자 포함/긴 SKU 로 넘치면 1까지 줄인다. SKU 길이는 사용자마다 다르므로
 * 상한은 항상 사용자 설정(#lay-bc-mw)이 결정한다.
 * bc.autoFit === false 면 설정값을 그대로 사용 (자동 조절 없음).
 * @param {Object} bc - barcode 레이아웃 { x, y, moduleWidth, autoFit }
 * @param {string} value - 바코드 값
 * @param {string} type - CODE128 | EAN13 | QR
 * @param {string} orientation - 'N' | 'R'
 * @param {Object} region - { width, height }
 * @returns {number} 적용할 moduleWidth
 */
function effectiveModuleWidth(bc, value, type, orientation, region) {
  // 사용자 설정 = 상한 (autoFit off 면 그대로 사용할 값)
  const cap = Math.max(1, Math.min(MAX_MODULE_WIDTH, bc.moduleWidth || 3));

  if (bc.autoFit === false || type === 'QR') return cap;

  // EAN13 은 고정 95모듈, CODE128 은 길이 비례
  const modules = type === 'EAN13' ? 95 : code128Modules(value);
  if (modules <= 0) return cap;

  // 회전(R) 시 바코드는 리본 길이 방향(+y)으로 자란다
  const margin = 10;
  const avail = orientation === 'R'
    ? region.height - (bc.y || 0) - margin
    : region.width - (bc.x || 0) - margin;

  // 가용 폭에 들어가는 최대 모듈 폭 — 사용자 상한을 넘지 않는다
  const fit = Math.floor(avail / modules);

  return Math.max(1, Math.min(cap, fit));
}

/**
 * 바코드가 라벨에 들어가는지 진단 — UI 경고/프리뷰용 (출력 자체는 막지 않음).
 * @param {Object} bc - barcode 레이아웃
 * @param {string} value - 바코드 값
 * @param {string} type - CODE128 | EAN13 | QR
 * @param {string} orientation - 'N' | 'R'
 * @param {Object} region - { width, height }
 * @returns {Object} { moduleWidth, totalWidth, avail, overflow, tooNarrow }
 */
function inspectBarcodeFit(bc, value, type, orientation, region) {
  const mw = effectiveModuleWidth(bc, value, type, orientation, region);
  const modules = type === 'EAN13' ? 95 : code128Modules(value);
  const margin = 10;
  const avail = orientation === 'R'
    ? region.height - (bc.y || 0) - margin
    : region.width - (bc.x || 0) - margin;
  const totalWidth = modules * mw;

  return {
    moduleWidth: mw,
    totalWidth,
    avail,
    overflow: totalWidth > avail,               // 상한을 못 줄여 라벨 밖으로 나감
    tooNarrow: mw < MIN_SCANNABLE_MODULE_WIDTH, // 너무 얇아 스캔 실패 위험
  };
}

/**
 * 출력 밀도 명령 (~SD) — 라벨 포맷(^XA..^XZ) 밖의 전역 즉시 명령
 * @param {number|string} value - 0~30 절대값
 * @returns {string|null} 범위 밖/미설정 시 null (프린터 기본값 사용)
 */
function darknessZpl(value) {
  const d = parseInt(value, 10);
  if (!Number.isFinite(d) || d < 0 || d > 30) return null;

    if (m) {
      const mod = Number(m[3]);
      const modulos = qrModuleCount(utf8Len(m[4]));
      out.elementos.push({ tipo: 'qr', x: Number(m[1]), y: Number(m[2]), modulos, modulo: mod, lado: modulos * mod });
      continue;
    }
    // [2026-10-03] raya entre productos (^GB ancho,alto,grosor)
    m = /^\^FO(\d+),(\d+)\^GB(\d+),(\d+),(\d+)\^FS$/.exec(ln);
    if (m) {
      out.elementos.push({ tipo: 'linea', x: Number(m[1]), y: Number(m[2]), ancho: Number(m[3]), alto: Number(m[4]) });
      continue;
    }
    // [PEDIDO 10] ^FB opcional = bloque de 1 línea alineado (C/R) dentro de `ancho`
    m = /^\^FO(\d+),(\d+)\^A0N,(\d+),(\d+)(?:\^FB(\d+),\d+,\d+,([LCRJ]))?\^FD(.*)\^FS$/.exec(ln);
    if (m) {
      const e = { tipo: 'texto', x: Number(m[1]), y: Number(m[2]), alto: Number(m[3]), texto: m[7] };
      if (m[5]) { e.ancho = Number(m[5]); e.alinear = m[6]; }
      out.elementos.push(e);
    }
  }

  return out;
}

/**
 * Etiqueta de prueba («Imprimir test» y «Imprimir prueba» del panel).
 *
 * ★ [2026-10-07 usuario] «더블 밴드로 놓고 테스트 버튼을 누를 때 더블 밴드로 나오게».
 *   Antes era un ZPL fijo de 50×25 (^PW400): con «Modo Duplicado» (100×25) salía sólo la
 *   etiqueta izquierda y la derecha en blanco. Ahora sigue el modo como `formatLabel`:
 *   ^PW = ancho del modo y, si es doble banda, la misma prueba en las dos mitades.
 * ★ Los demás modos salen igual que antes (50×25, a la izquierda).
 *
 * @param {Object} mode - modo efectivo (getEffectiveMode): width, halfWidth, duplicate, name
 * @param {{darkness?: number|null, speed?: number|null}} ajustes
 * @returns {string} ZPL
 */
function formatTestLabel(mode, { darkness = null, speed = null } = {}) {
  const doble = !!(mode && mode.duplicate && mode.halfWidth);
  const ancho = doble ? mode.width : 400;
  // ★ [codex 041] el código se achica a su etiqueta, igual que `renderCopy`: con ^BY3 mide
  //   435 dots. En doble banda la izquierda se metía en la derecha; en una cara (400 dots)
  //   se cortaba el final (2026-10-07 «맞춰줘»). Nunca más ancho que los 400 de antes.
  const region = doble ? mode.halfWidth : Math.min(400, (mode && mode.width) || 400);
  const by = effectiveModuleWidth({ x: 10, moduleWidth: 3 }, '1234567890', 'CODE128', 'N', {
    width: region,
    height: (mode && mode.height) || 200,
  });
  const copia = (dx) => [
    `^FO${10 + dx},5^A0N,22,22^FDVENTAGO ZEBRA TEST^FS`,
    `^FO${10 + dx},30^BY${by}^BCN,50,Y,N,N^FD1234567890^FS`,
    `^FO${10 + dx},100^A0N,28,28^FD$0.00^FS`,
    `^FO${10 + dx},135^A0N,16,16^FDD:${darkness ?? 'auto'} V:${speed ?? 'auto'}^FS`,
    // en doble banda, cuál es cuál: así se ve si la derecha salió corrida
    ...(doble ? [`^FO${10 + dx},158^A0N,16,16^FD${dx === 0 ? 'IZQ' : 'DER'} · ${sanitize(mode.name || '')}^FS`] : []),
  ];

  return [
    darknessZpl(darkness),
    '^XA',
    `^PW${ancho}`,
    // [codex 041] el alto del modo (puede estar personalizado), como la etiqueta real
    `^LL${doble && mode.height ? mode.height : 200}`,
    '^CI28',
    speedZpl(speed),
    ...copia(0),
    ...(doble ? copia(mode.halfWidth) : []),
    '^XZ',
  ]
    .filter(Boolean)
    .join('\n');
}

module.exports = {
  formatLabel,
  formatTestLabel,
  formatBatchLabels,
  formatQrLabel,
  resolveMode,
  estTextWidth,
  nivelFontSize,
  code128Modules,
  effectiveModuleWidth,
  inspectBarcodeFit,
  darknessZpl,
  speedZpl,
  MAX_MODULE_WIDTH,
  MIN_SCANNABLE_MODULE_WIDTH,
  utf8Len,
/**
 * formatTestLabel — «Imprimir test» sigue el modo elegido (2026-10-07).
 * 실행: node test/test-label.test.js
 *
 *  - Modo Duplicado (doble banda): ^PW = ancho del modo y la prueba en las DOS etiquetas
 *  - los demás modos: el ZPL de antes, con el código achicado a su etiqueta
 */
const assert = require('assert');
const { formatTestLabel, resolveMode } = require('../src/zpl-formatter');

let passed = 0;
function ok(name, cond) {
  assert.ok(cond, name);
  passed += 1;
  console.log('  ✓', name);
}

console.log('formatTestLabel — prueba según el modo\n');

// el ZPL fijo que imprimía la prueba antes del cambio (main.js printTest)
const ANTES = (d, v) =>
  [
    d,
    '^XA',
    '^PW400',
    '^LL200',
    '^CI28',
    v,
    '^FO10,5^A0N,22,22^FDVENTAGO ZEBRA TEST^FS',
    '^FO10,30^BY3^BCN,50,Y,N,N^FD1234567890^FS',
    '^FO10,100^A0N,28,28^FD$0.00^FS',
    `^FO10,135^A0N,16,16^FDD:${d ? 15 : 'auto'} V:${v ? 4 : 'auto'}^FS`,
    '^XZ',
  ]
    .filter(Boolean)
    .join('\n');

// ── doble banda ──
const dup = { ...resolveMode('modo-duplicado') };
const zDup = formatTestLabel(dup, {});
ok('doble banda: ^PW800 (las dos etiquetas)', zDup.includes('^PW800') && !zDup.includes('^PW400'));
ok(
  'doble banda: la prueba sale dos veces',
  zDup.split('VENTAGO ZEBRA TEST').length - 1 === 2 && zDup.split('^FD1234567890').length - 1 === 2,
);
ok('doble banda: la derecha empieza en la mitad (x = 400 + 10)', zDup.includes('^FO410,5^A0N,22,22^FDVENTAGO ZEBRA TEST'));
ok('doble banda: el código de barras derecho también corrido', /\^FO410,30\^BY\d\^BCN/.test(zDup));
ok('doble banda: cada mitad dice cuál es', zDup.includes('IZQ · Modo Duplicado') && zDup.includes('DER · Modo Duplicado'));
ok('doble banda: un solo ^XA/^XZ (una etiqueta física)', zDup.split('^XA').length === 2 && zDup.split('^XZ').length === 2);

// [codex 041] cada código entra en su mitad (como renderCopy): x + módulos × ^BY ≤ mitad
const { code128Modules } = require('../src/zpl-formatter');
const by = Number(/\^BY(\d+)/.exec(zDup)[1]);
ok(
  `doble banda: el código entra en su mitad (^BY${by} → ${10 + code128Modules('1234567890') * by} ≤ 400)`,
  10 + code128Modules('1234567890') * by <= dup.halfWidth,
);
ok('doble banda: ^LL del modo', zDup.includes(`^LL${dup.height}`));
ok('doble banda: alto personalizado', formatTestLabel({ ...dup, height: 240 }, {}).includes('^LL240'));

// ancho personalizado del modo (getEffectiveMode recalcula halfWidth)
const zCustom = formatTestLabel({ ...dup, width: 832, halfWidth: 416 }, {});
ok('ancho personalizado: ^PW832 y la derecha en x = 426', zCustom.includes('^PW832') && zCustom.includes('^FO426,5'));

// ── los demás modos: igual que antes salvo el código, que ahora entra en la etiqueta ──
const ANTES_BY2 = ANTES(null, null).replace('^BY3', '^BY2');
for (const key of ['simple-face', 'doble-face']) {
  const z = formatTestLabel(resolveMode(key), {});
  ok(`${key}: el ZPL de antes con ^BY2`, z === ANTES_BY2);
  const byK = Number(/\^BY(\d+)/.exec(z)[1]);
  ok(`${key}: el código entra en 400 dots (^BY${byK})`, 10 + code128Modules('1234567890') * byK <= 400);
}
// poliamida (200 de ancho): el código se achica a lo que entra, nunca más ancho que antes
const zPoli = formatTestLabel(resolveMode('poliamida-vertical'), {});
const byPoli = Number(/\^BY(\d+)/.exec(zPoli)[1]);
ok(`poliamida: ^BY${byPoli} → entra en 200`, 10 + code128Modules('1234567890') * byPoli <= 200);
ok('poliamida: resto igual que antes', zPoli.replace(`^BY${byPoli}`, '^BY3') === ANTES(null, null));
// una cara con ancho personalizado mayor: la prueba sigue en ^PW400, así que el código también
ok('una cara ancha: el código sigue ajustado a 400', formatTestLabel({ ...resolveMode('simple-face'), width: 832 }, {}) === ANTES_BY2);
// sin modo (por si acaso): como una cara
ok('sin modo: como una cara', formatTestLabel(null, {}) === ANTES_BY2);

// densidad y velocidad siguen entrando
const conAjustes = formatTestLabel(resolveMode('simple-face'), { darkness: 15, speed: 4 });
ok('densidad/velocidad: ~SD y ^PR presentes', /~SD15/.test(conAjustes) && /\^PR4/.test(conAjustes));
ok('densidad/velocidad en doble banda', /~SD15/.test(formatTestLabel(dup, { darkness: 15, speed: 4 })));

console.log(`\n${passed} ok`);
diff --git a/zebra-agent/src/zpl-formatter.js b/zebra-agent/src/zpl-formatter.js
index 8cfea42..17ea2b7 100644
--- a/zebra-agent/src/zpl-formatter.js
+++ b/zebra-agent/src/zpl-formatter.js
@@ -1077,14 +1077,14 @@ function zplADibujo(zpl) {
 function formatTestLabel(mode, { darkness = null, speed = null } = {}) {
   const doble = !!(mode && mode.duplicate && mode.halfWidth);
   const ancho = doble ? mode.width : 400;
-  // ★ [codex 041] en doble banda el código va achicado a su mitad, igual que `renderCopy`
-  //   (con ^BY3 mide 435 dots y la izquierda se metía en la etiqueta derecha)
-  const by = doble
-    ? effectiveModuleWidth({ x: 10, moduleWidth: 3 }, '1234567890', 'CODE128', 'N', {
-        width: mode.halfWidth,
-        height: mode.height || 200,
-      })
-    : 3;
+  // ★ [codex 041] el código se achica a su etiqueta, igual que `renderCopy`: con ^BY3 mide
+  //   435 dots. En doble banda la izquierda se metía en la derecha; en una cara (400 dots)
+  //   se cortaba el final (2026-10-07 «맞춰줘»). Nunca más ancho que los 400 de antes.
+  const region = doble ? mode.halfWidth : Math.min(400, (mode && mode.width) || 400);
+  const by = effectiveModuleWidth({ x: 10, moduleWidth: 3 }, '1234567890', 'CODE128', 'N', {
+    width: region,
+    height: (mode && mode.height) || 200,
+  });
   const copia = (dx) => [
     `^FO${10 + dx},5^A0N,22,22^FDVENTAGO ZEBRA TEST^FS`,
     `^FO${10 + dx},30^BY${by}^BCN,50,Y,N,N^FD1234567890^FS`,
diff --git a/zebra-agent/test/test-label.test.js b/zebra-agent/test/test-label.test.js
index 6484461..6f3b8e4 100644
--- a/zebra-agent/test/test-label.test.js
+++ b/zebra-agent/test/test-label.test.js
@@ -3,7 +3,7 @@
  * 실행: node test/test-label.test.js
  *
  *  - Modo Duplicado (doble banda): ^PW = ancho del modo y la prueba en las DOS etiquetas
- *  - los demás modos: exactamente el ZPL de antes (50×25, a la izquierda)
+ *  - los demás modos: el ZPL de antes, con el código achicado a su etiqueta
  */
 const assert = require('assert');
 const { formatTestLabel, resolveMode } = require('../src/zpl-formatter');
@@ -62,10 +62,23 @@ ok('doble banda: alto personalizado', formatTestLabel({ ...dup, height: 240 }, {
 const zCustom = formatTestLabel({ ...dup, width: 832, halfWidth: 416 }, {});
 ok('ancho personalizado: ^PW832 y la derecha en x = 426', zCustom.includes('^PW832') && zCustom.includes('^FO426,5'));
 
-// ── los demás modos: igual que antes ──
-for (const key of ['simple-face', 'doble-face', 'poliamida-vertical']) {
-  ok(`${key}: el mismo ZPL de antes`, formatTestLabel(resolveMode(key), {}) === ANTES(null, null));
+// ── los demás modos: igual que antes salvo el código, que ahora entra en la etiqueta ──
+const ANTES_BY2 = ANTES(null, null).replace('^BY3', '^BY2');
+for (const key of ['simple-face', 'doble-face']) {
+  const z = formatTestLabel(resolveMode(key), {});
+  ok(`${key}: el ZPL de antes con ^BY2`, z === ANTES_BY2);
+  const byK = Number(/\^BY(\d+)/.exec(z)[1]);
+  ok(`${key}: el código entra en 400 dots (^BY${byK})`, 10 + code128Modules('1234567890') * byK <= 400);
 }
+// poliamida (200 de ancho): el código se achica a lo que entra, nunca más ancho que antes
+const zPoli = formatTestLabel(resolveMode('poliamida-vertical'), {});
+const byPoli = Number(/\^BY(\d+)/.exec(zPoli)[1]);
+ok(`poliamida: ^BY${byPoli} → entra en 200`, 10 + code128Modules('1234567890') * byPoli <= 200);
+ok('poliamida: resto igual que antes', zPoli.replace(`^BY${byPoli}`, '^BY3') === ANTES(null, null));
+// una cara con ancho personalizado mayor: la prueba sigue en ^PW400, así que el código también
+ok('una cara ancha: el código sigue ajustado a 400', formatTestLabel({ ...resolveMode('simple-face'), width: 832 }, {}) === ANTES_BY2);
+// sin modo (por si acaso): como una cara
+ok('sin modo: como una cara', formatTestLabel(null, {}) === ANTES_BY2);
 
 // densidad y velocidad siguen entrando
 const conAjustes = formatTestLabel(resolveMode('simple-face'), { darkness: 15, speed: 4 });

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
/bin/zsh -lc "node zebra-agent/test/test-label.test.js && node - <<'NODE'
const {formatTestLabel,resolveMode,code128Modules}=require('./zebra-agent/src/zpl-formatter');
for (const key of ['simple-face','doble-face','poliamida-vertical','modo-duplicado']) {
 const z=formatTestLabel(resolveMode(key),{});
 console.log(key, 'modules='+code128Modules('1234567890'), z.match(/\\"'^PW'"\\d+/)?.[0], z.match(/\\"'^BY'"\\d+/)?.[0]);
}
NODE
nl -ba zebra-agent/src/zpl-formatter.js | sed -n '1072,1108p'; nl -ba zebra-agent/test/test-label.test.js | sed -n '60,90p'" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 0ms:
formatTestLabel — prueba según el modo

  ✓ doble banda: ^PW800 (las dos etiquetas)
  ✓ doble banda: la prueba sale dos veces
  ✓ doble banda: la derecha empieza en la mitad (x = 400 + 10)
  ✓ doble banda: el código de barras derecho también corrido
  ✓ doble banda: cada mitad dice cuál es
  ✓ doble banda: un solo ^XA/^XZ (una etiqueta física)
  ✓ doble banda: el código entra en su mitad (^BY2 → 300 ≤ 400)
  ✓ doble banda: ^LL del modo
  ✓ doble banda: alto personalizado
  ✓ ancho personalizado: ^PW832 y la derecha en x = 426
  ✓ simple-face: el ZPL de antes con ^BY2
  ✓ simple-face: el código entra en 400 dots (^BY2)
  ✓ doble-face: el ZPL de antes con ^BY2
  ✓ doble-face: el código entra en 400 dots (^BY2)
  ✓ poliamida: ^BY1 → entra en 200
  ✓ poliamida: resto igual que antes
  ✓ una cara ancha: el código sigue ajustado a 400
  ✓ sin modo: como una cara
  ✓ densidad/velocidad: ~SD y ^PR presentes
  ✓ densidad/velocidad en doble banda

20 ok
simple-face modules=145 ^PW400 ^BY2
doble-face modules=145 ^PW400 ^BY2
poliamida-vertical modules=145 ^PW400 ^BY1
modo-duplicado modules=145 ^PW800 ^BY2
  1072	 *
  1073	 * @param {Object} mode - modo efectivo (getEffectiveMode): width, halfWidth, duplicate, name
  1074	 * @param {{darkness?: number|null, speed?: number|null}} ajustes
  1075	 * @returns {string} ZPL
  1076	 */
  1077	function formatTestLabel(mode, { darkness = null, speed = null } = {}) {
  1078	  const doble = !!(mode && mode.duplicate && mode.halfWidth);
  1079	  const ancho = doble ? mode.width : 400;
  1080	  // ★ [codex 041] el código se achica a su etiqueta, igual que `renderCopy`: con ^BY3 mide
  1081	  //   435 dots. En doble banda la izquierda se metía en la derecha; en una cara (400 dots)
  1082	  //   se cortaba el final (2026-10-07 «맞춰줘»). Nunca más ancho que los 400 de antes.
  1083	  const region = doble ? mode.halfWidth : Math.min(400, (mode && mode.width) || 400);
  1084	  const by = effectiveModuleWidth({ x: 10, moduleWidth: 3 }, '1234567890', 'CODE128', 'N', {
  1085	    width: region,
  1086	    height: (mode && mode.height) || 200,
  1087	  });
  1088	  const copia = (dx) => [
  1089	    `^FO${10 + dx},5^A0N,22,22^FDVENTAGO ZEBRA TEST^FS`,
  1090	    `^FO${10 + dx},30^BY${by}^BCN,50,Y,N,N^FD1234567890^FS`,
  1091	    `^FO${10 + dx},100^A0N,28,28^FD$0.00^FS`,
  1092	    `^FO${10 + dx},135^A0N,16,16^FDD:${darkness ?? 'auto'} V:${speed ?? 'auto'}^FS`,
  1093	    // en doble banda, cuál es cuál: así se ve si la derecha salió corrida
  1094	    ...(doble ? [`^FO${10 + dx},158^A0N,16,16^FD${dx === 0 ? 'IZQ' : 'DER'} · ${sanitize(mode.name || '')}^FS`] : []),
  1095	  ];
  1096	
  1097	  return [
  1098	    darknessZpl(darkness),
  1099	    '^XA',
  1100	    `^PW${ancho}`,
  1101	    // [codex 041] el alto del modo (puede estar personalizado), como la etiqueta real
  1102	    `^LL${doble && mode.height ? mode.height : 200}`,
  1103	    '^CI28',
  1104	    speedZpl(speed),
  1105	    ...copia(0),
  1106	    ...(doble ? copia(mode.halfWidth) : []),
  1107	    '^XZ',
  1108	  ]
    60	
    61	// ancho personalizado del modo (getEffectiveMode recalcula halfWidth)
    62	const zCustom = formatTestLabel({ ...dup, width: 832, halfWidth: 416 }, {});
    63	ok('ancho personalizado: ^PW832 y la derecha en x = 426', zCustom.includes('^PW832') && zCustom.includes('^FO426,5'));
    64	
    65	// ── los demás modos: igual que antes salvo el código, que ahora entra en la etiqueta ──
    66	const ANTES_BY2 = ANTES(null, null).replace('^BY3', '^BY2');
    67	for (const key of ['simple-face', 'doble-face']) {
    68	  const z = formatTestLabel(resolveMode(key), {});
    69	  ok(`${key}: el ZPL de antes con ^BY2`, z === ANTES_BY2);
    70	  const byK = Number(/\^BY(\d+)/.exec(z)[1]);
    71	  ok(`${key}: el código entra en 400 dots (^BY${byK})`, 10 + code128Modules('1234567890') * byK <= 400);
    72	}
    73	// poliamida (200 de ancho): el código se achica a lo que entra, nunca más ancho que antes
    74	const zPoli = formatTestLabel(resolveMode('poliamida-vertical'), {});
    75	const byPoli = Number(/\^BY(\d+)/.exec(zPoli)[1]);
    76	ok(`poliamida: ^BY${byPoli} → entra en 200`, 10 + code128Modules('1234567890') * byPoli <= 200);
    77	ok('poliamida: resto igual que antes', zPoli.replace(`^BY${byPoli}`, '^BY3') === ANTES(null, null));
    78	// una cara con ancho personalizado mayor: la prueba sigue en ^PW400, así que el código también
    79	ok('una cara ancha: el código sigue ajustado a 400', formatTestLabel({ ...resolveMode('simple-face'), width: 832 }, {}) === ANTES_BY2);
    80	// sin modo (por si acaso): como una cara
    81	ok('sin modo: como una cara', formatTestLabel(null, {}) === ANTES_BY2);
    82	
    83	// densidad y velocidad siguen entrando
    84	const conAjustes = formatTestLabel(resolveMode('simple-face'), { darkness: 15, speed: 4 });
    85	ok('densidad/velocidad: ~SD y ^PR presentes', /~SD15/.test(conAjustes) && /\^PR4/.test(conAjustes));
    86	ok('densidad/velocidad en doble banda', /~SD15/.test(formatTestLabel(dup, { darkness: 15, speed: 4 })));
    87	
    88	console.log(`\n${passed} ok`);

hook: PostToolUse
hook: PostToolUse
hook: PostToolUse Failed
hook: PostToolUse Completed
codex
이상 없음.

검증 결과:

- 단면 400 dots: `avail = 400 - 10 - 10 = 380`, `floor(380 / 145) = 2` → `^BY2`
- 폴리아미다 200 dots: `avail = 180`, `floor(180 / 145) = 1` → `^BY1`
- 복제 모드도 각 `halfWidth` 기준으로 계산되어 오른쪽 영역 침범 없음
- 사용자 상한 `3`도 유지됨
- 테스트 20개 모두 통과

검토 위치: [zpl-formatter.js](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/zebra-agent/src/zpl-formatter.js:1077), [test-label.test.js](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/zebra-agent/test/test-label.test.js:65)

잔여 물리적 제약은 폴리아미다의 `^BY1`이 기존 코드의 최소 권장 스캔 폭인 2 dots보다 작다는 점이지만, 이번 요구사항에 명시된 의도된 결과이며 diff의 오류는 아닙니다. 파일은 수정하지 않았습니다.
hook: Stop
hook: Stop
hook: Stop Failed
hook: Stop Completed
tokens used
30,071
이상 없음.

검증 결과:

- 단면 400 dots: `avail = 400 - 10 - 10 = 380`, `floor(380 / 145) = 2` → `^BY2`
- 폴리아미다 200 dots: `avail = 180`, `floor(180 / 145) = 1` → `^BY1`
- 복제 모드도 각 `halfWidth` 기준으로 계산되어 오른쪽 영역 침범 없음
- 사용자 상한 `3`도 유지됨
- 테스트 20개 모두 통과

검토 위치: [zpl-formatter.js](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/zebra-agent/src/zpl-formatter.js:1077), [test-label.test.js](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/zebra-agent/test/test-label.test.js:65)

잔여 물리적 제약은 폴리아미다의 `^BY1`이 기존 코드의 최소 권장 스캔 폭인 2 dots보다 작다는 점이지만, 이번 요구사항에 명시된 의도된 결과이며 diff의 오류는 아닙니다. 파일은 수정하지 않았습니다.

## 처리
- 지적 0건. 폴리아미다 ^BY1(스캔 권장 2 미만)은 의도된 결과로 인정 — 그 모드의 테스트는 원래 가로 400 기준이라 글자도 200 폭을 넘는다. 사용자 보고에 명시.
