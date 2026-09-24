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
  static GlobalKey? _contentKey;
  static double? _lastPixels;
  static double? _lastMax;
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

  /// שורש התוכן הנגלל — ממנו סורקים את גבהי התיבות כדי לזהות מי משתנה.
  static void watchContent(GlobalKey key) => _contentKey = key;

  /// גבהי התיבות מהסריקה הקודמת, לפי נתיב בעץ.
  static Map<String, ({double height, String type})> _heights = {};

  static Map<String, ({double height, String type})> _scanHeights() {
    final result = <String, ({double height, String type})>{};
    final root = _contentKey?.currentContext?.findRenderObject();
    if (root is! RenderBox) return result;
    void visit(RenderObject node, String path, int depth) {
      if (result.length > 4000 || depth > 8) return;
      if (node is RenderBox && node.hasSize) {
        result[path] = (height: node.size.height, type: '${node.runtimeType}');
      }
      var index = 0;
      node.visitChildren((child) {
        visit(child, '$path/${index++}', depth + 1);
      });
    }

    visit(root, '', 0);
    return result;
  }

  /// רושם אילו תיבות שינו גובה מאז הסריקה הקודמת — כך מאתרים את הרכיב
  /// שמזיז את גבול הגלילה בשבריר פיקסל.
  static void _logHeightChanges() {
    final Map<String, ({double height, String type})> current;
    try {
      current = _scanHeights();
    } catch (_) {
      return;
    }
    if (_heights.isNotEmpty) {
      var reported = 0;
      for (final entry in current.entries) {
        final previous = _heights[entry.key];
        if (previous == null || previous.height == entry.value.height) continue;
        if (reported++ >= 12) break;
        _log(
          'height ${entry.key} ${entry.value.type} '
          '${previous.height.toStringAsFixed(3)} -> '
          '${entry.value.height.toStringAsFixed(3)}',
        );
      }
      final added = current.length - _heights.length;
      if (added != 0) _log('height boxCountDelta=$added');
    }
    _heights = current;
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
    // תיאור מלא של ה-ScrollActivity קיים רק בבנייה debug, ולכן בגרסת release
    // נשאר הדגל הזה בלבד.
    final activity = 'scrolling=${position.isScrollingNotifier.value}';
    final pixels = position.pixels;
    final max = position.maxScrollExtent;
    // שינוי של שבריר פיקסל בגבול הוא הטריגר לבאג, ולכן נסרק בכל שינוי שלו.
    final maxChanged = _lastMax == null || (max - _lastMax!).abs() > 0.0001;
    if (maxChanged) {
      _log(
        'maxChanged ${_lastMax?.toStringAsFixed(4) ?? '-'} -> '
        '${max.toStringAsFixed(4)} over=${(pixels - max).toStringAsFixed(2)}',
      );
      _lastMax = max;
      _logHeightChanges();
    }
    if (_lastPixels != null &&
        (pixels - _lastPixels!).abs() < 0.01 &&
        activity == _lastActivity) {
      return;
    }
    _lastPixels = pixels;
    _lastActivity = activity;
    _log(
      'frame px=${pixels.toStringAsFixed(2)} max=${max.toStringAsFixed(4)} '
      'viewport=${position.viewportDimension.toStringAsFixed(1)} activity=$activity '
      'dir=${position.userScrollDirection.name}',
    );
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
