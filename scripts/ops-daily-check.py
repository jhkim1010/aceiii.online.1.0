#!/usr/bin/env python3
"""
[Phase 75 W1] VentaGo 일일 운영 점검 — 용량·추세 감시

목적
  "지금 이 순간"만 보는 기존 감시(uptime-watchdog / 500 알람)에 **추세**를 더한다.
  디스크는 어느 날 갑자기 차지 않는다. 며칠에 걸쳐 차오르다 마지막 하루에 서비스를 멈춘다.

설계 원칙
  1. JSONL 파일에 append — DB 테이블을 쓰지 않는다.
     DB 가 아플 때도 기록이 남아야 하고, 그때가 가장 중요한 순간이다.
  2. pgbouncer(5432) 를 **우회**하고 PG 5434 에 직결한다. 앱 pool 예산에 영향을 주지 않는다.
     하루 1회, 조회성 쿼리만, 커넥션 1개.
  3. **성공 침묵** — 임계 위반 시에만 즉시 Telegram. 매일 오는 "정상" 알림은 곧 무시되고,
     무시되는 알람은 진짜 사고도 함께 묻는다. 추세는 주 1회 요약으로 본다.
  4. **절대값 + 변화율** — 변화율이 더 일찍 알려준다. 그리고 소진 예측이
     "언제까지 조치해야 하는가"에 답한다.
  5. 알림 경로는 tools/uptime-watchdog.sh 의 방식을 그대로 재사용한다(.uptime.env). 새 채널을 만들지 않는다.

실행
  sudo -u postgres /var/lib/postgresql/ops-metrics/ops-daily-check.py
  옵션: --dry-run (Telegram 미발송, 리포트만 출력)

Phase 74 연계
  WAL 아카이브·복제 슬롯·백업 항목은 Phase 74 가 도입되면 값이 채워진다.
  아직 없으면 조용히 건너뛴다(에러 아님).
"""

from __future__ import annotations

import argparse
import gzip
import json
import os
import shutil
import subprocess
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

# ── 설정 ────────────────────────────────────────────────────────────────────

BASE_DIR = Path(os.environ.get('OPS_METRICS_DIR', '/var/lib/postgresql/ops-metrics'))
JSONL_PATH = BASE_DIR / 'daily.jsonl'
LOG_PATH = BASE_DIR / 'ops-daily-check.log'
ENV_PATH = BASE_DIR / '.uptime.env'          # TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID

# [Phase 75 W0-8] 컨테이너 밖으로 뺀 앱 로그. compose 의 volume 과 같은 경로여야 한다.
APP_LOG_DIR = Path(os.environ.get('APP_LOG_DIR', '/var/lib/ventago-logs/app'))

BACKUP_DIR = Path(os.environ.get('PG_BACKUP_DIR', '/var/lib/postgresql/pg_backups'))
WAL_ARCHIVE_DIR = Path(os.environ.get('PG_WAL_ARCHIVE_DIR', '/var/lib/postgresql/pg_wal_archive'))

PG_PORT = os.environ.get('OPS_PG_PORT', '5434')   # ★ pgbouncer(5432) 우회 — 직결
PG_DB = os.environ.get('OPS_PG_DB', 'ventago')
API_PORT = os.environ.get('OPS_API_PORT', '5002')

# pgbouncer admin 콘솔 — TCP 전용(unix socket 없음), stats_users 계정으로만 SHOW POOLS 가능
PGB_HOST = os.environ.get('OPS_PGB_HOST', '127.0.0.1')
PGB_PORT = os.environ.get('OPS_PGB_PORT', '5432')
PGB_USER = os.environ.get('OPS_PGB_USER', 'coolsistema')

# 감시 대상 마운트 — 존재하는 것만 사용
WATCH_MOUNTS = ['/', '/var', '/var/lib/postgresql']

# ── 임계값 ──────────────────────────────────────────────────────────────────

# env 로 덮어쓸 수 있게 둔다 — W1 게이트 2번(임계 낮춰 1회 실행 → Telegram 도달 확인)을
# 스크립트를 고치지 않고 반복 검증하기 위해서다. 고쳐서 검증하면 원복을 빠뜨린다.
DISK_PCT_WARN = float(os.environ.get('OPS_DISK_PCT_WARN', 70.0))     # 사용자 지정
DISK_PCT_CRIT = float(os.environ.get('OPS_DISK_PCT_CRIT', 85.0))
DISK_DELTA_WARN_GB = float(os.environ.get('OPS_DISK_DELTA_WARN_GB', 10.0))  # 절대값보다 먼저 잡힌다
EXHAUST_DAYS_WARN = 30        # 소진 예측 잔여일
BACKUP_STALE_HOURS = 26       # Phase 74 R4 와 동일 기준
WAL_SLOT_KEEP_RATIO_WARN = 0.70
TABLE_WEEKLY_GROWTH_WARN = 2.0  # 주간 2배 이상 증가면 이상치

