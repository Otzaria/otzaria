import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/personal_notes/view/personal_notes_screen.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_content_view.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import '../test_helpers/memory_cache_provider.dart';

class MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

class FakePersonalNotesRepository extends PersonalNotesRepository {
  FakePersonalNotesRepository({
    required this.books,
    required this.notesByBookId,
  });

  final List<BookNotesInfo> books;
  final Map<String, List<PersonalNote>> notesByBookId;

  @override
  Future<List<BookNotesInfo>> listBooksWithNotes() async => books;

  @override
  Future<List<PersonalNote>> loadNotes(
    String bookId, {
    int? categoryId,
  }) async {
    return notesByBookId[bookId] ?? const [];
  }
}

class DelayedTocProvider implements LibraryProvider {
  final secondBookToc = Completer<List<TocEntry>?>();
  final calls = <String>[];

  @override
  Future<List<TocEntry>?> getBookToc(
    String title,
    int categoryId,
    String fileType, {
    BookSource preferSource = BookSource.official,
  }) async {
    calls.add(title);
    if (title == 'ספר א') {
      return [TocEntry(text: 'פרק ייחודי של ספר א', index: 0, level: 2)];
    }
    return secondBookToc.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class DelayedPersonalNotesRepository extends PersonalNotesRepository {
  DelayedPersonalNotesRepository({required this.books});

  final List<BookNotesInfo> books;
  final Map<String, Completer<List<PersonalNote>>> requests = {};

  @override
  Future<List<BookNotesInfo>> listBooksWithNotes() async => books;

  @override
  Future<List<PersonalNote>> loadNotes(
    String bookId, {
    int? categoryId,
  }) {
    return requests.putIfAbsent(bookId, Completer.new).future;
  }
}

class RefreshingDelayedPersonalNotesRepository extends PersonalNotesRepository {
  RefreshingDelayedPersonalNotesRepository({required this.bookLists});

  final List<List<BookNotesInfo>> bookLists;
  final Map<String, List<Completer<List<PersonalNote>>>> requests = {};
  int _listCall = 0;

  @override
  Future<List<BookNotesInfo>> listBooksWithNotes() async {
    final index = _listCall < bookLists.length
        ? _listCall
        : bookLists.length - 1;
    _listCall++;
    return bookLists[index];
  }

  @override
  Future<List<PersonalNote>> loadNotes(
    String bookId, {
    int? categoryId,
  }) {
    final request = Completer<List<PersonalNote>>();
    requests.putIfAbsent(bookId, () => []).add(request);
    return request.future;
  }
}

class TrackingPersonalNotesBloc extends PersonalNotesBloc {
  TrackingPersonalNotesBloc({required super.repository});

  int activeStreamSubscriptions = 0;
  int canceledStreamSubscriptions = 0;

  @override
  Stream<PersonalNotesState> get stream => _TrackingStream(
    super.stream,
    onListen: () => activeStreamSubscriptions++,
    onCancel: () {
      activeStreamSubscriptions--;
      canceledStreamSubscriptions++;
    },
  );
}

class _TrackingStream<T> extends Stream<T> {
  _TrackingStream(
    this.source, {
    required this.onListen,
    required this.onCancel,
  });

  final Stream<T> source;
  final void Function() onListen;
  final void Function() onCancel;

  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    onListen();
    return _TrackingSubscription(
      source.listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      ),
      onCancel,
    );
  }
}

class _TrackingSubscription<T> implements StreamSubscription<T> {
  _TrackingSubscription(this.source, this.onCancel);

  final StreamSubscription<T> source;
  final void Function() onCancel;
  bool _canceled = false;

  @override
  Future<void> cancel() {
    if (!_canceled) {
      _canceled = true;
      onCancel();
    }
    return source.cancel();
  }

  @override
  void onData(void Function(T data)? handleData) => source.onData(handleData);

  @override
  void onError(Function? handleError) => source.onError(handleError);

  @override
  void onDone(void Function()? handleDone) => source.onDone(handleDone);

  @override
  void pause([Future<void>? resumeSignal]) => source.pause(resumeSignal);

  @override
  void resume() => source.resume();

  @override
  bool get isPaused => source.isPaused;

