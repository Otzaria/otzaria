param([string]$Index)
$ErrorActionPreference = 'Stop'
$blocks = Get-Content -LiteralPath $Index -Raw | ConvertFrom-Json
foreach ($block in $blocks) {
  $tokens = $null; $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($block.path, [ref]$tokens, [ref]$errors) | Out-Null
  if ($errors.Count) { $errors | Format-List; throw $block.name }
}
Write-Host "Parsed all $($blocks.Count) final PowerShell blocks."
