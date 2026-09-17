import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:path/path.dart' as p;

/// רישום זמני לאבחון issue #1386 — קפיצות גלילה בסוף מסך ההגדרות במק.
///
/// רושם כל אירוע מצביע ואת מיקום הגלילה בכל פריים אל `logs/scroll_diag.txt`,
/// כדי לזהות מי מזיז את המיקום. להסרה עם סגירת ה-issue.
class ScrollDiagnostics {
  ScrollDiagnostics._();

  static const int _maxLines = 60000;

  static final List<String> _buffer = [];
  static bool _started = false;
  static int _written = 0;
  static DateTime? _epoch;
  static ScrollPosition? _position;
  static double? _lastPixels;
  static String? _lastActivity;

  static String get logPath =>
      p.join(p.dirname(ErrorLogFile.resolvePath()), 'scroll_diag.txt');

  static void start() {
    if (_started) return;
    _started = true;
    _epoch = DateTime.now();
    _log('=== scroll_diag start ${_epoch!.toIso8601String()} ===');
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointerEvent);
    WidgetsBinding.instance.addPersistentFrameCallback(_onFrame);
  }

  /// עוקב אחרי ה-[ScrollPosition] של אזור התוכן שבו הבאג מופיע.
  static void watch(ScrollController controller) {
    if (!controller.hasClients) return;
    _position = controller.position;
  }

  static void _onPointerEvent(PointerEvent event) {
    final String? line = switch (event) {
      PointerScrollEvent() =>
        'scroll dy=${event.scrollDelta.dy.toStringAsFixed(1)} '
            'dx=${event.scrollDelta.dx.toStringAsFixed(1)} kind=${event.kind.name} '
            'dev=${event.device}',
      PointerScrollInertiaCancelEvent() =>
        'inertiaCancel kind=${event.kind.name}',
      PointerPanZoomStartEvent() => 'panZoomStart',
      PointerPanZoomUpdateEvent() =>
        'panZoomUpdate pan=${event.pan.dy.toStringAsFixed(1)},'
            '${event.pan.dx.toStringAsFixed(1)} scale=${event.scale.toStringAsFixed(2)}',
      PointerPanZoomEndEvent() => 'panZoomEnd',
      PointerHoverEvent() => null,
      PointerDownEvent() => 'down btn=${event.buttons}',
      PointerUpEvent() => 'up',
      _ => null,
    };
    if (line != null) _log(line);
    if (event is PointerPanZoomEndEvent || event is PointerUpEvent) flush();
  }

  static void _onFrame(Duration _) {
    final position = _position;
    if (position == null || !position.hasPixels) return;
    // מדפיסים רק כשמשהו השתנה — אחרת הלוג מתמלא בפריימים זהים.
    // תיאור ה-ScrollPosition כולל את ה-ScrollActivity הפעילה, וזו התשובה
    // לשאלה מי מזיז את המיקום: גרירה, בליסטיקה או קפיצה מאולצת.
    final activity = _activityOf(position);
    final pixels = position.pixels;
    if (_lastPixels != null &&
        (pixels - _lastPixels!).abs() < 0.01 &&
        activity == _lastActivity) {
      return;
    }
    _lastPixels = pixels;
    _lastActivity = activity;
    _log(
      'frame px=${pixels.toStringAsFixed(1)} max=${position.maxScrollExtent.toStringAsFixed(1)} '
      'viewport=${position.viewportDimension.toStringAsFixed(1)} activity=$activity '
      'dir=${position.userScrollDirection.name}',
    );
  }

  static String _activityOf(ScrollPosition position) {
    final match = RegExp(
      r'(\w*ScrollActivity)#',
    ).firstMatch(position.toString());
    return match?.group(1) ?? 'unknown';
  }

  static void _log(String line) {
    if (_written >= _maxLines) return;
    _written++;
    final ms = _epoch == null
        ? 0
        : DateTime.now().difference(_epoch!).inMilliseconds;
    _buffer.add('$ms $line');
    if (_buffer.length >= 200) flush();
  }

  static void flush() {
    if (_buffer.isEmpty) return;
    final lines = _buffer.join('\n');
    _buffer.clear();
    try {
      final file = File(logPath);
      if (!file.parent.existsSync()) file.parent.createSync(recursive: true);
      file.writeAsStringSync('$lines\n', mode: FileMode.append, flush: true);
    } catch (_) {
      // אבחון בלבד — כישלון כתיבה לא מפיל כלום.
    }
  }
}
