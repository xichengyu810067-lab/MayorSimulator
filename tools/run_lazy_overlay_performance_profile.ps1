#requires -Version 7.4

[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$GodotExe,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$OutputRoot,
    [ValidateRange(50, 100)][int]$SampleIntervalMilliseconds = 75,
    [ValidateRange(50, 2000)][int]$HoldMilliseconds = 500,
    [ValidateRange(30, 300)][int]$WatchdogSeconds = 120,
    [ValidateRange(1, 30)][int]$MarkerTimeoutSeconds = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'source_fingerprint.ps1')
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$outputsRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot '.tmp\performance-profile-lazy-overlay'))
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)

function Get-TextHash {
    param([AllowEmptyString()][string]$Text)
    $hash = [Security.Cryptography.SHA256]::Create()
    try { return [Convert]::ToHexString($hash.ComputeHash([Text.UTF8Encoding]::new($false).GetBytes($Text))).ToLowerInvariant() }
    finally { $hash.Dispose() }
}

function Invoke-ProjectGit {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $result = @(& git -c "safe.directory=$projectRoot" -c core.quotePath=false -C $projectRoot @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "Git command failed: $($result -join ' ')" }
    return ($result -join "`n").Trim()
}

function Get-SourceIdentity {
    $status = Invoke-ProjectGit -Arguments @('status', '--porcelain=v1', '--untracked-files=all')
    return [ordered]@{
        branch = Invoke-ProjectGit -Arguments @('branch', '--show-current')
        head = Invoke-ProjectGit -Arguments @('rev-parse', 'HEAD')
        tree = Invoke-ProjectGit -Arguments @('rev-parse', 'HEAD^{tree}')
        status_sha256 = Get-TextHash $status
        source_fingerprint = Get-MayorSourceFingerprint -ProjectRoot $projectRoot
    }
}

function Assert-NewOutputRoot {
    param([Parameter(Mandatory)][string]$Candidate)
    if (-not (Test-MayorPathInside -Candidate $outputsRoot -Parent $projectRoot)) { throw 'Canonical profile root escaped the project worktree.' }
    if (-not (Test-MayorPathInside -Candidate $Candidate -Parent $outputsRoot)) {
        throw 'OutputRoot must be a fresh child of .tmp\\performance-profile-lazy-overlay; absolute and traversal escapes are rejected.'
    }
    $trimChars = [char[]]@([char]'\', [char]'/' )
    $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    if ($Candidate.TrimEnd($trimChars).Equals($outputsRoot.TrimEnd($trimChars), $comparison)) {
        throw 'OutputRoot must be a child directory, not the canonical profile root itself.'
    }
    if (Test-Path -LiteralPath $Candidate) { throw 'OutputRoot already exists; evidence is append-only.' }
    if (Test-Path -LiteralPath $outputsRoot -PathType Leaf) { throw 'Canonical profile root must be a directory.' }
    if (Test-Path -LiteralPath $outputsRoot) { $null = Assert-MayorNotReparsePoint -Path $outputsRoot -Label 'Canonical profile root' }
}

function Assert-ExistingPathChainSafe {
    param([Parameter(Mandatory)][string]$Candidate)
    $relative = [IO.Path]::GetRelativePath($projectRoot, $Candidate)
    $current = $projectRoot
    $null = Assert-MayorNotReparsePoint -Path $current -Label 'Project root'
    foreach ($part in @($relative -split '[\\/]+' | Where-Object { $_ -ne '' -and $_ -ne '.' })) {
        $current = Join-Path $current $part
        if (Test-Path -LiteralPath $current) { $null = Assert-MayorNotReparsePoint -Path $current -Label 'Output-root path component' }
    }
}

function Get-ExecutableIdentity {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Godot executable not found: $Path" }
    $item = Assert-MayorNotReparsePoint -Path $Path -Label 'Godot executable'
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $item.FullName
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.CreateNoWindow = $true
    $null = $info.ArgumentList.Add('--version')
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    try {
        if (-not $process.Start()) { throw 'Godot --version process did not start.' }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(15000)) {
            $process.Kill($true)
            $null = $process.WaitForExit(15000)
            throw 'Godot --version exceeded its 15-second deadline.'
        }
        if (-not $stdoutTask.Wait(5000) -or -not $stderrTask.Wait(5000)) { throw 'Godot --version output streams did not close.' }
        $version = ($stdoutTask.GetAwaiter().GetResult() + "`n" + $stderrTask.GetAwaiter().GetResult()).Trim()
        if ($process.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($version)) { throw 'Godot --version failed.' }
    }
    finally {
        $process.Dispose()
    }
    return [ordered]@{
        executable_path = $item.FullName
        executable_sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        version = $version
    }
}

