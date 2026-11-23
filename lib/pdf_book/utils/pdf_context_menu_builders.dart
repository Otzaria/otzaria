import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart' show VoidCallback, setEquals;
import 'package:otzaria/models/links.dart' as otz_links;
import 'package:otzaria/text_book/utils/reader_menu_entries.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/misc/link_context_menu_entry.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

/// בונה את תת־תפריט הקישורים בטעינה עצלה, כדי שפתיחת התפריט הראשי
/// לא תמתין לפתרון ההפניות של הקישורים.
AppContextMenuEntry buildPdfLinksContextMenuEntry({
  required List<otz_links.Link> relevantLinks,
  required bool showOpenLinksPaneEntry,
  required VoidCallback onOpenLinksPane,
  required void Function(otz_links.Link link) onOpenLink,
}) {
  List<AppContextMenuEntry> buildLinkChildren() {
    return <AppContextMenuEntry>[
      if (showOpenLinksPaneEntry) ...[
        AppContextMenuEntry(
          label: 'פתח קישורים בחלונית צד',
          onTap: onOpenLinksPane,
        ),
        const AppContextMenuEntry.divider(),
      ],
      ...relevantLinks.map(
        (link) => buildLinkContextMenuEntry(
          link: link,
          onTap: () => onOpenLink(link),
        ),
      ),
    ];
  }

  return AppContextMenuEntry(
    label: 'קישורים',
    icon: OtzariaIcons.links_24_regular,
    enabled: relevantLinks.isNotEmpty,
    childrenBuilder: buildLinkChildren,
  );
}

/// מעדכן ושומר בחירה שהשתנתה, ופותח את חלונית המפרשים בכל לחיצה.
void applyPdfCommentatorSelection({
  required Set<String> activeCommentators,
  required Set<String> updated,
  required VoidCallback onChanged,
  required VoidCallback onOpenPane,
}) {
  if (!setEquals(activeCommentators, updated)) {
    activeCommentators
      ..clear()
      ..addAll(updated);
    onChanged();
  }
  onOpenPane();
}

/// מחליף את תפריט ההקשר של pdfrx, כולל פעולות ברירת המחדל שלו כמו העתקה.
List<AppContextMenuEntry> buildPdfContextMenuEntries({
  required List<AppContextMenuEntry> commentatorChildren,
  required bool hasRelevantCommentators,
  required bool canSelectCommentators,
  required AppContextMenuEntry linksEntry,
  required bool hasTextSelection,
  required ReaderMenuSelection? selection,
  required bool canCopySelection,
  required VoidCallback onSearchInBook,
  required VoidCallback onSearchAllBooks,
  required VoidCallback onCopySelection,
  required VoidCallback onAddBookmark,
  required VoidCallback onAddNote,
}) {
  return [
    // שורת אייקונים עליונה בסגנון Windows 11, כמו בתצוגת הטקסט.
    AppContextMenuEntry.iconRow([
      buildSearchAllBooksIconAction(
        selection: selection ?? ReaderMenuSelection(null),
        enabled: hasTextSelection && (selection?.hasText ?? true),
        onTap: onSearchAllBooks,
      ),
      AppContextMenuIconAction(
        label: 'העתקה',
        icon: FluentIcons.copy_24_regular,
        enabled: canCopySelection,
        onTap: onCopySelection,
      ),
      AppContextMenuIconAction(
        label: 'הערה',
        tooltip: 'הוסף הערה אישית',
        icon: FluentIcons.note_add_24_regular,
        onTap: onAddNote,
      ),
    ]),
    const AppContextMenuEntry.divider(),
    AppContextMenuEntry(
      label: 'חיפוש בספר',
      icon: FluentIcons.search_24_regular,
      onTap: onSearchInBook,
    ),
    AppContextMenuEntry(
      label: 'מפרשים',
      icon: OtzariaIcons.book_24_regular,
      // התת-תפריט פעיל אם יש בדף מפרשים זמינים, או אם ניתן לפתוח את
      // חלונית בחירת המפרשים (כדי לאפשר בחירה התחלתית גם בדף ללא מפרשים).
      enabled: hasRelevantCommentators || canSelectCommentators,
      children: commentatorChildren,
    ),
    linksEntry,
    const AppContextMenuEntry.divider(),
    AppContextMenuEntry(
      label: 'הוסף סימניה לעמוד זה',
      icon: FluentIcons.bookmark_add_24_regular,
      onTap: onAddBookmark,
    ),
  ];
}
