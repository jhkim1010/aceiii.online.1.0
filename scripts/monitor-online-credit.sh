#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# monitor-online-credit.sh — venta online 첫 배송건 외상(sale_credit) 검증 (온디맨드)
#
# 운영(PG10) 의 delivered 온라인 주문을 조회해 외상 처리 불변식을 검증하고,
# 결과를 텔레그램(coolsistema_bot)으로 알린다. 운영 상태 변경 없음(SELECT only).
#
# 사용법:
#   ./scripts/monitor-online-credit.sh            # 검증 + (배송건 있거나 이상 시) 텔레그램 전송
#   ./scripts/monitor-online-credit.sh --quiet    # 텔레그램 미전송(콘솔만)
#   ./scripts/monitor-online-credit.sh --force     # 배송건 0이어도 텔레그램 전송
#
# 검증 불변식 (per delivered online_order):
#   · mirror_sale_id 존재 + sales 행 존재
#   · sale.client_id IS NULL (레거시 FK 미사용) & sale.store_client_id 설정됨
#   · 외상(metadata.shipSaldo>0): sale_credit 정확히 1건 & 금액=shipSaldo & payment_status≠paid
#   · 완납(shipSaldo<=0): sale_credit 0건
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

SSH_HOST="jhkim-server"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/api-ventago/.env"
QUIET=0; FORCE=0; LOCAL=0
for a in "$@"; do
  case "$a" in
    --quiet) QUIET=1;;
    --force) FORCE=1;;
    --local) LOCAL=1;;   # 로컬 PG18 로 검증 (prod SSH 대신 — self-test 용)
  esac
done

# 텔레그램 자격 (api-ventago/.env 재사용)
TG_TOKEN=$(grep -iE "^TELEGRAM_BOT_TOKEN=" "$ENV_FILE" 2>/dev/null | cut -d= -f2-)
TG_CHAT=$(grep -iE "^TELEGRAM_CHAT_ID=" "$ENV_FILE" 2>/dev/null | cut -d= -f2-)

# 검증 SQL — 파이프 구분 행 + 마지막 verdict 컬럼
read -r -d '' SQL <<'EOSQL'
WITH deliv AS (
  SELECT o.id, o.store_id, o.order_number, o.total, o.payment_status,
         o.mirror_sale_id, o.client_id,
         COALESCE(NULLIF(o.metadata->>'shipSaldo','')::numeric, 0) AS ship_saldo
  FROM online_orders o
  WHERE o.status = 'delivered'
),
cl AS (
  SELECT sale_id, COUNT(*) n, COALESCE(SUM(amount),0) amt, MAX(store_client_id) sc
  FROM credit_ledger WHERE movement_type='sale_credit' GROUP BY sale_id
),
spm AS (
  SELECT sale_id, COALESCE(SUM(amount),0) paid FROM sale_payment_methods GROUP BY sale_id
)
SELECT d.store_id
  ||'|'|| d.order_number
  ||'|'|| d.id
  ||'|'|| d.total::numeric(14,2)
  ||'|'|| d.payment_status
  ||'|'|| COALESCE(d.mirror_sale_id::text,'-')
  ||'|'|| d.ship_saldo::numeric(14,2)
  ||'|'|| COALESCE(cl.n,0)
  ||'|'|| COALESCE(cl.amt,0)::numeric(14,2)
  ||'|'|| COALESCE(spm.paid,0)::numeric(14,2)
  ||'|'|| COALESCE(s.store_client_id::text,'-')
  ||'|'|| COALESCE(s.client_id::text,'NULL')
  ||'|'|| CASE
       WHEN d.mirror_sale_id IS NULL THEN 'ANOMALY:mirror_없음'
       WHEN s.id IS NULL THEN 'ANOMALY:mirror_sale_행_없음'
       WHEN s.client_id IS NOT NULL THEN 'ANOMALY:sale.client_id_비어있지않음(FK위험)'
       WHEN d.ship_saldo > 0 AND s.store_client_id IS NULL THEN 'ANOMALY:store_client_id_없음'
       WHEN d.ship_saldo > 0 AND COALESCE(cl.n,0) <> 1 THEN 'ANOMALY:sale_credit_행수<>1'
       WHEN d.ship_saldo > 0 AND ROUND(COALESCE(cl.amt,0),2) <> ROUND(d.ship_saldo,2) THEN 'ANOMALY:외상금액불일치'
       WHEN d.ship_saldo > 0 AND d.payment_status = 'paid' THEN 'ANOMALY:외상인데payment=paid'
       WHEN d.ship_saldo <= 0 AND COALESCE(cl.n,0) > 0 THEN 'ANOMALY:완납인데sale_credit존재'
       ELSE 'OK'
     END
