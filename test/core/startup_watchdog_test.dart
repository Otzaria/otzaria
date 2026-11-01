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
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final describe = source.substring(start, end);
    expect(describe, contains('::VirtualQuery('));
    expect(describe, contains('info.Type == MEM_IMAGE'));
    expect(describe, contains('::GetMappedFileNameW('));
    expect(describe, contains('length > 0 && length < MAX_PATH'));
    expect(describe, contains('info.AllocationBase'));
    expect(describe, isNot(contains('::GetModuleFileNameW(')));
    expect(describe, isNot(contains('::GetModuleHandle')));

    expect(
      source,
      contains('return CaptureSuspendedStack(g_main_thread, frames);'),
    );
    // בזמן ההשהיה רק syscalls ו-memcpy; פרישה ותרגום נוטלים נעילות.
    final captureStart = source.indexOf('bool CaptureSuspendedStack(HANDLE');
    final suspended = source.substring(
      source.indexOf('::SuspendThread(thread)', captureStart),
      source.indexOf('::ResumeThread(thread);', captureStart),
    );
    expect(suspended, contains('::GetThreadContext('));
    expect(suspended, contains('CopyStackBytes('));
    for (final forbidden in [
      'RtlLookupFunctionEntry',
      'RtlVirtualUnwind',
      'Unwind',
      'DescribeAddress(',
      'GetMappedFileName',
      'push_back',
      'std::vector',
      'std::string',
      'reserve',
      'resize',
      'new ',
      'malloc',
    ]) {
      expect(suspended, isNot(contains(forbidden)), reason: forbidden);
    }
    expect(
      source.substring(source.indexOf('::ResumeThread(thread);', captureStart)),
      contains('UnwindCopiedStack('),
    );

    final watcher = source.substring(source.indexOf('void WatcherLoop()'));
    final captureCall = watcher.indexOf('CaptureMainThreadStack(&frames);');
    final reportCall = watcher.indexOf('ReportStall(');
    expect(captureCall, greaterThanOrEqualTo(0));
    expect(reportCall, greaterThan(captureCall));
    // הגדרה + קריאה יחידה ב-AppendStackSection, שרץ רק אחרי החידוש.
    expect(RegExp(r'\bDescribeAddress\(').allMatches(source), hasLength(2));
    final section = source.substring(
      source.indexOf('void AppendStackSection('),
      source.indexOf('void ReportStall('),
    );
    expect(section, contains('DescribeAddress(frame)'));
  });

  test('פריים Dart מזוהה כ-app.so לפי כותרת ה-ELF, בלי loader APIs', () {
    final dartBase = source.substring(
      source.indexOf('ULONG_PTR DartImageBase('),
      source.indexOf('std::string DartBuildId('),
    );
    expect(dartBase, contains('info.Type != MEM_PRIVATE'));
    expect(dartBase, contains('info.AllocationBase'));
    expect(dartBase, contains('ReadBytes(base, magic, sizeof(magic))'));
    expect(dartBase, isNot(contains('GetModule')));

    final describe = source.substring(
      source.indexOf('std::string DescribeAddress('),
      source.indexOf('#if defined(_M_X64) || defined(_M_ARM64)'),
    );
    expect(describe, contains('"app.so+0x%llx"'));
    expect(
      describe.indexOf('DartImageBase(address)'),
      lessThan(describe.indexOf('info.Type == MEM_IMAGE')),
    );
  });

  test('זהות הבנייה נכתבת לפני שורת Stack, שאחריה הכול פריימים', () {
    final identity = source.substring(
      source.indexOf('void AppendBuildIdentitySection('),
      source.indexOf('void ReportStall('),
    );
    expect(identity, contains('"Build commit: "'));
    expect(identity, contains('"Dart build-id: "'));
    expect(identity, contains('AppendModulePdbLines(frames, report);'));
    expect(identity, isNot(contains('Stack')));
    final pdbLines = source.substring(
      source.indexOf('void AppendModulePdbLines('),
      source.indexOf('std::string DescribeAddress('),
    );
    expect(pdbLines, contains('"Module PDB: "'));
    expect(pdbLines, contains('GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT'));
    expect(pdbLines, contains('DartImageBase(frame) != 0'));
    final stall = source.substring(source.indexOf('void ReportStall('));
    expect(
      stall.indexOf('AppendBuildIdentitySection(frames, &report);'),
      allOf(
        greaterThanOrEqualTo(0),
        lessThan(stall.indexOf('AppendStackSection(frames, &report);')),
      ),
    );
    // רק הקובץ שמשתמש ב-commit מקומפל מחדש כשהוא משתנה.
    expect(
      File('windows/runner/CMakeLists.txt').readAsStringSync(),
      contains('set_property(SOURCE "startup_watchdog.cpp" APPEND PROPERTY'),
    );
  });

  test('הכלים המשותפים ל-hang_monitor עוטפים את אותם מימושים', () {
    final shared = source.substring(source.indexOf('}  // namespace\n'));
    expect(
      shared,
      contains(
        'bool CaptureMainStack(std::vector<ULONG_PTR>* frames) {\n'
        '  return CaptureMainThreadStack(frames);',
      ),
    );
    expect(shared, contains('AppendStackSection(frames, report);'));
    expect(shared, contains('AppendToLog(text);'));
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
    final revealStart = windowSource.indexOf(
      'if (call.method_name() == "close")',
    );
    expect(revealStart, greaterThanOrEqualTo(0));
    final reveal = windowSource.substring(
      revealStart,
      windowSource.indexOf('result->Success();', revealStart),
    );
    expect(reveal, contains('startup_watchdog::RequestStop();'));
    final stop = source.substring(source.indexOf('void Stop()'));
    expect(stop, contains('RequestStop();'));
    expect(stop, contains('g_watcher.joinable()'));
    expect(stop, contains('g_watcher.join()'));
  });

  group('hang_monitor', () {
    final hang = File(
      'windows/runner/hang_monitor.cpp',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final normalizedMain = mainSource.replaceAll('\r\n', '\n');
    final normalizedWindow = windowSource.replaceAll('\r\n', '\n');
    final watcher = hang.substring(
      hang.indexOf('void WatcherLoop()'),
      hang.indexOf('}  // namespace'),
    );

    test('IsHungAppWindow ולא WM_TIMER, שמורעב בהצפת הודעות', () {
      expect(watcher, contains('::IsHungAppWindow(g_window)'));
      expect(hang, isNot(contains('SetTimer(')));
      expect(watcher, isNot(contains('WM_TIMER')));
      expect(watcher, contains('kRequiredHungPolls'));
    });

    test('מתעלם מדיבאגר ומחזרה משינה', () {
      expect(watcher, contains('::IsDebuggerPresent()'));
      expect(hang, contains('::QueryUnbiasedInterruptTime('));
      expect(watcher, contains('::GetTickCount64()'));
      expect(watcher, contains('awake < grace_until'));
    });

    test('מתרגם לשמות מודולים רק אחרי חידוש ה-thread', () {
      final captureFrames = hang.substring(
        hang.indexOf('std::vector<ULONG_PTR> CaptureFrames()'),
        hang.indexOf('void ReportRecovered('),
      );
      expect(
        captureFrames,
        contains('startup_watchdog::CaptureMainStack(&frames);'),
      );
      expect(captureFrames, isNot(contains('AppendStack(')));
      // התרגום ב-ReportHang/ReportSample, אחרי שהלכידה חזרה.
      expect(watcher, contains('ReportHang(CaptureFrames(), reports == 1);'));
      expect(
        watcher,
        contains(
          'ReportSample(++samples, awake - hang_started_at, CaptureFrames());',
        ),
      );
      expect(watcher, isNot(contains('AppendStack(')));
      expect(watcher, isNot(contains('RefreshModules')));
      expect(watcher, isNot(contains('EnumProcessModules')));
      expect(hang, isNot(contains('DescribeAddress')));
      expect(hang, isNot(contains('SuspendThread')));
    });

    test('פורמט הרשומה תואם את המפענח (App hang / AppHang)', () {
      expect(hang, contains('"\\n=== App hang " + startup_watchdog::'));
      expect(hang, contains('"Message: AppHang: UI thread not responding\\n"'));
      expect(hang, contains('"\\n=== App hang recovered " +'));
      expect(hang, contains('"Duration: %llums\\n"'));
    });

    test('זהות הבנייה לפני Stack, ודגימות נוספות אחרי `---` ובמספר מוגבל', () {
      final report = hang.substring(
        hang.indexOf('void ReportHang('),
        hang.indexOf('void ReportSample('),
      );
      expect(
        report.indexOf('AppendBuildIdentity(all_frames, &report);'),
        allOf(
          greaterThanOrEqualTo(0),
          lessThan(report.indexOf('AppendStack(frames, &report);')),
        ),
      );
      final sample = hang.substring(
        hang.indexOf('void ReportSample('),
        hang.indexOf('std::vector<ULONG_PTR> CaptureFrames()'),
      );
      expect(sample, contains('"--- Sample %d, %llums into the hang ---\\n"'));
      expect(sample, isNot(contains('=== ')));
      expect(watcher, contains('samples < kMaxExtraSamples'));
      expect(watcher, contains('awake - last_sample_at >= kSampleIntervalMs'));
    });

    test('מתחיל בחשיפה, רק בחלון ראשי שאינו CLI, ונעצר לפני ה-watchdog', () {
      final revealStart = normalizedWindow.indexOf(
        'if (call.method_name() == "close")',
      );
      final reveal = normalizedWindow.substring(
        revealStart,
        normalizedWindow.indexOf('result->Success();', revealStart),
      );
      expect(
        reveal.indexOf('hang_monitor::Start();'),
        greaterThan(reveal.indexOf('startup_watchdog::RequestStop();')),
      );
      expect(
        normalizedMain,
        contains(
          'if (!is_cli_invocation) hang_monitor::SetMainWindow(main_hwnd);',
        ),
      );
      final exit = normalizedMain.lastIndexOf('startup_watchdog::Stop();');
      expect(
        normalizedMain.lastIndexOf('hang_monitor::Stop();'),
        allOf(greaterThanOrEqualTo(0), lessThan(exit)),
      );
      expect(
        File('windows/runner/CMakeLists.txt').readAsStringSync(),
        contains('"hang_monitor.cpp"'),
      );
    });

    test('השחרור מגיע ל-Dart דרך process_control', () {
      final start = normalizedWindow.indexOf(
        'if (message == hang_monitor::kMsgAppHangRecovered)',
      );
      expect(start, greaterThanOrEqualTo(0));
      final handler = normalizedWindow.substring(
        start,
        normalizedWindow.indexOf('return 0;', start),
      );
      expect(handler, contains('"appHangRecovered"'));
      expect(handler, contains('"durationMs"'));
    });
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

  test('מחסנית עמוקה: ראש, שורת השמטה שמתחילה ב-"..." ותחתית', () {
    // error_log_blocks.dart מחשב את חתימת התקיעה רק מהשורות שלפני "...".
    expect(source, contains('constexpr size_t kTopFrames = 48;'));
    expect(source, contains(r'"  ... (%zu frames omitted%s) ...\n"'));
    final section = source.substring(
      source.indexOf('void AppendStackSection('),
      source.indexOf('void AppendBuildIdentitySection('),
    );
    expect(section, contains('i == kTopFrames'));
    expect(section, contains('count - kTopFrames - kBottomFrames'));
  });
}
