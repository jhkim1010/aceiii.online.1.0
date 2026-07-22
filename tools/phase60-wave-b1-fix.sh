#!/bin/bash
# ============================================================================
# Phase 60 Wave B1-FIX (2026-07-21) — minio·deploy 443 블록에 auth_basic 누락 교정
#   원인: b1 이 첫 proxy_pass(80 블록)에만 삽입 → 443(실접속) 무인증
#   조치: 443 server 블록의 server_name 직후에 서버레벨 auth_basic 삽입(멱등)
#   cooldb·portainer 는 이미 정상(401) → 대상 제외
# 실행: ssh jhkim@62.72.7.245 'bash -s' < tools/phase60-wave-b1-fix.sh
# ============================================================================
set -uo pipefail
TS=$(date +%s)
for N in minio deploy; do
  F=/etc/nginx/sites-enabled/$N.coolsistema.com.conf
  echo "== $N: 443 블록 auth 삽입 =="
  sudo cp "$F" "/etc/nginx/sites-disabled/$N.443fix.bak.$TS" 2>/dev/null || sudo cp "$F" "$F.443fix.bak.$TS"
  sudo python3 - "$F" <<'PYEOF'
import sys
p = sys.argv[1]
lines = open(p).read().split('\n')
# server 블록 범위 파싱(brace depth)
blocks, depth, start = [], 0, None
for idx, l in enumerate(lines):
    if depth == 0 and 'server' in l and '{' in l:
        start = idx
    depth += l.count('{') - l.count('}')
    if start is not None and depth == 0:
        blocks.append((start, idx)); start = None
# listen 443 을 포함한 블록 찾기
tgt = next(((s, e) for s, e in blocks if any('listen 443' in lines[k] for k in range(s, e+1))), None)
if not tgt:
    print('  !! 443 블록 없음 — skip'); sys.exit(0)
s, e = tgt
if any('auth_basic' in lines[k] for k in range(s, e+1)):
    print('  이미 적용됨 — skip'); sys.exit(0)
ins = next((k for k in range(s, e+1) if 'server_name' in lines[k]), s)
new = lines[:ins+1] + ['    auth_basic "Restricted";',
                       '    auth_basic_user_file /etc/nginx/.htpasswd-admin;'] + lines[ins+1:]
open(p, 'w').write('\n'.join(new))
print('  삽입 완료 (443 server_name 직후, 서버레벨)')
PYEOF
done

echo "== nginx 검증·reload (실패 시 자동 원복) =="
if sudo nginx -t 2>/dev/null; then
  sudo systemctl reload nginx; echo "  reload 완료"
else
  echo "  !! 문법오류 — 원복"
  for N in minio deploy; do
    B=$(ls -t /etc/nginx/sites-disabled/$N.443fix.bak.$TS /etc/nginx/sites-enabled/$N.coolsistema.com.conf.443fix.bak.$TS 2>/dev/null | head -1)
    [ -n "${B:-}" ] && sudo cp "$B" /etc/nginx/sites-enabled/$N.coolsistema.com.conf
  done
  sudo nginx -t && sudo systemctl reload nginx; echo "  원복 완료"; exit 1
fi

echo "== 최종 검증: 4종 모두 401 이어야 정상 =="
for N in cooldb portainer minio deploy; do
  CODE=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 8 "https://$N.coolsistema.com/")
  echo "  $N.coolsistema.com → HTTP $CODE (기대: 401)"
done
AM=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 8 "https://apiminio.coolsistema.com/minio/health/live")
echo "  apiminio(S3) → HTTP $AM (기대: 200 — 앱 무영향)"
