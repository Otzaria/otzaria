import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/notes_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/windowing/dialog_owner.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/personal_notes/services/personal_note_draft_service.dart';
import 'package:otzaria/personal_notes/services/personal_notes_service.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_changes.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/personal_notes/view/personal_notes_screen.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor_dialog.dart';
import 'package:otzaria/personal_notes/widgets/personal_notes_export_dialog.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/widgets/controls/bar_button.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../test_helpers/memory_cache_provider.dart';
import '../test_helpers/capture_file_saves.dart';

class _LibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

class _SourceBook extends TextBook {
  _SourceBook() : super(id: 1, title: 'ספר א', categoryId: 47);

  @override
  Future<List<TocEntry>> get tableOfContents async => const [];
}

class _ExportPicker extends FilePickerPlatform with MockPlatformInterfaceMixin {
  Uint8List? bytes;

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    String mimeType = 'application/octet-stream',
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    this.bytes = bytes;
    return null;
  }
}

PersonalNote _note(String bookId, String content) => PersonalNote(
  id: 'note-$bookId',
  bookId: bookId,
  lineNumber: 1,
  lastKnownLineNumber: null,
  status: PersonalNoteStatus.located,
  content: content,
  contentPlain: content,
  contentFormat: PersonalNoteContentFormat.plain,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

BookNotesInfo _book(String id) => BookNotesInfo(
  bookId: id,
  noteCount: 1,
  lastUpdated: DateTime(2026),
);

class _Repository extends PersonalNotesRepository {
  _Repository(this.notes, {super.service});

  final Map<String, List<PersonalNote>> notes;
  bool delayLists = false;
  bool delayFullNotes = false;
  bool delayStoredNotes = false;
  bool delayUpdates = false;
  final updateRequests = <Completer<void>>[];
  final updateTargets = <({String bookId, String noteId, int? categoryId})>[];
  final listRequests = <Completer<List<BookNotesInfo>>>[];
  final fullRequests = <String, List<Completer<List<PersonalNote>>>>{};
  final storedRequests = <String, List<Completer<List<PersonalNote>>>>{};
  final fullReads = <String>[];
  final storedReads = <String>[];
  int listReads = 0;

  @override
  Future<List<BookNotesInfo>> listBooksWithNotes() {
    listReads++;
    if (delayLists) {
      final request = Completer<List<BookNotesInfo>>();
      listRequests.add(request);
      return request.future;
    }
    return Future.value([
      for (final entry in notes.entries)
        if (entry.value.isNotEmpty)
          BookNotesInfo(
            bookId: entry.key,
            noteCount: entry.value.length,
            lastUpdated: DateTime(2026),
          ),
    ]);
  }

  Future<List<PersonalNote>> _read(
    String bookId, {
    required bool delayed,
    required Map<String, List<Completer<List<PersonalNote>>>> requests,
  }) {
    if (!delayed) return Future.value(List.of(notes[bookId] ?? const []));
    final request = Completer<List<PersonalNote>>();
    requests.putIfAbsent(bookId, () => []).add(request);
    return request.future;
  }

  @override
  Future<List<PersonalNote>> loadNotes(String bookId, {int? categoryId}) {
    fullReads.add(bookId);
    return _read(bookId, delayed: delayFullNotes, requests: fullRequests);
  }

  @override
  Future<List<PersonalNote>> loadStoredNotes(String bookId) {
    storedReads.add(bookId);
    return _read(bookId, delayed: delayStoredNotes, requests: storedRequests);
  }

  @override
  Future<PersonalNote> persistNote({
    required String bookId,
    required String noteId,
    required String content,
    required String contentPlain,
    required PersonalNoteContentFormat contentFormat,
    int? categoryId,
  }) async {
    updateTargets.add((bookId: bookId, noteId: noteId, categoryId: categoryId));
    if (delayUpdates) {
      final request = Completer<void>();
      updateRequests.add(request);
      await request.future;
    }
    notes[bookId] = [
      for (final note in notes[bookId] ?? const <PersonalNote>[])
        if (note.id == noteId)
          note.copyWith(
            content: content,
            contentPlain: contentPlain,
            contentFormat: contentFormat,
          )
        else
          note,
    ];
    PersonalNotesChanges.notify(bookId);
    return notes[bookId]!.singleWhere((note) => note.id == noteId);
  }

  void completePending() {
    for (final request in updateRequests) {
      if (!request.isCompleted) request.complete();
    }
    for (final request in listRequests) {
      if (!request.isCompleted) request.complete(const []);
    }
    for (final requests in [fullRequests, storedRequests]) {
      for (final bookRequests in requests.values) {
        for (final request in bookRequests) {
          if (!request.isCompleted) request.complete(const []);
        }
      }
    }
  }
}

Future<void> _pump(WidgetTester tester, [int count = 8]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

void _expectExportEnabled(WidgetTester tester, bool enabled) {
  for (final tooltip in ['גיבוי הערות', 'ייצוא לטקסט', 'ייצוא לוורד']) {
    final button = tester.widget<BarButton>(
      find.byWidgetPredicate(
        (widget) => widget is BarButton && widget.tooltip == tooltip,
      ),
    );
    expect(button.onPressed != null, enabled, reason: tooltip);
  }
}

Future<PersonalNotesBloc> _mount(
  WidgetTester tester,
  _Repository repository, {
  Library? library,
}) async {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final notesBloc = PersonalNotesBloc(repository: repository);
  final settingsRepository = SettingsRepository();
  final settingsBloc = SettingsBloc(repository: settingsRepository);
  final libraryBloc = _LibraryBloc();
  whenListen(
    libraryBloc,
    const Stream<LibraryState>.empty(),
    initialState: LibraryState(
      library: library ?? Library(categories: []),
      isLoading: false,
    ),
  );
  addTearDown(() async {
    UiSnack.hide();
    await tester.pumpWidget(const SizedBox.shrink());
    repository.completePending();
    await tester.pump();
    await notesBloc.close();
    await settingsBloc.close();
    await libraryBloc.close();
  });
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        RepositoryProvider<SettingsRepository>.value(value: settingsRepository),
        BlocProvider<SettingsBloc>.value(value: settingsBloc),
        BlocProvider<LibraryBloc>.value(value: libraryBloc),
        BlocProvider<PersonalNotesBloc>.value(value: notesBloc),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        home: Scaffold(
          body: PersonalNotesManagerScreen(repository: repository),
        ),
      ),
    ),
  );
  await _pump(tester);
  return notesBloc;
}

