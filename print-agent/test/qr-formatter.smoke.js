const assert = require('assert');
const { formatQrHtml } = require('../src/qr-formatter');

(async () => {
  const html = await formatQrHtml({
    qrUrl: 'https://ventago.coolsistema.com/m/stock?s=6&p=10',
    code: 'CM-001',
    name: 'Remera',
    price: 1500,
    priceLabel: 'Minorista',
  });

  assert(typeof html === 'string', 'html must be string');
  assert(html.includes('data:image'), 'QR img data-uri present');
  assert(html.includes('CM-001'), 'code present');
  assert(html.includes('Remera'), 'name present');
  assert(html.includes('1500'), 'price present');
  assert(html.includes('Minorista'), 'priceLabel present');

  // 가격 null 이면 가격 줄 생략 확인
  const noPrice = await formatQrHtml({ qrUrl: 'x', code: 'C', name: 'N', price: null, priceLabel: 'X' });
  assert(!noPrice.includes('class="price"'), 'price line omitted when null');

  const esc = await formatQrHtml({ qrUrl: 'x', code: 'A&B', name: '<b>x</b>', price: 1, priceLabel: 'P' });
  assert(esc.includes('A&amp;B'), 'code amp escaped');
  assert(esc.includes('&lt;b&gt;'), 'name angle-brackets escaped');
  assert(!esc.includes('<b>x</b>'), 'raw tag must not appear');

  console.log('qr-formatter smoke OK');
})().catch((e) => { console.error(e); process.exit(1); });
