#!/usr/bin/env node
/*
 * 가상 감열 프린터 (TCP 9100 + HTML 미리보기)
 * - TCP 9100: Print Agent가 보내는 raw ESC/POS 바이트 수신
 * - HTTP 9180: 누적된 영수증을 HTML로 미리보기 (2초 자동 새로고침)
 *
 * 실행: node virtual-printer.js
 * Print Agent 설정: host=127.0.0.1, port=9100, type=network
 */

const net = require('net');
const http = require('http');

const TCP_PORT = 9100;
const HTTP_PORT = 9180;
const MAX_RECEIPTS = 50;

// 수신된 영수증 누적 (최신순)
const receipts = [];

// ESC/POS 바이트 → 텍스트 라인 배열로 파싱
// 지원: 텍스트, LF, ESC @ (init), ESC a (align), ESC E (emphasis),
//       GS V (cut), GS ! (size), ESC d (feed n lines), GS v 0 (raster image - skip)
function parseEscPos(buf) {
  const lines = [];
  let current = { text: '', align: 'left', bold: false, double: false };

  const flush = () => {
    if (current.text.length > 0 || lines.length === 0 || lines[lines.length - 1].text !== '') {
      lines.push({ ...current });
    }
    current = { text: '', align: current.align, bold: current.bold, double: current.double };
  };

  let i = 0;
  while (i < buf.length) {
    const b = buf[i];

    // LF
    if (b === 0x0a) {
      flush();
      i++;
      continue;
    }

    // CR (무시)
    if (b === 0x0d) {
      i++;
      continue;
    }

    // ESC (0x1b)
    if (b === 0x1b) {
      const cmd = buf[i + 1];

      // ESC @ — 초기화
      if (cmd === 0x40) {
        current.align = 'left';
        current.bold = false;
        current.double = false;
        i += 2;
        continue;
      }

      // ESC a n — 정렬 (0=left, 1=center, 2=right)
      if (cmd === 0x61) {
        const n = buf[i + 2];
        current.align = n === 1 ? 'center' : n === 2 ? 'right' : 'left';
        i += 3;
        continue;
      }

      // ESC E n — emphasis (bold)
      if (cmd === 0x45) {
        current.bold = buf[i + 2] !== 0;
        i += 3;
        continue;
      }

      // ESC ! n — print mode
      if (cmd === 0x21) {
        const n = buf[i + 2];
        current.bold = (n & 0x08) !== 0;
        current.double = (n & 0x30) !== 0;
        i += 3;
        continue;
      }

      // ESC d n — feed n lines
      if (cmd === 0x64) {
        const n = buf[i + 2] || 0;
        for (let k = 0; k < n; k++) flush();
        i += 3;
        continue;
      }

      // ESC J n / ESC 3 n / ESC 2 — 라인 간격 (skip)
      if (cmd === 0x4a || cmd === 0x33) { i += 3; continue; }
      if (cmd === 0x32) { i += 2; continue; }

      // ESC t n — 코드 페이지 (skip)
      if (cmd === 0x74) { i += 3; continue; }

      // ESC M n — 폰트 (skip)
      if (cmd === 0x4d) { i += 3; continue; }

      // 알 수 없는 ESC — 2바이트 skip
      i += 2;
      continue;
    }

    // GS (0x1d)
    if (b === 0x1d) {
      const cmd = buf[i + 1];

      // GS V — cut (m 또는 m n)
      if (cmd === 0x56) {
        flush();
        lines.push({ text: '✂ ─────── CUT ───────', align: 'center', bold: false, double: false, cut: true });
        // GS V m: 2바이트, GS V m n: 3바이트 — m=0/1이면 2바이트, m=65/66이면 3바이트
        const m = buf[i + 2];
        i += (m === 65 || m === 66) ? 4 : 3;
        continue;
      }

      // GS ! n — character size
      if (cmd === 0x21) {
        const n = buf[i + 2];
        current.double = n !== 0;
        i += 3;
        continue;
      }

      // GS v 0 — raster bit image (skip 전체)
      if (cmd === 0x76 && buf[i + 2] === 0x30) {
        const xL = buf[i + 4], xH = buf[i + 5];
        const yL = buf[i + 6], yH = buf[i + 7];
        const width = (xH << 8) | xL;
        const height = (yH << 8) | yL;
        const dataLen = width * height;
        lines.push({ text: `[이미지 ${width * 8}x${height}px]`, align: 'center', bold: false, double: false, image: true });
        i += 8 + dataLen;
        continue;
      }

      // GS L — left margin (skip 4 bytes)
      if (cmd === 0x4c) { i += 4; continue; }

      // GS W — print area width (skip 4 bytes)
      if (cmd === 0x57) { i += 4; continue; }

      // 알 수 없는 GS — 2바이트 skip
      i += 2;
      continue;
    }

    // 일반 텍스트 (printable + 확장 ASCII/UTF-8)
    if (b >= 0x20 || b >= 0x80) {
      // UTF-8 디코딩을 위해 바이트 누적 후 마지막에 변환
      current.text += String.fromCharCode(b);
      i++;
      continue;
    }

    // 그 외 제어문자 무시
    i++;
  }

  if (current.text.length > 0) flush();

  // Latin1 → UTF-8 재해석 (escpos 라이브러리는 cp437/latin1 사용 가능)
  return lines.map((l) => {
    try {
      const bytes = Buffer.from(l.text, 'binary');
      l.text = bytes.toString('utf8');
    } catch (_) {}

    return l;
  });
}

