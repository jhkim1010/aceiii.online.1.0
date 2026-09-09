#Requires -Version 5.1
<#
  Ventago Edge Agent — instalacion asistida (Windows)

  Que hace:
    1. Verifica requisitos (Node >= 18, PostgreSQL) y dice que falta si falta.
    2. Crea la base local `ventago_edge` si no existe.
    3. Instala dependencias (npm install).
    4. Escribe config.json pidiendo la agentKey.
    5. Registra una tarea programada que lo levanta al iniciar Windows
       y lo vuelve a levantar si se cae.
    6. Arranca el servicio y verifica /api/health.

  Que NO hace (a proposito):
    - NO instala Node ni PostgreSQL. Descargarlos e instalarlos es una decision
      del duenio del equipo (version, ruta, contrasena del superusuario).
      El script dice exactamente que falta y de donde bajarlo.

  Uso (PowerShell como Administrador, dentro de la carpeta edge-agent):
      Set-ExecutionPolicy -Scope Process Bypass -Force
      .\install.ps1

  Reinstalar/actualizar: volver a correrlo. Es idempotente — no pisa una
  config.json existente salvo que se pase -Reconfigurar.
#>
param(
  [switch]$Reconfigurar,
  [string]$AgentKey,
  [string]$PgUser = 'postgres',
  [string]$PgPassword,
  [int]$Puerto = 5010
)

$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
$nombreTarea = 'VentagoEdgeAgent'

function Titulo($t) { Write-Host ""; Write-Host "== $t ==" -ForegroundColor Cyan }
function Ok($t)     { Write-Host "  [OK] $t" -ForegroundColor Green }
function Aviso($t)  { Write-Host "  [!]  $t" -ForegroundColor Yellow }
function Fallo($t)  { Write-Host "  [X]  $t" -ForegroundColor Red }

# ── 1. Requisitos ──────────────────────────────────────────────────────────
Titulo "1/6  Requisitos"

$faltan = @()

$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
  $faltan += "Node.js 18 o superior  ->  https://nodejs.org/en/download"
} else {
  $v = (& node --version) -replace '^v',''
  $mayor = [int]($v.Split('.')[0])
  if ($mayor -lt 18) { $faltan += "Node.js 18+ (tiene $v)  ->  https://nodejs.org/en/download" }
  else { Ok "Node $v" }
}

$psql = Get-Command psql -ErrorAction SilentlyContinue
if (-not $psql) {
  # instalacion tipica de EDG que no quedo en el PATH
  $cand = Get-ChildItem 'C:\Program Files\PostgreSQL\*\bin\psql.exe' -ErrorAction SilentlyContinue |
          Sort-Object FullName -Descending | Select-Object -First 1
  if ($cand) {
    $env:Path = "$($cand.Directory.FullName);$env:Path"
    $psql = Get-Command psql -ErrorAction SilentlyContinue
    Ok "PostgreSQL encontrado en $($cand.Directory.FullName) (agregado al PATH de esta sesion)"
  }
}
if (-not $psql) {
  $faltan += "PostgreSQL 14+  ->  https://www.postgresql.org/download/windows/"
} elseif (-not $cand) {
  Ok "psql en PATH"
}

if ($faltan.Count -gt 0) {
  Fallo "Faltan requisitos. Instalelos y vuelva a correr este script:"
  $faltan | ForEach-Object { Write-Host "       - $_" }
  exit 1
}

# ── 2. Base local ──────────────────────────────────────────────────────────
Titulo "2/6  Base de datos local (ventago_edge)"

if (-not $PgPassword) {
  $sec = Read-Host "Contrasena del usuario '$PgUser' de PostgreSQL" -AsSecureString
  $PgPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
}
$env:PGPASSWORD = $PgPassword

$existe = & psql -U $PgUser -h 127.0.0.1 -tAc "SELECT 1 FROM pg_database WHERE datname='ventago_edge'" 2>$null
if ($LASTEXITCODE -ne 0) {
  Fallo "No se pudo conectar a PostgreSQL con el usuario '$PgUser'. Revise la contrasena y que el servicio este corriendo."
  exit 1
}
if ($existe -eq '1') {
  Ok "ventago_edge ya existe (no se toca — el espejo y la outbox se conservan)"
} else {
  & psql -U $PgUser -h 127.0.0.1 -c "CREATE DATABASE ventago_edge" | Out-Null
  Ok "ventago_edge creada"
}

