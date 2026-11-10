import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/migration/database/journal_mode.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';

import '../../../test_helpers/memory_cache_provider.dart';
import '../../../test_helpers/stub_personal_notes_bloc.dart';
import '../../../test_helpers/stub_settings_bloc.dart';

const _content = [
  '(ח) ונח מצא חן בעיני ה׳',
  '(ט) אלה תולדת נח נח איש צדיק',
  '(י) ויולד נח שלשה בנים',
];

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  @override
  final TextBookRepository repository = _Repository();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Repository implements TextBookRepository {
  @override
  Future<List<Link>> getBookLinksInRange(
    TextBook book, {
    required int startIndex,
    required int endIndex,
    Iterable<String>? targetBookTitles,
  }) async => const [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _failWorkerStartup() => throw StateError('worker unavailable');

const _busyMessage =
    'סמני החלוקה והכותרות לא נטענו בגלל עומס. לחצו כדי לנסות שוב.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late StubSettingsBloc settings;
  late StubPersonalNotesBloc notes;
  late _TestTextBookBloc bloc;
  final tabs = <TextBookTab>[];

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    temporary = await Directory.systemTemp.createTemp('section_admission');
    AppPaths.debugOverrideDataRootPath(temporary.path);
    final dbPath = '${temporary.path}/seforim.db';
    final database = MyDatabase.withPath(dbPath);
    final raw = await database.database;
    raw.execute(
      "INSERT INTO category (id, title, level) VALUES (7, 'כללי', 0)",
    );
    raw.execute("INSERT INTO source (id, name) VALUES (1, 'אוצריא')");
    raw.execute(
      "INSERT INTO book (id, categoryId, sourceId, title, totalLines) VALUES (1, 7, 1, 'ספר', 3)",
    );
    for (var i = 0; i < _content.length; i++) {
      raw.execute(
        'INSERT INTO line (id, bookId, lineIndex, content) VALUES (?, 1, ?, ?)',
        [i + 1, i, _content[i]],
      );
    }
    raw.execute(
      "INSERT INTO tocText (id, text) VALUES (1, 'כותרת מהמסד'), (2, 'סעיף בדיקה')",
    );
    raw.execute(
      "INSERT INTO alt_toc_structure (id, bookId, key) VALUES (1, 1, 'Topic'), (2, 1, 'Seifim')",
    );
    raw.execute(
      'INSERT INTO alt_toc_entry (id, structureId, textId, level, lineId, hasChildren) VALUES (1, 1, 1, 1, 2, 0), (2, 2, 2, 1, 2, 0)',
    );
    database.close();
    await normalizeJournalModeForReadOnly(dbPath);
    await Settings.setValue<String>(
      SettingsRepository.keyDbEffectivePath,
      dbPath,
    );
    await SqliteDataProvider.instance.dispose();
    await SqliteDataProvider.instance.initialize();
    DatabaseLibraryProvider.instance.clearCache();
    await LibraryProviderManager.instance.resolveProviderForBook(
      'ספר',
      categoryId: 7,
      fileType: 'txt',
    );
    settings = StubSettingsBloc(SettingsState.initial());
    notes = StubPersonalNotesBloc(const PersonalNotesState.initial());
    bloc = _TestTextBookBloc(
      TextBookLoaded(
        book: TextBook(id: 1, title: 'ספר', categoryId: 7),
        content: _content,
        fontSize: 18,
        showLeftPane: false,
        showSplitView: false,
        showPageShapeView: false,
        activeCommentators: const [],
        commentatorGroups: const [],
        availableCommentators: const [],
        links: const [],
        visibleLinks: const [],
        linksByLine: const {},
        tableOfContents: const [],
        removeNikud: false,
        visibleIndices: const [0],
        selectedIndex: 0,
        selectedIndices: const {0},
        pinLeftPane: false,
        searchText: '',
      ),
    );
  });

  tearDown(() async {
    UiSnack.hide();
    DbReadWorker.maxPendingWorkerReads = 64;
    DbReadWorker.workerSetUpForTesting = null;
    DbReadWorker.stallTimeout = const Duration(seconds: 10);
    DbReadWorker.admissionTimeout = const Duration(seconds: 10);
    DbReadWorker.disposeForTesting();
    await SqliteDataProvider.instance.dispose();
    await UserBooksDatabaseHolder.instance.close();
    DatabaseLibraryProvider.instance.clearCache();
    LibraryProviderManager.instance.resetForTesting();
    for (final tab in tabs) {
      tab.dispose();
    }
    tabs.clear();
    await bloc.close();
    await settings.close();
    await notes.close();
    AppPaths.debugOverrideDataRootPath(null);
    await temporary.delete(recursive: true);
  });

  TextBookTab tab({
    String? versionTitle,
    BookSource source = BookSource.official,
  }) {
    final value = TextBookTab(
      book: TextBook(
        id: 1,
        title: 'ספר',
        categoryId: 7,
        source: source,
        versionTitle: versionTitle,
      ),
      index: 0,
    );
    tabs.add(value);
    return value;
  }

  Future<void> mount(WidgetTester tester, TextBookTab value) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: AppWindowKeys.current.navigator,
        locale: const Locale('he', 'IL'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('he', 'IL')],
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: bloc),
            BlocProvider<PersonalNotesBloc>.value(value: notes),
            BlocProvider<SettingsBloc>.value(value: settings),
          ],
          child: Scaffold(
            body: CombinedView(
              data: _content,
              tab: value,
              openBookCallback: (_) {},
              openLeftPaneTab: (_, {searchText}) {},
              textSize: 18,
              showCommentaryAsExpansionTiles: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> finishRead(WidgetTester tester) async {
    final deadline = Stopwatch()..start();
    do {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    } while (DbReadWorker.hasPendingReads &&
        deadline.elapsed < const Duration(seconds: 3));
    expect(DbReadWorker.hasPendingReads, isFalse);
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    UiSnack.hide();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('עומס מתמשך נתפס ומאפשר שחזור כותרות בלחיצה בלי החלפת לשונית', (
    tester,
  ) async {
    DbReadWorker.maxPendingWorkerReads = 0;
    await mount(tester, tab());
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.takeException(), isNull);
    expect(find.text(_busyMessage), findsOneWidget);
    expect(
      find.textContaining('כותרת מהמסד', findRichText: true),
      findsNothing,
    );
    DbReadWorker.maxPendingWorkerReads = 64;
    await tester.tap(find.text(_busyMessage));
    await finishRead(tester);
    expect(
      find.textContaining('כותרת מהמסד', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('סעיף בדיקה', findRichText: true),
      findsOneWidget,
    );
    await unmount(tester);
  });

  testWidgets('ניסיון אוטומטי יחיד מתאושש לאחר שהמכסה משתחררת', (tester) async {
    DbReadWorker.maxPendingWorkerReads = 0;
    await mount(tester, tab());
    DbReadWorker.maxPendingWorkerReads = 64;
    final sent = DbReadWorker.sentMessageCount;
    await tester.pump(const Duration(seconds: 1));
    await finishRead(tester);
    expect(DbReadWorker.sentMessageCount, sent + 1);
    expect(tester.takeException(), isNull);
    expect(
      find.textContaining('כותרת מהמסד', findRichText: true),
      findsOneWidget,
    );
    expect(find.text(_busyMessage), findsNothing);
    expect(
      find.textContaining('סעיף בדיקה', findRichText: true),
      findsOneWidget,
    );
    await unmount(tester);
  });

  testWidgets('עומס מתמשך אינו יוצר לולאת ניסיונות ברקע', (tester) async {
    DbReadWorker.maxPendingWorkerReads = 0;
    await mount(tester, tab());
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text(_busyMessage), findsOneWidget);
    DbReadWorker.maxPendingWorkerReads = 64;
    final sent = DbReadWorker.sentMessageCount;
    await tester.pump(const Duration(seconds: 30));
    await finishRead(tester);
    expect(DbReadWorker.sentMessageCount, sent);
    expect(
      find.textContaining('כותרת מהמסד', findRichText: true),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('לחיצה על הודעת עומס ישנה אינה טוענת את הלשונית הקודמת', (
    tester,
  ) async {
    DbReadWorker.maxPendingWorkerReads = 0;
    await mount(tester, tab());
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text(_busyMessage), findsOneWidget);
    await mount(tester, tab(versionTitle: 'אחרת'));
    DbReadWorker.maxPendingWorkerReads = 64;
    final sent = DbReadWorker.sentMessageCount;
    await tester.tap(find.text(_busyMessage));
    await tester.pump(const Duration(seconds: 1));
    await finishRead(tester);
    expect(DbReadWorker.sentMessageCount, sent);
    expect(
      find.textContaining('כותרת מהמסד', findRichText: true),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  for (final alternative in [true, false]) {
    testWidgets(
      'החלפה ל${alternative ? "מהדורה" : "מקור מצורף"} מבטלת ניסיון ממתין ותוצאה ישנה',
      (tester) async {
        DbReadWorker.maxPendingWorkerReads = 0;
        await mount(tester, tab());
        await mount(
          tester,
          tab(
            versionTitle: alternative ? 'אחרת' : null,
            source: alternative
                ? BookSource.official
                : BookSource.attached('other'),
          ),
        );
        DbReadWorker.maxPendingWorkerReads = 64;
        final sent = DbReadWorker.sentMessageCount;
        await tester.pump(const Duration(seconds: 1));
        await finishRead(tester);
        expect(DbReadWorker.sentMessageCount, sent);
        expect(
          find.textContaining('כותרת מהמסד', findRichText: true),
          findsNothing,
        );
        expect(find.text(_busyMessage), findsNothing);
        expect(tester.takeException(), isNull);
        await unmount(tester);
      },
    );
  }

  testWidgets('תוצאה ממתינה בתור fallback אינה מוחזרת ללשונית שהוחלפה', (
    tester,
  ) async {
    DbReadWorker.disposeForTesting();
    DbReadWorker.workerSetUpForTesting = _failWorkerStartup;
    final gates = [Completer<void>(), Completer<void>()];
    final held = [
      for (final gate in gates)
        DbReadWorker.trackFallbackRead(() => gate.future),
    ];
    try {
      await mount(tester, tab());
      final deadline = Stopwatch()..start();
      while (DbReadWorker.resourceUsage.queuedReads == 0 &&
          deadline.elapsed < const Duration(seconds: 3)) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(DbReadWorker.resourceUsage.queuedReads, 1);
      await mount(tester, tab(versionTitle: 'אחרת'));
    } finally {
      for (final gate in gates) {
        gate.complete();
      }
    }
    await Future.wait(held);
    await finishRead(tester);
    expect(
      find.textContaining('כותרת מהמסד', findRichText: true),
      findsNothing,
    );
    expect(find.text(_busyMessage), findsNothing);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('dispose מבטל ניסיון ממתין בלי קריאה נוספת', (tester) async {
    DbReadWorker.maxPendingWorkerReads = 0;
    await mount(tester, tab());
    await tester.pumpWidget(const SizedBox.shrink());
    DbReadWorker.maxPendingWorkerReads = 64;
    final sent = DbReadWorker.sentMessageCount;
    await tester.pump(const Duration(seconds: 1));
    await finishRead(tester);
    expect(DbReadWorker.sentMessageCount, sent);
    expect(tester.takeException(), isNull);
  });
}
