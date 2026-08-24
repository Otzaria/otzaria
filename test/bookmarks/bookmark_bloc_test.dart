import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_state.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/bookmarks/repository/bookmark_repository.dart';
import 'package:otzaria/models/books.dart';

// ─── Fake repository ─────────────────────────────────────────────────────────

class _FakeBookmarkRepository implements BookmarkRepository {
  List<Bookmark> _bookmarks;
  int saveCallCount = 0;
  int clearCallCount = 0;

  _FakeBookmarkRepository({List<Bookmark>? initial})
    : _bookmarks = initial ?? [];

  @override
  Future<List<Bookmark>> loadBookmarks() async => List.from(_bookmarks);

  @override
  Future<void> saveBookmarks(List<Bookmark> bookmarks) async {
    _bookmarks = List.from(bookmarks);
    saveCallCount++;
  }

  @override
  Future<void> clearBookmarks() async {
    _bookmarks = [];
    clearCallCount++;
  }

  // Unused BaseListRepository methods
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

TextBook _book({String title = 'ספר א'}) => TextBook(
  title: title,
  filePath: '/fake/$title.txt',
);

Bookmark _bookmark({
  String ref = 'בראשית א',
  String bookTitle = 'ספר א',
  int index = 0,
}) => Bookmark(
  ref: ref,
  book: _book(title: bookTitle),
  index: index,
);

Future<BookmarkBloc> _makeBloc({List<Bookmark>? initial}) async {
  final repo = _FakeBookmarkRepository(initial: initial);
  final bloc = BookmarkBloc(repo);
  // Allow _loadBookmarks to complete
  await Future<void>.delayed(Duration.zero);
  return bloc;
}

/// מחסן שהכתיבה אליו נכשלת — למסלול שממתין לשמירה (הגשר לתוספים).
class _FailingBookmarkRepository extends _FakeBookmarkRepository {
  _FailingBookmarkRepository({super.initial});

  @override
  Future<void> saveBookmarks(List<Bookmark> bookmarks) async {
    saveCallCount++;
    throw Exception('disk full');
  }
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  // UiSnack בכשל שמירה נוגע ב-WidgetsBinding.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BookmarkBloc מסלול שממתין לשמירה', () {
    test('addBookmarkAndSave מחזיר false כשהשמירה לדיסק נכשלה', () async {
      final bloc = BookmarkBloc(_FailingBookmarkRepository());
      await Future<void>.delayed(Duration.zero);

      final saved = await bloc.addBookmarkAndSave(
        ref: 'בראשית א',
        book: _book(),
        index: 0,
      );

      expect(saved, isFalse);
    });

    test('addBookmarkAndSave מחזיר true כשהשמירה הצליחה', () async {
      final bloc = await _makeBloc();

      expect(
        await bloc.addBookmarkAndSave(
          ref: 'בראשית א',
          book: _book(),
          index: 0,
        ),
        isTrue,
      );
    });

    test('addBookmarkAndSave מחזיר false על כפילות', () async {
      final bloc = await _makeBloc(initial: [_bookmark(ref: 'בראשית א')]);

      expect(
        await bloc.addBookmarkAndSave(
          ref: 'בראשית א',
          book: _book(),
          index: 0,
        ),
        isFalse,
      );
    });

    test('מסלול ה-UI אינו חוסם — addBookmark מחזיר מיד true', () async {
      final bloc = BookmarkBloc(_FailingBookmarkRepository());
      await Future<void>.delayed(Duration.zero);

      expect(bloc.addBookmark(ref: 'בראשית א', book: _book(), index: 0), true);
      expect(bloc.state.bookmarks, hasLength(1));
    });

