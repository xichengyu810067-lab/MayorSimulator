[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$GodotExe,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$PackPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$OutputPath,
    [ValidateRange(1, 600)][int]$TimeoutSeconds = 120,
    [switch]$KeepTemporaryRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-RegularFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label is missing: $Path"
    }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "$Label must not be a reparse point: $Path"
    }
    return $item
}

$godot = (Resolve-Path -LiteralPath $GodotExe -ErrorAction Stop).Path
$pack = (Assert-RegularFile -Path $PackPath -Label 'PCK input').FullName
$output = [IO.Path]::GetFullPath($OutputPath)
$outputParent = Split-Path -Parent $output
if ([string]::IsNullOrWhiteSpace($outputParent) -or -not (Test-Path -LiteralPath $outputParent -PathType Container)) {
    throw "Output parent is missing: $outputParent"
}
if (Test-Path -LiteralPath $output) {
    throw "OutputPath already exists: $output"
}

$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('mayor-pck-inventory-' + [guid]::NewGuid().ToString('N'))
$blankProjectRoot = Join-Path $temporaryRoot 'blank-project'
$scannerPath = Join-Path $temporaryRoot 'scanner.gd'
$stdoutPath = Join-Path $temporaryRoot 'stdout.log'
$stderrPath = Join-Path $temporaryRoot 'stderr.log'
$godotLogPath = Join-Path $temporaryRoot 'godot.log'
$sentinel = '__pck_inventory_source_sentinel__.txt'
$completed = $false
$exitCode = -1

