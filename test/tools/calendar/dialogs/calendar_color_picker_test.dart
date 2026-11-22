// בורר הצבע בדיאלוג האירוע (פריט 27): הצבע הנבחר מסומן בוי ובהודעה לקורא
// המסך, ולא בצבע המסגרת בלבד.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/dialogs/calendar_event_dialog.dart';

import '../../../helpers/memory_settings_cache.dart';

void main() {
  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  testWidgets('הצבע שנבחר מסומן בוי ו-Semantics selected, והשאר לא', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(1200, 900);
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

    final check = find.byIcon(FluentIcons.checkmark_24_regular);
    SemanticsNode node(String label) =>
        tester.getSemantics(find.bySemanticsLabel(label));

    // בהתחלה נבחר "ללא צבע".
    await tester.tap(find.text('בחר צבע'));
    await tester.pumpAndSettle();
    expect(check, findsOneWidget);
    expect(node('ללא צבע'), isSemantics(isSelected: true, isButton: true));

    await tester.tap(find.byTooltip('ירוק'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('בחר צבע'));
    await tester.pumpAndSettle();

    expect(check, findsOneWidget);
    expect(
      find.descendant(of: find.byTooltip('ירוק'), matching: check),
      findsOneWidget,
    );
    expect(node('ירוק'), isSemantics(isSelected: true, isButton: true));
    expect(node('אדום'), isSemantics(isSelected: false, isButton: true));
    expect(node('ללא צבע'), isSemantics(isSelected: false, isButton: true));
    semantics.dispose();
  });
}
