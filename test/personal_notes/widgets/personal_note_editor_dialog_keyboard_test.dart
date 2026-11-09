import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor_dialog.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_header.dart';
import 'package:otzaria/widgets/dialogs/dialog_dismiss_guard.dart';

import '../../test_helpers/memory_cache_provider.dart';

void main() {
  Object? result;

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    result = 'pending';
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      RepositoryProvider(
        create: (_) => SettingsRepository(),
        child: BlocProvider(
          create: (context) => SettingsBloc(
            repository: context.read<SettingsRepository>(),
          ),
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    result = await showDialog<PersonalNoteEditorResult>(
                      context: context,
                      builder: (_) => const Directionality(
                        textDirection: TextDirection.rtl,
                        child: PersonalNoteEditorDialog(initialContent: 'שלום'),
                      ),
                    );
                  },
                  child: const Text('פתח'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('פתח'));
    await tester.pumpAndSettle();
  }

  FocusNode closeFocus(WidgetTester tester) => Focus.of(
    tester.element(
      find
          .descendant(
            of: find.byType(AppDialogHeader),
            matching: find.byType(Icon),
          )
          .last,
    ),
  );

  FocusNode actionFocus(WidgetTester tester, String text) => tester
      .widget<ActionButton>(find.widgetWithText(ActionButton, text))
      .focusNode!;

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
    testWidgets('סגירה בכותרת עם ${key.keyLabel} מבטלת ולא שומרת', (
      tester,
    ) async {
      await open(tester);
      closeFocus(tester).requestFocus();
      await tester.pump();
      await press(tester, key);
      expect(result, isNull);
      expect(find.byType(PersonalNoteEditorDialog), findsNothing);
    });
  }

  testWidgets('Enter בביטול פועל לפי הפוקוס גם בלי מעבר בחיצים', (
    tester,
  ) async {
    await open(tester);
    actionFocus(tester, 'ביטול').requestFocus();
    await tester.pump();
    await press(tester, LogicalKeyboardKey.enter);
    expect(result, isNull);
  });

  testWidgets('Enter בשמירה מחזיר את תוכן ההערה', (tester) async {
    await open(tester);
    actionFocus(tester, 'שמור').requestFocus();
    await tester.pump();
    await press(tester, LogicalKeyboardKey.enter);
    expect((result as PersonalNoteEditorResult).contentPlain.trim(), 'שלום');
  });

  testWidgets('חיצים מחליפים בין שמירה וביטול לפי הפוקוס בפועל', (
    tester,
  ) async {
    await open(tester);
    final cancel = actionFocus(tester, 'ביטול');
    final save = actionFocus(tester, 'שמור');
    cancel.requestFocus();
    await tester.pump();
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(save.hasFocus, isTrue);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(cancel.hasFocus, isTrue);
    await press(tester, LogicalKeyboardKey.enter);
    expect(result, isNull);
  });

  testWidgets('Tab משמירה לביטול אינו משאיר פעולת שמירה ישנה', (
    tester,
  ) async {
    await open(tester);
    actionFocus(tester, 'שמור').requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(actionFocus(tester, 'ביטול').hasFocus, isTrue);
    await press(tester, LogicalKeyboardKey.enter);
    expect(result, isNull);
  });

  testWidgets('סגירה מהכותרת עם שינויים מבקשת החלטה על הטיוטה', (
    tester,
  ) async {
    await open(tester);
    tester
        .widget<quill.QuillEditor>(find.byType(quill.QuillEditor))
        .controller
        .replaceText(0, 0, 'טיוטה ', const TextSelection.collapsed(offset: 6));
    await tester.pump();
    closeFocus(tester).requestFocus();
    await tester.pump();
    await press(tester, LogicalKeyboardKey.enter);
    expect(result, 'pending');
    expect(find.text('שמור טיוטה'), findsOneWidget);
    await tester.tap(find.text('סגור בלי לשמור'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets('Enter בעורך אינו שומר או סוגר את ההערה', (tester) async {
    await open(tester);
    await press(tester, LogicalKeyboardKey.enter);
    expect(result, 'pending');
    expect(find.byType(PersonalNoteEditorDialog), findsOneWidget);
  });

  testWidgets('Escape בעורך בלי שינויים סוגר את הדיאלוג (DD-08)', (
    tester,
  ) async {
    await open(tester);
    final editor = tester.widget<quill.QuillEditor>(
      find.byType(quill.QuillEditor),
    );
    expect(editor.focusNode.hasFocus, isTrue);
    await press(tester, LogicalKeyboardKey.escape);
    expect(result, isNull);
    expect(find.byType(PersonalNoteEditorDialog), findsNothing);
  });

  testWidgets('Escape בעורך עם שינויים שואל על הטיוטה (DD-08)', (
    tester,
  ) async {
    await open(tester);
    final editor = tester.widget<quill.QuillEditor>(
      find.byType(quill.QuillEditor),
    );
    editor.controller.replaceText(
      0,
      0,
      'טיוטה ',
      const TextSelection.collapsed(offset: 6),
    );
    await tester.pump();
    expect(editor.focusNode.hasFocus, isTrue);
    await press(tester, LogicalKeyboardKey.escape);
    expect(result, 'pending');
    expect(find.text('שמור טיוטה'), findsOneWidget);
    await tester.tap(find.text('סגור בלי לשמור'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets('Escape מהכותרת מבטל', (tester) async {
    await open(tester);
    closeFocus(tester).requestFocus();
    await tester.pump();
    await press(tester, LogicalKeyboardKey.escape);
    expect(result, isNull);
  });

  for (final (modifier, isMac) in [
    (LogicalKeyboardKey.controlLeft, false),
    (LogicalKeyboardKey.metaLeft, true),
    (LogicalKeyboardKey.altLeft, false),
  ]) {
    testWidgets('${modifier.keyLabel}+Enter מהכותרת עדיין שומר', (
      tester,
    ) async {
      ShortcutHelper.isMacForTesting = isMac;
      addTearDown(() => ShortcutHelper.isMacForTesting = null);
      await open(tester);
      closeFocus(tester).requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(modifier);
      await tester.pumpAndSettle();
      expect((result as PersonalNoteEditorResult).contentPlain.trim(), 'שלום');
    });
  }

  for (final (button, closes) in [('ביטול', false), ('סגור בלי לשמור', true)]) {
    testWidgets(
      'סגירת החלון עם שינויים שואלת על הטיוטה; "$button" '
      '${closes ? 'סוגר' : 'משאיר את החלון ואת ההערה'} (q11 Q3)',
      (tester) async {
        await open(tester);
        tester
            .widget<quill.QuillEditor>(find.byType(quill.QuillEditor))
            .controller
            .replaceText(
              0,
              0,
              'טיוטה ',
              const TextSelection.collapsed(offset: 6),
            );
        await tester.pump();
        bool? allowed;
        unawaited(
          DialogDismissGuard.confirmWindowClose().then((v) => allowed = v),
        );
        await tester.pumpAndSettle();
        expect(find.text('שמור טיוטה'), findsOneWidget);
        expect(allowed, isNull, reason: 'החלון מחכה להחלטה');
        // "ביטול" מופיע גם בעורך; שאלת הטיוטה היא העליונה.
        await tester.tap(find.text(button).last);
        await tester.pumpAndSettle();
        expect(allowed, closes);
        expect(
          find.byType(PersonalNoteEditorDialog),
          closes ? findsNothing : findsOneWidget,
        );
        expect(result, closes ? isNull : 'pending');
      },
    );
  }

  testWidgets('סגירת החלון בלי שינויים סוגרת בלי לשאול', (tester) async {
    await open(tester);
    expect(
      await tester.runAsync(DialogDismissGuard.confirmWindowClose),
      isTrue,
    );
    await tester.pumpAndSettle();
    expect(find.text('שמור טיוטה'), findsNothing);
  });
}
