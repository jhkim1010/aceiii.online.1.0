#!/usr/bin/env bash
#
# Ventago 가용성 감시 — 호스트 레벨.
#
# 왜 있나 (2026-09-08): API 가 **5시간** 다운이었는데 아무 알림도 안 갔다.
#   docker healthcheck 는 실패를 592회 기록했지만 그 기록을 **읽는 사람이 없었다.**
#   사용자가 먼저 발견했다.
#
# ★ 감시는 **감시 대상 밖에서** 돈다. 앱 안의 cron 으로 만들면 앱이 죽을 때 알림도
#   같이 죽는다 — 이번 사고가 정확히 그 형태였다(앱이 부팅을 못 끝냈다).
#   그래서 systemd 타이머 + curl 로 텔레그램에 직접 보낸다. 앱도 DB 도 안 거친다.
#
# ★ `set -e` 를 쓰지 않는다. 감시 스크립트에서 그건 **진단하기 전에 죽는** 장치다 —
#   실패를 감지하려고 부른 명령이 0이 아닌 코드를 내면 스크립트가 조용히 끝난다.
#   실패는 값으로 다루고, 마지막에 한 번에 판정한다.
#
# ★ 「부재」에서도 울린다. 컨테이너가 unhealthy 인 경우뿐 아니라 **아예 없는** 경우·
#   멈춘 경우도 장애다. 없는 것을 못 보는 감시가 이 저장소에서 여러 번 조용히 죽었다.
#
# 설치: scripts/install-health-watch.sh (systemd 타이머 60초)

STATE_DIR=${STATE_DIR:-/var/lib/ventago-health-watch}
STATE_FILE="$STATE_DIR/state"
ENV_FILE=${ENV_FILE:-/var/lib/jenkins/workspace/api-new-coolsistema/.env}

# 연속 N회 실패해야 경보 — 순간적인 네트워크 흔들림으로 울리지 않게 한다.
FALLOS_PARA_ALERTA=${FALLOS_PARA_ALERTA:-2}
# 장애가 계속되는 동안 이 간격(초)마다 다시 알린다. 한 번 울리고 마는 감시는
# 새벽에 놓치면 그대로 묻힌다.
REPETIR_SEG=${REPETIR_SEG:-1800}
# 아무 일 없어도 하루 한 번 살아 있다고 알린다 — **침묵 자체가 고장일 수 있다.**
LATIDO_SEG=${LATIDO_SEG:-86400}

