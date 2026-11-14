import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';

import '../../helpers/memory_settings_cache.dart';

/// התצוגה המקדימה בספרייה מציגה ספר שהמשתמש לא בחר (issue #957):
/// ניווט "חזור"/"בית" משאיר בפאנל את הספר מהתיקייה הקודמת. הטסטים כאן
/// מקבעים את החוזה ההפוך — מעבר תיקייה מנקה את הספר, והפאנל מציג את התיקייה
/// שאליה הגיעו (issue #1173).
Category _category(
  String title, {
  List<Book> books = const [],
  List<Category> subCategories = const [],
}) {
  final category = Category(
    title: title,
    description: '',
    shortDescription: '',
    order: 0,
    subCategories: List.of(subCategories),
    books: List.of(books),
    parent: null,
  );
  for (final sub in category.subCategories) {
    sub.parent = category;
  }
  return category;
}

Library _library(List<Category> categories) {
  final library = Library(categories: categories);
  for (final sub in library.subCategories) {
    sub.parent = library;
  }
  return library;
}

void main() {
  late Category chasidut;
  late Category halacha;
  late Library library;
  late TextBook firstChasidutBook;
  late TextBook halachaBook;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Settings.init(cacheProvider: MemorySettingsCache());

    firstChasidutBook = TextBook(title: 'תניא', order: 1);
    halachaBook = TextBook(title: 'שולחן ערוך', order: 1);
    chasidut = _category(
      'חסידות',
      books: [
        firstChasidutBook,
        TextBook(title: 'נועם אלימלך', order: 2),
      ],
    );
    halacha = _category('הלכה', books: [halachaBook]);
    library = _library([chasidut, halacha]);
  });

  group('LibraryState.previewBook — שורש הבאג', () {
    test('העברת null ל-copyWith אינה מנקה את הספר המוצג', () {
      final withPreview = const LibraryState().copyWith(
        previewBook: firstChasidutBook,
      );

      expect(
        withPreview.copyWith(previewBook: null).previewBook,
        firstChasidutBook,
        reason: 'previewBook ?? this.previewBook — null נבלע, ולכן נדרש דגל',
      );
    });

    test('copyWith רגיל אינו מאבד את הספר המוצג', () {
      final withPreview = const LibraryState().copyWith(
        previewBook: firstChasidutBook,
      );

      expect(
        withPreview.copyWith(isSearching: true).previewBook,
        firstChasidutBook,
        reason: 'רק מעבר תיקייה מנקה — לא כל עדכון state',
      );
    });

    test('clearPreviewBook מנקה את הספר המוצג', () {
      final withPreview = const LibraryState().copyWith(
        previewBook: firstChasidutBook,
      );

      expect(withPreview.copyWith(clearPreviewBook: true).previewBook, isNull);
    });
  });

  group('LibraryBloc — מעבר תיקייה מנקה את התצוגה המקדימה', () {
    late LibraryBloc bloc;

    setUp(() {
      bloc = LibraryBloc();
      // מצב פתיחה: הספרייה נטענה, המשתמש נמצא בקטגוריה ובחר בה ספר.
      bloc.emit(
        const LibraryState().copyWith(
          library: library,
          currentCategory: chasidut,
          previewBook: firstChasidutBook,
        ),
      );
    });

    tearDown(() async {
      await bloc.close();
    });

    test(
      '"בית" (NavigateToCategory לשורש) מנקה את הספר מהתיקייה הקודמת',
      () async {
        // הרצף שמסך הספרייה שולח ב-_handleNavigateHome.
        bloc.add(NavigateToCategory(library));
        bloc.add(const UpdateSearchQuery(''));
        bloc.add(const SearchBooks());
        await Future<void>.delayed(Duration.zero);

        expect(bloc.state.currentCategory, library);
        expect(
          bloc.state.previewBook,
          isNull,
          reason: 'הספר שנבחר בחסידות אינו מוצג בשורש הספרייה',
        );
        expect(bloc.state.previewCategory, library);
      },
    );

    test('"חזור" (NavigateUp) מנקה את הספר מהתיקייה הקודמת', () async {
      // הרצף שמסך הספרייה שולח ב-_handleNavigateUp.
      final searchCleared = bloc.stream.firstWhere(
        (state) => state.searchQuery == null,
      );
      bloc.add(NavigateUp());
      bloc.add(const SearchBooks());
      await searchCleared;

      expect(bloc.state.currentCategory, library);
      expect(bloc.state.previewBook, isNull);
      expect(bloc.state.previewCategory, library);
    });

    test('כניסה לקטגוריה אחרת אינה גוררת את הספר הקודם', () async {
      bloc.add(NavigateToCategory(halacha));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.currentCategory, halacha);
      expect(bloc.state.previewBook, isNull);
      expect(
        bloc.state.previewCategory,
        halacha,
        reason: 'התיקייה שנכנסו אליה מוצגת, ולא הספר הראשון שבה',
      );
    });

    test('בחירת ספר אחרי הניווט עדיין עובדת', () async {
      bloc.add(NavigateToCategory(halacha));
      bloc.add(SelectBookForPreview(halachaBook));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.previewBook, halachaBook);
    });

    test('NavigateUp מהשורש אינו משנה דבר', () async {
      bloc.emit(
        bloc.state.copyWith(
          currentCategory: library,
          previewBook: firstChasidutBook,
          searchQuery: 'תניא',
        ),
      );

      bloc.add(NavigateUp());
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.currentCategory, library);
      expect(bloc.state.searchQuery, 'תניא');
      expect(
        bloc.state.previewBook,
        firstChasidutBook,
        reason: 'אין מעבר תיקייה ולכן הספר המוצג נשאר נבחר',
      );
    });

    for (final (name, home) in [
      ('"בית" בשורש', true),
      ('ניקוי החיפוש', false),
    ]) {
      test(
        '$name אחרי חיפוש מנקה את הספר מתוצאות החיפוש (issue #957)',
        () async {
          bloc.emit(
            bloc.state.copyWith(
              currentCategory: library,
              searchQuery: 'תניא',
              searchResults: [firstChasidutBook],
              previewBook: firstChasidutBook,
            ),
          );

          // הרצפים של _handleNavigateHome ושל onClear בשדה החיפוש.
          if (home) bloc.add(NavigateToCategory(library));
          bloc.add(const UpdateSearchQuery(''));
          bloc.add(const SearchBooks());
          await Future<void>.delayed(Duration.zero);

          expect(bloc.state.previewBook, isNull);
          expect(bloc.state.previewCategory, library);
        },
      );
    }

    test('"בית" בשורש מחזיר את התצוגה המקדימה מתיקייה שנבחרה לשורש '
        '(issue #4626)', () async {
      // תצוגת רשת: לחיצה אחת על תיקייה בוחרת אותה לתצוגה המקדימה בלי לנווט.
      bloc.emit(
        LibraryState(
          library: library,
          currentCategory: library,
          previewCategory: chasidut,
        ),
      );

      bloc.add(NavigateToCategory(library));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.currentCategory, library);
      expect(bloc.state.previewCategory, library);
      expect(bloc.state.previewBook, isNull);
    });

    test('NavigateToCategory לקטגוריה הפתוחה מנקה ספר שנבחר בה', () async {
      bloc.emit(
        bloc.state.copyWith(
          currentCategory: library,
          previewBook: firstChasidutBook,
        ),
      );

      bloc.add(NavigateToCategory(library));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.currentCategory, library);
      expect(bloc.state.previewBook, isNull);
      expect(bloc.state.previewCategory, library);
    });
  });
}
