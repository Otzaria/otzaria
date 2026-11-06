param([string]$OutputDirectory = '', [switch]$EnableNativeTrace)
$ErrorActionPreference = 'Stop'
# The workflow copies this launcher to the bundle root as run.ps1.
$bundle = $PSScriptRoot
$metadata = Get-Content (Join-Path $bundle 'qa-bundle.json') -Raw | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $bundle ('history-results-' + [Guid]::NewGuid().ToString('N'))
}
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
$env:REPORT_QA_HISTORY_OUTPUT = (Resolve-Path $OutputDirectory).Path
$env:REPORT_QA_HISTORY_CONTROLLER = Join-Path $bundle 'qa/windows_history_qa_controller.ps1'
$env:REPORT_QA_SOURCE_HEAD = $metadata.sourceHead
$env:REPORT_QA_QA_HEAD = $metadata.qaHead
if ($EnableNativeTrace) {
    $env:REPORT_QA_HISTORY_TRACE = Join-Path $env:REPORT_QA_HISTORY_OUTPUT 'raw-native.jsonl'
} else { Remove-Item Env:REPORT_QA_HISTORY_TRACE -ErrorAction SilentlyContinue }
$application = $null
$completed = $null
try {
    $application = Start-Process (Join-Path $bundle 'otzaria.exe') -WorkingDirectory $bundle -PassThru -RedirectStandardOutput (Join-Path $env:REPORT_QA_HISTORY_OUTPUT 'application.stdout.log') -RedirectStandardError (Join-Path $env:REPORT_QA_HISTORY_OUTPUT 'application.stderr.log')
    $deadline = [DateTime]::UtcNow.AddMinutes(12)
    $summary = Join-Path $env:REPORT_QA_HISTORY_OUTPUT 'flutter-summary.json'
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-Path $summary) {
            try { $completed = Get-Content $summary -Raw | ConvertFrom-Json; break }
            catch { }
        }
        if ($application.HasExited) { break }
        Start-Sleep -Milliseconds 500
    }
    if ($null -eq $completed) { throw 'The standalone Flutter bundle did not produce a complete test summary; no history result may be inferred.' }
    $completed | ConvertTo-Json -Depth 20 | Write-Output
    if (!$completed.allTestsPassed) { exit 1 }
} finally {
    if ($null -ne $application -and !$application.HasExited) {
        & taskkill.exe /PID $application.Id /T /F | Out-Null
    }
}
