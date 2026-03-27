import 'dart:convert';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor.dart';

void main() {
  testWidgets('כפתור bold פועל גם כ-toggle ומסיר עיצוב קיים', (tester) async {
    final controller = buildPersonalNoteEditorController(
      initialContent: 'שלום',
      initialFormat: PersonalNoteContentFormat.plain,
    );

    controller.quillController.updateSelection(
      const TextSelection(baseOffset: 0, extentOffset: 4),
      quill.ChangeSource.local,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PersonalNoteEditorBody(
            controller: controller,
            focusNode: FocusNode(),
            scrollController: ScrollController(),
            autofocus: false,
            linkableNotes: const [],
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(FluentIcons.text_bold_24_regular));
    await tester.pump();

    expect(_deltaHasAttribute(controller, quill.Attribute.bold), isTrue);

    controller.quillController.updateSelection(
      const TextSelection(baseOffset: 0, extentOffset: 4),
      quill.ChangeSource.local,
    );

    await tester.tap(find.byIcon(FluentIcons.text_bold_24_regular));
    await tester.pump();

    expect(_deltaHasAttribute(controller, quill.Attribute.bold), isFalse);
  });
}

bool _deltaHasAttribute(
  PersonalNoteEditorController controller,
  quill.Attribute attribute,
) {
  final operations = jsonDecode(
    jsonEncode(controller.quillController.document.toDelta().toJson()),
  ) as List<dynamic>;

  for (final operation in operations) {
    final attributes = (operation as Map<String, dynamic>)['attributes'];
    if (attributes is Map<String, dynamic> &&
        attributes.containsKey(attribute.key)) {
      return true;
    }
  }

  return false;
}
