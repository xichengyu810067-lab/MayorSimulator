#requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}

function Invoke-IsolatedRunner {
    param(
        [Parameter(Mandatory)][string]$Runner,
        [Parameter(Mandatory)][string]$Child,
        [Parameter(Mandatory)][string]$ProfileName,
        [Parameter(Mandatory)][int]$MinimumRuntimeSeconds
    )
    & $script:WindowsPowerShellExe -NoProfile -ExecutionPolicy Bypass -File $Runner -GodotExe $Child -ProfileName $ProfileName -RendererMode Mobile -MinimumRuntimeSeconds $MinimumRuntimeSeconds | Out-Null
    return [int]$LASTEXITCODE
}

function New-SyntheticChild {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][int]$SleepSeconds,
        [Parameter(Mandatory)][int]$ExitCode
    )
    $body = @"
@echo off
setlocal EnableExtensions
set "logfile="
:arguments
if "%~1"=="" goto ready
if /I "%~1"=="--log-file" (
  set "logfile=%~2"
  shift
)
shift
goto arguments
:ready
if not "%logfile%"=="" > "%logfile%" echo synthetic native child log
ping 127.0.0.1 -n $($SleepSeconds + 1) > nul
exit /b $ExitCode
"@
    [IO.File]::WriteAllText($Path, $body, [Text.UTF8Encoding]::new($false))
}

$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..') -ErrorAction Stop).Path
$WindowsPowerShellExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $WindowsPowerShellExe -PathType Leaf)) { throw "Windows PowerShell 5.1 is unavailable: $WindowsPowerShellExe" }
$runner = Join-Path $projectRoot 'tools\run_isolated_playtest.ps1'
if (-not (Test-Path -LiteralPath $runner -PathType Leaf)) { throw "Runner not found: $runner" }
$testRoot = Join-Path $projectRoot ('.tmp\isolated-playtest-contract-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -ErrorAction Stop | Out-Null
$profileSuffix = [Guid]::NewGuid().ToString('N').Substring(0, 12)

$successChild = Join-Path $testRoot 'success-child.cmd'
$crashChild = Join-Path $testRoot 'crash-child.cmd'
$shortChild = Join-Path $testRoot 'short-child.cmd'
New-SyntheticChild -Path $successChild -SleepSeconds 2 -ExitCode 0
New-SyntheticChild -Path $crashChild -SleepSeconds 0 -ExitCode 23
New-SyntheticChild -Path $shortChild -SleepSeconds 0 -ExitCode 0

$expectedHead = (& git -c "safe.directory=$projectRoot" -C $projectRoot rev-parse HEAD).Trim()
$expectedTree = (& git -c "safe.directory=$projectRoot" -C $projectRoot rev-parse 'HEAD^{tree}').Trim()
if ($LASTEXITCODE -ne 0) { throw 'Could not resolve test source identity.' }

$successProfile = 'synthetic-success-' + $profileSuffix
$successExit = Invoke-IsolatedRunner -Runner $runner -Child $successChild -ProfileName $successProfile -MinimumRuntimeSeconds 1
Assert-True -Condition ($successExit -eq 0) -Message "success child runner exit was $successExit, expected 0"
$successSummaryPath = Join-Path $projectRoot ('.tmp\isolated-playtest\' + $successProfile + '\playtest-result.json')
$successSummary = Get-Content -LiteralPath $successSummaryPath -Raw | ConvertFrom-Json
Assert-True -Condition ($successSummary.status -eq 'passed') -Message 'success child was not recorded as passed'
Assert-True -Condition ([int]$successSummary.process.process_id -gt 0) -Message 'success child PID was not recorded'
Assert-True -Condition ([int]$successSummary.process.child_exit_code -eq 0) -Message 'success child exit code was not recorded as zero'
Assert-True -Condition ($successSummary.source.head -eq $expectedHead -and $successSummary.source.tree -eq $expectedTree) -Message 'success source identity was not recorded'
Assert-True -Condition (-not [string]::IsNullOrWhiteSpace([string]$successSummary.isolation.godot_log_sha256)) -Message 'success log SHA-256 was not recorded'

$crashProfile = 'synthetic-crash-' + $profileSuffix
$crashExit = Invoke-IsolatedRunner -Runner $runner -Child $crashChild -ProfileName $crashProfile -MinimumRuntimeSeconds 0
Assert-True -Condition ($crashExit -ne 0) -Message 'synthetic crash child unexpectedly passed'
$crashSummaryPath = Join-Path $projectRoot ('.tmp\isolated-playtest\' + $crashProfile + '\playtest-result.json')
$crashSummary = Get-Content -LiteralPath $crashSummaryPath -Raw | ConvertFrom-Json
Assert-True -Condition ($crashSummary.status -eq 'child_failed') -Message 'synthetic crash child was not recorded as child_failed'
Assert-True -Condition ([int]$crashSummary.process.child_exit_code -eq 23) -Message 'synthetic crash child exit code was not preserved'

$shortProfile = 'synthetic-short-' + $profileSuffix
$shortExit = Invoke-IsolatedRunner -Runner $runner -Child $shortChild -ProfileName $shortProfile -MinimumRuntimeSeconds 2
Assert-True -Condition ($shortExit -eq 3) -Message "short child runner exit was $shortExit, expected 3"
$shortSummaryPath = Join-Path $projectRoot ('.tmp\isolated-playtest\' + $shortProfile + '\playtest-result.json')
$shortSummary = Get-Content -LiteralPath $shortSummaryPath -Raw | ConvertFrom-Json
Assert-True -Condition ($shortSummary.status -eq 'short_process') -Message 'short child was not recorded as short_process'
Assert-True -Condition ([int]$shortSummary.process.child_exit_code -eq 0) -Message 'short child exit code was not preserved'

$beforeReuseHash = (Get-FileHash -LiteralPath $successSummaryPath -Algorithm SHA256).Hash
$reuseExit = Invoke-IsolatedRunner -Runner $runner -Child $successChild -ProfileName $successProfile -MinimumRuntimeSeconds 1
Assert-True -Condition ($reuseExit -ne 0) -Message 'reused profile unexpectedly launched'
$afterReuseHash = (Get-FileHash -LiteralPath $successSummaryPath -Algorithm SHA256).Hash
Assert-True -Condition ($beforeReuseHash -eq $afterReuseHash) -Message 'reused profile changed prior result evidence'

& $WindowsPowerShellExe -NoProfile -ExecutionPolicy Bypass -File $runner -GodotExe $successChild -ProfileName ('synthetic-invalid-' + $profileSuffix) -RendererMode 'Mobile;--path=C:\escape'
$invalidRendererExit = [int]$LASTEXITCODE
Assert-True -Condition ($invalidRendererExit -ne 0) -Message 'renderer argument injection unexpectedly passed validation'

Write-Output 'ISOLATED_PLAYTEST_RUNNER_CONTRACT_PASSED: checks=17'
