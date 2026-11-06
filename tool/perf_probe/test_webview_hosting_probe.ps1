#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:assertions = 0
Import-Module (Join-Path $PSScriptRoot 'webview_hosting_probe.psm1') -Force
function Assert-Equal($Expected, $Actual, [string]$Message) {
    $script:assertions++
    if ($Expected -cne $Actual) { throw "$Message; expected=$Expected actual=$Actual" }
}
function Assert-Throws([scriptblock]$Action, [string]$Pattern, [string]$Message) {
    $script:assertions++
    $failure = $null
    try { & $Action | Out-Null } catch { $failure = $_.Exception.Message }
    if ($null -eq $failure -or $failure -notlike $Pattern) { throw "$Message; failure=$failure" }
}
function New-Sample([double]$Elapsed, [object[]]$Processes, [int]$Missing = 0) {
    return [pscustomobject]@{ elapsedSeconds = $Elapsed; processes = $Processes; missingProcesses = $Missing }
}
function New-Record([int]$Id, [double]$Cpu, [string]$Started = 'first') {
    return [pscustomobject]@{ processId = $Id; cpuSeconds = $Cpu; startedUtc = $Started }
}
$started = [datetime]'2026-01-01T00:00:00Z'
function New-ProcessSnapshot([int]$Id, [int]$Parent, $Created) {
    return [pscustomobject]@{ ProcessId = $Id; ParentProcessId = $Parent; CreationDate = $Created }
}
$root = New-ProcessSnapshot 10 12 $started
$child = New-ProcessSnapshot 11 10 $started.AddSeconds(20)
$grandchild = New-ProcessSnapshot 12 11 $started.AddSeconds(30)
$foreign = New-ProcessSnapshot 99 1 $started.AddSeconds(40)
$tree = @(Get-WebViewHostingTree -RootProcessId 10 -RootStartedUtc $started -Processes @(
    $grandchild, $child, $root, $foreign
))
Assert-Equal '10,11,12' ($tree.ProcessId -join ',') 'Descendants, cycles and unrelated processes'
$older = New-ProcessSnapshot 13 11 $started.AddSeconds(10)
$olderChild = New-ProcessSnapshot 14 13 $started.AddSeconds(40)
$tree = @(Get-WebViewHostingTree -RootProcessId 10 -RootStartedUtc $started -Processes @(
    $olderChild, $older, $grandchild, $child, $root
))
Assert-Equal '10,11,12' ($tree.ProcessId -join ',') 'Reused parent PID cannot claim an older process or its children'
$unknown = New-ProcessSnapshot 15 11 $null
$unknownChild = New-ProcessSnapshot 16 15 $started.AddSeconds(50)
$tree = @(Get-WebViewHostingTree -RootProcessId 10 -RootStartedUtc $started -Processes @(
    $unknownChild, $unknown, $child, $root
))
Assert-Equal '10,11,15' ($tree.ProcessId -join ',') 'Unknown child identity is retained as missing but cannot extend ancestry'
Assert-Throws {
    Get-WebViewHostingTree -RootProcessId 10 -RootStartedUtc $started -Processes @()
} '*launched process identity*' 'An empty snapshot cannot represent a valid process sample'
Assert-Throws {
    Get-WebViewHostingTree -RootProcessId 10 -RootStartedUtc $started.AddSeconds(1) -Processes @($root, $child)
} '*launched process identity*' 'Reused root PID must not select a foreign tree'
Assert-Throws {
    Get-WebViewHostingTree -RootProcessId 10 -RootStartedUtc $started -Processes @($root, $root)
} '*Duplicate PID*' 'Ambiguous snapshot identities are rejected'
Assert-Equal 1 (@(Get-WebViewHostingTree -RootProcessId 10 -RootStartedUtc $started.AddTicks(9) -Processes @($root))).Count 'CIM microsecond precision is accepted'
Assert-Throws {
    Get-WebViewHostingTree -RootProcessId 10 -RootStartedUtc $started.AddTicks(10) -Processes @($root)
} '*launched process identity*' 'A full microsecond difference is not rounding'

