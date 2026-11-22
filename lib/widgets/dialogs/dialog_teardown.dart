import 'dart:async';

import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_surfaces.dart';

/// הדרך היחידה לפתוח חלון קופץ באפליקציה (UIL-028). כמו [showDialog], אבל
/// משלים `null` גם כשה-Navigator פורק לפני בניית הדיאלוג.
///
/// בכוונה בלי `themes: InheritedTheme.capture(...)` של [showDialog]: הלכידה
/// מקפיאה את ה-`Theme` של לשונית הקריאה כפי שהיה בפתיחה, ודיאלוג שנשאר פתוח
/// בזמן החלפת ערכה (מערכת בשקיעה, חלון אחר) היה נשאר בערכה הישנה. בלעדיה הוא
/// יושב מתחת ל-`Theme` של האפליקציה, שמתעדכן בזמן אמת. הכיוון עובר במפורש
/// (`_withOpenerDirection`), ולכן אין תלות בשאר העטיפות שבדרך.
///
/// כל הפתיחות עוברות כאן, גם מההגדרות, שאין בהן עטיפת `Theme` מקומית ולכן
/// [showDialog] שם לא היה מתקלקל: מקום אחד לתיקון, ופתיחה גולמית שתתווסף
/// בלשונית קריאה לא תחזיר את הבעיה.
///
/// [barrierColor] — ההחשכה מאחורי הדיאלוג; null הוא ההחשכה של הערכה, שנקבעת
/// פעם אחת בפתיחה (ההפרש בין הערכות הוא ערך `scrim` אחד, ונראה רק בחלון של
/// שניות). `Colors.transparent` — בלי החשכה.
Future<T?> showDialogUntilTornDown<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<T>(
    context: context,
    builder: builder,
    barrierDismissible: barrierDismissible,
    barrierColor:
        barrierColor ??
        DialogTheme.of(context).barrierColor ??
        Theme.of(context).dialogTheme.barrierColor ??
        AppSurfaces.scrim(Theme.of(context).colorScheme),
    traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
  );
  return Future.any([navigator.push<T>(route), route.completed]);
}
