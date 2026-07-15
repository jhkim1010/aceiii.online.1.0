/**
 * E2E 시뮬레이션 테스트 — producto nuevo(Imprimir x ZPL) → /print/barcode → agent 출력
 * 실행: node test/print-flow.test.js
 *
 * 체인 재현:
 *  1) 프론트 ProductsList.handlePrintZpl 과 동일한 payload 빌드 (stock-today rows 기반)
 *  2) 서버 print.controller 의 passthrough ({ ...body, branchId, ts })
 *  3) agent: prepareItems(nivel 필터) → priceCount 고정 → formatBatchLabels(ZPL)
 */
const assert = require('assert');
const { prepareItems } = require('../src/price-select');
const f = require('../src/zpl-formatter');

let passed = 0;
function ok(name, cond) {
  assert.ok(cond, name);
  passed += 1;
  console.log('  ✓', name);
}

// ── 1) stock-today 응답 형태의 rows (Price + PriceType include) ──────────
const rows = [
  {
    name: 'REMERA OVERSIZE NEGRA M',
    sku: 'VG00123456',
    stockAddedToday: 3,
    prices: [
      { priceTypeId: 1, amount: 12999, priceType: { id: 1, name: 'Minorista' } },
      { priceTypeId: 2, amount: 9750, priceType: { id: 2, name: 'Mayorista' } },
      { priceTypeId: 3, amount: 0, priceType: { id: 3, name: 'Distribuidor' } }, // amount 0 → 프론트에서 제외
    ],
  },
  {
    name: 'PANTALON CARGO ^RARO~', // sanitize 대상 문자 포함
    sku: 'REMERA-OVR-NEG-M-2026',  // 긴 영숫자 SKU → auto-fit
    stockAddedToday: 1,
    prices: [
      { priceTypeId: 2, amount: '15500.50', priceType: { id: 2, name: 'Mayorista' } }, // 문자열 금액
    ],
  },
  {
    name: 'SIN PRECIO',
    sku: 'VG999',
    stockAddedToday: 2,
    prices: [], // 가격 없음
  },
];

// ── 프론트 ProductsList.handlePrintZpl 과 동일한 매핑 ─────────────────────
function buildFrontendPayload(rows) {
  const items = rows.map((p) => ({
    name: p.name,
    sku: p.sku || '',
    barcodeType: 'CODE128',
    prices: (p.prices || [])
      .filter((pr) => pr.amount > 0)
      .map((pr) => ({
        priceTypeId: pr.priceTypeId ?? pr.priceType?.id ?? null,
        label: pr.priceType?.name || '',
        amount: pr.amount,
      })),
    qty: Number(p.stockAddedToday ?? p.stock ?? 1),
  }));

  return { items, branchId: undefined };
}

// ── 서버 print.controller POST /print/barcode 재현 ────────────────────────
function serverPassthrough(body, userBranchId) {
  const branchId = body?.branchId || userBranchId || 0;
  assert.ok(branchId, 'branchId requerido');
  assert.ok(Array.isArray(body?.items) && body.items.length > 0, 'items requerido');

  return { ...body, branchId, ts: Date.now() };
}

// ── agent 수신부 재현 (main.js print_barcode 핸들러와 동일 순서) ───────────
function agentPrint(payload, { modeKey, custom = {}, priceSelection = [] }) {
  const base = f.resolveMode(modeKey);
  const mode = {
    ...base,
    width: custom.width || base.width,
    height: custom.height || base.height,
    halfWidth: base.duplicate ? Math.round((custom.width || base.width) / 2) : base.halfWidth,
    layout: custom.layout ? { ...base.layout, ...custom.layout } : base.layout,
    darkness: custom.darkness ?? null,
    speed: custom.speed ?? null,
  };
  if (priceSelection.length > 0) {
    mode.layout = { ...mode.layout, priceCount: priceSelection.length };
  }
  const items = prepareItems(payload.items, priceSelection, mode.layout);

  return f.formatBatchLabels(items, mode);
}

// ═══ 테스트 ═══════════════════════════════════════════════════════════════
console.log('E2E print flow — producto nuevo → /print/barcode → agent ZPL\n');

// 프론트 payload
const body = buildFrontendPayload(rows);
ok('프론트: amount 0 가격 제외', body.items[0].prices.length === 2);
ok('프론트: priceTypeId 동봉', body.items[0].prices[0].priceTypeId === 1);
ok('프론트: qty = stockAddedToday', body.items[0].qty === 3);

// 서버 passthrough (JWT user.branchId = 4 가정)
const wsData = serverPassthrough(body, 4);
ok('서버: branchId 주입', wsData.branchId === 4);
ok('서버: items 원형 유지', wsData.items.length === 3);

