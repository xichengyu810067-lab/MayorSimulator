#requires -Version 7.4

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string]$Version,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputDirectory,

    [ValidateNotNullOrEmpty()]
    [string]$WindowsStagingDirectory = 'builds/windows',

    [ValidateNotNullOrEmpty()]
    [string]$LinuxStagingDirectory = 'builds/linux',

    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

if ([IO.Path]::IsPathRooted($OutputDirectory)) {
    $outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
}
else {
    $outputRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot $OutputDirectory))
}

function Test-PathInside {
    param(
        [Parameter(Mandatory)][string]$Candidate,
        [Parameter(Mandatory)][string]$Parent
    )

    $relative = [IO.Path]::GetRelativePath(
        [IO.Path]::GetFullPath($Parent),
        [IO.Path]::GetFullPath($Candidate)
    )
    $isRelativePath = -not ([IO.Path]::IsPathRooted($relative))
    $escapesParent = $relative -eq '..' -or
        $relative.StartsWith('..' + [IO.Path]::DirectorySeparatorChar) -or
        $relative.StartsWith('..' + [IO.Path]::AltDirectorySeparatorChar)
    return ($relative -eq '.') -or ($isRelativePath -and -not $escapesParent)
}

function Resolve-StagingDirectory {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Label
    )

    $candidate = if ([IO.Path]::IsPathRooted($Path)) {
        [IO.Path]::GetFullPath($Path)
    }
    else {
        [IO.Path]::GetFullPath((Join-Path $projectRoot $Path))
    }
    if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
        throw "$Label staging directory is missing: $candidate"
    }
    $item = Get-Item -LiteralPath $candidate -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "$Label staging directory must not be a symlink, junction, or other reparse point: $candidate"
    }
    return $item.FullName
}

$windowsStaging = Resolve-StagingDirectory -Path $WindowsStagingDirectory -Label 'Windows'
$linuxStaging = Resolve-StagingDirectory -Path $LinuxStagingDirectory -Label 'Linux'
if ((Test-PathInside -Candidate $windowsStaging -Parent $linuxStaging) -or
    (Test-PathInside -Candidate $linuxStaging -Parent $windowsStaging)) {
    throw 'Windows and Linux staging directories must be distinct and must not contain one another.'
}

if ((Test-PathInside -Candidate $outputRoot -Parent $windowsStaging) -or
    (Test-PathInside -Candidate $outputRoot -Parent $linuxStaging)) {
    throw "OutputDirectory must not be a staging directory or one of its descendants: $outputRoot"
}
if (Test-Path -LiteralPath $outputRoot) {
    throw "OutputDirectory already exists; choose a new directory so no release artifact can be overwritten: $outputRoot"
}

$windowsSpecs = @(
    [pscustomobject]@{ Name = 'MayorSimulator.exe'; MinimumBytes = 1MB; Magic = [byte[]]@(0x4D, 0x5A); Mode = 0 },
    [pscustomobject]@{ Name = 'MayorSimulator.pck'; MinimumBytes = 1KB; Magic = [byte[]]@(0x47, 0x44, 0x50, 0x43); Mode = 0 },
    [pscustomobject]@{ Name = 'RELEASE_README.txt'; MinimumBytes = 500; Magic = $null; Mode = 0 },
    [pscustomobject]@{ Name = 'THIRD_PARTY_NOTICES.md'; MinimumBytes = 100; Magic = $null; Mode = 0 },
    [pscustomobject]@{ Name = 'GODOT_COPYRIGHT.txt'; MinimumBytes = 1000; Magic = $null; Mode = 0 }
)
$linuxSpecs = @(
    [pscustomobject]@{ Name = 'MayorSimulator.x86_64'; MinimumBytes = 1MB; Magic = [byte[]]@(0x7F, 0x45, 0x4C, 0x46); Mode = 493 },
    [pscustomobject]@{ Name = 'MayorSimulator.pck'; MinimumBytes = 1KB; Magic = [byte[]]@(0x47, 0x44, 0x50, 0x43); Mode = 420 },
    [pscustomobject]@{ Name = 'RELEASE_README.txt'; MinimumBytes = 500; Magic = $null; Mode = 420 },
    [pscustomobject]@{ Name = 'THIRD_PARTY_NOTICES.md'; MinimumBytes = 100; Magic = $null; Mode = 420 },
    [pscustomobject]@{ Name = 'GODOT_COPYRIGHT.txt'; MinimumBytes = 1000; Magic = $null; Mode = 420 }
)

