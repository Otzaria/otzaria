#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'installed_plugin_windows_diagnostics.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'installed_plugin_windows_exit.psm1') -Force
# Synthetic minidumps exercise parsing/ownership only, not an installed debugger.
& (Get-Module installed_plugin_windows_diagnostics) {
    function script:Read-InstalledPluginDumpWithDebugger { param($State, $DumpPath) }
}
$script:assertions = 0
function Assert-Equal($Expected, $Actual, [string]$Message) {
    $script:assertions++
    if ($Expected -cne $Actual) { throw "$Message; expected=$Expected actual=$Actual" }
}
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('installed-diagnostic-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporary | Out-Null
$testRegistry = 'HKCU:\Software\OtzariaInstalledProbeTests\' + [guid]::NewGuid().ToString('N')
$created = [datetimeoffset]'2026-11-07T21:20:59Z'
function New-TestDump([string]$Path, [uint32]$ProcessId = 42, [uint32]$Creation = $created.ToUnixTimeSeconds()) {
    $writer = [IO.BinaryWriter]::new([IO.File]::Create($Path))
    try {
        foreach ($value in @(0x504d444d, 0, 2, 32, 0, 0)) { $writer.Write([uint32]$value) }
        $writer.Write([uint64]0)
        foreach ($value in @(15, 24, 56, 6, 168, 80, 24, 3, $ProcessId, $Creation, 0, 0,
                7, 0, 3221226505, 1)) { $writer.Write([uint32]$value) }
        $writer.Write([uint64]0); $writer.Write([uint64]0x7ff00123)
        $writer.Write([uint32]1); $writer.Write([uint32]0); $writer.Write([uint64]7)
        for ($index = 1; $index -lt 15; $index++) { $writer.Write([uint64]0) }
        $writer.Write([uint64]0)
    } finally { $writer.Dispose() }
}
function New-TestState([string]$Name) {
    return Start-InstalledPluginCrashDiagnostics -Directory (Join-Path $temporary $Name) -RegistryPath $testRegistry
}
try {
    $dump = Join-Path $temporary 'known.dmp'
    New-TestDump $dump
    $decoded = Read-InstalledPluginMinidumpIdentity $dump
    Assert-Equal 42 $decoded.processId 'The minidump carries its own process ID'
    Assert-Equal $created.ToUnixTimeSeconds() $decoded.processCreateTime 'The dump carries process creation time, not file modification time'
    Assert-Equal '0xC0000409' $decoded.exception.codeHex 'The generic fast-fail status remains exact'
    Assert-Equal 7 $decoded.exception.parameters[0] 'The first exception parameter identifies the fast-fail subcode'
    foreach ($change in @(
        { param($bytes) $bytes[0] = 0 },
        { param($bytes) [BitConverter]::GetBytes([uint32]129).CopyTo($bytes, 8) },
        { param($bytes) [BitConverter]::GetBytes([uint32]1).CopyTo($bytes, 60) },
        { param($bytes) [BitConverter]::GetBytes([uint32]16).CopyTo($bytes, 112) }
    )) {
        $bytes = [IO.File]::ReadAllBytes($dump); & $change $bytes
        $invalid = Join-Path $temporary 'invalid.dmp'; [IO.File]::WriteAllBytes($invalid, $bytes)
        $rejected = $false
        try { $null = Read-InstalledPluginMinidumpIdentity $invalid } catch { $rejected = $true }
        Assert-Equal $true $rejected 'Malformed or incomplete minidump identity cannot be attributed'
    }
    $repo = Join-Path $temporary 'repo'
    $profile = Join-Path $repo 'build/windows/x64/runner/Profile'
    New-Item -ItemType Directory -Path $profile -Force | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $profile 'otzaria.exe'), [byte[]](1, 2, 3, 4))
    [IO.File]::WriteAllBytes((Join-Path $profile 'otzaria.pdb'), [byte[]](5, 6, 7, 8))
    [IO.File]::WriteAllBytes((Join-Path $profile 'flutter_windows.dll'), [byte[]](9, 10, 11, 12))
    $identity = @{ availability = 'collected'; processId = 42; processCreatedUtc = $created.UtcDateTime }
    foreach ($case in @('matching', 'wrong-pid', 'wrong-lifetime')) {
        $state = New-TestState $case
        $path = Join-Path $state.dumpDirectory 'otzaria.exe.42.dmp'
        New-TestDump -Path $path -ProcessId $(if ($case -eq 'wrong-pid') { 43 } else { 42 }) `
            -Creation $(if ($case -eq 'wrong-lifetime') { $created.ToUnixTimeSeconds() - 1 } else { $created.ToUnixTimeSeconds() })
        Complete-InstalledPluginCrashDiagnostics -State $state -RepositoryRoot $repo -Identity $identity -Failed $true -DumpWaitSeconds 0
        $expected = if ($case -eq 'matching') { 'collected' } else { 'unavailable' }
        Assert-Equal $expected $state.dump.availability 'Only the retained process PID and lifetime identify a dump'
        Assert-Equal ($case -eq 'matching') (Test-Path (Join-Path $state.directory 'artifacts/dumps/otzaria.exe.42.dmp')) 'Unrelated dumps are not uploaded as this app crash'
        Assert-Equal $true (Test-Path (Join-Path $state.directory 'artifacts/symbols/build/windows/x64/runner/Profile/otzaria.pdb')) 'Actual PDB bytes survive the runner'
        Assert-Equal $true ('flutter_windows.dll' -in $state.symbols.missing) 'Missing module symbols are explicit'
        Assert-Equal $false ('otzaria.exe' -in $state.symbols.missing) 'Available PDBs are distinguished from missing symbols'
        $copied = $state.files | Where-Object { $_.artifact -eq 'modules/otzaria.exe' }
        Assert-Equal (Get-FileHash (Join-Path $profile 'otzaria.exe')).Hash.ToLowerInvariant() $copied.sha256 'The uploaded module is hashed after copying'
    }
    $limited = New-TestState 'limited'
    $limited.maxFileBytes = 3
    Assert-Equal $null (Copy-InstalledPluginDiagnosticFile $limited (Join-Path $profile 'otzaria.pdb') 'too-large.pdb') 'Oversized symbol files are omitted'
    Assert-Equal 0 $limited.copiedBytes 'An omitted file does not consume the upload budget'
    $limited.maxFileBytes = 8; $limited.maxBytes = 6
    $null = Copy-InstalledPluginDiagnosticFile $limited (Join-Path $profile 'otzaria.pdb') 'one.pdb'
    Assert-Equal $null (Copy-InstalledPluginDiagnosticFile $limited (Join-Path $profile 'otzaria.exe') 'two.exe') 'Total diagnostic bytes are bounded'
    $limited.maxBytes = 100; $limited.maxFiles = 1
    Assert-Equal $null (Copy-InstalledPluginDiagnosticFile $limited (Join-Path $profile 'otzaria.exe') 'three.exe') 'Diagnostic file count is bounded'
    Remove-Item -LiteralPath $limited.directory -Recurse -Force
    Complete-InstalledPluginCrashDiagnostics -State $limited -RepositoryRoot $repo -Identity $null -Failed $false
    Assert-Equal $true (@($limited.errors | Where-Object { $_ -like 'Diagnostic receipt:*' }).Count -gt 0) 'A failed diagnostic receipt is retained as a secondary error'
    Assert-Equal 37 (Get-InstalledPluginRunExitCode -DriverExitCode 37 -Report $null -ExitEvidence @{ availability = 'unavailable' }) 'The original driver failure remains authoritative after diagnostic cleanup failure'

    foreach ($failure in @('copy', 'hash', 'copy-cleanup')) {
        $broken = New-TestState ('broken-' + $failure)
        $broken.maxBytes = 6
        $module = Get-Module installed_plugin_windows_diagnostics
        & $module {
            param($Failure)
            if ($Failure -in @('copy', 'copy-cleanup')) {
                function script:Write-InstalledPluginDiagnosticCopy {
                    param($Source, $Destination, $Length)
                    $Destination.WriteByte(99)
                    throw 'controlled partial copy failure'
                }
            } else {
                function script:Get-FileHash { param($LiteralPath, $Algorithm) throw 'controlled hash failure' }
            }
            if ($Failure -eq 'copy-cleanup') {
                function script:Remove-Item { param($LiteralPath, $ErrorAction) throw 'controlled cleanup failure' }
            }
        } $failure
        Assert-Equal $null (Copy-InstalledPluginDiagnosticFile $broken (Join-Path $profile 'otzaria.pdb') 'failed.pdb') 'Copy/hash failure remains a diagnostic error'
        Assert-Equal ($failure -eq 'copy-cleanup') (Test-Path (Join-Path $broken.directory 'artifacts/failed.pdb')) 'An owned partial or unhashed destination is removed unless cleanup itself fails'
        Assert-Equal 4 $broken.reservedBytes 'A failed attempt cannot escape the aggregate byte budget'
        Assert-Equal $null (Copy-InstalledPluginDiagnosticFile $broken (Join-Path $profile 'otzaria.exe') 'another.exe') 'Repeated failures cannot exceed the byte limit'
        if ($failure -eq 'copy-cleanup') {
            Assert-Equal 'controlled partial copy failure' $broken.files[0].reason 'Cleanup cannot replace the first copy failure'
            Assert-Equal 'controlled cleanup failure' $broken.files[0].cleanupError 'Failed cleanup remains separate secondary evidence'
            Assert-Equal 1 (Get-Item (Join-Path $broken.directory 'artifacts/failed.pdb')).Length 'Unremoved partial bytes remain within reserved size'
        }
        Import-Module (Join-Path $PSScriptRoot 'installed_plugin_windows_diagnostics.psm1') -Force
        Restore-InstalledPluginCrashRegistry $broken
    }

    if ($IsWindows) {
        # Real registry-provider controls use an isolated HKCU key, never production WER settings.
        $fresh = New-TestState 'registry-fresh'
        Assert-Equal 'configured' $fresh.availability 'WER values were installed in the isolated native registry control'
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($testRegistry.Substring(6), $true)
        Assert-Equal 'ExpandString' $key.GetValueKind('DumpFolder').ToString() 'DumpFolder retains the WER-required registry kind'
        Assert-Equal 1 $key.GetValue('DumpType') 'Only a minidump is requested'
        Assert-Equal 1 $key.GetValue('DumpCount') 'Only one dump is retained'
        $key.Close()
        Restore-InstalledPluginCrashRegistry $fresh
        Assert-Equal $false (Test-Path -LiteralPath $testRegistry) 'A newly owned empty key is removed'
        New-Item -Path $testRegistry -Force | Out-Null
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($testRegistry.Substring(6), $true)
        $key.SetValue('DumpFolder', '%TEMP%\previous', [Microsoft.Win32.RegistryValueKind]::ExpandString)
        $key.SetValue('DumpType', 2, [Microsoft.Win32.RegistryValueKind]::DWord)
        $key.SetValue('unrelated', 'keep', [Microsoft.Win32.RegistryValueKind]::String); $key.Close()
        $existing = New-TestState 'registry-existing'
        Complete-InstalledPluginCrashDiagnostics -State $existing -RepositoryRoot $repo -Identity $null -Failed $false
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($testRegistry.Substring(6), $true)
        Assert-Equal '%TEMP%\previous' $key.GetValue('DumpFolder', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) 'Restoration preserves unexpanded registry data'
        Assert-Equal 'ExpandString' $key.GetValueKind('DumpFolder').ToString() 'Restoration preserves the original registry kind'
        Assert-Equal 2 $key.GetValue('DumpType') 'The previous dump mode is restored even after a successful run'
        Assert-Equal $false ('DumpCount' -in $key.GetValueNames()) 'Previously absent values are removed'
        Assert-Equal 'keep' $key.GetValue('unrelated') 'Unrelated registry data is preserved'; $key.Close()
        $external = New-TestState 'registry-external'
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($testRegistry.Substring(6), $true); $key.SetValue('DumpCount', 9, [Microsoft.Win32.RegistryValueKind]::DWord); $key.Close()
        Restore-InstalledPluginCrashRegistry $external
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($testRegistry.Substring(6), $true)
        Assert-Equal 9 $key.GetValue('DumpCount') 'A later external writer retains ownership of its value'
        Assert-Equal 2 $key.GetValue('DumpType') 'Other still-owned values are restored'; $key.Close()
        Assert-Equal 'preservedExternalChange' ($external.restoration | Where-Object { $_.name -eq 'DumpCount' }).result 'Ownership conflict is explicit in the receipt'
        $module = Get-Module installed_plugin_windows_diagnostics
        & $module {
            $script:writes = 0
            function script:Set-InstalledPluginCrashRegistryValue {
                param($Key, $Name, $Value)
                $script:writes++
                if ($script:writes -eq 2) { throw 'controlled partial registry configuration failure' }
                $Key.SetValue($Name, $Value.value, [Microsoft.Win32.RegistryValueKind]$Value.kind)
            }
        }
        $partial = Start-InstalledPluginCrashDiagnostics -Directory (Join-Path $temporary 'registry-partial') -RegistryPath "$testRegistry\partial"
        Assert-Equal 'unavailable' $partial.availability 'A partially configured WER key is not reported as configured'
        Complete-InstalledPluginCrashDiagnostics -State $partial -RepositoryRoot $repo -Identity $null -Failed $false
        Assert-Equal $false (Test-Path -LiteralPath "$testRegistry\partial") 'Already-written values are restored after partial setup failure'
        Assert-Equal $true (@($partial.errors | Where-Object { $_ -like '*controlled partial registry*' }).Count -gt 0) 'The original setup failure is retained'
        Import-Module (Join-Path $PSScriptRoot 'installed_plugin_windows_diagnostics.psm1') -Force
    } else { Write-Host 'Native HKCU registry controls require Windows and are mandatory in the Windows workflow.' }
    Write-Host "Passed $script:assertions crash diagnostic assertions."
} finally {
    if ($IsWindows -and (Test-Path -LiteralPath $testRegistry)) { Remove-Item -LiteralPath $testRegistry -Recurse -Force }
    Remove-Item -LiteralPath $temporary -Recurse -Force
}
exit 0
