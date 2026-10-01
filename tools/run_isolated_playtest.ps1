#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()][string]$GodotExe = $(if ($env:GODOT_GUI_EXE) { $env:GODOT_GUI_EXE } else { 'Godot_v4.7-stable_win64.exe' }),
    [ValidatePattern('^[A-Za-z0-9](?:[A-Za-z0-9._-]{0,62}[A-Za-z0-9_-])?$')][string]$ProfileName = 'manual-visible',
    [ValidateSet('Mobile', 'Compatibility')][string]$RendererMode = 'Mobile',
    [ValidateRange(0, 600)][int]$MinimumRuntimeSeconds = 3,
    [string]$TestProjectRoot,
    [switch]$AllowSyntheticTestChild
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
    [IO.Directory]::CreateDirectory($Path) | Out-Null
    $null = Assert-NotReparsePoint -Path $Path -Label $Label
    $probe = Join-Path $Path '.renderer-runner-write-probe'
    [IO.File]::WriteAllText($probe, 'writable', [Text.UTF8Encoding]::new($false))
    if (-not (Test-Path -LiteralPath $probe -PathType Leaf)) { throw "$Label is not writable: $Path" }
}

function Get-GitOutput {
    param([Parameter(Mandatory)][string]$ProjectRoot, [Parameter(Mandatory)][string[]]$Arguments)
    $output = @(& git -c "safe.directory=$ProjectRoot" -c core.quotePath=false -C $ProjectRoot @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "Git command failed: $($output -join ' ')" }
    return $output
}

