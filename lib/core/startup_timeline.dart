import 'package:flutter/foundation.dart';
import 'package:otzaria/core/error_log_file.dart';

/// ציר הזמן של עליית התוכנה, מ-`main()` ועד חשיפת החלון הראשי.
///
/// החלון הראשי מוסתר עד `presentMainWindow`, ורשת הביטחון של המסך הראשי
/// מתחילה רק אחרי הבוטסטרפ — עלייה איטית נראית למשתמש כסמל צף בלבד, ובלי
/// הרשומה הזו ב-errors.txt אין דרך לדעת איזה שלב עיכב אותה (issue #1192).
class StartupTimeline {
  StartupTimeline({
    void Function(String text)? sink,
    this.slowThreshold = const Duration(seconds: 20),
  }) : _sink = sink ?? ErrorLogFile.appendText;

  static final StartupTimeline instance = StartupTimeline();

  /// עלייה שנמשכה פחות מזה אינה נרשמת — errors.txt נשאר יומן של תקלות בלבד.
  final Duration slowThreshold;

  final void Function(String text) _sink;
  final Stopwatch _clock = Stopwatch();
  final List<_Phase> _phases = [];
  final List<_Mark> _marks = [];
  bool _reported = false;

  /// מתחיל את השעון. קריאה חוזרת אינה מאפסת אותו.
  void start() {
    if (!_clock.isRunning && _clock.elapsedTicks == 0) _clock.start();
  }

  int get elapsedMs => _clock.elapsedMilliseconds;

  /// מריץ שלב עלייה ורושם את משכו. חריגה עוברת הלאה; המשך נרשם גם אז.
  Future<T> phase<T>(String name, Future<T> Function() body) async {
    final startedAt = elapsedMs;
    try {
      return await body();
    } finally {
      _phases.add(_Phase(name, startedAt, elapsedMs - startedAt));
    }
  }

  /// נקודת ציון ללא משך — למשל "הבוטסטרפ הסתיים" או "חשיפה דרך רשת הביטחון".
  void mark(String name) => _marks.add(_Mark(name, elapsedMs));

  /// נקרא בחשיפת החלון הראשי. רושם ללוג רק אם העלייה חרגה מ-[slowThreshold].
  /// הקריאה הראשונה בלבד נחשבת — הפעלה מחדש של העץ אינה רושמת שוב.
  void finishAtReveal({DateTime? now, String? version}) {
    if (_reported) return;
    _reported = true;
    _clock.stop();
    if (_clock.elapsed < slowThreshold) return;
    try {
      _sink(format(now: now, version: version));
    } catch (error) {
      debugPrint('⚠️ רישום ציר הזמן של העלייה נכשל: $error');
    }
  }

  /// הרשומה כפי שתיכתב ל-errors.txt.
  String format({DateTime? now, String? version}) {
    final buffer = StringBuffer()
      ..writeln(
        '=== Slow startup ${(now ?? DateTime.now()).toIso8601String()} ===',
      )
      ..writeln('Version: ${version ?? ErrorLogFile.appVersion}')
      ..writeln('Window shown after: ${_clock.elapsedMilliseconds}ms')
      ..writeln(
        'Measured from Dart main(); native/engine startup before it is not '
        'included. A gap between one phase end and the next start is time '
        'spent outside the measured phases.',
      )
      ..writeln('Phases (start → duration):');
    for (final phase in _phases) {
      buffer.writeln(
        '  ${phase.name}: @${phase.startedAtMs}ms ${phase.durationMs}ms',
      );
    }
    if (_marks.isNotEmpty) {
      buffer.writeln('Marks:');
      for (final mark in _marks) {
        buffer.writeln('  ${mark.name}: @${mark.atMs}ms');
      }
    }
    buffer.writeln();
    return buffer.toString();
  }
}

class _Phase {
  const _Phase(this.name, this.startedAtMs, this.durationMs);
  final String name;
  final int startedAtMs;
  final int durationMs;
}

class _Mark {
  const _Mark(this.name, this.atMs);
  final String name;
  final int atMs;
}
