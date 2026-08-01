#!/usr/bin/env bash
# settleClosedPrevious 자동 이체 검증 — 서랍을 새로 연 다음날 실행한다.
#
#   ./tools/check-caja-settlement.sh            # 오늘 기준
#   ./tools/check-caja-settlement.sh 2026-08-02 # 날짜 지정
#
# 기대: 그날 처음 열린 서랍마다, 직전 마감분이 아직 정산되지 않았다면
#       caja_fuerte_operations 에 source='auto_cierre' 1행 + 직전 등록에 retiro(automatico) 1행.
set -euo pipefail
DAY="${1:-$(date +%F)}"

ssh jhkim-server "sudo -u postgres psql -p 5434 -d ventago -A -F' | ' \
  -c \"\\echo '=== 1) 그날 개시된 caja ==='\" \
  -c \"SELECT cr.id, b.name caja, cr.date, cr.start_time, cr.initial_amount, cr.user_id
        FROM cash_registers cr JOIN boxes b ON b.id=cr.box_id
       WHERE cr.date='${DAY}' AND b.is_deleted=false ORDER BY b.id, cr.id;\" \
  -c \"\\echo '=== 2) 그날 발생한 금고 자동이체 (source=auto_cierre) ==='\" \
  -c \"SELECT o.id, o.cash_register_id, o.amount, o.type, o.description, o.created_at
        FROM caja_fuerte_operations o
       WHERE o.source='auto_cierre' AND o.created_at::date='${DAY}' ORDER BY o.id;\" \
  -c \"\\echo '=== 3) 그날 기록된 자동 retiro (직전 등록 상쇄분) ==='\" \
  -c \"SELECT id, cash_register_id, amount, description, created_at
        FROM box_operations
       WHERE execution_type='automatico' AND type='retiro' AND created_at::date='${DAY}'
       ORDER BY id;\" \
  -c \"\\echo '=== 4) 이중 이체 감시 — 등록 1건당 auto_cierre 가 2회 이상이면 결함 ==='\" \
  -c \"SELECT cash_register_id, count(*) veces, SUM(amount) total
        FROM caja_fuerte_operations WHERE source='auto_cierre'
       GROUP BY cash_register_id HAVING count(*) > 1 ORDER BY 1;\" \
  -c \"\\echo '=== 5) 금고 잔액 ==='\" \
  -c \"SELECT cf.id, b.name sucursal, cf.balance
        FROM caja_fuertes cf JOIN branches b ON b.id=cf.branch_id ORDER BY cf.id;\""
