# Tuned VIctory-Belobug launcher for hybrid NVIDIA laptop (i7-12650H 6P+4E, RTX 4050 6 GB, 16 GB RAM, NVMe SSD).
# Saves logs into .\logs\run-*.log and .\logs\latest.log using a single buffered StreamWriter (no per-line file reopen stalls).
param(
    [ValidateSet('series-s', 'series-x')][string]$Console = 'series-s',
    [ValidateSet('1280x720', '1600x900', '1920x1080')][string]$DisplayMode = '1920x1080',
    [ValidateSet(0, 30, 40, 60)][int]$TargetFps = 60,
    [ValidateRange(64, 1536)][int]$CardBuffersMB = 512,
    [ValidateRange(0, 850)][int]$PipelineWaitMs = 16,
    [ValidateSet('warn', 'info', 'debug')][string]$LogLevel = 'warn',
    [string]$LogFile = '',
    [switch]$Hud,
    [switch]$Kbm,
    [switch]$Safe
)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$runner = Join-Path $PSScriptRoot 'target\release\victory.exe'
if (-not (Test-Path $runner)) {
    Write-Error "Build target\release\victory.exe first."
    exit 2
}

$cfgLines = & $runner config
$gameDir = ($cfgLines | Where-Object { $_ -match '^game_dir\s*:\s*(.+)$' } | ForEach-Object { $Matches[1].Trim() }) | Select-Object -First 1
if (-not $gameDir) {
    Write-Error "Could not read game_dir from victory.toml."
    exit 2
}
$exe = Get-ChildItem -Path $gameDir -Filter '*.exe' -File | Sort-Object Length -Descending | Select-Object -First 1
if (-not $exe) {
    Write-Error "No title executable found in $gameDir"
    exit 2
}

# Clean leftover VICTORY_* overrides from the current shell (keep path vars)
$keepVars = 'VICTORY_CONFIG', 'VICTORY_GAME_DIR', 'VICTORY_CACHE_DIR', 'VICTORY_DATA_DIR', 'VICTORY_FIDELITYFX_DIR'
Get-ChildItem Env:VICTORY_* -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin $keepVars } | ForEach-Object {
    Remove-Item "Env:$($_.Name)" -ErrorAction SilentlyContinue
}

$defaults = @{
    VICTORY_D3D12_ADAPTER            = 'NVIDIA'
    VICTORY_DISPLAY_MODE             = $DisplayMode
    VICTORY_LEVELS_ON_DEMAND         = '0'
    VICTORY_PORT_CONSTANTS           = '0'
    VICTORY_PORT_DESCRIPTORS         = if ($Safe) { '0' } else { '1' }
    VICTORY_PORT_CBV                 = if ($Safe) { '0' } else { '1' }
    VICTORY_PORT_GUARD               = if ($Safe) { '0' } else { '1' }
    VICTORY_PORT_JOURNAL             = if ($Safe) { '0' } else { '1' }
    VICTORY_RESIDENCY                = '1'
    VICTORY_CARD_GUARD               = '1'
    VICTORY_TEXTURE_ROOM_PERCENT     = '90'
    VICTORY_CARD_ROOM_FOR_TARGETS_MB = '1100'
    VICTORY_CARD_ROOM_FOR_BUFFERS    = '0'
    VICTORY_INDIRECT_REST            = '0'
    VICTORY_XMA_REFILL               = '1'
    VICTORY_AMBIENT                  = '0.85'
    VICTORY_AMBIENT_MOST             = '1.15'
    VICTORY_AMBIENT_AIR              = '1.4'
    VICTORY_AMBIENT_SETTLE           = '250,3'
    VICTORY_PIPELINE_WAIT_MS         = "$PipelineWaitMs"
    VICTORY_SCREEN_WAIT_MS           = '10000'
    VICTORY_D3D12_BACKGROUND         = '0'
    VICTORY_LANE_CORE                = '1'
    VICTORY_TEXTURE_NO_WAIT          = '1'
    VICTORY_RELAY                    = '2'
    VICTORY_WIDE_BACK                = '1'
    VICTORY_CARD_REHASH_RUNS         = '1'
    VICTORY_JOIN_COPIES              = '1'
    VICTORY_INDIRECT_WINDOW          = '1'
    VICTORY_RELAY_COPY               = '1'
    VICTORY_CARD_STEPS               = '2'
    VICTORY_INDIRECT_BATCH           = '2'
    VICTORY_MAP_THREADS              = '1'
    VICTORY_TITLE_PRIORITIES         = '0'
    VICTORY_CARD_AWAKE               = '1'
    VICTORY_SHOW_AFTER               = '1'
    VICTORY_THIN                     = if ($Safe) { '0' } else { '1' }
    VICTORY_THIN_THREADS             = '6'
    VICTORY_JOIN_PARTS               = '6'
    VICTORY_UPLOAD_AHEAD             = if ($Safe) { '0' } else { '1' }
    VICTORY_SUBMIT_DEPTH             = '16'
    VICTORY_LATE_WAIT_LISTS          = '192'
    VICTORY_WINDOW_KB                = '256'
    VICTORY_WINDOW_TAILS             = '1'
    VICTORY_CARD_BUFFERS_MIN_KB      = '64'
    VICTORY_CARD_BUFFERS_MB          = "$CardBuffersMB"
    VICTORY_WINDOW_BUDGET_MB         = '512'
    VICTORY_DSTORAGE_IO              = 'direct'
    VICTORY_DSTORAGE_WORKERS         = '8'
    VICTORY_LOG                      = $LogLevel
    VICTORY_CARD_ACCOUNTING          = if ($LogLevel -eq 'warn') { '0' } else { '1' }
    VICTORY_D3D12_DRED               = 'faults'
}

