param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$Action)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($Action -ceq 'history-state') {
    Import-Module -Name (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1') -Force -ErrorAction Stop
    $state = [ordered]@{
        available = $false; enabled = $null; error = $null; hresult = $null
        processId = $PID; psVersion = [string]$PSVersionTable.PSVersion
        apartmentState = [string][Threading.Thread]::CurrentThread.GetApartmentState()
        inputSent = $false; clipboardChanged = $false
    }
    try {
        if ($state.apartmentState -cne 'STA') { throw 'History-state observation requires the STA helper.' }
        $null = [Windows.ApplicationModel.DataTransfer.Clipboard, Windows.ApplicationModel.DataTransfer, ContentType = WindowsRuntime]
        $state.enabled = [Windows.ApplicationModel.DataTransfer.Clipboard]::IsHistoryEnabled()
        $state.available = $true
    } catch { $state.error = $_.Exception.ToString(); $state.hresult = $_.Exception.GetBaseException().HResult }
    Write-Output ($state | ConvertTo-Json -Compress)
    exit 0
}
if ($Action -ceq 'format-metadata') {
    Import-Module -Name (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1') -Force -ErrorAction Stop
    $observation = [ordered]@{
        utc = [DateTime]::UtcNow.ToString('o'); available = $false; error = $null
        processId = $PID; apartmentState = [string][Threading.Thread]::CurrentThread.GetApartmentState()
        inputSent = $false; clipboardWritePerformed = $false; dataReadPerformed = $false; formats = $null
    }
    try {
        Add-Type -Path (Join-Path $Root 'native.dll')
        $observation.formats = [WinVQa.Native]::ObserveClipboardFormats()
        $observation.available = $observation.formats.nativeComplete -and $observation.formats.oleComplete
    } catch { $observation.error = $_.Exception.ToString() }
    Write-Output ($observation | ConvertTo-Json -Compress -Depth 8)
    exit 0
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -Path (Join-Path $Root 'native.dll')
$config = Get-Content (Join-Path $Root 'case.json') -Raw | ConvertFrom-Json
$ownerWindow = New-Object Windows.Forms.Form
$clipboardOwner = $ownerWindow.Handle
function Seed([string]$Which) {
    for ($attempt = 0; $attempt -lt 5; $attempt++) {
        try {
            if ($config.payload -eq 'image') {
                $color = if ($Which -eq 'A') { $config.imageA } else { $config.imageB }
                [WinVQa.Native]::SetFixtureBitmap($clipboardOwner, $color[0], $color[1], $color[2])
            } else {
                $text = if ($Which -eq 'A') { $config.fixtureA } else { $config.fixtureB }
                if ($text -notmatch '^OTZARIA-HISTORY-QA-[AB]-[a-z-]+$') { throw 'Refusing non-fixture text' }
                [WinVQa.Native]::SetFixtureText($clipboardOwner, $text)
            }
            return
        } catch { if ($attempt -eq 4) { throw }; Start-Sleep -Milliseconds 100 }
    }
}
function Clipboard-Label {
    if ($config.payload -eq 'text') {
        $text = [Windows.Forms.Clipboard]::GetText()
        if ($text -ceq $config.fixtureA) { return 'A' }
        if ($text -ceq $config.fixtureB) { return 'B' }
        return 'other'
    }
    $image = [Windows.Forms.Clipboard]::GetImage()
    if ($null -eq $image) { return 'no-image' }
    $bitmap = New-Object Drawing.Bitmap($image)
    try {
        if ($bitmap.Width -ne 4 -or $bitmap.Height -ne 4) { return 'other-image-size' }
        $pixel = $bitmap.GetPixel(0, 0)
        foreach ($which in @('A', 'B')) {
            $color = if ($which -eq 'A') { $config.imageA } else { $config.imageB }
            if ($pixel.R -eq $color[0] -and $pixel.G -eq $color[1] -and $pixel.B -eq $color[2]) { return $which }
        }
        return 'other-image'
    } finally { $bitmap.Dispose(); $image.Dispose() }
}

try {
    switch ($Action) {
        'seed-A' { Seed 'A' }
        'seed-B' { Seed 'B' }
        'read' { }
        default { throw 'Unknown clipboard fixture action' }
    }
    Write-Output (Clipboard-Label)
} finally { $ownerWindow.Dispose() }
