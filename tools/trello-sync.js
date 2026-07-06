#!/usr/bin/env node
/**
 * Trello 보드 동기화 스크립트 (반자동 유지보수 루프용)
 *
 * 보드(ACE III ver online)의 리스트/카드/코멘트를 JSON 으로 받아
 * .planning/trello-inbox/ 에 저장한다. Claude 일일 스케줄 작업이 이 파일을 읽음.
 *
 * 사용법:
 *   node tools/trello-sync.js
 *
 * 자격 증명: tools/.trello-credentials.json (gitignore 됨)
 *   { "key": "...", "token": "...", "board": "tZfnxQGC" }
 */

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const CRED_PATH = path.join(__dirname, '.trello-credentials.json');
const OUT_DIR = path.join(ROOT, '.planning', 'trello-inbox');

async function main() {
  // 자격 증명 로드
  if (!fs.existsSync(CRED_PATH)) {
    console.error(`[trello-sync] 자격 증명 파일 없음: ${CRED_PATH}`);
    process.exit(1);
  }
  const { key, token, board } = JSON.parse(fs.readFileSync(CRED_PATH, 'utf8'));
  if (!key || !token || !board) {
    console.error('[trello-sync] key/token/board 값이 필요합니다');
    process.exit(1);
  }

  const auth = `key=${key}&token=${token}`;
  const api = (p, q = '') => fetch(`https://api.trello.com/1/${p}?${q}${q ? '&' : ''}${auth}`)
    .then(async r => {
      if (!r.ok) throw new Error(`Trello API ${p} → HTTP ${r.status}: ${await r.text()}`);
      return r.json();
    });

  // ── Hechos 이동 단계 ──
  // triage-state.json 에서 hechosPending=true 인 카드를 "Hechos (Corregidos en nube)"
  // 리스트로 이동. archive 하지 않음 (사용자 지시 2026-07-07: 진척된 카드는 Hechos 로).
  // Claude 루프가 "수정 완료+push 됨" 으로 판정한 카드만 hechosPending 을 세팅한다.
  try {
    const statePath = path.join(OUT_DIR, 'triage-state.json');
    if (fs.existsSync(statePath)) {
      const state = JSON.parse(fs.readFileSync(statePath, 'utf8'));
      const pending = Object.entries(state.cards || {}).filter(
        ([, info]) => info && info.hechosPending === true && !info.movedToHechosAt
      );
      if (pending.length > 0) {
        // 리스트 id 는 하드코딩하지 않고 이름으로 탐색 (보드 구조 변경에 견고)
        const boardLists = await api(`boards/${board}/lists`, 'fields=name');

        // "Hechos (Corregidos en nube)" 우선, 없으면 "Hechos" 로 시작하는 리스트(예: Hechos Semanales)
        const hechosList =
          boardLists.find(l => /^hechos \(corregi/i.test(l.name)) ||
          boardLists.find(l => /^hechos/i.test(l.name));
        if (!hechosList) {
          console.error('[trello-sync] "Hechos..." 리스트를 찾지 못해 이동 스킵');
        } else {
          let changed = false;
          for (const [cardId, info] of pending) {
            const r = await fetch(
              `https://api.trello.com/1/cards/${cardId}?idList=${hechosList.id}&pos=top&${auth}`,
              { method: 'PUT' }
            );
            if (r.ok) {
              info.hechosPending = false;
              info.movedToHechosAt = new Date().toISOString().slice(0, 10);
              changed = true;
              console.log(`[trello-sync] → Hechos: ${cardId.slice(0, 8)}`);
            } else {
              console.error(`[trello-sync] Hechos 이동 실패 ${cardId.slice(0, 8)}: HTTP ${r.status}`);
            }
          }
          if (changed) fs.writeFileSync(statePath, JSON.stringify(state, null, 2));
        }
      }
    }
  } catch (err) {
    // 이동 실패는 sync 를 막지 않음
    console.error(`[trello-sync] Hechos 이동 단계 오류: ${err.message}`);
  }

  // ── 카드 콘텐츠 업데이트 단계 ──
  // pending-card-updates.json 의 항목(desc 교체 + checklist 추가)을 카드에 적용.
  // Manuales 계획 기록 등 Claude 루프가 준비한 콘텐츠를 Mac 네트워크에서 반영한다.
  try {
    const updPath = path.join(OUT_DIR, 'pending-card-updates.json');
    if (fs.existsSync(updPath)) {
      const upd = JSON.parse(fs.readFileSync(updPath, 'utf8'));
      let changed = false;
      let listsCache = null;
      for (const u of upd.updates || []) {
        if (!u || u.appliedAt) continue;
        let cardId = u.cardId;

        if (!cardId && u.createInList && u.name) {
          // 신규 카드 생성 모드 — createInList(리스트 이름) + name (+ desc)
          listsCache = listsCache || (await api(`boards/${board}/lists`, 'fields=name'));
          const target = listsCache.find(l => l.name === u.createInList);
          if (!target) {
            console.error(`[trello-sync] 리스트 "${u.createInList}" 없음 — 카드 생성 스킵`);
            continue;
          }
          const cr = await fetch(`https://api.trello.com/1/cards?${auth}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ idList: target.id, name: u.name, desc: u.desc || '', pos: 'bottom' })
          });
          if (!cr.ok) {
            console.error(`[trello-sync] 카드 생성 실패 (${u.name}): HTTP ${cr.status}`);
            continue;
          }
          const crJson = await cr.json();
          cardId = crJson.id;
          u.cardId = cardId;
        } else if (cardId && typeof u.desc === 'string') {
          // 기존 카드 desc 교체 모드
          const r = await fetch(`https://api.trello.com/1/cards/${cardId}?${auth}`, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ desc: u.desc })
          });
          if (!r.ok) {
            console.error(`[trello-sync] desc 업데이트 실패 ${cardId.slice(0, 8)}: HTTP ${r.status}`);
            continue;
          }
        }

        if (!cardId) continue;
        if (u.checklist && u.checklist.name && Array.isArray(u.checklist.items)) {
          const cl = await fetch(
            `https://api.trello.com/1/cards/${cardId}/checklists?name=${encodeURIComponent(u.checklist.name)}&${auth}`,
            { method: 'POST' }
          );
          if (!cl.ok) {
            console.error(`[trello-sync] checklist 생성 실패 ${cardId.slice(0, 8)}: HTTP ${cl.status}`);
            continue;
          }
          const clJson = await cl.json();
          for (const item of u.checklist.items) {
            const ir = await fetch(
              `https://api.trello.com/1/checklists/${clJson.id}/checkItems?name=${encodeURIComponent(item)}&${auth}`,
              { method: 'POST' }
            );
            if (!ir.ok) console.error(`[trello-sync] checkItem 실패 (${item.slice(0, 30)}…): HTTP ${ir.status}`);
          }
        }
        if (u.attachments && Array.isArray(u.attachments)) {
          // 파일 첨부 모드 — ROOT 상대 경로 (docx 매뉴얼 등)
          for (const rel of u.attachments) {
            const fp = path.join(ROOT, rel);
            if (!fs.existsSync(fp)) {
              console.error(`[trello-sync] 첨부 파일 없음: ${rel}`);
              continue;
            }
            const fd = new FormData();
            fd.append('file', new Blob([fs.readFileSync(fp)]), path.basename(fp));
            const ar = await fetch(`https://api.trello.com/1/cards/${cardId}/attachments?${auth}`, {
              method: 'POST',
              body: fd
            });
            if (!ar.ok) console.error(`[trello-sync] 첨부 실패 (${rel}): HTTP ${ar.status}`);
            else console.log(`[trello-sync] attached: ${path.basename(fp)} → ${cardId.slice(0, 8)}`);
          }
        }

        if (u.checkItems && u.checkItems.checklist && Array.isArray(u.checkItems.items)) {
          // 체크 항목 완료 모드 — 매뉴얼 주제 문서화 완료 시 tildar
          const cardChecklists = await api(`cards/${cardId}/checklists`);
          const targetCl = cardChecklists.find(c => c.name === u.checkItems.checklist);
          if (!targetCl) {
            console.error(`[trello-sync] 체크리스트 "${u.checkItems.checklist}" 없음 (${cardId.slice(0, 8)})`);
          } else {
            for (const itemName of u.checkItems.items) {
              const it = (targetCl.checkItems || []).find(ci => ci.name === itemName);
              if (!it) {
                console.error(`[trello-sync] 체크 항목 없음: ${itemName.slice(0, 40)}…`);
                continue;
              }
              const pr = await fetch(
                `https://api.trello.com/1/cards/${cardId}/checkItem/${it.id}?state=complete&${auth}`,
                { method: 'PUT' }
              );
              if (!pr.ok) console.error(`[trello-sync] 체크 실패 (${itemName.slice(0, 40)}…): HTTP ${pr.status}`);
            }
          }
        }

        u.appliedAt = new Date().toISOString().slice(0, 10);
        changed = true;
        console.log(`[trello-sync] card updated: ${cardId.slice(0, 8)}`);
      }
      if (changed) fs.writeFileSync(updPath, JSON.stringify(upd, null, 2));
    }
  } catch (err) {
    // 업데이트 실패는 sync 를 막지 않음
    console.error(`[trello-sync] 카드 업데이트 단계 오류: ${err.message}`);
  }

  try {
    // 리스트 + 카드 + 최근 액션(코멘트) 병렬 수집
    const [lists, cards, actions] = await Promise.all([
      api(`boards/${board}/lists`, 'fields=name,pos'),
      api(
        `boards/${board}/cards`,
        'fields=name,desc,idList,labels,dateLastActivity,shortUrl,due,closed&attachments=true&attachment_fields=url,name&checklists=all'
      ),
      api(`boards/${board}/actions`, 'filter=commentCard&limit=100')
    ]);

    // 카드에 코멘트 붙이기
    const commentsByCard = {};
    for (const a of actions) {
      const cardId = a.data?.card?.id;
      if (!cardId) continue;
      (commentsByCard[cardId] ||= []).push({
        date: a.date,
        member: a.memberCreator?.fullName || a.memberCreator?.username || '?',
        text: a.data?.text || ''
      });
    }

    const listNameById = Object.fromEntries(lists.map(l => [l.id, l.name]));
    const snapshot = {
      syncedAt: new Date().toISOString(),
      board,
      lists: lists.map(l => ({ id: l.id, name: l.name })),
      cards: cards
        .filter(c => !c.closed)
        .map(c => ({
          id: c.id,
          name: c.name,
          desc: c.desc,
          list: listNameById[c.idList] || c.idList,
          idList: c.idList,
          labels: (c.labels || []).map(l => l.name || l.color),
          lastActivity: c.dateLastActivity,
          url: c.shortUrl,
          attachments: (c.attachments || []).map(a => ({ name: a.name, url: a.url })),
          checklists: (c.checklists || []).map(cl => ({
            name: cl.name,
            items: (cl.checkItems || []).map(i => ({ name: i.name, state: i.state }))
          })),
          comments: commentsByCard[c.id] || []
        }))
    };

    fs.mkdirSync(OUT_DIR, { recursive: true });
    const dateTag = new Date().toISOString().slice(0, 10);
    fs.writeFileSync(path.join(OUT_DIR, `board-${dateTag}.json`), JSON.stringify(snapshot, null, 2));
    fs.writeFileSync(path.join(OUT_DIR, 'latest.json'), JSON.stringify(snapshot, null, 2));

    console.log(
      `[trello-sync] OK — 리스트 ${snapshot.lists.length}개, 카드 ${snapshot.cards.length}개 → .planning/trello-inbox/latest.json`
    );
  } catch (err) {
    // 실패해도 이전 latest.json 은 보존됨
    console.error(`[trello-sync] 실패: ${err.message}`);
    process.exit(1);
  }
}

main();
