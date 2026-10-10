import 'package:flutter/foundation.dart' show listEquals;
import 'package:otzaria/text_book/bloc/text_book_state.dart';

/// מסנן עדכוני גלילה ומטא-בחירה שאינם משנים את עץ הקורא. מחזיר `true`
/// כשצריך לבנות מחדש.
///
/// התנאי לשימוש: אף חלק בתת-העץ אינו נגזר מ-`visibleIndices` או משדות
/// הבחירה. מי שצריך את מיקום הגלילה קורא אותו חי מ-`positionsListener` דרך
/// `resolveTopmostSourceLine`.
///
/// חייב לעטוף גם כל פאנל מפרשים שמאזין ל-bloc בעצמו — `buildWhen` בהורה אינו
/// מגן עליו, ובלעדיו כל תזוזת סימון בונה את כל המפרשים מחדש (issue #976).
///
/// ההשוואה עוברת דרך `copyWith`, ולכן שדה שיתווסף ל-props ולא ל-`copyWith`
/// יישבר כאן בשקט — ראו את בדיקת הסחיפה
/// ב-`test/text_book/view/visible_indices_rebuild_gate_test.dart`.
bool shouldRebuildReader(TextBookState previous, TextBookState current) {
  if (previous is! TextBookLoaded || current is! TextBookLoaded) return true;
  if (!listEquals(previous.content, current.content)) return true;
  return previous.copyWith(
        visibleIndices: current.visibleIndices,
        // נגזר מהגלילה לחלונית הקישורים, שנבנית בעצמה; הקורא נגזר מ-linksByLine.
        visibleLinks: identical(previous.linksByLine, current.linksByLine)
            ? current.visibleLinks
            : null,
        clearSelectedText: true,
      ) !=
      current.copyWith(clearSelectedText: true);
}
