import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// משאיר את כפתורי החלון ואת אזורי הגרירה של שורת הכותרת פעילים גם כשדיאלוג
/// פתוח (DD-16). עוטף את ה-Navigator, ב-`builder` של ה-MaterialApp.
///
/// שכבת ההחשכה של דיאלוג (ModalBarrier) מכסה את כל החלון, גם את שורת
/// הכותרת. בנקודה שבתוך [WindowCaptionRegion] בודקים קודם מה הבדיקה הרגילה
/// פוגעת בו:
/// - האזור עצמו: אין מה לשנות.
/// - תיבה בגודל החלון כולו: זו שכבת ההחשכה. האזור מקבל את האירוע ישירות,
///   ושאר השורה (כרטיסיות, היסטוריה, סימניות) נשארת חסומה. באזור גרירה
///   ([WindowCaptionRegion.isDragArea]) גם ההחשכה מקבלת אותו אחרי האזור,
///   ולכן לחיצה על חלק ריק בשורה סוגרת תפריט, וגרירה מזיזה את החלון.
/// - כל דבר אחר (תוכן דיאלוג או תפריט מעל השורה): הוא מקבל את האירוע,
///   כמו שהוא מצויר.
///
/// אזור שחסום במקומו (IgnorePointer, AbsorbPointer או Offstage מעליו, כמו
/// התוכן שמתחת למסך הפתיחה) לא מקבל את האירוע גם מעל שכבה בגודל החלון.
///
/// הפוקוס, Esc והמלכודת של הדיאלוג לא משתנים: כפתורי החלון אינם ניתנים
/// לפוקוס. הסגירה עוברת באותו מסלול כמו Alt+F4 (`onWindowClose`), ודיאלוג
/// עם שינויים שלא נשמרו שואל קודם (`DialogDismissGuard.confirmWindowClose`).
class WindowCaptionHitTestScope extends SingleChildRenderObjectWidget {
  const WindowCaptionHitTestScope({super.key, required Widget super.child});

  @override
  RenderWindowCaptionHitTestScope createRenderObject(BuildContext context) =>
      RenderWindowCaptionHitTestScope();
}

/// ה-RenderObject של [WindowCaptionHitTestScope]. ציבורי בשביל הבדיקות.
class RenderWindowCaptionHitTestScope extends RenderProxyBox {
  final List<_RenderWindowCaptionRegion> _regions = [];

  /// true בזמן שה-scope בודק אזור ישירות, מעל שכבת ההחשכה. אזור
  /// [WindowCaptionRegion.onlyAboveDialogs] פעיל רק אז.
  bool _redirecting = false;

  void _add(_RenderWindowCaptionRegion region) => _regions.add(region);