API_URL=${API_URL:-https://newapi.coolsistema.com/api/health}
APP_URL=${APP_URL:-https://app.coolsistema.com/}
# ★ `:-` 가 아니라 `-` 다. 콜론이 있으면 **빈 값일 때도** 기본값을 쓴다 —
#   외부 감시(servidor2)는 로컬 컨테이너가 없어 일부러 빈 값을 주는데, `:-` 였을 때는
#   그걸 무시하고 운영 컨테이너 이름을 거기서 찾아 **영구 오경보**를 냈다(2026-09-08 실측).
#   빈 값은 「안 본다」는 뜻이고, 그건 미설정과 다르다.
CONTENEDORES=${CONTENEDORES-"api_ventago ventagoapp"}

# ★ 경보에 찍히는 환경 이름. 스테이지에서 시험할 때 운영 경보와 **구분되지 않으면**
#   그 경보는 위험하다 — 진짜 장애를 시험으로 착각해 넘길 수 있다.
ETIQUETA=${ETIQUETA:-PROD}

mkdir -p "$STATE_DIR" 2>/dev/null

# ── 텔레그램 ── 자격증명은 .env 하나에서만 온다(사본을 만들지 않는다).
enviar_telegram() {
  local texto="$1"
  local token chat
  token=$(grep -E '^TELEGRAM_BOT_TOKEN=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- | tr -d '"'"'"'\r')
  chat=$(grep -E '^TELEGRAM_CHAT_ID=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- | tr -d '"'"'"'\r')

  if [ -z "$token" ] || [ -z "$chat" ]; then
    logger -t ventago-health-watch "텔레그램 자격증명 없음 ($ENV_FILE) — 경보를 보낼 수 없다"
    return 1
  fi

  # --data-urlencode 로 보낸다. 메시지에 & 나 개행이 들어가도 안 깨진다.
  curl -sS --max-time 15 -o /dev/null \
    "https://api.telegram.org/bot${token}/sendMessage" \
    --data-urlencode "chat_id=${chat}" \
    --data-urlencode "text=${texto}" \
    --data-urlencode "disable_web_page_preview=true"
  local rc=$?
  if [ $rc -ne 0 ]; then
    # 경보를 못 보낸 것 자체는 알릴 방법이 없다 — 로그에 남기고 하루치 latido 로 드러낸다.
    logger -t ventago-health-watch "텔레그램 전송 실패 rc=$rc"
  fi

  return $rc
}

# ── 점검 ── 실패 사유를 줄 단위로 모은다. 빈 문자열 = 정상.
problemas=""
anotar() { problemas="${problemas}${problemas:+$'\n'}$1"; }

for c in $CONTENEDORES; do
  estado=$(docker inspect "$c" --format '{{.State.Status}}' 2>/dev/null)
  if [ -z "$estado" ]; then
    # ★ 없는 컨테이너. unhealthy 만 보는 감시는 이걸 못 본다.
    anotar "• ${c}: 컨테이너가 없다"
    continue
  fi
  if [ "$estado" != "running" ]; then
    anotar "• ${c}: ${estado}"
    continue
  fi
  # healthcheck 가 정의된 컨테이너만 salud 를 본다(없으면 빈 문자열 → 통과).
  salud=$(docker inspect "$c" --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' 2>/dev/null)
  if [ -n "$salud" ] && [ "$salud" != "healthy" ]; then
    rachas=$(docker inspect "$c" --format '{{if .State.Health}}{{.State.Health.FailingStreak}}{{end}}' 2>/dev/null)
    anotar "• ${c}: ${salud} (연속 실패 ${rachas}회)"
  fi
done

# ★ 컨테이너 상태와 **다른 것을 잰다.** healthcheck 는 컨테이너 안에서 localhost 를
#   부르므로 nginx 업스트림이 엉뚱한 포트를 가리켜도 healthy 로 보인다.
#   공개 URL 은 사용자가 실제로 밟는 경로다. 두 겹이 같은 조건이면 한 겹이다.
for par in "API|$API_URL" "APP|$APP_URL"; do
  nombre=${par%%|*}
  url=${par#*|}
  codigo=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 "$url" 2>/dev/null)
  if [ "$codigo" != "200" ]; then
    anotar "• ${nombre} 공개 URL: HTTP ${codigo:-무응답} (${url})"
  fi
done

# ── 상태 전이 판정 ──
ahora=$(date +%s)
fallos_prev=0
estado_prev=ok
ultimo_aviso=0
ultimo_latido=0
# shellcheck disable=SC1090
[ -f "$STATE_FILE" ] && . "$STATE_FILE" 2>/dev/null

if [ -n "$problemas" ]; then
  fallos=$((fallos_prev + 1))
else
  fallos=0
fi

host="${ETIQUETA} $(hostname -s 2>/dev/null || echo servidor)"
avisar=0
mensaje=""

if [ "$fallos" -ge "$FALLOS_PARA_ALERTA" ]; then
  if [ "$estado_prev" = "ok" ]; then
    avisar=1
    mensaje="🔴 Ventago CAÍDO — ${host}
$(date '+%Y-%m-%d %H:%M:%S %Z')

${problemas}

(${fallos}회 연속 확인 실패)"
  elif [ $((ahora - ultimo_aviso)) -ge "$REPETIR_SEG" ]; then
    avisar=1
    minutos=$(( (ahora - ultimo_aviso) / 60 ))
    mensaje="🔴 Ventago SIGUE CAÍDO — ${host}
$(date '+%Y-%m-%d %H:%M:%S %Z') · ${minutos}분째

${problemas}"
  fi
  estado_nuevo=caido
elif [ "$estado_prev" = "caido" ] && [ "$fallos" -eq 0 ]; then
  avisar=1
  mensaje="🟢 Ventago RECUPERADO — ${host}
$(date '+%Y-%m-%d %H:%M:%S %Z')

Todos los chequeos en verde."
  estado_nuevo=ok
else
  estado_nuevo=$estado_prev
  [ "$fallos" -eq 0 ] && estado_nuevo=ok
fi

# 하루 한 번 생존 신호 — 이 메시지가 안 오면 **감시가 죽은 것**이다.
#
# ★ `fallos -eq 0` 이 반드시 필요하다. `estado_nuevo` 만 보면 **실패가 임계값 아래로
#   쌓이는 중**(fallos=1)에도 ok 이므로, 고장 나 있는 순간에 「🟢 정상」을 보낸다.
#   2026-09-08 스테이지 실험에서 실제로 그랬다 — 감시가 거짓말하면 없느니만 못하다.
#
# ★ `avisar -eq 0` 도 필요하다. 없으면 이 블록이 **복구 메시지를 덮어쓴다** —
#   장애가 하루를 넘겨 생존 신호 시각과 겹치면, 「🟢 복구됨」 대신 「🟢 정상」이 가서
#   장애가 있었다는 사실 자체가 사라진다. 2026-09-08 스테이지 실험에서 실제로 그랬다.
if [ "$avisar" -eq 0 ] && [ "$estado_nuevo" = "ok" ] && [ "$fallos" -eq 0 ] &&
   [ $((ahora - ultimo_latido)) -ge "$LATIDO_SEG" ]; then
  avisar=1
  mensaje="🟢 Ventago OK — ${host}
$(date '+%Y-%m-%d %H:%M:%S %Z')
(하루 1회 생존 신호. 이 메시지가 끊기면 감시 자체가 멈춘 것이다.)"
  ultimo_latido=$ahora
fi

if [ "$avisar" -eq 1 ]; then
  enviar_telegram "$mensaje" && ultimo_aviso=$ahora
  logger -t ventago-health-watch "경보 발송: $(echo "$mensaje" | head -1)"
fi

cat > "$STATE_FILE" <<EOF
fallos_prev=$fallos
estado_prev=$estado_nuevo
ultimo_aviso=$ultimo_aviso
ultimo_latido=$ultimo_latido
EOF

exit 0
