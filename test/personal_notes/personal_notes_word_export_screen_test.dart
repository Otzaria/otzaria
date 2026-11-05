import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/windowing/dialog_owner.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/personal_notes/view/personal_notes_screen.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../helpers/memory_settings_cache.dart';

class _LibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

class _NotesRepository extends PersonalNotesRepository {
  final notes = [
    for (var line = 1; line <= 3; line++)
      PersonalNote(
        id: 'note-$line',
        bookId: 'ספר בדיקה|user',
        lineNumber: line,
        displayTitle: 'כותרת $line',
        lastKnownLineNumber: null,
        status: PersonalNoteStatus.located,
        content: 'תוכן $line',
        contentPlain: 'תוכן $line',
        contentFormat: PersonalNoteContentFormat.plain,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
  ];

  @override
  Future<List<BookNotesInfo>> listBooksWithNotes() async => [
    BookNotesInfo(
      bookId: 'ספר בדיקה|user',
      noteCount: notes.length,
      lastUpdated: DateTime(2026),
    ),
  ];

  @override
  Future<List<PersonalNote>> loadNotes(
    String bookId, {
    int? categoryId,
  }) async => notes;
}

class _TocProvider implements LibraryProvider {
  @override
  Future<List<TocEntry>?> getBookToc(
    String title,
    int categoryId,
    String fileType, {
    BookSource preferSource = BookSource.official,
  }) async => [TocEntry(text: 'פרק א', index: 0, level: 1)];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    await UserBooksDatabaseHolder.instance.close();
    root = await Directory.systemTemp.createTemp('notes-word-location-');
    AppPaths.debugOverrideDataRootPath(root.path);
    final db = MyDatabase.withPath(
      await UserBooksDatabaseHolder.resolveDbPath(),
    );
    await SeforimRepository(db).ensureInitialized();
    final raw = await db.database;
    raw.execute(
      "INSERT INTO book (id, categoryId, sourceId, title) "
      "VALUES (1, 1, 1, 'ספר בדיקה')",
    );
    for (final (index, ref) in [(0, 'א, א'), (1, 'א, ב'), (2, '   ')]) {
      raw.execute(
        'INSERT INTO line (id, bookId, lineIndex, content, heRef) '
        'VALUES (?, 1, ?, ?, ?)',
        [index + 1, index, 'שורה $index', ref],
      );
    }
    db.close();
    // פתיחת הקובץ ואתחול המנוע צריכים להסתיים מחוץ לשעון המדומה של ה-widget.
    await UserBooksDatabaseHolder.instance.repository;
    final provider = _TocProvider();
    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: {
        BookCompositeKey.create(
          title: 'ספר בדיקה',
          categoryId: 1,
          fileType: 'txt',
          source: BookSource.user,
        ): provider,
      },
      providers: [provider],
    );
  });

  tearDown(() async {
    LibraryProviderManager.instance.resetForTesting();
    await UserBooksDatabaseHolder.instance.close();
    AppPaths.debugOverrideDataRootPath(null);
    await root.delete(recursive: true);
  });

  testWidgets('ייצוא משתמש בכתובת השורה המדויקת וב-TOC רק כגיבוי', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final picker = _ExportPicker();
    final previousPicker = FilePickerPlatform.instance;
    final previousOwner = DialogOwner.hwnd();
    FilePickerPlatform.instance = picker;
    DialogOwner.mainWindowHwnd = 7;
    addTearDown(() {
      FilePickerPlatform.instance = previousPicker;
      DialogOwner.mainWindowHwnd = previousOwner;
    });
    final repository = _NotesRepository();
    final notesBloc = PersonalNotesBloc(repository: repository);
    final settingsBloc = SettingsBloc(repository: SettingsRepository());
    final libraryBloc = _LibraryBloc();
    addTearDown(notesBloc.close);
    addTearDown(settingsBloc.close);
    addTearDown(libraryBloc.close);
    whenListen(
      libraryBloc,
      const Stream<LibraryState>.empty(),
      initialState: LibraryState(
        library: Library(categories: [])
          ..books.add(
            TextBook(
              id: 1,
              title: 'ספר בדיקה',
              categoryId: 1,
              source: BookSource.user,
            ),
          ),
        isLoading: false,
      ),
    );
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          RepositoryProvider<SettingsRepository>.value(
            value: SettingsRepository(),
          ),
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
          BlocProvider<LibraryBloc>.value(value: libraryBloc),
          BlocProvider<PersonalNotesBloc>.value(value: notesBloc),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: PersonalNotesManagerScreen(repository: repository),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('ייצוא לוורד'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ייצא'));
    for (var i = 0; i < 100 && picker.bytes == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(picker.bytes, isNotNull);
    final archive = ZipDecoder().decodeBytes(picker.bytes!);
    final document = utf8.decode(
      archive.findFile('word/document.xml')!.content as List<int>,
    );
    expect(document, contains('א, א'));
    expect(document, contains('א, ב'));
    expect(document, contains('פרק א'));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
