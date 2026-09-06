import 'package:flutter/foundation.dart';
import 'package:otzaria/models/links.dart';

/// מפתח הזיהוי של קטע מפרש בודד ברשימת המפרשים.
///
/// מקור אמת יחיד: הרשימה ממפה לפיו את אינדקסי הגלילה, ולחיצה על עוגן-אות
/// מייצרת לפיו את היעד. שני צדדים שמרכיבים את המפתח בנפרד היו מפספסים זה את
/// זה בשקט — הגלילה הייתה נופלת חזרה לכותרת הקבוצה בלי שדבר ידווח.
///
/// `index2` הוא מה שמבדיל בין שני קטעים של אותו מפרש על אותה שורה; בלעדיו
/// שניהם היו נראים כאותו יעד.
String commentaryLinkKey(Link link) =>
    '${link.index1}_${link.path2}_${link.index2}';

/// בקשה לגלול את רשימת המפרשים אל מפרש מסוים, ואם אפשר אל הקטע המדויק שלו.
///
/// [linkKey] הוא היעד המבוקש; [title] הוא הנפילה-אחורה כשהקטע אינו ברשימה
/// (סוננו סוגים, הקבוצה עדיין לא נבנתה).
@immutable
class CommentaryScrollRequest {
  /// שם המפרש, כפי שהוא מופיע ככותרת קבוצה ברשימה.
  final String title;

  /// [commentaryLinkKey] של הקטע שהעוגן מקשר אליו.
  final String? linkKey;

  /// מזהה עולה. בלעדיו לחיצה חוזרת על אותו עוגן הייתה מייצרת ערך זהה,
  /// `ValueNotifier` לא היה מודיע, והגלילה השנייה לא הייתה קורית.
  final int requestId;

  /// שורת המקור שממנה נלחץ העוגן. הלחיצה גם בוחרת אותה
  /// (`UpdateSelectedIndex`), ולכן הרשימה רואה "מעבר קטע" ומאפסת את
  /// הגלילה — אלא אם היא יודעת שזה הקטע של הבקשה עצמה.
  final int? sourceLine;

  const CommentaryScrollRequest({
    required this.title,
    required this.requestId,
    this.linkKey,
    this.sourceLine,
  });

  @override
  bool operator ==(Object other) =>
      other is CommentaryScrollRequest &&
      other.title == title &&
      other.linkKey == linkKey &&
      other.requestId == requestId &&
      other.sourceLine == sourceLine;

  @override
  int get hashCode => Object.hash(title, linkKey, requestId, sourceLine);

  @override
  String toString() =>
      'CommentaryScrollRequest($title, $linkKey, שורה $sourceLine, #$requestId)';
}
