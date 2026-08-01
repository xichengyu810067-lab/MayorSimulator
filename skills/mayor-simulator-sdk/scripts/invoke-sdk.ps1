[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$SdkArguments
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$entrypoint = Join-Path $projectRoot 'sdk\mayor-sdk.ps1'
if (-not (Test-Path -LiteralPath $entrypoint -PathType Leaf)) {
    throw "Mayor Simulator SDK entrypoint was not found: $entrypoint"
}
& $entrypoint @SdkArguments
exit $LASTEXITCODE
