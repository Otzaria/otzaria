import 'package:flutter/widgets.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';

import '../helpers/memory_settings_cache.dart';

/// נתונים שנשמרו לפני BookSource (סימניות, היסטוריה וטאבים ב-Hive) חייבים
/// להיטען לאותו מקור ולאותם מפתחות זהות, וגרסה ישנה חייבת לקרוא את מה שנכתב.
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  Map<dynamic, dynamic> legacyBook(String type, {bool? isUserBook}) => {
    'type': type,
    'title': 'ספר',
    'id': 5,
    'categoryId': 3,
    'fileType': type == 'PdfBook' ? 'pdf' : 'txt',
    if (type == 'PdfBook') 'path': 'C:/books/ספר.pdf',
    if (type == 'PdfBook') 'filePath': 'C:/books/ספר.pdf',
    'isUserBook': ?isUserBook,
  };

  Map<String, dynamic> legacyBookmark(Map<dynamic, dynamic> book) => {
    'ref': 'ספר א',
    'index': 4,
    'book': book,
    'commentatorsToShow': <dynamic>[],
  };

  test('סימניה ישנה (Map של Hive) שומרת מקור ומפתח זהות', () {
    final official = Bookmark.fromJson(
      legacyBookmark(legacyBook('TextBook', isUserBook: false)),
    );
    final user = Bookmark.fromJson(
      legacyBookmark(legacyBook('TextBook', isUserBook: true)),
    );
    final missingFlag = Bookmark.fromJson(
      legacyBookmark(legacyBook('TextBook')),
    );

    expect(official.book.source, BookSource.official);
    expect(user.book.source, BookSource.user);
    expect(missingFlag.book.source, BookSource.official);
    expect(bookIdentity(official.book), 'id:5');
    expect(bookIdentity(user.book), 'id:5$kUserBookIdentitySuffix');
  });

  test('ספר PDF ישן: המקור והזהות נשמרים', () {
    final pdf = Bookmark.fromJson(
      legacyBookmark(legacyBook('PdfBook', isUserBook: true)),
    );
    expect(pdf.book, isA<PdfBook>());
    expect(pdf.book.source, BookSource.user);
    expect(bookIdentity(pdf.book), 'id:5|pdf$kUserBookIdentitySuffix');
  });

  test('JSON חדש נקרא בגרסה ישנה לפי isUserBook', () {
    for (final source in [BookSource.official, BookSource.user]) {
      final json = TextBook(title: 'ספר', id: 5, source: source).toJson();
      expect(json['isUserBook'], source.isUser);
      expect(json['source'], source.wireKey);
    }
    final attached = TextBook(
      title: 'ספר',
      source: BookSource.attached('lib'),
    ).toJson();
    expect(attached['isUserBook'], isFalse);
  });

  test('טאב טקסט ו-PDF ישנים נטענים לאותו מקור', () {
    final text = TextBookTab.fromJson({
      'initalIndex': 0,
      'commentators': <String>[],
      'book': legacyBook('TextBook', isUserBook: true),
    });
    addTearDown(text.dispose);
    expect(text.book.source, BookSource.user);

    final restored = TextBookTab.fromJson(text.toJson());
    addTearDown(restored.dispose);
    expect(restored.book.source, BookSource.user);

    final pdf = PdfBookTab.fromJson({
      'path': 'C:/books/ספר.pdf',
      'book': legacyBook('PdfBook', isUserBook: false),
    });
    expect(pdf.book.source, BookSource.official);
  });

  test('מפתח מורכב ישן ומפתח הגדרות פר-ספר לא השתנו', () {
    expect(BookCompositeKey.tryParse('ספר|3|txt')!.source, BookSource.official);
    expect(
      BookCompositeKey.tryParse('ספר|3|txt|o')!.source,
      BookSource.official,
    );
    expect(BookCompositeKey.tryParse('ספר|3|txt|u')!.source, BookSource.user);
    expect(
      BookCompositeKey.tryParse('ספר|3|txt|zz')!.source,
      BookSource.official,
    );
    expect(
      BookCompositeKey.create(
        title: 'ספר',
        categoryId: 3,
        source: BookSource.user,
      ).toStorageKey(),
      'ספר|3|txt|u',
    );

    expect(
      PerBookSettings.bookKey(TextBook(title: 'ספר', categoryId: 3)),
      'o__3__ספר',
    );
    expect(
      PerBookSettings.bookKey(
        TextBook(title: 'ספר', categoryId: 3, source: BookSource.user),
      ),
      'u__3__ספר',
    );
  });
}
