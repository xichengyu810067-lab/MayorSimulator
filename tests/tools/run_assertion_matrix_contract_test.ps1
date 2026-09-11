#requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param([Parameter(Mandatory = $true)][bool]$Condition, [Parameter(Mandatory = $true)][string]$Message)
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}

function New-MunicipalDiagnosticBlock {
    param(
        [Parameter(Mandatory = $true)][string]$Warning,
        [Parameter(Mandatory = $true)][string]$OverlayFunction,
        [Parameter(Mandatory = $true)][int]$OverlayLine,
        [Parameter(Mandatory = $true)][int]$TestLine
    )

    return @(
        "WARNING: $Warning"
        '   at: push_warning (core/variant/variant_utility.cpp:1033)'
        '   GDScript backtrace (most recent call first):'
        "       [0] $OverlayFunction (res://ui/shell/municipal_overlay.gd:$OverlayLine)"
        "       [1] _run (res://tests/integration/main_integration_test.gd:$TestLine)"
    ) -join "`r`n"
}

function Write-SyntheticGodot {
    param([Parameter(Mandatory = $true)][string]$FixtureRoot)

    $childPath = Join-Path $FixtureRoot 'synthetic-godot.cmd'
    $fixtureLogPath = Join-Path $FixtureRoot 'fixture.log'
    $child = @"
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
set "fixture=$fixtureLogPath"
if not "%logfile%"=="" copy /y "%fixture%" "%logfile%" > nul
type "%fixture%" 1>&2
echo Mayor Simulator main integration test passed.
exit /b 0
"@
    [IO.File]::WriteAllText($childPath, $child, [Text.UTF8Encoding]::new($false))
    return $childPath
}

function Invoke-ContractCase {
    param(
        [Parameter(Mandatory = $true)][string]$Runner,
        [Parameter(Mandatory = $true)][string]$FixtureRoot,
        [Parameter(Mandatory = $true)][string]$SyntheticGodot,
        [Parameter(Mandatory = $true)][string]$FixtureLog,
        [Parameter(Mandatory = $true)][string]$CaseName
    )

    [IO.File]::WriteAllText((Join-Path $FixtureRoot 'fixture.log'), $FixtureLog, [Text.UTF8Encoding]::new($false))
    $outputRoot = Join-Path $FixtureRoot ("output-$CaseName")
    & $Runner -GodotExe $SyntheticGodot -ManifestPath (Join-Path $FixtureRoot 'assertion_matrix.json') -OutputRoot $outputRoot -TestId main_integration | Out-Null
    $exitCode = $LASTEXITCODE
    $summary = Get-Content -LiteralPath (Join-Path $outputRoot 'summary.json') -Raw | ConvertFrom-Json
    return [pscustomobject]@{ exit_code = [int]$exitCode; summary = $summary }
}

$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$runner = Join-Path $projectRoot 'tools\run_assertion_matrix.ps1'
Assert-True -Condition (Test-Path -LiteralPath $runner -PathType Leaf) -Message "Runner not found: $runner"
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('mayor-assertion-matrix-contract-' + [Guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Path $fixtureRoot -ErrorAction Stop | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $fixtureRoot 'tests\integration') -Force -ErrorAction Stop | Out-Null
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'tests\integration\main_integration_test.gd'), '# synthetic fixture', [Text.UTF8Encoding]::new($false))
    $manifest = @{
        schema_version = 1
        name = 'assertion-matrix-contract-fixture'
        tests = @(@{
            id = 'main_integration'
            script = 'res://tests/integration/main_integration_test.gd'
            success_pattern = 'Mayor Simulator main integration test passed.'
            timeout_seconds = 240
        })
    } | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'assertion_matrix.json'), $manifest, [Text.UTF8Encoding]::new($false))
    $syntheticGodot = Write-SyntheticGodot -FixtureRoot $fixtureRoot

    $expectedBlocks = @(
        New-MunicipalDiagnosticBlock -Warning "MunicipalOverlay has no registered page named 'unknown_municipal_page'." -OverlayFunction 'open_page' -OverlayLine 179 -TestLine 497
        New-MunicipalDiagnosticBlock -Warning "MunicipalOverlay page 'released_navigation_test' is no longer valid." -OverlayFunction 'open_page' -OverlayLine 183 -TestLine 512
        New-MunicipalDiagnosticBlock -Warning "MunicipalOverlay skipped an unavailable history page named 'released_navigation_test'." -OverlayFunction '_handle_back' -OverlayLine 584 -TestLine 520
    )
    $positive = Invoke-ContractCase -Runner $runner -FixtureRoot $fixtureRoot -SyntheticGodot $syntheticGodot -FixtureLog ($expectedBlocks -join "`r`n") -CaseName 'positive'
    Assert-True -Condition ($positive.exit_code -eq 0 -and $positive.summary.results[0].product_clean) -Message ("exact main integration diagnostics were not accepted; exit={0}; reasons={1}" -f $positive.exit_code, (@($positive.summary.results[0].failure_reasons) -join '; '))

    $unknown = Invoke-ContractCase -Runner $runner -FixtureRoot $fixtureRoot -SyntheticGodot $syntheticGodot -FixtureLog (($expectedBlocks + 'WARNING: unexpected municipal diagnostic.') -join "`r`n") -CaseName 'unknown'
    Assert-True -Condition ($unknown.exit_code -ne 0 -and -not $unknown.summary.results[0].product_clean) -Message 'unknown diagnostic was accepted'

    $duplicate = Invoke-ContractCase -Runner $runner -FixtureRoot $fixtureRoot -SyntheticGodot $syntheticGodot -FixtureLog (($expectedBlocks + $expectedBlocks[0]) -join "`r`n") -CaseName 'duplicate'
    Assert-True -Condition ($duplicate.exit_code -ne 0 -and -not $duplicate.summary.results[0].product_clean) -Message 'duplicate expected diagnostic was accepted'

    $missing = Invoke-ContractCase -Runner $runner -FixtureRoot $fixtureRoot -SyntheticGodot $syntheticGodot -FixtureLog ($expectedBlocks[0..1] -join "`r`n") -CaseName 'missing'
    Assert-True -Condition ($missing.exit_code -ne 0 -and -not $missing.summary.results[0].product_clean) -Message 'missing expected diagnostic was accepted'

    $mismatchedBlock = New-MunicipalDiagnosticBlock -Warning "MunicipalOverlay has no registered page named 'unknown_municipal_page'." -OverlayFunction 'open_page' -OverlayLine 179 -TestLine 999
    $mismatch = Invoke-ContractCase -Runner $runner -FixtureRoot $fixtureRoot -SyntheticGodot $syntheticGodot -FixtureLog ((@($mismatchedBlock) + $expectedBlocks[1..2]) -join "`r`n") -CaseName 'backtrace-mismatch'
    Assert-True -Condition ($mismatch.exit_code -ne 0 -and -not $mismatch.summary.results[0].product_clean) -Message 'backtrace mismatch was accepted'

    Write-Output 'ASSERTION_MATRIX_EXPECTED_DIAGNOSTICS_CONTRACT_PASSED: checks=5'
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction Stop
    }
}