function New-FakeProcess([datetime]$Created) {
    $process = [pscustomobject]@{
        StartTime = $Created; ProcessName = 'test-process'
        TotalProcessorTime = [timespan]::FromSeconds(2.5)
        PrivateMemorySize64 = [long]123456; WorkingSet64 = [long]654321
        Disposed = $false
    }
    $process | Add-Member -MemberType ScriptMethod -Name Dispose -Value { $this.Disposed = $true }
    return $process
}
$first = New-FakeProcess $started.AddTicks(9)
$check = New-FakeProcess $started.AddTicks(9)
$reads = [System.Collections.Generic.Queue[object]]::new()
$reads.Enqueue($first)
$reads.Enqueue($check)
$reader = { param($processId) $reads.Dequeue() }.GetNewClosure()
$record = Read-WebViewHostingProcess -Snapshot $root -ReadProcess $reader
Assert-Equal 10 $record.processId 'Read metrics belong to the selected process'
Assert-Equal 2.5 $record.cpuSeconds 'CPU units remain seconds'
Assert-Equal 123456 $record.privateCommitBytes 'Private commit remains in bytes'
Assert-Equal 654321 $record.workingSetBytes 'Working set remains a separate byte metric'
Assert-Equal $true $first.Disposed 'The sampled process handle is disposed'
Assert-Equal $true $check.Disposed 'The verification process handle is disposed'
$replacement = New-FakeProcess $started.AddSeconds(1)
$reader = { param($processId) $replacement }.GetNewClosure()
Assert-Throws {
    Read-WebViewHostingProcess -Snapshot $root -ReadProcess $reader
} '*identity changed after*' 'PID reuse between CIM and counter reads is rejected'
Assert-Equal $true $replacement.Disposed 'Rejected process handles are disposed'
Assert-Throws {
    Read-WebViewHostingProcess -Snapshot $unknown -ReadProcess $reader
} '*identity changed after*' 'Unknown creation time never becomes measured CPU or memory'
$first = New-FakeProcess $started
$replacement = New-FakeProcess $started.AddSeconds(1)
$reads = [System.Collections.Generic.Queue[object]]::new()
$reads.Enqueue($first)
$reads.Enqueue($replacement)
$reader = { param($processId) $reads.Dequeue() }.GetNewClosure()
Assert-Throws {
    Read-WebViewHostingProcess -Snapshot $root -ReadProcess $reader
} '*identity changed while*' 'PID reuse while reading counters is rejected'
Assert-Equal $true $first.Disposed 'The old process handle is disposed after mid-read reuse'
Assert-Equal $true $replacement.Disposed 'The replacement process handle is disposed after mid-read reuse'
$first = New-FakeProcess $started
$reads = [System.Collections.Generic.Queue[object]]::new()
$reads.Enqueue($first)
$reader = { param($processId) $reads.Dequeue() }.GetNewClosure()
Assert-Throws {
    Read-WebViewHostingProcess -Snapshot $root -ReadProcess $reader
} '*Queue empty*' 'A process that exits during counter reads invalidates that process sample'
Assert-Equal $true $first.Disposed 'The process handle is disposed when verification fails'

if ($IsWindows) {
    $self = [System.Diagnostics.Process]::GetCurrentProcess()
    try {
        $snapshot = Get-CimInstance Win32_Process -Filter "ProcessId=$($self.Id)" -Property ProcessId, ParentProcessId, CreationDate
        $tree = @(Get-WebViewHostingTree -RootProcessId $self.Id -RootStartedUtc $self.StartTime -Processes @($snapshot))
        $record = Read-WebViewHostingProcess -Snapshot $tree[0]
        Assert-Equal $self.Id $record.processId 'Real CIM and Process creation times identify the same Windows process'
        Assert-Equal $true ($record.privateCommitBytes -ge 0) 'Real private commit is readable without elevated access'
    } finally { $self.Dispose() }
}

