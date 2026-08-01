#requires -Version 7.4

[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$GodotExe,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$OutputRoot,
    [ValidateRange(30, 1800)][int]$TimeoutSeconds = 420
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'source_fingerprint.ps1')

function Assert-PathChainWithoutReparsePoint {
    param(
        [Parameter(Mandatory)][string]$Candidate,
        [Parameter(Mandatory)][string]$Boundary
    )
    $current = [IO.Path]::GetFullPath($Candidate)
    $boundaryFull = [IO.Path]::GetFullPath($Boundary)
    while ($true) {
        if (Test-Path -LiteralPath $current) {
            $null = Assert-MayorNotReparsePoint -Path $current -Label 'UI capture path component'
        }
        if ($current.Equals($boundaryFull, [StringComparison]::OrdinalIgnoreCase)) {
            break
        }
        $parent = [IO.Directory]::GetParent($current)
        if ($null -eq $parent -or -not (Test-MayorPathInside -Candidate $parent.FullName -Parent $boundaryFull)) {
            throw "UI capture path escaped the project workspace: $Candidate"
        }
        $current = $parent.FullName
    }
}

function Get-FileRecord {
    param([Parameter(Mandatory)][string]$Path)
    $item = Assert-MayorNotReparsePoint -Path $Path -Label 'UI capture evidence file'
    if ($item.PSIsContainer) {
        throw "Expected an evidence file, found a directory: $Path"
    }
    return [pscustomobject][ordered]@{
        path = [IO.Path]::GetRelativePath($OutputRoot, $item.FullName).Replace('\', '/')
        bytes = [long]$item.Length
        sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

function Get-PngHeader {
    param([Parameter(Mandatory)][string]$Path)
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        if ($stream.Length -lt 24) {
            throw "PNG is shorter than its required header: $Path"
        }
        $header = [byte[]]::new(24)
        if ($stream.Read($header, 0, $header.Length) -ne $header.Length) {
            throw "Could not read the complete PNG header: $Path"
        }
    }
    finally {
        $stream.Dispose()
    }
    $magic = [byte[]](137, 80, 78, 71, 13, 10, 26, 10)
    for ($index = 0; $index -lt $magic.Length; $index++) {
        if ($header[$index] -ne $magic[$index]) {
            throw "PNG magic mismatch: $Path"
        }
    }
    $width = [int64]$header[16] * 16777216 + [int64]$header[17] * 65536 + [int64]$header[18] * 256 + $header[19]
    $height = [int64]$header[20] * 16777216 + [int64]$header[21] * 65536 + [int64]$header[22] * 256 + $header[23]
    return [pscustomobject]@{ width = $width; height = $height }
}

$GodotExe = (Resolve-Path -LiteralPath $GodotExe -ErrorAction Stop).Path
$godotItem = Assert-MayorNotReparsePoint -Path $GodotExe -Label 'Godot executable'
if ($godotItem.PSIsContainer) {
    throw "GodotExe must be a file: $GodotExe"
}

$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
if (-not (Test-MayorPathInside -Candidate $OutputRoot -Parent $projectRoot) -or
    $OutputRoot.Equals($projectRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputRoot must be a child path inside the project workspace: $OutputRoot"
}
if (Test-Path -LiteralPath $OutputRoot) {
    throw "OutputRoot already exists; UI capture evidence is append-only: $OutputRoot"
}
Assert-PathChainWithoutReparsePoint -Candidate $OutputRoot -Boundary $projectRoot

$expectedCaptures = [ordered]@{
    start = 'fullscreen-start-screen.png'
    start_loading = 'fullscreen-start-loading.png'
    tutorial_intro = 'fullscreen-tutorial-intro.png'
    tutorial_buildings = 'fullscreen-tutorial-buildings.png'
    tutorial_governance = 'fullscreen-tutorial-governance.png'
    tutorial_replay = 'fullscreen-tutorial-replay.png'
    main = 'fullscreen-main.png'
    weather_cloudy = 'fullscreen-weather-cloudy.png'
    weather_rain = 'fullscreen-weather-rain.png'
    settings = 'fullscreen-settings.png'
    settings_dark_en = 'fullscreen-settings-dark-en.png'
    building_context = 'fullscreen-building-context.png'
    hub = 'fullscreen-municipal-hub.png'
    hub_development = 'fullscreen-municipal-development.png'
    buildings = 'fullscreen-buildings.png'
    governance = 'fullscreen-governance.png'
    governance_review = 'fullscreen-governance-review.png'
    governance_implemented = 'fullscreen-governance-implemented.png'
    judicial = 'fullscreen-judicial.png'
    oversight = 'fullscreen-oversight.png'
    blueprint = 'fullscreen-blueprint.png'
    blueprint_review = 'fullscreen-blueprint-review.png'
    finance = 'fullscreen-finance.png'
    public_affairs = 'fullscreen-public-affairs.png'
    city_data = 'fullscreen-city-data.png'
    city_data_residents = 'fullscreen-city-data-residents.png'
    city_data_finance = 'fullscreen-city-data-finance.png'
    city_data_previous_month = 'fullscreen-city-data-previous-month.png'
    city_data_previous_month_warning = 'fullscreen-city-data-previous-month-warning.png'
    report = 'fullscreen-report.png'
    report_version_updates = 'fullscreen-report-version-updates.png'
    dark_blueprint = 'fullscreen-dark-blueprint.png'
    exit_confirm = 'fullscreen-exit-confirm.png'
}
if ($expectedCaptures.Count -ne 33) {
    throw "Internal UI capture contract must contain exactly 33 states; found $($expectedCaptures.Count)."
}

$preFingerprint = Get-MayorSourceFingerprint -ProjectRoot $projectRoot
New-Item -ItemType Directory -Path $OutputRoot -ErrorAction Stop | Out-Null
$null = Assert-MayorNotReparsePoint -Path $OutputRoot -Label 'UI capture output root'

$captureRoot = Join-Path $OutputRoot 'screenshots'
$appDataRoot = Join-Path $OutputRoot 'appdata'
$localAppDataRoot = Join-Path $OutputRoot 'localappdata'
New-Item -ItemType Directory -Path $appDataRoot, $localAppDataRoot -ErrorAction Stop | Out-Null
$stdoutPath = Join-Path $OutputRoot 'stdout.log'
$stderrPath = Join-Path $OutputRoot 'stderr.log'
$godotLogPath = Join-Path $OutputRoot 'godot.log'

$startedAt = [DateTimeOffset]::UtcNow
$completed = $false
$exitCode = -1
$stdoutText = ''
$stderrText = ''
$launchError = $null
$outputCaptureComplete = $false

try {
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $GodotExe
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $false
    $startInfo.Environment['APPDATA'] = $appDataRoot
    $startInfo.Environment['LOCALAPPDATA'] = $localAppDataRoot
    foreach ($argument in @(
        '--verbose',
        '--path', $projectRoot,
        '--script', 'res://tests/ui/capture_ui_readability.gd',
        '--log-file', $godotLogPath,
        '--', "--ui-capture-output-dir=$captureRoot"
    )) {
        $startInfo.ArgumentList.Add([string]$argument)
    }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw 'Godot process did not start.'
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $completed = $process.WaitForExit($TimeoutSeconds * 1000)
        if (-not $completed) {
            try { $process.Kill($true) } catch { }
            $null = $process.WaitForExit(30000)
        }
        if ($process.HasExited) {
            $stdoutReady = $stdoutTask.Wait(15000)
            $stderrReady = $stderrTask.Wait(15000)
            if (-not $stdoutReady -or -not $stderrReady) {
                try { $process.StandardOutput.Dispose() } catch { }
                try { $process.StandardError.Dispose() } catch { }
                throw 'Redirected Godot output pipes did not close within 15 seconds after process exit.'
            }
            $stdoutText = $stdoutTask.GetAwaiter().GetResult()
            $stderrText = $stderrTask.GetAwaiter().GetResult()
            $outputCaptureComplete = $true
            $exitCode = if ($completed) { [int]$process.ExitCode } else { -1 }
        }
        else {
            try { $process.StandardOutput.Dispose() } catch { }
            try { $process.StandardError.Dispose() } catch { }
            throw 'Godot process tree did not exit within 30 seconds after the acceptance timeout.'
        }
    }
    finally {
        if ($null -ne $process) { $process.Dispose() }
    }
}
catch {
    $launchError = $_.Exception.Message
}
finally {
    [IO.File]::WriteAllText($stdoutPath, $stdoutText, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($stderrPath, $stderrText, [Text.UTF8Encoding]::new($false))
}

$finishedAt = [DateTimeOffset]::UtcNow
$failures = [System.Collections.Generic.List[string]]::new()
if ($null -ne $launchError) { $failures.Add("Godot launch failed: $launchError") }
if (-not $completed) { $failures.Add("Godot did not complete within $TimeoutSeconds seconds.") }
if ($exitCode -ne 0) { $failures.Add("Godot exit code was $exitCode.") }
if (-not $outputCaptureComplete) { $failures.Add('Godot stdout/stderr capture did not complete.') }
foreach ($requiredLog in @($stdoutPath, $stderrPath, $godotLogPath)) {
    if (-not (Test-Path -LiteralPath $requiredLog -PathType Leaf)) {
        $failures.Add("Required log is missing: $requiredLog")
    }
}

$ansiPattern = "`e\[[0-?]*[ -/]*[@-~]"
$certificatePattern = '(?m)^ERROR: Failed to read the root certificate store\.\r?\n\s*at: get_system_ca_certificates \(platform/windows/os_windows\.cpp:\d+\)\r?\n?'
$logParts = @($stdoutText, $stderrText)
if (Test-Path -LiteralPath $godotLogPath -PathType Leaf) {
    $logParts += [IO.File]::ReadAllText($godotLogPath, [Text.Encoding]::UTF8)
}
$plainLog = [regex]::Replace(($logParts -join "`n"), $ansiPattern, '')
$environmentWarningCount = [regex]::Matches($plainLog, $certificatePattern).Count
$productLog = [regex]::Replace($plainLog, $certificatePattern, '')
$diagnostics = @([regex]::Matches($productLog, '(?im)^(?:SCRIPT ERROR|ERROR|WARNING):[^\r\n]*') | ForEach-Object { $_.Value.Trim() })
foreach ($leakPattern in @('Leaked instance:', 'ObjectDB instances? (?:was|were) leaked at exit', 'resources? still in use at exit', 'Resource still in use:', 'Orphan StringName:', 'unclaimed string names at exit')) {
    if ([regex]::IsMatch($productLog, $leakPattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
        $diagnostics += "leak signature: $leakPattern"
    }
}
if ($diagnostics.Count -ne 0) {
    $failures.Add("Product diagnostics were found: $($diagnostics -join ' | ')")
}
$marker = 'UI_CAPTURE_ACCEPTANCE_PASSED captures=33 physical=2880x1800'
$markerCount = [regex]::Matches($stdoutText, "(?m)^$([regex]::Escape($marker))\r?$").Count
if ($markerCount -ne 1) {
    $failures.Add("Expected the success marker exactly once in stdout; found $markerCount.")
}

$resultPath = Join-Path $captureRoot 'capture-result.json'
$validatedCaptures = [System.Collections.Generic.List[object]]::new()
if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
    $failures.Add("Capture result is missing: $resultPath")
}
else {
    try {
        $null = Assert-MayorNotReparsePoint -Path $captureRoot -Label 'Screenshot output directory'
        $resultItem = Assert-MayorNotReparsePoint -Path $resultPath -Label 'Capture result'
        if ($resultItem.PSIsContainer) { throw 'capture-result.json is a directory.' }
        $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
        if ([int]$result.schema_version -ne 1 -or [string]$result.suite -cne 'mayor-simulator-ui-capture-acceptance' -or [string]$result.status -cne 'PASS') {
            throw 'Capture result schema, suite, or status is invalid.'
        }
        if ([int]$result.required_capture_count -ne 33 -or [int]$result.capture_count -ne 33 -or @($result.captures).Count -ne 33) {
            throw 'Capture result does not contain the complete 33-state contract.'
        }
        if (@($result.physical_size).Count -ne 2 -or [int]$result.physical_size[0] -ne 2880 -or [int]$result.physical_size[1] -ne 1800) {
            throw 'Capture result physical size is not exactly 2880x1800.'
        }
        if (-not ([IO.Path]::GetFullPath([string]$result.output_directory)).Equals([IO.Path]::GetFullPath($captureRoot), [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Capture result output_directory does not match the wrapper-owned screenshot directory.'
        }

        $seenStates = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $seenFilenames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($capture in @($result.captures)) {
            $state = [string]$capture.state
            $filename = [string]$capture.filename
            if (-not $seenStates.Add($state) -or -not $seenFilenames.Add($filename)) { throw "Duplicate capture state or filename: $state / $filename" }
            if (-not $expectedCaptures.Contains($state) -or [string]$expectedCaptures[$state] -cne $filename) { throw "Unexpected capture mapping: $state / $filename" }
            if ([IO.Path]::GetFileName($filename) -cne $filename -or $filename -notmatch '^[a-z0-9-]+\.png$') { throw "Unsafe capture filename: $filename" }
            $pngPath = Join-Path $captureRoot $filename
            if (-not (Test-Path -LiteralPath $pngPath -PathType Leaf)) { throw "Capture PNG is missing: $pngPath" }
            $pngItem = Assert-MayorNotReparsePoint -Path $pngPath -Label "Capture PNG '$state'"
            $header = Get-PngHeader -Path $pngPath
            $hash = (Get-FileHash -LiteralPath $pngPath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($header.width -ne 2880 -or $header.height -ne 1800 -or [int]$capture.width -ne 2880 -or [int]$capture.height -ne 1800) { throw "Capture dimensions are invalid for $state." }
            if ([long]$capture.bytes -ne [long]$pngItem.Length -or [long]$pngItem.Length -le 24) { throw "Capture byte count is invalid for $state." }
            if ([string]$capture.sha256 -cne $hash -or $hash -notmatch '^[0-9a-f]{64}$') { throw "Capture SHA-256 mismatch for $state." }
            $validatedCaptures.Add([pscustomobject][ordered]@{ state=$state; filename=$filename; width=2880; height=1800; bytes=[long]$pngItem.Length; sha256=$hash })
        }
        foreach ($state in $expectedCaptures.Keys) {
            if (-not $seenStates.Contains([string]$state)) { throw "Capture state is missing: $state" }
        }
        $items = @(Get-ChildItem -LiteralPath $captureRoot -Force)
        $expectedNames = @($expectedCaptures.Values) + 'capture-result.json'
        if ($items.Count -ne $expectedNames.Count) { throw "Screenshot directory item count mismatch: expected $($expectedNames.Count), found $($items.Count)." }
        foreach ($item in $items) {
            if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Name -cnotin $expectedNames) { throw "Unexpected screenshot output item: $($item.FullName)" }
        }
    }
    catch {
        $failures.Add("Capture evidence validation failed: $($_.Exception.Message)")
    }
}

try {
    foreach ($item in @(Get-ChildItem -LiteralPath $OutputRoot -Recurse -Force)) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Evidence tree contains a reparse point: $($item.FullName)" }
    }
}
catch {
    $failures.Add($_.Exception.Message)
}

try {
    $postFingerprint = Get-MayorSourceFingerprint -ProjectRoot $projectRoot
    if ([string]$postFingerprint.fingerprint_sha256 -cne [string]$preFingerprint.fingerprint_sha256 -or
        [int]$postFingerprint.file_count -ne [int]$preFingerprint.file_count -or
        [long]$postFingerprint.total_bytes -ne [long]$preFingerprint.total_bytes) {
        $failures.Add('Source fingerprint changed during UI capture acceptance.')
    }
}
catch {
    $failures.Add("Post-run source fingerprint failed: $($_.Exception.Message)")
    $postFingerprint = $null
}

if ($failures.Count -ne 0) {
    foreach ($failure in $failures) { Write-Error $failure -ErrorAction Continue }
    exit 1
}

$summaryPath = Join-Path $OutputRoot 'summary.json'
$summaryPartialPath = $summaryPath + '.partial'
$fileEvidence = [ordered]@{}
foreach ($path in @($stdoutPath, $stderrPath, $godotLogPath, $resultPath)) {
    $record = Get-FileRecord -Path $path
    $fileEvidence[$record.path] = $record
}
$summary = [ordered]@{
    schema_version = 1
    suite = 'mayor-simulator-ui-capture-acceptance'
    status = 'PASS'
    output_root_policy = 'refuse_existing_workspace_directory'
    project_root = $projectRoot
    output_root = $OutputRoot
    started_at_utc = $startedAt.ToString('o')
    finished_at_utc = $finishedAt.ToString('o')
    duration_seconds = [Math]::Round(($finishedAt - $startedAt).TotalSeconds, 3)
    godot_executable = [ordered]@{ path=$GodotExe; bytes=[long]$godotItem.Length; sha256=(Get-FileHash -LiteralPath $GodotExe -Algorithm SHA256).Hash.ToLowerInvariant() }
    process = [ordered]@{ completed=$completed; exit_code=$exitCode; timeout_seconds=$TimeoutSeconds; output_capture_complete=$outputCaptureComplete }
    required_capture_count = 33
    capture_count = $validatedCaptures.Count
    physical_size = @(2880, 1800)
    success_marker = $marker
    success_marker_count = $markerCount
    environment_warning_count = $environmentWarningCount
    product_diagnostic_count = 0
    source = [ordered]@{ file_count=[int]$preFingerprint.file_count; total_bytes=[long]$preFingerprint.total_bytes; pre_fingerprint_sha256=[string]$preFingerprint.fingerprint_sha256; post_fingerprint_sha256=[string]$postFingerprint.fingerprint_sha256; unchanged=$true }
    captures = @($validatedCaptures)
    files = $fileEvidence
}
[IO.File]::WriteAllText($summaryPartialPath, ($summary | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
[IO.File]::Move($summaryPartialPath, $summaryPath)
Write-Output "UI capture acceptance passed: captures=33 physical=2880x1800 output=$OutputRoot"
exit 0
