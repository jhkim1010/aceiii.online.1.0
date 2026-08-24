#!/usr/bin/env bash
# =============================================================================
# Phase 86 — 샌드박스 PostgreSQL 18 기동 보장
# =============================================================================
# 검증 전용 DB. **운영에도 로컬 Mac(5432)에도 접속하지 않는다.**
#
# ★ 매 bash 호출 앞에서 부를 것.
#   이 샌드박스는 호출마다 프로세스 그룹이 정리되므로 서버가 죽는다.
#   PGDATA 는 남아 있으므로 재기동하면 데이터는 그대로다.
#
# ★ bash 로 실행할 것 (`bash tools/phase86/pgup.sh`).
#   마운트된 작업트리에서는 exec 비트가 유실돼 직접 실행이 Permission denied 가 된다.
#
# 환경 변수
#   PHASE86_PGROOT  PG 바이너리 루트 (기본: npm @embedded-postgres 설치 위치)
#   PHASE86_PGDIR   런타임 디렉터리 (기본 /tmp/pg86) — 소켓·로그·PGDATA
#   PHASE86_PGPORT  포트 (기본 55432 — 운영 5432/5434 와 충돌 회피)
# =============================================================================
set -uo pipefail

PGROOT="${PHASE86_PGROOT:-/tmp/pgbin/node_modules/@embedded-postgres/linux-arm64/native}"
PGDIR="${PHASE86_PGDIR:-/tmp/pg86}"
PGPORT="${PHASE86_PGPORT:-55432}"
PGDATA="$PGDIR/data"
SOCK="$PGDIR/.s.PGSQL.$PGPORT"
export LD_LIBRARY_PATH="$PGROOT/lib:${LD_LIBRARY_PATH:-}"

# ── 0. 바이너리 확인 ─────────────────────────────────────────────────────────
if [[ ! -x "$PGROOT/bin/postgres" ]]; then
  cat >&2 <<EOF
PG18 바이너리를 찾을 수 없습니다: $PGROOT/bin/postgres

설치 (npm 만 열려 있는 환경 기준):
  mkdir -p /tmp/pgbin && cd /tmp/pgbin && npm init -y
  npm i --force @embedded-postgres/linux-arm64@18.4.0-beta.17   # x64 면 linux-x64
  # --force 는 arm64 에서 optional-dep os/cpu 게이트를 넘기기 위한 것

또는 PHASE86_PGROOT 로 다른 PG18 설치 경로를 지정하세요.
EOF
  exit 1
fi

mkdir -p "$PGDIR"

# ── 1. 최초 1회 initdb ──────────────────────────────────────────────────────
if [[ ! -f "$PGDATA/PG_VERSION" ]]; then
  rm -rf "$PGDATA"
  if ! "$PGROOT/bin/initdb" -D "$PGDATA" -U postgres -A trust \
        --encoding=UTF8 --locale=C > "$PGDIR/initdb.log" 2>&1; then
    echo "initdb 실패:" >&2; tail -20 "$PGDIR/initdb.log" >&2; exit 1
  fi
fi

# ── 2. 이미 떠 있으면 그대로 ────────────────────────────────────────────────
if [[ -S "$SOCK" ]] && "$PGROOT/bin/pg_ctl" -D "$PGDATA" status >/dev/null 2>&1; then
  exit 0
fi

# ── 3. 기동 (최대 3회) ──────────────────────────────────────────────────────
for attempt in 1 2 3; do
  # 죽은 프로세스가 남긴 흔적을 치운다 — 안 치우면 "already in use" 로 계속 실패한다.
  rm -f "$SOCK" "$SOCK.lock" "$PGDATA/postmaster.pid" 2>/dev/null

  # listen_addresses='' → TCP 를 아예 열지 않는다(유닉스 소켓 전용).
  # 샌드박스 밖에서 접속할 이유가 없고, 포트를 안 여는 게 가장 안전하다.
  setsid nohup "$PGROOT/bin/postgres" -D "$PGDATA" -p "$PGPORT" -k "$PGDIR" \
    -c listen_addresses='' >> "$PGDIR/server.log" 2>&1 < /dev/null &
  disown 2>/dev/null

  for _ in $(seq 1 20); do
    [[ -S "$SOCK" ]] && exit 0
    sleep 0.5
  done
  echo "기동 재시도 $attempt/3" >&2
done

echo "PG18 기동 실패. 로그 마지막 20줄:" >&2
tail -20 "$PGDIR/server.log" >&2
exit 1
