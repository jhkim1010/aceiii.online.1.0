#!/usr/bin/env bash
#
# 운용3(대기 서버) 동기화 — 운영이 바뀐 만큼 대기 서버를 따라가게 한다.
#
# 왜 Mac 에서 도나 (2026-10-16): 양쪽에 다 SSH 할 수 있는 곳이 여기뿐이다. 운영에 대기 서버로 가는
#   키를 두면 운영 변경(승인 필요)이고, 대기 서버의 터널 키는 5434 만 열려 있다.
#   ★ 그래서 Mac 이 꺼져 있으면 동기화가 멈춘다 — 그걸 모르게 두지 않으려고 마지막 성공 시각을
#     대기 서버 `/opt/ventago/state/last-sync` 에 쓰고, 대기 서버의 감시가 그 신선도를 본다(부재 = 경보).
#
# 하는 것 (바뀐 것만):
#   1. 이미지 — 운영 api_ventago / ventagoapp 가 **지금 쓰는** 이미지 id. blue/green 이라 이름이
#      ventago_5002-… / ventago_5003-… 로 번갈아 바뀐다 → 대기에서는 고정 태그 ventago-{api,app}:standby.
#      바뀌면 옮기고 컨테이너를 **다시 만들기만** 한다(create). ★ 절대 start 하지 않는다.
#   2. AFIP 인증서 두 폴더 — 내용 해시가 다르면 통째로.
#   3. TLS 인증서(Let's Encrypt, 운영 certbot 이 갱신) — 지문이 다르면 옮기고 nginx reload.
#
# 사용: scripts/standby-sync.sh            (launchd 1시간 — com.ventago.standby-sync)
#       DRY=1 scripts/standby-sync.sh      (무엇이 다른지만)
#
# ★ set -e 를 쓰지 않는다(메모리 set-e-kills-the-guard-before-it-speaks). 실패는 값으로 모아 마지막에 판정.

PROD=${PROD:-jhkim-server}
STBY=${STBY:-ventago-standby}
DRY=${DRY:-}
LOG_TAG="[standby-sync $(date '+%Y-%m-%d %H:%M:%S')]"
fallos=""
hecho=""
nota() { hecho="${hecho}${hecho:+, }$1"; }
fallo() { fallos="${fallos}${fallos:+; }$1"; }

ssh_ok() { ssh -o BatchMode=yes -o ConnectTimeout=10 "$1" true 2>/dev/null; }
if ! ssh_ok "$PROD"; then echo "$LOG_TAG ERROR: no llego a $PROD"; exit 2; fi
if ! ssh_ok "$STBY"; then echo "$LOG_TAG ERROR: no llego a $STBY"; exit 2; fi
# ★ 전환(failover) 뒤에는 운용3 가 원본이다 — 여기서 이미지를 바꾸면 **돌고 있는 api 를 created 로 되돌린다.**
if ssh "$STBY" "sudo test -f /opt/ventago/state/PROMOVIDO"; then echo "$LOG_TAG 운용3 가 승격돼 있다(PROMOVIDO) — 동기화하지 않는다"; exit 0; fi

