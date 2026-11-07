#Requires -Version 7.0
param([string]$NativeControlReportPath)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not ('InstalledPluginProbe.LifetimeObserverControls' -as [type])) {
    Add-Type -Path @((Join-Path $PSScriptRoot 'installed_plugin_windows_lifetime.cs'),
        (Join-Path $PSScriptRoot 'test_installed_plugin_windows_lifetime.cs'))
}
$exitModulePath = Join-Path $PSScriptRoot 'installed_plugin_windows_exit.psm1'
$controlModulePath = Join-Path $PSScriptRoot 'installed_plugin_windows_control.psm1'
Import-Module $exitModulePath -Force
$script:assertions = 0
function Assert-Equal($Expected, $Actual, [string]$Message) {
    $script:assertions++
    if ($Expected -cne $Actual) { throw "$Message; expected=$Expected actual=$Actual" }
}
$script:armed = [datetime]::Parse('2026-11-07T00:00:00Z').ToUniversalTime()
$script:created = $script:armed.AddSeconds(1).ToFileTimeUtc()
function New-Trace {
    $bootstrap = $script:armed.AddSeconds(2)
    $micros = [long](($bootstrap.Ticks - [datetime]::UnixEpoch.Ticks) / 10)
    return @{
        availability = 'collected'; errors = @(); campaignId = ('a' * 32); runId = "42-$micros"
        armedAtUtc = $script:armed; bootstrapUtc = $bootstrap; acknowledgedAtUtc = $bootstrap.AddMilliseconds(1)
        finishedAtUtc = $script:armed.AddSeconds(4); processName = 'otzaria.exe'
        bootstrapQuiescent = $true; identityVerified = $true
        identity = @{ pid = 42; creationFileTime = $script:created.ToString(); executable = 'C:\probe\otzaria.exe' }
        exitStatus = [uint32]0; exitFileTime = $script:armed.AddSeconds(3).ToFileTimeUtc().ToString(); waitResult = 0
        cleanup = @{ handleAcquired = $true; handleClosed = $true; listenerStopped = $true; channelClosed = $true; bootstrapTaskCompleted = $true }
    }
}
function New-Report($Trace) {
    return @{
        pid = 42; runId = $Trace.runId; platform = 'windows'; buildMode = 'profile'
        status = 'passed'; errors = @(); testFailures = @()
        windowsLifetime = @{
            version = 1; kind = 'ready'; campaignId = $Trace.campaignId; pid = 42; runId = $Trace.runId
            creationFileTime = $Trace.identity.creationFileTime; executable = $Trace.identity.executable
            acknowledgedAtUtc = $Trace.acknowledgedAtUtc; bootstrapQuiescent = $true
        }
    }
}
function Assert-RejectedEvidence([string]$Label, [scriptblock]$Change) {
    $trace = New-Trace; $report = New-Report $trace
    & $Change $trace $report
    $evidence = Get-InstalledPluginExitEvidence -Trace $trace -Report $report
    Assert-Equal 'unavailable' $evidence.availability $Label
    Assert-Equal $true (-not [string]::IsNullOrWhiteSpace($evidence.reason)) "$Label retains its failure reason"
}
function New-ApplicationEvent {
    param([uint32]$ProcessNumber = 42, [long]$Creation = $script:created,
        [string]$Executable = 'C:\probe\otzaria.exe',
        [datetime]$Utc = $script:armed.AddSeconds(3))
    $pidText = '0x{0:x}' -f $ProcessNumber
    $creationText = '0x{0:x}' -f $Creation
    $pathText = [Security.SecurityElement]::Escape($Executable)
    $timeText = $Utc.ToUniversalTime().ToString('o')
    return @"
<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event">
<System><Provider Name="Application Error"/><EventID>1000</EventID><TimeCreated SystemTime="$timeText"/></System>
<EventData><Data Name="AppName">otzaria.exe</Data><Data Name="AppPath">$pathText</Data>
<Data Name="ProcessId">$pidText</Data><Data Name="ProcessCreationTime">$creationText</Data>
<Data Name="ExceptionCode">c0000005</Data><Data Name="ModuleName">native.dll</Data>
<Data Name="ModulePath">C:\probe\native.dll</Data><Data Name="FaultingOffset">0</Data>
<Data Name="IntegratorReportId">controlled-report</Data></EventData></Event>
"@
}
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('installed-exit-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporary | Out-Null
try {
    $protocol = [InstalledPluginProbe.LifetimeObserverControls]::Run() | ConvertFrom-Json -AsHashtable
    Assert-Equal 29 $protocol.outcomes.Count 'All controlled native protocol cases ran'
    Assert-Equal $true ($protocol.assertions -ge 200) 'Protocol controls execute their detailed assertions'
    Write-Host ($protocol | ConvertTo-Json -Depth 10 -Compress)

    $trace = New-Trace; $report = New-Report $trace
    $evidence = Get-InstalledPluginExitEvidence $trace $report
    Assert-Equal 'collected' $evidence.availability 'Exact acknowledged lifetime is accepted'
    Assert-Equal 42 $evidence.processId 'Native PID is retained'
    Assert-Equal $script:created.ToString() $evidence.creationFileTime 'Native FILETIME is retained exactly'
    Assert-Equal '0x00000000' $evidence.exitStatusHex 'Native exit zero stays explicit'
    $trace.exitStatus = [uint32]3221225477
    $unsigned = Get-InstalledPluginExitEvidence $trace $report
    Assert-Equal ([uint32]3221225477) $unsigned.exitStatus 'NTSTATUS is preserved unsigned'
    Assert-Equal '0xC0000005' $unsigned.exitStatusHex 'NTSTATUS hexadecimal representation is preserved'

    Assert-RejectedEvidence 'Missing native observation fails' { param($t, $r) $t.availability = 'unavailable' }
    Assert-RejectedEvidence 'Native errors fail' { param($t, $r) $t.errors = @('native query failed') }
    Assert-RejectedEvidence 'Unverified identity fails' { param($t, $r) $t.identityVerified = $false }
    Assert-RejectedEvidence 'Unfinished bootstrap fails' { param($t, $r) $t.bootstrapQuiescent = $false }
    Assert-RejectedEvidence 'A native wait timeout fails' { param($t, $r) $t.waitResult = 258 }
    foreach ($field in @('handleAcquired', 'handleClosed', 'listenerStopped', 'channelClosed', 'bootstrapTaskCompleted')) {
        $trace = New-Trace; $report = New-Report $trace; $trace.cleanup[$field] = $false
        Assert-Equal 'unavailable' (Get-InstalledPluginExitEvidence $trace $report).availability "Missing cleanup $field fails"
    }
    Assert-RejectedEvidence 'Foreign platform fails' { param($t, $r) $r.platform = 'linux' }
    Assert-RejectedEvidence 'A non-profile report fails' { param($t, $r) $r.buildMode = 'debug' }
    foreach ($invalidPid in @(0, -1, 42.5, '42', [long]4294967296)) {
        $trace = New-Trace; $report = New-Report $trace; $report.pid = $invalidPid
        Assert-Equal 'unavailable' (Get-InstalledPluginExitEvidence $trace $report).availability 'Invalid report PID fails'
    }
    Assert-RejectedEvidence 'Foreign report PID fails' { param($t, $r) $r.pid = 43 }
    Assert-RejectedEvidence 'Foreign report run fails' { param($t, $r) $r.runId = '43-1794010000000000' }
    Assert-RejectedEvidence 'Missing acknowledgement fails' { param($t, $r) $r.Remove('windowsLifetime') }
    Assert-RejectedEvidence 'Foreign campaign fails' { param($t, $r) $r.windowsLifetime.campaignId = 'b' * 32 }
    Assert-RejectedEvidence 'Foreign acknowledgement run fails' { param($t, $r) $r.windowsLifetime.runId = '43-1794010000000000' }
    Assert-RejectedEvidence 'Foreign acknowledgement PID fails' { param($t, $r) $r.windowsLifetime.pid = 43 }
    Assert-RejectedEvidence 'One native creation tick matters' { param($t, $r) $r.windowsLifetime.creationFileTime = ([long]$t.identity.creationFileTime + 1).ToString() }
    Assert-RejectedEvidence 'Foreign executable fails' { param($t, $r) $r.windowsLifetime.executable = 'C:\foreign\otzaria.exe' }
    Assert-RejectedEvidence 'Unfinished acknowledgement fails' { param($t, $r) $r.windowsLifetime.bootstrapQuiescent = $false }
    Assert-RejectedEvidence 'Foreign acknowledgement instant fails' { param($t, $r) $r.windowsLifetime.acknowledgedAtUtc = $t.acknowledgedAtUtc.AddTicks(1) }
    foreach ($invalidExit in @($null, '0', -1, [long]4294967296)) {
        $trace = New-Trace; $report = New-Report $trace; $trace.exitStatus = $invalidExit
        Assert-Equal 'unavailable' (Get-InstalledPluginExitEvidence $trace $report).availability 'An unobserved or invalid native exit cannot pass'
    }
    Assert-Equal 'unavailable' (Get-InstalledPluginExitEvidence $null $null).availability 'Missing trace and report fail'
    $trace = New-Trace; $report = New-Report $trace
    Assert-Equal 'unavailable' (Get-InstalledPluginExitEvidence $trace $null).availability 'Missing final report fails native acceptance'

    $crashes = @{ availability = 'collected'; truncated = $false; events = @() }
    foreach ($acceptedExit in @([uint32]0, [uint32]::MaxValue)) {
        $trace = New-Trace; $trace.exitStatus = $acceptedExit; $report = New-Report $trace
        $evidence = Get-InstalledPluginExitEvidence $trace $report
        Assert-Equal 0 (Get-InstalledPluginRunExitCode -DriverExitCode 0 -Report $report -ExitEvidence $evidence -ApplicationErrors $crashes) 'Only complete passing evidence accepts normal or Dart termination'
    }
    foreach ($rejectedExit in @(37, 259, [uint32]3221225477)) {
        $trace = New-Trace; $trace.exitStatus = $rejectedExit; $report = New-Report $trace
        $evidence = Get-InstalledPluginExitEvidence $trace $report
        Assert-Equal 1 (Get-InstalledPluginRunExitCode -DriverExitCode 0 -Report $report -ExitEvidence $evidence -ApplicationErrors $crashes) 'Unexpected native statuses cannot pass'
    }
    $trace = New-Trace; $report = New-Report $trace; $evidence = Get-InstalledPluginExitEvidence $trace $report
    Assert-Equal 37 (Get-InstalledPluginRunExitCode -DriverExitCode 37 -Report $null -ExitEvidence @{ availability = 'unavailable' } -DiagnosticErrors @('later error')) 'The original driver exit takes precedence over diagnostic failures'
    Assert-Equal 1 (Get-InstalledPluginRunExitCode -DriverExitCode $null -Report $report -ExitEvidence $evidence -ApplicationErrors $crashes) 'Missing driver exit fails'
    Assert-Equal 1 (Get-InstalledPluginRunExitCode -DriverExitCode 0 -Report $null -ExitEvidence $evidence -ApplicationErrors $crashes) 'Missing framework report fails'
    Assert-Equal 1 (Get-InstalledPluginRunExitCode -DriverExitCode 0 -Report $report -ExitEvidence $evidence -ApplicationErrors $crashes -DiagnosticErrors @('raw I/O failed')) 'Diagnostic errors cannot be hidden by successful native exit'
    foreach ($field in @('errors', 'testFailures')) {
        foreach ($value in @('missing', 'not-array', 'nonempty')) {
            $report = New-Report $trace
            if ($value -eq 'missing') { $report.Remove($field) }
            elseif ($value -eq 'not-array') { $report[$field] = 'none' }
            else { $report[$field] = @('framework failure') }
            Assert-Equal 1 (Get-InstalledPluginRunExitCode -DriverExitCode 0 -Report $report -ExitEvidence $evidence -ApplicationErrors $crashes) 'Framework completion requires explicit empty error and test failure arrays'
        }
    }
    $report = New-Report $trace; $report.status = 'running'
    Assert-Equal 1 (Get-InstalledPluginRunExitCode -DriverExitCode 0 -Report $report -ExitEvidence $evidence -ApplicationErrors $crashes) 'An unfinished framework report cannot pass'
    $report = New-Report $trace
    foreach ($badCrashQuery in @(
        @{ availability = 'unavailable'; truncated = $false; events = @() },
        @{ availability = 'collected'; truncated = $true; events = @() },
        @{ availability = 'collected'; truncated = $false; events = @(@{ exceptionCode = 'c0000005' }) },
        @{ availability = 'collected'; truncated = $false; events = 'none' })) {
        Assert-Equal 1 (Get-InstalledPluginRunExitCode -DriverExitCode 0 -Report $report -ExitEvidence $evidence -ApplicationErrors $badCrashQuery) 'Missing, truncated or correlated crash evidence fails'
    }
    Assert-Equal 1 (Get-InstalledPluginRunExitCode -DriverExitCode 0 -Report $report -ExitEvidence $evidence) 'Crash query evidence is required'

    $events = @(
        (New-ApplicationEvent),
        (New-ApplicationEvent -ProcessNumber 43),
        (New-ApplicationEvent -Creation ($script:created + 1)),
        (New-ApplicationEvent -Creation ($script:created - 1)),
        (New-ApplicationEvent -Executable 'C:\foreign\otzaria.exe'),
        (New-ApplicationEvent -Utc $script:armed.AddSeconds(1)),
        (New-ApplicationEvent -Utc $script:armed.AddSeconds(5)),
        ((New-ApplicationEvent).Replace('Application Error', 'Foreign Provider'))
    )
    $xml = [xml]('<Events>' + ($events -join '') + '</Events>')
    $selected = @(Select-InstalledPluginApplicationErrors -Events $xml -Identity $evidence -ArmedAtUtc $trace.armedAtUtc -FinishedAtUtc $trace.finishedAtUtc)
    Assert-Equal 1 $selected.Count 'Only the exact PID, executable, native creation and bounded event time correlate'
    Assert-Equal 'c0000005' $selected[0].exceptionCode 'Correlated exception details remain available'
    Assert-Equal $script:created $selected[0].processCreatedUtc.ToFileTimeUtc() 'Crash correlation preserves all native creation ticks'
    $trace.availability = 'unavailable'; $trace.errors = @('exit observation failed')
    $partialIdentity = Get-InstalledPluginExitEvidence $trace $null
    Assert-Equal 'unavailable' $partialIdentity.availability 'Partial identity never pretends to prove exit'
    Assert-Equal 42 $partialIdentity.processId 'Verified startup identity survives a missing final report'
    Assert-Equal $script:created.ToString() $partialIdentity.creationFileTime 'Partial crash correlation retains native creation'
    $partialEvents = @(Select-InstalledPluginApplicationErrors -Events $xml -Identity $partialIdentity -ArmedAtUtc $trace.armedAtUtc -FinishedAtUtc $trace.finishedAtUtc)
    Assert-Equal 1 $partialEvents.Count 'Missing final report does not erase a verifiable correlated crash'
    if (-not $IsWindows) {
        $unavailable = Read-InstalledPluginApplicationErrors -Trace $trace -Identity $partialIdentity
        Assert-Equal 'unavailable' $unavailable.availability 'A missing Windows event provider is unavailable, never an empty success'
    }

    $pwsh = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
    $childScript = Join-Path $temporary 'logged-child.ps1'
    [IO.File]::WriteAllText($childScript, @'
[IO.File]::WriteAllText($args[0], 'owned child started')
[Console]::Out.WriteLine('stdout-first')
[Console]::Error.WriteLine('stderr-middle')
[Console]::Out.WriteLine('stdout-last')
exit 37
'@)
    $marker = Join-Path $temporary 'logged-child-started.txt'
    $log = Join-Path $temporary 'native.log'
    $logged = Invoke-InstalledPluginLoggedCommand -Command $pwsh -Arguments @('-NoLogo', '-NoProfile', '-File', $childScript, $marker) -LogPath $log
    Assert-Equal 37 $logged.exitCode 'The actual native child exit is retained'
    Assert-Equal $null $logged.error 'Successful raw logging has no diagnostic error'
    $rawLog = [IO.File]::ReadAllText($log)
    foreach ($line in @('stdout-first', 'stderr-middle', 'stdout-last')) {
        Assert-Equal $true $rawLog.Contains($line) 'Both native output streams are preserved'
    }
    Remove-Item -LiteralPath $marker
    $collision = Invoke-InstalledPluginLoggedCommand -Command $pwsh -Arguments @('-NoLogo', '-NoProfile', '-File', $childScript, $marker) -LogPath $log
    Assert-Equal $null $collision.exitCode 'A raw log collision prevents launch'
    Assert-Equal $true ($null -ne $collision.error) 'A raw log collision remains explicit'
    Assert-Equal $false (Test-Path -LiteralPath $marker) 'A colliding raw log cannot launch the child'
    Assert-Equal $rawLog ([IO.File]::ReadAllText($log)) 'Earlier raw logs are immutable'

    foreach ($mode in @('writer-error', 'console-error')) {
        $module = Import-Module $exitModulePath -Force -PassThru
        try {
            & $module {
                param($Mode)
                if ($Mode -eq 'writer-error') {
                    function script:New-InstalledPluginLogWriter {
                        param([IO.Stream]$Stream)
                        return [InstalledPluginProbe.ControlledLogWriter]::new($Stream)
                    }
                } else {
                    function script:Write-Host { param($Object) throw 'controlled console output failure' }
                }
            } $mode
            $failureLog = Join-Path $temporary "$mode.log"
            $result = Invoke-InstalledPluginLoggedCommand -Command $pwsh -Arguments @('-NoLogo', '-NoProfile', '-File', $childScript, $marker) -LogPath $failureLog
            Assert-Equal 37 $result.exitCode 'Diagnostic failures do not interrupt draining or replace actual child exit'
            Assert-Equal $true $result.error.Contains($(if ($mode -eq 'writer-error') { 'controlled raw writer failure' } else { 'controlled console output failure' })) 'The first output failure remains explicit'
            if ($mode -eq 'console-error') {
                Assert-Equal $true ([IO.File]::ReadAllText($failureLog)).Contains('stdout-last') 'Raw log continues after console output failure'
            }
        } finally { Remove-Module $module }
    }
    Import-Module $exitModulePath -Force

    if ($IsWindows) {
        $nativeDirectory = Join-Path $temporary 'native-child'
        New-Item -ItemType Directory -Path $nativeDirectory | Out-Null
        if ([string]::IsNullOrWhiteSpace($NativeControlReportPath)) {
            $NativeControlReportPath = Join-Path $temporary 'native-exit-control.json'
        }
        Import-Module $controlModulePath -Force
        $native = Invoke-InstalledPluginExitControl -Directory $nativeDirectory -ReportPath $NativeControlReportPath
        Assert-Equal 'passed' $native.status 'Real Windows owned child control passed'
        Assert-Equal 37 $native.child.exitCode 'The owned native child actually exited 37'
        Assert-Equal 'InstalledPluginProbe.WindowsProcessFactory' $native.trace.nativeAdapter 'The native gate uses the production Windows adapter'
        Assert-Equal 'collected' $native.observation.availability 'The exact retained native handle proves exit'
        Assert-Equal 37 $native.observation.exitStatus 'Retained native exit matches the real child exit'
        Assert-Equal $native.child.pid $native.observation.processId 'Native evidence belongs to the owned child'
        Assert-Equal $true $native.trace.cleanup.handleClosed 'The actual native handle closes before evidence acceptance'
        Assert-Equal $true $native.cleanup.childExited 'No owned child remains after the native gate'
        Assert-Equal $true $native.cleanup.observerDisposed 'The real native observer is disposed'
        Assert-Equal 0 $native.cleanup.errors.Count 'Native cleanup has no diagnostic failures'
        Write-Host "PASS real Windows retained lifetime: exit 37; receipt $NativeControlReportPath"
    } else {
        Write-Host 'NOT_RUN real Windows retained lifetime: this host is not Windows.'
    }
} finally {
    Get-Module installed_plugin_windows_control | Remove-Module
    Get-Module installed_plugin_windows_exit | Remove-Module
    Remove-Item -LiteralPath $temporary -Recurse -Force
}
Write-Host "Passed $script:assertions exit contract assertions plus $($protocol.assertions) C# protocol assertions."
exit 0