    test('removeBookmarkAndSave מחזיר false כשהשמירה נכשלה', () async {
      final bloc = BookmarkBloc(
        _FailingBookmarkRepository(initial: [_bookmark(ref: 'בראשית א')]),
      );
      await Future<void>.delayed(Duration.zero);

      expect(await bloc.removeBookmarkAndSave(0), isFalse);
    });
  });

  group('BookmarkBloc removeBookmark גבולות', () {
    test('אינדקס מחוץ לתחום מחזיר false ואינו משנה דבר', () async {
      final bloc = await _makeBloc(initial: [_bookmark()]);

      expect(bloc.removeBookmark(5), isFalse);
      expect(bloc.removeBookmark(-1), isFalse);
      expect(bloc.state.bookmarks, hasLength(1));
    });

    test('אינדקס תקף מחזיר true ומסיר', () async {
      final bloc = await _makeBloc(initial: [_bookmark()]);

      expect(bloc.removeBookmark(0), isTrue);
      expect(bloc.state.bookmarks, isEmpty);
    });
  });

  group('BookmarkBloc', () {
    group('initial load', () {
      test('מתחיל עם רשימה ריקה כאשר אין סימניות', () async {
        final bloc = await _makeBloc();
        expect(bloc.state.bookmarks, isEmpty);
      });

      test('טוען סימניות קיימות ב-init', () async {
        final existing = [_bookmark(ref: 'בראשית א'), _bookmark(ref: 'שמות א')];
        final bloc = await _makeBloc(initial: existing);
        expect(bloc.state.bookmarks.length, 2);
        expect(bloc.state.bookmarks[0].ref, 'בראשית א');
        expect(bloc.state.bookmarks[1].ref, 'שמות א');
      });
    });

    group('addBookmark', () {
      test('מוסיף סימנייה חדשה ומחזיר true', () async {
        final bloc = await _makeBloc();
        final result = bloc.addBookmark(
          ref: 'בראשית א',
          book: _book(),
          index: 0,
        );
        expect(result, isTrue);
        expect(bloc.state.bookmarks.length, 1);
        expect(bloc.state.bookmarks.first.ref, 'בראשית א');
      });

      test('מגדיר createdAt בסימנייה חדשה', () async {
        final bloc = await _makeBloc();
        bloc.addBookmark(ref: 'בראשית א', book: _book(), index: 0);
        expect(bloc.state.bookmarks.first.createdAt, isNotNull);
      });

      test(
        'לא מוסיף סימנייה כפולה (אותו ספר + אותו index) ומחזיר false',
        () async {
          final bloc = await _makeBloc(initial: [_bookmark(ref: 'בראשית א')]);
          final result = bloc.addBookmark(
            ref: 'בראשית א',
            book: _book(),
            index: 0,
          );
          expect(result, isFalse);
          expect(bloc.state.bookmarks.length, 1);
        },
      );

      test('מוסיף מספר סימניות באותו ספר באינדקסים שונים', () async {
        // לשעבר נדחתה סימניה שנייה באותו ref (למשל כשכל סעיף בפרק מקבל את
        // אותו ref) - עכשיו הזיהוי לפי book + index, ולכן מותר.
        final bloc = await _makeBloc(
          initial: [
            _bookmark(ref: 'בראשית א', bookTitle: 'ספר א', index: 0),
          ],
        );
        final result = bloc.addBookmark(
          ref: 'בראשית א',
          book: _book(title: 'ספר א'),
          index: 5,
        );
        expect(result, isTrue);
        expect(bloc.state.bookmarks.length, 2);
        expect(bloc.state.bookmarks.map((b) => b.index).toList(), [0, 5]);
      });

      test('מאפשר אותו index בספרים שונים', () async {
        final bloc = await _makeBloc(
          initial: [_bookmark(bookTitle: 'ספר א', index: 5)],
        );
        final result = bloc.addBookmark(
          ref: 'אחר',
          book: _book(title: 'ספר ב'),
          index: 5,
        );
        expect(result, isTrue);
        expect(bloc.state.bookmarks.length, 2);
      });

      test(
        'מאפשר אותה כותרת + index אבל נתיבי קובץ שונים (מהדורות שונות של אותו שם)',
        () async {
          // P1: לא בטלה למזג דו מהדורות של אותו ספר (נתיבי קובץ שונים) - הזיהות לא
          // לפי כותרת בלבד אלא לפי filePath/path.
          final bookA = TextBook(title: 'ספר א', filePath: '/edition-1/א.txt');
          final bookB = TextBook(title: 'ספר א', filePath: '/edition-2/א.txt');

          final bloc = BookmarkBloc(
            _FakeBookmarkRepository(
              initial: [
                Bookmark(ref: 'בראשית א', book: bookA, index: 0),
              ],
            ),
          );
          await Future<void>.delayed(Duration.zero);

          final result = bloc.addBookmark(
            ref: 'בראשית א',
            book: bookB,
            index: 0,
          );

          expect(result, isTrue);
          expect(bloc.state.bookmarks.length, 2);
        },
      );

      test('שומר את הסימנייה ב-repository', () async {
        final repo = _FakeBookmarkRepository();
        final bloc = BookmarkBloc(repo);
        await Future<void>.delayed(Duration.zero);

        bloc.addBookmark(ref: 'בראשית א', book: _book(), index: 0);

        expect(repo.saveCallCount, 1);
        expect(repo._bookmarks.length, 1);
      });

      test('שומר commentatorsToShow בסימנייה', () async {
        final bloc = await _makeBloc();
        bloc.addBookmark(
          ref: 'בראשית א',
          book: _book(),
          index: 0,
          commentatorsToShow: ['רש"י', 'רמב"ן'],
        );
        expect(bloc.state.bookmarks.first.commentatorsToShow, [
          'רש"י',
          'רמב"ן',
        ]);
      });

      test('מוסיף מספר סימניות שונות', () async {
        final bloc = await _makeBloc();
        bloc.addBookmark(ref: 'בראשית א', book: _book(), index: 0);
        bloc.addBookmark(
          ref: 'שמות א',
          book: _book(title: 'ספר ב'),
          index: 5,
        );
        expect(bloc.state.bookmarks.length, 2);
      });

      test('שומר label בסימנייה חדשה', () async {
        final bloc = await _makeBloc();
        bloc.addBookmark(
          ref: 'בראשית א',
          book: _book(),
          index: 0,
          label: 'בראשית ברא אלהים',
        );
        expect(bloc.state.bookmarks.first.label, 'בראשית ברא אלהים');
      });

      test(
        'אותו ספר + אותו index אבל targetKind שונה — מותר (לא כפולה)',
        () async {
          // סימנייה רגילה וסימנייה של מפרשים על אותו מיקום הן שתי רשומות נפרדות.
          final bloc = await _makeBloc(
            initial: [
              Bookmark(
                ref: 'בראשית א',
                book: _book(),
                index: 0,
                targetKind: BookmarkTargetKind.book,
              ),
            ],
          );

          final result = bloc.addBookmark(
            ref: 'מפרשים | בראשית א',
            book: _book(),
            index: 0,
            targetKind: BookmarkTargetKind.commentators,
          );

          expect(result, isTrue);
          expect(bloc.state.bookmarks.length, 2);
          expect(
            bloc.state.bookmarks.map((b) => b.targetKind).toList(),
            [BookmarkTargetKind.book, BookmarkTargetKind.commentators],
          );
        },
      );

      test(
        'אותו ספר + אותו index + אותו targetKind commentators — נדחה',
        () async {
          final bloc = await _makeBloc(
            initial: [
              Bookmark(
                ref: 'מפרשים | בראשית א',
                book: _book(),
                index: 0,
                targetKind: BookmarkTargetKind.commentators,
              ),
            ],
          );

          final result = bloc.addBookmark(
            ref: 'מפרשים | בראשית א (נוסח שונה)',
            book: _book(),
            index: 0,
            targetKind: BookmarkTargetKind.commentators,
          );

          expect(result, isFalse);
          expect(bloc.state.bookmarks.length, 1);
        },
      );

      test('שומר targetKind בסימנייה', () async {
        final bloc = await _makeBloc();
        bloc.addBookmark(
          ref: 'מפרשים | בראשית א',
          book: _book(),
          index: 0,
          targetKind: BookmarkTargetKind.commentators,
        );
        expect(
          bloc.state.bookmarks.first.targetKind,
          BookmarkTargetKind.commentators,
        );
      });
    });

    group('removeBookmark', () {
      test('מסיר סימנייה לפי אינדקס', () async {
        final bloc = await _makeBloc(
          initial: [
            _bookmark(ref: 'בראשית א'),
            _bookmark(ref: 'שמות א'),
          ],
        );
        bloc.removeBookmark(0);
        expect(bloc.state.bookmarks.length, 1);
        expect(bloc.state.bookmarks.first.ref, 'שמות א');
      });

      test('שומר אחרי הסרה', () async {
        final repo = _FakeBookmarkRepository(
          initial: [_bookmark(ref: 'בראשית א')],
        );
        final bloc = BookmarkBloc(repo);
        await Future<void>.delayed(Duration.zero);

        bloc.removeBookmark(0);

        expect(repo.saveCallCount, 1);
        expect(repo._bookmarks, isEmpty);
      });

      test('מסיר מהסוף ללא השפעה על שאר הסימניות', () async {
        final bloc = await _makeBloc(
          initial: [
            _bookmark(ref: 'א'),
            _bookmark(ref: 'ב'),
            _bookmark(ref: 'ג'),
          ],
        );
        bloc.removeBookmark(2);
        expect(bloc.state.bookmarks.map((b) => b.ref).toList(), ['א', 'ב']);
      });
    });

    group('updateBookmarkLabel', () {
      test('מעדכן את ה-label של סימנייה קיימת', () async {
        final bloc = await _makeBloc(initial: [_bookmark(ref: 'בראשית א')]);
        bloc.updateBookmarkLabel(0, 'תיאור חדש');
        expect(bloc.state.bookmarks.first.label, 'תיאור חדש');
      });

      test('label ריק מאפס לברירת המחדל (null)', () async {
        final bloc = await _makeBloc(
          initial: [
            Bookmark(
              ref: 'בראשית א',
              book: _book(),
              index: 0,
              label: 'תיאור קיים',
            ),
          ],
        );
        bloc.updateBookmarkLabel(0, '   ');
        expect(bloc.state.bookmarks.first.label, isNull);
      });

      test('אינדקס מחוץ לתחום לא משנה דבר', () async {
        final bloc = await _makeBloc(initial: [_bookmark(ref: 'בראשית א')]);
        bloc.updateBookmarkLabel(5, 'תיאור');
        expect(bloc.state.bookmarks.first.label, isNull);
      });
    });

    group('clearBookmarks', () {
      test('מנקה את כל הסימניות', () async {
        final bloc = await _makeBloc(
          initial: [
            _bookmark(ref: 'בראשית א'),
            _bookmark(ref: 'שמות א'),
          ],
        );
        bloc.clearBookmarks();
        expect(bloc.state.bookmarks, isEmpty);
      });

      test('קורא ל-clearBookmarks ב-repository', () async {
        final repo = _FakeBookmarkRepository(
          initial: [_bookmark(ref: 'בראשית א')],
        );
        final bloc = BookmarkBloc(repo);
        await Future<void>.delayed(Duration.zero);

        bloc.clearBookmarks();

        expect(repo.clearCallCount, 1);
      });
    });

    group('clearBookmarksForBook', () {
      test(
        'מוחק רק סימניות של הספר שצויין ומשאיר ספרים אחרים ומחזיר true',
        () async {
          final bookA = _book(title: 'ספר א');
          final bookB = _book(title: 'ספר ב');
          final bloc = await _makeBloc(
            initial: [
              Bookmark(ref: 'א-1', book: bookA, index: 0),
              Bookmark(ref: 'א-2', book: bookA, index: 10),
              Bookmark(ref: 'ב-1', book: bookB, index: 5),
            ],
          );

          final removed = bloc.clearBookmarksForBook(bookA);

          expect(removed, isTrue);
          expect(bloc.state.bookmarks.length, 1);
          expect(bloc.state.bookmarks.first.book.title, 'ספר ב');
        },
      );

      test(
        'ללא סימניות תואמות - מחזיר false ולא משנה state ולא קורא ל-repository',
        () async {
          final repo = _FakeBookmarkRepository(
            initial: [
              _bookmark(bookTitle: 'ספר א'),
            ],
          );
          final bloc = BookmarkBloc(repo);
          await Future<void>.delayed(Duration.zero);
          repo.saveCallCount = 0;

          final removed = bloc.clearBookmarksForBook(_book(title: 'ספר ב'));

          expect(removed, isFalse);
          expect(bloc.state.bookmarks.length, 1);
          expect(repo.saveCallCount, 0);
        },
      );
    });

    group('BookmarkState', () {
      test('copyWith מעדכן רק את השדות שנמסרו', () {
        final state = BookmarkState(bookmarks: [_bookmark()]);
        final updated = state.copyWith(bookmarks: []);
        expect(updated.bookmarks, isEmpty);
      });

      test('copyWith ללא ארגומנטים מחזיר אותו ערך', () {
        final bookmarks = [_bookmark()];
        final state = BookmarkState(bookmarks: bookmarks);
        final copy = state.copyWith();
        expect(copy.bookmarks, same(bookmarks));
      });

      test('BookmarkState.initial מחזיר רשימה ריקה', () {
        final state = BookmarkState.initial();
        expect(state.bookmarks, isEmpty);
      });
    });
  });

  group('bookIdentity', () {
    test('מהדורה חלופית מקבלת זהות שונה מהנוסח הממוזג של אותו ספר', () {
      final merged = TextBook(id: 7, title: 'טור', categoryId: 3);
      final edition = merged.copyWith(versionTitle: 'Warsaw 1861');
      final otherEdition = merged.copyWith(versionTitle: 'Vilna 1923');

      expect(bookIdentity(merged), isNot(bookIdentity(edition)));
      expect(bookIdentity(edition), isNot(bookIdentity(otherEdition)));
      expect(
        bookIdentity(edition),
        bookIdentity(merged.copyWith(versionTitle: 'Warsaw 1861')),
      );
    });

    test('PDF שחולק id עם מהדורת הטקסט מקבל זהות נפרדת', () {
      final text = TextBook(id: 103, title: 'ברכות', categoryId: 3);
      final pdf = PdfBook(
        id: 103,
        title: 'ברכות',
        path: r'C:\books\תלמוד בבלי\ברכות.pdf',
        categoryId: 3,
      );

      expect(bookIdentity(pdf), isNot(bookIdentity(text)));
    });

    test('historyKey של מהדורה חלופית נפרד משל הנוסח הממוזג', () {
      final merged = TextBook(id: 7, title: 'טור', categoryId: 3);
      final edition = merged.copyWith(versionTitle: 'Warsaw 1861');

      final mergedEntry = Bookmark(ref: 'טור א', book: merged, index: 5);
      final editionEntry = Bookmark(ref: 'טור א', book: edition, index: 9);

      expect(mergedEntry.historyKey, isNot(editionEntry.historyKey));
      expect(editionEntry.historyKey, contains('Warsaw 1861'));
    });
  });

  group('Bookmark model', () {
    test('toJson ו-fromJson עוברים סיבוב מלא', () {
      final original = Bookmark(
        ref: 'בראשית א א',
        book: _book(title: 'בראשית'),
        index: 42,
        commentatorsToShow: ['רש"י'],
      );

      final json = original.toJson();
      final restored = Bookmark.fromJson(json);

      expect(restored.ref, original.ref);
      expect(restored.book.title, original.book.title);
      expect(restored.index, original.index);
      expect(restored.commentatorsToShow, original.commentatorsToShow);
    });

    test('toJson/fromJson שומרים targetKind.book', () {
      final original = Bookmark(
        ref: 'בראשית א',
        book: _book(),
        index: 0,
        targetKind: BookmarkTargetKind.book,
      );
      final restored = Bookmark.fromJson(original.toJson());
      expect(restored.targetKind, BookmarkTargetKind.book);
    });

    test('toJson/fromJson שומרים targetKind.commentators', () {
      final original = Bookmark(
        ref: 'מפרשים | בראשית א',
        book: _book(),
        index: 0,
        commentatorsToShow: ['רש"י'],
        targetKind: BookmarkTargetKind.commentators,
      );
      final json = original.toJson();
      final restored = Bookmark.fromJson(json);

      expect(restored.targetKind, BookmarkTargetKind.commentators);
      expect(restored.ref, original.ref);
      expect(restored.commentatorsToShow, original.commentatorsToShow);
    });

    test('toJson כולל מפתח targetKind', () {
      final bm = Bookmark(
        ref: 'א',
        book: _book(),
        index: 0,
        targetKind: BookmarkTargetKind.commentators,
      );
      final json = bm.toJson();
      expect(json['targetKind'], 'commentators');
    });

    test('historyKey כולל targetKind לסימנייה רגילה', () {
      final bm = _bookmark(bookTitle: 'בראשית');
      expect(bm.historyKey, 'book:בראשית');
    });

    test('historyKey כולל targetKind לסימניית מפרשים', () {
      final bm = Bookmark(
        ref: 'מפרשים | בראשית א',
        book: _book(title: 'בראשית'),
        index: 42,
        targetKind: BookmarkTargetKind.commentators,
      );
      expect(bm.historyKey, 'commentators:בראשית');
    });

    test('historyKey הוא ref לסימנייה חיפוש', () {
      final bm = Bookmark(
        ref: 'שאילתא',
        book: _book(),
        index: 0,
        isSearch: true,
      );
      expect(bm.historyKey, 'שאילתא');
    });

    test('fromJson מטפל ב-commentatorsToShow חסר', () {
      final json = {
        'ref': 'א',
        'index': 0,
        'book': _book().toJson(),
      };
      final bm = Bookmark.fromJson(json);
      expect(bm.commentatorsToShow, isEmpty);
    });

    test('fromJson מטפל ב-isSearch חסר (ברירת מחדל false)', () {
      final json = {
        'ref': 'א',
        'index': 0,
        'book': _book().toJson(),
      };
      final bm = Bookmark.fromJson(json);
      expect(bm.isSearch, isFalse);
    });

    test('fromJson מטפל ב-targetKind חסר (ברירת מחדל book)', () {
      final json = {
        'ref': 'א',
        'index': 0,
        'book': _book().toJson(),
      };
      final bm = Bookmark.fromJson(json);
      expect(bm.targetKind, BookmarkTargetKind.book);
    });

    test('toJson/fromJson שומרים createdAt', () {
      final created = DateTime(2026, 6, 21, 10, 30);
      final original = Bookmark(
        ref: 'א',
        book: _book(),
        index: 0,
        createdAt: created,
      );
      final restored = Bookmark.fromJson(original.toJson());
      expect(restored.createdAt, created);
    });

    test('fromJson מטפל ב-createdAt חסר (ברירת מחדל null)', () {
      final json = {
        'ref': 'א',
        'index': 0,
        'book': _book().toJson(),
      };
      final bm = Bookmark.fromJson(json);
      expect(bm.createdAt, isNull);
    });
  });
}
