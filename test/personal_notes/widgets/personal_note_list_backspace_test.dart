import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/widgets/inline_note_editor.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor_dialog.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

import '../../test_helpers/memory_cache_provider.dart';

enum _Surface { inline, dialog }

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

Future<quill.QuillController> _open(
  WidgetTester tester,
  List<Map<String, dynamic>> delta, {
  _Surface surface = _Surface.inline,
}) async {
  final content = jsonEncode(delta);
  await tester.pumpWidget(
    _host(
      surface == _Surface.inline
          ? InlineNoteEditor(
              bookId: 'list-backspace-test',
              draftLineNumber: 1,
              initialContent: content,
              initialFormat: PersonalNoteContentFormat.quillDelta,
              linkableNotes: const [],
              onSave: (_) {},
              onCancel: () {},
            )
          : Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<PersonalNoteEditorResult>(
                  context: context,
                  builder: (_) => Directionality(
                    textDirection: TextDirection.rtl,
                    child: PersonalNoteEditorDialog(
                      initialContent: content,
                      initialContentFormat:
                          PersonalNoteContentFormat.quillDelta,
                    ),
                  ),
                ),
                child: const Text('פתח'),
              ),
            ),
    ),
  );
  if (surface == _Surface.dialog) {
    await tester.tap(find.text('פתח'));
  }
  await tester.pumpAndSettle();
  final editor = tester.widget<quill.QuillEditor>(
    find.byType(quill.QuillEditor),
  );
  editor.focusNode.requestFocus();
  await tester.pumpAndSettle();
  return editor.controller;
}

List<Map<String, dynamic>> _list(String kind, {String second = ''}) => [
  {'insert': 'ראשון'},
  {
    'insert': '\n',
    'attributes': {'list': kind},
  },
  if (second.isNotEmpty) {'insert': second},
  {
    'insert': '\n',
    'attributes': {'list': kind},
  },
];

Map<String, dynamic> _lineAttributes(
  quill.QuillController controller,
  int at,
) => controller.document.queryChild(at).node!.toDelta().last.attributes ?? {};

Future<void> _select(
  WidgetTester tester,
  quill.QuillController controller,
  TextSelection selection,
) async {
  controller.updateSelection(selection, quill.ChangeSource.local);
  await tester.pump();
}

Future<void> _type(
  WidgetTester tester,
  quill.QuillController controller,
  String text,
) async {
  final selection = controller.selection;
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: controller.document.toPlainText().replaceRange(
        selection.start,
        selection.end,
        text,
      ),
      selection: TextSelection.collapsed(offset: selection.start + text.length),
    ),
  );
  await tester.pump();
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  expect(tester.takeException(), isNull);
}

void _testOnWindows(String description, WidgetTesterCallback callback) {
  testWidgets(description, (tester) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    final previousErrorHandler = FlutterError.onError!;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    FlutterError.onError = (details) {
      // takeException below keeps the assertion strict; retain its original stack.
      debugPrintSynchronously(
        'List keyboard error: ${details.exceptionAsString()}',
      );
      debugPrintSynchronously(details.stack.toString());
      previousErrorHandler(details);
    };
    try {
      await callback(tester);
    } finally {
      FlutterError.onError = previousErrorHandler;
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });
}

