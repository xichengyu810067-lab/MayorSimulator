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
$expectedNativeCaptures = [ordered]@{
    start = [ordered]@{ filename = 'native-start-screen.png'; landmark = 'start_actions' }
    main = [ordered]@{ filename = 'native-main.png'; landmark = 'status_hud' }
    settings = [ordered]@{ filename = 'native-settings.png'; landmark = 'settings_panel' }
    municipal_overlay = [ordered]@{ filename = 'native-municipal-overlay.png'; landmark = 'municipal_overlay' }
}
if ($expectedNativeCaptures.Count -ne 4) {
    throw "Internal native GUI capture contract must contain exactly 4 states; found $($expectedNativeCaptures.Count)."
}

$preFingerprint = Get-MayorSourceFingerprint -ProjectRoot $projectRoot
New-Item -ItemType Directory -Path $OutputRoot -ErrorAction Stop | Out-Null
$null = Assert-MayorNotReparsePoint -Path $OutputRoot -Label 'UI capture output root'

$captureRoot = Join-Path $OutputRoot 'screenshots'
$nativeCaptureRoot = Join-Path $OutputRoot 'native-window'
Assert-PathChainWithoutReparsePoint -Candidate $captureRoot -Boundary $projectRoot
Assert-PathChainWithoutReparsePoint -Candidate $nativeCaptureRoot -Boundary $projectRoot
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
        '--', "--ui-capture-output-dir=$captureRoot", "--ui-native-output-dir=$nativeCaptureRoot"
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
$marker = 'UI_CAPTURE_CANONICAL_ACCEPTANCE_PASSED native_gui=PASS native_captures=4 offscreen_evidence=PASS offscreen_captures=33 physical=2880x1800 logical=1280x800'
$markerCount = [regex]::Matches($stdoutText, "(?m)^$([regex]::Escape($marker))\r?$").Count
if ($markerCount -ne 1) {
    $failures.Add("Expected the success marker exactly once in stdout; found $markerCount.")
}

