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

  group('חיפוש מבחירה עם סמני הערות', () {
    ReaderMenuSelection fromHtml(String selected, String html) =>
        ReaderMenuSelection(
          selected,
          sourceLines: [html],
          lineStart: 0,
          lineEnd: 0,
        );

    test('בחירה המסתיימת בסמן אינה מצמידה אותו למילת החיפוש', () {
      final selection = fromHtml(
        'הודאתו3963',
        'הרי שסמך על מקצת הודאתו<sup class="footnote-marker">3963</sup>',
      );
      expect(selection.cleaned, 'הודאתו');
      expect(selection.quote(20), 'הודאתו');
      expect(selection.hasText, isTrue);
    });

    test('בחירה החוצה סמן משאירה גבול בין מילות הגוף', () {
      expect(
        fromHtml('אב1גד', 'אב<sup class="footnote-marker">1</sup>גד').cleaned,
        'אב גד',
      );
    });

    test('פסיק בגוף הטקסט אחרי סמן נשאר בשאילתה', () {
      expect(
        fromHtml(
          'אב1,',
          'אב<sup class="footnote-marker">1</sup>,',
        ).cleaned,
        'אב ,',
      );
    });

    test('מרכאה סוגרת בגוף הטקסט אחרי סמן נשארת בשאילתה', () {
      expect(
        fromHtml(
          '"אב1"',
          '"אב<sup class="footnote-marker">1</sup>"',
        ).cleaned,
        '"אב "',
      );
    });

    test('פיסוק מוסתר אינו מונע התאמה מדויקת לסמן', () {
      expect(
        fromHtml(
          'אב1 גד',
          'אב<sup class="footnote-marker">1</sup>, גד',
        ).cleaned,
        'אב גד',
      );
    });

    test('פיסוק בתוך הסמן מוסר ופיסוק סמוך בגוף נשמר', () {
      expect(
        fromHtml(
          'אב1,,',
          'אב<sup class="footnote-marker">1,</sup>,',
        ).cleaned,
        'אב ,',
      );
    });

    test('בחירה המסתיימת בתוך סמן מסירה גם סמן חלקי', () {
      expect(
        fromHtml(
          'הודאתו39',
          'הודאתו<sup class="footnote-marker">3963</sup>',
        ).cleaned,
        'הודאתו',
      );
    });

    test('עיצוב המקונן בתוך הסמן אינו משאיר את ספרותיו', () {
      expect(
        fromHtml(
          'הודאתו3963',
          '<b>הודאתו</b><sup class="footnote-marker"><i>3963</i></sup>',
        ).cleaned,
        'הודאתו',
      );
    });

    test('בחירה רב שורתית מסירה סמנים בלי להדביק שורות', () {
      expect(
        ReaderMenuSelection(
          'אב1\nגד2',
          sourceLines: const [
            'אב<sup class="footnote-marker">1</sup>',
            'גד<sup class="footnote-marker">2</sup>',
          ],
          lineStart: 0,
          lineEnd: 1,
        ).cleaned,
        'אב גד',
      );
    });

    test('מספרים בגוף הטקסט נשמרים לצד הסרת הסמן', () {
      expect(
        fromHtml(
          'סימן3963 הלכה127',
          'סימן3963 הלכה12<sup class="footnote-marker">7</sup>',
        ).cleaned,
        'סימן3963 הלכה12',
      );
    });

    test('sup רגיל ומחלקה דומה נשמרים', () {
      expect(
        fromHtml(
          'אב123',
          'אב<sup>1</sup><sup class="not-footnote-marker">2</sup>'
              '<sup class="footnote-marker">3</sup>',
        ).cleaned,
        'אב12',
      );
    });

    test('סמן מזוהה גם כשיש לו מחלקות נוספות', () {
      expect(
        fromHtml(
          'אב1',
          "אב<sup class='small footnote-marker end'>1</sup>",
        ).cleaned,
        'אב',
      );
    });

    test('ישויות ורווחי HTML נשמרים כתוכן פשוט', () {
      expect(
        fromHtml(
          'אב & גד1 דה',
          'אב &amp; גד<sup class="footnote-marker">1</sup><br>דה',
        ).cleaned,
        'אב & גד דה',
      );
    });

    test('בלי מקור אין ניחוש שמספר הוא סמן', () {
      expect(ReaderMenuSelection('הודאתו3963').cleaned, 'הודאתו3963');
    });

    test('טווח שורות חסר או לא תקף משאיר את הבחירה', () {
      for (final range in <(int?, int?)>[
        (null, 0),
        (0, null),
        (-1, 0),
        (1, 0),
        (0, 1),
      ]) {
        expect(
          ReaderMenuSelection(
            'אב1',
            sourceLines: const ['אב<sup class="footnote-marker">1</sup>'],
            lineStart: range.$1,
            lineEnd: range.$2,
          ).cleaned,
          'אב1',
          reason: 'אין להסיק שמספר הוא הערה מתוך טווח $range',
        );
      }
    });

    test('מקור שאינו מתאים לבחירה אינו משנה אותה', () {
      expect(
        fromHtml('גד1', 'אב<sup class="footnote-marker">1</sup>').cleaned,
        'גד1',
      );
    });

    test('בחירה עמומה בין מספר גוף לסמן אינה משנה את המספר', () {
      expect(
        fromHtml('אב1', 'אב1 אב<sup class="footnote-marker">1</sup>').cleaned,
        'אב1',
      );
    });

    test('טווח המקור מגביל את ההתאמה לשורה שנבחרה', () {
      const lines = ['אב1', 'אב<sup class="footnote-marker">1</sup>'];
      expect(
        ReaderMenuSelection(
          'אב1',
          sourceLines: lines,
          lineStart: 0,
          lineEnd: 0,
        ).cleaned,
        'אב1',
      );
      expect(
        ReaderMenuSelection(
          'אב1',
          sourceLines: lines,
          lineStart: 1,
          lineEnd: 1,
        ).cleaned,
        'אב',
      );
    });

    test('תווי הכיווניות שהמרנדר מוסיף לסמן אינם מכשילים את ההתאמה', () {
      expect(
        fromHtml(
          'הודאתו\u20663963\u2069',
          'הודאתו<sup class="footnote-marker">3963</sup>',
        ).cleaned,
        'הודאתו',
      );
    });

    test('תווי כיווניות במקור מנורמלים יחד עם הבחירה', () {
      expect(
        fromHtml(
          'הודאתו3963',
          'הודאתו<sup class="footnote-marker">\u20663963\u2069</sup>',
        ).cleaned,
        'הודאתו',
      );
    });

    test('נרמול הכיווניות אינו מוחק מספר גוף או sup רגיל', () {
      expect(
        fromHtml(
          'סימן 123 ומקום\u20664\u2069\u20667\u2069',
          'סימן 123 ומקום<sup>4</sup><sup class="footnote-marker">7</sup>',
        ).cleaned,
        'סימן 123 ומקום4',
      );
    });

    testWidgets('בחירה של סמן בלבד ניתנת להעתקה אך אינה שאילתת חיפוש', (
      tester,
    ) async {
      const original = '\u20663963\u2069';
      final selection = fromHtml(
        original,
        '<sup class="footnote-marker">3963</sup>',
      );
      expect(selection.cleaned, isEmpty);
      expect(selection.hasText, isFalse);
      expect(selection.hasOriginalText, isTrue);
      late BuildContext context;
      await tester.pumpWidget(
        Builder(
          builder: (value) {
            context = value;
            return const SizedBox.shrink();
          },
        ),
      );
      String? copied;
      final row = buildReaderIconRow(
        context: context,
        selection: selection,
        book: TextBook(title: 'ספר בדיקה'),
        paragraphIndex: 0,
        selectedText: original,
        onCopy: () => copied = original,
        onAddNote: () {},
      );
      final actions = row.iconRowActions!;
      expect(
        actions.firstWhere((item) => item.label == 'חיפוש').enabled,
        isFalse,
      );
      final copy = actions.firstWhere((item) => item.label == 'העתקה');
      expect(copy.enabled, isTrue);
      copy.onTap!();
      expect(copied, original);
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
