import 'package:flutter/foundation.dart';

/// Thrown by [PreCloseRegistry.runAll] when one or more registered callbacks
/// fail after their retry budget is exhausted.
///
/// All callbacks are still attempted even if some fail, so [errors] can
/// contain entries for multiple callbacks.
class PreCloseFlushFailure implements Exception {
  /// Per-callback error messages (one entry per failed callback).
  final List<String> errors;

  const PreCloseFlushFailure(this.errors);

  @override
  String toString() =>
      'PreCloseFlushFailure: ${errors.length} flush callback(s) '
      'failed at app exit:\n${errors.join('\n')}';
}

/// Registry for callbacks that must run before the app closes Hive and exits.
///
/// Usage:
///   - Register a flush callback in a BLoC/service constructor.
///   - Unregister in close()/dispose().
///   - AppWindowListener calls [runAll] before Hive.close().
class PreCloseRegistry {
  PreCloseRegistry._();

  static final List<Future<void> Function()> _callbacks = [];

  /// Register a callback to run before app close.
  static void register(Future<void> Function() callback) {
    _callbacks.add(callback);
  }

  /// Unregister a previously registered callback.
  static void unregister(Future<void> Function() callback) {
    _callbacks.remove(callback);
  }

  /// Run all registered callbacks in order.
  ///
  /// Each callback is retried once on failure (2 attempts total, 50 ms apart).
  /// All callbacks are run regardless of individual failures — no callback is
  /// skipped because a preceding one failed.
  ///
  /// Throws [PreCloseFlushFailure] if one or more callbacks exhaust their
  /// retry budget, so the caller can treat persistent flush failures as a
  /// first-class error (e.g. report to crash monitoring) rather than a silent
  /// log that is invisible in production.
  static Future<void> runAll() async {
    final errors = <String>[];

    for (final callback in List<Future<void> Function()>.from(_callbacks)) {
      bool succeeded = false;
      Object? lastError;
      for (int attempt = 1; attempt <= 2 && !succeeded; attempt++) {
        try {
          await callback();
          succeeded = true;
        } catch (e) {
          lastError = e;
          debugPrint(
            '⚠️ PreCloseRegistry callback attempt $attempt/2 failed: $e',
          );
          if (attempt < 2) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
        }
      }
      if (!succeeded) {
        errors.add(lastError.toString());
      }
    }

    if (errors.isNotEmpty) {
      throw PreCloseFlushFailure(errors);
    }
  }
}
