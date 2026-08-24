/**
 * Phase 86 검증용 pg 클라이언트 팩토리.
 *
 * `pg` 모듈을 여러 위치에서 찾는다 — 이 스크립트들은 모노레포 워크스페이스 밖
 * (tools/)에 있어서 단순 require('pg') 가 환경에 따라 실패한다.
 *
 * 접속 대상은 **샌드박스 PG18 전용**이다. 운영(5434)·로컬 Mac(5432) 에 붙지 않는다.
 */
const path = require('path');

function resolvePg() {
  const candidates = [
    process.env.PG_MODULE, // 명시 지정
    'pg',
    path.resolve(__dirname, '../../node_modules/pg'), // 모노레포 루트 호이스팅
    path.resolve(__dirname, '../../api-ventago/node_modules/pg'),
    '/tmp/cx/node_modules/pg',
  ].filter(Boolean);

  for (const c of candidates) {
    try {
      return require(c);
    } catch (_) {
      /* 다음 후보 */
    }
  }
  throw new Error(
    `pg 모듈을 찾지 못했습니다. 시도한 경로:\n  ${candidates.join('\n  ')}\n` +
      `해결: 저장소 루트에서 npm i, 또는 PG_MODULE=<경로> 지정.`,
  );
}

const { Client } = resolvePg();

/** 샌드박스 PG18 에 연결된 Client 를 돌려준다 (이미 connect 됨). */
async function connect() {
  const c = new Client({
    host: process.env.PHASE86_PGDIR || '/tmp/pg86',
    port: Number(process.env.PHASE86_PGPORT || 55432),
    user: 'postgres',
    database: 'postgres',
  });
  await c.connect();

  return c;
}

module.exports = { connect };
