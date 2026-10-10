import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File(
    'windows/runner/startup_watchdog.cpp',
  ).readAsStringSync().replaceAll('\r\n', '\n');
  final mainSource = File('windows/runner/main.cpp').readAsStringSync();
  final windowSource = File(
    'windows/runner/flutter_window.cpp',
  ).readAsStringSync();

  test('ה-watcher אינו מרענן מודולים דרך loader APIs', () {
    final start = source.indexOf('void WatcherLoop()');
    final end = source.indexOf('\n}\n\n}  // namespace', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final watcher = source.substring(start, end);
    expect(watcher, isNot(contains('RefreshModules')));
    expect(watcher, isNot(contains('EnumProcessModules')));
    expect(source, contains('std::atomic_load_explicit(&g_modules'));
  });

  test('ה-heartbeat אינו סורק מודולים במסלול העלייה', () {
    final start = source.indexOf('void CALLBACK HeartbeatProc(');
    final end = source.indexOf('\n}', start);
    expect(start, greaterThanOrEqualTo(0));
    final heartbeat = source.substring(start, end);
    expect(heartbeat, isNot(contains('RefreshModules')));
    expect(heartbeat, isNot(contains('GetMappedFileName')));
    expect(heartbeat, isNot(contains('VirtualQuery')));
    expect(heartbeat, contains('RequestStop()'));
  });

  test('DLL מאוחר מזוהה ממיפוי רק אחרי חידוש ה-thread הראשי', () {
    final start = source.indexOf('std::string DescribeAddress(');
    final end = source.indexOf('\n}', start);
    final describe = source.substring(start, end);
    expect(describe, contains('::VirtualQuery('));
    expect(describe, contains('info.Type == MEM_IMAGE'));
    expect(describe, contains('::GetMappedFileNameW('));
    expect(describe, contains('length > 0 && length < MAX_PATH'));
    expect(describe, contains('info.AllocationBase'));
    expect(describe, isNot(contains('::GetModuleFileNameW(')));
    expect(describe, isNot(contains('::GetModuleHandle')));

    final captureStart = source.indexOf('bool CaptureMainThreadStack(');
    final captureEnd = source.indexOf('\n}', captureStart);
    final capture = source.substring(captureStart, captureEnd);
    expect(capture, contains('::ResumeThread(g_main_thread);'));
    expect(capture, isNot(contains('DescribeAddress(')));
    expect(capture, isNot(contains('GetMappedFileName')));
    expect(capture, isNot(contains('VirtualQuery')));

    final watcher = source.substring(source.indexOf('void WatcherLoop()'));
    expect(
      watcher.indexOf('ReportStall('),
      greaterThan(watcher.indexOf('CaptureMainThreadStack(&frames);')),
    );
    expect(RegExp(r'\bDescribeAddress\(').allMatches(source), hasLength(2));
  });

  test('כשל timer אינו מפעיל watcher', () {
    final timer = source.indexOf('g_timer = ::SetTimer');
    final failed = source.indexOf('if (g_timer == 0)', timer);
    final watcher = source.indexOf('g_watcher = std::thread', timer);
    expect(timer, greaterThanOrEqualTo(0));
    expect(failed, greaterThan(timer));
    expect(watcher, greaterThan(failed));
  });

  test('חשיפה מבקשת עצירה והיציאה משלימה join', () {
    expect(windowSource, contains('startup_watchdog::RequestStop();'));
    final stop = source.substring(source.indexOf('void Stop()'));
    expect(stop, contains('RequestStop();'));
    expect(stop, contains('g_watcher.joinable()'));
    expect(stop, contains('g_watcher.join()'));
  });

  test('יצירת חלון מרעננת snapshot וכשל מנקה משאבים', () {
    final failure = mainSource.indexOf(
      'if (!window.Create(kMainWindowTitle, origin, size))',
    );
    final refresh = mainSource.indexOf(
      'startup_watchdog::RefreshModules();',
      failure,
    );
    expect(failure, greaterThanOrEqualTo(0));
    expect(refresh, greaterThan(failure));
    final failureBlock = mainSource.substring(failure, refresh);
    expect(failureBlock, contains('startup_watchdog::Stop();'));
    expect(failureBlock, contains('splash::Close();'));
    expect(failureBlock, contains('::CoUninitialize();'));
  });
}
