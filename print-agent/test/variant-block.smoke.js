/**
 * 변형(색×사이즈) 블록 — **정보가 없으면 그리지 않는다** (2026-09-23 사용자 지시).
 *
 * 사용자가 실물 티켓 사진과 함께: 「color unico y talle unica 인 경우에는 테이블 형태로
 * 출력할 이유가 없어.」 종이에 1×1 표가 찍히는데 그 칸의 수량은 이미 품목 줄에 있다.
 * 열감지 종이는 줄마다 돈이다.
 *
 * 백엔드(`print-invoice-items.ts`)는 축이 없을 때 `'—'` 를 채우지만, 매장이 **실제
 * 색/사이즈 행**으로 「Color Único」·「Talle Única」를 만들어 쓴다 —
 * 운영 실측(2026-09-23): 그 이름을 가진 매장 15곳, 다른 변종 없음.
 * 로컬에는 `UNICO` 도 2곳 있어서 악센트·대소문자·접두어를 모두 흡수한다.
 *
 * ★ 이 파일은 «안 그린다» 를 단언한다 — 그래서 ⑤⑥ 대조군이 **필수**다.
 *   진짜 변형까지 안 그리게 되면 손님이 무엇을 샀는지 종이에서 사라진다.
 *
 * 실행: node print-agent/test/variant-block.smoke.js
 */
const assert = require('assert');
const { formatTempTicketHtml, formatInvoiceHtml } = require('../src/formatter');

// CSS 에도 `.vtable` / `.vchip` 이 있다 — 스타일을 걷어내고 **마크업만** 본다.
// (처음 재 볼 때 이걸 안 해서 여섯 경우가 전부 «표 있음» 으로 보였다.)
const cuerpo = (html) => html.replace(/<style[\s\S]*?<\/style>/g, '');

const ticket = (variants, render = formatTempTicketHtml) =>
  cuerpo(
    render({
      ticketType: 'invoiced',
      items: [
        { name: 'TOP REMERA', quantity: 2, unitPrice: 5000, subtotal: 10000, variants },
      ],
      totals: { subtotal: 10000, totalAmount: 10000 },
      invoice: { number: 6, date: '2026-09-23T12:00:00' },
    }),
  );

const hayTabla = (html) => html.includes('class="vtable');
const chips = (html) =>
  (html.match(/<span class="vchip">([^<]*)<\/span>/g) || []).map((s) =>
    s.replace(/<[^>]+>/g, ''),
  );

// ── ① el caso que reportó el usuario ───────────────────────────────────────
for (const [nombre, colors, sizes] of [
  ['Color Único / Talle Única', ['Color Único'], ['Talle Única']],
  ['sin acentos', ['Color Unico'], ['Talle Unica']],
  ['en mayúsculas', ['UNICO'], ['UNICA']],
  ['sin la palabra Color/Talle', ['Único'], ['Única']],
  ['placeholder del backend', ['—'], ['—']],
]) {
  const html = ticket({
    colors,
    sizes,
    matrix: { [colors[0]]: { [sizes[0]]: 2 } },
  });
  assert(!hayTabla(html), `${nombre}: no se dibuja la tabla`);
  assert(chips(html).length === 0, `${nombre}: tampoco chips`);
}

// ── ② un solo eje sin información → chips, no tabla ────────────────────────
// Antes esto salía como tabla con una fila «Color Único». La cantidad tiene que
// seguir siendo correcta: la clave de la matriz es la etiqueta real, no '—'.
const soloTalles = ticket({
  colors: ['Color Único'],
  sizes: ['S', 'M'],
  matrix: { 'Color Único': { S: 1, M: 1 } },
});
assert(!hayTabla(soloTalles), 'un eje: sin tabla');
assert.deepStrictEqual(chips(soloTalles), ['S:1', 'M:1'], 'un eje: chips con cantidad');

const soloColores = ticket({
  colors: ['Rojo', 'Azul'],
  sizes: ['Talle Única'],
  matrix: { Rojo: { 'Talle Única': 1 }, Azul: { 'Talle Única': 1 } },
});
assert(!hayTabla(soloColores), 'un eje (color): sin tabla');
assert.deepStrictEqual(
  chips(soloColores),
  ['Rojo:1', 'Azul:1'],
  'un eje (color): chips con cantidad',
);

// ── ③ CONTROL — las variantes reales se siguen imprimiendo ─────────────────
// Sin esto, "no dibujar nunca" pasaría todo lo de arriba y el cliente perdería
// la información de qué se llevó.
const real = ticket({
  colors: ['Rojo', 'Azul'],
  sizes: ['S', 'M'],
  matrix: { Rojo: { S: 1 }, Azul: { M: 1 } },
});
assert(hayTabla(real), 'control: variantes reales SÍ llevan tabla');
assert(real.includes('Rojo') && real.includes('Azul'), 'control: los colores aparecen');

// Un 1×1 real (Rojo × M) también se imprime: ahí el color y el talle son datos
// que el nombre del producto no dice.
const unoPorUno = ticket({ colors: ['Rojo'], sizes: ['M'], matrix: { Rojo: { M: 2 } } });
assert(hayTabla(unoPorUno), 'control: 1×1 real se mantiene');

// ── ④ el ticket de reimpresión comparte la misma función ───────────────────
const reimpresion = ticket(
  { colors: ['Color Único'], sizes: ['Talle Única'], matrix: { 'Color Único': { 'Talle Única': 2 } } },
  formatInvoiceHtml,
);
assert(!hayTabla(reimpresion), 'reimpresión: misma regla');

console.log('variant-block smoke OK');
