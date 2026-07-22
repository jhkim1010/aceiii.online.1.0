#!/bin/bash
# ============================================================================
# Phase 60 Wave B1-FIX2 (2026-07-21) — minio·deploy 443 auth 를 location 내부로
#   서버레벨 auth 가 이 환경에서 location 상속 안 됨(200/403 유지).
#   cooldb·portainer 처럼 location / 내부(proxy_pass 앞)에 삽입 = 검증된 패턴.
# 실행: ssh jhkim@62.72.7.245 'bash -s' < tools/phase60-wave-b1-fix2.sh
# ============================================================================
set -uo pipefail
TS=$(date +%s)
for N in minio deploy; do
  F=/etc/nginx/sites-enabled/$N.coolsistema.com.conf
  echo "== $N: 443 location 내부에 auth 삽입 =="
  sudo cp "$F" "$F.locfix.bak.$TS"
  sudo python3 - "$F" <<'PYEOF'
import sys
p = sys.argv[1]
lines = open(p).read().split('\n')
# server 블록 범위
blocks, depth, start = [], 0, None
for i, l in enumerate(lines):
    if depth == 0 and 'server' in l and '{' in l: start = i
    depth += l.count('{') - l.count('}')
    if start is not None and depth == 0: blocks.append((start, i)); start = None
tgt = next(((s, e) for s, e in blocks if any('listen 443' in lines[k] for k in range(s, e+1))), None)
if not tgt: print('  !! 443 블록 없음'); sys.exit(0)
s, e = tgt
# 1) 서버레벨(비효과) auth 제거: location 이전에 있는 auth_basic 줄 삭제
loc = next((k for k in range(s, e+1) if 'location' in lines[k] and '{' in lines[k]), e)
keep = [l for idx, l in enumerate(lines)
        if not (s <= idx < loc and 'auth_basic' in l)]
# 인덱스 재계산
lines = keep
blocks, depth, start = [], 0, None
for i, l in enumerate(lines):
    if depth == 0 and 'server' in l and '{' in l: start = i
    depth += l.count('{') - l.count('}')
    if start is not None and depth == 0: blocks.append((start, i)); start = None
s, e = next((b for b in blocks if any('listen 443' in lines[k] for k in range(b[0], b[1]+1))))
loc = next(k for k in range(s, e+1) if 'location' in lines[k] and '{' in lines[k])
# 2) location 내부에 이미 auth 있으면 skip
if any('auth_basic' in lines[k] for k in range(loc, e+1)):
    print('  location 에 이미 auth 있음 — skip'); open(p,'w').write('\n'.join(lines)); sys.exit(0)
new = lines[:loc+1] + ['    auth_basic "Restricted";',
                       '    auth_basic_user_file /etc/nginx/.htpasswd-admin;'] + lines[loc+1:]
open(p, 'w').write('\n'.join(new))
print('  삽입 완료 (443 location / 내부)')
PYEOF
done

echo "== nginx 검증·reload (실패 시 자동 원복) =="
if sudo nginx -t 2>/dev/null; then
  sudo systemctl reload nginx; echo "  reload 완료"
else
  echo "  !! 문법오류 — 원복"
  for N in minio deploy; do sudo cp "/etc/nginx/sites-enabled/$N.coolsistema.com.conf.locfix.bak.$TS" "/etc/nginx/sites-enabled/$N.coolsistema.com.conf"; done
  sudo nginx -t && sudo systemctl reload nginx; echo "  원복 완료"; exit 1
fi

echo "== 최종 검증: 4종 모두 401 이어야 정상 =="
for N in cooldb portainer minio deploy; do
  CODE=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 8 "https://$N.coolsistema.com/")
  echo "  $N → HTTP $CODE (기대: 401)"
done
AM=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 8 "https://apiminio.coolsistema.com/minio/health/live")
echo "  apiminio(S3) → HTTP $AM (기대: 200)"
echo "== 인증 성공 로그인 확인: curl -u admin:비번 로 200/302 나오면 정상 =="
