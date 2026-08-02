#requires -Version 7.4

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9]{4}\.[0-9]{2}\.[0-9]{2}$')]
    [string]$Version,

    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$GodotExe,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$TemplatesArchive,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ExportAppDataRoot,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$OutputRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$OFFICIAL_GODOT_47_TEMPLATES_SHA256 = '9714459dc071907c0f3d5f17d608faf69e7cda21331fc5d39c4503ffa4e99eec'
$requiredSaveKillPhases = @(
    'temp_partial_write',
    'temp_verified',
    'backup_removed',
    'primary_rotated',
    'primary_installed'
)
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'source_fingerprint.ps1')

function Resolve-RequiredRegularFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Label,
        [string]$RelativeBase = $projectRoot
    )

    $candidate = if ([IO.Path]::IsPathRooted($Path)) {
        [IO.Path]::GetFullPath($Path)
    }
    else {
        [IO.Path]::GetFullPath((Join-Path $RelativeBase $Path))
    }
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw "$Label is missing or is not a regular file: $candidate"
    }
    $item = Assert-MayorNotReparsePoint -Path $candidate -Label $Label
    if ($item.PSIsContainer) {
        throw "$Label is not a regular file: $candidate"
    }
    return $item.FullName
}

function Assert-ExistingAncestorsNotReparse {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Label
    )

    $current = [IO.Path]::GetFullPath($Path)
    while (-not (Test-Path -LiteralPath $current)) {
        $parent = [IO.Path]::GetDirectoryName($current)
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -ceq $current) {
            throw "$Label has no existing ancestor: $Path"
        }
        $current = $parent
    }
    while (-not [string]::IsNullOrWhiteSpace($current)) {
        $null = Assert-MayorNotReparsePoint -Path $current -Label "$Label ancestor"
        $parent = [IO.Path]::GetDirectoryName($current)
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -ceq $current) {
            break
        }
        $current = $parent
    }
}

function Resolve-NewDirectoryPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Label,
        [string]$RelativeBase = $projectRoot
    )

    $candidate = if ([IO.Path]::IsPathRooted($Path)) {
        [IO.Path]::GetFullPath($Path)
    }
    else {
        [IO.Path]::GetFullPath((Join-Path $RelativeBase $Path))
    }
    if (Test-Path -LiteralPath $candidate) {
        throw "$Label already exists; use a new append-only run directory: $candidate"
    }
    Assert-ExistingAncestorsNotReparse -Path $candidate -Label $Label
    return $candidate
}

function New-AppendOnlyDirectory {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Label
    )
    $fullPath = [IO.Path]::GetFullPath($Path)
    if (Test-Path -LiteralPath $fullPath) {
        throw "$Label appeared before creation; refusing to reuse it: $fullPath"
    }
    $parent = Split-Path -Parent $fullPath
    if ([string]::IsNullOrWhiteSpace($parent)) {
        throw "$Label must name a child directory: $fullPath"
    }
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Assert-ExistingAncestorsNotReparse -Path $fullPath -Label $Label
    if (Test-Path -LiteralPath $fullPath) {
        throw "$Label appeared during parent creation; refusing to reuse it: $fullPath"
    }
    New-Item -ItemType Directory -Path $fullPath | Out-Null
}

function Test-PathEqual {
    param([string]$Left, [string]$Right)
    return [IO.Path]::GetFullPath($Left).Equals(
        [IO.Path]::GetFullPath($Right),
        [StringComparison]::OrdinalIgnoreCase
    )
}

function Write-JsonUtf8 {
    param(
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string]$Path,
        [int]$Depth = 20
    )
    $json = $Value | ConvertTo-Json -Depth $Depth
    [IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
}

function Read-JsonFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Label
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label is missing: $Path"
    }
    try {
        return [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "$Label is not valid JSON: $($_.Exception.Message)"
    }
}

function Assert-JsonTrue {
    param($Value, [string]$Label)
    if (-not ($Value -is [bool]) -or -not $Value) {
        throw "$Label must be the JSON boolean true."
    }
}

function Assert-JsonFalse {
    param($Value, [string]$Label)
    if (-not ($Value -is [bool]) -or $Value) {
        throw "$Label must be the JSON boolean false."
    }
}

