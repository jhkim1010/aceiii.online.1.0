#!/bin/zsh
# 로컬 클론들이 origin 보다 뒤처졌는지 확인하고, 뒤처졌으면 macOS 알림을 띄운다.
# launchd(com.ventago.git-fetch-notify)에서 로그인 시 + 주기적으로 실행.
# 각 repo 를 개별 처리해 하나가 실패해도 나머지 검사를 막지 않는다.

set -u
ROOT="/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0"
LOG="/tmp/git-fetch-notify.log"
ts() { date '+%Y-%m-%d %H:%M:%S'; }

notify() {
  # $1: 제목, $2: 본문
  /usr/bin/osascript -e "display notification \"$2\" with title \"$1\"" 2>/dev/null || true
}

check_repo() {
  local dir="$1"
  [ -e "$dir/.git" ] || return 0
  local name; name="$(basename "$dir")"

  # 원격 갱신 (네트워크). 실패해도 계속.
  if ! git -C "$dir" fetch --quiet 2>>"$LOG"; then
    echo "$(ts) [$name] fetch 실패" >>"$LOG"; return 0
  fi

  # 비교 기준(upstream) 결정: 추적 브랜치가 있으면 그걸, 없으면 origin/<현재브랜치> 로 폴백
  local upstream cur counts behind ahead
  upstream="$(git -C "$dir" rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null)"
  if [ -z "${upstream:-}" ]; then
    cur="$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)"
    if [ -n "${cur:-}" ] && git -C "$dir" rev-parse --verify --quiet "origin/$cur" >/dev/null 2>&1; then
      upstream="origin/$cur"
    else
      echo "$(ts) [$name] 비교 기준 없음(upstream·origin/현재브랜치 모두 없음)" >>"$LOG"; return 0
    fi
  fi

  counts="$(git -C "$dir" rev-list --left-right --count "${upstream}...HEAD" 2>/dev/null)" || return 0
  behind="$(echo "$counts" | awk '{print $1}')"
  ahead="$(echo "$counts" | awk '{print $2}')"
  echo "$(ts) [$name] behind=$behind ahead=$ahead (기준=$upstream)" >>"$LOG"

  if [ "${behind:-0}" -gt 0 ]; then
    notify "git: $name 뒤처짐" "origin 보다 ${behind}개 뒤 — Mac 에서 git pull --rebase 필요"
  fi
}

echo "$(ts) === git-fetch-notify 시작 ===" >>"$LOG"
check_repo "$ROOT"
for sub in "$ROOT"/*/; do
  check_repo "${sub%/}"
done
echo "$(ts) === 끝 ===" >>"$LOG"
