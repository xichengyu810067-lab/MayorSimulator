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
    $git = (Get-Command git -ErrorAction Stop).Source

    function Invoke-ExactGit {
        param(
            [Parameter(Mandatory = $true)]
            [string]$WorkingDirectory,
            [Parameter(Mandatory = $true)]
            [string]$Check,
            [Parameter(Mandatory = $true)]
            [string[]]$Arguments
        )

        $output = & $git -c "safe.directory=$WorkingDirectory" -C $WorkingDirectory @Arguments 2>&1
        if ($LASTEXITCODE -ne 0) {
            $detail = ($output | Out-String).Trim()
            throw "Embedded SDK validation failed ($Check): $detail"
        }
        return ($output | Out-String).Trim()
    }

    $gitlinkRecord = Invoke-ExactGit -WorkingDirectory $projectRoot -Check 'parent sdk gitlink' -Arguments @('ls-tree', 'HEAD', '--', 'sdk')
    $gitlinkMatch = [regex]::Match($gitlinkRecord, '^160000\s+commit\s+(?<oid>[0-9a-fA-F]{40})\s+sdk$')
    if (-not $gitlinkMatch.Success) {
        throw "Embedded SDK validation failed (parent sdk gitlink): HEAD:sdk is not a gitlink."
    }
    $expectedOid = $gitlinkMatch.Groups['oid'].Value.ToLowerInvariant()
    $entrypoint = Join-Path $directRoot 'mayor-sdk.ps1'
    if (-not (Test-Path -LiteralPath $entrypoint -PathType Leaf)) {
        throw "Embedded SDK validation failed (direct checkout): '$entrypoint' is missing. Set process-local MAYOR_SDK_HOME to a standalone SDK root."
    }

    $candidateDotGit = Get-Item -Force -LiteralPath (Join-Path $directRoot '.git') -ErrorAction SilentlyContinue
    if ($null -eq $candidateDotGit -or $candidateDotGit.PSIsContainer) {
        throw "Embedded SDK validation failed (candidate submodule): direct sdk must use a submodule gitfile, not a standalone repository."
    }
    $insideWorkTree = Invoke-ExactGit -WorkingDirectory $directRoot -Check 'candidate worktree' -Arguments @('rev-parse', '--is-inside-work-tree')
    $candidateTopLevel = Invoke-ExactGit -WorkingDirectory $directRoot -Check 'candidate worktree root' -Arguments @('rev-parse', '--show-toplevel')
    $normalizedDirectRoot = (Resolve-Path -LiteralPath $directRoot).Path.TrimEnd('\', '/')
    $normalizedTopLevel = (Resolve-Path -LiteralPath $candidateTopLevel).Path.TrimEnd('\', '/')
    if ($insideWorkTree -ne 'true' -or -not [string]::Equals($normalizedTopLevel, $normalizedDirectRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Embedded SDK validation failed (candidate worktree): direct sdk is not a Git worktree rooted at '$directRoot'."
    }

    $candidateHead = (Invoke-ExactGit -WorkingDirectory $directRoot -Check 'candidate HEAD' -Arguments @('rev-parse', 'HEAD')).ToLowerInvariant()
    if ($candidateHead -ne $expectedOid) {
        throw "Embedded SDK validation failed (candidate HEAD): expected $expectedOid but found $candidateHead."
    }
    $expectedGitDir = Invoke-ExactGit -WorkingDirectory $projectRoot -Check 'candidate gitdir' -Arguments @('rev-parse', '--path-format=absolute', '--git-path', 'modules/sdk')
    $candidateGitDir = Invoke-ExactGit -WorkingDirectory $directRoot -Check 'candidate gitdir' -Arguments @('rev-parse', '--absolute-git-dir')
    $normalizedExpectedGitDir = (Resolve-Path -LiteralPath $expectedGitDir).Path.TrimEnd('\', '/')
    $normalizedCandidateGitDir = (Resolve-Path -LiteralPath $candidateGitDir).Path.TrimEnd('\', '/')
    if (-not [string]::Equals($normalizedCandidateGitDir, $normalizedExpectedGitDir, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Embedded SDK validation failed (candidate submodule): direct sdk is not attached to '$projectRoot'."
    }
    $superprojectOutput = & $git -c "safe.directory=$projectRoot" -c "safe.directory=$directRoot" -C $projectRoot -C sdk rev-parse --show-superproject-working-tree 2>&1
    if ($LASTEXITCODE -ne 0) {
        $detail = ($superprojectOutput | Out-String).Trim()
        throw "Embedded SDK validation failed (candidate superproject): $detail"
    }
    $superproject = ($superprojectOutput | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($superproject)) {
        throw "Embedded SDK validation failed (candidate superproject): direct sdk is not a submodule of '$projectRoot'."
    }
    $normalizedProjectRoot = (Resolve-Path -LiteralPath $projectRoot).Path.TrimEnd('\', '/')
    $normalizedSuperproject = (Resolve-Path -LiteralPath $superproject).Path.TrimEnd('\', '/')
    if (-not [string]::Equals($normalizedSuperproject, $normalizedProjectRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Embedded SDK validation failed (candidate superproject): expected '$projectRoot' but found '$superproject'."
    }
    $status = Invoke-ExactGit -WorkingDirectory $directRoot -Check 'candidate cleanliness' -Arguments @('status', '--porcelain')
    if (-not [string]::IsNullOrWhiteSpace($status)) {
        throw "Embedded SDK validation failed (candidate cleanliness): direct sdk has local changes."
    }
    return $directRoot
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
