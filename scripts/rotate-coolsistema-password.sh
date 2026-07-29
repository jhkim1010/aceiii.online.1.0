#!/bin/bash
# ============================================================
# [Phase 65 W7-3] coolsistema DB 비밀번호 회전 — 운영 서버(srv803182)에서 실행
#
# 실행 방법 (Mac에서):
#   scp scripts/rotate-coolsistema-password.sh jhkim-server:/tmp/rotate.sh
#   ssh jhkim-server "bash /tmp/rotate.sh"
#
# 순서 (무중단 최소화):
#   0) 백업 (userlist / .env / .pgpass)
#   1) 새 비밀번호 생성 (출력하지 않음 — ~/.rotate_tmp, 검증 후 자동 삭제)
#   2) PG18(5434) + 구 PG10(5433) ALTER ROLE — md5 검증자 유지 (pgbouncer auth_type=md5)
#   3) pgbouncer userlist 갱신 + reload  ← 이 시점부터 새 클라이언트 인증은 새 비밀번호
#   4) 앱 .env 갱신 + docker compose up -d (컨테이너 재생성 ~30초)
#   5) ~/.pgpass 갱신
#   6) 검증: PG직접(5434) + pgbouncer 경유(5432) + /api/health
#   7) 성공 시 ~/.rotate_tmp 삭제. 실패 시 백업으로 복구 안내 출력
#
# 롤백 (문제 발생 시):
#   sudo cp /etc/pgbouncer/userlist.txt.bak-20260729 /etc/pgbouncer/userlist.txt && sudo systemctl reload pgbouncer
#   sudo cp <workspace>/.env.bak-20260729 <workspace>/.env && (cd <workspace> && docker compose up -d)
#   구 비밀번호로 ALTER ROLE 되돌리기 (구 비밀번호는 git 이력에 있음 — 그래서 회전하는 것)
# ============================================================
set -e
umask 077
WS=/var/lib/jenkins/workspace/api-new-coolsistema

echo "== 0) 백업 =="
sudo cp /etc/pgbouncer/userlist.txt /etc/pgbouncer/userlist.txt.bak-20260729
sudo cp $WS/.env $WS/.env.bak-20260729
cp ~/.pgpass ~/.pgpass.bak-20260729

echo "== 1) 새 비밀번호 생성 (비노출) =="
openssl rand -base64 30 | tr -d '/+=' | cut -c1-26 > ~/.rotate_tmp
NEW=$(cat ~/.rotate_tmp)
[ ${#NEW} -ge 20 ] || { echo "생성 실패"; exit 1; }

echo "== 2) ALTER ROLE (5434 + 5433, md5 검증자 유지) =="
sudo -u postgres psql -p 5434 -v ON_ERROR_STOP=1 -c "SET password_encryption='md5'; ALTER ROLE coolsistema PASSWORD '$NEW';"
sudo -u postgres psql -p 5433 -v ON_ERROR_STOP=1 -c "SET password_encryption='md5'; ALTER ROLE coolsistema PASSWORD '$NEW';" || echo "(5433 구 클러스터 미기동이면 무시)"

echo "== 3) pgbouncer userlist + reload =="
HASH="md5$(printf '%s' "${NEW}coolsistema" | md5sum | cut -d' ' -f1)"
sudo sed -i "s/^\"coolsistema\".*/\"coolsistema\" \"$HASH\"/" /etc/pgbouncer/userlist.txt
sudo grep -c '^"coolsistema"' /etc/pgbouncer/userlist.txt
sudo systemctl reload pgbouncer

echo "== 4) 앱 .env + 컨테이너 재생성 =="
sudo sed -i "s|^DATABASE_PASSWORD=.*|DATABASE_PASSWORD=$NEW|" $WS/.env
(cd $WS && docker compose up -d)

echo "== 5) .pgpass 갱신 =="
sed -i "s/^\(.*:coolsistema\):.*/\1:$NEW/" ~/.pgpass
chmod 600 ~/.pgpass

echo "== 6) 검증 =="
sleep 25
psql -h 127.0.0.1 -p 5434 -U coolsistema -d ventago -Atc "SELECT 'PG직접 OK'"
psql -h 127.0.0.1 -p 5432 -U coolsistema -d ventago -Atc "SELECT 'pgbouncer OK'"
for i in 1 2 3 4 5 6; do
  R=$(curl -s -m 5 http://localhost:5002/api/health | head -c 60)
  echo "health[$i]: $R"
  echo "$R" | grep -q '"ok":true' && break
  sleep 10
done
echo "$R" | grep -q '"ok":true' || { echo "❌ 앱 헬스 실패 — 롤백 절차 참조 (백업: *.bak-20260729)"; exit 1; }

echo "== 7) 정리 =="
rm -f ~/.rotate_tmp /tmp/rotate.sh
echo "✅ 회전 완료 — 새 비밀번호는 $WS/.env 와 ~/.pgpass 에만 존재"
