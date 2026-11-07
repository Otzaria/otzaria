param([Parameter(Mandatory = $true)][string]$Root, [switch]$ValidateClipboardHelper, [switch]$ValidateShellVerifier)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName WindowsBase
Add-Type -Path (Join-Path $PSScriptRoot 'windows_history_qa_native.cs') -OutputAssembly (Join-Path $Root 'native.dll')
Add-Type -Path (Join-Path $Root 'native.dll')
[void][WinVQa.Native]::SetProcessDPIAware()
$config = Get-Content (Join-Path $Root 'case.json') -Raw | ConvertFrom-Json
$result = [ordered]@{
  probeCompleted = $false; historySelectionVerified = $false; otzariaFormTested = !($ValidateClipboardHelper -or $ValidateShellVerifier)
  outcome = 'starting'; historyWindowIdentified = $false; enableButtonInvoked = $false
  clipboardBeforeSelection = $null; clipboardAfterSelection = $null
  historyOpeningMechanism = 'SendInput Win+V with mapped scan codes; completion only through actual history selection'
  actions = @(); focusChecks = @(); historyStateSamples = @(); historyClosures = @(); caretPreparations = @(); clipboardFormatSamples = @(); error = $null
}
$script:deadline = [DateTime]::UtcNow.AddSeconds(70)
$script:clipboardCall = 0
$script:verifiedShellProcesses = @{}
# UI Automation runs in MTA; short, bounded STA helpers own clipboard data.
$originalCursor = New-Object WinVQa.Native+Point
[void][WinVQa.Native]::GetCursorPos([ref]$originalCursor)

