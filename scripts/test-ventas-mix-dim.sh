#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
# Ventas 차원분석 (mix) 검증 — Phase 22 디버그 용
#
# 목적:
#   sales-cockpit/mix?dim={category|color|size|season|product} 5개 차원의
#   1) DB 레벨 raw 쿼리 결과
#   2) API 레벨 HTTP 응답 (JWT 토큰 필요)
#   두 쪽의 불일치를 drill down
#
# 사용:
#   ./scripts/test-ventas-mix-dim.sh                # DB 검증만
#   ./scripts/test-ventas-mix-dim.sh --api <JWT>    # API 호출도
#
# 환경변수:
#   PG_USER    (default: postgres)
#   PG_DB      (default: ventago)
#   STORE_ID   (default: 1)
#   START_DATE (default: 이번 달 1일)
#   END_DATE   (default: 오늘)
#   API_BASE   (default: http://localhost:5002/api)
# ─────────────────────────────────────────────────────────────────

set -u

PG_USER=${PG_USER:-postgres}
PG_DB=${PG_DB:-ventago}
STORE_ID=${STORE_ID:-1}
START_DATE=${START_DATE:-$(date -v1d +%Y-%m-%d 2>/dev/null || date -d "$(date +%Y-%m-01)" +%Y-%m-%d)}
END_DATE=${END_DATE:-$(date +%Y-%m-%d)}
API_BASE=${API_BASE:-http://localhost:5002/api}

JWT=""
if [[ "${1:-}" == "--api" && -n "${2:-}" ]]; then
  JWT="$2"
fi

C_CYAN="\033[36m"; C_YEL="\033[33m"; C_GRN="\033[32m"; C_RED="\033[31m"; C_RST="\033[0m"

echo -e "${C_CYAN}=== Ventas Mix Dim 검증 ===${C_RST}"
echo "  store_id=${STORE_ID}  date=[${START_DATE} ~ ${END_DATE}]"
echo "  pg=${PG_USER}@${PG_DB}  api=${API_BASE}"
echo ""

# ── DB 레벨 검증 ──
echo -e "${C_YEL}[1/3] CTE 필터 매칭 카운트${C_RST}"
psql -U "$PG_USER" -d "$PG_DB" -x <<SQL
WITH sid AS (
  SELECT si.id AS sale_item_id, si.sale_id, si.quantity, si.subtotal AS line_subtotal,
         s.store_id, s.status AS sale_status, s.sale_date,
         p.color_id, col.name AS color_name,
         p.size_id, sz.name AS size_name,
         p.season_id, se.name AS season_name,
         p.category_id, cat.name AS category_name
  FROM sale_items si
  JOIN sales s ON s.id = si.sale_id
  LEFT JOIN products p ON p.id = si.product_id
  LEFT JOIN colors col ON col.id = p.color_id
  LEFT JOIN sizes sz ON sz.id = p.size_id
  LEFT JOIN seasons se ON se.id = p.season_id
  LEFT JOIN categories cat ON cat.id = p.category_id
)
SELECT
  COUNT(*) AS total_sale_items,
  COUNT(*) FILTER (WHERE store_id = ${STORE_ID}) AS match_store,
  COUNT(*) FILTER (WHERE sale_status IN ('Facturado','Pagado','Pendiente por pagar')) AS match_status,
  COUNT(*) FILTER (WHERE sale_date >= '${START_DATE}'::date
                     AND sale_date <  ('${END_DATE}'::date + INTERVAL '1 day')) AS match_date,
  COUNT(*) FILTER (WHERE store_id = ${STORE_ID}
                     AND sale_status IN ('Facturado','Pagado','Pendiente por pagar')
                     AND sale_date >= '${START_DATE}'::date
                     AND sale_date <  ('${END_DATE}'::date + INTERVAL '1 day')) AS match_all
FROM sid;
SQL

echo ""
echo -e "${C_YEL}[2/3] 5개 dim 별 그룹 수 + 샘플${C_RST}"
for DIM in category color size season; do
  echo -e "\n${C_CYAN}─── dim=${DIM} ───${C_RST}"
  psql -U "$PG_USER" -d "$PG_DB" <<SQL
WITH sid AS (
  SELECT si.quantity, si.subtotal AS line_subtotal,
         s.store_id, s.status AS sale_status, s.sale_date,
         p.color_id, col.name AS color_name,
         p.size_id, sz.name AS size_name,
         p.season_id, se.name AS season_name,
         p.category_id, cat.name AS category_name
  FROM sale_items si
  JOIN sales s ON s.id = si.sale_id
  LEFT JOIN products p ON p.id = si.product_id
  LEFT JOIN colors col ON col.id = p.color_id
  LEFT JOIN sizes sz ON sz.id = p.size_id
  LEFT JOIN seasons se ON se.id = p.season_id
  LEFT JOIN categories cat ON cat.id = p.category_id
)
SELECT ${DIM}_id AS id,
       COALESCE(${DIM}_name, 'Sin') AS name,
       SUM(quantity)::int AS qty,
       SUM(line_subtotal)::bigint AS amount,
       COUNT(*)::int AS lines
FROM sid
WHERE store_id = ${STORE_ID}
  AND sale_status IN ('Facturado','Pagado','Pendiente por pagar')
  AND sale_date >= '${START_DATE}'::date
  AND sale_date <  ('${END_DATE}'::date + INTERVAL '1 day')
GROUP BY ${DIM}_id, ${DIM}_name
ORDER BY amount DESC NULLS LAST
LIMIT 10;
SQL
done

# ── API 레벨 검증 (옵션) ──
if [[ -n "$JWT" ]]; then
  echo ""
  echo -e "${C_YEL}[3/3] API 응답 비교 (JWT 제공됨)${C_RST}"
  printf "%-10s  %-8s  %-10s  %s\n" "dim" "status" "bytes" "sample"
  echo "────────────────────────────────────────────────────"
  for DIM in category color size season product; do
    URL="${API_BASE}/reports/sales-cockpit/mix?startDate=${START_DATE}&endDate=${END_DATE}&storeId=${STORE_ID}&limit=10&dim=${DIM}"
    RES=$(curl -s -w "\n__HTTP_STATUS__:%{http_code}\n__SIZE__:%{size_download}" \
              -H "Authorization: Bearer ${JWT}" \
              "$URL")
    STATUS=$(echo "$RES" | grep __HTTP_STATUS__ | cut -d: -f2)
    SIZE=$(echo "$RES" | grep __SIZE__ | cut -d: -f2)
    BODY=$(echo "$RES" | sed '/__HTTP_STATUS__/,$d')
    SAMPLE=$(echo "$BODY" | head -c 120)
    # 색상: status 200 & size > 100 = 초록, 그 외 빨강
    if [[ "$STATUS" == "200" && "$SIZE" -gt 100 ]]; then
      printf "${C_GRN}%-10s  %-8s  %-10s${C_RST}  %s\n" "$DIM" "$STATUS" "$SIZE" "$SAMPLE"
    else
      printf "${C_RED}%-10s  %-8s  %-10s${C_RST}  %s\n" "$DIM" "$STATUS" "$SIZE" "$SAMPLE"
    fi
  done
else
  echo ""
  echo -e "${C_YEL}[3/3] API 비교 SKIP — JWT 미지정 (사용: --api <token>)${C_RST}"
  echo "  토큰 얻는 법:"
  echo "    1) 브라우저에서 로그인 → DevTools Network 탭"
  echo "    2) 아무 /api/* 요청 > Headers > Authorization 값 복사 (Bearer 제외)"
  echo "    3) ./scripts/test-ventas-mix-dim.sh --api <token>"
fi

echo ""
echo -e "${C_GRN}완료${C_RST}"
