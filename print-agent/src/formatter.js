/**
 * VentaGO — Ticket de Control (Comprobante Interno)
 * HTML 티켓 생성기
 *
 * 출력 파이프라인:
 *   formatInvoiceHtml(data) → HTML 문자열
 *   → Electron offscreen BrowserWindow → PNG Buffer
 *   → ESC/POS 래스터 이미지 → 감열 프린터
 *
 * 80mm 감열지 = 576px @ 203dpi (표준)
 */

// ─── 유틸 ──────────────────────────────────────────────────────────────────────

const formatMoney = (amount) => {
  const n = Number(amount || 0);

  return n.toLocaleString('es-AR', {
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  });
};

// ─── 변형 매트릭스 렌더 (color × size) — invoice + temp ticket 공유 ──────────
//
// 백엔드 (sales-create.service.ts::groupItemsForPrint) 가 동봉한 variants 가 있으면
// 헤더 행 아래에 색×사이즈 표(또는 한 줄 inline) 를 그린다.
// 영수증 폭 (576px) 안에 들어가도록 컬럼 6/9 개 기준으로 폰트 단계적 축소.
const renderVariantBlockShared = (v) => {
  if (!v || !v.matrix) return '';
  const colors = Array.isArray(v.colors) ? v.colors : [];
  const sizes  = Array.isArray(v.sizes)  ? v.sizes  : [];

  // '—' = 백엔드가 한쪽 축이 없을 때 채우는 placeholder.
  const colorIsDummy = colors.length === 1 && colors[0] === '—';
  const sizeIsDummy  = sizes.length  === 1 && sizes[0]  === '—';
  if (colorIsDummy && sizeIsDummy) return '';

  // 한 축만 있는 경우 — chip 한 줄 inline
  if (colorIsDummy) {
    const cells = sizes
      .map((s) => {
        const n = v.matrix['—']?.[s] || 0;

        return n > 0 ? `<span class="vchip">${s}:${n}</span>` : '';
      })
      .filter(Boolean).join('');

    return `
      <tr class="variant-inline-row">
        <td></td>
        <td colspan="3" class="variant-inline-cell">${cells}</td>
      </tr>`;
  }
  if (sizeIsDummy) {
    const cells = colors
      .map((c) => {
        const n = v.matrix[c]?.['—'] || 0;

        return n > 0 ? `<span class="vchip">${c}:${n}</span>` : '';
      })
      .filter(Boolean).join('');

    return `
      <tr class="variant-inline-row">
        <td></td>
        <td colspan="3" class="variant-inline-cell">${cells}</td>
      </tr>`;
  }

  // 두 축 모두 있음 → 매트릭스 표
  const sizeColCount = sizes.length;
  const tableCls = sizeColCount >= 9 ? 'vtable tiny' : (sizeColCount >= 6 ? 'vtable small' : 'vtable');
  const head = `<tr><th class="vth-corner"></th>${sizes
    .map((s) => `<th class="vth">${s}</th>`).join('')}</tr>`;
  const body = colors
    .map((c) => {
      const cells = sizes.map((s) => {
        const n = v.matrix[c]?.[s];

        return `<td class="vtd${n ? '' : ' empty'}">${n ? n : ''}</td>`;
      }).join('');

      return `<tr><th class="vth-row">${c}</th>${cells}</tr>`;
    }).join('');

  return `
      <tr class="variant-table-row">
        <td></td>
        <td colspan="3" class="variant-table-cell">
          <table class="${tableCls}">
            <thead>${head}</thead>
            <tbody>${body}</tbody>
          </table>
        </td>
      </tr>`;
};

