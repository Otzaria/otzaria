function Assert-ServerHistoryPrerequisite {
    param(
        [Parameter(Mandatory)]$Summary,
        [Parameter(Mandatory)][string]$SourceHead,
        [Parameter(Mandatory)][string]$QaHead,
        [Parameter(Mandatory)][bool]$NativeTraceExpected,
        [Parameter(Mandatory)]$OperatingSystem
    )
    if ($OperatingSystem.Caption -notmatch '^Microsoft Windows Server\b' -or
        $OperatingSystem.ProductType -notin @(2, 3)) {
        throw 'Missing history may only be classified as a Windows Server prerequisite.'
    }
    if ($SourceHead -cnotmatch '^[0-9a-f]{40}$' -or $QaHead -cnotmatch '^[0-9a-f]{40}$' -or
        $Summary.sourceHead -cne $SourceHead -or $Summary.qaHead -cne $QaHead -or
        $Summary.nativeTraceEnabled -isnot [bool] -or $Summary.nativeTraceEnabled -ne $NativeTraceExpected -or
        $Summary.allTestsPassed -isnot [bool] -or $Summary.allTestsPassed) {
        throw 'The Server observation does not identify the expected candidate, trace state and failed history tests.'
    }
    $controls = @('plain-v-focused', 'alt-v-focused', 'posted-v-focused')
    $history = @('text-focused', 'text-unfocused', 'image-focused', 'image-unfocused')
    $expected = @($controls + $history)
    $observed = @($Summary.cases | ForEach-Object { $_.case })
    if ($observed.Count -ne 7 -or
        @(Compare-Object -CaseSensitive ($expected | Sort-Object) ($observed | Sort-Object)).Count -ne 0) {
        throw 'The Server observation must contain exactly the seven distinct native cases.'
    }
    foreach ($case in $Summary.cases) {
        $isControl = $case.case -cin $controls
        $controller = $case.controller
        if ($case.negativeControl -isnot [bool] -or $case.negativeControl -ne $isControl -or
            $case.reportAssertionsPassed -isnot [bool] -or $case.reportAssertionsPassed -ne $isControl -or
            $case.historySelectionVerified -isnot [bool] -or $case.historySelectionVerified -or
            ($case.controllerExitCode -isnot [int] -and $case.controllerExitCode -isnot [long]) -or
            $case.controllerExitCode -ne 0 -or $case.controllerTimedOut -eq $true -or
            $controller.probeCompleted -isnot [bool] -or !$controller.probeCompleted -or
            $controller.historyWindowIdentified -isnot [bool] -or $controller.historyWindowIdentified -or
            $controller.historySelectionVerified -isnot [bool] -or $controller.historySelectionVerified -or
            $null -ne $controller.error) {
            throw "A Server case has an infrastructure error or contradictory result: $($case.case)"
        }
        $expectedOutcome = if ($isControl) { 'native-negative-control-sent-without-history-ui' } else { 'history-window-not-identified' }
        if ($controller.outcome -cne $expectedOutcome -or
            ($isControl -and ($controller.nativeControlInputSent -isnot [bool] -or !$controller.nativeControlInputSent)) -or
            (!$isControl -and $controller.historyOpeningAttempts -ne 2)) {
            throw "The Server case did not complete its required native observation: $($case.case)"
        }
        foreach ($key in @('nativeControl', 'nativeAlt', 'nativeWin', 'nativeV')) {
            if ($case.inputBeforeCleanup.$key -isnot [bool] -or $case.inputBeforeCleanup.$key) {
                throw "A Server case left an input key pressed before cleanup: $($case.case) / $key"
            }
        }
        if ($null -eq $case.inputBeforeCleanup.flutterKeys -or $case.inputBeforeCleanup.flutterKeys.Count -ne 0 -or
            $case.inputBeforeCleanup.foreground -ne $case.flutterWindow) {
            throw "The Server observation lost Flutter focus or left Flutter keys pressed: $($case.case)"
        }
    }
    $expectedFailures = @($history | ForEach-Object { 'real Windows history selection in report: ' + $_ })
    $failedNames = @($Summary.failedTests)
    $failures = @($Summary.failureDetails)
    $reported = @($Summary.reportedFailureDetails)
    if ($failedNames.Count -ne 4 -or $failures.Count -ne 4 -or $reported.Count -ne 4 -or
        @(Compare-Object -CaseSensitive ($expectedFailures | Sort-Object) ($failedNames | Sort-Object)).Count -ne 0 -or
        @(Compare-Object -CaseSensitive ($expectedFailures | Sort-Object) (@($failures.methodName) | Sort-Object)).Count -ne 0 -or
        @(Compare-Object -CaseSensitive ($expectedFailures | Sort-Object) (@($reported.methodName) | Sort-Object)).Count -ne 0) {
        throw 'Only the four named history tests may fail in the Server prerequisite.'
    }
    $reason = 'Real Windows history selection is a prerequisite, not a simulated paste: history-window-not-identified'
    $expectedFailure = 'The following TestFailure was thrown running a test: Expected: true Actual: <false> ' +
        $reason + ' When the exception was thrown, this was the stack:'
    foreach ($failure in $failures) {
        if ($failure.details -isnot [string]) { throw 'A Server failure is missing its original Flutter diagnostic.' }
        $observation = @($reported | Where-Object { $_.methodName -ceq $failure.methodName })[0]
        $message = ($observation.exceptionMessage -replace '\s+', ' ').Trim()
        if ($observation.exceptionType -cne 'TestFailure' -or $message -cne ('Expected: true Actual: <false> ' + $reason) -or
            $observation.details -cne $failure.details) {
            throw "The original Flutter failure was replaced or was not the missing-history assertion: $($failure.methodName)"
        }
        $normalized = ($failure.details -replace '\s+', ' ').Trim()
        if (!$normalized.Contains($expectedFailure) -or
            [regex]::Matches($normalized, 'The following .*? was thrown').Count -ne 1 -or
            $normalized -match '(?i)Multiple exceptions') {
            throw "A Server test failed for a reason other than the missing history window: $($failure.methodName)"
        }
    }
    return @{
        outcome = 'server-history-ui-unavailable'; sourceHead = $SourceHead; qaHead = $QaHead
        nativeTraceEnabled = $NativeTraceExpected; host = @{ caption = $OperatingSystem.Caption; productType = $OperatingSystem.ProductType }
        reportCasesPassed = 3; historyCasesUnsupported = 4; historyCasesPassed = 0
        rawAllTestsPassed = $Summary.allTestsPassed; failedTests = $failedNames
    }
}
