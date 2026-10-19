#!/bin/bash
# usage: run.sh file.sql
{ echo "SET default_transaction_read_only=on; SET statement_timeout='60s';"; cat "$1"; } | ssh jhkim-server "sudo -u postgres psql -p 5434 -d ventago -At -F'|' -q"