$nativeResultPath = Join-Path $nativeCaptureRoot 'native-result.json'
$validatedNativeCaptures = [System.Collections.Generic.List[object]]::new()
if (-not (Test-Path -LiteralPath $nativeResultPath -PathType Leaf)) {
    $failures.Add("Native GUI result is missing: $nativeResultPath")
}
else {
    try {
        $null = Assert-MayorNotReparsePoint -Path $nativeCaptureRoot -Label 'Native GUI output directory'
        $nativeResultItem = Assert-MayorNotReparsePoint -Path $nativeResultPath -Label 'Native GUI result'
        if ($nativeResultItem.PSIsContainer) { throw 'native-result.json is a directory.' }
        $nativeResult = Get-Content -LiteralPath $nativeResultPath -Raw | ConvertFrom-Json
        if ([int]$nativeResult.schema_version -ne 1 -or
            [string]$nativeResult.suite -cne 'mayor-simulator-native-window-ui-acceptance' -or
            [string]$nativeResult.status -cne 'PASS' -or
            [string]$nativeResult.native_gui_status -cne 'PASS' -or
            [string]$nativeResult.capture_role -cne 'native_gui') {
            throw 'Native GUI result schema, suite, or PASS statuses are invalid.'
        }
        if ([string]$nativeResult.capture_surface_kind -cne 'native_fullscreen_root' -or
            [string]$nativeResult.scene_parent -cne 'root_window' -or
            [bool]$nativeResult.uses_subviewport -or
            [bool]$nativeResult.capture_surface_mirrored) {
            throw 'Native GUI result was not captured from an unmirrored Main scene attached directly to the root window.'
        }
        if ([string]$nativeResult.window_mode -cnotin @('fullscreen', 'exclusive_fullscreen')) {
            throw "Native GUI window mode is invalid: $($nativeResult.window_mode)"
        }
        if ([int]$nativeResult.required_capture_count -ne 4 -or [int]$nativeResult.capture_count -ne 4 -or @($nativeResult.captures).Count -ne 4) {
            throw 'Native GUI result does not contain the complete four-state contract.'
        }
        if (@($nativeResult.physical_size).Count -ne 2 -or @($nativeResult.logical_size).Count -ne 2 -or
            @($nativeResult.window_size).Count -ne 2 -or @($nativeResult.root_texture_size).Count -ne 2) {
            throw 'Native GUI result is missing measured surface dimensions.'
        }
        if ([string]$nativeResult.physical_size_role -cne 'native_root_capture_and_os_window_pixels' -or
            [string]$nativeResult.window_size_role -cne 'os_fullscreen_window') {
            throw 'Native GUI result does not identify its native-capture and OS-window size roles.'
        }
        $nativeWidth = [int]$nativeResult.physical_size[0]
        $nativeHeight = [int]$nativeResult.physical_size[1]
        $nativeLogicalWidth = [int]$nativeResult.logical_size[0]
        $nativeLogicalHeight = [int]$nativeResult.logical_size[1]
        $nativeWindowWidth = [int]$nativeResult.window_size[0]
        $nativeWindowHeight = [int]$nativeResult.window_size[1]
        if ($nativeWidth -lt 1280 -or $nativeHeight -lt 720 -or
            $nativeWindowWidth -lt 1280 -or $nativeWindowHeight -lt 720 -or
            $nativeLogicalWidth -lt 1280 -or $nativeLogicalHeight -lt 720) {
            throw "Native GUI dimensions are below acceptance minimums: backing=${nativeWidth}x${nativeHeight} window=${nativeWindowWidth}x${nativeWindowHeight} logical=${nativeLogicalWidth}x${nativeLogicalHeight}."
        }
        if ($nativeWindowWidth -ne $nativeWidth -or $nativeWindowHeight -ne $nativeHeight) {
            throw 'Native GUI capture pixels and OS-window dimensions do not match exactly.'
        }
        $nativeBackingWidth = [int]$nativeResult.root_texture_size[0]
        $nativeBackingHeight = [int]$nativeResult.root_texture_size[1]
        if ($nativeBackingWidth -lt 1280 -or $nativeBackingHeight -lt 720) {
            throw "Native GUI backing dimensions are below acceptance minimums: ${nativeBackingWidth}x${nativeBackingHeight}."
        }
        $backingScaleX = [double]$nativeBackingWidth / [double]$nativeLogicalWidth
        $backingScaleY = [double]$nativeBackingHeight / [double]$nativeLogicalHeight
        $windowScaleX = [double]$nativeWindowWidth / [double]$nativeLogicalWidth
        $windowScaleY = [double]$nativeWindowHeight / [double]$nativeLogicalHeight
        if ([Math]::Abs($backingScaleX - $backingScaleY) -gt 0.01 -or [Math]::Abs($windowScaleX - $windowScaleY) -gt 0.01) {
            throw 'Native GUI backing, OS-window, and logical dimensions are not uniformly scaled.'
        }
        if ([string]$nativeResult.display_server -eq '' -or [int]$nativeResult.current_screen_index -lt 0 -or
            [int]$nativeResult.current_screen_dpi -le 0 -or [double]$nativeResult.current_screen_scale -le 0.0 -or
            @($nativeResult.current_screen_size).Count -ne 2 -or [int]$nativeResult.current_screen_size[0] -le 0 -or [int]$nativeResult.current_screen_size[1] -le 0) {
            throw 'Native GUI current-screen DPI/scale metadata is invalid.'
        }
        if ([int]$nativeResult.current_screen_size[0] -ne $nativeWindowWidth -or [int]$nativeResult.current_screen_size[1] -ne $nativeWindowHeight) {
            throw 'Native GUI OS window does not fill the current screen.'
        }
        if (-not ([IO.Path]::GetFullPath([string]$nativeResult.output_directory)).Equals([IO.Path]::GetFullPath($nativeCaptureRoot), [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Native GUI output_directory does not match the wrapper-owned native-window directory.'
        }

        $seenNativeStates = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $seenNativeFilenames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $seenNativeHashes = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($capture in @($nativeResult.captures)) {
            $state = [string]$capture.state
            $filename = [string]$capture.filename
            if (-not $seenNativeStates.Add($state) -or -not $seenNativeFilenames.Add($filename)) { throw "Duplicate native capture state or filename: $state / $filename" }
            if (-not $expectedNativeCaptures.Contains($state) -or [string]$expectedNativeCaptures[$state].filename -cne $filename -or
                [string]$expectedNativeCaptures[$state].landmark -cne [string]$capture.landmark) {
                throw "Unexpected native capture mapping or landmark: $state / $filename / $($capture.landmark)"
            }
            if ([IO.Path]::GetFileName($filename) -cne $filename -or $filename -notmatch '^[a-z0-9-]+\.png$') { throw "Unsafe native capture filename: $filename" }
            $pngPath = Join-Path $nativeCaptureRoot $filename
            if (-not (Test-Path -LiteralPath $pngPath -PathType Leaf)) { throw "Native capture PNG is missing: $pngPath" }
            $pngItem = Assert-MayorNotReparsePoint -Path $pngPath -Label "Native capture PNG '$state'"
            $header = Get-PngHeader -Path $pngPath
            $hash = (Get-FileHash -LiteralPath $pngPath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($header.width -ne $nativeWidth -or $header.height -ne $nativeHeight -or [int]$capture.width -ne $nativeWidth -or [int]$capture.height -ne $nativeHeight) { throw "Native capture dimensions are invalid for $state." }
            if ([long]$capture.bytes -ne [long]$pngItem.Length -or [long]$pngItem.Length -le 24) { throw "Native capture byte count is invalid for $state." }
            if ([string]$capture.sha256 -cne $hash -or $hash -notmatch '^[0-9a-f]{64}$') { throw "Native capture SHA-256 mismatch for $state." }
            if (-not $seenNativeHashes.Add($hash)) { throw "Duplicate native capture content hash detected for $state." }
            if (@($capture.landmark_rect).Count -ne 4 -or [double]$capture.landmark_rect[2] -le 0.0 -or [double]$capture.landmark_rect[3] -le 0.0 -or
                [double]$capture.landmark_rect[0] -lt 0.0 -or [double]$capture.landmark_rect[1] -lt 0.0 -or
                ([double]$capture.landmark_rect[0] + [double]$capture.landmark_rect[2]) -gt ($nativeLogicalWidth + 1.0) -or
                ([double]$capture.landmark_rect[1] + [double]$capture.landmark_rect[3]) -gt ($nativeLogicalHeight + 1.0)) {
                throw "Native UI landmark geometry is invalid for $state."
            }
            $validatedNativeCaptures.Add([pscustomobject][ordered]@{ state=$state; filename=$filename; width=$nativeWidth; height=$nativeHeight; bytes=[long]$pngItem.Length; sha256=$hash; landmark=[string]$capture.landmark })
        }
        foreach ($state in $expectedNativeCaptures.Keys) {
            if (-not $seenNativeStates.Contains([string]$state)) { throw "Native capture state is missing: $state" }
        }
        $nativeItems = @(Get-ChildItem -LiteralPath $nativeCaptureRoot -Force)
        $expectedNativeNames = @($expectedNativeCaptures.Values | ForEach-Object { [string]$_.filename }) + 'native-result.json'
        if ($nativeItems.Count -ne $expectedNativeNames.Count) { throw "Native-window directory item count mismatch: expected $($expectedNativeNames.Count), found $($nativeItems.Count)." }
        foreach ($item in $nativeItems) {
            if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Name -cnotin $expectedNativeNames) { throw "Unexpected native-window output item: $($item.FullName)" }
        }
    }
    catch {
        $failures.Add("Native GUI evidence validation failed: $($_.Exception.Message)")
    }
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
        if ([int]$result.schema_version -ne 1 -or [string]$result.suite -cne 'mayor-simulator-ui-capture-acceptance' -or
            [string]$result.status -cne 'PASS' -or [string]$result.offscreen_evidence_status -cne 'PASS' -or
            [string]$result.capture_role -cne 'offscreen_evidence_only') {
            throw 'Capture result schema, suite, or status is invalid.'
        }
        $utcStyles = [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal
        $nativeStartedAt = [DateTimeOffset]::Parse([string]$nativeResult.started_at_utc, [Globalization.CultureInfo]::InvariantCulture, $utcStyles)
        $nativeFinishedAt = [DateTimeOffset]::Parse([string]$nativeResult.finished_at_utc, [Globalization.CultureInfo]::InvariantCulture, $utcStyles)
        $offscreenStartedAt = [DateTimeOffset]::Parse([string]$result.started_at_utc, [Globalization.CultureInfo]::InvariantCulture, $utcStyles)
        $offscreenFinishedAt = [DateTimeOffset]::Parse([string]$result.finished_at_utc, [Globalization.CultureInfo]::InvariantCulture, $utcStyles)
        if ($nativeStartedAt -gt $nativeFinishedAt -or $nativeFinishedAt -gt $offscreenStartedAt -or $offscreenStartedAt -gt $offscreenFinishedAt) {
            throw 'Native and offscreen evidence timestamps are not in monotonic phase order.'
        }
        if ([int]$result.required_capture_count -ne 33 -or [int]$result.capture_count -ne 33 -or @($result.captures).Count -ne 33) {
            throw 'Capture result does not contain the complete 33-state contract.'
        }
        if (@($result.physical_size).Count -ne 2 -or [int]$result.physical_size[0] -ne 2880 -or [int]$result.physical_size[1] -ne 1800) {
            throw 'Capture result physical size is not exactly 2880x1800.'
        }
        if (@($result.logical_size).Count -ne 2 -or [int]$result.logical_size[0] -ne 1280 -or [int]$result.logical_size[1] -ne 800) {
            throw 'Capture result logical size is not exactly 1280x800.'
        }
        $captureSurfaceKind = [string]$result.capture_surface_kind
        if ($captureSurfaceKind -cne 'offscreen_subviewport') {
            throw "33-state evidence must come from offscreen_subviewport; actual=$captureSurfaceKind"
        }
        $captureSurfaceMirrored = [bool]$result.capture_surface_mirrored
        if ($captureSurfaceKind -ceq 'offscreen_subviewport' -and $captureSurfaceMirrored) {
            throw 'Offscreen evidence capture must remain isolated from the native-resolution GUI acceptance window.'
        }
        if (@($result.native_window_size).Count -ne 2 -or [int]$result.native_window_size[0] -le 0 -or [int]$result.native_window_size[1] -le 0) {
            throw 'Capture result native_window_size is invalid.'
        }
        if (-not ([IO.Path]::GetFullPath([string]$result.output_directory)).Equals([IO.Path]::GetFullPath($captureRoot), [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Capture result output_directory does not match the wrapper-owned screenshot directory.'
        }

        $seenStates = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $seenFilenames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $seenHashes = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
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
            if (-not $seenHashes.Add($hash)) { throw "Duplicate capture content hash detected for $state." }
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
foreach ($path in @($stdoutPath, $stderrPath, $godotLogPath, $nativeResultPath, $resultPath)) {
    $record = Get-FileRecord -Path $path
    $fileEvidence[$record.path] = $record
}
$summary = [ordered]@{
    schema_version = 1
    suite = 'mayor-simulator-canonical-native-and-offscreen-ui-acceptance'
    status = 'PASS'
    native_gui_status = 'PASS'
    offscreen_evidence_status = 'PASS'
    output_root_policy = 'refuse_existing_workspace_directory'
    project_root = $projectRoot
    output_root = $OutputRoot
    started_at_utc = $startedAt.ToString('o')
    finished_at_utc = $finishedAt.ToString('o')
    duration_seconds = [Math]::Round(($finishedAt - $startedAt).TotalSeconds, 3)
    godot_executable = [ordered]@{ path=$GodotExe; bytes=[long]$godotItem.Length; sha256=(Get-FileHash -LiteralPath $GodotExe -Algorithm SHA256).Hash.ToLowerInvariant() }
    process = [ordered]@{ completed=$completed; exit_code=$exitCode; timeout_seconds=$TimeoutSeconds; output_capture_complete=$outputCaptureComplete }
    required_capture_count = 37
    capture_count = ($validatedNativeCaptures.Count + $validatedCaptures.Count)
    native_gui = [ordered]@{
        status = 'PASS'
        required_capture_count = 4
        capture_count = $validatedNativeCaptures.Count
        capture_surface_kind = 'native_fullscreen_root'
        scene_parent = 'root_window'
        physical_size = @($nativeWidth, $nativeHeight)
        physical_size_role = [string]$nativeResult.physical_size_role
        logical_size = @($nativeLogicalWidth, $nativeLogicalHeight)
        window_size = @([int]$nativeResult.window_size[0], [int]$nativeResult.window_size[1])
        root_texture_size = @([int]$nativeResult.root_texture_size[0], [int]$nativeResult.root_texture_size[1])
        display_server = [string]$nativeResult.display_server
        current_screen_index = [int]$nativeResult.current_screen_index
        current_screen_dpi = [int]$nativeResult.current_screen_dpi
        current_screen_scale = [double]$nativeResult.current_screen_scale
        current_screen_size = @([int]$nativeResult.current_screen_size[0], [int]$nativeResult.current_screen_size[1])
        started_at_utc = [string]$nativeResult.started_at_utc
        finished_at_utc = [string]$nativeResult.finished_at_utc
        captures = @($validatedNativeCaptures)
    }
    offscreen_evidence = [ordered]@{
        status = 'PASS'
        required_capture_count = 33
        capture_count = $validatedCaptures.Count
        physical_size = @(2880, 1800)
        logical_size = @(1280, 800)
        capture_surface_kind = $captureSurfaceKind
        capture_surface_mirrored = $captureSurfaceMirrored
        preview_window_size = @([int]$result.native_window_size[0], [int]$result.native_window_size[1])
        started_at_utc = [string]$result.started_at_utc
        finished_at_utc = [string]$result.finished_at_utc
        captures = @($validatedCaptures)
    }
    success_marker = $marker
    success_marker_count = $markerCount
    environment_warning_count = $environmentWarningCount
    product_diagnostic_count = 0
    source = [ordered]@{ file_count=[int]$preFingerprint.file_count; total_bytes=[long]$preFingerprint.total_bytes; pre_fingerprint_sha256=[string]$preFingerprint.fingerprint_sha256; post_fingerprint_sha256=[string]$postFingerprint.fingerprint_sha256; unchanged=$true }
    files = $fileEvidence
}
[IO.File]::WriteAllText($summaryPartialPath, ($summary | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
[IO.File]::Move($summaryPartialPath, $summaryPath)
Write-Output "Canonical UI acceptance passed: native_gui=PASS captures=4 capture=${nativeWidth}x${nativeHeight} backing=${nativeBackingWidth}x${nativeBackingHeight} window=${nativeWindowWidth}x${nativeWindowHeight} logical=${nativeLogicalWidth}x${nativeLogicalHeight}; offscreen_evidence=PASS captures=33 physical=2880x1800 output=$OutputRoot"
exit 0
