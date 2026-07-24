// print-agent/src/fiscal-formatter.js
// AFIP Comprobante Fiscal HTML 포맷터 (Phase 57 W1)
//
// D-01/D-02/D-03: el backend (buildFactura) decide TODAS las reglas AFIP y envía
// la shape `factura` estructurada; el print-agent SOLO renderiza — nunca re-deriva
// letra/IVA. El QR se genera aquí como imagen escaneable (QRCode.toDataURL), no como
// texto de URL. Documento HTML standalone (mismo pipeline HTML→PNG→ESC/POS, Phase 11).
'use strict';

const QRCode = require('qrcode');

/**
 * HTML 특수문자 이스케이프 (T-57-04: injection 방지).
 * 텍스트 필드는 전부 interpolar 전에 escapeHtml 을 통과시킨다.
 * qrUrl 은 QRCode.toDataURL 내부로만 들어가고 절대 innerHTML/href 로 쓰지 않는다.
 *
 * @param {*} s
 * @returns {string}
 */
function escapeHtml(s) {
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/**
 * 금액 포맷 (es-AR, 2 decimales). 유효하지 않으면 '0,00'.
 *
 * @param {*} n
 * @returns {string}
 */
function money(n) {
  const num = Number(n);

  if (!isFinite(num)) {
    return '0,00';
  }

  // 전자세금계산서(factura electrónica)는 법정 표기대로 소수점 2자리 유지
  return num.toLocaleString('es-AR', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
}

/**
 * 날짜 포맷 (es-AR dd/mm/yyyy). 파싱 실패 시 원본 문자열 반환.
 *
 * @param {*} value
 * @returns {string}
 */
function formatDate(value) {
  if (!value) {
    return '—';
  }

  try {
    const d = new Date(value);

    if (!isNaN(d.getTime())) {
      return d.toLocaleDateString('es-AR', {
        day: '2-digit', month: '2-digit', year: 'numeric',
      });
    }
  } catch (_e) {
    // 파싱 실패는 아래 원본 반환으로 폴백
  }

  return String(value);
}

/**
 * AFIP Comprobante Fiscal HTML 생성 (async — QRCode.toDataURL 이 async).
 *
 * @param {object} factura  backend buildFactura 의 shape D-02:
 *   {
 *     letra:'A'|'B'|'M', cod:'NN', number, fecha?,
 *     emisor:{razonSocial,cuit,domicilio,condIva,iibb,inicioAct},
 *     receptor: {tipo:'identificado',razonSocial,cuit,condIva,domicilio}
 *             | {tipo:'consumidorFinal',doc?},
 *     items:[{cant,desc,pUnit,subtotal}],
 *     neto, iva21, total, ivaDiscrim:boolean,
 *     cae, caeVto, qrUrl
 *   }
 * @returns {Promise<string>} HTML 문자열
 */
async function formatFiscalHtml(factura) {
  const f = factura || {};
  const emisor = f.emisor || {};
  const receptor = f.receptor || {};

  // QR RG 4892 를 data-URI PNG 로 생성 (escaneable, 360px). qrUrl 은 여기 이외로 절대 노출 X.
  const qrDataUri = await QRCode.toDataURL(String(f.qrUrl || ''), {
    margin: 1,
    width: 360,
  });

  // ── 1. Letra box + COD ─────────────────────────────────────────────
  const letra = escapeHtml(f.letra || '');
  const cod = escapeHtml(f.cod || '');

  // ── 2. N° comprobante + fecha ─────────────────────────────────────
  const numero = escapeHtml(f.number || '');
  const fecha = formatDate(f.fecha || new Date());
  // comprobante 제목 — CoolSyncro 감열 참조("FACTURA A/B/M"). NC/ND 는 백엔드 확장 시 title 로 대체.
  const titulo = f.letra ? `FACTURA ${escapeHtml(f.letra)}` : 'COMPROBANTE';

  // ── 3. EMISOR ─────────────────────────────────────────────────────
  const emisorHtml = `
    ${emisor.nombreFantasia ? `<div class="fantasia">${escapeHtml(emisor.nombreFantasia)}</div>` : ''}
    <div class="razon">${escapeHtml(emisor.razonSocial || '')}</div>
    <div class="line"><span class="k">CUIT:</span> ${escapeHtml(emisor.cuit || '')}</div>
    ${emisor.domicilio ? `<div class="line">${escapeHtml(emisor.domicilio)}</div>` : ''}
    <div class="line"><span class="k">Cond. IVA:</span> ${escapeHtml(emisor.condIva || '')}</div>
    ${emisor.iibb ? `<div class="line"><span class="k">IIBB:</span> ${escapeHtml(emisor.iibb)}</div>` : ''}
    ${emisor.inicioAct ? `<div class="line"><span class="k">Inicio act.:</span> ${escapeHtml(emisor.inicioAct)}</div>` : ''}`;

  // ── 4. RECEPTOR (A/M identidad completa vs B Consumidor Final) ─────
  let receptorHtml;

  if (receptor.tipo === 'identificado') {
    receptorHtml = `
      <div class="line"><span class="k">Cliente:</span> ${escapeHtml(receptor.razonSocial || '-')}</div>
      ${receptor.cuit ? `<div class="line"><span class="k">CUIT:</span> ${escapeHtml(receptor.cuit)}</div>` : ''}
      <div class="line"><span class="k">Cond. IVA:</span> ${escapeHtml(receptor.condIva || '-')}</div>
      ${receptor.domicilio ? `<div class="line"><span class="k">Domicilio:</span> ${escapeHtml(receptor.domicilio)}</div>` : ''}`;
  } else {
    receptorHtml = `
      <div class="line cf">Consumidor Final</div>
      ${receptor.doc ? `<div class="line"><span class="k">Doc:</span> ${escapeHtml(receptor.doc)}</div>` : ''}`;
  }

  // ── 5. Ítems — stacked 2줄(설명 줄 + "cant x pUnit ... subtotal" 줄) ────────
  // 큰 폰트에서 표 4열이 80mm 폭에 안 들어가므로 CoolSyncro 감열처럼 품목당 2줄로 쌓는다.
  const itemsRows = (Array.isArray(f.items) ? f.items : [])
    .map((it) => `
      <div class="item">
        <div class="idesc">${escapeHtml(it.desc)}</div>
        <div class="iline"><span>${escapeHtml(it.cant)} x ${money(it.pUnit)}</span><span class="r">${money(it.subtotal)}</span></div>
      </div>`)
    .join('');

  // ── 6. IVA 21% discriminado — SOLO A/M (factura.ivaDiscrim) ───────
  const ivaBlock = f.ivaDiscrim
    ? `
      <div class="iline sub"><span>Subtotal</span><span class="r">${money(f.neto)}</span></div>
      <div class="iline sub"><span>IVA 21%</span><span class="r">${money(f.iva21)}</span></div>`
    : '';

  // ── 7-8. TOTAL + CAE ──────────────────────────────────────────────
  const totalStr = money(f.total);
  const cae = escapeHtml(f.cae || '');
  const caeVtoStr = formatDate(f.caeVto);

  return `<!DOCTYPE html>
<html><head><meta charset="utf-8"><style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  /* 감열 이진화(renderer-engine binarize threshold 128) 후에도 획이 끊기지 않도록
     본문 전체를 굵게 + Courier New — formatter.js(컨트롤 티켓) 흐림수정과 동일 처리. */
  /* 폰트 ~50% 확대(2026-07-24). 좁은 80mm 폭이라 긴 줄은 자연 줄바꿈(2줄+) 허용.
     품목은 표 대신 stacked 2줄(설명 줄 + 수량×단가/소계 줄) — 큰 폰트에서도 안 잘림. */
  body { width: 576px; font-family: 'Courier New', 'Lucida Console', monospace; font-weight: bold; color: #000; padding: 12px 16px; word-break: break-word; }
  .letrabox {
    border: 4px solid #000;
    width: 104px; height: 88px;
    margin: 0 auto 4px;
    display: flex; align-items: center; justify-content: center;
    flex-direction: column;
  }
  .letra { font-size: 60px; font-weight: bold; line-height: 1; }
  .cod { text-align: center; font-size: 27px; font-weight: bold; margin-bottom: 8px; }
  .doc-meta { text-align: center; font-size: 30px; font-weight: bold; margin-bottom: 8px; }
  .doc-meta .nro { font-size: 27px; font-weight: bold; margin-top: 2px; }
  .doc-meta .fecha { font-size: 24px; margin-top: 2px; }
  .sect {
    border-top: 2px solid #000;
    padding: 8px 0 4px;
    margin-top: 6px;
  }
  .sect-title {
    font-size: 24px; font-weight: bold; text-transform: uppercase;
    letter-spacing: 1px; margin-bottom: 4px;
  }
  .fantasia { font-size: 36px; font-weight: bold; margin-bottom: 2px; }
  .razon { font-size: 30px; font-weight: bold; margin-bottom: 2px; }
  .line { font-size: 27px; margin: 4px 0; }
  .line .k { color: #000; }
  .line.cf { font-size: 28px; font-weight: bold; }
  /* 품목 stacked 레이아웃 */
  .items { margin-top: 6px; }
  .item { margin: 8px 0; }
  .idesc { font-size: 26px; margin-bottom: 2px; }
  .iline { display: flex; justify-content: space-between; gap: 10px; font-size: 26px; }
  .iline .r { text-align: right; white-space: nowrap; }
  .iline.sub { font-weight: bold; margin-top: 4px; }
  .total {
    border-top: 2px solid #000; margin-top: 8px; padding-top: 8px;
    text-align: right; font-size: 39px; font-weight: bold;
  }
  .cae-block { border-top: 2px solid #000; margin-top: 8px; padding-top: 8px; }
  .cae-block .cae-num { font-size: 30px; font-weight: bold; letter-spacing: 1px; }
  .qr-wrap { text-align: center; margin-top: 12px; }
  .qr { width: 320px; height: 320px; margin: 0 auto; }
  .leyenda {
    text-align: center; font-size: 24px; font-weight: bold; margin-top: 10px;
  }
</style></head><body>

  <div class="letrabox"><div class="letra">${letra}</div></div>
  <div class="cod">COD. ${cod}</div>

  <div class="doc-meta">
    ${titulo}
    <div class="nro">N° ${numero}</div>
    <div class="fecha">${fecha}</div>
  </div>

  <div class="sect">
    ${emisorHtml}
  </div>

  <div class="sect">
    <div class="sect-title">Receptor</div>
    ${receptorHtml}
  </div>

  <div class="sect">
    <div class="items">
      ${itemsRows}
      ${ivaBlock}
    </div>
  </div>

  <div class="total">TOTAL: ${totalStr}</div>

  <div class="cae-block">
    <div class="line"><span class="k">CAE N°:</span> <span class="cae-num">${cae}</span></div>
    <div class="line"><span class="k">Vencimiento CAE:</span> ${caeVtoStr}</div>
  </div>

  <div class="qr-wrap">
    <img class="qr" src="${qrDataUri}" />
  </div>

  <div class="leyenda">Comprobante autorizado — AFIP/ARCA</div>

</body></html>`;
}

module.exports = { formatFiscalHtml };
