#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Open-InstalledPluginCrashRegistryKey {
    param([string]$Path)
    if ($Path -notmatch '^(HKLM|HKCU):\\(.+)$') { throw 'Expected a local registry path.' }
    $base = if ($Matches[1] -eq 'HKLM') { [Microsoft.Win32.Registry]::LocalMachine } else { [Microsoft.Win32.Registry]::CurrentUser }
    # Request write access explicitly; snapshots still preserve the original kinds and raw values.
    $key = $base.OpenSubKey($Matches[2], $true)
    if ($null -eq $key) { throw "Registry key is unavailable: $Path" }
    return $key
}

function Set-InstalledPluginCrashRegistryValue {
    param($Key, [string]$Name, [hashtable]$Value)
    $Key.SetValue($Name, $Value.value, [Microsoft.Win32.RegistryValueKind]$Value.kind)
}

function Read-InstalledPluginRegistryValue {
    param($Key, [string]$Name)
    if ($Name -notin $Key.GetValueNames()) { return @{ exists = $false } }
    return @{
        exists = $true; kind = $Key.GetValueKind($Name).ToString()
        value = $Key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    }
}

function Start-InstalledPluginCrashDiagnostics {
    param([Parameter(Mandatory)][string]$Directory,
        [string]$RegistryPath = 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\otzaria.exe')
    $state = @{
        schemaVersion = 1; directory = $Directory; dumpDirectory = Join-Path $Directory 'pending'
        registryPath = $RegistryPath; registryExisted = $true; registryValues = @{}; ownsDirectory = $false
        availability = 'unavailable'; startedAtUtc = [datetime]::UtcNow; restoredAtUtc = $null
        errors = [Collections.Generic.List[string]]::new(); restoration = @(); configuration = @()
        files = [Collections.Generic.List[object]]::new(); copiedBytes = [long]0; copiedFiles = 0
        reservedBytes = [long]0; reservedFiles = 0
        maxBytes = [long]1GB; maxFileBytes = [long]512MB; maxFiles = 64
        dump = @{ availability = 'unavailable'; reason = 'No identified crash dump collected.' }
        symbols = @{ missing = @(); reason = 'Collected only after a failed run.' }
        debugger = @{ availability = 'unavailable'; reason = 'No collected dump or installed cdb.exe.' }
        scope = 'Per-app WER minidump for the empty fixture. File collection and optional dump decoding occur only after flutter drive exits.'
    }
    $key = $null
    try {
        if (-not [IO.Path]::IsPathFullyQualified($Directory)) { throw 'Crash diagnostics require an absolute, fresh directory.' }
        New-Item -ItemType Directory -Path $Directory -ErrorAction Stop | Out-Null
        $state.ownsDirectory = $true
        New-Item -ItemType Directory -Path $state.dumpDirectory | Out-Null
        if (-not $IsWindows) { throw 'WER registry configuration requires Windows.' }
        foreach ($path in @('HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AeDebug',
                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\AeDebug',
                'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting',
                'HKCU:\SOFTWARE\Microsoft\Windows\Windows Error Reporting')) {
            $entry = @{ path = $path; exists = Test-Path -LiteralPath $path; values = @{} }
            if ($entry.exists) {
                $configKey = Get-Item -LiteralPath $path
                try {
                    foreach ($name in @('Auto', 'Debugger', 'Disabled', 'DontShowUI')) {
                        $entry.values[$name] = Read-InstalledPluginRegistryValue $configKey $name
                    }
                } finally { $configKey.Close() }
            }
            $state.configuration += $entry
        }
        $state.registryExisted = Test-Path -LiteralPath $RegistryPath
        if (-not $state.registryExisted) { New-Item -Path $RegistryPath -Force | Out-Null }
        $key = Open-InstalledPluginCrashRegistryKey $RegistryPath
        $owned = @{
            DumpFolder = @{ kind = 'ExpandString'; value = $state.dumpDirectory }
            DumpCount = @{ kind = 'DWord'; value = 1 }
            DumpType = @{ kind = 'DWord'; value = 1 }
        }
        foreach ($name in $owned.Keys) {
            $state.registryValues[$name] = @{ before = Read-InstalledPluginRegistryValue $key $name; owned = $owned[$name]; attempted = $false }
        }
        foreach ($name in $owned.Keys) {
            $state.registryValues[$name].attempted = $true
            Set-InstalledPluginCrashRegistryValue $key $name $owned[$name]
        }
        $state.availability = 'configured'
    } catch { $state.errors.Add("WER configuration: $($_.Exception.Message)") }
    finally { if ($null -ne $key) { $key.Close() } }
    return $state
}

function Restore-InstalledPluginCrashRegistry {
    param([Parameter(Mandatory)][hashtable]$State)
    $key = $null
    try {
        if ($State.registryValues.Count -eq 0) { return }
        $key = Open-InstalledPluginCrashRegistryKey $State.registryPath
        foreach ($name in $State.registryValues.Keys) {
            $saved = $State.registryValues[$name]
            if (-not $saved.attempted) { continue }
            try {
                $current = Read-InstalledPluginRegistryValue $key $name
                # A later writer owns its new value. Do not restore over it.
                if (-not $current.exists -or $current.kind -cne $saved.owned.kind -or $current.value -cne $saved.owned.value) {
                    $State.restoration += @{ name = $name; result = 'preservedExternalChange' }
                    continue
                }
                if ($saved.before.exists) {
                    $key.SetValue($name, $saved.before.value, [Microsoft.Win32.RegistryValueKind]$saved.before.kind)
                } else { $key.DeleteValue($name, $false) }
                $State.restoration += @{ name = $name; result = 'restored' }
            } catch { $State.errors.Add("Restore ${name}: $($_.Exception.Message)") }
        }
        $removeKey = -not $State.registryExisted -and $key.ValueCount -eq 0 -and $key.SubKeyCount -eq 0
        $key.Close(); $key = $null
        if ($removeKey) { Remove-Item -LiteralPath $State.registryPath }
    } catch { $State.errors.Add("WER restoration: $($_.Exception.Message)") }
    finally {
        if ($null -ne $key) { $key.Close() }
        $State.restoredAtUtc = [datetime]::UtcNow
    }
}

function Read-InstalledPluginMinidumpIdentity {
    param([Parameter(Mandatory)][string]$Path)
    $reader = $null
    try {
        # Exclusive access prevents accepting a dump while WER still writes it.
        $reader = [IO.BinaryReader]::new([IO.File]::Open($Path, 'Open', 'Read', 'None'))
        if ($reader.BaseStream.Length -lt 32 -or $reader.ReadUInt32() -ne 0x504d444d) { throw 'Invalid minidump header.' }
        $null = $reader.ReadUInt32()
        $count = $reader.ReadUInt32(); $directory = $reader.ReadUInt32()
        if ($count -gt 128 -or [long]$directory + [long]$count * 12 -gt $reader.BaseStream.Length) { throw 'Invalid minidump stream directory.' }
        $streams = @{}
        $reader.BaseStream.Position = $directory
        for ($index = 0; $index -lt $count; $index++) {
            $kind = $reader.ReadUInt32(); $size = $reader.ReadUInt32(); $offset = $reader.ReadUInt32()
            if ([long]$offset + [long]$size -gt $reader.BaseStream.Length) { throw 'Truncated minidump stream.' }
            if ($kind -in @(6, 15)) {
                if ($streams.ContainsKey([int]$kind)) { throw 'Duplicate minidump identity or exception stream.' }
                $streams[[int]$kind] = @{ size = $size; offset = $offset }
            }
        }
        if (-not $streams.ContainsKey(15) -or $streams[15].size -lt 24) { throw 'Minidump has no process identity stream.' }
        $reader.BaseStream.Position = $streams[15].offset
        $size = $reader.ReadUInt32(); $flags = $reader.ReadUInt32()
        if ($size -lt 24 -or ($flags -band 3) -ne 3) { throw 'Minidump does not include PID and process creation time.' }
        $result = @{ processId = $reader.ReadUInt32(); processCreateTime = $reader.ReadUInt32(); exception = $null }
        if ($streams.ContainsKey(6) -and $streams[6].size -ge 168) {
            $reader.BaseStream.Position = $streams[6].offset + 8
            $code = $reader.ReadUInt32(); $null = $reader.ReadUInt32(); $null = $reader.ReadUInt64()
            $address = $reader.ReadUInt64(); $parameters = $reader.ReadUInt32(); $null = $reader.ReadUInt32()
            if ($parameters -gt 15) { throw 'Invalid minidump exception parameter count.' }
            $values = @(for ($index = 0; $index -lt $parameters; $index++) { $reader.ReadUInt64() })
            $result.exception = @{ code = $code; codeHex = ('0x{0:X8}' -f $code); address = ('0x{0:X16}' -f $address); parameters = $values }
        }
        return $result
    } finally { if ($null -ne $reader) { $reader.Dispose() } }
}

function Write-InstalledPluginDiagnosticCopy {
    param([IO.Stream]$Source, [IO.Stream]$Destination, [long]$Length)
    $buffer = [byte[]]::new(65536)
    $remaining = $Length
    while ($remaining -gt 0) {
        $read = $Source.Read($buffer, 0, [int][Math]::Min($buffer.Length, $remaining))
        if ($read -eq 0) { throw 'Diagnostic source was truncated during copying.' }
        $Destination.Write($buffer, 0, $read)
        $remaining -= $read
    }
    if ($Source.ReadByte() -ne -1) { throw 'Diagnostic source grew during copying.' }
    $Destination.Flush($true)
}

function Copy-InstalledPluginDiagnosticFile {
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$RelativePath)
    $record = @{ source = $Path; artifact = $RelativePath; availability = 'unavailable'; bytes = $null; sha256 = $null; reason = $null }
    $State.files.Add($record)
    $source = $null; $target = $null; $destination = $null; $ownsDestination = $false
    try {
        $file = Get-Item -LiteralPath $Path
        $record.bytes = $file.Length
        if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Reparse points are not diagnostic inputs.' }
        if ($file.Length -gt $State.maxFileBytes -or $State.reservedBytes + $file.Length -gt $State.maxBytes -or $State.reservedFiles -ge $State.maxFiles) { throw 'Diagnostic file/byte limit reached.' }
        # Reserve before any destination bytes exist, including failed copies/hashes.
        # A failed cleanup can never free budget for another unaccounted partial file.
        $State.reservedBytes += $file.Length; $State.reservedFiles++
        $artifactRoot = [IO.Path]::GetFullPath((Join-Path $State.directory 'artifacts')) + [IO.Path]::DirectorySeparatorChar
        $destination = [IO.Path]::GetFullPath((Join-Path $artifactRoot $RelativePath))
        if (-not $destination.StartsWith($artifactRoot, [StringComparison]::Ordinal)) { throw 'Diagnostic destination escaped its owned artifact directory.' }
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        $source = [IO.File]::Open($Path, 'Open', 'Read', 'Read')
        $target = [IO.File]::Open($destination, 'CreateNew', 'Write', 'None'); $ownsDestination = $true
        Write-InstalledPluginDiagnosticCopy -Source $source -Destination $target -Length $file.Length
        $target.Dispose(); $target = $null; $source.Dispose(); $source = $null
        $record.sha256 = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
        $State.copiedBytes += $file.Length; $State.copiedFiles++
        $record.availability = 'collected'
        return $destination
    } catch {
        $record.reason = $_.Exception.Message
        if ($null -ne $target) {
            try { $target.Dispose() } catch { $State.errors.Add("Partial diagnostic close: $($_.Exception.Message)") }
            $target = $null
        }
        if ($ownsDestination) {
            try { Remove-Item -LiteralPath $destination -ErrorAction Stop }
            catch { $record['cleanupError'] = $_.Exception.Message }
        }
        return $null
    } finally {
        try { if ($null -ne $target) { $target.Dispose() } }
        catch { $State.errors.Add("Diagnostic destination close: $($_.Exception.Message)") }
        try { if ($null -ne $source) { $source.Dispose() } }
        catch { $State.errors.Add("Diagnostic source close: $($_.Exception.Message)") }
    }
}

