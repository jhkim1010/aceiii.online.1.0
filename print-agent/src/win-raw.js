/**
 * win-raw.js
 *
 * [2026-10-12] Bytes ESC/POS crudos a una impresora de Windows (spooler, datatype RAW).
 *
 * Por qué: el modo «Impresora del sistema» pasa la imagen por el driver gráfico (GDI).
 * En Shaple (EPSON TM-T20IV detrás del Virtual Port Driver, puerto ESDPRT001/COM3) la
 * página de prueba de Windows salía, pero nuestro ticket salía como papel en blanco
 * continuo. Con RAW el driver no dibuja nada: los bytes llegan tal cual a la impresora,
 * igual que por red (escpos-network), que es el camino que ya funciona en otras tiendas.
 *
 * Mismo mecanismo que zebra-agent/src/zebra-printer.js (WritePrinter, RAW) — probado.
 * Nombre de impresora y ruta van por variables de entorno (sin inyección en el script).
 */
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFile } = require('child_process');

const PS_SCRIPT = [
  "$ErrorActionPreference = 'Stop'",
  'try {',
  "  $cs = @'",
  'using System;',
  'using System.Runtime.InteropServices;',
  'public class VentagoRawPrinter {',
  '  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]',
  '  public struct DOCINFO { [MarshalAs(UnmanagedType.LPWStr)] public string pDocName; [MarshalAs(UnmanagedType.LPWStr)] public string pOutputFile; [MarshalAs(UnmanagedType.LPWStr)] public string pDataType; }',
  '  [DllImport("winspool.Drv", EntryPoint="OpenPrinterW", SetLastError=true, CharSet=CharSet.Unicode, ExactSpelling=true)] static extern bool OpenPrinter(string src, out IntPtr hPrinter, IntPtr pd);',
  '  [DllImport("winspool.Drv", EntryPoint="ClosePrinter", SetLastError=true)] static extern bool ClosePrinter(IntPtr hPrinter);',
  '  [DllImport("winspool.Drv", EntryPoint="StartDocPrinterW", SetLastError=true, CharSet=CharSet.Unicode, ExactSpelling=true)] static extern bool StartDocPrinter(IntPtr hPrinter, int level, [In] ref DOCINFO di);',
  '  [DllImport("winspool.Drv", EntryPoint="EndDocPrinter", SetLastError=true)] static extern bool EndDocPrinter(IntPtr hPrinter);',
  '  [DllImport("winspool.Drv", EntryPoint="StartPagePrinter", SetLastError=true)] static extern bool StartPagePrinter(IntPtr hPrinter);',
  '  [DllImport("winspool.Drv", EntryPoint="EndPagePrinter", SetLastError=true)] static extern bool EndPagePrinter(IntPtr hPrinter);',
  '  [DllImport("winspool.Drv", EntryPoint="WritePrinter", SetLastError=true)] static extern bool WritePrinter(IntPtr hPrinter, IntPtr pBytes, int dwCount, out int dwWritten);',
  '  public static int Send(string printerName, byte[] bytes) {',
  '    IntPtr hPrinter; int written = 0;',
  '    DOCINFO di = new DOCINFO(); di.pDocName = "Ventago ticket"; di.pDataType = "RAW";',
  '    if (!OpenPrinter(printerName, out hPrinter, IntPtr.Zero)) throw new Exception("OpenPrinter fallo (impresora no encontrada?): " + Marshal.GetLastWin32Error());',
  '    IntPtr p = Marshal.AllocCoTaskMem(bytes.Length); Marshal.Copy(bytes, 0, p, bytes.Length);',
  '    try {',
  '      if (!StartDocPrinter(hPrinter, 1, ref di)) throw new Exception("StartDocPrinter fallo: " + Marshal.GetLastWin32Error());',
  '      if (!StartPagePrinter(hPrinter)) throw new Exception("StartPagePrinter fallo: " + Marshal.GetLastWin32Error());',
  '      if (!WritePrinter(hPrinter, p, bytes.Length, out written)) throw new Exception("WritePrinter fallo: " + Marshal.GetLastWin32Error());',
  '      EndPagePrinter(hPrinter); EndDocPrinter(hPrinter);',
  '    } finally { Marshal.FreeCoTaskMem(p); ClosePrinter(hPrinter); }',
  '    return written;',
  '  }',
  '}',
  "'@",
  '  Add-Type -TypeDefinition $cs',
  '  $bytes = [System.IO.File]::ReadAllBytes($env:VENTAGO_RAW_FILE)',
  '  $n = [VentagoRawPrinter]::Send($env:VENTAGO_PRINTER_NAME, $bytes)',
  '  Write-Output ("RAW_OK " + $n + "/" + $bytes.Length)',
  '} catch { Write-Error $_.Exception.Message; exit 1 }',
].join('\r\n');

/**
 * @param {Buffer} bytes        ESC/POS listo
 * @param {string} printerName  nombre de la impresora en Windows
 * @param {function} log
 * @returns {Promise<void>}
 */
function sendRawToWindowsPrinter(bytes, printerName, log = () => {}) {
  if (!printerName) {
    return Promise.reject(new Error('deviceName 미설정 — 출력할 프린터 이름을 선택하세요'));
  }
  if (os.platform() !== 'win32') {
    return Promise.reject(new Error('RAW ESC/POS sólo en Windows'));
  }

  const stamp = `${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
  const binFile = path.join(os.tmpdir(), `ventago-raw-${stamp}.bin`);
  const psFile = path.join(os.tmpdir(), `ventago-raw-${stamp}.ps1`);

  fs.writeFileSync(binFile, bytes);
  // BOM — PowerShell lee el .ps1 como UTF-8
  fs.writeFileSync(psFile, '﻿' + PS_SCRIPT, 'utf8');

  const cleanup = () => {
    try { fs.unlinkSync(binFile); } catch (_e) { /* ya no está */ }
    try { fs.unlinkSync(psFile); } catch (_e) { /* ya no está */ }
  };

  log(`🧱 [win-raw] RAW ESC/POS → "${printerName}" (${bytes.length} bytes)`);

  return new Promise((resolve, reject) => {
    execFile(
      'powershell',
      ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', psFile],
      {
        timeout: 20000,
        windowsHide: true,
        env: Object.assign({}, process.env, {
          VENTAGO_RAW_FILE: binFile,
          VENTAGO_PRINTER_NAME: printerName,
        }),
      },
      (err, stdout, stderr) => {
        cleanup();
        if (err) {
          const msg = (stderr && String(stderr).trim()) || err.message;
          log(`❌ [win-raw] ${msg}`);

          return reject(new Error(`RAW ESC/POS falló: ${msg}`));
        }
        log(`✅ [win-raw] ${String(stdout || '').trim()}`);
        resolve();
      },
    );
  });
}

module.exports = { sendRawToWindowsPrinter, PS_SCRIPT };
