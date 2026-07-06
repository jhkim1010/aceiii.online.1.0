/**
 * 프린터 드라이버
 * USB 또는 네트워크 열감지 프린터로 ESC/POS 출력
 */
const escpos = require('escpos');
const fs = require('fs');
const os = require('os');
const path = require('path');

// ─── 개발 모드 감지 ─────────────────────────────────────────────────────────
// main.js 가 process.env.PRINT_AGENT_DEV='1' 을 세팅함.
// dev 일 때 printImage 는 실 프린터 대신 ~/Desktop/print-debug-*.png 로 저장.
const isDevMode = () => process.env.PRINT_AGENT_DEV === '1';

// PNG 미리보기 저장 경로 — 데스크톱 우선, 없으면 홈 디렉토리
const getPreviewDir = () => {
  const desktop = path.join(os.homedir(), 'Desktop');
  try {
    if (fs.existsSync(desktop) && fs.statSync(desktop).isDirectory()) return desktop;
  } catch (_) {}

  return os.homedir();
};

// PNG 버퍼를 파일로 저장하고 절대경로 반환
const savePreviewPng = (pngBuffer) => {
  const dir = getPreviewDir();
  const stamp = new Date()
    .toISOString()
    .replace(/[-:]/g, '')
    .replace(/\..+/, '')
    .replace('T', '_');
  const filePath = path.join(dir, `print-debug-${stamp}.png`);
  fs.writeFileSync(filePath, pngBuffer);

  return filePath;
};

// USB/네트워크 어댑터 로드 (설치 실패 시 graceful fallback)
let USB, Network;
try { USB = require('escpos-usb'); } catch (e) { USB = null; }
try { Network = require('escpos-network'); } catch (e) { Network = null; }

/**
 * 프린터 디바이스 생성
 */
const createDevice = (printerConfig) => {
  if (printerConfig.type === 'usb') {
    if (!USB) throw new Error('escpos-usb 패키지가 설치되지 않았습니다');
    return new USB(
      parseInt(printerConfig.vendorId, 16) || undefined,
      parseInt(printerConfig.productId, 16) || undefined
    );
  }

  if (printerConfig.type === 'network') {
    if (!Network) throw new Error('escpos-network 패키지가 설치되지 않았습니다');
    return new Network(printerConfig.host, printerConfig.port || 9100);
  }

  throw new Error(`지원하지 않는 프린터 타입: ${printerConfig.type}`);
};

/**
 * 영수증 출력
 * @param {string[]} lines - 포맷된 텍스트 라인 배열
 * @param {object} printerConfig - config.json의 printer 설정
 */
const printReceipt = (lines, printerConfig) => {
  return new Promise((resolve, reject) => {
    try {
      const device = createDevice(printerConfig);

      device.open((err) => {
        if (err) {
          return reject(new Error(`프린터 연결 실패: ${err.message}`));
        }

        try {
          const printer = new escpos.Printer(device);

          // ESC/POS 명령으로 출력
          printer
            .font('a')
            .align('lt')
            .style('normal')
            .size(1, 1);

          // 각 라인 출력
          for (const line of lines) {
            printer.text(line);
          }

          // 용지 절단 + 닫기
          printer
            .cut()
            .close(() => {
              resolve();
            });
        } catch (printError) {
          reject(new Error(`출력 중 오류: ${printError.message}`));
        }
      });
    } catch (deviceError) {
      reject(new Error(`디바이스 생성 실패: ${deviceError.message}`));
    }
  });
};

/**
 * 프린터 연결 테스트
 */
const testConnection = (printerConfig) => {
  // DEV 모드: 실 프린터 없어도 셋업 마법사가 진행되도록 가짜 성공 반환
  if (isDevMode()) {
    console.log(`[testConnection:DEV] 🟢 가짜 성공 — config: ${JSON.stringify(printerConfig)}`);

    return Promise.resolve({ devPreview: true });
  }

  // ── Windows/시스템 프린터: 이름이 목록에 존재하는지로 연결 확인 ──
  if (printerConfig.type === 'windows') {
    const { listSystemPrinters } = require('./win-printer');

    return listSystemPrinters().then((list) => {
      const found = list.some((p) => p.name === printerConfig.deviceName);

      if (!found) {
        throw new Error(`프린터 "${printerConfig.deviceName || '(sin nombre)'}" 를 찾을 수 없음`);
      }

      return {};
    });
  }

  return new Promise((resolve, reject) => {
    try {
      const device = createDevice(printerConfig);
      device.open((err) => {
        if (err) {
          return reject(new Error(`프린터 연결 불가: ${err.message}`));
        }
        // 연결 성공 → 바로 닫기
        try {
          const printer = new escpos.Printer(device);
          printer.close(() => resolve());
        } catch (e) {
          resolve(); // 닫기 실패해도 연결은 성공
        }
      });
    } catch (error) {
      reject(error);
    }
  });
};

