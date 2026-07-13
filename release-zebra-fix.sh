#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────
# zebra-agent 릴리즈 스크립트 (Windows RAW 인쇄 수정 배포)
# 사용법: 저장소 루트(ACE_online_1.0)에서
#         bash release-zebra-fix.sh
# 하는 일: zebra-agent 변경 커밋 → 다음 zebra-agent-v* 태그 생성 → push
#          → GitHub Actions(build-zebra-agent.yml) 가 Setup.exe 빌드하여
#            jhkim1010/ventago-downloads 에 업로드 (+ zebra-agent-latest 피드)
# ─────────────────────────────────────────────────────────────────────────
set -e

# 저장소 루트 자동 탐지 (어느 하위 폴더에서 실행해도 동작)
ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$ROOT_DIR" ]; then
  echo "✗ git 저장소 안에서 실행하세요 (ACE_online_1.0 내부)."
  exit 1
fi
cd "$ROOT_DIR"

BRANCH="$(git branch --show-current)"
echo "저장소: $ROOT_DIR"
echo "브랜치: $BRANCH"
echo ""

echo "--- zebra-agent 변경 스테이징 ---"
git add zebra-agent/
if git diff --cached --quiet; then
  echo "커밋할 zebra-agent 변경 없음 (이미 커밋된 상태에서 태그만 진행)"
else
  git commit -m "fix(zebra-agent): impresion USB Windows por winspool RAW

Reemplaza Out-Printer (renderiza via driver GDI -> imprime el ZPL como
documento de N paginas) por WritePrinter con datatype=RAW (winspool),
que envia el ZPL crudo directo a la impresora sin pasar por el driver.
Corrige el sintoma 'Printing - Page N of document' en GC420t USB."
  echo "커밋 완료"
fi
echo ""

echo "--- 다음 태그 계산 ---"
LATEST="$(git tag --list 'zebra-agent-v*' --sort=-version:refname | head -1)"
if [ -z "$LATEST" ]; then
  NEW="zebra-agent-v1.0.0"
else
  V="${LATEST#zebra-agent-v}"
  MA="$(echo "$V" | cut -d. -f1)"
  MI="$(echo "$V" | cut -d. -f2)"
  PA="$(echo "$V" | cut -d. -f3)"
  NEW="zebra-agent-v${MA}.${MI}.$((PA + 1))"
fi
echo "이전 태그: ${LATEST:-(없음)}  →  새 태그: $NEW"
git tag "$NEW"
echo ""

echo "--- push (origin $BRANCH + 태그) ---"
git push origin "$BRANCH" --tags
echo ""
echo "✓ 완료 — GitHub Actions 빌드 트리거됨: $NEW"
echo "  진행 상황: https://github.com/jhkim1010/aceiii.online.1.0/actions"
echo "  결과물:    https://github.com/jhkim1010/ventago-downloads/releases"
