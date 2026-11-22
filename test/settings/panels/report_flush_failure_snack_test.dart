// כשל בשליחת הדיווחים השמורים מוצג כשגיאה (אייקון וטון), לא כהודעה
// ניטרלית שדומה להודעת הצלחה.
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/report_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/panels/report_panel_widgets.dart';

void main() {
  tearDown(UiSnack.hide);

  Future<void> flush(WidgetTester tester, {required int sent}) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => flushReportQueue(
                context,
                pendingCount: () async => 2,
                flush: () async => sent,
                setBusy: (_) {},
              ),
              child: const Text('שלח'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('שלח'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('שליחה שנכשלה: הודעת שגיאה עם אייקון שגיאה', (tester) async {
    await flush(tester, sent: 0);

    expect(find.text(ReportMessages.pendingFlushFailed(2)), findsOneWidget);
    expect(find.byIcon(FluentIcons.error_circle_24_regular), findsOneWidget);
    // מרוקנים את טיימר ההודעה לפני סוף הבדיקה.
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('שליחה שהצליחה: הודעת הצלחה, בלי אייקון שגיאה', (tester) async {
    await flush(tester, sent: 2);

    expect(find.text(ReportMessages.pendingFlushed(2)), findsOneWidget);
    expect(find.byIcon(FluentIcons.error_circle_24_regular), findsNothing);
    await tester.pump(const Duration(seconds: 10));
  });
}
