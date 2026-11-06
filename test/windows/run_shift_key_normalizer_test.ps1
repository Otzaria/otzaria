$ErrorActionPreference = 'Stop'
$repoPath = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$logDirectory = Join-Path $repoPath 'build/reporting_qa'
New-Item -ItemType Directory -Force $logDirectory | Out-Null
$testLog = Join-Path $logDirectory 'native-keyboard.log'
$nativeQaOut = Join-Path ([IO.Path]::GetTempPath()) ('scan_code_qa_' + [Guid]::NewGuid())
try {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    $vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $vs) { throw 'MSVC not found' }
    $vcvars = Join-Path $vs 'VC/Auxiliary/Build/vcvars64.bat'
    $runnerDirectory = Join-Path $repoPath 'windows/runner'
    $implementation = Join-Path $runnerDirectory 'shift_key_normalizer.cpp'
    $testSource = Join-Path $PSScriptRoot 'shift_key_normalizer_test.cpp'
    New-Item -ItemType Directory $nativeQaOut | Out-Null
    cmd /c "call `"$vcvars`" >nul && cl /nologo /std:c++17 /W4 /WX /EHsc /utf-8 /I`"$runnerDirectory`" `"$implementation`" `"$testSource`" /Fo`"$nativeQaOut\\`" /Fe`"$nativeQaOut\scan-code-qa.exe`" /link user32.lib comctl32.lib" 2>&1 |
        Tee-Object -FilePath $testLog
    if ($LASTEXITCODE -ne 0) { throw "Native keyboard compile failed: $LASTEXITCODE" }
    & "$nativeQaOut\scan-code-qa.exe" 2>&1 | Tee-Object -FilePath $testLog -Append
    if ($LASTEXITCODE -ne 0) { throw "Native keyboard test failed: $LASTEXITCODE" }
} catch {
    ($_ | Out-String) | Out-File -FilePath $testLog -Append
    throw
} finally {
    if (Test-Path $nativeQaOut) { Remove-Item -Recurse -Force $nativeQaOut }
}
