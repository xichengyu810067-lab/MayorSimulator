[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$outputDirectory = Join-Path $projectRoot "docs\project-organization"
$jsonOutputPath = Join-Path $outputDirectory "RUNTIME_ASSET_LEDGER.json"
$markdownOutputPath = Join-Path $outputDirectory "RUNTIME_ASSET_LEDGER.md"
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Stop-LedgerGeneration {
	param([Parameter(Mandatory = $true)][string]$Message)
	throw "Runtime asset ledger validation failed: $Message"
}

function Get-ProjectPath {
	param([Parameter(Mandatory = $true)][string]$RelativePath)
	$normalized = $RelativePath.Replace("/", [System.IO.Path]::DirectorySeparatorChar)
	$fullPath = [System.IO.Path]::GetFullPath((Join-Path $projectRoot $normalized))
	$rootPrefix = $projectRoot.TrimEnd("\", "/") + [System.IO.Path]::DirectorySeparatorChar
	if (-not $fullPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
		Stop-LedgerGeneration "path escapes project root: $RelativePath"
	}
	return $fullPath
}

function Get-ResPathFile {
	param([Parameter(Mandatory = $true)][string]$ResPath)
	if (-not $ResPath.StartsWith("res://", [System.StringComparison]::Ordinal)) {
		Stop-LedgerGeneration "not a res:// path: $ResPath"
	}
	return Get-ProjectPath $ResPath.Substring(6)
}

function Read-ProjectText {
	param([Parameter(Mandatory = $true)][string]$RelativePath)
	$fullPath = Get-ProjectPath $RelativePath
	if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
		Stop-LedgerGeneration "required evidence file is missing: $RelativePath"
	}
	return [System.IO.File]::ReadAllText($fullPath)
}

function Get-RegexValues {
	param(
		[Parameter(Mandatory = $true)][string]$Text,
		[Parameter(Mandatory = $true)][string]$Pattern,
		[string]$GroupName = "value"
	)
	$values = foreach ($match in [System.Text.RegularExpressions.Regex]::Matches($Text, $Pattern)) {
		$match.Groups[$GroupName].Value
	}
	return @($values | Sort-Object -Unique)
}

function Assert-Count {
	param(
		[Parameter(Mandatory = $true)][object[]]$Values,
		[Parameter(Mandatory = $true)][int]$Expected,
		[Parameter(Mandatory = $true)][string]$Label
	)
	if ($Values.Count -ne $Expected) {
		Stop-LedgerGeneration "$Label count mismatch: expected=$Expected actual=$($Values.Count)"
	}
}

function Assert-SameStringSet {
	param(
		[Parameter(Mandatory = $true)][object[]]$Actual,
		[Parameter(Mandatory = $true)][object[]]$Expected,
		[Parameter(Mandatory = $true)][string]$Label
	)
	$actualSet = @($Actual | ForEach-Object { [string]$_ } | Sort-Object -Unique)
	$expectedSet = @($Expected | ForEach-Object { [string]$_ } | Sort-Object -Unique)
	$missing = @($expectedSet | Where-Object { $actualSet -notcontains $_ })
	$extra = @($actualSet | Where-Object { $expectedSet -notcontains $_ })
	if ($missing.Count -gt 0 -or $extra.Count -gt 0) {
		Stop-LedgerGeneration "$Label coverage mismatch: missing=[$($missing -join ', ')] extra=[$($extra -join ', ')]"
	}
}

function Convert-FileToResPath {
	param([Parameter(Mandatory = $true)][System.IO.FileInfo]$File)
	$relative = $File.FullName.Substring($projectRoot.Length).TrimStart("\", "/").Replace("\", "/")
	return "res://$relative"
}

$expectedCategoryCounts = [ordered]@{
	audio = 6
	npc_portrait = 8
	npc_walk_sheet = 8
	ui_icon = 37
	tutorial = 1
	background = 1
}

$audioReferencePath = "scripts/audio/audio_director.gd"
$npcReferencePath = "scripts/world/npc_actor.gd"
$iconReferencePath = "ui/theme/ui_icon_catalog.gd"
$buildingVisualReferencePath = "data/catalogs/building_visuals.gd"
$buildingCatalogReferencePath = "data/catalogs/buildings.gd"
$tutorialReferencePath = "ui/tutorial/tutorial_story_overlay.gd"
$backgroundReferencePath = "scripts/world/city_backdrop.gd"
$startScreenReferencePath = "ui/shell/start_screen.gd"

$audioText = Read-ProjectText $audioReferencePath
$npcText = Read-ProjectText $npcReferencePath
$iconText = Read-ProjectText $iconReferencePath
$buildingVisualText = Read-ProjectText $buildingVisualReferencePath
$buildingCatalogText = Read-ProjectText $buildingCatalogReferencePath
$tutorialText = Read-ProjectText $tutorialReferencePath
$backgroundText = Read-ProjectText $backgroundReferencePath
$startScreenText = Read-ProjectText $startScreenReferencePath

# Audio: the runtime preload registry must exactly cover the six delivered WAVs.
$audioPaths = @(Get-RegexValues $audioText 'preload\("(?<value>res://assets/audio/storybook_v1/[^"\r\n]+\.wav)"\)')
Assert-Count $audioPaths $expectedCategoryCounts.audio "audio runtime registry"
$audioDirectory = Get-ProjectPath "assets/audio/storybook_v1"
$deliveredAudioPaths = @(
	Get-ChildItem -LiteralPath $audioDirectory -File -Filter "*.wav" |
		ForEach-Object { Convert-FileToResPath $_ }
)
Assert-SameStringSet $audioPaths $deliveredAudioPaths "audio runtime registry versus delivery directory"

# NPC portraits: direct preloads must match every output in the canonical portrait pipeline record.
$portraitPaths = @(Get-RegexValues $npcText 'preload\("(?<value>res://assets/images/characters/npc/npc-[^/"\r\n]+\.png)"\)')
Assert-Count $portraitPaths $expectedCategoryCounts.npc_portrait "NPC portrait runtime registry"
$portraitMetadataPath = "assets/images/characters/npc/pipeline-meta.json"
$portraitMetadata = (Read-ProjectText $portraitMetadataPath) | ConvertFrom-Json
$portraitMetadataOutputs = @($portraitMetadata.assets | ForEach-Object { "res://assets/images/characters/npc/$($_.output)" })
Assert-Count $portraitMetadataOutputs $expectedCategoryCounts.npc_portrait "NPC portrait pipeline outputs"
Assert-SameStringSet $portraitPaths $portraitMetadataOutputs "NPC portrait runtime registry versus pipeline outputs"
$portraitRoleByPath = @{}
foreach ($record in $portraitMetadata.assets) {
	$output = [string]$record.output
	$role = [string]$record.role
	if ([string]::IsNullOrWhiteSpace($output) -or [string]::IsNullOrWhiteSpace($role)) {
		Stop-LedgerGeneration "NPC portrait pipeline output or role is blank"
	}
	$portraitRoleByPath["res://assets/images/characters/npc/$output"] = $role
}

# NPC walk sheets: preload references and the public ATLAS_PATHS registry must agree.
$walkPaths = @(Get-RegexValues $npcText '(?<value>res://assets/images/characters/npc/walk/[^/"\r\n]+/sheet-transparent\.png)')
Assert-Count $walkPaths $expectedCategoryCounts.npc_walk_sheet "NPC walk runtime references"
$atlasBlockMatch = [System.Text.RegularExpressions.Regex]::Match(
	$npcText,
	'(?s)const ATLAS_PATHS := \{(?<body>.*?)\r?\n\}'
)
if (-not $atlasBlockMatch.Success) {
	Stop-LedgerGeneration "NPC ATLAS_PATHS registry was not found"
}
$atlasPaths = @(Get-RegexValues $atlasBlockMatch.Groups["body"].Value '"(?<value>res://assets/images/characters/npc/walk/[^"\r\n]+/sheet-transparent\.png)"')
Assert-Count $atlasPaths $expectedCategoryCounts.npc_walk_sheet "NPC ATLAS_PATHS registry"
Assert-SameStringSet $walkPaths $atlasPaths "NPC walk preload references versus ATLAS_PATHS"
foreach ($walkPath in $walkPaths) {
	$walkMatch = [System.Text.RegularExpressions.Regex]::Match($walkPath, '/walk/(?<role>[^/]+)/sheet-transparent\.png$')
	if (-not $walkMatch.Success) {
		Stop-LedgerGeneration "cannot derive NPC walk role from $walkPath"
	}
	$walkMetadataResPath = "res://assets/images/characters/npc/walk/$($walkMatch.Groups['role'].Value)/pipeline-meta.json"
	$walkMetadataFile = Get-ResPathFile $walkMetadataResPath
	if (-not (Test-Path -LiteralPath $walkMetadataFile -PathType Leaf)) {
		Stop-LedgerGeneration "active NPC walk sheet lacks pipeline metadata: $walkPath"
	}
}

# UI icons: resolve the fallback symbol inside the canonical filename array, then compare with delivery files.
$iconRootMatch = [System.Text.RegularExpressions.Regex]::Match($iconText, 'const ROOT_PATH := "(?<value>res://[^"\r\n]+)"')
$iconFallbackMatch = [System.Text.RegularExpressions.Regex]::Match($iconText, 'const FALLBACK_FILENAME := "(?<value>[^"\r\n]+\.png)"')
$iconArrayMatch = [System.Text.RegularExpressions.Regex]::Match(
	$iconText,
	'(?s)const CANONICAL_FILENAMES: PackedStringArray = \[(?<body>.*?)\r?\n\]'
)
if (-not $iconRootMatch.Success -or -not $iconFallbackMatch.Success -or -not $iconArrayMatch.Success) {
	Stop-LedgerGeneration "UI icon canonical registry structure is incomplete"
}
$iconRoot = $iconRootMatch.Groups["value"].Value
$iconFilenames = @(Get-RegexValues $iconArrayMatch.Groups["body"].Value '"(?<value>[^"\r\n]+\.png)"')
if ($iconArrayMatch.Groups["body"].Value -notmatch '\bFALLBACK_FILENAME\b') {
	Stop-LedgerGeneration "UI icon canonical registry does not include FALLBACK_FILENAME"
}
$iconFilenames = @($iconFilenames + $iconFallbackMatch.Groups["value"].Value | Sort-Object -Unique)
Assert-Count $iconFilenames $expectedCategoryCounts.ui_icon "UI icon canonical filenames"
$iconPaths = @($iconFilenames | ForEach-Object { "$iconRoot/$_" })
$iconDirectory = Get-ResPathFile $iconRoot
$deliveredIconPaths = @(
	Get-ChildItem -LiteralPath $iconDirectory -File -Filter "*.png" |
		ForEach-Object { Convert-FileToResPath $_ }
)
Assert-SameStringSet $iconPaths $deliveredIconPaths "UI icon canonical registry versus delivery directory"

# Buildings: visual names must cover the gameplay catalog, ids must match folders, and all clean files must be registered.
$buildingRootMatch = [System.Text.RegularExpressions.Regex]::Match($buildingVisualText, 'const ROOT := "(?<value>res://[^"\r\n]+)"')
if (-not $buildingRootMatch.Success) {
	Stop-LedgerGeneration "building visual ROOT was not found"
}
$buildingRoot = $buildingRootMatch.Groups["value"].Value
$buildingMatches = [System.Text.RegularExpressions.Regex]::Matches(
	$buildingVisualText,
	'(?m)^\s*"(?<display>[^"]+)":\s*\{"id":\s*"(?<id>[^"]+)",.*?"asset":\s*ROOT \+ "(?<suffix>/[^"]+/clean\.png)"\},\s*$'
)
$buildingRecords = @(
	foreach ($match in $buildingMatches) {
		$display = $match.Groups["display"].Value
		$id = $match.Groups["id"].Value
		$suffix = $match.Groups["suffix"].Value
		$folder = $suffix.Split("/", [System.StringSplitOptions]::RemoveEmptyEntries)[0]
		if ($folder -ne $id) {
			Stop-LedgerGeneration "building visual id/path mismatch: id=$id suffix=$suffix"
		}
		[pscustomobject][ordered]@{
			display = $display
			id = $id
			path = "$buildingRoot$suffix"
		}
	}
)
$expectedCategoryCounts.building_clean = $buildingRecords.Count
$expectedTotal = [int](($expectedCategoryCounts.Values | Measure-Object -Sum).Sum)
$buildingIds = @($buildingRecords | ForEach-Object { $_.id })
if (@($buildingIds | Sort-Object -Unique).Count -ne $buildingIds.Count) {
	Stop-LedgerGeneration "building visual registry contains duplicate ids"
}
$buildingCatalogNames = @(Get-RegexValues $buildingCatalogText '(?m)^\t\t"(?<value>[^"]+)":\s*\{\s*$')
$buildingVisualNames = @($buildingRecords | ForEach-Object { $_.display })
Assert-Count $buildingCatalogNames $expectedCategoryCounts.building_clean "building gameplay catalog"
Assert-SameStringSet $buildingVisualNames $buildingCatalogNames "building visuals versus gameplay catalog"
$buildingPaths = @($buildingRecords | ForEach-Object { $_.path })
$buildingDirectory = Get-ResPathFile $buildingRoot
$deliveredBuildingPaths = @(
	Get-ChildItem -LiteralPath $buildingDirectory -File -Filter "clean.png" -Recurse |
		ForEach-Object { Convert-FileToResPath $_ }
)
Assert-SameStringSet $buildingPaths $deliveredBuildingPaths "building visual registry versus clean delivery files"

# The tutorial and city background are explicit runtime references, not directory scans.
$tutorialPaths = @(Get-RegexValues $tutorialText 'preload\("(?<value>res://assets/images/tutorial/[^"\r\n]+\.png)"\)')
Assert-Count $tutorialPaths $expectedCategoryCounts.tutorial "tutorial background runtime reference"
$cityBackdropPaths = @(Get-RegexValues $backgroundText 'load\("(?<value>res://assets/images/world/backgrounds/[^"\r\n]+\.png)"\)')
$startScreenBackgroundPaths = @(Get-RegexValues $startScreenText 'const BACKGROUND_PATH := "(?<value>res://assets/images/world/backgrounds/[^"\r\n]+\.png)"')
Assert-Count $cityBackdropPaths $expectedCategoryCounts.background "city backdrop runtime reference"
Assert-Count $startScreenBackgroundPaths $expectedCategoryCounts.background "start screen background runtime reference"
Assert-SameStringSet $cityBackdropPaths $startScreenBackgroundPaths "city backdrop versus start screen background"
$backgroundPaths = $cityBackdropPaths

$rootLicenseFiles = @(
	Get-ChildItem -LiteralPath $projectRoot -File |
		Where-Object { $_.Name -match '^(?i:LICENSE(?:\..*)?|COPYING(?:\..*)?)$' }
)
if ($rootLicenseFiles.Count -ne 0) {
	Stop-LedgerGeneration "project license assertion is stale; root license files now exist: $($rootLicenseFiles.Name -join ', ')"
}

$script:ledgerAssets = [System.Collections.Generic.List[object]]::new()
$standardRightsStatus = "provenance_documented_project_distribution_license_unselected"
$backgroundRightsStatus = "source_rights_unresolved_project_distribution_license_unselected"

function Add-LedgerAsset {
	param(
		[Parameter(Mandatory = $true)][string]$Category,
		[Parameter(Mandatory = $true)][string]$Purpose,
		[Parameter(Mandatory = $true)][string]$ResPath,
		[Parameter(Mandatory = $true)][string]$RuntimeReferenceEvidencePath,
		[Parameter(Mandatory = $true)][string]$ProvenanceEvidencePath,
		[Parameter(Mandatory = $true)][string]$ProvenanceStatus,
		[Parameter(Mandatory = $true)][string]$RightsLicenseStatus
	)
	$assetFile = Get-ResPathFile $ResPath
	if (-not (Test-Path -LiteralPath $assetFile -PathType Leaf)) {
		Stop-LedgerGeneration "runtime asset is missing: $ResPath"
	}
	$runtimeEvidenceFile = Get-ResPathFile $RuntimeReferenceEvidencePath
	$provenanceEvidenceFile = Get-ResPathFile $ProvenanceEvidencePath
	if (-not (Test-Path -LiteralPath $runtimeEvidenceFile -PathType Leaf)) {
		Stop-LedgerGeneration "runtime reference evidence is missing: $RuntimeReferenceEvidencePath"
	}
	if (-not (Test-Path -LiteralPath $provenanceEvidenceFile -PathType Leaf)) {
		Stop-LedgerGeneration "provenance evidence is missing: $ProvenanceEvidencePath"
	}
	$fileInfo = Get-Item -LiteralPath $assetFile
	if ($fileInfo.Length -le 0) {
		Stop-LedgerGeneration "runtime asset is empty: $ResPath"
	}
	$sha256 = (Get-FileHash -LiteralPath $assetFile -Algorithm SHA256).Hash.ToUpperInvariant()
	if ($sha256 -notmatch '^[0-9A-F]{64}$') {
		Stop-LedgerGeneration "invalid SHA-256 for $ResPath"
	}
	$script:ledgerAssets.Add([pscustomobject][ordered]@{
		category = $Category
		purpose = $Purpose
		res_path = $ResPath
		bytes = [int64]$fileInfo.Length
		sha256 = $sha256
		runtime_reference_evidence_path = $RuntimeReferenceEvidencePath
		provenance_evidence_path = $ProvenanceEvidencePath
		provenance_status = $ProvenanceStatus
		rights_license_status = $RightsLicenseStatus
	}) | Out-Null
}

$audioPurposes = @{
	"mayors-dawn-loop.wav" = "runtime background music loop"
	"ui-click.wav" = "runtime generic UI click cue"
	"page-turn.wav" = "runtime tutorial page-turn cue"
	"success-chime.wav" = "runtime success cue"
	"construction-complete.wav" = "runtime construction-complete cue"
	"warning-soft.wav" = "runtime non-destructive warning cue"
}
foreach ($path in ($audioPaths | Sort-Object)) {
	$filename = $path.Substring($path.LastIndexOf("/") + 1)
	if (-not $audioPurposes.ContainsKey($filename)) {
		Stop-LedgerGeneration "audio purpose is not declared for $filename"
	}
	Add-LedgerAsset "audio" $audioPurposes[$filename] $path "res://$audioReferencePath" `
		"res://assets/audio/storybook_v1/README.md" "documented_original_deterministic_pcm_synthesis" $standardRightsStatus
}

foreach ($path in ($portraitPaths | Sort-Object)) {
	$role = [string]$portraitRoleByPath[$path]
	if ([string]::IsNullOrWhiteSpace($role)) {
		Stop-LedgerGeneration "NPC portrait purpose role is missing for $path"
	}
	Add-LedgerAsset "npc_portrait" "runtime NPC portrait texture for role $role" $path "res://$npcReferencePath" `
		"res://$portraitMetadataPath" "local_source_sheet_and_processing_record_present_generator_identity_not_declared_in_record" $standardRightsStatus
}

foreach ($path in ($walkPaths | Sort-Object)) {
	$walkMatch = [System.Text.RegularExpressions.Regex]::Match($path, '/walk/(?<role>[^/]+)/sheet-transparent\.png$')
	$role = $walkMatch.Groups["role"].Value
	$metadataPath = "res://assets/images/characters/npc/walk/$role/pipeline-meta.json"
	Add-LedgerAsset "npc_walk_sheet" "runtime directional NPC walk sheet for role $role" $path "res://$npcReferencePath" `
		$metadataPath "local_processing_record_present_generator_identity_not_declared_in_record" $standardRightsStatus
}

foreach ($path in ($iconPaths | Sort-Object)) {
	$filename = $path.Substring($path.LastIndexOf("/") + 1)
	$concept = [System.IO.Path]::GetFileNameWithoutExtension($filename)
	Add-LedgerAsset "ui_icon" "canonical runtime UI icon for concept $concept" $path "res://$iconReferencePath" `
		"res://assets/images/ui/icons/storybook_v2/README.md" "documented_openai_imagegen_and_local_postprocessing" $standardRightsStatus
}

foreach ($record in ($buildingRecords | Sort-Object id)) {
	$metadataPath = "res://assets/images/world/buildings/storybook_v1/$($record.id)/pipeline-meta.json"
	$provenanceStatus = "documented_openai_imagegen_and_local_postprocessing_with_item_pipeline_record"
	$provenanceEvidencePath = "res://assets/images/world/buildings/storybook_v1/ART_PROVENANCE.md"
	if (-not (Test-Path -LiteralPath (Get-ResPathFile $metadataPath) -PathType Leaf)) {
		if ($record.id -ne "train_station") {
			Stop-LedgerGeneration "building pipeline metadata is missing: $metadataPath"
		}
		$provenanceStatus = "item_pipeline_record_missing_not_covered_by_26_item_provenance_record"
		$provenanceEvidencePath = "res://docs/release/train_station_asset_provenance_blocker.md"
	}
	Add-LedgerAsset "building_clean" "canonical buildable visual for $($record.id) ($($record.display))" $record.path `
		"res://$buildingVisualReferencePath" $provenanceEvidencePath `
		$provenanceStatus $standardRightsStatus
}

foreach ($path in $tutorialPaths) {
	Add-LedgerAsset "tutorial" "runtime tutorial story overlay background" $path "res://$tutorialReferencePath" `
		"res://assets/images/tutorial/story-intro-background.manifest.json" "manifest_declares_openai_imagegen" $standardRightsStatus
}

foreach ($path in $backgroundPaths) {
	Add-LedgerAsset "background" "runtime city map and start-screen background" $path "res://$backgroundReferencePath" `
		"res://THIRD_PARTY_NOTICES.md" "migrated_existing_asset_original_author_and_license_unresolved" $backgroundRightsStatus
}

$categoryOrder = @("audio", "npc_portrait", "npc_walk_sheet", "ui_icon", "building_clean", "tutorial", "background")
$categoryRank = @{}
for ($index = 0; $index -lt $categoryOrder.Count; $index += 1) {
	$categoryRank[$categoryOrder[$index]] = $index
}
$sortedAssets = @(
	$script:ledgerAssets |
		Sort-Object @{ Expression = { $categoryRank[$_.category] } }, @{ Expression = { $_.res_path } }
)
Assert-Count $sortedAssets $expectedTotal "ledger"

$duplicatePathGroups = @($sortedAssets | Group-Object res_path | Where-Object { $_.Count -gt 1 })
if ($duplicatePathGroups.Count -ne 0) {
	Stop-LedgerGeneration "duplicate res paths exist: $($duplicatePathGroups.Name -join ', ')"
}
$duplicateHashGroups = @($sortedAssets | Group-Object sha256 | Where-Object { $_.Count -gt 1 })
if ($duplicateHashGroups.Count -ne 0) {
	Stop-LedgerGeneration "duplicate content hashes exist: $($duplicateHashGroups.Name -join ', ')"
}

$requiredStringFields = @(
	"category",
	"purpose",
	"res_path",
	"sha256",
	"runtime_reference_evidence_path",
	"provenance_evidence_path",
	"provenance_status",
	"rights_license_status"
)
$blankMetadataFields = [System.Collections.Generic.List[string]]::new()
foreach ($asset in $sortedAssets) {
	foreach ($field in $requiredStringFields) {
		$value = [string]$asset.$field
		if ([string]::IsNullOrWhiteSpace($value)) {
			$blankMetadataFields.Add("$($asset.res_path):$field") | Out-Null
		}
	}
}
if ($blankMetadataFields.Count -ne 0) {
	Stop-LedgerGeneration "blank metadata fields exist: $($blankMetadataFields -join ', ')"
}

$actualCategoryCounts = [ordered]@{}
foreach ($category in $categoryOrder) {
	$count = @($sortedAssets | Where-Object { $_.category -eq $category }).Count
	$actualCategoryCounts[$category] = $count
	if ($count -ne [int]$expectedCategoryCounts[$category]) {
		Stop-LedgerGeneration "category count mismatch: category=$category expected=$($expectedCategoryCounts[$category]) actual=$count"
	}
}

$unresolvedRightsAssets = @($sortedAssets | Where-Object { $_.rights_license_status -eq $backgroundRightsStatus })
Assert-Count $unresolvedRightsAssets 1 "unresolved source-rights assets"
if ($unresolvedRightsAssets[0].res_path -ne "res://assets/images/world/backgrounds/city-map-background.png") {
	Stop-LedgerGeneration "the sole unresolved source-rights asset is not the canonical city background"
}

$ledger = [pscustomobject][ordered]@{
	schema_version = 1
	ledger_scope = "active_runtime_media_from_canonical_registries_and_explicit_runtime_references"
	determinism_policy = "fixed_order_no_dynamic_timestamp_content_hashes_from_current_files"
	project_distribution_license_status = "unselected_no_root_license_file"
	provenance_is_not_distribution_license = $true
	unresolved_source_rights_asset_count = 1
	unresolved_source_rights_res_path = "res://assets/images/world/backgrounds/city-map-background.png"
	expected_total = $expectedTotal
	actual_total = $sortedAssets.Count
	expected_category_counts = $expectedCategoryCounts
	actual_category_counts = $actualCategoryCounts
	validation = [pscustomobject][ordered]@{
		all_files_exist = $true
		all_sha256_present = $true
		duplicate_res_paths = 0
		duplicate_content_hashes = 0
		registry_coverage_complete = $true
		expected_counts_match = $true
		blank_required_metadata_fields = 0
	}
	assets = $sortedAssets
}

if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
	Stop-LedgerGeneration "output directory is missing: docs/project-organization"
}
$json = $ledger | ConvertTo-Json -Depth 8
$json = $json.Replace("`r`n", "`n") + "`n"
[System.IO.File]::WriteAllText($jsonOutputPath, $json, $utf8NoBom)

# Parse the emitted artifact before producing its companion summary.
$emittedLedger = [System.IO.File]::ReadAllText($jsonOutputPath) | ConvertFrom-Json
if ([int]$emittedLedger.actual_total -ne $expectedTotal -or $emittedLedger.assets.Count -ne $expectedTotal) {
	Stop-LedgerGeneration "emitted JSON did not round-trip with $expectedTotal assets"
}
$jsonSha256 = (Get-FileHash -LiteralPath $jsonOutputPath -Algorithm SHA256).Hash.ToUpperInvariant()

$markdownLines = [System.Collections.Generic.List[string]]::new()
$markdownLines.Add("# Runtime Asset Ledger") | Out-Null
$markdownLines.Add("") | Out-Null
$markdownLines.Add("本台帳只列入 canonical registry 或明確 runtime reference 可證明正在使用的 $expectedTotal 項媒體；原始圖、預覽、封存檔、測試截圖與 `.import` 不列入。") | Out-Null
$markdownLines.Add("") | Out-Null
$markdownLines.Add("- JSON SHA-256：``$jsonSha256``") | Out-Null
$markdownLines.Add("- 驗證：存在、SHA-256、重複路徑 0、重複內容雜湊 0、registry coverage、預期數量與必填 metadata 均通過。") | Out-Null
$markdownLines.Add("- 唯一未解來源權利資產：``res://assets/images/world/backgrounds/city-map-background.png``；作者與公開散布授權尚未建立。") | Out-Null
$markdownLines.Add("- 專案自身 ``LICENSE`` 尚未選定；``THIRD_PARTY_NOTICES.md`` 不是專案授權。") | Out-Null
$markdownLines.Add("- 生成／處理 provenance 只能說明素材如何產生，不等於授予或選定專案散布 license。") | Out-Null
$markdownLines.Add("") | Out-Null
$markdownLines.Add("| 類別 | 預期 | 實際 |") | Out-Null
$markdownLines.Add("|---|---:|---:|") | Out-Null
foreach ($category in $categoryOrder) {
	$markdownLines.Add("| ``$category`` | $($expectedCategoryCounts[$category]) | $($actualCategoryCounts[$category]) |") | Out-Null
}
$markdownLines.Add("| **合計** | **$expectedTotal** | **$($sortedAssets.Count)** |") | Out-Null
$markdownLines.Add("") | Out-Null
$markdownLines.Add("重建：``pwsh -NoProfile -File tools/generate_runtime_asset_ledger.ps1``。產生器不啟動 Godot、不修改 runtime 行為或素材。") | Out-Null
$markdown = ($markdownLines -join "`n") + "`n"
[System.IO.File]::WriteAllText($markdownOutputPath, $markdown, $utf8NoBom)

$markdownSha256 = (Get-FileHash -LiteralPath $markdownOutputPath -Algorithm SHA256).Hash.ToUpperInvariant()
$countSummary = @($categoryOrder | ForEach-Object { "$_=$($actualCategoryCounts[$_])" }) -join ","
Write-Output "RUNTIME_ASSET_LEDGER_OK total=$($sortedAssets.Count) $countSummary"
Write-Output "json_sha256=$jsonSha256"
Write-Output "markdown_sha256=$markdownSha256"
Write-Output "blank_required_metadata_fields=$($blankMetadataFields.Count)"
