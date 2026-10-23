import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/plugins/repository/plugin_correction_draft_repository.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/plugins/view/plugin_correction_paragraph.dart';
import 'package:otzaria/widgets/smart_text/inline_html_document.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import '../../test_helpers/activate_correction_paragraph.dart';

class _CountingService extends PluginCorrectionSessionService {
  int editableTextCalls = 0;

  @override
  String editableText(String tabId, int index, String source) {
    editableTextCalls++;
    return super.editableText(tabId, index, source);
  }
}

void main() {
  testWidgets('סשן פעיל אינו מעבד פסקה שחורגת ממגבלת המקור', (tester) async {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    final service = _CountingService()
      ..draftRepository = PluginCorrectionDraftRepository.direct(db);
    addTearDown(service.dispose);
    final source = 'א' * (PluginCorrectionSessionService.maxTextLength + 1);
    final session = (await tester.runAsync(
      () => service.begin(
        owner: 'owner',
        tabId: 'tab',
        bookId: 'ספר',
        bookUid: 'id:1',
        libraryVersion: '1',
        loadSource: (_) async => source,
      ),
    ))!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PluginCorrectionParagraph(
            tabId: 'tab',
            sectionIndex: 0,
            sourceText: source,
            settings: const RenderSettings(),
            original: const Text('קריאה'),
            service: service,
            sessionActive: true,
          ),
        ),
      ),
    );
    expect(find.text('קריאה'), findsOneWidget);
    expect(find.byType(RtlTextField), findsNothing);
    expect(service.editableTextCalls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => service.end('owner', session['sessionId'], 0));
  });

  testWidgets('קריאה רגילה אינה מעבדת טקסט עבור עורך שאינו פעיל', (
    tester,
  ) async {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    final service = _CountingService()
      ..draftRepository = PluginCorrectionDraftRepository.direct(db);
    addTearDown(service.dispose);
    const source = '<b>מקור</b>';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PluginCorrectionParagraph(
            tabId: 'tab',
            sectionIndex: 0,
            sourceText: source,
            settings: const RenderSettings(),
            original: const Text('קריאה'),
            service: service,
            sessionActive: false,
          ),
        ),
      ),
    );
    expect(service.editableTextCalls, 0);
    expect(find.byType(RtlTextField), findsNothing);
    final session = (await tester.runAsync(
      () => service.begin(
        owner: 'owner',
        tabId: 'tab',
        bookId: 'ספר',
        bookUid: 'id:1',
        libraryVersion: '1',
        loadSource: (_) async => source,
      ),
    ))!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PluginCorrectionParagraph(
            tabId: 'tab',
            sectionIndex: 0,
            sourceText: source,
            settings: const RenderSettings(),
            original: const Text('קריאה'),
            service: service,
            sessionActive: true,
          ),
        ),
      ),
    );
    expect(find.text('קריאה'), findsOneWidget);
    expect(find.byType(RtlTextField), findsNothing);
    await activateCorrectionParagraph(tester, find.text('קריאה'));
    await tester.pump();
    expect(find.byType(RtlTextField), findsOneWidget);
    expect(
      tester.widget<RtlTextField>(find.byType(RtlTextField)).controller!.text,
      'מקור',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PluginCorrectionParagraph(
            tabId: 'tab',
            sectionIndex: 1,
            sourceText: '<b>אחר</b>',
            settings: const RenderSettings(),
            original: const Text('קריאה'),
            service: service,
            sessionActive: true,
          ),
        ),
      ),
    );
    expect(
      tester.widget<RtlTextField>(find.byType(RtlTextField)).controller!.text,
      'אחר',
    );
    final calls = service.editableTextCalls;
    await tester.runAsync(() => service.end('owner', session['sessionId'], 0));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PluginCorrectionParagraph(
            tabId: 'tab',
            sectionIndex: 0,
            sourceText: source,
            settings: const RenderSettings(),
            original: const Text('קריאה'),
            service: service,
            sessionActive: false,
          ),
        ),
      ),
    );
    expect(service.editableTextCalls, calls);
    expect(find.text('קריאה'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final source in [
    '<h2>אב</h2>',
    '<H2>אב</H2>',
    '<!--הערה--><h2>אב</h2>',
  ]) {
    testWidgets('כותרת בעורך מוגדלת פעם אחת כמו בקורא: $source', (
      tester,
    ) async {
      final db = sqlite3.openInMemory();
      addTearDown(db.close);
      final service = PluginCorrectionSessionService()
        ..draftRepository = PluginCorrectionDraftRepository.direct(db);
      addTearDown(service.dispose);
      const settings = RenderSettings();
      final session = (await tester.runAsync(
        () => service.begin(
          owner: 'owner',
          tabId: 'tab',
          bookId: 'ספר',
          bookUid: 'id:1',
          libraryVersion: '1',
          loadSource: (_) async => source,
        ),
      ))!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PluginCorrectionParagraph(
              tabId: 'tab',
              sectionIndex: 0,
              sourceText: source,
              settings: settings,
              original: const Text('קריאה'),
              service: service,
              sessionActive: true,
            ),
          ),
        ),
      );
      await activateCorrectionParagraph(tester, find.text('קריאה'));
      await tester.pump();
      final editor = tester.state<EditableTextState>(find.byType(EditableText));
      final span = editor.renderEditable.text! as TextSpan;
      double? sizeOf(InlineSpan span) => span is TextSpan
          ? (span.text?.isNotEmpty ?? false)
                ? span.style?.fontSize
                : span.children
                      ?.map(sizeOf)
                      .firstWhere((size) => size != null, orElse: () => null)
          : null;
      final reader = InlineHtmlDocument.parseLine(
        source,
        TextStyle(fontSize: settings.fontSize),
      )!;
      expect(reader.isHeading, isTrue);
      expect(sizeOf(span), reader.style.fontSize);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(
        () => service.end('owner', session['sessionId'], 0),
      );
    });
  }

  group('העורך מצייר כל אות כמו SmartTextWidget של הקורא', () {
    TextStyle? glyph(InlineSpan span, String char, TextStyle inherited) {
      if (span is! TextSpan) return null;
      final style = inherited.merge(span.style);
      if (span.text?.contains(char) ?? false) return style;
      for (final child in span.children ?? const <InlineSpan>[]) {
        final found = glyph(child, char, style);
        if (found != null) return found;
      }
      return null;
    }

    TextStyle readerGlyph(WidgetTester tester, String char) => glyph(
      tester
          .renderObjectList<RenderParagraph>(
            find.descendant(
              of: find.byType(SmartTextWidget),
              matching: find.byType(RichText),
            ),
          )
          .firstWhere(
            (paragraph) => paragraph.text.toPlainText().contains(char),
          )
          .text,
      char,
      const TextStyle(),
    )!;

    TextStyle editorGlyph(WidgetTester tester, String char) => glyph(
      tester
          .state<EditableTextState>(find.byType(EditableText))
          .renderEditable
          .text!,
      char,
      const TextStyle(),
    )!;

    void expectSameLook(TextStyle editor, TextStyle reader) {
      expect(editor.color, reader.color);
      expect(editor.fontSize, reader.fontSize);
      expect(editor.fontWeight, reader.fontWeight);
      expect(editor.decorationColor, reader.decorationColor);
    }

    const linkDecoration =
        '<a href="https://example.com" '
        'style="text-decoration-color: currentcolor">אב גד</a>';
    final cases = {
      'רווח כפול': '<b style="color:#ff0000">אב  גד</b>',
      'רווחי קצה': ' <b style="color:#ff0000">אב גד</b> ',
      'BR': '<b style="color:#ff0000">אב<br>גד</b>',
      'NBSP': '<b style="color:#ff0000">אב&nbsp;גד</b>',
      'כותרת H2 עם רווח כפול': '<H2>אב  גד</H2>',
      'קישור': '<a href="https://example.com">אב גד</a>',
      'קישור עם צבע קו מהנושא': linkDecoration,
      'כותרת H2 עם ישות שאינה בטקסט הקנוני': '<H2>אב&copy;גד</H2>',
      'line-height לא נתמך לצד צבע':
          '<b style="color:red;line-height:1.5">אב גד</b>',
      'line-height לא נתמך בלבד': '<b style="line-height:1.5">אב גד</b>',
    };
    for (final MapEntry(key: name, value: source) in cases.entries) {
      testWidgets(name, (tester) async {
        final db = sqlite3.openInMemory();
        addTearDown(db.close);
        final service = PluginCorrectionSessionService()
          ..draftRepository = PluginCorrectionDraftRepository.direct(db);
        addTearDown(service.dispose);
        const settings = RenderSettings();
        await tester.runAsync(
          () => service.begin(
            owner: 'owner',
            tabId: 'tab',
            bookId: 'ספר',
            bookUid: 'id:1',
            libraryVersion: '1',
            loadSource: (_) async => source,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PluginCorrectionParagraph(
                tabId: 'tab',
                sectionIndex: 0,
                sourceText: source,
                settings: settings,
                original: SmartTextWidget(text: source, settings: settings),
                service: service,
                sessionActive: true,
              ),
            ),
          ),
        );
        final reader = {
          for (final char in ['א', 'ג']) char: readerGlyph(tester, char),
        };
        await activateCorrectionParagraph(
          tester,
          find.byType(SmartTextWidget),
        );
        await tester.pump();
        // גם אחרי הרווח או השבירה: הסטה הייתה צובעת את ג בסגנון אחר.
        for (final char in ['א', 'ג']) {
          expectSameLook(editorGlyph(tester, char), reader[char]!);
        }

        final text = tester
            .widget<RtlTextField>(find.byType(RtlTextField))
            .controller!
            .text;
        final at = text.indexOf('א') + 1;
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: at),
          ),
        );
        await tester.pump();
        final typed = text.replaceRange(at, at, 'ק');
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: typed,
            selection: TextSelection.collapsed(offset: at + 1),
          ),
        );
        await tester.pump();
        expectSameLook(editorGlyph(tester, 'ק'), reader['א']!);
        expectSameLook(editorGlyph(tester, 'ג'), reader['ג']!);

        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: typed,
            selection: TextSelection.collapsed(offset: at + 1),
            composing: TextRange(start: at, end: at + 1),
          ),
        );
        await tester.pump();
        final composing = editorGlyph(tester, 'ק');
        expectSameLook(composing, reader['א']!);
        expect(
          composing.decoration?.contains(TextDecoration.underline),
          isTrue,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
        await tester.runAsync(
          () => service.shutdown(timeout: const Duration(seconds: 5)),
        );
        await tester.pump();
      });
    }
  });
}
