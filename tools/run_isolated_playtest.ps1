#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()][string]$GodotExe = 'C:\Users\USER\Tools\Godot\Godot_v4.7-stable_win64.exe',
    [ValidatePattern('^[A-Za-z0-9](?:[A-Za-z0-9._-]{0,62}[A-Za-z0-9_-])?$')][string]$ProfileName = 'manual-visible',
    [ValidateSet('Mobile', 'Compatibility')][string]$RendererMode = 'Mobile'
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
    New-Item -ItemType Directory -Path $Path -ErrorAction Stop | Out-Null
    $null = Assert-NotReparsePoint -Path $Path -Label $Label
    $probe = Join-Path $Path '.renderer-runner-write-probe'
    [IO.File]::WriteAllText($probe, 'writable', [Text.UTF8Encoding]::new($false))
    if (-not (Test-Path -LiteralPath $probe -PathType Leaf)) { throw "$Label is not writable: $Path" }
}

$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..') -ErrorAction Stop).Path
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
$arguments = @(
    '--path', $projectRoot,
    '--rendering-method', $renderer.method,
    '--rendering-driver', $renderer.driver,
    '--log-file', $godotLog
)

$env:APPDATA = $isolatedAppData
$env:LOCALAPPDATA = $isolatedLocalAppData
Write-Output "Launching isolated playtest profile: $profileRoot"
Write-Output "Renderer mode: $RendererMode ($($renderer.method)/$($renderer.driver))"
Write-Output "Isolated Godot user:// root: $isolatedUserData"
& $GodotExe @arguments
exit $LASTEXITCODE
