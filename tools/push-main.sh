#!/bin/bash
# main push — 서브모듈 먼저, 루트 마지막 (submodule pointer 정합성)
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "== ventago-app push =="
git -C "$ROOT/ventago-app" push origin main

echo "== api-ventago push =="
git -C "$ROOT/api-ventago" push origin main

echo "== root push =="
git -C "$ROOT" push origin main

echo "== 완료 =="
