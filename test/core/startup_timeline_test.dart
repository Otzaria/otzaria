import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/startup_timeline.dart';

void main() {
  test('עלייה מהירה אינה נרשמת', () async {
    final written = <String>[];
    final timeline = StartupTimeline(
      sink: written.add,
      slowThreshold: const Duration(hours: 1),
    )..start();
    await timeline.phase('sqlite', () async {});
    timeline.finishAtReveal();
    expect(written, isEmpty);
  });

  test('עלייה איטית נרשמת פעם אחת עם הפאזות והציונים', () async {
    final written = <String>[];
    final timeline = StartupTimeline(
      sink: written.add,
      slowThreshold: Duration.zero,
    )..start();
    await timeline.phase('initHive', () async {});
    await expectLater(
      timeline.phase('sqlite', () async => throw StateError('boom')),
      throwsStateError,
    );
    timeline.mark('bootstrapDone');
    timeline.finishAtReveal(now: DateTime.utc(2026, 9, 7), version: '1.2.3');
    timeline.finishAtReveal();

    expect(written, hasLength(1));
    final report = written.single;
    expect(report, startsWith('=== Slow startup 2026-09-07T00:00:00.000Z ==='));
    expect(report, contains('Version: 1.2.3'));
    expect(report, contains(RegExp(r'Window shown after: \d+ms')));
    expect(report, contains(RegExp(r'  initHive: @\d+ms \d+ms')));
    expect(report, contains(RegExp(r'  sqlite: @\d+ms \d+ms')));
    expect(report, contains(RegExp(r'  bootstrapDone: @\d+ms')));
  });

  test('הפאזה מחזירה את תוצאת הגוף', () async {
    final timeline = StartupTimeline(sink: (_) {})..start();
    expect(await timeline.phase('x', () async => 42), 42);
  });
}
