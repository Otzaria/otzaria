import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_content_view.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/theme/app_theme_data.dart';

/// כפתור "הדגשה" כותב רקע צהוב בלבד. הטקסט נשאר בצבע הערכה,
/// ובכהה הוא בהיר על צהוב (כ-1.3:1). צבע הטקסט על הדגשה הוא צבע תוכן קבוע
/// שנגזר מהרקע, זהה בעורך, בתצוגה ובתצוגה המקדימה.
void main() {
  const highlighted = 'טקסט מודגש';
  final delta = [
    {
      'insert': highlighted,
      'attributes': {'background': '#fff59d'},
    },
    {'insert': '\n'},
  ];

  PersonalNote note() => PersonalNote(
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

  ThemeData theme(Brightness brightness) {
    final light = brightness == Brightness.light;
    final scheme = AppThemeData.createColorScheme(
      light ? AppSeedColors.defaultLight : AppSeedColors.purple,
      brightness,
    );
    return light
        ? AppThemeData.light(scheme, compactMenuMode: false)
        : AppThemeData.dark(scheme, compactMenuMode: false);
  }

  Future<void> pumpApp(
    WidgetTester tester,
    Brightness brightness,
    Widget child,
  ) => tester.pumpWidget(
    MaterialApp(
      theme: theme(brightness),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: child),
      ),
    ),
  );

  /// הסגנון האפקטיבי של קטע הטקסט המודגש (כולל ירושה מההורים).
  TextStyle runStyle(WidgetTester tester) {
    TextStyle? found;
    void visit(InlineSpan span, TextStyle inherited) {
      final style = inherited.merge(span.style);
      if (span is! TextSpan) return;
      if (span.text == highlighted) found = style;
      for (final child in span.children ?? const <InlineSpan>[]) {
        visit(child, style);
      }
    }

    for (final element in find.byType(RichText).evaluate()) {
      visit(
        (element.widget as RichText).text,
        DefaultTextStyle.of(element).style,
      );
    }
    expect(found, isNotNull, reason: 'הקטע המודגש לא נמצא');
    return found!;
  }

  double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  void expectReadable(WidgetTester tester, String where) {
    final style = runStyle(tester);
    expect(style.backgroundColor, isNotNull, reason: '$where: אין רקע');
    expect(style.color, isNotNull, reason: '$where: אין צבע טקסט');
    final ratio = contrast(style.color!, style.backgroundColor!);
    expect(
      ratio,
      greaterThanOrEqualTo(4.5),
      reason: '$where: ניגודיות ${ratio.toStringAsFixed(2)}:1',
    );
  }

  for (final brightness in Brightness.values) {
    final label = brightness == Brightness.dark ? 'כהה' : 'בהיר';

    testWidgets('הדגשה קריאה בתצוגה המקדימה הקלה ($label)', (tester) async {
      await pumpApp(
        tester,
        brightness,
        PersonalNoteContentView(note: note(), interactive: false),
      );
      expect(find.byType(quill.QuillEditor), findsNothing);
      expectReadable(tester, 'תצוגה קלה');
    });

    testWidgets('הדגשה קריאה בתצוגת Quill בכרטיס ($label)', (tester) async {
      await pumpApp(
        tester,
        brightness,
        PersonalNoteContentView(note: note(), interactive: true),
      );
      expect(find.byType(quill.QuillEditor), findsOneWidget);
      expectReadable(tester, 'תצוגת Quill');
    });

    testWidgets('הדגשה קריאה בעורך ($label)', (tester) async {
      final controller = buildPersonalNoteEditorController(
        initialContent: jsonEncode(delta),
        initialFormat: PersonalNoteContentFormat.quillDelta,
      );
      addTearDown(controller.dispose);
      await pumpApp(
        tester,
        brightness,
        PersonalNoteEditorBody(
          controller: controller,
          focusNode: FocusNode(),
          scrollController: ScrollController(),
          autofocus: false,
          linkableNotes: const [],
        ),
      );
      expectReadable(tester, 'עורך');
    });
  }
}
