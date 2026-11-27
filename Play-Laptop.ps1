# Tuned VIctory-Belobug NVIDIA launcher for RTX 4050 6 GB / 16 GB RAM
param(
    [ValidateSet('series-s', 'series-x')][string]$Console = 'series-s',
    [ValidateSet('1280x720', '1664x936', '1920x1080')][string]$OutputMode = '1280x720',
    [ValidateSet(6, 7)][int]$Upscaler = 6,
    [string]$RenderScale = '0.75',
    [ValidateSet(0, 30, 40, 60)][int]$TargetFps = 60,
    [ValidateRange(64, 1536)][int]$CardBuffersMB = 128,
    [ValidateRange(0, 6144)][int]$TextureBudgetMB = 1800,
    [ValidateRange(10, 100)][int]$MeshLimitPct = 100,
    [ValidateRange(1, 16)][int]$MaxAniso = 4,
    [ValidateRange(0, 850)][int]$PipelineWaitMs = 200,
    [ValidateRange(50, 90)][int]$TextureRoomPct = 78,
    [ValidateSet('warn', 'info', 'debug')][string]$LogLevel = 'info',
    [string]$LogFile = '',
    [switch]$LevelsOnDemand,
    [switch]$PortConstants,
    [switch]$CardAccounting,
    [switch]$Vsync,
    [switch]$FastLight,
    [switch]$Hud,
    [switch]$FullHud,
    [switch]$Kbm,
    [switch]$Safe
)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$runner = Join-Path $PSScriptRoot 'target\release\victory.exe'
if (-not (Test-Path $runner)) { Write-Error "Build target\release\victory.exe first."; exit 2 }

# Warn if running on laptop battery (NVIDIA GPU drops to 20-35 W on battery)
try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    $power = [System.Windows.Forms.SystemInformation]::PowerStatus
    if ($power.PowerLineStatus -eq 'Offline') {
        $pct = [math]::Round($power.BatteryLifePercent * 100)
        Write-Warning "Laptop en bateria ($pct%). Conecta el cargador para rendimiento completo de la RTX 4050."
    }
} catch {}

if ($RenderScale -ne '') {
    $parsedScale = 0.0
    if (-not [double]::TryParse($RenderScale, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsedScale) -or $parsedScale -lt 0.5 -or $parsedScale -gt 1.0) {
        Write-Error "RenderScale '$RenderScale' invalido: el motor solo acepta valores entre 0.5 y 1.0."
        exit 2
    }
}

$cfgLines = & $runner config
$gameDir = ($cfgLines | Where-Object { $_ -match '^game_dir\s*:\s*(.+)$' } | ForEach-Object { $Matches[1].Trim() }) | Select-Object -First 1
$dataDir = ($cfgLines | Where-Object { $_ -match '^data_dir\s*:\s*(.+)$' } | ForEach-Object { $Matches[1].Trim() }) | Select-Object -First 1
if (-not $gameDir) { Write-Error "Could not read game_dir from victory.toml."; exit 2 }
$exe = Get-ChildItem -Path $gameDir -Filter '*.exe' -File | Sort-Object Length -Descending | Select-Object -First 1
if (-not $exe) { Write-Error "No title executable found in $gameDir"; exit 2 }

# Warn if saved title settings still store a 4K UI plane or VSync on
if ($dataDir -and (Test-Path $dataDir)) {
    $settingsFiles = Get-ChildItem -Path $dataDir -Filter 'settings.xml' -Recurse -ErrorAction SilentlyContinue
    foreach ($sf in $settingsFiles) {
        $xmlText = Get-Content -Path $sf.FullName -Raw -ErrorAction SilentlyContinue
        if ($xmlText -match '<uiResolution>[\s\S]*?<width\s+value="3840"') {
            Write-Warning "settings.xml ($($sf.FullName)) tiene uiResolution=3840x2160."
        }
        if ($xmlText -match '<vSync\s+value="[^0"]') {
            Write-Warning "settings.xml ($($sf.FullName)) tiene vSync activo."
        }
    }
}

$keepVars = 'VICTORY_CONFIG', 'VICTORY_GAME_DIR', 'VICTORY_CACHE_DIR', 'VICTORY_DATA_DIR', 'VICTORY_FIDELITYFX_DIR'
Get-ChildItem Env:VICTORY_* -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin $keepVars } | ForEach-Object {
    Remove-Item "Env:$($_.Name)" -ErrorAction SilentlyContinue
}

if ($Upscaler -eq 7 -and $OutputMode -ne '1920x1080') {
    Write-Warning "FSR4 (Upscaler 7) en Series S solo soporta 1920x1080. Usa -Upscaler 6 para $OutputMode."
}

