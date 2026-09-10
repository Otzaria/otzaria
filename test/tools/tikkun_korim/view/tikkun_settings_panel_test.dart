import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_settings.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/tikkun_settings_panel.dart';

Future<TikkunSettings?> _pumpPanel(
  WidgetTester tester, {
  TikkunSettings settings = const TikkunSettings(),
  required void Function(TikkunSettings) onChanged,
}) async {
  await tester.binding.setSurfaceSize(const Size(700, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('he', 'IL'),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SingleChildScrollView(
            child: TikkunSettingsPanel(
              settings: settings,
              onChanged: onChanged,
            ),
          ),
        ),
      ),
    ),
  );
  return null;
}

void main() {
  testWidgets('כיבוי מתג "הצגת טור המנוקד" מסתיר את הטור', (tester) async {
    TikkunSettings? updated;
    await _pumpPanel(tester, onChanged: (s) => updated = s);

    expect(find.text('הטור מוצג'), findsWidgets);
    await tester.tap(find.text('הצגת טור המנוקד'));
    await tester.pumpAndSettle();

    expect(updated?.hideNikud, isTrue);
  });

  testWidgets('כיבוי מתג קווי ההפרדה מסתיר אותם, והתיאור לפי המצב', (
    tester,
  ) async {
    TikkunSettings? updated;
    await _pumpPanel(tester, onChanged: (s) => updated = s);
    expect(find.text('הקווים יוצגו'), findsOneWidget);

    await tester.tap(find.text('קווי הפרדה בין השורות'));
    await tester.pumpAndSettle();
    expect(updated?.hideRowBorders, isTrue);

    await _pumpPanel(
      tester,
      settings: const TikkunSettings(hideRowBorders: true),
      onChanged: (_) {},
    );
    expect(find.text('הקווים לא יוצגו'), findsOneWidget);
  });

  testWidgets('סדר הטורים הוא בורר ולא מתג', (tester) async {
    TikkunSettings? updated;
    await _pumpPanel(tester, onChanged: (s) => updated = s);

    expect(find.text('סדר הטורים'), findsOneWidget);
    await tester.tap(find.text('ניקוד בימין'));
    await tester.pumpAndSettle();

    expect(updated?.swapColumns, isTrue);
  });

  testWidgets('הגדרת מירכוז מוצגת רק כשטור אחד מוסתר', (tester) async {
    await _pumpPanel(tester, onChanged: (_) {});
    expect(find.text('מרכוז הטור המוצג'), findsNothing);

    await _pumpPanel(
      tester,
      settings: const TikkunSettings(hideStam: true),
      onChanged: (_) {},
    );
    expect(find.text('מרכוז הטור המוצג'), findsOneWidget);
  });

  testWidgets('הזזת מחוון המרווח מעדכנת את ההגדרה', (tester) async {
    TikkunSettings? updated;
    await _pumpPanel(tester, onChanged: (s) => updated = s);

    final slider = find.byType(Slider).first;
    await tester.drag(slider, const Offset(-60, 0));
    await tester.pumpAndSettle();

    expect(updated, isNotNull);
    expect(updated!.lineSpacing, isNot(1.0));
    expect(updated!.lineSpacing, inInclusiveRange(0.5, 2.4));
  });

  testWidgets('אין הגדרות גודל גופן וזום', (tester) async {
    await _pumpPanel(tester, onChanged: (_) {});

    expect(find.byType(Slider), findsOneWidget);
    expect(find.text('גודל גופן סת"ם'), findsNothing);
    expect(find.text('גודל גופן ניקוד'), findsNothing);
    expect(find.text('זום תצוגה'), findsNothing);
  });

  testWidgets('כל ההגדרות המרכזיות מופיעות בחלונית', (tester) async {
    await _pumpPanel(tester, onChanged: (_) {});

    for (final label in [
      'גופן סת"ם',
      'גופן ניקוד',
      'מרווח בין שורות',
      'הצגת טור הסת"ם',
      'סדר הטורים',
      'קווי הפרדה בין השורות',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }

    expect(find.text('הסתרת שם השם'), findsOneWidget);
    expect(find.text('פתיחה בהפעלה'), findsOneWidget);
    expect(find.text('נוסח'), findsOneWidget);
    expect(find.text('מנהג לקריאות חגים ומועדים'), findsOneWidget);
  });

  testWidgets('בורר טעמי עשרת הדברות מעביר את הבחירה והתיאור לפי המצב', (
    tester,
  ) async {
    TikkunSettings? updated;
    await _pumpPanel(tester, onChanged: (s) => updated = s);

    expect(find.text('טעמי עשרת הדברות'), findsOneWidget);
    expect(find.text('שתי מערכות הטעמים על אותן אותיות'), findsOneWidget);

    await tester.tap(find.text('טעם עליון'));
    await tester.pumpAndSettle();
    expect(updated?.decalogueTaam, TikkunDecalogueTaam.elyon);

    await _pumpPanel(
      tester,
      settings: const TikkunSettings(
        decalogueTaam: TikkunDecalogueTaam.tachton,
      ),
      onChanged: (s) => updated = s,
    );
    expect(find.text('הטעמים שקוראים בהם ביחיד'), findsOneWidget);

    await tester.tap(find.text('משולב'));
    await tester.pumpAndSettle();
    expect(updated?.decalogueTaam, TikkunDecalogueTaam.merged);
  });
}
