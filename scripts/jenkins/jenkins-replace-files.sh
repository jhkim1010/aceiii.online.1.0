#!/usr/bin/env bash
# =============================================================================
# JENKINS_HOME(/var/lib/jenkins) 파일 안전 교체 절차
#   대상: jobs/*/config.xml, plugins/*.jpi, secrets/ + credentials.xml
#
# 실행 위치: 운영 서버(srv803182) 안에서. sudo 권한 필요.
#   → Mac 에서는 같은 폴더의 jenkins-remote.sh 래퍼를 사용하세요.
#
# ★ 절대 하지 말 것: sudo cp / sudo vim 으로 직접 수정
#    → 파일 소유자가 root 가 되어 Jenkins 데몬이 못 쓰게 되고 빌드가 깨집니다.
#      반드시 이 스크립트의 jput() 또는 `install -o jenkins -g jenkins` 를 쓰세요.
# =============================================================================
set -euo pipefail

JH="${JENKINS_HOME:-/var/lib/jenkins}"
BACKUP_DIR="/var/backups/jenkins"
TS="$(date +%Y%m%d-%H%M%S)"

[[ $EUID -eq 0 ]] || { echo "root 로 실행하세요: sudo bash $0 $*" >&2; exit 1; }

# ---- 공통 헬퍼 --------------------------------------------------------------

# 파일을 올바른 소유권/퍼미션으로 배치
#   jput <원본파일> <대상경로> [모드]
jput() {
  local src="$1" dst="$2" mode="${3:-644}"
  [[ -f "$src" ]] || { echo "원본 없음: $src" >&2; return 1; }
  install -o jenkins -g jenkins -m "$mode" -D "$src" "$dst"
  echo "  교체됨: $dst  ($(stat -c '%U:%G %a' "$dst"))"
}

jenkins_running() { systemctl is-active --quiet jenkins; }

# ---- 0. 백업 (모든 작업 전 필수) -------------------------------------------
cmd_backup() {
  echo "=== 백업 ==="
  mkdir -p "$BACKUP_DIR"
  local out="$BACKUP_DIR/jenkins-home-$TS.tar.gz"

  # 빌드 산출물/워크스페이스는 제외해 크기를 줄임 (복구에 불필요)
  tar czf "$out" \
      --exclude="$JH/workspace" \
      --exclude="$JH/caches" \
      --exclude="$JH/war" \
      -C "$(dirname "$JH")" "$(basename "$JH")"

  chmod 600 "$out"   # secrets 포함 → 다른 사용자 읽기 금지
  echo "백업 완료: $out ($(du -h "$out" | cut -f1))"
  echo "복구: systemctl stop jenkins && tar xzf $out -C $(dirname "$JH") && systemctl start jenkins"
}

# ---- 1. Job 설정 (jobs/<job>/config.xml) ------------------------------------
# Jenkins 를 멈추지 않아도 됩니다. 교체 후 디스크에서 설정을 다시 읽게 합니다.
# 주의: 리로드 전에 웹 UI 에서 해당 Job 을 저장하면 메모리 상태가 디스크를
#       덮어써서 교체분이 날아갑니다. 교체~리로드 사이에는 UI 를 만지지 마세요.
cmd_job() {
  local src="$1" job="$2"
  echo "=== Job 설정 교체: $job ==="

  [[ -d "$JH/jobs/$job" ]] || { echo "[중단] Job 이 없습니다: $JH/jobs/$job" >&2; return 1; }

  # XML 문법 검증 — 깨진 XML 을 넣으면 해당 Job 이 통째로 사라져 보입니다
  if command -v xmllint >/dev/null; then
    xmllint --noout "$src" || { echo "[중단] XML 문법 오류" >&2; return 1; }
  else
    echo "  (xmllint 없음 — XML 검증 생략. apt install libxml2-utils 권장)"
  fi

  # 개별 Job 백업
  cp -a "$JH/jobs/$job/config.xml" "$JH/jobs/$job/config.xml.bak-$TS"
  echo "  이전 설정 백업: config.xml.bak-$TS"

  jput "$src" "$JH/jobs/$job/config.xml" 644

  echo "--- 설정 리로드 ---"
  echo "다음 중 하나를 수행하세요:"
  echo "  a) 웹 UI: Manage Jenkins → Reload Configuration from Disk"
  echo "  b) CLI  : java -jar $JH/war/WEB-INF/lib/cli-*.jar -s http://localhost:8080/ reload-configuration"
  echo "리로드 후 Job 페이지에서 설정이 반영됐는지 확인하세요."
}

