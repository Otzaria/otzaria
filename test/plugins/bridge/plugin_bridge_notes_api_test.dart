import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/personal_notes/services/personal_notes_service.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_adapter.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';

import '../../test_helpers/memory_cache_provider.dart';

const _book = 'בראשית';
const _content =
    'בראשית ברא אלהים\nויאמר אלהים יהי אור ויהי אור\nוירא אלהים את האור';

class _MemoryNotesDb implements PersonalNotesDatabase {
  final notes = <String, PersonalNote>{};

  @override
  Future<List<PersonalNote>> loadNotes(String bookId) async =>
      notes.values.where((note) => note.bookId == bookId).toList();

  @override
  Future<void> insertNote(PersonalNote note) async => notes[note.id] = note;

  @override
  Future<void> batchUpdateNotes(List<PersonalNote> changed) async {
    for (final note in changed) {
      notes[note.id] = note;
    }
  }

  @override
  Future<PersonalNote?> getNote(String id) async => notes[id];

  @override
  Future<void> updateNote(PersonalNote note) async => notes[note.id] = note;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// המאגר האמיתי, עם ספר קבוע ומסד בזיכרון.
class _Repository extends PersonalNotesRepository {
  _Repository(this.db)
    : service = PersonalNotesService(database: db, random: Random(1)),
      super(
        service: PersonalNotesService(database: db),
        database: db,
      );

  final _MemoryNotesDb db;
  final PersonalNotesService service;

  @override
  Future<String> loadBookContent(String bookId, {int? categoryId}) async =>
      _content;

  @override
  Future<List<PersonalNote>> loadNotes(String bookId, {int? categoryId}) =>
      service.loadNotes(bookId: bookId, bookContent: _content);

  @override
  Future<PersonalNote> createNote({
    required String bookId,
    required int? lineNumber,
    required String content,
    required String contentPlain,
    required PersonalNoteContentFormat contentFormat,
    String? selectedText,
    int? selectionColumn,
    String? sourceSelectedText,
    int? sourceSelectionOffset,
    bool punctuationHidden = false,
    PdfNoteAnchor? pdfAnchor,
    int? categoryId,
    int? endLineNumber,
    int? occurrenceIndex,
    bool requireWordAnchor = false,
  }) => service.createNote(
    bookId: bookId,
    bookContent: lineNumber == null ? '' : _content,
    lineNumber: lineNumber,
    content: content,
    contentPlain: contentPlain,
    contentFormat: contentFormat,
    selectedText: selectedText,
    sourceSelectedText: sourceSelectedText,
    sourceSelectionOffset: sourceSelectionOffset,
    endLineNumber: endLineNumber,
    occurrenceIndex: occurrenceIndex,
    requireWordAnchor: requireWordAnchor,
  );

  @override
  Future<PersonalNote> setNoteLocation({
    required String bookId,
    required String noteId,
    required PersonalNoteScope scope,
    int? lineNumber,
    int? endLineNumber,
    String? sourceText,
    int? sourceOffset,
    int? occurrenceIndex,
    int? categoryId,
  }) => service.setNoteLocation(
    bookId: bookId,
    bookContent: _content,
    noteId: noteId,
    scope: scope,
    lineNumber: lineNumber,
    endLineNumber: endLineNumber,
    sourceText: sourceText,
    sourceOffset: sourceOffset,
    occurrenceIndex: occurrenceIndex,
  );
}

class _MockHistoryBloc extends Mock implements HistoryBloc {}

class _MockNavigationBloc extends Mock implements NavigationBloc {}

class _MockCalendarCubit extends Mock implements CalendarCubit {}

class _MockWorkspaceBloc extends Mock implements WorkspaceBloc {}

class _MockSearchRepository extends Mock implements SearchRepository {}

class _MockBookOpenCoordinator extends Mock implements BookOpenCoordinator {}

class _StubTabsBloc extends Mock implements TabsBloc {
  @override
  TabsState get state => TabsState.initial();
}

class _StubPluginRegistryRepository extends PluginRegistryRepository {
  @override
  Future<bool?> getPermission(String pluginId, String permission) async => true;
}

InstalledPlugin _plugin() => InstalledPlugin(
  pluginId: 'test.notes',
  name: 'Notes Test',
  version: '1.0.0',
  installPath: '/',
  entrypointPath: 'index.html',
  enabled: true,
  pinned: true,
  manifest: PluginManifest(
    schemaVersion: 1,
    id: 'test.notes',
    name: 'Notes Test',
    version: '1.0.0',
    description: '',
    author: '',
    homepage: '',
    entrypoint: 'index.html',
    minAppVersion: '1.0.0',
    sdkVersion: '1.x',
    permissions: const ['notes.read', 'notes.write'],
    networkEnabled: false,
    networkAllowlist: const [],
    toolTabTitle: 'Notes Test',
    toolTabOrder: 1,
    defaultPinned: true,
    publishedDataTypes: const [],
  ),
  installedAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

Matcher _codedError(String code) => throwsA(
  isA<Exception>().having((e) => e.toString(), 'message', contains(code)),
);

void main() {
  late _MemoryNotesDb db;
  late PluginBridgeAdapter adapter;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    db = _MemoryNotesDb();
    adapter = PluginBridgeAdapter(
      _plugin(),
      dependencies: PluginBridgeDependencies(
        historyBloc: _MockHistoryBloc(),
        tabsBloc: _StubTabsBloc(),
        navigationBloc: _MockNavigationBloc(),
        calendarCubit: _MockCalendarCubit(),
        workspaceBloc: _MockWorkspaceBloc(),
        searchRepository: _MockSearchRepository(),
        personalNotesRepository: _Repository(db),
        bookOpenCoordinator: _MockBookOpenCoordinator(),
        themePayloadBuilder: () => <String, dynamic>{},
        showConfirmDialog: ({required title, required content}) async => true,
        showWarningDialog:
            ({required title, required content, required subtitle}) async =>
                true,
      ),
      pluginRepository: _StubPluginRegistryRepository(),
    );
  });