function Assert-FileMagic {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][byte[]]$Expected,
        [Parameter(Mandatory)][string]$Label
    )
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        foreach ($expectedByte in $Expected) {
            if ($stream.ReadByte() -ne [int]$expectedByte) {
                throw "$Label has an unexpected file signature: $Path"
            }
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Get-FileEvidence {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Label = 'Evidence file'
    )
    $fullPath = Resolve-RequiredRegularFile -Path $Path -Label $Label
    $item = Get-Item -LiteralPath $fullPath -Force
    $reportedPath = if (Test-MayorPathInside -Candidate $fullPath -Parent $projectRoot) {
        [IO.Path]::GetRelativePath($projectRoot, $fullPath).Replace('\', '/')
    }
    else {
        $fullPath
    }
    return [pscustomobject][ordered]@{
        path = $reportedPath
        bytes = [long]$item.Length
        sha256 = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

function Assert-ExactRegularFiles {
    param(
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][string[]]$ExpectedNames,
        [Parameter(Mandatory)][string]$Label
    )
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        throw "$Label directory is missing: $Directory"
    }
    $directoryItem = Assert-MayorNotReparsePoint -Path $Directory -Label "$Label directory"
    if (-not $directoryItem.PSIsContainer) {
        throw "$Label is not a directory: $Directory"
    }
    $entries = @(Get-ChildItem -LiteralPath $Directory -Force)
    if ($entries.Count -ne $ExpectedNames.Count) {
        throw "$Label file count mismatch: expected $($ExpectedNames.Count), found $($entries.Count)."
    }
    $actualNames = @($entries | ForEach-Object { $_.Name })
    [Array]::Sort($actualNames, [StringComparer]::Ordinal)
    $expectedSorted = @($ExpectedNames)
    [Array]::Sort($expectedSorted, [StringComparer]::Ordinal)
    for ($index = 0; $index -lt $expectedSorted.Count; $index++) {
        if ($actualNames[$index] -cne $expectedSorted[$index]) {
            throw "$Label content mismatch: expected '$($expectedSorted[$index])', found '$($actualNames[$index])'."
        }
    }
    foreach ($entry in $entries) {
        if ($entry.PSIsContainer -or ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "$Label contains a directory or reparse point: $($entry.FullName)"
        }
    }
}

function Get-StreamSha256 {
    param([Parameter(Mandatory)][IO.Stream]$Stream)
    $hasher = [Security.Cryptography.SHA256]::Create()
    try {
        return [Convert]::ToHexString($hasher.ComputeHash($Stream)).ToLowerInvariant()
    }
    finally {
        $hasher.Dispose()
    }
}

$commandRecords = [System.Collections.Generic.List[object]]::new()

function Invoke-CapturedCommand {
    param(
        [Parameter(Mandatory)][ValidatePattern('^[a-z0-9_-]+$')][string]$Id,
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][string]$LogDirectory,
        [Parameter(Mandatory)][ValidateRange(1, 86400)][int]$TimeoutSeconds,
        [hashtable]$Environment = @{}
    )

    $stdoutPath = Join-Path $LogDirectory "$Id.stdout.log"
    $stderrPath = Join-Path $LogDirectory "$Id.stderr.log"
    if ((Test-Path -LiteralPath $stdoutPath) -or (Test-Path -LiteralPath $stderrPath)) {
        throw "Command log path already exists for '$Id'."
    }

    $start = [DateTimeOffset]::UtcNow
    $process = [Diagnostics.Process]::new()
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Executable
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $Arguments) {
        $null = $startInfo.ArgumentList.Add([string]$argument)
    }
    foreach ($name in $Environment.Keys) {
        $startInfo.Environment[[string]$name] = [string]$Environment[$name]
    }
    $process.StartInfo = $startInfo

    $started = $false
    $timedOut = $false
    $exitCode = -1
    $stdout = ''
    $stderr = ''
    $captureError = ''
    $outputCaptureComplete = $false
    try {
        $started = $process.Start()
        if (-not $started) {
            throw "Process.Start returned false for command '$Id'."
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $completed = $process.WaitForExit($TimeoutSeconds * 1000)
        if (-not $completed) {
            $timedOut = $true
            try { $process.Kill($true) } catch { }
            $null = $process.WaitForExit(30000)
        }
        if ($process.HasExited) {
            $exitCode = [int]$process.ExitCode
            $stdoutReady = $stdoutTask.Wait(15000)
            $stderrReady = $stderrTask.Wait(15000)
            if (-not $stdoutReady -or -not $stderrReady) {
                try { $process.StandardOutput.Dispose() } catch { }
                try { $process.StandardError.Dispose() } catch { }
                throw "Redirected output pipes did not close after command '$Id' exited."
            }
            $stdout = $stdoutTask.GetAwaiter().GetResult()
            $stderr = $stderrTask.GetAwaiter().GetResult()
            $outputCaptureComplete = $true
        }
        else {
            # Never turn an acceptance timeout into an unbounded redirected-
            # pipe wait. Closing the readers lets their tasks settle; any
            # incomplete tail is explicitly recorded as such.
            try { $process.StandardOutput.Dispose() } catch { }
            try { $process.StandardError.Dispose() } catch { }
            try {
                if ($stdoutTask.Wait(5000)) { $stdout = $stdoutTask.GetAwaiter().GetResult() }
            }
            catch { }
            try {
                if ($stderrTask.Wait(5000)) { $stderr = $stderrTask.GetAwaiter().GetResult() }
            }
            catch { }
            $stderr += "COMMAND_PROCESS_TREE_DID_NOT_EXIT_AFTER_TIMEOUT$([Environment]::NewLine)"
        }
    }
    catch {
        $captureError = $_.Exception.Message
        if ($started -and -not $process.HasExited) {
            try { $process.Kill($true) } catch { }
            $null = $process.WaitForExit(30000)
        }
        if ($started -and $process.HasExited) {
            $exitCode = [int]$process.ExitCode
        }
        $stderr = if ([string]::IsNullOrEmpty($stderr)) {
            "COMMAND_START_OR_WAIT_ERROR: $captureError$([Environment]::NewLine)"
        }
        else {
            $stderr + [Environment]::NewLine + "COMMAND_START_OR_WAIT_ERROR: $captureError" + [Environment]::NewLine
        }
    }
    finally {
        $process.Dispose()
    }

    [IO.File]::WriteAllText($stdoutPath, $stdout, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($stderrPath, $stderr, [Text.UTF8Encoding]::new($false))
    $finish = [DateTimeOffset]::UtcNow
    $environmentRecord = [ordered]@{}
    foreach ($name in @($Environment.Keys | Sort-Object)) {
        $environmentRecord[[string]$name] = [string]$Environment[$name]
    }
    $record = [pscustomobject][ordered]@{
        id = $Id
        executable = $Executable
        arguments = @($Arguments)
        working_directory = $WorkingDirectory
        environment_overrides = $environmentRecord
        started = $started
        started_at_utc = $start.ToString('o')
        finished_at_utc = $finish.ToString('o')
        duration_seconds = [Math]::Round(($finish - $start).TotalSeconds, 3)
        timeout_seconds = $TimeoutSeconds
        timed_out = $timedOut
        exit_code = $exitCode
        output_capture_complete = $outputCaptureComplete
        capture_error = $captureError
        stdout_path = $stdoutPath
        stderr_path = $stderrPath
    }
    $commandRecords.Add($record)
    return $record
}

function Assert-CommandSucceeded {
    param([Parameter(Mandatory)]$Command)
    if (-not $Command.started -or
        $Command.timed_out -or
        [int]$Command.exit_code -ne 0 -or
        -not $Command.output_capture_complete -or
        -not [string]::IsNullOrEmpty([string]$Command.capture_error)) {
        throw "Command '$($Command.id)' failed: started=$($Command.started) timed_out=$($Command.timed_out) exit=$($Command.exit_code) capture_complete=$($Command.output_capture_complete). See its independent stdout/stderr logs."
    }
}

function Get-LogAssessment {
    param([Parameter(Mandatory)][string[]]$Paths)

    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($path in $Paths) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Required Godot log is missing: $path"
        }
        $parts.Add([IO.File]::ReadAllText($path, [Text.Encoding]::UTF8))
    }
    $ansiPattern = "`e\[[0-?]*[ -/]*[@-~]"
    $certificatePattern = '(?m)^ERROR: Failed to read the root certificate store\.\r?\n\s*at: get_system_ca_certificates \(platform/windows/os_windows\.cpp:\d+\)\r?\n?'
    $plain = [regex]::Replace(($parts -join "`n"), $ansiPattern, '')
    $environmentWarningCount = [regex]::Matches($plain, $certificatePattern).Count
    $productLog = [regex]::Replace($plain, $certificatePattern, '')
    $diagnostics = @([regex]::Matches($productLog, '(?im)^(?:SCRIPT ERROR|ERROR|WARNING):[^\r\n]*') | ForEach-Object { $_.Value.Trim() })
    $leakPatterns = @(
        'Leaked instance:',
        'ObjectDB instances? (?:was|were) leaked at exit',
        'resources? still in use at exit',
        'Resource still in use:',
        'Orphan StringName:',
        'unclaimed string names at exit'
    )
    $leaks = [System.Collections.Generic.List[string]]::new()
    foreach ($pattern in $leakPatterns) {
        if ([regex]::IsMatch($productLog, $pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            $leaks.Add($pattern)
        }
    }
    return [pscustomobject][ordered]@{
        environment_warning_count = $environmentWarningCount
        product_diagnostic_count = $diagnostics.Count
        leak_signature_count = $leaks.Count
        product_diagnostics = $diagnostics
        leak_signatures = @($leaks)
        product_clean = $diagnostics.Count -eq 0 -and $leaks.Count -eq 0
    }
}

function Assert-FingerprintEqual {
    param($Expected, $Actual, [string]$Label)
    if ([int]$Expected.file_count -ne [int]$Actual.file_count -or
        [long]$Expected.total_bytes -ne [long]$Actual.total_bytes -or
        [string]$Expected.fingerprint_sha256 -cne [string]$Actual.fingerprint_sha256) {
        throw "$Label source fingerprint changed during the single-run release acceptance."
    }
}