GB = 1024 ** 3


# ── 유틸 ────────────────────────────────────────────────────────────────────

def log(msg: str) -> None:
    """로그 파일과 stdout 양쪽에 기록."""
    line = f"[{datetime.now().strftime('%F %T')}] {msg}"
    print(line)
    try:
        with LOG_PATH.open('a', encoding='utf-8') as f:
            f.write(line + '\n')
    except OSError:
        pass  # 로그 실패가 점검 자체를 막지 않는다


def run(cmd: list[str], timeout: int = 20) -> str | None:
    """외부 명령 실행. 실패해도 None 을 돌려주고 계속 진행한다(부분 수집 허용)."""
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        if r.returncode != 0:
            return None

        return r.stdout.strip()
    except (subprocess.SubprocessError, OSError):
        return None


def psql(sql: str, port: str = PG_PORT, db: str = PG_DB,
         user: str | None = None) -> str | None:
    """
    조회성 SQL 1건 실행 (-A -t: 구분자 없는 tuple-only).
    커넥션 1개만 쓰고 즉시 끊는다. pool 잠식 없음.
    """
    cmd = ['psql', '-p', port, '-d', db, '-A', '-t', '-X', '-q',
           '-v', 'ON_ERROR_STOP=1', '-c', sql]
    if user:
        cmd[1:1] = ['-U', user]

    return run(cmd)


def load_env() -> None:
    """.uptime.env 를 읽어 환경변수로 올린다(uptime-watchdog.sh 와 같은 방식)."""
    if not ENV_PATH.exists():
        return
    try:
        for raw in ENV_PATH.read_text(encoding='utf-8').splitlines():
            line = raw.strip()
            if not line or line.startswith('#') or '=' not in line:
                continue
            key, _, val = line.partition('=')
            os.environ.setdefault(key.strip(), val.strip().strip('"').strip("'"))
    except OSError as err:
        log(f"WARN .uptime.env 읽기 실패: {err}")


def send_telegram(text: str, dry_run: bool = False) -> None:
    """Telegram 발송. 자격증명이 없으면 로그만 남기고 넘어간다(감시 자체는 계속)."""
    token = os.environ.get('TELEGRAM_BOT_TOKEN', '')
    chat_id = os.environ.get('TELEGRAM_CHAT_ID', '')

    if dry_run:
        log(f"[dry-run] Telegram 미발송:\n{text}")

        return
    if not token or not chat_id:
        log(f"TELEGRAM 미설정 — 알림 생략: {text[:120]}")

        return

    payload = urllib.parse.urlencode({
        'chat_id': chat_id, 'text': text, 'parse_mode': 'HTML',
    }).encode()
    url = f"https://api.telegram.org/bot{token}/sendMessage"
    try:
        with urllib.request.urlopen(url, data=payload, timeout=15) as resp:
            resp.read()
    except Exception as err:  # noqa: BLE001 — 알림 실패가 점검을 막으면 안 된다
        log(f"WARN Telegram 발송 실패: {err}")


# ── 수집 ────────────────────────────────────────────────────────────────────

def collect_disk() -> dict[str, Any]:
    """파티션별 사용량. 같은 디바이스는 중복 제거."""
    out: dict[str, Any] = {}
    seen: set[tuple[int, int]] = set()
    for mount in WATCH_MOUNTS:
        p = Path(mount)
        if not p.exists():
            continue
        try:
            st = os.stat(mount)
            key = (st.st_dev, 0)
            if key in seen:
                continue
            seen.add(key)
            usage = shutil.disk_usage(mount)
        except OSError:
            continue
        out[mount] = {
            'total': usage.total,
            'used': usage.used,
            'free': usage.free,
            'pct': round(usage.used / usage.total * 100, 2) if usage.total else 0.0,
        }

    return out