if ($TargetFps -eq 60) {
    $defaults['VICTORY_FRAME_INTERVAL_MS'] = '16.667'
} elseif ($TargetFps -eq 40) {
    $defaults['VICTORY_FRAME_INTERVAL_MS'] = '25.0'
} elseif ($TargetFps -eq 0) {
    $defaults['VICTORY_FRAME_INTERVAL_MS'] = '0'
}

if ($Console -eq 'series-x') {
    $defaults['VICTORY_OUTPUT'] = $DisplayMode
}
if ($Hud) {
    $defaults['VICTORY_PANEL'] = '1'
}
if ($Kbm) {
    $defaults['VICTORY_KBM_GTA'] = '1'
}

foreach ($k in $defaults.Keys) {
    Set-Item "Env:$k" $defaults[$k]
}

$logsDir = Join-Path $PSScriptRoot 'logs'
New-Item -ItemType Directory -Force $logsDir | Out-Null
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$runLog = if ($LogFile -ne '') { $LogFile } else { Join-Path $logsDir "run-$timestamp.log" }
$latestLog = Join-Path $logsDir 'latest.log'
$runLogDir = Split-Path -Parent $runLog
if ($runLogDir -and -not (Test-Path $runLogDir)) {
    New-Item -ItemType Directory -Force $runLogDir | Out-Null
}

$powerState = 'Unknown'
try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    $powerState = [string][System.Windows.Forms.SystemInformation]::PowerStatus.PowerLineStatus
    if ($powerState -eq 'Offline') {
        Write-Warning "LA LAPTOP ESTA EN BATERIA! Conecta el cargador AC: en bateria la RTX 4050 y el CPU bajan su potencia 3x-5x."
    }
} catch {}

$header = @(
    "================================================================================"
    "VIctory-Belobug NVIDIA Run Log - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')"
    "Console: $Console | DisplayMode: $DisplayMode | TargetFps: $TargetFps | CardBuffersMB: $CardBuffersMB | LogLevel: $LogLevel | Safe: $Safe | Power: $powerState"
    "Executable: $($exe.FullName)"
    "Runner: $runner"
    "--- VICTORY_* Environment ---"
)
foreach ($k in ($defaults.Keys | Sort-Object)) {
    $header += "$k=$($defaults[$k])"
}
$header += @(
    "---victory config---"
    $cfgLines
    "================================================================================"
    ""
)
$header | Set-Content -Path $runLog -Encoding UTF8

Write-Host "Launching $($exe.Name) [VIctory-Belobug NVIDIA | $Console | $DisplayMode | ${TargetFps}FPS | CardBuffers=${CardBuffersMB}MB]" -ForegroundColor Cyan
Write-Host "Guardando log en: $runLog (y copia al cerrar en $latestLog)" -ForegroundColor Green

$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$exitCode = 1
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$writer = New-Object System.IO.StreamWriter($runLog, $true, $utf8NoBom)
$writer.AutoFlush = $true
try {
    & $runner run $exe.FullName --console $Console --execute 2>&1 | ForEach-Object {
        $line = "$_"
        $writer.WriteLine($line)
        if ($LogLevel -ne 'warn' -or $line -match 'WARN|ERROR|fps|panic|removed') {
            Write-Host $line
        }
    }
    $exitCode = $LASTEXITCODE
} finally {
    if ($null -ne $writer) {
        $writer.WriteLine("`n================================================================================")
        $writer.WriteLine("Exited at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz') with code $exitCode")
        $writer.Dispose()
    }
    $ErrorActionPreference = $prevEap
}

Copy-Item -Path $runLog -Destination $latestLog -Force
Write-Host "Sesion terminada (codigo $exitCode). Log guardado en: $latestLog" -ForegroundColor Green
exit $exitCode