function Install-VerifiedTemplates {
    param(
        [Parameter(Mandatory)][string]$ArchivePath,
        [Parameter(Mandatory)][string]$DestinationDirectory,
        [Parameter(Mandatory)][string]$ManifestPath
    )

    if (Test-Path -LiteralPath $DestinationDirectory) {
        throw "Template destination must be clean and absent: $DestinationDirectory"
    }
    New-Item -ItemType Directory -Path $DestinationDirectory | Out-Null

    $archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    $records = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    try {
        foreach ($entry in $archive.Entries) {
            $archiveName = $entry.FullName.Replace('\', '/')
            if ([string]::IsNullOrWhiteSpace($archiveName)) {
                throw 'Template archive contains an empty entry name.'
            }
            if ($archiveName.StartsWith('/', [StringComparison]::Ordinal) -or
                $archiveName.Contains(':') -or
                @($archiveName.Split('/') | Where-Object { $_ -eq '..' -or $_ -eq '.' }).Count -gt 0) {
                throw "Template archive contains an unsafe entry path: $archiveName"
            }
            if ($archiveName.EndsWith('/', [StringComparison]::Ordinal)) {
                continue
            }
            if (-not $archiveName.StartsWith('templates/', [StringComparison]::Ordinal)) {
                throw "Template archive file is outside the expected templates/ root: $archiveName"
            }
            $relativeName = $archiveName.Substring('templates/'.Length)
            if ([string]::IsNullOrWhiteSpace($relativeName) -or -not $seen.Add($relativeName)) {
                throw "Template archive contains an empty or duplicate file: $relativeName"
            }
            $destinationPath = [IO.Path]::GetFullPath((Join-Path $DestinationDirectory $relativeName))
            if (-not (Test-MayorPathInside -Candidate $destinationPath -Parent $DestinationDirectory)) {
                throw "Template archive entry escaped the clean install directory: $archiveName"
            }
            $parent = Split-Path -Parent $destinationPath
            if (-not (Test-Path -LiteralPath $parent)) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }

            $entryStream = $entry.Open()
            try {
                $entryHash = Get-StreamSha256 -Stream $entryStream
            }
            finally {
                $entryStream.Dispose()
            }
            $entryStream = $entry.Open()
            $destinationStream = [IO.File]::Open($destinationPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try {
                $entryStream.CopyTo($destinationStream)
                $destinationStream.Flush($true)
            }
            finally {
                $destinationStream.Dispose()
                $entryStream.Dispose()
            }
            $installedHash = (Get-FileHash -LiteralPath $destinationPath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($installedHash -cne $entryHash) {
                throw "Installed export template differs from its archive entry: $relativeName"
            }
            $records.Add([pscustomobject][ordered]@{
                path = $relativeName.Replace('\', '/')
                bytes = [long](Get-Item -LiteralPath $destinationPath).Length
                sha256 = $installedHash
            })
        }
    }
    finally {
        $archive.Dispose()
    }

    foreach ($requiredTemplate in @('windows_release_x86_64.exe', 'linux_release.x86_64')) {
        if (-not $seen.Contains($requiredTemplate)) {
            throw "Official template archive is missing required export template: $requiredTemplate"
        }
    }
    $installedItems = @(Get-ChildItem -LiteralPath $DestinationDirectory -Recurse -Force)
    foreach ($item in $installedItems) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Clean template install contains a reparse point: $($item.FullName)"
        }
    }
    $installedFiles = @($installedItems | Where-Object { -not $_.PSIsContainer })
    if ($installedFiles.Count -ne $records.Count) {
        throw "Clean template install file count mismatch: expected $($records.Count), found $($installedFiles.Count)."
    }

    $recordArray = @($records)
    [Array]::Sort($recordArray, [Comparison[object]]{
        param($left, $right)
        return [StringComparer]::Ordinal.Compare([string]$left.path, [string]$right.path)
    })
    $canonicalLines = @($recordArray | ForEach-Object { "$($_.path)`t$($_.bytes)`t$($_.sha256)" })
    $canonicalBytes = [Text.UTF8Encoding]::new($false).GetBytes(($canonicalLines -join "`n") + "`n")
    $hasher = [Security.Cryptography.SHA256]::Create()
    try {
        $templateFingerprint = [Convert]::ToHexString($hasher.ComputeHash($canonicalBytes)).ToLowerInvariant()
    }
    finally {
        $hasher.Dispose()
    }
    $manifest = [pscustomobject][ordered]@{
        schema_version = 1
        source_archive_sha256 = $OFFICIAL_GODOT_47_TEMPLATES_SHA256
        installed_directory = $DestinationDirectory
        file_count = $recordArray.Count
        total_bytes = [long](($recordArray | Measure-Object -Property bytes -Sum).Sum)
        fingerprint_sha256 = $templateFingerprint
        entries = $recordArray
    }
    Write-JsonUtf8 -Value $manifest -Path $ManifestPath -Depth 8
    return $manifest
}

function Assert-InstalledTemplatesMatchManifest {
    param(
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)]$Manifest
    )
    $records = [System.Collections.Generic.List[object]]::new()
    $pending = [System.Collections.Generic.Stack[string]]::new()
    $pending.Push($Directory)
    while ($pending.Count -gt 0) {
        foreach ($item in @(Get-ChildItem -LiteralPath $pending.Pop() -Force)) {
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Installed template tree contains a reparse point after use: $($item.FullName)"
            }
            if ($item.PSIsContainer) {
                $pending.Push($item.FullName)
                continue
            }
            $records.Add([pscustomobject][ordered]@{
                path = [IO.Path]::GetRelativePath($Directory, $item.FullName).Replace('\', '/')
                bytes = [long]$item.Length
                sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            })
        }
    }
    $recordArray = @($records)
    [Array]::Sort($recordArray, [Comparison[object]]{
        param($left, $right)
        return [StringComparer]::Ordinal.Compare([string]$left.path, [string]$right.path)
    })
    $expectedRecords = @($Manifest.entries)
    if ($recordArray.Count -ne [int]$Manifest.file_count -or $expectedRecords.Count -ne $recordArray.Count) {
        throw 'Installed template tree file count changed after export.'
    }
    for ($index = 0; $index -lt $recordArray.Count; $index++) {
        if ([string]$recordArray[$index].path -cne [string]$expectedRecords[$index].path -or
            [long]$recordArray[$index].bytes -ne [long]$expectedRecords[$index].bytes -or
            [string]$recordArray[$index].sha256 -cne [string]$expectedRecords[$index].sha256) {
            throw "Installed template tree changed after export at index $index."
        }
    }
    $canonicalLines = @($recordArray | ForEach-Object { "$($_.path)`t$($_.bytes)`t$($_.sha256)" })
    $canonicalBytes = [Text.UTF8Encoding]::new($false).GetBytes(($canonicalLines -join "`n") + "`n")
    $hasher = [Security.Cryptography.SHA256]::Create()
    try {
        $fingerprint = [Convert]::ToHexString($hasher.ComputeHash($canonicalBytes)).ToLowerInvariant()
    }
    finally {
        $hasher.Dispose()
    }
    if ($fingerprint -cne [string]$Manifest.fingerprint_sha256) {
        throw 'Installed template tree fingerprint changed after export.'
    }
    return [pscustomobject][ordered]@{
        file_count = $recordArray.Count
        fingerprint_sha256 = $fingerprint
        exact_match = $true
    }
}

function Assert-SummaryWithinCommandWindow {
    param(
        [Parameter(Mandatory)]$Summary,
        [Parameter(Mandatory)]$Command,
        [Parameter(Mandatory)][string]$Label
    )
    try {
        $summaryStart = [DateTimeOffset]::Parse([string]$Summary.started_at)
        $summaryFinish = [DateTimeOffset]::Parse([string]$Summary.finished_at)
        $commandStart = [DateTimeOffset]::Parse([string]$Command.started_at_utc).AddSeconds(-2)
        $commandFinish = [DateTimeOffset]::Parse([string]$Command.finished_at_utc).AddSeconds(2)
    }
    catch {
        throw "$Label contains invalid run timestamps."
    }
    if ($summaryStart -lt $commandStart -or $summaryFinish -gt $commandFinish -or $summaryFinish -lt $summaryStart) {
        throw "$Label timestamps do not belong to the captured command run."
    }
}

function Assert-AssertionMatrixSummary {
    param(
        [Parameter(Mandatory)]$Summary,
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$ManifestPath,
        [Parameter(Mandatory)][string]$ExpectedOutputRoot,
        [Parameter(Mandatory)][string]$ExpectedGodotExe,
        [Parameter(Mandatory)]$Command
    )

    $manifestTests = @($Manifest.tests)
    $results = @($Summary.results)
    if ([string]$Summary.matrix -cne [string]$Manifest.name -or
        [int]$Summary.schema_version -ne [int]$Manifest.schema_version -or
        -not (Test-PathEqual -Left ([string]$Summary.manifest) -Right $ManifestPath) -or
        -not (Test-PathEqual -Left ([string]$Summary.project_root) -Right $projectRoot) -or
        -not (Test-PathEqual -Left ([string]$Summary.output_root) -Right $ExpectedOutputRoot) -or
        -not (Test-PathEqual -Left ([string]$Summary.godot_executable) -Right $ExpectedGodotExe) -or
        [int]$Summary.manifest_test_count -ne $manifestTests.Count -or
        [int]$Summary.selected_test_count -ne $manifestTests.Count -or
        [int]$Summary.product_clean_count -ne $manifestTests.Count -or
        [int]$Summary.failed_count -ne 0 -or
        $results.Count -ne $manifestTests.Count) {
        throw 'Assertion matrix summary does not satisfy the complete current-manifest contract.'
    }
    Assert-SummaryWithinCommandWindow -Summary $Summary -Command $Command -Label 'Assertion matrix summary'

    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    for ($index = 0; $index -lt $manifestTests.Count; $index++) {
        $expected = $manifestTests[$index]
        $result = $results[$index]
        $id = [string]$result.id
        if (-not $seen.Add($id) -or $id -cne [string]$expected.id -or [string]$result.script -cne [string]$expected.script) {
            throw "Assertion matrix result order, id, or script mismatch at index $index."
        }
        Assert-JsonTrue -Value $result.product_clean -Label "Assertion result '$id' product_clean"
        if ([int]$result.exit_code -ne 0 -or @($result.failure_reasons).Count -ne 0) {
            throw "Assertion result is not clean: $id"
        }
        $warningCount = [int]$result.environment_warning_count
        $expectedStatus = if ($warningCount -gt 0) { 'PASS_WITH_ENVIRONMENT_WARNING' } else { 'PASS' }
        if ($warningCount -lt 0 -or [string]$result.status -cne $expectedStatus) {
            throw "Assertion result has an inconsistent status or warning count: $id"
        }
        $expectedCaseRoot = Join-Path $ExpectedOutputRoot ('{0:D2}-{1}' -f ($index + 1), $id)
        if (-not (Test-PathEqual -Left ([string]$result.output_directory) -Right $expectedCaseRoot)) {
            throw "Assertion result points outside its fresh run directory: $id"
        }
    }
}

function Assert-CleanSaveKillWorkerRun {
    param($Run, [string]$Label)
    if ($null -eq $Run) {
        throw "$Label is missing."
    }
    Assert-JsonTrue -Value $Run.completed -Label "$Label completed"
    Assert-JsonTrue -Value $Run.all_processes_stopped -Label "$Label all_processes_stopped"
    Assert-JsonTrue -Value $Run.success_marker -Label "$Label success_marker"
    Assert-JsonTrue -Value $Run.product_clean -Label "$Label product_clean"
    if ([int]$Run.exit_code -ne 0 -or @($Run.product_diagnostics).Count -ne 0 -or @($Run.leak_signatures).Count -ne 0) {
        throw "$Label is not a clean completed worker run."
    }
}

