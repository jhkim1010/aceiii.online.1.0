#!/usr/bin/env bash
# =============================================================================
# srv803182 (62.72.7.245) 운영 서버에 wiljac SSH 계정 생성
#   - 인증: SSH 공개키만 (비밀번호 로그인 불가)
#   - 권한: 전체 sudo (NOPASSWD) + docker / jenkins 그룹
#   - 용도: docker, Jenkins, MongoDB 전체 운영 작업
#
# ※ 이 계정은 root 와 동등한 권한을 갖습니다. 신뢰하는 사람에게만 부여하세요.
#
# 실행 위치: Mac 로컬 터미널 (jhkim-server SSH alias 사용)
# 사용법: bash add-wiljac-user.sh
# =============================================================================
set -euo pipefail

# ---- 1. 설정 ---------------------------------------------------------------
NEW_USER="wiljac"
SSH_HOST="${SSH_HOST:-jhkim-server}"

# Wiljac Aular 의 공개키 (2026-08-12 사용자 제공)
WILJAC_PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKuID1mNDIzT50IXt3Ih3nYTiqdTzfi6B8a+Gqz0+6Tk Wiljac Aular"

# ---- 2. 사전 점검 (읽기 전용) ----------------------------------------------
echo "=== 사전 점검 ==="
ssh "$SSH_HOST" bash -s <<EOF
  echo '- OS:'; . /etc/os-release && echo "  \$PRETTY_NAME"
  echo '- 기존 $NEW_USER 계정:'; id $NEW_USER 2>/dev/null || echo '  (없음 — 신규 생성 진행)'
  echo '- sudo 그룹명 확인:'
  getent group sudo  >/dev/null && echo '  sudo  있음 (Debian/Ubuntu 계열)'
  getent group wheel >/dev/null && echo '  wheel 있음 (RHEL 계열)'
  echo '- docker 그룹:';  getent group docker  || echo '  (없음 — docker 미설치?)'
  echo '- jenkins 그룹:'; getent group jenkins || echo '  (없음 — Jenkins 미설치?)'
  echo '- MongoDB 설치 여부:'
  command -v mongod mongosh mongo 2>/dev/null || echo '  (mongod/mongosh 없음 — 컨테이너 안에서 도는지 확인 필요)'
  sudo docker ps --format '  container: {{.Names}} ({{.Image}})' 2>/dev/null | grep -i mongo || true
  echo '- sshd 인증 설정:'
  sudo sshd -T 2>/dev/null | grep -E '^(passwordauthentication|pubkeyauthentication|permitrootlogin)' | sed 's/^/  /' || true
EOF

cat <<'WARN'

--------------------------------------------------------------------
경고: 아래 진행 시 wiljac 은 root 와 동등한 권한을 갖게 됩니다.
      (NOPASSWD sudo + docker 그룹)
      운영 DB(PostgreSQL 5434), 배포, 서버 재시작 모두 가능해집니다.
--------------------------------------------------------------------
WARN
read -rp $'계속 진행할까요? (y/N) ' ok
[[ "$ok" == "y" || "$ok" == "Y" ]] || { echo "취소됨"; exit 0; }

# ---- 3. 계정 생성 + 공개키 등록 --------------------------------------------
echo "=== 계정 생성 ==="
ssh "$SSH_HOST" "sudo bash -s" <<EOF
set -euo pipefail

if ! id $NEW_USER >/dev/null 2>&1; then
  useradd -m -s /bin/bash -c 'Wiljac Aular (ops)' $NEW_USER
  echo '계정 생성 완료: $NEW_USER'
else
  echo '계정이 이미 존재합니다 — 키/권한만 갱신합니다'
fi

# 비밀번호 로그인 차단 (공개키 로그인은 정상 동작)
passwd -l $NEW_USER >/dev/null

# authorized_keys 등록 (기존 키가 있으면 덮어씀)
install -d -m 700 -o $NEW_USER -g $NEW_USER /home/$NEW_USER/.ssh
echo '$WILJAC_PUBKEY' > /home/$NEW_USER/.ssh/authorized_keys
chown $NEW_USER:$NEW_USER /home/$NEW_USER/.ssh/authorized_keys
chmod 600 /home/$NEW_USER/.ssh/authorized_keys
echo '공개키 등록 완료'
EOF

