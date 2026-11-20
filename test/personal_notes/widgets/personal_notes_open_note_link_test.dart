import 'dart:convert';
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/messages/notes_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/personal_notes/utils/note_link_detection.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_link_dialog.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_view_dialog.dart';
import 'package:otzaria/personal_notes/widgets/personal_notes_sidebar.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/personal_notes/utils/personal_notes_book_key.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';

import '../../test_helpers/memory_cache_provider.dart';

class _EmptyNotesBloc extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _EmptyNotesBloc() : super(const PersonalNotesState.initial());
}

class _LibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {
  _LibraryBloc(Library? library) {
    whenListen(
      this,
      const Stream<LibraryState>.empty(),
      initialState: LibraryState(library: library),
    );
  }
}

class _TabsBloc extends MockBloc<TabsEvent, TabsState> implements TabsBloc {
  _TabsBloc() {
    whenListen(
      this,
      const Stream<TabsState>.empty(),
      initialState: TabsState.initial(),
    );
  }

  final opened = <OpenOrFocusTab>[];

  @override
  void add(TabsEvent event) {
    if (event is OpenOrFocusTab) opened.add(event);
  }
}

class _HistoryBloc extends MockBloc<HistoryEvent, HistoryState>
    implements HistoryBloc {
  _HistoryBloc() {
    whenListen(
      this,
      const Stream<HistoryState>.empty(),
      initialState: HistoryInitial(),
    );
  }
}

class _NavigationBloc extends MockBloc<NavigationEvent, NavigationState>
    implements NavigationBloc {}

void main() {
  final database = PersonalNotesDatabase.instance;
  late Directory root;
  late BuildContext hostContext;
  final navigated = <int>[];
  late _TabsBloc tabs;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() async {
    navigated.clear();
    await database.close();
    root = await Directory.systemTemp.createTemp('personal_notes_link_');
    await Directory('${root.path}/databases').create();
    AppPaths.debugOverrideDataRootPath(root.path);
    await Settings.setValue(
      SettingsRepository.keyDatabasesPath,
      '${root.path}/databases',
    );
  });

  tearDown(() async {
    await database.close();
    AppPaths.debugOverrideDataRootPath(null);
    await Settings.setValue(SettingsRepository.keyDatabasesPath, '');
    await root.delete(recursive: true);
  });

  Future<void> pumpReader(WidgetTester tester, {Library? library}) async {
    final bloc = _EmptyNotesBloc();
    final libraryBloc = _LibraryBloc(library);
    final history = _HistoryBloc();
    final navigation = _NavigationBloc();
    tabs = _TabsBloc();
    addTearDown(bloc.close);
    addTearDown(libraryBloc.close);
    addTearDown(history.close);
    addTearDown(navigation.close);
    addTearDown(tabs.close);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: MultiBlocProvider(
          providers: [
            BlocProvider<PersonalNotesBloc>.value(value: bloc),
            BlocProvider<LibraryBloc>.value(value: libraryBloc),
            BlocProvider<TabsBloc>.value(value: tabs),
            BlocProvider<HistoryBloc>.value(value: history),
            BlocProvider<NavigationBloc>.value(value: navigation),
          ],
          child: Scaffold(
            body: Builder(
              builder: (context) {
                hostContext = context;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('קישור לשורה שומר תווים שמורים במפתח ספר מקומי', (tester) async {
    await pumpReader(tester);
    final bookId = personalNotesBookKeyFor('מקומי & ספר #1', BookSource.user);
    final result = showDialog<PersonalNoteLinkTarget>(
      context: hostContext,
      builder: (_) => PersonalNoteLinkDialog(bookId: bookId, notes: const []),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'מספר שורה'), '7');
    await tester.tap(find.text('הוסף'));
    await tester.pumpAndSettle();

    final target = (await result)!;
    await openNoteLink(hostContext, target.url, bookId, (line, {note}) {
      navigated.add(line);
    });
    expect(navigated, [7]);
  });

  Future<void> tapLink(WidgetTester tester, String noteId) async {
    openNoteLink(
      hostContext,
      personalNoteLinkUrl(noteId),
      'ספר הקורא',
      (line, {note}) => navigated.add(line),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('קישור בקורא להערה כללית נטען מהמסד ומוצג לקריאה', (
    tester,
  ) async {
    final target = PersonalNote(
      id: 'general-1',
      bookId: PersonalNote.generalBookId,
      lineNumber: null,
      lastKnownLineNumber: null,
      status: PersonalNoteStatus.book,
      content: 'תוכן ההערה הכללית',
      contentPlain: 'תוכן ההערה הכללית',
      contentFormat: PersonalNoteContentFormat.plain,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
    await tester.runAsync(() => database.insertNote(target));
    await pumpReader(tester);

    await tapLink(tester, 'general-1');

    expect(find.byType(PersonalNoteViewDialog), findsOneWidget);
    expect(find.text('תוכן ההערה הכללית'), findsOneWidget);
    expect(navigated, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('קישור בקורא להערה שנמחקה מודיע במקום לשתוק', (tester) async {
    await tester.runAsync(() => database.loadNotes('x'));
    await pumpReader(tester);

    await tapLink(tester, 'deleted-note');

    expect(find.text(NotesMessages.linkedNoteDeleted), findsOneWidget);
    expect(find.byType(PersonalNoteViewDialog), findsNothing);

    UiSnack.hide();
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('קישור יחסי בהערה ממסד מצורף פותח את מהדורת המקור ולא את הקורא', (
    tester,
  ) async {
    final attached = PdfBook(
      title: 'שם משותף',
      path: '/test/source.pdf',
      id: 17,
      source: BookSource.attached('source'),
    );
    final anotherEdition = PdfBook(
      title: attached.title,
      path: '/test/other.pdf',
      id: 18,
      source: attached.source,
    );
    final category = Category(
      title: 'ספרייה',
      description: '',
      shortDescription: '',
      books: [
        TextBook(title: attached.title),
        attached,
        anotherEdition,
      ],
      subCategories: [],
      order: 0,
      parent: null,
    );
    final library = Library(categories: [category]);
    category.parent = library;
    final target = PersonalNote(
      id: 'attached-note',
      bookId: personalNotesBookKey(attached),
      lineNumber: 3,
      lastKnownLineNumber: null,
      status: PersonalNoteStatus.located,
      content: jsonEncode([
        {
          'insert': 'קישור לשורה',
          'attributes': {'link': 'otzaria://book?line=7'},
        },
        {'insert': '\n'},
      ]),
      contentPlain: 'קישור לשורה',
      contentFormat: PersonalNoteContentFormat.quillDelta,
      pdfAnchor: PdfNoteAnchor(
        pageNumber: 3,
        x: 0.2,
        y: 0.4,
        documentId: pdfPersonalNoteDocumentId(attached),
      ),
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
    await tester.runAsync(() => database.insertNote(target));
    await pumpReader(tester, library: library);
    await tapLink(tester, target.id);

    await tester.tap(find.widgetWithText(ActionChip, 'קישור לשורה'));
    await tester.pumpAndSettle();

    expect(navigated, isEmpty);
    final opened = tabs.opened.single.tab as PdfBookTab;
    expect(opened.book, attached);
    expect(opened.pageNumber, 7);
    opened.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
