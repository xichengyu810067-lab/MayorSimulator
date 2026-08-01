param(
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName Microsoft.VisualBasic

$sourceRoots = @('scripts', 'ui', 'data', 'systems')
$extensions = @('*.gd', '*.tscn', '*.json')
$sources = [System.Collections.Generic.HashSet[string]]::new()
# Source strings in the project are single-line quoted literals.  Excluding
# physical newlines prevents a closing quote on one declaration from being
# mistaken for the opening quote of a later Chinese literal/comment.
$quotedPattern = '"(?:[^"\\\r\n]|\\.)*[\p{IsCJKUnifiedIdeographs}](?:[^"\\\r\n]|\\.)*"'

foreach ($relativeRoot in $sourceRoots) {
    $root = Join-Path $ProjectRoot $relativeRoot
    foreach ($extension in $extensions) {
        foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File -Filter $extension) {
            if ($file.FullName.StartsWith((Join-Path $ProjectRoot 'data\localization'), [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }
            $raw = Get-Content -LiteralPath $file.FullName -Raw
            foreach ($match in [regex]::Matches($raw, $quotedPattern)) {
                try {
                    $decoded = $match.Value | ConvertFrom-Json
                    if (-not [string]::IsNullOrWhiteSpace($decoded)) {
                        [void]$sources.Add([string]$decoded)
                    }
                } catch {
                    Write-Warning "Skipped a non-JSON-compatible string in $($file.FullName): $($match.Value)"
                }
            }
        }
    }
}

$extraSources = @(
    '淨額較建議 %s',
    '收入 $%d｜%s',
    '收入 $%d｜%s｜%s',
    '有%s',
    '缺%s',
    '安全缺口',
    '單項收入缺口',
    '民意 -%d',
    '民意穩定',
    '第 %d 年　｜　%d 件待處理',
    '第 %d 日裁決　｜　案件嚴重度 %d / 100',
    '第 %d 日表決　｜　證據強度 %d / 100　｜　%s',
    '尚未提出辯護',
    '已提出：%s',
    '✓ %s',
    '耐久 %d｜%s',
    '不可客製',
    '建築',
    '行政違法審判',
    '市長',
    '彈劾質詢',
    '目前無待處理案件',
    '案件成立後即可選擇辯護策略。',
    '接受處理',
    '已列入處理',
    '%d 件有效陳情｜系統會自動更新',
    '正在設計：%s',
    '工  工程隊 %d / 20 可用  •  %d%%',
    '✓ 已收件｜審核中｜剩餘 %d 個遊戲日（約 %d 分鐘）',
    '審核中｜剩餘 %d 日',
    '✓ 審核通過｜請關閉視窗，回到地圖點擊空地開工。',
    '已核准｜等待開工',
    '! 審核未通過｜%s｜修改參數後可重新送審。',
    '修改後重新送審',
    '⌂ 已核准並施工中｜完工後可送審新版。',
    '施工中',
    '✓ 上一版已完工｜目前可以送審新版。',
    '送審新版藍圖',
    '尚未送審｜完成設計後按上方按鈕。',
    '送審藍圖',
    '%s　$%d\n%s　修 $%d/月',
    '%s\n%s\n%s',
    '%s  %s',
    '%s  %s  %s',
    '%s %s%d%s',
    '繁體中文',
    '简体中文',
    'English',
    '日本語',
    '한국어'
)
foreach ($extra in $extraSources) {
    [void]$sources.Add($extra)
}

$orderedSources = @($sources | Sort-Object)
$outputRoot = Join-Path $ProjectRoot 'data\localization'
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null

function Protect-Placeholders([string]$Text, [int]$SourceIndex) {
    $tokens = [System.Collections.Generic.List[object]]::new()
    $argumentCounter = [int[]]@(0)
    $protected = [regex]::Replace($Text, '%(?:\+|0\d+)?[sdf]|%%', {
        param($match)
        $token = "[[PH_${SourceIndex}_$($tokens.Count)]]"
        $isLiteral = $match.Value -eq '%%'
        $argumentIndex = -1
        if (-not $isLiteral) {
            $argumentIndex = $argumentCounter[0]
            $argumentCounter[0]++
        }
        $tokens.Add([pscustomobject]@{
            Token = $token
            Value = $match.Value
            Replacement = $match.Value
        })
        return $token
    })
    return [pscustomobject]@{ Text = $protected; Tokens = @($tokens) }
}

function Restore-Placeholders([string]$Text, $Tokens) {
    $restored = $Text
    foreach ($token in $Tokens) {
        $restored = [regex]::Replace(
            $restored,
            [regex]::Escape([string]$token.Token),
            [System.Text.RegularExpressions.MatchEvaluator]{ param($match) [string]$token.Replacement },
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
    }
    return $restored
}

function Convert-TargetPlaceholders([string]$Text) {
    return $Text
}

function Invoke-GoogleBatch([string]$TargetLanguage, $Batch) {
    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in $Batch) {
        $parts.Add("<<<L10N_$('{0:D6}' -f $entry.Index)>>>")
        $parts.Add([string]$entry.Protected.Text)
    }
    $payload = $parts -join "`n"
    $encoded = [uri]::EscapeDataString($payload)
    $uri = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=zh-TW&tl=$TargetLanguage&dt=t&q=$encoded"
    $response = $null
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            $response = (Invoke-WebRequest -UseBasicParsing -Uri $uri -TimeoutSec 45).Content | ConvertFrom-Json
            break
        } catch {
            if ($attempt -eq 3) { throw }
            Start-Sleep -Seconds $attempt
        }
    }
    $translatedPayload = (($response[0] | ForEach-Object { [string]$_[0] }) -join '')
    $matches = [regex]::Matches($translatedPayload, '(?s)<<<L10N_(\d{6})>>>\s*(.*?)(?=\n<<<L10N_\d{6}>>>|$)')
    $result = @{}
    foreach ($match in $matches) {
        $index = [int]$match.Groups[1].Value
        $result[$index] = $match.Groups[2].Value.Trim()
    }
    return $result
}

