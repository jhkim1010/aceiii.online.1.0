#!/usr/bin/env bash
# **최신 전체 백업 폴더를 tar 로 흘려보낸다 — 읽기 전용.**
#
# ★★★ 이 스크립트가 존재하는 이유는 **권한을 좁히기 위해서**다. 백업 서버가
#   운영 서버에 셸을 갖게 하면, 운영이 뚫렸을 때가 아니라 **백업 서버가 뚫렸을 때**
#   운영까지 함께 간다. `authorized_keys` 의 `command=` 로 이 스크립트 하나에
#   묶어 두면, 그 키로 할 수 있는 일은 «최신 백업을 읽는 것» 뿐이다.
#
# ★★ 인자를 받지 않는다. `SSH_ORIGINAL_COMMAND` 도 보지 않는다 — 보면 그것이
#   곧 우회로가 된다.
set -euo pipefail
BASE="/var/lib/postgresql/pg_backups/todas"
D="$(ls -dt "${BASE}"/20* 2>/dev/null | head -1)"
[ -n "${D}" ] || { echo "백업 폴더 없음" >&2; exit 1; }
# stdout 으로만 나간다. 이름은 폴더명 그대로 — 받는 쪽이 어느 시점인지 알아야 한다.
echo "${D##*/}" >&2
tar -C "${BASE}" -cf - "${D##*/}"
