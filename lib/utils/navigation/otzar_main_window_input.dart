import 'dart:async';

import 'package:flutter/services.dart';

/// Windows-only adapter. The runner owns the actual Win32 input operation.
/// Success means input was sent, not that the intended book was rendered.
abstract final class OtzarMainWindowInput {
  static const channel = MethodChannel('otzaria/otzar_main_window');
  static Future<void> _pending = Future<void>.value();

  static Future<void> openBook(int bookId) {
    if (bookId <= 0) {
      return Future<void>.error(ArgumentError.value(bookId, 'bookId'));
    }
    final operation = _pending.then((_) async {
      final result = await channel.invokeMapMethod<String, dynamic>(
        'openBookById',
        <String, Object>{'bookId': bookId},
      );
      if (result?['sent'] != true) {
        throw PlatformException(
          code: 'input_not_confirmed',
          message: 'The Windows runner did not confirm input delivery.',
        );
      }
    });
    // A failed request must not poison the queue for subsequent requests.
    _pending = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return operation;
  }
}
