[CmdletBinding()]
param(
    [switch]$Write,
    [string]$SdkRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$governancePaths = @(
    'docs/repository-governance/README.md',
    'docs/repository-governance/file_disposition.json',
    'tools/validate_file_disposition.ps1'
)
$ledgerRelativePath = 'docs/repository-governance/file_disposition.json'
$allowedDecisions = @(
    'RETAIN',
    'RETAIN_BLOCKED',
    'REFACTOR_APPROVED',
    'RETIRE_APPROVED'
)

function Invoke-RepoGit {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$AllowFailure
    )

    $output = @(& git -c "safe.directory=$Root" -c core.quotePath=false -C $Root @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    if (-not $AllowFailure -and $exitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed for $Root with exit code $exitCode`: $($output -join [Environment]::NewLine)"
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = $output
    }
}

function Get-SingleGitLine {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $result = Invoke-RepoGit -Root $Root -Arguments $Arguments
    if ($result.Output.Count -ne 1) {
        throw "Expected one line from git $($Arguments -join ' ') in $Root; received $($result.Output.Count)."
    }
    return ([string]$result.Output[0]).Trim()
}

function Resolve-SdkRoot {
    param(
        [Parameter(Mandatory = $true)][string]$GameRoot,
        [string]$RequestedRoot
    )

    if (-not [string]::IsNullOrWhiteSpace($RequestedRoot)) {
        return [IO.Path]::GetFullPath($RequestedRoot)
    }
    $gameParent = Split-Path -Parent $GameRoot
    $rebuildRoot = if ((Split-Path -Leaf $gameParent) -eq '.worktrees') {
        Split-Path -Parent $gameParent
    }
    else {
        $gameParent
    }
    return Join-Path $rebuildRoot '40_sdk'
}

function Get-PathCategory {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string]$Path
    )

    if ($Repository -eq 'sdk') { return 'sdk' }
    if ($governancePaths -contains $Path) { return 'repository_governance' }
    if ($Path -eq 'sdk') { return 'sdk_gitlink' }
    if ($Path.StartsWith('.github/')) { return 'ci' }
    if ($Path.StartsWith('scripts/')) { return 'runtime_code' }
    if ($Path.StartsWith('ui/')) { return 'ui_code' }
    if ($Path.StartsWith('scenes/')) { return 'scene' }
    if ($Path.StartsWith('tests/')) { return 'test_or_fixture' }
    if ($Path.StartsWith('tools/')) { return 'tooling' }
    if ($Path.StartsWith('data/')) { return 'data_contract' }
    if ($Path.StartsWith('docs/')) { return 'documentation' }
    if ($Path.StartsWith('skills/')) { return 'skill_contract' }
    if ($Path.StartsWith('assets/')) { return 'asset' }
    if ($Path -match '(?i)\.(png|jpg|jpeg|gif|svg|wav|ogg|mp3|ttf|otf|import)$') { return 'asset' }
    return 'project_contract'
}

function Get-Disposition {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)][Collections.Generic.HashSet[string]]$RuntimeAssets
    )

    if ($Repository -eq 'sdk') {
        return [pscustomobject]@{ Decision = 'RETAIN'; Evidence = 'standalone_sdk_contract_and_exact_game_gitlink' }
    }
    if ($governancePaths -contains $Path) {
        return [pscustomobject]@{ Decision = 'RETAIN'; Evidence = 'repository_governance_contract' }
    }
    if ($Path -eq 'sdk') {
        return [pscustomobject]@{ Decision = 'RETAIN'; Evidence = 'exact_sdk_gitlink_required_by_mayor_sdk_contract' }
    }
    if ($RuntimeAssets.Contains($Path) -or ($Path.EndsWith('.import') -and $RuntimeAssets.Contains($Path.Substring(0, $Path.Length - '.import'.Length)))) {
        return [pscustomobject]@{ Decision = 'RETAIN'; Evidence = 'active_runtime_asset_ledger_or_required_import_sidecar' }
    }
    if ($Category -eq 'asset') {
        return [pscustomobject]@{ Decision = 'RETAIN_BLOCKED'; Evidence = 'visual_rights_dynamic_load_or_source_art_value_requires_human_closure' }
    }
    return [pscustomobject]@{ Decision = 'RETAIN'; Evidence = 'validated_project_test_tool_release_or_history_contract' }
}

$scriptProjectCandidate = Split-Path -Parent $PSScriptRoot
$gameRoot = Get-SingleGitLine -Root $scriptProjectCandidate -Arguments @('rev-parse', '--show-toplevel')
$resolvedSdkRoot = Resolve-SdkRoot -GameRoot $gameRoot -RequestedRoot $SdkRoot
if (-not (Test-Path -LiteralPath $resolvedSdkRoot -PathType Container)) {
    throw "Standalone SDK root does not exist: $resolvedSdkRoot"
}

$ledgerPath = Join-Path $gameRoot $ledgerRelativePath
$sourceCommit = if ($Write) {
    Get-SingleGitLine -Root $gameRoot -Arguments @('rev-parse', 'HEAD')
}
else {
    if (-not (Test-Path -LiteralPath $ledgerPath -PathType Leaf)) {
        throw "Ledger does not exist: $ledgerPath"
    }
    [string]((Get-Content -Raw -LiteralPath $ledgerPath | ConvertFrom-Json).source.game.commit)
}
$sourceTree = Get-SingleGitLine -Root $gameRoot -Arguments @('rev-parse', "$sourceCommit`^{tree}")
$sdkCommit = Get-SingleGitLine -Root $resolvedSdkRoot -Arguments @('rev-parse', 'HEAD')
$sdkTree = Get-SingleGitLine -Root $resolvedSdkRoot -Arguments @('rev-parse', 'HEAD^{tree}')

$gitlinkLine = Get-SingleGitLine -Root $gameRoot -Arguments @('ls-tree', $sourceCommit, '--', 'sdk')
if ($gitlinkLine -notmatch '^160000 commit (?<sha>[0-9a-f]{40})\tsdk$') {
    throw "Game source does not contain the expected sdk gitlink: $gitlinkLine"
}
if ($Matches.sha -ne $sdkCommit) {
    throw "SDK gitlink mismatch: game=$($Matches.sha) standalone=$sdkCommit"
}

$baseGamePaths = @((Invoke-RepoGit -Root $gameRoot -Arguments @('ls-tree', '-r', '--name-only', $sourceCommit)).Output | ForEach-Object { [string]$_ })
$sdkPaths = @((Invoke-RepoGit -Root $resolvedSdkRoot -Arguments @('ls-files')).Output | ForEach-Object { [string]$_ })
$expectedGamePaths = @($baseGamePaths + $governancePaths | Sort-Object -Unique)
$expectedSdkPaths = @($sdkPaths | Sort-Object -Unique)

if ($Write) {
    foreach ($relativePath in $governancePaths | Where-Object { $_ -ne $ledgerRelativePath }) {
        if (-not (Test-Path -LiteralPath (Join-Path $gameRoot $relativePath) -PathType Leaf)) {
            throw "Governance overlay file is missing before ledger generation: $relativePath"
        }
    }

    $runtimeLedgerPath = Join-Path $gameRoot 'docs/project-organization/RUNTIME_ASSET_LEDGER.json'
    $runtimeLedger = Get-Content -Raw -LiteralPath $runtimeLedgerPath | ConvertFrom-Json
    $runtimeAssets = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($asset in @($runtimeLedger.assets)) {
        $relativePath = ([string]$asset.res_path) -replace '^res://', ''
        [void]$runtimeAssets.Add($relativePath)
    }

    $entries = [Collections.Generic.List[object]]::new()
    foreach ($path in $expectedGamePaths) {
        $category = Get-PathCategory -Repository 'game' -Path $path
        $disposition = Get-Disposition -Repository 'game' -Path $path -Category $category -RuntimeAssets $runtimeAssets
        $entries.Add([ordered]@{
            repository = 'game'
            path = $path
            category = $category
            decision = $disposition.Decision
            evidence = $disposition.Evidence
        })
    }
    foreach ($path in $expectedSdkPaths) {
        $category = Get-PathCategory -Repository 'sdk' -Path $path
        $disposition = Get-Disposition -Repository 'sdk' -Path $path -Category $category -RuntimeAssets $runtimeAssets
        $entries.Add([ordered]@{
            repository = 'sdk'
            path = $path
            category = $category
            decision = $disposition.Decision
            evidence = $disposition.Evidence
        })
    }

    $summary = [ordered]@{}
    foreach ($decision in $allowedDecisions) {
        $summary[$decision] = @($entries | Where-Object { $_.decision -eq $decision }).Count
    }
    $ledger = [ordered]@{
        schema_version = 1
        generated_utc = [DateTime]::UtcNow.ToString('o')
        policy = [ordered]@{
            unapproved_refactor_or_retirement_fails = $true
            public_release_authorized = $false
        }
        source = [ordered]@{
            game = [ordered]@{
                repository = 'xichengyu810067-lab/MayorSimulator'
                commit = $sourceCommit
                tree = $sourceTree
                base_path_count = $baseGamePaths.Count
                governance_overlay_paths = $governancePaths
                expected_path_count = $expectedGamePaths.Count
            }
            sdk = [ordered]@{
                repository = 'xichengyu810067-lab/MayorSimulator-SDK'
                commit = $sdkCommit
                tree = $sdkTree
                expected_path_count = $expectedSdkPaths.Count
            }
        }
        decision_summary = $summary
        entries = $entries
    }
    $ledgerDirectory = Split-Path -Parent $ledgerPath
    if (-not (Test-Path -LiteralPath $ledgerDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $ledgerDirectory -Force | Out-Null
    }
    $ledger | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ledgerPath -Encoding utf8NoBOM
}

$loaded = Get-Content -Raw -LiteralPath $ledgerPath | ConvertFrom-Json
if ([int]$loaded.schema_version -ne 1) {
    throw "Unsupported ledger schema version: $($loaded.schema_version)"
}
if ([string]$loaded.source.game.commit -ne $sourceCommit -or [string]$loaded.source.game.tree -ne $sourceTree) {
    throw 'Ledger game source identity does not match the pinned source commit/tree.'
}
if ([string]$loaded.source.sdk.commit -ne $sdkCommit -or [string]$loaded.source.sdk.tree -ne $sdkTree) {
    throw 'Ledger SDK source identity does not match the standalone SDK checkout.'
}

$ancestry = Invoke-RepoGit -Root $gameRoot -Arguments @('merge-base', '--is-ancestor', $sourceCommit, 'HEAD') -AllowFailure
if ($ancestry.ExitCode -ne 0) {
    throw "Ledger source commit $sourceCommit is not an ancestor of current HEAD."
}
$changedSinceSource = @((Invoke-RepoGit -Root $gameRoot -Arguments @('diff', '--name-only', "$sourceCommit..HEAD")).Output | ForEach-Object { [string]$_ })
$unexpectedChanges = @($changedSinceSource | Where-Object { $governancePaths -notcontains $_ })
if ($unexpectedChanges.Count -gt 0) {
    throw "Ledger source drift outside the governance overlay: $($unexpectedChanges -join ', ')"
}

$entryKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$gameEntryPaths = [Collections.Generic.List[string]]::new()
$sdkEntryPaths = [Collections.Generic.List[string]]::new()
foreach ($entry in @($loaded.entries)) {
    $repository = [string]$entry.repository
    $path = [string]$entry.path
    $decision = [string]$entry.decision
    $evidence = [string]$entry.evidence
    if ([string]::IsNullOrWhiteSpace($repository) -or [string]::IsNullOrWhiteSpace($path) -or
        [string]::IsNullOrWhiteSpace($decision) -or [string]::IsNullOrWhiteSpace($evidence)) {
        throw 'Ledger contains a blank repository, path, decision, or evidence field.'
    }
    if ($allowedDecisions -notcontains $decision) {
        throw "Ledger contains an unsupported decision for $repository`:$path`: $decision"
    }
    if ($decision -in @('REFACTOR_APPROVED', 'RETIRE_APPROVED')) {
        throw "Approved destructive disposition requires a separate reviewed work order: $repository`:$path"
    }
    $key = "$repository`:$path"
    if (-not $entryKeys.Add($key)) {
        throw "Duplicate ledger entry: $key"
    }
    if ($repository -eq 'game') { $gameEntryPaths.Add($path) }
    elseif ($repository -eq 'sdk') { $sdkEntryPaths.Add($path) }
    else { throw "Unsupported repository label: $repository" }
}

function Assert-ExactPathSet {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string[]]$Expected,
        [Parameter(Mandatory = $true)][string[]]$Actual
    )

    $expectedSet = [Collections.Generic.HashSet[string]]::new([string[]]$Expected, [StringComparer]::Ordinal)
    $actualSet = [Collections.Generic.HashSet[string]]::new([string[]]$Actual, [StringComparer]::Ordinal)
    $missing = @($Expected | Where-Object { -not $actualSet.Contains($_) })
    $unexpected = @($Actual | Where-Object { -not $expectedSet.Contains($_) })
    if ($missing.Count -gt 0 -or $unexpected.Count -gt 0) {
        throw "$Label path mismatch. missing=[$($missing -join ', ')] unexpected=[$($unexpected -join ', ')]"
    }
}

Assert-ExactPathSet -Label 'game' -Expected $expectedGamePaths -Actual $gameEntryPaths.ToArray()
Assert-ExactPathSet -Label 'sdk' -Expected $expectedSdkPaths -Actual $sdkEntryPaths.ToArray()

$computedSummary = [ordered]@{}
foreach ($decision in $allowedDecisions) {
    $computedSummary[$decision] = @($loaded.entries | Where-Object { $_.decision -eq $decision }).Count
    if ([int]$loaded.decision_summary.$decision -ne [int]$computedSummary[$decision]) {
        throw "Decision summary mismatch for $decision."
    }
}

[ordered]@{
    status = 'pass'
    game_source_commit = $sourceCommit
    game_source_tree = $sourceTree
    sdk_commit = $sdkCommit
    sdk_tree = $sdkTree
    game_paths = $expectedGamePaths.Count
    sdk_paths = $expectedSdkPaths.Count
    decisions = $computedSummary
} | ConvertTo-Json -Depth 5
