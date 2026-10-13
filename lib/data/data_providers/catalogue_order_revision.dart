import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// גרסת הסדר הקטלוגי שנצרב לאינדקס. הסדר מקודד ל-documentId בזמן
/// האינדוקס, ולכן שינוי בלוגיקה של `SearchCatalogueOrderHelper` מחייב
/// העלאת המספר — בלעדיה אינדקס קיים ימשיך להחזיר את הסדר הישן.
///
/// העלאת המספר מחייבת גם בניית האינדקס המוכן-מראש שמצורף לגרסה
/// (`release_index_builder_cli.dart`) — אחרת הוא יימחק ויבנה מחדש
/// אצל כל מי שיתקין אותו.
const int kCatalogueOrderRevision = 2;

/// קורא וכותב את גרסת הסדר הקטלוגי בתיקיית האינדקס, ומכריע אם אינדקס
/// קיים נבנה בגרסה ישנה ולכן חייב בנייה מחדש.
class CatalogueOrderRevision {
  CatalogueOrderRevision._();

  static const String fileName = 'otzaria_catalogue_order.json';

  static File fileFor(String indexPath) => File(p.join(indexPath, fileName));

  /// הגרסה השמורה, או null כשאין קובץ או שתוכנו אינו קריא.
  ///
  /// שני המצבים מתמזגים בכוונה: כשל קריאה מוביל לבנייה מחדש אחת שכותבת
  /// חותם תקין, בעוד ההנחה ההפוכה ("כנראה עדכני") הייתה משאירה סדר שגוי
  /// לצמיתות. הכתיבה ב-[write] אטומית כדי שקובץ חצוי לא ייווצר מלכתחילה.
  static int? read(String indexPath) =>
      _readStamp(indexPath)?['catalogueOrderRevision'] as int?;

  /// האם האינדקס נחתם אחרי שספרים אישיים (`uid:`) קיבלו טווח סדר משלהם.
  /// באינדקס ישן הם בסדר שבתוך הרצף, ורשומותיהם נמחקות פעם אחת לאינדוקס מחדש.
  static bool hasPersonalOrderRange(String indexPath) =>
      _readStamp(indexPath)?['personalOrderRange'] == true;

  static Map<String, dynamic>? _readStamp(String indexPath) {
    try {
      final file = fileFor(indexPath);
      if (!file.existsSync()) return null;
      final decoded = jsonDecode(file.readAsStringSync());
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (e) {
      debugPrint('⚠️ קריאת גרסת הסדר הקטלוגי נכשלה: $e');
      return null;
    }
  }

  /// כותב את הגרסה הנוכחית ומחזיר האם הצליח. הכתיבה עוברת דרך קובץ זמני
  /// ו-rename, כדי שהפסקה באמצע תשאיר את החותם הקודם ולא קובץ חצוי.
  static bool write(
    String indexPath, {
    int revision = kCatalogueOrderRevision,
    bool personalOrderRange = true,
  }) {
    try {
      final directory = Directory(indexPath);
      if (!directory.existsSync()) {
        directory.createSync(recursive: true);
      }
      final target = fileFor(indexPath);
      final temp = File('${target.path}.tmp');
      temp.writeAsStringSync(
        jsonEncode({
          'catalogueOrderRevision': revision,
          'personalOrderRange': personalOrderRange,
        }),
        flush: true,
      );
      temp.renameSync(target.path);
      return true;
    } catch (e) {
      debugPrint('⚠️ כתיבת גרסת הסדר הקטלוגי נכשלה: $e');
      return false;
    }
  }

  /// האם מותר לחתום את הגרסה הנוכחית על האינדקס שבדיסק. חותמים רק על
  /// אינדקס ריק שמצבו ידוע — חתימה על אינדקס מלא הייתה מכריזה סדר ישן
  /// כתקין, ומצב לא ידוע (כשל קריאה או אינדקס זמני) אינו מעיד על ריקנות.
  static bool shouldStamp({
    required bool indexStateIsKnown,
    required bool hasIndexedBooks,
  }) => indexStateIsKnown && !hasIndexedBooks;

  /// האם האינדקס הקיים נבנה בגרסת סדר ישנה. אינדקס בלי מסמכים חיים אינו
  /// מיושן — אין בו סדר שגוי לתקן, וזה גם מצב ההתקנה הנקייה. מצב לא ידוע
  /// אינו מכריז מיושן, כדי לא למחוק אינדקס תקין על סמך קריאה שנכשלה.
  static bool isStale({
    required int? storedRevision,
    required bool hasIndexedBooks,
    bool indexStateIsKnown = true,
    int currentRevision = kCatalogueOrderRevision,
  }) {
    if (!indexStateIsKnown) return false;
    if (!hasIndexedBooks) return false;
    return storedRevision != currentRevision;
  }
}
