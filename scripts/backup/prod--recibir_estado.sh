#!/usr/bin/env bash
# **서버2 의 복구 시험 결과를 받아 적는다.** (운영 서버에서 실행)
#
# ★★★ 왜 «서버2 가 민다»(운영이 당기지 않고). 운영 → 서버2 로 새 통로를 열면
#   운영이 뚫렸을 때 백업 시험장까지 같이 뚫린다. 서버2 → 운영 방향은 백업을
#   당겨오느라 **이미 열려 있는 방향**이라, 여기에 얹으면 노출이 안 늘어난다.
#
# ★★ 이 스크립트는 authorized_keys 의 `command=` 로 강제 실행된다.
#   그래서 서버2 가 무슨 명령을 보내든 **여기만 돈다** — SSH_ORIGINAL_COMMAND 를
#   절대 쓰지 않는다(쓰는 순간 강제 명령이 무의미해진다).
set -uo pipefail

DEST="/var/lib/postgresql/pg_backups/estado_restore_test.json"
TMP="${DEST}.tmp.$$"

# ★ 입력은 «서버2 가 보낸 것» 이다. 서버2 가 뚫리면 여기로 아무거나 들어온다.
#   그래서 (1) 크기를 자르고 (2) 제어문자를 지운다. 이 파일은 감시 스크립트가
#   읽을 뿐이지만, 로그에 그대로 찍히면 터미널을 조작할 수 있다.
head -c 4096 | tr -d '\000-\010\013\014\016-\037' > "${TMP}"

if [ ! -s "${TMP}" ]; then
    rm -f "${TMP}"
    echo "빈 보고 — 무시" >&2
    exit 1
fi

mv -f "${TMP}" "${DEST}"
chmod 640 "${DEST}"
echo "ok"