// HTML 렌더링
function renderHtml() {
  const items = receipts
    .map((r, idx) => {
      const linesHtml = r.lines
        .map((l) => {
          const style = [
            `text-align:${l.align}`,
            l.bold ? 'font-weight:700' : '',
            l.double ? 'font-size:18px' : 'font-size:13px',
            l.cut ? 'color:#999;border-top:1px dashed #ccc;margin-top:6px;padding-top:6px' : '',
            l.image ? 'color:#0a7;font-style:italic' : '',
          ]
            .filter(Boolean)
            .join(';');
          const text = (l.text || '&nbsp;').replace(/[<>&]/g, (c) => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;' }[c]));

          return `<div style="${style}">${text}</div>`;
        })
        .join('');

      return `
        <div class="receipt">
          <div class="receipt-header">
            <span>#${receipts.length - idx}</span>
            <span>${new Date(r.ts).toLocaleString('es-PE')}</span>
            <span>${r.bytes}B</span>
          </div>
          <div class="receipt-body">${linesHtml}</div>
        </div>`;
    })
    .join('');

  return `<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="UTF-8">
<meta http-equiv="refresh" content="2">
<title>가상 감열 프린터 (${receipts.length})</title>
<style>
  * { box-sizing: border-box; }
  body { font-family: -apple-system, system-ui, sans-serif; background: #f3f4f6; margin: 0; padding: 20px; }
  h1 { font-size: 18px; margin: 0 0 4px; color: #111; }
  .sub { color: #666; font-size: 12px; margin-bottom: 20px; }
  .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(320px, 1fr)); gap: 16px; }
  .receipt { background: #fff; border-radius: 6px; box-shadow: 0 1px 3px rgba(0,0,0,.08); overflow: hidden; }
  .receipt-header { display: flex; justify-content: space-between; padding: 8px 12px; background: #1f2937; color: #d1d5db; font-size: 11px; font-family: monospace; }
  .receipt-body { padding: 16px 14px; font-family: 'Menlo', 'Courier New', monospace; line-height: 1.4; color: #111; background: #fafafa; }
  .empty { text-align: center; padding: 60px; color: #888; }
</style>
</head>
<body>
  <h1>🖨️ 가상 감열 프린터</h1>
  <div class="sub">TCP 9100 수신 · ${receipts.length}개 영수증 · 2초 자동 새로고침</div>
  ${receipts.length === 0
    ? '<div class="empty">아직 수신된 영수증이 없습니다.<br>Print Agent에서 host=127.0.0.1, port=9100으로 설정 후 테스트 출력을 보내세요.</div>'
    : `<div class="grid">${items}</div>`}
</body>
</html>`;
}

// TCP 서버 — ESC/POS 수신
const tcpServer = net.createServer((socket) => {
  const remote = `${socket.remoteAddress}:${socket.remotePort}`;
  console.log(`[TCP] 연결됨: ${remote}`);
  const chunks = [];

  socket.on('data', (chunk) => chunks.push(chunk));

  socket.on('end', () => {
    const buf = Buffer.concat(chunks);
    if (buf.length === 0) {
      console.log(`[TCP] 빈 데이터 (${remote})`);

      return;
    }
    const lines = parseEscPos(buf);
    receipts.unshift({ ts: Date.now(), bytes: buf.length, lines });
    if (receipts.length > MAX_RECEIPTS) receipts.length = MAX_RECEIPTS;
    console.log(`[TCP] 영수증 수신 (${buf.length}B, ${lines.length}줄) from ${remote}`);
  });

  socket.on('error', (err) => {
    console.log(`[TCP] 에러 (${remote}): ${err.message}`);
  });
});

tcpServer.listen(TCP_PORT, '0.0.0.0', () => {
  console.log(`[TCP] 가상 프린터 listening on 0.0.0.0:${TCP_PORT}`);
});

// HTTP 서버 — 미리보기
const httpServer = http.createServer((req, res) => {
  if (req.url === '/clear') {
    receipts.length = 0;
    res.writeHead(302, { Location: '/' });
    res.end();

    return;
  }
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
  res.end(renderHtml());
});

httpServer.listen(HTTP_PORT, () => {
  console.log(`[HTTP] 미리보기: http://localhost:${HTTP_PORT}`);
  console.log(`[HTTP] 초기화: http://localhost:${HTTP_PORT}/clear`);
});

process.on('SIGINT', () => {
  console.log('\n종료합니다...');
  tcpServer.close();
  httpServer.close();
  process.exit(0);
});
