import 'package:flutter/material.dart';

/// כותרת מקטע: titleMedium בצבע הערכה (primary), DD-14.
/// מוכרזת לקורא מסך ככותרת.
class AppSectionLabel extends StatelessWidget {
  final String text;
  final TextAlign? textAlign;

  const AppSectionLabel(this.text, {super.key, this.textAlign});

  /// הסגנון עצמו, לכותרת שנבנית בתוך רכיב אחר (למשל [SettingsCard]).
  static TextStyle? styleOf(BuildContext context) {
    final theme = Theme.of(context);
    return theme.textTheme.titleMedium?.copyWith(
      color: theme.colorScheme.primary,
    );
  }

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(text, style: styleOf(context), textAlign: textAlign),
  );
}
