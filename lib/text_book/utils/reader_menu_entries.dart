import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/widgets.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/tools/dictionary/dictionary_context_menu_entries.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';
import 'package:otzaria/utils/text/word_at_position.dart';
import 'package:otzaria/utils/text/global_search_helper.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/widgets/misc/app_popup_menu.dart';
import 'package:otzaria/widgets/misc/direct_link_menu_entries.dart';
import 'package:otzaria/widgets/misc/link_context_menu_entry.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

/// בחירת טקסט לחיפוש: ללא ניקוד וטעמים, ועם רווחים ומעברי שורה מכווצים.
class ReaderMenuSelection {
  ReaderMenuSelection(String? selectedText) : cleaned = _clean(selectedText);

  final String cleaned;

  bool get hasText => cleaned.isNotEmpty;

  /// [cleaned] cut to [maxChars] graphemes, for labels and tooltips.
  String quote(int maxChars) {
    final prefix = cleaned.characters.take(maxChars + 1);
    return prefix.length > maxChars ? '${prefix.take(maxChars)}...' : cleaned;
  }

  static String _clean(String? text) {
    var raw = text?.trim() ?? '';
    if (utils.hasNikud(raw)) raw = utils.removeVolwels(raw);
    return raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  }
}

/// The icon row at the top of a reader's main text context menu: search all
/// books, copy, add a note and, for a book in the library, copy a link.
AppContextMenuEntry buildReaderIconRow({
  required BuildContext context,
  required ReaderMenuSelection selection,
  required Book book,
  required int paragraphIndex,
  required String? selectedText,
  required VoidCallback onCopy,
  required VoidCallback onAddNote,
}) {
  final bookId = book.id;
  return AppContextMenuEntry.iconRow([
    buildSearchAllBooksIconAction(
      selection: selection,
      onTap: () =>
          openGlobalSearch(context, selection.cleaned, insertAdjacent: true),
    ),
    AppContextMenuIconAction(
      label: 'העתקה',
      icon: FluentIcons.copy_24_regular,
      enabled: selection.hasText,
      onTap: onCopy,
    ),
    AppContextMenuIconAction(
      label: 'הערה',
      icon: FluentIcons.note_add_24_regular,
      onTap: onAddNote,
    ),
    if (bookId != null)
      AppContextMenuIconAction(
        label: 'קישור',
        icon: OtzariaIcons.link_copy_24_regular,
        submenuBuilder: () => buildDirectLinkSubmenuActions(
          bookId: bookId,
          source: book.source,
          index: paragraphIndex,
          selectedText: selectedText,
        ),
      ),
  ]);
}

/// פעולת חיפוש בכל הספרים; [enabled] נקבע לפי הבחירה אם לא סופק.
AppContextMenuIconAction buildSearchAllBooksIconAction({
  required ReaderMenuSelection selection,
  required VoidCallback onTap,
  bool? enabled,
}) {
  return AppContextMenuIconAction(
    label: 'חיפוש',
    tooltip: selection.hasText
        ? 'חיפוש "${selection.quote(14)}" בכל הספרים'
        : 'חיפוש בכל הספרים',
    icon: FluentIcons.library_24_regular,
    enabled: enabled ?? selection.hasText,
    onTap: onTap,
  );
}

/// The children of a paragraph's "קישורים" submenu: [openPaneEntry], when
/// given, then one entry per link. While the links of the paragraph are
/// still loading and none is known yet, a disabled "loading" entry.
List<AppContextMenuEntry> buildParagraphLinksMenuChildren({
  required List<Link> links,
  required bool isLoading,
  required bool removeNikud,
  required bool removePunctuation,
  required double maxFontSize,
  required void Function(Link link) onOpenLink,
  AppContextMenuEntry? openPaneEntry,
}) {
  if (links.isEmpty) {
    return isLoading
        ? const [AppContextMenuEntry(label: 'טוען קישורים…', enabled: false)]
        : const <AppContextMenuEntry>[];
  }
  return [
    if (openPaneEntry != null) ...[
      openPaneEntry,
      const AppContextMenuEntry.divider(),
    ],
    for (final link in links)
      buildLinkContextMenuEntry(
        link: link,
        removeNikud: removeNikud,
        removePunctuation: removePunctuation,
        maxFontSize: maxFontSize,
        onTap: () => onOpenLink(link),
      ),
  ];
}

/// The dictionary section of a reader's context menu, after a divider: the
/// lookups for [selectedText], or for the word under [tapPosition] when
/// nothing is selected. Empty when there is nothing to look up.
List<AppContextMenuEntry> buildReaderDictionaryEntries({
  required BuildContext context,
  required String? selectedText,
  required Offset tapPosition,
  required DictionaryLookupRepository repository,
}) {
  final lookupText = (selectedText?.trim().isNotEmpty == true)
      ? selectedText
      : wordAtGlobalPosition(tapPosition);
  final entries = buildDictionaryContextMenuEntries(
    context: context,
    selectedText: lookupText,
    repository: repository,
  );
  if (entries.isEmpty) return const [];
  return [const AppContextMenuEntry.divider(), ...entries];
}

/// The entry of a reader's "קישורים" submenu that opens the links pane.
AppContextMenuEntry buildOpenLinksPaneEntry({required VoidCallback onTap}) =>
    AppContextMenuEntry(
      label: 'פתח קישורים בחלונית צד',
      icon: FluentIcons.panel_right_24_regular,
      onTap: onTap,
    );