class _ServiceMutationRepository extends _Repository {
  _ServiceMutationRepository(super.notes, this._mutationService)
    : super(service: _mutationService);

  final PersonalNotesService _mutationService;
  static const _bookContent = 'first line\nsecond line\nthird line';

  @override
  Future<List<PersonalNote>> repositionNote({
    required String bookId,
    required String noteId,
    required int lineNumber,
    PdfNoteAnchor? pdfAnchor,
    int? categoryId,
  }) => _mutationService.repositionNote(
    bookId: bookId,
    bookContent: _bookContent,
    noteId: noteId,
    lineNumber: lineNumber,
    pdfAnchor: pdfAnchor,
  );

  @override
  Future<PersonalNote> moveNote({
    required String bookId,
    required String noteId,
    required int lineNumber,
    PdfNoteAnchor? pdfAnchor,
    int? categoryId,
  }) => _mutationService.moveNote(
    bookId: bookId,
    bookContent: _bookContent,
    noteId: noteId,
    lineNumber: lineNumber,
    pdfAnchor: pdfAnchor,
  );
}

class _MutationRefreshDatabase extends Fake implements PersonalNotesDatabase {
  _MutationRefreshDatabase(this.notes);

  final Map<String, List<PersonalNote>> notes;
  int writes = 0;
  int listReads = 0;

  @override
  Future<List<PersonalNote>> loadNotes(String bookId) async {
    listReads++;
    throw StateError('list refresh failed after the write');
  }

  @override
  Future<PersonalNote?> getNote(String noteId) async {
    for (final bookNotes in notes.values) {
      for (final note in bookNotes) {
        if (note.id == noteId) return note;
      }
    }
    return null;
  }