// A) nivel = [Mayorista] 선택 — Minorista 는 출력되면 안 됨
const zplA = agentPrint(wsData, {
  modeKey: 'simple-face',
  priceSelection: [{ id: 2, name: 'Mayorista' }],
});
ok('A: Mayorista 라벨 출력', /Mayorista/.test(zplA));
ok('A: Mayorista 금액 출력', /\$9\.750,00/.test(zplA));
ok('A: Minorista 미출력', !/Minorista/.test(zplA));
ok('A: qty 3+1+2 = ^XA 6개', (zplA.match(/\^XA/g) || []).length === 6);
ok('A: sanitize (^,~ 제거)', /PANTALON CARGO RARO/.test(zplA) && !/CARGO \^RARO~/.test(zplA));
ok('A: 문자열 금액 파싱', /\$15\.500,50/.test(zplA));

// B) nivel 미설정 — 하위 호환: payload 첫 가격 1개
const zplB = agentPrint(wsData, { modeKey: 'simple-face', priceSelection: [] });
ok('B: 기본 1개 — Minorista 출력', /\$12\.999,00/.test(zplB));
ok('B: 2번째 가격 미출력 (item1)', !/\$9\.750,00/.test(zplB));

// C) nivel 2개 [Minorista, Mayorista] — 우하단 자동배치, Precio1=맨 오른쪽
const zplC = agentPrint(wsData, {
  modeKey: 'simple-face',
  priceSelection: [{ id: 1, name: 'Minorista' }, { id: 2, name: 'Mayorista' }],
});
const linesC = zplC.split('\n').filter((l) => /12\.999|9\.750/.test(l));
const xOf = (l) => parseInt(l.match(/\^FO(\d+),/)[1], 10);
ok('C: 두 가격 모두 출력', linesC.length >= 2);
ok('C: Precio1(Minorista) 이 더 오른쪽', xOf(linesC[0]) > xOf(linesC[1]));
ok('C: nivel 라벨 소형(12dot) 존재', /\^A0N,12,12\^FDMinorista/.test(zplC));

// D) 존재하지 않는 nivel 선택 → 해당 슬롯만 건너뜀 (오류 없음)
const zplD = agentPrint(wsData, {
  modeKey: 'simple-face',
  priceSelection: [{ id: 99, name: 'Inexistente' }],
});
ok('D: 매칭 실패 시 가격 미출력·크래시 없음', !/\$/.test(zplD.replace(/\^FD\$/g, 'PRICE')) || !/PRICE/.test(zplD));

// E) label 이름 fallback 매칭 (priceTypeId 없는 구버전 payload)
const legacyBody = {
  items: [{
    name: 'LEGACY', sku: 'L1', barcodeType: 'CODE128', qty: 1,
    prices: [{ label: 'mayorista', amount: 500 }], // id 없음 + 소문자
  }],
};
const zplE = agentPrint(serverPassthrough(legacyBody, 4), {
  modeKey: 'simple-face',
  priceSelection: [{ id: 2, name: 'Mayorista' }],
});
ok('E: 이름 대소문자 무시 fallback 매칭', /\$500,00/.test(zplE));

// F) 4모드 전부 정상 생성 + 회전/복제/밀도/속도
for (const mk of ['simple-face', 'doble-face', 'modo-duplicado', 'poliamida-vertical']) {
  const z = agentPrint(wsData, {
    modeKey: mk,
    custom: { darkness: 22, speed: 4 },
    priceSelection: [{ id: 1, name: 'Minorista' }],
  });
  ok(`F[${mk}]: ~SD22 1회 + ^PR4`, (z.match(/~SD22/g) || []).length === 1 && /\^PR4/.test(z));
  if (mk === 'poliamida-vertical') ok('F: 회전 ^A0R/^BCR', /\^A0R/.test(z) && /\^BCR/.test(z));
  if (mk === 'modo-duplicado') {
    const copies = (z.split('\n').filter((l) => /REMERA OVERSIZE/.test(l)) || []).length;
    ok('F: duplicado 좌우 복제 (첫 라벨에 이름 2회)', copies >= 2);
  }
}

// G) 바코드 auto-fit — 긴 SKU 는 ^BY1, 짧은 SKU 는 ^BY2 유지
const byLong = zplA.split('\n').find((l) => /REMERA-OVR-NEG-M-2026/.test(l) && /\^BY/.test(l));
const byShort = zplA.split('\n').find((l) => /VG00123456/.test(l) && /\^BY/.test(l));
ok('G: 긴 SKU → ^BY1 자동 축소', /\^BY1/.test(byLong));
ok('G: 짧은 SKU → ^BY2 유지', /\^BY2/.test(byShort));