/**
 * PNG 이미지 버퍼 → ESC/POS 래스터 이미지 출력
 *
 * 파이프라인:
 *   PNG Buffer (Electron offscreen BrowserWindow에서 캡처)
 *   → escpos.Image.load()
 *   → printer.image() 래스터 명령
 *   → cut()
 *
 * @param {Buffer} pngBuffer - PNG 바이너리 버퍼
 * @param {object} printerConfig - printer 설정
 */
// escpos.Image.load 를 Promise 로 감싸기 — 시그니처: load(url, type, callback).
// Buffer 입력의 경우 get-pixels 가 MIME 타입을 요구하므로 'image/png' 명시.
// callback 을 생략하면 get-pixels 내부에서 "callback is not a function" 오류 발생.
const loadImageFromBuffer = (pngBuffer) => {
  return new Promise((resolve, reject) => {
    try {
      escpos.Image.load(pngBuffer, 'image/png', (result) => {
        // escpos 는 성공/실패 모두 단일 콜백으로 반환 — Error instance 로 분기
        if (result instanceof Error) {
          return reject(new Error(`이미지 로드 실패: ${result.message}`));
        }

        resolve(result);
      });
    } catch (loadErr) {
      reject(new Error(`이미지 로드 throw: ${loadErr.message}`));
    }
  });
};

/**
 * 네트워크 프린터 TCP preflight — escpos-network 의 device.open 은 connect
 * 타임아웃이 없어 프린터 다운 시 OS TCP 타임아웃(수십 초)까지 hang 된다.
 * 인쇄 전 짧은 TCP 연결로 도달성을 확인해 빠르고 명확하게 실패시킨다.
 *
 * @param {string} host
 * @param {number} port
 * @param {number} timeoutMs
 */
const preflightTcp = (host, port, timeoutMs = 2500) => {
  return new Promise((resolve, reject) => {
    const net = require('net');
    const sock = new net.Socket();
    let settled = false;

    const finish = (err) => {
      if (settled) return;
      settled = true;
      try { sock.destroy(); } catch (_e) { /* ignore */ }
      if (err) reject(err); else resolve();
    };

    const timer = setTimeout(
      () => finish(new Error(`프린터 도달 불가 (${host}:${port} — ${timeoutMs}ms 타임아웃)`)),
      timeoutMs,
    );

    sock.once('connect', () => { clearTimeout(timer); finish(); });
    sock.once('error', (e) => {
      clearTimeout(timer);
      finish(new Error(`프린터 도달 불가 (${host}:${port} — ${e.code || e.message})`));
    });

    try {
      sock.connect({ host, port });
    } catch (e) {
      clearTimeout(timer);
      finish(new Error(`프린터 도달 불가 (${host}:${port} — ${e.message})`));
    }
  });
};