# ── 3. Dependencias ────────────────────────────────────────────────────────
Titulo "3/6  Dependencias (npm install)"
Push-Location $raiz
try {
  & npm install --omit=dev 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "npm install fallo" }
  Ok "dependencias instaladas"
} finally { Pop-Location }

# ── 4. config.json ─────────────────────────────────────────────────────────
Titulo "4/6  Configuracion"
$cfgPath = Join-Path $raiz 'config.json'

if ((Test-Path $cfgPath) -and -not $Reconfigurar) {
  Ok "config.json ya existe — no se toca (use -Reconfigurar para reescribirlo)"
} else {
  if (-not $AgentKey) {
    Write-Host "  La agentKey se obtiene en Ventago: Sucursales -> Impresoras -> agregar agente tipo 'edge'."
    $AgentKey = Read-Host "  agentKey"
  }
  if (-not $AgentKey -or $AgentKey.Length -lt 10) { Fallo "agentKey invalida"; exit 1 }

  $cfg = [ordered]@{
    cloudApiUrl           = 'https://newapi.coolsistema.com/api'
    agentKey              = $AgentKey
    port                  = $Puerto
    localDb               = [ordered]@{
      host = '127.0.0.1'; port = 5432; database = 'ventago_edge'
      user = $PgUser; password = $PgPassword
    }
    pullIntervalMs        = 300000
    stockIntervalMs       = 60000
    pruneIntervalMs       = 3600000
    healthProbeIntervalMs = 15000
    pushIntervalMs        = 20000
    logLevel              = 'info'
  }
  $cfg | ConvertTo-Json -Depth 5 | Set-Content -Path $cfgPath -Encoding UTF8

  # La config lleva la contrasena de PG y la agentKey — que no la lea cualquiera.
  icacls $cfgPath /inheritance:r /grant:r "$env:USERNAME:(R,W)" "SYSTEM:(F)" "Administrators:(F)" | Out-Null
  Ok "config.json escrito (permisos restringidos)"
}

# ── 5. Arranque automatico ─────────────────────────────────────────────────
Titulo "5/6  Arranque automatico"
# ★ Sin esto el agente NO vuelve solo despues de un reinicio. El piloto de
#   coolsistema quedo apagado desde 2026-07-20 exactamente por esto.
$nodeExe = (Get-Command node).Source
$accion  = New-ScheduledTaskAction -Execute $nodeExe -Argument 'src\index.js' -WorkingDirectory $raiz
$disparo = New-ScheduledTaskTrigger -AtStartup
$config  = New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
             -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$dueno   = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest

Unregister-ScheduledTask -TaskName $nombreTarea -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName $nombreTarea -Action $accion -Trigger $disparo `
  -Settings $config -Principal $dueno -Description 'Ventago Edge Sync Agent' | Out-Null
Ok "tarea '$nombreTarea' registrada (arranca con Windows, reintenta cada 1 min si se cae)"

# ── 6. Arrancar y verificar ────────────────────────────────────────────────
Titulo "6/6  Arranque y verificacion"
Start-ScheduledTask -TaskName $nombreTarea
Start-Sleep -Seconds 6

try {
  $salud = Invoke-RestMethod -Uri "http://127.0.0.1:$Puerto/api/health" -TimeoutSec 10
  Ok "agente respondiendo en el puerto $Puerto"
  Write-Host "       cloudOnline = $($salud.cloudOnline)"
  if (-not $salud.cloudOnline) {
    Aviso "El agente arranco pero NO ve la nube. Revise internet y la agentKey."
    Aviso "Un 401 en el log significa agentKey incorrecta (no es problema de red)."
  }
} catch {
  Fallo "El agente no respondio en http://127.0.0.1:$Puerto/api/health"
  Write-Host "       Revise el log: $raiz\logs\edge-agent-$(Get-Date -Format yyyy-MM-dd).log"
  exit 1
}

Write-Host ""
Write-Host "Listo." -ForegroundColor Green
Write-Host "  Estado:   http://127.0.0.1:$Puerto/api/edge/status"
Write-Host "  Log:      $raiz\logs\"
Write-Host "  Detener:  Stop-ScheduledTask -TaskName $nombreTarea"
Write-Host "  Arrancar: Start-ScheduledTask -TaskName $nombreTarea"
