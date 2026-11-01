import 'dart:async';

import 'package:flutter/services.dart';

/// פותח ספר בחלון אוצר החכמה הפתוח, דרך ה-runner של Windows בלבד.
/// הצלחה פירושה שהקלט נשלח, לא שהספר אכן נפתח.
abstract final class OtzarMainWindowInput {
  static const channel = MethodChannel('otzaria/otzar_main_window');
  static Future<void> _pending = Future<void>.value();

  static Future<void> openBook(int bookId) {
    if (bookId <= 0) {
      return Future<void>.error(ArgumentError.value(bookId, 'bookId'));
    }
    final operation = _pending.then(
      (_) => channel.invokeMethod<void>('openBookById', <String, Object>{
        'bookId': bookId,
      }),
    );
    // A failed request must not poison the queue for subsequent requests.
    _pending = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return operation;
  }
}
