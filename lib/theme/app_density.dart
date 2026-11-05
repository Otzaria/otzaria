import 'package:flutter/material.dart';
import 'package:otzaria/core/windowing/device_chrome.dart';
import 'package:otzaria/theme/app_input_tokens.dart';
import 'package:otzaria/theme/layout_tokens.dart';

/// צפיפות הממשק (ההגדרה "צפיפות ממשק"), כחלק מערכת הנושא.
///
/// נבנה ב-[AppThemeData] מתוך ההגדרה, ולכן כל רכיב שקורא [AppDensity.of]
/// נבנה מחדש מיד כשהיא משתנה.
@immutable
class AppDensity extends ThemeExtension<AppDensity> {
  const AppDensity({required this.isCompact});

  static const regular = AppDensity(isCompact: false);
  static const compact = AppDensity(isCompact: true);

  /// הצפיפות של ה-Theme הקרוב; Theme שלא נבנה ב-[AppThemeData] הוא רגיל.
  static AppDensity of(BuildContext context) =>
      Theme.of(context).extension<AppDensity>() ?? regular;

  final bool isCompact;

  /// חלון קטן לצפיפות ברירת המחדל. שם "צפיפות ממשק" שלא נבחרה מצומצמת
  /// (`SettingsState.compactMenuModeFor`), ובחירה מפורשת, גם "רגיל", נשמרת.
  /// - בטלפון ובטאבלט ([DeviceChrome.isMobile]): הצד הקצר מתחת ל-600
  ///   ([LayoutBreakpoints.compact]) — טלפון לאורך ולרוחב, או חצי מסך של 10".
  /// - במחשב: רק חלון נמוך ([WindowClass.isShortOf], מתחת ל-480). מחשב נייד
  ///   1366×768 בהגדלה של 125% מוגדל לכל המסך הוא כ-1093×566, ולפי הצד הקצר
  ///   כל האפליקציה הייתה מתהפכת למצומצמת, ובחזרה כשהחלון יוצא ממצב מוגדל.
  static bool isSmallWindow(Size size) => DeviceChrome.isMobile
      ? size.shortestSide < LayoutBreakpoints.compact
      : size.height < LayoutBreakpoints.compactHeight;

  /// גובה השורה הראשית של הסרגל העליון.
  double get topBarHeight => isCompact ? 44 : 56;

  /// גובה שדה קלט.
  double get fieldHeight => AppInputTokens.height(isCompact);

  @override
  AppDensity copyWith({bool? isCompact}) =>
      AppDensity(isCompact: isCompact ?? this.isCompact);

  @override
  AppDensity lerp(AppDensity? other, double t) =>
      other != null && t >= 0.5 ? other : this;

  @override
  bool operator ==(Object other) =>
      other is AppDensity && other.isCompact == isCompact;

  @override
  int get hashCode => isCompact.hashCode;
}

/// בונה את [builder] לפי [AppDensity.isSmallWindow] של החלון, ובונה מחדש רק
/// כשהתשובה מתהפכת, לא בכל שינוי גודל: ב-App נבנית בו ערכת הנושא, ובנייה
/// שלה בכל פריים של גרירת גודל החלון הייתה בונה מחדש את כל האפליקציה.
///
/// [builder] מקבל רק את התשובה, ולא context: תלות אחרת שהייתה נקראת דרכו
/// לא הייתה מרעננת את התוצאה השמורה.
class SmallWindowBuilder extends StatefulWidget {
  const SmallWindowBuilder({super.key, required this.builder});

  final Widget Function(bool isSmallWindow) builder;

  @override
  State<SmallWindowBuilder> createState() => _SmallWindowBuilderState();
}

class _SmallWindowBuilderState extends State<SmallWindowBuilder> {
  bool? _isSmall;
  Widget? _built;

  @override
  void didUpdateWidget(SmallWindowBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    _built = null;
  }

  @override
  Widget build(BuildContext context) {
    final isSmall = AppDensity.isSmallWindow(MediaQuery.sizeOf(context));
    if (_built == null || isSmall != _isSmall) {
      _isSmall = isSmall;
      _built = widget.builder(isSmall);
    }
    return _built!;
  }
}

/// קורא ל-[onChanged] כשה-[AppDensity] של ה-Theme משתנה, פעם אחת לכל שינוי,
/// אחרי הפריים: כשהחלון עובר את הסף של [AppDensity.isSmallWindow] והצפיפות
/// שבפועל מתהפכת בלי שההגדרה השתנתה. בבנייה הראשונה אין קריאה.
///
/// ה-Theme משתנה רק כשערכת הנושא נבנית מחדש ([SmallWindowBuilder]), ולא בכל
/// פריים של שינוי גודל; גם במעבר המונפש בין ערכות הנושא הצפיפות מתהפכת פעם
/// אחת ([AppDensity.lerp]).
class AppDensityListener extends StatefulWidget {
  const AppDensityListener({
    super.key,
    required this.onChanged,
    required this.child,
  });

  final ValueChanged<AppDensity> onChanged;
  final Widget child;

  @override
  State<AppDensityListener> createState() => _AppDensityListenerState();
}

class _AppDensityListenerState extends State<AppDensityListener> {
  AppDensity? _density;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final density = AppDensity.of(context);
    final previous = _density;
    _density = density;
    if (previous == null || previous == density) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _density == density) widget.onChanged(density);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
