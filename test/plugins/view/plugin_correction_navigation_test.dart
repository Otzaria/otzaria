import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/plugins/repository/plugin_correction_draft_repository.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/plugins/view/plugin_correction_paragraph.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import '../../test_helpers/activate_correction_paragraph.dart';

void main() {
  const sources = ['פסקה ראשונה', 'פסקה שנייה'];

  Future<PluginCorrectionSessionService> begin(WidgetTester tester) async {
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
        loadSource: (index) async => sources[index],
      ),
    );
    return service;
  }

  Future<void> pump(
    WidgetTester tester,
    PluginCorrectionSessionService service, {
    String searchText = '',
  }) => tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Column(
            children: [
              for (var i = 0; i < sources.length; i++)
                PluginCorrectionParagraph(
                  tabId: 'tab',
                  sectionIndex: i,
                  sourceText: sources[i],
                  settings: RenderSettings(searchText: searchText),
                  original: Text('קריאה $i'),
                  service: service,
                  sessionActive: true,
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> finish(
    WidgetTester tester,
    PluginCorrectionSessionService service,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => service.flushAll());
  }

  testWidgets('חץ מטה בשורה האחרונה מעביר עריכה לפסקה הבאה, וחץ מעלה חוזר', (
    tester,
  ) async {
    final service = await begin(tester);
    await pump(tester, service);
    await activateCorrectionParagraph(tester, find.text('קריאה 0'));
    await tester.pump();
    expect(find.byType(EditableText), findsOneWidget);
    expect(find.text('קריאה 1'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    final editors = find.byType(EditableText);
    expect(editors, findsOneWidget);
    expect(
      tester.widget<EditableText>(editors).controller.text,
      sources[1],
    );
    expect(tester.widget<EditableText>(editors).focusNode.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      sources[0],
    );
    await finish(tester, service);
  });

  testWidgets('חץ מטה ומעלה שומר על אותו מקום אופקי בפסקה הסמוכה', (
    tester,
  ) async {
    final service = await begin(tester);
    await pump(tester, service);
    await activateCorrectionParagraph(tester, find.text('קריאה 0'));
    await tester.pump();
    EditableText editor() =>
        tester.widget<EditableText>(find.byType(EditableText));
    editor().controller.selection = const TextSelection.collapsed(offset: 3);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(editor().controller.text, sources[1]);
    expect(editor().controller.selection.baseOffset, 3);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(editor().controller.text, sources[0]);
    expect(editor().controller.selection.baseOffset, 3);
    await finish(tester, service);
  });

  testWidgets('לחיצה אחת מפעילה עריכה, ושדה העריכה מקבל ירידת שורה', (
    tester,
  ) async {
    final service = await begin(tester);
    await pump(tester, service);
    await tester.tap(find.text('קריאה 0'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    expect(find.byType(EditableText), findsOneWidget);
    await tester.showKeyboard(find.byType(EditableText));
    await tester.pump(const Duration(seconds: 1));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'פסקה\n ראשונה',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump();
    expect(service.editableText('tab', 0, sources[0]), 'פסקה\n ראשונה');
    expect(service.isCorrected('tab', 0, sources[0]), isTrue);
    await finish(tester, service);
  });

  testWidgets('חיפוש מודגש בעורך כמו בפסקה הרגילה', (tester) async {
    final service = await begin(tester);
    await pump(tester, service, searchText: 'ראשונה');
    await activateCorrectionParagraph(tester, find.text('קריאה 0'));
    await tester.pump();
    final editor = tester.widget<EditableText>(find.byType(EditableText));
    final span = editor.controller.buildTextSpan(
      context: tester.element(find.byType(EditableText)),
      style: editor.style,
      withComposing: false,
    );
    final marked = (span.children ?? const <InlineSpan>[])
        .whereType<TextSpan>()
        .where((part) => part.style?.backgroundColor == const Color(0xFFFFFF00))
        .map((part) => part.text)
        .toList();
    expect(marked, ['ראשונה']);
    await finish(tester, service);
  });
}
