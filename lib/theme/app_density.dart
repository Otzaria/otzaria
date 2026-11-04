import 'package:flutter/material.dart';
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

/// בחלון נמוך ([WindowClass.isShortOf], טלפון לרוחב) הכרום שמתחת עובר לצפיפות
/// הקומפקטית, גם כשההגדרה "רגיל": שם הגובה הוא האילוץ. הסרגלים יורדים מ־56
/// ל־44, ועמודת הניווט מ־74 ל־60 (q12 Q8). בצפיפות קומפקטית אין שינוי.
///
/// העץ זהה בשני המצבים (Theme תמיד), כדי שסיבוב הטלפון לא יבנה מחדש את
/// המסכים שמתחת.
class ShortWindowDensity extends StatelessWidget {
  const ShortWindowDensity({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact =
        WindowClass.isShortOf(context) && !AppDensity.of(context).isCompact;
    return Theme(
      data: compact
          ? theme.copyWith(
              extensions: [
                ...theme.extensions.values.where((e) => e is! AppDensity),
                AppDensity.compact,
              ],
            )
          : theme,
      child: child,
    );
  }
}
