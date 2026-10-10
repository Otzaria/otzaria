import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/plugins/view/plugin_correction_paragraph.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

class _CountingService extends PluginCorrectionSessionService {
  int editableTextCalls = 0;

  @override
  String editableText(String tabId, int index, String source) {
    editableTextCalls++;
    return super.editableText(tabId, index, source);
  }
}

void main() {
  testWidgets('קריאה רגילה אינה מעבדת טקסט עבור עורך שאינו פעיל', (
    tester,
  ) async {
    final service = _CountingService();
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
          ),
        ),
      ),
    );
    expect(service.editableTextCalls, 0);
    expect(find.byType(RtlTextField), findsNothing);
    final session = service.begin(
      owner: 'owner',
      tabId: 'tab',
      bookId: 'ספר',
      bookUid: 'id:1',
      libraryVersion: '1',
      loadSource: (_) async => source,
    );
    await tester.pump();
    expect(find.byType(RtlTextField), findsOneWidget);
    expect(
      tester.widget<RtlTextField>(find.byType(RtlTextField)).controller!.text,
      'מקור',
    );
    final calls = service.editableTextCalls;
    service.end('owner', session['sessionId'], 0);
    await tester.pump();
    expect(service.editableTextCalls, calls);
    expect(find.text('קריאה'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
