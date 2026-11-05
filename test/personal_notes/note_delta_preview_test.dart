import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
// Quill paints block borders in this render object, which is not exported.
// ignore: implementation_imports
import 'package:flutter_quill/src/editor/widgets/text/text_block.dart'
    as quill_render;
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/widgets/note_delta_preview.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_content_view.dart';

/// התצוגה הקלה של כרטיסי הרשת חייבת להיראות כמו QuillEditor לקריאה בלבד.
void main() {
  final richDelta = [
    {'insert': 'כותרת ההערה'},
    {
      'insert': '\n',
      'attributes': {'header': 2},
    },
    {'insert': 'רגיל '},
    {
      'insert': 'מודגש',
      'attributes': {'bold': true},
    },
    {'insert': ' '},
    {
      'insert': 'נטוי',
      'attributes': {'italic': true},
    },
    {'insert': ' '},
    {
      'insert': 'קו תחתי',
      'attributes': {'underline': true},
    },
    {'insert': ' '},
    {
      'insert': 'חוצה',
      'attributes': {'strike': true},
    },
    {'insert': ' '},
    {
      'insert': 'מסומן',
      'attributes': {'background': '#fff59d'},
    },
    {'insert': ' '},
    {
      'insert': 'גדול',
      'attributes': {'size': 22},
    },
    {'insert': ' '},
    {
      'insert': 'צבעוני',
      'attributes': {'color': '#e53935'},
    },
    {'insert': '\n'},
    {'insert': 'פריט ראשון'},
    {
      'insert': '\n',
      'attributes': {'list': 'bullet'},
    },
    {'insert': 'פריט שני'},
    {
      'insert': '\n',
      'attributes': {'list': 'bullet'},
    },
    {'insert': 'אחד'},
    {
      'insert': '\n',
      'attributes': {'list': 'ordered'},
    },
    {'insert': 'שתיים'},
    {
      'insert': '\n',
      'attributes': {'list': 'ordered'},
    },
    {'insert': 'ציטוט'},
    {
      'insert': '\n',
      'attributes': {'blockquote': true},
    },
    {
      'insert': 'קישור',
      'attributes': {'link': 'otzaria://book?bookId=Test&line=1'},
    },
    {'insert': ' וגם https://example.com בטקסט\n'},
  ];

  PersonalNote note(List<Map<String, Object>> delta) => PersonalNote(
    id: 'pn_1',
    bookId: 'Test',
    lineNumber: 1,
    displayTitle: 'כותרת',
    lastKnownLineNumber: null,
    status: PersonalNoteStatus.located,
    content: jsonEncode(delta),
    contentPlain: '',
    contentFormat: PersonalNoteContentFormat.quillDelta,
    createdAt: DateTime(2025, 1, 1),
    updatedAt: DateTime(2025, 1, 2),
  );

  Future<Size> pump(
    WidgetTester tester,
    PersonalNote note, {
    required bool interactive,
    int? maxPreviewChars,
  }) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('he', 'IL'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: UnconstrainedBox(
              constrainedAxis: Axis.horizontal,
              alignment: Alignment.topCenter,
              child: SizedBox(
                key: key,
                width: 400,
                child: PersonalNoteContentView(
                  note: note,
                  interactive: interactive,
                  maxPreviewChars: maxPreviewChars,
                  textStyle: const TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: Color(0xFF444444),
                    fontFamily: 'serif',
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return tester.getSize(find.byKey(key));
  }

  /// כל קטע טקסט מוצג עם הסגנון האפקטיבי שלו (כולל ירושה מהורים).
  Map<String, TextStyle> renderedRuns(WidgetTester tester) {
    final runs = <String, TextStyle>{};
    void visit(InlineSpan span, TextStyle inherited) {
      final style = inherited.merge(span.style);
      if (span is TextSpan) {
        final text = span.text;
        if (text != null && text.trim().isNotEmpty) runs[text] = style;
        for (final child in span.children ?? const <InlineSpan>[]) {
          visit(child, style);
        }
      }
    }

    for (final element in find.byType(RichText).evaluate()) {
      final richText = element.widget as RichText;
      if (element.findAncestorWidgetOfExactType<ActionChip>() != null) continue;
      visit(richText.text, const TextStyle());
    }
    return runs;
  }

  void expectSameStyle(String text, TextStyle actual, TextStyle expected) {
    expect(actual.fontSize, expected.fontSize, reason: '$text fontSize');
    expect(actual.fontWeight, expected.fontWeight, reason: '$text weight');
    expect(actual.fontStyle, expected.fontStyle, reason: '$text italic');
    expect(actual.decoration, expected.decoration, reason: '$text decoration');
    expect(actual.color, expected.color, reason: '$text color');
    expect(
      actual.backgroundColor,
      expected.backgroundColor,
      reason: '$text background',
    );
    expect(actual.height, expected.height, reason: '$text height');
    expect(actual.fontFamily, expected.fontFamily, reason: '$text family');
  }

  Future<void> expectParity(
    WidgetTester tester,
    PersonalNote note, {
    int? maxPreviewChars,
    bool expectLight = true,
  }) async {
    final quillSize = await pump(
      tester,
      note,
      interactive: true,
      maxPreviewChars: maxPreviewChars,
    );
    expect(find.byType(quill.QuillEditor), findsOneWidget);
    final quillRuns = renderedRuns(tester);
    final quillChips = find.byType(ActionChip).evaluate().length;

    final lightSize = await pump(
      tester,
      note,
      interactive: false,
      maxPreviewChars: maxPreviewChars,
    );
    expect(
      find.byType(quill.QuillEditor),
      expectLight ? findsNothing : findsOneWidget,
    );
    expect(find.byType(EditableText), findsNothing);
    expect(
      find.byType(NoteDeltaPreview),
      expectLight ? findsOneWidget : findsNothing,
    );
    final lightRuns = renderedRuns(tester);

    expect(quillRuns.length, greaterThan(5));
    expect(lightRuns.keys.toSet(), quillRuns.keys.toSet());
    for (final text in quillRuns.keys) {
      expectSameStyle(text, lightRuns[text]!, quillRuns[text]!);
    }
    expect(find.byType(ActionChip).evaluate().length, quillChips);
    expect(lightSize.height, moreOrLessEquals(quillSize.height, epsilon: 1));
  }

  testWidgets('פסקאות ועיצוב inline משתמשים במסלול הקל ללא שינוי עיצוב', (
    tester,
  ) async {
    await expectParity(
      tester,
      note([
        ...richDelta.sublist(2, 17),
        {
          'insert': 'קישור',
          'attributes': {'link': 'https://example.com'},
        },
        {'insert': '\n'},
      ]),
    );
  });

  testWidgets('תצוגה אינטראקטיבית וקלה יורשות את הגופן והצבע של ההערה', (
    tester,
  ) async {
    for (final interactive in [true, false]) {
      await pump(
        tester,
        note([
          {'insert': 'הערה בעברית\n'},
        ]),
        interactive: interactive,
      );
      final style = renderedRuns(tester)['הערה בעברית']!;
      expect(style.color, const Color(0xFF444444));
      expect(style.fontFamily, 'serif');
      expect(style.fontWeight, FontWeight.w500);
      expect(style.height, 1.5);
    }
  });

  testWidgets('עיצוב, רשימות, ציטוט וקישורים זהים לעורך Quill', (
    tester,
  ) async {
    await expectParity(tester, note(richDelta), expectLight: false);
  });

  testWidgets('קיצור התצוגה המקדימה זהה לעורך Quill', (tester) async {
    await expectParity(
      tester,
      note(richDelta),
      maxPreviewChars: 40,
      expectLight: false,
    );
    expect(find.textContaining('…', findRichText: true), findsOneWidget);
  });

  testWidgets('מספור רשימה מוזחת ושורות קוד זהים לעורך Quill', (tester) async {
    await expectParity(
      tester,
      note([
        {'insert': 'אחד'},
        {
          'insert': '\n',
          'attributes': {'list': 'ordered'},
        },
        {'insert': 'פנימי'},
        {
          'insert': '\n',
          'attributes': {'list': 'ordered', 'indent': 1},
        },
        {'insert': 'שתיים'},
        {
          'insert': '\n',
          'attributes': {'list': 'ordered'},
        },
        {'insert': 'code'},
        {
          'insert': '\n',
          'attributes': {'code-block': true},
        },
      ]),
      expectLight: false,
    );
    expect(find.text('a.'), findsOneWidget);
    expect(find.text('2.'), findsOneWidget);
  });

  testWidgets('ציטוט ב-RTL מצויר עם קו בצד ימין', (tester) async {
    await pump(
      tester,
      note([
        {'insert': 'ציטוט'},
        {
          'insert': '\n',
          'attributes': {'blockquote': true},
        },
      ]),
      interactive: false,
    );
    final block = tester.allRenderObjects
        .whereType<quill_render.RenderEditableTextBlock>()
        .where(
          (block) =>
              block.container.style.containsKey(quill.Attribute.blockQuote.key),
        )
        .toSet()
        .single;
    final border = (block.decoration as BoxDecoration).border! as Border;
    expect(border.right.width, 4);
    expect(border.left, BorderSide.none);
  });
}