def collect_postgres() -> dict[str, Any]:
    """DB 크기 · 상위 테이블 · dead tuple · 복제 슬롯. 실패 항목은 None 으로 남긴다."""
    pg: dict[str, Any] = {}

    size = psql(f"SELECT pg_database_size('{PG_DB}');")
    pg['db_size'] = int(size) if size and size.isdigit() else None

    # 상위 10개 테이블 (인덱스 포함 총 크기)
    rows = psql(
        "SELECT relname||'|'||pg_total_relation_size(relid) "
        "FROM pg_catalog.pg_statio_user_tables "
        "ORDER BY pg_total_relation_size(relid) DESC LIMIT 10;"
    )
    tables: dict[str, int] = {}
    if rows:
        for line in rows.splitlines():
            name, _, val = line.partition('|')
            if val.isdigit():
                tables[name] = int(val)
    pg['top_tables'] = tables

    # dead tuple 총합 + autovacuum 지연 의심 테이블 수
    dead = psql("SELECT COALESCE(sum(n_dead_tup),0) FROM pg_stat_user_tables;")
    pg['dead_tuples'] = int(dead) if dead and dead.isdigit() else None

    stale = psql(
        "SELECT count(*) FROM pg_stat_user_tables "
        "WHERE n_dead_tup > 10000 "
        "AND (last_autovacuum IS NULL OR last_autovacuum < now() - interval '1 day');"
    )
    pg['vacuum_overdue_tables'] = int(stale) if stale and stale.isdigit() else None

    # 복제 슬롯 (Phase 74 도입 후 값이 생긴다 — 없으면 빈 목록)
    slots = psql(
        "SELECT slot_name||'|'||COALESCE(active::text,'f')||'|'||"
        "COALESCE(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)::bigint::text,'0') "
        "FROM pg_replication_slots;"
    )
    slot_list: list[dict[str, Any]] = []
    if slots:
        for line in slots.splitlines():
            parts = line.split('|')
            if len(parts) == 3:
                slot_list.append({
                    'name': parts[0],
                    'active': parts[1] == 't',
                    'lag_bytes': int(parts[2]) if parts[2].lstrip('-').isdigit() else 0,
                })
    pg['replication_slots'] = slot_list

    keep = psql("SHOW max_slot_wal_keep_size;")
    pg['max_slot_wal_keep_size'] = keep

    pg['postmaster_start'] = psql("SELECT pg_postmaster_start_time();")

    return pg


def collect_backup() -> dict[str, Any]:
    """최신 덤프의 나이·크기. Phase 74 의 백업 감시가 여기에 얹힌다."""
    info: dict[str, Any] = {'latest_dump': None, 'age_hours': None, 'size': None, 'count': 0}
    if not BACKUP_DIR.exists():
        return info

    dumps = sorted(BACKUP_DIR.glob('ventago_*.dump'), key=lambda p: p.stat().st_mtime)
    info['count'] = len(dumps)
    if not dumps:
        return info

    latest = dumps[-1]
    st = latest.stat()
    info['latest_dump'] = latest.name
    info['size'] = st.st_size
    info['age_hours'] = round((datetime.now().timestamp() - st.st_mtime) / 3600, 2)

    return info


def collect_wal_archive() -> dict[str, Any]:
    """WAL 아카이브 디렉터리 크기 — Phase 74 R1 도입 후 의미를 갖는다."""
    info: dict[str, Any] = {'exists': WAL_ARCHIVE_DIR.exists(), 'size': None, 'files': 0}
    if not info['exists']:
        return info

    total = 0
    count = 0
    try:
        for f in WAL_ARCHIVE_DIR.iterdir():
            if f.is_file():
                total += f.stat().st_size
                count += 1
    except OSError:
        return info
    info['size'] = total
    info['files'] = count

    return info


def collect_pgbouncer() -> dict[str, Any]:
    """
    cl_waiting 피크 — 커넥션이 상한에 닿았는지 알려준다(Phase 75 G1).
    접속 권한이 없으면 조용히 None. 게이트 판정 시 이 값이 없으면 '미측정'으로 남는다.
    """
    out: dict[str, Any] = {'cl_waiting': None, 'sv_active': None, 'available': False}
    # pgbouncer 는 unix socket 없이 TCP 로만 뜬다(listen_addr=*). 인증은 md5 →
    # ~postgres/.pgpass 의 stats_users 계정(pgbouncer.ini) 로 붙는다.
    raw = run(['psql', '-h', PGB_HOST, '-p', PGB_PORT, '-U', PGB_USER, '-d', 'pgbouncer',
               '-A', '-X', '-q', '-P', 'footer=off', '-c', 'SHOW POOLS;'])
    if not raw:
        return out

    lines = raw.splitlines()
    if len(lines) < 2:
        return out

    # 컬럼 순서는 pgbouncer 버전마다 다르다(1.19 에서 cl_*_cancel_req 가 끼어들었다).
    # 위치가 아니라 헤더 이름으로 찾는다 — 위치로 세면 조용히 엉뚱한 값을 모은다.
    header = [h.strip() for h in lines[0].split('|')]
    if 'cl_waiting' not in header:
        return out

    i_wait = header.index('cl_waiting')
    i_act = header.index('sv_active') if 'sv_active' in header else None

    out['available'] = True
    waiting = 0
    active = 0
    for line in lines[1:]:
        cols = line.split('|')
        if len(cols) != len(header):
            continue
        if cols[i_wait].strip().isdigit():
            waiting += int(cols[i_wait])
        if i_act is not None and cols[i_act].strip().isdigit():
            active += int(cols[i_act])
    out['cl_waiting'] = waiting
    out['sv_active'] = active if i_act is not None else None

    return out


