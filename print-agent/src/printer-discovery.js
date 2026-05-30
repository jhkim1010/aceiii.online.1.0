// print-agent/src/printer-discovery.js
// USB + 네트워크 프린터 자동 탐색
'use strict';

const net = require('net');
const os  = require('os');

// 선택적 USB 지원 (libusb 없는 환경도 graceful skip)
let USB = null;
try { USB = require('escpos-usb'); } catch (_e) { /* libusb 미설치: 네트워크만 탐색 */ }

/**
 * USB + 네트워크 프린터 탐색
 * @returns {Promise<Array<{ type: string, label: string, config: object }>>}
 */
async function discoverPrinters() {
  const results = [];

  // ── 시스템(OS) 프린터 탐색 — Windows 이름 기반 무음 인쇄용 (우선 표시) ──────
  // libusb 불필요. 설치된 모든 프린터(감열 + 일반)를 이름으로 노출.
  try {
    const { listSystemPrinters } = require('./win-printer');
    const sysPrinters = await listSystemPrinters();

    sysPrinters.forEach((p) => {
      results.push({
        type:  'windows',
        label: p.isDefault
          ? `Sistema — ${p.displayName || p.name} (predeterminada)`
          : `Sistema — ${p.displayName || p.name}`,
        config: { type: 'windows', deviceName: p.name, width: 48 },
      });
    });
  } catch (_e) {
    // electron 컨텍스트 밖이거나 조회 실패 — USB/네트워크 탐색으로 진행
  }

  // ── USB 탐색 ─────────────────────────────────────────────────────────────
  if (USB) {
    try {
      const devices = USB.findPrinter();

      devices.forEach((d) => {
        const vid = d.deviceDescriptor.idVendor.toString(16).toUpperCase().padStart(4, '0');
        const pid = d.deviceDescriptor.idProduct.toString(16).toUpperCase().padStart(4, '0');

        results.push({
          type:  'usb',
          label: `USB — VID:${vid} PID:${pid}`,
          config: {
            type:      'usb',
            vendorId:  '0x' + vid,
            productId: '0x' + pid,
          },
        });
      });
    } catch (_e) {
      // libusb 런타임 에러 — graceful skip
    }
  }

  // ── 네트워크 탐색: 로컬 서브넷 포트 9100 스캔 ─────────────────────────────
  const subnet = detectLocalSubnet();

  if (subnet) {
    const hosts = await scanSubnet(subnet, 9100, 300);

    hosts.forEach((host) => {
      results.push({
        type:  'network',
        label: `Red — ${host}:9100`,
        config: { type: 'network', host, port: 9100 },
      });
    });
  }

  return results;
}

/**
 * 로컬 IPv4 서브넷 감지 (예: '192.168.1')
 * @returns {string|null}
 */
function detectLocalSubnet() {
  const ifaces = os.networkInterfaces();

  for (const iface of Object.values(ifaces)) {
    if (!iface) continue;

    for (const addr of iface) {
      if (addr.family === 'IPv4' && !addr.internal) {
        const parts = addr.address.split('.');

        if (parts[0] !== '169') { // APIPA 제외
          return parts.slice(0, 3).join('.');
        }
      }
    }
  }

  return null;
}

/**
 * 서브넷 내 특정 포트 스캔
 * @param {string} subnet   '192.168.1'
 * @param {number} port     9100
 * @param {number} timeout  ms per host
 * @returns {Promise<string[]>}
 */
async function scanSubnet(subnet, port, timeout = 300) {
  const probes = [];

  for (let i = 1; i <= 254; i++) {
    const host = `${subnet}.${i}`;

    probes.push(
      new Promise((resolve) => {
        const sock = new net.Socket();
        let done = false;

        const finish = (ok) => {
          if (done) return;
          done = true;
          sock.destroy();
          resolve(ok ? host : null);
        };

        sock.setTimeout(timeout);
        sock.connect(port, host, () => finish(true));
        sock.on('error',   () => finish(false));
        sock.on('timeout', () => finish(false));
      })
    );
  }

  const results = await Promise.all(probes);

  return results.filter(Boolean);
}

module.exports = { discoverPrinters };
