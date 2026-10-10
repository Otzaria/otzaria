import 'package:flutter/material.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/navigation/nav_side_panel.dart';

import '../../test_helpers/memory_cache_provider.dart';

void main() {
  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  Future<void> pump(WidgetTester tester, {required bool isPinned}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NavPanelPinButton(isPinned: isPinned, onToggle: () {}),
          ),
        ),
      );

  testWidgets('נעיצה בהגדרות: הכפתור מסביר שהנעיצה נקבעה שם', (tester) async {
    await Settings.setValue<bool>('key-pin-sidebar', true);
    await pump(tester, isPinned: false);

    expect(find.byTooltip('החלונית נעוצה לפי ההגדרות'), findsOneWidget);
    expect(find.byTooltip('בטל נעיצה'), findsNothing);
  });

  testWidgets('בלי נעיצה בהגדרות: הכפתור מציע את הפעולה', (tester) async {
    await Settings.setValue<bool>('key-pin-sidebar', false);

    await pump(tester, isPinned: true);
    expect(find.byTooltip('בטל נעיצה'), findsOneWidget);

    await pump(tester, isPinned: false);
    expect(find.byTooltip('נעץ את החלונית'), findsOneWidget);
  });
}
