[CmdletBinding()]
param(
    [string]$GodotExe = 'C:\Users\USER\Tools\Godot\Godot_v4.7-stable_win64_console.exe',
    [string]$ManifestPath = '',
    [string]$OutputRoot = '',
    [string[]]$TestId = @(),
    [int]$DefaultTimeoutSeconds = 120
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Some hosted Windows shells expose both `Path` and `PATH` in the inherited
# environment block.  Start-Process compares environment keys
# case-insensitively and throws before Godot starts, so normalize the duplicate
# aliases once in this process while preserving the effective search path.
$effectivePath = $env:Path
$pathKeys = @(
    [System.Environment]::GetEnvironmentVariables().Keys |
        Where-Object { $_.ToString().ToLowerInvariant() -eq 'path' }
)
if ($pathKeys.Count -gt 1) {
    foreach ($pathKey in $pathKeys) {
        [System.Environment]::SetEnvironmentVariable(
            [string]$pathKey,
            $null,
            [System.EnvironmentVariableTarget]::Process
        )
    }
    [System.Environment]::SetEnvironmentVariable(
        'Path',
        $effectivePath,
        [System.EnvironmentVariableTarget]::Process
    )
}

$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
    $ManifestPath = Join-Path $projectRoot 'tests\assertion_matrix.json'
}
$ManifestPath = (Resolve-Path -LiteralPath $ManifestPath).Path

if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) {
    throw "Godot executable not found: $GodotExe"
}
if ($DefaultTimeoutSeconds -lt 1) {
    throw 'DefaultTimeoutSeconds must be at least 1.'
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
if ([int]$manifest.schema_version -ne 1) {
    throw "Unsupported assertion manifest schema_version: $($manifest.schema_version)"
}
if ([string]::IsNullOrWhiteSpace([string]$manifest.name)) {
    throw 'Assertion manifest name must not be empty.'
}
if ($null -ne $manifest.PSObject.Properties['expected_test_count']) {
    throw 'Assertion manifest count must be derived from the live tests array; remove expected_test_count.'
}
$allTests = @($manifest.tests)
if ($allTests.Count -lt 1) {
    throw 'Assertion manifest tests array must not be empty.'
}

$seenIds = @{}
$seenScripts = @{}
foreach ($test in $allTests) {
    $id = [string]$test.id
    $script = [string]$test.script
    $successPattern = [string]$test.success_pattern
    if ($id -notmatch '^[a-z0-9_]+$') {
        throw "Unsafe or empty test id: $id"
    }
    if ($seenIds.ContainsKey($id)) {
        throw "Duplicate test id: $id"
    }
    if ($script -notmatch '^res://tests/.+\.gd$' -or $script.Contains('..')) {
        throw "Test script must stay under res://tests: $script"
    }
    if ($seenScripts.ContainsKey($script)) {
        throw "Duplicate test script: $script"
    }
    if ([string]::IsNullOrWhiteSpace($successPattern)) {
        throw "Missing success pattern for test: $id"
    }

    $relativeScript = $script.Substring('res://'.Length).Replace('/', '\')
    $absoluteScript = Join-Path $projectRoot $relativeScript
    if (-not (Test-Path -LiteralPath $absoluteScript -PathType Leaf)) {
        throw "Test script not found: $absoluteScript"
    }
    $seenIds[$id] = $true
    $seenScripts[$script] = $true
}

$selectedTests = $allTests
if ($TestId.Count -gt 0) {
    $requestedIds = @{}
    foreach ($requestedId in $TestId) {
        if (-not $seenIds.ContainsKey($requestedId)) {
            throw "Unknown test id: $requestedId"
        }
        $requestedIds[$requestedId] = $true
    }
    $selectedTests = @($allTests | Where-Object { $requestedIds.ContainsKey([string]$_.id) })
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $OutputRoot = Join-Path $projectRoot ".tmp\assertion-matrix\$timestamp"
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$ansiPattern = "`e\[[0-?]*[ -/]*[@-~]"
$certificatePattern = '(?m)^ERROR: Failed to read the root certificate store\.\r?\n\s*at: get_system_ca_certificates \(platform/windows/os_windows\.cpp:\d+\)\r?\n?'
$leakPatterns = @(
    'Leaked instance:',
    'ObjectDB instances? (?:was|were) leaked at exit',
    'resources? still in use at exit',
    'Resource still in use:',
    'Orphan StringName:',
    'unclaimed string names at exit'
)

function Read-Utf8FileWithRetry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LiteralPath,
        [int]$MaxAttempts = 20,
        [int]$DelayMilliseconds = 100
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            return [IO.File]::ReadAllText($LiteralPath, [Text.Encoding]::UTF8)
        }
        catch [IO.IOException] {
            if ($attempt -eq $MaxAttempts) {
                throw
            }
            Start-Sleep -Milliseconds $DelayMilliseconds
        }
    }
}

