#!/usr/bin/env bash
# ------------------------------------------------------------
# GSD plan / wave / phase 완료 감지 → Telegram 알림
#
# 동작:
#   - PostToolUse(Write|Edit) hook 으로 실행 (STATE.md / phase 내 plan/summary 수정 시점)
#   - .planning/STATE.md 의 completed_phases / completed_plans 추출
#   - phase 내 plan 파일들의 wave 와 SUMMARY 존재 여부로 wave 완료 판단
#   - 이전 스냅샷(.claude/hooks/.gsd-snapshot.json) 과 비교
#   - 증가분 발견 시 Telegram 알림 (백그라운드, 비차단)
# ------------------------------------------------------------
set -u

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${HOOK_DIR}/telegram.env"
SNAPSHOT="${HOOK_DIR}/.gsd-snapshot.json"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
STATE_MD="${PROJECT_DIR}/.planning/STATE.md"
PHASES_DIR="${PROJECT_DIR}/.planning/phases"

[[ -f "${ENV_FILE}" && -f "${STATE_MD}" ]] || exit 0
# shellcheck disable=SC1090
source "${ENV_FILE}"
[[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]] || exit 0

HOOK_INPUT="$(cat 2>/dev/null || true)"
# STATE.md 또는 phase 폴더 파일 변경에만 반응 (노이즈 차단)
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
  // 각 phase 디렉토리에서 NN-MM-PLAN.md 와 NN-MM-SUMMARY.md 를 매칭 → wave 별 완료율
  const waveStatus = {};  // { 'phaseKey|wave': 'done'|'partial' }
  const phasesDir = '${PHASES_DIR}';
  if (fs.existsSync(phasesDir)) {
    for (const entry of fs.readdirSync(phasesDir, { withFileTypes: true })) {
      if (!entry.isDirectory()) continue;
      const phaseKey = entry.name;
      const dir = path.join(phasesDir, phaseKey);
      const files = fs.readdirSync(dir);
      // wave 별로 plan/summary 카운트
      const waves = {};  // { waveNum: { total: n, done: m } }
      for (const f of files) {
        const pm = f.match(/^(\d+)-(\d+)-PLAN\.md$/);
        if (!pm) continue;
        const planNum = pm[2];
        // plan frontmatter 에서 wave 읽기
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

# 이전 스냅샷
FIRST_RUN="false"
if [[ -f "${SNAPSHOT}" ]]; then
  PREV_JSON="$(cat "${SNAPSHOT}")"
else
  # 최초 실행: 알림 보내지 않고 스냅샷만 저장 (과거 진행분을 '새로 완료' 로 오인하지 않도록)
  echo "${NOW_JSON}" > "${SNAPSHOT}"
  chmod 600 "${SNAPSHOT}" 2>/dev/null
  exit 0
fi

# 비교 + 메시지 생성
MESSAGE="$(node -e "
  const prev = ${PREV_JSON};
  const now  = ${NOW_JSON};
  const out = [];

  // 1) Phase 완료 (최우선)
  if (now.completedPhases > (prev.completedPhases || 0)) {
    out.push('🎉 *Phase 완료!*');
    out.push('📊 전체: ' + now.completedPhases + '/' + now.totalPhases + ' phases (' + now.percent + '%)');
    out.push('📋 누적 plans: ' + now.completedPlans + '/' + now.totalPlans);
    if (now.desc) out.push('📝 ' + now.desc);
  } else {
    // 2) Wave 완료 (phase 완료 아닐 때만 — phase 완료는 wave 완료를 포함하므로)
    const prevWaves = prev.waveStatus || {};
    const nowWaves = now.waveStatus || {};
    const newlyDoneWaves = [];
    for (const [key, status] of Object.entries(nowWaves)) {
      if (status === 'done' && prevWaves[key] !== 'done') {
        newlyDoneWaves.push(key);
      }
    }
    if (newlyDoneWaves.length > 0) {
      out.push('🌊 *Wave 완료!*');
      for (const k of newlyDoneWaves) {
        const [p, w] = k.split('|');
        out.push('  • ' + p + ' · Wave ' + w);
      }
      out.push('📋 진행: ' + now.completedPlans + '/' + now.totalPlans + ' plans (' + now.percent + '%)');
    } else if (now.completedPlans > (prev.completedPlans || 0)) {
      // 3) Plan 완료 (wave/phase 완료가 아닌 단일 plan 완료)
      const delta = now.completedPlans - prev.completedPlans;
      out.push('✅ *Plan 완료 (+' + delta + ')*');
      out.push('📋 진행: ' + now.completedPlans + '/' + now.totalPlans + ' plans (' + now.percent + '%)');
      out.push('🎯 현재 Phase: ' + now.phase);
      if (now.desc) out.push('📝 ' + now.desc);
    }
  }

  process.stdout.write(out.join('\n'));
" 2>/dev/null)"

# 항상 스냅샷 갱신
echo "${NOW_JSON}" > "${SNAPSHOT}"
chmod 600 "${SNAPSHOT}" 2>/dev/null

[[ -z "${MESSAGE}" ]] && exit 0

PROJECT_NAME="$(basename "${PROJECT_DIR}")"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"

FULL="${MESSAGE}

📁 ${PROJECT_NAME}
🕒 ${TIMESTAMP}"

curl -s --max-time 3 \
  -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d "chat_id=${TELEGRAM_CHAT_ID}" \
  --data-urlencode "text=${FULL}" \
  -d "parse_mode=Markdown" \
  -d "disable_web_page_preview=true" \
  >/dev/null 2>&1 &

exit 0
