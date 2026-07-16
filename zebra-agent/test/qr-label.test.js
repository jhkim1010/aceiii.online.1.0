/**
 * formatQrLabel 단위 테스트 — QR 배치 델타 라벨
 * 실행: node test/qr-label.test.js
 *
 * 검증 대상 (Phase 38 D-8/D-9/D-10, Phase 37 파서 계약, 2026-07-15 D-5/D-7):
 *  - QR 인코딩 값이 입력 qrUrl 과 byte-identical (딥링크 /m/stock?s=&p= 훼손 없음)
 *  - ECC M (^FDMA) — Q 에서 낮춰 같은 높이에 더 큰 QR
 *  - QR 실측 폭에서 역산한 좌우 배치 (splitRatio 폐기)
 *  - layout.mode='doble' → 같은 상품 2장 (^BQN 2회, 이름 2회)
 *  - layout 수치(widthMm/heightMm/qrModule/fontSize) 가 ZPL 에 반영
 *  - sanitize (^,~ 제거) / 긴 이름 줄바꿈
 */
const assert = require('assert');
const {
  formatQrLabel,
  qrModuleCount,
  utf8Len,
  effectiveQrModule,
  QR_MARGIN,
  QR_GAP,
} = require('../src/zpl-formatter');

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
ok('A: QR 인코딩 = qrUrl byte-identical', zplA.includes(`^FDMA,${qrUrl}^FS`));
ok('A: ECC M 사용 (Q 아님)', /\^FDMA,/.test(zplA) && !/\^FDQA,/.test(zplA));
ok('A: 시작/종료 프레임', zplA.startsWith('^XA') && zplA.trim().endsWith('^XZ'));

// B) layout 수치 반영 — 기본 50x25mm → ^PW400 / ^LL200
ok('B: widthMm=50 → ^PW400', /\^PW400\b/.test(zplA));
ok('B: heightMm=25 → ^LL200', /\^LL200\b/.test(zplA));
// 기본 cap 6 이지만 25mm 높이(200dot)/33모듈 → 실효 5
ok('B: 기본 cap 6 + 50x25 → ^BQN,2,5', /\^BQN,2,5\^FDMA,/.test(zplA));

// C) 우 패널 내용 — 이름(^A0N) + `${priceLabel}: ${price}`
ok('C: 이름 ^A0N 폰트 출력', /\^A0N,\d+,\d+\^FDREMERA/.test(zplA));
ok('C: 가격줄 priceLabel: $price', /\^FDMinorista: \$12\.999,00\^FS/.test(zplA));

// D) 좌우 배치 — QR 실측 폭에서 역산 (splitRatio 폐기)
//    50byte URL → 33모듈, 50x25 라벨에서 module 5 → qrRight 175, textX 187
const region = 400;
const modulesD = qrModuleCount(utf8Len(qrUrl));
const moduleD = effectiveQrModule(qrUrl, 6, 200, region);
const qrRightD = QR_MARGIN + modulesD * moduleD;
const textXD = qrRightD + QR_GAP;
const qrLine = zplA.split('\n').find((l) => /\^BQN/.test(l));
const nameLine = zplA.split('\n').find((l) => /\^FDREMERA/.test(l));
const xOf = (l) => parseInt(l.match(/\^FO(\d+),/)[1], 10);

ok('D: 실측 — 33모듈 × module 5', modulesD === 33 && moduleD === 5);
ok('D: QR 은 좌측 margin 에서 시작', xOf(qrLine) === QR_MARGIN);
ok('D: 텍스트는 QR 우측끝 + gap 에서 시작', xOf(nameLine) === textXD);
ok('D: QR 과 텍스트가 겹치지 않음', xOf(nameLine) > qrRightD);

