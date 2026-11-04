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

function Get-WebViewHostingTreeIds {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$RootProcessId,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Processes
    )
    $ids = [System.Collections.Generic.HashSet[int]]::new()
    [void]$ids.Add($RootProcessId)
    do {
        $changed = $false
        foreach ($process in $Processes) {
            if ($ids.Contains([int]$process.ParentProcessId)) {
                if ($ids.Add([int]$process.ProcessId)) { $changed = $true }
            }
        }
    } while ($changed)
    return @($ids | Sort-Object)
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

Export-ModuleMember -Function New-WebViewHostingStartInfo, Get-WebViewHostingTreeIds, Get-WebViewHostingCpuPercent
