'use strict';

// **한 번에 하나씩** 돌리되, **한 작업의 실패·멈춤이 다음 작업을 막지 않는다.**
//
// ★ 종전 renderer-engine 의 큐는 `queue = queue.then(fn)` 이었다. fn 이 한 번 reject
//   하면 queue 자체가 rejected 로 남고, 이후 모든 `.then(fn)` 은 fn 을 **부르지도 않고**
//   같은 오류로 끝난다 — 렌더 타임아웃 한 번이면 재시작 전까지 출력이 전부 실패했다.
//   그래서 꼬리(tail)는 결과와 상관없이 항상 fulfilled 로 이어 간다.
//
// ★ slotTimeoutMs: 앞 작업이 **영영 안 끝나면**(escpos close 콜백 누락 등) 큐가 멈춘다.
//   직렬화 전에는 그 경우에도 다음 출력이 나갔으므로, 직렬화가 그보다 나빠지면 안 된다.
//   그래서 앞 작업을 기다리는 시간에 상한을 둔다 — 넘으면 다음 작업을 시작한다.
//   (앞 작업의 promise 는 그대로 호출부에 남는다. 큐만 놓아 준다.)

function createSerialQueue({ slotTimeoutMs = 0 } = {}) {
  let tail = Promise.resolve();

  function run(fn) {
    // ★ 슬롯 시간은 **이 작업이 실제로 시작된 순간부터** 잰다. 등록 시점부터 재면
    //   대기 중인 작업들의 타이머가 한꺼번에 만료돼 여러 개가 동시에 풀린다.
    let markStarted;
    const started = new Promise((resolve) => { markStarted = resolve; });
    const job = tail.then(() => {
      markStarted();

      return fn();
    });

    const settled = job.then(() => undefined, () => undefined);

    // ★ 상한을 넘기면 앞 작업은 **돌고 있는 채로** 다음이 시작된다(겹칠 수 있다).
    //   취소할 수단이 없는 작업(escpos)에서 「절대 안 겹침」과 「절대 안 멈춤」은 함께
    //   보장할 수 없다 — 멈춘 작업 하나가 이후 출력을 영원히 막는 쪽이 더 나쁘다.
    //   직렬화 전에는 항상 겹쳤으므로, 멈춘 경우에만 겹치는 지금이 그보다 나쁘지 않다.
    tail = slotTimeoutMs > 0
      ? started.then(() => Promise.race([
        settled,
        new Promise((resolve) => setTimeout(resolve, slotTimeoutMs)),
      ]))
      : settled;

    return job;
  }

  return { run };
}

module.exports = { createSerialQueue };
