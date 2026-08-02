#requires -Version 7.4

Set-StrictMode -Version Latest

function Test-MayorPathInside {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Candidate,
        [Parameter(Mandatory)][string]$Parent
    )

    $relative = [IO.Path]::GetRelativePath(
        [IO.Path]::GetFullPath($Parent),
        [IO.Path]::GetFullPath($Candidate)
    )
    if ($relative -eq '.') {
        return $true
    }
    if ([IO.Path]::IsPathRooted($relative)) {
        return $false
    }
    return -not (
        $relative -eq '..' -or
        $relative.StartsWith('..' + [IO.Path]::DirectorySeparatorChar) -or
        $relative.StartsWith('..' + [IO.Path]::AltDirectorySeparatorChar)
    )
}

function Assert-MayorNotReparsePoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Label
    )

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "$Label must not be a symlink, junction, or other reparse point: $($item.FullName)"
    }
    return $item
}

function Get-MayorSourceFingerprint {
    <#
    .SYNOPSIS
        Computes the release-acceptance source fingerprint.

    .DESCRIPTION
        The contract deliberately includes every file type below the runtime,
        data, asset, test, and release-tool trees. Reparse points are rejected
        instead of followed, so content outside the reviewed project cannot be
        smuggled into an acceptance run.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ProjectRoot
    )

    $root = (Resolve-Path -LiteralPath $ProjectRoot -ErrorAction Stop).Path
    $rootItem = Assert-MayorNotReparsePoint -Path $root -Label 'Project root'
    if (-not $rootItem.PSIsContainer) {
        throw "ProjectRoot is not a directory: $root"
    }

    $directoryInputs = @(
        'assets',
        'data',
        'scenes',
        'scripts',
        'systems',
        'tests',
        'tools',
        'ui',
        '.github/workflows'
    )
    $singleFileInputs = @(
        'project.godot',
        'default_bus_layout.tres',
        'export_presets.cfg',
        'README.md',
        'THIRD_PARTY_NOTICES.md',
        'GODOT_COPYRIGHT.txt',
        'RELEASE_README.txt',
        '.gitignore',
        '莉拉，柳樹村的花店員.png',
        '莉拉，柳樹村的花店員.png.import'
    )

    $paths = [System.Collections.Generic.List[string]]::new()
    $seenPaths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    foreach ($relativeDirectory in $directoryInputs) {
        $directoryPath = [IO.Path]::GetFullPath((Join-Path $root $relativeDirectory))
        if (-not (Test-MayorPathInside -Candidate $directoryPath -Parent $root)) {
            throw "Fingerprint directory escaped the project root: $relativeDirectory"
        }
        if (-not (Test-Path -LiteralPath $directoryPath -PathType Container)) {
            throw "Required fingerprint directory is missing: $directoryPath"
        }
        $null = Assert-MayorNotReparsePoint -Path $directoryPath -Label "Fingerprint directory '$relativeDirectory'"

        $pending = [System.Collections.Generic.Stack[string]]::new()
        $pending.Push($directoryPath)
        while ($pending.Count -gt 0) {
            $currentDirectory = $pending.Pop()
            foreach ($child in @(Get-ChildItem -LiteralPath $currentDirectory -Force -ErrorAction Stop)) {
                if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw "Fingerprint scope contains a symlink, junction, or other reparse point: $($child.FullName)"
                }
                if ($child.PSIsContainer) {
                    $pending.Push($child.FullName)
                    continue
                }
                if ($seenPaths.Add($child.FullName)) {
                    $paths.Add($child.FullName)
                }
            }
        }
    }

    foreach ($relativeFile in $singleFileInputs) {
        $filePath = [IO.Path]::GetFullPath((Join-Path $root $relativeFile))
        if (-not (Test-MayorPathInside -Candidate $filePath -Parent $root)) {
            throw "Fingerprint file escaped the project root: $relativeFile"
        }
        if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
            throw "Required fingerprint file is missing: $filePath"
        }
        $null = Assert-MayorNotReparsePoint -Path $filePath -Label "Fingerprint file '$relativeFile'"
        if ($seenPaths.Add($filePath)) {
            $paths.Add($filePath)
        }
    }

    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($path in $paths) {
        $item = Assert-MayorNotReparsePoint -Path $path -Label 'Fingerprint file'
        if ($item.PSIsContainer) {
            throw "Fingerprint contract expected a file but found a directory: $path"
        }
        $relative = [IO.Path]::GetRelativePath($root, $item.FullName).Replace('\', '/')
        if ($relative -eq '..' -or $relative.StartsWith('../', [StringComparison]::Ordinal)) {
            throw "Fingerprint file escaped the project root: $($item.FullName)"
        }
        $records.Add([pscustomobject][ordered]@{
            path = $relative
            bytes = [long]$item.Length
            sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        })
    }

    $recordArray = @($records)
    [Array]::Sort($recordArray, [Comparison[object]]{
        param($left, $right)
        return [StringComparer]::Ordinal.Compare([string]$left.path, [string]$right.path)
    })
    if ($recordArray.Count -eq 0) {
        throw 'Fingerprint scope unexpectedly contains no files.'
    }

    $lines = @($recordArray | ForEach-Object { "$($_.path)`t$($_.bytes)`t$($_.sha256)" })
    $canonicalBytes = [Text.UTF8Encoding]::new($false).GetBytes(($lines -join "`n") + "`n")
    $hasher = [Security.Cryptography.SHA256]::Create()
    try {
        $fingerprint = [Convert]::ToHexString($hasher.ComputeHash($canonicalBytes)).ToLowerInvariant()
    }
    finally {
        $hasher.Dispose()
    }

    return [pscustomobject][ordered]@{
        schema_version = 1
        algorithm = 'sha256(path-tab-bytes-tab-sha256-lf)'
        project_root = $root
        file_count = $recordArray.Count
        total_bytes = [long](($recordArray | Measure-Object -Property bytes -Sum).Sum)
        fingerprint_sha256 = $fingerprint
        entries = $recordArray
    }
}
