/**
 * formatQrLabel 단위 테스트 — QR 배치 델타 라벨(1:3 좌우 분할)
 * 실행: node test/qr-label.test.js
 *
 * 검증 대상 (Phase 38 D-8/D-9/D-10, Phase 37 파서 계약):
 *  - QR 인코딩 값이 입력 qrUrl 과 byte-identical (딥링크 /m/stock?s=&p= 훼손 없음)
 *  - 좌 1/4 QR / 우 3/4 이름+가격의 1:3 좌표 배치
 *  - layout.mode='doble' → 같은 상품 2장 (^BQN 2회, 이름 2회)
 *  - layout 수치(widthMm/heightMm/qrModule/splitRatio/fontSize) 가 ZPL 에 반영
 *  - sanitize (^,~ 제거) / 긴 이름 줄바꿈
 */
const assert = require('assert');
const { formatQrLabel } = require('../src/zpl-formatter');

let passed = 0;
function ok(name, cond) {
  assert.ok(cond, name);
  passed += 1;
  console.log('  ✓', name);
}

console.log('formatQrLabel — QR 배치 델타 라벨 (1:3)\n');

// ── 기본 입력 (Phase 37 딥링크 QR) ────────────────────────────────────────
const qrUrl = 'https://ventago.coolsistema.com/m/stock?s=6&p=1234';
const base = {
  qrUrl,
  name: 'REMERA OVERSIZE NEGRA',
  price: 12999,
  priceLabel: 'Minorista',
};

// A) QR 페이로드 = qrUrl (byte-identical, 딥링크 훼손 없음)
const zplA = formatQrLabel(base);
ok('A: ^BQN QR 명령 존재', /\^BQN/.test(zplA));
ok('A: QR 인코딩 = qrUrl byte-identical', zplA.includes(`^FDQA,${qrUrl}^FS`));
ok('A: 시작/종료 프레임', zplA.startsWith('^XA') && zplA.trim().endsWith('^XZ'));

// B) layout 수치 반영 — 기본 50x25mm → ^PW400 / ^LL200
ok('B: widthMm=50 → ^PW400', /\^PW400\b/.test(zplA));
ok('B: heightMm=25 → ^LL200', /\^LL200\b/.test(zplA));
ok('B: qrModule 기본 4 → ^BQN,2,4', /\^BQN,2,4\^FDQA,/.test(zplA));

// C) 우 패널 내용 — 이름(^A0N) + `${priceLabel}: ${price}`
ok('C: 이름 ^A0N 폰트 출력', /\^A0N,\d+,\d+\^FDREMERA/.test(zplA));
ok('C: 가격줄 priceLabel: $price', /\^FDMinorista: \$12\.999,00\^FS/.test(zplA));

// D) 1:3 좌우 배치 — QR 은 좌측(x < region*splitRatio), 이름은 우측(x >= split)
const region = 400;
const splitRatio = 0.25;
const splitX = Math.round(region * splitRatio);
const qrLine = zplA.split('\n').find((l) => /\^BQN/.test(l));
const nameLine = zplA.split('\n').find((l) => /\^FDREMERA/.test(l));
const xOf = (l) => parseInt(l.match(/\^FO(\d+),/)[1], 10);
ok('D: QR 은 좌 1/4 (x < split)', xOf(qrLine) < splitX);
ok('D: 이름은 우 3/4 (x >= split)', xOf(nameLine) >= splitX);

// E) layout 수치 변경 반영 — qrModule/fontSize/splitRatio/치수
const zplE = formatQrLabel({
  ...base,
  layout: { widthMm: 100, heightMm: 50, qrModule: 8, splitRatio: 0.5, fontSize: 30 },
});
ok('E: widthMm=100 → ^PW800', /\^PW800\b/.test(zplE));
ok('E: heightMm=50 → ^LL400', /\^LL400\b/.test(zplE));
ok('E: qrModule=8 → ^BQN,2,8', /\^BQN,2,8\^FDQA,/.test(zplE));
ok('E: fontSize=30 → 이름 ^A0N,30,30', /\^A0N,30,30\^FDREMERA/.test(zplE));
const splitXe = Math.round(800 * 0.5);
const nameLineE = zplE.split('\n').find((l) => /\^FDREMERA/.test(l));
ok('E: splitRatio=0.5 → 이름 x >= 400', xOf(nameLineE) >= splitXe);

// F) doble — 같은 상품 2장 (^BQN 2회, 이름 2회, 미디어 폭 2배)
const zplF = formatQrLabel({ ...base, layout: { mode: 'doble' } });
ok('F: doble → ^BQN 2회', (zplF.match(/\^BQN/g) || []).length === 2);
ok('F: doble → 이름 2회', (zplF.match(/\^FDREMERA/g) || []).length === 2);
ok('F: doble → 미디어 폭 2배 ^PW800', /\^PW800\b/.test(zplF));
ok('F: doble → 두 QR 모두 qrUrl byte-identical', (zplF.match(new RegExp(`\\^FDQA,${qrUrl.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\^FS`, 'g')) || []).length === 2);
// 오른쪽 복제본은 offsetX=region 만큼 이동
const qrLinesF = zplF.split('\n').filter((l) => /\^BQN/.test(l));
ok('F: 오른쪽 복제본 offsetX 적용', xOf(qrLinesF[1]) > xOf(qrLinesF[0]));

// G) simple 기본 — 블록 1회
const zplG = formatQrLabel({ ...base, layout: { mode: 'simple' } });
ok('G: simple → ^BQN 1회', (zplG.match(/\^BQN/g) || []).length === 1);
ok('G: 미지정 → simple (블록 1회)', (zplA.match(/\^BQN/g) || []).length === 1);

// H) sanitize — 이름의 ^ / ~ 제거로 ZPL 무결
const zplH = formatQrLabel({ ...base, name: 'CARGO ^RARO~ AZUL' });
ok('H: sanitize (^,~ 제거)', /CARGO RARO AZUL/.test(zplH) && !/CARGO \^RARO~/.test(zplH));

// I) 줄바꿈 — 우 패널 폭 초과 이름은 여러 줄로 분할
const longName = 'PANTALON CARGO OVERSIZE ALGODON PREMIUM NEGRO TALLE ESPECIAL';
const zplI = formatQrLabel({ ...base, name: longName });
const nameFragments = zplI.split('\n').filter((l) => /\^A0N,\d+,\d+\^FD/.test(l) && !/\^FDMinorista/.test(l));
ok('I: 긴 이름 여러 줄 분할 (>1 name ^FD)', nameFragments.length > 1);
// 각 줄이 서로 다른 y 좌표 → 세로로 쌓임
const yOf = (l) => parseInt(l.match(/\^FO\d+,(\d+)/)[1], 10);
ok('I: 줄바꿈 라인들이 서로 다른 y 로 쌓임', yOf(nameFragments[1]) > yOf(nameFragments[0]));

// J) 빈 이름/가격 방어 — 크래시 없이 생성
const zplJ = formatQrLabel({ qrUrl, name: '', price: null, priceLabel: '' });
ok('J: 빈 필드에도 ^XA/^XZ 생성', /\^XA/.test(zplJ) && /\^XZ/.test(zplJ) && zplJ.includes(`^FDQA,${qrUrl}^FS`));

console.log(`\n${passed} checks passed ✅`);