def collect_sockets() -> int | None:
    """API 포트의 established 연결 수 — 동시 WebSocket 규모의 대리 지표."""
    raw = run(['bash', '-c',
               f"ss -tn state established '( sport = :{API_PORT} )' 2>/dev/null | tail -n +2 | wc -l"])

    return int(raw) if raw and raw.isdigit() else None


def collect_mac_heartbeat() -> float | None:
    """
    Mac 워치독의 heartbeat 나이(시간).

    상호 감시 구조 — Mac 워치독은 "서버 백업이 도는가"를 보고,
    서버 일일 점검은 "Mac 워치독이 살아 있는가"를 본다.
    한쪽이 죽으면 다른 쪽이 알린다. 2026-08-06 에 launchd 4개가
    조용히 죽어 있던 사고(감시기를 아무도 감시하지 않음)의 재발 방지 장치다.
    """
    hb = BASE_DIR / 'mac-watchdog.heartbeat'
    if not hb.exists():
        return None

    return round((datetime.now().timestamp() - hb.stat().st_mtime) / 3600, 2)


def _percentile(values: list[float], p: float) -> int:
    """aggregate-perf.js 와 같은 방식(정렬 후 최근접 인덱스) — 두 집계가 어긋나면 안 된다."""
    if not values:
        return 0
    s = sorted(values)
    idx = min(len(s) - 1, max(0, round((len(s) - 1) * p)))

    return round(s[idx])


SAMPLES_RETENTION_DAYS = 14


def samples_path(day: str) -> Path:
    return BASE_DIR / f'samples-{day}.jsonl'


def run_sample() -> int:
    """
    [Phase 75] 하루 1회 측정으로는 **피크를 영원히 못 본다.**

    일일 점검은 04:10 UTC(아르헨티나 01:10)에 도는데 그건 하루 중 가장 조용한 시각이다.
    실제로 `sockets` 는 나흘 내내 0 이었고, `cl_waiting` 도 같은 골짜기만 찍고 있었다.
    그런데 W2 게이트("동시 연결 1/3 이하")와 G1("cl_waiting 피크 지속 0") · G6(동시 소켓
    상시 관측)은 전부 **피크**를 요구한다 — 골짜기 값으로는 판정 자체가 성립하지 않는다.

    그래서 짧은 주기로 표본만 남긴다. 무거운 수집은 하지 않는다(소켓 카운트 + pgbouncer 1회).
    """
    load_env()
    now = datetime.now(timezone.utc)
    pgb = collect_pgbouncer()
    row = {
        'ts': now.isoformat(),
        'sockets': collect_sockets(),
        'cl_waiting': pgb.get('cl_waiting'),
        'sv_active': pgb.get('sv_active'),
    }
    try:
        BASE_DIR.mkdir(parents=True, exist_ok=True)
        with samples_path(now.strftime('%Y-%m-%d')).open('a', encoding='utf-8') as f:
            f.write(json.dumps(row, ensure_ascii=False) + '\n')
    except OSError as err:
        print(f"샘플 기록 실패: {err}", file=sys.stderr)

        return 1

    # 오래된 표본 정리 — 이 파일은 초 단위로 늘어나므로 방치하면 디스크를 먹는다.
    cutoff = (now - timedelta(days=SAMPLES_RETENTION_DAYS)).strftime('%Y-%m-%d')
    try:
        for f in BASE_DIR.glob('samples-*.jsonl'):
            if f.stem.replace('samples-', '') < cutoff:
                f.unlink()
    except OSError:
        pass

    return 0


