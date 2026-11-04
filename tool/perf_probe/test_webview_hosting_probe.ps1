#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'webview_hosting_probe.psm1') -Force
function Assert-Equal($Expected, $Actual, [string]$Message) {
    if ($Expected -cne $Actual) { throw "$Message; expected=$Expected actual=$Actual" }
}
function New-Sample([double]$Elapsed, [object[]]$Processes, [int]$Missing = 0) {
    return [pscustomobject]@{ elapsedSeconds = $Elapsed; processes = $Processes; missingProcesses = $Missing }
}
function New-Record([int]$Id, [double]$Cpu, [string]$Started = 'first') {
    return [pscustomobject]@{ processId = $Id; cpuSeconds = $Cpu; startedUtc = $Started }
}
$tree = @(Get-WebViewHostingTreeIds -RootProcessId 10 -Processes @(
    @{ ProcessId = 12; ParentProcessId = 11 },
    @{ ProcessId = 11; ParentProcessId = 10 },
    @{ ProcessId = 10; ParentProcessId = 12 },
    @{ ProcessId = 99; ParentProcessId = 1 }
))
Assert-Equal '10,11,12' ($tree -join ',') 'Descendants, cycles and unrelated processes'
Assert-Equal 10 (Get-WebViewHostingTreeIds -RootProcessId 10 -Processes @()) 'Root survives an empty snapshot'

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