function Get-EngineIdentity {
    param([Parameter(Mandatory)][string]$Path)
    $requested = Get-ExecutableIdentity -Path $Path
    $worker = $requested
    if ($requested.executable_path.EndsWith('_console.exe', [StringComparison]::OrdinalIgnoreCase)) {
        $standardCandidate = $requested.executable_path.Substring(0, $requested.executable_path.Length - '_console.exe'.Length) + '.exe'
        if (-not (Test-Path -LiteralPath $standardCandidate -PathType Leaf)) {
            throw 'Godot console launcher has no sibling engine executable; direct engine ownership cannot be proven.'
        }
        $worker = Get-ExecutableIdentity -Path $standardCandidate
        if ($worker.version -cne $requested.version) { throw 'Godot console launcher and engine executable versions differ.' }
    }
    return [ordered]@{
        requested_executable_path = $requested.executable_path
        requested_executable_sha256 = $requested.executable_sha256
        executable_path = $worker.executable_path
        executable_sha256 = $worker.executable_sha256
        version = $worker.version
    }
}

function Get-UserDataPath {
    param([Parameter(Mandatory)][string]$AppDataRoot)
    $projectText = Get-Content -LiteralPath (Join-Path $projectRoot 'project.godot') -Raw
    $name = [regex]::Match($projectText, '(?m)^config/name="([^"\r\n]+)"\s*$')
    if (-not $name.Success) { throw 'project.godot has no simple application name.' }
    return Join-Path (Join-Path $AppDataRoot 'Godot\app_userdata') ([regex]::Replace($name.Groups[1].Value, '[\\/:*?"<>|%]', '-'))
}

function Read-PhaseMarkers {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    $result = [Collections.Generic.List[object]]::new()
    foreach ($line in @(Get-Content -LiteralPath $Path)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $result.Add(($line | ConvertFrom-Json)) } catch { throw "Invalid phase marker JSON: $($_.Exception.Message)" }
    }
    return @($result)
}

function Assert-PhaseContract {
    param([Parameter(Mandatory)][object[]]$Markers)
    $expected = @('startup_ready', 'first_open_completed', 'validation_completed')
    if ($Markers.Count -ne $expected.Count) { throw "Expected exactly three phases, found $($Markers.Count)." }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $previous = [int64]-1
    for ($index = 0; $index -lt $expected.Count; $index++) {
        if ([int]$Markers[$index].schema_version -ne 1) { throw "Unexpected marker schema at index $index." }
        $phase = [string]$Markers[$index].phase
        if (-not $seen.Add($phase)) { throw "Duplicate profile phase: $phase" }
        if ($phase -cne $expected[$index]) { throw "Unexpected profile phase at index $index." }
        $ticks = [int64]$Markers[$index].monotonic_usec
        if ($ticks -le $previous) { throw 'Phase timestamps are not strictly monotonic.' }
        $previous = $ticks
    }
}

function Wait-PhaseMarkers {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][int]$TimeoutSeconds
    )
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $lastFailure = 'marker file is not visible'
    do {
        try {
            $markers = @(Read-PhaseMarkers -Path $Path)
            Assert-PhaseContract -Markers $markers
            return $markers
        }
        catch {
            $lastFailure = $_.Exception.Message
        }
        if ($clock.Elapsed.TotalSeconds -ge $TimeoutSeconds) { break }
        Start-Sleep -Milliseconds 25
    } while ($true)
    throw "Complete phase marker was not visible within $TimeoutSeconds seconds: $lastFailure"
}

function Get-LogAssessment {
    param([Parameter(Mandatory)][string[]]$LogPaths)
    $parts = [Collections.Generic.List[string]]::new()
    foreach ($path in $LogPaths) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $parts.Add([IO.File]::ReadAllText($path, [Text.Encoding]::UTF8))
        }
    }
    $plainLog = [regex]::Replace(($parts -join "`n"), "`e\[[0-?]*[ -/]*[@-~]", '')
    $certificatePattern = '(?m)^ERROR: Failed to read the root certificate store\.\r?\n\s*at: get_system_ca_certificates \(platform/windows/os_windows\.cpp:\d+\)\r?\n?'
    $environmentWarningCount = [regex]::Matches($plainLog, $certificatePattern).Count
    $productLog = [regex]::Replace($plainLog, $certificatePattern, '')
    $diagnostics = [Collections.Generic.List[string]]::new()
    foreach ($pattern in @('Leaked instance:', 'ObjectDB instances? (?:was|were) leaked at exit', 'resources? still in use at exit', 'Resource still in use:', 'Orphan StringName:', 'unclaimed string names at exit')) {
        if ([regex]::IsMatch($productLog, $pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            $diagnostics.Add("leak signature: $pattern")
        }
    }
    foreach ($match in [regex]::Matches($productLog, '(?im)^(?:SCRIPT ERROR|ERROR|WARNING):[^\r\n]*')) {
        $message = $match.Value.Trim()
        if (-not $diagnostics.Contains($message)) { $diagnostics.Add($message) }
    }
    return [ordered]@{
        environment_warning_count = $environmentWarningCount
        product_diagnostics = @($diagnostics)
    }
}

