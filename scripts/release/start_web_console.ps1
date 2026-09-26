param(
    [switch]$NoBrowser,
    [switch]$NoBuild,
    [int]$ApiPort = 5000,
    [int]$WebPort = 8787
)
$ErrorActionPreference = 'Stop'
$client = 'E:\FlutterProject\nonto'
$backend = 'D:\NanTuPy'
$python = Join-Path $backend '.venv\Scripts\python.exe'
$flutter = 'D:\flutter\bin\flutter.bat'
$runtime = Join-Path $client '.run\deployment-console'
$pidFile = Join-Path $runtime 'pids.json'
$logDir = Join-Path $runtime 'logs'
$configFile = Join-Path $client 'scripts\release\release.config.json'

function Fail([string]$message) {
    Write-Host "[FAILED] $message" -ForegroundColor Red
    exit 1
}
function Require-File([string]$path, [string]$label) {
    if (!(Test-Path -LiteralPath $path -PathType Leaf)) { Fail "$label not found: $path" }
}
function Require-Directory([string]$path, [string]$label) {
    if (!(Test-Path -LiteralPath $path -PathType Container)) { Fail "$label not found: $path" }
}
function Get-CommandLine([int]$processId) {
    try { return (Get-CimInstance Win32_Process -Filter "ProcessId=$processId").CommandLine } catch { return $null }
}
function Test-TrackedProcess($record, [string]$expectedMarker) {
    if ($null -eq $record -or "$($record.id)" -notmatch '^[1-9][0-9]*$') { return $false }
    $process = Get-Process -Id ([int]$record.id) -ErrorAction SilentlyContinue
    if ($null -eq $process) { return $false }
    try { $actualExecutable = $process.Path } catch { return $false }
    if (![string]::Equals($actualExecutable, $python, [StringComparison]::OrdinalIgnoreCase)) { return $false }
    $commandLine = Get-CommandLine $process.Id
    return $commandLine -and ($commandLine.IndexOf($expectedMarker, [StringComparison]::OrdinalIgnoreCase) -ge 0)
}
function Assert-PortAvailable([int]$port, [string]$name) {
    $owner = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($owner) { Fail "$name port $port is owned by PID $($owner.OwningProcess). Unknown processes are never stopped." }
}
function Save-Tracked {
    @($script:tracked) | ConvertTo-Json | Set-Content -LiteralPath $pidFile -Encoding UTF8
}
function Start-Tracked([string]$name, [string]$file, [string[]]$arguments, [string]$workingDirectory, [string]$marker, [int]$port = 0) {
    $record = $script:previous | Where-Object { $_.name -eq $name } | Select-Object -First 1
    if (Test-TrackedProcess $record $marker) {
        Write-Host "Reusing $name (PID $($record.id))"
        return @{ name = $name; id = [int]$record.id; executable = $file; marker = $marker }
    }
    if ($port -gt 0) { Assert-PortAvailable $port $name }
    $log = Join-Path $logDir "$name.log"
    $process = Start-Process -FilePath $file -ArgumentList $arguments -WorkingDirectory $workingDirectory `
        -RedirectStandardOutput $log -RedirectStandardError "$log.err" -PassThru -WindowStyle Minimized
    Start-Sleep -Seconds 1
    if ($process.HasExited) { Fail "$name exited during startup. See $log.err" }
    return @{ name = $name; id = $process.Id; executable = $file; marker = $marker }
}

if ($ApiPort -lt 1 -or $ApiPort -gt 65535 -or $WebPort -lt 1 -or $WebPort -gt 65535 -or $ApiPort -eq $WebPort) {
    Fail 'API and Web ports must be distinct integers in the range 1-65535.'
}
Require-Directory $client 'Client directory'
Require-Directory $backend 'Backend directory'
Require-File $python 'Backend Python environment'
Require-File $flutter 'Flutter SDK'
Require-File (Join-Path $backend 'app\main.py') 'FastAPI entry point'
Require-File (Join-Path $client 'scripts\release\deployment_worker.py') 'Deployment worker'
Require-File (Join-Path $client 'scripts\release\web_console_server.py') 'Web console server'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$script:previous = @()
if (Test-Path -LiteralPath $pidFile -PathType Leaf) {
    try {
        $decoded = Get-Content -Raw -LiteralPath $pidFile | ConvertFrom-Json
        $script:previous = @($decoded | ForEach-Object { $_ })
    } catch {
        Fail 'The PID record is invalid. Inspect running processes before removing it.'
    }
}

if (!$NoBuild) {
    Push-Location $client
    try {
        $previousPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            & $flutter build web --release --no-pub '--base-href=/nonto/' --no-source-maps `
                "--dart-define=API_BASE_URL=http://127.0.0.1:$ApiPort/api" `
                "--dart-define=WS_URL=ws://127.0.0.1:$ApiPort/ws" *> (Join-Path $logDir 'web-build.log')
            $buildExitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $previousPreference
        }
        if ($buildExitCode -ne 0) { Fail 'Flutter Web build failed. See .run\deployment-console\logs\web-build.log.' }
    } finally { Pop-Location }
}
$webRoot = Join-Path $client 'build\web'
Require-Directory $webRoot 'Web build directory'

$script:tracked = @()
$apiMarker = "uvicorn app.main:app --host 127.0.0.1 --port $ApiPort"
$script:tracked += Start-Tracked 'api' $python @('-m', 'uvicorn', 'app.main:app', '--host', '127.0.0.1', '--port', "$ApiPort") $backend $apiMarker $ApiPort
Save-Tracked

if (Test-Path -LiteralPath $configFile -PathType Leaf) {
    $workerScript = Join-Path $client 'scripts\release\deployment_worker.py'
    $script:tracked += Start-Tracked 'worker' $python @($workerScript, '--backend-root', $backend, '--config', $configFile) $client $workerScript
    Save-Tracked
} else {
    Write-Host '[NOTICE] release.config.json is not initialized. API and Web are running, but the worker was not started.' -ForegroundColor Yellow
}

$webServer = Join-Path $client 'scripts\release\web_console_server.py'
$webMarker = "web_console_server.py --port $WebPort"
$script:tracked += Start-Tracked 'web' $python @($webServer, '--port', "$WebPort", '--root', $webRoot) $client $webMarker $WebPort
Save-Tracked

$url = "http://127.0.0.1:$WebPort/nonto/#/settings/deployments"
Write-Host "Deployment console: $url" -ForegroundColor Green
if (!$NoBrowser) { Start-Process $url }
