import 'package:flutter/widgets.dart';
import 'package:otzaria/settings/l10n/settings_text_scope.dart';

/// מחיל על כרום הממשק — שורת הכותרת עם הכרטיסיות, סרגל הניווט וחלונית הכלים —
/// את כיוון הכתיבה של שפת הממשק, כך שבשפה LTR הם עוברים לצד שמאל.
class ChromeDirectionality extends StatelessWidget {
  const ChromeDirectionality({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: SettingsTextScope.languageOf(context).textDirection,
    child: child,
  );
}

/// מחזיר תת-עץ ל-RTL בתוך כרום שהתהפך — הספרים והטקסט התורני נשארים עברית
/// ואינם תלויים בשפת הממשק.
class ContentDirectionality extends StatelessWidget {
  const ContentDirectionality({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: child,
  );
}
