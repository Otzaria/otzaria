import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/utils/link_helpers.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';

/// בניית פעולות "העתק קישור ישיר" לשורת אייקונים (תת-תפריט פשוט).
///
/// מאחד מימוש משוכפל שהיה ב-combined_book_screen.dart וב-simple_text_viewer.dart.
/// משתמש ב-[buildDirectLinkSubmenuEntries] (לוגיקה טהורה) ועוטף ב-
/// [AppContextMenuSubAction] עם אייקון אחיד וקריאה ל-[copyLinkToClipboard].
List<AppContextMenuSubAction> buildDirectLinkSubmenuActions({
  required int bookId,
  required int index,
  required String? selectedText,
}) {
  final entries = buildDirectLinkSubmenuEntries(
    bookId: bookId,
    index: index,
    selectedText: selectedText,
  );
  return entries
      .map(
        (e) => AppContextMenuSubAction(
          label: e.label,
          icon: FluentIcons.link_24_regular,
          enabled: e.link != null,
          onTap: e.link != null ? () => copyLinkToClipboard(e.link!) : null,
        ),
      )
      .toList();
}

/// גרסת [AppContextMenuEntry] של [buildDirectLinkSubmenuActions], לשימוש
/// ב-childrenBuilder של תפריט הקשר מלא.
List<AppContextMenuEntry> buildDirectLinkContextMenuEntries({
  required int bookId,
  required int index,
  required String? selectedText,
}) =>
    buildDirectLinkSubmenuActions(
          bookId: bookId,
          index: index,
          selectedText: selectedText,
        )
        .map(
          (a) => AppContextMenuEntry(
            label: a.label,
            icon: a.icon,
            enabled: a.enabled,
            onTap: a.onTap,
          ),
        )
        .toList();
