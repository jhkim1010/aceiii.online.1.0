// print-agent/renderer/setup-wizard.js
let selectedPrinter = null;

// ─── 고정 서버 URL (사용자 입력 불필요 — main.js SERVER_URL 단일 출처) ───────
// 마법사 로드 시 1회 조회하여 readonly 표시 칸에 반영한다.
let serverUrl = '';
(async () => {
  try {
    serverUrl = await window.electronAPI.getServerUrl();
    const disp = document.getElementById('serverDisplay');
    if (disp) disp.value = serverUrl;
  } catch (err) {
    console.error('[setup-wizard] getServerUrl 실패:', err);
  }
})();

// ─── Step 1: 연결 테스트 ───────────────────────────────────────────────────
document.getElementById('btnTestConn').addEventListener('click', async () => {
  const key = document.getElementById('apiKey').value.trim();
  const resultEl = document.getElementById('testResult');

  if (!key) {
    resultEl.textContent = '⚠️  Ingrese el API Key';
    resultEl.className = 'result-msg error';

    return;
  }

  // 서버 URL 미로딩(레이스) 대비 — 클릭 시점에 비어있으면 재조회.
  if (!serverUrl) {
    try {
      serverUrl = await window.electronAPI.getServerUrl();
    } catch (err) {
      resultEl.textContent = `❌ ${err.message}`;
      resultEl.className = 'result-msg error';

      return;
    }
  }

  resultEl.textContent = '⏳ Probando conexión...';
  resultEl.className = 'result-msg';

  try {
    const result = await window.electronAPI.testConnection(serverUrl, key);

    if (result.success) {
      resultEl.textContent = '✅ Conexión exitosa';
      resultEl.className = 'result-msg success';
      document.getElementById('btnStep1Next').disabled = false;
      await window.electronAPI.setConfig('apiUrl', serverUrl);
      await window.electronAPI.setConfig('apiKey', key);
    } else {
      resultEl.textContent = `❌ ${result.error}`;
      resultEl.className = 'result-msg error';
      document.getElementById('btnStep1Next').disabled = true;
    }
  } catch (err) {
    resultEl.textContent = `❌ ${err.message}`;
    resultEl.className = 'result-msg error';
  }
});

document.getElementById('btnStep1Next').addEventListener('click', () => goToStep(2));

// ─── Step 2: 프린터 탐색 ──────────────────────────────────────────────────
// 자식 요소 안전 생성 헬퍼 (XSS 방지)
function clearChildren(el) {
  while (el.firstChild) el.removeChild(el.firstChild);
}

document.getElementById('btnDiscover').addEventListener('click', async () => {
  const listEl = document.getElementById('printerList');
  clearChildren(listEl);
  const loading = document.createElement('p');
  loading.textContent = '🔍 Buscando...';
  listEl.appendChild(loading);

  try {
    const printers = await window.electronAPI.discoverPrinters();
    clearChildren(listEl);

    if (!printers || !printers.length) {
      const empty = document.createElement('p');
      empty.className = 'hint';
      empty.textContent = 'No se encontraron impresoras automáticamente. Configure manualmente en Ajustes.';
      listEl.appendChild(empty);

      return;
    }

    printers.forEach((p, i) => {
      const row = document.createElement('div');
      row.className = 'printer-row';

      const input = document.createElement('input');
      input.type = 'radio';
      input.name = 'printer';
      input.id = `p${i}`;
      input.value = String(i);

      const label = document.createElement('label');
      label.htmlFor = `p${i}`;

      const badge = document.createElement('span');
      badge.className = 'badge';
      badge.textContent = String(p.type || '').toUpperCase();

      label.appendChild(badge);
      label.appendChild(document.createTextNode(' ' + (p.label || '')));

      row.appendChild(input);
      row.appendChild(label);

      input.addEventListener('change', () => {
        selectedPrinter = p;
        document.getElementById('btnPrintTest').disabled = false;
        document.getElementById('btnStep2Next').disabled = false;
      });
      listEl.appendChild(row);
    });
  } catch (err) {
    clearChildren(listEl);
    const errEl = document.createElement('p');
    errEl.className = 'result-msg error';
    errEl.textContent = `❌ ${err.message}`;
    listEl.appendChild(errEl);
  }
});

document.getElementById('btnPrintTest').addEventListener('click', async () => {
  if (!selectedPrinter) return;
  await window.electronAPI.setConfig('printer', selectedPrinter.config);
  const result = await window.electronAPI.testPrint();
  const el = document.getElementById('printTestResult');
  el.textContent = result.success ? '✅ Test impreso correctamente' : `❌ ${result.error}`;
  el.className = `result-msg ${result.success ? 'success' : 'error'}`;
});

document.getElementById('btnStep2Back').addEventListener('click', () => goToStep(1));
document.getElementById('btnStep2Next').addEventListener('click', async () => {
  if (selectedPrinter) {
    await window.electronAPI.setConfig('printer', selectedPrinter.config);
  }
  goToStep(3);
});

// ─── Step 3: 완료 ─────────────────────────────────────────────────────────
document.getElementById('btnFinish').addEventListener('click', async () => {
  await window.electronAPI.completeSetup();
});

// ─── 단계 전환 ───────────────────────────────────────────────────────────────
function goToStep(n) {
  document.querySelectorAll('.wizard-step').forEach((el, i) => {
    el.classList.toggle('hidden', i + 1 !== n);
  });
  document.querySelectorAll('.step').forEach((el, i) => {
    el.classList.toggle('active', i + 1 <= n);
  });
}
