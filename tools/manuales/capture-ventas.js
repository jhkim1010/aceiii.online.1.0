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
// 주의: 헤더는 CSS text-transform 으로 대문자 표시될 수 있어 대소문자 무시 + 말단 노드 기준 탐색
async function blurClientData(page) {
  await page.evaluate(() => {
    // 텍스트를 포함하는 가장 작은 요소에서 위로 올라가며
    // 데이터 테이블을 포함하는 조상 전체를 blur (헤더만 blur 되는 문제 방지)
    const cands = [...document.querySelectorAll('div,span,p,h2,h3')]
      .filter((e) => /lista de los clientes/i.test(e.textContent || ''))
      .sort((a, b) => (a.textContent || '').length - (b.textContent || '').length);
    let node = cands[0];
    for (let i = 0; i < 8 && node; i++) {
      if (node.querySelector && node.querySelector('table, .MuiDataGrid-root, .ag-root-wrapper')) {
        node.style.filter = 'blur(9px)';
        break;
      }
      node = node.parentElement;
    }
  }).catch(() => {});
}

// 텍스트로 요소를 찾아 실제 마우스 클릭 (MUI 는 DOM .click() 이 안 먹는 경우가 있음)
async function clickByText(page, reStr, maxLen = 80) {
  const handle = await page.evaluateHandle((re, ml) => {
    const rx = new RegExp(re, 'i');
    const cands = [...document.querySelectorAll('button,li,div,span,p,h2')]
      .filter((e) => rx.test(e.textContent || '') && (e.textContent || '').trim().length < ml);
    cands.sort((a, b) => (a.textContent || '').length - (b.textContent || '').length);

    return cands[0] || null;
  }, reStr, maxLen);
  const el = handle.asElement();
  if (!el) return false;
  const box = await el.boundingBox();
  if (!box) return false;
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);

  return true;
}

// «Seleccionar Sucursal» 모달 처리 — 새 세션은 지점 미지정이라 모달이 화면을 가림
async function selectSucursal(page) {
  const modalShown = () =>
    page.evaluate(() => /seleccionar sucursal/i.test(document.body.textContent || '')).catch(() => false);

  if (!(await modalShown())) return;
  console.log('[capture] sucursal 모달 감지 — 선택 시도');

  // 옵션(Sucursal principal) 실제 클릭 → Confirmar 활성화 대기 후 클릭
  await clickByText(page, 'Sucursal principal', 80);
  await sleep(1000);
  for (let i = 0; i < 6; i++) {
    const enabled = await page.evaluate(() => {
      const btn = [...document.querySelectorAll('button')].find((b) => /confirmar/i.test(b.textContent || ''));

      return btn ? !btn.disabled : false;
    });
    if (enabled) {
      await clickByText(page, 'Confirmar', 30);
      break;
    }

    // 아직 비활성 — 옵션 클릭 재시도
    await clickByText(page, 'Sucursal principal', 80);
    await sleep(900);
  }
  await sleep(2500);
  console.log(`[capture] sucursal 선택 ${(await modalShown()) ? '실패 — 수동 확인 필요' : '완료'}`);
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

    // 지점 사전 지정 — «Seleccionar Sucursal» 모달 우회 (BranchContext 가 localStorage 를 읽음)
    // Cool Store(id=1) / store_id=1 (admin@cool.test 계정 기준). 계정이 다르면 값 조정.
    await page.evaluate(() => {
      window.localStorage.setItem('selectedBranchId', '1');
      window.localStorage.setItem('selectedBranchStoreId', '1');
    });

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
    await selectSucursal(page);

    // 02 — Nueva Venta (POS)
    await goTo(page, '/nueva-venta', 4000);
    await selectSucursal(page);
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

  // 전 영역(Producto/Admin/Stock/MP/Talleres) 캡처 체인 실행
  // — 러너 재시작 없이 확장하기 위한 위임. 러너 whitelist 에 capture-manuales 가
  //   반영된 뒤에는 이 체인을 제거해도 됨.
  try {
    const { execFileSync } = require('child_process');
    execFileSync('node', [path.join(__dirname, 'capture-manuales.js')], { stdio: 'inherit', env: process.env });
  } catch (e) {
    console.error('[capture] capture-manuales 체인 실패:', e.message);
  }
})();