$trialProcess = [pscustomobject]@{ HasExited = $false; ExitOnRefresh = $false; RefreshCount = 0 }
$trialProcess | Add-Member -MemberType ScriptMethod -Name Refresh -Value {
    $this.RefreshCount++
    if ($this.ExitOnRefresh) { $this.HasExited = $true }
}
$writer = [System.IO.StringWriter]::new()
try {
    Complete-WebViewHostingTrial -Process $trialProcess -Writer $writer -ElapsedSeconds 30
    $end = $writer.ToString() | ConvertFrom-Json
    Assert-Equal $true $end.complete 'A process alive at trial completion produces a complete record'
    Assert-Equal 30 $end.elapsedSeconds 'Completion records the measured duration'
    Assert-Equal 1 $trialProcess.RefreshCount 'Final liveness is checked after the sampling loop'
} finally { $writer.Dispose() }
$trialProcess.ExitOnRefresh = $true
$writer = [System.IO.StringWriter]::new()
try {
    Assert-Throws {
        Complete-WebViewHostingTrial -Process $trialProcess -Writer $writer -ElapsedSeconds 30
    } '*trial is incomplete*' 'Exit during the final sleep must not count as a completed trial'
    Assert-Equal '' $writer.ToString() 'An exited process cannot write a successful end record'
} finally { $writer.Dispose() }

$a = New-Sample 0 @((New-Record 10 1), (New-Record 11 2))
$b = New-Sample 2 @((New-Record 10 2), (New-Record 11 2.5))
Assert-Equal 75 (Get-WebViewHostingCpuPercent $a $b) 'CPU uses elapsed seconds and all observed processes'
Assert-Equal $null (Get-WebViewHostingCpuPercent $null $b) 'First sample is unknown, not zero'
Assert-Equal $null (Get-WebViewHostingCpuPercent $a $a) 'Zero interval is unknown'
Assert-Equal $null (Get-WebViewHostingCpuPercent $b $a) 'Clock reversal is unknown'
$c = New-Sample 2 @((New-Record 10 1), (New-Record 11 2))
Assert-Equal 0 (Get-WebViewHostingCpuPercent $a $c) 'A measured idle interval is zero'
$c = New-Sample 2 @((New-Record 10 1), (New-Record 11 2)) 1
Assert-Equal $null (Get-WebViewHostingCpuPercent $a $c) 'An unreadable process invalidates the interval'
$c = New-Sample 2 @((New-Record 10 1))
Assert-Equal $null (Get-WebViewHostingCpuPercent $a $c) 'Process exit is not negative CPU'
$c = New-Sample 2 @((New-Record 10 2), (New-Record 11 3 'reused'))
Assert-Equal $null (Get-WebViewHostingCpuPercent $a $c) 'Reused PID is a different process'
$c = New-Sample 2 @((New-Record 10 0.5), (New-Record 11 2))
Assert-Equal $null (Get-WebViewHostingCpuPercent $a $c) 'A counter reset is unknown'
$c = New-Sample 2 @((New-Record 10 ([double]::NaN)), (New-Record 11 2))
Assert-Equal $null (Get-WebViewHostingCpuPercent $a $c) 'NaN cannot become a JSON metric'
$c = New-Sample 2 @((New-Record 10 1), (New-Record 10 1))
Assert-Equal $null (Get-WebViewHostingCpuPercent $a $c) 'Duplicate processes cannot count twice'

$variable = 'FLUTTER_INAPPWEBVIEW_WINDOWS_FORCE_HWND'
$original = [System.Environment]::GetEnvironmentVariable($variable, 'Process')
try {
    [System.Environment]::SetEnvironmentVariable($variable, 'parent-value', 'Process')
    $executable = (Get-Process -Id $PID).Path
    $forced = New-WebViewHostingStartInfo -Executable $executable -Mode hwnd -RunId 'run-forced' -DiagnosticsPath 'forced.jsonl'
    $normal = New-WebViewHostingStartInfo -Executable $executable -Mode default -RunId 'run-default' -DiagnosticsPath 'default.jsonl'
    Assert-Equal '1' $forced.Environment[$variable] 'HWND set only for the child'
    Assert-Equal '0' $normal.Environment[$variable] 'Composition request replaces an inherited force flag'
    Assert-Equal 'run-forced' $forced.Environment['OTZARIA_WEBVIEW_PROBE_RUN_ID'] 'Run identity is child-specific'
    Assert-Equal 'default.jsonl' $normal.Environment['OTZARIA_DEV_DIAGNOSTICS_OUT'] 'Diagnostics use a per-trial file'
    Assert-Equal 'parent-value' ([System.Environment]::GetEnvironmentVariable($variable, 'Process')) 'Parent environment is unchanged'
    Assert-Equal '--dev-diagnostics=log' $forced.ArgumentList[0] 'Arguments are not shell text'
    Assert-Equal $false $forced.UseShellExecute 'No shell interpolation'
} finally {
    [System.Environment]::SetEnvironmentVariable($variable, $original, 'Process')
}

