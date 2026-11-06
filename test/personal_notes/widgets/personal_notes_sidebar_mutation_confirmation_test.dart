import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show FlutterQuillLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/notes_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/personal_notes/widgets/personal_notes_sidebar.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';

import '../../test_helpers/memory_cache_provider.dart';

class _PendingRepository extends PersonalNotesRepository {
  final note = PersonalNote(
    id: 'note',
    bookId: 'ספר בדיקה',
    lineNumber: 1,
    lastKnownLineNumber: null,
    status: PersonalNoteStatus.located,
    content: 'תוכן ההערה',
    contentPlain: 'תוכן ההערה',
    contentFormat: PersonalNoteContentFormat.plain,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final pendingWrite = Completer<List<PersonalNote>>();
  final targets = <({String bookId, String noteId, int lineNumber})>[];

  @override
  Future<List<PersonalNote>> loadNotes(
    String bookId, {
    int? categoryId,
  }) async => [note];

  @override
  Future<List<PersonalNote>> loadStoredNotes(String bookId) async => [note];

  @override
  Future<List<PersonalNote>> repositionNote({
    required String bookId,
    required String noteId,
    required int lineNumber,
    PdfNoteAnchor? pdfAnchor,
    int? categoryId,
  }) {
    targets.add((bookId: bookId, noteId: noteId, lineNumber: lineNumber));
    return pendingWrite.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  testWidgets('sidebar does not announce a failed reposition as successful', (
    tester,
  ) async {
    final repository = _PendingRepository();
    final bloc = PersonalNotesBloc(repository: repository);
    addTearDown(() async {
      if (repository.targets.isNotEmpty &&
          !repository.pendingWrite.isCompleted) {
        repository.pendingWrite.completeError(StateError('test cleanup'));
      }
      UiSnack.hide();
      await tester.pumpWidget(const SizedBox.shrink());
      await bloc.close();
    });
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        locale: const Locale('he'),
        supportedLocales: const [Locale('he'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        home: Scaffold(
          body: BlocProvider<PersonalNotesBloc>.value(
            value: bloc,
            child: PersonalNotesSidebar(
              bookId: repository.note.bookId,
              repository: repository,
              visibleLineIndices: const [0],
              onNavigateToLine: (_, {note}) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('שנה שיוך לשורה נבחרת'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).last, '3');
    await tester.tap(find.text('שמור'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final success = NotesMessages.noteAssignedToLine(3);
    final announcedBeforeWrite = find.text(success).evaluate().isNotEmpty;

    repository.pendingWrite.completeError(StateError('שיוך נדחה'));
    await tester.pumpAndSettle();

    expect(repository.targets, [
      (
        bookId: repository.note.bookId,
        noteId: repository.note.id,
        lineNumber: 3,
      ),
    ]);
    expect(announcedBeforeWrite, isFalse);
    expect(find.textContaining('שיוך נדחה'), findsOneWidget);
    expect(find.text(success), findsNothing);
  });
}