// D-2) 침범 불가 회귀 가드 — cap 을 최대로 올려도 텍스트를 못 덮는다
const zplD2 = formatQrLabel({ ...base, layout: { qrModule: 10 } });
const qrLineD2 = zplD2.split('\n').find((l) => /\^BQN/.test(l));
const nameLineD2 = zplD2.split('\n').find((l) => /\^FDREMERA/.test(l));
const moduleD2 = Number(/\^BQN,2,(\d+)/.exec(qrLineD2)[1]);
ok('D-2: cap 10 이어도 QR 우측끝 < 텍스트 x',
  QR_MARGIN + modulesD * moduleD2 < xOf(nameLineD2));

// E) layout 수치 변경 반영 — qrModule(상한)/fontSize/치수
const zplE = formatQrLabel({
  ...base,
  layout: { widthMm: 100, heightMm: 50, qrModule: 8, fontSize: 30 },
});
ok('E: widthMm=100 → ^PW800', /\^PW800\b/.test(zplE));
ok('E: heightMm=50 → ^LL400', /\^LL400\b/.test(zplE));
// 100x50 → region 800, H 400. byHeight=floor(380/33)=11, byWidth=floor(430/33)=13 → min(8,11,13)=8, cap 이 이김
ok('E: qrModule=8 → ^BQN,2,8', /\^BQN,2,8\^FDMA,/.test(zplE));
ok('E: fontSize=30 → 이름 ^A0N,30,30', /\^A0N,30,30\^FDREMERA/.test(zplE));
const nameLineE = zplE.split('\n').find((l) => /\^FDREMERA/.test(l));
ok('E: 큰 라벨에서도 텍스트가 QR 우측에 위치',
  xOf(nameLineE) === QR_MARGIN + modulesD * 8 + QR_GAP);

// F) doble — 같은 상품 2장 (^BQN 2회, 이름 2회, 미디어 폭 2배)
const zplF = formatQrLabel({ ...base, layout: { mode: 'doble' } });
ok('F: doble → ^BQN 2회', (zplF.match(/\^BQN/g) || []).length === 2);
ok('F: doble → 이름 2회', (zplF.match(/\^FDREMERA/g) || []).length === 2);
ok('F: doble → 미디어 폭 2배 ^PW800', /\^PW800\b/.test(zplF));
ok('F: doble → 두 QR 모두 qrUrl byte-identical', (zplF.match(new RegExp(`\\^FDMA,${qrUrl.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\^FS`, 'g')) || []).length === 2);
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
ok('J: 빈 필드에도 ^XA/^XZ 생성', /\^XA/.test(zplJ) && /\^XZ/.test(zplJ) && zplJ.includes(`^FDMA,${qrUrl}^FS`));

// K) 전역 출력 파라미터 — QR 도 밀도(~SD)/속도(^PR) 적용
const zplK = formatQrLabel({ ...base, layout: { darkness: 22, speed: 4 } });
ok('K: ~SD22 적용', /~SD22/.test(zplK));
ok('K: ~SD 는 ^XA 앞 (포맷 밖 전역 명령)', zplK.indexOf('~SD22') < zplK.indexOf('^XA'));
ok('K: ^PR4 적용', /\^PR4/.test(zplK));
ok('K: ^PR 은 ^XA..^XZ 안', zplK.indexOf('^PR4') > zplK.indexOf('^XA') && zplK.indexOf('^PR4') < zplK.indexOf('^XZ'));

// K-2) 미설정/범위 밖 → 명령 미발행 (프린터 기본값)
const zplK2 = formatQrLabel({ ...base, layout: { darkness: 99, speed: 0 } });
ok('K-2: 범위 밖 → ~SD/^PR 없음', !/~SD/.test(zplK2) && !/\^PR/.test(zplK2));
ok('K-2: layout 미지정 → ~SD/^PR 없음', !/~SD/.test(zplA) && !/\^PR/.test(zplA));

// L) splitRatio 는 폐기 — 잔존 설정이 있어도 무시 (하위호환, 무해)
const zplL = formatQrLabel({ ...base, layout: { splitRatio: 0.5 } });
const zplLNoSplit = formatQrLabel({ ...base, layout: {} });
ok('L: 잔존 splitRatio 는 결과에 영향 없음', zplL === zplLNoSplit);

console.log(`\n${passed} checks passed ✅`);
