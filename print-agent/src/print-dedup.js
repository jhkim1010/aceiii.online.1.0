'use strict';

// **한 인쇄 작업은 한 번만 인쇄된다.** 이 파일이 그 불변식을 지킨다.
//
// 왜 여기인가: 중복은 여러 층에서 생긴다 — 같은 POST 두 번, 클라우드와 엣지가
// 겹치는 failover 순간, 소켓 재접속, 지점 브로드캐스트, 사용자의 더블클릭.
// 각 층을 하나씩 막아도 **다음 층이 새로 생기면 다시 뚫린다.** 마지막 관문인
// 에이전트가 「이 작업은 이미 찍었다」를 알면, 어느 경로로 두 번 오든 종이는 한 장이다.
//
// ★ 기록은 **인쇄 전에** 한다(at-most-once). 인쇄 도중 죽으면 그 작업은 안 나온
//   채로 끝난다 — 사용자가 요구한 것이 그 방향이다: 「한 장이 빠지는 것」보다
//   「두 장이 나가는 것」이 나쁘다. 빠진 것은 사람이 재인쇄할 수 있다.
//
// ★ jobId 가 **없는** 이벤트는 막지 않는다. 구버전 서버·엣지와 섞여 돌기 때문이다
//   (그 경우는 종전과 똑같이 동작한다 — 이 파일이 회귀를 만들지 않는다).

// ★ 상한과 만료를 넉넉히 잡는 이유: 여기서 잊는 순간 **그 작업은 다시 인쇄된다.**
//   하루 1,000건을 넘는 지점이면 24h·1000건으로는 같은 날 안에 밀려난다.
//   30일 · 50,000건이면 사람이 재전송을 시도할 수 있는 어떤 창보다 길다.
//   (한 항목이 문자열 40자 + 숫자 → 50,000건이라도 수 MB 수준이다.)
const MAX_ENTRIES = 50000;
const TTL_MS = 30 * 24 * 60 * 60 * 1000;

// jobId → 처리 시각(ms)
const seen = new Map();

let persist = null; // { get(key), set(key, value) } — electron-store 등

function prune(now) {
  for (const [id, ts] of seen) {
    if (now - ts > TTL_MS) seen.delete(id);
  }

  // TTL 로도 안 줄면 오래된 것부터 버린다 (Map 은 삽입 순서를 지킨다)
  while (seen.size > MAX_ENTRIES) {
    const oldest = seen.keys().next().value;

    if (oldest === undefined) break;
    seen.delete(oldest);
  }
}

// 디스크 저장이 실패한 사실을 **알린다**. 조용히 넘어가면 재기동 뒤 그 작업이
// 다시 인쇄되는데, 아무도 이유를 모른다.
let onPersistError = null;

function save() {
  if (!persist) return;

  try {
    persist.set('printJobsSeen', Array.from(seen.entries()));
  } catch (err) {
    // ★ 인쇄 자체는 막지 않는다 — 지금 이 장은 나가야 한다. 다만 「재기동을 넘어선
    //   보장이 지금 깨져 있다」를 남긴다.
    if (typeof onPersistError === 'function') {
      try { onPersistError(err); } catch (_e) { /* 알림 실패는 무시 */ }
    } else {
      console.error('[print-dedup] 원장 저장 실패 — 재기동 시 중복 인쇄 가능:', err?.message);
    }
  }
}

/**
 * 재기동 후에도 기억하게 한다. 에이전트가 재시작하는 사이에 같은 작업이 다시
 * 배달될 수 있다(서버 재전송·소켓 재연결). 메모리만 쓰면 그때 두 장이 나온다.
 */
function attachStore(store, onError) {
  persist = store;
  onPersistError = typeof onError === 'function' ? onError : null;

  try {
    const saved = store.get('printJobsSeen');

    if (Array.isArray(saved)) {
      const now = Date.now();

      for (const [id, ts] of saved) {
        if (typeof id === 'string' && typeof ts === 'number' && now - ts <= TTL_MS) {
          seen.set(id, ts);
        }
      }
    }
  } catch (_e) { /* 손상된 저장값은 무시 — 빈 원장으로 시작 */ }
}

/**
 * 이 작업을 지금 인쇄해도 되는가. **부작용이 있다** — true 를 돌려주는 순간
 * 그 jobId 는 「처리됨」으로 기록된다. 호출부는 곧바로 인쇄해야 한다.
 *
 * @param {*} jobId 서버/엣지가 실은 작업 식별자. 없으면 항상 true(구버전 호환).
 * @returns {boolean} 인쇄해야 하면 true, 이미 찍은 작업이면 false
 */
function claimJob(jobId) {
  if (!jobId || typeof jobId !== 'string') return true;

  const now = Date.now();

  prune(now);

  if (seen.has(jobId)) return false;

  seen.set(jobId, now);
  save();

  return true;
}

/** 시험용 — 원장을 비운다. */
function _reset() {
  seen.clear();
  persist = null;
  onPersistError = null;
}

module.exports = { claimJob, attachStore, _reset, MAX_ENTRIES, TTL_MS };
