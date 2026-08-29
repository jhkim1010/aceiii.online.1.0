#!/usr/bin/env bash
# **매일: 운영에서 최신 백업을 당겨와 복구 시험을 돌리고, 결과를 알린다.**
#
# ★★★ 왜 «당겨오는가»(운영이 밀지 않고). 운영 서버가 뚫려도 백업 서버를 못
#   건드리게 하기 위해서다. 운영에 있는 이 키는 `command=` 로 «최신 백업을
#   읽는 것» 하나에 묶여 있어 셸이 열리지 않는다(2026-08-29 대조군으로 확인).
#
# ★★ 받은 것을 **매번 지운다**. 서버2는 백업 보관소가 아니라 시험장이다.
#   보관은 운영(14일) + Dropbox 가 한다.
#
# ★★★ 알림 규칙 — «실패할 때만 알린다» 는 함정이다.
#   이 스크립트가 아예 안 돌면(크론 삭제·서버 다운·키 만료) **아무 소리도 안 난다.**
#   그래서 두 겹으로 짠다:
#     (1) 여기서: 실패·낡은 백업이면 즉시 텔레그램. 성공은 **월요일만** 보낸다
#         (매일 «정상» 이 오면 사람이 읽지 않게 되고, 그러면 알림이 없는 것과 같다).
#     (2) 운영에서: 이 결과 파일이 **48시간 넘게 갱신 안 되면** 경보
#         (`vigilar_restore_test.sh`). 부재를 알아채는 것은 **다른 기계**여야 한다 —
#         죽은 기계는 자기가 죽었다고 말하지 못한다.
set -uo pipefail

BASE="/var/lib/postgresql/restore-test"
IN="${BASE}/incoming"
LOG="${BASE}/pull_and_test.log"
ORIGEN="postgres@62.72.7.245"
KEY="${HOME}/.ssh/id_backup"
KEY_REP="${HOME}/.ssh/id_report"
ENV_FILE="${BASE}/.uptime.env"

mkdir -p "${IN}"
log(){ echo "[$(date '+%F %T')] $*" | tee -a "${LOG}"; }

# ── 알림 ────────────────────────────────────────────────────────────────────
avisar(){  # $1 = 본문
    # 자격증명이 없으면 조용히 넘어간다 — 알림 실패가 시험을 막으면 안 된다.
    [ -r "${ENV_FILE}" ] || { log "WARN 알림 설정 없음(${ENV_FILE})"; return 0; }
    # shellcheck disable=SC1090
    set -a; . "${ENV_FILE}"; set +a
    [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ] || {
        log "WARN 텔레그램 미설정 — 알림 생략"; return 0; }
    # ★★ `-o /dev/null` 만 두면 **토큰이 틀려도 curl 은 성공(0)** 이다.
    #   텔레그램은 4xx + {"ok":false} 로 답하는데 그걸 안 보면
    #   「경고가 없다 = 잘 갔다」 가 거짓이 된다 — 알림이 죽은 줄도 모르게 된다.
    #   그래서 **응답 본문의 ok:true 를 직접 확인한다.**
    local resp
    resp="$(curl -sS -m 20 \
        --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=$1" \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" 2>&1)"
    case "${resp}" in
        *'"ok":true'*) : ;;
        *) log "WARN 텔레그램 발송 실패: ${resp:0:200}" ;;
    esac
}

# ★ 알림 경로 자가시험. 「토큰이 만료돼 반년째 아무 알림도 안 갔다」 는 사고를
#   막으려면 **알림 자체를 가끔 눌러 봐야** 한다:  pull_and_test.sh --probar-aviso
if [ "${1:-}" = "--probar-aviso" ]; then
    avisar "🔵 [시험] 복구 시험 알림 경로 점검 — $(hostname) $(date '+%F %T')"
    log "알림 시험 발송 시도 완료"
    exit 0
fi

# 운영 서버에 결과를 밀어 올린다(부재 감시용). 실패해도 시험 결과는 안 바꾼다.
reportar(){  # $1 = json
    printf '%s' "$1" | ssh -i "${KEY_REP}" -o BatchMode=yes \
        -o StrictHostKeyChecking=accept-new -o ConnectTimeout=20 \
        "${ORIGEN}" >/dev/null 2>>"${LOG}" \
        || log "WARN 운영에 상태 보고 실패"
}

