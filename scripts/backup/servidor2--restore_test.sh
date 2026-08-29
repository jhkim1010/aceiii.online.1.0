#!/usr/bin/env bash
# =============================================================================
# **복구 시험 — 백업이 «있다» 가 아니라 «복원된다» 를 매일 증명한다.**
# =============================================================================
# ★★★ 왜 필요한가. 2026-08-29 이전에는 예약된 백업이 `ventago` 하나뿐이었고,
#   125개 테넌트 DB 의 마지막 백업은 9개월 전이었다. 그때 «백업이 있다» 는 말은
#   `pg_restore -l` 이 통과한다는 뜻이었는데, 그것은 **덤프의 목차를 읽을 수 있다**
#   는 뜻이지 복원된다는 뜻이 아니다. 그 차이를 재는 것이 이 스크립트다.
#
# ★★ 운영 서버가 아니라 **서버2**에서 돈다. 운영에는 이미 Jenkins·Docker·PG 가
#   같은 호스트에 있고 swap 이 0이다 — 복구 시험까지 얹으면 안 된다.
#
# ★ 매일 **표본**을 돌린다(전체 125개가 아니라). 전체 복원은 몇 시간이 걸려
#   매일 돌 수 없고, 매일 안 도는 검사는 결국 안 도는 검사다.
#   표본은 «가장 큰 것 + 무작위 N개» 로 고른다 — 큰 것은 늘 확인하고,
#   무작위는 시간이 지나며 전체를 훑는다.
# =============================================================================
set -uo pipefail

PGBIN="/usr/lib/postgresql/18/bin"
PORT=5440                                   # 복구 전용 클러스터
LOCAL="/var/lib/postgresql/restore-test"
LOG="${LOCAL}/restore_test.log"
MUESTRA_ALEATORIA=3                          # 무작위로 더 뽑을 개수

mkdir -p "${LOCAL}"
log(){ echo "[$(date '+%F %T')] $*" | tee -a "${LOG}"; }

SRC="${1:-}"
if [ -z "${SRC}" ] || [ ! -d "${SRC}" ]; then
    log "백업 폴더를 못 찾았다: '${SRC}' — 중단"; exit 1
fi

log "=== 복구 시험 시작 — 원본 ${SRC}"

# ★ MANIFEST 로 무결성부터 본다. 전송 중 깨졌으면 복원 이전의 문제다.
if [ -f "${SRC}/MANIFEST.txt" ]; then
    MALOS=0
    while IFS=$'\t' read -r DB SIZE HASH; do
        F="${SRC}/${DB}.dump"
        [ -f "${F}" ] || { log "누락: ${DB}"; MALOS=$((MALOS+1)); continue; }
        AHORA="$(sha256sum "${F}" | cut -d' ' -f1)"
        [ "${AHORA}" = "${HASH}" ] || { log "해시 불일치: ${DB}"; MALOS=$((MALOS+1)); }
    done < "${SRC}/MANIFEST.txt"
    TOTAL_MAN=$(wc -l < "${SRC}/MANIFEST.txt")
    log "무결성: ${TOTAL_MAN}개 중 이상 ${MALOS}개"
    [ "${MALOS}" -eq 0 ] || { log "전송/보관 중 손상 — 중단"; exit 1; }
else
    log "MANIFEST 가 없다 — 중단"; exit 1
fi

# ── 표본 고르기: 가장 큰 것 + 무작위 N
GRANDE="$(ls -S "${SRC}"/*.dump 2>/dev/null | head -1)"
mapfile -t AZAR < <(ls "${SRC}"/*.dump | grep -vF "${GRANDE}" | shuf -n "${MUESTRA_ALEATORIA}")
MUESTRA=("${GRANDE}" "${AZAR[@]}")

log "표본 ${#MUESTRA[@]}개: $(for f in "${MUESTRA[@]}"; do basename "$f" .dump; done | tr '\n' ' ')"

OK=0; FAIL=0
for F in "${MUESTRA[@]}"; do
    DB="$(basename "${F}" .dump)"
    TGT="rt_${DB}"
    "${PGBIN}/dropdb"   -p "${PORT}" --if-exists "${TGT}" >>"${LOG}" 2>&1
    "${PGBIN}/createdb" -p "${PORT}" "${TGT}"             >>"${LOG}" 2>&1

    T0=$(date +%s)
    # ★ --no-owner/--no-privileges: 역할이 이 클러스터에 없다. 복원 가능성을
    #   재는 것이 목적이므로 소유권은 시험 대상이 아니다.
    if "${PGBIN}/pg_restore" -p "${PORT}" -d "${TGT}" --no-owner --no-privileges \
         --exit-on-error "${F}" >>"${LOG}" 2>&1; then
        T1=$(date +%s)
        # ★★ 복원이 «성공» 했다고 끝이 아니다. **데이터가 실제로 있는지** 본다 —
        #    빈 DB 도 오류 없이 복원된다.
        # ★ table_type 을 안 걸면 **뷰까지 센다**(loulou68: 실제 70인데 100).
        #   그리고 스키마를 public 으로 고정하면 안 된다 — 이 DB 들에는 public
        #   아닌 스키마가 있다([[db-has-a-non-public-reseller-schema]]).
        #   pg_restore 목록은 스키마를 안 가리므로 이쪽도 안 가려야 대조가 성립한다.
        TABLAS=$("${PGBIN}/psql" -p "${PORT}" -d "${TGT}" -At -c \
          "SELECT count(*) FROM information_schema.tables
            WHERE table_type='BASE TABLE'
              AND table_schema NOT IN ('pg_catalog','information_schema')")
        FILAS=$("${PGBIN}/psql" -p "${PORT}" -d "${TGT}" -At -c \
          "SELECT COALESCE(sum(n_live_tup),0) FROM pg_stat_user_tables")
        # ★★★ «0개면 실패» 는 틀렸다. 진짜로 빈 테넌트 DB 가 있다(2026-08-29:
        #   krafting 은 운영에서도 public 테이블 0개다). 그런 것을 매일 실패로
        #   보고하면 **일주일 안에 아무도 이 로그를 안 본다.**
        #   그래서 «덤프가 담고 있다고 말하는 개수» 와 대조한다 —
        #   빈 DB 는 0 == 0 이라 통과하고, 진짜 유실은 걸린다.
        # "TABLE DATA" 행도 같은 패턴에 걸리므로 반드시 뺀다 — 안 빼면 기대치가
        # 두 배가 돼 **모든 DB 가 실패**한다(=검사가 죽는다).
        ESPERADAS=$("${PGBIN}/pg_restore" -l "${F}" 2>/dev/null \
                    | grep -E "^[0-9]+; [0-9]+ [0-9]+ TABLE " \
                    | grep -vc "TABLE DATA")
        if [ "${TABLAS:-0}" -eq "${ESPERADAS:-0}" ]; then
            log "  ✓ ${DB}: 테이블 ${TABLAS}/${ESPERADAS}개 · 행 약 ${FILAS} · $((T1-T0))초"
            OK=$((OK+1))
        else
            log "  ✗ ${DB}: 덤프에는 ${ESPERADAS}개인데 복원 결과는 ${TABLAS}개다"
            FAIL=$((FAIL+1))
        fi
    else
        log "  ✗ ${DB}: 복원 실패"
        FAIL=$((FAIL+1))
    fi
    "${PGBIN}/dropdb" -p "${PORT}" --if-exists "${TGT}" >>"${LOG}" 2>&1
done

log "=== 결과: 성공 ${OK} / 실패 ${FAIL}"
[ "${FAIL}" -eq 0 ] || exit 1
