param([string]$OutputDirectory = '', [switch]$EnableNativeTrace, [switch]$ServerPrerequisite)
$ErrorActionPreference = 'Stop'
# The workflow copies this launcher to the bundle root as run.ps1.
$bundle = $PSScriptRoot
$metadata = Get-Content (Join-Path $bundle 'qa-bundle.json') -Raw | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $bundle ('history-results-' + [Guid]::NewGuid().ToString('N'))
}
if ((Test-Path $OutputDirectory) -and @(Get-ChildItem -LiteralPath $OutputDirectory -Force).Count -gt 0) {
    throw 'Use an empty output directory for each run; existing evidence will not be reused or removed.'
}
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
$env:REPORT_QA_HISTORY_OUTPUT = (Resolve-Path $OutputDirectory).Path
$env:REPORT_QA_HISTORY_CONTROLLER = Join-Path $bundle 'qa/windows_history_qa_controller.ps1'
$env:REPORT_QA_SOURCE_HEAD = $metadata.sourceHead
$env:REPORT_QA_QA_HEAD = $metadata.qaHead
$env:REPORT_QA_BASELINE_HEAD = $metadata.baselineHead
$env:REPORT_QA_BASELINE_RUN = $metadata.baselineRun
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
    if ($completed.qaHead -ne $metadata.qaHead -or $completed.sourceHead -ne $metadata.sourceHead) {
        throw 'The completed test summary does not match the packaged candidate.'
    }
    $expected = @('plain-v-focused', 'alt-v-focused', 'posted-v-focused', 'text-focused', 'text-unfocused', 'image-focused', 'image-unfocused')
    $observed = @($completed.cases | ForEach-Object { $_.case })
    if ($observed.Count -ne $expected.Count -or @(Compare-Object ($expected | Sort-Object) ($observed | Sort-Object)).Count -gt 0) {
        throw 'The standalone bundle did not complete all seven distinct native cases.'
    }
    if ($completed.nativeTraceEnabled -ne $EnableNativeTrace.IsPresent) {
        throw 'The native trace state does not match the requested standalone run.'
    }
    if (!$EnableNativeTrace -and (Test-Path (Join-Path $env:REPORT_QA_HISTORY_OUTPUT 'raw-native.jsonl'))) {
        throw 'Native trace output appeared during a run that must not use instrumentation.'
    }
    if ($ServerPrerequisite) {
        . (Join-Path $bundle 'qa/windows_history_qa_server_prerequisite.ps1')
        $proof = Assert-ServerHistoryPrerequisite -Summary $completed -SourceHead $metadata.sourceHead -QaHead $metadata.qaHead `
            -NativeTraceExpected $EnableNativeTrace.IsPresent -OperatingSystem (Get-CimInstance Win32_OperatingSystem)
        $proof['summarySha256'] = (Get-FileHash $summary -Algorithm SHA256).Hash
        $proof | ConvertTo-Json -Depth 10 | Set-Content -Encoding utf8 (Join-Path $env:REPORT_QA_HISTORY_OUTPUT 'server-prerequisite.json')
        Write-Output 'Server prerequisite verified: 3 native controls passed; 4 history cases remain unsupported and failed in the original Flutter evidence.'
        return
    }
    if (@($completed.cases | Where-Object { !$_.reportAssertionsPassed -or (!$_.negativeControl -and !$_.historySelectionVerified) }).Count -gt 0) {
        throw 'One or more standalone report cases did not prove the required result.'
    }
    if (!$completed.allTestsPassed) { exit 1 }
} finally {
    if ($null -ne $application -and !$application.HasExited) {
        & taskkill.exe /PID $application.Id /T /F | Out-Null
    }
}
