import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/services/personal_note_draft_service.dart';
import 'package:otzaria/personal_notes/widgets/inline_note_editor.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor_dialog.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_link_dialog.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';

import '../../test_helpers/memory_cache_provider.dart';

class _DraftCache extends MemoryCacheProvider {
  int writes = 0;
  int removals = 0;
  Completer<void>? writeGate;
  Completer<void>? removeGate;

  @override
  Future<void> setObject<T>(String key, T? value) async {
    final stored = super.setObject(key, value);
    if (key.startsWith(PersonalNoteDraftService.keyPrefix)) {
      writes++;
      await writeGate?.future;
    }
    await stored;
  }

  @override
  Future<void> remove(String key) async {
    final removed = super.remove(key);
    if (key.startsWith(PersonalNoteDraftService.keyPrefix)) {
      removals++;
      await removeGate?.future;
    }
    await removed;
  }
}

class _CountingDocument extends quill.Document {
  _CountingDocument(super.data) : super.fromJson();

  int deltaReads = 0;

  @override
  Delta toDelta() {
    deltaReads++;
    return super.toDelta();
  }
}

class _ObservableFocusNode extends FocusNode {
  bool get listening => hasListeners;
}

Widget _host(Widget child) => RepositoryProvider(
  create: (_) => SettingsRepository(),
  child: BlocProvider(
    create: (context) =>
        SettingsBloc(repository: context.read<SettingsRepository>()),
    child: MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: child),
      ),
    ),
  ),
);

