import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tools/biographies/data/author_biography_links.dart';
import 'package:otzaria/tools/biographies/models/biography.dart';
import 'package:otzaria/tools/biographies/repository/biographies_repository.dart';
import 'package:otzaria/tools/biographies/widgets/biography_card.dart';

TextBook _book(
  String title,
  String? author, {
  String categoryPath = 'מחשבה ומוסר',
  BookSource source = BookSource.official,
}) => TextBook(
  title: title,
  author: author,
  categoryPath: categoryPath,
  source: source,
);

void main() {
  group('biography works link to library books (issue #5203)', () {
    BiographiesRepository repository(List<Book> books) => BiographiesRepository(
      updatedPathProvider: () async => '/nonexistent/bio.json.gz',
      loadAsset: (key) async {
        expect(key, AuthorBiographyLinks.assetKey);
        return ByteData.sublistView(
          utf8.encode(
            jsonEncode({
              'version': 1,
              'authors': {'בחיי אבן פקודה': 'bio1', 'יהודה הלוי': 'bio2'},
            }),
          ),
        );
      },
      libraryBooks: () async => books,
    );

    test(
      'groups official books by the biography of their catalog authors',
      () async {
        final duties = _book('חובות הלבבות', 'בחיי אבן פקודה');
        final kuzari = _book('כוזרי', 'יהודה הלוי');
        final joint = _book('ספר משותף', 'בחיי אבן פקודה, יהודה הלוי');
        final byId = await repository([
          duties,
          kuzari,
          joint,
          _book('חובות הלבבות', 'מחבר אחר'),
          _book('ספר אישי', 'בחיי אבן פקודה', source: BookSource.user),
        ]).libraryBooksByBiography();

        expect(byId.keys, unorderedEquals(['bio1', 'bio2']));
        expect(byId['bio1'], [duties, joint]);
        expect(byId['bio2'], [kuzari, joint]);
      },
    );

    test('a work matches one book with its title', () {
      final duties = _book('חובות הלבבות', 'בחיי אבן פקודה');
      final books = [_book('תורת הנפש', 'בחיי אבן פקודה'), duties];
      expect(BiographiesRepository.bookForWork('חובות הלבבות', books), duties);
      expect(BiographiesRepository.bookForWork('ספר אחר', books), isNull);
    });

    test('a work matches the volumes "<work> על ..." of one shelf', () {
      final first = _book('גור אריה על בראשית', 'מהר"ל', categoryPath: 'תנך');
      final books = [
        first,
        _book('גור אריה על שמות', 'מהר"ל', categoryPath: 'תנך'),
        _book('גור אריהו', 'מהר"ל', categoryPath: 'תנך'),
      ];
      expect(BiographiesRepository.bookForWork('גור אריה', books), first);
    });

    test('an exact title wins over volumes that only start with it', () {
      final exact = _book('מנחת שי', 'מחבר', categoryPath: 'תנך');
      final books = [
        _book('מנחת שי על איוב', 'מחבר', categoryPath: 'תנך'),
        exact,
      ];
      expect(BiographiesRepository.bookForWork('מנחת שי', books), exact);
    });

    test('several candidates on different shelves get no link', () {
      final books = [
        _book('חידושים', 'מחבר', categoryPath: 'תלמוד'),
        _book('חידושים', 'מחבר', categoryPath: 'הלכה'),
      ];
      expect(BiographiesRepository.bookForWork('חידושים', books), isNull);
    });

    testWidgets('a matched work is a link that opens its book', (tester) async {
      final semantics = tester.ensureSemantics();
      final duties = _book('חובות הלבבות', 'בחיי אבן פקודה');
      Book? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: BiographyCard(
                biography: const Biography(
                  id: 'bio1',
                  name: 'רבינו בחיי',
                  works: [
                    BiographyWork(title: 'חובות הלבבות', description: 'מוסר'),
                    BiographyWork(title: 'ספר שאינו בספרייה'),
                  ],
                ),
                initiallyExpanded: true,
                bookForWork: (title) =>
                    BiographiesRepository.bookForWork(title, [duties]),
                onOpenBook: (book) => opened = book,
              ),
            ),
          ),
        ),
      );

      final link = find.text('חובות הלבבות');
      expect(link, findsOneWidget);
      expect(
        tester.getSemantics(link),
        matchesSemantics(
          label: 'חובות הלבבות',
          isLink: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      expect(find.byTooltip('פתח את הספר'), findsOneWidget);
      expect(find.textContaining('ספר שאינו בספרייה'), findsOneWidget);

      await tester.tap(link);
      expect(opened, same(duties));
      semantics.dispose();
    });
  });
}
