param([string]$Output = '')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'windows_history_qa_server_prerequisite.ps1')
$source = '1111111111111111111111111111111111111111'
$qa = '2222222222222222222222222222222222222222'
$hostRecord = [pscustomobject]@{ Caption = 'Microsoft Windows Server 2025 Datacenter'; ProductType = 3 }
$controls = @('plain-v-focused', 'alt-v-focused', 'posted-v-focused')
$history = @('text-focused', 'text-unfocused', 'image-focused', 'image-unfocused')
$names = @($controls + $history)
$failure = @'
The following TestFailure was thrown running a test:
Expected: true
  Actual: <false>
Real Windows history selection is a prerequisite, not a simulated paste:
history-window-not-identified

When the exception was thrown, this was the stack:
#4 main.<anonymous closure> (report_clipboard_history_windows_qa_test.dart)
'@
$fixture = @{
    sourceHead = $source; qaHead = $qa; nativeTraceEnabled = $false; allTestsPassed = $false
    failedTests = @($history | ForEach-Object { 'real Windows history selection in report: ' + $_ })
    failureDetails = @($history | ForEach-Object { @{ methodName = 'real Windows history selection in report: ' + $_; details = $failure } })
    reportedFailureDetails = @($history | ForEach-Object { @{
        methodName = 'real Windows history selection in report: ' + $_; details = $failure; exceptionType = 'TestFailure'
        exceptionMessage = "Expected: true`n  Actual: <false>`nReal Windows history selection is a prerequisite, not a simulated paste:`nhistory-window-not-identified"
    } })
    cases = @($names | ForEach-Object {
        $control = $_ -cin $controls
        @{
            case = $_; negativeControl = $control; reportAssertionsPassed = $control; historySelectionVerified = $false
            controllerExitCode = 0; flutterWindow = 101
            controller = @{
                probeCompleted = $true; historyWindowIdentified = $false; historySelectionVerified = $false; error = $null
                outcome = if ($control) { 'native-negative-control-sent-without-history-ui' } else { 'history-window-not-identified' }
                nativeControlInputSent = $control; historyOpeningAttempts = if ($control) { 0 } else { 2 }
            }
            inputBeforeCleanup = @{ foreground = 101; nativeControl = $false; nativeAlt = $false; nativeWin = $false; nativeV = $false; flutterKeys = @() }
        }
    })
}
$encoded = $fixture | ConvertTo-Json -Depth 16
$records = New-Object 'Collections.Generic.List[object]'
function Check([string]$Name, [scriptblock]$Change, [bool]$Accept = $false, [bool]$Trace = $false, $HostOverride = $hostRecord) {
    $candidate = $encoded | ConvertFrom-Json
    if ($null -ne $Change) { & $Change $candidate }
    $accepted = $false; $errorText = $null; $proof = $null
    try {
        $proof = Assert-ServerHistoryPrerequisite -Summary $candidate -SourceHead $source -QaHead $qa -NativeTraceExpected $Trace -OperatingSystem $HostOverride
        $accepted = $true
    } catch { $errorText = $_.Exception.Message }
    if ($accepted -ne $Accept) { throw "Unexpected Server classifier result for ${Name}: $errorText" }
    if ($accepted -and ($proof.reportCasesPassed -ne 3 -or $proof.historyCasesUnsupported -ne 4 -or
        $proof.historyCasesPassed -ne 0 -or $proof.rawAllTestsPassed -ne $false)) {
        throw 'The Server classifier misrepresented unsupported history as a passing test.'
    }
    $records.Add(@{ case = $Name; accepted = $accepted; expectedAcceptance = $Accept; error = $errorText; passed = $true })
}
Check 'exact_server_trace_off' $null $true
Check 'exact_server_trace_on' { param($v) $v.nativeTraceEnabled = $true } $true $true
Check 'windows11_not_server' $null $false $false ([pscustomobject]@{ Caption = 'Microsoft Windows 11 Enterprise'; ProductType = 1 })
Check 'server_caption_with_client_product_type' $null $false $false ([pscustomobject]@{ Caption = 'Microsoft Windows Server 2025 Datacenter'; ProductType = 1 })
Check 'wrong_source' { param($v) $v.sourceHead = '3333333333333333333333333333333333333333' }
Check 'wrong_qa' { param($v) $v.qaHead = '3333333333333333333333333333333333333333' }
Check 'wrong_trace_state' { param($v) $v.nativeTraceEnabled = $true }
Check 'string_trace_state' { param($v) $v.nativeTraceEnabled = 'false' }
Check 'all_passed_must_not_be_claimed' { param($v) $v.allTestsPassed = $true }
Check 'string_all_passed' { param($v) $v.allTestsPassed = 'false' }
Check 'missing_case' { param($v) $v.cases = @($v.cases[0..5]) }
Check 'duplicated_case' { param($v) $v.cases[6].case = $v.cases[5].case }
Check 'extra_case' { param($v) $v.cases += $v.cases[0] }
Check 'wrong_case_name_capitalization' { param($v) $v.cases[0].case = 'Plain-v-focused' }
Check 'control_failed' { param($v) $v.cases[0].reportAssertionsPassed = $false }
Check 'string_control_result' { param($v) $v.cases[0].reportAssertionsPassed = 'true' }
Check 'control_not_classified' { param($v) $v.cases[0].negativeControl = $false }
Check 'history_incorrectly_classified_as_control' { param($v) $v.cases[3].negativeControl = $true }
Check 'history_cannot_pass' { param($v) $v.cases[3].reportAssertionsPassed = $true }
Check 'history_was_selected' { param($v) $v.cases[3].historySelectionVerified = $true }
Check 'controller_selected_history' { param($v) $v.cases[3].controller.historySelectionVerified = $true }
Check 'history_window_was_identified' { param($v) $v.cases[3].controller.historyWindowIdentified = $true }
Check 'controller_exit_one' { param($v) $v.cases[3].controllerExitCode = 1 }
Check 'controller_missing_exit' { param($v) $v.cases[3].controllerExitCode = $null }
Check 'controller_string_exit' { param($v) $v.cases[3].controllerExitCode = '0' }
Check 'controller_timeout' { param($v) $v.cases[3] | Add-Member -NotePropertyName controllerTimedOut -NotePropertyValue $true }
Check 'controller_not_completed' { param($v) $v.cases[3].controller.probeCompleted = $false }
Check 'controller_string_completed' { param($v) $v.cases[3].controller.probeCompleted = 'true' }
Check 'controller_error' { param($v) $v.cases[3].controller.error = 'Unexpected foreground window' }
Check 'wrong_control_outcome' { param($v) $v.cases[0].controller.outcome = 'history-window-not-identified' }
Check 'control_input_missing' { param($v) $v.cases[0].controller.nativeControlInputSent = $false }
Check 'wrong_history_outcome' { param($v) $v.cases[3].controller.outcome = 'history-visible-but-fixture-selection-not-identified' }
Check 'history_probe_did_not_finish_bounded_attempts' { param($v) $v.cases[3].controller.historyOpeningAttempts = 1 }
Check 'native_key_still_pressed' { param($v) $v.cases[3].inputBeforeCleanup.nativeV = $true }
Check 'native_key_state_missing' { param($v) $v.cases[3].inputBeforeCleanup.nativeControl = $null }
Check 'flutter_key_still_pressed' { param($v) $v.cases[3].inputBeforeCleanup.flutterKeys = @('0x76') }
Check 'flutter_key_state_missing' { param($v) $v.cases[3].inputBeforeCleanup.flutterKeys = $null }
Check 'wrong_foreground_at_completion' { param($v) $v.cases[3].inputBeforeCleanup.foreground = 202 }
Check 'missing_named_failure' { param($v) $v.failedTests = @($v.failedTests[0..2]) }
Check 'extra_named_failure' { param($v) $v.failedTests += 'tearDownAll' }
Check 'duplicate_named_failure' { param($v) $v.failedTests[3] = $v.failedTests[2] }
Check 'missing_failure_details' { param($v) $v.failureDetails = @($v.failureDetails[0..2]) }
Check 'extra_failure_details' { param($v) $v.failureDetails += [pscustomobject]@{ methodName = 'tearDownAll'; details = 'Cleanup failed' } }
Check 'wrong_failure_method' { param($v) $v.failureDetails[0].methodName = 'real Windows history selection in report: plain-v-focused' }
Check 'failure_without_details' { param($v) $v.failureDetails[0].details = $null }
Check 'unrelated_failure' { param($v) $v.failureDetails[0].details = 'The following StateError was thrown running a test: Unexpected framework exception' }
Check 'wrong_assertion_actual' { param($v) $v.failureDetails[0].details = $v.failureDetails[0].details.Replace('Actual: <false>', 'Actual: <null>') }
Check 'wrong_history_failure_reason' { param($v) $v.failureDetails[0].details = $v.failureDetails[0].details.Replace('history-window-not-identified', 'history-selection-did-not-select-A') }
Check 'multiple_exceptions_with_original_reason' { param($v) $v.failureDetails[0].details += "`nMultiple exceptions were detected." }
Check 'additional_exception_with_original_reason' { param($v) $v.failureDetails[0].details += "`nThe following StateError was thrown running a test: Cleanup failed" }
Check 'overwritten_earlier_framework_failure' { param($v) $v.reportedFailureDetails += [pscustomobject]@{
    methodName = $v.reportedFailureDetails[0].methodName; exceptionType = 'FlutterError'; exceptionMessage = 'Unexpected layout failure'; details = 'Unexpected layout failure'
} }
Check 'earlier_failure_not_retained_in_summary' { param($v) $v.reportedFailureDetails = @($v.reportedFailureDetails[0..2]) }
Check 'wrong_original_exception_type' { param($v) $v.reportedFailureDetails[0].exceptionType = 'StateError' }
Check 'original_failure_message_has_another_error' { param($v) $v.reportedFailureDetails[0].exceptionMessage += ' Another failure occurred.' }
Check 'original_failure_differs_from_mapped_failure' { param($v) $v.reportedFailureDetails[0].details = 'Earlier failure that was replaced' }
$result = @{ fixture = 'Synthetic Server summary; failure diagnostic shape matches observed Flutter 3.47.7 output'; cases = $records; passed = $true; nativeWindowsExecuted = $false }
if (![string]::IsNullOrWhiteSpace($Output)) {
    $result | ConvertTo-Json -Depth 12 | Set-Content -Encoding utf8 $Output
}
Write-Output "Server prerequisite classifier: $($records.Count) cases passed; native Windows execution remains required."
