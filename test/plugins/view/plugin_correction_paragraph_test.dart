import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/plugins/repository/plugin_correction_draft_repository.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/plugins/view/plugin_correction_paragraph.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
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
}