function Write-Catalog([string]$Locale, [string]$TargetLanguage) {
    $catalog = [ordered]@{}
    if ($Locale -eq 'zh_TW') {
        foreach ($source in $orderedSources) {
            $catalog[$source] = Convert-TargetPlaceholders $source
        }
    } elseif ($Locale -eq 'zh_CN') {
        foreach ($source in $orderedSources) {
			# Visual Basic's SimplifiedChinese conversion replaces the Unicode
			# checkmark with '?'. Protect this UI-status symbol while converting the
			# Chinese text so generated catalogs remain semantically intact.
			$protectedSource = $source.Replace('✓', '[[L10N_CHECKMARK]]').Replace('・', '[[L10N_MIDDOT]]')
            $converted = [Microsoft.VisualBasic.Strings]::StrConv(
				$protectedSource,
                [Microsoft.VisualBasic.VbStrConv]::SimplifiedChinese,
                2052
            )
			$converted = $converted.Replace('[[L10N_CHECKMARK]]', '✓').Replace('[[L10N_MIDDOT]]', '・')
            $catalog[$source] = Convert-TargetPlaceholders $converted
        }
    } else {
        $entries = [System.Collections.Generic.List[object]]::new()
        for ($index = 0; $index -lt $orderedSources.Count; $index++) {
            $entries.Add([pscustomobject]@{
                Index = $index
                Source = $orderedSources[$index]
                Protected = Protect-Placeholders $orderedSources[$index] $index
            })
        }
        $cursor = 0
        while ($cursor -lt $entries.Count) {
            $batch = [System.Collections.Generic.List[object]]::new()
            $length = 0
            while ($cursor -lt $entries.Count) {
                $candidate = $entries[$cursor]
                $candidateLength = ([string]$candidate.Protected.Text).Length + 30
                $candidateIsMultiline = ([string]$candidate.Protected.Text).Contains("`n")
                if ($batch.Count -gt 0 -and $length + $candidateLength -gt 2600) { break }
                if ($batch.Count -gt 0 -and $candidateIsMultiline) { break }
                $batch.Add($candidate)
                $length += $candidateLength
                $cursor++
                if ($candidateIsMultiline) { break }
            }
            $translated = Invoke-GoogleBatch $TargetLanguage @($batch)
            foreach ($entry in $batch) {
                if (-not $translated.ContainsKey($entry.Index)) {
                    throw "Missing translated entry $($entry.Index) for $Locale"
                }
                $value = Restore-Placeholders ([string]$translated[$entry.Index]) $entry.Protected.Tokens
                foreach ($token in $entry.Protected.Tokens) {
                    if (-not $value.Contains([string]$token.Replacement)) {
                        throw "Placeholder validation failed for $Locale source: $($entry.Source)`nTranslated: $value`nMissing: $($token.Token) => $($token.Replacement)"
                    }
                }
                $catalog[$entry.Source] = $value
            }
            Write-Host "$Locale translated $cursor / $($entries.Count)"
        }
    }
    $path = Join-Path $outputRoot "$Locale.json"
    $catalog | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $path -Encoding UTF8
    Write-Host "Wrote $path ($($catalog.Count) entries)"
}

Write-Catalog 'zh_TW' ''
Write-Catalog 'zh_CN' ''
Write-Catalog 'en' 'en'
Write-Catalog 'ja' 'ja'
Write-Catalog 'ko' 'ko'

$manifest = [ordered]@{
    schema_version = 1
    source_locale = 'zh_TW'
    locales = @('zh_TW', 'zh_CN', 'en', 'ja', 'ko')
    source_count = $orderedSources.Count
    generated_at = (Get-Date).ToString('o')
}
$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $outputRoot 'manifest.json') -Encoding UTF8
Write-Host "Localization generation completed. Sources=$($orderedSources.Count)"