# ---- 2. 플러그인 (plugins/*.jpi) --------------------------------------------
# Jenkins 정지 필수. .jpi 옆의 동명 디렉터리는 압축 해제 캐시이므로 반드시
# 함께 지워야 합니다 — 안 지우면 옛 버전이 그대로 로드됩니다(흔한 함정).
cmd_plugin() {
  local src="$1" name="$2"   # name 예: git, workflow-aggregator
  echo "=== 플러그인 교체: $name ==="

  jenkins_running && { echo "Jenkins 정지 중..."; systemctl stop jenkins; }

  # 기존 플러그인 백업
  [[ -f "$JH/plugins/$name.jpi" ]] && \
    cp -a "$JH/plugins/$name.jpi" "$BACKUP_DIR/$name.jpi.bak-$TS" 2>/dev/null || true

  rm -rf "$JH/plugins/$name"           # 압축 해제 캐시 디렉터리
  rm -f  "$JH/plugins/$name.jpi.pinned" \
         "$JH/plugins/$name.hpi" \
         "$JH/plugins/$name.jpi.disabled"
  jput "$src" "$JH/plugins/$name.jpi" 644

  echo "Jenkins 시작..."
  systemctl start jenkins
  sleep 5
  systemctl --no-pager status jenkins | head -5
  echo "확인: Manage Jenkins → Plugins → Installed 에서 버전과 의존성 경고를 보세요."
}

# ---- 3. 자격증명 / 비밀값 (secrets/, credentials.xml) -----------------------
# ★ 가장 위험한 작업입니다.
#   credentials.xml 안의 값은 secrets/master.key + secrets/hudson.util.Secret
#   으로 암호화돼 있습니다. 이 셋은 한 세트라서:
#     - credentials.xml 만 다른 서버에서 가져오면 → 복호화 불가(자격증명 전멸)
#     - secrets/ 만 교체하면 → 기존의 모든 암호화 값이 무효화됨
#   반드시 세 가지를 같은 인스턴스에서 함께 옮기거나, 아예 옮기지 말고
#   Jenkins UI 에서 자격증명을 다시 입력하는 편이 안전합니다.
cmd_secrets() {
  local src_dir="$1"   # secrets/ 와 credentials.xml 이 함께 들어있는 디렉터리
  echo "=== 자격증명 교체 ==="
  cat <<'W'
경고: credentials.xml 과 secrets/ 는 반드시 같은 인스턴스에서 나온 한 세트여야
      합니다. 짝이 안 맞으면 모든 자격증명이 복호화 불가가 되고, Jenkins 는
      조용히 빈 값으로 빌드를 돌려 배포가 실패합니다.
권장  : 파일 교체 대신 Manage Jenkins → Credentials 에서 재입력.
W
  read -rp "그래도 진행할까요? (yes 를 입력) " ok
  [[ "$ok" == "yes" ]] || { echo "취소됨"; return 0; }

  [[ -d "$src_dir/secrets" && -f "$src_dir/credentials.xml" ]] || {
    echo "[중단] $src_dir 안에 secrets/ 와 credentials.xml 이 모두 있어야 합니다" >&2
    return 1; }

  cmd_backup   # 이 작업만큼은 직전 백업을 강제

  jenkins_running && { echo "Jenkins 정지 중..."; systemctl stop jenkins; }

  # secrets/ 는 통째로 교체 (부분 교체 시 키 불일치)
  rm -rf "$JH/secrets"
  cp -a "$src_dir/secrets" "$JH/secrets"
  chown -R jenkins:jenkins "$JH/secrets"
  chmod 700 "$JH/secrets"
  find "$JH/secrets" -type f -exec chmod 600 {} +

  jput "$src_dir/credentials.xml" "$JH/credentials.xml" 600

  echo "Jenkins 시작..."
  systemctl start jenkins
  sleep 8
  echo "확인: Manage Jenkins → Credentials 에서 항목이 보이는지, 그리고"
  echo "      실제 빌드를 1회 돌려 인증이 통과하는지 반드시 검증하세요."
}

# ---- 사용법 -----------------------------------------------------------------
case "${1:-}" in
  backup)  cmd_backup ;;
  job)     cmd_job     "${2:?사용법: $0 job <새config.xml> <job명>}" "${3:?job명 필요}" ;;
  plugin)  cmd_plugin  "${2:?사용법: $0 plugin <새파일.jpi> <플러그인명>}" "${3:?플러그인명 필요}" ;;
  secrets) cmd_secrets "${2:?사용법: $0 secrets <secrets와 credentials.xml 이 든 디렉터리>}" ;;
  *)
    cat <<USAGE
사용법: sudo bash $0 <명령>

  backup                              JENKINS_HOME 전체 백업 (작업 전 항상 먼저)
  job     <config.xml> <job명>        Job 설정 교체 + 리로드 안내 (무중단)
  plugin  <파일.jpi>   <플러그인명>   플러그인 교체 (Jenkins 재시작)
  secrets <디렉터리>                  자격증명 교체 (Jenkins 재시작, 위험)

예시:
  sudo bash $0 backup
  sudo bash $0 job /tmp/new-config.xml api-new-coolsistema
  sudo bash $0 plugin /tmp/git.jpi git
  sudo bash $0 secrets /tmp/jenkins-creds
USAGE
    exit 1 ;;
esac