def collect_intraday(day: str) -> dict[str, Any]:
    """전일 표본에서 피크/분포를 뽑는다. 표본이 없으면 available=False."""
    out: dict[str, Any] = {'available': False, 'n': 0}
    path = samples_path(day)
    if not path.exists():
        return out

    sockets: list[float] = []
    waiting: list[float] = []
    try:
        with path.open(encoding='utf-8', errors='replace') as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    r = json.loads(line)
                except ValueError:
                    continue
                if isinstance(r.get('sockets'), (int, float)):
                    sockets.append(float(r['sockets']))
                if isinstance(r.get('cl_waiting'), (int, float)):
                    waiting.append(float(r['cl_waiting']))
    except OSError:
        return out

    if not sockets and not waiting:
        return out

    return {
        'available': True,
        'date': day,
        'n': max(len(sockets), len(waiting)),
        'sockets_peak': int(max(sockets)) if sockets else None,
        'sockets_p95': _percentile(sockets, 0.95) if sockets else None,
        'sockets_median': _percentile(sockets, 0.5) if sockets else None,
        'cl_waiting_peak': int(max(waiting)) if waiting else None,
        # 피크가 0 이 아니면 G1 이 깨진 것이다 — 하루 1회 측정으로는 볼 수 없던 값.
        'cl_waiting_nonzero_samples': sum(1 for w in waiting if w > 0),
    }


def collect_route_perf() -> dict[str, Any]:
    """
    route timing p50/p95 (Phase 75 W0-8).

    프론트가 `/app/logs/perf-YYYY-MM-DD.log` 에 JSONL 로 남긴 것을 읽는다.
    2026-08-06 까지는 이 디렉터리가 컨테이너 안에만 있어 **배포마다 사라졌고**,
    그래서 p95 기준선이 존재하지 않았다. compose 에 호스트 volume 을 붙이면서
    비로소 축적이 시작된다 — 이 값이 W7 "나아졌는가" 판정의 유일한 비교 기준이다.

    어제 파일을 본다: 이 점검은 04:10 에 돌므로 오늘 파일은 4시간치뿐이다.
    """
    out: dict[str, Any] = {'available': False, 'n': 0, 'p50': None, 'p95': None, 'slowest': []}
    day = (datetime.now() - timedelta(days=1)).strftime('%Y-%m-%d')

    # ★ winston 은 `zippedArchive: true` 로 회전한다 — **어제 파일은 보통 `.log.gz` 다.**
    #   `.log` 만 보던 초안은 2026-08-07~09 사흘치를 통째로 놓쳤다(전부 n=0).
    #   데이터는 멀쩡히 쌓이고 있었는데 읽는 쪽이 못 본 것이라, 로그만 보면 "계측이 안 된다"로
    #   오진하기 쉽다. 회전 시점과 점검 시점의 경합 때문에 둘 다 존재할 수 있으므로 둘 다 본다.
    plain = APP_LOG_DIR / f'perf-{day}.log'
    gz = APP_LOG_DIR / f'perf-{day}.log.gz'
    path = plain if plain.exists() else gz
    if not path.exists():
        return out

    routes: dict[str, list[float]] = {}
    allms: list[float] = []
    try:
        opener = (
            (lambda: gzip.open(path, 'rt', encoding='utf-8', errors='replace'))
            if path.suffix == '.gz'
            else (lambda: path.open(encoding='utf-8', errors='replace'))
        )
        with opener() as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    row = json.loads(line)
                except ValueError:
                    continue
                if row.get('kind') != 'route-timing':
                    continue
                ms = row.get('ms')
                if not isinstance(ms, (int, float)):
                    continue
                allms.append(float(ms))
                routes.setdefault(row.get('toPath') or 'unknown', []).append(float(ms))
    except OSError:
        return out

    if not allms:
        return out

    slowest = sorted(
        ({'path': k, 'p95': _percentile(v, 0.95), 'n': len(v)} for k, v in routes.items()),
        key=lambda r: -r['p95'],
    )[:5]

    return {
        'available': True,
        'date': day,
        'n': len(allms),
        'p50': _percentile(allms, 0.5),
        'p95': _percentile(allms, 0.95),
        'slowest': slowest,
    }


def collect_docker() -> dict[str, Any]:
    """Docker 이미지·컨테이너 점유. 권한 없으면 None."""
    raw = run(['docker', 'system', 'df', '--format', '{{.Type}}|{{.Size}}'])
    if not raw:
        return {'available': False}

    return {'available': True, 'raw': raw.splitlines()}


def collect() -> dict[str, Any]:
    """전체 스냅샷 1건."""
    return {
        'ts': datetime.now(timezone.utc).isoformat(),
        'date': datetime.now().strftime('%Y-%m-%d'),
        'disk': collect_disk(),
        'pg': collect_postgres(),
        'backup': collect_backup(),
        'wal_archive': collect_wal_archive(),
        'pgbouncer': collect_pgbouncer(),
        'sockets': collect_sockets(),
        'route_perf': collect_route_perf(),
        'intraday': collect_intraday(
            (datetime.now() - timedelta(days=1)).strftime('%Y-%m-%d')
        ),
        'mac_heartbeat_hours': collect_mac_heartbeat(),
        'docker': collect_docker(),
    }


