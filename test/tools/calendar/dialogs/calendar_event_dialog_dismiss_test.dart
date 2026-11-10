import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/dialogs/calendar_event_dialog.dart';

import '../../../helpers/memory_settings_cache.dart';

/// DD-08: דיאלוג האירוע שואל לפני סגירה עם שינויים שלא נשמרו.
void main() {
  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  Future<void> pumpDialog(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => showCalendarEventDialog(
                context: context,
                state: CalendarState.initial(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('Escape בלי שינויים סוגר מיד', (tester) async {
    await pumpDialog(tester);
    expect(find.byType(CalendarEventDialog), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(CalendarEventDialog), findsNothing);
  });

  testWidgets('Escape וביטול אחרי הקלדה שואלים, ו"המשך לערוך" משאיר', (
    tester,
  ) async {
    await pumpDialog(tester);
    await tester.enterText(find.byType(TextField).first, 'שיעור');
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('לסגור בלי לשמור?'), findsOneWidget);
    await tester.tap(find.text('המשך לערוך'));
    await tester.pumpAndSettle();
    expect(find.byType(CalendarEventDialog), findsOneWidget);

    await tester.tap(find.text('ביטול'));
    await tester.pumpAndSettle();
    expect(find.text('לסגור בלי לשמור?'), findsOneWidget);
    await tester.tap(find.text('סגור בלי לשמור'));
    await tester.pumpAndSettle();
    expect(find.byType(CalendarEventDialog), findsNothing);
  });
}
