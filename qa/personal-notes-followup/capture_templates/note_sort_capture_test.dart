import 'package:flutter/services.dart';
import 'qa_capture_helpers.dart' as qa;
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/models/personal_notes_sort_order.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/personal_notes/view/personal_notes_screen.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_content_view.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';

import '__REPO_URI__/test/test_helpers/memory_cache_provider.dart';

class _LibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

PersonalNote _note(
  String id, {
  required String bookId,
  required DateTime created,
  DateTime? updated,
  int? line = 1,
  String? content,
}) => PersonalNote(
  id: id,
  bookId: bookId,
  lineNumber: line,
  lastKnownLineNumber: null,
  status: line == null
      ? PersonalNoteStatus.missing
      : PersonalNoteStatus.located,
  content: content ?? id,
  contentPlain: content ?? id,
  contentFormat: PersonalNoteContentFormat.plain,
  createdAt: created,
  updatedAt: updated ?? created,
);

List<String> _sortedIds(
  List<PersonalNote> notes,
  PersonalNotesSortOrder order,
) => ([...notes]..sort(order.compare)).map((note) => note.id).toList();

class _Repository extends PersonalNotesRepository {
  _Repository(this.notes);

  final List<PersonalNote> notes;

  @override
  Future<List<BookNotesInfo>> listBooksWithNotes() async => [
    for (final bookId in notes.map((note) => note.bookId).toSet())
      BookNotesInfo(
        bookId: bookId,
        noteCount: notes.where((note) => note.bookId == bookId).length,
        lastUpdated: DateTime(2026),
      ),
  ];

  @override
  Future<List<PersonalNote>> loadNotes(
    String bookId, {
    int? categoryId,
  }) async => notes.where((note) => note.bookId == bookId).toList();
}

