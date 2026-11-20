import 'dart:io';

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
import 'package:otzaria/personal_notes/widgets/personal_note_view_dialog.dart';
import 'package:otzaria/personal_notes/widgets/personal_notes_sidebar.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

import '../../test_helpers/memory_cache_provider.dart';

class _EmptyNotesBloc extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _EmptyNotesBloc() : super(const PersonalNotesState.initial());
}

void main() {
  final database = PersonalNotesDatabase.instance;
  late Directory root;
  late BuildContext hostContext;
  final navigated = <int>[];

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

  Future<void> pumpReader(WidgetTester tester) async {
    final bloc = _EmptyNotesBloc();
    addTearDown(bloc.close);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: BlocProvider<PersonalNotesBloc>.value(
          value: bloc,
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
}
