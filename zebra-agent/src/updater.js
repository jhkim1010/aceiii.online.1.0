// src/updater.js — electron-updater 기반 자동 업데이트 (Windows 전용)
// (print-agent · zebra-agent 동일 파일 — feed 이름만 다르다)
//
// 동작 원리:
//   1) 부팅 10초 후 + 이후 4시간마다 publish URL(고정 롤링 릴리즈)의 latest.yml 확인
//   2) 새 버전 발견 → 백그라운드 다운로드 (SHA512 검증 포함)
//   3) 설치 — 세 경로:
//      · 새벽 03–06시(PC 현지 시각) + 인쇄 0건 + 10분간 인쇄 없음 → 조용히 재시작·설치
//      · 창의 「Actualizar ahora」 / 트레이 메뉴 → 인쇄 중이 아니면 즉시
//      · 트레이 「Salir」 → 다운로드돼 있으면 설치하고 종료
//   ★ 종전엔 3)이 「앱 종료 시」 하나뿐이었는데 「Salir」가 app.exit() 라 quit 이벤트가
//     안 나서 **한 번도 설치되지 않았다**(update-policy.js 머리 주석 실측 참고).
//
// 스킵 조건:
//   - dev 모드 / 미패키징 (app.isPackaged === false)
//   - macOS/Linux (코드서명 없어 자동 업데이트 불가 — 매장 PC 는 Windows)
//   스킵돼도 컨트롤러는 돌려준다(화면이 「Windows 설치본에서만」 을 표시한다).
const { app } = require('electron');
const { puedeInstalarSolo, puedeInstalarAMano } = require('./update-policy');

// 4시간마다 재확인 — 매장 영업 중 하루 2~3회 체크 수준
const CHECK_INTERVAL_MS = 4 * 60 * 60 * 1000;

// 부팅 직후는 WebSocket 연결 등과 겹치지 않도록 10초 지연
const FIRST_CHECK_DELAY_MS = 10 * 1000;

// 새벽 자동 설치 조건을 보는 주기
const INSTALL_TICK_MS = 5 * 60 * 1000;

const MOTIVO_TEXTO = {
  'sin-descarga': 'Todavía no hay una actualización descargada',
};

/**
 * 자동 업데이트 초기화.
 * @param {object}   opts
 * @param {string}   opts.feed       로그 표시용 feed 이름
 * @param {object}   opts.actividad  update-policy.crearActividad() 의 결과 (인쇄 진행 추적)
 * @param {Function} opts.onLog      로그 콜백 (broadcastLog)
 * @param {Function} opts.onEstado   상태 변경 콜백 (estado) — 트레이·창 갱신용
 * @returns {object} 컨트롤러 { estado, buscar, instalarAhora, instalarAlSalir }
 */
