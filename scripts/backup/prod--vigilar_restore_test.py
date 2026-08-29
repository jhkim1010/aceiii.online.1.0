#!/usr/bin/env python3
"""**서버2 의 복구 시험이 살아 있는지 감시한다.** (운영 서버에서 매일 실행)

★★★ 왜 이것이 따로 필요한가.
  복구 시험은 서버2 에서 돈다. 그 시험이 «실패» 를 알리는 것은 서버2 자신이다.
  그런데 서버2 가 꺼지거나, 크론이 지워지거나, SSH 키가 만료되면
  **실패조차 나지 않는다 — 그냥 조용해진다.** 조용함은 정상과 구별되지 않는다.
  그래서 «보고가 도착했는가» 를 **다른 기계**(=운영)에서 본다.

  같은 형태로 세 번 당했다: 감시 장치는 «부재» 에서 침묵한다.
"""
import json
import os
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

ESTADO = Path('/var/lib/postgresql/pg_backups/estado_restore_test.json')
ENV = Path('/var/lib/postgresql/ops-metrics/.uptime.env')
LIMITE_H = 48   # 하루 걸러 한 번은 와야 한다. 이틀이면 확실히 이상이다.


def cargar_env() -> None:
    try:
        for linea in ENV.read_text(encoding='utf-8').splitlines():
            linea = linea.strip()
            if not linea or linea.startswith('#') or '=' not in linea:
                continue
            k, _, v = linea.partition('=')
            os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))
    except OSError as err:
        print(f'WARN .uptime.env 읽기 실패: {err}', file=sys.stderr)


def avisar(texto: str) -> None:
    token = os.environ.get('TELEGRAM_BOT_TOKEN', '')
    chat = os.environ.get('TELEGRAM_CHAT_ID', '')
    if not token or not chat:
        print(f'TELEGRAM 미설정 — 알림 생략: {texto[:120]}', file=sys.stderr)

        return
    datos = urllib.parse.urlencode({'chat_id': chat, 'text': texto}).encode()
    url = f'https://api.telegram.org/bot{token}/sendMessage'
    try:
        with urllib.request.urlopen(url, data=datos, timeout=15) as r:
            r.read()
    except Exception as err:  # noqa: BLE001 — 알림 실패가 감시를 막으면 안 된다
        print(f'WARN 발송 실패: {err}', file=sys.stderr)


def main() -> int:
    cargar_env()

    if not ESTADO.exists():
        avisar('🔴 복구 시험 보고가 **한 번도** 도착하지 않았다. '
               '서버2 의 크론과 SSH 키를 확인할 것.')

        return 1

    # ★ 파일의 mtime 이 아니라 **보고 안의 ts** 를 본다.
    #   서버2 가 낡은 내용을 계속 밀어도 mtime 은 매일 새로워지기 때문이다.
    try:
        d = json.loads(ESTADO.read_text(encoding='utf-8'))
        ts = time.strptime(d['ts'], '%Y-%m-%dT%H:%M:%SZ')
        edad_h = (time.time() - time.mktime(ts) + time.timezone) / 3600.0
    except Exception as err:  # noqa: BLE001
        avisar(f'🔴 복구 시험 보고를 읽을 수 없다 ({err}). 내용: '
               f'{ESTADO.read_text(encoding="utf-8", errors="replace")[:200]}')

        return 1

    resumen = (f"백업 {d.get('carpeta', '?')} · 성공 {d.get('ok', '?')} / "
               f"실패 {d.get('fallos', '?')} · 보고 {edad_h:.0f}시간 전")

    if edad_h > LIMITE_H:
        avisar(f'🔴 복구 시험이 {edad_h:.0f}시간째 보고하지 않는다 — '
               f'서버2 가 꺼졌거나 크론이 사라졌다.\n마지막: {resumen}')

        return 1

    if d.get('estado') != 'ok':
        avisar(f"🔴 마지막 복구 시험이 «{d.get('estado')}» 로 끝났다.\n{resumen}")

        return 1

    print(f'정상 — {resumen}')

    return 0


if __name__ == '__main__':
    sys.exit(main())
