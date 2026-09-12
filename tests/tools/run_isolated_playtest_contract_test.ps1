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
        [Parameter(Mandatory)][string]$RendererMode,
        [string]$TestProjectRoot
    )
    $parts = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Runner, '-GodotExe', $Child, '-ProfileName', $ProfileName, '-RendererMode', $RendererMode, '-MinimumRuntimeSeconds', [string]$MinimumRuntimeSeconds)
    if (-not [string]::IsNullOrWhiteSpace($TestProjectRoot)) { $parts += @('-TestProjectRoot', $TestProjectRoot, '-AllowSyntheticTestChild') }
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
        [Parameter(Mandatory)][int]$ExitCode,
        [string]$ConcurrentMutationPath
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
if not "$ConcurrentMutationPath"=="" start "" /b cmd /c "ping 127.0.0.1 -n 2 > nul & > "$ConcurrentMutationPath" echo changed-during-run"
ping 127.0.0.1 -n $($SleepSeconds + 1) > nul
exit /b $ExitCode
"@
    [IO.File]::WriteAllText($Path, $body, [Text.UTF8Encoding]::new($false))
}

function Remove-InvocationFixtureDirectory {
    param(
        [Parameter(Mandatory)][string]$FixtureDirectory,
        [Parameter(Mandatory)][string]$InvocationName,
        [Parameter(Mandatory)][string]$TempDirectory
    )

    Assert-True -Condition ([IO.Directory]::Exists($FixtureDirectory)) -Message "cleanup target did not exist: $FixtureDirectory"

    $resolvedTarget = (Resolve-Path -LiteralPath $FixtureDirectory -ErrorAction Stop).Path
    $resolvedSystemTemp = (Resolve-Path -LiteralPath $TempDirectory -ErrorAction Stop).Path
    $targetName = [IO.Path]::GetFileName($resolvedTarget.TrimEnd('\'))
    Assert-True -Condition ($targetName -ceq $InvocationName) -Message "cleanup target name was not created by this invocation: $resolvedTarget"
    Assert-True -Condition ($targetName -match '^mayor-isolated-playtest-contract(?:-project)?-[0-9a-f]{32}$') -Message "cleanup target name was not an allowed contract fixture name: $resolvedTarget"

    $canonicalParent = [IO.Path]::GetFullPath(([IO.Directory]::GetParent($resolvedTarget)).FullName).TrimEnd('\')
    $canonicalSystemTemp = [IO.Path]::GetFullPath($resolvedSystemTemp).TrimEnd('\')
    Assert-True -Condition ($canonicalParent -ieq $canonicalSystemTemp) -Message "cleanup target parent was not the system temp directory: $resolvedTarget"
    Assert-True -Condition ($canonicalParent -ine [IO.Path]::GetPathRoot($canonicalParent).TrimEnd('\')) -Message "cleanup target parent resolved to a filesystem root: $resolvedTarget"

    $cursor = $resolvedTarget
    while ($true) {
        $item = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
        Assert-True -Condition (([IO.FileAttributes]$item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) -Message "cleanup target contains a reparse point: $cursor"
        if ($cursor.TrimEnd('\') -ieq $resolvedSystemTemp.TrimEnd('\')) { break }
        $parentInfo = [IO.Directory]::GetParent($cursor)
        $parent = if ($null -eq $parentInfo) { $null } else { $parentInfo.FullName }
        Assert-True -Condition (-not [string]::IsNullOrWhiteSpace($parent) -and $parent -ine $cursor) -Message "cleanup target did not resolve beneath system temp: $resolvedTarget"
        $cursor = $parent
    }

    Remove-Item -LiteralPath $resolvedTarget -Recurse -Force -ErrorAction Stop
}

$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..') -ErrorAction Stop).Path
$WindowsPowerShellExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $WindowsPowerShellExe -PathType Leaf)) { throw "Windows PowerShell 5.1 is unavailable: $WindowsPowerShellExe" }
$runner = Join-Path $projectRoot 'tools\run_isolated_playtest.ps1'
if (-not (Test-Path -LiteralPath $runner -PathType Leaf)) { throw "Runner not found: $runner" }
$systemTempPath = [IO.Path]::GetTempPath()
$testRootName = 'mayor-isolated-playtest-contract-' + [Guid]::NewGuid().ToString('N')
$fixtureProjectRootName = 'mayor-isolated-playtest-contract-project-' + [Guid]::NewGuid().ToString('N')
$testRoot = Join-Path $systemTempPath $testRootName
$fixtureProjectRoot = Join-Path $systemTempPath $fixtureProjectRootName
$testRootCreated = $false
$fixtureProjectRootCreated = $false
$changedFixturePath = $null
$originalTrackedFixtureBytes = $null

try {
New-Item -ItemType Directory -Path $testRoot -ErrorAction Stop | Out-Null
$testRootCreated = $true
New-Item -ItemType Directory -Path $fixtureProjectRoot -ErrorAction Stop | Out-Null
$fixtureProjectRootCreated = $true
[IO.File]::WriteAllText((Join-Path $fixtureProjectRoot 'project.godot'), "[application]`nconfig/name=`"Isolated Runner Contract`"`n", [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $fixtureProjectRoot 'tracked-fixture.txt'), "original`n", [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $fixtureProjectRoot '.gitignore'), ".tmp/`n", [Text.UTF8Encoding]::new($false))
$changedFixturePath = Join-Path $fixtureProjectRoot 'tracked-fixture.txt'
$originalTrackedFixtureBytes = [IO.File]::ReadAllBytes($changedFixturePath)
& git -C $fixtureProjectRoot init -q
& git -C $fixtureProjectRoot -c user.name='Runner Contract' -c user.email='runner-contract@example.invalid' add .gitignore project.godot tracked-fixture.txt
& git -C $fixtureProjectRoot -c user.name='Runner Contract' -c user.email='runner-contract@example.invalid' commit -q -m 'contract fixture'
if ($LASTEXITCODE -ne 0) { throw 'Could not create isolated Git contract fixture.' }
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

$expectedHead = (& git -c "safe.directory=$fixtureProjectRoot" -C $fixtureProjectRoot rev-parse HEAD).Trim()
$expectedTree = (& git -c "safe.directory=$fixtureProjectRoot" -C $fixtureProjectRoot rev-parse 'HEAD^{tree}').Trim()
if ($LASTEXITCODE -ne 0) { throw 'Could not resolve test source identity.' }

$successProfile = 'synthetic-success-' + $profileSuffix
$successResult = Invoke-IsolatedRunner -Runner $runner -Child $successChild -ProfileName $successProfile -MinimumRuntimeSeconds 1 -RendererMode Mobile -TestProjectRoot $fixtureProjectRoot
$successExit = [int]$successResult.exit_code
Assert-True -Condition ($successExit -eq 0) -Message "success child runner exit was $successExit, expected 0"
$successSummaryPath = Join-Path $fixtureProjectRoot ('.tmp\isolated-playtest\' + $successProfile + '\playtest-result.json')
$successSummary = Get-Content -LiteralPath $successSummaryPath -Raw | ConvertFrom-Json
Assert-True -Condition ($successSummary.status -eq 'passed') -Message 'success child was not recorded as passed'
Assert-True -Condition ([int]$successSummary.process.process_id -gt 0) -Message 'success child PID was not recorded'
Assert-True -Condition ([int]$successSummary.process.child_exit_code -eq 0) -Message 'success child exit code was not recorded as zero'
Assert-True -Condition ($successSummary.source.before_run.head -eq $expectedHead -and $successSummary.source.before_run.tree -eq $expectedTree) -Message 'success source identity was not recorded'
Assert-True -Condition ($successSummary.source.after_run.head -eq $expectedHead -and $successSummary.source.after_run.tree -eq $expectedTree) -Message 'success post-run source identity was not recorded'
Assert-True -Condition (-not [string]::IsNullOrWhiteSpace([string]$successSummary.isolation.godot_log_sha256)) -Message 'success log SHA-256 was not recorded'

$crashProfile = 'synthetic-crash-' + $profileSuffix
$crashResult = Invoke-IsolatedRunner -Runner $runner -Child $crashChild -ProfileName $crashProfile -MinimumRuntimeSeconds 0 -RendererMode Mobile -TestProjectRoot $fixtureProjectRoot
$crashExit = [int]$crashResult.exit_code
Assert-True -Condition ($crashExit -ne 0) -Message 'synthetic crash child unexpectedly passed'
$crashSummaryPath = Join-Path $fixtureProjectRoot ('.tmp\isolated-playtest\' + $crashProfile + '\playtest-result.json')
$crashSummary = Get-Content -LiteralPath $crashSummaryPath -Raw | ConvertFrom-Json
Assert-True -Condition ($crashSummary.status -eq 'child_failed') -Message 'synthetic crash child was not recorded as child_failed'
Assert-True -Condition ([int]$crashSummary.process.child_exit_code -eq -1073741819) -Message 'synthetic Windows crash exit code was not preserved as signed Int32'

$shortProfile = 'synthetic-short-' + $profileSuffix
$shortResult = Invoke-IsolatedRunner -Runner $runner -Child $shortChild -ProfileName $shortProfile -MinimumRuntimeSeconds 2 -RendererMode Mobile -TestProjectRoot $fixtureProjectRoot
$shortExit = [int]$shortResult.exit_code
Assert-True -Condition ($shortExit -eq 3) -Message "short child runner exit was $shortExit, expected 3"
$shortSummaryPath = Join-Path $fixtureProjectRoot ('.tmp\isolated-playtest\' + $shortProfile + '\playtest-result.json')
$shortSummary = Get-Content -LiteralPath $shortSummaryPath -Raw | ConvertFrom-Json
Assert-True -Condition ($shortSummary.status -eq 'short_process') -Message 'short child was not recorded as short_process'
Assert-True -Condition ([int]$shortSummary.process.child_exit_code -eq 0) -Message 'short child exit code was not preserved'

$beforeReuseHash = (Get-FileHash -LiteralPath $successSummaryPath -Algorithm SHA256).Hash
$reuseResult = Invoke-IsolatedRunner -Runner $runner -Child $successChild -ProfileName $successProfile -MinimumRuntimeSeconds 1 -RendererMode Mobile -TestProjectRoot $fixtureProjectRoot
$reuseExit = [int]$reuseResult.exit_code
Assert-True -Condition ($reuseExit -ne 0) -Message 'reused profile unexpectedly launched'
$afterReuseHash = (Get-FileHash -LiteralPath $successSummaryPath -Algorithm SHA256).Hash
Assert-True -Condition ($beforeReuseHash -eq $afterReuseHash) -Message 'reused profile changed prior result evidence'

$invalidRendererResult = Invoke-IsolatedRunner -Runner $runner -Child $successChild -ProfileName ('synthetic-invalid-' + $profileSuffix) -MinimumRuntimeSeconds 1 -RendererMode 'Mobile;--path=C:\escape' -TestProjectRoot $fixtureProjectRoot
$invalidRendererExit = [int]$invalidRendererResult.exit_code
Assert-True -Condition ($invalidRendererExit -ne 0) -Message 'renderer argument injection unexpectedly passed validation'
$traversalResult = Invoke-IsolatedRunner -Runner $runner -Child $successChild -ProfileName '..' -MinimumRuntimeSeconds 1 -RendererMode Mobile -TestProjectRoot $fixtureProjectRoot
Assert-True -Condition ([int]$traversalResult.exit_code -ne 0) -Message 'traversal profile unexpectedly passed validation'

$sourceChangeProfile = 'synthetic-source-change-' + $profileSuffix
$sourceChangeChild = Join-Path $testRoot 'source-change-child.cmd'
New-SyntheticChild -Path $sourceChangeChild -SleepSeconds 3 -ExitCode 0 -ConcurrentMutationPath $changedFixturePath
$sourceChangeResult = Invoke-IsolatedRunner -Runner $runner -Child $sourceChangeChild -ProfileName $sourceChangeProfile -MinimumRuntimeSeconds 1 -RendererMode Mobile -TestProjectRoot $fixtureProjectRoot
Assert-True -Condition ([int]$sourceChangeResult.exit_code -ne 0) -Message 'source-changing child unexpectedly passed'
$sourceChangeSummaryPath = Join-Path $fixtureProjectRoot ('.tmp\isolated-playtest\' + $sourceChangeProfile + '\playtest-result.json')
$sourceChangeSummary = Get-Content -LiteralPath $sourceChangeSummaryPath -Raw | ConvertFrom-Json
Assert-True -Condition ($sourceChangeSummary.status -eq 'source_changed') -Message 'concurrent source change was not recorded as source_changed'
Assert-True -Condition ([int]$sourceChangeSummary.process.process_id -gt 0 -and [int]$sourceChangeSummary.process.child_exit_code -eq 0) -Message 'source-changing child evidence was not retained'
Assert-True -Condition (-not [string]::IsNullOrWhiteSpace([string]$sourceChangeSummary.isolation.godot_log_sha256)) -Message 'source-changing child log hash was not retained'
Assert-True -Condition ($sourceChangeSummary.source.before_run.status -eq '' -and $sourceChangeSummary.source.after_run.status -match 'tracked-fixture.txt') -Message 'source-change before/after status was not retained'
[IO.File]::WriteAllBytes($changedFixturePath, $originalTrackedFixtureBytes)
$fixtureStatusAfterRestore = (& git -C $fixtureProjectRoot status --porcelain=v1) -join "`n"
Assert-True -Condition ([string]::IsNullOrWhiteSpace($fixtureStatusAfterRestore)) -Message 'source-change fixture was not restored cleanly'

Write-Output 'ISOLATED_PLAYTEST_RUNNER_CONTRACT_PASSED: checks=27'
}
finally {
    if ($null -ne $originalTrackedFixtureBytes -and -not [string]::IsNullOrWhiteSpace($changedFixturePath)) {
        [IO.File]::WriteAllBytes($changedFixturePath, $originalTrackedFixtureBytes)
    }
    if ($fixtureProjectRootCreated) {
        Remove-InvocationFixtureDirectory -FixtureDirectory $fixtureProjectRoot -InvocationName $fixtureProjectRootName -TempDirectory $systemTempPath
    }
    if ($testRootCreated) {
        Remove-InvocationFixtureDirectory -FixtureDirectory $testRoot -InvocationName $testRootName -TempDirectory $systemTempPath
    }
    Assert-True -Condition (-not [IO.Directory]::Exists($fixtureProjectRoot)) -Message "fixture project directory remained after cleanup: $fixtureProjectRoot"
    Assert-True -Condition (-not [IO.Directory]::Exists($testRoot)) -Message "fixture tool directory remained after cleanup: $testRoot"
}