// 변형 표 + chip 공통 CSS — invoice / temp ticket style 블록 양쪽에서 동일 사용
const VARIANT_CSS = `
  tr.item-row.has-variants td {
    border-bottom: none;
    background: #fafafa;
  }
  tr.variant-table-row td,
  tr.variant-inline-row td {
    background: #fafafa !important;
    padding: 0 14px 6px 14px !important;
    border-bottom: 1px dotted #cfcfcf !important;
  }
  .variant-inline-cell { padding-left: 8px !important; }
  .vchip {
    display: inline-block;
    margin: 2px 6px 2px 0;
    padding: 1px 8px;
    border: 1px solid #999;
    border-radius: 10px;
    font-size: 15px;
    background: #fff;
    color: #333;
  }
  table.vtable {
    border-collapse: collapse;
    margin: 4px 0 2px 0;
    width: auto;
    background: #fff;
  }
  table.vtable th,
  table.vtable td {
    border: 1px solid #555;
    padding: 3px 8px;
    text-align: center;
    font-size: 16px;
    min-width: 28px;
  }
  table.vtable .vth-corner { background: #1a1a1a; min-width: 60px; }
  table.vtable .vth { background: #333; color: #fff; font-weight: bold; }
  table.vtable .vth-row {
    background: #ececec; color: #1a1a1a;
    text-align: left; font-weight: bold;
    white-space: nowrap; padding-right: 12px;
  }
  table.vtable .vtd { font-weight: bold; color: #111; }
  table.vtable .vtd.empty { color: #bbb; font-weight: normal; background: #f8f8f8; }
  table.vtable.small th, table.vtable.small td {
    font-size: 14px; padding: 2px 5px; min-width: 22px;
  }
  table.vtable.tiny th, table.vtable.tiny td {
    font-size: 12px; padding: 1px 3px; min-width: 18px;
  }
`;

// ─── HTML 티켓 생성 ────────────────────────────────────────────────────────────

/**
 * invoiceData → HTML 문자열
 *
 * @param {object} data
 *   data.store      { name, address, cuit, phone? }
 *   data.invoice    { number, date, copy? }
 *   data.seller     { name }
 *   data.client     { name?, document? }
 *   data.items[]    { code?, name, quantity, unitPrice, subtotal, discount? }
 *   data.discounts[]{ name, amount }
 *   data.recharges[]{ name, amount }
 *   data.totals     { subtotal, discountAmount?, transport?, totalAmount }
 *   data.paymentMethods[] { method, option?, amount, change? }
 *   data.footer     { line1?, line2? }
 */
