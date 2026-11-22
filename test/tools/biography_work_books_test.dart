import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tools/biographies/data/biographies_codec.dart';
import 'package:otzaria/tools/biographies/models/biography.dart';
import 'package:otzaria/tools/biographies/repository/biographies_repository.dart';
import 'package:otzaria/tools/biographies/widgets/biography_card.dart';

import 'biographies_codec_test.dart' show encodeBundle, samplePayload;

/// Library books of the official catalog (version 39) behind the failures
/// reported when PR #5660 was closed.
TextBook _book(
  String title,
  String author, {
  BookSource source = BookSource.official,
}) => TextBook(title: title, author: author, source: source);

final _yesodeiHatorah = _book(
  'פרי חדש על משנה תורה, הלכות יסודי התורה',
  'חזקיה די סילוה',
);
final _chovotHalevavot = _book('חובות הלבבות', 'בחיי אבן פקודה');

const _priChadash = BiographyWork(
  title: 'פרי חדש',
  description: 'חיבור הלכה על השולחן ערוך, בעיקר אורח חיים ויורה דעה',
);
const _chovot = BiographyWork(
  title: 'חובות הלבבות',
  books: ['חובות הלבבות'],
);

void main() {
  group('biography works link to library books (issue #5203)', () {
    test('a work carries the book titles mapped in the bundle', () {
      final payload = samplePayload();
      ((payload['entries'] as List).first as Map)['works'] = [
        {
          'title': 'חובות הלבבות',
          'description': 'מיסודות ספרי המוסר',
          'books': ['חובות הלבבות'],
        },
        {'title': 'פרי חדש'},
      ];
      final works = BiographiesCodec.decode(
        encodeBundle(payload),
      ).entries.first.works;
      expect(works.first.books, ['חובות הלבבות']);
      expect(works.last.books, isEmpty);
    });

    test('"פרי חדש" on the Shulchan Arukh does not open the commentary on '
        'Mishneh Torah by the same author', () async {
      final repo = BiographiesRepository(
        libraryBooks: () async => [
          _yesodeiHatorah,
          _book(
            'פרי חדש על משנה תורה, הלכות דעות',
            'חזקיה די סילוה',
          ),
        ],
      );
      final books = await repo.libraryBooksByTitle();
      expect(BiographiesRepository.bookForWork(_priChadash, books), isNull);
    });

    test('"חובות הלבבות" opens its mapped book, whatever the catalog '
        'author is called', () async {
      final repo = BiographiesRepository(
        libraryBooks: () async => [_yesodeiHatorah, _chovotHalevavot],
      );
      final books = await repo.libraryBooksByTitle();
      expect(
        BiographiesRepository.bookForWork(_chovot, books),
        same(_chovotHalevavot),
      );
    });

    test('a mapped title that names several library books has no link, and '
        'personal books are not candidates', () async {
      final repo = BiographiesRepository(
        libraryBooks: () async => [
          _chovotHalevavot,
          _book('חובות הלבבות', 'אחר'),
          _book('מסילת ישרים', 'משה חיים לוצאטו', source: BookSource.user),
        ],
      );
      final books = await repo.libraryBooksByTitle();
      expect(BiographiesRepository.bookForWork(_chovot, books), isNull);
      expect(
        BiographiesRepository.bookForWork(
          const BiographyWork(title: 'מסילת ישרים', books: ['מסילת ישרים']),
          books,
        ),
        isNull,
      );
    });

    test('a work of several volumes opens the first one in the library', () {
      final second = _book('ספר חלק ב', 'מחבר');
      expect(
        BiographiesRepository.bookForWork(
          const BiographyWork(title: 'ספר', books: ['ספר חלק א', 'ספר חלק ב']),
          {second.title: second},
        ),
        same(second),
      );
    });

    testWidgets('the card links a mapped work only', (tester) async {
      Book? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SingleChildScrollView(
                child: BiographyCard(
                  biography: const Biography(
                    id: 'Q762229',
                    name: 'רבינו בחיי בן יוסף אבן פקודה',
                    works: [_chovot, _priChadash],
                  ),
                  initiallyExpanded: true,
                  bookForWork: (work) => BiographiesRepository.bookForWork(
                    work,
                    {
                      _chovotHalevavot.title: _chovotHalevavot,
                      _yesodeiHatorah.title: _yesodeiHatorah,
                    },
                  ),
                  onOpenBook: (book) => opened = book,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final link = find.bySemanticsLabel('חובות הלבבות');
      expect(link, findsOneWidget);
      expect(tester.getSemantics(link), isSemantics(isLink: true));
      expect(find.bySemanticsLabel(RegExp('^פרי חדש\$')), findsNothing);

      await tester.tap(find.text('חובות הלבבות'));
      expect(opened, same(_chovotHalevavot));

      opened = null;
      await tester.tap(find.textContaining('פרי חדש'));
      expect(opened, isNull);
    });
  });
}
