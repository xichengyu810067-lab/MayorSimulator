#requires -Version 7.4
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$runner = Get-Content -LiteralPath (Join-Path $projectRoot 'tools\run_lazy_overlay_performance_profile.ps1') -Raw
$integration = Get-Content -LiteralPath (Join-Path $projectRoot 'tests\integration\main_integration_test.gd') -Raw

function Assert-Contains {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -notmatch $Pattern) { throw $Message }
}
function Assert-NotContains {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -match $Pattern) { throw $Message }
}

Assert-Contains $runner 'ValidateRange\(50, 100\)' 'Sampling interval is not constrained to 50-100ms.'
Assert-Contains $runner 'performance-profile-lazy-overlay' 'Runner does not use a canonical .tmp profile root.'
Assert-Contains $runner 'Test-MayorPathInside -Candidate \$Candidate -Parent \$outputsRoot' 'Runner lacks output-root containment validation.'
Assert-Contains $runner 'OutputRoot must be a child directory, not the canonical profile root itself.' 'Runner allows the fixed profile root to be reused as evidence output.'
Assert-Contains $runner '(?s)EndsWith\(''_console\.exe''.*?\$standardCandidate.*?requested_executable_sha256.*?executable_sha256' 'Runner does not resolve and hash both the requested launcher and actual engine executable.'
Assert-Contains $runner '\$launchedExecutablePath = Wait-ProcessExecutablePath -Process \$process -ExpectedPath \$engine\.executable_path' 'Runner does not use a bounded launched-PID identity handshake against the verified engine executable.'
Assert-Contains $runner '\$process\.Kill\(\$true\)' 'Runner lacks exception-path process-tree cleanup.'
Assert-Contains $runner 'source_fingerprint' 'Runner does not bind a project source fingerprint.'
Assert-Contains $runner '(?s)@\(''startup_ready'', ''first_open_completed'', ''validation_completed''\).*?function Wait-PhaseMarkers.*?mayor_simulator\\tests\\performance_profile_lazy_overlay_phases\.jsonl.*?Wait-PhaseMarkers -Path \$markerPath -TimeoutSeconds \$MarkerTimeoutSeconds' 'Runner does not enforce ordered phases and bounded marker visibility at the explicit user-data path.'
Assert-Contains $runner 'ObjectDB instances\? \(\?:was\|were\) leaked at exit' 'Runner does not fail closed on ObjectDB leak diagnostics.'
Assert-Contains $runner 'GPU counter unavailable' 'Runner does not retain a concrete GPU-unavailable reason.'
Assert-Contains $runner 'not a RAM-total claim' 'Runner does not state its RAM claim boundary.'
Assert-Contains $integration '--performance-profile-lazy-overlay' 'Integration test has no explicit performance-profile opt-in.'
Assert-Contains $integration 'if performance_profile_only:\s*\r?\n\s*_emit_performance_profile_phase\("startup_ready"\)' 'Startup marker is not guarded by explicit opt-in.'
Assert-Contains $integration 'if performance_profile_only:\s*\r?\n\s*_emit_performance_profile_phase\("first_open_completed"\)' 'First-open marker is not guarded by explicit opt-in.'
Assert-Contains $integration '--performance-profile-hold-ms=' 'Profile hold is not opt-in instrumentation.'
Assert-Contains $integration 'await TestCleanup\.finish\(self, \[main\], 1 if _failed else 0\)' 'Profile mode bypasses the leak-clean fixture teardown.'
Assert-NotContains $integration 'RAM_MUNICIPAL_PROFILE_PHASE|ram-municipal-profile' 'Integration test retains a legacy RAM profile marker or switch.'

Write-Output 'LAZY_OVERLAY_PERFORMANCE_PROFILE_CONTRACT_PASSED: checks=18'
