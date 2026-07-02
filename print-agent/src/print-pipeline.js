/**
 * print-pipeline.js
 *
 * HTML 티켓 → PNG → 프린터 전체 파이프라인.
 * main.js의 WebSocket 이벤트 핸들러에서 호출.
 *
 * 사용법:
 *   const { printTicket } = require('./src/print-pipeline');
 *   await printTicket(invoiceData, printerConfig);
 */

const { formatInvoiceHtml } = require('./formatter');
const { renderHtmlToPng }   = require('./renderer-engine');
const { printImage }        = require('./printer');

/**
 * 판매 데이터 → HTML → PNG → 프린터
 *
 * @param {object} data         - formatInvoiceHtml() 입력 데이터
 * @param {object} printerCfg   - printer 설정 (type, host, port, ...)
 * @param {function} log        - 단계별 디버그 로그 콜백 (운영 추적용, 선택)
 */
async function printTicket(data, printerCfg, log = () => {}) {
  const t0 = Date.now();

  // 0. 프린터 설정 검증 — 설정 누락이면 이후 단계 진입 전에 명확히 실패
  if (!printerCfg || !printerCfg.type) {
    throw new Error('printer no configurado (printerCfg 없음 또는 type 누락)');
  }
  log(
    `🔧 [pipeline] printerCfg type=${printerCfg.type} ` +
      `host=${printerCfg.host || '-'}:${printerCfg.port || '-'} ` +
      `device=${printerCfg.deviceName || '-'}`,
  );

  // 1. HTML 생성
  const html = formatInvoiceHtml(data);
  log(`📝 [1/3] HTML 생성 완료 (${html ? html.length : 0} chars, ${Date.now() - t0}ms)`);

  // 2. HTML → PNG (Electron offscreen)
  //    80mm @ 203dpi = 576px
  const t1 = Date.now();
  const pngBuffer = await renderHtmlToPng(html, 576);
  log(`🖼️ [2/3] PNG 렌더 완료 (${pngBuffer ? pngBuffer.length : 0} bytes, ${Date.now() - t1}ms)`);

  // 3. PNG → ESC/POS → 프린터
  const t2 = Date.now();
  await printImage(pngBuffer, printerCfg, log);
  log(`🧾 [3/3] 프린터 전송 완료 (${Date.now() - t2}ms, 총 ${Date.now() - t0}ms)`);
}

module.exports = { printTicket };