$directory = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
[void][System.IO.Directory]::CreateDirectory($directory)
try {
    $path = Join-Path $directory 'observations.jsonl'
    function New-DiagnosticRecord([string]$Type, [double]$Second) {
        return @{
            type = $Type; utc = $started.AddSeconds($Second).ToString('o')
            pid = 10; probeRunId = 'run-a'; session = 1
            version = 'test-build'; buildMode = 'profile'; flutterVersion = '3.47.7'; osVersion = 'Windows test'
        }
    }
    function New-Attachment([string]$Mode = 'composition', [string]$Id = ('a' * 32), [double]$Second = 1) {
        $record = New-DiagnosticRecord 'webview_backend' $Second
        $record.event = 'attached'; $record.attachmentId = $Id
        $record.pluginId = 'test.plugin'; $record.hostKind = 'Plugin'
        $record.physicalWidth = 1200; $record.physicalHeight = 800; $record.devicePixelRatio = 1.25
        $record.webView2RuntimeVersion = '123.0.0.0'
        $record.backend = @{
            schemaVersion = 1; scope = 'nativeCreation'; availability = 'collected'
            source = 'WindowsInAppWebViewController.creationDetails'
            requested = $Mode; observed = $Mode; verified = $true; nativeViewId = 8
            fallbackReasonAvailable = $false; fallbackStage = $null; fallbackHresult = $null
            ongoingModeVerified = $false
        }
        return $record
    }
    function New-Diagnostics([string]$Mode = 'composition') {
        return @(
            (New-DiagnosticRecord 'session' 0.1), (New-Attachment $Mode)
            (New-DiagnosticRecord 'webview_probe_tick' 2), (New-DiagnosticRecord 'webview_probe_tick' 3)
            (New-DiagnosticRecord 'webview_probe_tick' 4), (New-DiagnosticRecord 'webview_probe_tick' 5)
        )
    }
    function Read-Backend([object[]]$Records, [string]$Requested = 'composition') {
        $Records | ForEach-Object { ConvertTo-Json -InputObject $_ -Depth 10 -Compress } |
            Set-Content -LiteralPath $path -Encoding utf8
        return Read-WebViewHostingBackend -Path $path -RunId 'run-a' -RootProcessId 10 -RootStartedUtc $started `
            -SampleStartedUtc $started.AddSeconds(2.5) -SampleEndedUtc $started.AddSeconds(4.5) -RequestedBackend $Requested
    }
    function Assert-Reason($Backend, [string]$Reason) {
        Assert-Equal $true ($Backend.reasons -ccontains $Reason) "Must retain reason $Reason"
    }
    $composition = Read-Backend (New-Diagnostics)
    $hwnd = Read-Backend (New-Diagnostics 'hwnd') 'hwnd'
    Assert-Equal 'composition' $composition.actualBackend 'Composition comes from the getter record'
    Assert-Equal 'hwnd' $hwnd.actualBackend 'HWND comes from the getter record'
    Assert-Equal $true $composition.verified 'An explicit native mode is verified'
    Assert-Equal $false $composition.ongoingModeVerified 'Creation is never rebranded as continuous observation'
    Assert-Equal 0 $composition.reasons.Count 'A complete creation observation is comparable'
    Assert-Equal $false $composition.activeAttachments[0].backend.fallbackReasonAvailable 'No reason does not imply no fallback'

    $records = New-Diagnostics
    $records[1].backend.observed = 'hwnd'
    $records[1].backend.fallbackReasonAvailable = $true
    $records[1].backend.fallbackStage = 'capture'; $records[1].backend.fallbackHresult = 2147500037
    $fallback = Read-Backend $records
    Assert-Equal 'hwnd' $fallback.actualBackend 'Capture/RDP fallback remains observed HWND'
    Assert-Equal $true $fallback.verified 'Fallback does not erase valid native evidence'
    Assert-Reason $fallback 'composition_fell_back_to_hwnd'
    Assert-Equal 2147500037 $fallback.observations[0].backend.fallbackHresult 'Unsigned creation HRESULT is preserved'

    $records = New-Diagnostics 'hwnd'; $records[1].backend.observed = 'composition'
    Assert-Reason (Read-Backend $records 'hwnd') 'forced_hwnd_mismatch'
    $records = New-Diagnostics; $records[1].backend.verified = $false; $records[1].backend.observed = $null
    $legacy = Read-Backend $records
    Assert-Reason $legacy 'unverified_backend'
    Assert-Equal $null $legacy.actualBackend 'A force flag or compatibility default cannot infer the backend'
    $records = New-Diagnostics; $records[1].backend.observed = 'future-mode'
    Assert-Reason (Read-Backend $records) 'unverified_backend'
    $records = New-Diagnostics; $records[1].backend.source = 'absence-of-fallback-event'
    Assert-Reason (Read-Backend $records) 'unverified_backend'
    $records = New-Diagnostics; $records[1].backend.verified = 1
    Assert-Reason (Read-Backend $records) 'unverified_backend'
    $records = New-Diagnostics; $records[1].backend.requested = 'hwnd'
    Assert-Reason (Read-Backend $records) 'request_metadata_mismatch'
    $records = New-Diagnostics; $records[1].probeRunId = 'older-run'
    Assert-Reason (Read-Backend $records) 'foreign_run_or_process'
    $records = New-Diagnostics; $records[1].pid = 99
    Assert-Reason (Read-Backend $records) 'foreign_run_or_process'
    $records = New-Diagnostics; $records[1].utc = $started.AddSeconds(-1).ToString('o')
    Assert-Reason (Read-Backend $records) 'invalid_record_time'
    $records = New-Diagnostics; $records[3].session = 2
    Assert-Reason (Read-Backend $records) 'collection_session_changed'
    $records = New-Diagnostics; $records[3].type = 'end'
    Assert-Reason (Read-Backend $records) 'collection_stopped_during_sampling'
    $records = New-Diagnostics
    Assert-Reason (Read-Backend $records[0..4]) 'sampling_interval_not_covered'
    $records = New-Diagnostics
    $records[5].utc = $started.AddSeconds(6).ToString('o')
    Assert-Reason (Read-Backend @($records[0], $records[1], $records[2], $records[5])) 'diagnostics_gap_during_sampling'
    $records = New-Diagnostics; $records[0].utc = $started.AddSeconds(3).ToString('o')
    Assert-Reason (Read-Backend $records) 'collection_started_after_sampling'
    $records = New-Diagnostics; $records[1].physicalWidth = 0
    Assert-Reason (Read-Backend $records) 'host_setup_unavailable'
    $records = New-Diagnostics; $records[1].webView2RuntimeVersion = $null
    Assert-Reason (Read-Backend $records) 'host_setup_unavailable'
    $records = New-Diagnostics
    Assert-Reason (Read-Backend (@($records[0]) + $records[2..5])) 'no_active_webviews'

    $records = New-Diagnostics
    $records = @($records[0], $records[1], (New-Attachment 'hwnd' ('b' * 32) 1.5)) + $records[2..5]
    $mixed = Read-Backend $records
    Assert-Reason $mixed 'mixed_backends'
    Assert-Equal $null $mixed.actualBackend 'Mixed hosts never collapse to one backend'
    Assert-Equal 2 $mixed.activeAttachments.Count 'Same native id does not merge independent attachments'

    $records = New-Diagnostics
    $detached = New-Attachment 'composition' ('a' * 32) 1.5; $detached.event = 'detached'
    $records = @($records[0], $records[1], $detached, (New-Attachment 'composition' ('b' * 32) 1.75)) + $records[2..5]
    $replacement = Read-Backend $records
    Assert-Equal 0 $replacement.reasons.Count 'A disposed pre-sampling host is replaced without stale metadata'
    Assert-Equal ('b' * 32) $replacement.activeAttachments[0].attachmentId 'Native id reuse keeps the new lifetime'
    $records[2].utc = $started.AddSeconds(3).ToString('o')
    Assert-Reason (Read-Backend $records) 'host_set_changed_during_sampling'
    $records = New-Diagnostics
    Assert-Reason (Read-Backend (@($records[0], $records[1], $records[1]) + $records[2..5])) 'duplicate_attachment'

    $records = New-Diagnostics
    [void](Read-Backend $records)
    Add-Content -LiteralPath $path -Value '{"truncated":' -Encoding utf8
    $invalid = Read-WebViewHostingBackend -Path $path -RunId 'run-a' -RootProcessId 10 -RootStartedUtc $started `
        -SampleStartedUtc $started.AddSeconds(2.5) -SampleEndedUtc $started.AddSeconds(4.5) -RequestedBackend composition
    Assert-Reason $invalid 'diagnostics_unreadable_or_invalid'
    $missing = Read-WebViewHostingBackend -Path (Join-Path $directory 'missing.jsonl') -RunId 'run-a' -RootProcessId 10 -RootStartedUtc $started `
        -SampleStartedUtc $started.AddSeconds(2.5) -SampleEndedUtc $started.AddSeconds(4.5) -RequestedBackend composition
    Assert-Reason $missing 'diagnostics_unreadable_or_invalid'

    function New-Trial($Backend, [int]$Number) {
        return [pscustomobject]@{
            complete = $true; setupConfirmed = $true; backend = $Backend
            runId = "run-$Number"; processId = $Number; startedUtc = "start-$Number"
            executableSha256 = 'same-build'; scenario = 'same-workload'; displaySetup = 'same-DPI'
        }
    }
    $left = New-Trial $composition 1; $right = New-Trial $hwnd 2
    $pair = Get-WebViewHostingComparison @($left, $right)
    Assert-Equal $true $pair.comparisonReady 'Only verified different modes with matching setup are comparable'
    Assert-Equal $null $pair.performanceConclusion 'Readiness never invents a performance winner'
    $left.backend = $fallback
    Assert-Equal $false (Get-WebViewHostingComparison @($left, $right)).comparisonReady 'HWND versus HWND is not an A/B comparison'
    $left.backend = $legacy
    Assert-Equal $false (Get-WebViewHostingComparison @($left, $right)).comparisonReady 'Missing metadata keeps the pair noncomparable'
    $left.backend = $invalid
    Assert-Equal $false (Get-WebViewHostingComparison @($left, $right)).comparisonReady 'A truncated diagnostics file cannot make a comparable pair'
    $left.backend = $missing
    Assert-Equal $false (Get-WebViewHostingComparison @($left, $right)).comparisonReady 'An absent diagnostics file remains an explicit noncomparable result'
    $left.backend = $composition; $left.setupConfirmed = $false
    Assert-Equal $false (Get-WebViewHostingComparison @($left, $right)).comparisonReady 'Unconfirmed manual setup is not accepted'
    $left.setupConfirmed = 'false'
    Assert-Equal $false (Get-WebViewHostingComparison @($left, $right)).comparisonReady 'A string cannot forge boolean setup confirmation'
    $left.setupConfirmed = $true; $left.complete = $false
    Assert-Equal $false (Get-WebViewHostingComparison @($left, $right)).comparisonReady 'Incomplete raw trials cannot be compared'
    $left.complete = $true; $right.displaySetup = 'different-DPI'
    Assert-Equal $false (Get-WebViewHostingComparison @($left, $right)).comparisonReady 'Different DPI/workload descriptions are rejected'
    $right.displaySetup = 'same-DPI'; $right.runId = $left.runId
    Assert-Equal $false (Get-WebViewHostingComparison @($left, $right)).comparisonReady 'A reused run identity is rejected'
    $right.runId = 'run-2'; $right.backend.setup = @('different-viewport')
    Assert-Equal $false (Get-WebViewHostingComparison @($left, $right)).comparisonReady 'Different native viewport observations are rejected'
    $right.backend.setup = $left.backend.setup; $right.backend.collectionMetadata.buildMode = 'debug'
    Assert-Equal $false (Get-WebViewHostingComparison @($left, $right)).comparisonReady 'Debug measurements are not compared with profile'
    $right.backend.collectionMetadata.buildMode = 'profile'; $right.backend.collectionMetadata.flutterVersion = 'unavailable'
    Assert-Equal $false (Get-WebViewHostingComparison @($left, $right)).comparisonReady 'Missing Flutter version keeps the pair noncomparable'
} finally {
    [System.IO.Directory]::Delete($directory, $true)
}
Write-Host "WebView hosting probe unit tests passed: $script:assertions assertions."
