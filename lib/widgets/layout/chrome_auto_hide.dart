import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:otzaria/theme/app_motion.dart';
import 'package:otzaria/theme/app_tokens.dart';

/// הסתרת הסרגלים בגלילה בטלפון: סרגל הקורא והסרגל התחתון.
///
/// גלילה למטה בקורא מסתירה אותם; גלילה למעלה, הגעה לראש הטקסט או הקשה
/// מציגות אותם. [ChromeAutoHideScope] יושב בחלון הראשי, הקורא מדווח דרך
/// [ChromeAutoHideScrollListener], וכל סרגל עטוף ב-[ChromeAutoHide].
class ChromeAutoHideController extends ValueNotifier<bool> {
  ChromeAutoHideController() : super(true);

  bool get visible => value;

  void show() => value = true;

  void hide() => value = false;
}

/// מספק את [ChromeAutoHideController]. [enabled] false (מחשב, טאבלט, קורא
/// מסך) — הסרגלים תמיד גלויים והגלילה לא מדווחת.
class ChromeAutoHideScope extends InheritedNotifier<ChromeAutoHideController> {
  const ChromeAutoHideScope({
    super.key,
    required ChromeAutoHideController controller,
    required this.enabled,
    required super.child,
  }) : super(notifier: controller);

  final bool enabled;

  /// הבקר, רק כשההסתרה פעילה.
  static ChromeAutoHideController? controllerOf(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<ChromeAutoHideScope>();
    return scope != null && scope.enabled ? scope.notifier : null;
  }

  /// האם הסרגלים גלויים. בונה מחדש את הקורא כשהמצב משתנה.
  static bool visibleOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ChromeAutoHideScope>();
    return scope == null || !scope.enabled || scope.notifier!.visible;
  }

  @override
  bool updateShouldNotify(ChromeAutoHideScope oldWidget) =>
      super.updateShouldNotify(oldWidget) || enabled != oldWidget.enabled;
}

/// סרגל שנעלם כש-[ChromeAutoHideScope] מוסתר: מתכווץ לגובה 0 ונגלל אל מחוץ
/// לקצה שלו. [keepBottomInset] — לסרגל התחתון: השוליים של המערכת (פס
/// המחוות) נשארים גם כשהסרגל מוסתר, כדי שהטקסט לא ייכנס מתחתיו.
class ChromeAutoHide extends StatelessWidget {
  const ChromeAutoHide({
    super.key,
    required this.child,
    this.keepBottomInset = false,
  });

  final Widget child;
  final bool keepBottomInset;

  @override
  Widget build(BuildContext context) {
    final visible = ChromeAutoHideScope.visibleOf(context);
    final inset = keepBottomInset ? MediaQuery.paddingOf(context).bottom : 0.0;
    final bar = ClipRect(
      child: AnimatedAlign(
        alignment: Alignment.bottomCenter,
        heightFactor: visible ? 1 : 0,
        duration: AppMotion.duration(context, AppTokens.animNormal),
        curve: Curves.easeInOut,
        child: IgnorePointer(
          ignoring: !visible,
          child: ExcludeFocus(
            excluding: !visible,
            child: keepBottomInset
                ? MediaQuery.removePadding(
                    context: context,
                    removeBottom: true,
                    child: child,
                  )
                : child,
          ),
        ),
      ),
    );
    if (!keepBottomInset) return bar;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        bar,
        SizedBox(height: inset),
      ],
    );
  }
}

/// מדווח ל-[ChromeAutoHideScope] על גלילה אנכית בתוכן ועל הקשה בו. לא בולע
/// אירועים: הגלילה וההקשה ממשיכות לתוכן.
class ChromeAutoHideScrollListener extends StatefulWidget {
  const ChromeAutoHideScrollListener({super.key, required this.child});

  final Widget child;

  @override
  State<ChromeAutoHideScrollListener> createState() =>
      _ChromeAutoHideScrollListenerState();
}

class _ChromeAutoHideScrollListenerState
    extends State<ChromeAutoHideScrollListener> {
  Offset? _down;

  bool _onScroll(ScrollNotification notification) {
    final controller = ChromeAutoHideScope.controllerOf(context);
    if (controller == null || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification is UserScrollNotification) {
      switch (notification.direction) {
        case ScrollDirection.reverse:
          controller.hide();
        case ScrollDirection.forward:
          controller.show();
        case ScrollDirection.idle:
          break;
      }
    } else if (notification is ScrollUpdateNotification &&
        notification.metrics.pixels <= notification.metrics.minScrollExtent) {
      controller.show();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // ChromeAutoHideScope.controllerOf אינו רושם תלות, ולכן נבנה מחדש עם
    // ההורה; ההאזנה עצמה זולה גם כשההסתרה כבויה.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) => _down = event.position,
      onPointerUp: (event) {
        final down = _down;
        _down = null;
        if (down == null || (event.position - down).distance > kTouchSlop) {
          return;
        }
        ChromeAutoHideScope.controllerOf(context)?.show();
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: widget.child,
      ),
    );
  }
}
