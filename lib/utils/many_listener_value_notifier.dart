import 'package:flutter/foundation.dart';

/// [ValueListenable] שכל שורה מוצגת יכולה להאזין לו.
///
/// [ChangeNotifier] סורק ומזיז את רשימת המאזינים בכל הסרה, ולכן פירוק של
/// אלפי שורות שמאזינות לאותו מופע הוא ריבועי (#3145). כאן ההסרה ב-O(1).
class ManyListenerValueNotifier<T> implements ValueListenable<T> {
  ManyListenerValueNotifier(this._value);

  T _value;
  final Map<VoidCallback, int> _listeners = {};

  @override
  T get value => _value;

  set value(T newValue) {
    if (_value == newValue) return;
    _value = newValue;
    for (final listener in List.of(_listeners.keys)) {
      // מאזין שהוסר בזמן ההודעה אינו נקרא, כמו ב-ChangeNotifier.
      if (!_listeners.containsKey(listener)) continue;
      try {
        listener();
      } catch (exception, stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: exception,
            stack: stack,
            library: 'foundation library',
            context: ErrorDescription(
              'while dispatching notifications for $runtimeType',
            ),
          ),
        );
      }
    }
  }

  @override
  void addListener(VoidCallback listener) =>
      _listeners.update(listener, (count) => count + 1, ifAbsent: () => 1);

  @override
  void removeListener(VoidCallback listener) {
    final count = _listeners[listener];
    if (count == null) return;
    if (count == 1) {
      _listeners.remove(listener);
    } else {
      _listeners[listener] = count - 1;
    }
  }
}