function Get-ProcessSample {
    param([Parameter(Mandatory)][Diagnostics.Process]$Process, [Parameter(Mandatory)][Diagnostics.Stopwatch]$Clock)
    $Process.Refresh()
    return [ordered]@{
        monotonic_milliseconds = [int64]$Clock.ElapsedMilliseconds
        utc = [DateTimeOffset]::UtcNow.ToString('o')
        pid = [int]$Process.Id
        working_set_bytes = [int64]$Process.WorkingSet64
        private_bytes = [int64]$Process.PrivateMemorySize64
        cpu_total_milliseconds = [int64]$Process.TotalProcessorTime.TotalMilliseconds
        memory_interpretation = 'per-process working-set and private-byte observations; not a RAM-total claim'
    }
}

function Wait-ProcessExecutablePath {
    param(
        [Parameter(Mandatory)][Diagnostics.Process]$Process,
        [Parameter(Mandatory)][string]$ExpectedPath,
        [ValidateRange(100, 5000)][int]$TimeoutMilliseconds = 5000
    )
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $lastFailure = 'process path is not visible'
    do {
        try {
            $Process.Refresh()
            $candidate = [string]$Process.Path
            if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                $actualPath = [IO.Path]::GetFullPath($candidate)
                if ($actualPath -cne $ExpectedPath) { throw 'Launched PID does not belong to the verified engine executable.' }
                return $actualPath
            }
        }
        catch {
            $lastFailure = $_.Exception.Message
        }
        if ($Process.HasExited -or $clock.ElapsedMilliseconds -ge $TimeoutMilliseconds) { break }
        Start-Sleep -Milliseconds 10
    } while ($true)
    throw "Launched PID executable identity was not proven within $TimeoutMilliseconds milliseconds: $lastFailure"
}

Assert-NewOutputRoot -Candidate $OutputRoot
Assert-ExistingPathChainSafe -Candidate $OutputRoot
$engine = Get-EngineIdentity -Path $GodotExe
$sourceBefore = Get-SourceIdentity
[IO.Directory]::CreateDirectory($outputsRoot) | Out-Null
[IO.Directory]::CreateDirectory($OutputRoot) | Out-Null
$null = Assert-MayorNotReparsePoint -Path $OutputRoot -Label 'Profile output root'