# ---- 4. 그룹 부여 (docker / jenkins) ---------------------------------------
echo "=== 그룹 부여 ==="
ssh "$SSH_HOST" "sudo bash -s" <<EOF
set -euo pipefail
for g in docker jenkins; do
  if getent group "\$g" >/dev/null; then
    usermod -aG "\$g" $NEW_USER && echo "  + \$g 그룹 추가"
  else
    echo "  ! \$g 그룹 없음 — 건너뜀"
  fi
done
EOF

# ---- 5. 전체 sudo 부여 ------------------------------------------------------
# 비밀번호가 잠겨 있으므로(공개키 전용) NOPASSWD 여야 sudo 가 동작합니다.
# 비밀번호를 물어보게 하려면 아래 sudoers 에서 NOPASSWD: 를 지우고
# 서버에서 `sudo passwd wiljac` 로 비밀번호를 설정하십시오.
echo "=== sudo 권한 설치 ==="
ssh "$SSH_HOST" "sudo bash -s" <<'EOF'
set -euo pipefail
TMP=$(mktemp)
cat > "$TMP" <<'SUDOERS'
# wiljac — 운영 서버 전체 관리 권한 (2026-08-12)
# docker / Jenkins / MongoDB 운영 작업용. root 와 동등한 권한임.
# 회수: rm /etc/sudoers.d/50-wiljac
wiljac ALL=(ALL:ALL) NOPASSWD: ALL
SUDOERS

# 문법 검증 후에만 설치 (문법 오류 시 sudo 전체가 망가지는 것을 방지)
if visudo -cqf "$TMP"; then
  install -m 440 -o root -g root "$TMP" /etc/sudoers.d/50-wiljac
  echo 'sudoers 설치 완료: /etc/sudoers.d/50-wiljac'
else
  echo '[중단] sudoers 문법 오류 — 설치하지 않음' >&2
  rm -f "$TMP"; exit 1
fi
rm -f "$TMP"
EOF

# ---- 6. 검증 ---------------------------------------------------------------
echo "=== 검증 ==="
ssh "$SSH_HOST" bash -s <<EOF
  echo '- 계정 정보:'; id $NEW_USER
  echo '- 소속 그룹:'; groups $NEW_USER
  echo '- authorized_keys:'; sudo ls -la /home/$NEW_USER/.ssh/
  echo '- 허용된 sudo 명령:'; sudo -l -U $NEW_USER
EOF

cat <<'MSG'

=== 완료 ===

[wiljac 에게 안내할 내용]
  ssh wiljac@62.72.7.245

  ~/.ssh/config 등록:
    Host ventago
      HostName 62.72.7.245
      User wiljac
      IdentityFile ~/.ssh/id_ed25519

  docker 그룹은 재로그인 후 적용됩니다. 첫 접속에서 permission denied 가
  나면 로그아웃 후 다시 접속하거나 `newgrp docker` 를 실행하세요.

[별도로 해줘야 하는 것 — 이 스크립트로는 안 됨]
  1) Jenkins 웹 UI 계정
     Jenkins 는 자체 사용자 DB를 씁니다(OS 계정과 무관).
     Manage Jenkins → Users → Create User 에서 wiljac 계정을 따로 만들고
     Manage Jenkins → Security → Authorization 에서 권한을 부여하세요.
  2) MongoDB 인증
     mongod 가 --auth 로 떠 있으면 OS 계정과 무관하게 DB 사용자가 필요합니다:
       use admin
       db.createUser({user:"wiljac", pwd:passwordPrompt(),
                      roles:[{role:"readWrite", db:"<DB명>"}]})

[감사 로그]
  sudo 사용 내역:  sudo journalctl _COMM=sudo --since today
  SSH 로그인 내역: sudo journalctl -u ssh --since today | grep wiljac

[회수]
  ssh jhkim-server "sudo rm -f /etc/sudoers.d/50-wiljac && sudo userdel -r wiljac"
[접속만 임시 차단]
  ssh jhkim-server "sudo usermod -s /usr/sbin/nologin wiljac"
MSG
