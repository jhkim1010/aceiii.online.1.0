/* eslint-disable */
// ============================================================================
// Phase 63 — 다매장 동시 판매 버스트 테스트 (k6)
//
// 목적: 여러 매장의 여러 터미널이 0.1~1초 간격으로 "동시에" 판매를 발생시킬 때
//   ① 요청 성공 수 == DB 저장 수 (판매 누락 없음)
//   ② 매장(지점)별 daily_number 가 중복되지 않음 (채번 경합 검증)
//   ③ 응답 지연이 무너지지 않음
// 를 검증한다. verify-burst.sql 로 사후 정합성 확인.
//
// 부하 모델: constant-arrival-rate — VU 가 아니라 "초당 판매 건수"를 고정한다.
//   실제 러시아워는 터미널이 얼마나 있느냐가 아니라 초당 몇 건이 꽂히느냐가 관건.
//
// 실행:
//   k6 run -e BASE_URL=http://127.0.0.1:5012/api -e RATE=10 -e DUR=2m burst-multistore.js
//   RATE=초당 판매 시도 건수 (기본 10 = 0.1초 간격), DUR=지속 시간
//
// 사전 조건: seed-burst-multistore.sql 실행 (lt_s<store>_<n> 유저)
// ============================================================================
import http from 'k6/http';
import { check } from 'k6';
import { Counter, Trend } from 'k6/metrics';

const BASE_URL = __ENV.BASE_URL || 'http://127.0.0.1:5012/api';
const PASSWORD = __ENV.LT_PASSWORD || 'loadtest123';
const RATE = Number(__ENV.RATE || 10); // 초당 판매 시도 (10 = 0.1초 간격)
const DUR = __ENV.DUR || '2m';
const STORES = (__ENV.STORES || '3,6,8,9,11').split(',').map(Number);
const PER_STORE = Number(__ENV.PER_STORE || 10); // 매장당 터미널 수

// 매장×터미널 = 전체 가상 터미널 수. 도달률을 감당할 만큼 VU 를 준다.
const TOTAL_TERMINALS = STORES.length * PER_STORE;

export const options = {
  scenarios: {
    burst: {
      executor: 'constant-arrival-rate',
      rate: RATE,
      timeUnit: '1s',
      duration: DUR,
      preAllocatedVUs: TOTAL_TERMINALS,
      maxVUs: TOTAL_TERMINALS,
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.001'],
    sale_ms: ['p(95)<300'],
  },
};

const saleMs = new Trend('sale_ms');
const saleOk = new Counter('sale_ok'); // ★ 이 값과 DB 저장 건수가 일치해야 한다
const saleErr = new Counter('sale_err');

// VU 별 세션 (VU 하나 = 터미널 하나로 고정)
let S = null;

function headers() {
  return {
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${S.jwt}`,
      'x-session-token': S.sessionToken,
    },
    timeout: '30s',
    tags: { store: String(S.storeId) }, // 매장별 지표 분리
  };
}

// VU 번호 → (매장, 터미널) 결정론적 매핑
function assign() {
  const idx = (__VU - 1) % TOTAL_TERMINALS;
  const storeIdx = idx % STORES.length; // 라운드로빈 → 매장들이 번갈아 발생
  const termNo = Math.floor(idx / STORES.length) + 1;

  return { store: STORES[storeIdx], n: ((termNo - 1) % PER_STORE) + 1 };
}

function boot() {
  const { store, n } = assign();
  const username = `lt_s${store}_${n}`;

  const lr = http.post(
    `${BASE_URL}/auth/login`,
    JSON.stringify({
      emailOrUsername: username,
      password: PASSWORD,
      deviceFingerprint: `lt-s${store}-fp-${n}`,
    }),
    { headers: { 'Content-Type': 'application/json' }, timeout: '30s' },
  );

  if (!check(lr, { 'burst login 200': (r) => r.status === 200 })) return false;

  const b = lr.json();
  S = {
    jwt: b.accessToken || b.token,
    sessionToken: b.sessionToken || '',
    storeId: null,
    branchId: null,
    clientId: null,
    products: [],
    efectivoId: 1,
    username,
  };

  const res = http.batch([
    ['GET', `${BASE_URL}/auth/me`, null, headers()],
    ['GET', `${BASE_URL}/products`, null, headers()],
    ['GET', `${BASE_URL}/payment-methods`, null, headers()],
    ['GET', `${BASE_URL}/clients?page=0&pageSize=20`, null, headers()],
  ]);

  try {
    const me = res[0].json();
    S.storeId = me.storeId;
    S.branchId = me.branchId;

    const pl = res[1].json();
    const plist = Array.isArray(pl) ? pl : pl.data || [];
    S.products = plist.slice(0, 50).map((p) => ({
      id: p.id,
      price: Number(p.price || p.salePrice || 100),
    }));

    const pms = res[2].json();
    const pmList = Array.isArray(pms) ? pms : pms.data || [];
    const ef = pmList.find((m) => (m.slug || m.name || '').toLowerCase().includes('efectivo'));
    if (ef) S.efectivoId = ef.id;

    const cl = res[3].json();
    const clist = Array.isArray(cl) ? cl : cl.data || [];
    if (clist.length > 0) S.clientId = clist[0].id;
  } catch (e) {
    S = null;

    return false;
  }

  const ready = S.products.length > 0 && S.clientId != null && S.storeId != null;
  if (!ready) S = null;

  return ready;
}

export default function () {
  if (!S && !boot()) return;

  const p = S.products[Math.floor(Math.random() * S.products.length)];
  const qty = 1 + Math.floor(Math.random() * 3);
  const total = p.price * qty;

  const res = http.post(
    `${BASE_URL}/sales`,
    JSON.stringify({
      clientId: S.clientId,
      storeId: S.storeId,
      branchId: S.branchId,
      status: 'Pagado',
      subtotal: total,
      totalAmount: total,
      // ★ 사후 대조용 마커 — notes 에 VU/매장/반복 번호를 심어
      //   "요청했는데 DB 에 없는 건"을 정확히 특정할 수 있게 한다.
      notes: `BURST|${S.username}|vu${__VU}|it${__ITER}`,
      items: [{ productId: p.id, quantity: qty, price: p.price, total }],
      paymentMethods: [{ paymentMethodId: S.efectivoId, amount: total }],
      printTicket: false,
    }),
    headers(),
  );

  saleMs.add(res.timings.duration);

  if (check(res, { 'burst sale 201/200': (r) => r.status === 201 || r.status === 200 })) {
    saleOk.add(1);
  } else {
    saleErr.add(1);
    if (res.status === 401) S = null; // 세션 만료 → 재부팅
    console.error(`sale 실패 store=${S ? S.storeId : '?'} status=${res.status} body=${String(res.body).slice(0, 200)}`);
  }
}
