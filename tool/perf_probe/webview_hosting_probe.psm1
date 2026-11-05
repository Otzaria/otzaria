#Requires -Version 7.0
Set-StrictMode -Version Latest

function New-WebViewHostingStartInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][ValidateSet('default', 'hwnd')][string]$Mode
    )
    $info = [System.Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $Executable
    $info.WorkingDirectory = [System.IO.Path]::GetDirectoryName($Executable)
    $info.UseShellExecute = $false
    $info.ArgumentList.Add('--dev-diagnostics=log')
    # Change only the child's environment, not the user's shell or registry.
    $variable = 'FLUTTER_INAPPWEBVIEW_WINDOWS_FORCE_HWND'
    if ($Mode -eq 'hwnd') {
        $info.Environment[$variable] = '1'
    } else {
        [void]$info.Environment.Remove($variable)
    }
    return $info
}

function Test-WebViewHostingCreationTime($Expected, $Actual) {
    if ($Expected -isnot [datetime] -or $Actual -isnot [datetime]) { return $false }
    # CIM dates have microsecond precision; Process.StartTime has 100 ns ticks.
    return [math]::Abs(($Expected.ToUniversalTime() - $Actual.ToUniversalTime()).Ticks) -lt 10
}

function Get-WebViewHostingTree {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$RootProcessId,
        [Parameter(Mandatory)][datetime]$RootStartedUtc,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Processes
    )
    $byId = @{}
    foreach ($process in $Processes) {
        $id = [int]$process.ProcessId
        if ($byId.ContainsKey($id)) { throw 'Duplicate PID in the process snapshot.' }
        $byId[$id] = $process
    }
    if (-not $byId.ContainsKey($RootProcessId) -or
        -not (Test-WebViewHostingCreationTime $RootStartedUtc $byId[$RootProcessId].CreationDate)) {
        throw 'The process snapshot does not contain the launched process identity.'
    }
    $tree = @{ $RootProcessId = $byId[$RootProcessId] }
    do {
        $changed = $false
        foreach ($process in $Processes) {
            $id = [int]$process.ProcessId
            $parentId = [int]$process.ParentProcessId
            if ($tree.ContainsKey($id) -or -not $tree.ContainsKey($parentId)) { continue }
            $parent = $tree[$parentId]
            if ($parent.CreationDate -isnot [datetime]) { continue }
            if ($process.CreationDate -is [datetime] -and
                $process.CreationDate.ToUniversalTime() -lt $parent.CreationDate.ToUniversalTime()) { continue }
            # Unknown child identity is counted as missing, but cannot extend the tree.
            $tree[$id] = $process
            $changed = $true
        }
    } while ($changed)
    return @($tree.Values | Sort-Object ProcessId)
}

function Read-WebViewHostingProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Snapshot,
        [scriptblock]$ReadProcess = { param($processId) [System.Diagnostics.Process]::GetProcessById($processId) }
    )
    $process = $null
    $check = $null
    try {
        $process = & $ReadProcess ([int]$Snapshot.ProcessId)
        $started = $process.StartTime.ToUniversalTime()
        if (-not (Test-WebViewHostingCreationTime $Snapshot.CreationDate $started)) {
            throw 'Process identity changed after the process snapshot.'
        }
        $record = [pscustomobject]@{
            processId = [int]$Snapshot.ProcessId; startedUtc = $started.ToString('o')
            name = $process.ProcessName
            cpuSeconds = $process.TotalProcessorTime.TotalSeconds
            privateCommitBytes = $process.PrivateMemorySize64
            workingSetBytes = $process.WorkingSet64
        }
        # StartTime is cached on Process, even across Refresh; use a fresh lookup.
        $check = & $ReadProcess ([int]$Snapshot.ProcessId)
        if ($check.StartTime.ToUniversalTime() -ne $started) {
            throw 'Process identity changed while reading counters.'
        }
        return $record
    } finally {
        if ($null -ne $check) { $check.Dispose() }
        if ($null -ne $process) { $process.Dispose() }
    }
}

function Complete-WebViewHostingTrial {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Process,
        [Parameter(Mandatory)][System.IO.TextWriter]$Writer,
        [Parameter(Mandatory)][double]$ElapsedSeconds
    )
    $Process.Refresh()
    if ($Process.HasExited) { throw 'The application exited while sampling; trial is incomplete.' }
    $Writer.WriteLine((@{ type = 'end'; complete = $true; elapsedSeconds = $ElapsedSeconds } | ConvertTo-Json -Compress))
    $Writer.Flush()
}

function Get-WebViewHostingCpuPercent {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Previous,
        [Parameter(Mandatory)][object]$Current
    )
    # CPU seconds / monotonic elapsed seconds. 100% means one fully used core,
    # not the whole machine. Missing samples and process churn remain unknown.
    if ($null -eq $Previous) { return $null }
    $seconds = [double]$Current.elapsedSeconds - [double]$Previous.elapsedSeconds
    if ($seconds -le 0 -or -not [double]::IsFinite($seconds)) { return $null }
    if ($Previous.missingProcesses -ne 0 -or $Current.missingProcesses -ne 0) {
        return $null
    }
    $old = @{}
    foreach ($process in $Previous.processes) {
        $key = "$($process.processId):$($process.startedUtc)"
        if ($old.ContainsKey($key)) { return $null }
        $old[$key] = $process
    }
    if ($old.Count -eq 0 -or $old.Count -ne @($Current.processes).Count) {
        return $null
    }
    $seen = [System.Collections.Generic.HashSet[string]]::new()
    $delta = 0.0
    foreach ($process in $Current.processes) {
        $key = "$($process.processId):$($process.startedUtc)"
        if (-not $old.ContainsKey($key) -or -not $seen.Add($key)) { return $null }
        if ($null -eq $process.cpuSeconds -or $null -eq $old[$key].cpuSeconds) {
            return $null
        }
        $before = [double]$old[$key].cpuSeconds
        $after = [double]$process.cpuSeconds
        if (-not [double]::IsFinite($before) -or -not [double]::IsFinite($after) -or
            $before -lt 0 -or $after -lt $before) { return $null }
        $delta += $after - $before
    }
    return 100.0 * $delta / $seconds
}

Export-ModuleMember -Function New-WebViewHostingStartInfo, Get-WebViewHostingTree, Read-WebViewHostingProcess, Complete-WebViewHostingTrial, Get-WebViewHostingCpuPercent