  @override
  Future<E> asFuture<E>([E? futureValue]) => source.asFuture(futureValue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  testWidgets('טוען הערות כבר בכניסה הראשונה למסך', (tester) async {
    final note = PersonalNote(
      id: 'note-1',
      bookId: 'ספר בדיקה',
      lineNumber: 12,
      displayTitle: 'כותרת הערה',
      lastKnownLineNumber: null,
      status: PersonalNoteStatus.located,
      content: 'תוכן הערה ראשונית',
      contentPlain: 'תוכן הערה ראשונית',
      contentFormat: PersonalNoteContentFormat.plain,
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 1, 2),
    );
    final repository = FakePersonalNotesRepository(
      books: [
        BookNotesInfo(
          bookId: 'ספר בדיקה',
          noteCount: 1,
          lastUpdated: DateTime(2025, 1, 2),
        ),
      ],
      notesByBookId: {
        'ספר בדיקה': [note],
      },
    );
    final personalNotesBloc = PersonalNotesBloc(repository: repository);
    final settingsBloc = SettingsBloc(repository: SettingsRepository());
    final libraryBloc = MockLibraryBloc();
    final libraryState = LibraryState(
      library: Library(categories: []),
      isLoading: false,
      currentCategory: null,
    );

    whenListen(
      libraryBloc,
      const Stream<LibraryState>.empty(),
      initialState: libraryState,
    );

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
          BlocProvider<LibraryBloc>.value(value: libraryBloc),
          BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: Scaffold(
            body: PersonalNotesManagerScreen(repository: repository),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('ספר בדיקה'), findsOneWidget);
    expect(find.text('כותרת הערה'), findsOneWidget);
    expect(find.text('תוכן הערה ראשונית'), findsOneWidget);
  });

