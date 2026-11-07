function Restore-PerfLockfileQuoting([string]$Path, [byte[]]$OriginalBytes) {
  $resolvedBytes = [IO.File]::ReadAllBytes($Path)
  $originalHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($OriginalBytes)).ToLowerInvariant()
  $resolvedHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($resolvedBytes)).ToLowerInvariant()
  $changed = $originalHash -cne $resolvedHash
  if ($changed) {
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    $pattern = '(?m)^(?<prefix>[ \t]+(?:ref|resolved-ref):[ \t]*)(?<quote>["'']?)(?<sha>[0-9a-fA-F]{40})\k<quote>(?<suffix>[ \t]*\r?)$'
    $before = [regex]::Replace($utf8.GetString($OriginalBytes), $pattern, '${prefix}${sha}${suffix}')
    $after = [regex]::Replace($utf8.GetString($resolvedBytes), $pattern, '${prefix}${sha}${suffix}')
    if ($before -cne $after) { throw 'pubspec.lock changed beyond quotes around full ref/resolved-ref SHAs; source bytes were not restored.' }
    [IO.File]::WriteAllBytes($Path, $OriginalBytes)
  }
  $restoredHash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($restoredHash -cne $originalHash) { throw 'Original pubspec.lock bytes were not restored.' }
  return [ordered]@{
    restoredQuotingOnly = $changed; originalSha256 = $originalHash
    resolvedSha256 = $resolvedHash; restoredSha256 = $restoredHash
    rule = 'Only matching quotes around unchanged full ref/resolved-ref SHAs may differ.'
  }
}
