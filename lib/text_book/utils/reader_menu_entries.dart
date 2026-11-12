import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/widgets.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:otzaria/book_protection/models/book_protection.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_book/utils/inline_notes_utils.dart' as notes;
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
  ReaderMenuSelection(
    String? selectedText, {
    List<String>? sourceLines,
    int? lineStart,
    int? lineEnd,
  }) : hasOriginalText = _clean(selectedText).isNotEmpty,
       cleaned = _clean(
         _withoutFootnoteMarkers(selectedText, sourceLines, lineStart, lineEnd),
       );

  final String cleaned;
  final bool hasOriginalText;

  bool get hasText => cleaned.isNotEmpty;

  /// [cleaned] cut to [maxChars] graphemes, for labels and tooltips.
  String quote(int maxChars) {
    final prefix = cleaned.characters.take(maxChars + 1);
    return prefix.length > maxChars ? '${prefix.take(maxChars)}...' : cleaned;
  }

  static String? _withoutFootnoteMarkers(
    String? text,
    List<String>? lines,
    int? start,
    int? end,
  ) {
    if (text == null ||
        text.isEmpty ||
        lines == null ||
        start == null ||
        end == null ||
        start < 0 ||
        end < start ||
        end >= lines.length) {
      return text;
    }
    final source = lines.getRange(start, end + 1).join('\n');
    if (!source.contains('footnote-marker')) return text;
    final selected = _clean(utils.removeSearchInvisibles(text));
    if (selected.isEmpty) return text;
    final selectedKey = _matchingKey(selected);
    final withoutBodies = notes.stripInlineNotes(source);
    final withoutPunctuation = utils.removePunctuation(withoutBodies);
    String? result;
    for (final html in {
      withoutBodies,
      withoutPunctuation,
    }) {
      final mapped = _mapFootnoteMarkers(html);
      final sourceKey = _matchingKey(mapped.text);
      var start = sourceKey.indexOf(selectedKey);
      var occurrences = 0;
      while (start >= 0) {
        if (++occurrences > 12) return text;
        final query = StringBuffer();
        var removed = false;
        for (var i = 0; i < selected.length; i++) {
          if (mapped.markers[start + i]) {
            query.write(' ');
            removed = true;
          } else {
            query.write(selected[i]);
          }
        }
        if (!removed) return text;
        final candidate = _clean(query.toString());
        if (result != null && result != candidate) return text;
        result = candidate;
        start = sourceKey.indexOf(selectedKey, start + 1);
      }
    }
    return result ?? text;
  }

  static ({String text, List<bool> markers}) _mapFootnoteMarkers(String html) {
    final fragment = html_parser.parseFragment(html);
    final hasNikud = utils.hasNikud(fragment.text ?? '');
    final text = StringBuffer();
    final markers = <bool>[];
    var pendingSpace = false;
    void append(String value, bool insideMarker) {
      if (hasNikud) value = utils.removeVolwels(value);
      final normalized = utils
          .removeSearchInvisibles(value)
          .replaceAll(RegExp(r'\s+'), ' ');
      for (var i = 0; i < normalized.length; i++) {
        final character = normalized[i];
        if (character == ' ') {
          pendingSpace = true;
        } else {
          if (pendingSpace && text.isNotEmpty) {
            text.write(' ');
            markers.add(false);
          }
          pendingSpace = false;
          text.write(character);
          markers.add(insideMarker);
        }
      }
    }

    final breakingTags = <String, bool>{};
    void visit(html_dom.Node node, bool insideMarker) {
      if (node is html_dom.Text) {
        append(node.data, insideMarker);
      } else if (node is html_dom.Element) {
        final tag = node.localName ?? '';
        final marker =
            insideMarker ||
            (tag == 'sup' && node.classes.contains('footnote-marker'));
        final breaks = breakingTags.putIfAbsent(
          tag,
          () => utils.stripHtmlIfNeeded('<$tag>') == ' ',
        );
        if (breaks) append(' ', marker);
        for (final child in node.nodes) {
          visit(child, marker);
        }
        if (breaks) append(' ', marker);
      }
    }

    // גבולות הסמן נקבעים לפני הסרת התגים, כך שפיסוק סמוך נשאר בגוף הטקסט.
    for (final node in fragment.nodes) {
      visit(node, false);
    }
    return (text: text.toString(), markers: markers);
  }

  static String _matchingKey(String text) {
    final replaced = utils.replaceHolyNames(text);
    return replaced.length == text.length ? replaced : text;
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
  BookProtection protection = BookProtection.none,
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
      enabled: selection.hasOriginalText,
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
        icon: OtzariaIcons.link_24_regular,
        submenuBuilder: () => buildDirectLinkSubmenuActions(
          bookId: bookId,
          source: book.source,
          index: paragraphIndex,
          selectedText: selectedText,
          protection: () async => protection,
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
      : wordAtGlobalPosition(
          tapPosition,
          view: context.findAncestorWidgetOfExactType<View>()?.view,
        );
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