PersonalNote _note() => PersonalNote(
  id: 'note-1',
  bookId: 'test-book',
  lineNumber: 1,
  lastKnownLineNumber: null,
  status: PersonalNoteStatus.located,
  content: jsonEncode([
    {'insert': 'טקסט קיים\n'},
  ]),
  contentPlain: 'טקסט קיים',
  contentFormat: PersonalNoteContentFormat.quillDelta,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

quill.QuillController _quill(WidgetTester tester) =>
    tester.widget<quill.QuillEditor>(find.byType(quill.QuillEditor)).controller;

Future<void> _pumpInline(
  WidgetTester tester, {
  PersonalNote? note,
  String initialContent = '',
  ValueChanged<PersonalNoteEditorResult>? onSave,
  VoidCallback? onCancel,
}) async {
  await tester.pumpWidget(
    _host(
      InlineNoteEditor(
        note: note,
        bookId: 'test-book',
        draftLineNumber: note == null ? 1 : null,
        draftNoteId: note?.id,
        initialContent: initialContent,
        linkableNotes: const [],
        onSave: onSave ?? (_) {},
        onCancel: onCancel ?? () {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openDialog(
  WidgetTester tester, {
  ValueChanged<PersonalNoteEditorResult?>? onClosed,
}) async {
  await tester.pumpWidget(
    _host(
      Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            final result = await showDialog<PersonalNoteEditorResult>(
              context: context,
              builder: (_) => PersonalNoteEditorDialog(
                initialContent: _note().content,
                initialContentFormat: PersonalNoteContentFormat.quillDelta,
                bookId: 'test-book',
                draftLineNumber: 1,
              ),
            );
            onClosed?.call(result);
          },
          child: const Text('פתח'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('פתח'));
  await tester.pumpAndSettle();
}

Future<void> _tapAction(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(ActionButton, label).last);
  await tester.pumpAndSettle();
}

void main() {
  late _DraftCache cache;
  final drafts = PersonalNoteDraftService();

  setUp(() async {
    cache = _DraftCache();
    await Settings.init(cacheProvider: cache);
  });

  testWidgets('תנועות סמן בדיאלוג אינן מעתיקות או מסריילות את המסמך', (
    tester,
  ) async {
    await _openDialog(tester);
    final controller = _quill(tester);
    final original = controller.document;
    final document = _CountingDocument([
      for (var i = 0; i < 200; i++)
        {
          'insert': 'שורה ארוכה לבדיקת בחירה ומחזור חיים $i\n',
          'attributes': {'bold': i.isEven},
        },
    ]);
    controller.document = document;
    await tester.pump();
    original.close();
    document.deltaReads = 0;

    for (var i = 0; i < 1000; i++) {
      controller.updateSelection(
        TextSelection.collapsed(offset: i % 100),
        quill.ChangeSource.local,
      );
    }

    expect(document.deltaReads, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('שינוי עיצוב בדיאלוג מציע טיוטה ו-undo מחזיר מצב נקי', (
    tester,
  ) async {
    await _openDialog(tester);
    final controller = _quill(tester);
    controller.formatText(0, 4, quill.Attribute.bold);
    await tester.pump();
    await _tapAction(tester, 'ביטול');
    expect(find.text('שמור טיוטה'), findsOneWidget);

    await _tapAction(tester, 'ביטול');
    controller.undo();
    await tester.pump();
    await _tapAction(tester, 'ביטול');
    expect(find.byType(PersonalNoteEditorDialog), findsNothing);
    expect(find.text('שמור טיוטה'), findsNothing);
  });

  testWidgets('redo של עיצוב בדיאלוג נשמר בטיוטה', (tester) async {
    await _openDialog(tester);
    final controller = _quill(tester);
    controller.formatText(0, 4, quill.Attribute.bold);
    controller.undo();
    controller.redo();
    await tester.pump();
    await _tapAction(tester, 'ביטול');
    await _tapAction(tester, 'שמור טיוטה');

    final draft = await drafts.loadDraft(bookId: 'test-book', lineNumber: 1);
    expect(draft?.content, contains('"bold":true'));
    expect(draft?.contentPlain, 'טקסט קיים');
  });

  testWidgets('בחירה בלבד בעורך הפנימי אינה כותבת או מוחקת טיוטה', (
    tester,
  ) async {
    await _pumpInline(tester, note: _note());
    cache.writes = cache.removals = 0;
    final controller = _quill(tester);
    for (var i = 0; i < 30; i++) {
      controller.updateSelection(
        TextSelection.collapsed(offset: i % 8),
        quill.ChangeSource.local,
      );
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(cache.writes, 0);
    expect(cache.removals, 0);
  });

  testWidgets('שינוי עיצוב ישיר, undo ו-redo מעדכנים טיוטה פנימית', (
    tester,
  ) async {
    await _pumpInline(tester, note: _note());
    final controller = _quill(tester);
    controller.document.format(0, 4, quill.Attribute.bold);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      (await drafts.loadDraft(bookId: 'test-book', noteId: 'note-1'))?.content,
      contains('"bold":true'),
    );

    controller.undo();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      await drafts.loadDraft(bookId: 'test-book', noteId: 'note-1'),
      isNull,
    );

    controller.redo();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      (await drafts.loadDraft(bookId: 'test-book', noteId: 'note-1'))?.content,
      contains('"bold":true'),
    );
  });

  testWidgets('הסרה עם אירוע שטרם נמסר שומרת צילום לפני שחרור הבקר', (
    tester,
  ) async {
    await _pumpInline(tester);
    final controller = _quill(tester);
    final gate = cache.writeGate = Completer<void>();
    controller.document.insert(0, 'טיוטה אחרונה');
    await tester.pumpWidget(const SizedBox.shrink());

    expect(controller.document.documentChangeObserver.isClosed, isTrue);
    gate.complete();
    await tester.pump();
    expect(
      (await drafts.loadDraft(
        bookId: 'test-book',
        lineNumber: 1,
      ))?.contentPlain,
      'טיוטה אחרונה',
    );
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('שמירה שאושרה מוסרת את התוכן גם כשהניקוי מסתיים לאחר הסרה', (
    tester,
  ) async {
    PersonalNoteEditorResult? saved;
    await _pumpInline(
      tester,
      note: _note(),
      onSave: (result) => saved = result,
    );
    final gate = cache.removeGate = Completer<void>();
    await tester.tap(find.widgetWithText(ActionButton, 'שמור'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    gate.complete();
    await tester.pump();

    expect(saved?.contentPlain, 'טקסט קיים');
    expect(tester.takeException(), isNull);
  });

  for (final save in [true, false]) {
    testWidgets(
      'flush מושהה אינו מחזיר טיוטה אחרי ${save ? 'שמירה' : 'ביטול'}',
      (
        tester,
      ) async {
        PersonalNoteEditorResult? saved;
        var cancelled = false;
        await _pumpInline(
          tester,
          note: _note(),
          onSave: (result) => saved = result,
          onCancel: () => cancelled = true,
        );
        final gate = cache.writeGate = Completer<void>();
        _quill(tester).replaceText(
          0,
          0,
          'שינוי ',
          const TextSelection.collapsed(offset: 6),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(cache.writes, 1);

        if (save) {
          await _tapAction(tester, 'שמור');
          expect(saved?.contentPlain, 'שינוי טקסט קיים');
        } else {
          await _tapAction(tester, 'ביטול');
          await _tapAction(tester, 'סגור בלי לשמור');
          expect(cancelled, isTrue);
        }
        gate.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          await drafts.loadDraft(bookId: 'test-book', noteId: 'note-1'),
          isNull,
        );
      },
    );
  }

  for (final dialog in [true, false]) {
    for (final rich in [true, false]) {
      testWidgets(
        'הדבקה ${rich ? 'מעוצבת' : 'רגילה'} שמסתיימת אחרי סגירת '
        '${dialog ? 'דיאלוג' : 'עורך פנימי'} מתבטלת',
        (tester) async {
          if (dialog) {
            await _openDialog(tester);
          } else {
            await _pumpInline(tester, note: _note());
          }
          final controller = _quill(tester);
          if (rich) {
            controller.formatText(0, 4, quill.Attribute.bold);
            controller.updateSelection(
              const TextSelection(baseOffset: 0, extentOffset: 4),
              quill.ChangeSource.local,
            );
            // ignore: experimental_member_use
            controller.clipboardSelection(true);
            await tester.pump();
          }
          final before = controller.document.toDelta();
          final clipboard = Completer<Object?>();
          var reads = 0;
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'Clipboard.getData') {
                reads++;
                return clipboard.future;
              }
              return null;
            },
          );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger
                .setMockMethodCallHandler(SystemChannels.platform, null),
          );
          var updated = 0;
          // ignore: experimental_member_use
          final paste = controller.clipboardPaste(
            updateEditor: () => updated++,
          );
          await tester.pump();
          expect(reads, 1);
          await tester.pumpWidget(const SizedBox.shrink());
          clipboard.complete({'text': rich ? 'טקסט' : 'הדבקה חדשה'});
          await tester.pump();

          expect(await paste, isFalse);
          expect(updated, 0);
          expect(controller.document.toDelta(), before);
          expect(controller.document.documentChangeObserver.isClosed, isTrue);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('הדבקת מקלדת שהושלמה אחרי הסרה אינה גוללת את העורך הישן', (
    tester,
  ) async {
    await _pumpInline(tester, note: _note());
    final editor = tester.state<quill.QuillRawEditorState>(
      find.byType(quill.QuillRawEditor),
    );
    final clipboard = Completer<Object?>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async =>
          call.method == 'Clipboard.getData' ? clipboard.future : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final paste = editor.pasteText(SelectionChangedCause.keyboard);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    clipboard.complete({'text': 'טקסט מהלוח'});
    await tester.pump();
    await paste;
    expect(tester.takeException(), isNull);
  });

  testWidgets('גוף העורך מחליף listener של focus ומשאיר בעלות אצל היוצר', (
    tester,
  ) async {
    final first = _ObservableFocusNode();
    final second = _ObservableFocusNode();
    final focus = ValueNotifier<FocusNode>(first);
    final scroll = ScrollController();
    final controller = buildPersonalNoteEditorController(
      initialContent: _note().content,
      initialFormat: PersonalNoteContentFormat.quillDelta,
    );
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    addTearDown(focus.dispose);
    addTearDown(scroll.dispose);
    addTearDown(controller.quillController.dispose);
    await tester.pumpWidget(
      _host(
        ValueListenableBuilder<FocusNode>(
          valueListenable: focus,
          builder: (_, node, _) => PersonalNoteEditorBody(
            controller: controller,
            focusNode: node,
            scrollController: scroll,
            autofocus: false,
            linkableNotes: const [],
          ),
        ),
      ),
    );
    focus.value = second;
    await tester.pump();
    expect(first.listening, isFalse);
    expect(second.listening, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(second.listening, isFalse);
    expect(
      controller.quillController.document.documentChangeObserver.isClosed,
      isFalse,
    );
  });

  testWidgets('תוצאת חלונית קישור אחרי הסרת העורך אינה משנה מסמך ששוחרר', (
    tester,
  ) async {
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    await tester.pumpWidget(
      _host(
        ValueListenableBuilder<bool>(
          valueListenable: visible,
          builder: (_, show, _) => show
              ? InlineNoteEditor(
                  note: _note(),
                  bookId: 'test-book',
                  draftNoteId: 'note-1',
                  linkableNotes: const [],
                  onSave: (_) {},
                  onCancel: () {},
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final controller = _quill(tester);
    final before = controller.document.toDelta();
    await tester.tap(find.byTooltip('הוסף קישור'));
    await tester.pumpAndSettle();
    visible.value = false;
    await tester.pumpAndSettle();
    Navigator.of(
      tester.element(find.byType(PersonalNoteLinkDialog)),
    ).pop(
      const PersonalNoteLinkTarget(label: 'קישור', url: 'https://example.org'),
    );
    await tester.pumpAndSettle();

    expect(controller.document.toDelta(), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('30 מחזורי דיאלוג משחררים את המסמך בשמירה ובביטול', (
    tester,
  ) async {
    var closedDocuments = 0;
    final subscriptions = <StreamSubscription<quill.DocChange>>[];
    addTearDown(() async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    });
    for (var cycle = 0; cycle < 30; cycle++) {
      await _openDialog(tester);
      final controller = _quill(tester);
      subscriptions.add(
        controller.changes.listen(null, onDone: () => closedDocuments++),
      );
      if (cycle.isEven) {
        await _tapAction(tester, 'שמור');
      } else {
        await _tapAction(tester, 'ביטול');
      }
      expect(find.byType(PersonalNoteEditorDialog), findsNothing);
    }
    expect(closedDocuments, 30);
    expect(tester.takeException(), isNull);
  });

  testWidgets('30 מחזורי עורך פנימי משחררים מסמך ושומרים טיוטה לפני debounce', (
    tester,
  ) async {
    var closedDocuments = 0;
    final subscriptions = <StreamSubscription<quill.DocChange>>[];
    addTearDown(() async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    });
    for (var cycle = 0; cycle < 30; cycle++) {
      await _pumpInline(tester);
      final controller = _quill(tester);
      subscriptions.add(
        controller.changes.listen(null, onDone: () => closedDocuments++),
      );
      controller.document.insert(0, 'טיוטה $cycle');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(
        (await drafts.loadDraft(
          bookId: 'test-book',
          lineNumber: 1,
        ))?.contentPlain,
        'טיוטה $cycle',
      );
    }
    await tester.pump(const Duration(seconds: 1));
    expect(closedDocuments, 30);
    expect(tester.takeException(), isNull);
  });
}