const formatInvoiceHtml = (data) => {
  // 날짜 / 시간
  const fecha = data.invoice?.date ? new Date(data.invoice.date) : new Date();
  const fechaStr = fecha.toLocaleDateString('es-AR', {
    day: '2-digit', month: '2-digit', year: 'numeric',
  });
  const horaStr = fecha.toLocaleTimeString('es-AR', {
    hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false,
  });

  // 변형 매트릭스 → 영수증 HTML 한 줄(들) 생성.
  // 백엔드 (sales-create.service.ts::groupItemsForPrint) 가 동봉한 variants 가 있으면
  // 헤더 행 아래에 색×사이즈 표를 그린다. 영수증 폭 (576px) 안에 들어가도록:
  //   - color 만 / size 만 → 1줄 inline ("Rojo:2 Azul:3")
  //   - color × size → 표 (헤더=sizes, 행=colors). 컬럼이 8개 초과면 폰트 축소.
  // ⤷ renderVariantBlockShared() 와 동일 로직 — temp ticket 과 공유 위해 추출됨.

  // 상품 행 생성 — 항목별 discount 없음 (전부 소계 아래로).
  // 변형 (color/size) 그룹이면 헤더 행 + 매트릭스 행 한 쌍을 생성.
  const itemRows = (data.items || []).map((item) => {
    const qty      = item.quantity  || 1;
    const price    = item.unitPrice || 0;
    const subtotal = item.subtotal  || qty * price;
    const descMain = item.name      || 'Producto';
    const descCode = item.code      ? `<span class="item-code">[${item.code}]</span> ` : '';
    const variantBlock = renderVariantBlockShared(item.variants);

    return `
      <tr class="item-row${variantBlock ? ' has-variants' : ''}">
        <td class="qty-cell">${qty}</td>
        <td class="desc-cell">${descCode}${descMain}</td>
        <td class="unit-cell">${formatMoney(price)}</td>
        <td class="amount-cell">${formatMoney(subtotal)}</td>
      </tr>${variantBlock}`;
  }).join('');

  // 결제수단 행
  const paymentRows = (data.paymentMethods || []).map((pm) => {
    const label = pm.option ? `${pm.method} (${pm.option})` : pm.method;
    const changeRow = pm.change !== undefined
      ? `<tr class="change-row">
           <td class="pay-label sub">↳ Vuelto</td>
           <td class="pay-amount sub">${formatMoney(pm.change)}</td>
         </tr>`
      : '';

    return `
      <tr class="pay-row">
        <td class="pay-label"><span class="pay-star">★</span> ${label}</td>
        <td class="pay-amount">${formatMoney(pm.amount)}</td>
      </tr>
      ${changeRow}`;
  }).join('');

  // ── 소계 구역 행 구성 ──────────────────────────────────────────────────────
  // 순서: Subtotal → +Recargos → -Descuentos → +Envío → (구분선) → TOTAL
  // 모든 항목별 discount도 여기서 처리

  // 1) Subtotal 행 (항상 표시)
  const subtotalRow = `
    <tr class="sum-row subtotal-line">
      <td class="sum-label">Subtotal</td>
      <td class="sum-amount">${formatMoney(data.totals?.subtotal ?? data.totals?.totalAmount)}</td>
    </tr>`;

  // 2) Recargos (+)
  const recargoRows = (data.recharges || []).map(r => `
    <tr class="sum-row plus">
      <td class="sum-label">+ Recargo — ${r.name}</td>
      <td class="sum-amount">+ ${formatMoney(r.amount)}</td>
    </tr>`).join('');

  // 3) Descuentos globales (-) — 전체 할인
  const descuentoRows = (data.discounts || []).map(d => `
    <tr class="sum-row minus">
      <td class="sum-label">− Descuento — ${d.name}</td>
      <td class="sum-amount">− ${formatMoney(d.amount)}</td>
    </tr>`).join('');

  // 4) Descuentos por ítem (-) — 상품별 할인도 여기로
  const itemDescuentoRows = (data.items || [])
    .filter(i => i.discount && i.discount > 0)
    .map(i => `
      <tr class="sum-row minus">
        <td class="sum-label">− Desc. ${i.name || 'ítem'}</td>
        <td class="sum-amount">− ${formatMoney(i.discount)}</td>
      </tr>`).join('');

  // 5) Envío / transporte (+)
  const envioRow = (data.totals?.transport > 0) ? `
    <tr class="sum-row plus">
      <td class="sum-label">+ Envío</td>
      <td class="sum-amount">+ ${formatMoney(data.totals.transport)}</td>
    </tr>` : '';

  const copyNum = data.invoice?.copy ?? 1;
  const footer1 = data.footer?.line1 || '★ ¡Gracias x elegirnos! ★';
  const footer2 = data.footer?.line2 || 'Cambios solo por falla de fábrica · Lun–Vie';

  return `<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8" />
<style>
  /* ── 기본 리셋 ── */
  * { margin: 0; padding: 0; box-sizing: border-box; }

  /* ── 80mm = 576px @ 203dpi ── */
  body {
    width: 576px;
    background: #ffffff;
    font-family: 'Courier New', 'Lucida Console', monospace;
    font-size: 20px;
    color: #1a1a1a;
    padding: 0;
  }

  /* ── 최상단 배너 ── */
  .banner {
    background: #1a1a1a;
    color: #ffffff;
    text-align: center;
    font-size: 15px;
    letter-spacing: 1px;
    padding: 6px 0;
    font-weight: normal;
  }

  /* ── 매장 헤더 ── */
  .store-header {
    background: #f5f5f5;
    border-bottom: 3px solid #1a1a1a;
    text-align: center;
    padding: 14px 12px 10px;
  }
  .store-name {
    font-size: 28px;
    font-weight: bold;
    letter-spacing: 2px;
    text-transform: uppercase;
    line-height: 1.1;
  }
  .store-sub {
    font-size: 17px;
    color: #444;
    margin-top: 4px;
    line-height: 1.4;
  }
  .store-cuit {
    font-size: 17px;
    font-weight: bold;
    margin-top: 6px;
    letter-spacing: 1px;
  }

  /* ── 티켓 메타 정보 ── */
  .ticket-meta {
    border-bottom: 1px dashed #888;
    padding: 10px 14px 8px;
    font-size: 18px;
    line-height: 1.6;
  }
  .ticket-num {
    text-align: center;
    font-size: 22px;
    font-weight: bold;
    letter-spacing: 2px;
    margin-bottom: 4px;
  }
  .meta-row {
    display: flex;
    justify-content: space-between;
  }
  .meta-label { color: #666; }
  .meta-val   { font-weight: bold; }

  /* ── 상품 테이블 ── */
  .items-section { padding: 0 0 4px; }

  .col-header {
    display: flex;
    background: #1a1a1a;
    color: #fff;
    font-size: 16px;
    font-weight: bold;
    letter-spacing: 0.5px;
    padding: 5px 14px;
  }
  .col-header .c-qty  { width: 36px;  text-align: center; }
  .col-header .c-desc { flex: 1;      padding-left: 8px; }
  .col-header .c-unit { width: 90px;  text-align: right; }
  .col-header .c-amt  { width: 90px;  text-align: right; }

  table.items {
    width: 100%;
    border-collapse: collapse;
  }
  table.items td { vertical-align: top; padding: 5px 0; }

  /* 수량 */
  .qty-cell {
    width: 36px;
    text-align: center;
    font-weight: bold;
    font-size: 20px;
    padding-left: 14px !important;
    color: #333;
  }

  /* 상품명 — word-wrap으로 자동 2줄 */
  .desc-cell {
    padding-left: 8px !important;
    padding-right: 6px !important;
    font-size: 19px;
    line-height: 1.35;
    word-break: break-word;
    /* 긴 이름 2줄 제한: 넘치면 말줄임표 */
    display: -webkit-box;
    -webkit-line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
  }
  .desc-cell.sub {
    font-size: 16px;
    color: #666;
    padding-top: 1px !important;
    -webkit-line-clamp: unset;
  }
  .item-code {
    color: #888;
    font-size: 16px;
  }

  /* 단가 */
  .unit-cell {
    width: 90px;
    text-align: right;
    font-size: 18px;
    color: #555;
    white-space: nowrap;
    padding-right: 6px !important;
  }

  /* 소계 */
  .amount-cell {
    width: 90px;
    text-align: right;
    font-weight: bold;
    font-size: 20px;
    white-space: nowrap;
    padding-right: 14px !important;
  }
  .amount-cell.sub {
    font-size: 16px;
    font-weight: normal;
    color: #c00;
  }

  /* 짝수 행 배경 */
  table.items tr.item-row:nth-child(odd) td {
    background: #fafafa;
  }

  /* ── 변형 표 (color × size) — temp ticket 과 공유 ── */
  ${VARIANT_CSS}

  /* ── 소계 구역 ── */
  .totals-section {
    border-top: 2px dashed #aaa;
    padding: 6px 14px 0;
  }
  table.sum-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 19px;
  }
  table.sum-table td { padding: 4px 0; }

  /* Subtotal 행 — 약간 굵게 */
  .sum-row.subtotal-line .sum-label { color: #333; font-weight: bold; }
  .sum-row.subtotal-line .sum-amount { color: #333; font-weight: bold; }

  /* +Recargo / +Envío — 파란색 */
  .sum-row.plus .sum-label  { color: #1565c0; }
  .sum-row.plus .sum-amount { color: #1565c0; font-weight: bold; }

  /* -Descuento — 빨간색 */
  .sum-row.minus .sum-label  { color: #c62828; }
  .sum-row.minus .sum-amount { color: #c62828; font-weight: bold; }

  /* 공통: 금액 우측 정렬 */
  .sum-amount { text-align: right; white-space: nowrap; width: 120px; }

  /* ── 합계 블록 ── */
  .total-block {
    background: #1a1a1a;
    color: #fff;
    margin: 8px 0 0;
    padding: 10px 14px;
    display: flex;
    justify-content: space-between;
    align-items: center;
  }
  .total-label { font-size: 22px; font-weight: bold; letter-spacing: 1px; }
  .total-amount { font-size: 30px; font-weight: bold; letter-spacing: 1px; }

  /* ── 결제수단 ── */
  .payment-section {
    border-top: 1px dashed #888;
    padding: 8px 14px 4px;
  }
  .payment-title {
    font-size: 15px;
    font-weight: bold;
    color: #888;
    letter-spacing: 1px;
    text-transform: uppercase;
    margin-bottom: 4px;
  }
  table.payments { width: 100%; border-collapse: collapse; font-size: 20px; }
  table.payments td { padding: 3px 0; }
  .pay-star { color: #888; font-size: 14px; }
  .pay-label { font-weight: bold; }
  .pay-label.sub { font-size: 16px; color: #888; font-weight: normal; padding-left: 14px; }
  .pay-amount { text-align: right; font-weight: bold; }
  .pay-amount.sub { font-size: 16px; color: #888; font-weight: normal; }

  /* ── 푸터 ── */
  .footer {
    border-top: 3px solid #1a1a1a;
    margin-top: 10px;
    padding: 10px 14px 14px;
    text-align: center;
  }
  .footer-main {
    font-size: 20px;
    font-weight: bold;
    letter-spacing: 1px;
  }
  .footer-sub {
    font-size: 16px;
    color: #666;
    margin-top: 4px;
    line-height: 1.4;
  }

  /* ── 하단 여백 (용지 절단용) ── */
  .cut-space { height: 40px; }
</style>
</head>
<body>

<!-- 최상단 배너 -->
<div class="banner">DOCUMENTO NO VÁLIDO COMO FACTURA</div>

<!-- 매장 헤더 -->
<div class="store-header">
  <div class="store-name">${data.store?.name || 'TIENDA'}</div>
  ${data.store?.address ? `<div class="store-sub">${data.store.address}</div>` : ''}
  ${data.store?.phone   ? `<div class="store-sub">Tel: ${data.store.phone}</div>` : ''}
  ${data.store?.cuit    ? `<div class="store-cuit">CUIT: ${data.store.cuit}</div>` : ''}
</div>

<!-- 티켓 메타 -->
<div class="ticket-meta">
  <div class="ticket-num">Copia (${copyNum}) : # ${data.invoice?.number || '0'}</div>
  <div class="meta-row">
    <span class="meta-label">Fecha</span>
    <span class="meta-val">${fechaStr}</span>
  </div>
  <div class="meta-row">
    <span class="meta-label">Hora</span>
    <span class="meta-val">${horaStr}</span>
  </div>
  <div class="meta-row">
    <span class="meta-label">Vendedor</span>
    <span class="meta-val">${data.seller?.name || '—'}</span>
  </div>
  ${data.client?.name ? `
  <div class="meta-row">
    <span class="meta-label">Cliente</span>
    <span class="meta-val">${data.client.name}</span>
  </div>` : ''}
  ${data.client?.document ? `
  <div class="meta-row">
    <span class="meta-label">Doc.</span>
    <span class="meta-val">${data.client.document}</span>
  </div>` : ''}
</div>

<!-- 상품 목록 -->
<div class="items-section">
  <div class="col-header">
    <span class="c-qty">Cnt</span>
    <span class="c-desc">Descripcion</span>
    <span class="c-unit">P.Unit</span>
    <span class="c-amt">SubTot</span>
  </div>
  <table class="items">
    <tbody>
      ${itemRows}
    </tbody>
  </table>
</div>

<!-- 소계 구역: Subtotal → +Recargo → -Descuento → +Envío → TOTAL -->
<div class="totals-section">
  <table class="sum-table">
    <tbody>
      ${subtotalRow}
      ${recargoRows}
      ${descuentoRows}
      ${itemDescuentoRows}
      ${envioRow}
    </tbody>
  </table>

  <!-- TOTAL 블록 -->
  <div class="total-block">
    <span class="total-label">TOTAL</span>
    <span class="total-amount">$ ${formatMoney(data.totals?.totalAmount)}</span>
  </div>
</div>

<!-- 결제수단 -->
${(data.paymentMethods || []).length > 0 ? `
<div class="payment-section">
  <div class="payment-title">Forma de Pago</div>
  <table class="payments">
    <tbody>
      ${paymentRows}
    </tbody>
  </table>
</div>` : ''}

<!-- 푸터 -->
<div class="footer">
  <div class="footer-main">${footer1}</div>
  <div class="footer-sub">${footer2}</div>
</div>

<!-- 용지 절단 여백 -->
<div class="cut-space"></div>

</body>
</html>`;
};