# 어떤 경로로 끝나든 상태를 남긴다 — «보고가 없다» 와 «실패했다» 는 다른 사건이다.
ESTADO="desconocido"; DETALLE="시작 전"; OKN=0; FALLOS=0; EDAD_H=-1; CARPETA="-"
terminar(){
    local rc=$1
    reportar "$(printf '{"ts":"%s","estado":"%s","ok":%d,"fallos":%d,"edad_h":%d,"carpeta":"%s","rc":%d}' \
        "$(date -u '+%FT%TZ')" "${ESTADO}" "${OKN}" "${FALLOS}" "${EDAD_H}" "${CARPETA}" "${rc}")"
    log "=== 종료 (${ESTADO}, 종료코드 ${rc})"
    exit "${rc}"
}

log "=== 당겨오기 시작"
rm -rf "${IN:?}"/*

if ! ssh -i "${KEY}" -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
        -o ConnectTimeout=20 "${ORIGEN}" 2>>"${LOG}" | tar -C "${IN}" -xf -; then
    log "당겨오기 실패 — 운영 접속 또는 tar 오류"
    ESTADO="fallo_descarga"
    avisar "🔴 복구 시험: 운영에서 백업을 못 받았다 (SSH/tar 오류). 서버2 로그: ${LOG}"
    terminar 1
fi

D="$(ls -dt "${IN}"/20* 2>/dev/null | head -1)"
if [ -z "${D}" ]; then
    log "받은 폴더가 없다"
    ESTADO="sin_carpeta"
    avisar "🔴 복구 시험: 받은 백업 폴더가 없다 — 운영의 백업 크론을 확인할 것"
    terminar 1
fi
CARPETA="$(basename "${D}")"

# ★ 백업이 **오늘 것인지** 본다. 크론이 죽어 어제 것을 매일 성공적으로 시험하면
#   «백업이 신선하다» 는 착각이 생긴다 — 감시가 침묵하는 전형적 형태다.
# ★★★ 폴더 이름의 시각은 **운영 서버 시간(UTC)** 이다. 서버2 는 UTC-3 이라
#   그냥 `date -d` 로 읽으면 3시간이 어긋나 방금 만든 백업이 «-2시간 전» 이 된다
#   (2026-08-29 실측). 감시하려던 값이 음수가 되면 그 감시는 아무것도 안 막는다.
#   그래서 **UTC 로 명시해서** 읽는다.
STAMP="$(echo "${CARPETA}" | sed 's/_/ /; s/\(....\)\(..\)\(..\) \(..\)\(..\)\(..\)/\1-\2-\3 \4:\5:\6/')"
EDAD_H=$(( ( $(date -u +%s) - $(date -u -d "${STAMP}" +%s) ) / 3600 ))
log "받은 백업: ${CARPETA} — ${EDAD_H}시간 전"
VIEJO=0
if [ "${EDAD_H}" -gt 30 ]; then
    VIEJO=1
    log "★ 경고: 백업이 ${EDAD_H}시간 전 것이다 — 운영의 백업 크론을 확인할 것"
fi

SALIDA="$(/var/lib/postgresql/restore_test.sh "${D}" 2>&1)"
RC=$?
echo "${SALIDA}"

OKN=$(echo "${SALIDA}"    | sed -n 's/.*성공 \([0-9]\+\) \/ 실패 [0-9]\+.*/\1/p' | tail -1)
FALLOS=$(echo "${SALIDA}" | sed -n 's/.*성공 [0-9]\+ \/ 실패 \([0-9]\+\).*/\1/p' | tail -1)
OKN="${OKN:-0}"; FALLOS="${FALLOS:-0}"

rm -rf "${IN:?}"/*

RESUMEN="백업 ${CARPETA} (${EDAD_H}h 전) · 복원 성공 ${OKN} / 실패 ${FALLOS}"

if [ "${RC}" -ne 0 ] || [ "${FALLOS}" -gt 0 ]; then
    ESTADO="fallo"
    avisar "🔴 복구 시험 실패 — ${RESUMEN}"$'\n'"서버2 로그: ${LOG}"
elif [ "${VIEJO}" -eq 1 ]; then
    ESTADO="ok_pero_viejo"
    avisar "🟠 복구는 됐지만 백업이 낡았다 (${EDAD_H}시간 전) — ${RESUMEN}"
else
    ESTADO="ok"
    # 성공은 **월요일만** 알린다. 매일 보내면 읽지 않게 된다.
    [ "$(date +%u)" = "1" ] && avisar "🟢 주간 확인 — 복구 시험 정상. ${RESUMEN}"
fi

terminar "${RC}"