function Assert-SaveOsKillSummary {
    param(
        [Parameter(Mandatory)]$Summary,
        [Parameter(Mandatory)][string]$ExpectedOutputRoot,
        [Parameter(Mandatory)][string]$ExpectedGodotExe,
        [Parameter(Mandatory)][string]$ExpectedGodotVersion,
        [Parameter(Mandatory)]$Command
    )

    $results = @($Summary.results)
    $summaryPhases = @($Summary.required_phases)
    if ([int]$Summary.schema_version -ne 1 -or
        [string]$Summary.suite -cne 'mayor-simulator-save-os-kill-qa' -or
        [string]$Summary.output_root_policy -cne 'refuse_existing_directory' -or
        -not (Test-PathEqual -Left ([string]$Summary.project_root) -Right $projectRoot) -or
        -not (Test-PathEqual -Left ([string]$Summary.output_root) -Right $ExpectedOutputRoot) -or
        -not (Test-PathEqual -Left ([string]$Summary.godot_executable) -Right $ExpectedGodotExe) -or
        [string]$Summary.godot_version -cne $ExpectedGodotVersion -or
        [int]$Summary.requested_phase_count -ne $requiredSaveKillPhases.Count -or
        [int]$Summary.result_count -ne $requiredSaveKillPhases.Count -or
        [int]$Summary.product_clean_count -ne $requiredSaveKillPhases.Count -or
        [int]$Summary.passed_count -ne $requiredSaveKillPhases.Count -or
        [int]$Summary.failed_count -ne 0 -or
        [int]$Summary.forced_termination_count -ne $requiredSaveKillPhases.Count -or
        [int]$Summary.semantic_check_total -lt 173 -or
        $summaryPhases.Count -ne $requiredSaveKillPhases.Count -or
        $results.Count -ne $requiredSaveKillPhases.Count) {
        throw 'OS-kill summary does not satisfy the complete five-phase durability contract.'
    }
    Assert-JsonTrue -Value $Summary.all_processes_stopped -Label 'OS-kill summary all_processes_stopped'
    Assert-SummaryWithinCommandWindow -Summary $Summary -Command $Command -Label 'OS-kill summary'

    for ($index = 0; $index -lt $requiredSaveKillPhases.Count; $index++) {
        if ([string]$summaryPhases[$index] -cne $requiredSaveKillPhases[$index]) {
            throw "OS-kill required phase order mismatch at index $index."
        }
        $phase = $requiredSaveKillPhases[$index]
        $result = $results[$index]
        if ([string]$result.phase -cne $phase -or [string]$result.status -cne 'PASS' -or @($result.errors).Count -ne 0) {
            throw "OS-kill result failed or is out of order: $phase"
        }
        Assert-JsonTrue -Value $result.product_clean -Label "OS-kill '$phase' product_clean"
        Assert-CleanSaveKillWorkerRun -Run $result.seed_run -Label "OS-kill '$phase' seed run"
        Assert-CleanSaveKillWorkerRun -Run $result.verification_run -Label "OS-kill '$phase' verification run"

        $marker = $result.interruption_marker
        $interruption = $result.interruption_run
        if ($null -eq $marker -or $null -eq $interruption -or
            [int]$marker.schema_version -ne 1 -or
            [string]$marker.phase -cne $phase -or
            [int]$marker.process_id -le 0 -or
            [int]$marker.process_id -ne [int]$interruption.writer_process_id -or
            [int]$interruption.marker_process_id -ne [int]$interruption.writer_process_id) {
            throw "OS-kill interruption identity evidence is invalid: $phase"
        }
        Assert-JsonTrue -Value $marker.ready_for_forced_termination -Label "OS-kill '$phase' marker ready"
        Assert-JsonTrue -Value $interruption.stop_process_force -Label "OS-kill '$phase' forced termination"
        Assert-JsonTrue -Value $interruption.writer_exited_after_stop -Label "OS-kill '$phase' writer stopped"
        Assert-JsonTrue -Value $interruption.launcher_exited_after_stop -Label "OS-kill '$phase' launcher stopped"
        Assert-JsonTrue -Value $interruption.product_clean_before_termination -Label "OS-kill '$phase' pre-termination product clean"

        $semantic = $result.semantic_verification
        $expectedSource = if ($phase -ceq 'primary_rotated') { 'backup' } else { 'primary' }
        if ($null -eq $semantic -or
            [int]$semantic.schema_version -ne 1 -or
            [string]$semantic.mode -cne 'verify' -or
            [string]$semantic.phase -cne $phase -or
            [int]$semantic.checks -le 0 -or
            @($semantic.failures).Count -ne 0 -or
            [string]$semantic.load_source -cne $expectedSource -or
            [int]$semantic.recovery_error -ne 0) {
            throw "OS-kill semantic verification evidence is invalid: $phase"
        }
        Assert-JsonTrue -Value $semantic.success -Label "OS-kill '$phase' semantic success"
        $followUp = $semantic.after_follow_up_save
        Assert-JsonTrue -Value $followUp.primary.exists -Label "OS-kill '$phase' follow-up primary exists"
        Assert-JsonTrue -Value $followUp.primary.semantic_valid -Label "OS-kill '$phase' follow-up primary semantic_valid"
        Assert-JsonTrue -Value $followUp.backup.exists -Label "OS-kill '$phase' follow-up backup exists"
        Assert-JsonTrue -Value $followUp.backup.semantic_valid -Label "OS-kill '$phase' follow-up backup semantic_valid"
        Assert-JsonFalse -Value $followUp.temporary.exists -Label "OS-kill '$phase' stale temporary exists"
        Assert-JsonFalse -Value $followUp.recovery_temporary.exists -Label "OS-kill '$phase' stale recovery temporary exists"

        $expectedCaseRoot = Join-Path $ExpectedOutputRoot ('{0:D2}-{1}' -f ($index + 1), $phase)
        if (-not (Test-PathEqual -Left ([string]$result.case_root) -Right $expectedCaseRoot)) {
            throw "OS-kill result points outside its fresh run directory: $phase"
        }
    }

    $hashInputs = [ordered]@{
        runner_sha256 = 'tools/run_save_os_kill_qa.ps1'
        worker_sha256 = 'tests/qa/save_os_kill_worker.gd'
        save_service_sha256 = 'scripts/core/save_service.gd'
    }
    foreach ($field in $hashInputs.Keys) {
        $currentHash = (Get-FileHash -LiteralPath (Join-Path $projectRoot $hashInputs[$field]) -Algorithm SHA256).Hash.ToLowerInvariant()
        if ([string]$Summary.$field -cne $currentHash) {
            throw "OS-kill summary source hash is stale for $($hashInputs[$field])."
        }
    }
}

