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
const PER_STORE = Number(__ENV.PER_STORE || 10); // 매장당 터미널 수

// 매장 목록: 300매장 규모에서는 쉼표 목록이 너무 길어 env 로 넘기기 나쁘다.
// STORES_FILE(한 줄 쉼표 구분 또는 JSON 배열)을 우선 사용하고, 없으면 STORES 를 쓴다.
// open() 은 init 컨텍스트 전용 — 여기서만 호출 가능하다.
function loadStores() {
  const file = __ENV.STORES_FILE;
  if (file) {
    const raw = open(file).trim();
    const parsed = raw.startsWith('[')
      ? JSON.parse(raw)
      : raw.split(/[\s,]+/).filter(Boolean).map(Number);

    if (!parsed.length) {
      throw new Error(`STORES_FILE 이 비어 있다: ${file}`);
    }

    return parsed.map(Number);
  }

  return (__ENV.STORES || '3,6,8,9,11').split(',').map(Number);
}

const STORES = loadStores();

// 매장×터미널 = 전체 가상 터미널 수. 도달률을 감당할 만큼 VU 를 준다.
const TOTAL_TERMINALS = STORES.length * PER_STORE;

// ★ VU 상한: 전체 터미널을 다 띄우면 300매장×10 = 3,000 VU 가 되어 부하생성기 자체가
//   무거워진다. 동시에 필요한 VU 는 "도달률 × 요청 지연" 수준이면 충분하다(Little's Law).
//   단, VU 하나가 터미널 하나이므로 **VU 수가 매장 수보다 적으면 일부 매장은 아예
//   판매하지 않는다** — 다매장 분산을 측정하는 시나리오에서 그건 조용한 커버리지 축소다.
//   그래서 하한을 STORES.length 로 둔다(= 전 매장 최소 1터미널).
const VU_CAP = Number(
  __ENV.VU_CAP ||
    Math.min(TOTAL_TERMINALS, Math.max(50, STORES.length, RATE * 3)),
);

// 실제 커버리지 — 요약에 남겨 "몇 매장이 실제로 판매했는지"를 사후에 알 수 있게 한다.
const ACTIVE_STORES = Math.min(STORES.length, VU_CAP);
const TERMINALS_PER_STORE = Math.max(1, Math.floor(VU_CAP / STORES.length));

// 워밍업: 모든 VU 가 첫 반복에서 로그인하므로, 도달률을 처음부터 최대로 주면
// 로그인 폭주(실측 80건/s 부터 붕괴)로 서버가 아니라 부팅이 병목이 된다.
// WARMUP 이 켜져 있으면 도달률을 단계적으로 올려 로그인을 분산시킨다.
const WARMUP = String(__ENV.WARMUP || 'true') === 'true';

const burstScenario = WARMUP
  ? {
      executor: 'ramping-arrival-rate',
      startRate: Math.max(1, Math.round(RATE / 10)),
      timeUnit: '1s',
      preAllocatedVUs: VU_CAP,
      maxVUs: VU_CAP,
      stages: [
        { duration: '1m', target: Math.max(1, Math.round(RATE / 2)) },
        { duration: '1m', target: RATE },
        { duration: DUR, target: RATE },
      ],
    }
  : {
      executor: 'constant-arrival-rate',
      rate: RATE,
      timeUnit: '1s',
      duration: DUR,
      preAllocatedVUs: VU_CAP,
      maxVUs: VU_CAP,
    };

export const options = {
  scenarios: { burst: burstScenario },
  thresholds: {
    http_req_failed: ['rate<0.001'],
    sale_ms: ['p(95)<300'],
  },
};

const saleMs = new Trend('sale_ms');
const saleOk = new Counter('sale_ok'); // ★ 이 값과 DB 저장 건수가 일치해야 한다
const saleErr = new Counter('sale_err');

// 실행 조건을 로그에 남긴다 — 나중에 결과만 보고 "몇 매장이었지?" 를 추측하지 않도록.
export function setup() {
  console.log(
    `[burst] 매장 ${STORES.length}개 (id ${STORES[0]}~${STORES[STORES.length - 1]}) | ` +
      `목표 ${RATE} 판매/s | VU ${VU_CAP} | 매장당 터미널 ~${TERMINALS_PER_STORE} | ` +
      `실제 판매 매장 ${ACTIVE_STORES}개 | warmup=${WARMUP} | 지속 ${DUR}`,
  );

  if (ACTIVE_STORES < STORES.length) {
    console.warn(
      `[burst] ★ VU 부족으로 ${STORES.length - ACTIVE_STORES}개 매장은 판매하지 않는다. ` +
        `VU_CAP 을 올리거나 RATE 를 낮춰라.`,
    );
  }

  return {};
}

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
