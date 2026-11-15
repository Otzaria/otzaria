import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/notes_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor.dart';

// טקסט ענק בהערה תוקע את ה-UI (#5131): העורך חוסם גדילה מעבר לתקרה.
void main() {
  tearDown(UiSnack.hide);

  final tooLongMessage = NotesMessages.noteTooLong(personalNoteMaxLength);

  Future<quill.QuillController> pumpEditor(
    WidgetTester tester,
    String text,
  ) async {
    final controller = buildPersonalNoteEditorController(
      initialContent: text,
      initialFormat: PersonalNoteContentFormat.plain,
    );
    final focusNode = FocusNode();
    final scrollController = ScrollController();
    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
      scrollController.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: Scaffold(
          body: PersonalNoteEditorBody(
            controller: controller,
            focusNode: focusNode,
            scrollController: scrollController,
            autofocus: false,
            linkableNotes: const [],
          ),
        ),
      ),
    );
    return controller.quillController;
  }

  void mockClipboardText(WidgetTester tester, String text) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async =>
          call.method == 'Clipboard.getData' ? {'text': text} : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
  }

  Future<void> pasteFromKeyboard(WidgetTester tester) async {
    final editor = tester.state<quill.QuillRawEditorState>(
      find.byType(quill.QuillRawEditor),
    );
    await editor.pasteText(SelectionChangedCause.keyboard);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> expectTooLongMessageShown(WidgetTester tester) async {
    expect(find.text(tooLongMessage), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  }

  String plainText(quill.QuillController controller) =>
      controller.document.toPlainText();

  testWidgets('הדבקה שחורגת מהתקרה נדחית ומציגה הודעה', (tester) async {
    final controller = await pumpEditor(tester, 'הערה קצרה');
    controller.updateSelection(
      const TextSelection.collapsed(offset: 4),
      quill.ChangeSource.local,
    );
    mockClipboardText(tester, 'א' * personalNoteMaxLength);

    await pasteFromKeyboard(tester);

    expect(plainText(controller), 'הערה קצרה\n');
    expect(controller.document.length - 1, lessThan(personalNoteMaxLength));
    await expectTooLongMessageShown(tester);
  });

  testWidgets('הדבקה בתוך התקרה מתבצעת בלי הודעה', (tester) async {
    final controller = await pumpEditor(tester, 'הערה');
    controller.updateSelection(
      const TextSelection.collapsed(offset: 4),
      quill.ChangeSource.local,
    );
    mockClipboardText(tester, ' ארוכה יותר');

    await pasteFromKeyboard(tester);

    expect(plainText(controller), 'הערה ארוכה יותר\n');
    expect(find.text(tooLongMessage), findsNothing);
  });

  testWidgets('החלפת בחירה נבדקת לפי האורך שנוצר אחריה', (tester) async {
    final initial = 'ב' * (personalNoteMaxLength - 5);
    final controller = await pumpEditor(tester, initial);
    controller.updateSelection(
      const TextSelection(baseOffset: 0, extentOffset: 10),
      quill.ChangeSource.local,
    );
    mockClipboardText(tester, 'ג' * 15);

    await pasteFromKeyboard(tester);

    expect(controller.document.length - 1, personalNoteMaxLength);
    expect(find.text(tooLongMessage), findsNothing);
  });

  testWidgets('הקלדה בהערה מלאה נחסמת ושדה הקלט חוזר לטקסט המסמך', (
    tester,
  ) async {
    final initial = 'ד' * personalNoteMaxLength;
    final controller = await pumpEditor(tester, initial);
    await tester.tap(find.byType(quill.QuillEditor));
    await tester.pump();
    controller.updateSelection(
      const TextSelection.collapsed(offset: personalNoteMaxLength),
      quill.ChangeSource.local,
    );
    await tester.pump();

    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: '$initialה\n',
        selection: const TextSelection.collapsed(
          offset: personalNoteMaxLength + 1,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(plainText(controller), '$initial\n');
    final editor = tester.state<quill.QuillRawEditorState>(
      find.byType(quill.QuillRawEditor),
    );
    expect(editor.currentTextEditingValue?.text, '$initial\n');
    await expectTooLongMessageShown(tester);
  });

  testWidgets('הערה קיימת ארוכה מהתקרה נפתחת שלמה, ומחיקה בה מותרת', (
    tester,
  ) async {
    final initial = 'ו' * (personalNoteMaxLength + 1000);
    final controller = await pumpEditor(tester, initial);

    expect(plainText(controller), '$initial\n');

    controller.replaceText(0, 10, '', null);
    expect(controller.document.length - 1, personalNoteMaxLength + 990);

    controller.replaceText(0, 0, 'ז', null);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.document.length - 1, personalNoteMaxLength + 990);
    await expectTooLongMessageShown(tester);
  });
}
