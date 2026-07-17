#!/usr/bin/env bash
# pg_backups → Dropbox 자동 업로드 (rclone)
# 실행: postgres OS 유저 (백업 크론 03:17 직후 03:40에 실행)
# 정책: 복사(copy) — 서버 14일 로테이션은 기존 pg_backup_ventago.sh가 관리
# DB 커넥션을 전혀 사용하지 않으므로 pool에 영향 없음
set -uo pipefail

BACKUP_DIR="/var/lib/postgresql/pg_backups"
REMOTE="dropbox:ventago_pg_backups"
LOG="${BACKUP_DIR}/dropbox_sync.log"

log(){ echo "[$(date '+%F %T')] $*" >> "${LOG}"; }

log "Dropbox 업로드 시작"

# 백업 파일만 복사 (쓰기 진행 중인 파일 회피: 생성 1분 이상 지난 파일만)
if rclone copy "${BACKUP_DIR}" "${REMOTE}" \
    --include "ventago_*.dump" \
    --include "globals_*.sql.gz" \
    --min-age 1m \
    --bwlimit 8M \
    --retries 5 --retries-sleep 30s \
    --log-file "${LOG}" --log-level INFO; then
    log "Dropbox 업로드 성공"
else
    log "Dropbox 업로드 실패 — dropbox_sync.log 확인 필요"
    exit 1
fi

# (선택) Dropbox 쪽 90일 초과 백업 자동 정리 — 원하면 아래 주석 해제
# rclone delete "${REMOTE}" --min-age 90d --include "ventago_*.dump" --include "globals_*.sql.gz" >> "${LOG}" 2>&1

log "완료"