# ── 1. 이미지 ────────────────────────────────────────────────────────────────
for par in "api_ventago|ventago-api:standby|api_ventago" "ventagoapp|ventago-app:standby|ventagoapp"; do
  cont=${par%%|*}; resto=${par#*|}; tag=${resto%%|*}; svc_name=${resto#*|}
  img_prod=$(ssh "$PROD" "docker inspect $cont --format '{{.Config.Image}}'" 2>/dev/null)
  id_prod=$(ssh "$PROD" "docker image inspect '$img_prod' --format '{{.Id}}'" 2>/dev/null)
  if [ -z "$img_prod" ] || [ -z "$id_prod" ]; then fallo "$cont: 운영에서 이미지를 못 읽었다"; continue; fi
  id_stby=$(ssh "$STBY" "sudo cat /opt/ventago/state/$cont.prod-image-id 2>/dev/null")
  if [ "$id_prod" = "$id_stby" ]; then continue; fi
  if [ -n "$DRY" ]; then nota "$cont 이미지 다름(${id_stby:0:19} → ${id_prod:0:19})"; continue; fi
  # 옮기기: 운영 docker save → zstd → Mac → 대기 docker load. 운영 쪽은 nice 로 낮춘다.
  cargado=$(ssh "$PROD" "nice -n 15 docker save '$img_prod' | nice -n 15 zstd -3 -T2 -q" \
    | ssh "$STBY" "zstd -d -q | sudo docker load" 2>&1 | grep -aoE 'Loaded image: .*' | tail -1)
  if [ -z "$cargado" ]; then fallo "$cont: 이미지 전송 실패"; continue; fi
  ssh "$STBY" "sudo docker tag '$img_prod' '$tag' \
    && sudo docker compose -f /opt/ventago/docker-compose.yml --project-directory /tmp create --force-recreate --no-deps $( [ "$cont" = api_ventago ] && echo api || echo app ) >/dev/null 2>&1 \
    && [ \"\$(sudo docker inspect $svc_name --format '{{.State.Status}}')\" = created ] \
    && sudo install -d -m 755 /opt/ventago/state && echo '$id_prod' | sudo tee /opt/ventago/state/$cont.prod-image-id >/dev/null" \
    && nota "$cont 이미지 갱신(${img_prod})" || fallo "$cont: 태그/재생성 실패"
done

# ── 2. AFIP 인증서 ────────────────────────────────────────────────────────────
# ★ LC_ALL=C: 두 서버의 로캘이 달라 정렬이 갈리면 같은 내용이 「다름」으로 나온다(2026-10-16 실측).
hash_dir() { echo "sudo sh -c 'cd \"$1\" 2>/dev/null && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -c1-16'"; }
for par in "/var/lib/ventago-certs|/opt/ventago/certs" "/var/lib/jenkins/workspace/certificados/coolsistema|/opt/ventago/certs-coolsistema"; do
  src=${par%%|*}; dst=${par#*|}
  hp=$(ssh "$PROD" "$(hash_dir "$src")" 2>/dev/null); hs=$(ssh "$STBY" "$(hash_dir "$dst")" 2>/dev/null)
  if [ -z "$hp" ]; then fallo "인증서 $src: 운영에서 못 읽었다"; continue; fi
  [ "$hp" = "$hs" ] && continue
  if [ -n "$DRY" ]; then nota "인증서 $(basename "$dst") 다름"; continue; fi
  ssh "$PROD" "sudo tar -C '$src' -czf - ." | ssh "$STBY" "sudo tar -C '$dst' -xzf -" \
    && nota "인증서 $(basename "$dst") 갱신" || fallo "인증서 $dst 전송 실패"
done

# ── 3. TLS ───────────────────────────────────────────────────────────────────
fp_p=$(ssh "$PROD" "sudo openssl x509 -in /etc/letsencrypt/live/coolsistema/fullchain.pem -noout -fingerprint -sha256" 2>/dev/null)
fp_s=$(ssh "$STBY" "sudo openssl x509 -in /etc/ssl/ventago/fullchain.pem -noout -fingerprint -sha256" 2>/dev/null)
if [ -z "$fp_p" ]; then
  fallo "TLS: 운영 인증서를 못 읽었다"
elif [ "$fp_p" != "$fp_s" ]; then
  if [ -n "$DRY" ]; then nota "TLS 다름"; else
    ssh "$PROD" "sudo tar -C /etc/letsencrypt/live/coolsistema -czhf - fullchain.pem privkey.pem" \
      | ssh "$STBY" "sudo tar -C /etc/ssl/ventago -xzf - && sudo chmod 600 /etc/ssl/ventago/privkey.pem && sudo nginx -t -q && sudo systemctl reload nginx" \
      && nota "TLS 갱신" || fallo "TLS 전송/reload 실패"
  fi
fi

# ── 판정 ─────────────────────────────────────────────────────────────────────
if [ -n "$fallos" ]; then
  echo "$LOG_TAG FALLO: $fallos${hecho:+ | hecho: $hecho}"
  exit 1
fi
# 성공 시각 — 대기 서버 감시(ventago-health-watch CHEQUEAR_REPLICA)가 신선도를 본다.
[ -z "$DRY" ] && ssh "$STBY" "sudo install -d -m 755 /opt/ventago/state && date +%s | sudo tee /opt/ventago/state/last-sync >/dev/null"
echo "$LOG_TAG OK: ${hecho:-sin cambios}"
exit 0
