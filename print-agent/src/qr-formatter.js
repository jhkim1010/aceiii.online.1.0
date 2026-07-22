// print-agent/src/qr-formatter.js
// Phase 38 — CodigoMadre QR 라벨 HTML 생성.
// renderHtmlToPng(html, 576) → printImage 파이프라인용 (fiscal 패턴 동일).
// 가격이 null 이면 가격 줄 생략.
'use strict';

const QRCode = require('qrcode');

function escapeHtml(s) {
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/**
 * CodigoMadre QR 라벨 HTML 생성
 *
 * @param {object} payload
 *   payload.qrUrl      {string} QR 코드에 인코딩할 URL
 *   payload.code       {string} CodigoMadre 코드 (예: 'CM-001')
 *   payload.name       {string} 상품명
 *   payload.price      {number|null} 가격 (null 이면 가격 줄 생략)
 *   payload.priceLabel {string} 가격 레이블 (예: 'Minorista')
 * @returns {Promise<string>} HTML 문자열
 */
async function formatQrHtml(payload) {
  const { qrUrl, code, name, price, priceLabel } = payload || {};

  // QR 코드를 data-URI PNG 로 생성 (360px, 여백 1 모듈)
  const qrDataUri = await QRCode.toDataURL(String(qrUrl || ''), {
    margin: 1,
    width: 360,
  });

  // 가격이 null/undefined 이면 가격 줄 전체 생략
  const priceLine =
    price != null
      ? `<div class="price">${priceLabel ? escapeHtml(priceLabel) + ': ' : ''}$ ${Math.round(Number(price) || 0)}</div>`
      : '';

  return `<!DOCTYPE html>
<html><head><meta charset="utf-8"><style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { width: 576px; font-family: monospace; text-align: center; padding: 16px 0; }
  .qr { width: 360px; height: 360px; margin: 0 auto; }
  .code { font-size: 34px; font-weight: bold; margin-top: 12px; }
  .name { font-size: 26px; margin-top: 6px; }
  .price { font-size: 30px; font-weight: bold; margin-top: 10px; }
</style></head><body>
  <img class="qr" src="${qrDataUri}" />
  <div class="code">${escapeHtml(code)}</div>
  <div class="name">${escapeHtml(name)}</div>
  ${priceLine}
</body></html>`;
}

module.exports = { formatQrHtml };