$hadAppData = Test-Path Env:APPDATA
$hadLocalAppData = Test-Path Env:LOCALAPPDATA
$originalAppData = $env:APPDATA
$originalLocalAppData = $env:LOCALAPPDATA
$results = [System.Collections.Generic.List[object]]::new()
$startedAt = Get-Date

try {
    for ($index = 0; $index -lt $selectedTests.Count; $index++) {
        $test = $selectedTests[$index]
        $id = [string]$test.id
        $caseNumber = $index + 1
        $caseRoot = Join-Path $OutputRoot ('{0:D2}-{1}' -f $caseNumber, $id)
        $appDataRoot = Join-Path $caseRoot 'appdata'
        $localAppDataRoot = Join-Path $caseRoot 'localappdata'
        New-Item -ItemType Directory -Force -Path $appDataRoot, $localAppDataRoot | Out-Null

        $stdoutPath = Join-Path $caseRoot 'stdout.log'
        $stderrPath = Join-Path $caseRoot 'stderr.log'
        $godotLogPath = Join-Path $caseRoot 'godot.log'
        $env:APPDATA = $appDataRoot
        $env:LOCALAPPDATA = $localAppDataRoot

        $timeoutSeconds = $DefaultTimeoutSeconds
        if ($null -ne $test.PSObject.Properties['timeout_seconds']) {
            $timeoutSeconds = [int]$test.timeout_seconds
        }
        $arguments = @(
            '--headless',
            '--verbose',
            '--path', ('"{0}"' -f $projectRoot),
            '--script', ('"{0}"' -f [string]$test.script),
            '--log-file', ('"{0}"' -f $godotLogPath)
        )

        Write-Output ('[{0}/{1}] RUN {2}' -f $caseNumber, $selectedTests.Count, $id)
        $caseStartedAt = Get-Date
        $process = $null
        $completed = $false
        $exitCode = -1
        try {
            $process = Start-Process -FilePath $GodotExe -ArgumentList $arguments -NoNewWindow -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
            $completed = $process.WaitForExit($timeoutSeconds * 1000)
            if (-not $completed) {
                if ($PSVersionTable.PSEdition -eq 'Core') {
                    $process.Kill($true)
                }
                else {
                    $process.Kill()
                }
            }
            # The parameterless overload also waits for asynchronous redirected
            # output to finish, so the log handles are safe to release and read.
            $process.WaitForExit()
            if ($completed) {
                $exitCode = [int]$process.ExitCode
            }
        }
        finally {
            if ($null -ne $process) {
                $process.Dispose()
            }
        }
        $durationSeconds = [Math]::Round(((Get-Date) - $caseStartedAt).TotalSeconds, 3)

        $logParts = [System.Collections.Generic.List[string]]::new()
        foreach ($logPath in @($stdoutPath, $stderrPath, $godotLogPath)) {
            if (Test-Path -LiteralPath $logPath -PathType Leaf) {
                $logParts.Add((Read-Utf8FileWithRetry -LiteralPath $logPath))
            }
        }
        $plainLog = [regex]::Replace(($logParts -join "`n"), $ansiPattern, '')
        $environmentWarningCount = [regex]::Matches($plainLog, $certificatePattern).Count
        $productLog = [regex]::Replace($plainLog, $certificatePattern, '')
        $reasons = [System.Collections.Generic.List[string]]::new()

        if (-not $completed) {
            $reasons.Add("timeout after $timeoutSeconds seconds")
        }
        elseif ($exitCode -ne 0) {
            $reasons.Add("Godot exit code $exitCode")
        }
        if ($plainLog.IndexOf([string]$test.success_pattern, [StringComparison]::Ordinal) -lt 0) {
            $reasons.Add('success marker missing')
        }

        foreach ($leakPattern in $leakPatterns) {
            if ([regex]::IsMatch($productLog, $leakPattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
                $reasons.Add("leak signature: $leakPattern")
            }
        }

        $diagnosticMatches = [regex]::Matches($productLog, '(?im)^(?:SCRIPT ERROR|ERROR|WARNING):[^\r\n]*')
        foreach ($diagnosticMatch in $diagnosticMatches) {
            $diagnostic = $diagnosticMatch.Value.Trim()
            if (-not $reasons.Contains($diagnostic)) {
                $reasons.Add($diagnostic)
            }
        }

        $passed = $reasons.Count -eq 0
        $status = if ($passed -and $environmentWarningCount -gt 0) {
            'PASS_WITH_ENVIRONMENT_WARNING'
        }
        elseif ($passed) {
            'PASS'
        }
        else {
            'FAIL'
        }
        $result = [pscustomobject]@{
            id = $id
            script = [string]$test.script
            status = $status
            product_clean = $passed
            exit_code = $exitCode
            duration_seconds = $durationSeconds
            environment_warning_count = $environmentWarningCount
            failure_reasons = @($reasons)
            output_directory = $caseRoot
        }
        $results.Add($result)
        Write-Output ('[{0}/{1}] {2} {3} ({4}s)' -f $caseNumber, $selectedTests.Count, $status, $id, $durationSeconds)
    }
}
finally {
    if ($hadAppData) {
        $env:APPDATA = $originalAppData
    }
    else {
        Remove-Item Env:APPDATA -ErrorAction SilentlyContinue
    }
    if ($hadLocalAppData) {
        $env:LOCALAPPDATA = $originalLocalAppData
    }
    else {
        Remove-Item Env:LOCALAPPDATA -ErrorAction SilentlyContinue
    }
}

$finishedAt = Get-Date
$passedCount = @($results | Where-Object { $_.product_clean }).Count
$failedCount = $results.Count - $passedCount
$environmentWarningTests = @($results | Where-Object { $_.environment_warning_count -gt 0 }).Count
$summary = [pscustomobject]@{
    matrix = [string]$manifest.name
    schema_version = [int]$manifest.schema_version
    manifest = $ManifestPath
    godot_executable = $GodotExe
    project_root = $projectRoot
    output_root = $OutputRoot
    started_at = $startedAt.ToString('o')
    finished_at = $finishedAt.ToString('o')
    duration_seconds = [Math]::Round(($finishedAt - $startedAt).TotalSeconds, 3)
    manifest_test_count = $allTests.Count
    selected_test_count = $selectedTests.Count
    product_clean_count = $passedCount
    failed_count = $failedCount
    environment_warning_test_count = $environmentWarningTests
    environment_warning = 'Godot could not read the Windows root certificate store; recorded separately and never removed from raw logs.'
    results = @($results)
}
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputRoot 'summary.json') -Encoding UTF8

