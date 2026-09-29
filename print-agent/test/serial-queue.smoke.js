// 직렬 큐 계약 — **한 번의 실패가 이후 출력을 전부 죽이지 않는다.**
//
// ★ 대조군: 종전 코드(`q = q.then(fn)`)를 그대로 재현해, 같은 시나리오에서 실제로
//   이후 작업이 fn 을 부르지도 않고 실패하는지 먼저 보인다. 이 대조군이 통과하지
//   않으면(=옛 패턴도 멀쩡하면) 아래 검사는 아무것도 지키지 않는 것이다.
//
// 실행: node print-agent/test/serial-queue.smoke.js
const assert = require('assert');
const { createSerialQueue } = require('../src/serial-queue');

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ★ 큐가 멈추면 이벤트 루프가 비어 node 가 **exit 0 으로** 조용히 끝난다.
//   끝까지 안 돌았으면 실패로 만든다 — 「출력이 비면 안 돈 것」.
let done = false;
process.on('exit', () => {
  if (!done) {
    console.error('serial-queue.smoke INCOMPLETO — el test no terminó (cola trabada)');
    process.exitCode = 1;
  }
});

(async () => {
  // ── 대조군: 옛 패턴은 한 번 실패하면 이후가 전부 죽는다 ──
  {
    let q = Promise.resolve();
    const oldRun = (fn) => (q = q.then(fn));
    let calls = 0;

    await oldRun(() => { calls++; throw new Error('timeout'); }).catch(() => {});
    const r = await oldRun(() => { calls++; return 'ok'; }).then((v) => v, (e) => `ERR:${e.message}`);

    assert.strictEqual(r, 'ERR:timeout', '대조군: 옛 큐는 두 번째 작업도 같은 오류로 끝난다');
    assert.strictEqual(calls, 1, '대조군: 두 번째 fn 은 불리지도 않는다');
  }

  // ── ① 실패 뒤에도 다음 작업이 실제로 돈다 ──
  {
    const q = createSerialQueue();
    let calls = 0;
    const a = q.run(async () => { calls++; throw new Error('render timeout'); });
    const b = q.run(async () => { calls++; return 'png'; });

    await assert.rejects(a, /render timeout/, '실패한 작업은 호출부에 실패로 돌아간다');
    assert.strictEqual(await b, 'png', '다음 작업은 성공한다');
    assert.strictEqual(calls, 2);
  }

  // ── ② 동기 throw 도 큐를 죽이지 않는다 ──
  {
    const q = createSerialQueue();
    const a = q.run(() => { throw new Error('sync'); });
    const b = q.run(() => 7);

    await assert.rejects(a, /sync/);
    assert.strictEqual(await b, 7);
  }

  // ── ③ 한 번에 하나씩 (겹치지 않는다) ──
  {
    const q = createSerialQueue();
    let running = 0;
    let max = 0;
    const order = [];
    const job = (id, ms) => q.run(async () => {
      running++; max = Math.max(max, running);
      await sleep(ms);
      order.push(id);
      running--;
    });

    await Promise.all([job(1, 30), job(2, 5), job(3, 1)]);
    assert.strictEqual(max, 1, '동시에 둘이 돌지 않는다');
    assert.deepStrictEqual(order, [1, 2, 3], '들어온 순서대로');
  }

  // ── ④ 앞 작업이 영영 안 끝나도 슬롯 상한 뒤엔 다음이 돈다 ──
  {
    const q = createSerialQueue({ slotTimeoutMs: 50 });
    q.run(() => new Promise(() => {})); // 영영 안 끝나는 작업(escpos close 누락)
    const t0 = Date.now();
    const b = await q.run(async () => 'next');

    assert.strictEqual(b, 'next');
    assert.ok(Date.now() - t0 >= 45, '상한 전에는 기다렸다');
  }

  // ── ④-b 슬롯 시간은 실행 시작부터 잰다 — 대기 중인 작업들이 한꺼번에 풀리지 않는다 ──
  //   A 가 멈추고 B·C 가 대기: 상한 뒤 B 가 시작되고, C 는 **B 가 끝난 뒤**에 시작해야 한다.
  {
    const q = createSerialQueue({ slotTimeoutMs: 60 });
    const log = [];
    q.run(() => new Promise(() => {}));
    const b = q.run(async () => { log.push(['B+', Date.now()]); await sleep(30); log.push(['B-', Date.now()]); });
    const c = q.run(async () => { log.push(['C+', Date.now()]); });
    await Promise.all([b, c]);
    const tB = log.find((x) => x[0] === 'B-')[1];
    const tC = log.find((x) => x[0] === 'C+')[1];
    assert.ok(tC >= tB, `C 는 B 가 끝난 뒤 시작한다 (C+=${tC} B-=${tB})`);
  }

  // ── ⑤ 대조군: 상한이 없으면 멈춘 작업 뒤는 안 돈다 (④가 상한 덕인지 확인) ──
  {
    const q = createSerialQueue();
    q.run(() => new Promise(() => {}));
    let ran = false;
    q.run(async () => { ran = true; });
    await sleep(80);
    assert.strictEqual(ran, false, '대조군: 상한 없이는 막힌다');
  }

  done = true;
  console.log('serial-queue.smoke OK');
})().catch((e) => { console.error(e); process.exit(1); });
