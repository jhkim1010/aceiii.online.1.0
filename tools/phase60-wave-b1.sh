#!/bin/bash
# ============================================================================
# Phase 60 Wave B1 (교정판 2026-07-21) — 관리 도구 nginx basic auth 추가
#   대상: portainer / minio(콘솔) / deploy(Jenkins) / cooldb(pgAdmin)
#   ★apiminio(S3) 제외 — 앱 MinIO 클라이언트는 basic 헤더 미전송(걸면 업로드 401)
#   ★기존판의 'api3 중지' 단계 삭제 — oldapi-cool-web-1 는 리포팅에 실사용 중(로그 확인됨)
#   무중단·멱등·nginx 문법오류 시 자동 원복
# 실행: ssh jhkim@62.72.7.245 'bash -s' < tools/phase60-wave-b1.sh
# ============================================================================
set -euo pipefail
CONFS="portainer minio deploy cooldb"
HT=/etc/nginx/.htpasswd-admin

echo "== [사전점검] 대상 서브도메인 baseline =="
for N in $CONFS apiminio; do
  CODE=$(curl -sk -o /dev/null -w '%{http_code}' "https://$N.coolsistema.com/" || echo "ERR")
  echo "  $N.coolsistema.com → HTTP $CODE"
done

echo "== [1] 관리자 비밀번호 생성 (htpasswd, 멱등) =="
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q apache2-utils >/dev/null 2>&1 || true
if sudo test -f "$HT"; then
  echo "  기존 htpasswd 유지 (재생성: sudo rm $HT 후 재실행)"
  PW="(기존 비밀번호 유지)"
else
  PW=$(openssl rand -base64 12 | tr -d '/+=' | cut -c1-14)
  sudo htpasswd -bc "$HT" admin "$PW" >/dev/null 2>&1
  echo "  사용자: admin 생성"
fi

echo "== [2] vhost 4종에 auth_basic 삽입 (백업 후, 멱등) =="
TS=$(date +%s)
sudo mkdir -p /etc/nginx/sites-disabled
for N in $CONFS; do
  F=/etc/nginx/sites-enabled/$N.coolsistema.com.conf
  if ! sudo test -f "$F"; then echo "  $N: vhost 파일 없음 — skip"; continue; fi
  if sudo grep -q "auth_basic" "$F"; then echo "  $N: 이미 적용됨 — skip"; continue; fi
  sudo cp "$F" "/etc/nginx/sites-disabled/$N.conf.bak.$TS"
  sudo python3 - "$F" <<'PYEOF'
import sys
p = sys.argv[1]
lines = open(p).readlines()
out, done = [], False
for ln in lines:
    # 443 블록의 활성 proxy_pass(127.0.0.1) 바로 앞에 auth + websocket 헤더 삽입
    if (not done) and ('proxy_pass' in ln) and ('127.0.0.1' in ln) and not ln.strip().startswith('#'):
        ind = ln[:len(ln) - len(ln.lstrip())]
        out += [f'{ind}auth_basic "Restricted";\n',
                f'{ind}auth_basic_user_file /etc/nginx/.htpasswd-admin;\n',
                f'{ind}proxy_http_version 1.1;\n',
                f'{ind}proxy_set_header Upgrade $http_upgrade;\n',
                f'{ind}proxy_set_header Connection "upgrade";\n']
        done = True
    out.append(ln)
open(p, 'w').writelines(out)
print('  삽입 완료:', p.split('/')[-1], '' if done else '(!! proxy_pass 미발견 — 수동확인)')
PYEOF
done

echo "== [3] nginx 검증·reload (실패 시 자동 원복) =="
if sudo nginx -t 2>/dev/null; then
  sudo systemctl reload nginx
  echo "  reload 완료"
else
  echo "  !! nginx 문법 오류 — 백업 원복"
  for N in $CONFS; do
    B=$(ls -t /etc/nginx/sites-disabled/$N.conf.bak.$TS 2>/dev/null | head -1)
    [ -n "${B:-}" ] && sudo cp "$B" /etc/nginx/sites-enabled/$N.coolsistema.com.conf
  done
  sudo nginx -t && sudo systemctl reload nginx
  echo "  원복 완료 — 중단"; exit 1
fi

echo "== [4] 검증: 무인증 접근은 401, apiminio 는 영향 없어야 함 =="
for N in $CONFS; do
  CODE=$(curl -sk -o /dev/null -w '%{http_code}' "https://$N.coolsistema.com/")
  echo "  $N.coolsistema.com → HTTP $CODE (기대: 401)"
done
AM=$(curl -sk -o /dev/null -w '%{http_code}' "https://apiminio.coolsistema.com/minio/health/live")
echo "  apiminio(S3 health) → HTTP $AM (기대: 200 — 앱 경로 무영향)"

echo ""
echo "=============================================="
echo " 관리 도구 접속: 사용자 admin / 비밀번호: $PW"
echo " 지금 저장하세요 (다시 출력 안 됨). 이후 각 도구 자체 로그인은 그대로."
echo "=============================================="
