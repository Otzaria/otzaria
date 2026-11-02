import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_input_tokens.dart';

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
