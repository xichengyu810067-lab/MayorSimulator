[CmdletBinding()]
param(
    [string]$GodotExe = $(if ($env:GODOT_EXE) { $env:GODOT_EXE } else { 'Godot_v4.7-stable_win64_console.exe' }),
    [string]$OutputRoot = '',
    [string[]]$Phase = @(
        'temp_partial_write',
        'temp_verified',
        'backup_removed',
        'primary_rotated',
        'primary_installed'
    ),
    [int]$MarkerTimeoutSeconds = 30,
    [int]$WorkerTimeoutSeconds = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$workerScript = Join-Path $projectRoot 'tests\qa\save_os_kill_worker.gd'
$saveServiceScript = Join-Path $projectRoot 'scripts\core\save_service.gd'
$validPhases = @(
    'temp_partial_write',
    'temp_verified',
    'backup_removed',
    'primary_rotated',
    'primary_installed'
)

if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) {
    throw "Godot executable not found: $GodotExe"
}
$GodotWorkerExe = $GodotExe
if ($GodotExe.EndsWith('_console.exe', [StringComparison]::OrdinalIgnoreCase)) {
    $standardCandidate = $GodotExe.Substring(0, $GodotExe.Length - '_console.exe'.Length) + '.exe'
    if (Test-Path -LiteralPath $standardCandidate -PathType Leaf) {
        # Launch the engine process directly. The console binary is a Windows
        # wrapper that can outlive or orphan its actual writer child on an
        # early timeout before the lifecycle marker is available.
        $GodotWorkerExe = (Resolve-Path -LiteralPath $standardCandidate).Path
    }
}
$workerUsesDirectEngine = -not $GodotWorkerExe.EndsWith('_console.exe', [StringComparison]::OrdinalIgnoreCase)
$allowedWorkerExecutablePaths = @($GodotWorkerExe, $GodotExe) | ForEach-Object { [IO.Path]::GetFullPath($_) } | Sort-Object -Unique
if (-not (Test-Path -LiteralPath $workerScript -PathType Leaf)) {
    throw "OS-kill worker not found: $workerScript"
}
if ($MarkerTimeoutSeconds -lt 1 -or $WorkerTimeoutSeconds -lt 1) {
    throw 'Timeout values must be at least one second.'
}
if ($Phase.Count -lt 1) {
    throw 'At least one interruption phase is required.'
}
$seenPhases = @{}
foreach ($requestedPhase in $Phase) {
    if ($validPhases -notcontains $requestedPhase) {
        throw "Unsupported interruption phase: $requestedPhase"
    }
    if ($seenPhases.ContainsKey($requestedPhase)) {
        throw "Duplicate interruption phase: $requestedPhase"
    }
    $seenPhases[$requestedPhase] = $true
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $OutputRoot = Join-Path $projectRoot ".tmp\save-os-kill-qa\$timestamp"
}
elseif (-not [IO.Path]::IsPathRooted($OutputRoot)) {
    $OutputRoot = Join-Path $projectRoot $OutputRoot
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
if (Test-Path -LiteralPath $OutputRoot) {
    throw "OutputRoot already exists; use a new append-only evidence directory: $OutputRoot"
}
New-Item -ItemType Directory -Path $OutputRoot | Out-Null

$ansiPattern = "`e\[[0-?]*[ -/]*[@-~]"
$certificatePattern = '(?m)^ERROR: Failed to read the root certificate store\.\r?\n\s*at: get_system_ca_certificates \(platform/windows/os_windows\.cpp:\d+\)\r?\n?'
$diagnosticPattern = '(?im)^(?:SCRIPT ERROR|ERROR|WARNING):[^\r\n]*'
$leakPatterns = @(
    'Leaked instance:',
    'ObjectDB instances? (?:was|were) leaked at exit',
    'resources? still in use at exit',
    'Resource still in use:',
    'Orphan StringName:',
    'unclaimed string names at exit'
)

function Get-LogAssessment {
    param([string[]]$LogPaths)

    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($logPath in $LogPaths) {
        if (Test-Path -LiteralPath $logPath -PathType Leaf) {
            $parts.Add([IO.File]::ReadAllText($logPath, [Text.Encoding]::UTF8))
        }
    }
    $plainLog = [regex]::Replace(($parts -join "`n"), $ansiPattern, '')
    $environmentWarningCount = [regex]::Matches($plainLog, $certificatePattern).Count
    $productLog = [regex]::Replace($plainLog, $certificatePattern, '')
    $diagnostics = @([regex]::Matches($productLog, $diagnosticPattern) | ForEach-Object { $_.Value.Trim() })
    $leaks = [System.Collections.Generic.List[string]]::new()
    foreach ($leakPattern in $leakPatterns) {
        if ([regex]::IsMatch($productLog, $leakPattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            $leaks.Add($leakPattern)
        }
    }
    return [pscustomobject]@{
        environment_warning_count = $environmentWarningCount
        product_diagnostics = $diagnostics
        leak_signatures = @($leaks)
        product_clean = $diagnostics.Count -eq 0 -and $leaks.Count -eq 0
        combined_plain_log = $plainLog
    }
}

function Wait-WorkerLifecycleMarker {
    param(
        [Parameter(Mandatory)][string]$MarkerPath,
        [Parameter(Mandatory)][string]$Mode,
        [Parameter(Mandatory)][System.Diagnostics.Process]$Launcher,
        [Parameter(Mandatory)][datetime]$Deadline
    )

    while ((Get-Date) -lt $Deadline) {
        if (Test-Path -LiteralPath $MarkerPath -PathType Leaf) {
            try {
                $candidate = Get-Content -LiteralPath $MarkerPath -Raw | ConvertFrom-Json -ErrorAction Stop
                if ($candidate.schema_version -is [long] -and
                    [long]$candidate.schema_version -eq 1 -and
                    $candidate.mode -is [string] -and
                    [string]$candidate.mode -ceq $Mode -and
                    $candidate.process_id -is [long] -and
                    [long]$candidate.process_id -gt 0) {
                    return [int]$candidate.process_id
                }
            }
            catch {
                # The worker publishes atomically; retrying also keeps this
                # runner compatible with evidence from an older worker.
            }
        }
        if ($Launcher.HasExited) {
            throw "$Mode worker launcher exited before publishing its lifecycle marker (exit $($Launcher.ExitCode))."
        }
        Start-Sleep -Milliseconds 25
    }
    throw "$Mode worker did not publish its lifecycle marker before the deadline."
}

function Stop-WorkerProcessPair {
    param(
        [Parameter(Mandatory)][System.Diagnostics.Process]$Launcher,
        [int]$WriterProcessId = 0
    )

    $writerIds = [System.Collections.Generic.HashSet[int]]::new()
    $writerIdentityValid = $true
    if ($WriterProcessId -gt 0) {
        $null = $writerIds.Add($WriterProcessId)
    }
    # If the lifecycle marker could not be read, restrict fallback discovery
    # to direct children of this dedicated launcher. Never scan or terminate
    # unrelated Godot processes globally.
    try {
        foreach ($child in @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$($Launcher.Id)" -ErrorAction Stop)) {
            $childPath = [string]$child.ExecutablePath
            if (-not [string]::IsNullOrWhiteSpace($childPath) -and
                $allowedWorkerExecutablePaths -contains [IO.Path]::GetFullPath($childPath)) {
                $null = $writerIds.Add([int]$child.ProcessId)
            }
        }
    }
    catch {
        # The marker PID remains the primary authority. CIM is only a bounded
        # cleanup fallback for failures before marker publication.
    }

    foreach ($writerId in $writerIds) {
        $writer = Get-Process -Id $writerId -ErrorAction SilentlyContinue
        if ($null -ne $writer) {
            $writerPath = ''
            try { $writerPath = [IO.Path]::GetFullPath([string]$writer.Path) } catch { $writerPath = '' }
            if ([string]::IsNullOrWhiteSpace($writerPath) -or $allowedWorkerExecutablePaths -notcontains $writerPath) {
                $writerIdentityValid = $false
                continue
            }
            Stop-Process -Id $writerId -Force -ErrorAction SilentlyContinue
            $null = $writer.WaitForExit(10000)
        }
    }
    if (-not $Launcher.HasExited) {
        Stop-Process -Id $Launcher.Id -Force -ErrorAction SilentlyContinue
        $null = $Launcher.WaitForExit(10000)
    }

    $writerStopped = @($writerIds | Where-Object { $null -ne (Get-Process -Id $_ -ErrorAction SilentlyContinue) }).Count -eq 0
    $discoveryProven = $WriterProcessId -gt 0 -or $workerUsesDirectEngine
    return $discoveryProven -and $writerIdentityValid -and $writerStopped -and $Launcher.HasExited
}

function Invoke-GodotWorker {
    param(
        [string]$Mode,
        [string]$CasePhase,
        [string]$RunRoot,
        [string]$SuccessPattern
    )

    New-Item -ItemType Directory -Force -Path $RunRoot | Out-Null
    $stdoutPath = Join-Path $RunRoot 'stdout.log'
    $stderrPath = Join-Path $RunRoot 'stderr.log'
    $godotLogPath = Join-Path $RunRoot 'godot.log'
    $arguments = @(
        '--headless',
        '--verbose',
        '--path', ('"{0}"' -f $projectRoot),
        '--script', 'res://tests/qa/save_os_kill_worker.gd',
        '--log-file', ('"{0}"' -f $godotLogPath),
        '--',
        "--save-kill-qa-mode=$Mode"
    )
    if (-not [string]::IsNullOrWhiteSpace($CasePhase)) {
        $arguments += "--save-kill-qa-phase=$CasePhase"
    }

    $startedAt = Get-Date
    $process = Start-Process -FilePath $GodotWorkerExe -ArgumentList $arguments -NoNewWindow -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    $lifecycleMarkerPath = Join-Path $env:MAYOR_SAVE_KILL_QA_CONTROL_ROOT "worker-$Mode-marker.json"
    $writerProcessId = 0
    $workerProcessesStopped = $false
    try {
        $writerProcessId = Wait-WorkerLifecycleMarker `
            -MarkerPath $lifecycleMarkerPath `
            -Mode $Mode `
            -Launcher $process `
            -Deadline ((Get-Date).AddSeconds([Math]::Min(10, $WorkerTimeoutSeconds)))
    }
    catch {
        $null = Stop-WorkerProcessPair -Launcher $process -WriterProcessId $writerProcessId
        throw
    }
    $completed = $process.WaitForExit($WorkerTimeoutSeconds * 1000)
    if (-not $completed) {
        $workerProcessesStopped = Stop-WorkerProcessPair -Launcher $process -WriterProcessId $writerProcessId
    }
    else {
        $writer = Get-Process -Id $writerProcessId -ErrorAction SilentlyContinue
        if ($null -ne $writer) {
            $completed = $false
            $workerProcessesStopped = Stop-WorkerProcessPair -Launcher $process -WriterProcessId $writerProcessId
        }
        else {
            $workerProcessesStopped = $process.HasExited
        }
    }
    if ($process.HasExited) {
        # Flush redirected handles only after bounded cleanup has proved exit.
        $process.WaitForExit()
    }
    else {
        $completed = $false
        $workerProcessesStopped = $false
    }
    $exitCode = if ($completed) { [int]$process.ExitCode } else { -1 }
    $assessment = Get-LogAssessment -LogPaths @($stdoutPath, $stderrPath, $godotLogPath)
    $hasSuccessPattern = $assessment.combined_plain_log.IndexOf($SuccessPattern, [StringComparison]::Ordinal) -ge 0
    return [pscustomobject]@{
        mode = $Mode
        completed = $completed
        process_id = $process.Id
        launcher_process_id = $process.Id
        writer_process_id = $writerProcessId
        all_processes_stopped = $workerProcessesStopped
        exit_code = $exitCode
        duration_seconds = [Math]::Round(((Get-Date) - $startedAt).TotalSeconds, 3)
        success_marker = $hasSuccessPattern
        product_clean = $assessment.product_clean
        environment_warning_count = $assessment.environment_warning_count
        product_diagnostics = @($assessment.product_diagnostics)
        leak_signatures = @($assessment.leak_signatures)
        stdout_path = $stdoutPath
        stderr_path = $stderrPath
        godot_log_path = $godotLogPath
    }
}

function Assert-CleanWorker {
    param([object]$Run, [string]$Label)

    if (-not $Run.completed) {
        throw "$Label timed out."
    }
    if (-not $Run.all_processes_stopped) {
        throw "$Label left its launcher or writer process running."
    }
    if ($Run.exit_code -ne 0) {
        throw "$Label exited with code $($Run.exit_code)."
    }
    if (-not $Run.success_marker) {
        throw "$Label success marker is missing."
    }
    if (-not $Run.product_clean) {
        throw "$Label emitted product diagnostics or leak signatures."
    }
}

function Get-ArtifactRecord {
    param(
        [string]$SourcePath,
        [string]$EvidenceName,
        [string]$EvidenceDirectory
    )

    $record = [ordered]@{
        source_path = $SourcePath
        exists = Test-Path -LiteralPath $SourcePath -PathType Leaf
        size_bytes = 0
        sha256 = ''
        evidence_copy = ''
    }
    if ($record.exists) {
        $item = Get-Item -LiteralPath $SourcePath
        $destination = Join-Path $EvidenceDirectory $EvidenceName
        Copy-Item -LiteralPath $SourcePath -Destination $destination
        $record.size_bytes = [long]$item.Length
        $record.sha256 = (Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
        $record.evidence_copy = $destination
    }
    return [pscustomobject]$record
}

function Get-InterruptedTemporaryArtifactRecord {
    param(
        [Parameter(Mandatory)][object]$Marker,
        [Parameter(Mandatory)][string]$SavePath,
        [Parameter(Mandatory)][string]$AppDataRoot,
        [Parameter(Mandatory)][string]$EvidenceDirectory
    )

    $markerTemporaryPath = [string]$Marker.temporary_path
    if ([string]::IsNullOrWhiteSpace($markerTemporaryPath)) {
        throw 'Interruption marker does not declare the actual private temporary path.'
    }
    try {
        $canonicalSavePath = [IO.Path]::GetFullPath($SavePath)
        $canonicalAppDataRoot = [IO.Path]::GetFullPath($AppDataRoot).TrimEnd('\') + '\'
        $canonicalTemporaryPath = [IO.Path]::GetFullPath($markerTemporaryPath)
        if (Test-Path -LiteralPath $canonicalTemporaryPath -PathType Leaf) {
            $canonicalTemporaryPath = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $canonicalTemporaryPath).Path)
        }
        $canonicalSaveDirectory = [IO.Path]::GetDirectoryName($canonicalSavePath)
        $canonicalTemporaryDirectory = [IO.Path]::GetDirectoryName($canonicalTemporaryPath)
        $canonicalTemporaryParent = [IO.Path]::GetDirectoryName($canonicalTemporaryDirectory)
    }
    catch {
        throw "Interruption marker temporary path is not canonicalizable: $markerTemporaryPath"
    }

    $expectedDirectoryPrefix = ".$(Split-Path -Leaf $canonicalSavePath).save."
    if (
        -not $canonicalTemporaryPath.StartsWith($canonicalAppDataRoot, [StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals($canonicalTemporaryParent, $canonicalSaveDirectory, [StringComparison]::OrdinalIgnoreCase) -or
        -not (Split-Path -Leaf $canonicalTemporaryDirectory).StartsWith($expectedDirectoryPrefix, [StringComparison]::Ordinal) -or
        -not [string]::Equals((Split-Path -Leaf $canonicalTemporaryPath), 'payload.tmp', [StringComparison]::Ordinal)
    ) {
        throw "Interruption marker temporary path escapes the run private-save root: $canonicalTemporaryPath"
    }

    # A post-install interruption intentionally observes that the unique path
    # was consumed by the atomic rename. Every other phase must retain a real
    # private temporary file; neither case may fall back to a fixed .tmp name.
    if (-not (Test-Path -LiteralPath $canonicalTemporaryPath -PathType Leaf) -and $Marker.phase -cne 'primary_installed') {
        throw "Interruption marker temporary path does not exist before its expected consumption stage: $canonicalTemporaryPath"
    }
    $record = Get-ArtifactRecord -SourcePath $canonicalTemporaryPath -EvidenceName 'temporary.json' -EvidenceDirectory $EvidenceDirectory
    $record | Add-Member -NotePropertyName marker_path -NotePropertyValue $canonicalTemporaryPath
    $record | Add-Member -NotePropertyName marker_path_within_private_root -NotePropertyValue $true
    return $record
}

$hadAppData = Test-Path Env:APPDATA
$hadLocalAppData = Test-Path Env:LOCALAPPDATA
$hadControlRoot = Test-Path Env:MAYOR_SAVE_KILL_QA_CONTROL_ROOT
$originalAppData = $env:APPDATA
$originalLocalAppData = $env:LOCALAPPDATA
$originalControlRoot = $env:MAYOR_SAVE_KILL_QA_CONTROL_ROOT
$results = [System.Collections.Generic.List[object]]::new()
$startedAt = Get-Date

try {
    for ($index = 0; $index -lt $Phase.Count; $index++) {
        $casePhase = $Phase[$index]
        $caseRoot = Join-Path $OutputRoot ('{0:D2}-{1}' -f ($index + 1), $casePhase)
        $appDataRoot = Join-Path $caseRoot 'appdata'
        $localAppDataRoot = Join-Path $caseRoot 'localappdata'
        New-Item -ItemType Directory -Force -Path $caseRoot, $appDataRoot, $localAppDataRoot | Out-Null
        $env:APPDATA = $appDataRoot
        $env:LOCALAPPDATA = $localAppDataRoot
        $env:MAYOR_SAVE_KILL_QA_CONTROL_ROOT = $caseRoot

        Write-Output ('[{0}/{1}] RUN {2}' -f ($index + 1), $Phase.Count, $casePhase)
        $phaseStartedAt = Get-Date
        $errors = [System.Collections.Generic.List[string]]::new()
        $seedRun = $null
        $interruptRun = $null
        $verifyRun = $null
        $marker = $null
        $preRecoveryArtifacts = $null
        $verifyResult = $null
        $crashProcess = $null
        $writerProcessId = 0

        try {
            $seedRun = Invoke-GodotWorker -Mode 'seed' -CasePhase '' -RunRoot (Join-Path $caseRoot 'seed') -SuccessPattern 'SAVE_OS_KILL_SEED_OK'
            Assert-CleanWorker -Run $seedRun -Label "$casePhase seed worker"
            $seedResultPath = Join-Path $caseRoot 'seed-result.json'
            $seedResult = Get-Content -LiteralPath $seedResultPath -Raw | ConvertFrom-Json
            if (-not $seedResult.success) {
                throw "$casePhase seed result is not successful."
            }

            $interruptRoot = Join-Path $caseRoot 'interrupt'
            New-Item -ItemType Directory -Force -Path $interruptRoot | Out-Null
            $interruptStdout = Join-Path $interruptRoot 'stdout.log'
            $interruptStderr = Join-Path $interruptRoot 'stderr.log'
            $interruptGodotLog = Join-Path $interruptRoot 'godot.log'
            $interruptArguments = @(
                '--headless',
                '--verbose',
                '--path', ('"{0}"' -f $projectRoot),
                '--script', 'res://tests/qa/save_os_kill_worker.gd',
                '--log-file', ('"{0}"' -f $interruptGodotLog),
                '--',
                '--save-kill-qa-mode=crash',
                "--save-kill-qa-phase=$casePhase"
            )
            $interruptStartedAt = Get-Date
            $crashProcess = Start-Process -FilePath $GodotWorkerExe -ArgumentList $interruptArguments -NoNewWindow -PassThru -RedirectStandardOutput $interruptStdout -RedirectStandardError $interruptStderr
            $writerProcessId = Wait-WorkerLifecycleMarker `
                -MarkerPath (Join-Path $caseRoot 'worker-crash-marker.json') `
                -Mode 'crash' `
                -Launcher $crashProcess `
                -Deadline ((Get-Date).AddSeconds([Math]::Min(10, $MarkerTimeoutSeconds)))
            $markerPath = Join-Path $caseRoot 'interrupt-marker.json'
            $deadline = (Get-Date).AddSeconds($MarkerTimeoutSeconds)
            $marker = $null
            while ($null -eq $marker) {
                if ($crashProcess.HasExited) {
                    throw "$casePhase crash worker exited before publishing its interruption marker (exit $($crashProcess.ExitCode))."
                }
                if ((Get-Date) -ge $deadline) {
                    throw "$casePhase crash worker did not publish a complete interruption marker within $MarkerTimeoutSeconds seconds."
                }
                if (Test-Path -LiteralPath $markerPath -PathType Leaf) {
                    try {
                        $candidate = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json -ErrorAction Stop
                        $candidatePid = [int]$candidate.process_id
                        if ($candidate.schema_version -is [long] -and
                            [long]$candidate.schema_version -eq 1 -and
                            $candidate.phase -is [string] -and
                            [string]$candidate.phase -ceq $casePhase -and
                            $candidate.process_id -is [long] -and
                            $candidatePid -eq $writerProcessId -and
                            $candidate.temporary_path -is [string] -and
                            -not [string]::IsNullOrWhiteSpace([string]$candidate.temporary_path) -and
                            $candidate.ready_for_forced_termination -is [bool] -and
                            [bool]$candidate.ready_for_forced_termination) {
                            $marker = $candidate
                            continue
                        }
                    }
                    catch {
                        # A marker published by an older/non-atomic worker may
                        # briefly be unreadable. Keep the original deadline and
                        # retry instead of converting that race into a CI flake.
                    }
                }
                Start-Sleep -Milliseconds 25
            }
            $writerProcessId = [int]$marker.process_id
            $writerProcess = Get-Process -Id $writerProcessId -ErrorAction SilentlyContinue
            if ($null -eq $writerProcess) {
                throw "$casePhase marker writer PID $writerProcessId is not alive."
            }
            $writerPath = ''
            try { $writerPath = [IO.Path]::GetFullPath([string]$writerProcess.Path) } catch { $writerPath = '' }
            if ([string]::IsNullOrWhiteSpace($writerPath) -or $allowedWorkerExecutablePaths -notcontains $writerPath) {
                throw "$casePhase marker PID $writerProcessId does not belong to the configured Godot worker executable."
            }
            if ($workerUsesDirectEngine -and $writerProcessId -ne $crashProcess.Id) {
                throw "$casePhase direct-worker PID mismatch: launcher=$($crashProcess.Id) marker=$writerProcessId."
            }

            # This is the essential acceptance action: Windows terminates the
            # live Godot process while its SaveService call is paused at an
            # actual filesystem transition. The runner launches the standard
            # engine binary directly when it is available; the lifecycle and
            # interruption markers remain the authoritative writer identity.
            Stop-Process -Id $writerProcessId -Force -ErrorAction Stop
            $null = $writerProcess.WaitForExit(10000)
            if (-not $writerProcess.HasExited) {
                throw "$casePhase writer PID $writerProcessId remained alive after Stop-Process -Force."
            }
            $launcherStopped = $crashProcess.WaitForExit(10000)
            if (-not $launcherStopped) {
                throw "$casePhase console launcher remained alive after its writer was terminated."
            }
            $crashProcess.WaitForExit()
            $interruptAssessment = Get-LogAssessment -LogPaths @($interruptStdout, $interruptStderr, $interruptGodotLog)
            if (-not $interruptAssessment.product_clean) {
                throw "$casePhase interrupted worker emitted product diagnostics before termination."
            }
            $interruptRun = [pscustomobject]@{
                launcher_process_id = $crashProcess.Id
                writer_process_id = $writerProcessId
                marker_process_id = $writerProcessId
                writer_process_name = $writerProcess.ProcessName
                stop_process_force = $true
                writer_exited_after_stop = $writerProcess.HasExited
                launcher_exited_after_stop = $crashProcess.HasExited
                launcher_exit_code = [int]$crashProcess.ExitCode
                duration_seconds = [Math]::Round(((Get-Date) - $interruptStartedAt).TotalSeconds, 3)
                environment_warning_count = $interruptAssessment.environment_warning_count
                product_clean_before_termination = $interruptAssessment.product_clean
                stdout_path = $interruptStdout
                stderr_path = $interruptStderr
                godot_log_path = $interruptGodotLog
            }

            $savePath = [IO.Path]::GetFullPath([string]$seedResult.save_path)
            $appDataFull = [IO.Path]::GetFullPath($appDataRoot).TrimEnd('\') + '\'
            if (-not $savePath.StartsWith($appDataFull, [StringComparison]::OrdinalIgnoreCase)) {
                throw "$casePhase save path escaped its isolated APPDATA root: $savePath"
            }
            $artifactEvidenceRoot = Join-Path $caseRoot 'interrupted-artifacts'
            New-Item -ItemType Directory -Path $artifactEvidenceRoot | Out-Null
            $preRecoveryArtifacts = [pscustomobject]@{
                primary = Get-ArtifactRecord -SourcePath $savePath -EvidenceName 'primary.json' -EvidenceDirectory $artifactEvidenceRoot
                backup = Get-ArtifactRecord -SourcePath ($savePath + '.bak') -EvidenceName 'backup.json' -EvidenceDirectory $artifactEvidenceRoot
                temporary = Get-InterruptedTemporaryArtifactRecord -Marker $marker -SavePath $savePath -AppDataRoot $appDataRoot -EvidenceDirectory $artifactEvidenceRoot
                recovery_temporary = Get-ArtifactRecord -SourcePath ($savePath + '.recovery.tmp') -EvidenceName 'recovery-temporary.json' -EvidenceDirectory $artifactEvidenceRoot
            }

            $verifyRun = Invoke-GodotWorker -Mode 'verify' -CasePhase $casePhase -RunRoot (Join-Path $caseRoot 'verify') -SuccessPattern 'SAVE_OS_KILL_VERIFY_OK'
            Assert-CleanWorker -Run $verifyRun -Label "$casePhase verification worker"
            $verifyResultPath = Join-Path $caseRoot 'verify-result.json'
            $verifyResult = Get-Content -LiteralPath $verifyResultPath -Raw | ConvertFrom-Json
            if (-not $verifyResult.success -or @($verifyResult.failures).Count -ne 0) {
                throw "$casePhase semantic verification result is not successful."
            }
        }
        catch {
            $errors.Add($_.Exception.Message)
        }
        finally {
            if ($null -ne $crashProcess) {
                $cleanupStopped = Stop-WorkerProcessPair -Launcher $crashProcess -WriterProcessId $writerProcessId
                if (-not $cleanupStopped) {
                    $errors.Add("$casePhase cleanup could not confirm that the dedicated launcher/writer pair stopped.")
                }
            }
        }

        $passed = $errors.Count -eq 0
        $result = [pscustomobject]@{
            phase = $casePhase
            status = if ($passed) { 'PASS' } else { 'FAIL' }
            product_clean = $passed
            duration_seconds = [Math]::Round(((Get-Date) - $phaseStartedAt).TotalSeconds, 3)
            errors = @($errors)
            seed_run = $seedRun
            interruption_marker = $marker
            interruption_run = $interruptRun
            pre_recovery_artifacts = $preRecoveryArtifacts
            verification_run = $verifyRun
            semantic_verification = $verifyResult
            case_root = $caseRoot
        }
        $results.Add($result)
        Write-Output ('[{0}/{1}] {2} {3} ({4}s)' -f ($index + 1), $Phase.Count, $result.status, $casePhase, $result.duration_seconds)
    }
}
finally {
    if ($hadAppData) { $env:APPDATA = $originalAppData } else { Remove-Item Env:APPDATA -ErrorAction SilentlyContinue }
    if ($hadLocalAppData) { $env:LOCALAPPDATA = $originalLocalAppData } else { Remove-Item Env:LOCALAPPDATA -ErrorAction SilentlyContinue }
    if ($hadControlRoot) { $env:MAYOR_SAVE_KILL_QA_CONTROL_ROOT = $originalControlRoot } else { Remove-Item Env:MAYOR_SAVE_KILL_QA_CONTROL_ROOT -ErrorAction SilentlyContinue }
}

$finishedAt = Get-Date
$passedCount = @($results | Where-Object { $_.product_clean }).Count
$failedCount = $results.Count - $passedCount
$forcedTerminationCount = @($results | Where-Object { $null -ne $_.interruption_run -and $_.interruption_run.stop_process_force }).Count
$semanticCheckTotal = 0
foreach ($result in $results) {
    if ($null -ne $result.semantic_verification) {
        $semanticCheckTotal += [int]$result.semantic_verification.checks
    }
}
$allProcessesStopped = $results.Count -eq $Phase.Count -and @($results | Where-Object {
    $null -eq $_.seed_run -or
    -not $_.seed_run.all_processes_stopped -or
    $null -eq $_.interruption_run -or
    -not $_.interruption_run.writer_exited_after_stop -or
    -not $_.interruption_run.launcher_exited_after_stop -or
    $null -eq $_.verification_run -or
    -not $_.verification_run.all_processes_stopped
}).Count -eq 0
$godotVersion = (& $GodotExe --version | Select-Object -First 1).Trim()
$summary = [pscustomobject]@{
    schema_version = 1
    suite = 'mayor-simulator-save-os-kill-qa'
    started_at = $startedAt.ToString('o')
    finished_at = $finishedAt.ToString('o')
    duration_seconds = [Math]::Round(($finishedAt - $startedAt).TotalSeconds, 3)
    project_root = $projectRoot
    output_root = $OutputRoot
    output_root_policy = 'refuse_existing_directory'
    godot_executable = $GodotExe
    godot_worker_executable = $GodotWorkerExe
    godot_version = $godotVersion
    runner_sha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
    worker_sha256 = (Get-FileHash -LiteralPath $workerScript -Algorithm SHA256).Hash.ToLowerInvariant()
    save_service_sha256 = (Get-FileHash -LiteralPath $saveServiceScript -Algorithm SHA256).Hash.ToLowerInvariant()
    required_phases = $validPhases
    requested_phase_count = $Phase.Count
    result_count = $results.Count
    product_clean_count = $passedCount
    passed_count = $passedCount
    failed_count = $failedCount
    forced_termination_count = $forcedTerminationCount
    semantic_check_total = $semanticCheckTotal
    all_processes_stopped = $allProcessesStopped
    results = @($results)
}
$summaryPath = Join-Path $OutputRoot 'summary.json'
$summary | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

$markdown = [System.Collections.Generic.List[string]]::new()
$markdown.Add('# Save OS-kill QA summary')
$markdown.Add('')
$markdown.Add("- Godot: $godotVersion")
$markdown.Add("- Forced-termination phases: $($Phase.Count)")
$markdown.Add("- Passed: $passedCount")
$markdown.Add("- Failed: $failedCount")
$markdown.Add("- All interrupted processes stopped: $($summary.all_processes_stopped)")
$markdown.Add("- Duration: $($summary.duration_seconds) seconds")
$markdown.Add('')
$markdown.Add('| Phase | Status | Stop-Process -Force | Semantic checks | Load source |')
$markdown.Add('|---|---:|---:|---:|---:|')
foreach ($result in $results) {
    $forced = if ($null -ne $result.interruption_run) { $result.interruption_run.stop_process_force } else { $false }
    $checks = if ($null -ne $result.semantic_verification) { $result.semantic_verification.checks } else { 0 }
    $source = if ($null -ne $result.semantic_verification) { $result.semantic_verification.load_source } else { '' }
    $markdown.Add("| $($result.phase) | $($result.status) | $forced | $checks | $source |")
    foreach ($failure in $result.errors) {
        $markdown.Add("|  | failure: $($failure.Replace('|', '\|')) |  |  |  |")
    }
}
$markdown | Set-Content -LiteralPath (Join-Path $OutputRoot 'SUMMARY.md') -Encoding UTF8

$summarySha256 = (Get-FileHash -LiteralPath $summaryPath -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Output "Save OS-kill QA complete: passed=$passedCount failed=$failedCount summary=$summaryPath sha256=$summarySha256"
if ($failedCount -gt 0) {
    exit 1
}
exit 0
