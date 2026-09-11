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
        [Parameter(Mandatory)][int]$MinimumRuntimeSeconds,
        [Parameter(Mandatory)][string]$RendererMode
    )
    $parts = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Runner, '-GodotExe', $Child, '-ProfileName', $ProfileName, '-RendererMode', $RendererMode, '-MinimumRuntimeSeconds', [string]$MinimumRuntimeSeconds)
    $commandLine = (($parts | ForEach-Object {
        $part = [string]$_
        if ($part -match '[\s"]') { '"' + ($part -replace '(\\*)"', '$1$1\\"' -replace '(\\*)$', '$1$1') + '"' } else { $part }
    }) -join ' ')
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $script:WindowsPowerShellExe
    $info.Arguments = $commandLine
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    if (-not $process.Start()) { throw 'Synthetic runner process did not start.' }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    $exitCode = [int]$process.ExitCode
    $process.Dispose()
    return [pscustomobject]@{ exit_code = $exitCode; stdout = $stdout; stderr = $stderr }
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
$crashChild = Join-Path $testRoot 'crash-child.exe'
$shortChild = Join-Path $testRoot 'short-child.cmd'
New-SyntheticChild -Path $successChild -SleepSeconds 2 -ExitCode 0
New-SyntheticChild -Path $shortChild -SleepSeconds 0 -ExitCode 0
$crashSource = @'
using System;
using System.IO;
public static class SyntheticCrashChild {
    public static int Main(string[] args) {
        for (var index = 0; index + 1 < args.Length; index++) {
            if (args[index] == "--log-file") { File.WriteAllText(args[index + 1], "synthetic crash child log"); break; }
        }
        return unchecked((int)0xC0000005);
    }
}
'@
Add-Type -TypeDefinition $crashSource -Language CSharp -OutputAssembly $crashChild -OutputType ConsoleApplication -ErrorAction Stop

$expectedHead = (& git -c "safe.directory=$projectRoot" -C $projectRoot rev-parse HEAD).Trim()
$expectedTree = (& git -c "safe.directory=$projectRoot" -C $projectRoot rev-parse 'HEAD^{tree}').Trim()
if ($LASTEXITCODE -ne 0) { throw 'Could not resolve test source identity.' }

$successProfile = 'synthetic-success-' + $profileSuffix
$successResult = Invoke-IsolatedRunner -Runner $runner -Child $successChild -ProfileName $successProfile -MinimumRuntimeSeconds 1 -RendererMode Mobile
$successExit = [int]$successResult.exit_code
Assert-True -Condition ($successExit -eq 0) -Message "success child runner exit was $successExit, expected 0"
$successSummaryPath = Join-Path $projectRoot ('.tmp\isolated-playtest\' + $successProfile + '\playtest-result.json')
$successSummary = Get-Content -LiteralPath $successSummaryPath -Raw | ConvertFrom-Json
Assert-True -Condition ($successSummary.status -eq 'passed') -Message 'success child was not recorded as passed'
Assert-True -Condition ([int]$successSummary.process.process_id -gt 0) -Message 'success child PID was not recorded'
Assert-True -Condition ([int]$successSummary.process.child_exit_code -eq 0) -Message 'success child exit code was not recorded as zero'
Assert-True -Condition ($successSummary.source.head -eq $expectedHead -and $successSummary.source.tree -eq $expectedTree) -Message 'success source identity was not recorded'
Assert-True -Condition (-not [string]::IsNullOrWhiteSpace([string]$successSummary.isolation.godot_log_sha256)) -Message 'success log SHA-256 was not recorded'

$crashProfile = 'synthetic-crash-' + $profileSuffix
$crashResult = Invoke-IsolatedRunner -Runner $runner -Child $crashChild -ProfileName $crashProfile -MinimumRuntimeSeconds 0 -RendererMode Mobile
$crashExit = [int]$crashResult.exit_code
Assert-True -Condition ($crashExit -ne 0) -Message 'synthetic crash child unexpectedly passed'
$crashSummaryPath = Join-Path $projectRoot ('.tmp\isolated-playtest\' + $crashProfile + '\playtest-result.json')
$crashSummary = Get-Content -LiteralPath $crashSummaryPath -Raw | ConvertFrom-Json
Assert-True -Condition ($crashSummary.status -eq 'child_failed') -Message 'synthetic crash child was not recorded as child_failed'
Assert-True -Condition ([int]$crashSummary.process.child_exit_code -eq -1073741819) -Message 'synthetic Windows crash exit code was not preserved as signed Int32'

$shortProfile = 'synthetic-short-' + $profileSuffix
$shortResult = Invoke-IsolatedRunner -Runner $runner -Child $shortChild -ProfileName $shortProfile -MinimumRuntimeSeconds 2 -RendererMode Mobile
$shortExit = [int]$shortResult.exit_code
Assert-True -Condition ($shortExit -eq 3) -Message "short child runner exit was $shortExit, expected 3"
$shortSummaryPath = Join-Path $projectRoot ('.tmp\isolated-playtest\' + $shortProfile + '\playtest-result.json')
$shortSummary = Get-Content -LiteralPath $shortSummaryPath -Raw | ConvertFrom-Json
Assert-True -Condition ($shortSummary.status -eq 'short_process') -Message 'short child was not recorded as short_process'
Assert-True -Condition ([int]$shortSummary.process.child_exit_code -eq 0) -Message 'short child exit code was not preserved'

$beforeReuseHash = (Get-FileHash -LiteralPath $successSummaryPath -Algorithm SHA256).Hash
$reuseResult = Invoke-IsolatedRunner -Runner $runner -Child $successChild -ProfileName $successProfile -MinimumRuntimeSeconds 1 -RendererMode Mobile
$reuseExit = [int]$reuseResult.exit_code
Assert-True -Condition ($reuseExit -ne 0) -Message 'reused profile unexpectedly launched'
$afterReuseHash = (Get-FileHash -LiteralPath $successSummaryPath -Algorithm SHA256).Hash
Assert-True -Condition ($beforeReuseHash -eq $afterReuseHash) -Message 'reused profile changed prior result evidence'

$invalidRendererResult = Invoke-IsolatedRunner -Runner $runner -Child $successChild -ProfileName ('synthetic-invalid-' + $profileSuffix) -MinimumRuntimeSeconds 1 -RendererMode 'Mobile;--path=C:\escape'
$invalidRendererExit = [int]$invalidRendererResult.exit_code
Assert-True -Condition ($invalidRendererExit -ne 0) -Message 'renderer argument injection unexpectedly passed validation'
$traversalResult = Invoke-IsolatedRunner -Runner $runner -Child $successChild -ProfileName '..' -MinimumRuntimeSeconds 1 -RendererMode Mobile
Assert-True -Condition ([int]$traversalResult.exit_code -ne 0) -Message 'traversal profile unexpectedly passed validation'

Write-Output 'ISOLATED_PLAYTEST_RUNNER_CONTRACT_PASSED: checks=16'
