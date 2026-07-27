/* eslint-disable */
// ============================================================================
// Phase 63 Wave A — POS 부하 테스트 시나리오 (k6)
//
// 실제 POS(nueva-venta) 서버 부하 경로를 재현한다:
//   부팅 1회: login → /auth/me → /products → /payment-methods → /clients
//   반복:     POST /sales (1~4개 아이템, efectivo 결제)
//             10% POST /suspended-sales(hold), 5% GET /sales/daily-stats
//
// ★ 반드시 스테이징 DB(ventago_staging)를 바라보는 api_staging 컨테이너에만 실행.
//   운영 API(5002/newapi)에 직접 실행 금지 — README.md 절차 참조.
//
// 실행 예:
//   k6 run -e BASE_URL=http://127.0.0.1:5012/api -e PRESET=baseline pos-scenario.js
//
// 사전 조건: seed-staging.sql 로 lt_vu_1..N 유저 + IP/디바이스 사전등록 완료
// ============================================================================
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

const BASE_URL = __ENV.BASE_URL || 'http://127.0.0.1:5012/api';
const PASSWORD = __ENV.LT_PASSWORD || 'loadtest123'; // seed-staging.sql 과 일치해야 함
const USER_PREFIX = __ENV.LT_USER_PREFIX || 'lt_vu_';

// ── 프리셋: smoke(연기) / baseline(기준) / stress(한계 탐색) / full(3천 터미널) ──
const PRESETS = {
  // 스크립트/시드 검증용 — 주간에도 안전
  smoke: [
    { duration: '1m', target: 10 },
    { duration: '2m', target: 10 },
    { duration: '30s', target: 0 },
  ],
  // 주간 저강도 램프업 — watchdog.sh 동반 필수.
  // 심야 창을 못 쓸 때 회귀 확인용. 200VU 는 실측상 운영 여유 범위 안이다.
  daylight: [
    { duration: '2m', target: 100 },
    { duration: '4m', target: 200 },
    { duration: '1m', target: 0 },
  ],
  // 500 동시 목표 검증 — 심야 권장
  baseline: [
    { duration: '5m', target: 100 },
    { duration: '5m', target: 300 },
    { duration: '10m', target: 500 },
    { duration: '2m', target: 0 },
  ],
  // 첫 붕괴 지점 탐색 — 심야 전용
  stress: [
    { duration: '5m', target: 500 },
    { duration: '5m', target: 1000 },
    { duration: '5m', target: 1500 },
    { duration: '5m', target: 2000 },
    { duration: '2m', target: 0 },
  ],
  // 300매장 × 10터미널 리허설 (Wave E) — 심야 전용
  full: [
    { duration: '10m', target: 1000 },
    { duration: '10m', target: 2000 },
    { duration: '15m', target: 3000 },
    { duration: '10m', target: 3000 },
    { duration: '3m', target: 0 },
  ],
};
const preset = PRESETS[__ENV.PRESET || 'smoke'];

export const options = {
  scenarios: {
    pos: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: preset,
      gracefulRampDown: '30s',
    },
  },
  thresholds: {
    // Phase 63 합격선: P95 ≤ 300ms, 에러율 < 0.1%
    http_req_duration: ['p(95)<300'],
    http_req_failed: ['rate<0.001'],
    sale_create_ms: ['p(95)<300'],
    login_fail: ['rate<0.01'],
  },
};

const saleTrend = new Trend('sale_create_ms');
const loginFail = new Rate('login_fail');

// VU 별 세션 상태 (VU 컨텍스트에 유지 — 재로그인 최소화.
// active_sessions 는 유저당 1개라 같은 유저 재로그인 시 기존 세션이 죽는다)
let session = null;

