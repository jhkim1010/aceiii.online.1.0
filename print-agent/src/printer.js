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

const printImage = (pngBuffer, printerConfig) => {
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
    const { printImageSilent } = require('./win-printer');

    return printImageSilent(pngBuffer, printerConfig);
  }

  return new Promise((resolve, reject) => {
    try {
      const device = createDevice(printerConfig);

      device.open(async (err) => {
        if (err) {
          return reject(new Error(`프린터 연결 실패: ${err.message}`));
        }

        try {
          const printer = new escpos.Printer(device);
          const image   = await loadImageFromBuffer(pngBuffer);

          console.log('[printImage] image loaded, size=', image?.size);

          // image() 는 Promise 반환
          printer
            .align('ct')
            .image(image, 'D24')
            .then(() => {
              printer
                .feed(4)
                .cut()
                .close(() => resolve());
            })
            .catch((imgErr) => {
              reject(new Error(`이미지 래스터 오류: ${imgErr.message}`));
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

module.exports = { printReceipt, printImage, testConnection };
