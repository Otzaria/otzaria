# Prints <version>[.<hotfix>]+<run_number>, independently of the source ref.
# Mirrors release_tag.sh. Hotfix 0 keeps the 3-part tag that older clients can parse.
param(
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][string]$Ref,
    [Parameter(Mandatory = $true)][string]$RunNumber
)
$ErrorActionPreference = 'Stop'

$data = Get-Content -Raw -Path (Join-Path $PSScriptRoot 'version.json') | ConvertFrom-Json
if ($data.version -ne $Version) {
    throw "version.json has '$($data.version)' but pubspec.yaml has '$Version'"
}
$hotfixText = if ($null -ne $data.hotfix) { "$($data.hotfix)" } else { '0' }
if ($hotfixText -notmatch '^(0|[1-9][0-9]?)$') {
    throw "hotfix must be an integer 0-99 (got '$hotfixText')"
}

$base = if ([int]$hotfixText -gt 0) { "$Version.$hotfixText" } else { $Version }
"$base+$RunNumber"