const printImage = async (pngBuffer, printerConfig, log = () => {}) => {
  // ── DEV 모드: 실 프린터 호출 없이 PNG 만 저장 (PNG 미리보기 모드) ──
  // 80mm = 576px @ 203dpi 로 렌더된 이미지를 그대로 저장.
  // 운영 모드에서는 escpos 디바이스로 전송.
  if (isDevMode()) {
    return new Promise((resolve, reject) => {
      try {
        const filePath = savePreviewPng(pngBuffer);
        console.log(`[printImage:DEV] 🖼️  실 프린터 출력 스킵 — PNG 저장: ${filePath}`);
        console.log(`[printImage:DEV]    프린터 설정: ${JSON.stringify(printerConfig)}`);
        resolve({ devPreview: true, path: filePath });
      } catch (err) {
        reject(new Error(`PNG 미리보기 저장 실패: ${err.message}`));
      }
    });
  }

  // ── Windows/시스템 프린터: OS 드라이버 무음 인쇄 (libusb 불필요) ──
  // deviceName 으로 특정 프린터 고정 선택. 절단/용지폭은 드라이버 설정 따름.
  if (printerConfig.type === 'windows') {
    log(`🪟 [printImage] windows 드라이버 무음 인쇄 — device="${printerConfig.deviceName || '-'}"`);
    const { printImageSilent } = require('./win-printer');

    return printImageSilent(pngBuffer, printerConfig, log);
  }

  // 네트워크 프린터: 인쇄 전 TCP preflight — escpos open hang 대신 2.5초 내 명확한 실패
  if (printerConfig.type === 'network') {
    const pfT = Date.now();

    await preflightTcp(printerConfig.host, Number(printerConfig.port) || 9100);
    log(`🔎 [printImage] preflight OK (${Date.now() - pfT}ms)`);
  }

  return new Promise((resolve, reject) => {
    try {
      log(
        `🔌 [printImage] 디바이스 생성 type=${printerConfig.type} ` +
          `${printerConfig.host || ''}:${printerConfig.port || 9100}`,
      );
      const device  = createDevice(printerConfig);
      const openT   = Date.now();

      device.open(async (err) => {
        if (err) {
          // 가장 흔한 실패 지점 — 프린터 오프라인/IP·포트 오류/방화벽
          log(`❌ [printImage] 프린터 연결 실패 (${Date.now() - openT}ms): ${err.message}`);

          return reject(new Error(`프린터 연결 실패: ${err.message}`));
        }
        log(`🔗 [printImage] 프린터 연결 성공 (${Date.now() - openT}ms)`);

        try {
          const printer = new escpos.Printer(device);
          const image   = await loadImageFromBuffer(pngBuffer);

          log(`🖼️ [printImage] 이미지 로드 완료 size=${JSON.stringify(image ? image.size : null)}`);
          console.log('[printImage] image loaded, size=', image?.size);

          // ── 백지 진단(최종 방어선): escpos 가 실제 래스터화할 잉크 픽셀 수 측정 ──
          // image.data 는 픽셀당 0(백색)/1(잉크) 플랫 배열. 이 값이 0 이면 프린터로
          // 전부 백색만 전송 → 종이는 나오지만 아무것도 안 찍힘(빈 종이) 확정.
          try {
            const inkCount = Array.isArray(image?.data)
              ? image.data.reduce((sum, v) => sum + (v ? 1 : 0), 0)
              : -1;

            if (inkCount === 0) {
              log('🟥 [printImage] 경고: 래스터 잉크 픽셀 0 — 빈 종이 확정(렌더 백지). 프린터 아닌 렌더 단계 문제');
            } else {
              log(`🔬 [printImage] 래스터 잉크 픽셀=${inkCount} (0 이면 빈 종이)`);
            }
          } catch (inkErr) {
            log(`🔬 [printImage] 잉크 측정 실패: ${inkErr.message}`);
          }

          // image() 는 Promise 반환
          const rasterT = Date.now();
          printer
            .align('ct')
            .image(image, 'D24')
            .then(() => {
              log(`📤 [printImage] 래스터 전송 완료 (${Date.now() - rasterT}ms) → feed/cut`);
              printer
                .feed(4)
                .cut()
                .close(() => {
                  log('✂️ [printImage] cut/close 완료');
                  resolve();
                });
            })
            .catch((imgErr) => {
              log(`❌ [printImage] 이미지 래스터 오류: ${imgErr.message}`);
              reject(new Error(`이미지 래스터 오류: ${imgErr.message}`));
            });
        } catch (printError) {
          log(`❌ [printImage] 출력 중 오류: ${printError.message}`);
          reject(new Error(`출력 중 오류: ${printError.message}`));
        }
      });
    } catch (deviceError) {
      log(`❌ [printImage] 디바이스 생성 실패: ${deviceError.message}`);
      reject(new Error(`디바이스 생성 실패: ${deviceError.message}`));
    }
  });
};

module.exports = { printReceipt, printImage, testConnection };
