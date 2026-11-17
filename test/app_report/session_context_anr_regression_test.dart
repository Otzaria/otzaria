import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_report/repository/app_report_collector.dart';
import 'package:otzaria/app_report/services/android_anr_source.dart';
import 'package:otzaria/app_report/services/session_context_snapshot.dart';
import 'package:otzaria/app_report/services/unclean_exit_detector.dart';
import 'package:otzaria/app_report/view/crash_prompt_dialog.dart';
import 'package:otzaria/core/app_paths.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ANR מתהליך שלא שמר הקשר אינו מקבל את ההקשר של קודמו', () async {
    final tmp = Directory.systemTemp.createTempSync('anr_context_');
    AppPaths.debugOverrideDataRootPath(tmp.path);
    addTearDown(() {
      AppPaths.debugOverrideDataRootPath(null);
      tmp.deleteSync(recursive: true);
    });

    final snapshot = SessionContextSnapshot.instance;
    File(snapshot.path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'pid': 111,
          'savedAt': '2026-11-15T22:00:00.000Z',
          'context': {'screen': 'search'},
        }),
      );
    final statePath = '${tmp.path}/anr_state.json';
    File(statePath).writeAsStringSync('{"lastTimestamp":1}');
    final anr = await AndroidAnrSource(
      isAndroid: true,
      stateFilePath: statePath,
      invoker: (_) async => {
        'exits': [
          {
            'pid': 222,
            'timestamp': DateTime.utc(2026, 11, 15, 23).millisecondsSinceEpoch,
            'importance': 100,
            'mainThreadTrace': 'at org.otzaria.Blocking.call(Blocking.java:1)',
          },
        ],
      },
    ).takeNewAnr();
    expect(anr, isNotNull);
    final candidate = CrashCandidate.hang(
      signature: anr!.signature,
      details: anr.details,
      occurredInPreviousRun: true,
    );

    final automatic = await AppReportCollector(
      includeCurrentContext: false,
      previousRunContext: () => snapshot.previousFor(candidate.previousSession),
      appInfoLoader: () async => {},
    ).collectDiagnostics();
    final prompted = await CrashPromptDialog.collectorFor(
      candidate,
    ).collectDiagnostics();

    for (final diagnostics in [automatic, prompted]) {
      expect(diagnostics.containsKey('previousRun'), isFalse);
      expect(diagnostics.containsKey('context'), isFalse);
      expect(diagnostics.containsKey('searches'), isFalse);
    }
    expect((await snapshot.previous)?['pid'], 111);
  });
}
