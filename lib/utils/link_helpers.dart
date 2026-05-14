import 'package:flutter/services.dart';
import 'package:otzaria/core/ui_snack.dart';

export 'package:otzaria/utils/book_link_builder.dart';

/// העתקת קישור ללוח והצגת הודעה
Future<void> copyLinkToClipboard(String url) async {
  await Clipboard.setData(ClipboardData(text: url));
  UiSnack.show('הקישור הועתק ללוח');
}
