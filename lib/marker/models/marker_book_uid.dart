import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/models/plugin_book_identity.dart';

/// המזהה היציב של ספר בסימונים. מהדורה חלופית חולקת את ה-id עם הנוסח
/// הראשי, ולכן שם המהדורה הוא חלק מהמזהה — כמו בסימניות.
String markerBookUid(String uid, String? versionTitle) =>
    versionTitle == null ? uid : '$uid|version:$versionTitle';

/// סימון שייך לספר אחר באותה כותרת רק כששני המזהים יציבים ושונים: מזהה שנגזר
/// מנתיב הקובץ משתנה כשהספרייה עוברת מקום, ואז הכותרת היא שמכריעה.
bool markerOtherBook(String? markUid, String? bookUid) =>
    markUid != null &&
    bookUid != null &&
    markUid != bookUid &&
    _stableUid(markUid) &&
    _stableUid(bookUid);

bool _stableUid(String uid) =>
    const ['id:', 'uid:', 'ext:', 'db:'].any(uid.startsWith);

String markerBookUidOf(Book book) => markerBookUid(
  PluginBookIdentity.uidOf(book),
  book is TextBook ? book.versionTitle : null,
);
