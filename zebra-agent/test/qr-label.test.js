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

console.log('formatQrLabel — QR 배치 델타 라벨 (QR 자동맞춤 폭에서 역산한 좌우 분할)\n');

// ── 기본 입력 (Phase 37 딥링크 QR) ────────────────────────────────────────
const qrUrl = 'https://app.coolsistema.com/m/stock?s=6&p=1234';
const base = {
  contenido: qrUrl,
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
ok('C: 가격줄 priceLabel: $price (소수점 없음)', /\^FDMinorista: \$12\.999\^FS/.test(zplA));

// D) 좌우 배치 — QR 실측 폭에서 역산 (splitRatio 폐기)
//    50byte URL → 33모듈, 50x25 라벨에서 module 5 → qrRight 175, textX 187
//    주의: textX = qrRight + QR_GAP 는 renderQrBlock 이 "그렇게 만들도록 짜여" 있어서
//    'QR 과 텍스트가 겹치지 않음' 류 부등식은 구조상 항상 참 — 폭 캡 로직이 맞는지는
//    검증하지 못한다(실제 겹침-불가/폭 캡 속성은 test/qr-fit.test.js D·F 블록이 검증).
//    여기서는 그 공식이 formatQrLabel 실물 출력에도 그대로 배선돼 있는지만 확인한다.
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
ok('D: 텍스트 X 좌표가 formatQrLabel 실물에서도 qrRight+gap 공식과 일치 (배선 확인)',
  xOf(nameLine) === textXD);
ok('D: (참고, 구조상 항상 참) textX > qrRight — 진짜 겹침-불가 증명은 qr-fit.test.js D/F 참조',
  xOf(nameLine) > qrRightD);

// D-2) 폭 캡이 실제로 이기는 기하에서 auto-fit 이 진짜로 폭을 우선 축소하는지 검증.
//      25x50mm(세로로 긴 라벨): region 200(25mm), H 400(50mm)
//        byHeight = floor((400-20)/33) = 11 (넉넉)
//        byWidth  = floor((200*0.55-10)/33) = floor(100/33) = 3  ← 이게 이겨야 정상
//      cap 을 6→10 으로 올려도 결과가 그대로 3 이어야 "폭 캡이 진짜 바인딩 중"임이 증명됨
//      (기존 D-2 는 50x25 기하를 썼는데 거기선 byHeight(5)가 항상 먼저 묶여
//       cap 6 이든 10 이든 같은 5 가 나와 폭 캡을 전혀 exercise 하지 못했다).
const tallLayout = (cap) => ({ widthMm: 25, heightMm: 50, qrModule: cap });
const zplD2cap6 = formatQrLabel({ ...base, layout: tallLayout(6) });
const zplD2cap10 = formatQrLabel({ ...base, layout: tallLayout(10) });
const qrLineD2cap6 = zplD2cap6.split('\n').find((l) => /\^BQN/.test(l));
const qrLineD2cap10 = zplD2cap10.split('\n').find((l) => /\^BQN/.test(l));
// 이 좁은 기하(availW=69dot)에서는 "REMERA" 한 단어조차 폭을 넘어 문자 단위로 쪼개지므로
// 리터럴 REMERA 를 찾지 않고, 이름 패널의 첫 줄(가격줄 제외)을 일반적으로 잡는다.
const nameLineD2cap10 = zplD2cap10.split('\n')
  .find((l) => /\^A0N,\d+,\d+\^FD/.test(l) && !/\^FDMinorista/.test(l));

ok('D-2: 25x50mm(세로로 긴 라벨) cap 6 → 폭 캡(3)이 높이(11)보다 먼저 묶여 ^BQN,2,3',
  /\^BQN,2,3\^FDMA,/.test(qrLineD2cap6));
ok('D-2: cap 을 10 으로 올려도 결과 불변(여전히 ^BQN,2,3) — 폭 캡이 진짜 바인딩 중이라는 증거',
  /\^BQN,2,3\^FDMA,/.test(qrLineD2cap10));

const qrRightD2 = QR_MARGIN + modulesD * 3; // modulesD: 위에서 구한 33모듈 (동일 qrUrl)
ok('D-2: 텍스트 X 좌표 = 폭 캡으로 축소된 QR 실측 우측끝 + gap (실물 출력 배선 확인)',
  xOf(nameLineD2cap10) === qrRightD2 + QR_GAP);

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

// F) doble — 같은 상품 2장이 **같은 라벨 안에** 들어간다
//
// ★★★ [2026-09-25 사용자 요구] 「50mm x 25mm etiqueta 1개에 2개씩 출력」
//   여기 있던 단언은 **`^PW800`(미디어 폭 2배)** 이었다 — 즉 이 파일이 결함을
//   정답으로 고정하고 있었다. 50x25 라벨에서 `doble` 을 고르면 100mm 폭을 선언하는데,
//   프린터는 실제 용지 폭에서 자르므로 **오른쪽 QR 이 통째로 안 나온다.**
//   (100mm 카툴리나에서도 틀린다: widthMm=100 → ^PW1600 = 200mm.)
//   ⤷ 계약을 뒤집는다: **`^PW` 는 언제나 설정된 라벨 폭**이고, `doble` 은 그 폭을
//     둘로 나눠 쓴다.
const zplF = formatQrLabel({ ...base, layout: { mode: 'doble' } });
ok('F: doble → ^BQN 2회', (zplF.match(/\^BQN/g) || []).length === 2);
ok('F: doble → 이름 2회', (zplF.match(/\^FDREMERA/g) || []).length === 2);
ok('F: ★★★ doble 도 ^PW 는 라벨 폭 그대로 (^PW400) — 용지 밖으로 안 나간다',
  /\^PW400\b/.test(zplF) && !/\^PW800\b/.test(zplF));
ok('F: doble → 두 QR 모두 qrUrl byte-identical', (zplF.match(new RegExp(`\\^FDMA,${qrUrl.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\^FS`, 'g')) || []).length === 2);
// 오른쪽 복제본은 반 칸(offsetX = region/2) 만큼 이동
const qrLinesF = zplF.split('\n').filter((l) => /\^BQN/.test(l));
ok('F: 오른쪽 복제본 offsetX 적용', xOf(qrLinesF[1]) > xOf(qrLinesF[0]));

// ★★ 그리고 **아무것도 라벨 밖으로 나가지 않는다.** 이것이 옛 계약에서 깨져 있던 것이고,
//   «^BQN 이 2회» 같은 단언으로는 절대 안 잡힌다 — 두 번째 QR 은 ZPL 에 **있었고**
//   종이에만 없었다.
const pwF = Number(zplF.match(/\^PW(\d+)/)[1]);
const llF = Number(zplF.match(/\^LL(\d+)/)[1]);
const modulesF = qrModuleCount(utf8Len(qrUrl));
const moduleF = Number(zplF.match(/\^BQN,2,(\d+)/)[1]);

for (const [i, ln] of qrLinesF.entries()) {
  const x = xOf(ln);
  const y = Number(ln.match(/\^FO\d+,(\d+)/)[1]);
  ok(`F: QR ${i + 1} 이 라벨 폭 안 (x=${x}+${modulesF * moduleF} ≤ ${pwF})`,
    x + modulesF * moduleF <= pwF);
  ok(`F: QR ${i + 1} 이 라벨 높이 안 (y=${y}+${modulesF * moduleF} ≤ ${llF})`,
    y + modulesF * moduleF <= llF);
}

// 글자도 마찬가지 — QR 아래로 쌓이므로 아래로 넘칠 수 있다.
for (const ln of zplF.split('\n').filter((l) => /\^A0N/.test(l))) {
  const y = Number(ln.match(/\^FO\d+,(\d+)/)[1]);
  const fs = Number(ln.match(/\^A0N,(\d+)/)[1]);
  assert.ok(y + fs <= llF, `F: 글자가 라벨 아래로 넘친다 (y=${y}+${fs} > ${llF})`);
}
passed += 1;
console.log('  ✓ F: 글자도 전부 라벨 높이 안');

// ★ 스캔 가능한 크기인지 — 반으로 나눴다고 읽을 수 없게 되면 기능이 아니다.
ok(`F: QR module ${moduleF}dot ≥ 최소 스캔 폭 2dot(0.25mm)`, moduleF >= 2);

// ★ QR 은 칸 안에서 가운데. 왼쪽 정렬이면 오른쪽에만 여백이 몰려 가위로 반을 자를
//   때 경계가 어디인지 알기 어렵다. (주석으로만 적어 두면 지켜지는지 알 수 없어서
//   — 돌연변이 「왼쪽에 붙인다」가 살아남았다 — 여기서 잰다.)
const celdaF = Math.floor(pwF / 2);
for (const [i, ln] of qrLinesF.entries()) {
  const margenIzq = xOf(ln) - i * celdaF;
  const margenDer = celdaF - (xOf(ln) - i * celdaF) - modulesF * moduleF;
  ok(`F: QR ${i + 1} 이 칸 안에서 가운데 (좌 ${margenIzq} ≈ 우 ${margenDer})`,
    Math.abs(margenIzq - margenDer) <= 1);
}

// ★★★ 폭 한도가 **실제로 묶이는** 경우. 위 25mm 라벨에서는 높이가 먼저 걸려서
//   (byHeight 4 < byWidth 5) 폭 검사를 지워도 결과가 안 변한다 — 돌연변이가 살아남았다.
//   라벨을 키우면 반대가 된다: 50x50mm 에서 byHeight 10 · byWidth 5 → 폭이 한도다.
//   폭 검사를 지우면 QR 이 칸(25mm)을 넘어 **옆 칸을 침범하고 라벨 밖으로 나간다.**
const zplFw = formatQrLabel({ ...base, layout: { mode: 'doble', widthMm: 50, heightMm: 50 } });
const pwFw = Number(zplFw.match(/\^PW(\d+)/)[1]);
const moduleFw = Number(zplFw.match(/\^BQN,2,(\d+)/)[1]);
const qrLinesFw = zplFw.split('\n').filter((l) => /\^BQN/.test(l));
const celdaFw = Math.floor(pwFw / 2);

ok(`F-2: 라벨이 높아져도 QR 은 반 칸을 안 넘는다 (${modulesF}×${moduleFw} ≤ ${celdaFw - 2 * QR_MARGIN})`,
  modulesF * moduleFw <= celdaFw - 2 * QR_MARGIN);
ok('F-2: 왼쪽 QR 이 오른쪽 칸을 침범하지 않는다',
  xOf(qrLinesFw[0]) + modulesF * moduleFw <= celdaFw);
ok('F-2: 오른쪽 QR 이 라벨 밖으로 안 나간다',
  xOf(qrLinesFw[1]) + modulesF * moduleFw <= pwFw);

// ★★ 대조군: simple 은 **그대로**여야 한다. doble 만 고쳤다는 증거다.
const zplFs = formatQrLabel({ ...base, layout: { mode: 'simple' } });
ok('F: 대조군 — simple 은 ^PW400 · QR 1개 · 좌우 배치 그대로',
  /\^PW400\b/.test(zplFs) &&
  (zplFs.match(/\^BQN/g) || []).length === 1 &&
  xOf(zplFs.split('\n').find((l) => /\^FDREMERA/.test(l))) > xOf(zplFs.split('\n').find((l) => /\^BQN/.test(l))));

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
const zplJ = formatQrLabel({ contenido: qrUrl, name: '', price: null, priceLabel: '' });
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
