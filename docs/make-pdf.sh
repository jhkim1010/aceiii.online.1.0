#!/usr/bin/env bash
# docs/make-pdf.sh — 마크다운 문서를 PDF 로 변환한다.
#
#   ./docs/make-pdf.sh docs/manual-flujo-produccion.md
#   ./docs/make-pdf.sh                       # 인자 없으면 생산 흐름 매뉴얼
#
# pandoc/wkhtmltopdf 를 설치하지 않는다 — macOS 에 이미 있는 Chrome 헤드리스로 인쇄한다.
# 한글·스페인어가 섞이므로 시스템 폰트를 그대로 쓴다.
set -euo pipefail

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
[ -x "$CHROME" ] || { echo "Chrome 을 찾을 수 없다: $CHROME" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${1:-$ROOT/docs/manual-flujo-produccion.md}"
[ -f "$SRC" ] || { echo "입력 파일 없음: $SRC" >&2; exit 1; }

OUT="${SRC%.md}.pdf"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
HTML="$TMP/doc.html"

# 마크다운 → HTML (의존성 없이 python 표준 라이브러리로 최소 변환)
python3 - "$SRC" "$HTML" <<'PY'
import html, re, sys

src, out = sys.argv[1], sys.argv[2]
lines = open(src, encoding='utf-8').read().split('\n')
body, in_code, in_table = [], False, False

def inline(s: str) -> str:
    s = html.escape(s)
    s = re.sub(r'`([^`]+)`', r'<code>\1</code>', s)
    s = re.sub(r'\*\*([^*]+)\*\*', r'<strong>\1</strong>', s)
    return s

def close_table():
    global in_table
    if in_table:
        body.append('</tbody></table>')
        in_table = False

for raw in lines:
    line = raw.rstrip()

    if line.startswith('```'):
        close_table()
        body.append('</pre>' if in_code else '<pre>')
        in_code = not in_code
        continue
    if in_code:
        body.append(html.escape(raw))
        continue

    # 표: | a | b |  / 구분선은 건너뛴다
    if line.startswith('|') and line.endswith('|'):
        cells = [c.strip() for c in line.strip('|').split('|')]
        if all(re.fullmatch(r':?-{2,}:?', c) for c in cells):
            continue
        if not in_table:
            body.append('<table><thead>')
            body.append('<tr>' + ''.join(f'<th>{inline(c)}</th>' for c in cells) + '</tr>')
            body.append('</thead><tbody>')
            in_table = True
        else:
            body.append('<tr>' + ''.join(f'<td>{inline(c)}</td>' for c in cells) + '</tr>')
        continue
    close_table()

    if not line.strip():
        body.append('')
        continue
    if line.startswith('---'):
        body.append('<hr/>')
        continue
    m = re.match(r'^(#{1,6})\s+(.*)$', line)
    if m:
        lvl = len(m.group(1))
        body.append(f'<h{lvl}>{inline(m.group(2))}</h{lvl}>')
        continue
    if line.startswith('>'):
        body.append(f'<blockquote>{inline(line.lstrip("> "))}</blockquote>')
        continue
    # 이미지: ![캡션](경로)  — 단독 줄일 때만 <figure> 로 렌더
    m = re.match(r'^!\[([^\]]*)\]\(([^)]+)\)\s*$', line)
    if m:
        cap, path = m.group(1), m.group(2)
        # md 파일 기준 상대경로를 절대경로로 (Chrome file:// 로드용)
        import os
        abspath = os.path.abspath(os.path.join(os.path.dirname(src), path))
        body.append(
            f'<figure><img src="file://{html.escape(abspath)}"/>'
            f'<figcaption>{inline(cap)}</figcaption></figure>'
        )
        continue

    m = re.match(r'^(\s*)[-*]\s+(.*)$', line)
    if m:
        body.append(f'<li>{inline(m.group(2))}</li>')
        continue
    m = re.match(r'^(\s*)(\d+)\.\s+(.*)$', line)
    if m:
        body.append(f'<li>{inline(m.group(3))}</li>')
        continue
    body.append(f'<p>{inline(line)}</p>')

close_table()
if in_code:
    body.append('</pre>')

CSS = """
@page { size: A4; margin: 16mm 14mm; }
body { font-family: -apple-system, 'Apple SD Gothic Neo', 'Helvetica Neue', sans-serif;
       font-size: 10.5pt; line-height: 1.55; color: #1a1a2e; }
h1 { font-size: 20pt; border-bottom: 3px solid #f5a623; padding-bottom: 6px; }
h2 { font-size: 15pt; margin-top: 22px; border-bottom: 1px solid #ddd; padding-bottom: 4px;
     page-break-after: avoid; }
h3 { font-size: 12.5pt; margin-top: 16px; page-break-after: avoid; }
code { background: #f4f4f7; padding: 1px 4px; border-radius: 3px;
       font-family: 'SF Mono', Menlo, monospace; font-size: 9.3pt; }
pre  { background: #1a1a2e; color: #eaeaea; padding: 10px 12px; border-radius: 5px;
       font-family: 'SF Mono', Menlo, monospace; font-size: 8.8pt; line-height: 1.45;
       white-space: pre-wrap; word-break: break-word; page-break-inside: avoid; }
pre code { background: none; color: inherit; padding: 0; }
table { border-collapse: collapse; width: 100%; margin: 10px 0; font-size: 9.5pt;
        page-break-inside: avoid; }
th { background: #1a1a2e; color: #fff; text-align: left; }
th, td { border: 1px solid #ccc; padding: 5px 7px; vertical-align: top; }
tbody tr:nth-child(even) { background: #fafafa; }
blockquote { border-left: 4px solid #f5a623; background: #fffdf5; margin: 10px 0;
             padding: 7px 12px; }
blockquote p { margin: 0; }
li { margin-left: 18px; }
hr { border: none; border-top: 1px solid #e0e0e0; margin: 18px 0; }
figure { margin: 12px 0 16px; page-break-inside: avoid; }
figure img { width: 100%; border: 1px solid #ccc; border-radius: 4px; }
figcaption { font-size: 8.8pt; color: #666; margin-top: 4px; text-align: center; }
"""

open(out, 'w', encoding='utf-8').write(
    f'<!doctype html><meta charset="utf-8"><style>{CSS}</style>\n' + '\n'.join(body)
)
PY

"$CHROME" --headless --disable-gpu --no-pdf-header-footer \
  --print-to-pdf="$OUT" "file://$HTML" >/dev/null 2>&1

[ -f "$OUT" ] || { echo "PDF 생성 실패" >&2; exit 1; }
echo "생성 완료: $OUT ($(du -h "$OUT" | cut -f1))"
