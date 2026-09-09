'use strict';

// [A-1] ULID — 조율 없이 유일하고 시간순으로 정렬되는 26자 식별자.
//
// 왜 직접 구현하는가: 이 에이전트는 지점 PC 에 설치돼 **인터넷 없이** 돌아야 한다.
// 의존성을 최소로 유지하는 것이 이 패키지의 규칙이다(현재 dependencies 4개).
//
// 왜 ULID 인가: 종전 오프라인 번호는 `OFF-<지점>-<MAX(seq)+1>` 이었다. 지점 PC 를
// 재설치하거나 엣지 DB 를 다시 만들면 seq 가 **1부터 다시 시작해 이미 고객에게 종이로
// 나간 번호를 재발급**한다. 그 상태로 클라우드에 올라가면 `uq_sales_offline_number`
// 위반으로 두 번째 판매가 장부에 못 들어간다.
//
// 형식(사양 그대로):
//   [0..9]   48비트 타임스탬프(ms) — 앞자리가 시각이라 정렬이 곧 발생 순서다
//   [10..25] 80비트 난수
// 알파벳은 Crockford Base32 — I·L·O·U 가 없어 전화로 불러 줄 때 1/l, 0/O 혼동이 없다.

const crypto = require('crypto');

const ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ'; // 32자, Crockford
const TIME_LEN = 10;
const RANDOM_LEN = 16;

function encodeTime(now) {
  let out = '';
  let t = now;

  for (let i = TIME_LEN - 1; i >= 0; i--) {
    out = ALPHABET[t % 32] + out;
    t = Math.floor(t / 32);
  }

  return out;
}

function encodeRandom() {
  // crypto 로 뽑는다 — Math.random 은 같은 밀리초에 두 판매가 잡히면 충돌할 수 있다.
  const bytes = crypto.randomBytes(RANDOM_LEN);
  let out = '';

  for (let i = 0; i < RANDOM_LEN; i++) {
    out += ALPHABET[bytes[i] % 32];
  }

  return out;
}

// 26자 ULID. 인자는 테스트에서 시각을 고정하기 위한 것이다.
function ulid(now = Date.now()) {
  return encodeTime(now) + encodeRandom();
}

module.exports = { ulid, ALPHABET, TIME_LEN, RANDOM_LEN };