# ── 이력 · 추세 ─────────────────────────────────────────────────────────────

def load_history(limit: int = 30) -> list[dict[str, Any]]:
    """최근 N일 이력. 깨진 줄은 건너뛴다."""
    if not JSONL_PATH.exists():
        return []

    rows: list[dict[str, Any]] = []
    try:
        lines = JSONL_PATH.read_text(encoding='utf-8').splitlines()
    except OSError:
        return []

    for line in lines[-limit:]:
        line = line.strip()
        if not line:
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError:
            continue

    return rows


def disk_trend(history: list[dict[str, Any]], snap: dict[str, Any],
               mount: str) -> tuple[int | None, float | None, int | None]:
    """
    (전일 대비 증분 bytes, 7일 평균 일증분 bytes, 소진 예측 잔여일) 반환.
    이력이 부족하면 None.
    """
    used_now = snap['disk'].get(mount, {}).get('used')
    if used_now is None:
        return None, None, None

    series = [h['disk'][mount]['used'] for h in history
              if h.get('disk', {}).get(mount, {}).get('used') is not None]
    if not series:
        return None, None, None

    delta_1d = used_now - series[-1]

    avg_daily: float | None = None
    exhaust_days: int | None = None
    window = series[-7:]
    if len(window) >= 2:
        span_days = len(window) - 1
        avg_daily = (used_now - window[0]) / (span_days + 1)
        free_now = snap['disk'][mount]['free']
        if avg_daily and avg_daily > 0:
            exhaust_days = int(free_now / avg_daily)

    return delta_1d, avg_daily, exhaust_days


# ── 임계 판정 ───────────────────────────────────────────────────────────────

def evaluate(snap: dict[str, Any], history: list[dict[str, Any]]) -> list[tuple[str, str]]:
    """
    (등급, 메시지) 목록. 등급: 'CRIT' | 'WARN'.
    비어 있으면 알림을 보내지 않는다 — 성공 침묵.
    """
    alerts: list[tuple[str, str]] = []

    # 디스크 — 절대값 + 변화율 + 소진 예측
    for mount, d in snap['disk'].items():
        pct = d['pct']
        if pct >= DISK_PCT_CRIT:
            alerts.append(('CRIT', f"디스크 {mount} 사용률 {pct}% (임계 {DISK_PCT_CRIT}%)"))
        elif pct >= DISK_PCT_WARN:
            alerts.append(('WARN', f"디스크 {mount} 사용률 {pct}% (임계 {DISK_PCT_WARN}%)"))

        delta_1d, _avg, exhaust = disk_trend(history, snap, mount)
        if delta_1d is not None and delta_1d > DISK_DELTA_WARN_GB * GB:
            alerts.append(('WARN',
                           f"디스크 {mount} 하루 증분 {delta_1d / GB:.1f}GB "
                           f"(임계 {DISK_DELTA_WARN_GB}GB)"))
        if exhaust is not None and exhaust < EXHAUST_DAYS_WARN:
            grade = 'CRIT' if exhaust < 7 else 'WARN'
            alerts.append((grade, f"디스크 {mount} 소진 예측 <b>{exhaust}일</b> 남음"))

    # 백업 신선도 (Phase 74 R4)
    age = snap['backup'].get('age_hours')
    if age is None:
        alerts.append(('CRIT', "백업 덤프를 찾을 수 없습니다"))
    elif age > BACKUP_STALE_HOURS:
        alerts.append(('CRIT', f"백업이 {age:.0f}시간째 갱신되지 않았습니다 (임계 {BACKUP_STALE_HOURS}h)"))

    # 복제 슬롯 (Phase 74 R1) — 수신기 사망 → WAL 축적 → 디스크 폭발 경로
    for slot in snap['pg'].get('replication_slots', []):
        if not slot['active']:
            alerts.append(('CRIT',
                           f"복제 슬롯 <code>{slot['name']}</code> 비활성 — "
                           f"WAL 축적 위험 (lag {slot['lag_bytes'] / GB:.2f}GB)"))
        keep = snap['pg'].get('max_slot_wal_keep_size') or ''
        if keep and keep not in ('-1', '0'):
            limit = parse_pg_size(keep)
            if limit and slot['lag_bytes'] > limit * WAL_SLOT_KEEP_RATIO_WARN:
                alerts.append(('WARN',
                               f"복제 슬롯 <code>{slot['name']}</code> lag 가 "
                               f"max_slot_wal_keep_size 의 70% 초과 — PITR 연속성 상실 임박"))

    # 커넥션 — Phase 75 G1
    clw = snap['pgbouncer'].get('cl_waiting')
    if clw is not None and clw > 0:
        alerts.append(('WARN', f"pgbouncer 클라이언트 대기 {clw}건 — 커넥션 상한 도달"))

    # Mac 워치독 생존 — 상호 감시. 감시기를 아무도 감시하지 않으면 조용히 죽는다.
    hb = snap.get('mac_heartbeat_hours')
    if hb is None:
        # 파일 부재 = 한 번도 안 붙었거나 지워진 것. 여기서 침묵하면 감시기 미설치가
        # 영원히 안 잡힌다 — 놓치는 쪽이 오경보보다 나쁘다.
        alerts.append(('CRIT',
                       "Mac 워치독 heartbeat 파일이 없습니다 — "
                       "외부 감시(launchd)가 미설치이거나 삭제됐습니다"))
    elif hb > BACKUP_STALE_HOURS:
        alerts.append(('CRIT',
                       f"Mac 워치독 heartbeat 가 {hb:.0f}시간째 없습니다 — "
                       f"외부 감시(launchd)가 죽었을 수 있습니다"))

    # autovacuum 지연 — outbox 3초 쿼리의 유력 원인 후보(Phase 75 W4)
    overdue = snap['pg'].get('vacuum_overdue_tables')
    if overdue and overdue > 0:
        alerts.append(('WARN', f"autovacuum 지연 의심 테이블 {overdue}개 (dead tuple 1만 초과, 1일 이상 미수행)"))

    # 테이블 주간 증가율 이상치 — 어떤 테이블이 디스크를 먹는지 지목해 준다
    if history:
        prev_week = history[-7] if len(history) >= 7 else history[0]
        old = prev_week.get('pg', {}).get('top_tables', {})
        for name, size in snap['pg'].get('top_tables', {}).items():
            before = old.get(name)
            if before and before > 100 * 1024 * 1024 and size > before * TABLE_WEEKLY_GROWTH_WARN:
                alerts.append(('WARN',
                               f"테이블 <code>{name}</code> 주간 {size / before:.1f}배 증가 "
                               f"({before / GB:.2f}GB → {size / GB:.2f}GB)"))

    return alerts


