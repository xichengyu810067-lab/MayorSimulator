#requires -Version 7.4

[CmdletBinding()]
param(
    [string]$GodotExe = $(if ($env:GODOT_EXE) { $env:GODOT_EXE } else { 'Godot_v4.7-stable_win64_console.exe' }),
    [string]$OutputRoot = '',
    [int]$WatchdogSeconds = 600,
    [int]$SampleIntervalMilliseconds = 250,
    [switch]$PreflightOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'source_fingerprint.ps1')

$expectedHead = '31e323a7e7658134559495f844dd0fef642a2cce'
$expectedSdk = '60ab9fcae0160661377f9a550327e085e0d9a31c'
$treePeakLimit = [int64](4GB)
$saveByteLimit = [int64](512MB)

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $OutputRoot = Join-Path $projectRoot ".tmp\population-200k-capacity\$timestamp"
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
if (-not (Test-MayorPathInside -Candidate $OutputRoot -Parent $projectRoot)) {
    throw "OutputRoot must stay inside the authorized project root: $OutputRoot"
}
if (Test-Path -LiteralPath $OutputRoot) {
    throw "OutputRoot already exists; benchmark evidence is append-only: $OutputRoot"
}

$utf8NoBom = [Text.UTF8Encoding]::new($false)

function Write-NewUtf8File {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Text
    )
    if (Test-Path -LiteralPath $Path) {
        throw "Refusing to overwrite append-only evidence: $Path"
    }
    [IO.File]::WriteAllText($Path, $Text, $utf8NoBom)
}

function Write-NewJsonFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Value,
        [int]$Depth = 20
    )
    Write-NewUtf8File -Path $Path -Text (($Value | ConvertTo-Json -Depth $Depth) + "`n")
}

function Invoke-ProjectGit {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    $output = & git -c "safe.directory=$projectRoot" -C $projectRoot @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed: $($output -join [Environment]::NewLine)"
    }
    return @($output)
}

function Invoke-SdkGit {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    $sdkRoot = Join-Path $projectRoot 'sdk'
    $output = & git -c "safe.directory=$sdkRoot" -C $sdkRoot @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "sdk git $($Arguments -join ' ') failed: $($output -join [Environment]::NewLine)"
    }
    return @($output)
}

