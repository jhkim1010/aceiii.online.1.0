// src/updater.js — electron-updater 기반 자동 업데이트 (Windows 전용)
// (print-agent · zebra-agent 동일 파일 — feed 이름만 다르다)
//
// 동작 원리:
//   1) 부팅 10초 후 + 이후 4시간마다 publish URL(고정 롤링 릴리즈)의 latest.yml 확인
//   2) 새 버전 발견 → 백그라운드 다운로드 (SHA512 검증 포함)
//   3) 설치는 **사용자가 OK 할 때만** — 다운로드가 끝나면 묻는 창을 띄운다
//      (「Actualizar ahora」 / 「Más tarde」). 창의 띠·트레이 메뉴에서도 언제든 누를 수 있다.
//   ★ [2026-10-06 사용자] 「혼자 막 업데이트 되는 것은 원치 않아. 물어보고 사용자가 ok 할
//     때만」 → 새벽 자동 설치·종료 시 설치(autoInstallOnAppQuit)·「Salir」 설치를 모두 뺐다.
//
// 스킵 조건:
//   - dev 모드 / 미패키징 (app.isPackaged === false)
//   - macOS/Linux (코드서명 없어 자동 업데이트 불가 — 매장 PC 는 Windows)
//   스킵돼도 컨트롤러는 돌려준다(화면이 「Windows 설치본에서만」 을 표시한다).
const { app, dialog } = require('electron');
const { puedeInstalarAMano } = require('./update-policy');

// 4시간마다 재확인 — 매장 영업 중 하루 2~3회 체크 수준
const CHECK_INTERVAL_MS = 4 * 60 * 60 * 1000;

// 부팅 직후는 WebSocket 연결 등과 겹치지 않도록 10초 지연
const FIRST_CHECK_DELAY_MS = 10 * 1000;

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
 * @returns {object} 컨트롤러 { estado, buscar, instalarAhora }
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
  };

  const cambiar = (parcial) => {
    Object.assign(st, parcial);
    avisar({ ...st });
  };

  const sinActualizador = {
    estado: () => ({ ...st }),
    buscar: async () => ({ ...st }),
    instalarAhora: () => ({ ok: false, motivo: 'Sólo disponible en la versión instalada de Windows' }),
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

  // ★ 종료할 때 몰래 설치하지 않는다 — 설치는 사용자가 OK 할 때만
  autoUpdater.autoInstallOnAppQuit = false;
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
    log(`🔄 Actualización v${info.version} lista — se instala sólo si la aceptás («Actualizar ahora»)`);
    cambiar({ fase: 'listo', nueva: info.version, progreso: 100 });
    preguntar(info.version);
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
      log('⚠️ No se reinició: siguió llegando trabajo de impresión. Probá de nuevo con «Actualizar ahora».');

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

  // ★ espera el resultado: si no se pudo reiniciar (siguió imprimiendo), el botón vuelve a habilitarse
  const instalarAhora = async () => {
    const r = puedeInstalarAMano({ listo: st.fase === 'listo' });
    if (!r.ok) return { ok: false, motivo: MOTIVO_TEXTO[r.motivo] || r.motivo };
    if (!(await instalar(true))) {
      return { ok: false, motivo: 'Siguió llegando trabajo de impresión — probá de nuevo en un rato' };
    }

    return { ok: true };
  };

  // 다운로드가 끝나면 한 번 묻는다(버전마다 1회). 「Más tarde」면 띠·트레이에 남는다.
  let preguntada = null;
  const preguntar = (version) => {
    if (preguntada === version) {
      return;
    }
    preguntada = version;
    dialog
      .showMessageBox({
        type: 'question',
        title: 'Actualización disponible',
        message: `Hay una versión nueva del agente: v${version} (tenés v${st.actual}).`,
        detail: 'El agente se reinicia unos segundos. Si hay una impresión en curso, espera a que termine.',
        buttons: ['Actualizar ahora', 'Más tarde'],
        defaultId: 0,
        cancelId: 1,
        noLink: true,
      })
      .then(({ response }) => {
        if (response === 0) {
          instalarAhora();
        } else {
          log('⏸ Actualización pospuesta — podés instalarla con «Actualizar ahora»');
        }
      })
      .catch((err) => log(`⚠️ No se pudo mostrar la pregunta de actualización: ${err.message}`));
  };

  setTimeout(buscar, FIRST_CHECK_DELAY_MS);
  setInterval(buscar, CHECK_INTERVAL_MS);

  console.log('[updater] initialized — feed:', feed);

  return { estado: () => ({ ...st }), buscar, instalarAhora };
}

module.exports = { initAutoUpdater };
