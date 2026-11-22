// בעורך ההערות קפיצת מילה ב-RTL מחליפה שמאל וימין, אבל המקש
// שונה לפי פלטפורמה: Ctrl ב-Windows וב-Linux, Option ב-macOS וב-iOS (ב-macOS
// Ctrl+חץ שמור למערכת). כמו RtlSelectionShortcuts בספר.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor.dart';

void main() {
  const text = 'שלום עולם גדול';

  Future<int> caretAfter(
    WidgetTester tester, {
    required TargetPlatform platform,
    required LogicalKeyboardKey modifier,
    required LogicalKeyboardKey arrow,
    required int from,
  }) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      final controller = buildPersonalNoteEditorController(
        initialContent: text,
        initialFormat: PersonalNoteContentFormat.plain,
      );
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('he', 'IL'),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: PersonalNoteEditorBody(
                controller: controller,
                focusNode: focusNode,
                scrollController: ScrollController(),
                autofocus: false,
                linkableNotes: const [],
              ),
            ),
          ),
        ),
      );
      focusNode.requestFocus();
      controller.quillController.updateSelection(
        TextSelection.collapsed(offset: from),
        quill.ChangeSource.local,
      );
      await tester.pump();

      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(arrow);
      await tester.sendKeyUpEvent(modifier);
      await tester.pump();
      return controller.quillController.selection.extentOffset;
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  // ב-RTL שמאל הוא קדימה בטקסט: מתחילת ההערה אל סוף המילה הראשונה.
  for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
    testWidgets('$platform: Ctrl+שמאלה קופץ מילה קדימה, Ctrl+ימינה אחורה', (
      tester,
    ) async {
      final forward = await caretAfter(
        tester,
        platform: platform,
        modifier: LogicalKeyboardKey.controlLeft,
        arrow: LogicalKeyboardKey.arrowLeft,
        from: 0,
      );
      expect(forward, text.indexOf(' '));
      await tester.pumpWidget(const SizedBox.shrink());
      final backward = await caretAfter(
        tester,
        platform: platform,
        modifier: LogicalKeyboardKey.controlLeft,
        arrow: LogicalKeyboardKey.arrowRight,
        from: text.length,
      );
      expect(backward, text.lastIndexOf(' ') + 1);
    });
  }

  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    testWidgets('$platform: Option+שמאלה קופץ מילה קדימה, Option+ימינה אחורה', (
      tester,
    ) async {
      final forward = await caretAfter(
        tester,
        platform: platform,
        modifier: LogicalKeyboardKey.altLeft,
        arrow: LogicalKeyboardKey.arrowLeft,
        from: 0,
      );
      expect(forward, text.indexOf(' '));
      await tester.pumpWidget(const SizedBox.shrink());
      final backward = await caretAfter(
        tester,
        platform: platform,
        modifier: LogicalKeyboardKey.altLeft,
        arrow: LogicalKeyboardKey.arrowRight,
        from: text.length,
      );
      expect(backward, text.lastIndexOf(' ') + 1);
    });
  }
}
