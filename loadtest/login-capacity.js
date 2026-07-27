/* eslint-disable */
// ============================================================================
// Phase 63 F-4 — 로그인 처리 용량 측정
//
// 목적: "초당 몇 건의 로그인까지 견디는가"를 구해서, 3,000 터미널이 개점 시간에
//       몰릴 때 필요한 분산 시간을 계산할 수 있게 한다.
//
// 로그인은 bcrypt 해시 검증 + 권한 조립 + 약 55KB JSON 직렬화로 **CPU 바운드**다.
// 캐시는 동시 콜드 스타트(전 터미널이 같은 순간에 로그인)에는 효과가 없으므로
// 용량 자체를 아는 것이 대응(분산·증설)의 기준이 된다.
//
// 실행:
//   k6 run -e BASE_URL=http://127.0.0.1:5012/api -e RATE=10 -e DUR=30s login-capacity.js
//   RATE 를 5 → 10 → 20 → 40 으로 올려가며 p95 가 무너지는 지점을 찾는다.
// ============================================================================
import http from 'k6/http';
import { check } from 'k6';
import { Trend, Counter } from 'k6/metrics';

const BASE_URL = __ENV.BASE_URL || 'http://127.0.0.1:5012/api';
const PASSWORD = __ENV.LT_PASSWORD || 'loadtest123';
const RATE = Number(__ENV.RATE || 10);
const DUR = __ENV.DUR || '30s';
const STORES = (__ENV.STORES || '19,20,21,22,23').split(',').map(Number);
const PER_STORE = Number(__ENV.PER_STORE || 10);

export const options = {
  scenarios: {
    login: {
      executor: 'constant-arrival-rate',
      rate: RATE,
      timeUnit: '1s',
      duration: DUR,
      preAllocatedVUs: Math.max(20, RATE * 4),
      maxVUs: Math.max(50, RATE * 8),
    },
  },
};

const loginMs = new Trend('login_ms');
const meMs = new Trend('me_ms');
const failed = new Counter('login_failed');

export default function () {
  const store = STORES[Math.floor(Math.random() * STORES.length)];
  const n = 1 + Math.floor(Math.random() * PER_STORE);

  // 매 반복마다 새 지문 — 실제 "서로 다른 터미널이 각자 로그인" 상황 재현
  // (같은 유저 재로그인은 active_sessions 를 교체하지만 CPU 비용은 동일)
  const fp = `cap-${store}-${n}-${__VU}-${__ITER}`;

  const lr = http.post(
    `${BASE_URL}/auth/login`,
    JSON.stringify({
      emailOrUsername: `lt_s${store}_${n}`,
      password: PASSWORD,
      deviceFingerprint: fp,
    }),
    { headers: { 'Content-Type': 'application/json' }, timeout: '60s' },
  );

  loginMs.add(lr.timings.duration);

  if (!check(lr, { 'login 200': (r) => r.status === 200 })) {
    failed.add(1);

    return;
  }

  const b = lr.json();
  const h = {
    headers: {
      Authorization: `Bearer ${b.accessToken || b.token}`,
      'x-session-token': b.sessionToken || '',
    },
    timeout: '60s',
  };

  // 로그인 직후 항상 뒤따르는 호출 — 실제 부팅 비용에 포함해서 측정
  const me = http.get(`${BASE_URL}/auth/me`, h);
  meMs.add(me.timings.duration);
}
