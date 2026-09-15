import 'package:flutter/material.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/panels/tikkun_korim_settings_panel.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_settings.dart';

import '../../helpers/memory_settings_cache.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1000, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    const MaterialApp(
      locale: Locale('he', 'IL'),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SingleChildScrollView(child: TikkunKorimSettingsTab()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  testWidgets('הכרטיס מציג את פריטי "תוכן ומנהגים" של הכלי', (tester) async {
    await _pump(tester);

    expect(find.text('תיקון קוראים'), findsOneWidget);
    expect(find.text('פתיחה בהפעלה'), findsOneWidget);
    expect(find.text('נוסח הפטרה'), findsOneWidget);
    expect(find.text('מנהג לקריאות חגים ומועדים'), findsOneWidget);
    expect(find.text('הסתרת שם השם'), findsOneWidget);
  });

  testWidgets('שינוי במסך הכללי נכתב לאותם מפתחות של הכלי', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('מיקום אחרון'));
    await tester.tap(find.text('ספרדי'));
    await tester.tap(find.text('חוץ לארץ'));
    await tester.tap(find.text('הסתרת שם השם'));
    await tester.pumpAndSettle();

    final loaded = const TikkunSettingsStore().load();
    expect(loaded.startupMode, 'lastPosition');
    expect(loaded.nusach, 'sephard');
    expect(loaded.nusachLand, 'diaspora');
    expect(loaded.hideDivineName, isTrue);
  });
}
