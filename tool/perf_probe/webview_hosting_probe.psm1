#Requires -Version 7.0
Set-StrictMode -Version Latest

function New-WebViewHostingStartInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][ValidateSet('default', 'hwnd')][string]$Mode,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$DiagnosticsPath
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
        $info.Environment[$variable] = '0'
    }
    $info.Environment['OTZARIA_WEBVIEW_PROBE_RUN_ID'] = $RunId
    $info.Environment['OTZARIA_DEV_DIAGNOSTICS_OUT'] = $DiagnosticsPath
    return $info
}

function Read-WebViewHostingBackend {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][int]$RootProcessId,
        [Parameter(Mandatory)][datetime]$RootStartedUtc,
        [Parameter(Mandatory)][datetime]$SampleStartedUtc,
        [Parameter(Mandatory)][datetime]$SampleEndedUtc,
        [Parameter(Mandatory)][ValidateSet('composition', 'hwnd')][string]$RequestedBackend
    )
    $reasons = [System.Collections.Generic.HashSet[string]]::new()
    $observations = [System.Collections.Generic.List[object]]::new()
    $active = @{}
    $sessions = @()
    $ticks = @()
    $observed = $null
    $setup = @()
    $result = [ordered]@{
        schemaVersion = 1; scope = 'nativeCreation'; requested = $RequestedBackend
        actualBackend = $null; verified = $false; ongoingModeVerified = $false
        activeAttachments = @(); observations = @(); setup = @(); reasons = @(); collectionMetadata = @{}
    }
    try {
        $RootStartedUtc = $RootStartedUtc.ToUniversalTime()
        $SampleStartedUtc = $SampleStartedUtc.ToUniversalTime()
        $SampleEndedUtc = $SampleEndedUtc.ToUniversalTime()
        if ($SampleStartedUtc -lt $RootStartedUtc -or $SampleEndedUtc -le $SampleStartedUtc) {
            throw 'invalid_sampling_interval'
        }
        $lines = [System.IO.File]::ReadAllLines($Path)
        $lastTime = $null
        foreach ($line in $lines) {
            $record = ConvertFrom-Json -InputObject $line -AsHashtable -ErrorAction Stop
            if ($record.type -notin @('session', 'end', 'webview_backend', 'webview_probe_tick')) { continue }
            if ($record.probeRunId -cne $RunId -or $record.pid -ne $RootProcessId) {
                [void]$reasons.Add('foreign_run_or_process'); continue
            }
            $at = if ($record.utc -is [datetime]) { $record.utc.ToUniversalTime() } else {
                [datetime]::Parse($record.utc, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
            }
            if ($at -lt $RootStartedUtc -or ($null -ne $lastTime -and $at -lt $lastTime)) {
                [void]$reasons.Add('invalid_record_time')
            }
            $lastTime = $at
            if ($record.type -eq 'session') {
                $sessions += $record
                if ($at -gt $SampleStartedUtc) { [void]$reasons.Add('collection_started_after_sampling') }
                continue
            }
            if ($sessions.Count -ne 1 -or $record.session -ne $sessions[0].session) {
                [void]$reasons.Add('collection_session_changed')
            }
            if ($record.type -eq 'webview_probe_tick') { $ticks += $at; continue }
            if ($record.type -eq 'end') {
                if ($at -le $SampleEndedUtc) { [void]$reasons.Add('collection_stopped_during_sampling') }
                continue
            }
            $observations.Add($record)
            if ($at -gt $SampleEndedUtc) { continue }
            $id = $record.attachmentId
            if ($id -isnot [string] -or $id -notmatch '^[0-9a-f]{32}$') {
                [void]$reasons.Add('invalid_attachment_identity'); continue
            }
            if ($at -gt $SampleStartedUtc) { [void]$reasons.Add('host_set_changed_during_sampling') }
            switch ($record.event) {
                { $_ -in @('attached', 'present') } {
                    if ($active.ContainsKey($id)) { [void]$reasons.Add('duplicate_attachment') }
                    $active[$id] = $record
                }
                'detached' {
                    if (-not $active.ContainsKey($id)) { [void]$reasons.Add('unknown_detachment') }
                    $active.Remove($id)
                }
                default { [void]$reasons.Add('unknown_lifecycle_event') }
            }
        }
        if ($sessions.Count -ne 1) { [void]$reasons.Add('expected_one_collection_session') }
        $before = @($ticks | Where-Object { $_ -le $SampleStartedUtc })
        $after = @($ticks | Where-Object { $_ -ge $SampleEndedUtc })
        if ($before.Count -eq 0 -or $after.Count -eq 0) {
            [void]$reasons.Add('sampling_interval_not_covered')
        } else {
            $cover = @($ticks | Where-Object { $_ -ge $before[-1] -and $_ -le $after[0] })
            for ($i = 1; $i -lt $cover.Count; $i++) {
                if (($cover[$i] - $cover[$i - 1]).TotalSeconds -gt 3) {
                    [void]$reasons.Add('diagnostics_gap_during_sampling')
                }
            }
        }
        if ($active.Count -eq 0) { [void]$reasons.Add('no_active_webviews') }
        $modes = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($entry in $active.Values) {
            $backend = $entry.backend
            if ($null -eq $backend -or $backend.schemaVersion -ne 1 -or
                $backend.scope -cne 'nativeCreation' -or $backend.availability -cne 'collected' -or
                $backend.source -cne 'WindowsInAppWebViewController.creationDetails' -or
                $backend.verified -isnot [bool] -or $backend.verified -ne $true -or
                $backend.observed -cnotin @('composition', 'hwnd')) {
                [void]$reasons.Add('unverified_backend'); continue
            }
            [void]$modes.Add($backend.observed)
            if ($backend.requested -cne $RequestedBackend) { [void]$reasons.Add('request_metadata_mismatch') }
            if ($backend.observed -cne $RequestedBackend) {
                [void]$reasons.Add($(if ($RequestedBackend -eq 'hwnd') { 'forced_hwnd_mismatch' } else { 'composition_fell_back_to_hwnd' }))
            }
            if ($entry.physicalWidth -le 0 -or $entry.physicalHeight -le 0 -or $entry.devicePixelRatio -le 0 -or
                [string]::IsNullOrEmpty($entry.pluginId) -or [string]::IsNullOrEmpty($entry.hostKind) -or
                [string]::IsNullOrEmpty($entry.webView2RuntimeVersion)) {
                [void]$reasons.Add('host_setup_unavailable')
            }
            $setup += [ordered]@{
                pluginId = $entry.pluginId; hostKind = $entry.hostKind
                physicalWidth = $entry.physicalWidth; physicalHeight = $entry.physicalHeight
                devicePixelRatio = $entry.devicePixelRatio; webView2RuntimeVersion = $entry.webView2RuntimeVersion
            } | ConvertTo-Json -Compress
        }
        if ($modes.Count -gt 1) { [void]$reasons.Add('mixed_backends') }
        if ($modes.Count -eq 1 -and -not $reasons.Contains('unverified_backend')) {
            $observed = @($modes)[0]
        }
    } catch {
        [void]$reasons.Add('diagnostics_unreadable_or_invalid')
        $result.error = $_.Exception.Message
    }
    $result.actualBackend = $observed
    $result.verified = $null -ne $observed -and -not $reasons.Contains('diagnostics_unreadable_or_invalid') -and
        -not $reasons.Contains('foreign_run_or_process') -and -not $reasons.Contains('invalid_record_time')
    $result.activeAttachments = @($active.Values)
    $result.observations = @($observations.ToArray())
    $result.setup = @($setup | Sort-Object)
    if ($sessions.Count -eq 1) {
        foreach ($field in @('version', 'buildMode', 'flutterVersion', 'osVersion')) {
            $result.collectionMetadata[$field] = $sessions[0][$field]
        }
    }
    $result.reasons = @($reasons | Sort-Object)
    return [pscustomobject]$result
}