function initAutoUpdater({ feed, actividad, onLog, onEstado } = {}) {
  const log = typeof onLog === 'function' ? onLog : () => {};
  const avisar = typeof onEstado === 'function' ? onEstado : () => {};

  const st = {
    disponible: false,
    actual: app.getVersion(),
    fase: 'inactivo', // inactivo | buscando | al-dia | descargando | listo | error
    nueva: null,
    progreso: null,
    error: null,
    ultimaBusqueda: null,
    instalacionAuto: 'Automática entre las 3 y las 6 h, sin impresiones en curso',
  };

  const cambiar = (parcial) => {
    Object.assign(st, parcial);
    avisar({ ...st });
  };

  const sinActualizador = {
    estado: () => ({ ...st }),
    buscar: async () => ({ ...st }),
    instalarAhora: () => ({ ok: false, motivo: 'Sólo disponible en la versión instalada de Windows' }),
    instalarAlSalir: () => false,
  };

  // dev/미패키징 또는 비 Windows → 스킵
  if (!app.isPackaged || process.platform !== 'win32') {
    console.log('[updater] skip — packaged:', app.isPackaged, 'platform:', process.platform);

    return sinActualizador;
  }

  let autoUpdater;
  try {
    ({ autoUpdater } = require('electron-updater'));
  } catch (err) {
    // 의존성 누락 등 — 업데이트 실패가 프린트 기능을 막으면 안 됨
    log(`⚠️ auto-update no disponible: ${err.message}`);

    return sinActualizador;
  }

  st.disponible = true;

  autoUpdater.autoDownload = true;

  // 안전망으로 남긴다 — 정상 quit 경로(설치 프로그램·OS 재시작 등)에서는 여전히 설치된다
  autoUpdater.autoInstallOnAppQuit = true;
  autoUpdater.allowDowngrade = false;

  autoUpdater.on('checking-for-update', () => {
    if (st.fase !== 'listo' && st.fase !== 'descargando') cambiar({ fase: 'buscando', error: null });
  });

  autoUpdater.on('update-not-available', () => {
    if (st.fase !== 'listo') cambiar({ fase: 'al-dia', ultimaBusqueda: Date.now() });
  });

  autoUpdater.on('update-available', (info) => {
    log(`⬇️ Actualización disponible: v${info.version} — descargando en segundo plano...`);
    cambiar({ fase: 'descargando', nueva: info.version, progreso: 0, ultimaBusqueda: Date.now() });
  });

  autoUpdater.on('download-progress', (p) => {
    const pct = Math.floor(p?.percent || 0);
    if (pct !== st.progreso) cambiar({ fase: 'descargando', progreso: pct });
  });

  autoUpdater.on('update-downloaded', (info) => {
    log(`🔄 Actualización v${info.version} lista — se instalará sola de madrugada o con «Actualizar ahora»`);
    cambiar({ fase: 'listo', nueva: info.version, progreso: 100 });
  });

  autoUpdater.on('error', (err) => {
    // 네트워크 불안정 등은 흔함 — 경고 로그만 남기고 다음 주기에 재시도
    log(`⚠️ auto-update: ${err.message}`);
    if (st.fase !== 'listo') cambiar({ fase: 'error', error: err.message, ultimaBusqueda: Date.now() });
  });

  const buscar = async () => {
    if (st.fase === 'listo' || st.fase === 'descargando') return { ...st };
    try {
      await autoUpdater.checkForUpdates();
    } catch (err) {
      log(`⚠️ auto-update check: ${err.message}`);
      cambiar({ fase: 'error', error: err.message, ultimaBusqueda: Date.now() });
    }

    return { ...st };
  };

  // 재시작은 전부 여기를 지난다 — 인쇄 중·대기 중·ACK 전이면 기다린다(update-policy.esperarQuieto).
  // isSilent=true: 설치 창 없이 / isForceRunAfter: 설치 후 다시 띄울지
  let instalando = false;
  const instalar = async (volverAAbrir) => {
    if (instalando) return true;
    instalando = true;
    log(`🔄 Instalando v${st.nueva}: espera a que terminen las impresiones...`);

    const quieto = actividad ? await actividad.esperarQuieto() : true;
    if (!quieto) {
      instalando = false;
      log('⚠️ No se reinició: siguió llegando trabajo de impresión. Se reintentará.');

      return false;
    }

    // ★ sin await entre esperarQuieto() y quitAndInstall(): ningún trabajo entra en el medio
    autoUpdater.quitAndInstall(true, volverAAbrir);

    // Si por algo el instalador no arrancó, no dejar la puerta cerrada para siempre
    setTimeout(() => {
      if (actividad) actividad.abrir();
      instalando = false;
      log('⚠️ La instalación no arrancó — el agente sigue con la versión actual');
    }, 60 * 1000);

    return true;
  };

  const instalarAhora = () => {
    const r = puedeInstalarAMano({ listo: st.fase === 'listo' });
    if (!r.ok) return { ok: false, motivo: MOTIVO_TEXTO[r.motivo] || r.motivo };
    instalar(true);

    return { ok: true };
  };

  // 트레이 「Salir」: 다운로드돼 있으면 설치하고 끝낸다(다시 띄우지 않음)
  const instalarAlSalir = () => {
    if (st.fase !== 'listo') return false;
    instalar(false).then((ok) => {
      if (!ok) app.exit(0);
    });

    return true;
  };

  const vigilar = () => {
    const r = puedeInstalarSolo({
      listo: st.fase === 'listo',
      ahora: Date.now(),
      enCurso: actividad?.estado.enCurso || 0,
      ultimaActividad: actividad?.estado.ultimaActividad || 0,
    });
    if (r.ok && !instalando) {
      log('🌙 Instalación automática de madrugada (sin impresiones en curso)');
      instalar(true);
    }
  };

  setTimeout(buscar, FIRST_CHECK_DELAY_MS);
  setInterval(buscar, CHECK_INTERVAL_MS);
  setInterval(vigilar, INSTALL_TICK_MS);

  console.log('[updater] initialized — feed:', feed);

  return { estado: () => ({ ...st }), buscar, instalarAhora, instalarAlSalir };
}

module.exports = { initAutoUpdater };
