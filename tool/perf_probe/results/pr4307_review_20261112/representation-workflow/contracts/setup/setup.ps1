$ErrorActionPreference = 'Stop'
$validationRoot = Join-Path $env:RUNNER_TEMP 'reader-representation-validation'
$comparisonRoot = Join-Path $env:RUNNER_TEMP 'reader-representation-profile'
"VALIDATION_ROOT=$validationRoot" | Add-Content -LiteralPath $env:GITHUB_ENV
"COMPARISON_ROOT=$comparisonRoot" | Add-Content -LiteralPath $env:GITHUB_ENV
New-Item -ItemType Directory -Path $validationRoot -Force | Out-Null
git config --global core.longpaths true
if ($LASTEXITCODE -ne 0) { throw 'Could not enable Git long paths.' }
git config --global core.autocrlf false
if ($LASTEXITCODE -ne 0) { throw 'Could not preserve source line endings.' }
foreach ($revision in @($env:CONTROL_SHA, $env:CANDIDATE_SHA, $env:WORKFLOW_SHA)) {
  if ($revision -notmatch '^[0-9a-f]{40}$') { throw 'All experiment sources must be pinned.' }
}
[ordered]@{
  candidateSourceCommit = $env:CANDIDATE_SHA; flatControlSourceCommit = $env:CONTROL_SHA
  workflowCommit = $env:WORKFLOW_SHA; expectedControlTree = $env:CONTROL_TREE
  cycles = [int]$env:READER_CYCLES; warmup = [int]$env:READER_WARMUP
  repetitions = [int]$env:READER_REPETITIONS; bookLines = @(2000, 50000, 1000000)
  measuredSamplesPerActionAndSide = [int]$env:READER_CYCLES * 2 * [int]$env:READER_REPETITIONS
  processesPerSide = [int]$env:READER_CYCLES * 2
  scope = 'Representation and snapshot sharing, including flags-identity-mediated invalidation.'
  limitation = 'Hosted Windows; no physical-GPU claim and no identical-object-identity claim.'
} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $validationRoot 'experiment-plan.json') -Encoding utf8
