// **한 인쇄 작업은 한 번만 인쇄된다** — 마지막 관문의 계약 시험.
//
// ★ 대조군이 있다: 다른 작업은 통과해야 하고, jobId 가 없는 이벤트도 통과해야 한다
//   (구버전 서버/엣지와 섞여 돌기 때문에 여기서 막으면 인쇄가 통째로 멈춘다).
//
// 실행: node print-agent/test/print-dedup.smoke.js
const assert = require('assert');
const dedup = require('../src/print-dedup');

// ── ① 같은 작업은 한 번만 ──
dedup._reset();
assert.strictEqual(dedup.claimJob('sale-auto:42'), true, '첫 배달은 인쇄한다');
assert.strictEqual(dedup.claimJob('sale-auto:42'), false, '두 번째 배달은 거절한다');
assert.strictEqual(dedup.claimJob('sale-auto:42'), false, '세 번째도 거절한다');

// ── ② 대조군: 다른 작업은 막히지 않는다 ──
assert.strictEqual(dedup.claimJob('sale-auto:43'), true, '다른 판매는 인쇄한다');
assert.strictEqual(dedup.claimJob('sale-reprint:42:abc'), true, '재인쇄는 새 작업이다');

// ── ③ 대조군: jobId 가 없으면 막지 않는다 ──
// 구버전 서버/엣지는 이 필드를 안 보낸다. 여기서 막으면 인쇄가 통째로 멈춘다.
for (const vacio of [undefined, null, '', 0, false, {}, []]) {
  assert.strictEqual(dedup.claimJob(vacio), true, `jobId 없음(${JSON.stringify(vacio)})은 통과`);
}

// ── ④ 재기동을 넘어 기억한다 ──
// 에이전트가 재시작하는 사이에 같은 작업이 다시 배달될 수 있다.
const disco = new Map();
const fakeStore = { get: (k) => disco.get(k), set: (k, v) => disco.set(k, v) };

dedup._reset();
dedup.attachStore(fakeStore);
assert.strictEqual(dedup.claimJob('job-persistente'), true);
assert.ok(disco.get('printJobsSeen'), '원장이 디스크에 저장된다');

dedup._reset(); // 재시작 시뮬레이션 — 메모리는 비었다
assert.strictEqual(dedup.claimJob('job-persistente'), true, '대조군: 복구 전이면 인쇄한다');

dedup._reset();
dedup.attachStore(fakeStore); // 저장된 원장 복구
assert.strictEqual(dedup.claimJob('job-persistente'), false, '재시작 후에도 거절한다');

// ── ⑤ 원장이 무한히 자라지 않는다 ──
dedup._reset();
for (let i = 0; i < dedup.MAX_ENTRIES + 500; i++) dedup.claimJob(`j-${i}`);
assert.strictEqual(dedup.claimJob(`j-${dedup.MAX_ENTRIES + 499}`), false, '최근 것은 기억한다');

// ── ⑥ 손상된 저장값이 인쇄를 막지 않는다 ──
dedup._reset();
dedup.attachStore({ get: () => 'basura-no-array', set: () => {} });
assert.strictEqual(dedup.claimJob('tras-corrupcion'), true, '손상된 원장이면 빈 상태로 시작');

console.log('print-dedup smoke OK');
