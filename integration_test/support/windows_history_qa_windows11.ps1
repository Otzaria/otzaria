$ErrorActionPreference = 'Stop'
$bundle = (Resolve-Path flutter-history-x64).Path
$metadata = Get-Content "$bundle/qa-bundle.json" -Raw | ConvertFrom-Json
if ($metadata.qaHead -ne $env:REPORT_QA_AFTER_HEAD -or $metadata.sourceHead -ne $env:REPORT_QA_PRODUCT_HEAD -or
    $metadata.architecture -ne 'x64' -or $metadata.requiresFlutterTestRunner -ne $false) {
  throw 'Unexpected source bundle contract.'
}
Copy-Item "$bundle/qa-bundle.json" "$env:REPORT_QA_ARTIFACT_ROOT/qa-bundle.json"
$nativeSource = @'
using System;
using System.Collections.Generic;
using System.Text;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class QaProcessArchitecture {
  [StructLayout(LayoutKind.Sequential)] public struct MachineInfo { public ushort ProcessMachine; public ushort Reserved; public uint Attributes; }
  [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetProcessInformation(IntPtr process, int kind, out MachineInfo info, uint size);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool IsWow64Process2(IntPtr process, out ushort wowMachine, out ushort nativeMachine);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
  public static uint[] Read(int pid) {
    IntPtr handle = OpenProcess(0x1000, false, pid);
    if (handle == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
    try {
      MachineInfo machine; ushort wow, native;
      if (!GetProcessInformation(handle, 9, out machine, (uint)Marshal.SizeOf(typeof(MachineInfo))) ||
          !IsWow64Process2(handle, out wow, out native)) throw new Win32Exception(Marshal.GetLastWin32Error());
      return new uint[] { machine.ProcessMachine, native, wow, machine.Attributes };
    } finally { CloseHandle(handle); }
  }
}
public sealed class QaWindowState {
  public long Hwnd;
  public uint ProcessId, ThreadId;
  public string ClassName, Title;
  public bool Visible;
  public int Left, Top, Right, Bottom;
}
public sealed class QaDesktopState {
  public string ThreadDesktop, InputDesktop, WindowStation;
  public int InputDesktopError;
  public bool StationVisible;
}
public sealed class QaCaptionPoint {
  public int X, Y, HitTest;
  public long WindowAtPoint;
  public bool Verified;
}
public static class QaWindowActivation {
  [StructLayout(LayoutKind.Sequential)] struct Rect { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] struct Point { public int X, Y; }
  [StructLayout(LayoutKind.Sequential)] struct UserFlags { public int Inherit, Reserved; public uint Flags; }
  [StructLayout(LayoutKind.Sequential)] struct MouseInput {
    public int X, Y; public uint MouseData, Flags, Time; public UIntPtr ExtraInfo;
  }
  [StructLayout(LayoutKind.Explicit)] struct InputUnion { [FieldOffset(0)] public MouseInput Mouse; }
  [StructLayout(LayoutKind.Sequential)] struct Input { public uint Type; public InputUnion Data; }
  delegate bool EnumCallback(IntPtr window, IntPtr data);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumCallback callback, IntPtr data);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr window, StringBuilder text, int count);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr window, StringBuilder text, int count);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr window, out Rect rect);
  [DllImport("user32.dll")] static extern bool ShowWindowAsync(IntPtr window, int command);
  [DllImport("user32.dll")] static extern bool IsIconic(IntPtr window);
  [DllImport("user32.dll", SetLastError=true)] static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
  [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(Point point);
  [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr window, uint flags);
  [DllImport("user32.dll", SetLastError=true)] static extern IntPtr SendMessageTimeout(IntPtr window, uint message, UIntPtr wparam, IntPtr lparam, uint flags, uint timeout, out UIntPtr result);
  [DllImport("user32.dll", SetLastError=true)] static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] static extern bool GetCursorPos(out Point point);
  [DllImport("user32.dll", SetLastError=true)] static extern uint SendInput(uint count, Input[] inputs, int size);
  [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
  [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern int GetPackageFamilyName(IntPtr process, ref uint length, StringBuilder name);
  public static string PackageFamily(uint pid) {
    IntPtr process=OpenProcess(0x1000,false,pid);
    if (process==IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
    try {
      uint length=0; int status=GetPackageFamilyName(process,ref length,null);
      if (status==15700) return null;
      if (status!=122) throw new Win32Exception(status);
      var name=new StringBuilder((int)length);
      status=GetPackageFamilyName(process,ref length,name);
      if (status!=0) throw new Win32Exception(status);
      return name.ToString();
    } finally { CloseHandle(process); }
  }
  public static void ClickPrivacyPoint(IntPtr window, uint expectedPid, int x, int y) {
    QaWindowState state=Read(window);
    if (GetForegroundWindow()!=window || state.ProcessId!=expectedPid || !state.Visible ||
        state.ClassName!="Windows.UI.Core.CoreWindow" || state.Title!="Microsoft account" ||
        PackageFamily(expectedPid)!="Microsoft.Windows.CloudExperienceHost_cw5n1h2txyewy" ||
        x<state.Left || x>=state.Right || y<state.Top || y>=state.Bottom ||
        GetAncestor(WindowFromPoint(new Point { X=x, Y=y }),2)!=window)
      throw new Exception("The observed privacy control is not owned by the verified foreground CloudExperienceHost.");
    ClickPoint(x,y);
  }
  [DllImport("user32.dll")] static extern IntPtr GetThreadDesktop(uint thread);
  [DllImport("user32.dll")] static extern IntPtr GetProcessWindowStation();
  [DllImport("user32.dll", SetLastError=true)] static extern IntPtr OpenInputDesktop(uint flags, bool inherit, uint access);
  [DllImport("user32.dll")] static extern bool CloseDesktop(IntPtr desktop);
  [DllImport("user32.dll", EntryPoint="GetUserObjectInformationW", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool UserObjectName(IntPtr handle, int index, StringBuilder data, uint length, out uint needed);
  [DllImport("user32.dll", EntryPoint="GetUserObjectInformationW", SetLastError=true)] static extern bool UserObjectFlags(IntPtr handle, int index, out UserFlags flags, uint length, out uint needed);

  public static QaWindowState Read(IntPtr window) {
    uint process; uint thread = GetWindowThreadProcessId(window, out process);
    var className = new StringBuilder(256); var title = new StringBuilder(512);
    GetClassName(window, className, className.Capacity); GetWindowText(window, title, title.Capacity);
    Rect rect; GetWindowRect(window, out rect);
    return new QaWindowState { Hwnd=window.ToInt64(), ProcessId=process, ThreadId=thread,
      ClassName=className.ToString(), Title=title.ToString(), Visible=IsWindowVisible(window),
      Left=rect.Left, Top=rect.Top, Right=rect.Right, Bottom=rect.Bottom };
  }
  public static QaWindowState[] Windows() {
    var result = new List<QaWindowState>();
    EnumWindows((window, data) => { result.Add(Read(window)); return true; }, IntPtr.Zero);
    return result.ToArray();
  }
  static string Name(IntPtr handle) {
    if (handle == IntPtr.Zero) return null;
    uint needed; var name = new StringBuilder(256);
    return UserObjectName(handle, 2, name, 512, out needed) ? name.ToString() : null;
  }
  public static QaDesktopState Desktop() {
    IntPtr station = GetProcessWindowStation(); uint needed; UserFlags flags;
    var state = new QaDesktopState {
      ThreadDesktop=Name(GetThreadDesktop(GetCurrentThreadId())), WindowStation=Name(station),
      StationVisible=UserObjectFlags(station, 1, out flags, (uint)Marshal.SizeOf(typeof(UserFlags)), out needed) && (flags.Flags & 1) != 0 };
    IntPtr input = OpenInputDesktop(0, false, 1);
    if (input == IntPtr.Zero) state.InputDesktopError=Marshal.GetLastWin32Error();
    else { try { state.InputDesktop=Name(input); } finally { CloseDesktop(input); } }
    return state;
  }
  static void RequireOwnWindow(IntPtr window, uint expectedPid) {
    QaWindowState observed=Read(window);
    if (observed.ProcessId != expectedPid || observed.ClassName != "FLUTTER_RUNNER_WIN32_WINDOW")
      throw new Exception("The activation target is not the observed Flutter process/window.");
  }
  public static void Raise(IntPtr window, uint expectedPid) {
    RequireOwnWindow(window, expectedPid);
    ShowWindowAsync(window, IsIconic(window) ? 9 : 5);
    if (!SetWindowPos(window, IntPtr.Zero, 0, 0, 0, 0, 0x4053))
      throw new Win32Exception(Marshal.GetLastWin32Error());
  }
  static int HitTest(IntPtr window, int x, int y) {
    uint packed = ((uint)(ushort)y << 16) | (ushort)x; UIntPtr result;
    if (SendMessageTimeout(window, 0x84, UIntPtr.Zero, new IntPtr(unchecked((int)packed)), 2, 500, out result) == IntPtr.Zero) return -1;
    return unchecked((int)result.ToUInt64());
  }
  public static QaCaptionPoint[] CaptionPoints(IntPtr window, uint expectedPid) {
    RequireOwnWindow(window, expectedPid); QaWindowState state=Read(window);
    var result = new List<QaCaptionPoint>();
    int[] columns = { state.Left+(state.Right-state.Left)/2, state.Left+48 };
    foreach (int x in columns) {
      if (x<state.Left || x>=state.Right) continue;
      for (int offset=8; offset<=48 && state.Top+offset<state.Bottom; offset+=4) {
        int y=state.Top+offset; int hit=HitTest(window,x,y);
        IntPtr at=GetAncestor(WindowFromPoint(new Point { X=x, Y=y }),2);
        result.Add(new QaCaptionPoint { X=x, Y=y, HitTest=hit, WindowAtPoint=at.ToInt64(),
          Verified=state.Visible && hit==2 && at==window });
      }
    }
    return result.ToArray();
  }
  public static void ClickCaption(IntPtr window, uint expectedPid, int x, int y) {
    RequireOwnWindow(window,expectedPid); QaWindowState state=Read(window);
    if (!state.Visible || x<state.Left || x>=state.Right || y<state.Top || y>=state.Bottom ||
        HitTest(window,x,y)!=2 || GetAncestor(WindowFromPoint(new Point { X=x, Y=y }),2)!=window)
      throw new Exception("The observed title-bar point is no longer owned by the target Flutter window.");
    ClickPoint(x,y);
  }
  static void ClickPoint(int x, int y) {
    Point previous; bool hadCursor=GetCursorPos(out previous);
    try {
      if (!SetCursorPos(x,y)) throw new Win32Exception(Marshal.GetLastWin32Error());
      var down=new Input(); down.Data.Mouse.Flags=2;
      var up=new Input(); up.Data.Mouse.Flags=4;
      uint sent=SendInput(2,new[] { down,up },Marshal.SizeOf(typeof(Input)));
      if (sent!=2) { SendInput(1,new[] { up },Marshal.SizeOf(typeof(Input))); throw new Exception("Observed UI click accepted "+sent+" of 2 mouse inputs."); }
    } finally { if (hadCursor) SetCursorPos(previous.X,previous.Y); }
  }
}
'@
$nativeSourcePath = Join-Path $env:REPORT_QA_ARTIFACT_ROOT 'activation-native.cs'
[IO.File]::WriteAllText($nativeSourcePath, $nativeSource, [Text.UTF8Encoding]::new($false))
@{ workflowHead = $env:REPORT_QA_WORKFLOW_HEAD; sourceSha256 = (Get-FileHash $nativeSourcePath -Algorithm SHA256).Hash; productHead = $env:REPORT_QA_PRODUCT_HEAD; sourceQaHead = $env:REPORT_QA_AFTER_HEAD } |
  ConvertTo-Json | Set-Content -Encoding utf8 (Join-Path $env:REPORT_QA_ARTIFACT_ROOT 'activation-source.json')
Add-Type -TypeDefinition $nativeSource
Add-Type -AssemblyName System.Windows.Forms, System.Drawing, UIAutomationClient, UIAutomationTypes
function Read-QaAutomationBranch($Element, [int]$Depth, [int]$Parent, $Nodes, $Budget, $Walker) {
  if ($Depth -gt 16 -or $Budget.remaining -le 0) { return }
  try {
    $state = $Element.Current
    $index = $Nodes.Count
    $Nodes.Add(@{ parent = $Parent; depth = $Depth; name = $state.Name; automationId = $state.AutomationId;
      className = $state.ClassName; controlType = $state.ControlType.ProgrammaticName; processId = $state.ProcessId;
      enabled = $state.IsEnabled; offscreen = $state.IsOffscreen; rectangle = $state.BoundingRectangle.ToString() })
    $Budget.remaining--
    $child = $walker.GetFirstChild($Element)
    while ($null -ne $child -and $Budget.remaining -gt 0) {
      Read-QaAutomationBranch $child ($Depth + 1) $index $Nodes $Budget $Walker
      $child = $walker.GetNextSibling($child)
    }
  } catch { $Nodes.Add(@{ error = $_.Exception.Message; depth = $Depth; parent = $Parent }) }
}
function Save-QAWindowSnapshot([string]$Name) {
  $state = @{
    recordedAt = [DateTime]::UtcNow.ToString('o'); workflowHead = $env:REPORT_QA_WORKFLOW_HEAD
    processId = $PID; sessionId = (Get-Process -Id $PID).SessionId
    desktop = [QaWindowActivation]::Desktop(); foreground = [QaWindowActivation]::Read([QaWindowActivation]::GetForegroundWindow())
    windows = @([QaWindowActivation]::Windows()); foregroundAutomation = @()
  }
  $state['processes'] = @((@($state.windows.ProcessId) + @($state.foreground.ProcessId)) | Sort-Object -Unique | ForEach-Object {
    $observedPid = $_
    try {
      $observedProcess = Get-Process -Id $observedPid -ErrorAction Stop
      $entry = @{ processId = $observedProcess.Id; name = $observedProcess.ProcessName; path = $observedProcess.Path; sessionId = $observedProcess.SessionId }
      if ($observedPid -eq $state.foreground.ProcessId) {
        try { $entry['packageFamily'] = [QaWindowActivation]::PackageFamily([uint32]$observedPid) } catch { $entry['packageError'] = $_.Exception.Message }
        try {
          $signature = Get-AuthenticodeSignature -FilePath $observedProcess.Path -ErrorAction Stop
          $entry['signatureStatus'] = $signature.Status.ToString(); $entry['signerSubject'] = $signature.SignerCertificate.Subject
        } catch { $entry['signatureError'] = $_.Exception.Message }
      }
      $entry
    } catch { @{ processId = $observedPid; error = $_.Exception.Message } }
  })
  $jsonPath = Join-Path $env:REPORT_QA_ARTIFACT_ROOT ($Name + '.json')
  $state | ConvertTo-Json -Depth 10 | Set-Content -Encoding utf8 $jsonPath
  try {
    $bounds = [Windows.Forms.SystemInformation]::VirtualScreen
    $bitmap = New-Object Drawing.Bitmap($bounds.Width, $bounds.Height)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
      $graphics.CopyFromScreen($bounds.Location, [Drawing.Point]::Empty, $bounds.Size)
      $bitmap.Save((Join-Path $env:REPORT_QA_ARTIFACT_ROOT ($Name + '.png')), [Drawing.Imaging.ImageFormat]::Png)
    } finally { $graphics.Dispose(); $bitmap.Dispose() }
  } catch { $state['screenshotError'] = $_.Exception.Message }
  try {
    $nodes = New-Object 'Collections.Generic.List[object]'
    $budget = @{ remaining = 200 }
    $element = $null
    $isFlutter = $state.foreground.ClassName -in @('FLUTTER_RUNNER_WIN32_WINDOW', 'FLUTTERVIEW')
    if ($isFlutter) { $state['automationSkipped'] = 'Flutter uses Win32 metadata and screenshot only; do not enable platform semantics during a test.' }
    if (!$isFlutter -and $state.foreground.Hwnd -ne 0) {
      $element = [Windows.Automation.AutomationElement]::FromHandle([IntPtr]$state.foreground.Hwnd)
      Read-QaAutomationBranch $element 0 -1 $nodes $budget ([Windows.Automation.TreeWalker]::ControlViewWalker)
    }
    $state.foregroundAutomation = @($nodes.ToArray())
    $state['remainingAutomationBudget'] = $budget.remaining
    $rawNodes = New-Object 'Collections.Generic.List[object]'; $rawBudget = @{ remaining = 600 }
    if ($null -ne $element) { Read-QaAutomationBranch $element 0 -1 $rawNodes $rawBudget ([Windows.Automation.TreeWalker]::RawViewWalker) }
    $state['foregroundRawAutomation'] = @($rawNodes.ToArray()); $state['remainingRawAutomationBudget'] = $rawBudget.remaining
  } catch { $state['automationError'] = $_.Exception.Message }
  $state | ConvertTo-Json -Depth 10 | Set-Content -Encoding utf8 $jsonPath
  return $state
}
function Activate-QAFlutterWindow([Diagnostics.Process]$Application) {
  $deadline = [DateTime]::UtcNow.AddSeconds(40)
  $target = $null
  do {
    $candidates = @([QaWindowActivation]::Windows() | Where-Object {
      $_.ProcessId -eq $Application.Id -and $_.ClassName -ceq 'FLUTTER_RUNNER_WIN32_WINDOW' -and $_.Visible
    })
    if ($candidates.Count -gt 1) { throw 'More than one visible Flutter runner window was found before the first case.' }
    if ($candidates.Count -eq 1) { $target = $candidates[0]; break }
    if ($Application.HasExited) { throw 'Flutter exited before its visible window could be observed.' }
    Start-Sleep -Milliseconds 100
  } while ([DateTime]::UtcNow -lt $deadline)
  $before = Save-QAWindowSnapshot '01-before-activation'
  if ($null -eq $target) { throw 'No visible owned Flutter runner window was observed for activation.' }
  $desktop = $before.desktop
  if (!$desktop.StationVisible -or [string]::IsNullOrWhiteSpace($desktop.InputDesktop) -or
      $desktop.InputDesktop -ine $desktop.ThreadDesktop) {
    throw 'The runner does not expose this process desktop as the visible input desktop; no activation click is permitted.'
  }
  $window = [IntPtr]$target.Hwnd
  $activation = @{ workflowHead = $env:REPORT_QA_WORKFLOW_HEAD; target = $target;
    originalForeground = $before.foreground; mechanism = 'already-foreground'; titleBarClickSent = $false }
  $activationPath = Join-Path $env:REPORT_QA_ARTIFACT_ROOT 'activation.json'
  try {
    if ([QaWindowActivation]::GetForegroundWindow() -ne $window) {
      [QaWindowActivation]::Raise($window, [uint32]$Application.Id)
      $activation['setForegroundReturned'] = [QaWindowActivation]::SetForegroundWindow($window)
      $activation.mechanism = 'ShowWindowAsync/SetWindowPos/SetForegroundWindow'
      Start-Sleep -Milliseconds 200
    }
    if ([QaWindowActivation]::GetForegroundWindow() -ne $window) {
      [void](Save-QAWindowSnapshot '02-before-titlebar-click')
      $points = @([QaWindowActivation]::CaptionPoints($window, [uint32]$Application.Id))
      $activation['captionPoints'] = $points
      $activation | ConvertTo-Json -Depth 10 | Set-Content -Encoding utf8 $activationPath
      $point = $points | Where-Object { $_.Verified } | Select-Object -First 1
      if ($null -eq $point) { throw 'The Flutter title bar is not a verified visible click target; inspect the captured blocking window.' }
      [QaWindowActivation]::ClickCaption($window, [uint32]$Application.Id, $point.X, $point.Y)
      $activation.titleBarClickSent = $true
      $activation.mechanism = 'Verified native mouse click on the owned Flutter title bar'
    }
    $deadline = [DateTime]::UtcNow.AddSeconds(2)
    while ([QaWindowActivation]::GetForegroundWindow() -ne $window -and [DateTime]::UtcNow -lt $deadline) {
      Start-Sleep -Milliseconds 50
    }
    $activation['observedForeground'] = [QaWindowActivation]::Read([QaWindowActivation]::GetForegroundWindow())
    $activation['foregroundVerified'] = $activation.observedForeground.Hwnd -eq $target.Hwnd
    if (!$activation.foregroundVerified) { throw 'The real foreground still does not belong to Flutter after bounded activation.' }
  } finally {
    $activation | ConvertTo-Json -Depth 10 | Set-Content -Encoding utf8 $activationPath
    [void](Save-QAWindowSnapshot '03-after-activation')
  }
}
$ocrSource = @'
param([Parameter(Mandatory=$true)][string]$ImagePath, [Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Runtime.WindowsRuntime
[void][Windows.Storage.StorageFile, Windows.Storage, ContentType=WindowsRuntime]
[void][Windows.Storage.Streams.IRandomAccessStream, Windows.Storage.Streams, ContentType=WindowsRuntime]
[void][Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType=WindowsRuntime]
[void][Windows.Graphics.Imaging.SoftwareBitmap, Windows.Foundation, ContentType=WindowsRuntime]
[void][Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType=WindowsRuntime]
[void][Windows.Media.Ocr.OcrResult, Windows.Foundation, ContentType=WindowsRuntime]
function Await-WinRt($Operation, [Type]$ResultType) {
  $method = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.IsGenericMethodDefinition -and $_.GetGenericArguments().Count -eq 1 -and
    $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
  } | Select-Object -First 1
  if ($null -eq $method) { throw 'The public WinRT task adapter is unavailable.' }
  $task = $method.MakeGenericMethod($ResultType).Invoke($null, @($Operation))
  if (!$task.Wait(15000)) { throw 'The local Windows OCR operation timed out.' }
  return $task.Result
}
$file = Await-WinRt ([Windows.Storage.StorageFile]::GetFileFromPathAsync($ImagePath)) ([Windows.Storage.StorageFile])
$stream = Await-WinRt ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
try {
  $decoder = Await-WinRt ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
  $bitmap = Await-WinRt ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
  try {
    $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
    if ($null -eq $engine) { throw 'No installed local Windows OCR language is available.' }
    $ocr = Await-WinRt ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
    $result = @{ recordedAt = [DateTime]::UtcNow.ToString('o'); language = $engine.RecognizerLanguage.LanguageTag;
      width = $bitmap.PixelWidth; height = $bitmap.PixelHeight; text = $ocr.Text; lines = @($ocr.Lines | ForEach-Object {
        @{ text = $_.Text; words = @($_.Words | ForEach-Object {
          @{ text = $_.Text; x = $_.BoundingRect.X; y = $_.BoundingRect.Y; width = $_.BoundingRect.Width; height = $_.BoundingRect.Height }
        }) }
      }) }
    $result['fullFrameLines'] = $result.lines
    $result['valueCrops'] = @()
    $result | ConvertTo-Json -Depth 12 | Set-Content -Encoding utf8 $OutputPath
    $labels = @($result.lines | Where-Object { $_.text.Trim() -match '^(Location|Find my device|Inking\s*&\s*typing|Personalized offers)$' -and
      $_.words[0].x -ge 540 -and $_.words[0].x -le 570 -and $_.words[0].y -gt 230 -and $_.words[0].y -lt 600 } | Sort-Object { $_.words[0].y })
    if ($bitmap.PixelWidth -ne 1024 -or $bitmap.PixelHeight -ne 768) { throw 'Value crops require the reviewed 1024x768 privacy surface.' }
    $names = @($labels | ForEach-Object { $_.text.Trim() -replace '\s+', ' ' })
    $firstNames = @('Location', 'Find my device', 'Inking & typing')
    $finalNames = $firstNames + @('Personalized offers')
    $lastBottom = 625
    if (($names -join '|') -ceq ($firstNames -join '|')) {
      $result['privacyPage'] = 'initial'
    } elseif ($names.Count -ge 1 -and $names.Count -le 4 -and
        ($names -join '|') -ceq (($finalNames | Select-Object -Last $names.Count) -join '|')) {
      $footer = @($result.lines | Where-Object { $_.text -match '^Select Learn more for info on the above settings' -and
        $_.words[0].x -ge 540 -and $_.words[0].x -le 570 -and $_.words[0].y -gt 500 -and $_.words[0].y -lt 600 })
      $accept = @($result.lines | Where-Object { $_.text.Trim() -ceq 'Accept' -and $_.words.Count -eq 1 -and
        $_.words[0].x -gt 780 -and $_.words[0].x -lt 900 -and $_.words[0].y -gt 620 -and $_.words[0].y -lt 690 })
      if ($footer.Count -ne 1 -or $accept.Count -ne 1) { throw 'The final privacy profile requires its observed footer and Accept button.' }
      $lastBottom = [int]$footer[0].words[0].y - 8
      $result['privacyPage'] = 'final'
    } else { throw 'The visible setting labels do not match either reviewed privacy profile.' }
    $result | ConvertTo-Json -Depth 12 | Set-Content -Encoding utf8 $OutputPath
    $values = @()
    for ($index = 0; $index -lt $labels.Count; $index++) {
      $label = $labels[$index]
      $top = [int][Math]::Ceiling(($label.words | ForEach-Object { $_.y + $_.height } | Measure-Object -Maximum).Maximum + 8)
      $bottom = if ($index + 1 -lt $labels.Count) { [int]$labels[$index + 1].words[0].y - 8 } else { $lastBottom }
      if ($top -lt 250 -or $bottom -gt 625 -or $bottom -le $top -or $bottom - $top -gt 200) { throw 'Unrecognized privacy value crop geometry.' }
      $scale = 4
      $transform = [Windows.Graphics.Imaging.BitmapTransform]::new()
      $transform.ScaledWidth = $bitmap.PixelWidth * $scale; $transform.ScaledHeight = $bitmap.PixelHeight * $scale
      $bounds = [Windows.Graphics.Imaging.BitmapBounds]::new()
      $bounds.X = 598 * $scale; $bounds.Y = $top * $scale; $bounds.Width = 60 * $scale; $bounds.Height = ($bottom - $top) * $scale
      $transform.Bounds = $bounds
      $crop = Await-WinRt ($decoder.GetSoftwareBitmapAsync([Windows.Graphics.Imaging.BitmapPixelFormat]::Bgra8,
        [Windows.Graphics.Imaging.BitmapAlphaMode]::Premultiplied, $transform,
        [Windows.Graphics.Imaging.ExifOrientationMode]::IgnoreExifOrientation, [Windows.Graphics.Imaging.ColorManagementMode]::DoNotColorManage)) ([Windows.Graphics.Imaging.SoftwareBitmap])
      try {
        $recognized = Await-WinRt ($engine.RecognizeAsync($crop)) ([Windows.Media.Ocr.OcrResult])
        $cropLines = @($recognized.Lines | ForEach-Object {
          @{ text = $_.Text; sourceLabel = $label.text; words = @($_.Words | ForEach-Object {
            @{ text = $_.Text; x = 598 + $_.BoundingRect.X / $scale; y = $top + $_.BoundingRect.Y / $scale;
              width = $_.BoundingRect.Width / $scale; height = $_.BoundingRect.Height / $scale }
          }) }
        })
        $read = @{ label = $label.text; sourceBounds = @{ x = 598; y = $top; width = 60; height = $bottom - $top };
          scale = $scale; text = $recognized.Text; mappedLines = $cropLines }
        $result.valueCrops += $read
        $result | ConvertTo-Json -Depth 12 | Set-Content -Encoding utf8 $OutputPath
        $value = @($cropLines | Where-Object { $_.text.Trim() -cmatch '^(Yes|No)$' -and $_.words.Count -eq 1 })
        if ($value.Count -ne 1) { throw ('No unique literal Yes/No in the crop associated with ' + $label.text) }
        $original = @($result.fullFrameLines | Where-Object { $_.text.Trim() -cmatch '^(Yes|No)$' -and $_.words.Count -eq 1 -and
          [Math]::Abs(($_.words[0].y + $_.words[0].height / 2) - ($value[0].words[0].y + $value[0].words[0].height / 2)) -lt 10 })
        if (@($original | Where-Object { $_.text -cne $value[0].text }).Count -gt 0) { throw 'Cropped and full-frame OCR disagree about a privacy value.' }
        $values += $value[0]
      } finally { $crop.Dispose() }
    }
    $result.lines = @($result.fullFrameLines | Where-Object { $_.text.Trim() -cnotmatch '^(Yes|No)$' }) + $values
    $result | ConvertTo-Json -Depth 10 | Set-Content -Encoding utf8 $OutputPath
  } finally { $bitmap.Dispose() }
} finally { $stream.Dispose() }
'@
$script:privacyOcrPath = Join-Path $env:REPORT_QA_ARTIFACT_ROOT 'privacy-ocr.ps1'
[IO.File]::WriteAllText($script:privacyOcrPath, $ocrSource)
@{ sha256 = (Get-FileHash $script:privacyOcrPath).Hash; workflowHead = $env:REPORT_QA_WORKFLOW_HEAD; localWindowsOcrOnly = $true } | ConvertTo-Json | Set-Content -Encoding utf8 "$env:REPORT_QA_ARTIFACT_ROOT/privacy-ocr-source.json"
function Assert-QAPrivacyIdentity($Snapshot) {
  $foreground = $Snapshot.foreground
  $identity = @($Snapshot.processes | Where-Object { $_.processId -eq $foreground.ProcessId })
  if ($identity.Count -ne 1 -or $foreground.ClassName -cne 'Windows.UI.Core.CoreWindow' -or
      $foreground.Title -cne 'Microsoft account' -or !$foreground.Visible -or
      $identity[0].path -ine (Join-Path ([Environment]::SystemDirectory) 'WWAHost.exe') -or
      $identity[0].packageFamily -cne 'Microsoft.Windows.CloudExperienceHost_cw5n1h2txyewy' -or
      $identity[0].signatureStatus -ne 'Valid' -or $identity[0].signerSubject -notmatch 'CN=Microsoft Windows(?:,|$)' -or
      $identity[0].sessionId -ne $Snapshot.sessionId -or !$Snapshot.desktop.StationVisible -or
      $Snapshot.desktop.InputDesktop -cne $Snapshot.desktop.ThreadDesktop) {
    throw 'Only the observed, signed, same-session Windows CloudExperienceHost privacy screen may be operated.'
  }
  if ($foreground.Left -ne 0 -or $foreground.Top -ne 0 -or $foreground.Right -ne 1024 -or $foreground.Bottom -ne 768) {
    throw 'The privacy surface no longer has the visually reviewed 1024x768 layout.'
  }
  return $identity[0]
}
function Read-QALocalOcr([string]$ImagePath, [string]$OutputPath) {
  $child = New-Object Diagnostics.Process
  $child.StartInfo.FileName = Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell/v1.0/powershell.exe'
  $child.StartInfo.Arguments = '-NoProfile -NonInteractive -STA -File "' + $script:privacyOcrPath + '" -ImagePath "' + $ImagePath + '" -OutputPath "' + $OutputPath + '"'
  $child.StartInfo.UseShellExecute = $false; $child.StartInfo.CreateNoWindow = $true
  $child.StartInfo.RedirectStandardOutput = $true; $child.StartInfo.RedirectStandardError = $true
  $started = $false
  try {
    $started = $child.Start()
    if (!$started) { throw 'The local Windows OCR reader did not start.' }
    $stdout = $child.StandardOutput.ReadToEndAsync(); $stderr = $child.StandardError.ReadToEndAsync()
    if (!$child.WaitForExit(30000)) { throw 'The local Windows OCR reader exceeded 30 seconds.' }
    if (!$stdout.Wait(1000) -or !$stderr.Wait(1000)) { throw 'The local OCR output did not close.' }
    [IO.File]::WriteAllText($OutputPath + '.stdout.log', $stdout.Result)
    [IO.File]::WriteAllText($OutputPath + '.stderr.log', $stderr.Result)
    if ($child.ExitCode -ne 0) { throw ('Local Windows OCR failed with exit ' + $child.ExitCode + ': ' + $stderr.Result) }
    return Get-Content -LiteralPath $OutputPath -Raw | ConvertFrom-Json
  } finally { if ($started -and !$child.HasExited) { $child.Kill($true); $child.WaitForExit() }; $child.Dispose() }
}
function Test-QAPrivacyBlue($Color) { return $Color.R -lt 50 -and $Color.G -ge 90 -and $Color.G -le 145 -and $Color.B -ge 175 -and $Color.B -le 235 }
function Test-QAPrivacyButtonBlue($Color, [string]$Label) {
  return (Test-QAPrivacyBlue $Color) -or ($Label -ceq 'Accept' -and $Color.R -eq 0 -and $Color.G -eq 62 -and $Color.B -eq 146)
}
function Read-QAPrivacyAction($Ocr, [string]$ImagePath) {
  if ($Ocr.width -ne 1024 -or $Ocr.height -ne 768 -or $Ocr.language -notlike 'en*' -or
      ($Ocr.text -replace '\s+', ' ') -notmatch 'Choose privacy settings for your device') {
    throw 'The local OCR does not identify the visually reviewed Windows privacy page.'
  }
  $optionLabels = @($Ocr.lines | Where-Object { $_.text.Trim() -match '^(Location|Find my device|Inking\s*&\s*typing|Personalized offers)$' -and
    $_.words[0].x -ge 540 -and $_.words[0].x -le 570 -and $_.words[0].y -gt 230 -and $_.words[0].y -lt 600 })
  $optionValues = @($Ocr.lines | Where-Object { $_.text.Trim() -cmatch '^(Yes|No)$' -and $_.words.Count -eq 1 -and
    $_.words[0].x -ge 600 -and $_.words[0].x -le 630 -and $_.words[0].y -gt 250 -and $_.words[0].y -lt 625 })
  $expectedCount = $Ocr.valueCrops.Count
  if (($Ocr.privacyPage -cne 'initial' -and $Ocr.privacyPage -cne 'final') -or
      ($Ocr.privacyPage -ceq 'initial' -and $expectedCount -ne 3) -or $expectedCount -lt 1 -or $expectedCount -gt 4 -or
      $optionLabels.Count -ne $expectedCount -or $optionValues.Count -ne $expectedCount) {
    throw 'The recognized privacy profile must expose one value for each of its observed labels.'
  }
  foreach ($label in $optionLabels) {
    if (@($optionValues | Where-Object { $_.sourceLabel -ceq $label.text }).Count -ne 1) { throw 'Each observed privacy label must have exactly one associated value.' }
  }
  $bitmap = [Drawing.Bitmap]::FromFile($ImagePath)
  try {
    $blueRows = @()
    for ($y = 250; $y -lt 625; $y++) {
      $blue = 0
      for ($x = 550; $x -le 593; $x++) { if (Test-QAPrivacyBlue ($bitmap.GetPixel($x, $y))) { $blue++ } }
      if ($blue -ge 20) { $blueRows += $y }
    }
    $clusters = @(); $first = -1; $last = -1
    foreach ($y in $blueRows) {
      if ($first -ge 0 -and $y -ne $last + 1) { $clusters += @{ first = $first; last = $last }; $first = -1 }
      if ($first -lt 0) { $first = $y }; $last = $y
    }
    if ($first -ge 0) { $clusters += @{ first = $first; last = $last } }
    if ($clusters.Count -gt 0) {
      $cluster = $clusters[0]
      if ($cluster.last - $cluster.first -lt 11 -or $cluster.last - $cluster.first -gt 29) { throw 'An unrecognized blue control overlaps the reviewed toggle column.' }
      $centerY = [int][Math]::Round(($cluster.first + $cluster.last) / 2)
      $yes = @($Ocr.lines | Where-Object { $_.text.Trim() -ceq 'Yes' -and $_.words.Count -eq 1 -and
        $_.words[0].x -ge 600 -and $_.words[0].x -le 630 -and [Math]::Abs(($_.words[0].y + $_.words[0].height / 2) - $centerY) -le 10 })
      if ($yes.Count -ne 1) { throw 'A blue toggle lacks an unambiguous observed Yes label; do not advance privacy settings.' }
      $labels = @($Ocr.lines | Where-Object { $_.text.Trim() -match '^(Location|Find my device|Inking\s*&\s*typing|Personalized offers)$' -and
        $_.words[0].x -ge 540 -and $_.words[0].x -le 570 -and $_.words[0].y -lt $centerY -and $centerY - $_.words[0].y -lt 180 } | Sort-Object { $_.words[0].y } -Descending)
      if ($labels.Count -eq 0) { throw 'An enabled toggle has no recognized optional privacy setting label.' }
      if ($yes[0].sourceLabel -cne $labels[0].text -or
          ($Ocr.privacyPage -ceq 'final' -and $labels[0].text -cne 'Personalized offers')) {
        throw 'A final-page action may only disable the observed Personalized offers setting.'
      }
      return @{ kind = 'disable-optional-setting'; label = $labels[0].text; x = 572; y = $centerY; blueToggleCount = $clusters.Count }
    }
    if (@($optionValues | Where-Object { $_.text.Trim() -ceq 'Yes' }).Count -gt 0) { throw 'A recognized setting is still enabled; do not advance privacy settings.' }
    $buttons = @($Ocr.lines | Where-Object { $_.text.Trim() -cmatch '^(Next|Accept)$' -and $_.words.Count -eq 1 -and
      $_.words[0].x -gt 780 -and $_.words[0].x -lt 900 -and $_.words[0].y -gt 620 -and $_.words[0].y -lt 690 })
    if ($buttons.Count -ne 1) { throw 'There is no unique observed Next/Accept button on the verified privacy page.' }
    if (($Ocr.privacyPage -ceq 'initial' -and $buttons[0].text -cne 'Next') -or
        ($Ocr.privacyPage -ceq 'final' -and $buttons[0].text -cne 'Accept')) { throw 'The navigation button does not belong to the recognized privacy profile.' }
    if ($Ocr.privacyPage -ceq 'final') { [void](Assert-QAPrivacyToggleOff $Ocr @{ kind = 'disable-optional-setting'; label = 'Personalized offers' }) }
    $word = $buttons[0].words[0]; $x = [int][Math]::Round($word.x + $word.width / 2); $y = [int][Math]::Round($word.y + $word.height / 2)
    if (!(Test-QAPrivacyButtonBlue ($bitmap.GetPixel([int]($word.x - 15), $y)) $word.text) -or
        !(Test-QAPrivacyButtonBlue ($bitmap.GetPixel([int]($word.x + $word.width + 15), $y)) $word.text)) {
      throw 'The OCR Next/Accept label is not inside the observed blue button.'
    }
    return @{ kind = 'advance-privacy-page'; label = $word.text; x = $x; y = $y; blueToggleCount = 0 }
  } finally { $bitmap.Dispose() }
}
function Assert-QAPrivacyToggleOff($Ocr, $Action) {
  $crops = @($Ocr.valueCrops | Where-Object { $_.label -ceq $Action.label })
  $values = @($Ocr.lines | Where-Object { $_.sourceLabel -ceq $Action.label })
  if ($Action.kind -cne 'disable-optional-setting' -or $crops.Count -ne 1 -or $values.Count -ne 1 -or
      $values[0].text.Trim() -cne 'No' -or $values[0].words.Count -ne 1) {
    throw 'The same optional privacy setting did not visibly change to a unique No after the action.'
  }
  $word = $values[0].words[0]; $bounds = $crops[0].sourceBounds
  $mapped = @($crops[0].mappedLines | Where-Object { $_.text.Trim() -cmatch '^(Yes|No)$' -and $_.words.Count -eq 1 })
  if ($mapped.Count -ne 1 -or $mapped[0].sourceLabel -cne $Action.label -or $mapped[0].text.Trim() -cne 'No' -or
      $word.text -cne 'No' -or $word.x -lt $bounds.x -or $word.y -lt $bounds.y -or
      $word.x + $word.width -gt $bounds.x + $bounds.width -or $word.y + $word.height -gt $bounds.y + $bounds.height) {
    throw 'The observed No must lie inside the current crop belonging to the same privacy label.'
  }
  return @{ label = $Action.label; value = 'No'; word = $word; bounds = $bounds }
}
function Assert-QAPrivacyPagePrerequisite($Ocr, $Snapshot, $InitialPage) {
  if ($Ocr.privacyPage -ceq 'initial') {
    if ($null -ne $InitialPage) { throw 'Privacy returned to its initial profile after the observed Next action.' }
    return
  }
  if ($Ocr.privacyPage -cne 'final' -or $null -eq $InitialPage -or !$InitialPage.nextInputSent -or
      $InitialPage.window.Hwnd -ne $Snapshot.foreground.Hwnd -or $InitialPage.window.ProcessId -ne $Snapshot.foreground.ProcessId) {
    throw 'The final privacy profile requires a recorded Next action from the same verified window.'
  }
  $expected = @('Location', 'Find my device', 'Inking & typing')
  if ($InitialPage.values.Count -ne 3) { throw 'The initial privacy page was not fully verified before advancing.' }
  for ($index = 0; $index -lt 3; $index++) {
    if ($InitialPage.values[$index].label -cne $expected[$index] -or $InitialPage.values[$index].value -cne 'No') {
      throw 'All three initial privacy settings must have been observed as No before advancing.'
    }
  }
  foreach ($value in @($Ocr.lines | Where-Object { $_.sourceLabel -and $_.sourceLabel -cne 'Personalized offers' })) {
    if ($value.text.Trim() -cne 'No') { throw 'A previously disabled setting is no longer visibly No.' }
  }
}
function Test-QAStoredFinalPrivacyImages {
  $results = @()
  try {
    foreach ($trace in @('false', 'true')) {
      $fixture = Join-Path 'privacy-final-fixtures' ('windows11-flutter-history-trace-' + $trace + '-42234949689')
      $provenance = Get-Content (Join-Path $fixture 'windows11-harness-source.json') -Raw | ConvertFrom-Json
      if ($provenance.workflowHead -cne '44a21e45f026176433d1aa23603185f20b572a6b') { throw 'Unexpected source for the observed final privacy frame.' }
      $image = (Resolve-Path (Join-Path $fixture 'privacy-03.png')).Path
      $ocr = Read-QALocalOcr $image (Join-Path $env:REPORT_QA_ARTIFACT_ROOT ('stored-final-privacy-' + $trace + '-ocr.json'))
      $value = @($ocr.lines | Where-Object { $_.sourceLabel -ceq 'Personalized offers' })
      if ($ocr.privacyPage -cne 'final' -or $value.Count -ne 1 -or $value[0].text.Trim() -cne 'Yes') {
        throw 'The stored final frame does not expose the independently observed Personalized offers Yes.'
      }
      $initialOcr = Get-Content (Join-Path $fixture 'privacy-02-ocr.json') -Raw | ConvertFrom-Json
      $snapshot = Get-Content (Join-Path $fixture 'privacy-03.json') -Raw | ConvertFrom-Json
      $preparation = Get-Content (Join-Path $fixture 'privacy-preparation.json') -Raw | ConvertFrom-Json
      $next = @($preparation.actions | Where-Object { $_.kind -ceq 'advance-privacy-page' -and $_.label -ceq 'Next' -and $_.inputSent })
      if ($next.Count -ne 1) { throw 'The final fixture has no unique recorded Next action.' }
      $initial = @{ window = $next[0].window; nextInputSent = $true; values = @('Location', 'Find my device', 'Inking & typing' | ForEach-Object {
        Assert-QAPrivacyToggleOff $initialOcr @{ kind = 'disable-optional-setting'; label = $_ }
      }) }
      Assert-QAPrivacyPagePrerequisite $ocr $snapshot $initial
      $missingRejected = $false
      try { Assert-QAPrivacyPagePrerequisite $ocr $snapshot $null } catch { $missingRejected = $true }
      $changed = $initial | ConvertTo-Json -Depth 15 | ConvertFrom-Json; $changed.window.ProcessId = -1
      $changedRejected = $false
      try { Assert-QAPrivacyPagePrerequisite $ocr $snapshot $changed } catch { $changedRejected = $true }
      $enabled = $initial | ConvertTo-Json -Depth 15 | ConvertFrom-Json; $enabled.values[0].value = 'Yes'
      $enabledRejected = $false
      try { Assert-QAPrivacyPagePrerequisite $ocr $snapshot $enabled } catch { $enabledRejected = $true }
      if (!$missingRejected -or !$changedRejected -or !$enabledRejected) { throw 'An invalid final-page prerequisite was accepted.' }
      $action = Read-QAPrivacyAction $ocr $image
      if ($action.kind -cne 'disable-optional-setting' -or $action.label -cne 'Personalized offers') { throw 'The final fixture must select only its observed enabled Personalized offers toggle.' }
      $results += @{ trace = $trace; imageSha256 = (Get-FileHash $image).Hash; value = $value[0]; proposedAction = $action;
        missingRejected = $missingRejected; changedRejected = $changedRejected; enabledRejected = $enabledRejected; inputSent = $false; passed = $true }
    }
  } finally {
    @{ cases = $results; allPassed = $results.Count -eq 2; inputSent = $false } | ConvertTo-Json -Depth 12 |
      Set-Content -Encoding utf8 "$env:REPORT_QA_ARTIFACT_ROOT/stored-final-privacy-smoke.json"
  }
}
function Test-QAStoredPrivacyTransitions {
  $results = @()
  try {
    foreach ($trace in @('false', 'true')) {
      $fixture = Join-Path 'privacy-transition-fixtures' ('windows11-flutter-history-trace-' + $trace + '-42233490986')
      $provenance = Get-Content (Join-Path $fixture 'windows11-harness-source.json') -Raw | ConvertFrom-Json
      if ($provenance.workflowHead -cne '1b545dbd45d677766373bf3c4a13080385008092') { throw 'Unexpected source for the captured privacy transition.' }
      $preparation = Get-Content (Join-Path $fixture 'privacy-preparation.json') -Raw | ConvertFrom-Json
      if ($preparation.actions.Count -ne 1 -or !$preparation.actions[0].inputSent -or $preparation.actions[0].label -cne 'Location') {
        throw 'The stored transition does not identify the single observed Location action.'
      }
      $action = $preparation.actions[0]
      $before = Get-Content (Join-Path $fixture 'privacy-00-ocr.json') -Raw | ConvertFrom-Json
      $after = Get-Content (Join-Path $fixture 'privacy-01-ocr.json') -Raw | ConvertFrom-Json
      $observation = Assert-QAPrivacyToggleOff $after $action
      $unchangedRejected = $false
      try { [void](Assert-QAPrivacyToggleOff $before $action) } catch { $unchangedRejected = $true }
      if (!$unchangedRejected) { throw 'An unchanged Yes was incorrectly accepted as a completed disable action.' }
      $missing = $after | ConvertTo-Json -Depth 20 | ConvertFrom-Json
      $missing.lines = @($missing.lines | Where-Object { $_.sourceLabel -cne 'Location' })
      $missingRejected = $false
      try { [void](Assert-QAPrivacyToggleOff $missing $action) } catch { $missingRejected = $true }
      if (!$missingRejected) { throw 'A No belonging to another setting was incorrectly accepted.' }
      $duplicate = $after | ConvertTo-Json -Depth 20 | ConvertFrom-Json
      $duplicate.lines += @($duplicate.lines | Where-Object { $_.sourceLabel -ceq 'Location' })
      $duplicateRejected = $false
      try { [void](Assert-QAPrivacyToggleOff $duplicate $action) } catch { $duplicateRejected = $true }
      if (!$duplicateRejected) { throw 'Duplicate values for the same setting were incorrectly accepted.' }
      $outside = $after | ConvertTo-Json -Depth 20 | ConvertFrom-Json
      ($outside.lines | Where-Object { $_.sourceLabel -ceq 'Location' }).words[0].y = 100
      $outsideRejected = $false
      try { [void](Assert-QAPrivacyToggleOff $outside $action) } catch { $outsideRejected = $true }
      if (!$outsideRejected) { throw 'A No outside its associated crop was incorrectly accepted.' }
      $results += @{ trace = $trace; observation = $observation; unchangedRejected = $unchangedRejected;
        missingRejected = $missingRejected; duplicateRejected = $duplicateRejected; outsideRejected = $outsideRejected;
        beforeSha256 = (Get-FileHash (Join-Path $fixture 'privacy-00.png')).Hash;
        afterSha256 = (Get-FileHash (Join-Path $fixture 'privacy-01.png')).Hash; inputSent = $false; passed = $true }
    }
  } finally {
    @{ cases = $results; allPassed = $results.Count -eq 2; inputSent = $false } | ConvertTo-Json -Depth 12 |
      Set-Content -Encoding utf8 "$env:REPORT_QA_ARTIFACT_ROOT/stored-privacy-transition-smoke.json"
  }
}
function Test-QAStoredPrivacyImages {
  $results = @()
  $expectedLabels = @('Location', 'Find my device', 'Inking & typing')
  $expectedValues = @('Yes', 'No', 'Yes')
  try {
    foreach ($trace in @('false', 'true')) {
      $fixture = Join-Path 'privacy-ocr-fixtures' ('windows11-flutter-history-trace-' + $trace + '-42231302570')
      $provenance = Get-Content (Join-Path $fixture 'windows11-harness-source.json') -Raw | ConvertFrom-Json
      if ($provenance.workflowHead -cne '81d76124b4ab4d4493b4f573b23f7c944e78d94c') { throw 'Unexpected source for the previously captured privacy image.' }
      $image = (Resolve-Path (Join-Path $fixture 'privacy-00.png')).Path
      $ocr = Read-QALocalOcr $image (Join-Path $env:REPORT_QA_ARTIFACT_ROOT ('stored-privacy-' + $trace + '-ocr.json'))
      $pairs = @($ocr.valueCrops | ForEach-Object {
        $values = @($_.mappedLines | Where-Object { $_.text.Trim() -cmatch '^(Yes|No)$' -and $_.words.Count -eq 1 })
        if ($values.Count -ne 1) { throw 'The stored privacy image did not yield one value per label.' }
        @{ label = $_.label; value = $values[0].text; word = $values[0].words[0]; bounds = $_.sourceBounds }
      })
      if ($pairs.Count -ne 3) { throw 'The stored privacy image did not yield all three label/value pairs.' }
      for ($index = 0; $index -lt 3; $index++) {
        if ($pairs[$index].label -cne $expectedLabels[$index] -or $pairs[$index].value -cne $expectedValues[$index] -or
            $pairs[$index].word.y -lt $pairs[$index].bounds.y -or
            $pairs[$index].word.y + $pairs[$index].word.height -gt $pairs[$index].bounds.y + $pairs[$index].bounds.height) {
          throw 'The stored image OCR disagrees with the independently viewed label/value position.'
        }
      }
      $action = Read-QAPrivacyAction $ocr $image
      if ($action.kind -cne 'disable-optional-setting' -or $action.label -cne 'Location') { throw 'The stored frame does not select the observed enabled Location toggle.' }
      $results += @{ trace = $trace; imageSha256 = (Get-FileHash $image).Hash; pairs = $pairs; proposedAction = $action; inputSent = $false; passed = $true }
    }
  } finally {
    @{ cases = $results; allPassed = $results.Count -eq 2; inputSent = $false } | ConvertTo-Json -Depth 12 |
      Set-Content -Encoding utf8 "$env:REPORT_QA_ARTIFACT_ROOT/stored-privacy-ocr-smoke.json"
  }
}
function Prepare-QAWindowsPrivacy {
  $actions = New-Object 'Collections.Generic.List[object]'
  $status = @{ actions = $actions; completed = $false; source = 'Observed Windows first-login privacy UI'; accountSignIn = $false }
  $statusPath = Join-Path $env:REPORT_QA_ARTIFACT_ROOT 'privacy-preparation.json'
  $previous = $null; $previousText = $null; $initialPage = $null; $deadline = [DateTime]::UtcNow.AddMinutes(4)
  try {
    for ($attempt = 0; $attempt -lt 14; $attempt++) {
      if ([DateTime]::UtcNow -ge $deadline) { throw 'Privacy UI preparation exceeded four minutes.' }
      $name = 'privacy-{0:D2}' -f $attempt
      $snapshot = Save-QAWindowSnapshot $name
      if ($snapshot.foreground.ClassName -cne 'Windows.UI.Core.CoreWindow' -or $snapshot.foreground.Title -cne 'Microsoft account') {
        if ($attempt -gt 0 -and ($null -eq $previous -or $previous.label -cne 'Accept')) { throw 'Privacy lost the foreground before an observed Accept action.' }
        $status['outcome'] = if ($attempt -eq 0) { 'privacy-screen-not-present' } else { 'privacy-screen-dismissed-through-ui' }
        $status.completed = $true; return
      }
      $identity = Assert-QAPrivacyIdentity $snapshot
      $imagePath = Join-Path $env:REPORT_QA_ARTIFACT_ROOT ($name + '.png')
      $ocr = Read-QALocalOcr $imagePath (Join-Path $env:REPORT_QA_ARTIFACT_ROOT ($name + '-ocr.json'))
      Assert-QAPrivacyPagePrerequisite $ocr $snapshot $initialPage
      if ($null -ne $previous -and $previous.kind -eq 'disable-optional-setting') {
        $previous['verifiedOffObservation'] = Assert-QAPrivacyToggleOff $ocr $previous
        $previous['verifiedOff'] = $true
      } elseif ($null -ne $previous -and $ocr.text -ceq $previousText) { throw 'The privacy page did not change after its observed Next/Accept action.' }
      $action = Read-QAPrivacyAction $ocr $imagePath
      if ($action.kind -ceq 'advance-privacy-page' -and $action.label -ceq 'Next') {
        $initialPage = @{ window = $snapshot.foreground; nextInputSent = $false; screenshotSha256 = (Get-FileHash $imagePath).Hash;
          values = @('Location', 'Find my device', 'Inking & typing' | ForEach-Object {
            Assert-QAPrivacyToggleOff $ocr @{ kind = 'disable-optional-setting'; label = $_ }
          }) }
        $status['initialPageVerifiedNo'] = $initialPage
      }
      $fresh = Save-QAWindowSnapshot ($name + '-before-action')
      [void](Assert-QAPrivacyIdentity $fresh)
      if ($fresh.foreground.Hwnd -ne $snapshot.foreground.Hwnd -or $fresh.foreground.ProcessId -ne $snapshot.foreground.ProcessId -or
          (Get-FileHash $imagePath).Hash -ne (Get-FileHash (Join-Path $env:REPORT_QA_ARTIFACT_ROOT ($name + '-before-action.png'))).Hash) {
        throw 'The privacy surface changed while it was being recognized; no stale-target input is permitted.'
      }
      $action['recordedAt'] = [DateTime]::UtcNow.ToString('o'); $action['window'] = $snapshot.foreground; $action['process'] = $identity
      $action['screenshotSha256'] = (Get-FileHash $imagePath).Hash; $action['inputSent'] = $false
      $actions.Add($action); $status | ConvertTo-Json -Depth 15 | Set-Content -Encoding utf8 $statusPath
      if ([QaWindowActivation]::GetForegroundWindow() -ne [IntPtr]$snapshot.foreground.Hwnd) { throw 'Privacy lost the foreground before its UI action.' }
      $element = [Windows.Automation.AutomationElement]::FromPoint([Windows.Point]::new($action.x, $action.y))
      $pattern = $null
      if ($action.kind -eq 'disable-optional-setting' -and
          $element.TryGetCurrentPattern([Windows.Automation.TogglePattern]::Pattern, [ref]$pattern)) {
        if ($element.Current.ProcessId -ne $snapshot.foreground.ProcessId -or !$element.Current.IsEnabled -or $element.Current.IsOffscreen -or
            !$element.Current.BoundingRectangle.Contains([Windows.Point]::new($action.x, $action.y)) -or
            $pattern.Current.ToggleState -ne [Windows.Automation.ToggleState]::On) {
          throw 'The exposed UIA toggle contradicts the observed enabled privacy switch; no input is permitted.'
        }
        $pattern.Toggle(); $action['mechanism'] = 'UIAutomation TogglePattern'
      } else {
        if ($action.kind -eq 'disable-optional-setting' -and (!$element.Current.IsEnabled -or $element.Current.IsOffscreen)) {
          throw 'UIA reports an unavailable privacy control; no native fallback is permitted.'
        }
        [QaWindowActivation]::ClickPrivacyPoint([IntPtr]$snapshot.foreground.Hwnd, [uint32]$snapshot.foreground.ProcessId, $action.x, $action.y)
        $action['mechanism'] = 'Observed OCR/bitmap control with foreground ownership checked at native click'
      }
      $action.inputSent = $true; $previous = $action; $previousText = $ocr.text
      if ($action.kind -ceq 'advance-privacy-page' -and $action.label -ceq 'Next') { $initialPage.nextInputSent = $true }
      $status | ConvertTo-Json -Depth 15 | Set-Content -Encoding utf8 $statusPath
      Start-Sleep -Milliseconds 1500
    }
    throw 'The bounded privacy UI preparation did not finish within 14 observed actions.'
  } catch { $status['error'] = $_.Exception.ToString(); throw }
  finally { $status | ConvertTo-Json -Depth 15 | Set-Content -Encoding utf8 $statusPath }
}
[void](Save-QAWindowSnapshot '00-before-launch')
try { Test-QAStoredPrivacyImages; Test-QAStoredPrivacyTransitions; Test-QAStoredFinalPrivacyImages; Prepare-QAWindowsPrivacy } catch {
  [IO.File]::WriteAllText("$env:REPORT_QA_ARTIFACT_ROOT/privacy-error.txt", $_.Exception.ToString())
  [void](Save-QAWindowSnapshot 'privacy-error')
  throw
}
$output = Join-Path $env:REPORT_QA_ARTIFACT_ROOT 'run'
$arguments = '-NoProfile -NonInteractive -File "' + "$bundle/run.ps1" + '" -OutputDirectory "' + $output + '"'
if ($env:REPORT_QA_NATIVE_TRACE -eq 'true') { $arguments += ' -EnableNativeTrace' }
$launcher = New-Object Diagnostics.Process
$launcher.StartInfo.FileName = (Get-Process -Id $PID).Path
$launcher.StartInfo.Arguments = $arguments
$launcher.StartInfo.UseShellExecute = $false
$launcher.StartInfo.CreateNoWindow = $true
$launcher.StartInfo.RedirectStandardOutput = $true
$launcher.StartInfo.RedirectStandardError = $true
$started = $false
$application = $null
try {
  $started = $launcher.Start()
  if (!$started) { throw 'The standalone launcher did not start.' }
  $stdout = $launcher.StandardOutput.ReadToEndAsync()
  $stderr = $launcher.StandardError.ReadToEndAsync()
  $deadline = [DateTime]::UtcNow.AddSeconds(90)
  do {
    $application = Get-Process -Name otzaria -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq "$bundle\otzaria.exe" } | Select-Object -First 1
    if ($null -ne $application -or $launcher.HasExited) { break }
    Start-Sleep -Milliseconds 250
  } while ([DateTime]::UtcNow -lt $deadline)
  if ($null -eq $application) { throw 'The standalone Flutter process was not observed.' }
  $machine = [QaProcessArchitecture]::Read($application.Id)
  @{
    processId = $application.Id; path = $application.Path; sessionId = $application.SessionId
    processMachine = ('0x{0:X4}' -f $machine[0]); nativeMachine = ('0x{0:X4}' -f $machine[1])
    wowMachine = ('0x{0:X4}' -f $machine[2]); attributes = $machine[3]
    executableSha256 = (Get-FileHash $application.Path -Algorithm SHA256).Hash
  } | ConvertTo-Json | Set-Content -Encoding utf8 "$env:REPORT_QA_ARTIFACT_ROOT/flutter-process.json"
  if ($machine[0] -ne 0x8664 -or $machine[1] -ne 0xAA64) {
    throw 'The observed Flutter process must be x64 on native ARM64 Windows.'
  }
  Activate-QAFlutterWindow $application
  if (!$launcher.WaitForExit(13 * 60 * 1000)) { throw 'Standalone launcher exceeded its bounded run time.' }
  if (!$stdout.Wait(1000) -or !$stderr.Wait(1000)) { throw 'Standalone launcher output did not close.' }
  [IO.File]::WriteAllText("$env:REPORT_QA_ARTIFACT_ROOT/launcher.stdout.log", $stdout.Result)
  [IO.File]::WriteAllText("$env:REPORT_QA_ARTIFACT_ROOT/launcher.stderr.log", $stderr.Result)
  $exitCode = $launcher.ExitCode
  if ($exitCode -isnot [int]) { throw 'The standalone launcher did not produce a trustworthy exit code.' }
  @{ exitCode = $exitCode; processId = $launcher.Id } | ConvertTo-Json |
    Set-Content -Encoding utf8 "$env:REPORT_QA_ARTIFACT_ROOT/launcher-exit.json"
  exit $exitCode
} catch {
  [IO.File]::WriteAllText("$env:REPORT_QA_ARTIFACT_ROOT/wrapper-error.txt", $_.Exception.ToString())
  try { [void](Save-QAWindowSnapshot '99-wrapper-error') } catch { }
  throw
} finally {
  if ($started -and !$launcher.HasExited) { & taskkill.exe /PID $launcher.Id /T /F | Out-Null }
  if ($null -ne $application -and !$application.HasExited) { & taskkill.exe /PID $application.Id /T /F | Out-Null }
  if ($started) {
    if ($null -ne $stdout -and $stdout.Wait(1000)) { [IO.File]::WriteAllText("$env:REPORT_QA_ARTIFACT_ROOT/launcher.stdout.log", $stdout.Result) }
    if ($null -ne $stderr -and $stderr.Wait(1000)) { [IO.File]::WriteAllText("$env:REPORT_QA_ARTIFACT_ROOT/launcher.stderr.log", $stderr.Result) }
  }
  $launcher.Dispose()
}
