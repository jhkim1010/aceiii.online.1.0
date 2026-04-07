/**
 * 프린터 드라이버
 * USB 또는 네트워크 열감지 프린터로 ESC/POS 출력
 */
const escpos = require('escpos');

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
const printImage = (pngBuffer, printerConfig) => {
  return new Promise((resolve, reject) => {
    try {
      const device = createDevice(printerConfig);

      device.open((err) => {
        if (err) {
          return reject(new Error(`프린터 연결 실패: ${err.message}`));
        }

        try {
          const printer = new escpos.Printer(device);
          const image   = escpos.Image.load(pngBuffer);

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