  testWidgets('טוען שני ספרים בסדר ומציג כל הערה תחת ספרה', (tester) async {
    PersonalNote note(String id, String bookId, String content) => PersonalNote(
      id: id,
      bookId: bookId,
      lineNumber: 1,
      displayTitle: 'כותרת $bookId',
      lastKnownLineNumber: null,
      status: PersonalNoteStatus.located,
      content: content,
      contentPlain: content,
      contentFormat: PersonalNoteContentFormat.plain,
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 1, 2),
    );

    final repository = DelayedPersonalNotesRepository(
      books: [
        BookNotesInfo(
          bookId: 'ספר א',
          noteCount: 1,
          lastUpdated: DateTime(2025, 1, 2),
        ),
        BookNotesInfo(
          bookId: 'ספר ב',
          noteCount: 1,
          lastUpdated: DateTime(2025, 1, 2),
        ),
      ],
    );
    final personalNotesBloc = PersonalNotesBloc(repository: repository);
    final settingsBloc = SettingsBloc(repository: SettingsRepository());
    final libraryBloc = MockLibraryBloc();
    final libraryState = LibraryState(
      library: Library(categories: []),
      isLoading: false,
      currentCategory: null,
    );

    whenListen(
      libraryBloc,
      const Stream<LibraryState>.empty(),
      initialState: libraryState,
    );
    addTearDown(personalNotesBloc.close);
    addTearDown(settingsBloc.close);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
          BlocProvider<LibraryBloc>.value(value: libraryBloc),
          BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: Scaffold(
            body: PersonalNotesManagerScreen(repository: repository),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    expect(repository.requests.keys, contains('ספר א'));
    expect(repository.requests.keys, isNot(contains('ספר ב')));

    repository.requests['ספר א']!.complete([
      note('note-a', 'ספר א', 'תוכן א ייחודי'),
    ]);
    for (var i = 0; i < 10 && repository.requests['ספר ב'] == null; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(repository.requests.keys, contains('ספר ב'));

    repository.requests['ספר ב']!.complete([
      note('note-b', 'ספר ב', 'תוכן ב ייחודי'),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('תוכן א ייחודי'), findsOneWidget);
    expect(find.text('תוכן ב ייחודי'), findsOneWidget);

    final firstBook = tester.getTopLeft(find.text('ספר א')).dy;
    final firstNote = tester.getTopLeft(find.text('תוכן א ייחודי')).dy;
    final secondBook = tester.getTopLeft(find.text('ספר ב')).dy;
    final secondNote = tester.getTopLeft(find.text('תוכן ב ייחודי')).dy;
    expect(firstBook, lessThan(firstNote));
    expect(firstNote, lessThan(secondBook));
    expect(secondBook, lessThan(secondNote));
  });

  testWidgets('רענון מבטל מאזין תקוע ומתחיל רצף חדש', (
    tester,
  ) async {
    BookNotesInfo book(String id) => BookNotesInfo(
      bookId: id,
      noteCount: 0,
      lastUpdated: DateTime(2025, 1, 2),
    );

    final repository = RefreshingDelayedPersonalNotesRepository(
      bookLists: [
        [book('ספר א'), book('ספר ב')],
        [book('ספר ג')],
      ],
    );
    final personalNotesBloc = TrackingPersonalNotesBloc(
      repository: repository,
    );
    final settingsBloc = SettingsBloc(repository: SettingsRepository());
    final libraryBloc = MockLibraryBloc();
    whenListen(
      libraryBloc,
      const Stream<LibraryState>.empty(),
      initialState: LibraryState(
        library: Library(categories: []),
        isLoading: false,
        currentCategory: null,
      ),
    );
    addTearDown(personalNotesBloc.close);
    addTearDown(settingsBloc.close);
    addTearDown(() {
      for (final requests in repository.requests.values) {
        for (final request in requests) {
          if (!request.isCompleted) request.complete(const []);
        }
      }
    });

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
          BlocProvider<LibraryBloc>.value(value: libraryBloc),
          BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: Scaffold(
            body: PersonalNotesManagerScreen(repository: repository),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(repository.requests['ספר א'], hasLength(1));
    final cancellationsBeforeRefresh =
        personalNotesBloc.canceledStreamSubscriptions;

    await tester.tap(find.byTooltip('רענן'));
    await tester.pump();
    await tester.pump();
    for (var i = 0; i < 10 && repository.requests['ספר ג'] == null; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }

    expect(repository.requests['ספר ב'], isNull);
    expect(repository.requests['ספר ג'], hasLength(1));
    expect(
      personalNotesBloc.canceledStreamSubscriptions,
      greaterThan(cancellationsBeforeRefresh),
    );
    repository.requests['ספר א']!.single.complete(const []);
    repository.requests['ספר ג']!.single.complete(const []);
  });

  testWidgets('dispose מבטל מאזין לטעינה שנתקעה', (tester) async {
    final repository = DelayedPersonalNotesRepository(
      books: [
        BookNotesInfo(
          bookId: 'ספר תקוע',
          noteCount: 0,
          lastUpdated: DateTime(2025, 1, 2),
        ),
      ],
    );
    final personalNotesBloc = TrackingPersonalNotesBloc(
      repository: repository,
    );
    final settingsBloc = SettingsBloc(repository: SettingsRepository());
    final libraryBloc = MockLibraryBloc();
    whenListen(
      libraryBloc,
      const Stream<LibraryState>.empty(),
      initialState: LibraryState(
        library: Library(categories: []),
        isLoading: false,
        currentCategory: null,
      ),
    );
    addTearDown(personalNotesBloc.close);
    addTearDown(settingsBloc.close);
    addTearDown(() {
      final request = repository.requests['ספר תקוע'];
      if (request != null && !request.isCompleted) request.complete(const []);
    });

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
          BlocProvider<LibraryBloc>.value(value: libraryBloc),
          BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: Scaffold(
            body: PersonalNotesManagerScreen(repository: repository),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(repository.requests['ספר תקוע'], isNotNull);
    expect(personalNotesBloc.activeStreamSubscriptions, greaterThan(0));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(personalNotesBloc.activeStreamSubscriptions, 0);
    repository.requests['ספר תקוע']!.complete(const []);
  });

  Future<void> pumpScreenWithManyNotes(
    WidgetTester tester, {
    int books = 1,
    required int count,
  }) async {
    String bookIdAt(int b) => books == 1 ? 'ספר עמוס' : 'ספר עמוס $b';
    final notesByBookId = {
      for (var b = 0; b < books; b++)
        bookIdAt(b): [
          for (var i = 0; i < count; i++)
            PersonalNote(
              id: 'note-$b-$i',
              bookId: bookIdAt(b),
              lineNumber: i,
              displayTitle: 'כותרת $i',
              lastKnownLineNumber: null,
              status: PersonalNoteStatus.located,
              content: '[{"insert":"תוכן הערה מספר $i\\n"}]',
              contentPlain: 'תוכן הערה מספר $i',
              contentFormat: PersonalNoteContentFormat.quillDelta,
              createdAt: DateTime(2025, 1, 1),
              updatedAt: DateTime(2025, 1, 2),
            ),
        ],
    };
    final repository = FakePersonalNotesRepository(
      books: [
        for (var b = 0; b < books; b++)
          BookNotesInfo(
            bookId: bookIdAt(b),
            noteCount: count,
            lastUpdated: DateTime(2025, 1, 2),
          ),
      ],
      notesByBookId: notesByBookId,
    );
    final personalNotesBloc = PersonalNotesBloc(repository: repository);
    final settingsBloc = SettingsBloc(repository: SettingsRepository());
    final libraryBloc = MockLibraryBloc();
    whenListen(
      libraryBloc,
      const Stream<LibraryState>.empty(),
      initialState: LibraryState(
        library: Library(categories: []),
        isLoading: false,
        currentCategory: null,
      ),
    );
    addTearDown(personalNotesBloc.close);
    addTearDown(settingsBloc.close);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
          BlocProvider<LibraryBloc>.value(value: libraryBloc),
          BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: Scaffold(
            body: PersonalNotesManagerScreen(repository: repository),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('ספר עם מאות הערות בונה רק את הכרטיסים שבתצוגה', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpScreenWithManyNotes(tester, count: 300);

    final built = find
        .byType(
          PersonalNoteContentView,
          skipOffstage: false,
        )
        .evaluate()
        .length;
    expect(built, greaterThan(0));
    expect(built, lessThan(60));
  });

  testWidgets('מאות ספרים עם הערה אחת בונים רק את הקבוצות שבתצוגה', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpScreenWithManyNotes(tester, books: 300, count: 1);

    int builtCount(Finder finder) => finder.evaluate().length;
    final headers = builtCount(
      find.byIcon(
        FluentIcons.text_align_right_24_regular,
        skipOffstage: false,
      ),
    );
    final tocBuilders = builtCount(
      find.byWidgetPredicate(
        (w) => w is FutureBuilder,
        skipOffstage: false,
      ),
    );
    final cards = builtCount(
      find.byType(PersonalNoteContentView, skipOffstage: false),
    );
    expect(headers, inInclusiveRange(1, 20));
    expect(tocBuilders, inInclusiveRange(1, 20));
    expect(cards, inInclusiveRange(1, 20));
  });

  testWidgets(
    'סינון ופריסה מחדש אינם מציגים מיקום מספר אחר בזמן טעינת תוכן העניינים',
    (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final provider = DelayedTocProvider();
      final books = [
        TextBook(title: 'ספר א', categoryId: 1),
        TextBook(title: 'ספר ב', categoryId: 2),
      ];
      LibraryProviderManager.instance.seedMappingsForTesting(
        mapping: {
          for (final book in books) BookCompositeKey.fromBook(book)!: provider,
        },
        providers: [provider],
      );
      addTearDown(LibraryProviderManager.instance.resetForTesting);
      addTearDown(() {
        if (!provider.secondBookToc.isCompleted) {
          provider.secondBookToc.complete([]);
        }
      });

      PersonalNote note(String bookId, int index, String content) =>
          PersonalNote(
            id: '$bookId-$index',
            bookId: bookId,
            lineNumber: index + 1,
            displayTitle: 'כותרת $bookId $index',
            lastKnownLineNumber: null,
            status: PersonalNoteStatus.located,
            content: content,
            contentPlain: content,
            contentFormat: PersonalNoteContentFormat.plain,
            createdAt: DateTime(2025, 1, 1),
            updatedAt: DateTime(2025, 1, 2),
          );
      final repository = FakePersonalNotesRepository(
        books: [
          BookNotesInfo(
            bookId: 'ספר א',
            noteCount: 40,
            lastUpdated: DateTime(2025),
          ),
          BookNotesInfo(
            bookId: 'ספר ב',
            noteCount: 1,
            lastUpdated: DateTime(2025),
          ),
        ],
        notesByBookId: {
          'ספר א': [
            for (var i = 0; i < 40; i++)
              note('ספר א', i, i == 0 ? 'מחט' : 'תוכן אחר'),
          ],
          'ספר ב': [note('ספר ב', 0, 'מחט')],
        },
      );
      final personalNotesBloc = PersonalNotesBloc(repository: repository);
      final settingsBloc = SettingsBloc(repository: SettingsRepository());
      final libraryBloc = MockLibraryBloc();
      whenListen(
        libraryBloc,
        const Stream<LibraryState>.empty(),
        initialState: LibraryState(
          library: Library(categories: [])..books.addAll(books),
          isLoading: false,
          currentCategory: null,
        ),
      );
      addTearDown(personalNotesBloc.close);
      addTearDown(settingsBloc.close);
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
            BlocProvider<LibraryBloc>.value(value: libraryBloc),
          ],
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: PersonalNotesManagerScreen(repository: repository),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(provider.calls, ['ספר א']);

      await tester.enterText(find.byType(EditableText).first, 'מחט');
      await tester.pumpAndSettle();
      expect(provider.calls, ['ספר א', 'ספר ב']);
      final secondTitle = find.text('כותרת ספר ב 0');
      final secondCard = find
          .ancestor(of: secondTitle, matching: find.byType(Column))
          .first;
      void expectNoForeignLocation() {
        expect(secondTitle, findsOneWidget);
        expect(
          find.descendant(
            of: secondCard,
            matching: find.text('פרק ייחודי של ספר א'),
          ),
          findsNothing,
        );
      }

      expectNoForeignLocation();
      tester.view.physicalSize = const Size(700, 800);
      await tester.pumpAndSettle();
      expectNoForeignLocation();

      provider.secondBookToc.complete([
        TocEntry(text: 'פרק ייחודי של ספר ב', index: 0, level: 2),
      ]);
      await tester.pumpAndSettle();
      expectNoForeignLocation();
      expect(
        find.descendant(
          of: secondCard,
          matching: find.text('פרק ייחודי של ספר ב'),
        ),
        findsOneWidget,
      );
      expect(provider.calls, ['ספר א', 'ספר ב']);
    },
  );

  testWidgets('כרטיסי ההערות נשארים שלושה בשורה ובסדר השורות', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpScreenWithManyNotes(tester, count: 40);

    final first = tester.getTopLeft(find.text('כותרת 0'));
    final second = tester.getTopLeft(find.text('כותרת 1'));
    final third = tester.getTopLeft(find.text('כותרת 2'));
    final fourth = tester.getTopLeft(find.text('כותרת 3'));
    expect(second.dy, first.dy);
    expect(third.dy, first.dy);
    expect({first.dx, second.dx, third.dx}, hasLength(3));
    expect(fourth.dy, greaterThan(first.dy));
    expect(fourth.dx, first.dx);

    await tester.scrollUntilVisible(
      find.text('כותרת 39'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('כותרת 39'), findsOneWidget);
  });

  group('noteWithinDateRange - סינון לפי טווח תאריכים', () {
    PersonalNote noteUpdatedAt(DateTime updatedAt) => PersonalNote(
      id: 'n',
      bookId: 'ספר',
      lineNumber: 1,
      lastKnownLineNumber: null,
      status: PersonalNoteStatus.located,
      content: 'תוכן',
      contentPlain: 'תוכן',
      contentFormat: PersonalNoteContentFormat.plain,
      createdAt: DateTime(2025, 1, 1),
      updatedAt: updatedAt,
    );

    test('טווח null כולל כל הערה', () {
      expect(
        noteWithinDateRange(noteUpdatedAt(DateTime(2020, 5, 5)), null),
        isTrue,
      );
    });

    test('הערה בתוך הטווח נכללת', () {
      final range = DateTimeRange(
        start: DateTime(2025, 3, 1),
        end: DateTime(2025, 3, 31),
      );
      expect(
        noteWithinDateRange(noteUpdatedAt(DateTime(2025, 3, 15)), range),
        isTrue,
      );
    });

    test('הערה לפני תחילת הטווח לא נכללת', () {
      final range = DateTimeRange(
        start: DateTime(2025, 3, 1),
        end: DateTime(2025, 3, 31),
      );
      expect(
        noteWithinDateRange(noteUpdatedAt(DateTime(2025, 2, 28)), range),
        isFalse,
      );
    });

    test('הערה אחרי סוף הטווח לא נכללת', () {
      final range = DateTimeRange(
        start: DateTime(2025, 3, 1),
        end: DateTime(2025, 3, 31),
      );
      expect(
        noteWithinDateRange(noteUpdatedAt(DateTime(2025, 4, 1)), range),
        isFalse,
      );
    });

    test('הגבולות נכללים (כולל קצוות), בהתעלם מהשעה', () {
      final range = DateTimeRange(
        start: DateTime(2025, 3, 1),
        end: DateTime(2025, 3, 31),
      );
      // קצה תחתון, אפילו עם שעה מאוחרת באותו יום
      expect(
        noteWithinDateRange(noteUpdatedAt(DateTime(2025, 3, 1, 23, 59)), range),
        isTrue,
      );
      // קצה עליון, אפילו עם שעה מאוחרת באותו יום
      expect(
        noteWithinDateRange(
          noteUpdatedAt(DateTime(2025, 3, 31, 23, 59)),
          range,
        ),
        isTrue,
      );
    });
  });
}