function Assert-ExportStaging {
    param(
        [Parameter(Mandatory)][string]$WindowsDirectory,
        [Parameter(Mandatory)][string]$LinuxDirectory
    )
    $commonDocuments = @('RELEASE_README.txt', 'THIRD_PARTY_NOTICES.md', 'GODOT_COPYRIGHT.txt')
    Assert-ExactRegularFiles -Directory $WindowsDirectory -ExpectedNames (@('MayorSimulator.exe', 'MayorSimulator.pck') + $commonDocuments) -Label 'Windows staging'
    Assert-ExactRegularFiles -Directory $LinuxDirectory -ExpectedNames (@('MayorSimulator.x86_64', 'MayorSimulator.pck') + $commonDocuments) -Label 'Linux staging'

    $windowsExe = Join-Path $WindowsDirectory 'MayorSimulator.exe'
    $windowsPck = Join-Path $WindowsDirectory 'MayorSimulator.pck'
    $linuxExe = Join-Path $LinuxDirectory 'MayorSimulator.x86_64'
    $linuxPck = Join-Path $LinuxDirectory 'MayorSimulator.pck'
    if ((Get-Item -LiteralPath $windowsExe).Length -lt 1MB -or
        (Get-Item -LiteralPath $linuxExe).Length -lt 1MB -or
        (Get-Item -LiteralPath $windowsPck).Length -lt 1KB -or
        (Get-Item -LiteralPath $linuxPck).Length -lt 1KB) {
        throw 'Exported runtime or PCK is implausibly small.'
    }
    Assert-FileMagic -Path $windowsExe -Expected ([byte[]]@(0x4D, 0x5A)) -Label 'Windows executable'
    Assert-FileMagic -Path $windowsPck -Expected ([byte[]]@(0x47, 0x44, 0x50, 0x43)) -Label 'Windows PCK'
    Assert-FileMagic -Path $linuxExe -Expected ([byte[]]@(0x7F, 0x45, 0x4C, 0x46)) -Label 'Linux executable'
    Assert-FileMagic -Path $linuxPck -Expected ([byte[]]@(0x47, 0x44, 0x50, 0x43)) -Label 'Linux PCK'

    foreach ($name in $commonDocuments) {
        $canonicalHash = (Get-FileHash -LiteralPath (Join-Path $projectRoot $name) -Algorithm SHA256).Hash.ToLowerInvariant()
        foreach ($directory in @($WindowsDirectory, $LinuxDirectory)) {
            $stagedHash = (Get-FileHash -LiteralPath (Join-Path $directory $name) -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($stagedHash -cne $canonicalHash) {
                throw "Staged release document differs from the canonical project file: $name"
            }
        }
    }
    $windowsPckHash = (Get-FileHash -LiteralPath $windowsPck -Algorithm SHA256).Hash.ToLowerInvariant()
    $linuxPckHash = (Get-FileHash -LiteralPath $linuxPck -Algorithm SHA256).Hash.ToLowerInvariant()
    if ((Get-Item -LiteralPath $windowsPck).Length -ne (Get-Item -LiteralPath $linuxPck).Length -or
        $windowsPckHash -cne $linuxPckHash) {
        throw 'Windows and Linux exports do not contain the exact same PCK payload.'
    }
    return [pscustomobject][ordered]@{
        pck_bytes = [long](Get-Item -LiteralPath $windowsPck).Length
        pck_sha256 = $windowsPckHash
        pck_byte_identical = $true
    }
}

function Assert-PackageDirectory {
    param(
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][string]$ReleaseVersion
    )
    $windowsName = "MayorSimulator-Windows-x86_64-$ReleaseVersion.zip"
    $linuxName = "MayorSimulator-Linux-x86_64-$ReleaseVersion.tar.gz"
    Assert-ExactRegularFiles -Directory $Directory -ExpectedNames @($windowsName, $linuxName, 'SHA256SUMS') -Label 'Package output'
    $windowsPath = Join-Path $Directory $windowsName
    $linuxPath = Join-Path $Directory $linuxName
    $checksumsPath = Join-Path $Directory 'SHA256SUMS'
    $expectedLines = @(
        "$((Get-FileHash -LiteralPath $windowsPath -Algorithm SHA256).Hash.ToLowerInvariant())  $windowsName",
        "$((Get-FileHash -LiteralPath $linuxPath -Algorithm SHA256).Hash.ToLowerInvariant())  $linuxName"
    )
    $actualLines = @([IO.File]::ReadAllLines($checksumsPath, [Text.UTF8Encoding]::new($false)))
    if ($actualLines.Count -ne $expectedLines.Count) {
        throw 'SHA256SUMS line count mismatch.'
    }
    for ($index = 0; $index -lt $expectedLines.Count; $index++) {
        if ($actualLines[$index] -cne $expectedLines[$index]) {
            throw "SHA256SUMS mismatch at line $($index + 1)."
        }
    }
    return [pscustomobject][ordered]@{
        windows_archive = $windowsPath
        linux_archive = $linuxPath
        checksums = $checksumsPath
    }
}

