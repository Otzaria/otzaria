import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/services/personal_note_draft_service.dart';
import 'package:otzaria/personal_notes/widgets/inline_note_editor.dart';
import 'package:otzaria/personal_notes/widgets/note_tile.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

import '../../test_helpers/memory_cache_provider.dart';

PersonalNote _note() => PersonalNote(
  id: 'existing-note',
  bookId: 'ספר בדיקה',
  lineNumber: 4,
  lastKnownLineNumber: 4,
  displayTitle: 'שורה 4',
  status: PersonalNoteStatus.located,
  content: 'תוכן קודם',
  contentPlain: 'תוכן קודם',
  contentFormat: PersonalNoteContentFormat.plain,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

Widget _harness(PersonalNoteSaveCallback onSave) => RepositoryProvider(
  create: (_) => SettingsRepository(),
  child: BlocProvider(
    create: (context) =>
        SettingsBloc(repository: context.read<SettingsRepository>()),
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: NoteTile(
            note: _note(),
            bookId: _note().bookId,
            defaultExpanded: true,
            linkableNotes: const [],
            onSave: onSave,
            onDelete: () {},
            onLinkTap: (_) {},
          ),
        ),
      ),
    ),
  ),
);

quill.QuillController _controller(WidgetTester tester) =>
    tester.widget<quill.QuillEditor>(find.byType(quill.QuillEditor)).controller;

void _replaceContent(WidgetTester tester, String content) {
  final controller = _controller(tester);
  controller.replaceText(
    0,
    controller.document.length - 1,
    content,
    TextSelection.collapsed(offset: content.length),
  );
}

Future<void> _openEditor(WidgetTester tester) async {
  await tester.tap(find.byTooltip('עריכה'));
  await tester.pumpAndSettle();
  expect(find.byType(InlineNoteEditor), findsOneWidget);
}

Future<PersonalNoteDraft?> _draft() => PersonalNoteDraftService().loadDraft(
  bookId: _note().bookId,
  noteId: _note().id,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  testWidgets(
    'an edit waits for persistence and a failed save can be retried',
    (
      tester,
    ) async {
      final requests = <Completer<void>>[];
      final results = <PersonalNoteEditorResult>[];
      Future<void> save(PersonalNoteEditorResult result) {
        results.add(result);
        final request = Completer<void>();
        requests.add(request);
        return request.future;
      }

      await tester.pumpWidget(_harness(save));
      await tester.pumpAndSettle();
      await _openEditor(tester);
      const changed = 'תוכן ערוך שנשמר רק לאחר הצלחה';
      _replaceContent(tester, changed);
      await tester.pump();
      await tester.tap(find.text('שמור'));
      await tester.pump();

      expect(results.single.contentPlain, changed);
      expect(find.byType(InlineNoteEditor), findsOneWidget);
      expect(_controller(tester).readOnly, isTrue);

      // Both the button and keyboard shortcut must honor the same pending save.
      await tester.tap(find.text('שמור'));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.tap(find.byTooltip('ביטול'));
      await tester.pump();
      expect(results, hasLength(1));
      expect(find.byType(InlineNoteEditor), findsOneWidget);

      requests.single.completeError(StateError('write failed'));
      await tester.pumpAndSettle();
      expect(find.byType(InlineNoteEditor), findsOneWidget);
      expect(_controller(tester).readOnly, isFalse);
      expect(_controller(tester).document.toPlainText().trimRight(), changed);
      await tester.pump(const Duration(milliseconds: 300));
      expect((await _draft())?.contentPlain, changed);

      await tester.tap(find.text('שמור'));
      await tester.pump();
      expect(results, hasLength(2));
      expect(results.last.contentPlain, changed);
      requests.last.complete();
      await tester.pumpAndSettle();

      expect(find.byType(InlineNoteEditor), findsNothing);
      expect(find.byTooltip('עריכה'), findsOneWidget);
      expect(await _draft(), isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a failed edit restores its draft after the note is reopened', (
    tester,
  ) async {
    var attempts = 0;
    Future<void> save(PersonalNoteEditorResult result) async {
      attempts++;
      throw StateError('write failed');
    }

    await tester.pumpWidget(_harness(save));
    await tester.pumpAndSettle();
    await _openEditor(tester);
    const changed = 'טיוטת עריכה לאחר כשל כתיבה';
    _replaceContent(tester, changed);
    await tester.pump();
    await tester.tap(find.text('שמור'));
    await tester.pumpAndSettle();
    expect(attempts, 1);
    expect(find.byType(InlineNoteEditor), findsOneWidget);

    // Removal before the debounce elapses must also retain the unsaved edit.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect((await _draft())?.contentPlain, changed);
    await tester.pumpWidget(_harness(save));
    await tester.pumpAndSettle();

    expect(find.byType(InlineNoteEditor), findsOneWidget);
    expect(_controller(tester).document.toPlainText().trimRight(), changed);
    expect(_controller(tester).readOnly, isFalse);
    expect(attempts, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a pending edit can be removed without losing its draft on error',
    (
      tester,
    ) async {
      final request = Completer<void>();
      await tester.pumpWidget(_harness((_) => request.future));
      await tester.pumpAndSettle();
      await _openEditor(tester);
      const changed = 'טיוטה בזמן כתיבה ממתינה';
      _replaceContent(tester, changed);
      await tester.pump();
      await tester.tap(find.text('שמור'));
      await tester.pump();
      expect(_controller(tester).readOnly, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      request.completeError(StateError('late write failure'));
      await tester.pumpAndSettle();
      expect((await _draft())?.contentPlain, changed);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(_harness((_) {}));
      await tester.pumpAndSettle();
      expect(find.byType(InlineNoteEditor), findsOneWidget);
      expect(_controller(tester).document.toPlainText().trimRight(), changed);
      expect(_controller(tester).readOnly, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
