[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$SdkArguments
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$originalSdkHome = $env:MAYOR_SDK_HOME
$originalProjectRoot = $env:MAYOR_PROJECT_ROOT
$exitCode = 0

function Resolve-EmbeddedSdkRoot {
    $directRoot = Join-Path $projectRoot 'sdk'
    if (Test-Path -LiteralPath (Join-Path $directRoot 'mayor-sdk.ps1') -PathType Leaf) {
        return $directRoot
    }

    # A linked worktree can retain the parent gitlink while its local submodule
    # checkout is absent. Reuse only an initialized SDK checkout with the exact
    # same pin from another listed worktree; never trust a broad parent path.
    $git = Get-Command git -ErrorAction Stop
    $gitlink = & $git.Source -c "safe.directory=$projectRoot" -C $projectRoot ls-tree HEAD sdk
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gitlink)) {
        throw "Mayor Simulator embedded SDK entrypoint was not found: $(Join-Path $directRoot 'mayor-sdk.ps1')"
    }
    $worktreeLines = & $git.Source -c "safe.directory=$projectRoot" -C $projectRoot worktree list --porcelain
    if ($LASTEXITCODE -ne 0) {
        throw "Could not inspect linked worktrees for the embedded SDK."
    }
    foreach ($line in $worktreeLines) {
        if (-not $line.StartsWith('worktree ')) {
            continue
        }
        $candidateRoot = $line.Substring('worktree '.Length)
        $candidateSdkRoot = Join-Path $candidateRoot 'sdk'
        if (-not (Test-Path -LiteralPath (Join-Path $candidateSdkRoot 'mayor-sdk.ps1') -PathType Leaf)) {
            continue
        }
        $candidateGitlink = & $git.Source -c "safe.directory=$candidateRoot" -C $candidateRoot ls-tree HEAD sdk
        if ($LASTEXITCODE -eq 0 -and $candidateGitlink -eq $gitlink) {
            return $candidateSdkRoot
        }
    }
    throw "Mayor Simulator embedded SDK is not initialized for gitlink '$gitlink'. Set process-local MAYOR_SDK_HOME to a standalone SDK root."
}

try {
    # Keep the skill bound to the project that contains it without persisting
    # machine- or user-level environment changes.
    $env:MAYOR_PROJECT_ROOT = $projectRoot
    $sdkRoot = if ([string]::IsNullOrWhiteSpace($originalSdkHome)) {
        Resolve-EmbeddedSdkRoot
    }
    else {
        (Resolve-Path -LiteralPath $originalSdkHome).Path
    }
    $entrypoint = Join-Path $sdkRoot 'mayor-sdk.ps1'
    if (-not (Test-Path -LiteralPath $entrypoint -PathType Leaf)) {
        throw "Mayor Simulator SDK entrypoint was not found: $entrypoint"
    }

    # The SDK entrypoint uses `exit`; isolate it so this wrapper's finally block
    # always restores the caller's process environment.
    $shellName = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
    $powershell = Join-Path $PSHOME $shellName
    if (-not (Test-Path -LiteralPath $powershell -PathType Leaf)) {
        throw "PowerShell executable was not found: $powershell"
    }
    & $powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $entrypoint @SdkArguments
    $exitCode = $LASTEXITCODE
}
finally {
    if ($null -eq $originalSdkHome) {
        Remove-Item Env:MAYOR_SDK_HOME -ErrorAction SilentlyContinue
    }
    else {
        $env:MAYOR_SDK_HOME = $originalSdkHome
    }

    if ($null -eq $originalProjectRoot) {
        Remove-Item Env:MAYOR_PROJECT_ROOT -ErrorAction SilentlyContinue
    }
    else {
        $env:MAYOR_PROJECT_ROOT = $originalProjectRoot
    }
}

# Return control to an interactive caller so it can inspect the restored
# environment and the delegated SDK exit code.
$global:LASTEXITCODE = $exitCode
return
