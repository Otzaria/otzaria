import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/utils/reader_location_resolver.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';

import '../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  group('ReaderLocationSnapshot', () {
    test('signature is consistent for same location', () {
      final snapshot1 = ReaderLocationSnapshot(
        currentBook: 'בראשית',
        currentBookId: 'בראשית',
        currentId: 1,
        currentType: 'text',
        currentIndex: 42,
        currentRef: 'פרק ג',
      );

      final snapshot2 = ReaderLocationSnapshot(
        currentBook: 'בראשית',
        currentBookId: 'בראשית',
        currentId: 1,
        currentType: 'text',
        currentIndex: 42,
        currentRef: 'פרק ג',
      );

      expect(snapshot1.signature(), snapshot2.signature());
      expect(snapshot1, snapshot2);
    });

    test('signature differs for different locations', () {
      final snapshot1 = ReaderLocationSnapshot(
        currentBook: 'בראשית',
        currentBookId: 'בראשית',
        currentId: 1,
        currentType: 'text',
        currentIndex: 42,
        currentRef: 'פרק ג',
      );

      final snapshot2 = ReaderLocationSnapshot(
        currentBook: 'בראשית',
        currentBookId: 'בראשית',
        currentId: 1,
        currentType: 'text',
        currentIndex: 43,
        currentRef: 'פרק ד',
      );

      expect(snapshot1.signature(), isNot(snapshot2.signature()));
      expect(snapshot1, isNot(snapshot2));
    });

    test('signature differs for same name different id — no collision', () {
      final snapshot1 = ReaderLocationSnapshot(
        currentBook: 'ספר',
        currentBookId: 'ספר',
        currentId: 1,
        currentType: 'text',
        currentIndex: 0,
        currentRef: 'פרק א',
      );
      final snapshot2 = ReaderLocationSnapshot(
        currentBook: 'ספר',
        currentBookId: 'ספר',
        currentId: 2,
        currentType: 'pdf',
        currentIndex: 0,
        currentRef: 'פרק א',
      );

      expect(snapshot1.signature(), isNot(snapshot2.signature()));
      expect(snapshot1, isNot(snapshot2));
    });

    test('toJson returns correct structure including id and type', () {
      final snapshot = ReaderLocationSnapshot(
        currentBook: 'בראשית',
        currentBookId: 'בראשית',
        currentId: 183,
        currentType: 'text',
        currentIndex: 42,
        currentRef: 'פרק ג',
      );

      final json = snapshot.toJson();

      expect(json['currentBook'], 'בראשית');
      expect(json['currentBookId'], 'בראשית');
      expect(json['currentId'], 183);
      expect(json['currentType'], 'text');
      expect(json['currentIndex'], 42);
      expect(json['currentRef'], 'פרק ג');
    });

    test('handles null values correctly', () {
      final snapshot = ReaderLocationSnapshot(
        currentBook: null,
        currentBookId: null,
        currentId: null,
        currentType: null,
        currentIndex: 0,
        currentRef: null,
      );

      final json = snapshot.toJson();

      expect(json['currentBook'], isNull);
      expect(json['currentBookId'], isNull);
      expect(json['currentId'], isNull);
      expect(json['currentType'], isNull);
      expect(json['currentIndex'], 0);
      expect(json['currentRef'], isNull);
    });
  });

  group('resolveReaderLocation', () {
    test('returns null for null tab', () async {
      final result = await resolveReaderLocation(null);
      expect(result, isNull);
    });

    test('resolves location for PDF tab with currentTitle', () async {
      final pdfTab = PdfBookTab(
        book: PdfBook(id: 7, title: 'מסילת ישרים', path: '/tmp/mesilat.pdf'),
        pageNumber: 17,
      )..currentTitle.value = 'פרק ב';

      final result = await resolveReaderLocation(pdfTab);

      expect(result, isNotNull);
      expect(result!.currentBook, 'מסילת ישרים');
      expect(result.currentBookId, 'מסילת ישרים');
      expect(result.currentId, 7);
      expect(result.currentType, 'pdf');
      expect(result.currentIndex, 17);
      expect(result.currentRef, 'פרק ב');
    });

    test('resolves location for PDF tab without currentTitle', () async {
      final pdfTab = PdfBookTab(
        book: PdfBook(id: 7, title: 'מסילת ישרים', path: '/tmp/mesilat.pdf'),
        pageNumber: 17,
      );

      final result = await resolveReaderLocation(pdfTab);

      expect(result, isNotNull);
      expect(result!.currentBook, 'מסילת ישרים');
      expect(result.currentBookId, 'מסילת ישרים');
      expect(result.currentId, 7);
      expect(result.currentType, 'pdf');
      expect(result.currentIndex, 17);
      expect(result.currentRef, 'עמוד 17');
    });

    test('PDF tab with null book id returns null currentId', () async {
      final pdfTab = PdfBookTab(
        book: PdfBook(title: 'ספר ללא id', path: '/tmp/book.pdf'),
        pageNumber: 3,
      );
      final result = await resolveReaderLocation(pdfTab);
      expect(result!.currentId, isNull);
      expect(result.currentType, 'pdf');
    });

    test('resolves location for PDF tab at page 0', () async {
      final pdfTab = PdfBookTab(
        book: PdfBook(title: 'מסילת ישרים', path: '/tmp/mesilat.pdf'),
        pageNumber: 0,
      );

      final result = await resolveReaderLocation(pdfTab);

      expect(result, isNotNull);
      expect(result!.currentBook, 'מסילת ישרים');
      expect(result.currentIndex, 0);
      expect(result.currentRef, isNull);
    });

    test('resolves location for text tab with currentTitle', () async {
      final textTab = TextBookTab(
        book: TextBook(id: 42, title: 'בראשית'),
        index: 42,
      )..currentTitle.value = 'פרק ג';

      final result = await resolveReaderLocation(textTab);

      expect(result, isNotNull);
      expect(result!.currentBook, 'בראשית');
      expect(result.currentBookId, 'בראשית');
      expect(result.currentId, 42);
      expect(result.currentType, 'text');
      expect(result.currentIndex, 42);
      expect(result.currentRef, 'פרק ג');
    });

    test('resolves location for text tab with state currentTitle', () async {
      final textTab = TextBookTab(
        book: TextBook(id: 5, title: 'בראשית'),
        index: 42,
      );

      textTab.bloc.emit(
        TextBookLoaded.initial(
          book: textTab.book,
          index: textTab.index,
          showLeftPane: false,
          splitView: false,
        ).copyWith(
          visibleIndices: [42],
          currentTitle: 'פרק ג',
        ),
      );

      final result = await resolveReaderLocation(textTab);

      expect(result, isNotNull);
      expect(result!.currentBook, 'בראשית');
      expect(result.currentBookId, 'בראשית');
      expect(result.currentId, 5);
      expect(result.currentType, 'text');
      expect(result.currentIndex, 42);
      expect(result.currentRef, 'פרק ג');
    });

    test('resolves location for text tab without currentTitle', () async {
      final textTab = TextBookTab(
        book: TextBook(title: 'בראשית'),
        index: 42,
      );

      final result = await resolveReaderLocation(textTab);

      expect(result, isNotNull);
      expect(result!.currentBook, 'בראשית');
      expect(result.currentBookId, 'בראשית');
      expect(result.currentType, 'text');
      expect(result.currentIndex, 42);
      expect(result.currentRef, isNull);
    });

    test('prefers ValueNotifier title over state title for text tab', () async {
      final textTab = TextBookTab(
        book: TextBook(title: 'בראשית'),
        index: 42,
      )..currentTitle.value = 'פרק ג מה-notifier';

      textTab.bloc.emit(
        TextBookLoaded.initial(
          book: textTab.book,
          index: textTab.index,
          showLeftPane: false,
          splitView: false,
        ).copyWith(
          visibleIndices: [42],
          currentTitle: 'פרק ג מה-state',
        ),
      );

      final result = await resolveReaderLocation(textTab);

      expect(result, isNotNull);
      expect(result!.currentRef, 'פרק ג מה-notifier');
    });

    test('prefers ValueNotifier title over default for PDF tab', () async {
      final pdfTab = PdfBookTab(
        book: PdfBook(title: 'מסילת ישרים', path: '/tmp/mesilat.pdf'),
        pageNumber: 17,
      )..currentTitle.value = 'פרק ב';

      final result = await resolveReaderLocation(pdfTab);

      expect(result, isNotNull);
      expect(result!.currentRef, 'פרק ב');
    });
  });
}