  Future<dynamic> call(String action, Map<String, dynamic> args) =>
      adapter.execute('notes', action, {'bookId': _book, ...args});

  test(
    'notes.add: שורה, טווח, מילים וספר; returnNote מחזיר את ההערה',
    () async {
      expect(await call('add', {'lineNumber': 1, 'content': 'שורה'}), isTrue);

      final range =
          await call('add', {
                'lineNumber': 1,
                'endLineNumber': 3,
                'content': 'טווח',
                'returnNote': true,
              })
              as Map<String, dynamic>;
      expect(range['scope'], 'lines');
      expect(range['endLineNumber'], 3);
      expect(range['id'], isA<String>());

      final words =
          await call('add', {
                'lineNumber': 2,
                'text': 'אור',
                'occurrence': 1,
                'content': 'מילים',
                'returnNote': true,
              })
              as Map<String, dynamic>;
      expect(words['scope'], 'words');
      expect(words['anchorText'], 'אור');

      final book =
          await call('add', {
                'scope': 'book',
                'content': 'ספר',
                'returnNote': true,
              })
              as Map<String, dynamic>;
      expect((book['scope'], book['lineNumber']), ('book', null));

      final listed = (await call('list', {}) as List).cast<Map>();
      expect(listed.map((note) => note['scope']).toSet(), {
        'lines',
        'words',
        'book',
      });
    },
  );

  test('notes.add: מילים שאינן בשורה אינן יוצרות הערה', () async {
    await expectLater(
      call('add', {'lineNumber': 2, 'text': 'חושך', 'content': 'x'}),
      _codedError('error.not_found'),
    );
    await expectLater(
      call('add', {'lineNumber': 1, 'endLineNumber': 9, 'content': 'x'}),
      _codedError('error.invalid_params'),
    );
    expect(db.notes, isEmpty);
  });

  test('notes.setLocation מזיז הערה בין הסוגים', () async {
    final note =
        await call('add', {
              'lineNumber': 1,
              'content': 'הערה',
              'returnNote': true,
            })
            as Map<String, dynamic>;
    final id = note['id'];

    final words =
        await call('setLocation', {
              'noteId': id,
              'lineNumber': 3,
              'text': 'האור',
            })
            as Map<String, dynamic>;
    expect((words['scope'], words['lineNumber']), ('words', 3));

    final lines =
        await call('setLocation', {
              'noteId': id,
              'lineNumber': 2,
              'endLineNumber': 3,
            })
            as Map<String, dynamic>;
    expect((lines['scope'], lines['endLineNumber']), ('lines', 3));
    expect(lines['anchorText'], isNull);

    final book =
        await call('setLocation', {'noteId': id, 'scope': 'book'})
            as Map<String, dynamic>;
    expect(book['status'], 'book');

    await expectLater(
      call('setLocation', {'noteId': 'none', 'scope': 'book'}),
      _codedError('error.not_found'),
    );
  });
}
