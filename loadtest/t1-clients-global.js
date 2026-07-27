/* eslint-disable */
// ============================================================================
// Phase 63 T-1 — 고객 정보 동시 입력/수정/삭제 충돌 검증
//
// 검증 목표:
//   ① 매장 A 가 이미 global_clients 에 있는 고객을 추가할 때 global 에 중복이 생기지 않는가
//   ② 매장 A 가 global 에 없는 고객을 넣으면 global 에 정상 추가되는가
//   ③ 매장 B 가 같은 고객을 넣을 때 global 에 중복 기록되지 않는가
//   ④ 위 상황이 "동시에" 벌어질 때 500 에러 없이 처리되는가 (경합 내성)
//
// 부하 모델: 여러 매장이 **같은 문서번호 풀**을 공유하며 동시에 POST /clients.
//   같은 owner_group 안에서 document 는 유일해야 하므로 강한 경합이 발생한다.
//
// 실행:
//   k6 run -e BASE_URL=http://127.0.0.1:5012/api -e STORES=6,9,13,19,... \
//          -e RATE=20 -e DUR=60s -e DOC_POOL=40 t1-clients-global.js
//   → 이후 psql -f verify-t1-clients.sql
// ============================================================================
import http from 'k6/http';
import { check } from 'k6';
import { Counter } from 'k6/metrics';

const BASE_URL = __ENV.BASE_URL || 'http://127.0.0.1:5012/api';
const PASSWORD = __ENV.LT_PASSWORD || 'loadtest123';
const RATE = Number(__ENV.RATE || 20);
const DUR = __ENV.DUR || '60s';
const STORES = (__ENV.STORES || '6,9,13').split(',').map(Number);
const PER_STORE = Number(__ENV.PER_STORE || 2);
// 문서번호 풀 크기가 작을수록 매장 간 충돌이 잦아진다 (의도적으로 작게)
const DOC_POOL = Number(__ENV.DOC_POOL || 40);
// 이 실행을 식별하는 접두 — 검증 SQL 이 이 태그로 대상을 찾는다
const RUN_TAG = __ENV.RUN_TAG || 'T1';

const TOTAL = STORES.length * PER_STORE;

export const options = {
  scenarios: {
    t1: {
      executor: 'constant-arrival-rate',
      rate: RATE,
      timeUnit: '1s',
      duration: DUR,
      preAllocatedVUs: TOTAL,
      maxVUs: TOTAL,
    },
  },
  thresholds: {
    // ★ 경합으로 인한 5xx 는 0 이어야 한다 (이 테스트의 핵심 합격 조건)
    client_5xx: ['count==0'],
  },
};

const created = new Counter('client_created'); // 2xx
const c4xx = new Counter('client_4xx'); // 검증 실패 등 정상 거부
const c5xx = new Counter('client_5xx'); // ★ 경합 미처리 = 서버 오류
const updOk = new Counter('client_update_ok');
const delOk = new Counter('client_delete_ok');

let S = null;

function headers() {
  return {
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${S.jwt}`,
      'x-session-token': S.sessionToken,
    },
    timeout: '30s',
  };
}

function assign() {
  const idx = (__VU - 1) % TOTAL;

  return { store: STORES[idx % STORES.length], n: Math.floor(idx / STORES.length) + 1 };
}

// DNI 는 7~8자리 숫자면 유효 (체크섬 없음) — 풀에서 결정론적으로 생성
function docOf(i) {
  return String(30000000 + i); // 8자리
}

function boot() {
  const { store, n } = assign();
  const lr = http.post(
    `${BASE_URL}/auth/login`,
    JSON.stringify({
      emailOrUsername: `lt_s${store}_${n}`,
      password: PASSWORD,
      deviceFingerprint: `lt-s${store}-fp-${n}`,
    }),
    { headers: { 'Content-Type': 'application/json' }, timeout: '30s' },
  );

  if (!check(lr, { 'T1 login 200': (r) => r.status === 200 })) return false;

  const b = lr.json();
  S = {
    jwt: b.accessToken || b.token,
    sessionToken: b.sessionToken || '',
    storeId: null,
    store,
  };

  const me = http.get(`${BASE_URL}/auth/me`, headers());
  if (me.status !== 200) {
    S = null;

    return false;
  }
  S.storeId = me.json('storeId');

  return true;
}

export default function () {
  if (!S && !boot()) return;

  const i = Math.floor(Math.random() * DOC_POOL);
  const doc = docOf(i);

  // ── 등록: 여러 매장이 동시에 같은 document 를 넣는다 ──
  const res = http.post(
    `${BASE_URL}/clients`,
    JSON.stringify({
      fullname: `${RUN_TAG} Cliente ${i}`,
      document: doc,
      email: `${RUN_TAG.toLowerCase()}_${i}@loadtest.local`,
      phone: '1100000000',
      // 실측: address / provinceId / storeId 는 DTO 필수 (없으면 400)
      address: `Calle ${i}`,
      provinceId: 1,
      storeId: S.storeId,
      note: `${RUN_TAG}|store${S.storeId}|vu${__VU}`,
    }),
    headers(),
  );

  if (res.status >= 200 && res.status < 300) {
    created.add(1);

    // ── 수정: 방금 만든(또는 재사용된) 로컬 고객을 갱신 ──
    // 매장 A 의 수정이 다른 매장 데이터를 건드리지 않아야 한다(검증 SQL 에서 확인).
    let localId = null;
    try {
      localId = res.json('id');
    } catch (e) {
      localId = null;
    }

    if (localId && Math.random() < 0.3) {
      const up = http.put(
        `${BASE_URL}/clients/${localId}`,
        JSON.stringify({
          fullname: `${RUN_TAG} EDITADO s${S.storeId} c${i}`,
          phone: '1199999999',
        }),
        headers(),
      );
      if (up.status >= 200 && up.status < 300) updOk.add(1);
      if (up.status >= 500) c5xx.add(1);
    }

    // ── 삭제: 소량만 (매장 A 삭제가 매장 B 에 영향 주는지 확인용) ──
    if (localId && Math.random() < 0.1) {
      const del = http.del(`${BASE_URL}/clients/${localId}`, null, headers());
      if (del.status >= 200 && del.status < 300) delOk.add(1);
      if (del.status >= 500) c5xx.add(1);
    }
  } else if (res.status >= 500) {
    c5xx.add(1);
    console.error(
      `client 5xx store=${S.storeId} doc=${doc} status=${res.status} body=${String(res.body).slice(0, 200)}`,
    );
  } else {
    c4xx.add(1);
    if (res.status === 401) S = null;
  }

  check(res, { 'T1 client 5xx 없음': (r) => r.status < 500 });
}
