// print-agent/src/fiscal-formatter.js
// AFIP Comprobante Fiscal HTML 포맷터
'use strict';

const { formatInvoiceHtml } = require('./formatter');

/**
 * AFIP Comprobante Fiscal HTML 생성
 *
 * @param {object} data  컨트롤 티켓 데이터 + AFIP 추가 필드
 *   data.afip {
 *     tipo:       'Factura B'
 *     puntoVenta: '00005'
 *     numero:     '00000042'
 *     cae:        '12345678901234'
 *     vtoCae:     '2026-04-16'
 *     qrUrl:      'https://www.afip.gob.ar/fe/qr/?p=...'
 *   }
 * @returns {string} HTML 문자열
 */
const formatFiscalHtml = (data) => {
  const afip = data.afip || {};

  // 기본 컨트롤 티켓 HTML 생성
  const baseHtml = formatInvoiceHtml({
    ...data,
    _fiscalBanner: afip.tipo || 'Comprobante Fiscal',
  });

  // Vto. CAE 포맷
  let vtoCaeStr = '—';

  if (afip.vtoCae) {
    try {
      const d = new Date(afip.vtoCae);

      if (!isNaN(d.getTime())) {
        vtoCaeStr = d.toLocaleDateString('es-AR', {
          day: '2-digit', month: '2-digit', year: 'numeric',
        });
      }
    } catch (_e) {
      vtoCaeStr = String(afip.vtoCae);
    }
  }

  // AFIP 블록 HTML
  const afipBlock = `
    <div class="afip-section">
      <div class="afip-title">COMPROBANTE ELECTRÓNICO AFIP</div>
      <table class="afip-table">
        <tr>
          <td class="afip-label">Tipo</td>
          <td class="afip-val">${afip.tipo || '—'}</td>
        </tr>
        <tr>
          <td class="afip-label">Pto. Venta</td>
          <td class="afip-val">${afip.puntoVenta || '—'}</td>
        </tr>
        <tr>
          <td class="afip-label">Número</td>
          <td class="afip-val">${afip.numero || '—'}</td>
        </tr>
        <tr>
          <td class="afip-label">CAE</td>
          <td class="afip-val afip-cae">${afip.cae || '—'}</td>
        </tr>
        <tr>
          <td class="afip-label">Vto. CAE</td>
          <td class="afip-val">${vtoCaeStr}</td>
        </tr>
      </table>
      ${afip.qrUrl ? `
      <div class="afip-qr-url">
        <div class="afip-qr-label">Verificar en AFIP:</div>
        <div class="afip-qr-text">${afip.qrUrl}</div>
      </div>` : ''}
    </div>`;

  const afipCss = `
    <style>
      .afip-section {
        border-top: 3px solid #1a1a1a;
        padding: 10px 14px 8px;
        margin-top: 4px;
      }
      .afip-title {
        font-size: 14px;
        font-weight: bold;
        letter-spacing: 1px;
        text-transform: uppercase;
        color: #888;
        text-align: center;
        margin-bottom: 6px;
      }
      table.afip-table { width: 100%; border-collapse: collapse; font-size: 18px; }
      table.afip-table td { padding: 3px 0; }
      .afip-label { color: #666; width: 100px; }
      .afip-val   { font-weight: bold; }
      .afip-cae   { font-size: 16px; letter-spacing: 1px; }
      .afip-qr-url {
        margin-top: 8px;
        padding: 6px 0;
        border-top: 1px dashed #ccc;
      }
      .afip-qr-label { font-size: 14px; color: #888; }
      .afip-qr-text  {
        font-size: 14px;
        word-break: break-all;
        color: #333;
        margin-top: 2px;
      }
    </style>`;

  // baseHtml의 </body> 직전에 AFIP 블록 + CSS 삽입
  // 배너 텍스트도 AFIP 타입으로 교체
  let html = baseHtml;

  if (html.includes('</body>')) {
    html = html.replace('</body>', `${afipCss}${afipBlock}</body>`);
  } else {
    html = html + afipCss + afipBlock;
  }

  html = html.replace(
    'DOCUMENTO NO VÁLIDO COMO FACTURA',
    (afip.tipo || 'Comprobante Fiscal').toUpperCase()
  );

  return html;
};

module.exports = { formatFiscalHtml };
