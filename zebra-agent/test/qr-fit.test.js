/**
 * QR 자동맞춤 순수 함수 단위 테스트.
 * 실행: node test/qr-fit.test.js
 *
 * 검증 대상 (2026-07-15 설계 D-4/D-6/D-7):
 *  - qrModuleCount: ECC M byte capacity 경계
 *  - effectiveQrModule: 사용자 상한(cap) / 높이 제약 / 폭 55% 캡 중 최솟값
 */
const assert = require('assert');
const {
  utf8Len,
  qrModuleCount,
  effectiveQrModule,
  QR_MARGIN,
  QR_WIDTH_CAP,
  MAX_QR_MODULE,
} = require('../src/zpl-formatter');

let passed = 0;
function ok(name, cond) {
  assert.ok(cond, name);
  passed += 1;
  console.log('  ✓', name);
}

console.log('QR 자동맞춤 (ECC M + 높이/폭 제약)\n');

// ── A) utf8Len ────────────────────────────────────────────────────────────
ok('A: ASCII 길이', utf8Len('abc') === 3);
ok('A: 멀티바이트는 byte 로 계산', utf8Len('ñ') === 2);
ok('A: null/undefined → 0', utf8Len(null) === 0 && utf8Len(undefined) === 0);

// ── B) qrModuleCount — ECC M byte capacity 경계 ───────────────────────────
ok('B: 14byte → v1(21모듈)', qrModuleCount(14) === 21);
ok('B: 15byte → v2(25모듈)', qrModuleCount(15) === 25);
ok('B: 42byte → v3(29모듈)', qrModuleCount(42) === 29);
ok('B: 43byte → v4(33모듈)', qrModuleCount(43) === 33);
ok('B: 62byte → v4(33모듈)', qrModuleCount(62) === 33);
ok('B: 63byte → v5(37모듈)', qrModuleCount(63) === 37);
ok('B: 213byte → v10(57모듈)', qrModuleCount(213) === 57);
ok('B: 용량 초과(214byte) → 최대 57 (방어)', qrModuleCount(214) === 57);

// ── C) 실측 — 딥링크 50byte, 50x25mm 라벨 ─────────────────────────────────
// 'https://ventago.coolsistema.com/m/stock?s=6&p=1234' = 50 byte
// ECC M: 50 <= 62 → v4 = 33 모듈  (ECC Q 였다면 v5 = 37 모듈)
const url = 'https://ventago.coolsistema.com/m/stock?s=6&p=1234';
ok('C: 딥링크 50byte', utf8Len(url) === 50);
ok('C: ECC M → 33모듈 (Q의 37에서 축소)', qrModuleCount(utf8Len(url)) === 33);

// region 400(50mm), H 200(25mm), cap 6
//   byHeight = floor((200-20)/33) = 5
//   byWidth  = floor((400*0.55-10)/33) = floor(210/33) = 6
//   → min(6, 5, 6) = 5   ← ECC Q 시절 4 에서 확대
ok('C: 50x25 + cap 6 → module 5', effectiveQrModule(url, 6, 200, 400) === 5);

// ── D) 제약별로 누가 이기는지 ──────────────────────────────────────────────
// cap 이 이김: cap 3 < byHeight 5
ok('D: cap 이 최소 → cap 반환', effectiveQrModule(url, 3, 200, 400) === 3);

// 높이가 이김: cap 10, H 200 → byHeight 5, byWidth 6
ok('D: 높이 제약이 최소 → 5', effectiveQrModule(url, 10, 200, 400) === 5);

// 폭이 이김: region 200(25mm), H 400(50mm)
//   byHeight = floor(380/33) = 11
//   byWidth  = floor((200*0.55-10)/33) = floor(100/33) = 3
ok('D: 폭 55% 캡이 최소 → 3', effectiveQrModule(url, 10, 400, 200) === 3);

// ── E) 경계/방어 ──────────────────────────────────────────────────────────
ok('E: 최소 1 보장 (라벨이 아주 작아도 0/음수 금지)',
  effectiveQrModule(url, 10, 30, 30) === 1);
ok('E: cap 은 MAX_QR_MODULE 로 클램프',
  effectiveQrModule(url, 999, 4000, 4000) === MAX_QR_MODULE);
ok('E: cap 미지정 → 기본 6 상한', effectiveQrModule(url, undefined, 200, 400) === 5);
ok('E: cap 0/음수 → 최소 1 이상', effectiveQrModule(url, 0, 200, 400) >= 1);

// ── F) 텍스트 침범 불가 — QR 폭이 region 의 55% 를 절대 못 넘음 ────────────
for (const cap of [1, 3, 5, 8, 10]) {
  const m = effectiveQrModule(url, cap, 400, 400);
  const qrRight = QR_MARGIN + qrModuleCount(utf8Len(url)) * m;
  ok(`F: cap ${cap} → QR 우측끝(${qrRight}) <= region*${QR_WIDTH_CAP}(${400 * QR_WIDTH_CAP})`,
    qrRight <= 400 * QR_WIDTH_CAP);
}

console.log(`\n${passed} checks passed ✅`);
