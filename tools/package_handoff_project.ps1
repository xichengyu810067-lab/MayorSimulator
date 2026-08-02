#requires -Version 7.4

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,

    [Parameter(Mandatory = $true)]
    [string]$ArchivePath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$HandoffDirectoryName,

    [AllowEmptyString()]
    [string]$SevenZip = '',

    [string]$ControlMetadataPath = 'docs\release\CURRENT_CONTROL.json',

    [switch]$ManifestOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'source_fingerprint.ps1')

function Assert-InProjectPathChain {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Label
    )
    $full = [IO.Path]::GetFullPath($Path)
    if (-not (Test-MayorPathInside -Candidate $full -Parent $projectFull)) {
        throw "$Label must remain inside the project root: $full"
    }
    $relative = [IO.Path]::GetRelativePath($projectFull, $full)
    $current = $projectFull
    foreach ($segment in $relative.Split([IO.Path]::DirectorySeparatorChar, [StringSplitOptions]::RemoveEmptyEntries)) {
        $current = Join-Path $current $segment
        if (Test-Path -LiteralPath $current) {
            $null = Assert-MayorNotReparsePoint -Path $current -Label $Label
        }
    }
}

$projectFull = [System.IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
$archiveFull = [System.IO.Path]::GetFullPath($ArchivePath)
$archiveDirectory = [System.IO.Path]::GetDirectoryName($archiveFull)
$projectParent = [System.IO.Path]::GetDirectoryName($projectFull)
$projectName = [System.IO.Path]::GetFileName($projectFull)
$archiveName = [System.IO.Path]::GetFileName($archiveFull)
$invalidHandoffName = (
    [IO.Path]::IsPathRooted($HandoffDirectoryName) -or
    [IO.Path]::GetFileName($HandoffDirectoryName) -cne $HandoffDirectoryName -or
    $HandoffDirectoryName -in @('.', '..') -or
    $HandoffDirectoryName.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0
)
if ($invalidHandoffName) {
    throw "HandoffDirectoryName must be one safe top-level directory name: $HandoffDirectoryName"
}
$handoffRoot = [System.IO.Path]::GetFullPath((Join-Path $projectFull $HandoffDirectoryName))
$manifestPath = Join-Path $handoffRoot 'PACKAGE_CONTENT_MANIFEST.json'
$controlMetadataFull = if ([System.IO.Path]::IsPathRooted($ControlMetadataPath)) {
    [System.IO.Path]::GetFullPath($ControlMetadataPath)
} else {
    [System.IO.Path]::GetFullPath((Join-Path $projectFull $ControlMetadataPath))
}
$controlMetadataRelative = [System.IO.Path]::GetRelativePath($projectFull, $controlMetadataFull).Replace('\', '/')

if (-not (Test-Path -LiteralPath $projectFull -PathType Container)) {
    throw "Project root does not exist: $projectFull"
}
$null = Assert-MayorNotReparsePoint -Path $projectFull -Label 'Project root'
Assert-InProjectPathChain -Path $handoffRoot -Label 'Handoff directory'
if (-not (Test-Path -LiteralPath $handoffRoot -PathType Container)) {
    throw "Handoff directory does not exist: $handoffRoot"
}
if ([System.IO.Path]::IsPathRooted($controlMetadataRelative) -or
    $controlMetadataRelative -eq '..' -or
    $controlMetadataRelative.StartsWith('../', [System.StringComparison]::Ordinal)) {
    throw "Control metadata must remain inside the project root: $controlMetadataFull"
}
if (-not (Test-Path -LiteralPath $controlMetadataFull -PathType Leaf)) {
    throw "Current control metadata does not exist: $controlMetadataFull"
}
Assert-InProjectPathChain -Path $controlMetadataFull -Label 'Current control metadata'
$controlMetadata = Get-Content -LiteralPath $controlMetadataFull -Raw | ConvertFrom-Json -Depth 100
$controlThreadId = [string]$controlMetadata.task.thread_id
$controlStatus = [string]$controlMetadata.task.status_at_capture
if ($controlThreadId -notmatch '^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$') {
    throw "Current control metadata has an invalid task thread_id: $controlThreadId"
}
if ([string]::IsNullOrWhiteSpace($controlStatus)) {
    throw 'Current control metadata is missing task.status_at_capture.'
}
$controlMetadataSha256 = (Get-FileHash -LiteralPath $controlMetadataFull -Algorithm SHA256).Hash.ToLowerInvariant()
$manifestRelative = [System.IO.Path]::GetRelativePath($projectFull, $manifestPath).Replace('\', '/')
$historicalSnapshotPaths = @($controlMetadata.historical_snapshots | ForEach-Object { [string]$_.path })
if ($historicalSnapshotPaths -contains $manifestRelative) {
    throw "Refusing to overwrite a historical snapshot manifest; choose a fresh HandoffDirectoryName: $manifestRelative"
}
if (Test-Path -LiteralPath $manifestPath) {
    throw "Package manifest already exists; choose a fresh handoff directory: $manifestPath"
}
$requiredControlEvidence = @($controlMetadata.required_evidence_relative_paths | ForEach-Object { [string]$_ })
foreach ($relativeEvidence in $requiredControlEvidence) {
    $evidenceFull = [System.IO.Path]::GetFullPath((Join-Path $projectFull $relativeEvidence))
    $evidenceRelative = [System.IO.Path]::GetRelativePath($projectFull, $evidenceFull).Replace('\', '/')
    if ([System.IO.Path]::IsPathRooted($evidenceRelative) -or
        $evidenceRelative -eq '..' -or
        $evidenceRelative.StartsWith('../', [System.StringComparison]::Ordinal)) {
        throw "Required control evidence escaped the project root: $relativeEvidence"
    }
    if (-not (Test-Path -LiteralPath $evidenceFull -PathType Leaf)) {
        throw "Required control evidence is missing: $relativeEvidence"
    }
    Assert-InProjectPathChain -Path $evidenceFull -Label "Required control evidence '$relativeEvidence'"
}
$requiredGodotIgnoreMarkers = @(
    '.tmp/.gdignore',
    'artifacts/.gdignore',
    'backups/.gdignore',
    'builds/.gdignore',
    "$HandoffDirectoryName/.gdignore"
)
$missingGodotIgnoreMarkers = @($requiredGodotIgnoreMarkers | Where-Object {
    -not (Test-Path -LiteralPath (Join-Path $projectFull $_) -PathType Leaf)
})
if ($missingGodotIgnoreMarkers.Count -ne 0) {
    throw "Required Godot ignore markers are missing; packaging was not started: $($missingGodotIgnoreMarkers -join ', ')"
}
foreach ($marker in $requiredGodotIgnoreMarkers) {
    Assert-InProjectPathChain -Path (Join-Path $projectFull $marker) -Label "Godot ignore marker '$marker'"
}
if (-not [string]::Equals($archiveDirectory, $projectFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Archive must be written directly in the project root: $projectFull"
}
if (Test-Path -LiteralPath $archiveFull) {
    throw "Archive already exists; choose a fresh path: $archiveFull"
}
if (-not $ManifestOnly) {
    if ([string]::IsNullOrWhiteSpace($SevenZip)) {
        $sevenZipCommand = Get-Command '7z.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $sevenZipCommand) {
            throw '7-Zip is required for archive creation; pass -SevenZip or install 7z.exe on PATH.'
        }
        $SevenZip = $sevenZipCommand.Source
    }
    if (-not (Test-Path -LiteralPath $SevenZip -PathType Leaf)) {
        throw "7-Zip executable does not exist: $SevenZip"
    }
    $SevenZip = (Resolve-Path -LiteralPath $SevenZip).Path
}

$excludedTopLevel = @(
    '.godot',
    '_appdata',
    '_local_appdata',
    'LocalLow',
    '.tmp.driveupload',
    '.tmp.drivedownload'
)
$excludedLookup = @{}
foreach ($name in $excludedTopLevel) {
    $excludedLookup[$name.ToLowerInvariant()] = $true
}

function Get-ProjectRelativePath {
    param([Parameter(Mandatory = $true)][string]$FullName)
    return [System.IO.Path]::GetRelativePath($projectFull, $FullName).Replace('\', '/')
}

function Test-IncludedFile {
    param([Parameter(Mandatory = $true)][System.IO.FileInfo]$File)
    if ([string]::Equals($File.FullName, $archiveFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }
    $relative = Get-ProjectRelativePath -FullName $File.FullName
    $firstSegment = $relative.Split('/')[0].ToLowerInvariant()
    return -not $excludedLookup.ContainsKey($firstSegment)
}

function Get-IncludedFiles {
    $files = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    $pending = [System.Collections.Generic.Stack[string]]::new()
    $pending.Push($projectFull)
    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        foreach ($child in @(Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop)) {
            $relative = Get-ProjectRelativePath -FullName $child.FullName
            $firstSegment = $relative.Split('/')[0].ToLowerInvariant()
            if ($excludedLookup.ContainsKey($firstSegment)) {
                continue
            }
            if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Included package scope contains a symlink, junction, or other reparse point: $($child.FullName)"
            }
            if ($child.PSIsContainer) {
                $pending.Push($child.FullName)
            } elseif (Test-IncludedFile -File $child) {
                $files.Add($child)
            }
        }
    }
    return @($files)
}

function New-TopLevelStats {
    param(
        [Parameter(Mandatory = $true)][object[]]$Files,
        [Parameter(Mandatory = $true)][long]$ManifestBytes
    )
    $stats = @(
        $Files |
            Group-Object { (Get-ProjectRelativePath -FullName $_.FullName).Split('/')[0] } |
            ForEach-Object {
                [pscustomobject][ordered]@{
                    name = $_.Name
                    file_count = [int64]$_.Count
                    bytes = [int64](($_.Group | Measure-Object Length -Sum).Sum)
                }
            }
    )
    $handoffStat = $stats | Where-Object { $_.name -eq $HandoffDirectoryName } | Select-Object -First 1
    if ($null -eq $handoffStat) {
        $stats += [pscustomobject][ordered]@{
            name = $HandoffDirectoryName
            file_count = [int64]1
            bytes = $ManifestBytes
        }
    } else {
        $handoffStat.file_count = [int64]$handoffStat.file_count + 1
        $handoffStat.bytes = [int64]$handoffStat.bytes + $ManifestBytes
    }
    return @($stats | Sort-Object name)
}

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

$baseFiles = @(Get-IncludedFiles | Where-Object {
    -not [string]::Equals($_.FullName, $manifestPath, [System.StringComparison]::OrdinalIgnoreCase)
})
$baseCount = [int64]$baseFiles.Count
$baseBytes = [int64](($baseFiles | Measure-Object Length -Sum).Sum)
$chatManifestPath = Join-Path $handoffRoot 'chats\CHAT_EXPORT_MANIFEST.json'
if (-not (Test-Path -LiteralPath $chatManifestPath -PathType Leaf)) {
    throw "Chat export manifest does not exist: $chatManifestPath"
}
Assert-InProjectPathChain -Path $chatManifestPath -Label 'Chat export manifest'
$chatManifest = Get-Content -Raw -LiteralPath $chatManifestPath | ConvertFrom-Json -Depth 100
$capturedAt = [DateTimeOffset]::Now.ToString('o')
$manifestBytes = [int64]0
$manifestText = ''

for ($iteration = 0; $iteration -lt 20; $iteration++) {
    $manifest = [pscustomobject][ordered]@{
        schema_version = 1
        captured_at = $capturedAt
        source_project_root = $projectFull
        archive_filename = $archiveName
        archive_root_directory = $projectName
        included_file_count = $baseCount + 1
        included_uncompressed_bytes = $baseBytes + $manifestBytes
        excluded_top_level = @($excludedTopLevel)
        excluded_archive_itself = $archiveName
        goal = [pscustomobject][ordered]@{
            thread_id = $controlThreadId
            status = $controlStatus
            status_semantics = 'snapshot_only; completion is authoritative only after Codex update_goal succeeds'
            control_metadata_path = $controlMetadataRelative
            control_metadata_sha256 = $controlMetadataSha256
            live_thread_export_included = $false
        }
        chats = [pscustomobject][ordered]@{
            session_total = [int64]$chatManifest.session_total
            user_root = [int64]$chatManifest.session_counts.user
            subagent = [int64]$chatManifest.session_counts.subagent
            raw_bytes_total = [int64]$chatManifest.raw_bytes_total
            unreadable_count = [int64]$chatManifest.unreadable_count
            extra_chatgpt_snapshots = 5
        }
        top_level = @(New-TopLevelStats -Files $baseFiles -ManifestBytes $manifestBytes)
        notes = @(
            'The archive retains .git, .tmp, artifacts, builds, backups, assets, SDK WIP, goal and chat exports.',
            'Only rebuildable or machine-local state plus the archive itself are excluded.',
            'The imported chat export is historical and does not include the live controller thread; CURRENT_CONTROL.json is the live control pointer.',
            'Archive SHA-256 is stored beside the ZIP because embedding its own checksum would change the archive hash.'
        )
    }
    $candidate = ($manifest | ConvertTo-Json -Depth 12) + "`n"
    $candidateBytes = [int64]$utf8NoBom.GetByteCount($candidate)
    if ($candidateBytes -eq $manifestBytes) {
        $manifestText = $candidate
        break
    }
    $manifestBytes = $candidateBytes
    $manifestText = $candidate
}
if (-not $manifestText) {
    throw 'Failed to generate package content manifest.'
}
$manifestPartialPath = $manifestPath + '.partial'
if (Test-Path -LiteralPath $manifestPartialPath) {
    throw "Package manifest partial path already exists; refusing overwrite: $manifestPartialPath"
}
try {
    [System.IO.File]::WriteAllText($manifestPartialPath, $manifestText, $utf8NoBom)
    [System.IO.File]::Move($manifestPartialPath, $manifestPath)
} catch {
    if (Test-Path -LiteralPath $manifestPartialPath -PathType Leaf) {
        [System.IO.File]::Delete($manifestPartialPath)
    }
    throw
}

$sourceFiles = @(Get-IncludedFiles)
$sourceCount = [int64]$sourceFiles.Count
$sourceBytes = [int64](($sourceFiles | Measure-Object Length -Sum).Sum)
$finalManifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json -Depth 100
if ($sourceCount -ne [int64]$finalManifest.included_file_count) {
    throw "Source count drifted after manifest write: actual=$sourceCount manifest=$($finalManifest.included_file_count)"
}
if ($sourceBytes -ne [int64]$finalManifest.included_uncompressed_bytes) {
    throw "Source bytes drifted after manifest write: actual=$sourceBytes manifest=$($finalManifest.included_uncompressed_bytes)"
}

if ($ManifestOnly) {
    [pscustomobject][ordered]@{
        manifest_path = $manifestPath
        source_file_count = $sourceCount
        source_uncompressed_bytes = $sourceBytes
        archive_path = $archiveFull
    } | ConvertTo-Json -Depth 4
    return
}

$sevenZipArguments = @(
    'a',
    '-tzip',
    $archiveFull,
    ".\$projectName",
    "-x!$projectName\.godot",
    "-x!$projectName\_appdata",
    "-x!$projectName\_local_appdata",
    "-x!$projectName\LocalLow",
    "-x!$projectName\.tmp.driveupload",
    "-x!$projectName\.tmp.drivedownload",
    "-x!$projectName\$archiveName",
    '-mx=5',
    '-mmt=on',
    '-bb0',
    '-y'
)

Push-Location $projectParent
try {
    & $SevenZip @sevenZipArguments
    $archiveExit = $LASTEXITCODE
} finally {
    Pop-Location
}
if ($archiveExit -ne 0) {
    throw "7-Zip archive creation failed with exit code $archiveExit"
}

& $SevenZip t $archiveFull '-bb0'
$testExit = $LASTEXITCODE
if ($testExit -ne 0) {
    throw "7-Zip archive test failed with exit code $testExit"
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($archiveFull)
try {
    $fileEntries = @($zip.Entries | Where-Object { -not [string]::IsNullOrEmpty($_.Name) })
    $entryCount = [int64]$fileEntries.Count
    $entryBytes = [int64](($fileEntries | Measure-Object Length -Sum).Sum)
    $relativeEntries = @($fileEntries | ForEach-Object {
        $path = $_.FullName.Replace('\', '/')
        $separatorIndex = $path.IndexOf('/')
        if ($separatorIndex -lt 0) {
            throw "ZIP entry does not contain the expected root directory: $path"
        }
        [pscustomobject]@{
            entry = $_
            relative_path = $path.Substring($separatorIndex + 1)
        }
    })
    $excludedViolations = @($relativeEntries | Where-Object {
        $path = $_.relative_path
        foreach ($excluded in $excludedTopLevel) {
            if ($path.StartsWith("$excluded/", [System.StringComparison]::OrdinalIgnoreCase) -or
                [string]::Equals($path, $excluded, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }
        return [string]::Equals($path, $archiveName, [System.StringComparison]::OrdinalIgnoreCase)
    })
    $requiredExact = @(
        'project.godot',
        '.git/HEAD',
        'sdk/mayor_sdk.py',
        $controlMetadataRelative
    ) + $requiredControlEvidence
    $entryLookup = @{}
    foreach ($item in $relativeEntries) {
        $entryLookup[$item.relative_path.ToLowerInvariant()] = $true
    }
    $missingRequired = @($requiredExact | Where-Object {
        -not $entryLookup.ContainsKey($_.ToLowerInvariant())
    })
    $requiredLeafNames = @(
        'GOAL_CURRENT.json',
        'CHAT_EXPORT_MANIFEST.json'
    )
    foreach ($leafName in $requiredLeafNames) {
        if (-not ($relativeEntries | Where-Object { $_.entry.Name -eq $leafName } | Select-Object -First 1)) {
            $missingRequired += $leafName
        }
    }
} finally {
    $zip.Dispose()
}

if ($entryCount -ne $sourceCount) {
    throw "ZIP file entry count mismatch: zip=$entryCount source=$sourceCount"
}
if ($entryBytes -ne $sourceBytes) {
    throw "ZIP uncompressed byte mismatch: zip=$entryBytes source=$sourceBytes"
}
if ($excludedViolations.Count -ne 0) {
    throw "ZIP contains $($excludedViolations.Count) excluded file entries."
}
if ($missingRequired.Count -ne 0) {
    throw "ZIP is missing required entries: $($missingRequired -join ', ')"
}

$archiveInfo = Get-Item -LiteralPath $archiveFull
$hash = Get-FileHash -LiteralPath $archiveFull -Algorithm SHA256
[pscustomobject][ordered]@{
    archive_path = $archiveFull
    archive_bytes = [int64]$archiveInfo.Length
    sha256 = $hash.Hash
    source_file_count = $sourceCount
    source_uncompressed_bytes = $sourceBytes
    zip_file_entry_count = $entryCount
    zip_uncompressed_bytes = $entryBytes
    excluded_file_violations = $excludedViolations.Count
    missing_required_entries = $missingRequired.Count
    seven_zip_create_exit = $archiveExit
    seven_zip_test_exit = $testExit
} | ConvertTo-Json -Depth 6