function Read-InstalledPluginDumpWithDebugger {
    param([hashtable]$State, [string]$DumpPath)
    if (-not $IsWindows) { return }
    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Windows Kits/10/Debuggers/x64/cdb.exe'),
        (Join-Path $env:ProgramFiles 'Windows Kits/10/Debuggers/x64/cdb.exe')
    )
    $debugger = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if ($null -eq $debugger) { return }
    $process = [Diagnostics.Process]::new(); $started = $false
    try {
        $directories = @($State.files | Where-Object { $_.availability -eq 'collected' } |
            ForEach-Object { Split-Path -Parent (Join-Path (Join-Path $State.directory 'artifacts') $_.artifact) } | Sort-Object -Unique) -join ';'
        $process.StartInfo = [Diagnostics.ProcessStartInfo]::new($debugger)
        $process.StartInfo.UseShellExecute = $false; $process.StartInfo.CreateNoWindow = $true
        $process.StartInfo.RedirectStandardOutput = $true; $process.StartInfo.RedirectStandardError = $true
        # Local dump only. No debugger attachment or symbol-server requests during the scenario.
        foreach ($arg in @('-y', $directories, '-i', $directories, '-z', $DumpPath, '-c', '.exr -1; .ecxr; k 40; lm; q')) { $process.StartInfo.ArgumentList.Add($arg) }
        $started = $process.Start()
        if (-not $started) { throw 'Could not start the installed dump decoder.' }
        $stdout = $process.StandardOutput.ReadToEndAsync(); $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(20000)) { throw 'Post-exit dump decoder timed out after 20 seconds.' }
        if (-not $stdout.Wait(2000) -or -not $stderr.Wait(2000)) { throw 'Dump decoder output did not close.' }
        $text = $stdout.Result + "`nSTDERR:`n" + $stderr.Result
        $State.debugger = @{ availability = 'collected'; path = $debugger; exitCode = $process.ExitCode; truncated = $text.Length -gt 1MB }
        $text.Substring(0, [Math]::Min($text.Length, 1MB)) | Set-Content -LiteralPath (Join-Path $State.directory 'cdb.txt') -Encoding utf8
    } catch { $State.debugger = @{ availability = 'unavailable'; path = $debugger; reason = $_.Exception.Message } }
    finally {
        try { if ($started -and -not $process.HasExited) { $process.Kill($true); $null = $process.WaitForExit(2000) } }
        catch { $State.errors.Add("Dump decoder cleanup: $($_.Exception.Message)") }
        $process.Dispose()
    }
}

