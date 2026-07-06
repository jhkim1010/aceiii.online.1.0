#!/usr/bin/env node
/**
 * 전 영역 매뉴얼 화면 캡처 (Producto / Admin / Stock / Materia Prima / Talleres)
 *
 * 사용법: VENTAGO_USER=.. VENTAGO_PASS=.. node tools/manuales/capture-manuales.js
 * (agent-runner 의 'capture-manuales' 작업으로도 실행됨)
 *
 * 결과: docs/manual-captures/<area>/<name>.png
 * 페이지 단위 캡처만 수행 — 다이얼로그/인터랙션 의존 화면은 자리표시자 유지.
 */

const path = require('path');
const fs = require('fs');
const puppeteer = require('puppeteer');

const BASE = process.env.VENTAGO_URL || 'http://localhost:3050';
const USER = process.env.VENTAGO_USER;
const PASS = process.env.VENTAGO_PASS;
const OUT_ROOT = path.resolve(__dirname, '..', '..', 'docs', 'manual-captures');

if (!USER || !PASS) {
  console.error('VENTAGO_USER / VENTAGO_PASS 환경변수가 필요합니다');
  process.exit(1);
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// 캡처 목록 — area(폴더) → [캡처명, 경로]
const PLAN = {
  producto: [
    ['producto-01-alta', '/productos'],
    ['producto-02-codigo-madre', '/codigo-vista'],
    ['producto-03-catalogos', '/configuracion/productos'],
    ['producto-05-precios', '/precios'],
    ['producto-10-parametros', '/configuracion/productos'],
  ],
  admin: [
    ['admin-01-estructura', '/sucursales'],
    ['admin-02-usuarios', '/usuarios'],
    ['admin-04-configuracion', '/configuracion/preferencias'],
    ['admin-05-gastos', '/gastos'],
    ['admin-06-agentes', '/sucursales/1/impresora'],
    ['admin-07-clientes', '/cuentas-corrientes'],
    ['admin-08-dashboards', '/dashboards'],
  ],
  stock: [
    ['stock-01-consulta', '/reportes/stocks'],
    ['stock-02-movido', '/reportes/movidos'],
    ['stock-03-ajustes', '/configuracion/inventario'],
    ['stock-04-reportes-ventas', '/reportes/ventas'],
    ['stock-05-reportes-caja', '/control-de-caja'],
    ['stock-06-valorizado', '/dashboards/stock'],
    ['stock-07-materia-prima', '/materia-prima/inventario'],
    ['stock-08-talleres', '/talleres/control'],
  ],
  'materia-prima': [
    ['mp-01-alta', '/materia-prima/telas-madre'],
    ['mp-02-unidades', '/materia-prima/dashboard'],
    ['mp-04-inventario', '/materia-prima/inventario'],
    ['mp-05-movimientos', '/materia-prima/movimientos'],
    ['mp-06-proveedores', '/materia-prima/proveedores'],
    ['mp-07-pagos', '/materia-prima/pagos'],
  ],
  talleres: [
    ['talleres-01-etapas', '/talleres/etapas'],
    ['talleres-02-vendors', '/talleres/vendors'],
    ['talleres-03-bom', '/talleres'],
    ['talleres-04-corte', '/talleres/pedidos'],
    ['talleres-05-envios', '/talleres/envios'],
    ['talleres-06-recepcion', '/talleres/deliveries'],
    ['talleres-07-mermas', '/talleres/defects'],
    ['talleres-08-liquidacion', '/talleres/liquidaciones'],
    ['talleres-09-reportes', '/dashboards/talleres'],
  ],
};

// 개인정보 blur — 고객/거래처 이름·서류번호가 노출될 수 있는 목록 화면 보호
async function blurPII(page) {
  await page.evaluate(() => {
    const HEADS = [/lista de los clientes/i];
    for (const rx of HEADS) {
      const cands = [...document.querySelectorAll('div,span,p,h2,h3')]
        .filter((e) => rx.test(e.textContent || ''))
        .sort((a, b) => (a.textContent || '').length - (b.textContent || '').length);
      let node = cands[0];
      for (let i = 0; i < 8 && node; i++) {
        if (node.querySelector && node.querySelector('table, .MuiDataGrid-root, .ag-root-wrapper')) {
          node.style.filter = 'blur(9px)';
          break;
        }
        node = node.parentElement;
      }
    }
  }).catch(() => {});
}

(async () => {
  const browser = await puppeteer.launch({
    headless: 'new',
    args: ['--window-size=1440,900'],
    defaultViewport: { width: 1440, height: 900, deviceScaleFactor: 2 },
  });
  const page = await browser.newPage();

  try {
    // 로그인 (+ 지점 사전 지정으로 sucursal 모달 우회)
    await page.goto(`${BASE}/login`, { waitUntil: 'networkidle2', timeout: 60000 });
    await sleep(2000);
    await page.evaluate(() => {
      window.localStorage.setItem('selectedBranchId', '1');
      window.localStorage.setItem('selectedBranchStoreId', '1');
    });
    await page.type('input[placeholder*="usuario@" i], input[placeholder*="email" i]', USER, { delay: 20 });
    await page.type('input[type="password"]', PASS, { delay: 20 });
    await Promise.all([
      page.waitForNavigation({ waitUntil: 'networkidle2', timeout: 60000 }).catch(() => {}),
      page.evaluate(() => {
        const btn = [...document.querySelectorAll('button')].find((b) => /iniciar sesi/i.test(b.textContent || ''));
        if (btn) btn.click();
      }),
    ]);
    await sleep(4000);

    let ok = 0;
    let fail = 0;
    for (const [area, caps] of Object.entries(PLAN)) {
      const dir = path.join(OUT_ROOT, area);
      fs.mkdirSync(dir, { recursive: true });
      for (const [name, route] of caps) {
        try {
          await page.goto(`${BASE}${route}`, { waitUntil: 'networkidle2', timeout: 60000 }).catch(() => {});
          await sleep(3500);
          await blurPII(page);
          await page.screenshot({ path: path.join(dir, `${name}.png`) });
          console.log(`[capture] ${area}/${name}.png`);
          ok++;
        } catch (e) {
          console.error(`[capture] 실패 ${area}/${name}: ${e.message}`);
          fail++;
        }
      }
    }
    console.log(`[capture] 완료 — 성공 ${ok}, 실패 ${fail}`);
  } finally {
    await browser.close();
  }
})();
