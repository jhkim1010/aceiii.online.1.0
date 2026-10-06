/**
 * Actualización automática: cuándo se reinicia el agente para instalar.
 * Ejecutar: node test/update-policy.smoke.js   (mismo archivo en print-agent y zebra-agent)
 *
 * ★ 실측 2026-10-06: descargaba pero nunca instalaba — sólo «al salir», y «Salir» usaba
 *   app.exit() (no dispara 'quit'). En la calle: print 1.2.5/1.2.6 con 1.2.10 publicado.
 * ★ Regla dura: nunca reiniciar con una impresión en curso.
 */
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const {
  puedeInstalarSolo, puedeInstalarAMano, crearActividad, QUIETO_MS, ACK_MS,
} = require('../src/update-policy');

let pasaron = 0;
const it = async (nombre, fn) => {
  await fn();
  pasaron += 1;
  console.log(`  ✓ ${nombre}`);
};

// hora LOCAL de la PC
const aLas = (h, m = 0) => new Date(2026, 9, 7, h, m).getTime();

(async () => {
  await it('madrugada + quieto + descargada → instala sola', () => {
    assert.deepStrictEqual(
      puedeInstalarSolo({ listo: true, ahora: aLas(3, 30), enCurso: 0, ultimaActividad: aLas(1) }),
      { ok: true },
    );
  });

  await it('bordes de la ventana: 02:59 no · 03:00 sí · 05:59 sí · 06:00 no', () => {
    const r = (h, m) => puedeInstalarSolo({ listo: true, ahora: aLas(h, m), enCurso: 0, ultimaActividad: 0 }).ok;
    assert.deepStrictEqual([r(2, 59), r(3, 0), r(5, 59), r(6, 0)], [false, true, true, false]);
  });

  await it('de día no instala sola aunque esté quieta', () => {
    assert.strictEqual(
      puedeInstalarSolo({ listo: true, ahora: aLas(14), enCurso: 0, ultimaActividad: 0 }).motivo,
      'fuera-de-horario',
    );
  });

  await it('★ imprimiendo → de madrugada no arranca', () => {
    assert.strictEqual(
      puedeInstalarSolo({ listo: true, ahora: aLas(4), enCurso: 1, ultimaActividad: 0 }).motivo,
      'imprimiendo',
    );
  });

  await it('imprimió hace menos de 10 min → espera; justo 10 min → sí', () => {
    const ahora = aLas(4);
    assert.strictEqual(
      puedeInstalarSolo({ listo: true, ahora, enCurso: 0, ultimaActividad: ahora - QUIETO_MS + 1 }).motivo,
      'actividad-reciente',
    );
    assert.strictEqual(
      puedeInstalarSolo({ listo: true, ahora, enCurso: 0, ultimaActividad: ahora - QUIETO_MS }).ok,
      true,
    );
  });

  await it('sin descarga → nada (ni sola ni a mano)', () => {
    assert.strictEqual(puedeInstalarSolo({ listo: false, ahora: aLas(4), enCurso: 0, ultimaActividad: 0 }).ok, false);
    assert.strictEqual(puedeInstalarAMano({ listo: false }).ok, false);
  });

  await it('a mano: cualquier hora (la espera de impresiones la hace esperarQuieto)', () => {
    assert.deepStrictEqual(puedeInstalarAMano({ listo: true }), { ok: true });
  });

  await it('envolver cuenta el trabajo en curso y lo suelta también si falla', async () => {
    let t = 1000;
    const act = crearActividad(() => t);
    let soltar;
    const lento = act.envolver(() => new Promise((res) => { soltar = res; }));
    const p = lento();
    assert.strictEqual(act.estado.enCurso, 1);
    t = 2000;
    soltar('ok');
    assert.strictEqual(await p, 'ok');
    assert.strictEqual(act.estado.enCurso, 0);
    assert.strictEqual(act.estado.ultimaActividad, 2000);

    const falla = act.envolver(async () => { throw new Error('sin papel'); });
    await assert.rejects(falla(), /sin papel/);
    assert.strictEqual(act.estado.enCurso, 0);
  });

  // ── puerta: el reinicio espera impresión en curso, trabajos en la puerta y el ACK ──
  const reloj = () => {
    const r = { t: 100000 };
    r.fn = () => r.t;
    r.dormir = async (ms) => { r.t += ms; await new Promise((x) => setImmediate(x)); };

    return r;
  };

  await it('★ quieto hace rato → true en el acto, con la puerta CERRADA', async () => {
    const r = reloj();
    const act = crearActividad(r.fn);
    assert.strictEqual(await act.esperarQuieto({ dormirFn: r.dormir }), true);
    assert.strictEqual(act.estado.cerrado, true);
  });

  await it('★ espera la impresión en curso y después el ACK (12 s)', async () => {
    const r = reloj();
    const act = crearActividad(r.fn);
    let soltar;
    const trabajo = act.envolver(() => new Promise((res) => { soltar = res; }))();
    const espera = act.esperarQuieto({ dormirFn: r.dormir, pasoMs: 1000 });
    let listo = false;
    espera.then(() => { listo = true; });
    for (let i = 0; i < 5; i++) await r.dormir(0);
    assert.strictEqual(listo, false, 'reinició con una impresión en curso');
    const finImpresion = r.t;
    soltar();
    await trabajo;
    assert.strictEqual(await espera, true);
    assert.ok(r.t - finImpresion >= ACK_MS, `reinició ${r.t - finImpresion} ms después: antes del ACK`);
  });

  await it('★ trabajo que llega con la puerta cerrada: imprime primero (no se pierde)', async () => {
    const r = reloj();
    r.t = 0;
    const act = crearActividad(r.fn);
    const impresos = [];
    const imprimir = act.envolver(async (x) => { impresos.push(x); });
    act.estado.ultimaActividad = 0;
    r.t = 5000; // dentro del ACK: todavía no está quieto
    const espera = act.esperarQuieto({ dormirFn: r.dormir, pasoMs: 500 });
    await new Promise((x) => setImmediate(x));
    assert.strictEqual(act.estado.cerrado, true);
    const p = imprimir('ticket-1'); // llega con la puerta cerrada
    assert.strictEqual(await espera, true);
    // ★ al volver true se reinicia: lo que no imprimió hasta acá se perdió
    await new Promise((x) => setImmediate(x));
    assert.deepStrictEqual(impresos, ['ticket-1'], 'el trabajo en la puerta no se imprimió antes del reinicio');
    await p;
  });

  await it('plazo vencido → false y la puerta queda ABIERTA (el agente sigue imprimiendo)', async () => {
    const r = reloj();
    const act = crearActividad(r.fn);
    act.envolver(() => new Promise(() => {}))(); // nunca termina
    assert.strictEqual(await act.esperarQuieto({ dormirFn: r.dormir, plazoMs: 3000, pasoMs: 1000 }), false);
    assert.strictEqual(act.estado.cerrado, false);
  });

  // ── cableado ────────────────────────────────────────────────────────────────
  const raiz = path.join(__dirname, '..');
  const sinComentarios = (s) =>
    s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/[^\n]*/g, '$1');
  const MAIN = sinComentarios(fs.readFileSync(path.join(raiz, 'main.js'), 'utf8'));
  const esZebra = fs.existsSync(path.join(raiz, 'src', 'zpl-formatter.js'));

  await it('★ «Salir» pasa por salir() (instala si hay descarga), no por app.exit directo', () => {
    assert.ok(/label:\s*'Salir',\s*click:\s*salir\b/.test(MAIN), 'el menú Salir no llama a salir()');
    assert.ok(/function salir\(\)\s*\{\s*if \(updaterRef && updaterRef\.instalarAlSalir\(\)\) return;/.test(MAIN));
    assert.ok(/actividadImpresion\.esperarQuieto\(\{ plazoMs: 30 \* 1000 \}\)\.finally\(\(\) => app\.exit\(0\)\)/.test(MAIN),
      'Salir sin actualización no espera la impresión en curso');
  });

  await it('★ toda llamada a la impresora pasa por el contador', () => {
    const crudas = esZebra ? ['sendZplSinContar'] : ['printTicketSinContar', 'printImageSinContar', 'renderHtmlToPngSinContar'];
    for (const c of crudas) {
      // se usa sólo dos veces: al importarla y al envolverla
      const usos = MAIN.match(new RegExp(`\\b${c}\\b`, 'g')) || [];
      assert.strictEqual(usos.length, 2, `${c} se usa fuera del envoltorio (${usos.length})`);
      assert.ok(new RegExp(`actividadImpresion\\.envolver\\(${c}\\)`).test(MAIN), `${c} no está envuelta`);
    }
    assert.ok(/actividad:\s*actividadImpresion/.test(MAIN), 'el updater no recibe el contador');
  });

  await it('la ventana tiene la franja y el puente IPC', () => {
    const html = fs.readFileSync(path.join(raiz, 'renderer', 'index.html'), 'utf8');
    const pre = fs.readFileSync(path.join(raiz, 'preload.js'), 'utf8');
    assert.ok(html.includes('<script src="update-banner.js"></script>'));
    for (const canal of ['update:estado', 'update:buscar', 'update:instalar']) {
      assert.ok(pre.includes(`'${canal}'`), `preload sin ${canal}`);
      assert.ok(MAIN.includes(`ipcMain.handle('${canal}'`), `main sin ${canal}`);
    }
  });

  console.log(`update-policy: ${pasaron} pasaron`);
})().catch((e) => {
  console.error('✗', e.message);
  process.exit(1);
});