Future<void> _mount(WidgetTester tester, List<PersonalNote> notes) async {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repository = _Repository(notes);
  final notesBloc = PersonalNotesBloc(repository: repository);
  final settingsBloc = SettingsBloc(repository: SettingsRepository());
  final libraryBloc = _LibraryBloc();
  whenListen(
    libraryBloc,
    const Stream<LibraryState>.empty(),
    initialState: LibraryState(
      library: Library(categories: []),
      isLoading: false,
    ),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await notesBloc.close();
    await settingsBloc.close();
    await libraryBloc.close();
  });
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<SettingsBloc>.value(value: settingsBloc),
        BlocProvider<LibraryBloc>.value(value: libraryBloc),
        BlocProvider<PersonalNotesBloc>.value(value: notesBloc),
      ],
      child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: qa.captureTheme(),
            locale: const Locale('he', 'IL'),
            supportedLocales: const [Locale('he', 'IL')],
            localizationsDelegates: qa.localizations,
            builder: qa.captureBuilder,
        home: Scaffold(
          body: PersonalNotesManagerScreen(repository: repository),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<String> _visibleIds(WidgetTester tester) => tester
    .widgetList<PersonalNoteContentView>(find.byType(PersonalNoteContentView))
    .map((view) => view.note.id)
    .toList();

Future<void> _selectOrder(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('מיון הערות'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

List<PersonalNote> _screenNotes() => [
  _note(
    'a-old',
    bookId: 'ספר א',
    created: DateTime(2026, 1, 1, 8),
    updated: DateTime(2026, 1, 1, 13),
    content: 'סימון ישן',
  ),
  _note(
    'a-new',
    bookId: 'ספר א',
    created: DateTime(2026, 1, 1, 11),
    line: 2,
    content: 'סימון חדש',
  ),
  _note(
    'b-middle',
    bookId: 'ספר ב',
    created: DateTime(2026, 1, 1, 10),
    content: 'תוכן אחר',
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(qa.loadCaptureFonts);
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  group('Personal-note sort order', () {
    test('creation order spans books and compares the entire timestamp', () {
      final notes = [
        _note('a', bookId: 'ספר א', created: DateTime(2026, 1, 1, 9, 0, 1)),
        _note('c', bookId: 'ספר ג', created: DateTime(2026, 1, 1, 9, 0, 2)),
        _note(
          'b',
          bookId: 'ספר ב',
          created: DateTime(2026, 1, 1, 9, 0, 1, 500),
        ),
        _note('d', bookId: 'ספר ד', created: DateTime(2025, 12, 31, 23, 59)),
      ];
      expect(_sortedIds(notes, PersonalNotesSortOrder.newestCreated), [
        'c',
        'b',
        'a',
        'd',
      ]);
      expect(_sortedIds(notes, PersonalNotesSortOrder.oldestCreated), [
        'd',
        'a',
        'b',
        'c',
      ]);
    });

    test(
      'editing an old note affects updated order but not creation order',
      () {
        final notes = [
          _note(
            'old',
            bookId: 'ספר א',
            created: DateTime(2025),
            updated: DateTime(2026, 1, 1, 18),
          ),
          _note('new', bookId: 'ספר ב', created: DateTime(2026, 1, 1, 10)),
        ];
        expect(_sortedIds(notes, PersonalNotesSortOrder.newestCreated), [
          'new',
          'old',
        ]);
        expect(_sortedIds(notes, PersonalNotesSortOrder.lastUpdated), [
          'old',
          'new',
        ]);
        expect(PersonalNotesSortOrder.newestCreated.usesCreationDate, isTrue);
        expect(PersonalNotesSortOrder.oldestCreated.usesCreationDate, isTrue);
        expect(PersonalNotesSortOrder.lastUpdated.usesCreationDate, isFalse);
      },
    );

    test(
      'equal timestamps and missing locations keep a deterministic order',
      () {
        final date = DateTime(2026);
        final notes = [
          _note('a-later-id', bookId: 'ספר א', created: date, line: 2),
          _note('b', bookId: 'ספר ב', created: date),
          _note('a-earlier-id', bookId: 'ספר א', created: date, line: 2),
          _note('missing', bookId: 'ספר א', created: date, line: null),
          _note('a-line-1', bookId: 'ספר א', created: date),
        ];
        for (final order in PersonalNotesSortOrder.values) {
          expect(
            _sortedIds(notes, order),
            ['missing', 'a-line-1', 'a-earlier-id', 'a-later-id', 'b'],
            reason: order.name,
          );
        }
      },
    );

    test('missing locations participate in global chronological order', () {
      final notes = [
        _note('located', bookId: 'ספר א', created: DateTime(2026, 1, 1, 8)),
        _note(
          'missing',
          bookId: 'ספר ב',
          created: DateTime(2026, 1, 1, 9),
          line: null,
        ),
      ];
      expect(_sortedIds(notes, PersonalNotesSortOrder.newestCreated), [
        'missing',
        'located',
      ]);
    });

    test(
      'settings preserve every choice and recover from unknown values',
      () async {
        expect(
          loadPersonalNotesSortOrder(),
          PersonalNotesSortOrder.bookLocation,
        );
        for (final order in PersonalNotesSortOrder.values) {
          await savePersonalNotesSortOrder(order);
          expect(
            Settings.getValue<String>('key-personal-notes-sort-order'),
            order.name,
          );
          expect(loadPersonalNotesSortOrder(), order);
        }
        await Settings.setValue<String>(
          'key-personal-notes-sort-order',
          'removed-option',
        );
        expect(
          loadPersonalNotesSortOrder(),
          PersonalNotesSortOrder.bookLocation,
        );
      },
    );
  });

  testWidgets('chronological menu order stays global and survives reopening', (
    tester,
  ) async {
    final notes = _screenNotes();
    await _mount(tester, notes);
    expect(_visibleIds(tester), ['a-old', 'a-new', 'b-middle']);
    await _selectOrder(tester, 'החדשות ביותר תחילה');
    expect(_visibleIds(tester), ['a-new', 'b-middle', 'a-old']);
    expect(find.text('ספר א'), findsNWidgets(2));
    expect(
      tester.getTopLeft(find.text('סימון חדש')).dy,
      lessThan(tester.getTopLeft(find.text('תוכן אחר')).dy),
    );
    expect(
      tester.getTopLeft(find.text('תוכן אחר')).dy,
      lessThan(tester.getTopLeft(find.text('סימון ישן')).dy),
    );
    expect(
      tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .any(
            (tooltip) =>
                tooltip.message?.startsWith('נכתב:') == true &&
                tooltip.message!.endsWith('11:00'),
          ),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await _mount(tester, notes);
    expect(_visibleIds(tester), ['a-new', 'b-middle', 'a-old']);

    await _selectOrder(tester, 'עודכנו לאחרונה');
    expect(_visibleIds(tester), ['a-old', 'a-new', 'b-middle']);
    expect(
      tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .any(
            (tooltip) =>
                tooltip.message?.startsWith('עודכן:') == true &&
                tooltip.message!.endsWith('13:00'),
          ),
      isTrue,
    );
    await _selectOrder(tester, 'הוותיקות ביותר תחילה');
    expect(_visibleIds(tester), ['a-old', 'b-middle', 'a-new']);
  });

  testWidgets(
    'search and missing-note filters retain the selected date order',
    (
      tester,
    ) async {
      final notes = [
        ..._screenNotes(),
        _note(
          'b-missing',
          bookId: 'ספר ב',
          created: DateTime(2026, 1, 1, 12),
          line: null,
          content: 'סימון ללא מיקום',
        ),
      ];
      await _mount(tester, notes);
      await _selectOrder(tester, 'החדשות ביותר תחילה');
      expect(_visibleIds(tester), ['b-missing', 'a-new', 'b-middle', 'a-old']);
      await tester.enterText(
        find
            .descendant(
              of: find.byType(OtzariaSearchField),
              matching: find.byType(TextField),
            )
            .first,
        'סימון',
      );
      await tester.pumpAndSettle();
      expect(_visibleIds(tester), ['b-missing', 'a-new', 'a-old']);
      await tester.tap(find.text('הערות ללא מיקום'));
      await tester.pumpAndSettle();
      expect(_visibleIds(tester), ['b-missing']);
      expect(
        loadPersonalNotesSortOrder(),
        PersonalNotesSortOrder.newestCreated,
      );
    },
  );

  testWidgets('sorting menu fits a narrow screen and remains usable', (
    tester,
  ) async {
    await _mount(tester, _screenNotes());
    await tester.tap(find.byTooltip('הסתר ניווט'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await _selectOrder(tester, 'החדשות ביותר תחילה');
    expect(tester.takeException(), isNull);
    expect(_visibleIds(tester), ['a-new', 'b-middle', 'a-old']);
  });
  testWidgets('QA capture sorted notes manager', (tester) async {
    await _mount(tester, _screenNotes());
    tester.view.physicalSize = const Size(1200, 900);
    await tester.pumpAndSettle();
    await _selectOrder(tester, 'החדשות ביותר תחילה');
    await tester.tap(find.byTooltip('מיון הערות'));
    await tester.pumpAndSettle();
    await qa.capture(tester, '03-note-manager-sort');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  });

}