function authHeaders() {
  return {
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${session.jwt}`,
      'x-session-token': session.sessionToken || '',
    },
    timeout: '20s',
  };
}

// ── 부팅: 로그인 + 참조 데이터 로드 (실제 POS 첫 진입과 동일) ──
function boot() {
  const vu = __VU;
  const loginRes = http.post(
    `${BASE_URL}/auth/login`,
    JSON.stringify({
      emailOrUsername: `${USER_PREFIX}${vu}`,
      password: PASSWORD,
      deviceFingerprint: `lt-fp-${vu}`, // seed 로 terminal_devices 에 사전등록됨
    }),
    { headers: { 'Content-Type': 'application/json' }, timeout: '20s' },
  );

  const ok = check(loginRes, {
    'login 200': (r) => r.status === 200,
    'login 에 token 존재': (r) => !!(r.json('accessToken') || r.json('token')),
  });
  loginFail.add(!ok);
  if (!ok) {
    // 로그인 실패 시 이 iteration 포기 — throttle 회피를 위해 길게 대기
    sleep(30);
    return false;
  }

  const body = loginRes.json();
  session = {
    jwt: body.accessToken || body.token,
    sessionToken: body.sessionToken || '',
    storeId: null,
    branchId: null,
    clientId: null,
    products: [],
    efectivoId: 1, // 글로벌 efectivo=1 (운영 시드) — /payment-methods 로 갱신
  };

  // 초기 로드 4종 병렬 (POS 진입 시 실제 발생하는 조회들)
  const res = http.batch([
    ['GET', `${BASE_URL}/auth/me`, null, authHeaders()],
    ['GET', `${BASE_URL}/products`, null, authHeaders()],
    ['GET', `${BASE_URL}/payment-methods`, null, authHeaders()],
    // /clients 는 page/pageSize 필수(없으면 400)이고 page 는 **0-based**.
    // (프론트가 MUI TablePagination 0-based 를 그대로 전달 — page=1 은 2페이지)
    ['GET', `${BASE_URL}/clients?page=0&pageSize=20`, null, authHeaders()],
  ]);

  check(res[0], { 'me 200': (r) => r.status === 200 });
  check(res[1], { 'products 200': (r) => r.status === 200 });
  check(res[2], { 'payment-methods 200': (r) => r.status === 200 });
  check(res[3], { 'clients 200': (r) => r.status === 200 });

  try {
    const me = res[0].json();
    session.storeId = me.storeId || me.user?.storeId;
    session.branchId = me.branchId || me.user?.branchId;

    const prods = res[1].json();
    const list = Array.isArray(prods) ? prods : prods.data || [];
    // 판매 가능한 상품 200개만 샘플로 유지 (메모리 절약).
    // 실측: price 는 문자열('13000.00') → Number 변환 필수
    session.products = list.slice(0, 200).map((p) => ({
      id: p.id,
      price: Number(p.price || p.salePrice || 100),
    }));

    const pms = res[2].json();
    const pmList = Array.isArray(pms) ? pms : pms.data || [];
    const efectivo = pmList.find((m) => (m.slug || m.name || '').toLowerCase().includes('efectivo'));
    if (efectivo) session.efectivoId = efectivo.id;

    const clients = res[3].json();
    const clList = Array.isArray(clients) ? clients : clients.data || [];
    if (clList.length > 0) session.clientId = clList[0].id;
  } catch (e) {
    // 파싱 실패 시 세션 무효화 → 다음 iteration 재부팅
    session = null;
    return false;
  }

  return session.products.length > 0 && session.clientId != null;
}

// ── 판매 1건 생성 (핵심 부하 경로) ──
function createSale() {
  const nItems = 1 + Math.floor(Math.random() * 4); // 1~4개 아이템
  const items = [];
  let subtotal = 0;
  for (let i = 0; i < nItems; i++) {
    const p = session.products[Math.floor(Math.random() * session.products.length)];
    const qty = 1 + Math.floor(Math.random() * 3);
    items.push({ productId: p.id, quantity: qty, price: p.price, total: p.price * qty });
    subtotal += p.price * qty;
  }

  const payload = {
    clientId: session.clientId,
    storeId: session.storeId,
    branchId: session.branchId,
    status: 'Pagado',
    subtotal,
    totalAmount: subtotal,
    items,
    paymentMethods: [{ paymentMethodId: session.efectivoId, amount: subtotal }],
    printTicket: false, // 부하테스트에서 print dispatch 제외 (Wave E 에서 별도 검증)
  };

  const res = http.post(`${BASE_URL}/sales`, JSON.stringify(payload), authHeaders());
  saleTrend.add(res.timings.duration);

  const ok = check(res, { 'sale 201/200': (r) => r.status === 201 || r.status === 200 });
  if (res.status === 401) session = null; // 세션 만료 → 재부팅

  return ok;
}

export default function () {
  // 세션 없으면 부팅 (VU 시작 시 1회 + 401 후 재부팅)
  if (!session) {
    if (!boot()) return;
    sleep(1 + Math.random() * 3);
  }

  createSale();

  // 부가 트래픽: 10% hold, 5% daily-stats (실사용 비율 근사)
  const r = Math.random();
  if (r < 0.1) {
    // hold(대기 판매) — storeId/subtotal/totalAmount 필수 (실측 400 응답 반영)
    const p = session.products[Math.floor(Math.random() * session.products.length)];
    http.post(
      `${BASE_URL}/suspended-sales`,
      JSON.stringify({
        clientId: session.clientId,
        storeId: session.storeId,
        branchId: session.branchId,
        subtotal: p.price,
        totalAmount: p.price,
        items: [{ productId: p.id, quantity: 1, price: p.price, total: p.price }],
      }),
      authHeaders(),
    );
  } else if (r < 0.15) {
    http.get(`${BASE_URL}/sales/daily-stats`, authHeaders());
  }

  // think time: 터미널당 판매 간격 (러시아워 근사 20~60초)
  // ※ VU=터미널 모델. 3000 VU × (1건/40초 평균) ≈ 75 sales/s + 부가 호출
  sleep(20 + Math.random() * 40);
}