  @override
  Future<void> deleteNote(String noteId) async {
    final note = await getNote(noteId);
    if (note == null) return;
    notes[note.bookId]!.removeWhere((note) => note.id == noteId);
    writes++;
    PersonalNotesChanges.notify(note.bookId);
  }

  @override
  Future<void> updateNote(PersonalNote updated) async {
    final bookNotes = notes[updated.bookId]!;
    final index = bookNotes.indexWhere((note) => note.id == updated.id);
    if (index < 0) throw StateError('note no longer exists');
    bookNotes[index] = updated;
    writes++;
    PersonalNotesChanges.notify(updated.bookId);
  }
}

class _MutationRepository extends _Repository {
  _MutationRepository(super.notes);
  final pendingWrite = Completer<void>();
  final targets = <({String bookId, String noteId, int? line})>[];

  Future<List<PersonalNote>> _write(
    String bookId,
    String noteId,
    int? line,
  ) async {
    targets.add((bookId: bookId, noteId: noteId, line: line));
    await pendingWrite.future;
    notes[bookId] = [
      for (final note in notes[bookId] ?? <PersonalNote>[])
        if (note.id != noteId)
          note
        else if (line != null)
          note.copyWith(lineNumber: line, status: PersonalNoteStatus.located),
    ];
    PersonalNotesChanges.notify(bookId);
    return notes[bookId]!;
  }

  @override
  Future<void> removeNote({required String noteId}) async {
    final bookId = notes.entries
        .singleWhere((entry) => entry.value.any((note) => note.id == noteId))
        .key;
    await _write(bookId, noteId, null);
  }

