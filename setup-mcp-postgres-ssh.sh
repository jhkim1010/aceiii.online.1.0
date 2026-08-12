#!/usr/bin/env bash
# =============================================================================
#  PostgreSQL + MCP 셋업 스크립트
#  대상: macOS (Apple Silicon) / Homebrew postgresql@18 / 계정 marcoskim
#
#  설치 항목
#    1) Postgres MCP  (crystaldba/postgres-mcp)  - DB 직접 접근, 읽기+쓰기
#    2) SSH MCP       (@fangjunjie/ssh-mcp-server) - 로컬 셸에서 psql/brew 실행
#
#  설계 원칙
#    - 암호/패스프레이즈는 스크립트가 만들지 않고 사용자에게 직접 입력받음
#    - 비밀번호는 MCP 설정 JSON에 저장하지 않고 ~/.pgpass 로 분리
#    - SSH 는 127.0.0.1 / ::1 로만 바인딩하여 외부 노출 차단
#    - connection pool 낭비 방지를 위해 role 단위 연결 제한 + idle 타임아웃 설정
#    - 모든 단계는 멱등(idempotent). 재실행해도 안전함
# =============================================================================

set -euo pipefail

# ----- 설정값 ----------------------------------------------------------------
readonly PG_SUPERUSER="$(whoami)"          # Homebrew initdb 는 OS 계정명을 슈퍼유저로 생성
readonly PG_HOST="127.0.0.1"
readonly PG_PORT="5432"
readonly APP_DB="${PG_SUPERUSER}"          # 맨몸 psql 접속용 기본 DB
readonly MCP_ROLE="mcp_agent"              # MCP 전용 role (슈퍼유저 직접 사용 회피)
readonly MCP_POOL_LIMIT=4                  # 이 role 이 동시에 점유 가능한 최대 커넥션
readonly SSH_KEY="${HOME}/.ssh/id_ed25519_mcp"
# sshd 는 '먼저 나온 설정이 이깁니다'. Apple 기본값이 100-macos.conf 이므로
# 반드시 그보다 앞서도록 010 번호를 씁니다.
readonly SSHD_DROPIN="/etc/ssh/sshd_config.d/010-mcp-localhost.conf"

# ----- 출력 유틸 -------------------------------------------------------------
readonly C_OK=$'\033[32m'; readonly C_WARN=$'\033[33m'
readonly C_ERR=$'\033[31m'; readonly C_HDR=$'\033[1;36m'; readonly C_OFF=$'\033[0m'

step() { printf '\n%s▶ %s%s\n' "$C_HDR" "$1" "$C_OFF"; }
ok()   { printf '  %s✓%s %s\n' "$C_OK" "$C_OFF" "$1"; }
warn() { printf '  %s!%s %s\n' "$C_WARN" "$C_OFF" "$1"; }
die()  { printf '\n  %s✗ %s%s\n\n' "$C_ERR" "$1" "$C_OFF" >&2; exit 1; }

# 실패 지점을 알려주는 트랩 (에러 핸들링)
trap 'die "라인 ${LINENO} 에서 실패했습니다. 위 출력을 확인해 주세요."' ERR

# =============================================================================
# 0. 사전 점검
# =============================================================================
step "0/6  사전 점검"

[[ "$(uname -s)" == "Darwin" ]] || die "이 스크립트는 macOS 전용입니다."

command -v brew >/dev/null 2>&1 || die "Homebrew 가 없습니다. https://brew.sh 에서 설치해 주세요."
ok "Homebrew 확인"

command -v psql >/dev/null 2>&1 || die "psql 이 PATH 에 없습니다. 'brew link postgresql@18' 를 실행해 보세요."
ok "psql 확인 ($(psql --version))"

if ! pg_isready -h "$PG_HOST" -p "$PG_PORT" >/dev/null 2>&1; then
  die "PostgreSQL 이 응답하지 않습니다. 'brew services start postgresql@18' 후 다시 실행해 주세요."
fi
ok "PostgreSQL 응답 정상 (${PG_HOST}:${PG_PORT})"

