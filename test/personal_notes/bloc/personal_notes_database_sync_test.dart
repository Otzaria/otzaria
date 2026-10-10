import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/personal_notes/services/personal_notes_service.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/personal_notes/widgets/commentary_notes_section.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

import '../../test_helpers/memory_cache_provider.dart';

class _ServiceRepository extends PersonalNotesRepository {
  final service = PersonalNotesService();
  Completer<void>? contentGate;
  int storedCalls = 0;
  int contentCalls = 0;

  @override
  Future<List<PersonalNote>> loadNotes(String bookId, {int? categoryId}) async {
    contentCalls++;
    // קריאת תוכן הספר מסתיימת לפני קריאת SQLite, כמו במאגר האמיתי.
    await contentGate?.future;
    return service.loadNotes(
      bookId: bookId,
      bookContent: 'שורה ראשונה\nשורה שנייה',
    );
  }

  @override
  Future<List<PersonalNote>> loadStoredNotes(String bookId) {
    storedCalls++;
    return super.loadStoredNotes(bookId);
  }

  @override
  Future<List<PersonalNote>> deleteNote({
    required String bookId,
    required String noteId,
    int? categoryId,
  }) => service.deleteNote(
    bookId: bookId,
    bookContent: 'שורה ראשונה\nשורה שנייה',
    noteId: noteId,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final database = PersonalNotesDatabase.instance;
  late Directory root;
  late _ServiceRepository repository;
  late PersonalNotesBloc bloc;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() async {
    await database.close();
    root = await Directory.systemTemp.createTemp('notes_database_sync_');
    AppPaths.debugOverrideDataRootPath(root.path);
    await Settings.setValue(
      SettingsRepository.keyDatabasesPath,
      '${root.path}/databases',
    );
    repository = _ServiceRepository();
    bloc = PersonalNotesBloc(repository: repository);
    final loaded = bloc.stream.firstWhere(
      (state) => state.bookId == 'רש"י' && !state.isLoading,
    );
    bloc.add(const LoadPersonalNotes('רש"י'));
    await loaded;
  });

  tearDown(() async {
    await bloc.close();
    await database.close();
    AppPaths.debugOverrideDataRootPath(null);
    await Settings.setValue(SettingsRepository.keyDatabasesPath, '');
    await root.delete(recursive: true);
  });

  test('כתיבה בזמן קריאת תוכן נבדקת במסד רק לאחר סיום הטעינה', () async {
    repository.contentGate = Completer<void>();
    bloc.add(const LoadPersonalNotes('רש"י'));
    await pumpEventQueue();
    await database.insertNote(_note());
    await pumpEventQueue();

    expect(repository.storedCalls, 0);
    repository.contentGate!.complete();
    repository.contentGate = null;
    await pumpEventQueue();

    expect(bloc.state.locatedNotes.map((note) => note.id), ['note']);
    expect(repository.storedCalls, 1);
    expect(repository.contentCalls, 2);
  });

  test('מחיקה דרך השירות וה-bloc אינה קוראת שוב את תוכן הספר', () async {
    await database.insertNote(_note());
    await pumpEventQueue();
    final contentCalls = repository.contentCalls;
    bloc.add(const DeletePersonalNote(bookId: 'רש"י', noteId: 'note'));
    await pumpEventQueue();

    expect(bloc.state.locatedNotes, isEmpty);
    expect(await database.getNote('note'), isNull);
    expect(repository.contentCalls, contentCalls);
  });

  test('הערה מיובאת עם מיקום ישן מיושבת ברענון הרקע', () async {
    await database.batchInsertNotes([_note().copyWith(lineNumber: 2)]);
    await pumpEventQueue();

    expect(bloc.state.locatedNotes.single.lineNumber, 1);
    expect((await database.getNote('note'))!.lineNumber, 1);
  });

  testWidgets('אזור הערות המפרשים מתעדכן גם במחיקת ספר ובייבוא אצווה', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommentaryNotesSection(
            bookIds: const ['רש"י'],
            onOpenNote: (_, _) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('תוכן ההערה'), findsNothing);

    await tester.runAsync(() async {
      final refreshed = bloc.stream.firstWhere(
        (state) => state.locatedNotes.any((note) => note.id == 'note'),
      );
      await database.batchInsertNotes([_note()]);
      await refreshed;
    });
    await tester.pumpAndSettle();
    expect(find.text('תוכן ההערה'), findsOneWidget);
    expect(bloc.state.locatedNotes.map((note) => note.id), ['note']);
    expect(bloc.state.errorMessage, isNull);

    await tester.runAsync(() async {
      final refreshed = bloc.stream.firstWhere(
        (state) => state.locatedNotes.isEmpty,
      );
      await database.deleteBookNotes('רש"י');
      await refreshed;
    });
    await tester.pumpAndSettle();
    expect(find.text('תוכן ההערה'), findsNothing);
    expect(find.text('הערות על המפרשים המוצגים'), findsNothing);
    expect(bloc.state.locatedNotes, isEmpty);
    expect(bloc.state.errorMessage, isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

PersonalNote _note() => PersonalNote(
  id: 'note',
  bookId: 'רש"י',
  lineNumber: 1,
  displayTitle: 'שורה ראשונה',
  lastKnownLineNumber: 1,
  status: PersonalNoteStatus.located,
  content: 'תוכן ההערה',
  contentPlain: 'תוכן ההערה',
  contentFormat: PersonalNoteContentFormat.plain,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);
