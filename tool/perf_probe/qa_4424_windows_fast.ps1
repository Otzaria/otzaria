#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$source = '05e150d09758e0da45ca1877a4d650358f1aa17f'
$sourceTree = 'e43bd8f0db6d1b2a107f767c18e3261a27e15837'
$out = [IO.Path]::GetFullPath($env:QA_EVIDENCE_DIR)
if (Test-Path -LiteralPath $out) { throw 'QA evidence directory must be fresh.' }
[IO.Directory]::CreateDirectory($out) | Out-Null
$expected = @'
[{"path":"tool/perf_probe/installed_plugin_windows_lifetime.cs","sha256":"e373e8b5dcd6a17d925e52249050d9e99d0c0c1a04fa59523e8b1f86b30e4b15","bytes":19764},{"path":"tool/perf_probe/test_installed_plugin_windows_lifetime.cs","sha256":"bc93f45dbbd1646dd59a08c43f7e5f1f6c3a75a69345060dea610f766c930c04","bytes":15375},{"path":"pubspec.yaml","sha256":"b900e75318dfb65333f97e8529c52dfe08df0893292e535700094da7ae8c6b51","bytes":13609},{"path":"pubspec.lock","sha256":"94bf01c88e2568424d39a7da767ecdd70356c915f8636e0ccb233121bb6ef932","bytes":66487},{"path":"integration_test/support/installed_plugin_windows_lifetime.dart","sha256":"d896f1580440e1fe726595b8d0afc64046a6480cbb0a949cf9a04c009c8a8173","bytes":3701},{"path":".github/workflows/installed_plugin_probe.yml","sha256":"382f4f78f9b41fde647162d1058bec60d4df4ea4ad85cd48610cded77753b6d3","bytes":7040},{"path":"tool/perf_probe/installed_plugin_windows_control.psm1","sha256":"dea8243fa148fc09168e0833ac36b77fac03486e0657d478b545c672d0d23d5f","bytes":10454},{"path":"tool/perf_probe/installed_plugin_windows_exit.psm1","sha256":"5d1d26bc0adb24cc91f7ec81031daca4985233f7601a21dc30616c53ea373e96","bytes":15874},{"path":"tool/perf_probe/test_installed_plugin_windows_runner.ps1","sha256":"9f732afcc8093933db9402de470a1f34d0e55289c398589efecc616e5adc8b93","bytes":12152},{"path":"tool/perf_probe/installed_plugin_windows_runner.psm1","sha256":"205ccece2043181621a9dae1a98db59d6df76b93b788a48e57cb3afc66c6e462","bytes":10724},{"path":"tool/perf_probe/run_installed_plugin_windows.ps1","sha256":"edd23bafd7dd24ad7ffc4d090197610eed43c392e0050bc0b737fc8e4c7c0569","bytes":586},{"path":"integration_test/installed_plugin_resource_probe_test.dart","sha256":"4f03d7f8f7a2cb94ed79590af5995b9f146077cceb7f49d688c41dceaf9d642e","bytes":53896},{"path":"tool/perf_probe/WEBVIEW_RESOURCE_PROBE.md","sha256":"f97230e81069bf3799f0229999c649c0e7f4a5c4fd23890c39030f8e4ef58fc3","bytes":45250},{"path":"test/tool/perf_probe/installed_plugin_windows_lifetime_test.dart","sha256":"06e509186494e4a6a80a20f962a22bb92b3fb357fb7254b499db4056333443f3","bytes":6586},{"path":"tool/perf_probe/test_installed_plugin_windows_control.ps1","sha256":"157dff260b0c608be395193a8dde2d0821b45f029e82b8315ae8db2b5fe5a1da","bytes":12208},{"path":"tool/perf_probe/test_installed_plugin_windows_exit.ps1","sha256":"dd9f4244782b7f7043d9d66dad81b6acdf267e46e857a67ffb25f0bb518b4d0d","bytes":23197}]
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
function Read-Source-State([string]$Label) {
    $state = @{ status = @(git status --porcelain=v1); files = @() }
    if ($LASTEXITCODE -ne 0) { throw 'git status failed.' }
    $state.checkoutPolicy = @(git config --show-origin --get-regexp '^core\.(autocrlf|eol)$')
    $state.lineEndings = @(git ls-files --eol)
    Save-Qa ($Label + '-checkout-policy.json') @{ configuration = $state.checkoutPolicy; lineEndings = $state.lineEndings }
    foreach ($entry in $expected) {
        $file = Get-Item -LiteralPath $entry.path
        $sha = (Get-FileHash -LiteralPath $entry.path -Algorithm SHA256).Hash.ToLowerInvariant()
        $state.files += @{ path = $entry.path; bytes = $file.Length; sha256 = $sha }
        Save-Qa ($Label + '-frozen-file-map.json') $state.files
        if ($file.Length -ne $entry.bytes -or $sha -cne $entry.sha256) {
            Save-Qa ($Label + '-source-byte-mismatch.json') @{ path = $entry.path; expected = $entry; actualBytes = $file.Length; actualSha256 = $sha; actualBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes([IO.Path]::GetFullPath($entry.path))); sourceHead = (git rev-parse HEAD).Trim(); checkoutPolicy = $state.checkoutPolicy; lineEndings = $state.lineEndings }
            throw "Candidate byte mismatch: $($entry.path)"
        }
    }
    $state.index = @(git ls-files --stage)
    if ($LASTEXITCODE -ne 0) { throw 'git index snapshot failed.' }
    $state.allTracked = @()
    foreach ($path in @(git ls-files)) {
        $file = Get-Item -LiteralPath $path
        $state.allTracked += @{ path = $path; bytes = $file.Length; sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
    }
    return $state
}
$qaHead = (git rev-parse HEAD).Trim()
$actualSourceTree = (git rev-parse ($source + '^{tree}')).Trim()
Assert-Qa ($actualSourceTree -ceq $sourceTree) 'Candidate tree mismatch.'
$qaPaths = @(git diff --name-only $source HEAD)
Assert-Qa ($qaPaths.Count -eq 2 -and $qaPaths -contains '.github/workflows/qa_4424_windows_fast.yml' -and $qaPaths -contains 'tool/perf_probe/qa_4424_windows_fast.ps1') 'QA commit must add only the two declared QA files.'
Assert-Qa ((git rev-parse HEAD^).Trim() -ceq $source) 'QA commit is not a direct child of frozen source.'
Assert-Qa ((git rev-parse ($source + '^')).Trim() -ceq '2aa04e69f4b6802bd376aed41f529590a6c4f9b3') 'Source parent changed.'
$before = Read-Source-State 'before'
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
    $resolverRoot = Join-Path $out 'real command resolution'
    $firstDir = Join-Path $resolverRoot 'first path with spaces'
    $secondDir = Join-Path $resolverRoot 'second path with spaces'
    [IO.Directory]::CreateDirectory($firstDir) | Out-Null
    [IO.Directory]::CreateDirectory($secondDir) | Out-Null
    $basename = 'qaresolver_' + [guid]::NewGuid().ToString('N')
    $cmdPath = Join-Path $firstDir ($basename + '.cmd')
    $batPath = Join-Path $secondDir ($basename + '.bat')
    [IO.File]::WriteAllText($cmdPath, "@echo off`r`necho QA_CMD_STDOUT [%~1] [%~2]`r`necho QA_CMD_STDERR [%~1] [%~2] 1>&2`r`n> ""%~3"" echo CMD`r`nexit /b 23`r`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($batPath, "@echo off`r`necho QA_BAT_STDOUT [%~1] [%~2]`r`necho QA_BAT_STDERR [%~1] [%~2] 1>&2`r`n> ""%~3"" echo BAT`r`nexit /b 37`r`n", [Text.UTF8Encoding]::new($false))
    $originalPath = $env:PATH
    try {
        $env:PATH = "$firstDir;$secondDir;$originalPath"
        Run-Qa 'Independent old frozen module actually fails with multiple ApplicationInfo objects' {
            $oldDir = Join-Path $resolverRoot 'old source outside checkout'
            [IO.Directory]::CreateDirectory($oldDir) | Out-Null
            $oldPath = Join-Path $oldDir 'qa_old_windows_exit.psm1'
            [IO.File]::WriteAllBytes($oldPath, [Convert]::FromBase64String('I1JlcXVpcmVzIC1WZXJzaW9uIDcuMApTZXQtU3RyaWN0TW9kZSAtVmVyc2lvbiBMYXRlc3QKaWYgKC1ub3QgKCdJbnN0YWxsZWRQbHVnaW5Qcm9iZS5MaWZldGltZU9ic2VydmVyJyAtYXMgW3R5cGVdKSkgewogICAgQWRkLVR5cGUgLVBhdGggKEpvaW4tUGF0aCAkUFNTY3JpcHRSb290ICdpbnN0YWxsZWRfcGx1Z2luX3dpbmRvd3NfbGlmZXRpbWUuY3MnKQp9CgpmdW5jdGlvbiBTdGFydC1JbnN0YWxsZWRQbHVnaW5MaWZldGltZU9ic2VydmVyIHsKICAgIHBhcmFtKFtQYXJhbWV0ZXIoTWFuZGF0b3J5KV1bc3RyaW5nXSRFeGVjdXRhYmxlLCBbUGFyYW1ldGVyKE1hbmRhdG9yeSldW3N0cmluZ10kQ2FtcGFpZ25JZCwKICAgICAgICBbUGFyYW1ldGVyKE1hbmRhdG9yeSldW3N0cmluZ10kVG9rZW4sIFtpbnRdJFN0YXJ0dXBUaW1lb3V0TWlsbGlzZWNvbmRzID0gMTIwMDAwMCkKICAgIHJldHVybiBbSW5zdGFsbGVkUGx1Z2luUHJvYmUuTGlmZXRpbWVPYnNlcnZlcl06Om5ldygkRXhlY3V0YWJsZSwgJENhbXBhaWduSWQsICRUb2tlbiwgJFN0YXJ0dXBUaW1lb3V0TWlsbGlzZWNvbmRzKQp9CgpmdW5jdGlvbiBTdG9wLUluc3RhbGxlZFBsdWdpbkxpZmV0aW1lT2JzZXJ2ZXIgewogICAgcGFyYW0oW1BhcmFtZXRlcihNYW5kYXRvcnkpXSRPYnNlcnZlciwgW3VpbnQzMl0kRXhpdFRpbWVvdXRNaWxsaXNlY29uZHMgPSAxMDAwMCkKICAgICRPYnNlcnZlci5Db21wbGV0ZSgkRXhpdFRpbWVvdXRNaWxsaXNlY29uZHMpCiAgICByZXR1cm4gJE9ic2VydmVyLlNuYXBzaG90SnNvbigpIHwgQ29udmVydEZyb20tSnNvbiAtQXNIYXNodGFibGUKfQoKZnVuY3Rpb24gR2V0LUluc3RhbGxlZFBsdWdpbkV4aXRFdmlkZW5jZSB7CiAgICBwYXJhbShbQWxsb3dOdWxsKCldW2hhc2h0YWJsZV0kVHJhY2UsIFtBbGxvd051bGwoKV1bU3lzdGVtLkNvbGxlY3Rpb25zLklEaWN0aW9uYXJ5XSRSZXBvcnQpCiAgICAkZXZpZGVuY2UgPSBAewogICAgICAgIGF2YWlsYWJpbGl0eSA9ICd1bmF2YWlsYWJsZSc7IHJlYXNvbiA9ICRudWxsOyBwcm9jZXNzSWQgPSAkbnVsbDsgcnVuSWQgPSAkbnVsbAogICAgICAgIGJvb3RzdHJhcFV0YyA9ICRudWxsOyBjcmVhdGlvbkZpbGVUaW1lID0gJG51bGw7IGV4ZWN1dGFibGUgPSAkbnVsbDsgZXhpdEZpbGVUaW1lID0gJG51bGwKICAgICAgICBleGl0U3RhdHVzID0gJG51bGw7IGV4aXRTdGF0dXNIZXggPSAkbnVsbAogICAgICAgIHRlcm1pbmF0aW9uQ2F1c2UgPSAnTm90IGluZmVycmVkOiBmbHV0dGVyIGRyaXZlIGNhbiBzdG9wIHRoZSBhcHAgYWZ0ZXIgdGhlIHRlc3QuJwogICAgfQogICAgdHJ5IHsKICAgICAgICBpZiAoJG51bGwgLW5lICRUcmFjZSAtYW5kICRUcmFjZS5pZGVudGl0eVZlcmlmaWVkKSB7CiAgICAgICAgICAgICRldmlkZW5jZS5wcm9jZXNzSWQgPSAkVHJhY2UuaWRlbnRpdHkucGlkOyAkZXZpZGVuY2UucnVuSWQgPSAkVHJhY2UucnVuSWQKICAgICAgICAgICAgJGV2aWRlbmNlLmJvb3RzdHJhcFV0YyA9IFtkYXRldGltZV0kVHJhY2UuYm9vdHN0cmFwVXRjCiAgICAgICAgICAgICRldmlkZW5jZS5jcmVhdGlvbkZpbGVUaW1lID0gJFRyYWNlLmlkZW50aXR5LmNyZWF0aW9uRmlsZVRpbWU7ICRldmlkZW5jZS5leGVjdXRhYmxlID0gJFRyYWNlLmlkZW50aXR5LmV4ZWN1dGFibGUKICAgICAgICB9CiAgICAgICAgaWYgKCRudWxsIC1lcSAkVHJhY2UgLW9yICRUcmFjZS5hdmFpbGFiaWxpdHkgLW5lICdjb2xsZWN0ZWQnIC1vciAkVHJhY2UuZXJyb3JzLkNvdW50IC1ndCAwIC1vcgogICAgICAgICAgICAtbm90ICRUcmFjZS5pZGVudGl0eVZlcmlmaWVkIC1vciAtbm90ICRUcmFjZS5ib290c3RyYXBRdWllc2NlbnQgLW9yICRUcmFjZS53YWl0UmVzdWx0IC1uZSAwIC1vcgogICAgICAgICAgICAtbm90ICRUcmFjZS5jbGVhbnVwLmhhbmRsZUFjcXVpcmVkIC1vciAtbm90ICRUcmFjZS5jbGVhbnVwLmhhbmRsZUNsb3NlZCAtb3IKICAgICAgICAgICAgLW5vdCAkVHJhY2UuY2xlYW51cC5saXN0ZW5lclN0b3BwZWQgLW9yIC1ub3QgJFRyYWNlLmNsZWFudXAuY2hhbm5lbENsb3NlZCAtb3IgLW5vdCAkVHJhY2UuY2xlYW51cC5ib290c3RyYXBUYXNrQ29tcGxldGVkKSB7CiAgICAgICAgICAgIHRocm93ICdUaGUgcmV0YWluZWQgbmF0aXZlIGxpZmV0aW1lIG9yIGl0cyBjbGVhbnVwIGlzIHVuYXZhaWxhYmxlIG9yIGluY29tcGxldGUuJwogICAgICAgIH0KICAgICAgICBpZiAoJG51bGwgLWVxICRSZXBvcnQgLW9yICRSZXBvcnRbJ3BsYXRmb3JtJ10gLW5lICd3aW5kb3dzJyAtb3IgJFJlcG9ydFsnYnVpbGRNb2RlJ10gLW5lICdwcm9maWxlJykgewogICAgICAgICAgICB0aHJvdyAnQSByZWFkYWJsZSBXaW5kb3dzIHByb2ZpbGUgZGV2aWNlIHJlcG9ydCBpcyByZXF1aXJlZC4nCiAgICAgICAgfQogICAgICAgIGlmICgoJFJlcG9ydFsncGlkJ10gLWlzbm90IFtsb25nXSAtYW5kICRSZXBvcnRbJ3BpZCddIC1pc25vdCBbaW50XSkgLW9yCiAgICAgICAgICAgICRSZXBvcnRbJ3BpZCddIC1sZSAwIC1vciAkUmVwb3J0WydwaWQnXSAtZ3QgW3VpbnQzMl06Ok1heFZhbHVlKSB7IHRocm93ICdUaGUgcmVwb3J0IFBJRCBtdXN0IGJlIGEgdmFsaWQgaW50ZWdlci4nIH0KICAgICAgICAkYWNrID0gJFJlcG9ydFsnd2luZG93c0xpZmV0aW1lJ10KICAgICAgICBpZiAoJGFjayAtaXNub3QgW0NvbGxlY3Rpb25zLklEaWN0aW9uYXJ5XSAtb3IgJGFja1sna2luZCddIC1uZSAncmVhZHknIC1vciAkYWNrWyd2ZXJzaW9uJ10gLW5lIDEgLW9yCiAgICAgICAgICAgICRhY2tbJ2NhbXBhaWduSWQnXSAtY25lICRUcmFjZS5jYW1wYWlnbklkIC1vciAkYWNrWydydW5JZCddIC1jbmUgJFRyYWNlLnJ1bklkIC1vcgogICAgICAgICAgICAkUmVwb3J0WydydW5JZCddIC1jbmUgJFRyYWNlLnJ1bklkIC1vciAkYWNrWydwaWQnXSAtbmUgJFRyYWNlLmlkZW50aXR5LnBpZCAtb3IgJFJlcG9ydFsncGlkJ10gLW5lICRUcmFjZS5pZGVudGl0eS5waWQgLW9yCiAgICAgICAgICAgICRhY2tbJ2NyZWF0aW9uRmlsZVRpbWUnXSAtY25lICRUcmFjZS5pZGVudGl0eS5jcmVhdGlvbkZpbGVUaW1lIC1vcgogICAgICAgICAgICAkYWNrWydleGVjdXRhYmxlJ10gLWNuZSAkVHJhY2UuaWRlbnRpdHkuZXhlY3V0YWJsZSAtb3IgJGFja1snYm9vdHN0cmFwUXVpZXNjZW50J10gLW5lICR0cnVlIC1vcgogICAgICAgICAgICBbZGF0ZXRpbWVdJGFja1snYWNrbm93bGVkZ2VkQXRVdGMnXSAtbmUgW2RhdGV0aW1lXSRUcmFjZS5hY2tub3dsZWRnZWRBdFV0YykgewogICAgICAgICAgICB0aHJvdyAnVGhlIGZpbmFsIGRldmljZSByZXBvcnQgZG9lcyBub3QgYWNrbm93bGVkZ2UgdGhpcyBleGFjdCBuYXRpdmUgbGlmZXRpbWUuJwogICAgICAgIH0KICAgICAgICBpZiAoJG51bGwgLWVxICRUcmFjZS5leGl0U3RhdHVzIC1vcgogICAgICAgICAgICAoJFRyYWNlLmV4aXRTdGF0dXMgLWlzbm90IFtpbnRdIC1hbmQgJFRyYWNlLmV4aXRTdGF0dXMgLWlzbm90IFtsb25nXSAtYW5kICRUcmFjZS5leGl0U3RhdHVzIC1pc25vdCBbdWludDMyXSkpIHsKICAgICAgICAgICAgdGhyb3cgJ1RoZSBuYXRpdmUgZXhpdCBzdGF0dXMgbXVzdCBiZSBhbiBvYnNlcnZlZCB1bnNpZ25lZCBpbnRlZ2VyLicKICAgICAgICB9CiAgICAgICAgJGV2aWRlbmNlLmV4aXRGaWxlVGltZSA9ICRUcmFjZS5leGl0RmlsZVRpbWUKICAgICAgICAkZXZpZGVuY2UuZXhpdFN0YXR1cyA9IFt1aW50MzJdJFRyYWNlLmV4aXRTdGF0dXMKICAgICAgICAkZXZpZGVuY2UuZXhpdFN0YXR1c0hleCA9ICcweHswOlg4fScgLWYgJGV2aWRlbmNlLmV4aXRTdGF0dXMKICAgICAgICAkZXZpZGVuY2UuYXZhaWxhYmlsaXR5ID0gJ2NvbGxlY3RlZCcKICAgIH0gY2F0Y2ggeyAkZXZpZGVuY2UucmVhc29uID0gJF8uRXhjZXB0aW9uLk1lc3NhZ2UgfQogICAgcmV0dXJuICRldmlkZW5jZQp9CgpmdW5jdGlvbiBTZWxlY3QtSW5zdGFsbGVkUGx1Z2luQXBwbGljYXRpb25FcnJvcnMgewogICAgcGFyYW0oCiAgICAgICAgW1BhcmFtZXRlcihNYW5kYXRvcnkpXVt4bWxdJEV2ZW50cywKICAgICAgICBbUGFyYW1ldGVyKE1hbmRhdG9yeSldW2hhc2h0YWJsZV0kSWRlbnRpdHksCiAgICAgICAgW1BhcmFtZXRlcihNYW5kYXRvcnkpXVtkYXRldGltZV0kQXJtZWRBdFV0YywKICAgICAgICBbUGFyYW1ldGVyKE1hbmRhdG9yeSldW2RhdGV0aW1lXSRGaW5pc2hlZEF0VXRjLAogICAgICAgIFtzdHJpbmddJFByb2Nlc3NOYW1lID0gJ290emFyaWEuZXhlJwogICAgKQogICAgaWYgKCRudWxsIC1lcSAkSWRlbnRpdHkucHJvY2Vzc0lkIC1vciAkbnVsbCAtZXEgJElkZW50aXR5LmNyZWF0aW9uRmlsZVRpbWUpIHsgcmV0dXJuIH0KICAgIGZvcmVhY2ggKCRldmVudCBpbiAkRXZlbnRzLlNlbGVjdE5vZGVzKCcvKi8qW2xvY2FsLW5hbWUoKT0iRXZlbnQiXScpKSB7CiAgICAgICAgdHJ5IHsKICAgICAgICAgICAgJGRhdGEgPSBAe30KICAgICAgICAgICAgZm9yZWFjaCAoJGZpZWxkIGluICRldmVudC5TZWxlY3ROb2RlcygnLi8qW2xvY2FsLW5hbWUoKT0iRXZlbnREYXRhIl0vKltsb2NhbC1uYW1lKCk9IkRhdGEiXScpKSB7CiAgICAgICAgICAgICAgICAkZGF0YVskZmllbGQuR2V0QXR0cmlidXRlKCdOYW1lJyldID0gJGZpZWxkLklubmVyVGV4dAogICAgICAgICAgICB9CiAgICAgICAgICAgICRzeXN0ZW0gPSAkZXZlbnQuU2VsZWN0U2luZ2xlTm9kZSgnLi8qW2xvY2FsLW5hbWUoKT0iU3lzdGVtIl0nKQogICAgICAgICAgICAkcHJvdmlkZXIgPSAkc3lzdGVtLlNlbGVjdFNpbmdsZU5vZGUoJy4vKltsb2NhbC1uYW1lKCk9IlByb3ZpZGVyIl0nKS5HZXRBdHRyaWJ1dGUoJ05hbWUnKQogICAgICAgICAgICAkZXZlbnRJZCA9ICRzeXN0ZW0uU2VsZWN0U2luZ2xlTm9kZSgnLi8qW2xvY2FsLW5hbWUoKT0iRXZlbnRJRCJdJykuSW5uZXJUZXh0CiAgICAgICAgICAgIGlmICgkcHJvdmlkZXIgLW5lICdBcHBsaWNhdGlvbiBFcnJvcicgLW9yICRldmVudElkIC1uZSAnMTAwMCcgLW9yICRkYXRhWydBcHBOYW1lJ10gLWluZSAkUHJvY2Vzc05hbWUpIHsgY29udGludWUgfQogICAgICAgICAgICBpZiAoJGRhdGFbJ1Byb2Nlc3NJZCddIC1ub3RtYXRjaCAnXjB4WzAtOWEtZkEtRl0rJCcgLW9yICRkYXRhWydQcm9jZXNzQ3JlYXRpb25UaW1lJ10gLW5vdG1hdGNoICdeMHhbMC05YS1mQS1GXSskJykgeyBjb250aW51ZSB9CiAgICAgICAgICAgICRwcm9jZXNzSWQgPSBbQ29udmVydF06OlRvVUludDMyKCRkYXRhWydQcm9jZXNzSWQnXS5SZXBsYWNlKCcweCcsICcnKSwgMTYpCiAgICAgICAgICAgICRjcmVhdGVkID0gW2RhdGV0aW1lXTo6RnJvbUZpbGVUaW1lVXRjKFtDb252ZXJ0XTo6VG9JbnQ2NCgkZGF0YVsnUHJvY2Vzc0NyZWF0aW9uVGltZSddLlJlcGxhY2UoJzB4JywgJycpLCAxNikpCiAgICAgICAgICAgICR1dGMgPSBbZGF0ZXRpbWVdOjpQYXJzZSgkc3lzdGVtLlNlbGVjdFNpbmdsZU5vZGUoJy4vKltsb2NhbC1uYW1lKCk9IlRpbWVDcmVhdGVkIl0nKS5HZXRBdHRyaWJ1dGUoJ1N5c3RlbVRpbWUnKSkuVG9Vbml2ZXJzYWxUaW1lKCkKICAgICAgICAgICAgaWYgKCRwcm9jZXNzSWQgLW5lICRJZGVudGl0eS5wcm9jZXNzSWQgLW9yICRjcmVhdGVkLlRvRmlsZVRpbWVVdGMoKSAtbmUgW2xvbmddJElkZW50aXR5LmNyZWF0aW9uRmlsZVRpbWUgLW9yCiAgICAgICAgICAgICAgICAkZGF0YVsnQXBwUGF0aCddIC1pbmUgJElkZW50aXR5LmV4ZWN1dGFibGUgLW9yCiAgICAgICAgICAgICAgICAkdXRjIC1sdCAkSWRlbnRpdHkuYm9vdHN0cmFwVXRjIC1vciAkdXRjIC1ndCAkRmluaXNoZWRBdFV0YykgeyBjb250aW51ZSB9CiAgICAgICAgICAgIEB7CiAgICAgICAgICAgICAgICBwcm92aWRlciA9ICRwcm92aWRlcjsgZXZlbnRJZCA9IDEwMDA7IHV0YyA9ICR1dGM7IHByb2Nlc3NJZCA9ICRwcm9jZXNzSWQ7IHByb2Nlc3NDcmVhdGVkVXRjID0gJGNyZWF0ZWQKICAgICAgICAgICAgICAgIGFwcE5hbWUgPSAkZGF0YVsnQXBwTmFtZSddOyBhcHBQYXRoID0gJGRhdGFbJ0FwcFBhdGgnXTsgbW9kdWxlTmFtZSA9ICRkYXRhWydNb2R1bGVOYW1lJ10KICAgICAgICAgICAgICAgIG1vZHVsZVBhdGggPSAkZGF0YVsnTW9kdWxlUGF0aCddOyBleGNlcHRpb25Db2RlID0gJGRhdGFbJ0V4Y2VwdGlvbkNvZGUnXTsgZmF1bHRPZmZzZXQgPSAkZGF0YVsnRmF1bHRpbmdPZmZzZXQnXQogICAgICAgICAgICAgICAgcmVwb3J0SWQgPSAkZGF0YVsnSW50ZWdyYXRvclJlcG9ydElkJ10KICAgICAgICAgICAgfQogICAgICAgIH0gY2F0Y2ggeyB0aHJvdyAiQXBwbGljYXRpb24gRXJyb3IgcmVjb3JkIGNvdWxkIG5vdCBiZSBjb3JyZWxhdGVkOiAkKCRfLkV4Y2VwdGlvbi5NZXNzYWdlKSIgfQogICAgfQp9CgpmdW5jdGlvbiBSZWFkLUluc3RhbGxlZFBsdWdpbkFwcGxpY2F0aW9uRXJyb3JzIHsKICAgIHBhcmFtKFtQYXJhbWV0ZXIoTWFuZGF0b3J5KV1baGFzaHRhYmxlXSRUcmFjZSwgW1BhcmFtZXRlcihNYW5kYXRvcnkpXVtoYXNodGFibGVdJElkZW50aXR5KQogICAgJHJlc3VsdCA9IEB7IGF2YWlsYWJpbGl0eSA9ICd1bmF2YWlsYWJsZSc7IHJlYXNvbiA9ICRudWxsOyBldmVudHMgPSBAKCk7IGxpbWl0ID0gNjQ7IHRydW5jYXRlZCA9ICRmYWxzZSB9CiAgICBpZiAoJG51bGwgLWVxICRJZGVudGl0eS5wcm9jZXNzSWQpIHsgJHJlc3VsdC5yZWFzb24gPSAnTm8gdmVyaWZpZWQgcmVwb3J0IGlkZW50aXR5Lic7IHJldHVybiAkcmVzdWx0IH0KICAgICRwcm9jZXNzID0gW0RpYWdub3N0aWNzLlByb2Nlc3NdOjpuZXcoKQogICAgJHN0YXJ0ZWQgPSAkZmFsc2UKICAgIHRyeSB7CiAgICAgICAgJGVuZCA9IFtkYXRldGltZV06OlV0Y05vdwogICAgICAgICRzdGFydFRleHQgPSAkVHJhY2UuYXJtZWRBdFV0Yy5Ub1N0cmluZygneXl5eS1NTS1kZFRISDptbTpzcy5mZmZmZmZmWicpCiAgICAgICAgJGVuZFRleHQgPSAkZW5kLlRvU3RyaW5nKCd5eXl5LU1NLWRkVEhIOm1tOnNzLmZmZmZmZmZaJykKICAgICAgICAkcXVlcnkgPSAiKltTeXN0ZW1bUHJvdmlkZXJbQE5hbWU9J0FwcGxpY2F0aW9uIEVycm9yJ10gYW5kIEV2ZW50SUQ9MTAwMCBhbmQgVGltZUNyZWF0ZWRbQFN5c3RlbVRpbWU+PSckc3RhcnRUZXh0JyBhbmQgQFN5c3RlbVRpbWU8PSckZW5kVGV4dCddXV0iCiAgICAgICAgJHByb2Nlc3MuU3RhcnRJbmZvID0gW0RpYWdub3N0aWNzLlByb2Nlc3NTdGFydEluZm9dOjpuZXcoJ3dldnR1dGlsLmV4ZScpCiAgICAgICAgJHByb2Nlc3MuU3RhcnRJbmZvLlVzZVNoZWxsRXhlY3V0ZSA9ICRmYWxzZQogICAgICAgICRwcm9jZXNzLlN0YXJ0SW5mby5DcmVhdGVOb1dpbmRvdyA9ICR0cnVlCiAgICAgICAgJHByb2Nlc3MuU3RhcnRJbmZvLlJlZGlyZWN0U3RhbmRhcmRPdXRwdXQgPSAkdHJ1ZQogICAgICAgICRwcm9jZXNzLlN0YXJ0SW5mby5SZWRpcmVjdFN0YW5kYXJkRXJyb3IgPSAkdHJ1ZQogICAgICAgIGZvcmVhY2ggKCRhcmd1bWVudCBpbiBAKCdxZScsICdBcHBsaWNhdGlvbicsICIvcTokcXVlcnkiLCAnL2M6NjUnLCAnL3JkOnRydWUnLCAnL2Y6eG1sJywgJy9lOkV2ZW50cycpKSB7CiAgICAgICAgICAgICRwcm9jZXNzLlN0YXJ0SW5mby5Bcmd1bWVudExpc3QuQWRkKCRhcmd1bWVudCkKICAgICAgICB9CiAgICAgICAgJHN0YXJ0ZWQgPSAkcHJvY2Vzcy5TdGFydCgpCiAgICAgICAgaWYgKC1ub3QgJHN0YXJ0ZWQpIHsgdGhyb3cgJ0NvdWxkIG5vdCBzdGFydCB0aGUgYm91bmRlZCBBcHBsaWNhdGlvbiBFcnJvciBxdWVyeS4nIH0KICAgICAgICAkc3Rkb3V0ID0gJHByb2Nlc3MuU3RhbmRhcmRPdXRwdXQuUmVhZFRvRW5kQXN5bmMoKQogICAgICAgICRzdGRlcnIgPSAkcHJvY2Vzcy5TdGFuZGFyZEVycm9yLlJlYWRUb0VuZEFzeW5jKCkKICAgICAgICBpZiAoLW5vdCAkcHJvY2Vzcy5XYWl0Rm9yRXhpdCgxNTAwMCkpIHsgdGhyb3cgJ0FwcGxpY2F0aW9uIEVycm9yIHF1ZXJ5IHRpbWVkIG91dCBhZnRlciAxNSBzZWNvbmRzLicgfQogICAgICAgIGlmICgtbm90ICRzdGRvdXQuV2FpdCgyMDAwKSAtb3IgLW5vdCAkc3RkZXJyLldhaXQoMjAwMCkpIHsgdGhyb3cgJ0FwcGxpY2F0aW9uIEVycm9yIG91dHB1dCBkaWQgbm90IGNsb3NlLicgfQogICAgICAgIGlmICgkcHJvY2Vzcy5FeGl0Q29kZSAtbmUgMCkgeyB0aHJvdyAiQXBwbGljYXRpb24gRXJyb3IgcXVlcnkgZXhpdGVkICQoJHByb2Nlc3MuRXhpdENvZGUpOiAkKCRzdGRlcnIuUmVzdWx0KSIgfQogICAgICAgICR4bWwgPSBbeG1sXSRzdGRvdXQuUmVzdWx0CiAgICAgICAgJHJlc3VsdC50cnVuY2F0ZWQgPSAkeG1sLlNlbGVjdE5vZGVzKCcvKi8qW2xvY2FsLW5hbWUoKT0iRXZlbnQiXScpLkNvdW50IC1ndCAkcmVzdWx0LmxpbWl0CiAgICAgICAgJHJlc3VsdC5ldmVudHMgPSBAKFNlbGVjdC1JbnN0YWxsZWRQbHVnaW5BcHBsaWNhdGlvbkVycm9ycyAtRXZlbnRzICR4bWwgLUlkZW50aXR5ICRJZGVudGl0eSBgCiAgICAgICAgICAgIC1Bcm1lZEF0VXRjICRUcmFjZS5hcm1lZEF0VXRjIC1GaW5pc2hlZEF0VXRjICRlbmQgLVByb2Nlc3NOYW1lICRUcmFjZS5wcm9jZXNzTmFtZSB8IFNlbGVjdC1PYmplY3QgLUZpcnN0ICRyZXN1bHQubGltaXQpCiAgICAgICAgJHJlc3VsdC5hdmFpbGFiaWxpdHkgPSAnY29sbGVjdGVkJwogICAgICAgIGlmICgkcmVzdWx0LmV2ZW50cy5Db3VudCAtZXEgMCkgeyAkcmVzdWx0LnJlYXNvbiA9ICdObyBtYXRjaGluZyBBcHBsaWNhdGlvbiBFcnJvciBldmVudCB3YXMgb2JzZXJ2ZWQgaW4gdGhlIGJvdW5kZWQgcXVlcnkuJyB9CiAgICB9IGNhdGNoIHsgJHJlc3VsdC5yZWFzb24gPSAkXy5FeGNlcHRpb24uTWVzc2FnZSB9CiAgICBmaW5hbGx5IHsKICAgICAgICB0cnkgewogICAgICAgICAgICBpZiAoJHN0YXJ0ZWQgLWFuZCAtbm90ICRwcm9jZXNzLkhhc0V4aXRlZCkgewogICAgICAgICAgICAgICAgJHByb2Nlc3MuS2lsbCgkdHJ1ZSkKICAgICAgICAgICAgICAgIGlmICgtbm90ICRwcm9jZXNzLldhaXRGb3JFeGl0KDIwMDApKSB7IHRocm93ICdUaGUgb3duZWQgQXBwbGljYXRpb24gRXJyb3IgcXVlcnkgZGlkIG5vdCBleGl0IGFmdGVyIHRlcm1pbmF0aW9uLicgfQogICAgICAgICAgICB9CiAgICAgICAgfSBjYXRjaCB7ICRyZXN1bHQucmVhc29uID0gIiQoJHJlc3VsdC5yZWFzb24pIFF1ZXJ5IGNsZWFudXA6ICQoJF8uRXhjZXB0aW9uLk1lc3NhZ2UpIiB9CiAgICAgICAgJHByb2Nlc3MuRGlzcG9zZSgpCiAgICB9CiAgICByZXR1cm4gJHJlc3VsdAp9CgpmdW5jdGlvbiBDb3B5LUxpbWl0ZWRJbnN0YWxsZWRQbHVnaW5EaWFnbm9zdGljIHsKICAgIHBhcmFtKCRWYWx1ZSkKICAgIGlmICgkVmFsdWUgLWlzIFtzdHJpbmddKSB7IHJldHVybiAkVmFsdWUuU3Vic3RyaW5nKDAsIFtNYXRoXTo6TWluKDEwMjQsICRWYWx1ZS5MZW5ndGgpKSB9CiAgICBpZiAoJFZhbHVlIC1pcyBbQ29sbGVjdGlvbnMuSURpY3Rpb25hcnldKSB7CiAgICAgICAgJGNvcHkgPSBAe30KICAgICAgICBmb3JlYWNoICgka2V5IGluICRWYWx1ZS5LZXlzKSB7ICRjb3B5WyRrZXldID0gQ29weS1MaW1pdGVkSW5zdGFsbGVkUGx1Z2luRGlhZ25vc3RpYyAkVmFsdWVbJGtleV0gfQogICAgICAgIHJldHVybiAkY29weQogICAgfQogICAgaWYgKCRWYWx1ZSAtaXMgW0NvbGxlY3Rpb25zLklFbnVtZXJhYmxlXSkgewogICAgICAgIHJldHVybiAsQCgkVmFsdWUgfCBTZWxlY3QtT2JqZWN0IC1GaXJzdCA4IHwgRm9yRWFjaC1PYmplY3QgeyBDb3B5LUxpbWl0ZWRJbnN0YWxsZWRQbHVnaW5EaWFnbm9zdGljICRfIH0pCiAgICB9CiAgICByZXR1cm4gJFZhbHVlCn0KCmZ1bmN0aW9uIFNhdmUtSW5zdGFsbGVkUGx1Z2luSnNvbiB7CiAgICBwYXJhbShbUGFyYW1ldGVyKE1hbmRhdG9yeSldW2hhc2h0YWJsZV0kVmFsdWUsIFtQYXJhbWV0ZXIoTWFuZGF0b3J5KV1bc3RyaW5nXSRQYXRoKQogICAgJGpzb24gPSAkVmFsdWUgfCBDb252ZXJ0VG8tSnNvbiAtRGVwdGggMjAgLUNvbXByZXNzCiAgICAkdHJ1bmNhdGVkID0gW1RleHQuRW5jb2RpbmddOjpVVEY4LkdldEJ5dGVDb3VudCgkanNvbikgKyAxIC1ndCAyNTZLQgogICAgaWYgKCR0cnVuY2F0ZWQpIHsKICAgICAgICAkbGltaXRlZCA9IENvcHktTGltaXRlZEluc3RhbGxlZFBsdWdpbkRpYWdub3N0aWMgJFZhbHVlCiAgICAgICAgJGxpbWl0ZWQuc3RhdHVzID0gJ2ZhaWxlZCc7ICRsaW1pdGVkLmRpYWdub3N0aWNUcnVuY2F0ZWQgPSAkdHJ1ZQogICAgICAgICRsaW1pdGVkLm9yaWdpbmFsQnl0ZXMgPSBbVGV4dC5FbmNvZGluZ106OlVURjguR2V0Qnl0ZUNvdW50KCRqc29uKSArIDEKICAgICAgICAkbGltaXRlZC5kaWFnbm9zdGljTGltaXRzID0gQHsgc3RyaW5nQ2hhcmFjdGVycyA9IDEwMjQ7IGFycmF5SXRlbXMgPSA4IH0KICAgICAgICAkanNvbiA9ICRsaW1pdGVkIHwgQ29udmVydFRvLUpzb24gLURlcHRoIDIwIC1Db21wcmVzcwogICAgICAgIGlmIChbVGV4dC5FbmNvZGluZ106OlVURjguR2V0Qnl0ZUNvdW50KCRqc29uKSArIDEgLWd0IDI1NktCKSB7IHRocm93ICdMaW1pdGVkIG5hdGl2ZSBldmlkZW5jZSBzdGlsbCBleGNlZWRzIDI1NiBLaUIuJyB9CiAgICB9CiAgICAkc3RyZWFtID0gJG51bGwKICAgIHRyeSB7CiAgICAgICAgJHN0cmVhbSA9IFtJTy5GaWxlXTo6T3BlbigkUGF0aCwgW0lPLkZpbGVNb2RlXTo6Q3JlYXRlTmV3LCBbSU8uRmlsZUFjY2Vzc106OldyaXRlLCBbSU8uRmlsZVNoYXJlXTo6Tm9uZSkKICAgICAgICAkYnl0ZXMgPSBbVGV4dC5VVEY4RW5jb2RpbmddOjpuZXcoJGZhbHNlKS5HZXRCeXRlcygkanNvbiArICJgbiIpCiAgICAgICAgJHN0cmVhbS5Xcml0ZSgkYnl0ZXMsIDAsICRieXRlcy5MZW5ndGgpCiAgICAgICAgJHN0cmVhbS5GbHVzaCgkdHJ1ZSkKICAgIH0gZmluYWxseSB7IGlmICgkbnVsbCAtbmUgJHN0cmVhbSkgeyAkc3RyZWFtLkRpc3Bvc2UoKSB9IH0KICAgIGlmICgkdHJ1bmNhdGVkKSB7IHRocm93ICdOYXRpdmUgZXZpZGVuY2UgZXhjZWVkcyB0aGUgMjU2IEtpQiBsaW1pdDsgYm91bmRlZCBwYXJ0aWFsIGV2aWRlbmNlIHdhcyBzYXZlZC4nIH0KfQoKZnVuY3Rpb24gV3JpdGUtSW5zdGFsbGVkUGx1Z2luRGlhZ25vc3RpY0ZhbGxiYWNrIHsKICAgIHBhcmFtKFtoYXNodGFibGVdJFZhbHVlLCBbc3RyaW5nXSRTYXZlRXJyb3IpCiAgICAkbGltaXRlZCA9IENvcHktTGltaXRlZEluc3RhbGxlZFBsdWdpbkRpYWdub3N0aWMgJFZhbHVlCiAgICAkbGltaXRlZC5zdGF0dXMgPSAnZmFpbGVkJzsgJGxpbWl0ZWQuZGlhZ25vc3RpY0ZhbGxiYWNrID0gJHRydWUKICAgICRsaW1pdGVkLmRpYWdub3N0aWNTYXZlRXJyb3IgPSBDb3B5LUxpbWl0ZWRJbnN0YWxsZWRQbHVnaW5EaWFnbm9zdGljICRTYXZlRXJyb3IKICAgICRsaW1pdGVkLmRpYWdub3N0aWNMaW1pdHMgPSBAeyBzdHJpbmdDaGFyYWN0ZXJzID0gMTAyNDsgYXJyYXlJdGVtcyA9IDggfQogICAgJGpzb24gPSAkbGltaXRlZCB8IENvbnZlcnRUby1Kc29uIC1EZXB0aCAyMCAtQ29tcHJlc3MKICAgIGlmIChbVGV4dC5FbmNvZGluZ106OlVURjguR2V0Qnl0ZUNvdW50KCRqc29uKSAtZ3QgMjU2S0IpIHsKICAgICAgICAkanNvbiA9IEB7IHN0YXR1cyA9ICdmYWlsZWQnOyBkaWFnbm9zdGljRmFsbGJhY2sgPSAkdHJ1ZTsgZGlhZ25vc3RpY1RydW5jYXRlZCA9ICR0cnVlOwogICAgICAgICAgICBmaXJzdEVycm9yID0gJGxpbWl0ZWRbJ2ZpcnN0RXJyb3InXTsgZXJyb3IgPSAkbGltaXRlZFsnZXJyb3InXTsgY2hpbGQgPSAkbGltaXRlZFsnY2hpbGQnXTsKICAgICAgICAgICAgZHJpdmVyRXhpdENvZGUgPSAkbGltaXRlZFsnZHJpdmVyRXhpdENvZGUnXTsgc3RlcEV4aXRDb2RlID0gJGxpbWl0ZWRbJ3N0ZXBFeGl0Q29kZSddOwogICAgICAgICAgICBkaWFnbm9zdGljU2F2ZUVycm9yID0gJGxpbWl0ZWQuZGlhZ25vc3RpY1NhdmVFcnJvciB9IHwgQ29udmVydFRvLUpzb24gLURlcHRoIDEwIC1Db21wcmVzcwogICAgfQogICAgW0NvbnNvbGVdOjpFcnJvci5Xcml0ZUxpbmUoJGpzb24pCn0KCmZ1bmN0aW9uIE5ldy1JbnN0YWxsZWRQbHVnaW5Mb2dXcml0ZXIgewogICAgcGFyYW0oW0lPLlN0cmVhbV0kU3RyZWFtKQogICAgcmV0dXJuIFtJTy5TdHJlYW1Xcml0ZXJdOjpuZXcoJFN0cmVhbSwgW1RleHQuVVRGOEVuY29kaW5nXTo6bmV3KCRmYWxzZSkpCn0KCmZ1bmN0aW9uIEludm9rZS1JbnN0YWxsZWRQbHVnaW5Mb2dnZWRDb21tYW5kIHsKICAgIHBhcmFtKFtQYXJhbWV0ZXIoTWFuZGF0b3J5KV1bc3RyaW5nXSRDb21tYW5kLCBbc3RyaW5nW11dJEFyZ3VtZW50cywgW1BhcmFtZXRlcihNYW5kYXRvcnkpXVtzdHJpbmddJExvZ1BhdGgpCiAgICAkUFNOYXRpdmVDb21tYW5kVXNlRXJyb3JBY3Rpb25QcmVmZXJlbmNlID0gJGZhbHNlCiAgICAkbmF0aXZlQ29tbWFuZCA9IEdldC1Db21tYW5kICRDb21tYW5kIC1Db21tYW5kVHlwZSBBcHBsaWNhdGlvbiAtRXJyb3JBY3Rpb24gU3RvcAogICAgJHJlc3VsdCA9IEB7IGV4aXRDb2RlID0gJG51bGw7IGVycm9yID0gJG51bGw7IGxvZ1RydW5jYXRlZCA9ICRmYWxzZSB9CiAgICAkc3RyZWFtID0gJG51bGwKICAgICR3cml0ZXIgPSAkbnVsbAogICAgJGxvZ2dpbmdGYWlsZWQgPSAkZmFsc2UKICAgIHRyeSB7CiAgICAgICAgJHN0cmVhbSA9IFtJTy5GaWxlXTo6T3BlbigkTG9nUGF0aCwgW0lPLkZpbGVNb2RlXTo6Q3JlYXRlTmV3LCBbSU8uRmlsZUFjY2Vzc106OldyaXRlLCBbSU8uRmlsZVNoYXJlXTo6UmVhZCkKICAgICAgICAkd3JpdGVyID0gTmV3LUluc3RhbGxlZFBsdWdpbkxvZ1dyaXRlciAkc3RyZWFtCiAgICAgICAgJGdsb2JhbDpMQVNURVhJVENPREUgPSAkbnVsbAogICAgICAgICYgJG5hdGl2ZUNvbW1hbmQgQEFyZ3VtZW50cyAyPiYxIHwgRm9yRWFjaC1PYmplY3QgewogICAgICAgICAgICAkbGluZSA9ICRfLlRvU3RyaW5nKCkKICAgICAgICAgICAgaWYgKC1ub3QgJGxvZ2dpbmdGYWlsZWQpIHsKICAgICAgICAgICAgICAgIHRyeSB7CiAgICAgICAgICAgICAgICAgICAgaWYgKCRzdHJlYW0uUG9zaXRpb24gKyBbVGV4dC5FbmNvZGluZ106OlVURjguR2V0Qnl0ZUNvdW50KCRsaW5lKSArIDIgLWd0IDE2TUIpIHsKICAgICAgICAgICAgICAgICAgICAgICAgJHJlc3VsdC5sb2dUcnVuY2F0ZWQgPSAkdHJ1ZQogICAgICAgICAgICAgICAgICAgICAgICB0aHJvdyAnVGhlIGRyaXZlciBsb2cgZXhjZWVkcyAxNiBNaUIuJwogICAgICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgICAgICAgICAkd3JpdGVyLldyaXRlTGluZSgkbGluZSk7ICR3cml0ZXIuRmx1c2goKQogICAgICAgICAgICAgICAgfSBjYXRjaCB7CiAgICAgICAgICAgICAgICAgICAgJGxvZ2dpbmdGYWlsZWQgPSAkdHJ1ZQogICAgICAgICAgICAgICAgICAgIGlmICgkbnVsbCAtZXEgJHJlc3VsdC5lcnJvcikgeyAkcmVzdWx0LmVycm9yID0gJF8uRXhjZXB0aW9uLk1lc3NhZ2UgfQogICAgICAgICAgICAgICAgfQogICAgICAgICAgICB9CiAgICAgICAgICAgIHRyeSB7IFdyaXRlLUhvc3QgJGxpbmUgfQogICAgICAgICAgICBjYXRjaCB7IGlmICgkbnVsbCAtZXEgJHJlc3VsdC5lcnJvcikgeyAkcmVzdWx0LmVycm9yID0gJF8uRXhjZXB0aW9uLk1lc3NhZ2UgfSB9CiAgICAgICAgfQogICAgICAgIGlmICgkbnVsbCAtZXEgJGdsb2JhbDpMQVNURVhJVENPREUpIHsgdGhyb3cgJ1RoZSBkcml2ZXIgZGlkIG5vdCByZXR1cm4gYSBuYXRpdmUgZXhpdCBjb2RlLicgfQogICAgICAgICRyZXN1bHQuZXhpdENvZGUgPSBbaW50XSRnbG9iYWw6TEFTVEVYSVRDT0RFCiAgICB9IGNhdGNoIHsgaWYgKCRudWxsIC1lcSAkcmVzdWx0LmVycm9yKSB7ICRyZXN1bHQuZXJyb3IgPSAkXy5FeGNlcHRpb24uTWVzc2FnZSB9IH0KICAgIGZpbmFsbHkgewogICAgICAgIHRyeSB7IGlmICgkbnVsbCAtbmUgJHdyaXRlcikgeyAkd3JpdGVyLkRpc3Bvc2UoKSB9IH0KICAgICAgICBjYXRjaCB7IGlmICgkbnVsbCAtZXEgJHJlc3VsdC5lcnJvcikgeyAkcmVzdWx0LmVycm9yID0gJF8uRXhjZXB0aW9uLk1lc3NhZ2UgfSB9CiAgICAgICAgdHJ5IHsgaWYgKCRudWxsIC1uZSAkc3RyZWFtKSB7ICRzdHJlYW0uRGlzcG9zZSgpIH0gfQogICAgICAgIGNhdGNoIHsgaWYgKCRudWxsIC1lcSAkcmVzdWx0LmVycm9yKSB7ICRyZXN1bHQuZXJyb3IgPSAkXy5FeGNlcHRpb24uTWVzc2FnZSB9IH0KICAgIH0KICAgIHJldHVybiAkcmVzdWx0Cn0KCmZ1bmN0aW9uIEdldC1JbnN0YWxsZWRQbHVnaW5SdW5FeGl0Q29kZSB7CiAgICBwYXJhbShbQWxsb3dOdWxsKCldW051bGxhYmxlW2ludF1dJERyaXZlckV4aXRDb2RlLCBbQWxsb3dOdWxsKCldW1N5c3RlbS5Db2xsZWN0aW9ucy5JRGljdGlvbmFyeV0kUmVwb3J0LAogICAgICAgIFtQYXJhbWV0ZXIoTWFuZGF0b3J5KV1baGFzaHRhYmxlXSRFeGl0RXZpZGVuY2UsIFtBbGxvd051bGwoKV1bU3lzdGVtLkNvbGxlY3Rpb25zLklEaWN0aW9uYXJ5XSRBcHBsaWNhdGlvbkVycm9ycyA9ICRudWxsLAogICAgICAgIFtzdHJpbmdbXV0kRGlhZ25vc3RpY0Vycm9ycyA9IEAoKSkKICAgIGlmICgkbnVsbCAtbmUgJERyaXZlckV4aXRDb2RlIC1hbmQgJERyaXZlckV4aXRDb2RlIC1uZSAwKSB7IHJldHVybiBbaW50XSREcml2ZXJFeGl0Q29kZSB9CiAgICBpZiAoJG51bGwgLWVxICREcml2ZXJFeGl0Q29kZSAtb3IgJG51bGwgLWVxICRSZXBvcnQgLW9yICRSZXBvcnRbJ3N0YXR1cyddIC1uZSAncGFzc2VkJyAtb3IKICAgICAgICAkUmVwb3J0WydlcnJvcnMnXSAtaXNub3QgW2FycmF5XSAtb3IgJFJlcG9ydFsnZXJyb3JzJ10uQ291bnQgLW5lIDAgLW9yCiAgICAgICAgJFJlcG9ydFsndGVzdEZhaWx1cmVzJ10gLWlzbm90IFthcnJheV0gLW9yICRSZXBvcnRbJ3Rlc3RGYWlsdXJlcyddLkNvdW50IC1uZSAwIC1vcgogICAgICAgICRFeGl0RXZpZGVuY2UuYXZhaWxhYmlsaXR5IC1uZSAnY29sbGVjdGVkJyAtb3IgJERpYWdub3N0aWNFcnJvcnMuQ291bnQgLWd0IDApIHsgcmV0dXJuIDEgfQogICAgIyBEYXJ0IFByb2Nlc3M6OktpbGwgb24gV2luZG93cyB1c2VzIFRlcm1pbmF0ZVByb2Nlc3MoaGFuZGxlLCAtMSkuCiAgICBpZiAoJEV4aXRFdmlkZW5jZS5leGl0U3RhdHVzIC1ub3RpbiBAKDAsIFt1aW50MzJdOjpNYXhWYWx1ZSkpIHsgcmV0dXJuIDEgfQogICAgaWYgKCRudWxsIC1lcSAkQXBwbGljYXRpb25FcnJvcnMgLW9yICRBcHBsaWNhdGlvbkVycm9yc1snYXZhaWxhYmlsaXR5J10gLW5lICdjb2xsZWN0ZWQnIC1vcgogICAgICAgICRBcHBsaWNhdGlvbkVycm9yc1sndHJ1bmNhdGVkJ10gLW5lICRmYWxzZSAtb3IgJEFwcGxpY2F0aW9uRXJyb3JzWydldmVudHMnXSAtaXNub3QgW2FycmF5XSAtb3IKICAgICAgICAkQXBwbGljYXRpb25FcnJvcnNbJ2V2ZW50cyddLkNvdW50IC1ndCAwKSB7IHJldHVybiAxIH0KICAgIHJldHVybiAwCn0KCkV4cG9ydC1Nb2R1bGVNZW1iZXIgLUZ1bmN0aW9uIFN0YXJ0LUluc3RhbGxlZFBsdWdpbkxpZmV0aW1lT2JzZXJ2ZXIsIFN0b3AtSW5zdGFsbGVkUGx1Z2luTGlmZXRpbWVPYnNlcnZlciwKICAgIEdldC1JbnN0YWxsZWRQbHVnaW5FeGl0RXZpZGVuY2UsIFNlbGVjdC1JbnN0YWxsZWRQbHVnaW5BcHBsaWNhdGlvbkVycm9ycywgUmVhZC1JbnN0YWxsZWRQbHVnaW5BcHBsaWNhdGlvbkVycm9ycywKICAgIEludm9rZS1JbnN0YWxsZWRQbHVnaW5Mb2dnZWRDb21tYW5kLCBHZXQtSW5zdGFsbGVkUGx1Z2luUnVuRXhpdENvZGUsIFNhdmUtSW5zdGFsbGVkUGx1Z2luSnNvbiwgV3JpdGUtSW5zdGFsbGVkUGx1Z2luRGlhZ25vc3RpY0ZhbGxiYWNrCg=='))
            Copy-Item -LiteralPath 'tool/perf_probe/installed_plugin_windows_lifetime.cs' -Destination (Join-Path $oldDir 'installed_plugin_windows_lifetime.cs')
            Assert-Qa ((Get-FileHash -LiteralPath $oldPath -Algorithm SHA256).Hash.ToLowerInvariant() -ceq '24140aa825be6d5c8b571a1798048a503a9909836222ee889843539f7ac335d7') 'Old module is not the exact f4ac blob.'
            $candidates = @(Get-Command $basename -CommandType Application -ErrorAction Stop)
            Assert-Qa ($candidates.Count -ge 2) 'Old failure reproduction requires real multiple ApplicationInfo objects.'
            Assert-Qa ($candidates[0].Path -ceq $cmdPath) 'Unexpected Windows PATH precedence for old-module reproduction.'
            $markerPath = Join-Path $resolverRoot 'old child must not run.txt'
            $oldModule = Import-Module $oldPath -PassThru -Force
            try {
                $result = & $oldModule { param($Name, $Log, $Marker)
                    Invoke-InstalledPluginLoggedCommand -Command $Name -Arguments @('first argument with spaces', 'second argument with spaces', $Marker) -LogPath $Log
                } $basename (Join-Path $out 'old-resolution.log') $markerPath
                Save-Qa 'old-resolution.json' @{ candidates = @($candidates | Select-Object Name, Path, CommandType); result = $result; markerExists = (Test-Path -LiteralPath $markerPath); frozenOldSha256 = '24140aa825be6d5c8b571a1798048a503a9909836222ee889843539f7ac335d7' }
                Assert-Qa ($null -eq $result.exitCode) 'Old module unexpectedly returned a native child status.'
                Assert-Qa (-not [string]::IsNullOrWhiteSpace($result.error)) 'Old module did not expose its actual invocation failure.'
                Assert-Qa ($result.error.Contains($basename + '.cmd') -and $result.error.Contains($basename + '.bat')) 'Old failure did not name both actual candidates.'
                Assert-Qa (-not (Test-Path -LiteralPath $markerPath)) 'Old failure unexpectedly executed a native child.'
            } finally { Remove-Module $oldModule }
        }
        $fixedModule = Import-Module $modulePath -Force -PassThru
        try {
            foreach ($control in @(
                @{ name = 'PATH selects cmd'; pathOrder = "$firstDir;$secondDir;$originalPath"; command = $basename; expectedPath = $cmdPath; marker = 'CMD'; code = 23 },
                @{ name = 'reversed PATH selects bat'; pathOrder = "$secondDir;$firstDir;$originalPath"; command = $basename; expectedPath = $batPath; marker = 'BAT'; code = 37 },
                @{ name = 'explicit cmd bypasses reversed PATH'; pathOrder = "$secondDir;$firstDir;$originalPath"; command = $cmdPath; expectedPath = $cmdPath; marker = 'CMD'; code = 23 },
                @{ name = 'explicit bat bypasses original PATH'; pathOrder = "$firstDir;$secondDir;$originalPath"; command = $batPath; expectedPath = $batPath; marker = 'BAT'; code = 37 }
            )) {
                Run-Qa ("Independent fixed actual resolver: " + $control.name) {
                    $env:PATH = $control.pathOrder
                    $commands = @(Get-Command $control.command -CommandType Application -ErrorAction Stop)
                    Assert-Qa ($commands[0].Path -ceq $control.expectedPath) 'System resolver does not match independent expected path.'
                    if ($control.command -ceq $basename) { Assert-Qa ($commands.Count -ge 2) 'PATH regression lost its ambiguous actual command fixture.' }
                    $id = $control.name.Replace(' ', '-')
                    $logPath = Join-Path $out ($id + '.log')
                    $markerPath = Join-Path $resolverRoot ($id + ' child marker.txt')
                    $result = & $fixedModule { param($Name, $Log, $Marker)
                        Invoke-InstalledPluginLoggedCommand -Command $Name -Arguments @('first argument with spaces', 'second argument with spaces', $Marker) -LogPath $Log
                    } $control.command $logPath $markerPath
                    $log = [IO.File]::ReadAllText($logPath)
                    $marker = $(if (Test-Path -LiteralPath $markerPath) { [IO.File]::ReadAllText($markerPath).Trim() } else { $null })
                    Save-Qa ($id + '.json') @{ control = $control; candidates = @($commands | Select-Object Name, Path, CommandType); result = $result; childMarker = $marker; logSha256 = (Get-FileHash -LiteralPath $logPath -Algorithm SHA256).Hash.ToLowerInvariant() }
                    Assert-Qa ($result.exitCode -eq $control.code) 'Real native exit status changed.'
                    Assert-Qa ($null -eq $result.error -and $result.logTruncated -eq $false) 'Actual resolver returned failed or truncated evidence.'
                    Assert-Qa ($marker -ceq $control.marker) 'A competing command or no command executed.'
                    foreach ($stream in @('STDOUT','STDERR')) { Assert-Qa ($log.Contains("QA_$($control.marker)_$stream [first argument with spaces] [second argument with spaces]")) 'Native stream or argument grouping changed.' }
                    $other = $(if ($control.marker -ceq 'CMD') { 'BAT' } else { 'CMD' })
                    Assert-Qa (-not $log.Contains("QA_$($other)_")) 'A non-selected native candidate executed.'
                }
            }
        } finally { Remove-Module $fixedModule }
    } finally { $env:PATH = $originalPath }

} finally {
    $sourceUnchanged = $false
    $sourceError = $null
    try {
        $after = Read-Source-State 'after'
        Save-Qa 'after.json' $after
        Assert-Qa ($after.status.Count -eq 0) 'QA modified tracked or untracked application worktree files.'
        Assert-Qa (($before.index | ConvertTo-Json -Compress) -ceq ($after.index | ConvertTo-Json -Compress)) 'Index entries changed during QA.'
        Assert-Qa (($before.allTracked | ConvertTo-Json -Depth 6 -Compress) -ceq ($after.allTracked | ConvertTo-Json -Depth 6 -Compress)) 'Tracked file bytes changed during QA.'
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