$runs = [Collections.Generic.List[object]]::new()
$failures = [Collections.Generic.List[string]]::new()
for ($runNumber = 1; $runNumber -le 3; $runNumber++) {
    $runRoot = Join-Path $OutputRoot ('run-{0:D2}' -f $runNumber)
    [IO.Directory]::CreateDirectory($runRoot) | Out-Null
    $appData = Join-Path $runRoot 'appdata'; $localAppData = Join-Path $runRoot 'localappdata'
    [IO.Directory]::CreateDirectory($appData) | Out-Null; [IO.Directory]::CreateDirectory($localAppData) | Out-Null
    $userData = Get-UserDataPath -AppDataRoot $appData
    [IO.Directory]::CreateDirectory($userData) | Out-Null
    $markerPath = Join-Path $userData 'mayor_simulator\tests\performance_profile_lazy_overlay_phases.jsonl'
    $stdoutPath = Join-Path $runRoot 'stdout.log'; $stderrPath = Join-Path $runRoot 'stderr.log'; $godotLogPath = Join-Path $runRoot 'godot.log'
    $samples = [Collections.Generic.List[object]]::new(); $process = $null; $clock = [Diagnostics.Stopwatch]::StartNew()
    $launchedExecutablePath = $null; $assessment = $null
    $gpuReason = 'GPU counter unavailable: stable per-process GPU attribution would add counter work that could violate the required 50-100ms sampling cadence.'
    try {
        $info = [Diagnostics.ProcessStartInfo]::new()
        $info.FileName = $engine.executable_path; $info.WorkingDirectory = $projectRoot; $info.UseShellExecute = $false
        $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true; $info.CreateNoWindow = $true
        foreach ($argument in @('--headless', '--path', $projectRoot, '--script', 'res://tests/integration/main_integration_test.gd', '--log-file', $godotLogPath, '--', '--performance-profile-lazy-overlay', "--performance-profile-hold-ms=$HoldMilliseconds")) { $null = $info.ArgumentList.Add($argument) }
        $info.Environment['APPDATA'] = $appData; $info.Environment['LOCALAPPDATA'] = $localAppData
        $process = [Diagnostics.Process]::new(); $process.StartInfo = $info
        if (-not $process.Start()) { throw 'Godot process did not start.' }
        $launchedExecutablePath = Wait-ProcessExecutablePath -Process $process -ExpectedPath $engine.executable_path
        $stdoutTask = $process.StandardOutput.ReadToEndAsync(); $stderrTask = $process.StandardError.ReadToEndAsync()
        while (-not $process.HasExited -and $clock.Elapsed.TotalSeconds -lt $WatchdogSeconds) { $samples.Add((Get-ProcessSample -Process $process -Clock $clock)); Start-Sleep -Milliseconds $SampleIntervalMilliseconds }
        if (-not $process.HasExited) {
            $process.Kill($true)
            if (-not $process.WaitForExit(15000)) { throw 'Timed-out Godot process tree did not exit within the cleanup deadline.' }
            throw "Godot exceeded watchdog of $WatchdogSeconds seconds."
        }
        if (-not $stdoutTask.Wait(15000) -or -not $stderrTask.Wait(15000)) { throw 'Godot output streams did not close.' }
        [IO.File]::WriteAllText($stdoutPath, $stdoutTask.GetAwaiter().GetResult(), [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText($stderrPath, $stderrTask.GetAwaiter().GetResult(), [Text.UTF8Encoding]::new($false))
        $markers = @(Wait-PhaseMarkers -Path $markerPath -TimeoutSeconds $MarkerTimeoutSeconds)
        $assessment = Get-LogAssessment -LogPaths @($stdoutPath, $stderrPath, $godotLogPath)
        if ($process.ExitCode -ne 0) { throw "Godot exited with $($process.ExitCode)." }
        if ($assessment.product_diagnostics.Count -gt 0) { throw "Godot emitted product diagnostics: $($assessment.product_diagnostics -join '; ')" }
        if ($samples.Count -lt 3) { throw 'Too few samples for a profile.' }
        $runs.Add([ordered]@{ run = $runNumber; status = if ($assessment.environment_warning_count -gt 0) { 'PASS_WITH_ENVIRONMENT_WARNING' } else { 'PASS' }; engine_pid = $process.Id; launched_executable_path = $launchedExecutablePath; engine = $engine; samples = @($samples); phases = @($markers); diagnostics = $assessment; gpu_counter = [ordered]@{ status = 'UNAVAILABLE'; reason = $gpuReason }; exit_code = $process.ExitCode })
    } catch {
        $failures.Add("run-${runNumber}: $($_.Exception.Message)")
        $runs.Add([ordered]@{ run = $runNumber; status = 'FAIL'; engine_pid = if ($null -eq $process) { $null } else { $process.Id }; launched_executable_path = $launchedExecutablePath; engine = $engine; samples = @($samples); diagnostics = $assessment; gpu_counter = [ordered]@{ status = 'UNAVAILABLE'; reason = $gpuReason }; error = $_.Exception.Message })
    } finally {
        if ($null -ne $process) {
            try {
                if (-not $process.HasExited) {
                    $process.Kill($true)
                    $null = $process.WaitForExit(15000)
                }
            } finally { $process.Dispose() }
        }
    }
}

$sourceAfter = Get-SourceIdentity
if ($sourceBefore.head -cne $sourceAfter.head -or $sourceBefore.tree -cne $sourceAfter.tree -or $sourceBefore.source_fingerprint.fingerprint_sha256 -cne $sourceAfter.source_fingerprint.fingerprint_sha256) { $failures.Add('Project source identity changed during profiling.') }
$summary = [ordered]@{
    schema_version = 1; suite = 'lazy-overlay-performance-profile'; status = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
    output_root = $OutputRoot; sampling = [ordered]@{ interval_milliseconds = $SampleIntervalMilliseconds; run_count = 3; cadence_contract = '50-100ms' }
    source_before = $sourceBefore; source_after = $sourceAfter; runs = @($runs); failures = @($failures)
    memory_claim_boundary = 'Deferred allocation is not represented as a RAM-total decrease; raw per-process working-set and private-byte samples are retained.'
}
[IO.File]::WriteAllText((Join-Path $OutputRoot 'summary.json'), ($summary | ConvertTo-Json -Depth 32) + "`n", [Text.UTF8Encoding]::new($false))
if ($failures.Count -gt 0) { foreach ($failure in $failures) { Write-Error $failure }; exit 1 }
Write-Output "LAZY_OVERLAY_PERFORMANCE_PROFILE_PASSED output=$OutputRoot runs=3 interval_ms=$SampleIntervalMilliseconds"
