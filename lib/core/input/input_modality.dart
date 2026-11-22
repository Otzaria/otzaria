// lib/core/input/input_modality.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// המצביע האחרון שהמשתמש השתמש בו: עכבר (או משטח מגע) לעומת אצבע או עט.
///
/// באנדרואיד ובאייפון/אייפד ברירת המחדל היא מגע, ועכבר שהופיע אחרון מחזיר
/// את הממשק למידות מחשב (כפתורים צפופים) עד שמגיע אירוע מגע או עט. ב-Windows,
/// Linux ו-macOS אין שינוי: הממשק נשאר "מחשב" גם עם מסך מגע.
///
/// המעקב הוא [InputModalityScope] אחד מעל האפליקציה. מחוצה לו, ובבדיקות,
/// אין מצביע אחרון והמערכת נשארת בברירת המחדל לפי הפלטפורמה.
abstract final class InputModality {
  /// עכבר ומשטח מגע: מצביע עם ריחוף. אצבע, עט ושאר ההתקנים: בלי ריחוף.
  static bool isMouseKind(PointerDeviceKind kind) =>
      kind == PointerDeviceKind.mouse || kind == PointerDeviceKind.trackpad;

  /// `true` כשהמצביע האחרון עכבר, `false` כשהוא אצבע או עט, `null` כשעוד לא
  /// הגיע אירוע, או שאין [InputModalityScope] מעל [context]. קורא מהקשר
  /// ונבנה מחדש רק כשהערך מתהפך.
  static bool? lastPointerIsMouseOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_InputModalityInherited>()
      ?.notifier
      ?.value;
}

/// מקשיב לכל אירועי המצביע של החלון ומפרסם את סוג המצביע האחרון ל-
/// [InputModality.lastPointerIsMouseOf]. אם כבר יש [InputModalityScope] מעליו,
/// הוא עובר דרך (בלי מעקב שני).
///
/// [adaptTheme]: באנדרואיד/iOS, כשהמצביע האחרון עכבר, מחליף את שטח המגע
/// ואת צפיפות הערכה לאלה של מחשב. זו נקודת ההחלטה היחידה: כל רכיב שקורא
/// `materialTapTargetSize` מהערכה ([BarButton.isTouch], שדה החיפוש, מתגים)
/// מתעדכן בלי שינוי בו. רק האפליקציה מפעילה אותו.
class InputModalityScope extends StatefulWidget {
  const InputModalityScope({
    super.key,
    this.adaptTheme = false,
    required this.child,
  });

  final bool adaptTheme;
  final Widget child;

  @override
  State<InputModalityScope> createState() => _InputModalityScopeState();
}

class _InputModalityScopeState extends State<InputModalityScope> {
  // null: אין עדיין אירוע. הערך משתנה רק כשהסוג מתהפך, לא בכל תזוזה.
  final ValueNotifier<bool?> _lastIsMouse = ValueNotifier<bool?>(null);
  bool _tracking = false;

  void _onPointer(PointerEvent event) {
    if (event is! PointerDownEvent &&
        event is! PointerHoverEvent &&
        event is! PointerScrollEvent &&
        event is! PointerPanZoomStartEvent) {
      return;
    }
    _lastIsMouse.value = InputModality.isMouseKind(event.kind);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nested =
        context.getInheritedWidgetOfExactType<_InputModalityInherited>() !=
        null;
    if (nested == _tracking) {
      if (nested) {
        _tracking = false;
      } else {
        GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
        _tracking = true;
      }
    }
  }

  @override
  void dispose() {
    if (_tracking) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    }
    _lastIsMouse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nested =
        context.getInheritedWidgetOfExactType<_InputModalityInherited>() !=
        null;
    if (nested) return widget.child;
    Widget child = widget.child;
    if (widget.adaptTheme) child = _DesktopThemeWhenMouse(child: child);
    return _InputModalityInherited(notifier: _lastIsMouse, child: child);
  }
}

class _InputModalityInherited extends InheritedNotifier<ValueNotifier<bool?>> {
  const _InputModalityInherited({
    required ValueNotifier<bool?> super.notifier,
    required super.child,
  });
}

/// אנדרואיד/iOS עם עכבר אחרון: שטח מגע וצפיפות של ערכת מחשב.
class _DesktopThemeWhenMouse extends StatelessWidget {
  const _DesktopThemeWhenMouse({required this.child});

  final Widget child;

  static bool get _isMobile => switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => true,
    _ => false,
  };

  @override
  Widget build(BuildContext context) {
    final mouse = InputModality.lastPointerIsMouseOf(context) ?? false;
    if (!mouse || !_isMobile) return child;
    return Theme(
      data: Theme.of(context).copyWith(
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      child: child,
    );
  }
}
