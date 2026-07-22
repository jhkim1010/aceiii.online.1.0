#!/bin/bash
# ============================================================================
# Phase 60 Wave B — 긴급 롤백 키트 (2026-07-21)
#   심각한 문제 발생 시 Wave B 변경을 이전 상태로 되돌린다.
#   범위 선택:
#     status : 현재 상태만 표시(변경 없음) — 먼저 이걸로 확인 권장
#     b1     : basic auth 해제 (nginx)
#     b2     : 관리 포트 원복 (compose 원본 복원 + Jenkins override 제거, 재생성)
#     b3     : 인증서 권한 원복 (world 읽기 복원)
#     all    : b1+b2+b3 전부 원복
#   사용: ssh jhkim@62.72.7.245 'bash -s -- status' < tools/phase60-wave-b-rollback.sh
#         ssh jhkim@62.72.7.245 'bash -s -- all'    < tools/phase60-wave-b-rollback.sh
#   ※ Wave A(sshd)는 포함하지 않음(별도). B 구간은 SSH 무관.
# ============================================================================
set -uo pipefail
BASE=/var/lib/jenkins/workspace/certificados
MODE="${1:-}"
newest_bak() { sudo find "$(dirname "$1")" -maxdepth 1 -name "$(basename "$1").bak.*" -size +50c -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-; }
COMPOSE=( /home/coolsistema/infra/pgadmin/docker-compose.yml \
          /home/coolsistema/infra/portainer/docker-compose.yml \
          /home/coolsistema/infra/minio/docker-compose.yml \
          /home/coolsistema/mongodb/docker-compose.yml )
VHOSTS="portainer minio deploy cooldb"

show_status() {
  echo "===== [상태] 외부(0.0.0.0) 노출 포트 ====="
  sudo ss -ltn | awk 'NR>1{print $4}' | grep -E "0.0.0.0|\*:" | sort -u
  echo "===== [상태] 서브도메인 무인증 응답(401=auth걸림) ====="
  for N in $VHOSTS; do echo "  $N → $(curl -sk -o /dev/null -w '%{http_code}' --max-time 8 https://$N.coolsistema.com/)"; done
  echo "===== [상태] 인증서 world-readable 파일 수(0=하드닝됨) ====="
  sudo find "$BASE" -type f -perm -o+r | wc -l
  echo "===== [상태] Jenkins override ====="
  sudo test -f /etc/systemd/system/jenkins.service.d/override.conf && echo "  존재(127.0.0.1 바인딩)" || echo "  없음(원복상태)"
}

rb_b1() {
  echo "===== [B1 롤백] basic auth 해제 ====="
  TS=$(date +%s)
  for N in $VHOSTS; do
    F=/etc/nginx/sites-enabled/$N.coolsistema.com.conf
    sudo cp "$F" "$F.rollbak.$TS"
    sudo sed -i '/auth_basic /d; /auth_basic_user_file/d' "$F"
    echo "  $N: auth_basic 제거"
  done
  if sudo nginx -t 2>/dev/null; then sudo systemctl reload nginx; echo "  reload 완료"; else
    echo "  !! 문법오류 — 백업 원복"; for N in $VHOSTS; do sudo cp "/etc/nginx/sites-enabled/$N.coolsistema.com.conf.rollbak.$TS" "/etc/nginx/sites-enabled/$N.coolsistema.com.conf"; done; sudo systemctl reload nginx; return 1; fi
  for N in $VHOSTS; do echo "  검증 $N → $(curl -sk -o /dev/null -w '%{http_code}' --max-time 8 https://$N.coolsistema.com/) (401 아니면 해제됨)"; done
}

rb_b2() {
  echo "===== [B2 롤백] 관리 포트 원복(compose 원본 복원 + 재생성) ====="
  for CF in "${COMPOSE[@]}"; do
    BAK=$(newest_bak "$CF")
    if [ -z "$BAK" ]; then echo "  !! $CF: 백업없음 — skip"; continue; fi
    sudo cp "$BAK" "$CF"; echo "  복원 $CF <- $(basename "$BAK")"
    sudo docker compose -f "$CF" up -d 2>&1 | tail -1
  done
  echo "  Jenkins override 제거"
  sudo rm -f /etc/systemd/system/jenkins.service.d/override.conf
  sudo systemctl daemon-reload; sudo systemctl restart jenkins
  echo "  (Jenkins 재시작 30~60s)"
  echo "  검증: 외부 노출 포트에 8090/9000/9443/9001/9005/27021/8080 다시 보이면 원복됨"
  sudo ss -ltn | awk 'NR>1{print $4}' | grep -E "0.0.0.0" | sort -u
}

rb_b3() {
  echo "===== [B3 롤백] 인증서 world 읽기 복원 ====="
  sudo chmod -R o+rX "$BASE"
  echo "  world-readable 파일 수(복원 후): $(sudo find "$BASE" -type f -perm -o+r | wc -l)"
}

case "$MODE" in
  status) show_status ;;
  b1) rb_b1 ;;
  b2) rb_b2 ;;
  b3) rb_b3 ;;
  all) rb_b3; rb_b2; rb_b1; echo; echo "== 전체 롤백 완료 =="; show_status ;;
  *) echo "사용법: bash -s -- {status|b1|b2|b3|all}"; echo "  먼저 status 로 현재 상태 확인 권장"; exit 2 ;;
esac
