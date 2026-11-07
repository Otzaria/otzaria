#Requires -Version 7.0
param([Parameter(Mandatory)][ValidateSet('Build', 'Arm', 'Finish')][string]$Mode)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Join-Path $env:RUNNER_TEMP 'installed-plugin-probe/native-debug'
$build = Join-Path $root 'build'
$binary = Join-Path $build 'qa-native-debugger.exe'
$utf8 = [Text.UTF8Encoding]::new($false)

function Save-Json([string]$Path, $Value) {
    [IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 30) + [Environment]::NewLine), $utf8)
}
function New-Monitor([string]$Target, [string]$Destination) {
    if (Test-Path -LiteralPath $Destination) { throw "Fresh diagnostic directory required: $Destination" }
    New-Item -ItemType Directory -Path $Destination | Out-Null
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $binary
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    foreach ($value in @('--watch', $Target, $Destination, (Join-Path $Destination 'stop'))) {
        $info.ArgumentList.Add($value)
    }
    foreach ($name in @('GITHUB_TOKEN', 'GH_TOKEN')) { $info.Environment.Remove($name) | Out-Null }
    $child = [Diagnostics.Process]::Start($info)
    $identity = @{
        pid = $child.Id
        creationFileTime = $child.StartTime.ToUniversalTime().ToFileTimeUtc().ToString()
        executable = $binary
        target = $Target
        output = $Destination
    }
    Save-Json (Join-Path $Destination 'monitor-process.json') $identity
    $limit = [DateTime]::UtcNow.AddSeconds(15)
    while (-not (Test-Path -LiteralPath (Join-Path $Destination 'armed.json'))) {
        if ($child.HasExited) { throw "Diagnostic monitor exited before arming: $($child.ExitCode)" }
        if ([DateTime]::UtcNow -ge $limit) {
            [IO.File]::WriteAllText((Join-Path $Destination 'stop'), 'arm deadline', $utf8)
            throw 'Diagnostic monitor did not arm within 15 seconds'
        }
        Start-Sleep -Milliseconds 50
    }
    return $child
}

