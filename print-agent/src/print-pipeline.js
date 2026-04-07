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
 */
async function printTicket(data, printerCfg) {
  // 1. HTML 생성
  const html = formatInvoiceHtml(data);

  // 2. HTML → PNG (Electron offscreen)
  //    80mm @ 203dpi = 576px
  const pngBuffer = await renderHtmlToPng(html, 576);

  // 3. PNG → ESC/POS → 프린터
  await printImage(pngBuffer, printerCfg);
}

module.exports = { printTicket };
