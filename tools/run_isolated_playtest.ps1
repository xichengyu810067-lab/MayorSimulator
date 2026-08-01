param(
    [string]$GodotExe = 'C:\Users\USER\Tools\Godot\Godot_v4.7-stable_win64.exe',
    [string]$ProfileName = 'manual-visible'
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$profileRoot = Join-Path $projectRoot ('.tmp\isolated-playtest\' + $ProfileName)
$isolatedAppData = Join-Path $profileRoot 'appdata'
$isolatedLocalAppData = Join-Path $profileRoot 'localappdata'

if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) {
    throw "Godot executable not found: $GodotExe"
}

New-Item -ItemType Directory -Force -Path $isolatedAppData, $isolatedLocalAppData | Out-Null
$env:APPDATA = $isolatedAppData
$env:LOCALAPPDATA = $isolatedLocalAppData

Write-Output "Launching isolated playtest profile: $profileRoot"
Write-Output 'Normal Godot user:// data will not be used by this process.'
& $GodotExe --path $projectRoot
exit $LASTEXITCODE