function Complete-InstalledPluginCrashDiagnostics {
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][string]$RepositoryRoot,
        [AllowNull()][hashtable]$Identity, [bool]$Failed, [ValidateRange(0, 15)][int]$DumpWaitSeconds = 10)
    try {
        if (-not $State.ownsDirectory -or -not $Failed) { return }
        $State.symbols.reason = 'Profile binaries and available build PDBs, copied after failure with byte/file bounds.'
        $dumpPath = $null
        if ($null -ne $Identity -and $Identity.availability -eq 'collected') {
            $State.dump = @{ availability = 'unavailable'; reason = 'No matching, closed WER minidump within the post-exit deadline.'; processId = $Identity.processId; processCreatedUtc = $Identity.processCreatedUtc }
            $candidate = Join-Path $State.dumpDirectory "otzaria.exe.$($Identity.processId).dmp"
            $deadline = [Diagnostics.Stopwatch]::StartNew()
            do {
                if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                    try {
                        $dumpIdentity = Read-InstalledPluginMinidumpIdentity -Path $candidate
                        $created = [datetimeoffset]([datetime]$Identity.processCreatedUtc).ToUniversalTime()
                        if ($dumpIdentity.processId -ne $Identity.processId -or $dumpIdentity.processCreateTime -ne $created.ToUnixTimeSeconds()) { throw 'Dump PID/creation time does not match the retained native process handle.' }
                        $dumpPath = Copy-InstalledPluginDiagnosticFile -State $State -Path $candidate -RelativePath ('dumps/' + [IO.Path]::GetFileName($candidate))
                        if ($null -ne $dumpPath) { $State.dump.availability = 'collected'; $State.dump.reason = $null; $State.dump['identity'] = $dumpIdentity }
                        break
                    } catch { $State.dump.reason = $_.Exception.Message }
                }
                if ($deadline.Elapsed.TotalSeconds -ge $DumpWaitSeconds) { break }
                Start-Sleep -Milliseconds 200
            } while ($true)
        }
        $profile = Join-Path $RepositoryRoot 'build/windows/x64/runner/Profile'
        $modules = @(if (Test-Path -LiteralPath $profile -PathType Container) {
            Get-ChildItem -LiteralPath $profile -File | Where-Object { $_.Extension -in @('.exe', '.dll') } | Select-Object -First 65
        })
        $symbolNames = @($modules | ForEach-Object { $_.BaseName + '.pdb'; $_.Name + '.pdb' })
        $pdbs = @()
        foreach ($root in @('build/windows/x64/runner', 'build/windows/x64/plugins', 'windows/flutter/ephemeral')) {
            $path = Join-Path $RepositoryRoot $root
            if (Test-Path -LiteralPath $path -PathType Container) {
                $pdbs += @(Get-ChildItem -LiteralPath $path -Filter '*.pdb' -File -Recurse |
                    Where-Object { $_.Name -in $symbolNames -and ($root -eq 'windows/flutter/ephemeral' -or ($_.DirectoryName -split '[\\/]') -contains 'Profile') } |
                    Select-Object -First 65)
            }
        }
        # Preserve actual PDB bytes before modules; a hash alone cannot decode a crash stack.
        foreach ($file in @($pdbs | Sort-Object FullName -Unique | Select-Object -First 65)) {
            $relative = [IO.Path]::GetRelativePath($RepositoryRoot, $file.FullName)
            $null = Copy-InstalledPluginDiagnosticFile -State $State -Path $file.FullName -RelativePath ('symbols/' + $relative)
        }
        $preservedSymbols = @($State.files | Where-Object { $_.availability -eq 'collected' -and [IO.Path]::GetExtension($_.source) -eq '.pdb' } |
            ForEach-Object { [IO.Path]::GetFileName($_.source) })
        foreach ($file in $modules) {
            $null = Copy-InstalledPluginDiagnosticFile -State $State -Path $file.FullName -RelativePath ('modules/' + $file.Name)
            if (($file.BaseName + '.pdb') -notin $preservedSymbols -and ($file.Name + '.pdb') -notin $preservedSymbols) { $State.symbols.missing += $file.Name }
        }
        $aot = Join-Path $profile 'data/app.so'
        if (Test-Path -LiteralPath $aot -PathType Leaf) { $null = Copy-InstalledPluginDiagnosticFile -State $State -Path $aot -RelativePath 'modules/app.so' }
        if ($null -ne $dumpPath) { Read-InstalledPluginDumpWithDebugger -State $State -DumpPath $dumpPath }
    } catch { $State.errors.Add("Post-exit diagnostics: $($_.Exception.Message)") }
    finally {
        # Diagnostic and restoration failures are receipts only; they never replace the native/driver failure.
        Restore-InstalledPluginCrashRegistry -State $State
        if ($State.ownsDirectory) {
            try { $State | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath (Join-Path $State.directory 'diagnostics.json') -Encoding utf8 }
            catch { $State.errors.Add("Diagnostic receipt: $($_.Exception.Message)") }
        }
    }
}

Export-ModuleMember -Function Start-InstalledPluginCrashDiagnostics, Restore-InstalledPluginCrashRegistry,
    Read-InstalledPluginMinidumpIdentity, Copy-InstalledPluginDiagnosticFile, Complete-InstalledPluginCrashDiagnostics