function Get-SourceSnapshot {
    param([Parameter(Mandatory)][string]$Label)

    $fingerprint = Get-MayorSourceFingerprint -ProjectRoot $projectRoot
    $tracked = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $untracked = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($path in @(Invoke-ProjectGit ls-files)) {
        if (-not [string]::IsNullOrEmpty([string]$path)) { $null = $tracked.Add(([string]$path).Replace('\', '/')) }
    }
    foreach ($path in @(Invoke-ProjectGit ls-files --others --exclude-standard)) {
        if (-not [string]::IsNullOrEmpty([string]$path)) { $null = $untracked.Add(([string]$path).Replace('\', '/')) }
    }
    $entries = foreach ($entry in @($fingerprint.entries)) {
        $path = [string]$entry.path
        $tracking = if ($tracked.Contains($path)) { 'tracked' } elseif ($untracked.Contains($path)) { 'untracked' } else { 'other' }
        [pscustomobject][ordered]@{
            path = $path
            tracking = $tracking
            bytes = [int64]$entry.bytes
            sha256 = [string]$entry.sha256
        }
    }
    $statusLines = @(Invoke-ProjectGit status --porcelain=v2 --untracked-files=all)
    $sdkStatusLines = @(Invoke-SdkGit status --porcelain=v2 --untracked-files=all)
    $head = [string](@(Invoke-ProjectGit rev-parse HEAD)[0])
    $tree = [string](@(Invoke-ProjectGit rev-parse 'HEAD^{tree}')[0])
    $branch = [string](@(Invoke-ProjectGit branch --show-current)[0])
    $gitlinkFields = ([string](@(Invoke-ProjectGit ls-tree HEAD sdk)[0])) -split '\s+'
    $sdkGitlink = [string]$gitlinkFields[2]
    $sdkHead = [string](@(Invoke-SdkGit rev-parse HEAD)[0])
    return [pscustomobject][ordered]@{
        status = 'OK'
        label = $Label
        captured_at_utc = [DateTimeOffset]::UtcNow.ToString('o')
        project_root = $projectRoot
        branch = $branch
        head = $head
        head_tree = $tree
        sdk_gitlink = $sdkGitlink
        sdk_head = $sdkHead
        status_lines = $statusLines
        sdk_status_lines = $sdkStatusLines
        source = [pscustomobject][ordered]@{
            schema_version = [int]$fingerprint.schema_version
            algorithm = [string]$fingerprint.algorithm
            file_count = [int]$fingerprint.file_count
            total_bytes = [int64]$fingerprint.total_bytes
            fingerprint_sha256 = [string]$fingerprint.fingerprint_sha256
            tracked_count = @($entries | Where-Object tracking -eq 'tracked').Count
            untracked_count = @($entries | Where-Object tracking -eq 'untracked').Count
            other_count = @($entries | Where-Object tracking -eq 'other').Count
            entries = @($entries)
        }
    }
}

function Get-FileEvidence {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject][ordered]@{ path = $Path; exists = $false; bytes = 0; sha256 = '' }
    }
    $item = Get-Item -LiteralPath $Path
    return [pscustomobject][ordered]@{
        path = $item.FullName
        exists = $true
        bytes = [int64]$item.Length
        sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

function Get-LatestProgressMarker {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $last = Get-Content -LiteralPath $Path -Tail 1 -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace([string]$last)) { return $null }
    try { return ([string]$last | ConvertFrom-Json) } catch { return $null }
}

function Get-ProcessInventory {
    return @(Get-CimInstance Win32_Process -ErrorAction Stop | Select-Object ProcessId, ParentProcessId, Name, CreationDate, WorkingSetSize)
}

function Add-OwnedDescendants {
    param(
        [Parameter(Mandatory)][object[]]$Inventory,
        [Parameter(Mandatory)][Collections.Generic.Dictionary[int, object]]$Owned
    )
    $added = $true
    while ($added) {
        $added = $false
        foreach ($candidate in $Inventory) {
            $candidatePid = [int]$candidate.ProcessId
            $parentPid = [int]$candidate.ParentProcessId
            if ($candidatePid -le 0 -or $Owned.ContainsKey($candidatePid) -or -not $Owned.ContainsKey($parentPid)) { continue }
            $parent = $Owned[$parentPid]
            $Owned[$candidatePid] = [pscustomobject][ordered]@{
                pid = $candidatePid
                parent_pid = $parentPid
                depth = [int]$parent.depth + 1
                name = [string]$candidate.Name
                creation_utc = ([DateTime]$candidate.CreationDate).ToUniversalTime().ToString('o')
            }
            $added = $true
        }
    }
}

function Test-OwnedIdentityAlive {
    param(
        [Parameter(Mandatory)]$Identity,
        [Parameter(Mandatory)][object[]]$Inventory
    )
    $candidate = @($Inventory | Where-Object { [int]$_.ProcessId -eq [int]$Identity.pid }) | Select-Object -First 1
    if ($null -eq $candidate) { return $false }
    return ([DateTime]$candidate.CreationDate).ToUniversalTime().ToString('o') -ceq [string]$Identity.creation_utc
}

[IO.Directory]::CreateDirectory($OutputRoot) | Out-Null
$null = Assert-MayorNotReparsePoint -Path $OutputRoot -Label 'Benchmark output root'
$appDataRoot = Join-Path $OutputRoot 'appdata'
$localAppDataRoot = Join-Path $OutputRoot 'localappdata'
[IO.Directory]::CreateDirectory($appDataRoot) | Out-Null
[IO.Directory]::CreateDirectory($localAppDataRoot) | Out-Null

$beforePath = Join-Path $OutputRoot 'source-before.json'
$afterPath = Join-Path $OutputRoot 'source-after.json'
$manifestPath = Join-Path $OutputRoot 'manifest.json'
$summaryPath = Join-Path $OutputRoot 'summary.json'
$summaryMarkdownPath = Join-Path $OutputRoot 'SUMMARY.md'
$stdoutPath = Join-Path $OutputRoot 'stdout.log'
$stderrPath = Join-Path $OutputRoot 'stderr.log'
$godotLogPath = Join-Path $OutputRoot 'godot.log'
$progressPath = Join-Path $OutputRoot 'progress.jsonl'
$runnerProgressPath = Join-Path $OutputRoot 'runner-progress.jsonl'
$processSamplesPath = Join-Path $OutputRoot 'process-samples.jsonl'
$benchmarkResultPath = Join-Path $OutputRoot 'benchmark-result.json'
$preflightPath = Join-Path $OutputRoot 'preflight.json'
$runnerExitPath = Join-Path $OutputRoot 'runner-exit.json'

$runnerWriter = [IO.StreamWriter]::new($runnerProgressPath, $false, $utf8NoBom)
$runnerWriter.AutoFlush = $true
$sampleWriter = $null
$process = $null
$owned = [Collections.Generic.Dictionary[int, object]]::new()
$failures = [Collections.Generic.List[string]]::new()
$treePeak = [int64]0
$treePeakAtUtc = ''
$timedOut = $false
$launchError = $null
$godotExitCode = $null
$productLaunched = $false
$ownedRootBound = $false
$processSampleCount = 0
$samplingFailure = ''
$cleanupAttempted = $false
$cleanupMethod = 'none'
$cleanupVerificationAvailable = $false
$cleanupVerified = $false
$residualOwned = @()
$cleanupReason = 'Product process was not launched; cleanup and residue are not applicable.'
$startedAt = [DateTimeOffset]::UtcNow
$before = [pscustomobject][ordered]@{ status = 'NOT_CAPTURED'; label = 'before'; reason = 'Source-before capture has not run.' }
$after = [pscustomobject][ordered]@{ status = 'NOT_CAPTURED'; label = 'after'; reason = 'Source-after capture has not run.' }
$preflight = [pscustomobject][ordered]@{
    schema_version = 1
    status = 'NOT_RUN'
    started_at_utc = ''
    finished_at_utc = ''
    cim_available = $false
    inventory_count = 0
    runner_pid_bound = $false
    reason = 'CIM/Win32_Process preflight has not run.'
    product_launch_allowed = $false
    product_launched = $false
    preflight_only = [bool]$PreflightOnly
}
$cimPreflightPassed = $false

function New-SourceSnapshotFailure {
    param([Parameter(Mandatory)][string]$Label, [Parameter(Mandatory)][string]$Reason)
    return [pscustomobject][ordered]@{
        status = 'ERROR'
        label = $Label
        captured_at_utc = [DateTimeOffset]::UtcNow.ToString('o')
        project_root = $projectRoot
        reason = $Reason
    }
}

function Get-OwnedTreeSample {
    param(
        [Parameter(Mandatory)][object[]]$Inventory,
        [Parameter(Mandatory)][Collections.Generic.Dictionary[int, object]]$Owned,
        [Parameter(Mandatory)][DateTimeOffset]$CapturedAt
    )
    Add-OwnedDescendants -Inventory $Inventory -Owned $Owned
    $members = [Collections.Generic.List[object]]::new()
    $treeWorkingSet = [int64]0
    foreach ($identity in @($Owned.Values | Sort-Object pid)) {
        $candidate = @($Inventory | Where-Object { [int]$_.ProcessId -eq [int]$identity.pid }) | Select-Object -First 1
        if ($null -eq $candidate) { continue }
        if (([DateTime]$candidate.CreationDate).ToUniversalTime().ToString('o') -cne [string]$identity.creation_utc) { continue }
        $workingSet = [int64]$candidate.WorkingSetSize
        $treeWorkingSet += $workingSet
        $members.Add([ordered]@{
            pid = [int]$identity.pid
            parent_pid = [int]$identity.parent_pid
            name = [string]$identity.name
            creation_utc = [string]$identity.creation_utc
            working_set_bytes = $workingSet
        })
    }
    if ($members.Count -eq 0) {
        throw 'Owned process-tree sample contained no live process identities.'
    }
    return [pscustomobject][ordered]@{
        utc = $CapturedAt.ToString('o')
        tree_working_set_bytes = $treeWorkingSet
        processes = @($members)
    }
}

try {
    $runnerWriter.WriteLine(([ordered]@{ utc = $startedAt.ToString('o'); phase = 'source_before'; status = 'start' } | ConvertTo-Json -Compress))
    try { $before = Get-SourceSnapshot -Label 'before' } catch { $before = New-SourceSnapshotFailure -Label 'before' -Reason $_.Exception.Message; $failures.Add("Source-before capture failed: $($_.Exception.Message)") }
    Write-NewJsonFile -Path $beforePath -Value $before -Depth 100
    $runnerWriter.WriteLine(([ordered]@{ utc = [DateTimeOffset]::UtcNow.ToString('o'); phase = 'source_before'; status = [string]$before.status } | ConvertTo-Json -Compress))

    if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) { $failures.Add("Godot executable not found: $GodotExe") }
    if ($WatchdogSeconds -ne 600) { $failures.Add('The formal capacity watchdog is fixed at 600 seconds.') }
    if ($SampleIntervalMilliseconds -lt 100 -or $SampleIntervalMilliseconds -gt 1000) { $failures.Add('SampleIntervalMilliseconds must stay between 100 and 1000.') }
    if ([string]$before.status -ceq 'OK' -and ($before.branch -cne 'main' -or $before.head -cne $expectedHead -or $before.sdk_gitlink -cne $expectedSdk -or $before.sdk_head -cne $expectedSdk)) {
        $failures.Add("Formal benchmark baseline mismatch: branch=$($before.branch) head=$($before.head) sdk_gitlink=$($before.sdk_gitlink) sdk_head=$($before.sdk_head)")
    }

    $preflightStartedAt = [DateTimeOffset]::UtcNow
    $runnerWriter.WriteLine(([ordered]@{ utc = $preflightStartedAt.ToString('o'); phase = 'cim_preflight'; status = 'start' } | ConvertTo-Json -Compress))
    try {
        $preflightInventory = Get-ProcessInventory
        if ($preflightInventory.Count -eq 0) { throw 'Win32_Process inventory was empty.' }
        $selfRecord = @($preflightInventory | Where-Object { [int]$_.ProcessId -eq [int]$PID }) | Select-Object -First 1
        if ($null -eq $selfRecord) { throw "Win32_Process inventory did not contain the runner PID $PID." }
        if ($null -eq $selfRecord.CreationDate -or $null -eq $selfRecord.WorkingSetSize) { throw 'Win32_Process inventory omitted required identity or working-set fields.' }
        $cimPreflightPassed = $true
        $preflight = [pscustomobject][ordered]@{
            schema_version = 1
            status = 'PASS'
            started_at_utc = $preflightStartedAt.ToString('o')
            finished_at_utc = [DateTimeOffset]::UtcNow.ToString('o')
            cim_available = $true
            inventory_count = $preflightInventory.Count
            runner_pid_bound = $true
            reason = ''
            product_launch_allowed = $true
            product_launched = $false
            preflight_only = [bool]$PreflightOnly
        }
        if ($failures.Count -gt 0) {
            $preflight.status = 'FAIL'
            $preflight.reason = "Launch prerequisite validation failed: $(@($failures) -join ' | ')"
            $preflight.product_launch_allowed = $false
        }
    }
    catch {
        $preflightReason = $_.Exception.Message
        $failures.Add("CIM/Win32_Process preflight failed closed: $preflightReason")
        $preflight = [pscustomobject][ordered]@{
            schema_version = 1
            status = 'FAIL'
            started_at_utc = $preflightStartedAt.ToString('o')
            finished_at_utc = [DateTimeOffset]::UtcNow.ToString('o')
            cim_available = $false
            inventory_count = 0
            runner_pid_bound = $false
            reason = $preflightReason
            product_launch_allowed = $false
            product_launched = $false
            preflight_only = [bool]$PreflightOnly
        }
    }
    Write-NewJsonFile -Path $preflightPath -Value $preflight -Depth 20
    $runnerWriter.WriteLine(([ordered]@{ utc = [DateTimeOffset]::UtcNow.ToString('o'); phase = 'cim_preflight'; status = [string]$preflight.status; reason = [string]$preflight.reason } | ConvertTo-Json -Compress))

    if (-not $PreflightOnly -and $failures.Count -eq 0 -and $cimPreflightPassed) {
        $runnerWriter.WriteLine(([ordered]@{ utc = [DateTimeOffset]::UtcNow.ToString('o'); phase = 'launch'; status = 'start' } | ConvertTo-Json -Compress))
        $arguments = @(
            '--headless', '--verbose', '--path', ('"{0}"' -f $projectRoot),
            '--script', 'res://tests/performance/population_200k_capacity_benchmark.gd',
            '--log-file', ('"{0}"' -f $godotLogPath), '--',
            ('"--population-200k-output-root={0}"' -f $OutputRoot)
        )
        $process = Start-Process -FilePath $GodotExe -ArgumentList $arguments -NoNewWindow -PassThru `
            -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath `
            -Environment @{ APPDATA = $appDataRoot; LOCALAPPDATA = $localAppDataRoot }
        $productLaunched = $true
        $process.Refresh()
        $launchInventory = Get-ProcessInventory
        $rootCandidate = @($launchInventory | Where-Object { [int]$_.ProcessId -eq [int]$process.Id }) | Select-Object -First 1
        if ($null -eq $rootCandidate) { throw "Unable to bind launched root PID $($process.Id) to Win32_Process." }
        $owned[[int]$process.Id] = [pscustomobject][ordered]@{
            pid = [int]$process.Id
            parent_pid = 0
            depth = 0
            name = [string]$rootCandidate.Name
            creation_utc = ([DateTime]$rootCandidate.CreationDate).ToUniversalTime().ToString('o')
        }
        $ownedRootBound = $true
        $sampleWriter = [IO.StreamWriter]::new($processSamplesPath, $false, $utf8NoBom)
        $sampleWriter.AutoFlush = $true
        $firstSample = Get-OwnedTreeSample -Inventory $launchInventory -Owned $owned -CapturedAt ([DateTimeOffset]::UtcNow)
        $sampleWriter.WriteLine(($firstSample | ConvertTo-Json -Depth 8 -Compress))
        $processSampleCount += 1
        $treePeak = [int64]$firstSample.tree_working_set_bytes
        $treePeakAtUtc = [string]$firstSample.utc
        $runnerWriter.WriteLine(([ordered]@{ utc = [DateTimeOffset]::UtcNow.ToString('o'); phase = 'launch'; status = 'complete'; root_pid = $process.Id; first_sample_written = $true } | ConvertTo-Json -Compress))

        while (-not $process.HasExited) {
            $now = [DateTimeOffset]::UtcNow
            if (($now - $startedAt).TotalSeconds -ge $WatchdogSeconds) {
                $timedOut = $true
                $runnerWriter.WriteLine(([ordered]@{ utc = $now.ToString('o'); phase = 'watchdog'; status = 'timeout'; last_progress = Get-LatestProgressMarker -Path $progressPath } | ConvertTo-Json -Depth 10 -Compress))
                break
            }
            Start-Sleep -Milliseconds $SampleIntervalMilliseconds
            $process.Refresh()
            if ($process.HasExited) { break }
            try {
                $sample = Get-OwnedTreeSample -Inventory (Get-ProcessInventory) -Owned $owned -CapturedAt ([DateTimeOffset]::UtcNow)
                $sampleWriter.WriteLine(($sample | ConvertTo-Json -Depth 8 -Compress))
                $processSampleCount += 1
                if ([int64]$sample.tree_working_set_bytes -gt $treePeak) { $treePeak = [int64]$sample.tree_working_set_bytes; $treePeakAtUtc = [string]$sample.utc }
            }
            catch {
                $samplingFailure = $_.Exception.Message
                $failures.Add("Owned process-tree sampling failed: $samplingFailure")
                break
            }
        }
        if (($timedOut -or -not [string]::IsNullOrEmpty($samplingFailure)) -and -not $process.HasExited) {
            $cleanupAttempted = $true
            $cleanupMethod = 'root_process_kill_entire_tree'
            $process.Kill($true)
        }
        $null = $process.WaitForExit(30000)
        $process.Refresh()
        if ($process.HasExited -and -not $timedOut) { $godotExitCode = [int]$process.ExitCode }
    }
    elseif ($PreflightOnly) {
        $runnerWriter.WriteLine(([ordered]@{ utc = [DateTimeOffset]::UtcNow.ToString('o'); phase = 'preflight_only'; status = if ($failures.Count -eq 0) { 'pass' } else { 'fail' }; product_launched = $false } | ConvertTo-Json -Compress))
    }
}
catch {
    $launchError = $_.Exception.Message
    $failures.Add("Controlled runner exception: $launchError")
    $runnerWriter.WriteLine(([ordered]@{ utc = [DateTimeOffset]::UtcNow.ToString('o'); phase = 'runner'; status = 'exception'; message = $launchError } | ConvertTo-Json -Compress))
}
finally {
    if ($null -ne $process -and -not $process.HasExited) {
        $cleanupAttempted = $true
        $cleanupMethod = 'root_process_kill_entire_tree'
        try { $process.Kill($true); $null = $process.WaitForExit(30000) } catch { $failures.Add("Owned root process-tree cleanup failed: $($_.Exception.Message)") }
    }
    if ($null -ne $sampleWriter) { $sampleWriter.Dispose() }
    $runnerWriter.Dispose()
}

if ($productLaunched) {
    if (-not $ownedRootBound) {
        $cleanupReason = 'Cleanup verification unavailable because the launched root PID and creation-time identity were not bound.'
        $failures.Add($cleanupReason)
    }
    else {
        try {
            $residualInventory = Get-ProcessInventory
            $cleanupVerificationAvailable = $true
            $residualOwned = @($owned.Values | Where-Object { Test-OwnedIdentityAlive -Identity $_ -Inventory $residualInventory })
            $cleanupVerified = $residualOwned.Count -eq 0
            $cleanupReason = if ($cleanupVerified) { 'Every recorded root/descendant PID and creation-time identity is absent.' } else { "Recorded owned process residue count=$($residualOwned.Count)." }
            if (-not $cleanupVerified) { $failures.Add($cleanupReason) }
        }
        catch {
            $cleanupReason = "Cleanup verification unavailable because Win32_Process inventory failed: $($_.Exception.Message)"
            $failures.Add($cleanupReason)
        }
    }
    if ($processSampleCount -eq 0) { $failures.Add('Product launched without a non-empty owned process-tree sample.') }
}
if ($null -ne $process) { $process.Dispose() }

$finishedAt = [DateTimeOffset]::UtcNow
try { $after = Get-SourceSnapshot -Label 'after' } catch { $after = New-SourceSnapshotFailure -Label 'after' -Reason $_.Exception.Message; $failures.Add("Source-after capture failed: $($_.Exception.Message)") }
Write-NewJsonFile -Path $afterPath -Value $after -Depth 100

if ($timedOut) {
    $marker = Get-LatestProgressMarker -Path $progressPath
    $phase = if ($null -ne $marker) { "$($marker.phase):$($marker.status)" } else { 'no-progress-marker' }
    $failures.Add("Watchdog timeout after 600 seconds; last marker=$phase")
}
if ($productLaunched -and $null -eq $godotExitCode) { $failures.Add('Godot exit code is unavailable.') }
elseif ($productLaunched -and [int]$godotExitCode -ne 0) { $failures.Add("Godot exit code was $godotExitCode") }
if ($productLaunched -and $treePeak -gt $treePeakLimit) { $failures.Add("Tree PeakWorkingSet64 exceeded 4GiB: $treePeak") }

$benchmarkResult = $null
$primaryActual = [pscustomobject][ordered]@{ path = ''; exists = $false; bytes = 0; sha256 = '' }
$backupActual = [pscustomobject][ordered]@{ path = ''; exists = $false; bytes = 0; sha256 = '' }
try {
    if ($productLaunched) {
        $stdoutText = if (Test-Path -LiteralPath $stdoutPath) { [IO.File]::ReadAllText($stdoutPath, [Text.Encoding]::UTF8) } else { '' }
        $stderrText = if (Test-Path -LiteralPath $stderrPath) { [IO.File]::ReadAllText($stderrPath, [Text.Encoding]::UTF8) } else { '' }
        $godotText = if (Test-Path -LiteralPath $godotLogPath) { [IO.File]::ReadAllText($godotLogPath, [Text.Encoding]::UTF8) } else { '' }
        $certificatePattern = '(?m)^ERROR: Failed to read the root certificate store\.\r?\n\s*at: get_system_ca_certificates \(platform/windows/os_windows\.cpp:\d+\)\r?\n?'
        $productLog = [regex]::Replace("$stdoutText`n$stderrText`n$godotText", $certificatePattern, '')
        foreach ($pattern in @('SCRIPT ERROR:', 'Parse Error:', '(?m)^ERROR:', 'Leaked instance:', 'ObjectDB instances? (?:was|were) leaked at exit', 'resources? still in use at exit', 'Resource still in use:', 'Orphan StringName:', 'unclaimed string names at exit')) {
            if ($productLog -match $pattern) { $failures.Add("Product log matched failure pattern: $pattern") }
        }
        if ($productLog -notmatch 'POPULATION_200K_CAPACITY_BENCHMARK_PASSED') { $failures.Add('Benchmark success marker is missing') }
        if (Test-Path -LiteralPath $benchmarkResultPath -PathType Leaf) {
            try { $benchmarkResult = Get-Content -LiteralPath $benchmarkResultPath -Raw | ConvertFrom-Json -Depth 100 } catch { $failures.Add("Benchmark result JSON is unreadable: $($_.Exception.Message)") }
        }
        else { $failures.Add('Benchmark result JSON is missing') }
    }
    if ($null -ne $benchmarkResult) {
        if ([string]$benchmarkResult.status -cne 'PASS' -or @($benchmarkResult.failures).Count -ne 0) { $failures.Add('Benchmark result reported FAIL or non-empty failures') }
        if ([int]$benchmarkResult.fixed_configuration.population -ne 200000 -or [int]$benchmarkResult.fixed_configuration.seed -ne 20260810 -or [int]$benchmarkResult.fixed_configuration.cohort_size -ne 2048 -or [int]$benchmarkResult.fixed_configuration.full_batches -ne 97 -or [int]$benchmarkResult.fixed_configuration.tail -ne 1344) {
            $failures.Add('Benchmark fixed configuration drifted')
        }
        if (-not [bool]$benchmarkResult.population.hash_parity -or -not [bool]$benchmarkResult.full_hash.parity -or -not [bool]$benchmarkResult.cohort.unique -or [int]$benchmarkResult.cohort.coverage_count -ne 200000) {
            $failures.Add('Hash parity, cohort uniqueness, or coverage failed')
        }
        $primaryActual = Get-FileEvidence -Path ([string]$benchmarkResult.save.primary.path)
        $backupActual = Get-FileEvidence -Path ([string]$benchmarkResult.save.backup.path)
        if (-not $primaryActual.exists -or -not $backupActual.exists) { $failures.Add('Primary or backup save evidence is missing') }
        if ($primaryActual.bytes -gt $saveByteLimit -or $backupActual.bytes -gt $saveByteLimit) { $failures.Add('Primary or backup save exceeds 512MiB') }
        if ($primaryActual.sha256 -cne [string]$benchmarkResult.save.primary.sha256 -or $backupActual.sha256 -cne [string]$benchmarkResult.save.backup.sha256) { $failures.Add('Result is not bound to the actual primary/backup hashes') }
        if ($primaryActual.sha256 -cne $backupActual.sha256) { $failures.Add('Primary and backup save hashes differ') }
        if ([bool]$benchmarkResult.save.temporary_residue -or [bool]$benchmarkResult.save.recovery_temporary_residue) { $failures.Add('Save temporary residue was reported') }
    }
}
catch {
    $failures.Add("Post-run evidence validation failed: $($_.Exception.Message)")
}

$sourceStable = ([string]$before.status -ceq 'OK' -and [string]$after.status -ceq 'OK' -and
    $before.source.fingerprint_sha256 -ceq $after.source.fingerprint_sha256 -and
    $before.source.file_count -eq $after.source.file_count -and
    $before.source.total_bytes -eq $after.source.total_bytes
)
$gitStable = ([string]$before.status -ceq 'OK' -and [string]$after.status -ceq 'OK' -and
    $before.head -ceq $after.head -and
    $before.head_tree -ceq $after.head_tree -and
    $before.sdk_gitlink -ceq $after.sdk_gitlink -and
    $before.sdk_head -ceq $after.sdk_head -and
    (@($before.status_lines) -join "`n") -ceq (@($after.status_lines) -join "`n") -and
    (@($before.sdk_status_lines) -join "`n") -ceq (@($after.sdk_status_lines) -join "`n")
)
if (-not $sourceStable) { $failures.Add('Tracked/untracked source fingerprint changed during benchmark') }
if (-not $gitStable) { $failures.Add('HEAD/tree/SDK/status changed during benchmark') }

$status = if ($PreflightOnly) { if ($failures.Count -eq 0) { 'PREFLIGHT_PASS' } else { 'PREFLIGHT_FAIL' } } else { if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' } }
$runnerExitCode = if ($failures.Count -eq 0) { 0 } elseif ($PreflightOnly -or -not $productLaunched) { 2 } else { 1 }
$cleanup = [pscustomobject][ordered]@{
    status = if (-not $productLaunched) { 'NOT_APPLICABLE_NO_PRODUCT_LAUNCH' } elseif (-not $cleanupVerificationAvailable) { 'UNVERIFIED_INVENTORY_FAILURE' } elseif ($cleanupVerified) { 'VERIFIED_CLEAN' } else { 'VERIFIED_RESIDUE' }
    product_launched = $productLaunched
    cleanup_attempted = $cleanupAttempted
    cleanup_method = $cleanupMethod
    verification_available = $cleanupVerificationAvailable
    verified_clean = if ($cleanupVerificationAvailable) { $cleanupVerified } else { $null }
    residual_owned_count = if ($cleanupVerificationAvailable) { $residualOwned.Count } else { $null }
    reason = $cleanupReason
}
$manifest = [pscustomobject][ordered]@{
    schema_version = 1
    benchmark = 'population_200k_capacity'
    append_only_output_root = $OutputRoot
    status = $status
    runner_exit_code = $runnerExitCode
    product_launched = $productLaunched
    godot_executable = if (Test-Path -LiteralPath $GodotExe -PathType Leaf) { (Resolve-Path -LiteralPath $GodotExe).Path } else { $GodotExe }
    watchdog_seconds = 600
    sample_interval_milliseconds = $SampleIntervalMilliseconds
    started_at_utc = $startedAt.ToString('o')
    finished_at_utc = $finishedAt.ToString('o')
    before = $before
    after = $after
    preflight = $preflight
    source_stable = $sourceStable
    git_stable = $gitStable
    benchmark_result = Get-FileEvidence -Path $benchmarkResultPath
    process_samples = Get-FileEvidence -Path $processSamplesPath
    process_sample_count = $processSampleCount
    cleanup = $cleanup
    primary_save = $primaryActual
    backup_save = $backupActual
}
Write-NewJsonFile -Path $manifestPath -Value $manifest -Depth 100

$summary = [pscustomobject][ordered]@{
    schema_version = 1
    status = $status
    output_root = $OutputRoot
    started_at_utc = $startedAt.ToString('o')
    finished_at_utc = $finishedAt.ToString('o')
    duration_seconds = [Math]::Round(($finishedAt - $startedAt).TotalSeconds, 3)
    runner_exit_code = $runnerExitCode
    godot_exit_code = $godotExitCode
    product_launched = $productLaunched
    preflight = $preflight
    timed_out = $timedOut
    last_progress = Get-LatestProgressMarker -Path $progressPath
    process_sample_count = $processSampleCount
    tree_peak_working_set_bytes = if ($processSampleCount -gt 0) { $treePeak } else { $null }
    tree_peak_working_set_gib = if ($processSampleCount -gt 0) { [Math]::Round($treePeak / 1GB, 4) } else { $null }
    tree_peak_at_utc = $treePeakAtUtc
    tree_peak_limit_bytes = $treePeakLimit
    owned_root_and_descendant_processes = @($owned.Values | Sort-Object depth, pid)
    residual_owned_processes = @($residualOwned)
    cleanup = $cleanup
    source_stable = $sourceStable
    git_stable = $gitStable
    primary_save = $primaryActual
    backup_save = $backupActual
    benchmark = $benchmarkResult
    failures = @($failures)
    provisional_limits_are_release_sla = $false
}
Write-NewJsonFile -Path $summaryPath -Value $summary -Depth 100

$markdown = @(
    '# Population 200k capacity benchmark',
    '',
    "- Status: $status",
    "- Output root: $OutputRoot",
    "- Duration: $($summary.duration_seconds) seconds",
    "- Product launched: $productLaunched",
    "- CIM preflight: $($preflight.status)",
    "- Process samples: $processSampleCount",
    "- Tree peak working set: $(if ($processSampleCount -gt 0) { "$($summary.tree_peak_working_set_gib) GiB / 4 GiB provisional line" } else { 'unavailable; no sample claim' })",
    "- Cleanup truth: $($cleanup.status)",
    "- Primary save: $($primaryActual.bytes) bytes, SHA-256 $($primaryActual.sha256)",
    "- Backup save: $($backupActual.bytes) bytes, SHA-256 $($backupActual.sha256)",
    "- Source stable: $sourceStable",
    "- Git/SDK stable: $gitStable",
    '- Limits are provisional capacity gates, not release SLA.',
    ''
)
if ($failures.Count -gt 0) {
    $markdown += '## Failures'
    $markdown += ''
    $markdown += @($failures | ForEach-Object { "- $_" })
    $markdown += ''
}
Write-NewUtf8File -Path $summaryMarkdownPath -Text (($markdown -join "`n") + "`n")

$runnerExit = [pscustomobject][ordered]@{
    schema_version = 1
    status = $status
    exit_code = $runnerExitCode
    controlled = $true
    finalized = $true
    product_launched = $productLaunched
    preflight_status = [string]$preflight.status
    cleanup_status = [string]$cleanup.status
    finished_at_utc = $finishedAt.ToString('o')
}
Write-NewJsonFile -Path $runnerExitPath -Value $runnerExit -Depth 20

Write-Output "POPULATION_200K_CAPACITY_RUN status=$status output=$OutputRoot runner_exit=$runnerExitCode product_launched=$productLaunched process_samples=$processSampleCount cleanup=$($cleanup.status)"
exit $runnerExitCode