New-Item -ItemType Directory -Force $root | Out-Null
if ($Mode -eq 'Build') {
    New-Item -ItemType Directory -Path $build | Out-Null
    $vswhere = Join-Path ([Environment]::GetEnvironmentVariable('ProgramFiles(x86)')) 'Microsoft Visual Studio/Installer/vswhere.exe'
    $installation = (& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $installation) { throw 'MSVC installation is unavailable' }
    Import-Module (Join-Path $installation 'Common7/Tools/Microsoft.VisualStudio.DevShell.dll')
    Enter-VsDevShell -VsInstallPath $installation -SkipAutomaticLocation -DevCmdArguments '-arch=x64 -host_arch=x64' | Out-Null
    $source = Join-Path $PSScriptRoot 'qa_4424_native_debugger.cpp'
    & cl.exe /nologo /std:c++17 /EHsc /W4 /Zi /Od "/Fe$binary" "/Fo$build/qa-native-debugger.obj" "/Fd$build/qa-native-debugger-compiler.pdb" $source /link "/PDB:$build/qa-native-debugger.pdb" 2>&1 |
        Tee-Object -FilePath (Join-Path $root 'compile.log')
    if ($LASTEXITCODE -ne 0) { throw "Native diagnostic compiler failed: $LASTEXITCODE" }
    Save-Json (Join-Path $root 'compiler.json') @{
        installation = $installation
        compiler = (Get-Command cl.exe -CommandType Application | Select-Object -First 1).Path
        source = $source
        sourceSha256 = (Get-FileHash $source -Algorithm SHA256).Hash.ToLowerInvariant()
        binarySha256 = (Get-FileHash $binary -Algorithm SHA256).Hash.ToLowerInvariant()
        nativeProtocol = 'Owned exact executable and creation FILETIME; retained handle; DebugActiveProcess; no writes or target termination; fatal exceptions forwarded unhandled'
        scope = 'Diagnostic only; debugger activity cannot be treated as acceptance or performance measurement'
    }
    $control = Join-Path $build 'qa-failfast-control.exe'
    Copy-Item -LiteralPath $binary -Destination $control
    $controlOut = Join-Path $root 'control'
    $monitor = New-Monitor $control $controlOut
    $fault = $null
    try {
        $fault = Start-Process -FilePath $control -ArgumentList '--fault' -PassThru
        $faultFileTime = $fault.StartTime.ToUniversalTime().ToFileTimeUtc().ToString()
        if (-not $fault.WaitForExit(30000)) { throw 'Owned fail-fast control did not exit within 30 seconds' }
        if (-not $monitor.WaitForExit(30000)) { throw 'Native control observer did not finish within 30 seconds' }
        $summary = Get-Content -LiteralPath (Join-Path $controlOut 'native-debug-summary.json') -Raw | ConvertFrom-Json -AsHashtable
        $events = @(Get-Content -LiteralPath (Join-Path $controlOut 'native-debug-events.jsonl') |
            ForEach-Object { $_ | ConvertFrom-Json -AsHashtable })
        $fatal = @($events | Where-Object { $_.event -eq 'exception' -and $_.code -eq '0xc0000409' })
        if ($monitor.ExitCode -ne 0 -or $summary.pid -ne $fault.Id -or $summary.creationFileTime -cne $faultFileTime -or
            -not $summary.processExitObserved -or $summary.unsignedExit -ne 3221226505 -or
            $summary.dumpCount -lt 1 -or $summary.stackCount -lt 1 -or $summary.targetTerminatedByDebugger -or
            $fatal.Count -lt 1 -or $fatal[0].parameters[0] -cne '0x7') {
            throw 'Native diagnostic control did not prove the exact fail-fast lifetime, exception, dump and stack'
        }
        Save-Json (Join-Path $root 'control-result.json') @{
            status = 'passed'
            childPid = $fault.Id
            childCreationFileTime = $faultFileTime
            childUnsignedExit = $summary.unsignedExit
            observerExit = $monitor.ExitCode
            exception = $fatal[0]
            dumpCount = $summary.dumpCount
            stackCount = $summary.stackCount
            notApplicationAcceptance = $true
        }
        Write-Host 'BEGIN_QA_4424_NATIVE_DEBUG_CONTROL'
        Get-Content -LiteralPath (Join-Path $root 'control-result.json') -Raw | Write-Host
        Write-Host 'END_QA_4424_NATIVE_DEBUG_CONTROL'
    } finally {
        [IO.File]::WriteAllText((Join-Path $controlOut 'stop'), 'control finished', $utf8)
        if ($null -ne $fault) { $fault.Dispose() }
        $monitor.Dispose()
    }
    exit 0
}
if ($Mode -eq 'Arm') {
    $expected = [IO.Path]::GetFullPath((Join-Path (Get-Location).Path 'build/windows/x64/runner/Profile/otzaria.exe'))
    $monitor = New-Monitor $expected (Join-Path $root 'actual')
    $monitor.Dispose()
    exit 0
}

