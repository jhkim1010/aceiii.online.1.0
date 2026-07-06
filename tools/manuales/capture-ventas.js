#!/usr/bin/env node
/**
 * Ventas 매뉴얼 화면 캡처 스크립트 (localhost dev)
 *
 * 사용법 (Mac, 프론트 3050 + api 5002 실행 중이어야 함):
 *   cd tools/manuales && npm install
 *   VENTAGO_USER='이메일또는유저' VENTAGO_PASS='비밀번호' node capture-ventas.js
 *
 * 결과: docs/manual-captures/ventas/*.png
 * 이후: NODE_PATH 없이 프로젝트 루트에서
 *   node tools/manuales/build-manual.js content-ventas.js
 * 를 재실행하면 캡처가 삽입된 docx 가 재생성된다.
 *
 * 개인정보: POS 의 고객 목록(LISTA DE LOS CLIENTES)은 캡처 전에 blur 처리한다.
 */

const path = require('path');
const fs = require('fs');
const puppeteer = require('puppeteer');

const BASE = process.env.VENTAGO_URL || 'http://localhost:3050';
const USER = process.env.VENTAGO_USER;
const PASS = process.env.VENTAGO_PASS;
const OUT = path.resolve(__dirname, '..', '..', 'docs', 'manual-captures', 'ventas');

if (!USER || !PASS) {
  console.error('VENTAGO_USER / VENTAGO_PASS 환경변수가 필요합니다');
  process.exit(1);
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// 고객 개인정보(이름/CUIT) 패널 blur — 매뉴얼 공개용
async function blurClientData(page) {
  await page.evaluate(() => {
    const blur = (el) => { el.style.filter = 'blur(6px)'; };
    for (const h of document.querySelectorAll('h1,h2,h3,h4,h5,h6,div,span')) {
      const t = (h.textContent || '').trim();
      if (t === 'LISTA DE LOS CLIENTES' || t === 'INFO DE CLIENTE') {
        // 헤더가 속한 카드의 본문(테이블) 을 blur
        const card = h.closest('.MuiCard-root, .MuiPaper-root') || h.parentElement;
        if (card) {
          const tables = card.querySelectorAll('table, .MuiDataGrid-root, .ag-root-wrapper');
          if (tables.length) tables.forEach(blur);
          else if (t === 'LISTA DE LOS CLIENTES') blur(card);
        }
      }
    }
  }).catch(() => {});
}

async function shot(page, name, opts = {}) {
  await sleep(opts.wait ?? 1200);
  await blurClientData(page);
  const fp = path.join(OUT, `${name}.png`);
  await page.screenshot({ path: fp, fullPage: opts.fullPage ?? false });
  console.log(`[capture] ${name}.png`);
}

async function goTo(page, p, waitMs = 2500) {
  await page.goto(`${BASE}${p}`, { waitUntil: 'networkidle2', timeout: 60000 }).catch(() => {});
  await sleep(waitMs);
}

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const browser = await puppeteer.launch({
    headless: 'new',
    args: ['--window-size=1440,900'],
    defaultViewport: { width: 1440, height: 900, deviceScaleFactor: 2 },
  });
  const page = await browser.newPage();

  try {
    // 01 — 로그인 화면 (로그인 전)
    await goTo(page, '/login', 3000);
    await shot(page, 'ventas-01-login', { wait: 500 });

    // 로그인
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

    // 02 — Nueva Venta (POS)
    await goTo(page, '/nueva-venta', 4000);
    await shot(page, 'ventas-02-nueva-venta');

    // 03 — 코드 마드레: 상품 검색 → 첫 옵션 선택 → 변형 표
    try {
      const input = await page.$('input[placeholder*="Buscar Producto" i]');
      if (input) {
        await input.click();
        await input.type('a', { delay: 60 });
        await sleep(2500);
        await page.keyboard.press('ArrowDown');
        await page.keyboard.press('Enter');
        await sleep(2500);
        await shot(page, 'ventas-03-codigo-madre');
      }
    } catch (e) {
      console.error('[capture] 03 실패 (수동 캡처 필요):', e.message);
    }

    // 04 — 가격 레벨 드롭다운 열기
    try {
      await page.evaluate(() => {
        const el = [...document.querySelectorAll('div,input')].find((d) => /^PRECIO\s/i.test((d.value || d.textContent || '').trim()));
        if (el) el.click();
      });
      await sleep(1000);
      await shot(page, 'ventas-04-precios', { wait: 300 });
      await page.keyboard.press('Escape');
    } catch (e) {
      console.error('[capture] 04 실패:', e.message);
    }

    // 06 — 판매 보류 패널 (POS 전체 화면 하단)
    await shot(page, 'ventas-06-suspender', { wait: 300 });

    // 07 — 판매 내역
    await goTo(page, '/ventas', 4000);
    await shot(page, 'ventas-07-historial');

    // 08 — Caja
    await goTo(page, '/caja', 4000);
    await shot(page, 'ventas-08-caja');

    // 10 — 프린터/에이전트 (sucursales)
    await goTo(page, '/sucursales', 4000);
    await shot(page, 'ventas-10-impresion');

    // 05(결제 모달)·09(식당 살롱) 는 매장 상태/데이터 의존 → 수동 캡처 권장:
    //   05: POS 에 상품 담고 Generar venta 클릭 시 뜨는 결제 모달 (확정하지 말 것)
    //   09: 식당 모드 매장의 nueva-venta 살롱 화면
    console.log('[capture] 완료. 05/09 는 수동 캡처 후 같은 이름으로 저장하세요:');
    console.log('  ventas-05-pagos.png / ventas-09-restaurante.png →', OUT);
  } finally {
    await browser.close();
  }
})();
