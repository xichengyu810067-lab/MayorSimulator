#requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$GodotExe,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$OutputRoot,
    [ValidateRange(30, 900)][int]$TimeoutSeconds = 300
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'source_fingerprint.ps1')

function Get-PngRecord {
    param([Parameter(Mandatory)][string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.PSIsContainer -or $item.Length -le 0) { throw "Invalid PNG evidence: $Path" }
    $bytes = [IO.File]::ReadAllBytes($item.FullName)
    $magic = [byte[]](137,80,78,71,13,10,26,10)
    if ($bytes.Length -lt 24) { throw "PNG header invalid: $Path" }
    for ($index = 0; $index -lt $magic.Length; $index++) {
        if ($bytes[$index] -ne $magic[$index]) { throw "PNG header invalid: $Path" }
    }
    $width = [int64]$bytes[16] * 16777216 + [int64]$bytes[17] * 65536 + [int64]$bytes[18] * 256 + $bytes[19]
    $height = [int64]$bytes[20] * 16777216 + [int64]$bytes[21] * 65536 + [int64]$bytes[22] * 256 + $bytes[23]
    if ($width -le 0 -or $height -le 0) { throw "PNG dimensions invalid: $Path" }
    [ordered]@{ path=[IO.Path]::GetFileName($item.FullName); bytes=[long]$item.Length; width=$width; height=$height; sha256=(Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
}

$GodotExe = (Resolve-Path -LiteralPath $GodotExe).Path
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
if (-not (Test-MayorPathInside -Candidate $OutputRoot -Parent $projectRoot) -or $OutputRoot.Equals($projectRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'OutputRoot must be a child path inside the project workspace.' }
if (Test-Path -LiteralPath $OutputRoot) { throw 'OutputRoot already exists; evidence is append-only.' }
$pre = Get-MayorSourceFingerprint -ProjectRoot $projectRoot
New-Item -ItemType Directory -Path $OutputRoot -ErrorAction Stop | Out-Null
$appData = Join-Path $OutputRoot 'appdata'; $localAppData = Join-Path $OutputRoot 'localappdata'
New-Item -ItemType Directory -Path $appData,$localAppData -ErrorAction Stop | Out-Null
$stdoutPath = Join-Path $OutputRoot 'stdout.log'; $stderrPath = Join-Path $OutputRoot 'stderr.log'; $godotLogPath = Join-Path $OutputRoot 'godot.log'
$stdoutText = ''; $stderrText = ''; $completed = $false; $exitCode = -1; $launchError = $null
try {
    $info = [Diagnostics.ProcessStartInfo]::new(); $info.FileName = $GodotExe; $info.UseShellExecute = $false; $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true; $info.CreateNoWindow = $false
    $info.Environment['APPDATA'] = $appData; $info.Environment['LOCALAPPDATA'] = $localAppData
    foreach ($argument in @('--verbose','--path',$projectRoot,'--script','res://tests/manual/map_zoom_pan_visible_acceptance.gd','--log-file',$godotLogPath,'--',"--map-zoom-pan-output-dir=$OutputRoot")) { $info.ArgumentList.Add([string]$argument) }
    $process = [Diagnostics.Process]::new(); $process.StartInfo = $info
    if (-not $process.Start()) { throw 'Godot process did not start.' }
    $outTask = $process.StandardOutput.ReadToEndAsync(); $errTask = $process.StandardError.ReadToEndAsync()
    $completed = $process.WaitForExit($TimeoutSeconds * 1000)
    if (-not $completed) { try { $process.Kill($true) } catch {}; $null = $process.WaitForExit(30000) }
    if (-not $process.HasExited) { throw 'Godot process tree did not exit after timeout cleanup.' }
    if (-not $outTask.Wait(15000) -or -not $errTask.Wait(15000)) { throw 'Godot output pipes did not close after process exit.' }
    $stdoutText = $outTask.GetAwaiter().GetResult(); $stderrText = $errTask.GetAwaiter().GetResult(); $exitCode = if ($completed) { [int]$process.ExitCode } else { -1 }
}
catch { $launchError = $_.Exception.Message }
finally { if ($null -ne $process) { $process.Dispose() }; [IO.File]::WriteAllText($stdoutPath,$stdoutText,[Text.UTF8Encoding]::new($false)); [IO.File]::WriteAllText($stderrPath,$stderrText,[Text.UTF8Encoding]::new($false)) }

$failures = [Collections.Generic.List[string]]::new(); if ($launchError) { $failures.Add("Godot launch failed: $launchError") }; if (-not $completed) { $failures.Add('Godot did not complete before timeout.') }; if ($exitCode -ne 0) { $failures.Add("Godot exit code was $exitCode.") }
$godotLogText = if (Test-Path -LiteralPath $godotLogPath) { Get-Content -LiteralPath $godotLogPath -Raw } else { '' }
$plainLog = ($stdoutText + "`n" + $stderrText + "`n" + $godotLogText) -replace "`e\[[0-?]*[ -/]*[@-~]",''
$diagnostics = @([regex]::Matches($plainLog,'(?im)^(?:SCRIPT ERROR|ERROR|WARNING):[^\r\n]*') | ForEach-Object { $_.Value.Trim() })
foreach ($pattern in @('Leaked instance:','ObjectDB instances? (?:was|were) leaked at exit','resources? still in use at exit','Resource still in use:','Orphan StringName:','unclaimed string names at exit')) { if ([regex]::IsMatch($plainLog,$pattern,[Text.RegularExpressions.RegexOptions]::IgnoreCase)) { $diagnostics += "leak signature: $pattern" } }
if ($diagnostics.Count) { $failures.Add("Product diagnostics found: $($diagnostics -join ' | ')") }
$marker = 'NATIVE_MAP_ZOOM_PAN_VISIBLE_ACCEPTANCE_PASSED'; if ([regex]::Matches($stdoutText,"(?m)^$([regex]::Escape($marker)).*$" ).Count -ne 1) { $failures.Add('Expected success marker exactly once.') }
$states = @('before','zoomed','panned'); $captures = @(); $hashes = [Collections.Generic.HashSet[string]]::new()
try { foreach ($state in $states) { $record = Get-PngRecord (Join-Path $OutputRoot "native-map-$state.png"); $captures += $record; if (-not $hashes.Add([string]$record.sha256)) { throw "Duplicate capture hash for $state" } } } catch { $failures.Add($_.Exception.Message) }
$result = $null; try { $result = Get-Content -LiteralPath (Join-Path $OutputRoot 'map-zoom-pan-result.json') -Raw | ConvertFrom-Json; if ($result.status -cne 'PASS' -or $result.capture_surface_kind -cne 'native_fullscreen_root' -or $result.captures.Count -ne 3 -or $result.dragging_after_release -ne $false -or [double]$result.zoom.after -le [double]$result.zoom.before -or ($result.pan_offset.before -join ',') -eq ($result.pan_offset.after -join ',')) { throw 'Result contract is incomplete, not native-root, or did not prove zoom/pan/release.' } } catch { $failures.Add("Result validation failed: $($_.Exception.Message)") }
$post = $null; try { $post = Get-MayorSourceFingerprint -ProjectRoot $projectRoot; if ($post.fingerprint_sha256 -ne $pre.fingerprint_sha256) { throw 'Source fingerprint changed during acceptance.' } } catch { $failures.Add("Post-run source fingerprint failed: $($_.Exception.Message)") }
$summary = [ordered]@{ schema_version=1; suite='mayor-simulator-native-map-zoom-pan-visible-acceptance'; status=if($failures.Count){'FAIL'}else{'PASS'}; process=@{completed=$completed;exit_code=$exitCode;timeout_seconds=$TimeoutSeconds;cleanup_confirmed=$completed}; success_marker=$marker; captures=$captures; result=$result; diagnostics=$diagnostics; source=@{pre_fingerprint_sha256=$pre.fingerprint_sha256;post_fingerprint_sha256=if($post){$post.fingerprint_sha256}else{$null};unchanged=($null -ne $post -and $post.fingerprint_sha256 -eq $pre.fingerprint_sha256)}; failures=@($failures) }
[IO.File]::WriteAllText((Join-Path $OutputRoot 'summary.json'),($summary | ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
if ($failures.Count) { $failures | ForEach-Object { Write-Error $_ }; exit 1 }
Write-Output "Native map zoom/pan visible acceptance passed: states=3 output=$OutputRoot"