$markdown = [System.Collections.Generic.List[string]]::new()
$markdown.Add('# Assertion matrix summary')
$markdown.Add('')
$markdown.Add("- Manifest tests: $($allTests.Count)")
$markdown.Add("- Selected tests: $($selectedTests.Count)")
$markdown.Add("- Product-clean: $passedCount")
$markdown.Add("- Failed: $failedCount")
$markdown.Add("- Root-certificate environment warning: $environmentWarningTests test(s)")
$markdown.Add("- Duration: $([Math]::Round(($finishedAt - $startedAt).TotalSeconds, 3)) seconds")
$markdown.Add('')
$markdown.Add('| Test | Status | Exit | Seconds | Environment warnings |')
$markdown.Add('|---|---:|---:|---:|---:|')
foreach ($result in $results) {
    $markdown.Add("| $($result.id) | $($result.status) | $($result.exit_code) | $($result.duration_seconds) | $($result.environment_warning_count) |")
    foreach ($reason in $result.failure_reasons) {
        $markdown.Add("|  | reason: $($reason.Replace('|', '\|')) |  |  |  |")
    }
}
$markdown | Set-Content -LiteralPath (Join-Path $OutputRoot 'SUMMARY.md') -Encoding UTF8

Write-Output ("Matrix complete: product-clean=$passedCount failed=$failedCount environment-warning-tests=$environmentWarningTests output=$OutputRoot")
if ($failedCount -gt 0) {
    exit 1
}
exit 0
