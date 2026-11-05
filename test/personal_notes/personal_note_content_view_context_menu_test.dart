import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_content_view.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/misc/app_selection_area.dart';
import 'package:otzaria/widgets/text/selection_copy_shortcuts.dart';

/// issue #1271 — בתיבת הריחוף של הערה (עטופה ב-AppSelectionArea) לחיצה ימנית
/// פתחה גם את תפריט ההעתקה של אוצריא וגם את תפריט Flutter של עורך ההערה.
void main() {
  const noteText = 'תוכן ההערה לבדיקה';

  PersonalNote note() => PersonalNote(
    id: 'pn_1',
    bookId: 'Test',
    lineNumber: 1,
    displayTitle: 'כותרת',
    lastKnownLineNumber: null,
    status: PersonalNoteStatus.located,
    content: jsonEncode([
      {'insert': noteText},
      {'insert': '\n'},
    ]),
    contentPlain: noteText,
    contentFormat: PersonalNoteContentFormat.quillDelta,
    createdAt: DateTime(2025, 1, 1),
    updatedAt: DateTime(2025, 1, 2),
  );

  Future<void> rightClickText(WidgetTester tester) async {
    await tester.tapAt(
      tester.getCenter(find.text('תוכן ההערה לבדיקה', findRichText: true)),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
  }

  Future<void> onPlatform(
    TargetPlatform platform,
    Future<void> Function() body,
  ) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  void mockClipboard(WidgetTester tester, List<String> writes) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          writes.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
  }

  Future<void> pumpNote(WidgetTester tester, {bool withSelectionArea = false}) {
    final content = PersonalNoteContentView(note: note());
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: withSelectionArea ? AppSelectionArea(child: content) : content,
        ),
      ),
    );
  }

  testWidgets('בתוך AppSelectionArea נפתח רק תפריט ההעתקה של אוצריא', (
    tester,
  ) async {
    await onPlatform(TargetPlatform.windows, () async {
      await pumpNote(tester, withSelectionArea: true);

      await rightClickText(tester);

      expect(find.text('העתק'), findsOneWidget, reason: 'תפריט אוצריא');
      expect(
        find.byType(AdaptiveTextSelectionToolbar),
        findsNothing,
        reason:
            'תפריט Flutter של העורך אסור שיופיע לצד תפריט אוצריא (issue #1271)',
      );
    });
  });

  // בחלונית הצד של ההערות אין מארח עם תפריט, ונפתח תפריט Flutter של העורך
  // במקום תפריט אוצריא (issue #1590).
  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ]) {
    testWidgets('בלי מארח ב-$platform נפתח רק תפריט ההעתקה של אוצריא', (
      tester,
    ) async {
      await onPlatform(platform, () async {
        await pumpNote(tester);

        await rightClickText(tester);

        expect(find.text('העתק'), findsOneWidget, reason: 'תפריט אוצריא');
        expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
      });
    });
  }

  testWidgets('העתקה שומרת בדיוק על טווח הבחירה של Quill', (tester) async {
    await onPlatform(TargetPlatform.windows, () async {
      final clipboardWrites = <String>[];
      mockClipboard(tester, clipboardWrites);
      await pumpNote(tester);

      final text = find.text(noteText, findRichText: true);
      await tester.tapAt(tester.getCenter(text), kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(tester.getCenter(text), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();

      final controller = tester
          .state<quill.QuillEditorState>(find.byType(quill.QuillEditor))
          .controller;
      final selectedText = controller.getPlainText();
      expect(controller.selection.isCollapsed, isFalse);
      expect(selectedText, isNotEmpty);
      expect(selectedText, isNot(noteText));

      await rightClickText(tester);
      await tester.tap(find.text('העתק'));
      await tester.pumpAndSettle();

      expect(clipboardWrites, [selectedText]);
    });
  });

  // #3260: גרירה בתצוגת הקריאה של ההערה משאירה בחירה בלי פוקוס ב-Quill.
  // לכן Ctrl+C הגיע לקורא, גם כשהטקסט המסומן היה בגוף ההערה.
  for (final withSelectionArea in [false, true]) {
    testWidgets(
      'Ctrl+C אחרי גרירה בהערה לא ממוקדת מעתיק אותה (מארח: $withSelectionArea)',
      (tester) async {
        await onPlatform(TargetPlatform.windows, () async {
          final clipboardWrites = <String>[];
          mockClipboard(tester, clipboardWrites);
          final readerFocus = FocusNode();
          addTearDown(readerFocus.dispose);
          var readerCopies = 0;
          final content = PersonalNoteContentView(note: note());
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Column(
                  children: [
                    SelectionCopyShortcuts(
                      onCopy: () => readerCopies++,
                      child: SelectionArea(
                        focusNode: readerFocus,
                        child: const Text('טקסט הקורא'),
                      ),
                    ),
                    withSelectionArea
                        ? AppSelectionArea(child: content)
                        : content,
                  ],
                ),
              ),
            ),
          );
          readerFocus.requestFocus();
          await tester.pumpAndSettle();
          expect(readerFocus.hasFocus, isTrue);
          final editor = tester.widget<quill.QuillEditor>(
            find.byType(quill.QuillEditor),
          );
          expect(editor.focusNode.hasFocus, isFalse);

          final line = tester.getRect(find.text(noteText, findRichText: true));
          final gesture = await tester.startGesture(
            line.centerLeft + const Offset(2, 0),
            kind: PointerDeviceKind.mouse,
          );
          await tester.pump();
          for (var step = 0; step < 5; step++) {
            await gesture.moveBy(const Offset(6, 0));
            await tester.pump();
          }
          await gesture.up();
          await tester.pumpAndSettle();
          final selectedText = editor.controller.getPlainText();
          expect(editor.controller.selection.isCollapsed, isFalse);
          expect(selectedText, isNotEmpty);
          expect(selectedText, isNot(noteText));

          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          await tester.pumpAndSettle();

          expect(readerCopies, 0, reason: 'הבחירה הפעילה נמצאת בהערה');
          expect(clipboardWrites.where((text) => text.isNotEmpty), [
            selectedText,
          ]);
          expect(
            editor.controller.document.toPlainText().trimRight(),
            noteText,
          );
        });
      },
    );
  }

  // עורך Quill אינו מדווח ל-SelectionArea, ובלי רישום הבחירה "העתק" של תיבת
  // הריחוף נשאר מושבת (issue #1595).
  testWidgets('בתוך AppSelectionArea "העתק" מעתיק את הבחירה של Quill', (
    tester,
  ) async {
    await onPlatform(TargetPlatform.windows, () async {
      final clipboardWrites = <String>[];
      mockClipboard(tester, clipboardWrites);
      await pumpNote(tester, withSelectionArea: true);

      final text = find.text(noteText, findRichText: true);
      await tester.tapAt(tester.getCenter(text), kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(tester.getCenter(text), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      final selectedText = tester
          .state<quill.QuillEditorState>(find.byType(quill.QuillEditor))
          .controller
          .getPlainText();
      expect(selectedText, isNotEmpty);
      expect(selectedText, isNot(noteText));

      await rightClickText(tester);
      await tester.tap(find.text('העתק'));
      await tester.pumpAndSettle();

      expect(clipboardWrites, [selectedText]);
    });
  });

  testWidgets('בחירה ריקה משאירה את "העתק" מושבתת', (tester) async {
    await onPlatform(TargetPlatform.windows, () async {
      final clipboardWrites = <String>[];
      mockClipboard(tester, clipboardWrites);
      await pumpNote(tester);

      await rightClickText(tester);

      final copyLabel = find.text('העתק');
      expect(copyLabel, findsOneWidget);
      final copyButton = tester.widget<MenuItemButton>(
        find.byType(MenuItemButton),
      );
      expect(copyButton.onPressed, isNull);
      await tester.tap(copyLabel);
      await tester.pumpAndSettle();

      expect(clipboardWrites, isEmpty);
    });
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('במגע ב-$platform נשאר תפריט הבחירה הטבעי של העורך', (
      tester,
    ) async {
      await onPlatform(platform, () async {
        await pumpNote(tester);

        final editor = tester.widget<quill.QuillEditor>(
          find.byType(quill.QuillEditor),
        );

        expect(find.byType(AppContextMenuRegion), findsNothing);
        expect(
          editor.config.contextMenuBuilder,
          isNull,
          reason: 'Quill משתמש בתפריט הבחירה הטבעי של הפלטפורמה',
        );
      });
    });
  }
}