try {
    New-Item -ItemType Directory -Path $blankProjectRoot -ErrorAction Stop | Out-Null
    $outputRelative = [IO.Path]::GetRelativePath($blankProjectRoot, $output)
    if ($outputRelative -eq '.' -or
        (-not [IO.Path]::IsPathRooted($outputRelative) -and
        -not ($outputRelative -eq '..' -or $outputRelative.StartsWith('..' + [IO.Path]::DirectorySeparatorChar) -or $outputRelative.StartsWith('..' + [IO.Path]::AltDirectorySeparatorChar)))) {
        throw 'OutputPath must stay outside the isolated scanner project root.'
    }
    [IO.File]::WriteAllText(
        (Join-Path $blankProjectRoot 'project.godot'),
        "[application]`nconfig/name=`"Pck Inventory`"`n",
        [Text.UTF8Encoding]::new($false)
    )
    [IO.File]::WriteAllText(
        (Join-Path $blankProjectRoot $sentinel),
        "The scanner must never enumerate this blank-project sentinel.`n",
        [Text.UTF8Encoding]::new($false)
    )
    $scanner = @'
extends SceneTree

const SUCCESS_PREFIX := "PCK_INVENTORY_OK"

func _initialize() -> void:
	var output_path := ""
	var sentinel := ""
	var isolation_root := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--pck-inventory-output="):
			output_path = argument.trim_prefix("--pck-inventory-output=")
		elif argument.begins_with("--pck-inventory-sentinel="):
			sentinel = argument.trim_prefix("--pck-inventory-sentinel=")
		elif argument.begins_with("--pck-inventory-isolation-root="):
			isolation_root = argument.trim_prefix("--pck-inventory-isolation-root=")
	if output_path.is_empty() or sentinel.is_empty() or isolation_root.is_empty():
		_fail("missing required scanner arguments")
		return
	for environment_name in ["APPDATA", "LOCALAPPDATA", "HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"]:
		if not _is_path_inside(OS.get_environment(environment_name), isolation_root):
			_fail("scanner environment is not isolated")
			return
	if not _is_path_inside(OS.get_user_data_dir(), isolation_root):
		_fail("Godot user data directory is not isolated")
		return
	var entries: Array[String] = []
	var traversal_error := _collect_directory("res://", entries)
	if not traversal_error.is_empty():
		_fail(traversal_error)
		return
	if entries.is_empty():
		_fail("pack inventory is empty")
		return
	entries.sort()
	if entries.has(sentinel):
		_fail("blank-project filesystem overlay detected")
		return
	var output_file := FileAccess.open(output_path, FileAccess.WRITE)
	if output_file == null:
		_fail("unable to write inventory")
		return
	output_file.store_string("\n".join(entries) + "\n")
	output_file.close()
	print("%s entries=%d" % [SUCCESS_PREFIX, entries.size()])
	quit(0)


func _collect_directory(directory_path: String, entries: Array[String]) -> String:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return "unable to open packed directory"
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		if name != "." and name != "..":
			var child_path := directory_path.path_join(name)
			if directory.current_is_dir():
				var nested_error := _collect_directory(child_path, entries)
				if not nested_error.is_empty():
					directory.list_dir_end()
					return nested_error
			else:
				entries.append(child_path.trim_prefix("res://"))
		name = directory.get_next()
	directory.list_dir_end()
	return ""


func _is_path_inside(candidate: String, parent: String) -> bool:
	if candidate.is_empty() or parent.is_empty():
		return false
	var normalized_candidate := candidate.replace("\\", "/").simplify_path().to_lower()
	var normalized_parent := parent.replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
	return normalized_candidate == normalized_parent or normalized_candidate.begins_with(normalized_parent + "/")


func _fail(reason: String) -> void:
	push_error("PCK inventory failed: %s" % reason)
	quit(1)
'@
    [IO.File]::WriteAllText($scannerPath, $scanner, [Text.UTF8Encoding]::new($false))

    $appData = Join-Path $temporaryRoot 'appdata'
    $localAppData = Join-Path $temporaryRoot 'localappdata'
    $homeDirectory = Join-Path $temporaryRoot 'home'
    $xdgDataHome = Join-Path $temporaryRoot 'xdg-data'
    $xdgConfigHome = Join-Path $temporaryRoot 'xdg-config'
    $xdgCacheHome = Join-Path $temporaryRoot 'xdg-cache'
    New-Item -ItemType Directory -Path $appData, $localAppData, $homeDirectory, $xdgDataHome, $xdgConfigHome, $xdgCacheHome -ErrorAction Stop | Out-Null
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $godot
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    $startInfo.WorkingDirectory = $blankProjectRoot
    $startInfo.Environment['APPDATA'] = $appData
    $startInfo.Environment['LOCALAPPDATA'] = $localAppData
    $startInfo.Environment['HOME'] = $homeDirectory
    $startInfo.Environment['XDG_DATA_HOME'] = $xdgDataHome
    $startInfo.Environment['XDG_CONFIG_HOME'] = $xdgConfigHome
    $startInfo.Environment['XDG_CACHE_HOME'] = $xdgCacheHome
    foreach ($argument in @(
        '--headless', '--path', $blankProjectRoot, '--main-pack', $pack,
        '--script', $scannerPath, '--log-file', $godotLogPath, '--',
        "--pck-inventory-output=$output", "--pck-inventory-sentinel=$sentinel",
        "--pck-inventory-isolation-root=$temporaryRoot"
    )) {
        $startInfo.ArgumentList.Add([string]$argument)
    }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $stdoutTask = $null
    $stderrTask = $null
    try {
        if (-not $process.Start()) {
            throw 'Unable to start Godot PCK inventory scanner.'
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $completed = $process.WaitForExit($TimeoutSeconds * 1000)
        if (-not $completed) {
            $process.Kill($true)
        }
        $process.WaitForExit()
        [IO.File]::WriteAllText($stdoutPath, $stdoutTask.GetAwaiter().GetResult(), [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText($stderrPath, $stderrTask.GetAwaiter().GetResult(), [Text.UTF8Encoding]::new($false))
        if ($completed) {
            $exitCode = $process.ExitCode
        }
    }
    finally {
        $process.Dispose()
    }

    if (-not $completed -or $exitCode -ne 0) {
        throw "PCK inventory scanner failed: completed=$completed exit_code=$exitCode"
    }
    $scannerMarkers = @([IO.File]::ReadAllLines($stdoutPath, [Text.UTF8Encoding]::new($false)) | Where-Object {
        $_ -match '^PCK_INVENTORY_OK entries=[1-9][0-9]*$'
    })
    if ($scannerMarkers.Count -ne 1) {
        throw 'PCK inventory scanner success marker is missing or ambiguous.'
    }
    if (-not (Test-Path -LiteralPath $output -PathType Leaf)) {
        throw 'PCK inventory scanner produced no inventory file.'
    }
    $entries = @([IO.File]::ReadAllLines($output, [Text.UTF8Encoding]::new($false)) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($entries.Count -eq 0) {
        throw 'PCK inventory is empty.'
    }
    for ($index = 0; $index -lt $entries.Count; $index++) {
        $entry = $entries[$index]
        if ([IO.Path]::IsPathRooted($entry) -or $entry.Contains('\\') -or $entry -eq '..' -or $entry.StartsWith('../')) {
            throw 'PCK inventory contains a non-relative path.'
        }
        if ($index -gt 0 -and [string]::CompareOrdinal($entries[$index - 1], $entry) -ge 0) {
            throw 'PCK inventory is not an ordinal-sorted unique path list.'
        }
    }
    $deniedPrefixes = @('sdk/', 'tests/', 'tools/', 'docs/', '.tmp/', '.agents/', '.codex/', '.git/')
    $denied = [System.Collections.Generic.List[string]]::new()
    $deniedCategories = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($path in $entries) {
        if ($path -ceq 'data/save_schema_authority_registry.json') {
            $denied.Add($path)
            $null = $deniedCategories.Add('data/save_schema_authority_registry.json')
            continue
        }
        foreach ($prefix in $deniedPrefixes) {
            if ($path.StartsWith($prefix, [StringComparison]::Ordinal)) {
                $denied.Add($path)
                $null = $deniedCategories.Add($prefix)
                break
            }
        }
    }
    if ($denied.Count -ne 0) {
        throw "PCK inventory denylist hit: categories=$(@($deniedCategories | Sort-Object) -join ',') count=$($denied.Count)"
    }
    $hash = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-Output "PCK_INVENTORY_OK entries=$($entries.Count) sha256=$hash"
}
finally {
    if ($KeepTemporaryRoot) {
        Write-Output "PCK_INVENTORY_TEMP_ROOT=$temporaryRoot"
    }
    elseif (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