# 슈퍼유저로 postgres DB 에 붙을 수 있는지 확인 — 이후 모든 DDL 의 전제
psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_SUPERUSER" -d postgres -tAc 'SELECT 1' >/dev/null 2>&1 \
  || die "슈퍼유저 '${PG_SUPERUSER}' 로 접속할 수 없습니다."
ok "슈퍼유저 '${PG_SUPERUSER}' 접속 확인"

command -v claude >/dev/null 2>&1 \
  || warn "'claude' CLI 가 없습니다. 5단계 MCP 등록은 건너뛰고 설정 JSON 을 출력합니다."

# =============================================================================
# 1. 데이터베이스 생성 — "database marcoskim does not exist" 해결
# =============================================================================
step "1/6  데이터베이스 준비"

db_exists() {
  psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_SUPERUSER" -d postgres -tAc \
    "SELECT 1 FROM pg_database WHERE datname = '$1'" 2>/dev/null | grep -q 1
}

if db_exists "$APP_DB"; then
  ok "데이터베이스 '${APP_DB}' 이미 존재"
else
  createdb -h "$PG_HOST" -p "$PG_PORT" -U "$PG_SUPERUSER" "$APP_DB"
  ok "데이터베이스 '${APP_DB}' 생성 완료 — 이제 'psql' 만 쳐도 접속됩니다"
fi

# =============================================================================
# 2. MCP 전용 role 생성 + pool 낭비 방지 설정
#    ※ 비밀번호는 사용자가 직접 입력합니다.
# =============================================================================
step "2/6  MCP 전용 role '${MCP_ROLE}' 준비"

role_exists() {
  psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_SUPERUSER" -d postgres -tAc \
    "SELECT 1 FROM pg_roles WHERE rolname = '$1'" 2>/dev/null | grep -q 1
}

printf '\n  %s[사용자 입력]%s DB role "%s" 에 사용할 비밀번호를 정해 주세요.\n' \
       "$C_WARN" "$C_OFF" "$MCP_ROLE"
printf '  (화면에 표시되지 않습니다. 나중에 ~/.pgpass 에 저장됩니다)\n\n'