  @override
  Future<PersonalNote> moveNote({
    required String bookId,
    required String noteId,
    required int lineNumber,
    PdfNoteAnchor? pdfAnchor,
    int? categoryId,
  }) async {
    final stored = await _write(bookId, noteId, lineNumber);
    return stored.singleWhere((note) => note.id == noteId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  testWidgets('manager completes while the shared reader loads another book', (
    tester,
  ) async {
    final noteA = _note('ספר א', 'תוכן מנהל א');
    final noteB = _note('ספר ב', 'תוכן קורא ב');
    final repository = _Repository({
      'ספר א': [noteA],
      'ספר ב': [noteB],
    })..delayFullNotes = true;
    final reader = await _mount(tester, repository);
    expect(repository.fullRequests['ספר א'], hasLength(1));

    // The real restartable BLoC must remain free for a reader while A is pending.
    reader.add(const LoadPersonalNotes('ספר ב', categoryId: 91));
    await _pump(tester);
    repository.fullRequests['ספר ב']!.first.complete([noteB]);
    await _pump(tester);
    expect(reader.state.bookId, 'ספר ב');
    expect(reader.state.categoryId, 91);

    repository.fullRequests['ספר א']!.single.complete([noteA]);
    await _pump(tester);
    expect(find.text('תוכן מנהל א'), findsOneWidget);
    _expectExportEnabled(tester, false);
    expect(repository.fullRequests['ספר ב'], hasLength(2));
    repository.fullRequests['ספר ב']!.last.complete([noteB]);
    await _pump(tester);

    expect(find.text('תוכן מנהל א'), findsOneWidget);
    expect(find.text('תוכן קורא ב'), findsOneWidget);
    expect(reader.state.bookId, 'ספר ב');
    expect(reader.state.categoryId, 91);
    expect(reader.state.locatedNotes, [noteB]);
    _expectExportEnabled(tester, true);
  });

  testWidgets('an older book-list response cannot replace a newer refresh', (
    tester,
  ) async {
    final repository = _Repository({
      'ספר א': [_note('ספר א', 'תוכן ראשוני')],
      'ספר ג': [_note('ספר ג', 'תוכן רענון חדש')],
    });
    await _mount(tester, repository);
    repository.delayLists = true;
    final readsBefore = repository.fullReads.length;
    await tester.tap(find.byTooltip('רענן'));
    await _pump(tester);
    await tester.tap(find.byTooltip('רענן'));
    await _pump(tester);
    expect(repository.listRequests, hasLength(2));
    _expectExportEnabled(tester, false);

    repository.listRequests.last.complete([_book('ספר ג')]);
    await _pump(tester);
    expect(find.text('תוכן רענון חדש'), findsOneWidget);
    expect(find.text('תוכן ראשוני'), findsNothing);
    repository.listRequests.first.complete([_book('ספר א')]);
    await _pump(tester);

    expect(find.text('תוכן רענון חדש'), findsOneWidget);
    expect(find.text('תוכן ראשוני'), findsNothing);
    expect(repository.fullReads.skip(readsBefore), ['ספר ג']);
    _expectExportEnabled(tester, true);
  });

  testWidgets('late note completion from an older refresh is ignored', (
    tester,
  ) async {
    final old = _note('ספר א', 'תוכן מבקשה ישנה');
    final current = _note('ספר ב', 'תוכן מבקשה חדשה');
    final repository = _Repository({
      'ספר א': [old],
    })..delayFullNotes = true;
    await _mount(tester, repository);
    repository.notes
      ..clear()
      ..['ספר ב'] = [current];
    await tester.tap(find.byTooltip('רענן'));
    await _pump(tester);
    repository.fullRequests['ספר ב']!.single.complete([current]);
    await _pump(tester);
    repository.fullRequests['ספר א']!.single.complete([old]);
    await _pump(tester);

    expect(find.text('תוכן מבקשה חדשה'), findsOneWidget);
    expect(find.text('תוכן מבקשה ישנה'), findsNothing);
    expect(repository.fullReads, ['ספר א', 'ספר ב']);
    _expectExportEnabled(tester, true);
  });

  testWidgets(
    'storage changes update only affected books including create and delete',
    (
      tester,
    ) async {
      final repository = _Repository({
        'ספר א': [_note('ספר א', 'תוכן א ישן')],
        'ספר ב': [_note('ספר ב', 'תוכן ב יציב')],
      });
      final reader = await _mount(tester, repository);
      expect(repository.fullReads, ['ספר א', 'ספר ב']);
      expect(reader.state.bookId, isNull);

      repository.notes['ספר א'] = [_note('ספר א', 'תוכן א מעודכן')];
      PersonalNotesChanges.notify('ספר א');
      await _pump(tester);
      expect(find.text('תוכן א מעודכן'), findsOneWidget);
      expect(find.text('תוכן א ישן'), findsNothing);
      expect(find.text('תוכן ב יציב'), findsOneWidget);
      expect(repository.fullReads, ['ספר א', 'ספר ב']);
      expect(repository.storedReads, ['ספר א']);

      repository.notes['ספר ג'] = [_note('ספר ג', 'תוכן ספר חדש')];
      PersonalNotesChanges.notify('ספר ג');
      await _pump(tester);
      expect(find.text('תוכן ספר חדש'), findsOneWidget);
      expect(repository.fullReads, ['ספר א', 'ספר ב']);
      expect(repository.storedReads, ['ספר א', 'ספר ג']);

      repository.notes.remove('ספר ג');
      PersonalNotesChanges.notify('ספר ג');
      await _pump(tester);
      expect(find.text('תוכן ספר חדש'), findsNothing);
      expect(find.text('ספר ג'), findsNothing);
      expect(find.text('תוכן א מעודכן'), findsOneWidget);
      expect(find.text('תוכן ב יציב'), findsOneWidget);
      expect(repository.fullReads, ['ספר א', 'ספר ב']);
      expect(repository.storedReads, ['ספר א', 'ספר ג', 'ספר ג']);
      _expectExportEnabled(tester, true);
    },
  );

  testWidgets(
    'a storage change during the initial load is replayed afterward',
    (
      tester,
    ) async {
      final old = _note('ספר א', 'לפני שינוי בזמן טעינה');
      final latest = _note('ספר א', 'אחרי שינוי בזמן טעינה');
      final repository = _Repository({
        'ספר א': [old],
      })..delayFullNotes = true;
      await _mount(tester, repository);
      repository.notes['ספר א'] = [latest];
      PersonalNotesChanges.notify('ספר א');
      await _pump(tester);
      expect(repository.storedReads, isEmpty);
      _expectExportEnabled(tester, false);

      repository.fullRequests['ספר א']!.single.complete([old]);
      await _pump(tester);
      expect(find.text('אחרי שינוי בזמן טעינה'), findsOneWidget);
      expect(find.text('לפני שינוי בזמן טעינה'), findsNothing);
      expect(repository.fullReads, ['ספר א']);
      expect(repository.storedReads, ['ספר א']);
      _expectExportEnabled(tester, true);
    },
  );

  testWidgets('another write during a stored-note refresh is not lost', (
    tester,
  ) async {
    final old = _note('ספר א', 'תוכן לפני שתי כתיבות');
    final first = _note('ספר א', 'תוכן כתיבה ראשונה');
    final last = _note('ספר א', 'תוכן כתיבה אחרונה');
    final repository = _Repository({
      'ספר א': [old],
    });
    await _mount(tester, repository);
    repository.delayStoredNotes = true;
    PersonalNotesChanges.notify('ספר א');
    await _pump(tester);
    _expectExportEnabled(tester, false);
    PersonalNotesChanges.notify('ספר א');
    await _pump(tester);
    repository.storedRequests['ספר א']!.first.complete([first]);
    await _pump(tester);
    expect(repository.storedRequests['ספר א'], hasLength(2));
    _expectExportEnabled(tester, false);
    repository.storedRequests['ספר א']!.last.complete([last]);
    await _pump(tester);
    expect(find.text('תוכן כתיבה אחרונה'), findsOneWidget);
    expect(find.text('תוכן כתיבה ראשונה'), findsNothing);
    expect(repository.fullReads, ['ספר א']);
    _expectExportEnabled(tester, true);
  });

  testWidgets('manual refresh wins over an older stored-note response', (
    tester,
  ) async {
    final old = _note('ספר א', 'תוכן לפני רענון ידני');
    final latest = _note('ספר א', 'תוכן אחרי רענון ידני');
    final repository = _Repository({
      'ספר א': [old],
    });
    await _mount(tester, repository);
    repository.delayStoredNotes = true;
    PersonalNotesChanges.notify('ספר א');
    await _pump(tester);
    repository.notes['ספר א'] = [latest];
    await tester.tap(find.byTooltip('רענן'));
    await _pump(tester);
    expect(find.text('תוכן אחרי רענון ידני'), findsOneWidget);
    repository.storedRequests['ספר א']!.first.complete([old]);
    await _pump(tester);
    expect(find.text('תוכן אחרי רענון ידני'), findsOneWidget);
    expect(find.text('תוכן לפני רענון ידני'), findsNothing);
    expect(repository.storedRequests['ספר א'], hasLength(2));
    _expectExportEnabled(tester, false);
    repository.storedRequests['ספר א']!.last.complete([latest]);
    await _pump(tester);
    _expectExportEnabled(tester, true);
  });

  testWidgets(
    'one failed book preserves its notes and does not block other books',
    (
      tester,
    ) async {
      final oldA = _note('ספר א', 'תוכן א שנשמר לאחר כשל');
      final newB = _note('ספר ב', 'תוכן ב אחרי כשל א');
      final repository = _Repository({
        'ספר א': [oldA],
        'ספר ב': [_note('ספר ב', 'תוכן ב קודם')],
      });
      await _mount(tester, repository);
      repository.delayFullNotes = true;
      await tester.tap(find.byTooltip('רענן'));
      await _pump(tester);
      repository.fullRequests['ספר א']!.single.completeError(
        StateError('fixture failure'),
      );
      await _pump(tester);
      expect(repository.fullRequests['ספר ב'], hasLength(1));
      repository.fullRequests['ספר ב']!.single.complete([newB]);
      await _pump(tester);

      expect(find.text('תוכן א שנשמר לאחר כשל'), findsOneWidget);
      expect(find.text('תוכן ב אחרי כשל א'), findsOneWidget);
      expect(find.text(NotesMessages.notesLoadIncomplete), findsOneWidget);
      _expectExportEnabled(tester, false);

      repository.delayFullNotes = false;
      repository.notes['ספר ב'] = [newB];
      await tester.tap(find.text('נסה שוב'));
      await _pump(tester);
      expect(find.text('תוכן א שנשמר לאחר כשל'), findsOneWidget);
      expect(find.text('תוכן ב אחרי כשל א'), findsOneWidget);
      expect(find.text(NotesMessages.notesLoadIncomplete), findsNothing);
      _expectExportEnabled(tester, true);
    },
  );

  testWidgets(
    'stored-note failure preserves data and prevents incomplete export',
    (
      tester,
    ) async {
      final old = _note('ספר א', 'תוכן שמור לפני כשל רענון');
      final latest = _note('ספר א', 'תוכן שמור אחרי ניסיון חוזר');
      final repository = _Repository({
        'ספר א': [old],
      });
      await _mount(tester, repository);
      repository.delayStoredNotes = true;
      PersonalNotesChanges.notify('ספר א');
      await _pump(tester);
      repository.storedRequests['ספר א']!.single.completeError(
        StateError('fixture failure'),
      );
      await _pump(tester);
      expect(find.text('תוכן שמור לפני כשל רענון'), findsOneWidget);
      expect(find.text(NotesMessages.notesLoadIncomplete), findsOneWidget);
      _expectExportEnabled(tester, false);

      repository.notes['ספר א'] = [latest];
      await tester.tap(find.text('נסה שוב'));
      await _pump(tester);
      expect(find.text('תוכן שמור אחרי ניסיון חוזר'), findsOneWidget);
      expect(find.text(NotesMessages.notesLoadIncomplete), findsNothing);
      _expectExportEnabled(tester, true);
    },
  );

  testWidgets(
    'dispose ignores pending completion and unsubscribes from changes',
    (
      tester,
    ) async {
      final repository = _Repository({
        'ספר א': [_note('ספר א', 'תוכן מאוחר לאחר סגירה')],
        'ספר ב': [_note('ספר ב', 'תוכן נוסף')],
      })..delayFullNotes = true;
      await _mount(tester, repository);
      await tester.pumpWidget(const SizedBox.shrink());
      repository.fullRequests['ספר א']!.single.complete(
        repository.notes['ספר א'],
      );
      PersonalNotesChanges.notify('ספר ב');
      await _pump(tester);

      expect(repository.fullReads, ['ספר א']);
      expect(repository.storedReads, isEmpty);
      expect(repository.listReads, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'export keeps a complete snapshot across refresh before dialog build',
    (
      tester,
    ) async {
      final noteA = _note('ספר א', 'תוכן א במועד פתיחת הייצוא');
      final noteB = _note('ספר ב', 'תוכן ב במועד פתיחת הייצוא');
      final repository = _Repository({
        'ספר א': [noteA],
        'ספר ב': [noteB],
      });
      final picker = _ExportPicker();
      final previousOwner = DialogOwner.hwnd();
      captureFileSaves(picker, (bytes) => picker.bytes = bytes);
      DialogOwner.mainWindowHwnd = 7;
      addTearDown(() {
        DialogOwner.mainWindowHwnd = previousOwner;
      });
      await _mount(tester, repository);
      BarButton button(String tooltip) => tester.widget<BarButton>(
        find.byWidgetPredicate(
          (widget) => widget is BarButton && widget.tooltip == tooltip,
        ),
      );
      final refresh = button('רענן').onPressed!;
      button('גיבוי הערות').onPressed!();
      // Complete password verification and push the route without building it yet.
      await tester.idle();
      expect(find.byType(PersonalNotesExportDialog), findsNothing);

      repository.delayFullNotes = true;
      final updatedA = _note('ספר א', 'תוכן א לאחר פתיחת הייצוא');
      repository.notes
        ..clear()
        ..['ספר א'] = [updatedA]
        ..['ספר ג'] = [_note('ספר ג', 'תוכן חדש שעדיין לא נטען')];
      refresh();
      await tester.idle();
      expect(repository.fullRequests['ספר א'], hasLength(1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final dialog = tester.widget<PersonalNotesExportDialog>(
        find.byType(PersonalNotesExportDialog),
      );
      expect(dialog.allNotes, [noteA, noteB]);

      repository.fullRequests['ספר א']!.single.complete([updatedA]);
      await _pump(tester);
      repository.fullRequests['ספר ג']!.single.completeError(
        StateError('fixture failure while export dialog is open'),
      );
      await _pump(tester);
      expect(find.text(NotesMessages.notesLoadIncomplete), findsOneWidget);
      _expectExportEnabled(tester, false);

      await tester.tap(find.text('גבה'));
      await _pump(tester);
      expect(picker.bytes, isNotNull);
      final backup =
          jsonDecode(utf8.decode(picker.bytes!)) as Map<String, dynamic>;
      final exported = (backup['notes'] as List)
          .map(
            (value) =>
                PersonalNote.fromJson(Map<String, dynamic>.from(value as Map)),
          )
          .toList();
      expect(exported, [noteA, noteB]);
    },
  );

  testWidgets(
    'manager edit waits for persistence and clears only that note draft',
    (
      tester,
    ) async {
      final first = _note(
        'ספר א',
        'תוכן ראשון שמור',
      ).copyWith(id: 'edit-first');
      final second = _note(
        'ספר א',
        'תוכן שני שמור',
      ).copyWith(id: 'edit-second');
      final repository = _Repository({
        'ספר א': [first, second],
      })..delayUpdates = true;
      final drafts = PersonalNoteDraftService();
      PersonalNoteDraft draft(String content) => PersonalNoteDraft(
        content: content,
        contentPlain: content,
        contentFormat: PersonalNoteContentFormat.plain,
        updatedAt: DateTime(2026),
      );
      await drafts.saveDraft(
        bookId: first.bookId,
        categoryId: 47,
        noteId: first.id,
        draft: draft('טיוטת עריכה ראשונה'),
      );
      await drafts.saveDraft(
        bookId: second.bookId,
        categoryId: 47,
        noteId: second.id,
        draft: draft('טיוטת עריכה שנייה'),
      );
      await drafts.saveDraft(
        bookId: first.bookId,
        categoryId: 47,
        lineNumber: 1,
        draft: draft('טיוטת הערה חדשה'),
      );
      final reader = await _mount(
        tester,
        repository,
        library: Library(categories: [])..books.add(_SourceBook()),
      );
      reader.add(const LoadPersonalNotes('ספר קורא אחר', categoryId: 91));
      await _pump(tester);
      await tester.tap(find.byTooltip('עריכה').first);
      await tester.pumpAndSettle();
      final controller = tester
          .widget<quill.QuillEditor>(find.byType(quill.QuillEditor))
          .controller;
      expect(controller.document.toPlainText().trim(), 'טיוטת עריכה ראשונה');
      const updated = 'תוכן עריכה מעודכן';
      controller.replaceText(
        0,
        controller.document.length - 1,
        updated,
        TextSelection.collapsed(offset: updated.length),
      );
      await tester.pump();
      await tester.tap(find.text('שמור'));
      await _pump(tester);
      expect(repository.updateRequests, hasLength(1));
      expect(find.byType(PersonalNoteEditorDialog), findsOneWidget);
      expect(controller.readOnly, isTrue);
      repository.updateRequests.first.completeError(
        StateError('fixture write failure'),
      );
      await _pump(tester);
      expect(find.byType(PersonalNoteEditorDialog), findsOneWidget);
      expect(controller.readOnly, isFalse);
      expect(controller.document.toPlainText().trim(), updated);
      expect(
        (await drafts.loadDraft(
          bookId: first.bookId,
          categoryId: 47,
          noteId: first.id,
        ))?.contentPlain,
        'טיוטת עריכה ראשונה',
      );

      await tester.tap(find.text('שמור'));
      await _pump(tester);
      expect(repository.updateRequests, hasLength(2));
      repository.updateRequests.last.complete();
      await tester.pumpAndSettle();
      expect(find.byType(PersonalNoteEditorDialog), findsNothing);
      expect(
        repository.notes[first.bookId]!.first.contentPlain.trim(),
        updated,
      );
      expect(repository.updateTargets, [
        (bookId: first.bookId, noteId: first.id, categoryId: 47),
        (bookId: first.bookId, noteId: first.id, categoryId: 47),
      ]);
      expect(
        await drafts.loadDraft(
          bookId: first.bookId,
          categoryId: 47,
          noteId: first.id,
        ),
        isNull,
      );
      expect(
        (await drafts.loadDraft(
          bookId: second.bookId,
          categoryId: 47,
          noteId: second.id,
        ))?.contentPlain,
        'טיוטת עריכה שנייה',
      );
      expect(
        (await drafts.loadDraft(
          bookId: first.bookId,
          categoryId: 47,
          lineNumber: 1,
        ))?.contentPlain,
        'טיוטת הערה חדשה',
      );
      expect(reader.state.bookId, 'ספר קורא אחר');
      expect(reader.state.categoryId, 91);
      UiSnack.hide();
      await tester.pump();
    },
  );
  for (final reposition in [false, true]) {
    testWidgets(
      'manager acknowledges ${reposition ? "reposition" : "delete"} without a post-write list read',
      (tester) async {
        var note = _note('ספר א', 'תוכן פעולת מנהל');
        if (reposition) {
          note = note.copyWith(
            clearLineNumber: true,
            status: PersonalNoteStatus.missing,
          );
        }
        final notes = <String, List<PersonalNote>>{
          note.bookId: [note],
        };
        final database = _MutationRefreshDatabase(notes);
        final repository = _ServiceMutationRepository(
          notes,
          PersonalNotesService(database: database),
        );
        final reader = await _mount(tester, repository);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip(reposition ? 'מיקום מחדש' : 'מחיקה'));
        await tester.pumpAndSettle();
        if (reposition) {
          await tester.enterText(find.byType(EditableText).last, '3');
        }
        await tester.tap(find.text(reposition ? 'שמור' : 'מחק'));
        await tester.pumpAndSettle();

        final success = reposition
            ? NotesMessages.noteMovedToLine(3)
            : NotesMessages.noteDeleted;
        expect(database.writes, 1);
        expect(find.text(success), findsOneWidget);
        expect(database.listReads, 0);
        expect(find.textContaining('list refresh failed'), findsNothing);
        expect(reader.state.bookId, isNull);
        if (reposition) {
          expect(notes[note.bookId]!.single.lineNumber, 3);
        } else {
          expect(notes[note.bookId], isEmpty);
        }
        await expectLater(database.loadNotes(note.bookId), throwsStateError);
        await tester.pump(const Duration(seconds: 10));
      },
    );

    for (final fail in [false, true]) {
      testWidgets(
        'manager ${reposition ? "repositions" : "deletes"} only after confirmed write (failure: $fail)',
        (tester) async {
          var note = _note('ספר א', 'תוכן פעולת מנהל');
          if (reposition) {
            note = note.copyWith(
              clearLineNumber: true,
              status: PersonalNoteStatus.missing,
            );
          }
          final repository = _MutationRepository({
            'ספר א': [note],
          });
          final reader = await _mount(tester, repository);
          await tester.pumpAndSettle();
          expect(reader.state.bookId, isNull);
          await tester.tap(find.byTooltip(reposition ? 'מיקום מחדש' : 'מחיקה'));
          await tester.pumpAndSettle();
          if (reposition) {
            await tester.enterText(find.byType(EditableText).last, '3');
          }
          await tester.tap(find.text(reposition ? 'שמור' : 'מחק'));
          await _pump(tester);
          expect(repository.targets, [
            (bookId: note.bookId, noteId: note.id, line: reposition ? 3 : null),
          ]);
          final success = reposition
              ? NotesMessages.noteMovedToLine(3)
              : NotesMessages.noteDeleted;
          expect(find.text(success), findsNothing);
          expect(repository.notes[note.bookId], [note]);
          reader.add(const LoadPersonalNotes('ספר קורא אחר', categoryId: 91));
          await _pump(tester);
          if (fail) {
            repository.pendingWrite.completeError(StateError('כתיבה נדחתה'));
          } else {
            repository.pendingWrite.complete();
          }
          await tester.pumpAndSettle();
          expect(reader.state.bookId, 'ספר קורא אחר');
          if (fail) {
            expect(repository.notes[note.bookId], [note]);
            expect(find.text(success), findsNothing);
            expect(find.textContaining('כתיבה נדחתה'), findsOneWidget);
          } else {
            expect(find.text(success), findsOneWidget);
            if (reposition) {
              expect(repository.notes[note.bookId]!.single.lineNumber, 3);
            } else {
              expect(repository.notes[note.bookId], isEmpty);
            }
          }
          await tester.pump(const Duration(seconds: 10));
        },
      );
    }
  }
}
