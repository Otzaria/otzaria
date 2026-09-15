import 'dart:convert';

/// גבולות חלון כפי שנשמרים בסשן שלו (`window_sessions.bounds_json`).
///
/// הגבולות לוגיים, כפי ש-`getBounds` מחזיר, לצד ה-DPR של רגע השמירה —
/// כך אפשר לשחזר את הפיזי במדויק גם כשה-DPR השתנה. חלון ממוקסם שומר את
/// הדגל בלבד ומשאיר את גבולות ה"רגיל" האחרונים.
class WindowBounds {
  const WindowBounds({
    this.left,
    this.top,
    this.width,
    this.height,
    this.dpr,
    this.maximized = false,
  });

  final double? left;
  final double? top;
  final double? width;
  final double? height;
  final double? dpr;
  final bool maximized;

  bool get hasRect =>
      left != null && top != null && width != null && height != null;

  WindowBounds copyWith({
    double? left,
    double? top,
    double? width,
    double? height,
    double? dpr,
    bool? maximized,
  }) => WindowBounds(
    left: left ?? this.left,
    top: top ?? this.top,
    width: width ?? this.width,
    height: height ?? this.height,
    dpr: dpr ?? this.dpr,
    maximized: maximized ?? this.maximized,
  );

  /// מפענח JSON שמור; null או JSON פגום → null.
  static WindowBounds? decode(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map) return null;
      double? number(Object? v) => v is num ? v.toDouble() : null;
      return WindowBounds(
        left: number(decoded['left']),
        top: number(decoded['top']),
        width: number(decoded['width']),
        height: number(decoded['height']),
        dpr: number(decoded['dpr']),
        maximized: decoded['maximized'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  String encode() => jsonEncode({
    if (left != null) 'left': left,
    if (top != null) 'top': top,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    if (dpr != null) 'dpr': dpr,
    'maximized': maximized,
  });

  /// המסגרת בפיקסלים פיזיים, כפי שה-runner מצפה ב-`openWindow`.
  ({int left, int top, int width, int height})? toPhysical() {
    if (!hasRect) return null;
    final scale = (dpr != null && dpr! > 0) ? dpr! : 1.0;
    return (
      left: (left! * scale).round(),
      top: (top! * scale).round(),
      width: (width! * scale).round(),
      height: (height! * scale).round(),
    );
  }
}
