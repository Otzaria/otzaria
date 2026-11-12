function flutter {
  Write-Host "WORKFLOW CONTRACT ONLY: flutter $($args -join ' ')"
  $global:LASTEXITCODE = if ($env:SIMULATE_TEST_FAILURE -eq 'true' -and $args[0] -eq 'test') { 7 } else { 0 }
}
function dart { Write-Host "WORKFLOW CONTRACT ONLY: dart $($args -join ' ')"; $global:LASTEXITCODE = 0 }
function rustc { Write-Host 'WORKFLOW CONTRACT ONLY: rustc'; $global:LASTEXITCODE = 0 }

. ./tool/perf_probe/run_reader_comparison.ps1 -DefinitionsOnly
. ./tool/perf_probe/lockfile_quoting.ps1
$PSNativeCommandUseErrorActionPreference = $false
$repo = $PWD.Path
$checkout = Join-Path $env:RUNNER_TEMP 'reader-flat-control-validation-source'
$originalRelative = 'test/text_book/bloc/long_book_snapshot_regression_test.dart'
$generatedRelative = 'test/text_book/bloc/long_book_snapshot_regression_flat_control_validation_test.dart'
$originalHash = '9eeea22effd110ba786a64ccb00bebcffa2621997e071ba9616c580ff1c21356'
$generatedHash = '586b42792cabf70f3709f2eabbb6c5507d915c9d0e508af91954133a2e312ed7'
$assertion = "    expect(() => second.content[639] = 'מוטציה', throwsUnsupportedError);`n"
$tests = @(
  'test/text_book/models/chunked_list_test.dart',
  'test/text_book/bloc/background_full_content_loading_test.dart',
  'test/text_book/bloc/split_pane_warming_test.dart',
  'test/text_book/bloc/per_book_continuous_initial_load_test.dart',
  'test/text_book/bloc/continuous_reading_mode_test.dart',
  'test/text_book/bloc/inline_notes_commentator_test.dart',
  'test/text_book/utils/reader_content_revision_test.dart',
  'test/text_book/utils/reading_extent_estimates_test.dart',
  'test/text_book/utils/reading_segment_cache_test.dart',
  'test/text_book/utils/inline_notes_utils_test.dart',
  'test/text_book/view/page_shape/page_shape_notes_column_test.dart',
  'test/text_book/view/combined_view/continuous_reflow_keeps_place_test.dart',
  'test/tool/perf_probe/perf_fixture_test.dart',
  'test/tool/perf_probe/perf_reader_probe_test.dart',
  'test/tool/perf_probe/perf_reader_scroll_test.dart',
  'test/tool/perf_probe/perf_recorder_test.dart',
  'test/tool/perf_probe/report_test.dart'
)
$commands = [Collections.Generic.List[object]]::new()
$proof = [ordered]@{
  status = 'running'; sourceCommit = $env:CONTROL_SHA; commands = $commands
  originalTest = $originalRelative; originalSha256 = $originalHash
  generatedTest = $generatedRelative; generatedSha256 = $generatedHash
  removedUniqueAssertion = $assertion; removedOccurrences = 1
  commonTestFiles = $tests; generatedSuiteRunsAllRemainingAssertions = $true
  originalUnchanged = $false; generatedRemoved = $false; cleanSource = $false
}
function Invoke-ValidationCommand([string]$Name, [string]$Command, [string[]]$Arguments) {
  $entry = [ordered]@{ name = $Name; command = $Command; arguments = $Arguments; startedAtUtc = [DateTime]::UtcNow.ToString('o'); exitCode = $null }
  $commands.Add($entry)
  & $Command @Arguments 2>&1 | Tee-Object -FilePath (Join-Path $env:VALIDATION_ROOT "$Name.log")
  $entry.exitCode = $LASTEXITCODE; $entry.endedAtUtc = [DateTime]::UtcNow.ToString('o')
  if ($entry.exitCode -ne 0) { throw "$Name failed ($($entry.exitCode))." }
}
$added = $false; $generatedCreated = $false; $locationPushed = $false; $failure = $null
try {
  Invoke-ReaderGit $repo @('worktree', 'add', '--detach', $checkout, $env:CONTROL_SHA) | Out-Null
  $added = $true
  Assert-ReaderClean $checkout
  Push-Location $checkout
  $locationPushed = $true
  $bloc = Join-Path $checkout 'lib/text_book/bloc/text_book_bloc.dart'
  $proof.controlBlocSha256 = (Get-FileHash -LiteralPath $bloc -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($proof.controlBlocSha256 -cne $env:CONTROL_BLOC_SHA256) { throw 'Control source bytes do not match the reviewed file.' }
  Copy-Item -LiteralPath $bloc -Destination (Join-Path $env:VALIDATION_ROOT 'control-text_book_bloc.dart')
  Invoke-ValidationCommand 'flutter-version' 'flutter' @('--version', '--machine')
  Invoke-ValidationCommand 'dart-version' 'dart' @('--version')
  Invoke-ValidationCommand 'rust-version' 'rustc' @('--version')
  $lockfilePath = Join-Path $checkout 'pubspec.lock'
  $originalLockfile = [IO.File]::ReadAllBytes($lockfilePath)
  Invoke-ValidationCommand 'pub-get' 'flutter' @('pub', 'get', '--enforce-lockfile')
  $lockfileProof = Restore-PerfLockfileQuoting $lockfilePath $originalLockfile
  Write-ReaderJson (Join-Path $env:VALIDATION_ROOT 'lockfile-quoting.json') $lockfileProof
  Assert-ReaderClean $checkout
  Invoke-ValidationCommand 'format' 'dart' @('format', '--output=none', '--set-exit-if-changed', 'lib/text_book/bloc/text_book_bloc.dart')
  Invoke-ValidationCommand 'analyze' 'flutter' @('analyze', '--no-pub')
  Assert-ReaderClean $checkout
  $original = Join-Path $checkout $originalRelative
  $generated = Join-Path $checkout $generatedRelative
  if ((Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash.ToLowerInvariant() -cne $originalHash) { throw 'Original snapshot-test bytes differ.' }
  if (@(Invoke-ReaderGit $checkout @('ls-files', '--', $generatedRelative)).Count) { throw 'The validation sibling must be untracked.' }
  $utf8 = [Text.UTF8Encoding]::new($false, $true)
  $source = $utf8.GetString([IO.File]::ReadAllBytes($original))
  if ([regex]::Matches($source, [regex]::Escape($assertion)).Count -ne 1) { throw 'Expected exactly one incompatible representation assertion.' }
  $overlayBytes = $utf8.GetBytes($source.Replace($assertion, ''))
  $overlayHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($overlayBytes)).ToLowerInvariant()
  if ($overlayHash -cne $generatedHash) { throw 'Generated sibling differs from the reviewed one-line exclusion.' }
  $stream = [IO.File]::Open($generated, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
  try { $stream.Write($overlayBytes, 0, $overlayBytes.Length) } finally { $stream.Dispose() }
  $generatedCreated = $true
  Copy-Item -LiteralPath $original -Destination (Join-Path $env:VALIDATION_ROOT 'original-long_book_snapshot_regression_test.dart')
  Copy-Item -LiteralPath $generated -Destination (Join-Path $env:VALIDATION_ROOT 'generated-long_book_snapshot_regression_flat_control_validation_test.dart')
  Write-ReaderJson (Join-Path $env:VALIDATION_ROOT 'control-validation.json') $proof
  Invoke-ValidationCommand 'common-tests' 'flutter' (@('test', '--no-pub', '--reporter', 'expanded', '--concurrency=2') + $tests + @($generatedRelative))
  $proof.status = 'passed'
} catch {
  $failure = $_; $proof.status = 'failed'; $proof.error = $_.Exception.Message
  $_ | Out-String | Set-Content -LiteralPath (Join-Path $env:VALIDATION_ROOT 'control-validation-failure.log')
} finally {
  if ($locationPushed) { Pop-Location }
  if ($added) {
    try {
      if ($generatedCreated) {
        if ((Get-Item -LiteralPath $generated).LinkType) { throw 'Refusing to remove a linked validation sibling.' }
        if (@(Invoke-ReaderGit $checkout @('ls-files', '--', $generatedRelative)).Count) { throw 'Refusing to remove a tracked validation sibling.' }
        if ((Get-FileHash -LiteralPath $generated -Algorithm SHA256).Hash.ToLowerInvariant() -cne $generatedHash) { throw 'Refusing to remove a modified validation sibling.' }
        Remove-Item -LiteralPath $generated
        $proof.generatedRemoved = $true
      }
      $proof.originalUnchanged = (Get-FileHash -LiteralPath (Join-Path $checkout $originalRelative) -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $originalHash
      if (-not $proof.originalUnchanged) { throw 'The original snapshot test changed during validation.' }
      Assert-ReaderClean $checkout
      $proof.cleanSource = $true
    } catch {
      $proof.status = 'failed'; $proof.cleanupError = $_.Exception.Message
      if ($null -eq $failure) { $failure = $_ }
    } finally {
      Invoke-ReaderGit $checkout @('status', '--porcelain=v1', '--untracked-files=all') |
        Set-Content -LiteralPath (Join-Path $env:VALIDATION_ROOT 'control-final-status.txt')
      Invoke-ReaderGit $checkout @('diff', '--no-ext-diff') |
        Set-Content -LiteralPath (Join-Path $env:VALIDATION_ROOT 'control-final-diff.patch')
    }
    if ($proof.cleanSource) { Invoke-ReaderGit $repo @('worktree', 'remove', '--force', $checkout) | Out-Null }
  }
  Write-ReaderJson (Join-Path $env:VALIDATION_ROOT 'control-validation.json') $proof
}
if ($null -ne $failure) { Write-Error $failure; exit 1 }
if (-not $proof.generatedRemoved -or -not $proof.cleanSource) { throw 'Control validation did not finish with a removed sibling and clean source.' }
Assert-ReaderClean $repo