function Assert-FileMagic {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][byte[]]$Expected
    )

    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        foreach ($expectedByte in $Expected) {
            $actualByte = $stream.ReadByte()
            if ($actualByte -ne [int]$expectedByte) {
                throw "Unexpected file signature: $Path"
            }
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Get-StagingSnapshot {
    param(
        [Parameter(Mandatory)][string]$StagingPath,
        [Parameter(Mandatory)][object[]]$Specs
    )

    $requiredNames = @($Specs | ForEach-Object { [string]$_.Name })
    $entries = @(Get-ChildItem -LiteralPath $StagingPath -Force)
    $unexpected = @($entries | Where-Object { $requiredNames -notcontains $_.Name })
    if ($unexpected.Count -gt 0) {
        throw "Unexpected staging entries in '$StagingPath': $($unexpected.Name -join ', '). Update the explicit package contract before including new runtime dependencies."
    }
    if ($entries.Count -ne $requiredNames.Count) {
        throw "Staging entry count mismatch in '$StagingPath': expected $($requiredNames.Count), found $($entries.Count)."
    }

    $snapshot = [ordered]@{}
    foreach ($spec in $Specs) {
        $path = Join-Path $StagingPath ([string]$spec.Name)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Required staging file is missing: $path"
        }
        $item = Get-Item -LiteralPath $path -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Staging symlinks/reparse points are not accepted: $path"
        }
        if ($item.Length -lt [long]$spec.MinimumBytes) {
            throw "Required staging file is empty or implausibly small: $path ($($item.Length) bytes)"
        }
        if ($null -ne $spec.Magic) {
            Assert-FileMagic -Path $path -Expected ([byte[]]$spec.Magic)
        }
        $snapshot[[string]$spec.Name] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }
    return $snapshot
}

function Assert-CanonicalReleaseFiles {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$WindowsSnapshot,
        [Parameter(Mandatory)][System.Collections.IDictionary]$LinuxSnapshot
    )

    foreach ($name in @('RELEASE_README.txt', 'THIRD_PARTY_NOTICES.md', 'GODOT_COPYRIGHT.txt')) {
        $canonicalPath = Join-Path $projectRoot $name
        if (-not (Test-Path -LiteralPath $canonicalPath -PathType Leaf)) {
            throw "Canonical legal file is missing: $canonicalPath"
        }
        $canonicalHash = (Get-FileHash -LiteralPath $canonicalPath -Algorithm SHA256).Hash
        if ($WindowsSnapshot[$name] -ne $canonicalHash -or $LinuxSnapshot[$name] -ne $canonicalHash) {
            throw "Staged release document is not byte-identical to the canonical project file: $name"
        }
    }
}

function Assert-SnapshotUnchanged {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Before,
        [Parameter(Mandatory)][System.Collections.IDictionary]$After,
        [Parameter(Mandatory)][string]$Label
    )

    foreach ($name in $Before.Keys) {
        if (-not $After.Contains($name) -or $After[$name] -ne $Before[$name]) {
            throw "$Label staging changed while packaging: $name"
        }
    }
}

function Get-StreamSha256 {
    param([Parameter(Mandatory)][IO.Stream]$Stream)

    $hasher = [Security.Cryptography.SHA256]::Create()
    try {
        return [Convert]::ToHexString($hasher.ComputeHash($Stream))
    }
    finally {
        $hasher.Dispose()
    }
}

function Assert-ArchiveNames {
    param(
        [Parameter(Mandatory)][string[]]$Actual,
        [Parameter(Mandatory)][string[]]$Expected,
        [Parameter(Mandatory)][string]$ArchiveLabel
    )

    $actualSorted = @($Actual | Sort-Object)
    $expectedSorted = @($Expected | Sort-Object)
    if ($actualSorted.Count -ne $expectedSorted.Count) {
        throw "$ArchiveLabel content count mismatch: expected $($expectedSorted.Count), found $($actualSorted.Count)."
    }
    for ($index = 0; $index -lt $expectedSorted.Count; $index++) {
        if ($actualSorted[$index] -cne $expectedSorted[$index]) {
            throw "$ArchiveLabel content mismatch: expected '$($expectedSorted[$index])', found '$($actualSorted[$index])'."
        }
    }
}

