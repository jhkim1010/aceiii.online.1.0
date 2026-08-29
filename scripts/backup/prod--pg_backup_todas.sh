#!/usr/bin/env bash
# =============================================================================
# **PG10(5433)의 모든 테넌트 DB 를 매일 백업한다.**
# =============================================================================
# ★★★ 왜 필요한가. 2026-08-29 점검에서 드러난 것:
#   예약된 백업은 `pg_backup_ventago.sh` 하나였고 그것은 `ventago`(52MB)만 담았다.
#   PG10 의 **125개 테넌트 DB(34GB)** 는 마지막 백업이 **2025-11-19** — 9개월 전이다.
#   그동안 그 DB 들은 계속 쓰이고 있었다(한 곳만 24일간 쓰기 498만 건).
#   디스크 장애·랜섬웨어·사람 실수 어느 것이든 150개 매장의 9개월치가 사라진다.
#
# ★★ PG10 은 «롤백 안전망» 이 아니라 **가장 바쁜 운영 DB** 다. 문서에 그렇게 적혀
#   있었지만 실측이 뒤집었다. 이 스크립트는 그 사실 위에 서 있다.
#
# ★ PG18 의 pg_dump 로 PG10 을 읽는다(지원 범위 안, 실측 확인). 그래야 나온 덤프를
#   **지원되는 버전(PG18)으로 복원**할 수 있다 — PG10 은 2022-11 지원 종료다.
#
# 실측(2026-08-29): 1161MB DB → 48MB 덤프 / 9초. 전체 34GB → 약 1.4GB / 4~5분.
# =============================================================================
set -euo pipefail

PGBIN="/usr/lib/postgresql/18/bin"
PGPORT=5433                                  # PG10 직결 (pgbouncer 아님)
BASE="/var/lib/postgresql/pg_backups/todas"
RETENTION_DAYS=14
TS="$(date +%Y%m%d_%H%M%S)"
OUT="${BASE}/${TS}"
LOG="${BASE}/backup_todas.log"

mkdir -p "${OUT}"
log(){ echo "[$(date '+%F %T')] $*" | tee -a "${LOG}"; }

log "=== 전체 테넌트 백업 시작 (PG10:${PGPORT}) → ${OUT}"

# ── 역할/테이블스페이스 (DB 밖에 사는 것 — 이게 없으면 복원해도 소유자가 없다)
if "${PGBIN}/pg_dumpall" -p "${PGPORT}" --globals-only 2>>"${LOG}" | gzip > "${OUT}/GLOBALS.sql.gz"; then
    log "역할 백업 성공"
else
    log "역할 백업 실패 — 즉시 확인 필요"; exit 1
fi

# ── 대상 목록. template 과 postgres 는 뺀다.
mapfile -t DBS < <("${PGBIN}/psql" -p "${PGPORT}" -d postgres -At -c \
  "SELECT datname FROM pg_database WHERE datistemplate=false AND datname<>'postgres' ORDER BY datname")

TOTAL=${#DBS[@]}
log "대상 ${TOTAL}개"

# ★ 0건이면 실패다. 조용히 «성공» 으로 끝나면 아무도 백업이 빈 것을 모른다.
if [ "${TOTAL}" -eq 0 ]; then
    log "대상이 0개다 — 목록 조회가 실패했을 수 있다. 중단."; exit 1
fi

OK=0; FAIL=0
MANIFEST="${OUT}/MANIFEST.txt"
: > "${MANIFEST}"

for DB in "${DBS[@]}"; do
    F="${OUT}/${DB}.dump"
    if "${PGBIN}/pg_dump" -p "${PGPORT}" -Fc -d "${DB}" -f "${F}" 2>>"${LOG}"; then
        # ★★ 파일이 생겼다고 끝이 아니다. 읽히는지 확인한다 —
        #    «백업이 있다» 와 «복원할 수 있다» 는 다른 말이다.
        if "${PGBIN}/pg_restore" -l "${F}" >/dev/null 2>>"${LOG}"; then
            printf '%s\t%s\t%s\n' "${DB}" "$(stat -c%s "${F}")" "$(sha256sum "${F}" | cut -d' ' -f1)" >> "${MANIFEST}"
            OK=$((OK+1))
        else
            log "무결성 실패: ${DB} (덤프 손상)"; rm -f "${F}"; FAIL=$((FAIL+1))
        fi
    else
        log "덤프 실패: ${DB}"; FAIL=$((FAIL+1))
    fi
done

log "완료: 성공 ${OK} / 실패 ${FAIL} / 전체 ${TOTAL} · 크기 $(du -sh "${OUT}" | cut -f1)"

# ── 보관 정리는 **성공했을 때만** 한다.
#    실패한 날 옛 백업을 지우면 남는 것이 없다.
if [ "${FAIL}" -eq 0 ]; then
    find "${BASE}" -maxdepth 1 -type d -name '20*' -mtime +${RETENTION_DAYS} -print -exec rm -rf {} + >>"${LOG}" 2>&1 || true
else
    log "실패가 있어 보관 정리를 건너뛴다 (옛 백업을 지우지 않는다)"
fi

# ★ 하나라도 실패하면 종료코드로 알린다. cron 메일/모니터가 그것을 본다.
[ "${FAIL}" -eq 0 ] || exit 1
log "=== 종료"
