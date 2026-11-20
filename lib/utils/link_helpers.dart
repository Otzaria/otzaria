import 'package:flutter/services.dart';
import 'package:otzaria/core/messages/common_messages.dart';
import 'package:otzaria/core/ui_snack.dart';

export 'package:otzaria/utils/book_link_builder.dart';

/// העתקת קישור ללוח והצגת הודעה. משתמש ב‑[Clipboard.setData] של Flutter במקום
/// ב‑super_clipboard כי הקישור הוא טקסט בלבד וכך נמנעים מבעיית
/// `SystemClipboard.instance == null` שעלולה לגרום להודעת "הועתק" שקרית.
Future<void> copyLinkToClipboard(
  String url, {
  String? sectionMarkAlternative,
}) async {
  await Clipboard.setData(ClipboardData(text: url));
  // גרסאות של Word מתקשות בכתובות ארוכות. האורך קובע אם להציע חלופה בלבד.
  if (sectionMarkAlternative != null && url.length > 255) {
    UiSnack.showWithAction(
      message: CommonMessages.longTextMarkLinkCopied,
      actionLabel: CommonMessages.copyShortSectionMarkLink,
      onAction: () => copyLinkToClipboard(sectionMarkAlternative),
    );
  } else {
    UiSnack.show(CommonMessages.linkCopied);
  }
}
