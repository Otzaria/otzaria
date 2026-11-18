import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/plugins/repository/plugin_correction_draft_repository.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/plugins/view/plugin_correction_paragraph.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';
import '../../test_helpers/activate_correction_paragraph.dart';

void main() {
  const source = 'שָׁלוֹם עוֹלָם';

  RenderSettings settings(bool removeNikud, bool removeTeamim) =>
      RenderSettings(removeNikud: removeNikud, removeTeamim: removeTeamim);

  Future<PluginCorrectionSessionService> begin(
    WidgetTester tester, {
    String text = source,
  }) async {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    final service = PluginCorrectionSessionService()
      ..draftRepository = PluginCorrectionDraftRepository.direct(db);
    addTearDown(service.dispose);
    await tester.runAsync(
      () => service.begin(
        owner: 'owner',
        tabId: 'tab',
        bookId: 'ספר',
        bookUid: 'id:1',
        libraryVersion: '1',
        loadSource: (_) async => text,
      ),
    );
    return service;
  }

  Future<void> pump(
    WidgetTester tester,
    PluginCorrectionSessionService service, {
    required bool removeNikud,
    bool removeTeamim = false,
    String text = source,
    bool reading = false,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: PluginCorrectionParagraph(
            tabId: 'tab',
            sectionIndex: 0,
            sourceText: text,
            settings: settings(removeNikud, removeTeamim),
            original: reading
                ? SmartTextWidget(
                    text: text,
                    settings: settings(removeNikud, removeTeamim),
                  )
                : const Text('קריאה'),
            service: service,
            sessionActive: true,
          ),
        ),
      ),
    ),
  );

  testWidgets('ספר שהוגדר ללא ניקוד: העורך מציג בלי ניקוד ושומר ניקוד במקור', (
    tester,
  ) async {
    final service = await begin(tester);
    await pump(tester, service, removeNikud: true);
    await activateCorrectionParagraph(tester, find.text('קריאה'));
    await tester.pump();
    expect(find.byType(EditableText), findsOneWidget);
    EditableText editor() =>
        tester.widget<EditableText>(find.byType(EditableText));
    expect(editor().controller.text, 'שלום עולם');
    await tester.showKeyboard(find.byType(EditableText));
    await tester.pump(const Duration(seconds: 1));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'שלום עולם!',
        selection: TextSelection.collapsed(offset: 10),
      ),
    );
    await tester.pump();
    // רק התו שהוקלד התווסף; הניקוד של כל האותיות הקיימות נשמר.
    expect(service.editableText('tab', 0, source), '$source!');
    expect(editor().controller.text, 'שלום עולם!');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => service.flushAll());
  });

  testWidgets('ספר עם ניקוד: העורך מציג ניקוד', (tester) async {
    final service = await begin(tester);
    await pump(tester, service, removeNikud: false);
    await activateCorrectionParagraph(tester, find.text('קריאה'));
    await tester.pump();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      source,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => service.flushAll());
  });

  const tanakh = 'בְּרֵאשִׁ֖ית בָּרָ֣א אֱלֹהִ֑ים אֵ֣ת־הַשָּׁמַ֔יִם';
  for (final (nikud, teamim) in [(false, true), (true, true)]) {
    testWidgets(
      'העורך מציג את הטקסט של הקורא (ניקוד: $nikud, טעמים: $teamim)',
      (tester) async {
        final service = await begin(tester, text: tanakh);
        await pump(
          tester,
          service,
          removeNikud: nikud,
          removeTeamim: teamim,
          text: tanakh,
          reading: true,
        );
        final readingText = tester
            .widget<RichText>(
              find.descendant(
                of: find.byType(SmartTextWidget),
                matching: find.byType(RichText),
              ),
            )
            .text
            .toPlainText();
        await activateCorrectionParagraph(tester, find.byType(SmartTextWidget));
        await tester.pump();
        final editor = tester.widget<EditableText>(find.byType(EditableText));
        expect(editor.controller.text, readingText);
        final span = editor.controller.buildTextSpan(
          context: tester.element(find.byType(EditableText)),
          style: editor.style,
          withComposing: false,
        );
        // העלים של הקורא בשימוש: אילו הטקסט היה שונה, העורך היה טקסט פשוט.
        expect(span.children, isNotNull);
        expect(span.toPlainText(), readingText);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
        await tester.runAsync(() => service.flushAll());
      },
    );
  }

  testWidgets('ביטול וביצוע חוזר אחרי מחיקה מחזירים את הניקוד המלא', (
    tester,
  ) async {
    final service = await begin(tester);
    await pump(tester, service, removeNikud: true);
    await activateCorrectionParagraph(tester, find.text('קריאה'));
    await tester.pump();
    await tester.showKeyboard(find.byType(EditableText));
    await tester.pump(const Duration(seconds: 1));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'שלם עולם',
        selection: TextSelection.collapsed(offset: 3),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(service.editableText('tab', 0, source), 'שָׁלם עוֹלָם');
    expect(service.isCorrected('tab', 0, source), isTrue);
    Future<void> undo({bool redo = false}) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      if (redo) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      if (redo) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(seconds: 1));
    }

    await undo();
    expect(service.editableText('tab', 0, source), source);
    expect(service.isCorrected('tab', 0, source), isFalse);
    await undo(redo: true);
    expect(service.editableText('tab', 0, source), 'שָׁלם עוֹלָם');
    expect(service.isCorrected('tab', 0, source), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => service.flushAll());
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