  void _remove(_RenderWindowCaptionRegion region) => _regions.remove(region);

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    for (final region in _regions.reversed) {
      if (!_isLiveAt(region, position)) continue;
      if (!_coveredByBarrier(region, position)) break;
      // אזור גרירה שקוף (translucent) נרשם בתוצאה גם כשהוא מחזיר false.
      final before = result.path.length;
      result.addWithPaintTransform(
        transform: region.getTransformTo(this),
        position: position,
        hitTest: (result, local) {
          _redirecting = true;
          try {
            return region.hitTest(result, position: local);
          } finally {
            _redirecting = false;
          }
        },
      );
      if (result.path.length > before) {
        // באזור ריק בשורה (אזור גרירה) גם שכבת ההחשכה מקבלת את האירוע,
        // אחרי האזור: גרירה זוכה בזירת המחוות ומזיזה את החלון, ולחיצה
        // פשוטה מגיעה להחשכה וסוגרת תפריט או דיאלוג שנסגר בלחיצה בחוץ,
        // כמו לפני DD-16. כפתורי החלון פועלים בלי לסגור אותם.
        if (_inDragArea(position)) {
          return super.hitTest(result, position: position);
        }
        result.add(BoxHitTestEntry(this, position));
        return true;
      }
      break;
    }
    return super.hitTest(result, position: position);
  }

  /// האם [region] פעיל ומכיל את הנקודה.
  bool _isLiveAt(_RenderWindowCaptionRegion region, Offset position) {
    if (!region.attached || !region.hasSize) return false;
    if (_isInert(region)) return false;
    final local = MatrixUtils.transformPoint(
      Matrix4.tryInvert(region.getTransformTo(this)) ?? Matrix4.identity(),
      position,
    );
    return (Offset.zero & region.size).contains(local);
  }

  /// האם הנקודה באזור גרירה ([WindowCaptionRegion.isDragArea]) — חלק ריק
  /// של השורה, ולא כפתור חלון.
  bool _inDragArea(Offset position) => _regions.any(
    (region) => region.isDragArea && _isLiveAt(region, position),
  );

  /// האם מה שמעל [region] בנקודה הזו הוא תיבה בגודל החלון (שכבת ההחשכה).
  bool _coveredByBarrier(RenderBox region, Offset position) {
    final probe = BoxHitTestResult();
    super.hitTest(probe, position: position);
    if (probe.path.isEmpty) return false;
    final top = probe.path.first.target;
    if (_isWithin(top, region)) return false;
    return top is RenderBox &&
        top.hasSize &&
        top.size.width >= size.width - 1 &&
        top.size.height >= size.height - 1;
  }

  /// האם [region] חסום במקומו, ולכן אסור לעקוף בשבילו את שכבת ההחשכה:
  /// IgnorePointer או AbsorbPointer פעילים, או Offstage, בינו לבין ה-scope.
  /// כך, למשל, כפתורי החלון המוסתרים מתחת למסך הפתיחה נשארים חסומים.
  bool _isInert(RenderObject region) {
    var node = region.parent;
    while (node != null && !identical(node, this)) {
      if (node is RenderIgnorePointer && node.ignoring) return true;
      if (node is RenderAbsorbPointer && node.absorbing) return true;
      if (node is RenderOffstage && node.offstage) return true;
      node = node.parent;
    }
    return false;
  }

  bool _isWithin(HitTestTarget target, RenderObject region) {
    RenderObject? node = target is RenderObject ? target : null;
    while (node != null && !identical(node, this)) {
      if (identical(node, region)) return true;
      node = node.parent;
    }
    return false;
  }
}

/// אזור בשורת הכותרת שנשאר פעיל מעל דיאלוג: כפתורי החלון ואזורי הגרירה.
/// בלי [WindowCaptionHitTestScope] מעליו (טלפון, רשת, בדיקות) אין לו השפעה.
///
/// ⚠️ לעטוף רק את מה שמותר להפעיל כשדיאלוג פתוח. כל מה שבתוך האזור
/// מקבל לחיצות מעל שכבת ההחשכה.
class WindowCaptionRegion extends SingleChildRenderObjectWidget {
  const WindowCaptionRegion({
    super.key,
    this.isDragArea = false,
    this.onlyAboveDialogs = false,
    required Widget super.child,
  });

  /// true: חלק ריק של השורה (אזור גרירה). מעל דיאלוג, לחיצה פשוטה כאן מגיעה
  /// גם לשכבת ההחשכה, וסוגרת תפריט או דיאלוג שנסגר בלחיצה בחוץ; גרירה מזיזה
  /// את החלון. false (כפתורי החלון): רק האזור מקבל את האירוע.
  final bool isDragArea;

  /// true: האזור קיים רק מעל דיאלוג. בלי דיאלוג הוא ותוכנו שקופים לגמרי
  /// לבדיקת הפגיעה, למשל כשהשורה שמתחתיו כבר מטפלת בגרירה בעצמה.
  final bool onlyAboveDialogs;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderWindowCaptionRegion()
        ..isDragArea = isDragArea
        ..onlyAboveDialogs = onlyAboveDialogs;

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderWindowCaptionRegion)
      ..isDragArea = isDragArea
      ..onlyAboveDialogs = onlyAboveDialogs;
  }
}

class _RenderWindowCaptionRegion extends RenderProxyBox {
  RenderWindowCaptionHitTestScope? _scope;

  bool isDragArea = false;

  bool onlyAboveDialogs = false;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (onlyAboveDialogs && !(_scope?._redirecting ?? false)) return false;
    return super.hitTest(result, position: position);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    var node = parent;
    while (node != null && node is! RenderWindowCaptionHitTestScope) {
      node = node.parent;
    }
    _scope = node as RenderWindowCaptionHitTestScope?;
    _scope?._add(this);
  }

  @override
  void detach() {
    _scope?._remove(this);
    _scope = null;
    super.detach();
  }
}