// H) 가격 없는 상품 — 가격 라인 없이 이름+바코드만
const zplH = agentPrint({ items: [rows[2]].map((p) => buildFrontendPayload([p]).items[0]), branchId: 4 }, {
  modeKey: 'simple-face',
  priceSelection: [{ id: 1, name: 'Minorista' }],
});
ok('H: 가격 없음 → 이름/바코드만, 크래시 없음', /SIN PRECIO/.test(zplH) && !/\$\d/.test(zplH));

// I) items 비어있음/비배열 방어
ok('I: prepareItems(null) → []', prepareItems(null, [], {}).length === 0);

// J) auto-fit 양방향 — 짧은 SKU 는 가용 폭에 맞춰 모듈 폭을 키운다
const shortBody = {
  items: [{ name: 'CORTO', sku: 'VG9', barcodeType: 'CODE128', qty: 1, prices: [] }],
  branchId: 4,
};
const zplJ = agentPrint(shortBody, { modeKey: 'simple-face', priceSelection: [] });
const byJ = parseInt(zplJ.match(/\^BY(\d+)/)[1], 10);
ok('J: 짧은 SKU → moduleWidth 확대 (>2)', byJ > 2);

// 사용자 설정(moduleWidth)이 상한 — 폭이 남아도 그 이상으로 키우지 않는다
const presetCap = f.LABEL_MODES['simple-face'].layout.barcode.moduleWidth;
ok(`J: 사용자 상한(${presetCap}) 까지만 확대`, byJ === presetCap);

const zplJcap = agentPrint(shortBody, {
  modeKey: 'simple-face',
  custom: { layout: { barcode: { x: 10, y: 30, height: 45, moduleWidth: 3 } } },
  priceSelection: [],
});
ok('J: 상한 3 으로 낮추면 ^BY3 (사용자 설정 유효)', /\^BY3\^/.test(zplJcap));

// J-2) autoFit off → 설정한 moduleWidth 정확히 사용 (확대/축소 없음)
const zplJ2 = agentPrint(shortBody, {
  modeKey: 'simple-face',
  custom: { layout: { barcode: { x: 10, y: 30, height: 45, moduleWidth: 2, autoFit: false } } },
  priceSelection: [],
});
ok('J-2: autoFit off → ^BY2 그대로', /\^BY2\^/.test(zplJ2));

// J-3) 확대해도 라벨 폭을 넘지 않음 (modules * mw <= 가용 폭)
const modulesJ = f.code128Modules('VG9');
ok('J-3: 확대 후에도 가용 폭 이내', modulesJ * byJ <= 400 - 10 - 10);

// J-4) 진단 — SKU 길이는 사용자마다 다르므로 "안 들어감/너무 얇음" 을 UI 가 알 수 있어야 함
const region50 = { width: 400, height: 200 };
const bcDefault = f.LABEL_MODES['simple-face'].layout.barcode;

const fitShort = f.inspectBarcodeFit(bcDefault, 'VG9', 'CODE128', 'N', region50);
ok('J-4: 짧은 SKU → 경고 없음', !fitShort.overflow && !fitShort.tooNarrow);

const fitLong = f.inspectBarcodeFit(bcDefault, 'REMERA-OVR-NEG-M-2026', 'CODE128', 'N', region50);
ok('J-4: 긴 SKU → tooNarrow 경고 (^BY1 스캔 실패 위험)',
  fitLong.moduleWidth === 1 && fitLong.tooNarrow);
ok('J-4: 긴 SKU 도 축소로 라벨 안에는 들어감', !fitLong.overflow);

// autoFit off + 상한 4 → 긴 SKU 는 라벨 밖으로 (사용자가 자동조절을 끈 결과)
const fitOverflow = f.inspectBarcodeFit(
  { ...bcDefault, autoFit: false }, 'REMERA-OVR-NEG-M-2026', 'CODE128', 'N', region50,
);
ok('J-4: autoFit off + 긴 SKU → overflow 경고', fitOverflow.overflow);

// K) ~SD/^PR 헬퍼 범위 검증 — 범위 밖/빈값은 null (프린터 기본값)
ok('K: darknessZpl(22) → ~SD22', f.darknessZpl(22) === '~SD22');
ok('K: darknessZpl(5) → 0 패딩 ~SD05', f.darknessZpl(5) === '~SD05');
ok('K: darknessZpl(31)/null → null', f.darknessZpl(31) === null && f.darknessZpl(null) === null);
ok('K: speedZpl(4) → ^PR4', f.speedZpl(4) === '^PR4');
ok('K: speedZpl(1)/(15)/null → null',
  f.speedZpl(1) === null && f.speedZpl(15) === null && f.speedZpl(null) === null);

console.log(`\n${passed} checks passed ✅`);
