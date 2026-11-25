import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/personal_notes/view/personal_notes_screen.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor_dialog.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_view_dialog.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';

import '../test_helpers/memory_cache_provider.dart';

class _MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

class _Repository extends PersonalNotesRepository {
  _Repository(this.notesByBook);

  final Map<String, List<PersonalNote>> notesByBook;

  @override
  Future<List<BookNotesInfo>> listBooksWithNotes() async => [
    for (final entry in notesByBook.entries)
      BookNotesInfo(
        bookId: entry.key,
        noteCount: entry.value.length,
        lastUpdated: DateTime(2026, 1, 2),
      ),
  ];

  @override
  Future<List<PersonalNote>> loadNotes(
    String bookId, {
    int? categoryId,
  }) async => notesByBook[bookId] ?? const [];
}

PersonalNote _note(
  String id, {
  required String bookId,
  int? lineNumber,
  PersonalNoteStatus status = PersonalNoteStatus.located,
  required String content,
}) => PersonalNote(
  id: id,
  bookId: bookId,
  lineNumber: lineNumber,
  displayTitle: lineNumber == null ? null : 'כותרת $id',
  lastKnownLineNumber: null,
  status: status,
  content: content,
  contentPlain: content,
  contentFormat: PersonalNoteContentFormat.plain,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 2),
);

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  final longGeneral = '${'מילה ' * 60}סוף הערה כללית';
  final notes = {
    PersonalNote.generalBookId: [
      _note(
        'g',
        bookId: PersonalNote.generalBookId,
        status: PersonalNoteStatus.book,
        content: longGeneral,
      ),
    ],
    'ספר א': [
      _note('a', bookId: 'ספר א', lineNumber: 3, content: 'הערה בספר'),
    ],
  };

  Future<void> pumpScreen(
    WidgetTester tester, {
    Size size = const Size(2400, 1000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settingsBloc = SettingsBloc(repository: SettingsRepository());
    final libraryBloc = _MockLibraryBloc();
    addTearDown(settingsBloc.close);
    whenListen(
      libraryBloc,
      const Stream<LibraryState>.empty(),
      initialState: LibraryState(
        library: Library(categories: []),
        isLoading: false,
        currentCategory: null,
      ),
    );
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
          BlocProvider<LibraryBloc>.value(value: libraryBloc),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: Scaffold(
            body: PersonalNotesManagerScreen(repository: _Repository(notes)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> closeScreen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('הערות כלליות בקבוצה משלהן, בעץ וברשימה, בלי פתיחה בספר', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(
      find.widgetWithText(NavTreeTile, 'הערות כלליות'),
      findsOneWidget,
    );
    expect(find.text('הערות כלליות'), findsNWidgets(2));
    expect(find.text('הערה כללית'), findsOneWidget);
    expect(find.text(PersonalNote.generalBookId), findsNothing);
    expect(find.byTooltip('פתח ספר בשורה'), findsOneWidget);

    await tester.tap(find.widgetWithText(NavTreeTile, 'הערות כלליות'));
    await tester.pumpAndSettle();
    expect(find.text('הערה כללית'), findsOneWidget);
    expect(find.text('כותרת a'), findsNothing);

    await closeScreen(tester);
  });

  testWidgets('לחיצה על כרטיס פותחת את ההערה המלאה לקריאה', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('הערה כללית'));
    await tester.pumpAndSettle();

    final dialog = find.byType(PersonalNoteViewDialog);
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(
        of: dialog,
        matching: find.textContaining('סוף הערה כללית'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('פתח בספר')),
      findsNothing,
    );

    await tester.tap(find.descendant(of: dialog, matching: find.text('סגור')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('כותרת a'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(PersonalNoteViewDialog),
        matching: find.text('פתח בספר'),
      ),
      findsOneWidget,
    );

    await closeScreen(tester);
  });

  testWidgets('"הערה כללית חדשה" פותח עורך תחת מפתח ההערות הכלליות', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.tap(find.byTooltip('הערה כללית חדשה'));
    await tester.pumpAndSettle();

    final editor = tester.widget<PersonalNoteEditorDialog>(
      find.byType(PersonalNoteEditorDialog),
    );
    expect(editor.title, 'הערה כללית חדשה');
    expect(editor.bookId, PersonalNote.generalBookId);
    expect(editor.linkableNotes.map((n) => n.id), containsAll(['g', 'a']));

    await closeScreen(tester);
  });

  testWidgets('נייד: הערה כללית חדשה זמינה בתפריט עוד פעולות', (tester) async {
    await pumpScreen(tester, size: const Size(360, 800));
    expect(find.byTooltip('הערה כללית חדשה'), findsNothing);
    await tester.tap(find.byTooltip('עוד פעולות'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('הערה כללית חדשה'));
    await tester.pumpAndSettle();

    final editor = tester.widget<PersonalNoteEditorDialog>(
      find.byType(PersonalNoteEditorDialog),
    );
    expect(editor.bookId, PersonalNote.generalBookId);
    expect(tester.takeException(), isNull);
    await closeScreen(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