function New-WindowsZip {
    param(
        [Parameter(Mandatory)][string]$DestinationPath,
        [Parameter(Mandatory)][object[]]$Specs
    )

    $sourcePaths = @($Specs | ForEach-Object { Join-Path $windowsStaging ([string]$_.Name) })
    Compress-Archive -LiteralPath $sourcePaths -DestinationPath $DestinationPath -CompressionLevel Optimal

    $archive = [IO.Compression.ZipFile]::OpenRead($DestinationPath)
    try {
        $actualNames = @($archive.Entries | Where-Object { -not [string]::IsNullOrEmpty($_.Name) } | ForEach-Object { $_.FullName.Replace('\', '/') })
        Assert-ArchiveNames -Actual $actualNames -Expected @($Specs.Name) -ArchiveLabel 'Windows ZIP'
        foreach ($spec in $Specs) {
            $matches = @($archive.Entries | Where-Object { $_.FullName -ceq [string]$spec.Name })
            if ($matches.Count -ne 1) {
                throw "Windows ZIP entry is not unique: $($spec.Name)"
            }
            $sourcePath = Join-Path $windowsStaging ([string]$spec.Name)
            $sourceItem = Get-Item -LiteralPath $sourcePath
            if ($matches[0].Length -ne $sourceItem.Length) {
                throw "Windows ZIP entry length mismatch: $($spec.Name)"
            }
            $entryStream = $matches[0].Open()
            try {
                $archiveHash = Get-StreamSha256 -Stream $entryStream
            }
            finally {
                $entryStream.Dispose()
            }
            $sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
            if ($archiveHash -cne $sourceHash) {
                throw "Windows ZIP entry hash mismatch: $($spec.Name)"
            }
        }
    }
    finally {
        $archive.Dispose()
    }
}

function New-LinuxTarGz {
    param(
        [Parameter(Mandatory)][string]$DestinationPath,
        [Parameter(Mandatory)][object[]]$Specs
    )

    $fileStream = [IO.File]::Open($DestinationPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $gzipStream = [IO.Compression.GZipStream]::new($fileStream, [IO.Compression.CompressionLevel]::Optimal, $true)
    $tarWriter = [System.Formats.Tar.TarWriter]::new($gzipStream, [System.Formats.Tar.TarEntryFormat]::Pax, $true)
    try {
        foreach ($spec in $Specs) {
            $sourcePath = Join-Path $linuxStaging ([string]$spec.Name)
            $sourceItem = Get-Item -LiteralPath $sourcePath
            $entry = [System.Formats.Tar.PaxTarEntry]::new(
                [System.Formats.Tar.TarEntryType]::RegularFile,
                [string]$spec.Name
            )
            $entry.Mode = [IO.UnixFileMode][int]$spec.Mode
            $entry.Uid = 0
            $entry.Gid = 0
            $entry.ModificationTime = [DateTimeOffset]::new($sourceItem.LastWriteTimeUtc)
            $sourceStream = [IO.File]::Open($sourcePath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
            try {
                $entry.DataStream = $sourceStream
                $tarWriter.WriteEntry($entry)
            }
            finally {
                $sourceStream.Dispose()
            }
        }
    }
    finally {
        $tarWriter.Dispose()
        $gzipStream.Dispose()
        $fileStream.Dispose()
    }
}

function Get-LinuxTarEntries {
    param([Parameter(Mandatory)][string]$ArchivePath)

    $result = [System.Collections.Generic.List[object]]::new()
    $fileStream = [IO.File]::OpenRead($ArchivePath)
    $gzipStream = [IO.Compression.GZipStream]::new($fileStream, [IO.Compression.CompressionMode]::Decompress, $true)
    $tarReader = [System.Formats.Tar.TarReader]::new($gzipStream, $true)
    try {
        $entry = $tarReader.GetNextEntry()
        while ($null -ne $entry) {
            if ($entry.EntryType -ne [System.Formats.Tar.TarEntryType]::RegularFile -or $null -eq $entry.DataStream) {
                throw "Linux tar.gz contains a non-regular or unreadable entry: $($entry.Name)"
            }
            $result.Add([pscustomobject]@{
                Name = [string]$entry.Name
                Mode = [int]$entry.Mode
                Length = [long]$entry.Length
                Hash = Get-StreamSha256 -Stream $entry.DataStream
            })
            $entry = $tarReader.GetNextEntry()
        }
    }
    finally {
        $tarReader.Dispose()
        $gzipStream.Dispose()
        $fileStream.Dispose()
    }
    return @($result)
}

$windowsSnapshotBefore = Get-StagingSnapshot -StagingPath $windowsStaging -Specs $windowsSpecs
$linuxSnapshotBefore = Get-StagingSnapshot -StagingPath $linuxStaging -Specs $linuxSpecs
Assert-CanonicalReleaseFiles -WindowsSnapshot $windowsSnapshotBefore -LinuxSnapshot $linuxSnapshotBefore

$windowsArchiveName = "MayorSimulator-Windows-x86_64-$Version.zip"
$linuxArchiveName = "MayorSimulator-Linux-x86_64-$Version.tar.gz"
$checksumName = 'SHA256SUMS'

Write-Output "Validated Windows staging: $windowsStaging"
Write-Output "Validated Linux staging: $linuxStaging"
Write-Output "Planned output directory: $outputRoot"
Write-Output "Planned artifacts: $windowsArchiveName, $linuxArchiveName, $checksumName"

if ($DryRun) {
    Write-Output 'DRY_RUN_OK: no directory or release artifact was created.'
    return
}

$outputParent = Split-Path -Parent $outputRoot
$outputLeaf = Split-Path -Leaf $outputRoot
if ([string]::IsNullOrWhiteSpace($outputParent) -or [string]::IsNullOrWhiteSpace($outputLeaf)) {
    throw "OutputDirectory must name a child directory: $outputRoot"
}
if (-not (Test-Path -LiteralPath $outputParent)) {
    New-Item -ItemType Directory -Path $outputParent -Force | Out-Null
}
$outputParent = (Resolve-Path -LiteralPath $outputParent).Path

$runId = [Guid]::NewGuid().ToString('N')
$temporaryRoot = Join-Path $outputParent ".$outputLeaf.$runId.partial"
if (Test-Path -LiteralPath $temporaryRoot) {
    throw "Run-specific temporary directory already exists: $temporaryRoot"
}
New-Item -ItemType Directory -Path $temporaryRoot | Out-Null

$temporaryWindows = Join-Path $temporaryRoot $windowsArchiveName
$temporaryLinux = Join-Path $temporaryRoot $linuxArchiveName
$temporaryChecksums = Join-Path $temporaryRoot $checksumName
$published = $false

try {
    New-WindowsZip -DestinationPath $temporaryWindows -Specs $windowsSpecs
    New-LinuxTarGz -DestinationPath $temporaryLinux -Specs $linuxSpecs

    $tarEntries = @(Get-LinuxTarEntries -ArchivePath $temporaryLinux)
    Assert-ArchiveNames -Actual @($tarEntries.Name) -Expected @($linuxSpecs.Name) -ArchiveLabel 'Linux tar.gz'
    foreach ($spec in $linuxSpecs) {
        $matches = @($tarEntries | Where-Object { $_.Name -ceq [string]$spec.Name })
        if ($matches.Count -ne 1) {
            throw "Linux tar.gz entry is not unique: $($spec.Name)"
        }
        $sourcePath = Join-Path $linuxStaging ([string]$spec.Name)
        $sourceItem = Get-Item -LiteralPath $sourcePath
        $sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
        if ($matches[0].Mode -ne [int]$spec.Mode) {
            throw "Linux tar.gz mode mismatch: $($spec.Name)"
        }
        if ($matches[0].Length -ne $sourceItem.Length) {
            throw "Linux tar.gz entry length mismatch: $($spec.Name)"
        }
        if ($matches[0].Hash -cne $sourceHash) {
            throw "Linux tar.gz entry hash mismatch: $($spec.Name)"
        }
    }

    $windowsSnapshotAfter = Get-StagingSnapshot -StagingPath $windowsStaging -Specs $windowsSpecs
    $linuxSnapshotAfter = Get-StagingSnapshot -StagingPath $linuxStaging -Specs $linuxSpecs
    Assert-SnapshotUnchanged -Before $windowsSnapshotBefore -After $windowsSnapshotAfter -Label 'Windows'
    Assert-SnapshotUnchanged -Before $linuxSnapshotBefore -After $linuxSnapshotAfter -Label 'Linux'

    $windowsHash = (Get-FileHash -LiteralPath $temporaryWindows -Algorithm SHA256).Hash.ToLowerInvariant()
    $linuxHash = (Get-FileHash -LiteralPath $temporaryLinux -Algorithm SHA256).Hash.ToLowerInvariant()
    $checksumLines = @(
        "$windowsHash  $windowsArchiveName",
        "$linuxHash  $linuxArchiveName"
    )
    [IO.File]::WriteAllLines($temporaryChecksums, $checksumLines, [Text.UTF8Encoding]::new($false))

    $expectedReleaseFiles = @($windowsArchiveName, $linuxArchiveName, $checksumName)
    $actualReleaseItems = @(Get-ChildItem -LiteralPath $temporaryRoot -Force)
    if ($actualReleaseItems.Count -ne $expectedReleaseFiles.Count) {
        throw "Temporary release directory content count mismatch: expected $($expectedReleaseFiles.Count), found $($actualReleaseItems.Count)."
    }
    Assert-ArchiveNames `
        -Actual @($actualReleaseItems | ForEach-Object { $_.Name }) `
        -Expected $expectedReleaseFiles `
        -ArchiveLabel 'Release directory'
    foreach ($releaseItem in $actualReleaseItems) {
        if ($releaseItem.PSIsContainer -or ($releaseItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Temporary release directory contains a directory or reparse point: $($releaseItem.FullName)"
        }
    }
    if ((Get-FileHash -LiteralPath $temporaryWindows -Algorithm SHA256).Hash.ToLowerInvariant() -ne $windowsHash) {
        throw 'Windows archive hash changed before publication.'
    }
    if ((Get-FileHash -LiteralPath $temporaryLinux -Algorithm SHA256).Hash.ToLowerInvariant() -ne $linuxHash) {
        throw 'Linux archive hash changed before publication.'
    }
    $actualChecksumLines = @([IO.File]::ReadAllLines($temporaryChecksums, [Text.UTF8Encoding]::new($false)))
    if ($actualChecksumLines.Count -ne $checksumLines.Count) {
        throw 'SHA256SUMS line count changed before publication.'
    }
    for ($lineIndex = 0; $lineIndex -lt $checksumLines.Count; $lineIndex++) {
        if ($actualChecksumLines[$lineIndex] -cne $checksumLines[$lineIndex]) {
            throw 'SHA256SUMS content changed before publication.'
        }
    }

    if (Test-Path -LiteralPath $outputRoot) {
        throw "OutputDirectory appeared during packaging; refusing to overwrite it: $outputRoot"
    }
    Move-Item -LiteralPath $temporaryRoot -Destination $outputRoot
    $published = $true

    $finalWindows = Join-Path $outputRoot $windowsArchiveName
    $finalLinux = Join-Path $outputRoot $linuxArchiveName
    $finalChecksums = Join-Path $outputRoot $checksumName

    Write-Output 'PACKAGE_OK'
    Get-Item -LiteralPath $finalWindows, $finalLinux, $finalChecksums | Select-Object FullName, Length
    Get-Content -LiteralPath $finalChecksums
}
finally {
    $expectedTemporaryLeaf = ".$outputLeaf.$runId.partial"
    if (-not $published -and
        (Test-PathInside -Candidate $temporaryRoot -Parent $outputParent) -and
        (Split-Path -Leaf $temporaryRoot) -ceq $expectedTemporaryLeaf -and
        (Test-Path -LiteralPath $temporaryRoot -PathType Container)) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
