#!/usr/bin/env bash
# ------------------------------------------------------------
# GSD 진행 상황 스냅샷 갱신 hook (알림 없음)
#
# 이전 버전은 매 PostToolUse(Write|Edit) 때마다 Telegram 알림을 보냈으나,
# "Plan 1개 완료"를 "전체 작업 완료"로 오해하게 만드는 false positive 문제가 있었음.
# → 알림은 Stop hook 의 gsd-stop-notify.sh 로 이관.
#
# 이 스크립트는 이제 "진행도 스냅샷 갱신" 역할만 수행.
# .gsd-snapshot.json 이 최신 상태를 유지해야 Stop hook 에서 진행도 한 줄 요약 가능.
# ------------------------------------------------------------
set -u

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SNAPSHOT="${HOOK_DIR}/.gsd-snapshot.json"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
STATE_MD="${PROJECT_DIR}/.planning/STATE.md"
PHASES_DIR="${PROJECT_DIR}/.planning/phases"

[[ -f "${STATE_MD}" ]] || exit 0

HOOK_INPUT="$(cat 2>/dev/null || true)"
# STATE.md 또는 phase 파일 변경에만 반응 (노이즈 차단)
if ! echo "${HOOK_INPUT}" | grep -qE "STATE\.md|/phases/[^\"']*\.md"; then
  exit 0
fi

# ------------------------------------------------------------
# Node 로 STATE.md + phase 디렉토리 스캔하여 구조화된 상태 추출
# ------------------------------------------------------------
NOW_JSON="$(node -e "
  const fs = require('fs');
  const path = require('path');

  // STATE.md 파싱
  const stateTxt = fs.readFileSync('${STATE_MD}', 'utf-8');
  const pick = (re, t=stateTxt) => { const m = t.match(re); return m ? parseInt(m[1], 10) : 0; };
  const completedPhases = pick(/completed_phases:\s*(\d+)/);
  const completedPlans  = pick(/completed_plans:\s*(\d+)/);
  const totalPhases     = pick(/total_phases:\s*(\d+)/);
  const totalPlans      = pick(/total_plans:\s*(\d+)/);
  const percent         = pick(/percent:\s*(\d+)/);
  const phaseMatch      = stateTxt.match(/^Phase:\s*(\d+)/m);
  const phase           = phaseMatch ? parseInt(phaseMatch[1], 10) : 0;
  const descMatch       = stateTxt.match(/stopped_at:\s*\"?([^\"\n]+)\"?/);
  const desc            = descMatch ? descMatch[1].trim() : '';

  // phase 별 wave-completion 맵 계산
  const waveStatus = {};
  const phasesDir = '${PHASES_DIR}';
  if (fs.existsSync(phasesDir)) {
    for (const entry of fs.readdirSync(phasesDir, { withFileTypes: true })) {
      if (!entry.isDirectory()) continue;
      const phaseKey = entry.name;
      const dir = path.join(phasesDir, phaseKey);
      const files = fs.readdirSync(dir);
      const waves = {};
      for (const f of files) {
        const pm = f.match(/^(\d+)-(\d+)-PLAN\.md$/);
        if (!pm) continue;
        const planPath = path.join(dir, f);
        let wave = 1;
        try {
          const head = fs.readFileSync(planPath, 'utf-8').slice(0, 800);
          const wm = head.match(/wave:\s*(\d+)/);
          if (wm) wave = parseInt(wm[1], 10);
        } catch {}
        if (!waves[wave]) waves[wave] = { total: 0, done: 0 };
        waves[wave].total += 1;
        const summaryName = f.replace('-PLAN.md', '-SUMMARY.md');
        if (files.includes(summaryName)) waves[wave].done += 1;
      }
      for (const [w, s] of Object.entries(waves)) {
        const key = phaseKey + '|' + w;
        waveStatus[key] = (s.done === s.total && s.total > 0) ? 'done' : 'partial';
      }
    }
  }

  process.stdout.write(JSON.stringify({
    completedPhases, completedPlans, totalPhases, totalPlans, percent, phase, desc, waveStatus
  }));
" 2>/dev/null)"

[[ -z "${NOW_JSON}" ]] && exit 0

# 스냅샷 갱신만 수행 (알림 전송 없음 — Stop hook 에서 담당)
echo "${NOW_JSON}" > "${SNAPSHOT}"
chmod 600 "${SNAPSHOT}" 2>/dev/null

exit 0
