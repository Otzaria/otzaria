#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'webview_hosting_probe.psm1') -Force
function Assert-Equal($Expected, $Actual, [string]$Message) {
    if ($Expected -cne $Actual) { throw "$Message; expected=$Expected actual=$Actual" }
}
function Assert-Throws([scriptblock]$Action, [string]$Pattern, [string]$Message) {
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
    $forced = New-WebViewHostingStartInfo -Executable $executable -Mode hwnd
    $normal = New-WebViewHostingStartInfo -Executable $executable -Mode default
    Assert-Equal '1' $forced.Environment[$variable] 'HWND set only for the child'
    Assert-Equal $false $normal.Environment.ContainsKey($variable) 'Default must clear an inherited force flag'
    Assert-Equal 'parent-value' ([System.Environment]::GetEnvironmentVariable($variable, 'Process')) 'Parent environment is unchanged'
    Assert-Equal '--dev-diagnostics=log' $forced.ArgumentList[0] 'Arguments are not shell text'
    Assert-Equal $false $forced.UseShellExecute 'No shell interpolation'
} finally {
    [System.Environment]::SetEnvironmentVariable($variable, $original, 'Process')
}
Write-Host 'WebView hosting probe unit tests passed.'