// 하위 호환성: 기존 텍스트 모드 formatInvoice 도 유지
// (Electron 없는 환경, 테스트 등에서 사용)
const formatInvoice = (data, width = 48) => {
  // HTML 생성 후 태그 제거한 텍스트 fallback
  // 실제 출력은 formatInvoiceHtml() 사용 권장
  const lines = [];
  lines.push('DOCUMENTO NO VALIDO COMO FACTURA');
  lines.push('');
  lines.push((data.store?.name || 'TIENDA').toUpperCase());
  if (data.store?.address) lines.push(data.store.address);
  if (data.store?.cuit)    lines.push(`CUIT: ${data.store.cuit}`);
  lines.push('-'.repeat(width));

  const fecha = data.invoice?.date ? new Date(data.invoice.date) : new Date();
  lines.push(`Fecha: ${fecha.toLocaleDateString('es-AR')}  Hora: ${fecha.toLocaleTimeString('es-AR')}`);
  lines.push(`Vendedor: ${data.seller?.name || ''}`);
  lines.push('-'.repeat(width));

  for (const item of (data.items || [])) {
    const qty = item.quantity || 1;
    const price = item.unitPrice || 0;
    const subtotal = item.subtotal || qty * price;
    lines.push(`${qty}  ${item.name || 'Producto'}  ${price}  ${subtotal}`);
  }

  lines.push('-'.repeat(width));
  lines.push(`TOTAL: ${formatMoney(data.totals?.totalAmount)} pesos`);
  lines.push('');

  return lines;
};

