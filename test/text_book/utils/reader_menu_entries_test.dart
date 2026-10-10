import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';
import 'package:otzaria/text_book/utils/reader_menu_entries.dart';

void main() {
  group('ReaderMenuSelection', () {
    test('trims the selection and drops nikud', () {
      final selection = ReaderMenuSelection('  בְּרֵאשִׁית ');
      expect(selection.cleaned, 'בראשית');
      expect(selection.hasText, isTrue);
    });

    test('collapses line breaks of a multi-line selection', () {
      expect(
        ReaderMenuSelection('בראשית\nברא  \r\n אלהים').cleaned,
        'בראשית ברא אלהים',
      );
    });

    test('preserves the full search query beyond ten words', () {
      const words =
          'אחת שתים שלוש ארבע חמש שש שבע שמונה תשע עשר אחתעשרה שתיםעשרה';
      final selection = ReaderMenuSelection(words.replaceAll(' ', '\n'));
      expect(selection.cleaned, words);
    });

    test(
      'a tooltip preserves graphemes and only truncates longer selections',
      () {
        final selection = ReaderMenuSelection('א👨‍👩‍👧‍👦ב');
        expect(selection.quote(2), 'א👨‍👩‍👧‍👦...');
        expect(selection.quote(3), selection.cleaned);
        expect(selection.quote(0), '...');
        expect(ReaderMenuSelection('').quote(0), '');
      },
    );

    test('a missing or blank selection has no text', () {
      expect(ReaderMenuSelection(null).hasText, isFalse);
      expect(ReaderMenuSelection('  ').hasText, isFalse);
    });

    test('quotes up to the given number of characters', () {
      final selection = ReaderMenuSelection('בראשית ברא אלהים');
      expect(selection.quote(6), 'בראשית...');
      expect(selection.quote(40), 'בראשית ברא אלהים');
    });
  });

  group('buildReaderIconRow', () {
    Future<List<String>> describe(
      WidgetTester tester, {
      required String? selectedText,
      int? bookId,
    }) async {
      late BuildContext context;
      await tester.pumpWidget(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      );
      final row = buildReaderIconRow(
        context: context,
        selection: ReaderMenuSelection(selectedText),
        book: TextBook(title: 'ספר בדיקה', id: bookId),
        paragraphIndex: 0,
        selectedText: selectedText,
        onCopy: () {},
        onAddNote: () {},
      );
      return [
        for (final action in row.iconRowActions!)
          '${action.label}${action.enabled ? '' : ' (disabled)'}',
      ];
    }

    testWidgets('search and copy need a selection', (tester) async {
      expect(await describe(tester, selectedText: null), [
        'חיפוש (disabled)',
        'העתקה (disabled)',
        'הערה',
      ]);
      expect(await describe(tester, selectedText: 'שלום'), [
        'חיפוש',
        'העתקה',
        'הערה',
      ]);
    });

    testWidgets('a book in the library adds the link action', (tester) async {
      expect(await describe(tester, selectedText: null, bookId: 7), [
        'חיפוש (disabled)',
        'העתקה (disabled)',
        'הערה',
        'קישור',
      ]);
    });
  });

  group('buildParagraphLinksMenuChildren', () {
    final link = Link(
      heRef: 'בראשית א, א',
      index1: 1,
      path2: 'בראשית',
      index2: 1,
      connectionType: 'reference',
    );

    List<AppContextMenuEntry> children({
      List<Link> links = const [],
      bool isLoading = false,
      AppContextMenuEntry? openPaneEntry,
      void Function(Link)? onOpenLink,
    }) => buildParagraphLinksMenuChildren(
      links: links,
      isLoading: isLoading,
      removeNikud: false,
      removePunctuation: false,
      maxFontSize: 18,
      openPaneEntry: openPaneEntry,
      onOpenLink: onOpenLink ?? (_) {},
    );

    test('without links shows the loading entry only while loading', () {
      expect(children(), isEmpty);
      final loading = children(isLoading: true);
      expect(loading.single.label, 'טוען קישורים…');
      expect(loading.single.enabled, isFalse);
    });

    test('puts the open pane entry and a divider above the links', () {
      final opened = <Link>[];
      final entries = children(
        links: [link],
        openPaneEntry: const AppContextMenuEntry(label: 'פתח'),
        onOpenLink: opened.add,
      );

      expect(entries, hasLength(3));
      expect(entries[0].label, 'פתח');
      expect(entries[1].isDivider, isTrue);
      entries[2].onTap!();
      expect(opened, [link]);
    });

    test('without an open pane entry lists only the links', () {
      expect(children(links: [link], isLoading: true), hasLength(1));
    });
  });

  group('buildReaderDictionaryEntries', () {
    final repository = DictionaryLookupRepository(
      loadAcronyms: () async => <String, List<String>>{
        'רש"י': <String>['רבי שלמה יצחקי'],
      },
      loadAramaicEntries: () async => const [],
      loadLaazEntries: () async => const [],
    );

    Future<List<AppContextMenuEntry>> entries(
      WidgetTester tester,
      String? selectedText,
    ) async {
      await repository.ensureLoaded();
      late BuildContext context;
      await tester.pumpWidget(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      );
      return buildReaderDictionaryEntries(
        context: context,
        selectedText: selectedText,
        tapPosition: const Offset(-1000, -1000),
        repository: repository,
      );
    }

    testWidgets('a known selection gets a divider and its lookup', (
      tester,
    ) async {
      final result = await entries(tester, 'רש״י');
      expect(result, hasLength(2));
      expect(result.first.isDivider, isTrue);
    });

    testWidgets('nothing to look up leaves the section empty', (tester) async {
      expect(await entries(tester, null), isEmpty);
    });
  });

  test('the open links pane entry has its label and icon', () {
    var opened = 0;
    final entry = buildOpenLinksPaneEntry(onTap: () => opened++);
    expect(entry.label, 'פתח קישורים בחלונית צד');
    expect(entry.icon, isNotNull);
    entry.onTap!();
    expect(opened, 1);
  });
}