$defaults = @{
    VICTORY_D3D12_ADAPTER            = 'NVIDIA'
    VICTORY_DISPLAY_MODE             = $OutputMode
    VICTORY_OUTPUT                   = $OutputMode
    VICTORY_UPSCALER                 = "$Upscaler"
    VICTORY_VSYNC                    = if ($Vsync) { '1' } else { '0' }
    VICTORY_MAX_ANISO                = "$MaxAniso"
    VICTORY_MESH_LIMIT_PERCENT       = "$MeshLimitPct"
    # VICTORY_LEVELS_ON_DEMAND omitted by default (only set if -LevelsOnDemand is passed)
    VICTORY_PORT_CONSTANTS           = if ($PortConstants -and -not $Safe) { '1' } else { '0' }
    VICTORY_PORT_DESCRIPTORS         = if ($Safe) { '0' } else { '1' }
    VICTORY_PORT_CBV                 = if ($Safe) { '0' } else { '1' }
    VICTORY_PORT_GUARD               = if ($Safe) { '0' } else { '1' }
    VICTORY_PORT_JOURNAL             = if ($Safe) { '0' } else { '1' }
    VICTORY_RESIDENCY                = '1'
    VICTORY_CARD_GUARD               = '1'
    VICTORY_TEXTURE_ROOM_PERCENT     = "$TextureRoomPct"
    VICTORY_CARD_ROOM_FOR_TARGETS_MB = '1200'
    VICTORY_CARD_ROOM_FOR_BUFFERS    = '1'
    VICTORY_INDIRECT_REST            = '0'
    VICTORY_XMA_REFILL               = '1'
    VICTORY_AMBIENT                  = if ($FastLight) { 'constant:0.25' } else { '0.85' }
    VICTORY_AMBIENT_SHADE            = '0,0'
    VICTORY_AMBIENT_MOST             = '1.15'
    VICTORY_AMBIENT_SETTLE           = '250,3'
    VICTORY_PIPELINE_WAIT_MS         = "$PipelineWaitMs"
    VICTORY_SCREEN_WAIT_MS           = '10000'
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
    VICTORY_LATE_WAIT_LISTS          = '224'
    VICTORY_WINDOW_KB                = '256'
    VICTORY_WINDOW_TAILS             = '1'
    VICTORY_CARD_BUFFERS_MIN_KB      = '1024'
    VICTORY_CARD_BUFFERS_MB          = "$CardBuffersMB"
    VICTORY_WINDOW_BUDGET_MB         = '256'
    VICTORY_DSTORAGE_IO              = 'direct'
    VICTORY_DSTORAGE_WORKERS         = '8'
    VICTORY_LOG                      = $LogLevel
    VICTORY_CARD_ACCOUNTING          = if ($CardAccounting) { '1' } else { '0' }
    VICTORY_D3D12_DRED               = 'faults'
}

if ($LevelsOnDemand) {
    $defaults['VICTORY_LEVELS_ON_DEMAND'] = '1'
}
if ($TextureBudgetMB -gt 0) {
    $defaults['VICTORY_TEXTURE_BUDGET_MB'] = "$TextureBudgetMB"
}
if ($RenderScale -ne '' -and $Upscaler -eq 6) {
    $defaults['VICTORY_RENDER_SCALE'] = $RenderScale
}
if (-not $FastLight) {
    $defaults['VICTORY_AMBIENT_AIR'] = '1.4'
}

if ($TargetFps -eq 60) { $defaults['VICTORY_FRAME_INTERVAL_MS'] = '16.667' }
elseif ($TargetFps -eq 40) { $defaults['VICTORY_FRAME_INTERVAL_MS'] = '25.0' }
elseif ($TargetFps -eq 0) { $defaults['VICTORY_FRAME_INTERVAL_MS'] = '0' }

if ($FullHud) { $defaults['VICTORY_PANEL'] = '1' }
elseif ($Hud) { $defaults['VICTORY_PANEL'] = 'compact' }
if ($Kbm) { $defaults['VICTORY_KBM_GTA'] = '1' }

foreach ($k in $defaults.Keys) { Set-Item "Env:$k" $defaults[$k] }

$logsDir = Join-Path $PSScriptRoot 'logs'
New-Item -ItemType Directory -Force $logsDir | Out-Null
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$runLog = if ($LogFile -ne '') { $LogFile } else { Join-Path $logsDir "run-$timestamp.log" }
$latestLog = Join-Path $logsDir 'latest.log'

$header = @(
    "================================================================================"
    "VIctory-Belobug NVIDIA Run Log - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')"
    "Console: $Console | Display/Output: $OutputMode | Scale: $RenderScale | Up: $Upscaler | Mesh: ${MeshLimitPct}% | Aniso: x${MaxAniso} | VSync: $Vsync | TexBudget: ${TextureBudgetMB}MB | CardBuf: ${CardBuffersMB}MB"
    "Executable: $($exe.FullName)"
    "Runner: $runner"
    "--- VICTORY_* Environment ---"
)
foreach ($k in ($defaults.Keys | Sort-Object)) { $header += "$k=$($defaults[$k])" }
$header += @("---victory config---", $cfgLines, "================================================================================", "")
$header | Set-Content -Path $runLog -Encoding UTF8

Write-Host "Launching $($exe.Name) [$Console | Out=$OutputMode | Scale=$RenderScale | Mesh=${MeshLimitPct}% | Aniso=x${MaxAniso} | TexMax=${TextureBudgetMB}MB | VSync=$Vsync]" -ForegroundColor Cyan

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
        if ($LogLevel -eq 'debug' -or $line -match 'WARN|ERROR|fps,|ms/frame|display mode|presenting|resolution:|video memory|card accounting|no card copy|console |renderer port|panic|removed|DRED') {
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
Write-Host "Sesion terminada (codigo $exitCode). Log completo guardado en: $latestLog" -ForegroundColor Green
exit $exitCode