// ─── 임시(견적) 티켓 HTML 생성 ─────────────────────────────────────────────
//
// formatInvoiceHtml과 동일한 80mm(576px) 레이아웃을 재사용하되,
// 1) 최상단 배너를 'TICKET PROVISORIO'로 교체
// 2) 판매번호(`Copia (N) : # ...`) 행 제거
// 3) Forma de Pago 섹션 전체 생략 (결제 전이므로 의미 없음)
// 4) 하단 푸터를 'Documento de cortesía' 문구로 교체
//
// @param {object} data — formatInvoiceHtml과 동일한 스키마, paymentMethods/invoice.number 무시

const formatTempTicketHtml = (data) => {
  const fecha = new Date();
  const fechaStr = fecha.toLocaleDateString('es-AR', {
    day: '2-digit', month: '2-digit', year: 'numeric',
  });
  const horaStr = fecha.toLocaleTimeString('es-AR', {
    hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false,
  });

  // 상품 행 — formatInvoiceHtml과 동일한 마크업 + variants 매트릭스 재사용
  const itemRows = (data.items || []).map((item) => {
    const qty      = item.quantity  || 1;
    const price    = item.unitPrice || 0;
    const subtotal = item.subtotal  || qty * price;
    const descMain = item.name      || 'Producto';
    const descCode = item.code      ? `<span class="item-code">[${item.code}]</span> ` : '';
    const variantBlock = renderVariantBlockShared(item.variants);

    return `
      <tr class="item-row${variantBlock ? ' has-variants' : ''}">
        <td class="qty-cell">${qty}</td>
        <td class="desc-cell">${descCode}${descMain}</td>
        <td class="unit-cell">${formatMoney(price)}</td>
        <td class="amount-cell">${formatMoney(subtotal)}</td>
      </tr>${variantBlock}`;
  }).join('');

  // 소계 / 가감 행
  const subtotalRow = `
    <tr class="sum-row subtotal-line">
      <td class="sum-label">Subtotal</td>
      <td class="sum-amount">${formatMoney(data.totals?.subtotal ?? data.totals?.totalAmount)}</td>
    </tr>`;

  const recargoRows = (data.recharges || []).map(r => `
    <tr class="sum-row plus">
      <td class="sum-label">+ Recargo — ${r.name}</td>
      <td class="sum-amount">+ ${formatMoney(r.amount)}</td>
    </tr>`).join('');

  const descuentoRows = (data.discounts || []).map(d => `
    <tr class="sum-row minus">
      <td class="sum-label">− Descuento — ${d.name}</td>
      <td class="sum-amount">− ${formatMoney(d.amount)}</td>
    </tr>`).join('');

  const envioRow = (data.totals?.transport > 0) ? `
    <tr class="sum-row plus">
      <td class="sum-label">+ Envío</td>
      <td class="sum-amount">+ ${formatMoney(data.totals.transport)}</td>
    </tr>` : '';

  // Forma de Pago 행 — invoiced 티켓에서만 표시 (temp 견적은 결제 전이므로 생략)
  const paymentRows = (data.paymentMethods || []).map((pm) => {
    const label = pm.option ? `${pm.method} (${pm.option})` : pm.method;

    return `
      <tr class="pay-row">
        <td class="pay-label"><span class="pay-star">★</span> ${label}</td>
        <td class="pay-amount">${formatMoney(pm.amount)}</td>
      </tr>`;
  }).join('');

  const paymentSection = (data.ticketType === 'invoiced' && (data.paymentMethods || []).length > 0) ? `
<div class="payment-section">
  <div class="payment-title">Forma de Pago</div>
  <table class="payments">
    <tbody>
      ${paymentRows}
    </tbody>
  </table>
</div>` : '';

  return `<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8" />
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    width: 576px;
    background: #ffffff;
    font-family: 'Courier New', 'Lucida Console', monospace;
    font-size: 20px;
    color: #1a1a1a;
  }
  .banner {
    background: #1a1a1a;
    color: #ffffff;
    text-align: center;
    font-size: 15px;
    letter-spacing: 1px;
    padding: 6px 0;
  }
  .store-header {
    background: #f5f5f5;
    border-bottom: 3px solid #1a1a1a;
    text-align: center;
    padding: 14px 12px 10px;
  }
  .store-name { font-size: 28px; font-weight: bold; letter-spacing: 2px; text-transform: uppercase; line-height: 1.1; }
  .store-sub  { font-size: 17px; color: #444; margin-top: 4px; line-height: 1.4; }
  .store-cuit { font-size: 17px; font-weight: bold; margin-top: 6px; letter-spacing: 1px; }

  .ticket-meta {
    border-bottom: 1px dashed #888;
    padding: 10px 14px 8px;
    font-size: 18px;
    line-height: 1.6;
  }
  .presupuesto-title {
    text-align: center;
    font-size: 20px;
    font-weight: bold;
    letter-spacing: 1px;
    margin-bottom: 4px;
  }
  .meta-row { display: flex; justify-content: space-between; }
  .meta-label { color: #666; }
  .meta-val   { font-weight: bold; }

  .items-section { padding: 0 0 4px; }
  .col-header {
    display: flex;
    background: #1a1a1a;
    color: #fff;
    font-size: 16px;
    font-weight: bold;
    letter-spacing: 0.5px;
    padding: 5px 14px;
  }
  .col-header .c-qty  { width: 36px;  text-align: center; }
  .col-header .c-desc { flex: 1;      padding-left: 8px; }
  .col-header .c-unit { width: 90px;  text-align: right; }
  .col-header .c-amt  { width: 90px;  text-align: right; }

  table.items { width: 100%; border-collapse: collapse; }
  table.items td { vertical-align: top; padding: 5px 0; }
  .qty-cell { width: 36px; text-align: center; font-weight: bold; font-size: 20px; padding-left: 14px !important; color: #333; }
  .desc-cell {
    padding-left: 8px !important;
    padding-right: 6px !important;
    font-size: 19px;
    line-height: 1.35;
    word-break: break-word;
    display: -webkit-box;
    -webkit-line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
  }
  .item-code { color: #888; font-size: 16px; }
  .unit-cell { width: 90px; text-align: right; font-size: 18px; color: #555; white-space: nowrap; padding-right: 6px !important; }
  .amount-cell { width: 90px; text-align: right; font-weight: bold; font-size: 20px; white-space: nowrap; padding-right: 14px !important; }
  table.items tr.item-row:nth-child(odd) td { background: #fafafa; }

  /* variant matrix — invoice 와 공유 */
  ${VARIANT_CSS}

  .totals-section { border-top: 2px dashed #aaa; padding: 6px 14px 0; }
  table.sum-table { width: 100%; border-collapse: collapse; font-size: 19px; }
  table.sum-table td { padding: 4px 0; }
  .sum-row.subtotal-line .sum-label  { color: #333; font-weight: bold; }
  .sum-row.subtotal-line .sum-amount { color: #333; font-weight: bold; }
  .sum-row.plus  .sum-label  { color: #1565c0; }
  .sum-row.plus  .sum-amount { color: #1565c0; font-weight: bold; }
  .sum-row.minus .sum-label  { color: #c62828; }
  .sum-row.minus .sum-amount { color: #c62828; font-weight: bold; }
  .sum-amount { text-align: right; white-space: nowrap; width: 120px; }

  .total-block {
    background: #1a1a1a;
    color: #fff;
    margin: 8px 0 0;
    padding: 10px 14px;
    display: flex;
    justify-content: space-between;
    align-items: center;
  }
  .total-label  { font-size: 22px; font-weight: bold; letter-spacing: 1px; }
  .total-amount { font-size: 30px; font-weight: bold; letter-spacing: 1px; }

  .payment-section {
    margin-top: 8px;
    padding: 8px 14px 6px;
    border-top: 1px dashed #888;
  }
  .payment-title {
    font-size: 17px;
    font-weight: bold;
    text-align: center;
    letter-spacing: 1px;
    color: #333;
    margin-bottom: 4px;
  }
  table.payments { width: 100%; border-collapse: collapse; font-size: 19px; }
  table.payments td { padding: 3px 0; }
  .pay-label { color: #111; }
  .pay-star { color: #1565c0; margin-right: 4px; }
  .pay-amount { text-align: right; font-weight: bold; white-space: nowrap; }

  .footer {
    border-top: 3px solid #1a1a1a;
    margin-top: 10px;
    padding: 10px 14px 14px;
    text-align: center;
  }
  .footer-main { font-size: 20px; font-weight: bold; letter-spacing: 1px; }
  .footer-sub  { font-size: 16px; color: #666; margin-top: 4px; line-height: 1.4; }
  .cut-space { height: 40px; }
</style>
</head>
<body>

<!-- 최상단 배너 — ticketType 에 따라 분기 -->
<!-- 'invoiced' = 확정된 판매 (Generar Venta + autoImpTiq 플로우) -->
<!-- 'temp' 또는 생략 = 아직 이루어지지 않은 견적 (Imprimir Temp 플로우) -->
${data.ticketType === 'invoiced'
    ? '<div class="banner">COMPROBANTE DE VENTA — NO VÁLIDO COMO FACTURA</div>'
    : '<div class="banner">PRESUPUESTO TEMPORAL</div>'}

<!-- 매장 헤더 -->
<div class="store-header">
  <div class="store-name">${data.store?.name || 'TIENDA'}</div>
  ${data.store?.address ? `<div class="store-sub">${data.store.address}</div>` : ''}
  ${data.store?.phone   ? `<div class="store-sub">Tel: ${data.store.phone}</div>` : ''}
  ${data.store?.cuit    ? `<div class="store-cuit">CUIT: ${data.store.cuit}</div>` : ''}
</div>

<!-- 티켓 메타 — ticketType 에 따라 판매번호 노출 여부 결정 -->
<div class="ticket-meta">
  ${data.ticketType === 'invoiced' && (data.invoice?.number || data.invoice?.id)
    ? `<div class="presupuesto-title">Venta # ${data.invoice.number || data.invoice.id} — ${fechaStr} ${horaStr}</div>`
    : `<div class="presupuesto-title">Presupuesto — ${fechaStr} ${horaStr}</div>`}
  <div class="meta-row">
    <span class="meta-label">Vendedor</span>
    <span class="meta-val">${data.invoice?.seller || data.seller?.name || '—'}</span>
  </div>
  ${data.invoice?.client ? `
  <div class="meta-row">
    <span class="meta-label">Cliente</span>
    <span class="meta-val">${data.invoice.client}</span>
  </div>` : ''}
