#requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$GodotExe,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$OutputRoot,
    [Parameter(Mandatory)][ValidatePattern('^res://tests/manual/[a-z0-9_]+\.gd$')][string]$FixtureScript,
    [Parameter(Mandatory)][ValidatePattern('^--[a-z0-9-]+-output-dir=$')][string]$OutputArgumentPrefix,
    [Parameter(Mandatory)][ValidatePattern('^[a-z0-9-]+-result\.json$')][string]$ResultFilename,
    [Parameter(Mandatory)][ValidatePattern('^[a-z0-9-]+-actual-main-native\.png$')][string]$CaptureFilename,
    [Parameter(Mandatory)][ValidatePattern('^[A-Z0-9_]+_PASSED$')][string]$SuccessMarker,
    [Parameter(Mandatory)][ValidatePattern('^mayor-simulator-[a-z0-9-]+$')][string]$Suite,
    [ValidateRange(30, 900)][int]$TimeoutSeconds = 300
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'source_fingerprint.ps1')

function Get-TextSha256 {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { return [Convert]::ToHexString($hasher.ComputeHash([Text.UTF8Encoding]::new($false).GetBytes($Text))).ToLowerInvariant() }
    finally { $hasher.Dispose() }
}

function Get-PngRecord {
    param([Parameter(Mandatory)][string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    $bytes = [IO.File]::ReadAllBytes($item.FullName)
    $magic = [byte[]](137,80,78,71,13,10,26,10)
    if ($item.PSIsContainer -or $bytes.Length -lt 24) { throw "Invalid PNG evidence: $Path" }
    for ($index = 0; $index -lt $magic.Length; $index++) {
        if ($bytes[$index] -ne $magic[$index]) { throw "PNG header invalid: $Path" }
    }
    $width = [int64]$bytes[16] * 16777216 + [int64]$bytes[17] * 65536 + [int64]$bytes[18] * 256 + $bytes[19]
    $height = [int64]$bytes[20] * 16777216 + [int64]$bytes[21] * 65536 + [int64]$bytes[22] * 256 + $bytes[23]
    if ($width -le 0 -or $height -le 0) { throw "PNG dimensions invalid: $Path" }
    return [ordered]@{
        filename = $item.Name
        bytes = [long]$item.Length
        width = $width
        height = $height
        sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

$GodotExe = (Resolve-Path -LiteralPath $GodotExe).Path
$fixturePath = Join-Path $projectRoot ($FixtureScript.Substring('res://'.Length).Replace('/', '\'))
if (-not (Test-Path -LiteralPath $fixturePath -PathType Leaf)) { throw "Fixture not found: $FixtureScript" }
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
if (-not (Test-MayorPathInside -Candidate $OutputRoot -Parent $projectRoot) -or $OutputRoot.Equals($projectRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'OutputRoot must be a child path inside the project worktree.'
}
if (Test-Path -LiteralPath $OutputRoot) { throw 'OutputRoot already exists; evidence is append-only.' }

$branch = (git -c safe.directory=$projectRoot -C $projectRoot branch --show-current).Trim()
$head = (git -c safe.directory=$projectRoot -C $projectRoot rev-parse HEAD).Trim()
$tree = (git -c safe.directory=$projectRoot -C $projectRoot rev-parse 'HEAD^{tree}').Trim()
$statusText = (git -c safe.directory=$projectRoot -C $projectRoot status --porcelain=v1 --untracked-files=all) -join "`n"
$dirty = -not [string]::IsNullOrWhiteSpace($statusText)
$statusSha256 = Get-TextSha256 -Text $statusText
$pre = Get-MayorSourceFingerprint -ProjectRoot $projectRoot

New-Item -ItemType Directory -Path $OutputRoot -ErrorAction Stop | Out-Null
$appData = Join-Path $OutputRoot 'appdata'
$localAppData = Join-Path $OutputRoot 'localappdata'
New-Item -ItemType Directory -Path $appData,$localAppData -ErrorAction Stop | Out-Null
$stdoutPath = Join-Path $OutputRoot 'stdout.log'
$stderrPath = Join-Path $OutputRoot 'stderr.log'
$godotLogPath = Join-Path $OutputRoot 'godot.log'
$summaryPath = Join-Path $OutputRoot 'summary.json'
$resultPath = Join-Path $OutputRoot $ResultFilename
$capturePath = Join-Path $OutputRoot $CaptureFilename

$sourceIdentity = [ordered]@{
    worktree = $projectRoot
    branch = $branch
    head = $head
    tree = $tree
    dirty = $dirty
    status_sha256 = $statusSha256
    fingerprint = $pre.fingerprint_sha256
    fingerprint_file_count = $pre.file_count
    fingerprint_total_bytes = $pre.total_bytes
}

$stdoutText = ''
$stderrText = ''
$completed = $false
$exitCode = -1
$launchError = $null
$process = $null
try {
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $GodotExe
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.CreateNoWindow = $false
    $info.Environment['APPDATA'] = $appData
    $info.Environment['LOCALAPPDATA'] = $localAppData
    $info.Environment['MAYOR_ACCEPTANCE_WORKTREE'] = $projectRoot
    $info.Environment['MAYOR_ACCEPTANCE_BRANCH'] = $branch
    $info.Environment['MAYOR_ACCEPTANCE_HEAD'] = $head
    $info.Environment['MAYOR_ACCEPTANCE_TREE'] = $tree
    $info.Environment['MAYOR_ACCEPTANCE_DIRTY'] = $dirty.ToString().ToLowerInvariant()
    $info.Environment['MAYOR_ACCEPTANCE_STATUS_SHA256'] = $statusSha256
    $info.Environment['MAYOR_ACCEPTANCE_SOURCE_FINGERPRINT'] = $pre.fingerprint_sha256
    foreach ($argument in @(
        '--verbose', '--path', $projectRoot,
        '--script', $FixtureScript,
        '--log-file', $godotLogPath,
        '--', "$OutputArgumentPrefix$OutputRoot"
    )) { $info.ArgumentList.Add([string]$argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    if (-not $process.Start()) { throw 'Godot process did not start.' }
    $outTask = $process.StandardOutput.ReadToEndAsync()
    $errTask = $process.StandardError.ReadToEndAsync()
    $completed = $process.WaitForExit($TimeoutSeconds * 1000)
    if (-not $completed) {
        try { $process.Kill($true) } catch {}
        $null = $process.WaitForExit(30000)
    }
    if (-not $process.HasExited) { throw 'Godot process tree did not exit after timeout cleanup.' }
    if (-not $outTask.Wait(15000) -or -not $errTask.Wait(15000)) { throw 'Godot output pipes did not close.' }
    $stdoutText = $outTask.GetAwaiter().GetResult()
    $stderrText = $errTask.GetAwaiter().GetResult()
    $exitCode = if ($completed) { [int]$process.ExitCode } else { -1 }
}
catch { $launchError = $_.Exception.Message }
finally {
    if ($null -ne $process) { $process.Dispose() }
    [IO.File]::WriteAllText($stdoutPath, $stdoutText, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($stderrPath, $stderrText, [Text.UTF8Encoding]::new($false))
}

$failures = [Collections.Generic.List[string]]::new()
if ($launchError) { $failures.Add("Godot launch failed: $launchError") }
if (-not $completed) { $failures.Add('Godot did not complete before timeout.') }
if ($exitCode -ne 0) { $failures.Add("Godot exit code was $exitCode.") }
$godotLogText = if (Test-Path -LiteralPath $godotLogPath) { Get-Content -LiteralPath $godotLogPath -Raw } else { '' }
$plainLog = ($stdoutText + "`n" + $stderrText + "`n" + $godotLogText) -replace "`e\[[0-?]*[ -/]*[@-~]",''
$diagnostics = @([regex]::Matches($plainLog,'(?im)^(?:SCRIPT ERROR|ERROR|WARNING):[^\r\n]*') | ForEach-Object { $_.Value.Trim() } | Where-Object { $_ -notmatch 'Failed to read the root certificate store' })
foreach ($pattern in @('Leaked instance:','ObjectDB instances? (?:was|were) leaked at exit','resources? still in use at exit','Resource still in use:','Orphan StringName:','unclaimed string names at exit')) {
    if ([regex]::IsMatch($plainLog, $pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)) { $diagnostics += "leak signature: $pattern" }
}
if ($diagnostics.Count) { $failures.Add("Product diagnostics found: $($diagnostics -join ' | ')") }
if ([regex]::Matches($stdoutText, "(?m)^$([regex]::Escape($SuccessMarker)).*$").Count -ne 1) { $failures.Add('Expected success marker exactly once.') }

$capture = $null
try { $capture = Get-PngRecord -Path $capturePath } catch { $failures.Add($_.Exception.Message) }
$result = $null
try {
    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json -Depth 30
    if (
        $result.suite -cne $Suite -or
        $result.status -cne 'PASS' -or
        -not [bool]$result.contract_validated -or
        -not [bool]$result.actual_main -or
        $result.scene -cne 'res://scenes/Main.tscn' -or
        $result.capture_surface_kind -cne 'native_fullscreen_root' -or
        $result.captures.Count -ne 1
    ) { throw 'Result contract does not prove a validated actual-Main native acceptance.' }
    if (
        $result.source.worktree -cne $projectRoot -or
        $result.source.branch -cne $branch -or
        $result.source.head -cne $head -or
        $result.source.tree -cne $tree -or
        [bool]$result.source.dirty -ne $dirty -or
        $result.source.status_sha256 -cne $statusSha256 -or
        $result.source.fingerprint -cne $pre.fingerprint_sha256
    ) { throw 'Result source identity does not match the runner manifest.' }
    if ($null -ne $capture) {
        $fixtureCapture = $result.captures[0]
        if (
            $fixtureCapture.filename -cne $capture.filename -or
            [long]$fixtureCapture.bytes -ne [long]$capture.bytes -or
            [long]$fixtureCapture.width -ne [long]$capture.width -or
            [long]$fixtureCapture.height -ne [long]$capture.height -or
            $fixtureCapture.sha256 -cne $capture.sha256
        ) { throw 'Fixture capture metadata does not match the validated PNG.' }
    }
}
catch { $failures.Add("Result validation failed: $($_.Exception.Message)") }

$post = $null
try {
    $post = Get-MayorSourceFingerprint -ProjectRoot $projectRoot
    if ($post.fingerprint_sha256 -ne $pre.fingerprint_sha256) { throw 'Source fingerprint changed during acceptance.' }
    $postStatusText = (git -c safe.directory=$projectRoot -C $projectRoot status --porcelain=v1 --untracked-files=all) -join "`n"
    if ((Get-TextSha256 -Text $postStatusText) -ne $statusSha256) { throw 'Git status changed during acceptance.' }
}
catch { $failures.Add("Post-run source identity failed: $($_.Exception.Message)") }

$summary = [ordered]@{
    schema_version = 1
    suite = $Suite
    status = if ($failures.Count) { 'FAIL' } else { 'PASS' }
    source = [ordered]@{
        identity = $sourceIdentity
        post_fingerprint = if ($null -ne $post) { $post.fingerprint_sha256 } else { $null }
        unchanged = ($null -ne $post -and $post.fingerprint_sha256 -eq $pre.fingerprint_sha256)
    }
    fixture = $FixtureScript
    process = [ordered]@{ completed = $completed; exit_code = $exitCode; timeout_seconds = $TimeoutSeconds; cleanup_confirmed = $completed }
    success_marker = $SuccessMarker
    capture = $capture
    result = $result
    diagnostics = $diagnostics
    failures = @($failures)
}
[IO.File]::WriteAllText($summaryPath, ($summary | ConvertTo-Json -Depth 30), [Text.UTF8Encoding]::new($false))
if ($failures.Count) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}
Write-Output "Actual-Main visible acceptance passed: suite=$Suite output=$OutputRoot"
