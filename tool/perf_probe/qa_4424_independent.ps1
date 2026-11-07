#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$source = 'f7b03818cb9fc4476505dced02088063033d2e51'
$sourceTree = '3dd1c042150dddf57158031cbe235b3b5d7fbabe'
$out = [IO.Path]::GetFullPath($env:QA_EVIDENCE_DIR)
if (Test-Path -LiteralPath $out) { throw 'QA evidence directory must be fresh.' }
[IO.Directory]::CreateDirectory($out) | Out-Null
$expected = @'
[{"path":"tool/perf_probe/installed_plugin_windows_lifetime.cs","sha256":"e373e8b5dcd6a17d925e52249050d9e99d0c0c1a04fa59523e8b1f86b30e4b15","bytes":19764},{"path":"tool/perf_probe/test_installed_plugin_windows_lifetime.cs","sha256":"bc93f45dbbd1646dd59a08c43f7e5f1f6c3a75a69345060dea610f766c930c04","bytes":15375},{"path":"pubspec.yaml","sha256":"b900e75318dfb65333f97e8529c52dfe08df0893292e535700094da7ae8c6b51","bytes":13609},{"path":"pubspec.lock","sha256":"94bf01c88e2568424d39a7da767ecdd70356c915f8636e0ccb233121bb6ef932","bytes":66487},{"path":"integration_test/support/installed_plugin_windows_lifetime.dart","sha256":"d896f1580440e1fe726595b8d0afc64046a6480cbb0a949cf9a04c009c8a8173","bytes":3701},{"path":".github/workflows/installed_plugin_probe.yml","sha256":"382f4f78f9b41fde647162d1058bec60d4df4ea4ad85cd48610cded77753b6d3","bytes":7040},{"path":"tool/perf_probe/installed_plugin_windows_control.psm1","sha256":"dea8243fa148fc09168e0833ac36b77fac03486e0657d478b545c672d0d23d5f","bytes":10454},{"path":"tool/perf_probe/installed_plugin_windows_exit.psm1","sha256":"24140aa825be6d5c8b571a1798048a503a9909836222ee889843539f7ac335d7","bytes":15700},{"path":"tool/perf_probe/test_installed_plugin_windows_runner.ps1","sha256":"9f732afcc8093933db9402de470a1f34d0e55289c398589efecc616e5adc8b93","bytes":12152},{"path":"tool/perf_probe/installed_plugin_windows_runner.psm1","sha256":"205ccece2043181621a9dae1a98db59d6df76b93b788a48e57cb3afc66c6e462","bytes":10724},{"path":"tool/perf_probe/run_installed_plugin_windows.ps1","sha256":"edd23bafd7dd24ad7ffc4d090197610eed43c392e0050bc0b737fc8e4c7c0569","bytes":586},{"path":"integration_test/installed_plugin_resource_probe_test.dart","sha256":"4f03d7f8f7a2cb94ed79590af5995b9f146077cceb7f49d688c41dceaf9d642e","bytes":53896},{"path":"tool/perf_probe/WEBVIEW_RESOURCE_PROBE.md","sha256":"f97230e81069bf3799f0229999c649c0e7f4a5c4fd23890c39030f8e4ef58fc3","bytes":45250},{"path":"test/tool/perf_probe/installed_plugin_windows_lifetime_test.dart","sha256":"d4e648a679ef3f580b718e2323a182c75312648eefcece6cd0aab0dcb6fb44a5","bytes":6464},{"path":"tool/perf_probe/test_installed_plugin_windows_control.ps1","sha256":"157dff260b0c608be395193a8dde2d0821b45f029e82b8315ae8db2b5fe5a1da","bytes":12208},{"path":"tool/perf_probe/test_installed_plugin_windows_exit.ps1","sha256":"9741fb220c71af1b11580ea28a73a12abd02d3e896663fafa17c64f8c4d688c8","bytes":19069}]
'@ | ConvertFrom-Json -AsHashtable
$qaResults = [Collections.Generic.List[object]]::new()
function Assert-Qa([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Save-Qa([string]$Name, $Value) {
    [IO.File]::WriteAllText((Join-Path $out $Name), ($Value | ConvertTo-Json -Depth 40), [Text.UTF8Encoding]::new($false))
}
function Run-Qa([string]$Name, [scriptblock]$Body) {
    $item = @{ name = $Name; passed = $false; startedAtUtc = [datetime]::UtcNow; error = $null }
    try { & $Body; $item.passed = $true; Write-Host "QA PASS $Name" }
    catch { $item.error = $_.ToString(); $item.stack = $_.ScriptStackTrace; Write-Host "QA FAIL $Name : $_" }
    finally { $item.finishedAtUtc = [datetime]::UtcNow; $qaResults.Add($item); Save-Qa 'cases-partial.json' $qaResults.ToArray() }
}
function Read-Source-State {
    $state = @{ status = @(git status --porcelain=v1); files = @() }
    if ($LASTEXITCODE -ne 0) { throw 'git status failed.' }
    foreach ($entry in $expected) {
        $file = Get-Item -LiteralPath $entry.path
        $sha = (Get-FileHash -LiteralPath $entry.path -Algorithm SHA256).Hash.ToLowerInvariant()
        $state.files += @{ path = $entry.path; bytes = $file.Length; sha256 = $sha }
        Assert-Qa ($file.Length -eq $entry.bytes -and $sha -ceq $entry.sha256) "Candidate byte mismatch: $($entry.path)"
    }
    return $state
}
$qaHead = (git rev-parse HEAD).Trim()
$actualSourceTree = (git rev-parse ($source + '^{tree}')).Trim()
Assert-Qa ($actualSourceTree -ceq $sourceTree) 'Candidate tree mismatch.'
$qaPaths = @(git diff --name-only $source HEAD)
Assert-Qa ($qaPaths.Count -eq 2 -and $qaPaths -contains '.github/workflows/qa_4424_independent.yml' -and $qaPaths -contains 'tool/perf_probe/qa_4424_independent.ps1') 'QA commit must add only the two declared QA files.'
$before = Read-Source-State
Assert-Qa ($before.status.Count -eq 0) 'Initial source worktree is not clean.'
Save-Qa 'before.json' $before
$modulePath = [IO.Path]::GetFullPath('tool/perf_probe/installed_plugin_windows_exit.psm1')
Start-Transcript -Path (Join-Path $out 'transcript.txt') | Out-Null
try {
    Run-Qa 'Parse every frozen PowerShell source' {
        foreach ($entry in $expected) {
            if ($entry.path -match '\.ps(m)?1$') {
                $tokens = $null; $parseErrors = $null
                [Management.Automation.Language.Parser]::ParseFile([IO.Path]::GetFullPath($entry.path), [ref]$tokens, [ref]$parseErrors) | Out-Null
                Assert-Qa (@($parseErrors).Count -eq 0) ("PowerShell parse failed: " + $entry.path + ': ' + ($parseErrors | Out-String))
            }
        }
    }
    Run-Qa 'Frozen control suite in shared process' {
        & ./tool/perf_probe/test_installed_plugin_windows_control.ps1
        Assert-Qa ($LASTEXITCODE -eq 0) 'Control suite exit failed.'
    }
    Run-Qa 'Frozen runner suite in shared process' {
        & ./tool/perf_probe/test_installed_plugin_windows_runner.ps1
        Assert-Qa ($LASTEXITCODE -eq 0) 'Runner suite exit failed.'
    }
    Run-Qa 'Frozen exit suite and production native child gate' {
        $nativeReceipt = Join-Path $out 'native-control.json'
        & ./tool/perf_probe/test_installed_plugin_windows_exit.ps1 -NativeControlReportPath $nativeReceipt
        Assert-Qa ($LASTEXITCODE -eq 0) 'Exit suite exit failed.'
        $native = Get-Content -LiteralPath $nativeReceipt -Raw | ConvertFrom-Json -AsHashtable
        Assert-Qa ($native.status -ceq 'passed' -and $native.child.exitCode -eq 37) 'Native control must actually pass and exit 37.'
        Assert-Qa ($native.trace.nativeAdapter -ceq 'InstalledPluginProbe.WindowsProcessFactory') 'Native control used a controlled process adapter.'
    }
    Run-Qa 'Independent real driver exit 37 with compound raw and console failures' {
        if (-not ('QaDisposedStreamWriter' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
public sealed class QaDisposedStreamWriter : StreamWriter {
    public QaDisposedStreamWriter(Stream stream) : base(stream, new UTF8Encoding(false)) {}
    public override void WriteLine(string value) {
        BaseStream.Dispose();
        base.WriteLine(value);
    }
}
'@
        }
        $childPath = Join-Path $out 'io-child.ps1'
        $marker = Join-Path $out 'io-child-completed.txt'
        [IO.File]::WriteAllText($childPath, '[Console]::Out.WriteLine("first"); [Console]::Error.WriteLine("second"); [Console]::Out.WriteLine("third"); [IO.File]::WriteAllText($args[0], "completed before exit 37"); exit 37', [Text.UTF8Encoding]::new($false))
        $module = Import-Module $modulePath -Force -PassThru
        try {
            & $module {
                $script:QaConsoleAttempts = 0
                function script:New-InstalledPluginLogWriter { param([IO.Stream]$Stream) return [QaDisposedStreamWriter]::new($Stream) }
                function script:Write-Host { param($Value) $script:QaConsoleAttempts++; throw [IO.IOException]::new('QA controlled console sink closed') }
            }
            $logged = Invoke-InstalledPluginLoggedCommand -Command (Join-Path $PSHOME 'pwsh.exe') -Arguments @('-NoLogo', '-NoProfile', '-File', $childPath, $marker) -LogPath (Join-Path $out 'compound-io.log')
            $attempts = & $module { $script:QaConsoleAttempts }
            Save-Qa 'compound-io.json' @{ result = $logged; consoleAttempts = $attempts; childMarker = $(if (Test-Path -LiteralPath $marker) { [IO.File]::ReadAllText($marker) } else { $null }) }
            Assert-Qa ($logged.exitCode -eq 37) 'Compound log/console failures replaced real native exit 37.'
            Assert-Qa ($attempts -ge 3) 'Not all real child output was drained through the failing console.'
            Assert-Qa ([IO.File]::ReadAllText($marker) -ceq 'completed before exit 37') 'Native child did not reach its final marker.'
            Assert-Qa (-not [string]::IsNullOrWhiteSpace($logged.error)) 'Compound sink failure was not retained.'
        } finally { Remove-Module $module }
    }
    $nativeChildPath = Join-Path $out 'independent-native-child.ps1'
    [IO.File]::WriteAllText($nativeChildPath, @'
param([string]$ModulePath, [string]$ReportPath, [string]$Mode)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$record = @{ pid = $PID; mode = $Mode; acknowledged = $false; error = $null; actualCreationFileTime = $null; ack = $null }
$client = $null
$cancellation = $null
$childExit = 23
try {
    Import-Module $ModulePath
    $identity = [InstalledPluginProbe.WindowsProcess]::CurrentIdentity()
    $record.actualCreationFileTime = $identity.CreationFileTime.ToString([Globalization.CultureInfo]::InvariantCulture)
    $creation = $identity.CreationFileTime
    if ($Mode -ceq 'wrong-native-tick') { $creation++ }
    $micros = [long](([datetime]::UtcNow.Ticks - [datetime]::UnixEpoch.Ticks) / 10)
    $runId = "$PID-$micros"
    $token = $env:QA_TOKEN
    if ($Mode -ceq 'wrong-authentication') {
        $token = $(if ($token[0] -eq 'a') { 'b' } else { 'a' }) + $token.Substring(1)
    }
    $hello = @{
        version = 1; kind = 'hello'; campaignId = $env:QA_CAMPAIGN
        token = $token; pid = $PID; runId = $runId
        creationFileTime = $creation.ToString([Globalization.CultureInfo]::InvariantCulture)
    }
    $client = [Net.Sockets.TcpClient]::new()
    $cancellation = [Threading.CancellationTokenSource]::new(15000)
    $client.ConnectAsync([Net.IPAddress]::Loopback, [int]$env:QA_PORT, $cancellation.Token).AsTask().GetAwaiter().GetResult() | Out-Null
    $stream = $client.GetStream()
    $bytes = [Text.Encoding]::UTF8.GetBytes(($hello | ConvertTo-Json -Compress))
    $stream.Write($bytes, 0, $bytes.Length)
    $client.Client.Shutdown([Net.Sockets.SocketShutdown]::Send)
    $response = [InstalledPluginProbe.LifetimeObserver]::ReadBoundedAsync($stream, $cancellation.Token).GetAwaiter().GetResult()
    $ack = [Text.Encoding]::UTF8.GetString($response) | ConvertFrom-Json -AsHashtable
    if ($ack.kind -cne 'ready' -or $ack.version -ne 1 -or $ack.pid -ne $PID -or $ack.runId -cne $runId -or
        $ack.campaignId -cne $hello.campaignId -or $ack.token -cne $hello.token -or
        $ack.creationFileTime -cne $hello.creationFileTime -or $ack.bootstrapQuiescent -ne $true) {
        throw 'Independent child received a mismatched acknowledgement.'
    }
    $ack.Remove('token')
    $record.ack = $ack
    $record.acknowledged = $true
    $childExit = 37
} catch { $record.error = $_.ToString() }
finally {
    if ($null -ne $client) { $client.Dispose() }
    if ($null -ne $cancellation) { $cancellation.Dispose() }
    [IO.File]::WriteAllText($ReportPath, ($record | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
}
exit $childExit
'@, [Text.UTF8Encoding]::new($false))
    foreach ($mode in @('exact-native-lifetime', 'wrong-native-tick', 'wrong-authentication')) {
        Run-Qa "Independent production WindowsProcessFactory: $mode" {
            Import-Module $modulePath -Force
            $executable = Join-Path $PSHOME 'pwsh.exe'
            $campaign = [guid]::NewGuid().ToString('N')
            $token = [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32)).ToLowerInvariant()
            $observer = $null
            $child = [Diagnostics.Process]::new()
            $started = $false
            $childReportPath = Join-Path $out "$mode-child.json"
            try {
                $observer = Start-InstalledPluginLifetimeObserver -Executable $executable -CampaignId $campaign -Token $token -StartupTimeoutMilliseconds 20000
                $child.StartInfo = [Diagnostics.ProcessStartInfo]::new($executable)
                $child.StartInfo.UseShellExecute = $false
                $child.StartInfo.Environment['QA_PORT'] = $observer.Port.ToString()
                $child.StartInfo.Environment['QA_CAMPAIGN'] = $campaign
                $child.StartInfo.Environment['QA_TOKEN'] = $token
                foreach ($argument in @('-NoLogo', '-NoProfile', '-File', $nativeChildPath, $modulePath, $childReportPath, $mode)) {
                    $child.StartInfo.ArgumentList.Add($argument)
                }
                $started = $child.Start()
                Assert-Qa $started 'Independent child failed to start.'
                $ownedPid = $child.Id
                Assert-Qa ($child.WaitForExit(25000)) 'Independent child exceeded its bounded timeout.'
                $childExit = $child.ExitCode
                $trace = Stop-InstalledPluginLifetimeObserver -Observer $observer -ExitTimeoutMilliseconds 1000
                Save-Qa "$mode-trace.json" $trace
                $childReport = Get-Content -LiteralPath $childReportPath -Raw | ConvertFrom-Json -AsHashtable
                Assert-Qa ($childReport.pid -eq $ownedPid) 'Child report PID does not identify the owned native child.'
                Assert-Qa ($trace.nativeAdapter -ceq 'InstalledPluginProbe.WindowsProcessFactory') 'Independent control did not use the production native adapter.'
                foreach ($field in @('listenerStopped', 'channelClosed', 'bootstrapTaskCompleted')) {
                    Assert-Qa ([bool]$trace.cleanup[$field]) "Bootstrap cleanup missing: $field"
                }
                if ($mode -ceq 'exact-native-lifetime') {
                    Assert-Qa ($childExit -eq 37 -and $childReport.acknowledged -eq $true) 'Exact native lifetime did not receive and accept its acknowledgement.'
                    Assert-Qa ($trace.availability -ceq 'collected' -and $trace.exitStatus -eq 37) 'Actual retained handle did not collect native exit 37.'
                    Assert-Qa ($trace.identity.pid -eq $ownedPid -and $trace.identity.creationFileTime -ceq $childReport.actualCreationFileTime) 'Retained native identity does not match the exact child FILETIME and PID.'
                    Assert-Qa ($trace.cleanup.handleAcquired -and $trace.cleanup.handleClosed -and $trace.identityVerified) 'Accepted native handle was not verified and closed.'
                } else {
                    Assert-Qa ($childExit -eq 23 -and $childReport.acknowledged -eq $false) 'Invalid native hello was acknowledged.'
                    Assert-Qa ($trace.availability -ceq 'unavailable' -and $null -eq $trace.exitStatus -and $trace.errors.Count -gt 0) 'Invalid native hello produced accepted exit evidence.'
                    if ($mode -ceq 'wrong-native-tick') {
                        Assert-Qa ($trace.identity.creationFileTime -ceq $childReport.actualCreationFileTime) 'Negative native FILETIME control did not interrogate the actual child handle.'
                        Assert-Qa ($trace.cleanup.handleAcquired -and $trace.cleanup.handleClosed -and -not $trace.identityVerified) 'Wrong native FILETIME did not fail closed and release the actual acquired handle.'
                    } else {
                        Assert-Qa (-not $trace.cleanup.handleAcquired) 'Authentication failure opened a native handle.'
                    }
                }
            } finally {
                if ($started -and -not $child.HasExited) { $child.Kill($true); $child.WaitForExit(5000) | Out-Null }
                if ($null -ne $observer) { $observer.Dispose() }
                $child.Dispose()
                Get-Module installed_plugin_windows_exit | Remove-Module
            }
        }
    }
} finally {
    $sourceUnchanged = $false
    $sourceError = $null
    try {
        $after = Read-Source-State
        Save-Qa 'after.json' $after
        Assert-Qa ($after.status.Count -eq 0) 'QA modified tracked or untracked application worktree files.'
        $sourceUnchanged = $true
    } catch { $sourceError = $_.ToString() }
    $summary = @{
        schemaVersion = 1; sourceCommit = $source; sourceTree = $sourceTree; qaHead = $qaHead
        finishedAtUtc = [datetime]::UtcNow; sourceUnchanged = $sourceUnchanged; sourceError = $sourceError
        cases = $qaResults.ToArray(); fullApplicationAcceptance = 'NOT_RUN_BY_THIS_JOB'
        historicalLocalResultsUsed = $false; nativeAdapterRequired = 'InstalledPluginProbe.WindowsProcessFactory'
    }
    Save-Qa 'summary.json' $summary
    Write-Host 'BEGIN_QA_4424_SUMMARY'
    Write-Host ($summary | ConvertTo-Json -Depth 30 -Compress)
    Write-Host 'END_QA_4424_SUMMARY'
    Stop-Transcript | Out-Null
}
if (-not $sourceUnchanged -or @($qaResults | Where-Object { -not $_.passed }).Count -gt 0) { exit 1 }
exit 0
