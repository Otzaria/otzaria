import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/find_ref_preference_store.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/panels/find_ref_personal_order_tile.dart';

import '../../helpers/memory_settings_cache.dart';

const _book = (key: 'o|4', title: 'שולחן ערוך חושן משפט');
const _resetKey = ValueKey('find-ref-personal-order-reset');

Widget _wrap() => const MaterialApp(
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(body: FindRefPersonalOrderTile()),
  ),
);

/// משדר כל כתיבה, כמו ספקי האחסון של האפליקציה.
class _BroadcastingSettingsCache extends MemorySettingsCache {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get changes => _changes.stream;

  @override
  Future<void> setObject<T>(String key, T? value) async {
    await super.setObject<T>(key, value);
    _changes.add(key);
  }
}

void main() {
  setUp(() async {
    await Settings.init(cacheProvider: _BroadcastingSettingsCache());
    await FindRefPreferenceStore.setEnabled(true);
    FindRefPreferenceStore.clear();
  });

  testWidgets('מתעדכנת משינויים שנעשו מחוץ לשורה', (tester) async {
    await tester.pumpWidget(_wrap());
    expect(find.byKey(_resetKey), findsNothing);

    // פתיחת ספר מהאיתור או מחלון אחר בזמן שעמוד ההגדרות חי.
    FindRefPreferenceStore.recordOpen(_book);
    await tester.pump();
    expect(find.byKey(_resetKey), findsOneWidget);

    await Settings.setValue<bool>(FindRefPreferenceStore.enabledKey, false);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  for (final width in [360.0, 1000.0]) {
    testWidgets('ברוחב $width הכותרת אינה נקטעת כשהאיפוס מוצג', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      FindRefPreferenceStore.recordOpen(_book);
      await tester.pumpWidget(_wrap());

      final title = find.text('איתור מותאם אישית');
      expect(
        tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
        isFalse,
      );
      // ברוחב רחב הכול נשאר בשורה אחת.
      final sameRow =
          tester.getRect(find.byType(Switch)).top <
          tester.getRect(title).bottom;
      expect(sameRow, width > 600);
    });
  }

  testWidgets('המתג מכבה ומדליק, וכיבוי אינו מוחק את מה שנלמד', (tester) async {
    FindRefPreferenceStore.recordOpen(_book);
    await tester.pumpWidget(_wrap());

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(FindRefPreferenceStore.isEnabled, isFalse);
    expect(find.text('תוצאות האיתור יוצגו בסדר הרגיל'), findsOneWidget);
    expect(FindRefPreferenceStore.load().books.keys, ['o|4']);
    expect(find.byKey(_resetKey), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(FindRefPreferenceStore.isEnabled, isTrue);
    expect(FindRefPreferenceStore.snapshot(), isNotNull);
  });

  testWidgets('בלי נתונים אין לחצן איפוס', (tester) async {
    await tester.pumpWidget(_wrap());
    expect(find.byKey(_resetKey), findsNothing);
    expect(find.byType(Switch), findsOneWidget);
  });

  testWidgets('האיפוס מוחק אחרי אישור, ואז הלחצן נעלם', (tester) async {
    FindRefPreferenceStore.recordOpen(_book);
    await tester.pumpWidget(_wrap());

    await tester.tap(find.byKey(_resetKey));
    await tester.pumpAndSettle();
    expect(find.text('ביטול'), findsOneWidget);
    await tester.tap(find.text('ביטול'));
    await tester.pumpAndSettle();
    expect(FindRefPreferenceStore.load().isEmpty, isFalse);

    await tester.tap(find.byKey(_resetKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('איפוס'));
    await tester.pumpAndSettle();

    expect(FindRefPreferenceStore.load().isEmpty, isTrue);
    expect(FindRefPreferenceStore.isEnabled, isTrue);
    expect(find.byKey(_resetKey), findsNothing);
  });

  testWidgets('Enter על לחצן האיפוס אינו מחליף את המתג', (tester) async {
    FindRefPreferenceStore.recordOpen(_book);
    await tester.pumpWidget(_wrap());

    final icon = find.descendant(
      of: find.byKey(_resetKey),
      matching: find.byType(Icon),
    );
    Focus.of(tester.element(icon)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(FindRefPreferenceStore.isEnabled, isTrue);
    expect(find.text('ביטול'), findsOneWidget);
  });
}
