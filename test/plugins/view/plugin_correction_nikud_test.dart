import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/plugins/repository/plugin_correction_draft_repository.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/plugins/view/plugin_correction_paragraph.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import '../../test_helpers/activate_correction_paragraph.dart';

void main() {
  const source = 'שָׁלוֹם עוֹלָם';

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
        loadSource: (_) async => source,
      ),
    );
    return service;
  }

  Future<void> pump(
    WidgetTester tester,
    PluginCorrectionSessionService service, {
    required bool removeNikud,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: PluginCorrectionParagraph(
            tabId: 'tab',
            sectionIndex: 0,
            sourceText: source,
            settings: RenderSettings(removeNikud: removeNikud),
            original: const Text('קריאה'),
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
}
