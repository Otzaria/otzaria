import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/many_listener_value_notifier.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

void main() {
  test('מודיע רק כשהערך משתנה', () {
    final notifier = ManyListenerValueNotifier<int>(0);
    var calls = 0;
    notifier.addListener(() => calls++);

    notifier.value = 0;
    expect(calls, 0);
    notifier.value = 1;
    expect((notifier.value, calls), (1, 1));
  });

  test('מאזין שנוסף פעמיים נשאר עד שהוסר פעמיים', () {
    final notifier = ManyListenerValueNotifier<int>(0);
    var calls = 0;
    void listener() => calls++;
    notifier
      ..addListener(listener)
      ..addListener(listener)
      ..removeListener(listener);

    notifier.value = 1;
    expect(calls, 1);
    notifier.removeListener(listener);
    notifier.value = 2;
    expect(calls, 1);
  });

  test('מאזין שהוסר בזמן ההודעה אינו נקרא, ושגיאה אינה עוצרת את השאר', () {
    final notifier = ManyListenerValueNotifier<int>(0);
    final called = <String>[];
    void second() => called.add('second');
    notifier
      ..addListener(() {
        called.add('first');
        notifier.removeListener(second);
        throw StateError('listener failed');
      })
      ..addListener(second)
      ..addListener(() => called.add('third'));
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    try {
      notifier.value = 1;
    } finally {
      FlutterError.onError = previous;
    }

    expect(called, ['first', 'third']);
    expect(errors.single.exception, isA<StateError>());
  });

  test('פירוק אלפי שורות שמאזינות לתבנית החיפוש אינו ריבועי (#3145)', () {
    // עם ValueNotifier: כ-6 שניות ל-20 אלף מאזינים שמוסרים בסדר הפוך.
    final listeners = [for (var i = 0; i < 20000; i++) () {}];
    for (final listener in listeners) {
      highlightPatternRevision.addListener(listener);
    }
    final stopwatch = Stopwatch()..start();
    for (final listener in listeners.reversed) {
      highlightPatternRevision.removeListener(listener);
    }
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
  });
}