function Save-Json($Value, [string]$Name) {
    $Value | ConvertTo-Json -Depth 14 | Set-Content -Encoding UTF8 (Join-Path $Root $Name)
}
function File-Sha256([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose(); $stream.Dispose() }
}
function Initialize-ShellVerifier {
    $manifest = [IO.Path]::GetFullPath((Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Security/Microsoft.PowerShell.Security.psd1'))
    $evidence = [ordered]@{
        processId = $PID; processPath = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        psVersion = [string]$PSVersionTable.PSVersion; psHome = $PSHOME; inheritedModulePath = $env:PSModulePath
        moduleManifest = $manifest; inputSent = $false; verifierReady = $false
    }
    Save-Json $evidence 'shell-verifier.json'
    try {
        # Flutter inherits PS7's module paths; bind the verifier to this PS5 installation.
        $modules = @(Import-Module -Name $manifest -Force -PassThru -ErrorAction Stop)
        if ($modules.Count -ne 1 -or $modules[0].Name -cne 'Microsoft.PowerShell.Security') { throw 'The installed Security manifest did not load the expected module.' }
        $script:signatureCommand = $modules[0].ExportedCommands['Get-AuthenticodeSignature']
        if ($null -eq $script:signatureCommand -or $script:signatureCommand.CommandType -ne 'Cmdlet') { throw 'The installed Security module does not export its signature cmdlet.' }
        $probePath = Join-Path $env:windir 'System32/user32.dll'
        $probe = & $script:signatureCommand -LiteralPath $probePath -ErrorAction Stop
        $evidence.moduleBase = $script:signatureCommand.Module.ModuleBase
        $evidence.modulePath = $script:signatureCommand.Module.Path
        $evidence.moduleVersion = [string]$script:signatureCommand.Module.Version
        $evidence.commandAssembly = $script:signatureCommand.ImplementingType.Assembly.Location
        $evidence.probePath = $probePath
        $evidence.probeStatus = [string]$probe.Status
        $evidence.probeSigner = $probe.SignerCertificate.Subject
        if ($probe.Status -ne 'Valid' -or $probe.SignerCertificate.Subject -notmatch 'CN=Microsoft Windows(?:,|$)') {
            throw 'The signature verifier did not validate the trusted Windows probe.'
        }
        $evidence.verifierReady = $true
        Save-Json $evidence 'shell-verifier.json'
    } catch {
        $evidence.error = $_.Exception.ToString()
        Save-Json $evidence 'shell-verifier.json'
        throw
    }
}
function Read-HistoryState([string]$Stage) {
    $sample = [ordered]@{ stage = $Stage; utc = [DateTime]::UtcNow.ToString('o'); available = $false; enabled = $null; error = $null }
    try {
        $reading = (Invoke-Clipboard 'history-state') | ConvertFrom-Json
        if ($reading.apartmentState -cne 'STA' -or $reading.inputSent -or $reading.clipboardChanged -or
            $reading.available -isnot [bool] -or ($reading.available -and $reading.enabled -isnot [bool])) {
            throw 'The history-state helper did not provide a read-only STA observation.'
        }
        $sample.available = $reading.available
        $sample.enabled = $reading.enabled
        $sample.error = $reading.error
        $sample.hresult = $reading.hresult
        $sample.readerProcessId = $reading.processId
        $sample.readerPSVersion = $reading.psVersion
        $sample.apartmentState = $reading.apartmentState
    } catch { $sample.error = $_.Exception.ToString(); $sample.hresult = $_.Exception.HResult }
    $result.historyStateSamples += $sample
    Save-Json $result 'result.json'
    return $sample
}
function Read-ClipboardFormats([string]$Stage) {
    $sample = [ordered]@{ stage = $Stage; available = $false; observation = $null; error = $null }
    try {
        $reading = (Invoke-Clipboard 'format-metadata') | ConvertFrom-Json
        if ($reading.apartmentState -cne 'STA' -or $reading.inputSent -or $reading.clipboardWritePerformed -or $reading.dataReadPerformed) {
            throw 'Clipboard format metadata was not a read-only STA observation.'
        }
        $sample.observation = $reading
        $sample.available = $reading.available
    } catch { $sample.error = $_.Exception.ToString() }
    $result.clipboardFormatSamples += $sample
    Save-Json $result 'result.json'
}
function Assert-Time {
    if ([DateTime]::UtcNow -ge $script:deadline) { throw 'Controller deadline exceeded' }
}
function Capture-Screen([string]$Name) {
    $bounds = [Windows.Forms.SystemInformation]::VirtualScreen
    $bitmap = New-Object Drawing.Bitmap($bounds.Width, $bounds.Height)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CopyFromScreen($bounds.Location, [Drawing.Point]::Empty, $bounds.Size)
        $bitmap.Save((Join-Path $Root "$Name.png"), [Drawing.Imaging.ImageFormat]::Png)
    } finally { $graphics.Dispose(); $bitmap.Dispose() }
}
function Get-NodeData($Element, [int]$Parent, [int]$Depth) {
    $current = $Element.Current
    $rectangle = $current.BoundingRectangle
    return [ordered]@{
        parent = $Parent; depth = $Depth; name = $current.Name; automationId = $current.AutomationId
        runtimeId = @($Element.GetRuntimeId())
        className = $current.ClassName; controlType = $current.ControlType.ProgrammaticName
        processId = $current.ProcessId; enabled = $current.IsEnabled; offscreen = $current.IsOffscreen
        rectangle = @{ x = $rectangle.X; y = $rectangle.Y; width = $rectangle.Width; height = $rectangle.Height }
    }
}
function Read-Branch($Element, [int]$Parent, [int]$Depth, $Nodes, $Budget) {
    Assert-Time
    if ($Depth -gt 16 -or $Nodes.Count -ge 600 -or $Budget.remaining -le 0) { return }
    $index = $Nodes.Count
    try { $data = Get-NodeData $Element $Parent $Depth }
    catch { return }
    $Nodes.Add([pscustomobject]@{ element = $Element; data = $data })
    $Budget.remaining--
    $walker = [Windows.Automation.TreeWalker]::RawViewWalker
    try { $child = $walker.GetFirstChild($Element) } catch { return }
    while ($null -ne $child -and $Nodes.Count -lt 600 -and $Budget.remaining -gt 0) {
        Read-Branch $child $index ($Depth + 1) $Nodes $Budget
        try { $child = $walker.GetNextSibling($child) } catch { break }
    }
}
function Test-HistoryObservationRoot($Metadata) {
    return $Metadata.trustedWindowsShell -and !$Metadata.offscreen -and $Metadata.processName -in @('TextInputHost', 'InputApp')
}
function Snapshot([string]$Name, [bool]$ReadShell = $true) {
    Assert-Time
    $capturedAt = [DateTime]::UtcNow.ToString('o')
    # Save the real desktop before any potentially blocking UIA provider call.
    Capture-Screen $Name
    $trees = New-Object 'System.Collections.Generic.List[object]'
    $top = New-Object 'System.Collections.Generic.List[object]'
    $budget = @{ remaining = 2000 }
    Save-Json @{ stage = 'enumerating-top-level'; topLevel = @(); shellTrees = @() } "$Name.uia.json"
    $candidates = New-Object 'System.Collections.Generic.List[object]'
    $observedWindows = [WinVQa.Native]::ObserveDesktopWindows()
    $windowsObservedAt = [DateTime]::UtcNow.ToString('o')
    foreach ($window in $observedWindows) {
        Assert-Time
        $metadata = [ordered]@{
            processId = $window.processId; processName = $null; processPath = $null
            window = $window.handle; name = $window.title; className = $window.className
            offscreen = !$window.visible; trustedWindowsShell = $false; shellSignature = $null
            sampledByWindowFromPoint = $window.sampled; sampleX = $window.sampleX; sampleY = $window.sampleY
        }
        $top.Add($metadata)
        try {
            $process = [Diagnostics.Process]::GetProcessById($window.processId)
            $processPath = $null
            try { $processPath = $process.MainModule.FileName } catch { }
            $metadata.processName = $process.ProcessName
            $metadata.processPath = $processPath
            $signatureInfo = $null
            $trusted = $process.ProcessName -in @('TextInputHost', 'InputApp', 'ShellExperienceHost', 'ShellHost', 'explorer') -and
                $null -ne $processPath -and $processPath.StartsWith(($env:windir.TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)
            if ($trusted) {
                $identityKey = [string]$process.Id + '|' + $processPath
                if (!$script:verifiedShellProcesses.ContainsKey($identityKey)) {
                    $signature = & $script:signatureCommand -LiteralPath $processPath -ErrorAction Stop
                    $script:verifiedShellProcesses[$identityKey] = @{ status = [string]$signature.Status; subject = $signature.SignerCertificate.Subject;
                        trusted = $signature.Status -eq 'Valid' -and $signature.SignerCertificate.Subject -match 'CN=Microsoft Windows(?:,|$)' }
                }
                $signatureInfo = $script:verifiedShellProcesses[$identityKey]
                $trusted = $signatureInfo.trusted
            }
            $metadata.trustedWindowsShell = $trusted
            $metadata.shellSignature = $signatureInfo
            if ($ReadShell -and (Test-HistoryObservationRoot $metadata)) {
                $candidates.Add($metadata)
            }
        } catch { $metadata.error = $_.Exception.ToString() }
    }
    $seenRoots = @{}
    foreach ($metadata in @($candidates | Sort-Object { if ($_.processName -in @('TextInputHost', 'InputApp')) { 0 } else { 1 } })) {
        Assert-Time
        try {
            if (![WinVQa.Native]::WindowStillOwned([IntPtr]$metadata.window, [uint32]$metadata.processId)) { continue }
            $element = [Windows.Automation.AutomationElement]::FromHandle([IntPtr]$metadata.window)
            if ($null -eq $element -or $element.Current.ProcessId -ne $metadata.processId) { continue }
            $runtimeId = [string]$metadata.processId + '|' + ($element.GetRuntimeId() -join '.')
            if ($seenRoots.ContainsKey($runtimeId)) { continue }
            $seenRoots[$runtimeId] = $true
            $nodes = New-Object 'System.Collections.Generic.List[object]'
            Save-Json @{ stage = 'reading-shell-tree'; currentRoot = $metadata; topLevel = @($top.ToArray()) } "$Name.uia.json"
            Read-Branch $element -1 0 $nodes $budget
            $trees.Add([pscustomobject]@{ root = $metadata; nodes = $nodes })
        } catch { $top.Add(@{ error = $_.Exception.Message; window = $metadata.window }) }
    }
    $export = @($trees | ForEach-Object { @{ root = $_.root; nodes = @($_.nodes | ForEach-Object { $_.data }) } })
    Save-Json @{ stage = 'complete'; capturedAt = $capturedAt; windowsObservedAt = $windowsObservedAt;
        shellUiaRequested = $ReadShell; automationScope = 'history-hosts-only';
        foreground = [WinVQa.Native]::GetForegroundWindow().ToInt64(); topLevel = @($top.ToArray()); shellTrees = $export;
        remainingNodeBudget = $budget.remaining } "$Name.uia.json"
    return @($trees.ToArray())
}
function History-Trees($Trees) {
    return @($Trees | Where-Object {
        @($_.nodes | Where-Object { $_.data.name -match '(?i)clipboard' -or $_.data.automationId -match '(?i)clipboard' }).Count -gt 0
    })
}
function Activate-Node($Tree, [int]$Index, [string]$Reason, [string]$Expected) {
    $node = $Tree.nodes[$Index]
    $fresh = $node.element.Current
    $matches = if ($Expected -eq 'Turn on') { $fresh.Name -ceq 'Turn on' -and $fresh.ControlType -eq [Windows.Automation.ControlType]::Button }
        elseif ($Expected -eq '<image-row>') { $fresh.Name -ceq $node.data.name -and $fresh.ControlType.ProgrammaticName -eq $node.data.controlType }
        else { $fresh.Name.Contains($Expected) -and !$fresh.Name.Contains($config.fixtureB) }
    if (!$Tree.root.trustedWindowsShell -or !$fresh.IsEnabled -or $fresh.IsOffscreen -or
        $fresh.ProcessId -ne $Tree.root.processId -or !$matches) { throw 'Refusing an unverified or changed UI target' }
    $rectangle = $node.element.Current.BoundingRectangle
    $screen = [Windows.Forms.SystemInformation]::VirtualScreen
    if ($rectangle.IsEmpty -or $rectangle.Width -lt 4 -or $rectangle.Height -lt 4) { throw 'UI target has no usable on-screen rectangle' }
    $x = [int]($rectangle.X + $rectangle.Width / 2)
    $y = [int]($rectangle.Y + $rectangle.Height / 2)
    if (!$screen.Contains($x, $y)) { throw 'UI target is outside the captured desktop' }
    if (![WinVQa.Native]::PointStillOwned($x, $y, [uint32]$Tree.root.processId)) { throw 'The observed Shell target does not own the visible click point' }
    $action = @{ reason = $Reason; mechanism = 'SendInput mouse click'; target = $node.data; root = $Tree.root;
        x = $x; y = $y; pointOwnershipVerified = $true; inputSent = $false }
    $result.actions += $action
    Save-Json $result 'result.json'
    [WinVQa.Native]::Click($x, $y, [uint32]$Tree.root.processId)
    $action.inputSent = $true
    Save-Json $result 'result.json'
}

function Assert-FlutterForeground {
    [uint32]$owner = 0
    [void][WinVQa.Native]::GetWindowThreadProcessId([IntPtr][long]$config.window, [ref]$owner)
    if ($owner -ne $config.processId) { throw 'The requested Flutter window no longer belongs to the test process' }
    if ([WinVQa.Native]::GetForegroundWindow().ToInt64() -ne $config.window) { throw 'Flutter must own the foreground before input' }
}
function Focus-Flutter([string]$Stage = 'setup') {
    $focus = [ordered]@{ stage = $Stage; before = [WinVQa.Native]::GetForegroundWindow().ToInt64(); expected = $config.window; captionInputSent = $false }
    $result.focusChecks += $focus
    [WinVQa.Native]::RaiseFlutter([IntPtr][long]$config.window, [uint32]$config.processId)
    [void][WinVQa.Native]::SetForegroundWindow([IntPtr][long]$config.window)
    Start-Sleep -Milliseconds 300
    if ([WinVQa.Native]::GetForegroundWindow().ToInt64() -ne $config.window) {
        Capture-Screen ('focus-' + $result.focusChecks.Count + '-before-caption')
        $focus.captionPoints = @([WinVQa.Native]::CaptionPoints([IntPtr][long]$config.window, [uint32]$config.processId))
        $point = $focus.captionPoints | Where-Object { $_.verified } | Select-Object -First 1
        Save-Json $result 'result.json'
        if ($null -eq $point) { throw 'No visible owned Flutter title-bar point is available for activation.' }
        [WinVQa.Native]::ClickFlutterCaption([IntPtr][long]$config.window, [uint32]$config.processId, $point.x, $point.y)
        $focus.captionInputSent = $true
        Start-Sleep -Milliseconds 300
    }
    $focus.after = [WinVQa.Native]::GetForegroundWindow().ToInt64()
    Save-Json $result 'result.json'
    Assert-FlutterForeground
}
function Prepare-FocusedCaret([string]$Stage) {
    $case = [IO.Path]::GetFileName($Root)
    if ($case -notin @('plain-v-focused', 'alt-v-focused', 'posted-v-focused', 'text-focused', 'image-focused')) { return }
    if ($config.fixtureA -cne ('OTZARIA-HISTORY-QA-A-' + $case) -or $config.fixtureB -cne ('OTZARIA-HISTORY-QA-B-' + $case)) {
        throw 'The focused caret case does not match the packaged fixture identity.'
    }
    Assert-FlutterForeground
    $caret = [ordered]@{ stage = $Stage; case = $case; mechanism = 'Mapped native End after the field has focus'; foregroundBefore = [WinVQa.Native]::GetForegroundWindow().ToInt64(); inputSent = $false }
    $result.caretPreparations += $caret
    Save-Json $result 'result.json'
    $caret.key = [WinVQa.Native]::PrepareCaretEnd([IntPtr][long]$config.window, [uint32]$config.processId)
    $caret.inputSent = $true
    Start-Sleep -Milliseconds 150
    $caret.foregroundAfter = [WinVQa.Native]::GetForegroundWindow().ToInt64()
    Save-Json $result 'result.json'
    Assert-FlutterForeground
}
function Close-History($Trees, [string]$Stage) {
    $shellPids = @($Trees | Where-Object { $_.root.trustedWindowsShell -and $_.root.processName -in @('TextInputHost', 'InputApp') } | ForEach-Object { $_.root.processId } | Select-Object -Unique)
    $before = [WinVQa.Native]::GetForegroundWindow()
    [uint32]$owner = 0; [void][WinVQa.Native]::GetWindowThreadProcessId($before, [ref]$owner)
    $visibleBefore = @([WinVQa.Native]::ObserveDesktopWindows() | Where-Object { $_.sampled -and $_.visible -and $_.processId -in $shellPids })
    $closure = [ordered]@{ stage = $Stage; foregroundBefore = $before.ToInt64(); foregroundOwner = $owner; shellPids = $shellPids; visibleBefore = $visibleBefore; escapeSent = $false }
    $result.historyClosures += $closure
    $flutterOwnsForeground = $before.ToInt64() -eq $config.window -and $owner -eq $config.processId
    if ($owner -in $shellPids -or ($flutterOwnsForeground -and $visibleBefore.Count -gt 0)) {
        [WinVQa.Native]::Escape($before, $owner, $flutterOwnsForeground)
        $closure.escapeSent = $true
        Start-Sleep -Milliseconds 300
    }
    # A verified caption click can dismiss Shell UI without sending keys to another app.
    if ([WinVQa.Native]::GetForegroundWindow().ToInt64() -ne $config.window) { Focus-Flutter ($Stage + '-restore') }
    $limit = [DateTime]::UtcNow.AddSeconds(2)
    do {
        $visibleAfter = @([WinVQa.Native]::ObserveDesktopWindows() | Where-Object { $_.sampled -and $_.visible -and $_.processId -in $shellPids })
        if ($visibleAfter.Count -eq 0) { break }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $limit)
    $closure.foregroundAfter = [WinVQa.Native]::GetForegroundWindow().ToInt64()
    $closure.visibleAfter = $visibleAfter
    $closure.popupSurfaceClosed = $visibleAfter.Count -eq 0
    Capture-Screen ($Stage + '-closed')
    Save-Json $result 'result.json'
    if (!$closure.popupSurfaceClosed) { throw 'The observed history surface did not close before preparing the next opening.' }
    Assert-FlutterForeground
}
function Invoke-Clipboard([string]$Action) {
    $script:clipboardCall++
    $prefix = Join-Path $Root ('clipboard-' + $script:clipboardCall)
    $arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -STA -File "' + (Join-Path $PSScriptRoot 'windows_history_qa_clipboard.ps1') + '" -Root "' + $Root + '" -Action ' + $Action
    $child = New-Object Diagnostics.Process
    $child.StartInfo.FileName = Join-Path $PSHOME 'powershell.exe'
    $child.StartInfo.Arguments = $arguments
    $child.StartInfo.UseShellExecute = $false
    $child.StartInfo.CreateNoWindow = $true
    $child.StartInfo.RedirectStandardOutput = $true
    $child.StartInfo.RedirectStandardError = $true
    $started = $false
    try {
        $started = $child.Start()
        if (!$started) { throw 'Clipboard fixture helper did not start' }
        $stdout = $child.StandardOutput.ReadToEndAsync()
        $stderr = $child.StandardError.ReadToEndAsync()
        if (!$child.WaitForExit(5000)) { throw 'Clipboard fixture helper timed out' }
        if (!$stdout.Wait(1000) -or !$stderr.Wait(1000)) { throw 'Clipboard fixture helper output did not close' }
        [IO.File]::WriteAllText($prefix + '.stdout.txt', $stdout.Result)
        [IO.File]::WriteAllText($prefix + '.stderr.txt', $stderr.Result)
        $exitCode = $child.ExitCode
        Save-Json @{ action = $Action; processId = $child.Id; exitCode = $exitCode } ('clipboard-' + $script:clipboardCall + '.exit.json')
        if ($exitCode -ne 0) { throw ('Clipboard fixture helper exited ' + $exitCode + ': ' + $stderr.Result) }
        return $stdout.Result.Trim()
    } catch {
        [IO.File]::WriteAllText($prefix + '.failure.txt', $_.Exception.ToString())
        throw
    } finally {
        if ($started -and !$child.HasExited) { $child.Kill(); [void]$child.WaitForExit(1000) }
        $child.Dispose()
    }
}
function Seed([string]$Which) {
    $observed = Invoke-Clipboard ('seed-' + $Which)
    if ($observed -cne $Which) { throw 'Clipboard fixture seed did not round-trip' }
}
function Clipboard-Label { return (Invoke-Clipboard 'read') }
function Find-Text($Tree, [string]$Text) {
    $matches = @()
    for ($i = 1; $i -lt $Tree.nodes.Count; $i++) {
        $node = $Tree.nodes[$i].data
        if ($node.name.Contains($Text) -and $node.enabled -and !$node.offscreen -and
            !($node.name.Contains($config.fixtureA) -and $node.name.Contains($config.fixtureB))) {
            $matches += [pscustomobject]@{ tree = $Tree; index = $i; depth = $node.depth }
        }
    }
    return ($matches | Sort-Object depth -Descending | Select-Object -First 1)
}
function Save-RowTemplate($A, $B) {
    $tree = $A.tree
    $aPath = @(); $index = $A.index
    while ($index -ge 0) { $aPath += $index; $index = $tree.nodes[$index].data.parent }
    $bPath = @(); $index = $B.index
    while ($index -ge 0) { $bPath += $index; $index = $tree.nodes[$index].data.parent }
    $common = $aPath | Where-Object { $_ -in $bPath } | Select-Object -First 1
    if ($null -eq $common -or $common -eq $A.index -or $common -eq $B.index) { return }
    $rowA = $A.index
    while ($tree.nodes[$rowA].data.parent -ne $common) { $rowA = $tree.nodes[$rowA].data.parent }
    $rowB = $B.index
    while ($tree.nodes[$rowB].data.parent -ne $common) { $rowB = $tree.nodes[$rowB].data.parent }
    $a = $tree.nodes[$rowA].data; $b = $tree.nodes[$rowB].data
    if ($a.className -ne $b.className -or $a.controlType -ne $b.controlType -or $a.rectangle.y -eq $b.rectangle.y) { return }
    $parent = $tree.nodes[$common].data
    @{
        parentAutomationId = $parent.automationId; parentClassName = $parent.className
        parentControlType = $parent.controlType; rowClassName = $a.className
        rowControlType = $a.controlType; newestFirst = $b.rectangle.y -lt $a.rectangle.y
        learnedFromActualTextA = $a; learnedFromActualTextB = $b
    } | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 (Join-Path $env:REPORT_QA_HISTORY_OUTPUT 'history-row-template.json')
}
function Has-Image($Tree, [int]$Row) {
    $image = $false
    for ($i = $Row; $i -lt $Tree.nodes.Count; $i++) {
        $ancestor = $i
        while ($ancestor -ge 0 -and $ancestor -ne $Row) { $ancestor = $Tree.nodes[$ancestor].data.parent }
        if ($ancestor -ne $Row) { continue }
        $node = $Tree.nodes[$i].data
        if ($node.name -like '*OTZARIA-HISTORY-QA-*') { return $false }
        if ($node.controlType -eq 'ControlType.Image' -or $node.name -match '(?i)^image\b') { $image = $true }
    }
    return $image
}
function Find-OlderImage($Histories) {
    $path = Join-Path $env:REPORT_QA_HISTORY_OUTPUT 'history-row-template.json'
    if (!(Test-Path $path)) { return $null }
    $template = Get-Content $path -Raw | ConvertFrom-Json
    foreach ($tree in $Histories) {
        for ($parentIndex = 0; $parentIndex -lt $tree.nodes.Count; $parentIndex++) {
            $parent = $tree.nodes[$parentIndex].data
            if ($parent.automationId -cne $template.parentAutomationId -or $parent.className -cne $template.parentClassName -or
                $parent.controlType -cne $template.parentControlType) { continue }
            $rows = @()
            for ($i = 1; $i -lt $tree.nodes.Count; $i++) {
                $row = $tree.nodes[$i].data
                if ($row.parent -eq $parentIndex -and $row.className -ceq $template.rowClassName -and
                    $row.controlType -ceq $template.rowControlType -and !$row.offscreen -and $row.enabled) {
                    $rows += [pscustomobject]@{ tree = $tree; index = $i; y = $row.rectangle.y }
                }
            }
            $rows = if ($template.newestFirst) { @($rows | Sort-Object y) } else { @($rows | Sort-Object y -Descending) }
            if ($rows.Count -ge 2 -and (Has-Image $tree $rows[0].index) -and (Has-Image $tree $rows[1].index)) {
                $result['imageRowOrderLearnedFromActualTextHistory'] = $template
                return $rows[1]
            }
        }
    }
    return $null
}
if ($ValidateClipboardHelper) {
    Seed 'B'
    if ((Clipboard-Label) -ne 'B') { throw 'Clipboard helper smoke test did not preserve the fixture' }
    $failureObserved = $false
    try { [void](Invoke-Clipboard 'invalid-action') }
    catch {
        if ($_.Exception.Message -like 'Clipboard fixture helper exited 1:*') { $failureObserved = $true }
        else { throw }
    }
    if (!$failureObserved) { throw 'Clipboard helper smoke test did not preserve a failing exit code' }
    Save-Json @{ helperValidated = $true; failureExitCodeValidated = $true; nativeHelperSha256 = (File-Sha256 (Join-Path $Root 'native.dll')); historyTested = $false } 'smoke-result.json'
    exit 0
}
if ($ValidateShellVerifier) {
    Initialize-ShellVerifier
    $state = Read-HistoryState 'read-only-preflight'
    if (!$state.available) { throw 'The public history-state API is unavailable in the controller process; see result.json.' }
    exit 0
}
try {
    Save-Json @{ os = [Environment]::OSVersion.VersionString; imageOS = $env:ImageOS; imageVersion = $env:ImageVersion; flutterProcess = $config.processId; flutterWindow = $config.window; payload = $config.payload; sourceHead = $env:REPORT_QA_SOURCE_HEAD; qaHead = $env:REPORT_QA_QA_HEAD; flutterTestEnvironmentPresent = [Environment]::GetEnvironmentVariables().Contains('FLUTTER_TEST'); clipboardFormatObservationEnabled = ($env:REPORT_QA_CLIPBOARD_FORMATS -eq '1') } 'environment.json'
    Initialize-ShellVerifier
    Focus-Flutter
    try {
        $runtimeDirectory = Join-Path $env:REPORT_QA_HISTORY_OUTPUT 'runtime-x64'
        New-Item -ItemType Directory -Force $runtimeDirectory | Out-Null
        $runtimes = @(); $nativeClipboard = $null
        foreach ($module in (Get-Process -Id $config.processId).Modules) {
            if ($module.ModuleName -ieq 'super_native_extensions.dll') {
                $nativeClipboard = @{ name = $module.ModuleName; loadedFrom = $module.FileName; sha256 = (File-Sha256 $module.FileName) }
            }
            if ($module.ModuleName -notmatch '^(msvcp|vcruntime|vccorlib|concrt)[0-9].*\.dll$|^ucrtbased\.dll$') { continue }
            $target = Join-Path $runtimeDirectory $module.ModuleName
            Copy-Item $module.FileName $target -Force
            $runtimes += @{ name = $module.ModuleName; loadedFrom = $module.FileName; sha256 = (File-Sha256 $target) }
        }
        Save-Json @{ architecture = 'x64'; purpose = 'Temporary QA bundle only'; loadedRuntimeModules = $runtimes; nativeClipboard = $nativeClipboard } 'runtime-modules.json'
    } catch { Save-Json @{ error = $_.Exception.Message } 'runtime-copy-error.json' }
    [void](Snapshot '01-flutter-report-focused' $false)
    if ($config.mode -in @('plain-v', 'alt-v', 'posted-v')) {
        Seed 'B'
        if ((Clipboard-Label) -ne 'B') { throw 'Negative-control clipboard fixture verification failed' }
        $result.clipboardBeforeSelection = 'B'
        Focus-Flutter 'negative-control-before-input'
        Prepare-FocusedCaret 'negative-control-before-input'
        $result['controlForegroundBeforeInput'] = [WinVQa.Native]::GetForegroundWindow().ToInt64()
        if ($result.controlForegroundBeforeInput -ne $config.window) { throw 'Flutter lost the foreground before the negative control input.' }
        if ($config.mode -eq 'posted-v') {
            [WinVQa.Native]::PostUnmodifiedV([IntPtr][long]$config.window)
        } else { [WinVQa.Native]::TypeV($config.mode -eq 'alt-v') }
        $result['nativeControlInputSent'] = $true
        $result['controlForegroundAfterInput'] = [WinVQa.Native]::GetForegroundWindow().ToInt64()
        $result['controlMechanism'] = if ($config.mode -eq 'posted-v') { 'PostMessage WM_KEYDOWN/UP with scan=0, no modifiers' } else { 'SendInput VK_V with wScan=0; optional Alt uses MapVirtualKeyEx for the active layout; no Ctrl' }
        $result.outcome = 'native-negative-control-sent-without-history-ui'
        $result.probeCompleted = $true
        Start-Sleep -Milliseconds 700
        [void](Snapshot '02-negative-control-result' $false)
        $result['controlForegroundAtCompletion'] = [WinVQa.Native]::GetForegroundWindow().ToInt64()
        Save-Json $result 'result.json'
        exit 0
    }
    $initialHistoryState = Read-HistoryState 'before-initial-opening'
    $histories = @(); $snapshotTrees = @()
    for ($opening = 0; $opening -lt 2 -and $histories.Count -eq 0; $opening++) {
        Assert-Time
        if ($opening -gt 0) { Close-History $snapshotTrees '02-before-bounded-reopen' }
        Focus-Flutter ('history-opening-' + $opening)
        Prepare-FocusedCaret ('history-opening-' + $opening)
        Assert-FlutterForeground
        $result['historyOpeningAttempts'] = $opening + 1
        [WinVQa.Native]::OpenHistory([IntPtr][long]$config.window, [uint32]$config.processId)
        Start-Sleep -Milliseconds 1800
        $snapshotTrees = @(Snapshot ('02-win-v-opening-' + $opening))
        $histories = @(History-Trees $snapshotTrees)
        $historyDeadline = [DateTime]::UtcNow.AddSeconds(10)
        $retry = 0
        while ($histories.Count -eq 0 -and [DateTime]::UtcNow -lt $historyDeadline) {
            Assert-Time
            Start-Sleep -Milliseconds 1000
            $snapshotTrees = @(Snapshot ('02-win-v-opening-' + $opening + '-retry-' + $retry))
            $histories = @(History-Trees $snapshotTrees)
            $retry++
        }
    }
    if ($histories.Count -eq 0) {
        $result.outcome = 'history-window-not-identified'
        $result.probeCompleted = $true
        Save-Json $result 'result.json'
        exit 0
    }
    $turnOn = @()
    foreach ($tree in $histories) {
        for ($i = 0; $i -lt $tree.nodes.Count; $i++) {
            $node = $tree.nodes[$i].data
            if ($node.controlType -eq 'ControlType.Button' -and $node.name -ceq 'Turn on' -and $node.enabled -and !$node.offscreen) {
                $turnOn += [pscustomobject]@{ tree = $tree; index = $i }
            }
        }
    }
    $turnOn = @($turnOn | Group-Object { $_.tree.root.processId.ToString() + '|' + ($_.tree.nodes[$_.index].element.GetRuntimeId() -join '.') } | ForEach-Object { $_.Group[0] })
    if ($turnOn.Count -gt 1) { throw 'More than one distinct Windows history Turn on control was observed.' }
    if ($turnOn.Count -eq 1 -and (!$initialHistoryState.available -or !$initialHistoryState.enabled)) {
        Activate-Node $turnOn[0].tree $turnOn[0].index 'Enable local history through its real Turn on button' 'Turn on'
        $result.enableButtonInvoked = $true
        $stateDeadline = [DateTime]::UtcNow.AddSeconds(3)
        do {
            Start-Sleep -Milliseconds 200
            $enabledState = Read-HistoryState 'after-turn-on-click'
        } while ($enabledState.available -and !$enabledState.enabled -and [DateTime]::UtcNow -lt $stateDeadline)
        $snapshotTrees = @(Snapshot '03-after-turn-on')
        $histories = @(History-Trees $snapshotTrees)
        if ($enabledState.available -and !$enabledState.enabled) {
            Close-History $snapshotTrees '03-enable-not-confirmed'
            throw 'Windows history remained disabled after the verified Turn on click; no fixture selection was attempted.'
        }
    }
    Close-History $snapshotTrees '03-before-seeding'
    [void](Read-HistoryState 'after-preparation')
    Focus-Flutter 'before-seeding'
    Seed 'A'
    if ((Clipboard-Label) -ne 'A') { throw 'Clipboard fixture A verification failed' }
    Start-Sleep -Milliseconds 1200
    Seed 'B'
    if ((Clipboard-Label) -ne 'B') { throw 'Clipboard fixture B verification failed' }
    $result.clipboardBeforeSelection = 'B'
    Save-Json $result 'result.json'
    Start-Sleep -Milliseconds 1200
    Focus-Flutter 'before-fixture-history-opening'
    Prepare-FocusedCaret 'before-fixture-history-opening'
    Assert-FlutterForeground
    [WinVQa.Native]::OpenHistory([IntPtr][long]$config.window, [uint32]$config.processId)
    Start-Sleep -Milliseconds 1800
    $candidate = $null
    for ($attempt = 0; $attempt -lt 3 -and $null -eq $candidate; $attempt++) {
        $histories = @(History-Trees @(Snapshot ("04-history-A-after-B-" + $attempt)))
        if ($histories.Count -gt 0) { $result.historyWindowIdentified = $true }
        if ($config.payload -eq 'text') {
            foreach ($tree in $histories) {
                $a = Find-Text $tree $config.fixtureA
                $b = Find-Text $tree $config.fixtureB
                if ($null -ne $a -and $null -ne $b) { Save-RowTemplate $a $b; $candidate = $a; break }
            }
        } else { $candidate = Find-OlderImage $histories }
        if ($null -eq $candidate) { Start-Sleep -Milliseconds 600 }
    }
    if ($null -eq $candidate) {
        $result.outcome = if ($result.historyWindowIdentified) { 'history-visible-but-fixture-selection-not-identified' } else { 'history-window-not-identified' }
    } else {
        if ((Clipboard-Label) -ne 'B') { throw 'Current clipboard must still be B immediately before choosing older A' }
        $expected = if ($config.payload -eq 'text') { $config.fixtureA } else { '<image-row>' }
        Activate-Node $candidate.tree $candidate.index 'Select older fixture A through the actual Windows history UI' $expected
        if ($config.payload -eq 'image' -and $env:REPORT_QA_CLIPBOARD_FORMATS -eq '1') { Read-ClipboardFormats 'after-history-click-before-image-read' }
        $limit = [DateTime]::UtcNow.AddSeconds(5)
        do {
            Start-Sleep -Milliseconds 100
            $result.clipboardAfterSelection = Clipboard-Label
        } while ($result.clipboardAfterSelection -ne 'A' -and [DateTime]::UtcNow -lt $limit)
        $result.historySelectionVerified = $result.clipboardAfterSelection -eq 'A'
        $result.outcome = if ($result.historySelectionVerified) { 'real-history-selected-A-after-B' } else { 'history-selection-did-not-select-A' }
        # Post-paste evidence must not activate a Shell accessibility provider.
        [void](Snapshot '05-after-real-history-selection' $false)
        if ($config.payload -eq 'image' -and $env:REPORT_QA_CLIPBOARD_FORMATS -eq '1') { Read-ClipboardFormats 'after-image-label-verification' }
    }
    $result.probeCompleted = $true
    Save-Json $result 'result.json'
} catch {
    $result.outcome = 'probe-error'
    $result.error = $_.Exception.ToString()
    Save-Json $result 'result.json'
    try { Capture-Screen '98-error' } catch { }
    Write-Error $_ -ErrorAction Continue
    exit 1
} finally {
    [void][WinVQa.Native]::SetCursorPos($originalCursor.X, $originalCursor.Y)
}
