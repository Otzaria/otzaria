import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/widgets.dart';

/// מרכוז אנכי של תווית ממשק בעברית בתוך פקד (כרגע: הערך בתפריט הנפתח).
///
/// ב-Windows גופן הממשק הוא Segoe UI. המרווח שלו מעל קו הבסיס גדול בהרבה
/// מהמרווח שמתחתיו, והאותיות העבריות (בלי עולים ויורדים, חוץ מ-ק ו-ל) תופסות
/// רק את החלק התחתון שלו. לכן התיבה ממורכזת, אבל האותיות יושבות כ-2 פיקסלים
/// נמוך מהאמצע בגודל 14 (נמדד בצילום: בורר "ככתבם | בכינוי" ותפריט "יקוק").
/// ההזזה היא בציור בלבד ולא משנה את הפריסה או את המדידה, והיא יחסית לגודל
/// הגופן אחרי הגדלת הטקסט. בשאר הפלטפורמות הגופן אחר, ולא נמדד — בלי הזזה.
class UiLabelNudge extends StatelessWidget {
  const UiLabelNudge({super.key, required this.child});

  final Widget child;

  /// ההזזה כלפי מעלה, כחלק מגודל הגופן (2 פיקסלים ב-14).
  static const double _fraction = 1 / 7;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) {
      return child;
    }
    final fontSize = DefaultTextStyle.of(context).style.fontSize ?? 14;
    final scaled = MediaQuery.textScalerOf(context).scale(fontSize);
    return Transform.translate(
      offset: Offset(0, -scaled * _fraction),
      child: child,
    );
  }
}