MCP_PASSWORD=""
while [[ -z "$MCP_PASSWORD" ]]; do
  read -rs -p "  비밀번호        : " MCP_PASSWORD; echo
  read -rs -p "  비밀번호 재확인 : " _confirm;     echo
  if [[ "$MCP_PASSWORD" != "$_confirm" ]]; then
    warn "두 입력이 일치하지 않습니다. 다시 시도해 주세요."; MCP_PASSWORD=""
  elif [[ ${#MCP_PASSWORD} -lt 8 ]]; then
    warn "8자 이상으로 정해 주세요."; MCP_PASSWORD=""
  fi
done
unset _confirm

# SQL 문자열 리터럴 이스케이프 (작은따옴표 중복 처리)
_pw_escaped="${MCP_PASSWORD//\'/\'\'}"

# 비밀번호를 -c 인자로 넘기면 ps 출력에 평문이 노출되므로 stdin 으로 전달합니다
if role_exists "$MCP_ROLE"; then
  psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_SUPERUSER" -d postgres -v ON_ERROR_STOP=1 -q \
    <<<"ALTER ROLE ${MCP_ROLE} WITH LOGIN PASSWORD '${_pw_escaped}';"
  ok "기존 role '${MCP_ROLE}' 비밀번호 갱신"
else
  psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_SUPERUSER" -d postgres -v ON_ERROR_STOP=1 -q \
    <<<"CREATE ROLE ${MCP_ROLE} WITH LOGIN PASSWORD '${_pw_escaped}';"
  ok "role '${MCP_ROLE}' 생성 완료"
fi
unset _pw_escaped

# --- pool 낭비 방지: 연결 상한 + idle 세션 자동 종료 -------------------------
psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_SUPERUSER" -d postgres -v ON_ERROR_STOP=1 -q <<SQL
-- 이 role 이 점유할 수 있는 동시 커넥션 상한. MCP 가 폭주해도 DB 전체를 마비시키지 못함
ALTER ROLE ${MCP_ROLE} CONNECTION LIMIT ${MCP_POOL_LIMIT};

-- 트랜잭션 열어둔 채 방치된 세션을 30초 후 강제 종료 (pool 낭비의 주범)
ALTER ROLE ${MCP_ROLE} SET idle_in_transaction_session_timeout = '30s';

-- 유휴 세션을 5분 후 회수 (PostgreSQL 14+)
ALTER ROLE ${MCP_ROLE} SET idle_session_timeout = '5min';

-- 폭주 쿼리 차단
ALTER ROLE ${MCP_ROLE} SET statement_timeout = '60s';
SQL
ok "pool 가드 적용: 최대 ${MCP_POOL_LIMIT} 커넥션 / idle-in-tx 30s / idle 5min / statement 60s"

# --- 읽기+쓰기 권한 부여 (사용자 선택: read-write) ---------------------------
psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_SUPERUSER" -d "$APP_DB" -v ON_ERROR_STOP=1 -q <<SQL
GRANT CONNECT ON DATABASE ${APP_DB} TO ${MCP_ROLE};
GRANT USAGE, CREATE ON SCHEMA public TO ${MCP_ROLE};
GRANT ALL PRIVILEGES ON ALL TABLES    IN SCHEMA public TO ${MCP_ROLE};
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ${MCP_ROLE};
-- 앞으로 생성될 객체에도 자동 적용
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL PRIVILEGES ON TABLES TO ${MCP_ROLE};
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL PRIVILEGES ON SEQUENCES TO ${MCP_ROLE};
SQL
ok "'${APP_DB}' 에 대한 읽기+쓰기 권한 부여 완료"

# --- 비밀번호를 ~/.pgpass 로 분리 (MCP 설정 JSON 에 평문 저장 회피) ----------
readonly PGPASS="${HOME}/.pgpass"
# readonly 로 선언하면 뒤에서 unset 할 수 없어 스크립트가 중단됩니다 (일반 변수 사용)
PGPASS_LINE="${PG_HOST}:${PG_PORT}:${APP_DB}:${MCP_ROLE}:${MCP_PASSWORD}"

touch "$PGPASS"; chmod 600 "$PGPASS"
# 같은 host:port:db:user 조합의 기존 줄을 제거한 뒤 새로 추가
if [[ -s "$PGPASS" ]]; then
  grep -v "^${PG_HOST}:${PG_PORT}:${APP_DB}:${MCP_ROLE}:" "$PGPASS" > "${PGPASS}.tmp" || true
  mv "${PGPASS}.tmp" "$PGPASS"
fi
printf '%s\n' "$PGPASS_LINE" >> "$PGPASS"
chmod 600 "$PGPASS"
ok "~/.pgpass 에 자격증명 저장 (권한 600)"

# 접속 검증
if PGPASSFILE="$PGPASS" psql -h "$PG_HOST" -p "$PG_PORT" -U "$MCP_ROLE" -d "$APP_DB" \
     -tAc 'SELECT current_user' >/dev/null 2>&1; then
  ok "role '${MCP_ROLE}' 로 실제 접속 검증 성공"
else
  die "role '${MCP_ROLE}' 접속 검증 실패. pg_hba.conf 의 인증 방식을 확인해 주세요."
fi

unset MCP_PASSWORD PGPASS_LINE

# =============================================================================
# 3. SSH 셋업 — localhost 전용 바인딩 후 원격 로그인 활성화
# =============================================================================
step "3/6  SSH 셋업 (127.0.0.1 전용)"

# 3-0. drop-in 이 실제로 읽히는지 먼저 확인.
#      Include 지시자가 없으면 ListenAddress 제한이 조용히 무시되어
#      sshd 가 0.0.0.0 에 열립니다. 반드시 사전에 막아야 합니다.
if ! sudo grep -qE '^\s*Include\s+/etc/ssh/sshd_config\.d/' /etc/ssh/sshd_config 2>/dev/null; then
  warn "/etc/ssh/sshd_config 에 sshd_config.d Include 지시자가 없습니다."
  warn "drop-in 설정이 무시되어 SSH 가 외부에 노출될 수 있습니다."
  die "안전을 위해 중단합니다. /etc/ssh/sshd_config 에 다음 줄을 추가해 주세요:
      Include /etc/ssh/sshd_config.d/*"
fi
ok "sshd_config.d Include 지시자 확인"

# 3-1. 외부 노출을 막는 drop-in 설정을 '먼저' 넣고 나서 sshd 를 켠다 (순서 중요)
if [[ -f "$SSHD_DROPIN" ]]; then
  ok "sshd drop-in 설정 이미 존재: ${SSHD_DROPIN}"
else
  warn "sshd 를 localhost 전용으로 제한합니다. sudo 암호를 입력해 주세요."
  sudo mkdir -p "$(dirname "$SSHD_DROPIN")"
  sudo tee "$SSHD_DROPIN" >/dev/null <<'CONF'
# MCP 전용 SSH 설정 — 루프백에서만 수신하여 외부 노출을 차단합니다.
# 제거하려면 이 파일을 삭제한 뒤 sshd 를 재시작하세요.
ListenAddress 127.0.0.1
ListenAddress ::1
PermitRootLogin no
PermitEmptyPasswords no
PubkeyAuthentication yes
CONF
  sudo chmod 644 "$SSHD_DROPIN"
  ok "생성 완료: ${SSHD_DROPIN} (외부 인터페이스 수신 차단)"
fi

# 3-2. 원격 로그인 활성화
if sudo systemsetup -getremotelogin 2>/dev/null | grep -qi 'On'; then
  ok "원격 로그인 이미 활성화됨"
else
  # macOS 버전에 따라 확인 프롬프트가 뜨므로 yes 로 응답을 흘려보냅니다
  if yes | sudo systemsetup -setremotelogin on >/dev/null 2>&1; then
    ok "원격 로그인 활성화 완료"
  else
    warn "systemsetup 실패 — 터미널에 '전체 디스크 접근 권한'이 없을 수 있습니다."
    warn "시스템 설정 → 일반 → 공유 → 원격 로그인 을 직접 켜신 뒤 스크립트를 다시 실행해 주세요."
    die "원격 로그인을 활성화할 수 없습니다."
  fi
fi

# 3-3. 설정 반영을 위한 sshd 재시작
sudo launchctl kickstart -k system/com.apple.sshd 2>/dev/null || true
sleep 2
ok "sshd 재시작"

# 3-3b. [보안 게이트] sshd 가 루프백에만 묶였는지 실제로 확인.
#       0.0.0.0 이나 * 로 열려 있으면 즉시 되돌리고 중단합니다.
_ssh_binds="$(lsof -nP -iTCP:22 -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {print $9}' || true)"
if [[ -z "$_ssh_binds" ]]; then
  warn "포트 22 에서 수신 중인 sshd 를 찾지 못했습니다. 다음 단계에서 접속이 실패할 수 있습니다."
elif printf '%s\n' "$_ssh_binds" | grep -qE '(^|[^0-9.])(0\.0\.0\.0|\*):22'; then
  warn "sshd 가 모든 인터페이스(0.0.0.0)에 열려 있습니다 — 의도한 상태가 아닙니다."
  warn "원격 로그인을 즉시 끄고 중단합니다."
  yes | sudo systemsetup -setremotelogin off >/dev/null 2>&1 || true
  die "SSH 외부 노출이 감지되어 롤백했습니다. ${SSHD_DROPIN} 적용 여부를 확인해 주세요."
else
  ok "sshd 수신 주소가 루프백으로 제한됨: $(printf '%s' "$_ssh_binds" | tr '\n' ' ')"
fi
unset _ssh_binds

# 3-4. 키 생성 — 패스프레이즈는 사용자가 직접 입력
if [[ -f "$SSH_KEY" ]]; then
  ok "SSH 키 이미 존재: ${SSH_KEY}"
else
  printf '\n  %s[사용자 입력]%s SSH 키 패스프레이즈를 정해 주세요.\n' "$C_WARN" "$C_OFF"
  printf '  (그냥 Enter 를 누르면 패스프레이즈 없이 생성됩니다 — 이 경우 MCP 설정이 더 간단해집니다)\n\n'
  ssh-keygen -t ed25519 -f "$SSH_KEY" -C "mcp-local-$(date +%Y%m%d)"
  ok "SSH 키 생성 완료: ${SSH_KEY}"
fi
chmod 600 "$SSH_KEY"; chmod 644 "${SSH_KEY}.pub"

# 3-5. authorized_keys 등록 (중복 방지)
mkdir -p "${HOME}/.ssh"; chmod 700 "${HOME}/.ssh"
readonly AUTH_KEYS="${HOME}/.ssh/authorized_keys"
touch "$AUTH_KEYS"; chmod 600 "$AUTH_KEYS"

if grep -qF "$(cut -d' ' -f2 "${SSH_KEY}.pub")" "$AUTH_KEYS" 2>/dev/null; then
  ok "공개키 이미 등록됨"
else
  cat "${SSH_KEY}.pub" >> "$AUTH_KEYS"
  ok "authorized_keys 에 공개키 등록"
fi

# 3-6. known_hosts 등록 — 등록하지 않으면 MCP 가 호스트 검증에서 멈춥니다
ssh-keyscan -p 22 -H "$PG_HOST" 2>/dev/null >> "${HOME}/.ssh/known_hosts" || true
sort -u "${HOME}/.ssh/known_hosts" -o "${HOME}/.ssh/known_hosts" 2>/dev/null || true
ok "known_hosts 등록"

# 3-7. 접속 검증
if ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=5 \
       -o StrictHostKeyChecking=accept-new \
       "${PG_SUPERUSER}@${PG_HOST}" 'echo ok' 2>/dev/null | grep -q ok; then
  ok "SSH 접속 검증 성공 (패스프레이즈 없음)"
  SSH_HAS_PASSPHRASE="no"
else
  warn "BatchMode 검증 실패 — 패스프레이즈가 설정된 키로 보입니다 (정상입니다)."
  warn "MCP 설정에 --passphrase 인자를 추가하셔야 합니다."
  SSH_HAS_PASSPHRASE="yes"
fi

# =============================================================================
# 4. MCP 서버 패키지 설치
# =============================================================================
step "4/6  MCP 패키지 설치"

# 4-1. Postgres MCP (Python) — uv 가 있으면 uvx, 없으면 pipx 사용
if command -v uv >/dev/null 2>&1; then
  PG_MCP_CMD="uvx"; PG_MCP_ARGS="postgres-mcp"
  ok "uv 감지 — uvx 로 실행합니다 (별도 설치 불필요)"
elif command -v pipx >/dev/null 2>&1; then
  pipx install postgres-mcp >/dev/null 2>&1 || pipx upgrade postgres-mcp >/dev/null 2>&1 || true
  PG_MCP_CMD="postgres-mcp"; PG_MCP_ARGS=""
  ok "pipx 로 postgres-mcp 설치 완료"
else
  warn "uv / pipx 둘 다 없습니다. uv 를 설치합니다."
  brew install uv
  PG_MCP_CMD="uvx"; PG_MCP_ARGS="postgres-mcp"
  ok "uv 설치 완료"
fi

# 4-2. SSH MCP (Node) — npx 로 실행하므로 사전 설치는 캐시 목적
command -v node >/dev/null 2>&1 || { warn "Node.js 가 없습니다. 설치합니다."; brew install node; }
ok "Node.js 확인 ($(node --version))"

# =============================================================================
# 5. Claude 에 MCP 서버 등록
# =============================================================================
step "5/6  MCP 서버 등록"

# 비밀번호를 URI 에 넣지 않습니다 — psycopg 가 ~/.pgpass 를 자동으로 읽습니다
readonly DATABASE_URI="postgresql://${MCP_ROLE}@${PG_HOST}:${PG_PORT}/${APP_DB}"

if command -v claude >/dev/null 2>&1; then
  # 기존 등록이 있으면 제거 후 재등록 (멱등성 확보)
  claude mcp remove postgres  --scope user 2>/dev/null || true
  claude mcp remove local-ssh --scope user 2>/dev/null || true

  claude mcp add postgres --scope user \
    -e "DATABASE_URI=${DATABASE_URI}" \
    -e "PGPASSFILE=${HOME}/.pgpass" \
    -- ${PG_MCP_CMD} ${PG_MCP_ARGS} --access-mode=unrestricted
  ok "'postgres' MCP 등록 완료 (읽기+쓰기 모드)"

  if [[ "$SSH_HAS_PASSPHRASE" == "no" ]]; then
    claude mcp add local-ssh --scope user \
      -- npx -y @fangjunjie/ssh-mcp-server \
         --host "$PG_HOST" --port 22 \
         --username "$PG_SUPERUSER" --privateKey "$SSH_KEY"
    ok "'local-ssh' MCP 등록 완료"
  else
    warn "패스프레이즈가 있는 키라 자동 등록을 건너뜁니다."
    warn "아래 명령의 <패스프레이즈> 를 채워서 직접 실행해 주세요:"
    printf '\n    claude mcp add local-ssh --scope user -- \\\n'
    printf '      npx -y @fangjunjie/ssh-mcp-server \\\n'
    printf '      --host %s --port 22 --username %s \\\n' "$PG_HOST" "$PG_SUPERUSER"
    printf '      --privateKey %s --passphrase "<패스프레이즈>"\n\n' "$SSH_KEY"
  fi
else
  warn "'claude' CLI 가 없어 자동 등록을 건너뜁니다. 아래를 직접 실행해 주세요:"
  printf '\n    claude mcp add postgres --scope user \\\n'
  printf '      -e DATABASE_URI="%s" \\\n' "$DATABASE_URI"
  printf '      -e PGPASSFILE="%s/.pgpass" \\\n' "$HOME"
  printf '      -- %s %s --access-mode=unrestricted\n\n' "$PG_MCP_CMD" "$PG_MCP_ARGS"
fi

# =============================================================================
# 6. 최종 검증
# =============================================================================
step "6/6  최종 검증"

printf '\n  --- 현재 커넥션 상태 (pool 점검) ---\n'
psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_SUPERUSER" -d postgres -c "
SELECT state,
       count(*) AS sessions,
       max(now() - state_change) AS oldest
FROM pg_stat_activity
WHERE backend_type = 'client backend'
GROUP BY state
ORDER BY sessions DESC;"

psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_SUPERUSER" -d postgres -c "
SELECT rolname,
       rolconnlimit AS conn_limit,
       rolconfig    AS session_guards
FROM pg_roles
WHERE rolname = '${MCP_ROLE}';"

printf '\n  --- SSH 수신 인터페이스 (127.0.0.1 / ::1 만 나와야 정상) ---\n'
lsof -nP -iTCP:22 -sTCP:LISTEN 2>/dev/null || echo "  (sshd 미수신 — 원격 로그인 설정을 확인해 주세요)"

cat <<EOF

${C_OK}════════════════════════════════════════════════════════════${C_OFF}
  셋업 완료

  다음 단계
    1. Claude 데스크톱 앱을 완전히 종료했다가 다시 실행하세요.
       (MCP 서버는 앱 시작 시점에만 로드됩니다)
    2. 새 대화에서 "postgres MCP로 테이블 목록 보여줘" 라고 해보세요.

  등록된 MCP
    postgres   → ${DATABASE_URI}  (읽기+쓰기)
    local-ssh  → ${PG_SUPERUSER}@${PG_HOST}:22  (셸 명령 실행)

  되돌리기
    claude mcp remove postgres --scope user
    claude mcp remove local-ssh --scope user
    sudo rm ${SSHD_DROPIN} && yes | sudo systemsetup -setremotelogin off
    psql -d postgres -c "DROP ROLE ${MCP_ROLE};"
${C_OK}════════════════════════════════════════════════════════════${C_OFF}

EOF