void main() {
  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  for (final surface in _Surface.values) {
    for (final kind in ['bullet', 'ordered']) {
      _testOnWindows(
        'Backspace אחרי Enter יוצא מרשימת $kind ב-${surface.name}',
        (
          tester,
        ) async {
          final controller = await _open(tester, [
            {'insert': 'ראשון'},
            {
              'insert': '\n',
              'attributes': {'list': kind},
            },
          ], surface: surface);
          await _select(
            tester,
            controller,
            const TextSelection.collapsed(offset: 5),
          );
          await _type(tester, controller, '\n');
          expect(controller.document.toPlainText(), 'ראשון\n\n');
          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 6),
          );
          expect(_lineAttributes(controller, 6)['list'], kind);

          await _press(tester, LogicalKeyboardKey.backspace);

          expect(controller.document.toDelta().toJson(), [
            {'insert': 'ראשון'},
            {
              'insert': '\n',
              'attributes': {'list': kind},
            },
            {'insert': '\n'},
          ]);
          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 6),
          );
          await _type(tester, controller, 'המשך');
          expect(controller.document.toPlainText(), 'ראשון\nהמשך\n');
          expect(_lineAttributes(controller, 6)['list'], isNull);
          expect(_lineAttributes(controller, 0)['list'], kind);
          await _close(tester);
        },
      );
    }
  }

  for (final kind in ['bullet', 'ordered']) {
    _testOnWindows('Backspace ברשימת $kind מקוננת מוריד רמה ושומר עיצוב', (
      tester,
    ) async {
      final controller = await _open(tester, [
        {
          'insert': 'ראשון',
          'attributes': {'bold': true},
        },
        {
          'insert': '\n',
          'attributes': {'list': kind},
        },
        {
          'insert': '\n',
          'attributes': {
            'list': kind,
            'indent': 2,
            'align': 'right',
            'direction': 'rtl',
          },
        },
      ]);
      await _select(
        tester,
        controller,
        const TextSelection.collapsed(offset: 6),
      );
      for (final indent in [1, 0]) {
        await _press(tester, LogicalKeyboardKey.backspace);
        expect(_lineAttributes(controller, 6), {
          'list': kind,
          if (indent > 0) 'indent': indent,
          'align': 'right',
          'direction': 'rtl',
        });
        expect(controller.document.toPlainText(), 'ראשון\n\n');
        expect(controller.selection, const TextSelection.collapsed(offset: 6));
      }
      await _press(tester, LogicalKeyboardKey.backspace);
      expect(_lineAttributes(controller, 6), {
        'align': 'right',
        'direction': 'rtl',
      });
      expect(controller.document.toPlainText(), 'ראשון\n\n');
      expect(controller.document.toDelta().first.attributes, {'bold': true});
      expect(_lineAttributes(controller, 0), {'list': kind});
      expect(controller.selection, const TextSelection.collapsed(offset: 6));
      await _close(tester);
    });
  }

  _testOnWindows('פריט שאינו ריק שומר את מחיקת הטקסט הרגילה', (tester) async {
    final controller = await _open(tester, _list('bullet', second: 'שני'));
    await _select(tester, controller, const TextSelection.collapsed(offset: 7));
    await _press(tester, LogicalKeyboardKey.backspace);
    expect(controller.document.toPlainText(), 'ראשון\nני\n');
    expect(controller.selection, const TextSelection.collapsed(offset: 6));
    expect(_lineAttributes(controller, 6)['list'], 'bullet');
    await _close(tester);
  });

  _testOnWindows('Backspace בתחילת פריט שאינו ריק עדיין ממזג שורות', (
    tester,
  ) async {
    final controller = await _open(tester, _list('bullet', second: 'שני'));
    await _select(tester, controller, const TextSelection.collapsed(offset: 6));
    await _press(tester, LogicalKeyboardKey.backspace);
    expect(controller.document.toPlainText(), 'ראשוןשני\n');
    expect(controller.selection, const TextSelection.collapsed(offset: 5));
    expect(_lineAttributes(controller, 0)['list'], 'bullet');
    await _close(tester);
  });

  _testOnWindows('בחירה שמתחילה בפריט ריק נמחקת כטקסט', (tester) async {
    final controller = await _open(tester, _list('bullet'));
    await _select(
      tester,
      controller,
      const TextSelection(baseOffset: 6, extentOffset: 5),
    );
    await _press(tester, LogicalKeyboardKey.backspace);
    expect(controller.document.toPlainText(), 'ראשון\n');
    expect(controller.selection, const TextSelection.collapsed(offset: 5));
    expect(_lineAttributes(controller, 0)['list'], 'bullet');
    await _close(tester);
  });

  _testOnWindows('Delete קדימה בפריט ריק ממשיך למחוק קדימה', (tester) async {
    final controller = await _open(tester, [
      ..._list('bullet'),
      {'insert': 'אחרון'},
      {
        'insert': '\n',
        'attributes': {'list': 'bullet'},
      },
    ]);
    await _select(tester, controller, const TextSelection.collapsed(offset: 6));
    await _press(tester, LogicalKeyboardKey.delete);
    expect(controller.document.toPlainText(), 'ראשון\nאחרון\n');
    expect(controller.selection, const TextSelection.collapsed(offset: 6));
    expect(_lineAttributes(controller, 6)['list'], 'bullet');
    await _close(tester);
  });

  for (final modifier in [
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.shiftLeft,
  ]) {
    _testOnWindows('${modifier.keyLabel}+Backspace אינו הופך פריט לפסקה', (
      tester,
    ) async {
      final controller = await _open(tester, _list('bullet'));
      await _select(
        tester,
        controller,
        const TextSelection.collapsed(offset: 6),
      );
      final before = controller.document.toDelta();
      final selection = controller.selection;
      await tester.sendKeyDownEvent(modifier);
      await _press(tester, LogicalKeyboardKey.backspace);
      await tester.sendKeyUpEvent(modifier);
      expect(
        _lineAttributes(controller, controller.selection.start)['list'],
        'bullet',
      );
      if (modifier == LogicalKeyboardKey.altLeft) {
        expect(controller.document.toDelta(), before);
        expect(controller.selection, selection);
      }
      await _close(tester);
    });
  }

  _testOnWindows('Alt+Backspace בפריט הראשון עדיין מסיר רשימה', (tester) async {
    final controller = await _open(tester, [
      {
        'insert': '\n',
        'attributes': {
          'list': 'bullet',
          'indent': 2,
          'align': 'right',
          'direction': 'rtl',
        },
      },
    ]);
    await _select(tester, controller, const TextSelection.collapsed(offset: 0));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await _press(tester, LogicalKeyboardKey.backspace);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    expect(controller.document.toDelta().toJson(), [
      {'insert': '\n'},
    ]);
    expect(controller.selection, const TextSelection.collapsed(offset: 0));
    await _close(tester);
  });

  _testOnWindows('Alt+Backspace חוזר בפסקה ריקה אינו משנה תוכן', (
    tester,
  ) async {
    final controller = await _open(tester, [
      {'insert': '\n'},
    ]);
    await _select(tester, controller, const TextSelection.collapsed(offset: 0));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await _press(tester, LogicalKeyboardKey.backspace);
    await _press(tester, LogicalKeyboardKey.backspace);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    expect(controller.document.toDelta().toJson(), [
      {'insert': '\n'},
    ]);
    expect(controller.selection, const TextSelection.collapsed(offset: 0));
    await _close(tester);
  });

  _testOnWindows('פסקה ריקה אחרי רשימה עדיין נמחקת בלי לרשת רשימה', (
    tester,
  ) async {
    final controller = await _open(tester, [
      {'insert': 'ראשון'},
      {
        'insert': '\n',
        'attributes': {'list': 'bullet'},
      },
      {'insert': '\n'},
    ]);
    await _select(tester, controller, const TextSelection.collapsed(offset: 6));
    await _press(tester, LogicalKeyboardKey.backspace);
    expect(controller.document.toPlainText(), 'ראשון\n');
    expect(controller.selection, const TextSelection.collapsed(offset: 5));
    await _close(tester);
  });

  _testOnWindows('יציאה מרשימה נשמרת ב-undo וב-redo', (tester) async {
    final controller = await _open(tester, _list('bullet'));
    await _select(tester, controller, const TextSelection.collapsed(offset: 6));
    final before = controller.document.toDelta();
    await _press(tester, LogicalKeyboardKey.backspace);
    final after = controller.document.toDelta();
    expect(controller.document.toPlainText(), 'ראשון\n\n');
    expect(_lineAttributes(controller, 6)['list'], isNull);
    controller.undo();
    await tester.pump();
    expect(controller.document.toDelta(), before);
    controller.redo();
    await tester.pump();
    expect(controller.document.toDelta(), after);
    await _close(tester);
  });

  _testOnWindows('Backspace בפריט הראשון שומר יישור וכיווניות', (tester) async {
    final controller = await _open(tester, [
      {
        'insert': '\n',
        'attributes': {
          'list': 'bullet',
          'align': 'right',
          'direction': 'rtl',
        },
      },
    ]);
    await _press(tester, LogicalKeyboardKey.backspace);
    expect(_lineAttributes(controller, 0), {
      'align': 'right',
      'direction': 'rtl',
    });
    expect(controller.document.toPlainText(), '\n');
    expect(controller.selection, const TextSelection.collapsed(offset: 0));
    await _close(tester);
  });

  _testOnWindows('מצב קריאה בלבד אינו משנה פריט ריק', (tester) async {
    final owner = buildPersonalNoteEditorController(
      initialContent: jsonEncode(_list('bullet')),
      initialFormat: PersonalNoteContentFormat.quillDelta,
    );
    final controller = owner.quillController
      ..readOnly = true
      ..updateSelection(
        const TextSelection.collapsed(offset: 6),
        quill.ChangeSource.local,
      );
    final focus = FocusNode();
    final scroll = ScrollController();
    addTearDown(owner.dispose);
    addTearDown(focus.dispose);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      _host(
        PersonalNoteEditorBody(
          controller: owner,
          focusNode: focus,
          scrollController: scroll,
          autofocus: true,
          linkableNotes: const [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final before = controller.document.toDelta();
    await _press(tester, LogicalKeyboardKey.backspace);
    expect(controller.document.toDelta(), before);
    expect(controller.selection, const TextSelection.collapsed(offset: 6));
    await _close(tester);
  });
}
