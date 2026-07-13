# ─────────────────────────────────────────────────────────────────────────
# Windows RAW ZPL 테스트 — zebra-agent 재빌드 없이 프린터 자체를 검증
#
# 목적: 프린터(GC420t)가 winspool RAW 로 보낸 ZPL 을 "라벨"로 정상 인쇄하는지 확인.
#       라벨 1장이 깨끗이 나오면 → 새 zebra-agent 빌드가 문제를 해결함이 확정.
#       예전처럼 여러 페이지 문서가 나오면 → 프린터 이름/드라이버 쪽을 더 확인.
#
# 사용법 (그 Windows PC 의 PowerShell 에서):
#   powershell -ExecutionPolicy Bypass -File .\test-raw-zpl.ps1
#   (프린터 이름이 다르면)  ... -File .\test-raw-zpl.ps1 -PrinterName "ZDesigner GC420t"
# ─────────────────────────────────────────────────────────────────────────
param(
  [string]$PrinterName = "ZDesigner GC420t"
)

$ErrorActionPreference = 'Stop'

# 테스트 라벨 ZPL (50x25mm 대략) — 텍스트 + CODE128 바코드
$zpl = @"
^XA
^PW400
^LL200
^FO30,30^A0N,40,40^FDACE RAW TEST^FS
^FO30,90^A0N,26,26^FDwinspool RAW OK^FS
^FO30,130^BY2^BCN,60,Y,N,N^FD123456789^FS
^XZ
"@

$cs = @'
using System;
using System.Runtime.InteropServices;
public class ZebraRawPrinter {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct DOCINFO { [MarshalAs(UnmanagedType.LPWStr)] public string pDocName; [MarshalAs(UnmanagedType.LPWStr)] public string pOutputFile; [MarshalAs(UnmanagedType.LPWStr)] public string pDataType; }
  [DllImport("winspool.Drv", EntryPoint="OpenPrinterW", SetLastError=true, CharSet=CharSet.Unicode, ExactSpelling=true)] static extern bool OpenPrinter(string src, out IntPtr hPrinter, IntPtr pd);
  [DllImport("winspool.Drv", EntryPoint="ClosePrinter", SetLastError=true)] static extern bool ClosePrinter(IntPtr hPrinter);
  [DllImport("winspool.Drv", EntryPoint="StartDocPrinterW", SetLastError=true, CharSet=CharSet.Unicode, ExactSpelling=true)] static extern bool StartDocPrinter(IntPtr hPrinter, int level, [In, MarshalAs(UnmanagedType.LPStruct)] DOCINFO di);
  [DllImport("winspool.Drv", EntryPoint="EndDocPrinter", SetLastError=true)] static extern bool EndDocPrinter(IntPtr hPrinter);
  [DllImport("winspool.Drv", EntryPoint="StartPagePrinter", SetLastError=true)] static extern bool StartPagePrinter(IntPtr hPrinter);
  [DllImport("winspool.Drv", EntryPoint="EndPagePrinter", SetLastError=true)] static extern bool EndPagePrinter(IntPtr hPrinter);
  [DllImport("winspool.Drv", EntryPoint="WritePrinter", SetLastError=true)] static extern bool WritePrinter(IntPtr hPrinter, IntPtr pBytes, int dwCount, out int dwWritten);
  public static void Send(string printerName, byte[] bytes) {
    IntPtr hPrinter; int written = 0;
    DOCINFO di = new DOCINFO(); di.pDocName = "ACE RAW Test"; di.pDataType = "RAW";
    if (!OpenPrinter(printerName, out hPrinter, IntPtr.Zero)) throw new Exception("OpenPrinter fallo (nombre de impresora incorrecto?): " + Marshal.GetLastWin32Error());
    IntPtr p = Marshal.AllocCoTaskMem(bytes.Length); Marshal.Copy(bytes, 0, p, bytes.Length);
    try {
      if (!StartDocPrinter(hPrinter, 1, di)) throw new Exception("StartDocPrinter fallo: " + Marshal.GetLastWin32Error());
      if (!StartPagePrinter(hPrinter)) throw new Exception("StartPagePrinter fallo: " + Marshal.GetLastWin32Error());
      if (!WritePrinter(hPrinter, p, bytes.Length, out written)) throw new Exception("WritePrinter fallo: " + Marshal.GetLastWin32Error());
      EndPagePrinter(hPrinter); EndDocPrinter(hPrinter);
    } finally { Marshal.FreeCoTaskMem(p); ClosePrinter(hPrinter); }
  }
}
'@

Write-Host "사용 가능한 프린터 목록:" -ForegroundColor Cyan
Get-Printer | Select-Object -ExpandProperty Name | ForEach-Object { Write-Host "  - $_" }
Write-Host ""
Write-Host "대상 프린터: $PrinterName" -ForegroundColor Yellow

try {
  Add-Type -TypeDefinition $cs
  $bytes = [System.Text.Encoding]::ASCII.GetBytes($zpl)
  [ZebraRawPrinter]::Send($PrinterName, $bytes)
  Write-Host "RAW 전송 성공 → 라벨 1장이 인쇄되어야 정상입니다." -ForegroundColor Green
  Write-Host "여러 페이지 문서가 나오면 프린터 이름/드라이버를 다시 확인하세요." -ForegroundColor DarkYellow
} catch {
  Write-Host "실패: $($_.Exception.Message)" -ForegroundColor Red
  exit 1
}
