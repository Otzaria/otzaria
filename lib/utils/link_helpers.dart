import 'package:flutter/services.dart';
import 'package:otzaria/core/ui_snack.dart';

/// בניית קישור ישיר לספר לפי מזהה
String buildBookLink(int bookId) => 'otzaria://open/book/$bookId';

/// בניית קישור ישיר למקטע/עמוד ספציפי בספר
/// ערכי index שליליים מוחלפים ב-0
String buildSectionLink(int bookId, int index) =>
    'otzaria://open/book/$bookId?index=${index < 0 ? 0 : index}';

/// העתקת קישור ללוח והצגת הודעה
Future<void> copyLinkToClipboard(String url) async {
  await Clipboard.setData(ClipboardData(text: url));
  UiSnack.show('הקישור הועתק ללוח');
}