function Assert-SourceUidCompanions {
    foreach ($relativeDirectory in @('scripts', 'systems', 'ui', 'tests')) {
        $directory = Join-Path $projectRoot $relativeDirectory
        $null = Assert-MayorNotReparsePoint -Path $directory -Label "UID source directory '$relativeDirectory'"
        $pending = [System.Collections.Generic.Stack[string]]::new()
        $pending.Push($directory)
        while ($pending.Count -gt 0) {
            foreach ($source in @(Get-ChildItem -LiteralPath $pending.Pop() -Force)) {
                if (($source.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw "UID source scope must not contain a reparse point: $($source.FullName)"
                }
                if ($source.PSIsContainer) {
                    $pending.Push($source.FullName)
                    continue
                }
                if ($source.Extension -cne '.gd' -and $source.Extension -cne '.gdshader') {
                    continue
                }
                $uidPath = $source.FullName + '.uid'
                if (-not (Test-Path -LiteralPath $uidPath -PathType Leaf)) {
                    throw "Godot source UID companion is missing; run an official editor import before release acceptance: $uidPath"
                }
                $null = Assert-MayorNotReparsePoint -Path $uidPath -Label 'Godot source UID companion'
            }
        }
    }
}

# Preflight is intentionally read-only. In particular, a reused OutputRoot or
# a non-official template archive fails before any acceptance directory exists.
$rootLicenseFiles = @(
    Get-ChildItem -LiteralPath $projectRoot -File |
        Where-Object { $_.Name -match '^(?i:LICENSE(?:\..*)?|COPYING(?:\..*)?)$' }
)
if ($rootLicenseFiles.Count -eq 0) {
    throw 'Release license preflight failed: no root LICENSE or COPYING file exists.'
}

$runtimeLedgerPath = Join-Path $projectRoot 'docs\project-organization\RUNTIME_ASSET_LEDGER.json'
$runtimeLedger = Read-JsonFile -Path $runtimeLedgerPath -Label 'Runtime asset ledger'
$blockedProvenanceAssets = @($runtimeLedger.assets | Where-Object {
    [string]$_.provenance_status -match '(?i:missing|unresolved|unknown|not_covered)'
})
$blockedRightsAssets = @($runtimeLedger.assets | Where-Object {
    [string]$_.rights_license_status -match '(?i:missing|unresolved|unknown|unselected)'
})
if ([string]$runtimeLedger.project_distribution_license_status -match '(?i:missing|unresolved|unknown|unselected)' -or
    [int]$runtimeLedger.unresolved_source_rights_asset_count -ne 0 -or
    $blockedProvenanceAssets.Count -ne 0 -or
    $blockedRightsAssets.Count -ne 0) {
    $blockedPaths = @(
        @($blockedProvenanceAssets + $blockedRightsAssets) |
            ForEach-Object { [string]$_.res_path } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique |
            Select-Object -First 10
    )
    throw "Release asset-rights preflight failed: project_license=$($runtimeLedger.project_distribution_license_status) unresolved_source_rights=$($runtimeLedger.unresolved_source_rights_asset_count) blocked_provenance=$($blockedProvenanceAssets.Count) blocked_rights=$($blockedRightsAssets.Count) sample_paths=[$($blockedPaths -join ', ')]"
}

$outputFullPath = Resolve-NewDirectoryPath -Path $OutputRoot -Label 'OutputRoot'
if (-not (Test-MayorPathInside -Candidate $outputFullPath -Parent $projectRoot) -or
    (Test-PathEqual -Left $outputFullPath -Right $projectRoot)) {
    throw "OutputRoot must be a new child directory inside the project: $outputFullPath"
}
foreach ($relativeSourceDirectory in @('assets', 'data', 'scenes', 'scripts', 'systems', 'tests', 'tools', 'ui', '.github/workflows')) {
    $sourceDirectory = Join-Path $projectRoot $relativeSourceDirectory
    if (Test-MayorPathInside -Candidate $outputFullPath -Parent $sourceDirectory) {
        throw "OutputRoot must not be inside fingerprinted source directory '$relativeSourceDirectory': $outputFullPath"
    }
}

$exportAppDataFullPath = Resolve-NewDirectoryPath -Path $ExportAppDataRoot -Label 'ExportAppDataRoot'
if (Test-MayorPathInside -Candidate $exportAppDataFullPath -Parent $projectRoot) {
    throw "ExportAppDataRoot must be outside the project so engine state cannot be confused with reviewed source: $exportAppDataFullPath"
}
if ((Test-MayorPathInside -Candidate $exportAppDataFullPath -Parent $outputFullPath) -or
    (Test-MayorPathInside -Candidate $outputFullPath -Parent $exportAppDataFullPath)) {
    throw 'OutputRoot and ExportAppDataRoot must be disjoint and must not contain one another.'
}

$godotFullPath = Resolve-RequiredRegularFile -Path $GodotExe -Label 'Godot executable'
$templatesFullPath = Resolve-RequiredRegularFile -Path $TemplatesArchive -Label 'Godot export templates archive'
$godotExecutableInitialHash = (Get-FileHash -LiteralPath $godotFullPath -Algorithm SHA256).Hash.ToLowerInvariant()
$templatesArchiveHash = (Get-FileHash -LiteralPath $templatesFullPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($templatesArchiveHash -cne $OFFICIAL_GODOT_47_TEMPLATES_SHA256) {
    throw "Export templates archive is not the pinned official Godot 4.7 archive. Expected $OFFICIAL_GODOT_47_TEMPLATES_SHA256, found $templatesArchiveHash."
}

Assert-SourceUidCompanions
$sourceStart = Get-MayorSourceFingerprint -ProjectRoot $projectRoot
$versionParts = $Version.Split('.')
$expectedWindowsVersion = '{0}.{1}.{2}.0' -f ([int]$versionParts[0]), ([int]$versionParts[1]), ([int]$versionParts[2])
$presetText = [IO.File]::ReadAllText((Join-Path $projectRoot 'export_presets.cfg'), [Text.Encoding]::UTF8)
if ($presetText.IndexOf("application/file_version=`"$expectedWindowsVersion`"", [StringComparison]::Ordinal) -lt 0 -or
    $presetText.IndexOf("application/product_version=`"$expectedWindowsVersion`"", [StringComparison]::Ordinal) -lt 0) {
    throw "Release Version '$Version' does not match export_presets.cfg Windows metadata '$expectedWindowsVersion'."
}

New-AppendOnlyDirectory -Path $outputFullPath -Label 'OutputRoot'
$logsRoot = Join-Path $outputFullPath 'logs'
$commandLogsRoot = Join-Path $logsRoot 'commands'
$godotLogsRoot = Join-Path $logsRoot 'godot'
$qaRoot = Join-Path $outputFullPath 'qa'
$stagingRoot = Join-Path $outputFullPath 'staging'
$windowsStaging = Join-Path $stagingRoot 'windows'
$linuxStaging = Join-Path $stagingRoot 'linux'
New-Item -ItemType Directory -Path $logsRoot, $qaRoot, $stagingRoot | Out-Null
New-Item -ItemType Directory -Path $commandLogsRoot, $godotLogsRoot | Out-Null

$sourceStartManifestPath = Join-Path $outputFullPath 'source-fingerprint-start.json'
Write-JsonUtf8 -Value $sourceStart -Path $sourceStartManifestPath -Depth 8

New-AppendOnlyDirectory -Path $exportAppDataFullPath -Label 'ExportAppDataRoot'
$godotAppData = Join-Path $exportAppDataFullPath 'godot-appdata'
$godotLocalAppData = Join-Path $exportAppDataFullPath 'godot-localappdata'
$smokeAppData = Join-Path $exportAppDataFullPath 'smoke-appdata'
$smokeLocalAppData = Join-Path $exportAppDataFullPath 'smoke-localappdata'
New-Item -ItemType Directory -Path $godotAppData, $godotLocalAppData, $smokeAppData, $smokeLocalAppData | Out-Null
$templateParent = Join-Path $godotAppData 'Godot\export_templates'
New-Item -ItemType Directory -Path $templateParent -Force | Out-Null
$templateInstallDirectory = Join-Path $templateParent '4.7.stable'
$templateManifestPath = Join-Path $outputFullPath 'installed-template-manifest.json'
$templateManifest = Install-VerifiedTemplates `
    -ArchivePath $templatesFullPath `
    -DestinationDirectory $templateInstallDirectory `
    -ManifestPath $templateManifestPath

$engineEnvironment = @{
    APPDATA = $godotAppData
    LOCALAPPDATA = $godotLocalAppData
}
$smokeEnvironment = @{
    APPDATA = $smokeAppData
    LOCALAPPDATA = $smokeLocalAppData
}
$pwshExe = (Get-Process -Id $PID).Path
$published = $false
$evidencePartialPath = Join-Path $outputFullPath 'release-evidence.json.partial'
$evidenceFinalPath = Join-Path $outputFullPath 'release-evidence.json'

try {
    $versionCommand = Invoke-CapturedCommand `
        -Id 'godot_version' `
        -Executable $godotFullPath `
        -Arguments @('--version') `
        -WorkingDirectory $projectRoot `
        -LogDirectory $commandLogsRoot `
        -TimeoutSeconds 60 `
        -Environment $engineEnvironment
    Assert-CommandSucceeded -Command $versionCommand
    $versionLines = @([IO.File]::ReadAllLines($versionCommand.stdout_path, [Text.Encoding]::UTF8) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($versionLines.Count -lt 1 -or $versionLines[0] -notmatch '^4\.7\.stable(?:\.|$)') {
        throw "Unexpected Godot executable version: $($versionLines -join ' | ')"
    }
    $godotVersion = $versionLines[0].Trim()

    $assertionOutputRoot = Join-Path $qaRoot 'assertion-matrix'
    $manifestPath = Join-Path $projectRoot 'tests\assertion_matrix.json'
    $manifest = Read-JsonFile -Path $manifestPath -Label 'Assertion manifest'
    $manifestTests = @($manifest.tests)
    $manifestTestIds = @($manifestTests | ForEach-Object { [string]$_.id })
    $manifestTestScripts = @($manifestTests | ForEach-Object { [string]$_.script })
    if ($null -ne $manifest.PSObject.Properties['expected_test_count'] -or
        $manifestTests.Count -lt 1 -or
        @($manifestTestIds | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0 -or
        @($manifestTestIds | Sort-Object -Unique).Count -ne $manifestTests.Count -or
        @($manifestTestScripts | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0 -or
        @($manifestTestScripts | Sort-Object -Unique).Count -ne $manifestTests.Count) {
        throw 'Assertion manifest must derive its count from a non-empty tests array with unique ids and scripts.'
    }
    $assertionCommand = Invoke-CapturedCommand `
        -Id 'assertion_matrix' `
        -Executable $pwshExe `
        -Arguments @(
            '-NoProfile', '-File', (Join-Path $PSScriptRoot 'run_assertion_matrix.ps1'),
            '-GodotExe', $godotFullPath,
            '-ManifestPath', $manifestPath,
            '-OutputRoot', $assertionOutputRoot
        ) `
        -WorkingDirectory $projectRoot `
        -LogDirectory $commandLogsRoot `
        -TimeoutSeconds 7200
    Assert-CommandSucceeded -Command $assertionCommand
    $assertionSummaryPath = Join-Path $assertionOutputRoot 'summary.json'
    $assertionSummary = Read-JsonFile -Path $assertionSummaryPath -Label 'Fresh assertion matrix summary'
    Assert-AssertionMatrixSummary `
        -Summary $assertionSummary `
        -Manifest $manifest `
        -ManifestPath $manifestPath `
        -ExpectedOutputRoot $assertionOutputRoot `
        -ExpectedGodotExe $godotFullPath `
        -Command $assertionCommand

    $saveKillOutputRoot = Join-Path $qaRoot 'save-os-kill'
    $saveKillCommand = Invoke-CapturedCommand `
        -Id 'save_os_kill' `
        -Executable $pwshExe `
        -Arguments @(
            '-NoProfile', '-File', (Join-Path $PSScriptRoot 'run_save_os_kill_qa.ps1'),
            '-GodotExe', $godotFullPath,
            '-OutputRoot', $saveKillOutputRoot
        ) `
        -WorkingDirectory $projectRoot `
        -LogDirectory $commandLogsRoot `
        -TimeoutSeconds 1800
    Assert-CommandSucceeded -Command $saveKillCommand
    $saveKillSummaryPath = Join-Path $saveKillOutputRoot 'summary.json'
    $saveKillSummary = Read-JsonFile -Path $saveKillSummaryPath -Label 'Fresh OS-kill summary'
    Assert-SaveOsKillSummary `
        -Summary $saveKillSummary `
        -ExpectedOutputRoot $saveKillOutputRoot `
        -ExpectedGodotExe $godotFullPath `
        -ExpectedGodotVersion $godotVersion `
        -Command $saveKillCommand

    # Godot 4.7 verbose editor shutdown emits an engine-only orphan StringName
    # diagnostic on this Windows host. The non-verbose import performs the same
    # complete import and keeps the fail-closed product log contract meaningful
    # instead of whitelisting a leak signature.
    $importGodotLog = Join-Path $godotLogsRoot 'import.godot.log'
    $importCommand = Invoke-CapturedCommand `
        -Id 'godot_import' `
        -Executable $godotFullPath `
        -Arguments @('--headless', '--path', $projectRoot, '--import', '--log-file', $importGodotLog) `
        -WorkingDirectory $projectRoot `
        -LogDirectory $commandLogsRoot `
        -TimeoutSeconds 900 `
        -Environment $engineEnvironment
    Assert-CommandSucceeded -Command $importCommand
    $importAssessment = Get-LogAssessment -Paths @($importCommand.stdout_path, $importCommand.stderr_path, $importGodotLog)
    if (-not $importAssessment.product_clean) {
        throw 'Godot import emitted product diagnostics or leak signatures.'
    }

    New-Item -ItemType Directory -Path $windowsStaging, $linuxStaging | Out-Null
    $windowsExe = Join-Path $windowsStaging 'MayorSimulator.exe'
    $linuxExe = Join-Path $linuxStaging 'MayorSimulator.x86_64'
    $windowsExportGodotLog = Join-Path $godotLogsRoot 'windows-export.godot.log'
    $windowsExportCommand = Invoke-CapturedCommand `
        -Id 'windows_export' `
        -Executable $godotFullPath `
        -Arguments @('--headless', '--path', $projectRoot, '--export-release', 'Windows Desktop', $windowsExe, '--log-file', $windowsExportGodotLog) `
        -WorkingDirectory $projectRoot `
        -LogDirectory $commandLogsRoot `
        -TimeoutSeconds 1800 `
        -Environment $engineEnvironment
    Assert-CommandSucceeded -Command $windowsExportCommand
    $windowsExportAssessment = Get-LogAssessment -Paths @($windowsExportCommand.stdout_path, $windowsExportCommand.stderr_path, $windowsExportGodotLog)
    if (-not $windowsExportAssessment.product_clean) {
        throw 'Windows export emitted product diagnostics or leak signatures.'
    }

    $linuxExportGodotLog = Join-Path $godotLogsRoot 'linux-export.godot.log'
    $linuxExportCommand = Invoke-CapturedCommand `
        -Id 'linux_export' `
        -Executable $godotFullPath `
        -Arguments @('--headless', '--path', $projectRoot, '--export-release', 'Linux', $linuxExe, '--log-file', $linuxExportGodotLog) `
        -WorkingDirectory $projectRoot `
        -LogDirectory $commandLogsRoot `
        -TimeoutSeconds 1800 `
        -Environment $engineEnvironment
    Assert-CommandSucceeded -Command $linuxExportCommand
    $linuxExportAssessment = Get-LogAssessment -Paths @($linuxExportCommand.stdout_path, $linuxExportCommand.stderr_path, $linuxExportGodotLog)
    if (-not $linuxExportAssessment.product_clean) {
        throw 'Linux export emitted product diagnostics or leak signatures.'
    }

    foreach ($documentName in @('RELEASE_README.txt', 'THIRD_PARTY_NOTICES.md', 'GODOT_COPYRIGHT.txt')) {
        foreach ($directory in @($windowsStaging, $linuxStaging)) {
            Copy-Item -LiteralPath (Join-Path $projectRoot $documentName) -Destination (Join-Path $directory $documentName)
        }
    }
    $exportContract = Assert-ExportStaging -WindowsDirectory $windowsStaging -LinuxDirectory $linuxStaging

    $smokeGodotLog = Join-Path $godotLogsRoot 'windows-smoke.godot.log'
    $smokeCommand = Invoke-CapturedCommand `
        -Id 'windows_smoke' `
        -Executable $windowsExe `
        -Arguments @('--headless', '--log-file', $smokeGodotLog, '--', '--qa-release-smoke-frames=120') `
        -WorkingDirectory $windowsStaging `
        -LogDirectory $commandLogsRoot `
        -TimeoutSeconds 120 `
        -Environment $smokeEnvironment
    Assert-CommandSucceeded -Command $smokeCommand
    $requiredSmokeMarkers = @('QA_RELEASE_SMOKE_ARMED frames=120', 'QA_RELEASE_SMOKE_COMPLETED')
    $smokeStdoutLines = @([IO.File]::ReadAllLines($smokeCommand.stdout_path, [Text.Encoding]::UTF8))
    $smokeStdoutText = [IO.File]::ReadAllText($smokeCommand.stdout_path, [Text.Encoding]::UTF8)
    $smokeStderrText = [IO.File]::ReadAllText($smokeCommand.stderr_path, [Text.Encoding]::UTF8)
    $smokeGodotLines = @([IO.File]::ReadAllLines($smokeGodotLog, [Text.Encoding]::UTF8))
    $smokeGodotText = [IO.File]::ReadAllText($smokeGodotLog, [Text.Encoding]::UTF8)
    $markerIndexes = [System.Collections.Generic.List[int]]::new()
    $godotLogMarkerIndexes = [System.Collections.Generic.List[int]]::new()
    foreach ($marker in $requiredSmokeMarkers) {
        $matches = @($smokeStdoutLines | Where-Object { $_ -ceq $marker })
        if ($matches.Count -ne 1 -or [regex]::Matches($smokeStdoutText, [regex]::Escape($marker)).Count -ne 1) {
            throw "Windows product smoke stdout must contain exactly one exact marker: $marker"
        }
        $markerIndex = [Array]::IndexOf([string[]]$smokeStdoutLines, $marker)
        $markerIndexes.Add($markerIndex)
        $godotMatches = @($smokeGodotLines | Where-Object { $_ -ceq $marker })
        if ($godotMatches.Count -ne 1 -or [regex]::Matches($smokeGodotText, [regex]::Escape($marker)).Count -ne 1) {
            throw "Windows product smoke Godot log must contain exactly one exact marker: $marker"
        }
        $godotLogMarkerIndexes.Add([Array]::IndexOf([string[]]$smokeGodotLines, $marker))
        if ($smokeStderrText.IndexOf($marker, [StringComparison]::Ordinal) -ge 0) {
            throw "Windows product smoke marker appeared in stderr: $marker"
        }
    }
    if ($markerIndexes[0] -ge $markerIndexes[1]) {
        throw 'Windows product smoke stdout markers appeared out of order.'
    }
    if ($godotLogMarkerIndexes[0] -ge $godotLogMarkerIndexes[1]) {
        throw 'Windows product smoke Godot-log markers appeared out of order.'
    }
    $smokeAssessment = Get-LogAssessment -Paths @($smokeCommand.stdout_path, $smokeCommand.stderr_path, $smokeGodotLog)
    if (-not $smokeAssessment.product_clean -or
        [int]$smokeAssessment.product_diagnostic_count -ne 0 -or
        [int]$smokeAssessment.leak_signature_count -ne 0) {
        throw 'Windows product smoke emitted product diagnostics or leak signatures.'
    }

    $packageDirectory = Join-Path $outputFullPath 'packages'
    $packageCommand = Invoke-CapturedCommand `
        -Id 'package_release' `
        -Executable $pwshExe `
        -Arguments @(
            '-NoProfile', '-File', (Join-Path $PSScriptRoot 'package_release.ps1'),
            '-Version', $Version,
            '-OutputDirectory', $packageDirectory,
            '-WindowsStagingDirectory', $windowsStaging,
            '-LinuxStagingDirectory', $linuxStaging
        ) `
        -WorkingDirectory $projectRoot `
        -LogDirectory $commandLogsRoot `
        -TimeoutSeconds 900
    Assert-CommandSucceeded -Command $packageCommand
    $packageStdout = [IO.File]::ReadAllText($packageCommand.stdout_path, [Text.Encoding]::UTF8)
    if ($packageStdout.IndexOf('PACKAGE_OK', [StringComparison]::Ordinal) -lt 0) {
        throw 'Package command succeeded without the PACKAGE_OK publication marker.'
    }
    $packageContract = Assert-PackageDirectory -Directory $packageDirectory -ReleaseVersion $Version

    $godotExecutableFinalHash = (Get-FileHash -LiteralPath $godotFullPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $templatesArchiveFinalHash = (Get-FileHash -LiteralPath $templatesFullPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($godotExecutableFinalHash -cne $godotExecutableInitialHash) {
        throw 'Godot executable changed during the single-run acceptance.'
    }
    if ($templatesArchiveFinalHash -cne $templatesArchiveHash -or
        $templatesArchiveFinalHash -cne $OFFICIAL_GODOT_47_TEMPLATES_SHA256) {
        throw 'Official export templates archive changed during the single-run acceptance.'
    }
    $postRunTemplateContract = Assert-InstalledTemplatesMatchManifest -Directory $templateInstallDirectory -Manifest $templateManifest

    $sourceEnd = Get-MayorSourceFingerprint -ProjectRoot $projectRoot
    Assert-FingerprintEqual -Expected $sourceStart -Actual $sourceEnd -Label 'Post-command'
    $sourceEndManifestPath = Join-Path $outputFullPath 'source-fingerprint-end.json'
    Write-JsonUtf8 -Value $sourceEnd -Path $sourceEndManifestPath -Depth 8

    $sourcePublish = Get-MayorSourceFingerprint -ProjectRoot $projectRoot
    Assert-FingerprintEqual -Expected $sourceStart -Actual $sourcePublish -Label 'Pre-publication'
    $sourcePublishManifestPath = Join-Path $outputFullPath 'source-fingerprint-publication.json'
    Write-JsonUtf8 -Value $sourcePublish -Path $sourcePublishManifestPath -Depth 8

    $commandEvidence = [System.Collections.Generic.List[object]]::new()
    foreach ($command in $commandRecords) {
        $commandEvidence.Add([pscustomobject][ordered]@{
            id = $command.id
            executable = $command.executable
            arguments = @($command.arguments)
            working_directory = $command.working_directory
            environment_overrides = $command.environment_overrides
            started = $command.started
            started_at_utc = $command.started_at_utc
            finished_at_utc = $command.finished_at_utc
            duration_seconds = $command.duration_seconds
            timeout_seconds = $command.timeout_seconds
            timed_out = $command.timed_out
            exit_code = $command.exit_code
            output_capture_complete = $command.output_capture_complete
            capture_error = $command.capture_error
            stdout = Get-FileEvidence -Path $command.stdout_path -Label "$($command.id) stdout log"
            stderr = Get-FileEvidence -Path $command.stderr_path -Label "$($command.id) stderr log"
        })
    }

    $stagedFiles = [ordered]@{
        windows_executable = Get-FileEvidence -Path $windowsExe -Label 'Windows staged executable'
        windows_pck = Get-FileEvidence -Path (Join-Path $windowsStaging 'MayorSimulator.pck') -Label 'Windows staged PCK'
        windows_release_readme = Get-FileEvidence -Path (Join-Path $windowsStaging 'RELEASE_README.txt')
        windows_third_party_notices = Get-FileEvidence -Path (Join-Path $windowsStaging 'THIRD_PARTY_NOTICES.md')
        windows_godot_copyright = Get-FileEvidence -Path (Join-Path $windowsStaging 'GODOT_COPYRIGHT.txt')
        linux_executable = Get-FileEvidence -Path $linuxExe -Label 'Linux staged executable'
        linux_pck = Get-FileEvidence -Path (Join-Path $linuxStaging 'MayorSimulator.pck') -Label 'Linux staged PCK'
        linux_release_readme = Get-FileEvidence -Path (Join-Path $linuxStaging 'RELEASE_README.txt')
        linux_third_party_notices = Get-FileEvidence -Path (Join-Path $linuxStaging 'THIRD_PARTY_NOTICES.md')
        linux_godot_copyright = Get-FileEvidence -Path (Join-Path $linuxStaging 'GODOT_COPYRIGHT.txt')
    }
    $evidence = [ordered]@{
        schema_version = 3
        suite = 'mayor-simulator-single-run-release-acceptance'
        status = 'PASS'
        generated_at_utc = [DateTimeOffset]::UtcNow.ToString('o')
        release_version = $Version
        output_root = [IO.Path]::GetRelativePath($projectRoot, $outputFullPath).Replace('\', '/')
        source = [ordered]@{
            scope = 'all file types under assets, data, scenes, scripts, systems, tests, tools, ui, and .github/workflows; fixed project/export/README/legal/release files; conservative root asset and .gitignore inputs'
            file_count = [int]$sourceStart.file_count
            total_bytes = [long]$sourceStart.total_bytes
            fingerprint_sha256 = [string]$sourceStart.fingerprint_sha256
            start_manifest = Get-FileEvidence -Path $sourceStartManifestPath
            end_manifest = Get-FileEvidence -Path $sourceEndManifestPath
            publication_manifest = Get-FileEvidence -Path $sourcePublishManifestPath
            start_end_exact_match = $true
            publication_guard_expected_sha256 = [string]$sourceStart.fingerprint_sha256
        }
        engine = [ordered]@{
            version = $godotVersion
            executable = Get-FileEvidence -Path $godotFullPath -Label 'Godot executable'
            executable_start_end_sha256_match = $true
            powershell_version = $PSVersionTable.PSVersion.ToString()
            powershell_executable = Get-FileEvidence -Path $pwshExe -Label 'PowerShell executable'
            isolated_appdata_root = $exportAppDataFullPath
        }
        export_templates = [ordered]@{
            official_archive_sha256 = $OFFICIAL_GODOT_47_TEMPLATES_SHA256
            source_archive = Get-FileEvidence -Path $templatesFullPath -Label 'Official export templates archive'
            clean_install_directory = $templateInstallDirectory
            installed_file_count = [int]$templateManifest.file_count
            installed_fingerprint_sha256 = [string]$templateManifest.fingerprint_sha256
            archive_to_installed_stream_hash_match = $true
            post_run_installed_tree_exact_match = $postRunTemplateContract.exact_match
            installed_manifest = Get-FileEvidence -Path $templateManifestPath
            windows_release_template = Get-FileEvidence -Path (Join-Path $templateInstallDirectory 'windows_release_x86_64.exe')
            linux_release_template = Get-FileEvidence -Path (Join-Path $templateInstallDirectory 'linux_release.x86_64')
        }
        commands = @($commandEvidence)
        qa = [ordered]@{
            assertion_matrix = [ordered]@{
                manifest = Get-FileEvidence -Path $manifestPath
                summary = Get-FileEvidence -Path $assertionSummaryPath
                selected_test_count = [int]$assertionSummary.selected_test_count
                product_clean_count = [int]$assertionSummary.product_clean_count
                failed_count = [int]$assertionSummary.failed_count
            }
            save_os_kill = [ordered]@{
                summary = Get-FileEvidence -Path $saveKillSummaryPath
                required_phases = $requiredSaveKillPhases
                passed_count = [int]$saveKillSummary.passed_count
                failed_count = [int]$saveKillSummary.failed_count
                forced_termination_count = [int]$saveKillSummary.forced_termination_count
                semantic_check_total = [int]$saveKillSummary.semantic_check_total
                all_processes_stopped = $true
            }
        }
        godot_logs = [ordered]@{
            import = Get-FileEvidence -Path $importGodotLog
            windows_export = Get-FileEvidence -Path $windowsExportGodotLog
            linux_export = Get-FileEvidence -Path $linuxExportGodotLog
            windows_smoke = Get-FileEvidence -Path $smokeGodotLog
        }
        log_assessments = [ordered]@{
            import = $importAssessment
            windows_export = $windowsExportAssessment
            linux_export = $linuxExportAssessment
            windows_smoke = $smokeAssessment
        }
        exports = [ordered]@{
            pck_byte_identical = $exportContract.pck_byte_identical
            pck_bytes = $exportContract.pck_bytes
            pck_sha256 = $exportContract.pck_sha256
            exact_staging_contract = 'five regular files per platform'
            files = $stagedFiles
        }
        windows_product_smoke = [ordered]@{
            required_exact_stdout_markers = $requiredSmokeMarkers
            exact_stdout_marker_count_each = 1
            stdout_markers_in_order = $true
            exact_godot_log_marker_count_each = 1
            godot_log_markers_in_order = $true
            marker_in_stderr = $false
            exit_code = [int]$smokeCommand.exit_code
            product_diagnostic_count = [int]$smokeAssessment.product_diagnostic_count
            leak_signature_count = [int]$smokeAssessment.leak_signature_count
            environment_warning_count = [int]$smokeAssessment.environment_warning_count
        }
        packages = [ordered]@{
            windows_archive = Get-FileEvidence -Path $packageContract.windows_archive
            linux_archive = Get-FileEvidence -Path $packageContract.linux_archive
            sha256sums = Get-FileEvidence -Path $packageContract.checksums
        }
        canonical_release_documents = [ordered]@{
            release_readme = Get-FileEvidence -Path (Join-Path $projectRoot 'RELEASE_README.txt')
            third_party_notices = Get-FileEvidence -Path (Join-Path $projectRoot 'THIRD_PARTY_NOTICES.md')
            godot_copyright = Get-FileEvidence -Path (Join-Path $projectRoot 'GODOT_COPYRIGHT.txt')
        }
        limitations = @(
            'The Windows exported product was smoke-tested in this run; the Linux executable was exported and packaged but not executed on Windows.',
            'A real Linux runner or CI job must execute the Linux smoke test.',
            'Windows binaries and archives are unsigned.',
            'Background-material redistribution rights and the project-level LICENSE remain release blockers; this package is Internal Alpha only.'
        )
    }

    if ((Test-Path -LiteralPath $evidencePartialPath) -or (Test-Path -LiteralPath $evidenceFinalPath)) {
        throw 'Release evidence publication path unexpectedly appeared during the run.'
    }
    $evidenceJson = $evidence | ConvertTo-Json -Depth 24
    $evidenceStream = [IO.File]::Open($evidencePartialPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $evidenceBytes = [Text.UTF8Encoding]::new($false).GetBytes($evidenceJson + [Environment]::NewLine)
        $evidenceStream.Write($evidenceBytes, 0, $evidenceBytes.Length)
        $evidenceStream.Flush($true)
    }
    finally {
        $evidenceStream.Dispose()
    }

    # Last possible source check: a mismatch leaves only logs and removes the
    # partial JSON, never a success-named evidence file.
    $publicationGuard = Get-MayorSourceFingerprint -ProjectRoot $projectRoot
    Assert-FingerprintEqual -Expected $sourceStart -Actual $publicationGuard -Label 'Final publication guard'
    Move-Item -LiteralPath $evidencePartialPath -Destination $evidenceFinalPath
    $published = $true
    Write-Output "RELEASE_EVIDENCE_OK path=$evidenceFinalPath source_files=$($sourceStart.file_count) tests=$($manifestTests.Count) os_kill_phases=$($requiredSaveKillPhases.Count)"
}
finally {
    if (-not $published -and
        (Test-Path -LiteralPath $evidencePartialPath -PathType Leaf) -and
        (Test-MayorPathInside -Candidate $evidencePartialPath -Parent $outputFullPath) -and
        (Split-Path -Leaf $evidencePartialPath) -ceq 'release-evidence.json.partial') {
        Remove-Item -LiteralPath $evidencePartialPath -Force -ErrorAction SilentlyContinue
    }
}
