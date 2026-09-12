[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$GodotExe,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{40}$')]
    [string]$ExpectedHead,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{40}$')]
    [string]$ExpectedTree,

    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,

    [ValidateRange(1, 20)]
    [int]$RunCount = 3,

    [ValidateRange(2, 36000)]
    [int]$SmokeFrames = 180,

    [string]$OutputRoot = (Join-Path ([IO.Path]::GetTempPath()) ("mayor-main-exit-lifecycle-{0}" -f [Guid]::NewGuid().ToString('N')))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Git {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $output = & git -c "safe.directory=$ProjectRoot" -C $ProjectRoot @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed: $($output -join [Environment]::NewLine)"
    }
    return @($output)
}

function Convert-ToCommandDisplay {
    param(
        [Parameter(Mandatory = $true)][string]$FileName,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $quoted = foreach ($argument in $Arguments) {
        if ($argument -match '[\s"]') {
            '"{0}"' -f ($argument -replace '"', '\"')
        } else {
            $argument
        }
    }
    return @($FileName) + $quoted -join ' '
}

function New-ProcessStartInfo {
    param(
        [Parameter(Mandatory = $true)][string]$FileName,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [hashtable]$Environment = @{}
    )

    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $FileName
    $info.WorkingDirectory = $WorkingDirectory
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.CreateNoWindow = $false
    foreach ($argument in $Arguments) {
        $null = $info.ArgumentList.Add($argument)
    }
    foreach ($entry in $Environment.GetEnumerator()) {
        $info.Environment[$entry.Key] = [string]$entry.Value
    }
    return $info
}

function Invoke-CapturedProcess {
    param(
        [Parameter(Mandatory = $true)][Diagnostics.ProcessStartInfo]$StartInfo,
        [Parameter(Mandatory = $true)][string]$StdoutPath,
        [Parameter(Mandatory = $true)][string]$StderrPath
    )

    $startedUtc = [DateTime]::UtcNow
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $StartInfo
    if (-not $process.Start()) {
        throw "Failed to start $($StartInfo.FileName)"
    }
    $processId = $process.Id
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    # Deliberately no timeout/kill path: this probe must observe only a product-
    # initiated, graceful SceneTree.quit(). The caller can interrupt a genuinely
    # hung diagnostic and report it as BLOCKED without manufacturing clean exit.
    $process.WaitForExit()
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    $process.Refresh()
    $exitCode = $process.ExitCode
    $endedUtc = [DateTime]::UtcNow
    $process.Dispose()

    [IO.File]::WriteAllText($StdoutPath, $stdout, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($StderrPath, $stderr, [Text.UTF8Encoding]::new($false))

    return [ordered]@{
        pid = $processId
        started_utc = $startedUtc.ToString('o')
        ended_utc = $endedUtc.ToString('o')
        duration_ms = [Math]::Round(($endedUtc - $startedUtc).TotalMilliseconds, 3)
        exit_code = $exitCode
        stdout = $stdout
        stderr = $stderr
    }
}

function Get-Lines {
    param([AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) {
        return @()
    }
    return @($Text -split "`r?`n")
}

function Get-Tail {
    param(
        [AllowEmptyString()][string]$Text,
        [int]$MaximumLines = 200
    )
    $lines = @(Get-Lines -Text $Text)
    if ($lines.Count -le $MaximumLines) {
        return $lines
    }
    return @($lines[($lines.Count - $MaximumLines)..($lines.Count - 1)])
}

$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\', '/')
$GodotExe = (Resolve-Path -LiteralPath $GodotExe).Path
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot).TrimEnd('\', '/')
$ExpectedHead = $ExpectedHead.ToLowerInvariant()
$ExpectedTree = $ExpectedTree.ToLowerInvariant()
if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot 'scenes\Main.tscn') -PathType Leaf)) {
    throw "ProjectRoot does not contain scenes/Main.tscn: $ProjectRoot"
}
if ($OutputRoot.Equals($ProjectRoot, [StringComparison]::OrdinalIgnoreCase) -or
    $OutputRoot.StartsWith($ProjectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'OutputRoot must be outside ProjectRoot so evidence can never become a tracked product file.'
}

$headBefore = ([string](Invoke-Git -Arguments @('rev-parse', 'HEAD'))).Trim()
$treeBefore = ([string](Invoke-Git -Arguments @('rev-parse', 'HEAD^{tree}'))).Trim()
$branchBefore = ([string](Invoke-Git -Arguments @('branch', '--show-current'))).Trim()
$statusBefore = @(Invoke-Git -Arguments @('status', '--porcelain=v1', '--untracked-files=all'))
$statusBefore = @($statusBefore | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($headBefore -ne $ExpectedHead -or $treeBefore -ne $ExpectedTree) {
    throw "Unexpected source baseline. HEAD=$headBefore tree=$treeBefore"
}
if ($statusBefore.Count -gt 0) {
    throw "Source worktree is not clean: $($statusBefore -join '; ')"
}

New-Item -ItemType Directory -Path $OutputRoot -ErrorAction Stop | Out-Null

$versionStdout = Join-Path $OutputRoot 'godot-version.stdout.log'
$versionStderr = Join-Path $OutputRoot 'godot-version.stderr.log'
$versionInfo = New-ProcessStartInfo -FileName $GodotExe -Arguments @('--version') -WorkingDirectory $ProjectRoot
$versionProcess = Invoke-CapturedProcess -StartInfo $versionInfo -StdoutPath $versionStdout -StderrPath $versionStderr
$versionText = ($versionProcess.stdout + "`n" + $versionProcess.stderr).Trim()
if ($versionProcess.exit_code -ne 0 -or $versionText -notmatch '^4\.7(?:\.|\s|$)') {
    throw "Expected Godot 4.7, got exit=$($versionProcess.exit_code) output=$versionText"
}

$results = [Collections.Generic.List[object]]::new()
for ($runNumber = 1; $runNumber -le $RunCount; $runNumber++) {
    $runDirectory = Join-Path $OutputRoot ('run-{0:D2}' -f $runNumber)
    $appData = Join-Path $runDirectory 'appdata'
    $localAppData = Join-Path $runDirectory 'localappdata'
    New-Item -ItemType Directory -Path $appData, $localAppData -ErrorAction Stop | Out-Null

    $stdoutPath = Join-Path $runDirectory 'stdout.log'
    $stderrPath = Join-Path $runDirectory 'stderr.log'
    $arguments = @(
        '--verbose',
        '--path', $ProjectRoot,
        '--rendering-method', 'mobile',
        '--',
        "--qa-release-smoke-frames=$SmokeFrames"
    )
    $commandDisplay = Convert-ToCommandDisplay -FileName $GodotExe -Arguments $arguments
    $startInfo = New-ProcessStartInfo -FileName $GodotExe -Arguments $arguments -WorkingDirectory $ProjectRoot -Environment @{
        APPDATA = $appData
        LOCALAPPDATA = $localAppData
    }
    $captured = Invoke-CapturedProcess -StartInfo $startInfo -StdoutPath $stdoutPath -StderrPath $stderrPath
    $combined = $captured.stdout + "`n" + $captured.stderr
    $combinedLines = @(Get-Lines -Text $combined)
    $rendererLines = @($combinedLines | Where-Object { $_ -match '(?i)(renderer|rendering device|video adapter|vulkan|direct3d|opengl)' })
    $retentionLines = @($combinedLines | Where-Object { $_ -match '(?i)(ObjectDB|resource.*still in use|still in use.*resource|leaked instance|leak|RID allocations)' })
    $observation = if ($retentionLines.Count -gt 0) { 'REPRODUCED' } else { 'NOT_REPRODUCED' }
    $armed = $captured.stdout.Contains("QA_RELEASE_SMOKE_ARMED frames=$SmokeFrames")
    $completed = $captured.stdout.Contains('QA_RELEASE_SMOKE_COMPLETED')
    $normalExit = $captured.exit_code -eq 0 -and $armed -and $completed

    $results.Add([ordered]@{
        run = $runNumber
        command = $commandDisplay
        pid = $captured.pid
        started_utc = $captured.started_utc
        ended_utc = $captured.ended_utc
        duration_ms = $captured.duration_ms
        exit_code = $captured.exit_code
        appdata = $appData
        localappdata = $localAppData
        marker_armed = $armed
        marker_completed = $completed
        normal_scene_tree_exit = $normalExit
        observation = $observation
        renderer_lines = $rendererLines
        retention_lines = $retentionLines
        stdout_path = $stdoutPath
        stdout_sha256 = (Get-FileHash -LiteralPath $stdoutPath -Algorithm SHA256).Hash
        stdout_line_count = @(Get-Lines -Text $captured.stdout).Count
        stdout_tail = @(Get-Tail -Text $captured.stdout)
        stderr_path = $stderrPath
        stderr_sha256 = (Get-FileHash -LiteralPath $stderrPath -Algorithm SHA256).Hash
        stderr_line_count = @(Get-Lines -Text $captured.stderr).Count
        stderr_tail = @(Get-Tail -Text $captured.stderr)
    })
}

$headAfter = ([string](Invoke-Git -Arguments @('rev-parse', 'HEAD'))).Trim()
$treeAfter = ([string](Invoke-Git -Arguments @('rev-parse', 'HEAD^{tree}'))).Trim()
$branchAfter = ([string](Invoke-Git -Arguments @('branch', '--show-current'))).Trim()
$statusAfter = @(Invoke-Git -Arguments @('status', '--porcelain=v1', '--untracked-files=all'))
$statusAfter = @($statusAfter | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$sourceUnchanged = $headBefore -eq $headAfter -and $treeBefore -eq $treeAfter -and
    (($statusBefore -join "`n") -eq ($statusAfter -join "`n"))
$allNormal = @($results | Where-Object { -not $_.normal_scene_tree_exit }).Count -eq 0
$observation = if (@($results | Where-Object { $_.retention_lines.Count -gt 0 }).Count -gt 0) {
    'REPRODUCED'
} else {
    'NOT_REPRODUCED'
}

$summary = [ordered]@{
    schema = 'mayor-main-exit-lifecycle-probe-v1'
    generated_utc = [DateTime]::UtcNow.ToString('o')
    result = if ($allNormal -and $sourceUnchanged) { 'PASS' } else { 'FAIL' }
    observation = $observation
    godot_exe = $GodotExe
    godot_version = $versionText
    project_root = $ProjectRoot
    scene = 'res://scenes/Main.tscn'
    renderer_requested = 'mobile'
    smoke_frames = $SmokeFrames
    source_before = [ordered]@{
        branch = $branchBefore
        head = $headBefore
        tree = $treeBefore
        status = $statusBefore
    }
    source_after = [ordered]@{
        branch = $branchAfter
        head = $headAfter
        tree = $treeAfter
        status = $statusAfter
    }
    source_unchanged = $sourceUnchanged
    runs = $results
}

$summaryPath = Join-Path $OutputRoot 'summary.json'
[IO.File]::WriteAllText($summaryPath, ($summary | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
Write-Output "P3B_MAIN_EXIT_LIFECYCLE_RESULT=$($summary.result)"
Write-Output "P3B_MAIN_EXIT_LIFECYCLE_OBSERVATION=$($summary.observation)"
Write-Output "P3B_MAIN_EXIT_LIFECYCLE_SUMMARY=$summaryPath"
foreach ($result in $results) {
    Write-Output ("P3B_RUN={0} PID={1} EXIT={2} NORMAL={3} OBSERVATION={4} RETENTION_LINES={5}" -f $result.run, $result.pid, $result.exit_code, $result.normal_scene_tree_exit, $result.observation, $result.retention_lines.Count)
}
if ($summary.result -ne 'PASS') {
    exit 1
}