FROM deliv d
LEFT JOIN sales s ON s.id = d.mirror_sale_id
LEFT JOIN cl ON cl.sale_id = d.mirror_sale_id
LEFT JOIN spm ON spm.sale_id = d.mirror_sale_id
ORDER BY d.store_id, d.order_number;
EOSQL

SQL_ONE=$(echo "$SQL" | tr '\n' ' ')
if [ "$LOCAL" -eq 1 ]; then
  echo "[monitor] 로컬(PG18) delivered 온라인 주문 외상 검증 — $(date '+%Y-%m-%d %H:%M:%S')"
  export PGPASSWORD=$(grep -iE "^DATABASE_password=" "$ENV_FILE" 2>/dev/null | cut -d= -f2-)
  ROWS=$(psql -h localhost -p 5432 -U postgres -d ventago -tAc "$SQL_ONE" 2>&1)
  SSH_RC=$?
else
  echo "[monitor] 운영(PG10) delivered 온라인 주문 외상 검증 — $(date '+%Y-%m-%d %H:%M:%S')"
  ROWS=$(ssh "$SSH_HOST" "sudo -u postgres psql -d ventago -tAc \"$SQL_ONE\"" 2>&1)
  SSH_RC=$?
fi
if [ $SSH_RC -ne 0 ]; then
  echo "[monitor] SSH/DB 조회 실패 (rc=$SSH_RC):"; echo "$ROWS"; exit 1
fi

# 빈 줄 제거
ROWS=$(echo "$ROWS" | grep -vE '^\s*$')
CNT=$(echo "$ROWS" | grep -c '|' || true)
[ -z "$ROWS" ] && CNT=0
ANOM=$(echo "$ROWS" | grep -c 'ANOMALY' || true)

# 콘솔 표 출력
printf '%-6s %-6s %-8s %-12s %-8s %-8s %-12s %-4s %-12s %-12s %-8s %-6s %s\n' \
  STORE ORD# ORDER TOTAL PAYST MIRROR SHIPSALDO CLn CREDITAMT PAID SALE_SC SALE_CLI VERDICT
if [ "$CNT" -gt 0 ]; then
  echo "$ROWS" | while IFS='|' read -r st ord oid total payst mir ship cln clamt paid ssc scli verd; do
    printf '%-6s %-6s %-8s %-12s %-8s %-8s %-12s %-4s %-12s %-12s %-8s %-6s %s\n' \
      "$st" "$ord" "$oid" "$total" "$payst" "$mir" "$ship" "$cln" "$clamt" "$paid" "$ssc" "$scli" "$verd"
  done
else
  echo "(delivered 온라인 주문 없음 — 아직 첫 운영 배송건 미발생)"
fi
echo "[monitor] 요약: delivered=$CNT, anomalies=$ANOM"

# ── 텔레그램 알림 ──
send_telegram(){
  local text="$1"
  if [ -z "$TG_TOKEN" ] || [ -z "$TG_CHAT" ]; then
    echo "[monitor] 텔레그램 자격 없음 — 전송 skip"; return
  fi
  local http
  http=$(curl -s -o /dev/null -w '%{http_code}' \
    "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TG_CHAT}" \
    --data-urlencode "parse_mode=HTML" \
    --data-urlencode "disable_web_page_preview=true" \
    --data-urlencode "text=${text}")
  echo "[monitor] 텔레그램 전송 http=$http"
}

# 전송 조건: 배송건 존재 or 이상 or --force. --quiet 이면 미전송.
if [ "$QUIET" -eq 1 ]; then
  echo "[monitor] --quiet: 텔레그램 미전송"
elif [ "$CNT" -gt 0 ] || [ "$FORCE" -eq 1 ]; then
  HEAD="✅ OK"
  [ "$ANOM" -gt 0 ] && HEAD="🚨 <b>[ALERT] 외상 불변식 위반 ${ANOM}건</b>"
  BODY=$(echo "$ROWS" | while IFS='|' read -r st ord oid total payst mir ship cln clamt paid ssc scli verd; do
    echo "· store${st} #${ord}: total=${total} pay=${payst} shipSaldo=${ship} credit=${cln}건/${clamt} paid=${paid} → ${verd}"
  done)
  [ -z "$BODY" ] && BODY="(delivered 온라인 주문 없음)"
  MSG="${HEAD}
<b>venta online 외상 검증</b> ($(date '+%m-%d %H:%M'))
delivered=${CNT} anomalies=${ANOM}
<pre>${BODY}</pre>"
  send_telegram "$MSG"
else
  echo "[monitor] 배송건 0 & 이상 0 → 텔레그램 미전송 (--force 로 강제 가능)"
fi

# 이상 있으면 non-zero exit (CI/자동화 연동 대비)
[ "$ANOM" -gt 0 ] && exit 3 || exit 0
