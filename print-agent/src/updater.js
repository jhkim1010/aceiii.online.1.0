// src/updater.js — electron-updater 기반 자동 업데이트 (Windows 전용)
//
// 동작 원리:
//   1) 부팅 10초 후 + 이후 4시간마다 publish URL(고정 롤링 릴리즈)의 latest.yml 확인
//   2) 새 버전 발견 → 백그라운드 다운로드 (SHA512 검증 포함)
//   3) 앱 종료 시 자동 설치 (autoInstallOnAppQuit) — 트레이 수동 설치 메뉴도 제공
//
// 스킵 조건:
//   - dev 모드 / 미패키징 (app.isPackaged === false)
//   - macOS/Linux (코드서명 없어 자동 업데이트 불가 — 매장 PC 는 Windows)
const { app } = require('electron');

// 4시간마다 재확인 — 매장 영업 중 하루 2~3회 체크 수준
const CHECK_INTERVAL_MS = 4 * 60 * 60 * 1000;

// 부팅 직후는 WebSocket 연결 등과 겹치지 않도록 10초 지연
const FIRST_CHECK_DELAY_MS = 10 * 1000;

/**
 * 자동 업데이트 초기화.
 * @param {object}   opts
 * @param {Function} opts.onLog               로그 콜백 (broadcastLog)
 * @param {Function} opts.onUpdateDownloaded  다운로드 완료 콜백 (info) — 트레이 메뉴 갱신용
 * @returns {object|null} autoUpdater 인스턴스 (스킵 시 null)
 */
function initAutoUpdater({ onLog, onUpdateDownloaded } = {}) {
  const log = typeof onLog === 'function' ? onLog : () => {};

  // dev/미패키징 또는 비 Windows → 스킵
  if (!app.isPackaged || process.platform !== 'win32') {
    console.log('[updater] skip — packaged:', app.isPackaged, 'platform:', process.platform);

    return null;
  }

  let autoUpdater;
  try {
    ({ autoUpdater } = require('electron-updater'));
  } catch (err) {
    // 의존성 누락 등 — 업데이트 실패가 프린트 기능을 막으면 안 됨
    log(`⚠️ auto-update no disponible: ${err.message}`);

    return null;
  }

  autoUpdater.autoDownload = true;

  // 앱 종료('quit' 이벤트) 시 자동 설치 — 트레이 'Salir'(app.exit)에서도 quit 이벤트는 발생
  autoUpdater.autoInstallOnAppQuit = true;
  autoUpdater.allowDowngrade = false;

  autoUpdater.on('update-available', (info) => {
    log(`⬇️ Actualización disponible: v${info.version} — descargando en segundo plano...`);
  });

  autoUpdater.on('update-downloaded', (info) => {
    log(`🔄 Actualización v${info.version} lista — se instalará al reiniciar el agente`);
    if (typeof onUpdateDownloaded === 'function') {
      onUpdateDownloaded(info);
    }
  });

  autoUpdater.on('error', (err) => {
    // 네트워크 불안정 등은 흔함 — 경고 로그만 남기고 다음 주기에 재시도
    log(`⚠️ auto-update: ${err.message}`);
  });

  const check = () => {
    autoUpdater.checkForUpdates().catch((err) => {
      log(`⚠️ auto-update check: ${err.message}`);
    });
  };

  setTimeout(check, FIRST_CHECK_DELAY_MS);
  setInterval(check, CHECK_INTERVAL_MS);

  console.log('[updater] initialized — feed:', 'print-agent-latest (generic)');

  return autoUpdater;
}

module.exports = { initAutoUpdater };