function Get-WebViewHostingComparison {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Trials)
    $reasons = [System.Collections.Generic.HashSet[string]]::new()
    if ($Trials.Count -ne 2) { [void]$reasons.Add('expected_two_trials') }
    foreach ($trial in $Trials) {
        if ($trial.complete -isnot [bool] -or $trial.complete -ne $true) { [void]$reasons.Add('incomplete_trial') }
        if ($trial.setupConfirmed -isnot [bool] -or $trial.setupConfirmed -ne $true) { [void]$reasons.Add('setup_not_confirmed') }
        if ($trial.backend.verified -isnot [bool] -or $trial.backend.verified -ne $true) { [void]$reasons.Add('unverified_backend') }
        foreach ($reason in $trial.backend.reasons) { [void]$reasons.Add($reason) }
        if ($trial.backend.collectionMetadata['buildMode'] -cnotin @('profile', 'release')) {
            [void]$reasons.Add('non_measurement_build_mode')
        }
    }
    if ($Trials.Count -eq 2) {
        if (($Trials.backend.actualBackend | Sort-Object) -join ',' -cne 'composition,hwnd') {
            [void]$reasons.Add('requires_composition_and_hwnd')
        }
        if ($Trials[0].runId -ceq $Trials[1].runId -or
            ($Trials[0].processId -eq $Trials[1].processId -and $Trials[0].startedUtc -ceq $Trials[1].startedUtc)) {
            [void]$reasons.Add('requires_fresh_processes')
        }
        foreach ($field in @('executableSha256', 'scenario', 'displaySetup')) {
            if ([string]::IsNullOrWhiteSpace($Trials[0].$field) -or $Trials[0].$field -cne $Trials[1].$field) {
                [void]$reasons.Add('different_or_missing_setup')
            }
        }
        foreach ($field in @('version', 'buildMode', 'flutterVersion', 'osVersion')) {
            $left = $Trials[0].backend.collectionMetadata[$field]
            $right = $Trials[1].backend.collectionMetadata[$field]
            if ([string]::IsNullOrWhiteSpace($left) -or $left -in @('unknown', 'unavailable') -or $left -cne $right) {
                [void]$reasons.Add('different_or_missing_runtime_metadata')
            }
        }
        if (($Trials[0].backend.setup -join "`n") -cne ($Trials[1].backend.setup -join "`n")) {
            [void]$reasons.Add('different_host_setup')
        }
    }
    return [pscustomobject]@{
        comparisonReady = $reasons.Count -eq 0; scope = 'nativeCreation'
        ongoingModeVerified = $false; reasons = @($reasons | Sort-Object)
        performanceConclusion = $null; trials = $Trials
    }
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

Export-ModuleMember -Function New-WebViewHostingStartInfo, Get-WebViewHostingTree, Read-WebViewHostingProcess, Complete-WebViewHostingTrial, Get-WebViewHostingCpuPercent, Read-WebViewHostingBackend, Get-WebViewHostingComparison
