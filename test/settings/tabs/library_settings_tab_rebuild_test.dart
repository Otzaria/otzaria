import 'dart:async';
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:otzaria/attached_libraries/bloc/attached_libraries_bloc.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/panels/library_settings_panel.dart';
import 'package:otzaria/settings/services/custom_folders/bloc/custom_folders_bloc.dart';
import 'package:otzaria/settings/tabs/library_settings_tab.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:path/path.dart' as p;

import '../../helpers/memory_settings_cache.dart';

class _OpenEngine implements SearchEngine {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('$invocation');
}

class _MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _MockNavigationBloc extends MockBloc<NavigationEvent, NavigationState>
    implements NavigationBloc {}

class _MockAttachedLibrariesBloc
    extends MockBloc<AttachedLibrariesEvent, AttachedLibrariesState>
    implements AttachedLibrariesBloc {}

class _MockIndexingBloc extends MockBloc<IndexingEvent, IndexingState>
    implements IndexingBloc {}

class _MockCustomFoldersBloc
    extends MockBloc<CustomFoldersEvent, CustomFoldersState>
    implements CustomFoldersBloc {}

/// הלשונית נשארת חיה ברקע כשעוברים ממנה למסך הספרייה: איתור ועיון שם אינם
/// בונים אותה מחדש, ורענון הספרייה עדיין מגיע אליה.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late StreamController<LibraryState> libraryStates;
  late List<BlocBase<Object?>> blocs;

  Library libraryWithBook(String title) {
    final category = Category(
      title: 'תנ"ך',
      description: '',
      shortDescription: '',
      order: 1,
      subCategories: const [],
      books: [TextBook(id: 7, title: title, categoryPath: '/תנ"ך')],
      parent: null,
    );
    final library = Library(categories: [category]);
    category.parent = library;
    return library;
  }

  setUpAll(() {
    temp = Directory.systemTemp.createTempSync('library_settings_tab');
    // מצב נייד: הנתיבים בתיקייה הזמנית, ואין חיפוש עותק ספרייה יתום במחשב.
    File(p.join(temp.path, AppPaths.portableMarkerFileName)).createSync();
    AppPaths.debugOverrideResolvedExecutable(p.join(temp.path, 'otzaria.exe'));
    AppPaths.debugOverrideDataRootPath(temp.path);
  });

  tearDownAll(() {
    AppPaths.debugOverrideResolvedExecutable(null);
    AppPaths.debugOverrideDataRootPath(null);
    temp.deleteSync(recursive: true);
  });

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    await Settings.setValue<String>(
      SettingsRepository.keyLibraryPath,
      p.join(temp.path, 'books'),
    );
    libraryStates = StreamController<LibraryState>.broadcast();
    blocs = [];
  });

  tearDown(() async {
    await libraryStates.close();
    for (final bloc in blocs) {
      await bloc.close();
    }
  });

  T mock<T extends BlocBase<S>, S>(T bloc, S state, [Stream<S>? states]) {
    whenListen(bloc, states ?? Stream<S>.empty(), initialState: state);
    blocs.add(bloc);
    return bloc;
  }

  Future<void> pumpTab(
    WidgetTester tester,
    LibraryState initial, {
    IndexingBloc? indexing,
  }) async {
    // מנוע פתוח בלי צורך באיפוס. נוצר בתוך הבדיקה, כדי שההמתנה לו תסתיים
    // ב-pump.
    TantivyDataProvider.instance = TantivyDataProvider.forTesting(
      Future.value(_OpenEngine()),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<LibraryBloc>.value(
                value: mock(_MockLibraryBloc(), initial, libraryStates.stream),
              ),
              BlocProvider<SettingsBloc>.value(
                value: mock(_MockSettingsBloc(), SettingsState.initial()),
              ),
              BlocProvider<NavigationBloc>.value(
                value: mock(
                  _MockNavigationBloc(),
                  const NavigationState(currentScreen: Screen.settings),
                ),
              ),
              BlocProvider<AttachedLibrariesBloc>.value(
                value: mock(
                  _MockAttachedLibrariesBloc(),
                  const AttachedLibrariesState(),
                ),
              ),
              BlocProvider<IndexingBloc>.value(
                value:
                    indexing ??
                    mock<_MockIndexingBloc, IndexingState>(
                      _MockIndexingBloc(),
                      IndexingInitial(),
                    ),
              ),
              BlocProvider<CustomFoldersBloc>.value(
                value: mock(
                  _MockCustomFoldersBloc(),
                  const CustomFoldersState(),
                ),
              ),
            ],
            child: const LibrarySettingsTab(),
          ),
        ),
      ),
    );
    // בדיקת "נדרש איפוס" רצה אחרי הפריים הראשון.
    await tester.pump();
    await tester.pump();
  }

  Future<void> emit(WidgetTester tester, LibraryState state) async {
    libraryStates.add(state);
    // whenListen מעביר את ה-state דרך stream נוסף — שתי פעימות עד ה-builder.
    await tester.pump();
    await tester.pump();
  }

  Widget panel(WidgetTester tester) =>
      tester.widget(find.byType(LibrarySettingsPanel));

  testWidgets('איתור ועיון במסך הספרייה אינם בונים מחדש את הלשונית', (
    tester,
  ) async {
    final library = libraryWithBook('תהילים');
    final base = LibraryState(library: library, currentCategory: library);
    await pumpTab(tester, base);
    final built = panel(tester);
    final category = library.subCategories.single;
    final book = category.books.single;

    var state = base;
    for (final query in ['תה', 'תהי', 'תהילים']) {
      state = state.copyWith(searchQuery: query, isSearching: true);
      await emit(tester, state);
      state = state.copyWith(isSearching: false, searchResults: [book]);
      await emit(tester, state);
    }
    await emit(tester, state.copyWith(previewBook: book));
    await emit(tester, base.copyWith(currentCategory: category));
    await emit(tester, base.copyWith(previewCategory: category));

    expect(identical(panel(tester), built), isTrue);
    expect(find.text('האינדקס לא מעודכן'), findsOneWidget);
  });

  testWidgets('רענון הספרייה עדיין מעדכן את הלשונית', (tester) async {
    final library = libraryWithBook('תהילים');
    final base = LibraryState(library: library, currentCategory: library);
    await pumpTab(tester, base);
    final built = panel(tester);

    final empty = Library(categories: []);
    await emit(tester, base.copyWith(library: empty, currentCategory: empty));
    expect(find.text('הספרייה ריקה – אין ספרים לאינדוקס'), findsOneWidget);

    final refreshed = libraryWithBook('משלי');
    await emit(
      tester,
      base.copyWith(library: refreshed, currentCategory: refreshed),
    );
    expect(find.text('האינדקס לא מעודכן'), findsOneWidget);
    expect(identical(panel(tester), built), isFalse);
  });

  testWidgets('החלפת נתיב שנכשלה אחרי השמירה מציגה את הנתיב השמור', (
    tester,
  ) async {
    final oldPath = p.join(temp.path, 'hebrewbooks-old');
    final newPath = p.join(temp.path, 'hebrewbooks-new');
    await Settings.setValue<String>(
      SettingsRepository.keyHebrewBooksPath,
      oldPath,
    );
    final library = libraryWithBook('תהילים');
    final base = LibraryState(library: library, currentCategory: library);
    await pumpTab(tester, base);
    expect(find.textContaining('hebrewbooks-old'), findsOneWidget);

    // כמו UpdateHebrewBooksPath: הנתיב נשמר, והטעינה מסתיימת בשגיאה בלי
    // ספרייה חדשה.
    await emit(tester, base.copyWith(isLoading: true));
    await Settings.setValue<String>(
      SettingsRepository.keyHebrewBooksPath,
      newPath,
    );
    await emit(tester, base.copyWith(isLoading: false, error: 'שגיאה'));
    expect(find.textContaining('hebrewbooks-new'), findsOneWidget);
    expect(find.textContaining('hebrewbooks-old'), findsNothing);
  });

  testWidgets('החלפת נתיב שנכשלה בזמן רענון מציגה את הנתיב השמור', (
    tester,
  ) async {
    final oldPath = p.join(temp.path, 'hebrewbooks-old');
    final newPath = p.join(temp.path, 'hebrewbooks-new');
    await Settings.setValue<String>(
      SettingsRepository.keyHebrewBooksPath,
      oldPath,
    );
    final library = libraryWithBook('תהילים');
    final base = LibraryState(library: library, currentCategory: library);
    await pumpTab(tester, base);

    // UpdateHebrewBooksPath מתחיל בזמן רענון שכבר בטעינה, והרענון מסתיים
    // לפני שהנתיב נשמר: בסוף הכושל משתנה רק השגיאה.
    await emit(tester, base.copyWith(isLoading: true));
    final refreshed = libraryWithBook('משלי');
    await emit(
      tester,
      LibraryState(library: refreshed, currentCategory: refreshed),
    );
    await Settings.setValue<String>(
      SettingsRepository.keyHebrewBooksPath,
      newPath,
    );
    await emit(
      tester,
      LibraryState(
        library: refreshed,
        currentCategory: refreshed,
        error: 'שגיאה',
      ),
    );
    expect(find.textContaining('hebrewbooks-new'), findsOneWidget);
    expect(find.textContaining('hebrewbooks-old'), findsNothing);
  });

  testWidgets('השהיה מחלונית החיווי מוצגת בשורת האינדקס (issue #3243)', (
    tester,
  ) async {
    final library = libraryWithBook('תהילים');
    final indexingStates = StreamController<IndexingState>();
    addTearDown(indexingStates.close);
    const running = IndexingInProgress(
      booksProcessed: 3,
      totalBooks: 10,
      isCreatingIndex: true,
    );
    final indexing = mock<_MockIndexingBloc, IndexingState>(
      _MockIndexingBloc(),
      running,
      indexingStates.stream,
    );
    Future<void> emitIndexing(IndexingState state) async {
      indexingStates.add(state);
      await tester.pump();
      await tester.pump();
    }

    await pumpTab(
      tester,
      LibraryState(library: library, currentCategory: library),
      indexing: indexing,
    );
    expect(find.text('התקדמות האינדקס: 3/10'), findsOneWidget);
    expect(find.text('המשך'), findsNothing);

    // לחצן "השהה" בחלונית החיווי: IndexingBloc פולט את אותה התקדמות מושהית.
    await emitIndexing(
      const IndexingInProgress(
        booksProcessed: 3,
        totalBooks: 10,
        isCreatingIndex: true,
        isPaused: true,
      ),
    );
    expect(find.text('התקדמות האינדקס: 3/10'), findsNothing);
    expect(find.text('האינדוקס מושהה: 3/10'), findsOneWidget);
    expect(find.text('עצור'), findsOneWidget);

    await tester.tap(find.text('המשך'));
    verify(() => indexing.add(ResumeIndexing())).called(1);
    // ההמשך מחזיר את אותה ריצה עם אותו מונה.
    await emitIndexing(running);
    expect(find.text('התקדמות האינדקס: 3/10'), findsOneWidget);
    expect(find.text('המשך'), findsNothing);

    await emitIndexing(
      const IndexingInProgress(
        booksProcessed: 4,
        totalBooks: 10,
        isScanning: true,
        isPaused: true,
      ),
    );
    expect(find.text('בדיקת הספרים מושהית: 4/10'), findsOneWidget);
    expect(find.text('המשך'), findsOneWidget);

    // "עצור" בזמן השהיה מבטל את הריצה.
    await tester.tap(find.text('עצור'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('עצור').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    verify(() => indexing.add(CancelIndexing())).called(1);
  });

  testWidgets('הגדרות שנפתחות אחרי ההשהיה מציגות אותה (issue #3243)', (
    tester,
  ) async {
    final library = libraryWithBook('תהילים');
    await pumpTab(
      tester,
      LibraryState(library: library, currentCategory: library),
      indexing: mock<_MockIndexingBloc, IndexingState>(
        _MockIndexingBloc(),
        const IndexingInProgress(
          booksProcessed: 3,
          totalBooks: 10,
          isCreatingIndex: true,
          isPaused: true,
        ),
      ),
    );
    expect(find.text('האינדוקס מושהה: 3/10'), findsOneWidget);
    expect(find.text('המשך'), findsOneWidget);
    expect(find.text('עצור'), findsOneWidget);
  });
}
