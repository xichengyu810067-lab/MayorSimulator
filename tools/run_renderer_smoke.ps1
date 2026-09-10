#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$GodotExe,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$OutputRoot,
    [ValidateSet('Mobile', 'Compatibility')][string]$RendererMode = 'Mobile',
    [ValidateRange(15, 300)][int]$TimeoutSeconds = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-NotReparsePoint {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Label)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "$Label must not be a symlink, junction, or other reparse point: $($item.FullName)"
    }
    return $item
}

function Test-PathInside {
    param([Parameter(Mandatory)][string]$Candidate, [Parameter(Mandatory)][string]$Parent)
    $candidateFull = [IO.Path]::GetFullPath($Candidate).TrimEnd('\', '/')
    $parentFull = [IO.Path]::GetFullPath($Parent).TrimEnd('\', '/')
    return $candidateFull.StartsWith($parentFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Assert-ExistingPathChainSafe {
    param([Parameter(Mandatory)][string]$ProjectRoot, [Parameter(Mandatory)][string]$Candidate)
    $rootFull = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\', '/')
    $candidateFull = [IO.Path]::GetFullPath($Candidate).TrimEnd('\', '/')
    if ($candidateFull -ne $rootFull -and -not (Test-PathInside -Candidate $candidateFull -Parent $rootFull)) {
        throw "Path escaped the project worktree: $candidateFull"
    }
    $null = Assert-NotReparsePoint -Path $rootFull -Label 'Project root'
    $relative = $candidateFull.Substring($rootFull.Length).TrimStart('\', '/')
    $current = $rootFull
    foreach ($part in @($relative -split '[\\/]+' | Where-Object { $_ -ne '' })) {
        $current = Join-Path $current $part
        if (Test-Path -LiteralPath $current) {
            $null = Assert-NotReparsePoint -Path $current -Label 'Output path component'
        }
    }
}

function Get-TextSha256 {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $hasher = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
        return ([BitConverter]::ToString($hasher.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        $hasher.Dispose()
    }
}

function Get-GitOutput {
    param([Parameter(Mandatory)][string]$ProjectRoot, [Parameter(Mandatory)][string[]]$Arguments)
    $output = @(& git -c "safe.directory=$ProjectRoot" -c core.quotePath=false -C $ProjectRoot @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "Git command failed: $($output -join ' ')" }
    return $output
}

function Get-SourceFingerprint {
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $records = [Collections.Generic.List[string]]::new()
    $fileCount = 0
    $totalBytes = [long]0
    foreach ($line in @(Get-GitOutput -ProjectRoot $ProjectRoot -Arguments @('ls-files', '--stage'))) {
        if ([string]$line -notmatch '^([0-9]{6}) ([0-9a-f]{40,64}) ([0-9]+)\t(.*)$') {
            throw "Unexpected git ls-files record: $line"
        }
        $mode = $Matches[1]
        $objectId = $Matches[2]
        $relative = $Matches[4]
        if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative)) {
            throw "Unsafe tracked source path: $relative"
        }
        if ($mode -eq '160000') {
            $records.Add("$relative`tgitlink`t$objectId")
            continue
        }
        $path = [IO.Path]::GetFullPath((Join-Path $ProjectRoot $relative))
        if (-not (Test-PathInside -Candidate $path -Parent $ProjectRoot)) {
            throw "Tracked source escaped the project worktree: $relative"
        }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Tracked source file is missing or not a leaf: $relative"
        }
        $item = Assert-NotReparsePoint -Path $path -Label 'Tracked source file'
        $hash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $normalized = $relative.Replace('\', '/')
        $records.Add("$normalized`t$($item.Length)`t$hash")
        $fileCount++
        $totalBytes += [long]$item.Length
    }
    if ($records.Count -eq 0) { throw 'Source fingerprint contains no tracked records.' }
    $canonical = [string[]]$records.ToArray()
    [Array]::Sort($canonical, [StringComparer]::Ordinal)
    return [pscustomobject][ordered]@{
        algorithm = 'sha256(path-tab-bytes-tab-sha256-lf;gitlinks-by-object-id)'
        file_count = $fileCount
        total_bytes = $totalBytes
        fingerprint_sha256 = Get-TextSha256 -Text (($canonical -join "`n") + "`n")
    }
}

function Get-IsolatedUserDataPath {
    param([Parameter(Mandatory)][string]$ProjectRoot, [Parameter(Mandatory)][string]$AppDataRoot)
    $projectText = Get-Content -LiteralPath (Join-Path $ProjectRoot 'project.godot') -Raw -ErrorAction Stop
    $nameMatch = [regex]::Match($projectText, '(?m)^config/name="([^"\r\n]+)"\s*$')
    if (-not $nameMatch.Success) { throw 'project.godot has no simple application config/name for user:// isolation.' }
    $safeName = [regex]::Replace($nameMatch.Groups[1].Value, '[\\/:*?"<>|%]', '-')
    if ([string]::IsNullOrWhiteSpace($safeName)) { throw 'Godot user:// application directory name is empty.' }
    return Join-Path (Join-Path $AppDataRoot 'Godot\app_userdata') $safeName
}

function Initialize-WritableDirectory {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Label)
    New-Item -ItemType Directory -Path $Path -ErrorAction Stop | Out-Null
    $null = Assert-NotReparsePoint -Path $Path -Label $Label
    $probe = Join-Path $Path '.renderer-runner-write-probe'
    [IO.File]::WriteAllText($probe, 'writable', [Text.UTF8Encoding]::new($false))
    if (-not (Test-Path -LiteralPath $probe -PathType Leaf)) { throw "$Label is not writable: $Path" }
}

function ConvertTo-WindowsCommandLineArgument {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') { return $Value }
    $builder = New-Object Text.StringBuilder
    $null = $builder.Append('"')
    $backslashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') {
            $backslashes++
            continue
        }
        if ($character -eq '"') {
            $null = $builder.Append(('\' * ($backslashes * 2 + 1)))
            $null = $builder.Append('"')
            $backslashes = 0
            continue
        }
        if ($backslashes -gt 0) { $null = $builder.Append(('\' * $backslashes)); $backslashes = 0 }
        $null = $builder.Append($character)
    }
    if ($backslashes -gt 0) { $null = $builder.Append(('\' * ($backslashes * 2))) }
    $null = $builder.Append('"')
    return $builder.ToString()
}

$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..') -ErrorAction Stop).Path
$null = Assert-NotReparsePoint -Path $projectRoot -Label 'Project root'
$fixtureScript = 'res://tests/manual/intro_cinematic_visible_acceptance.gd'
$fixturePath = Join-Path $projectRoot 'tests\manual\intro_cinematic_visible_acceptance.gd'
if (-not (Test-Path -LiteralPath $fixturePath -PathType Leaf)) { throw "Intro visible acceptance fixture is missing: $fixtureScript" }
$null = Assert-NotReparsePoint -Path $fixturePath -Label 'Intro visible acceptance fixture'

if (Test-Path -LiteralPath $GodotExe -PathType Container) {
    throw "GodotExe must be an executable file, not a directory: $GodotExe"
}
if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) {
    throw "Godot executable not found: $GodotExe"
}
$godotItem = Assert-NotReparsePoint -Path $GodotExe -Label 'Godot executable'
$GodotExe = $godotItem.FullName

$outputsRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot '.tmp\renderer-smoke'))
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
if (-not (Test-PathInside -Candidate $outputsRoot -Parent $projectRoot)) {
    throw 'The renderer-smoke root escaped the project worktree.'
}
if (-not (Test-PathInside -Candidate $OutputRoot -Parent $outputsRoot)) {
    throw 'OutputRoot must be a fresh child of .tmp\renderer-smoke.'
}
if (Test-Path -LiteralPath $OutputRoot) {
    throw "OutputRoot already exists and cannot be reused: $OutputRoot"
}
Assert-ExistingPathChainSafe -ProjectRoot $projectRoot -Candidate $OutputRoot

if (Test-Path -LiteralPath $outputsRoot -PathType Leaf) { throw "Renderer-smoke root must be a directory: $outputsRoot" }
if (-not (Test-Path -LiteralPath $outputsRoot)) { New-Item -ItemType Directory -Path $outputsRoot -ErrorAction Stop | Out-Null }
$null = Assert-NotReparsePoint -Path $outputsRoot -Label 'Renderer-smoke root'

$branch = (@(Get-GitOutput -ProjectRoot $projectRoot -Arguments @('branch', '--show-current')) -join '').Trim()
$head = (@(Get-GitOutput -ProjectRoot $projectRoot -Arguments @('rev-parse', 'HEAD')) -join '').Trim()
$tree = (@(Get-GitOutput -ProjectRoot $projectRoot -Arguments @('rev-parse', 'HEAD^{tree}')) -join '').Trim()
$statusText = @(Get-GitOutput -ProjectRoot $projectRoot -Arguments @('status', '--porcelain=v1', '--untracked-files=all')) -join "`n"
if (-not [string]::IsNullOrWhiteSpace($statusText)) { throw 'Renderer smoke requires a clean committed worktree.' }
$statusSha256 = Get-TextSha256 -Text $statusText
$pre = Get-SourceFingerprint -ProjectRoot $projectRoot

New-Item -ItemType Directory -Path $OutputRoot -ErrorAction Stop | Out-Null
$null = Assert-NotReparsePoint -Path $OutputRoot -Label 'Renderer smoke output'
$appData = Join-Path $OutputRoot 'appdata'
$localAppData = Join-Path $OutputRoot 'localappdata'
$userData = Get-IsolatedUserDataPath -ProjectRoot $projectRoot -AppDataRoot $appData
Initialize-WritableDirectory -Path $appData -Label 'APPDATA isolation directory'
Initialize-WritableDirectory -Path $localAppData -Label 'LOCALAPPDATA isolation directory'
Initialize-WritableDirectory -Path $userData -Label 'Godot user:// isolation directory'

$renderer = if ($RendererMode -eq 'Mobile') {
    @{ method = 'mobile'; driver = 'vulkan'; renderer_pattern = '(?im)^.*Vulkan.*Forward Mobile.*$' }
} else {
    @{ method = 'gl_compatibility'; driver = 'opengl3'; renderer_pattern = '(?im)^.*OpenGL.*Compatibility.*$' }
}
$stdoutPath = Join-Path $OutputRoot 'stdout.log'
$stderrPath = Join-Path $OutputRoot 'stderr.log'
$godotLogPath = Join-Path $OutputRoot 'godot.log'
$importStdoutPath = Join-Path $OutputRoot 'import-stdout.log'
$importStderrPath = Join-Path $OutputRoot 'import-stderr.log'
$importGodotLogPath = Join-Path $OutputRoot 'import-godot.log'
$summaryPath = Join-Path $OutputRoot 'summary.json'

$godotProcessNames = @([IO.Path]::GetFileNameWithoutExtension($GodotExe))
if ($godotProcessNames[0].EndsWith('_console', [StringComparison]::OrdinalIgnoreCase)) {
    $godotProcessNames += $godotProcessNames[0].Substring(0, $godotProcessNames[0].Length - '_console'.Length)
}
$baselineProcessIds = @(Get-Process -Name $godotProcessNames -ErrorAction SilentlyContinue | ForEach-Object { [int]$_.Id })
$fixedArguments = @(
    '--verbose', '--path', $projectRoot,
    '--rendering-method', $renderer.method,
    '--rendering-driver', $renderer.driver,
    '--script', $fixtureScript,
    '--log-file', $godotLogPath
)

$importStdoutText = ''
$importStderrText = ''
$importCompleted = $false
$importExitCode = -1
$importLaunchError = $null
$importProcess = $null
$importProcessId = -1
try {
    $importInfo = New-Object Diagnostics.ProcessStartInfo
    $importInfo.FileName = $GodotExe
    $importInfo.WorkingDirectory = $projectRoot
    $importInfo.UseShellExecute = $false
    $importInfo.RedirectStandardOutput = $true
    $importInfo.RedirectStandardError = $true
    $importInfo.CreateNoWindow = $true
    $importArguments = @('--headless', '--editor', '--path', $projectRoot, '--import', '--log-file', $importGodotLogPath)
    $importInfo.Arguments = (($importArguments | ForEach-Object { ConvertTo-WindowsCommandLineArgument -Value ([string]$_) }) -join ' ')
    $importInfo.EnvironmentVariables['APPDATA'] = $appData
    $importInfo.EnvironmentVariables['LOCALAPPDATA'] = $localAppData
    $importProcess = New-Object Diagnostics.Process
    $importProcess.StartInfo = $importInfo
    if (-not $importProcess.Start()) { throw 'Godot import process did not start.' }
    $importProcessId = [int]$importProcess.Id
    $importOutTask = $importProcess.StandardOutput.ReadToEndAsync()
    $importErrTask = $importProcess.StandardError.ReadToEndAsync()
    $importCompleted = $importProcess.WaitForExit($TimeoutSeconds * 1000)
    if (-not $importCompleted) {
        & taskkill.exe /PID $importProcessId /T /F *> $null
        $null = $importProcess.WaitForExit(30000)
    }
    if (-not $importProcess.HasExited) { throw 'Godot import process tree did not exit after timeout cleanup.' }
    if (-not $importOutTask.Wait(15000) -or -not $importErrTask.Wait(15000)) { throw 'Godot import output pipes did not close.' }
    $importStdoutText = $importOutTask.GetAwaiter().GetResult()
    $importStderrText = $importErrTask.GetAwaiter().GetResult()
    if ($importCompleted) { $importExitCode = [int]$importProcess.ExitCode }
} catch {
    $importLaunchError = $_.Exception.Message
} finally {
    if ($null -ne $importProcess) { $importProcess.Dispose() }
    [IO.File]::WriteAllText($importStdoutPath, $importStdoutText, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($importStderrPath, $importStderrText, [Text.UTF8Encoding]::new($false))
}

$stdoutText = ''
$stderrText = ''
$completed = $false
$exitCode = -1
$launchError = $null
$process = $null
$launcherProcessId = -1
try {
    if ($importLaunchError) { throw "Godot import failed to launch: $importLaunchError" }
    if (-not $importCompleted) { throw 'Godot import did not complete before timeout.' }
    if ($importExitCode -ne 0) { throw "Godot import exit code was $importExitCode." }
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $GodotExe
    $info.WorkingDirectory = $projectRoot
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.CreateNoWindow = $false
    $info.Arguments = (($fixedArguments | ForEach-Object { ConvertTo-WindowsCommandLineArgument -Value ([string]$_) }) -join ' ')
    $info.EnvironmentVariables['APPDATA'] = $appData
    $info.EnvironmentVariables['LOCALAPPDATA'] = $localAppData
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    if (-not $process.Start()) { throw 'Godot process did not start.' }
    $launcherProcessId = [int]$process.Id
    $outTask = $process.StandardOutput.ReadToEndAsync()
    $errTask = $process.StandardError.ReadToEndAsync()
    $completed = $process.WaitForExit($TimeoutSeconds * 1000)
    if (-not $completed) {
        & taskkill.exe /PID $launcherProcessId /T /F *> $null
        $null = $process.WaitForExit(30000)
    }
    if (-not $process.HasExited) { throw 'Godot process tree did not exit after timeout cleanup.' }
    if (-not $outTask.Wait(15000) -or -not $errTask.Wait(15000)) { throw 'Godot output pipes did not close.' }
    $stdoutText = $outTask.GetAwaiter().GetResult()
    $stderrText = $errTask.GetAwaiter().GetResult()
    if ($completed) { $exitCode = [int]$process.ExitCode }
} catch {
    $launchError = $_.Exception.Message
} finally {
    if ($null -ne $process) { $process.Dispose() }
    [IO.File]::WriteAllText($stdoutPath, $stdoutText, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($stderrPath, $stderrText, [Text.UTF8Encoding]::new($false))
}

Start-Sleep -Seconds 2
$residualProcessIds = @(
    Get-Process -Name $godotProcessNames -ErrorAction SilentlyContinue |
        Where-Object { $baselineProcessIds -notcontains [int]$_.Id } |
        ForEach-Object { [int]$_.Id }
)
$cleanupConfirmed = $residualProcessIds.Count -eq 0
$failures = [Collections.Generic.List[string]]::new()
if ($launchError) { $failures.Add("Godot launch failed: $launchError") }
if (-not $completed) { $failures.Add('Godot did not complete before timeout.') }
if ($exitCode -ne 0) { $failures.Add("Godot exit code was $exitCode.") }
if (-not $cleanupConfirmed) { $failures.Add("Godot process cleanup incomplete: $($residualProcessIds -join ',')") }

$godotLogText = if (Test-Path -LiteralPath $godotLogPath -PathType Leaf) { Get-Content -LiteralPath $godotLogPath -Raw } else { '' }
$importGodotLogText = if (Test-Path -LiteralPath $importGodotLogPath -PathType Leaf) { Get-Content -LiteralPath $importGodotLogPath -Raw } else { '' }
$plainLog = ($importStdoutText + "`n" + $importStderrText + "`n" + $importGodotLogText + "`n" + $stdoutText + "`n" + $stderrText + "`n" + $godotLogText) -replace "`e\[[0-?]*[ -/]*[@-~]", ''
$environmentDiagnostics = @([regex]::Matches($plainLog, '(?im)^.*Failed to read the root certificate store.*$') | ForEach-Object { $_.Value.Trim() } | Sort-Object -Unique)
$productLog = [regex]::Replace($plainLog, '(?im)^.*Failed to read the root certificate store.*$', '')
$unexpectedDiagnostics = @([regex]::Matches($productLog, '(?im)^(?:SCRIPT ERROR|ERROR|WARNING):[^\r\n]*') | ForEach-Object { $_.Value.Trim() } | Sort-Object -Unique)
foreach ($pattern in @('Leaked instance:', 'ObjectDB instances? (?:was|were) leaked at exit', 'resources? still in use at exit', 'Resource still in use:', 'Orphan StringName:', 'unclaimed string names at exit')) {
    if ([regex]::IsMatch($productLog, $pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
        $unexpectedDiagnostics += "leak signature: $pattern"
    }
}
$crashLines = @([regex]::Matches($productLog, '(?im)^.*(?:igxelpicd64|EXCEPTION_ACCESS_VIOLATION|unhandled exception|fatal error).*$') | ForEach-Object { $_.Value.Trim() } | Sort-Object -Unique)
$unexpectedDiagnostics += $crashLines
$unexpectedDiagnostics = @($unexpectedDiagnostics | Sort-Object -Unique)
if ($unexpectedDiagnostics.Count -gt 0) { $failures.Add("Unexpected product diagnostics: $($unexpectedDiagnostics -join ' | ')") }

$readyMarker = 'VISIBLE_INTRO_CINEMATIC_READY:'
$completionMarker = 'VISIBLE_INTRO_CINEMATIC_ACCEPTANCE_COMPLETED'
$readyCount = [regex]::Matches($stdoutText, "(?m)^$([regex]::Escape($readyMarker)).*$").Count
$completionCount = [regex]::Matches($stdoutText, "(?m)^$([regex]::Escape($completionMarker))\s*$").Count
if ($readyCount -ne 1) { $failures.Add("Expected intro ready marker exactly once; found $readyCount.") }
if ($completionCount -ne 1) { $failures.Add("Expected intro completion marker exactly once; found $completionCount.") }
$rendererMatches = @([regex]::Matches($plainLog, $renderer.renderer_pattern) | ForEach-Object { $_.Value.Trim() } | Sort-Object -Unique)
if ($rendererMatches.Count -lt 1) {
    $failures.Add("Renderer log did not prove $RendererMode via $($renderer.method)/$($renderer.driver).")
}

$post = $null
$postStatusText = ''
$finalHead = ''
$finalTree = ''
try {
    $post = Get-SourceFingerprint -ProjectRoot $projectRoot
    $postStatusText = @(Get-GitOutput -ProjectRoot $projectRoot -Arguments @('status', '--porcelain=v1', '--untracked-files=all')) -join "`n"
    $finalHead = (@(Get-GitOutput -ProjectRoot $projectRoot -Arguments @('rev-parse', 'HEAD')) -join '').Trim()
    $finalTree = (@(Get-GitOutput -ProjectRoot $projectRoot -Arguments @('rev-parse', 'HEAD^{tree}')) -join '').Trim()
    if ($post.fingerprint_sha256 -cne $pre.fingerprint_sha256 -or (Get-TextSha256 -Text $postStatusText) -cne $statusSha256 -or $finalHead -cne $head -or $finalTree -cne $tree) {
        throw 'Source identity changed during renderer smoke.'
    }
} catch {
    $failures.Add("Post-run source identity failed: $($_.Exception.Message)")
}

$summary = [ordered]@{
    schema_version = 1
    suite = 'mayor-simulator-intro-renderer-smoke'
    status = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
    renderer = [ordered]@{
        requested_mode = $RendererMode
        rendering_method = $renderer.method
        rendering_driver = $renderer.driver
        log_matches = $rendererMatches
    }
    fixture = $fixtureScript
    markers = [ordered]@{ ready = $readyMarker; ready_count = $readyCount; completion = $completionMarker; completion_count = $completionCount }
    isolation = [ordered]@{ appdata = $appData; localappdata = $localAppData; user_data = $userData; precreated_and_writable = $true }
    process = [ordered]@{
        import_process_id = $importProcessId
        import_completed = $importCompleted
        import_exit_code = $importExitCode
        launcher_process_id = $launcherProcessId
        completed = $completed
        exit_code = $exitCode
        timeout_seconds = $TimeoutSeconds
        baseline_process_ids = $baselineProcessIds
        residual_process_ids = $residualProcessIds
        cleanup_confirmed = $cleanupConfirmed
    }
    source = [ordered]@{
        worktree = $projectRoot
        branch = $branch
        head = $head
        tree = $tree
        status_sha256 = $statusSha256
        fingerprint_algorithm = $pre.algorithm
        fingerprint_file_count = $pre.file_count
        fingerprint_total_bytes = $pre.total_bytes
        pre_fingerprint_sha256 = $pre.fingerprint_sha256
        post_fingerprint_sha256 = if ($null -ne $post) { $post.fingerprint_sha256 } else { $null }
        final_head = $finalHead
        final_tree = $finalTree
        unchanged = ($null -ne $post -and $post.fingerprint_sha256 -ceq $pre.fingerprint_sha256 -and $finalHead -ceq $head -and $finalTree -ceq $tree)
    }
    environment_diagnostics = $environmentDiagnostics
    unexpected_diagnostics = $unexpectedDiagnostics
    failures = @($failures)
}
[IO.File]::WriteAllText($summaryPath, ($summary | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Error $failure }
    exit 1
}
Write-Output "Renderer smoke passed: mode=$RendererMode output=$OutputRoot"
