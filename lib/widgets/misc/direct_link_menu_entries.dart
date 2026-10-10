import 'package:flutter/widgets.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/utils/link_helpers.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

/// האייקון של כל סוג קישור. שלושתם מבית ה-link של אוצריא, כדי שהתת-תפריט
/// ייקרא כמשפחה אחת: מסמך = המקטע עצמו, מרקר = המקטע מודגש, אל"ף = הטקסט
/// המסומן מודגש.
IconData _iconFor(DirectLinkKind kind) => switch (kind) {
  DirectLinkKind.section => OtzariaIcons.link_document_24_regular,
  DirectLinkKind.sectionMark => OtzariaIcons.link_marker_24_regular,
  DirectLinkKind.textMark => OtzariaIcons.link_alef_24_regular,
};

/// בניית פעולות "העתק קישור ישיר" לשורת אייקונים (תת-תפריט פשוט).
///
/// מאחד מימוש משוכפל שהיה ב-combined_book_screen.dart וב-simple_text_viewer.dart.
/// משתמש ב-[buildDirectLinkSubmenuEntries] (לוגיקה טהורה) ועוטף ב-
/// [AppContextMenuSubAction] עם האייקון של סוג הקישור וקריאה ל-
/// [copyLinkToClipboard].
List<AppContextMenuSubAction> buildDirectLinkSubmenuActions({
  required int bookId,
  BookSource source = BookSource.official,
  required int index,
  required String? selectedText,
}) {
  final entries = buildDirectLinkSubmenuEntries(
    bookId: bookId,
    source: source,
    index: index,
    selectedText: selectedText,
  );
  return entries
      .map(
        (e) => AppContextMenuSubAction(
          label: e.label,
          icon: _iconFor(e.kind),
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
  BookSource source = BookSource.official,
  required int index,
  required String? selectedText,
}) =>
    buildDirectLinkSubmenuActions(
          bookId: bookId,
          source: source,
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

/// The "העתק קישור ישיר" entry, with the links of
/// [buildDirectLinkContextMenuEntries] as its submenu.
AppContextMenuEntry buildCopyDirectLinkEntry({
  required int bookId,
  BookSource source = BookSource.official,
  required int index,
  required String? selectedText,
}) => AppContextMenuEntry(
  label: 'העתק קישור ישיר',
  icon: OtzariaIcons.link_24_regular,
  childrenBuilder: () => buildDirectLinkContextMenuEntries(
    bookId: bookId,
    source: source,
    index: index,
    selectedText: selectedText,
  ),
);
