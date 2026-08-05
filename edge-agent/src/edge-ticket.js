// [Phase 72-01] edge 티켓 검증 — 서버가 agentKey 로 HMAC 서명한 신원 증명.
//
// 이 파일은 서버의 api-ventago/src/app/offline-sync/edge-ticket.service.ts 와 **같은 형식**을
// 다룬다. 한쪽만 바뀌면 조용히 전부 401 이 되므로, 형식을 바꿀 때는 반드시 양쪽을 함께 고친다.
//
// 형식: base64url(payload).base64url(hmacSha256(agentKey, body))
//   payload = { u: userId, s: storeId, b: branchId, exp: epochSeconds }
//
// 왜 서버 JWT 를 그대로 안 쓰나 — edge 는 JWT_SECRET_KEY 를 갖고 있지 않다. 그래서 예전에는
// 서명을 검증하지 않고 payload 만 읽었고(server.js 구 decodeJwtPayload), 누구나 userId 를
// 위조할 수 있었다. agentKey 는 edge 가 이미 갖고 있으므로 네트워크 없이 검증된다.

const { createHmac, timingSafeEqual } = require('crypto');

function verifyEdgeTicket(ticket, key, nowSec) {
  const parts = String(ticket || '').split('.');

  if (parts.length !== 2) return null;

  const [body, mac] = parts;

  if (!body || !mac || !key) return null;

  const expected = createHmac('sha256', key).update(body).digest();
  let got;

  try {
    got = Buffer.from(mac, 'base64url');
  } catch {
    return null;
  }

  // 길이가 다르면 timingSafeEqual 이 throw 한다 — 먼저 거른다.
  if (got.length !== expected.length) return null;
  if (!timingSafeEqual(got, expected)) return null;

  try {
    const payload = JSON.parse(Buffer.from(body, 'base64url').toString('utf8'));

    if (typeof payload?.exp !== 'number' || payload.exp <= nowSec) return null;
    if (typeof payload?.u !== 'number' || typeof payload?.s !== 'number') return null;

    return payload;
  } catch {
    return null;
  }
}

module.exports = { verifyEdgeTicket };
