param(
    [Parameter(Mandatory = $true)]
    [string]$ManifestPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1) {
    throw "Unsupported manifest schema: $($manifest.schemaVersion)"
}

$archiveName = [string]$manifest.archive
if ([IO.Path]::GetFileName($archiveName) -ne $archiveName) {
    throw "Unsafe archive name: $archiveName"
}
if ([string]::IsNullOrWhiteSpace($archiveName) -or
    ([string]$manifest.sha256) -notmatch '^[0-9a-fA-F]{64}$') {
    throw 'Invalid archive metadata'
}
if (-not $manifest.parts -or $manifest.parts.Count -eq 0) {
    throw 'Manifest contains no parts'
}

$lines = @(
    "archive|$archiveName|$(([string]$manifest.sha256).ToLowerInvariant())"
)
foreach ($part in $manifest.parts) {
    $partName = [string]$part.name
    $partHash = ([string]$part.sha256).ToLowerInvariant()
    if ([IO.Path]::GetFileName($partName) -ne $partName) {
        throw "Unsafe part name: $partName"
    }
    if ([string]::IsNullOrWhiteSpace($partName) -or
        $partHash -notmatch '^[0-9a-f]{64}$' -or
        [int64]$part.size -le 0 -or
        [int64]$part.size -ge 2147483648) {
        throw "Invalid part metadata: $partName"
    }
    $lines += "part|$partName|$partHash"
}

[IO.File]::WriteAllLines(
    [IO.Path]::GetFullPath($OutputPath),
    $lines,
    [Text.UTF8Encoding]::new($false)
)
