import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/widgets/note_delta_preview.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_content_view.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_styles.dart';

/// #2531: הערה בשורה 1.5 בעורך ובתצוגה, ולא 1.15 של Quill.
void main() {
  PersonalNote note(List<Map<String, Object>> delta) => PersonalNote(
    id: 'n',
    bookId: 'b',
    lineNumber: 1,
    displayTitle: 't',
    lastKnownLineNumber: 1,
    status: PersonalNoteStatus.located,
    content: jsonEncode(delta),
    contentPlain: '',
    contentFormat: PersonalNoteContentFormat.quillDelta,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: child),
      ),
    ),
  );

  testWidgets('פסקה ורשימה בשורה 1.5; כותרת נשארת של Quill', (tester) async {
    await pump(tester, const SizedBox());
    final context = tester.element(find.byType(SizedBox));
    final styles = personalNoteStyles(context);
    final base = quill.DefaultStyles.getInstance(context);
    expect(styles.paragraph!.style.height, personalNoteLineHeight);
    expect(styles.lists!.style.height, personalNoteLineHeight);
    expect(styles.h1!.style.height, base.h1!.style.height);
  });

  testWidgets('התצוגה בעורך Quill מקבלת את סגנונות ההערה', (tester) async {
    await pump(
      tester,
      PersonalNoteContentView(
        note: note([
          {'insert': 'שורה\n'},
        ]),
      ),
    );
    final editor = tester.widget<quill.QuillEditor>(
      find.byType(quill.QuillEditor),
    );
    expect(
      editor.config.customStyles?.paragraph?.style.height,
      personalNoteLineHeight,
    );
  });

  testWidgets('התצוגה המקדימה בשורה 1.5', (tester) async {
    await pump(
      tester,
      PersonalNoteContentView(
        interactive: false,
        note: note([
          {'insert': 'שורה ראשונה\nשורה שנייה\n'},
        ]),
      ),
    );
    expect(find.byType(NoteDeltaPreview), findsOneWidget);
    final text = tester.widget<RichText>(
      find
          .descendant(
            of: find.byType(NoteDeltaPreview),
            matching: find.byType(RichText),
          )
          .first,
    );
    expect(text.text.style?.height, personalNoteLineHeight);
  });
}