function Get-SourceIdentity {
    param([Parameter(Mandatory)][string]$ProjectRoot)
    return [ordered]@{
        branch = (@(Get-GitOutput -ProjectRoot $ProjectRoot -Arguments @('branch', '--show-current')) -join '').Trim()
        head = (@(Get-GitOutput -ProjectRoot $ProjectRoot -Arguments @('rev-parse', 'HEAD')) -join '').Trim()
        tree = (@(Get-GitOutput -ProjectRoot $ProjectRoot -Arguments @('rev-parse', 'HEAD^{tree}')) -join '').Trim()
        status = @(Get-GitOutput -ProjectRoot $ProjectRoot -Arguments @('status', '--porcelain=v1', '--untracked-files=all')) -join "`n"
    }
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
        if ($backslashes -gt 0) {
            $null = $builder.Append(('\' * $backslashes))
            $backslashes = 0
        }
        $null = $builder.Append($character)
    }
    if ($backslashes -gt 0) { $null = $builder.Append(('\' * ($backslashes * 2))) }
    $null = $builder.Append('"')
    return $builder.ToString()
}

$runnerProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..') -ErrorAction Stop).Path
$projectRoot = $runnerProjectRoot
if (-not [string]::IsNullOrWhiteSpace($TestProjectRoot)) {
    $candidateTestRoot = (Resolve-Path -LiteralPath $TestProjectRoot -ErrorAction Stop).Path
    $testRootsParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
    $testRootName = [IO.Path]::GetFileName($candidateTestRoot)
    if (-not (Test-PathInside -Candidate $candidateTestRoot -Parent $testRootsParent) -or $testRootName -notmatch '^mayor-isolated-playtest-contract-project-[0-9a-f]{32}$') {
        throw 'TestProjectRoot is restricted to a generated isolated-playtest contract fixture under the system temporary directory.'
    }
    $projectRoot = $candidateTestRoot
}
if ($AllowSyntheticTestChild -and [string]::IsNullOrWhiteSpace($TestProjectRoot)) {
    throw 'AllowSyntheticTestChild requires the restricted TestProjectRoot fixture.'
}
$null = Assert-NotReparsePoint -Path $projectRoot -Label 'Project root'
if ($ProfileName -match '^(?i:con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\..*)?$') {
    throw "ProfileName is reserved by Windows: $ProfileName"
}

if (Test-Path -LiteralPath $GodotExe -PathType Container) {
    throw "GodotExe must be an executable file, not a directory: $GodotExe"
}
if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) {
    throw "Godot executable not found: $GodotExe"
}
$godotItem = Assert-NotReparsePoint -Path $GodotExe -Label 'Godot executable'
$GodotExe = $godotItem.FullName
if (-not $AllowSyntheticTestChild -and [IO.Path]::GetExtension($GodotExe) -ine '.exe') {
    throw "GodotExe must be a leaf .exe file: $GodotExe"
}

$profilesRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot '.tmp\isolated-playtest'))
$profileRoot = [IO.Path]::GetFullPath((Join-Path $profilesRoot $ProfileName))
if (-not (Test-PathInside -Candidate $profilesRoot -Parent $projectRoot)) {
    throw 'The isolated-playtest root escaped the project worktree.'
}
if (-not (Test-PathInside -Candidate $profileRoot -Parent $profilesRoot)) {
    throw 'ProfileName escaped .tmp\isolated-playtest.'
}
if (Test-Path -LiteralPath $profileRoot) {
    throw "Profile output already exists and cannot be reused: $profileRoot"
}
Assert-ExistingPathChainSafe -ProjectRoot $projectRoot -Candidate $profileRoot

if (Test-Path -LiteralPath $profilesRoot -PathType Leaf) {
    throw "Isolated-playtest root must be a directory: $profilesRoot"
}
if (-not (Test-Path -LiteralPath $profilesRoot)) {
    New-Item -ItemType Directory -Path $profilesRoot -ErrorAction Stop | Out-Null
}
$null = Assert-NotReparsePoint -Path $profilesRoot -Label 'Isolated-playtest root'
New-Item -ItemType Directory -Path $profileRoot -ErrorAction Stop | Out-Null
$null = Assert-NotReparsePoint -Path $profileRoot -Label 'Profile output'

$isolatedAppData = Join-Path $profileRoot 'appdata'
$isolatedLocalAppData = Join-Path $profileRoot 'localappdata'
$isolatedUserData = Get-IsolatedUserDataPath -ProjectRoot $projectRoot -AppDataRoot $isolatedAppData
Initialize-WritableDirectory -Path $isolatedAppData -Label 'APPDATA isolation directory'
Initialize-WritableDirectory -Path $isolatedLocalAppData -Label 'LOCALAPPDATA isolation directory'
Initialize-WritableDirectory -Path $isolatedUserData -Label 'Godot user:// isolation directory'

$renderer = if ($RendererMode -eq 'Mobile') {
    @{ method = 'mobile'; driver = 'vulkan' }
} else {
    @{ method = 'gl_compatibility'; driver = 'opengl3' }
}
$godotLog = Join-Path $profileRoot 'godot.log'
$summaryPath = Join-Path $profileRoot 'playtest-result.json'
$arguments = @(
    '--path', $projectRoot,
    '--rendering-method', $renderer.method,
    '--rendering-driver', $renderer.driver,
    '--log-file', $godotLog
)

$env:APPDATA = $isolatedAppData
$env:LOCALAPPDATA = $isolatedLocalAppData
$sourceBefore = Get-SourceIdentity -ProjectRoot $projectRoot
if (-not [string]::IsNullOrWhiteSpace($sourceBefore.status)) {
    throw 'Isolated playtest requires a clean committed worktree.'
}

Write-Output "Launching isolated playtest profile: $profileRoot"
Write-Output "Renderer mode: $RendererMode ($($renderer.method)/$($renderer.driver))"
Write-Output "Isolated Godot user:// root: $isolatedUserData"
$startedAtUtc = [DateTime]::UtcNow
$process = $null
$processId = $null
$processStartUtc = $null
$launchError = $null
$exitCode = $null
try {
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $GodotExe
    $startInfo.WorkingDirectory = $projectRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $false
    $startInfo.Arguments = (($arguments | ForEach-Object { ConvertTo-WindowsCommandLineArgument -Value ([string]$_) }) -join ' ')
    $startInfo.EnvironmentVariables['APPDATA'] = $isolatedAppData
    $startInfo.EnvironmentVariables['LOCALAPPDATA'] = $isolatedLocalAppData
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $startInfo
    if (-not $process.Start()) { throw 'Godot process did not start.' }
    $processId = [int]$process.Id
    $processStartUtc = $process.StartTime.ToUniversalTime().ToString('o')
    $process.WaitForExit()
    $process.Refresh()
    $exitCode = [int]$process.ExitCode
} catch {
    $launchError = $_.Exception.Message
} finally {
    $endedAtUtc = [DateTime]::UtcNow
    if ($null -ne $process) { $process.Dispose() }
}

$durationMilliseconds = [int][Math]::Round(($endedAtUtc - $startedAtUtc).TotalMilliseconds)
$logExists = Test-Path -LiteralPath $godotLog -PathType Leaf
$logSha256 = if ($logExists) { (Get-FileHash -LiteralPath $godotLog -Algorithm SHA256).Hash.ToLowerInvariant() } else { $null }
$sourceAfter = Get-SourceIdentity -ProjectRoot $projectRoot
$sourceChanged = ($sourceBefore.branch -ne $sourceAfter.branch) -or ($sourceBefore.head -ne $sourceAfter.head) -or ($sourceBefore.tree -ne $sourceAfter.tree) -or ($sourceBefore.status -ne $sourceAfter.status)
$status = if ($launchError) {
    'launch_failed'
} elseif ($exitCode -ne 0) {
    'child_failed'
} elseif ($durationMilliseconds -lt ($MinimumRuntimeSeconds * 1000)) {
    'short_process'
} elseif (-not $logExists) {
    'missing_log'
} else {
    'passed'
}
if ($sourceChanged) { $status = 'source_changed' }
$summary = [ordered]@{
    schema_version = 1
    suite = 'mayor-simulator-isolated-native-playtest'
    status = $status
    renderer = [ordered]@{ requested_mode = $RendererMode; rendering_method = $renderer.method; rendering_driver = $renderer.driver }
    source = [ordered]@{ worktree = $projectRoot; before_run = $sourceBefore; after_run = $sourceAfter }
    isolation = [ordered]@{ profile_root = $profileRoot; appdata = $isolatedAppData; localappdata = $isolatedLocalAppData; user_data = $isolatedUserData; godot_log = $godotLog; godot_log_sha256 = $logSha256 }
    process = [ordered]@{ process_id = $processId; started_at_utc = $processStartUtc; ended_at_utc = $endedAtUtc.ToString('o'); duration_milliseconds = $durationMilliseconds; child_exit_code = $exitCode; minimum_runtime_seconds = $MinimumRuntimeSeconds; launch_error = $launchError }
}
[IO.File]::WriteAllText($summaryPath, ($summary | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
Write-Output "Isolated playtest result: status=$status pid=$($summary.process.process_id) exit=$exitCode log=$godotLog"
if ($status -eq 'passed') { exit 0 }
if ($null -ne $exitCode -and $exitCode -ne 0) { exit $exitCode }
if ($status -eq 'short_process') { exit 3 }
exit 1
