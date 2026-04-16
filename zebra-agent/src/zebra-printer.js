/**
 * Zebra 프린터 TCP Raw Socket 전송 (포트 9100)
 * 요청마다 소켓 생성 → 전송 완료 즉시 socket.end() (누수 방지)
 */
const net = require('net');

const DEFAULT_PORT = 9100;
const CONNECT_TIMEOUT = 5000;

/**
 * ZPL 문자열을 Zebra 프린터로 전송
 * @param {string} zplString - ZPL II 명령 문자열
 * @param {string} host - 프린터 IP
 * @param {number} [port=9100] - 프린터 포트
 * @returns {Promise<{ ok: boolean, error?: string }>}
 */
function sendZpl(zplString, host, port = DEFAULT_PORT) {
  return new Promise((resolve) => {
    if (!host) {
      resolve({ ok: false, error: 'host requerido' });

      return;
    }

    const socket = new net.Socket();
    let settled = false;

    const finish = (result) => {
      if (settled) return;
      settled = true;
      socket.destroy();
      resolve(result);
    };

    socket.setTimeout(CONNECT_TIMEOUT);

    socket.on('timeout', () => {
      console.error(`[ZebraPrinter] timeout ${host}:${port}`);
      finish({ ok: false, error: `timeout ${host}:${port}` });
    });

    socket.on('error', (err) => {
      console.error(`[ZebraPrinter] error ${host}:${port}:`, err.message);
      finish({ ok: false, error: err.message });
    });

    socket.connect(port, host, () => {
      socket.write(zplString, 'utf8', (writeErr) => {
        if (writeErr) {
          console.error(`[ZebraPrinter] write error:`, writeErr.message);
          finish({ ok: false, error: writeErr.message });

          return;
        }

        // 전송 완료 → 즉시 종료
        socket.end(() => {
          finish({ ok: true });
        });
      });
    });
  });
}

/**
 * 프린터 연결 테스트 (빈 ZPL 전송 없이 TCP 연결만 확인)
 * @param {string} host
 * @param {number} [port=9100]
 * @returns {Promise<boolean>}
 */
function testConnection(host, port = DEFAULT_PORT) {
  return new Promise((resolve) => {
    const socket = new net.Socket();
    socket.setTimeout(3000);

    socket.on('connect', () => {
      socket.destroy();
      resolve(true);
    });

    socket.on('timeout', () => {
      socket.destroy();
      resolve(false);
    });

    socket.on('error', () => {
      socket.destroy();
      resolve(false);
    });

    socket.connect(port, host);
  });
}

module.exports = { sendZpl, testConnection, DEFAULT_PORT };
