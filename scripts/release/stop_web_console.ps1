$ErrorActionPreference = 'Stop'
$runtime = 'E:\FlutterProject\nonto\.run\deployment-console'
$pidFile = Join-Path $runtime 'pids.json'
$expectedExecutable = 'D:\NanTuPy\.venv\Scripts\python.exe'
if (!(Test-Path -LiteralPath $pidFile -PathType Leaf)) {
    Write-Host 'No tracked Web console processes are running.'
    exit 0
}
try {
    $decoded = Get-Content -Raw -LiteralPath $pidFile | ConvertFrom-Json
    $items = @($decoded | ForEach-Object { $_ })
} catch {
    Write-Host 'The PID record is invalid. No processes were stopped.' -ForegroundColor Red
    exit 1
}
foreach ($item in $items) {
    if ($item.name -notin @('api', 'worker', 'web')) {
        Write-Host 'The PID record contains an invalid process name. No processes were stopped.' -ForegroundColor Red
        exit 1
    }
    if ("$($item.id)" -notmatch '^[1-9][0-9]*$') {
        Write-Host 'The PID record contains an invalid process ID. No processes were stopped.' -ForegroundColor Red
        exit 1
    }
    if ([string]::IsNullOrWhiteSpace("$($item.marker)")) {
        Write-Host 'The PID record contains an empty process marker. No processes were stopped.' -ForegroundColor Red
        exit 1
    }
    if ("$($item.executable)" -ine $expectedExecutable) {
        Write-Host 'The PID record contains an unexpected executable. No processes were stopped.' -ForegroundColor Red
        exit 1
    }
}
foreach ($item in $items) {
    $process = Get-Process -Id ([int]$item.id) -ErrorAction SilentlyContinue
    if (!$process) { continue }
    try {
        $commandLine = (Get-CimInstance Win32_Process -Filter "ProcessId=$($process.Id)").CommandLine
        $actualExecutable = $process.Path
    } catch {
        $commandLine = $null
        $actualExecutable = $null
    }
    $identityMatches = ($actualExecutable -ieq "$($item.executable)") -and
        $commandLine -and
        ($commandLine.IndexOf("$($item.marker)", [StringComparison]::OrdinalIgnoreCase) -ge 0)
    if (!$identityMatches) {
        Write-Host "Skipped $($item.name) (PID $($item.id)): process identity does not match." -ForegroundColor Yellow
        continue
    }
    Stop-Process -Id $process.Id
    Write-Host "Stopped $($item.name) (PID $($process.Id))"
}
Remove-Item -LiteralPath $pidFile -Force
