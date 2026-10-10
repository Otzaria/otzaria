import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_changes.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/personal_notes/services/personal_notes_service.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/page_shape/simple_text_viewer.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../test_helpers/memory_cache_provider.dart';

/// רגרסיה: בצורת הדף, הערה על מפרש שנמחקה מחלונית ההערות השאירה את הטקסט
/// מודגש — טור המפרש החזיק עותק של ההערות שנטען רק בפתיחה ואחרי יצירה.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  late _TestTextBookBloc textBookBloc;
  late _TestPersonalNotesBloc personalNotesBloc;
  late _TestSettingsBloc settingsBloc;

  setUp(() {
    textBookBloc = _TestTextBookBloc(_loadedState());
    personalNotesBloc = _TestPersonalNotesBloc(_notesState('ספר בדיקה', []));
    settingsBloc = _TestSettingsBloc(SettingsState.initial());
  });

  tearDown(() async {
    await textBookBloc.close();
    await personalNotesBloc.close();
    await settingsBloc.close();
  });

  Widget harness(Widget viewer) => MaterialApp(
    home: MultiBlocProvider(
      providers: [
        BlocProvider<TextBookBloc>.value(value: textBookBloc),
        BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
        BlocProvider<SettingsBloc>.value(value: settingsBloc),
      ],
      child: Scaffold(body: viewer),
    ),
  );

  Future<void> pumpCommentary(
    WidgetTester tester,
    PersonalNotesRepository repository, {
    TextBook? reportBook,
  }) async {
    await tester.pumpWidget(
      harness(
        SimpleTextViewer(
          content: const ['שורת מפרש'],
          fontSize: 18,
          openBookCallback: (_) {},
          isMainText: false,
          bookTitle: 'רש"י',
          reportBook: reportBook ?? TextBook(title: 'רש"י', categoryId: 9),
          notesRepository: repository,
          onOpenCommentaryPersonalNote: (_, _, _) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  SmartTextWidget line(WidgetTester tester) =>
      tester.widget<SmartTextWidget>(find.byType(SmartTextWidget).first);

  bool isMarked(WidgetTester tester) =>
      line(tester).text.contains('otzaria://note?line=0');

  Future<void> notify(WidgetTester tester, String bookId) async {
    PersonalNotesChanges.notify(bookId);
    await tester.pumpAndSettle();
  }

  testWidgets('הערה שנמחקה במקום אחר מסירה את ההדגשה מטור המפרש', (
    tester,
  ) async {
    final repository = _NotesRepository([_note()]);
    await pumpCommentary(tester, repository);
    expect(isMarked(tester), isTrue, reason: 'תנאי מוקדם: ההערה מסומנת');
    expect(line(tester).onNoteTap, isNotNull);

    repository.notes = [];
    await notify(tester, 'רש"י');

    expect(isMarked(tester), isFalse, reason: 'ההערה נמחקה — אין להדגיש');
    expect(line(tester).onNoteTap, isNull);
  });

  testWidgets('הערה שנוספה במקום אחר מסומנת בטור המפרש', (tester) async {
    final repository = _NotesRepository([]);
    await pumpCommentary(tester, repository);
    expect(isMarked(tester), isFalse);

    repository.notes = [_note()];
    await notify(tester, 'רש"י');

    expect(isMarked(tester), isTrue);
  });

  testWidgets('הערה שהועברה לשורה אחרת יוצאת מהשורה הקודמת', (tester) async {
    final repository = _NotesRepository([_note()]);
    await pumpCommentary(tester, repository);

    repository.notes = [_note(line: 7)];
    await notify(tester, 'רש"י');

    expect(isMarked(tester), isFalse);
  });

  testWidgets('שינוי בהערות של ספר אחר אינו טוען מחדש את המפרש', (
    tester,
  ) async {
    final repository = _NotesRepository([_note()]);
    await pumpCommentary(tester, repository);
    final callsBefore = repository.loadCalls;

    repository.notes = [];
    await notify(tester, 'תוספות');

    expect(repository.loadCalls, callsBefore);
    expect(isMarked(tester), isTrue);
  });

  testWidgets('טעינה ישנה שמסתיימת אחרי המחיקה אינה מחזירה את ההדגשה', (
    tester,
  ) async {
    final repository = _NotesRepository([])..holdLoads = true;
    await pumpCommentary(tester, repository);
    expect(repository.pending, hasLength(1));

    await notify(tester, 'רש"י');
    expect(repository.pending, hasLength(2));

    repository.pending[1].complete(const []);
    await tester.pumpAndSettle();
    repository.pending[0].complete([_note()]);
    await tester.pumpAndSettle();

    expect(isMarked(tester), isFalse);
  });

  testWidgets('מפרש ממסד מצורף מתעדכן לפי המפתח המלא שלו בלבד', (
    tester,
  ) async {
    final repository = _NotesRepository([_note()]);
    await pumpCommentary(
      tester,
      repository,
      reportBook: TextBook(
        title: 'רש"י',
        categoryId: 9,
        source: BookSource.attached('ext'),
      ),
    );
    final callsBefore = repository.loadCalls;

    repository.notes = [];
    await notify(tester, 'רש"י');
    expect(
      repository.loadCalls,
      callsBefore,
      reason: 'הערות המהדורה הרשמית אינן הערות המהדורה המצורפת',
    );
    expect(isMarked(tester), isTrue);

    await notify(tester, 'רש"י|db:ext');
    expect(isMarked(tester), isFalse);
  });

  testWidgets('טור מפרש שנסגר מפסיק להאזין לשינויים', (tester) async {
    final repository = _NotesRepository([_note()]);
    await pumpCommentary(tester, repository);
    final callsBefore = repository.loadCalls;

    await tester.pumpWidget(harness(const SizedBox()));
    await notify(tester, 'רש"י');

    expect(repository.loadCalls, callsBefore);
  });

  testWidgets('טור מפרש מסתנכרן עם SQLite ומיישב מיקום מיובא', (tester) async {
    final database = PersonalNotesDatabase.instance;
    final repository = _SqliteRepository();
    final root = (await tester.runAsync(() async {
      await database.close();
      final root = await Directory.systemTemp.createTemp('commentary_notes_');
      AppPaths.debugOverrideDataRootPath(root.path);
      await Settings.setValue(
        SettingsRepository.keyDatabasesPath,
        '${root.path}/databases',
      );
      return root;
    }))!;
    try {
      await pumpCommentary(tester, repository);
      expect(isMarked(tester), isFalse);

      await tester.runAsync(() async {
        await repository.service.addNote(
          bookId: 'רש"י',
          bookContent: _SqliteRepository.content,
          lineNumber: 1,
          content: 'תוכן',
          contentPlain: 'תוכן',
          contentFormat: PersonalNoteContentFormat.plain,
        );
        await pumpEventQueue();
      });
      await tester.pumpAndSettle();
      expect(isMarked(tester), isTrue);

      await tester.runAsync(() async {
        await database.deleteBookNotes('רש"י');
        await pumpEventQueue();
      });
      await tester.pumpAndSettle();
      expect(isMarked(tester), isFalse);

      await tester.runAsync(() async {
        await database.batchInsertNotes([
          _note(line: 2).copyWith(displayTitle: 'שורת מפרש'),
        ]);
        await pumpEventQueue();
      });
      await tester.pumpAndSettle();
      expect(isMarked(tester), isTrue);
      expect(
        await tester.runAsync(() => database.getNote('1')),
        isA<PersonalNote>().having((note) => note.lineNumber, 'lineNumber', 1),
      );
    } finally {
      await tester.pumpWidget(harness(const SizedBox()));
      await tester.runAsync(() async {
        await database.close();
        AppPaths.debugOverrideDataRootPath(null);
        await Settings.setValue(SettingsRepository.keyDatabasesPath, '');
        await root.delete(recursive: true);
      });
    }
  });

  testWidgets('הטקסט הראשי מסיר את ההדגשה כשה-bloc מוחק את ההערה', (
    tester,
  ) async {
    personalNotesBloc.emit(_notesState('ספר בדיקה', [_note()]));
    await tester.pumpWidget(
      harness(
        SimpleTextViewer(
          content: const ['שורה א'],
          fontSize: 18,
          openBookCallback: (_) {},
          isMainText: true,
          onOpenSidebarTab: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final mainLine = find.byWidgetPredicate(
      (w) => w is SmartTextWidget && w.text.contains('otzaria://note?line=0'),
    );
    expect(mainLine, findsOneWidget, reason: 'תנאי מוקדם: ההערה מסומנת');

    personalNotesBloc.emit(_notesState('ספר בדיקה', []));
    await tester.pumpAndSettle();

    expect(mainLine, findsNothing);
  });
}

class _SqliteRepository extends PersonalNotesRepository {
  static const content = 'שורת מפרש\nשורה אחרת';
  final service = PersonalNotesService();

  @override
  Future<List<PersonalNote>> loadNotes(String bookId, {int? categoryId}) =>
      service.loadNotes(bookId: bookId, bookContent: content);
}

class _NotesRepository extends PersonalNotesRepository {
  _NotesRepository(this.notes);

  List<PersonalNote> notes;
  int loadCalls = 0;

  /// כשמופעל, כל טעינה ממתינה עד שהבדיקה משלימה אותה.
  bool holdLoads = false;
  final pending = <Completer<List<PersonalNote>>>[];

  @override
  Future<List<PersonalNote>> loadNotes(String bookId, {int? categoryId}) {
    loadCalls++;
    if (!holdLoads) return Future.value(List.of(notes));
    final completer = Completer<List<PersonalNote>>();
    pending.add(completer);
    return completer.future;
  }
}

PersonalNote _note({int line = 1}) {
  final now = DateTime(2026, 10, 4);
  return PersonalNote(
    id: '1',
    bookId: 'רש"י',
    lineNumber: line,
    displayTitle: 'שורה',
    lastKnownLineNumber: line,
    status: PersonalNoteStatus.located,
    content: 'תוכן',
    contentPlain: 'תוכן',
    contentFormat: PersonalNoteContentFormat.plain,
    createdAt: now,
    updatedAt: now,
  );
}

PersonalNotesState _notesState(String bookId, List<PersonalNote> notes) =>
    PersonalNotesState(
      isLoading: false,
      bookId: bookId,
      locatedNotes: notes,
      missingNotes: const [],
      errorMessage: null,
      filteredLocatedNotes: notes,
      filteredMissingNotes: const [],
    );

TextBookLoaded _loadedState() {
  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: false,
    content: const ['שורה א'],
    fontSize: 18,
    showSplitView: false,
    showPageShapeView: true,
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
    pinLeftPane: false,
    searchText: '',
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
  );
}

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestPersonalNotesBloc
    extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _TestPersonalNotesBloc(super.initialState) {
    on<PersonalNotesEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