def parse_pg_size(text: str) -> int | None:
    """'10GB' / '512MB' 같은 PG 설정값을 바이트로. 해석 실패 시 None."""
    t = text.strip().upper()
    units = {'KB': 1024, 'MB': 1024 ** 2, 'GB': 1024 ** 3, 'TB': 1024 ** 4}
    for suffix, mul in units.items():
        if t.endswith(suffix):
            num = t[:-len(suffix)].strip()
            try:
                return int(float(num) * mul)
            except ValueError:
                return None
    try:
        return int(t)
    except ValueError:
        return None


# ── 리포트 ──────────────────────────────────────────────────────────────────

def human(n: int | None) -> str:
    if n is None:
        return '—'
    for unit in ('B', 'KB', 'MB', 'GB', 'TB'):
        if abs(n) < 1024:
            return f"{n:.1f}{unit}"
        n /= 1024.0  # type: ignore[assignment]

    return f"{n:.1f}PB"


def weekly_summary(snap: dict[str, Any], history: list[dict[str, Any]]) -> str:
    """주 1회 트렌드 요약 — 읽히는 빈도라 유용하다."""
    lines = ["📊 <b>VentaGo 주간 운영 요약</b>", f"<i>{snap['date']}</i>", ""]

    for mount, d in snap['disk'].items():
        delta_1d, avg, exhaust = disk_trend(history, snap, mount)
        exhaust_txt = f"{exhaust}일 후 소진" if exhaust is not None else "소진 예측 불가"
        lines.append(
            f"💾 <code>{mount}</code> {d['pct']}% "
            f"({human(d['used'])}/{human(d['total'])}) · "
            f"일증분 {human(delta_1d)} · 7일평균 {human(int(avg)) if avg else '—'} · {exhaust_txt}"
        )

    lines.append("")
    lines.append(f"🗄 DB {human(snap['pg'].get('db_size'))} · "
                 f"dead tuple {snap['pg'].get('dead_tuples') or 0:,}")

    bk = snap['backup']
    lines.append(f"💿 백업 {bk.get('latest_dump') or '없음'} · "
                 f"{human(bk.get('size'))} · {bk.get('age_hours') or '—'}h 전 · "
                 f"보관 {bk.get('count')}개")

    if snap['pgbouncer'].get('available'):
        lines.append(f"🔌 pgbouncer 대기 {snap['pgbouncer'].get('cl_waiting')} · "
                     f"서버활성 {snap['pgbouncer'].get('sv_active')}")
    lines.append(f"🔗 API 연결 {snap.get('sockets') if snap.get('sockets') is not None else '—'}")

    # [Phase 75 W0-8] route p95 — W7 "나아졌는가" 판정의 유일한 비교 기준이다.
    rp = snap.get('route_perf') or {}
    if rp.get('available'):
        lines.append(f"⏱ route p95 {rp['p95']}ms · p50 {rp['p50']}ms · n {rp['n']:,} ({rp.get('date')})")
        for r in rp.get('slowest', [])[:3]:
            lines.append(f"   · {r['path']} p95 {r['p95']}ms (n {r['n']})")
    else:
        lines.append("⏱ route p95 — (수집 없음)")

    # [Phase 75] 피크는 하루 1회 측정으로 볼 수 없다 — 짧은 주기 표본에서 뽑는다.
    intr = snap.get('intraday') or {}
    if intr.get('available'):
        lines.append(
            f"📈 전일 피크 — 소켓 {intr.get('sockets_peak')} (p95 {intr.get('sockets_p95')}, "
            f"중앙 {intr.get('sockets_median')}) · cl_waiting 최대 {intr.get('cl_waiting_peak')} "
            f"[표본 {intr.get('n')}건]"
        )
    else:
        lines.append("📈 전일 피크 — (표본 없음)")

    hb = snap.get('mac_heartbeat_hours')
    lines.append(f"🖥 Mac 워치독 heartbeat {f'{hb:.1f}h 전' if hb is not None else '없음'}")

    top = snap['pg'].get('top_tables', {})
    if top:
        lines.append("")
        lines.append("<b>상위 테이블</b>")
        for name, size in list(top.items())[:5]:
            lines.append(f"  · {name} {human(size)}")

    return '\n'.join(lines)


