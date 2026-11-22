import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';

/// מקום שמור לפסקה רציפה שחלק משורותיה טרם נטען. הגובה משוער כשורת תצוגה
/// לכל שורת מקור, כדי שהגלילה לא תדלג עליה עד שתיטען.
class UnloadedParagraphPlaceholder extends StatelessWidget {
  const UnloadedParagraphPlaceholder({
    super.key,
    required this.lineCount,
    required this.fontSize,
    this.lineHeight,
  });

  final int lineCount;
  final double fontSize;

  /// מרווח השורות של הספר (#2306); null = ההגדרה הכללית.
  final double? lineHeight;

  @override
  Widget build(BuildContext context) {
    final effectiveLineHeight = context.select(
      (SettingsBloc bloc) => bloc.state.lineHeightForBook(lineHeight),
    );
    return SizedBox(height: lineCount * fontSize * effectiveLineHeight);
  }
}
