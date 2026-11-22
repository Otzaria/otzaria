import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:otzaria/book_protection/models/book_protection.dart';
import 'package:otzaria/book_protection/utils/copy_guard.dart';
import 'package:otzaria/core/messages/common_messages.dart';
import 'package:otzaria/core/share/text_share_service.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/divine_names/models/divine_name_forms.dart';

/// משתף טקסט נבחר דרך גיליון השיתוף של המערכת. שיתוף הוא העתקה אל אפליקציה
/// אחרת, ולכן עובר דרך אותה מגבלת העתקה של המו"ל ([protection]) ומסיר את אותם
/// מחברי השמות הקדושים כמו העתקה. טקסט ריק לא משותף.
///
/// [segmentCount] הוא מספר שורות המקור שנבחרו, כמו שההעתקה בקורא סופרת
/// (`selectionSegmentCount`). בלעדיו הספירה לפי שורות הטקסט, וזה לא מספיק
/// בקריאה רציפה: שורות מקור באותה פסקה ממוזגת מופרדות ברווח ולא ב-`\n`.
///
/// כשל בגיליון (אין Activity, טקסט גדול מדי להעברה) לא נזרק: מוצגת הודעה.
Future<void> shareSelectedText(
  String text, {
  BookProtection protection = BookProtection.none,
  Rect? origin,
  int? segmentCount,
}) async {
  if (text.trim().isEmpty) return;
  if (!ensureCopyAllowed(protection, segmentCount ?? countTextSegments(text))) {
    return;
  }
  try {
    await TextShareService.instance.shareText(
      withoutDivineNameJoiners(text),
      origin: origin,
    );
  } catch (e) {
    debugPrint('Share failed: $e');
    UiSnack.showError(CommonMessages.shareFailed);
  }
}
