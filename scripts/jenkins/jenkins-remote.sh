#!/usr/bin/env bash
# =============================================================================
# Mac 에서 원격으로 Jenkins 파일 교체를 실행하는 래퍼
#
# 하는 일: 교체할 파일을 서버 /tmp 로 올린 뒤 jenkins-replace-files.sh 를
#          원격 실행하고, 끝나면 /tmp 의 임시 파일을 지웁니다.
#
# 준비 (최초 1회):
#   bash jenkins-remote.sh setup
#
# 사용:
#   bash jenkins-remote.sh backup
#   bash jenkins-remote.sh job    ~/Desktop/new-config.xml api-new-coolsistema
#   bash jenkins-remote.sh plugin ~/Downloads/git.jpi git
#   bash jenkins-remote.sh secrets ~/Desktop/jenkins-creds
#
# 두 스크립트(jenkins-remote.sh, jenkins-replace-files.sh)를 같은 폴더에 두세요.
# =============================================================================
set -euo pipefail

SSH_HOST="${SSH_HOST:-jhkim-server}"     # 다른 alias 면: SSH_HOST=ventago bash ...
REMOTE_SCRIPT="/usr/local/sbin/jenkins-replace-files.sh"
LOCAL_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jenkins-replace-files.sh"
STAGE="/tmp/jenkins-stage-$$"

# 원격 임시 파일은 어떤 경로로 끝나든 정리
cleanup() { ssh "$SSH_HOST" "sudo rm -rf $STAGE" 2>/dev/null || true; }
trap cleanup EXIT

# ---- setup: 교체 스크립트를 서버에 설치 -------------------------------------
if [[ "${1:-}" == "setup" ]]; then
  [[ -f "$LOCAL_SCRIPT" ]] || { echo "jenkins-replace-files.sh 를 이 스크립트와 같은 폴더에 두세요" >&2; exit 1; }
  scp "$LOCAL_SCRIPT" "$SSH_HOST:/tmp/jrf.sh"
  ssh "$SSH_HOST" "sudo install -o root -g root -m 750 /tmp/jrf.sh $REMOTE_SCRIPT && rm -f /tmp/jrf.sh"
  echo "설치 완료: $SSH_HOST:$REMOTE_SCRIPT"
  exit 0
fi

# 설치돼 있는지 확인
# 750 root:root 로 설치되므로 일반 사용자의 test -x 는 항상 실패한다 → sudo 필요
ssh "$SSH_HOST" "sudo test -x $REMOTE_SCRIPT" || {
  echo "서버에 스크립트가 없습니다. 먼저 실행하세요:  bash $0 setup" >&2; exit 1; }

CMD="${1:-}"

case "$CMD" in

  # ---- 백업만 (업로드 없음) ------------------------------------------------
  backup)
    ssh -t "$SSH_HOST" "sudo bash $REMOTE_SCRIPT backup"
    ;;

  # ---- Job 설정 교체 -------------------------------------------------------
  job)
    SRC="${2:?사용법: $0 job <로컬 config.xml> <job명>}"
    JOB="${3:?job명이 필요합니다}"
    [[ -f "$SRC" ]] || { echo "파일 없음: $SRC" >&2; exit 1; }

    # Mac 에서 미리 XML 검증 (서버까지 갔다 오기 전에 거름)
    xmllint --noout "$SRC" 2>/dev/null || echo "  (경고: XML 검증 실패 또는 xmllint 없음 — 서버에서 재검증합니다)"

    ssh "$SSH_HOST" "mkdir -p $STAGE && chmod 700 $STAGE"
    scp "$SRC" "$SSH_HOST:$STAGE/config.xml"
    ssh -t "$SSH_HOST" "sudo bash $REMOTE_SCRIPT job $STAGE/config.xml '$JOB'"
    ;;

  # ---- 플러그인 교체 -------------------------------------------------------
  plugin)
    SRC="${2:?사용법: $0 plugin <로컬 파일.jpi> <플러그인명>}"
    NAME="${3:?플러그인명이 필요합니다}"
    [[ -f "$SRC" ]] || { echo "파일 없음: $SRC" >&2; exit 1; }

    echo "주의: Jenkins 가 재시작됩니다. 진행 중인 빌드가 있는지 확인하세요."
    ssh "$SSH_HOST" "sudo docker ps --format '  {{.Names}}' 2>/dev/null | head -5 || true"
    read -rp "계속할까요? (y/N) " ok
    [[ "$ok" == "y" || "$ok" == "Y" ]] || exit 0

    ssh "$SSH_HOST" "mkdir -p $STAGE && chmod 700 $STAGE"
    scp "$SRC" "$SSH_HOST:$STAGE/plugin.jpi"
    ssh -t "$SSH_HOST" "sudo bash $REMOTE_SCRIPT plugin $STAGE/plugin.jpi '$NAME'"
    ;;

  # ---- 자격증명 교체 (위험) ------------------------------------------------
  secrets)
    SRC="${2:?사용법: $0 secrets <secrets/ 와 credentials.xml 이 든 로컬 디렉터리>}"
    [[ -d "$SRC/secrets" && -f "$SRC/credentials.xml" ]] || {
      echo "[중단] $SRC 안에 secrets/ 디렉터리와 credentials.xml 이 모두 있어야 합니다" >&2; exit 1; }

    cat <<'W'
경고: 비밀값이 네트워크를 거쳐 서버 /tmp 에 잠시 저장됩니다.
      작업 후 자동 삭제되지만, 이 Mac 의 원본 디렉터리도 끝나면 지우십시오.
W
    read -rp "계속할까요? (yes 입력) " ok
    [[ "$ok" == "yes" ]] || exit 0

    ssh "$SSH_HOST" "mkdir -p $STAGE && chmod 700 $STAGE"
    # 퍼미션 보존을 위해 tar 로 스트리밍 (scp -r 은 모드가 뭉개질 수 있음)
    tar czf - -C "$SRC" secrets credentials.xml | ssh "$SSH_HOST" "sudo tar xzf - -C $STAGE"
    ssh -t "$SSH_HOST" "sudo bash $REMOTE_SCRIPT secrets $STAGE"
    echo
    echo "로컬 원본도 정리하세요:  rm -rf '$SRC'"
    ;;

  *)
    cat <<USAGE
사용법: bash $0 <명령>

  setup                              서버에 교체 스크립트 설치 (최초 1회)
  backup                             JENKINS_HOME 백업
  job     <로컬 config.xml> <job명>  Job 설정 교체 (무중단)
  plugin  <로컬 파일.jpi> <이름>     플러그인 교체 (Jenkins 재시작)
  secrets <로컬 디렉터리>            자격증명 교체 (Jenkins 재시작, 위험)

환경변수:
  SSH_HOST   접속 alias (기본: jhkim-server)
USAGE
    exit 1 ;;
esac
