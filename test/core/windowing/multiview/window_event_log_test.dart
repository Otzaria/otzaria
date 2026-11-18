import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/multiview/window_event_log.dart';

void main() {
  test('שומר רק את האירועים האחרונים, מהישן לחדש', () {
    final log = WindowEventLog(capacity: 3, now: () => DateTime.utc(2026));
    for (var i = 0; i < 5; i++) {
      log.add('open', {'slot': i});
    }

    final events = log.collect();
    expect(events.map((e) => e['slot']), [2, 3, 4]);
    expect(events.first['at'], '2026-01-01T00:00:00.000Z');
    expect(events.first['event'], 'open');
  });
}