# ── main ────────────────────────────────────────────────────────────────────

def main() -> int:
    parser = argparse.ArgumentParser(description='VentaGo 일일 운영 점검')
    parser.add_argument('--dry-run', action='store_true',
                        help='Telegram 미발송 · JSONL 미기록 · 리포트만 출력')
    parser.add_argument('--weekly', action='store_true',
                        help='요일과 무관하게 주간 요약을 강제 발송')
    parser.add_argument('--sample', action='store_true',
                        help='표본 1건만 기록하고 종료 (짧은 주기 크론용 — 피크 포착)')
    args = parser.parse_args()

    if args.sample:
        return run_sample()

    try:
        BASE_DIR.mkdir(parents=True, exist_ok=True)
    except OSError as err:
        print(f"FATAL 디렉터리 생성 실패 {BASE_DIR}: {err}", file=sys.stderr)

        return 1

    load_env()

    history = load_history()
    snap = collect()

    # 기록 먼저 — 이후 단계가 실패해도 시계열은 남는다
    if not args.dry_run:
        try:
            with JSONL_PATH.open('a', encoding='utf-8') as f:
                f.write(json.dumps(snap, ensure_ascii=False) + '\n')
        except OSError as err:
            log(f"WARN JSONL 기록 실패: {err}")

    alerts = evaluate(snap, history)

    if alerts:
        crit = [m for g, m in alerts if g == 'CRIT']
        warn = [m for g, m in alerts if g == 'WARN']
        head = "🚨 <b>VentaGo 운영 경보</b>" if crit else "⚠️ <b>VentaGo 운영 경고</b>"
        body = [head, f"<i>{snap['date']}</i>", ""]
        for m in crit:
            body.append(f"🚨 {m}")
        for m in warn:
            body.append(f"⚠️ {m}")
        send_telegram('\n'.join(body), dry_run=args.dry_run)
        log(f"알림 발송 — CRIT {len(crit)} / WARN {len(warn)}")
    else:
        # 성공 침묵. 매일 오는 "정상" 알림은 무시되고, 무시되는 알람은 사고도 함께 묻는다.
        log("정상 — 알림 없음")

    # 주간 요약 (일요일)
    if args.weekly or datetime.now().weekday() == 6:
        send_telegram(weekly_summary(snap, history), dry_run=args.dry_run)
        log("주간 요약 발송")

    if args.dry_run:
        print()
        print(weekly_summary(snap, history))
        print()
        print(f"판정 결과: {len(alerts)}건")
        for grade, msg in alerts:
            print(f"  [{grade}] {msg}")

    return 0


if __name__ == '__main__':
    sys.exit(main())
