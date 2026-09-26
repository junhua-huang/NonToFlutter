param(
    [string]$Config = "$PSScriptRoot\release.config.json",
    [ValidateSet('plan','package','deploy','register','restore')][string]$Mode = 'plan',
    [string]$Version = '',
    [string]$Release = '',
    [string]$Components = 'backend,web,android',
    [switch]$SchemaCompatible
)
$ErrorActionPreference = 'Stop'
$Python = (Get-Command py -ErrorAction SilentlyContinue).Source
if (!$Python) { $Python = (Get-Command python3 -ErrorAction SilentlyContinue).Source }
if (!$Python) { $Python = (Get-Command python -ErrorAction SilentlyContinue).Source }
if (!$Python) { throw 'Install a local Python interpreter (py, python3, or python) before publishing.' }
$Arguments = @("$PSScriptRoot\publish.py", '--config', $Config, '--mode', $Mode, '--components', $Components)
if ($Version) { $Arguments += @('--version', $Version) }
if ($Release) { $Arguments += @('--release', $Release) }
if ($SchemaCompatible) { $Arguments += '--schema-compatible' }
if ((Split-Path -Leaf $Python) -ieq 'py.exe') { & $Python '-3' @Arguments } else { & $Python @Arguments }
exit $LASTEXITCODE
