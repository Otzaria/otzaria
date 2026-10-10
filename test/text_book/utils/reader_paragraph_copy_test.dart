import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/utils/reader_paragraph_copy.dart';
import 'package:otzaria/utils/file/toc_parser.dart';

import '../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  group('buildParagraphCopyText', () {
    test('without headers copies the paragraph as rendered', () async {
      final text = await buildParagraphCopyText(
        processedText: '<b>בראשית</b> ברא',
        index: 0,
        copyWithHeaders: 'none',
        copyHeaderFormat: 'same_line_after_brackets',
        headerBook: TextBook(title: 'ספר בדיקה'),
      );

      expect(text.plainText, 'בראשית ברא');
      expect(text.htmlText, contains('<b>בראשית</b>'));
    });

    test('adds the book name the settings ask for', () async {
      final text = await buildParagraphCopyText(
        processedText: 'בראשית ברא',
        index: 0,
        copyWithHeaders: 'book_name',
        copyHeaderFormat: 'same_line_after_brackets',
        headerBook: TextBook(title: 'ספר בדיקה'),
      );

      expect(text.plainText, 'בראשית ברא (ספר בדיקה)');
    });

    test('adds the path of the paragraph from the book content', () async {
      final text = await buildParagraphCopyText(
        processedText: 'בראשית ברא',
        index: 1,
        copyWithHeaders: 'book_and_path',
        copyHeaderFormat: 'separate_line_before',
        headerBook: TextBook(title: 'ספר בדיקה'),
        bookContent: const ['<h2>פרק א</h2>', 'בראשית ברא'],
      );

      expect(text.plainText, 'ספר בדיקה, פרק א\nבראשית ברא');
    });

    test(
      'partial paragraphs preserve loaded headings and add missing parents',
      () async {
        const full = [
          '<h1>ספר</h1>',
          '<h2>פרק א</h2>',
          'טקסט',
          '<h3>הלכה א</h3><h4>סעיף א</h4>',
          'בראשית ברא',
        ];
        final text = await buildParagraphCopyText(
          processedText: '<b>בראשית</b> ברא',
          index: 4,
          copyWithHeaders: 'book_and_path',
          copyHeaderFormat: 'separate_line_before',
          headerBook: _TocBook(
            TocParser.parseEntriesFromContent(full.join('\n')),
          ),
          bookContent: const [
            '',
            '',
            '',
            '<h3>הלכה א</h3><h4>סעיף א</h4>',
            'בראשית ברא',
          ],
          isLineLoaded: (i) => i >= 3,
        );
        expect(text.plainText, 'ספר, פרק א, הלכה א, סעיף א\nבראשית ברא');
        expect(text.htmlText, 'ספר, פרק א, הלכה א, סעיף א\n<b>בראשית</b> ברא');
      },
    );

    test('without a book there are no headers', () async {
      final text = await buildParagraphCopyText(
        processedText: 'בראשית ברא',
        index: 0,
        copyWithHeaders: 'book_name',
        copyHeaderFormat: 'same_line_after_brackets',
      );

      expect(text.plainText, 'בראשית ברא');
    });
  });
}

class _TocBook extends TextBook {
  _TocBook(this.toc) : super(title: 'ספר');
  final List<TocEntry> toc;
  @override
  Future<List<TocEntry>> get tableOfContents async => toc;
}