</div>

<!-- 상품 목록 -->
<div class="items-section">
  <div class="col-header">
    <span class="c-qty">Cnt</span>
    <span class="c-desc">Descripcion</span>
    <span class="c-unit">P.Unit</span>
    <span class="c-amt">SubTot</span>
  </div>
  <table class="items">
    <tbody>
      ${itemRows}
    </tbody>
  </table>
</div>

<!-- 소계 구역 (결제수단 섹션 없음) -->
<div class="totals-section">
  <table class="sum-table">
    <tbody>
      ${subtotalRow}
      ${recargoRows}
      ${descuentoRows}
      ${envioRow}
    </tbody>
  </table>

  <div class="total-block">
    <span class="total-label">TOTAL</span>
    <span class="total-amount">$ ${formatMoney(data.totals?.totalAmount)}</span>
  </div>
</div>

${paymentSection}

<!-- 푸터 -->
<div class="footer">
  ${data.ticketType === 'invoiced'
    ? '<div class="footer-main">¡Gracias por su compra!</div><div class="footer-sub">Conserve este comprobante</div>'
    : '<div class="footer-main">Documento de cortesía</div><div class="footer-sub">No válido como comprobante</div>'}
</div>

<div class="cut-space"></div>

</body>
</html>`;
};

module.exports = { formatInvoiceHtml, formatInvoice, formatTempTicketHtml };