$actual = Join-Path $root 'actual'
$problems = [Collections.Generic.List[string]]::new()
if (-not (Test-Path -LiteralPath $actual -PathType Container)) {
    Save-Json (Join-Path $root 'finish.json') @{ status = 'notArmed'; errors = @('Native diagnostic did not arm') }
    exit 1
}
[IO.File]::WriteAllText((Join-Path $actual 'stop'), 'original runner returned', $utf8)
$identity = Get-Content -LiteralPath (Join-Path $actual 'monitor-process.json') -Raw | ConvertFrom-Json -AsHashtable
$monitor = Get-Process -Id $identity.pid -ErrorAction SilentlyContinue
if ($null -ne $monitor) {
    try {
        $null = $monitor.SafeHandle
        if ($monitor.StartTime.ToUniversalTime().ToFileTimeUtc().ToString() -cne $identity.creationFileTime -or
            -not [string]::Equals($monitor.MainModule.FileName, $identity.executable, [StringComparison]::OrdinalIgnoreCase)) {
            $problems.Add('Monitor PID identity changed; no action was taken on it')
        } elseif (-not $monitor.WaitForExit(30000)) {
            $problems.Add('Owned debugger did not stop within 30 seconds; target was not terminated')
        }
    } finally { $monitor.Dispose() }
}
$summaryPath = Join-Path $actual 'native-debug-summary.json'
$summary = $null
if (Test-Path -LiteralPath $summaryPath) {
    $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json -AsHashtable
    $nativePath = Join-Path (Split-Path -Parent $root) 'windows-native-exit.json'
    if (Test-Path -LiteralPath $nativePath) {
        $native = Get-Content -LiteralPath $nativePath -Raw | ConvertFrom-Json -AsHashtable
        Copy-Item -LiteralPath $nativePath -Destination (Join-Path $actual 'native-receipt-original-copy.json')
        if ($native.nativeExit -isnot [Collections.IDictionary] -or -not $native.nativeExit.ContainsKey('processId')) {
            $problems.Add('Original authenticated native identity is unavailable')
        } elseif ($native.nativeExit.processId -ne $summary.pid -or
            [string]$native.nativeExit.creationFileTime -cne [string]$summary.creationFileTime -or
            -not [string]::Equals([string]$native.nativeExit.executable, [string]$summary.executable, [StringComparison]::OrdinalIgnoreCase)) {
            $problems.Add('Debugger identity does not match the original authenticated native receipt')
        }
    } else { $problems.Add('Original native receipt was not produced') }
} else { $problems.Add('Native debugger summary was not produced') }
$eventPathForSymbols = Join-Path $actual 'native-debug-events.jsonl'
if (Test-Path -LiteralPath $eventPathForSymbols) {
    $symbolRows = [Collections.Generic.List[object]]::new()
    $totalBytes = 0L
    $symbolDir = Join-Path $actual 'symbols'
    New-Item -ItemType Directory -Force $symbolDir | Out-Null
    $workspacePrefix = [IO.Path]::GetFullPath($env:GITHUB_WORKSPACE).TrimEnd('\') + '\'
    $flutterPrefix = [IO.Path]::GetFullPath($env:FLUTTER_ROOT).TrimEnd('\') + '\'
    $moduleFiles = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($line in Get-Content -LiteralPath $eventPathForSymbols) {
        $entry = $line | ConvertFrom-Json -AsHashtable
        if ($entry.event -eq 'frame') {
            foreach ($key in @('module', 'pdb')) {
                if ($entry.ContainsKey($key) -and $entry[$key]) { $moduleFiles.Add([string]$entry[$key]) | Out-Null }
            }
        }
    }
    foreach ($name in $moduleFiles) {
        $full = [IO.Path]::GetFullPath($name)
        if (-not ($full.StartsWith($workspacePrefix, [StringComparison]::OrdinalIgnoreCase) -or
            $full.StartsWith($flutterPrefix, [StringComparison]::OrdinalIgnoreCase)) -or
            -not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
        $file = Get-Item -LiteralPath $full
        if ($totalBytes + $file.Length -gt 512MB) {
            $symbolRows.Add(@{ source = $full; bytes = $file.Length; copied = $false; reason = '512 MiB bound' })
            continue
        }
        $digest = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()
        $target = Join-Path $symbolDir ($digest.Substring(0, 12) + '-' + $file.Name)
        Copy-Item -LiteralPath $full -Destination $target
        $totalBytes += $file.Length
        $symbolRows.Add(@{ source = $full; bytes = $file.Length; sha256 = $digest; copied = $true; output = $target })
    }
    Save-Json (Join-Path $actual 'retained-symbol-inputs.json') @{ bytes = $totalBytes; files = @($symbolRows) }
}
$manifest = @(Get-ChildItem -LiteralPath $root -Recurse -File | ForEach-Object {
    @{
        path = [IO.Path]::GetRelativePath($root, $_.FullName)
        bytes = $_.Length
        sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
})
Save-Json (Join-Path $root 'raw-manifest.json') $manifest
Save-Json (Join-Path $root 'finish.json') @{
    status = $(if ($problems.Count) { 'incomplete' } else { 'collected' })
    errors = @($problems)
    sourceCommit = '05e150d09758e0da45ca1877a4d650358f1aa17f'
    debugger = $summary
    acceptanceClaim = $false
    physicalPerformance = 'NOT_RUN'
}
Write-Host 'BEGIN_QA_4424_NATIVE_DEBUG_SUMMARY'
Get-Content -LiteralPath (Join-Path $root 'finish.json') -Raw | Write-Host
Write-Host 'END_QA_4424_NATIVE_DEBUG_SUMMARY'
Write-Host 'BEGIN_QA_4424_NATIVE_DEBUG_EVENTS'
$eventPath = Join-Path $actual 'native-debug-events.jsonl'
if (Test-Path -LiteralPath $eventPath) {
    $eventFile = Get-Item -LiteralPath $eventPath
    if ($eventFile.Length -le 1500000) { Get-Content -LiteralPath $eventPath -Raw | Write-Host }
    else {
        Write-Host "Full $($eventFile.Length)-byte event log retained in artifact"
        Get-Content -LiteralPath $eventPath |
            ForEach-Object { $_ | ConvertFrom-Json -AsHashtable } |
            Where-Object { $_.event -in @('identity', 'exception', 'dump', 'processExit', 'error') } |
            ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 10 | Write-Host }
    }
}
Write-Host 'END_QA_4424_NATIVE_DEBUG_EVENTS'
if ($problems.Count) { exit 1 }
