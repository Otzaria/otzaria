import 'dart:ui' show Tristate;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/controls/segmented_control.dart';

void main() {
  Widget control({bool? showSelectedIcon}) => MaterialApp(
    home: Scaffold(
      body: showSelectedIcon == null
          ? AppSegmentedControl<int>(
              options: const [
                SegmentOption(value: 1, label: 'One'),
                SegmentOption(value: 2, label: 'Two'),
              ],
              currentValue: 1,
              onChanged: (_) {},
            )
          : AppSegmentedControl<int>(
              options: const [
                SegmentOption(value: 1, label: 'One'),
                SegmentOption(value: 2, label: 'Two'),
              ],
              currentValue: 1,
              onChanged: (_) {},
              showSelectedIcon: showSelectedIcon,
            ),
    ),
  );

  testWidgets('AppSegmentedControl hides the selected check icon by default', (
    tester,
  ) async {
    await tester.pumpWidget(control());

    expect(find.byIcon(FluentIcons.checkmark_24_regular), findsNothing);
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('AppSegmentedControl shows the check icon when asked to', (
    tester,
  ) async {
    await tester.pumpWidget(control(showSelectedIcon: true));

    expect(find.byIcon(FluentIcons.checkmark_24_regular), findsOneWidget);
  });

  testWidgets(
    'AppSegmentedControl shows a cut label in full on hover (#1862)',
    (tester) async {
      const labels = [
        'העמוד הנוכחי',
        'הפרשה',
        'הכל',
        'טווח עמודים',
        'טווח פסוקים',
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SizedBox(
                width: 460,
                child: AppSegmentedControl<String>(
                  expandToFillWidth: true,
                  options: [
                    for (final label in labels)
                      SegmentOption(value: label, label: label),
                  ],
                  currentValue: labels[1],
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );

      final cut = tester.renderObject<RenderParagraph>(
        find.text('טווח פסוקים'),
      );
      expect(cut.didExceedMaxLines, isTrue);
      for (final label in labels) {
        expect(find.byTooltip(label), findsOneWidget, reason: label);
      }
    },
  );

  testWidgets('AppSegmentedControl uses a custom tooltip and a label key', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppSegmentedControl<int>(
            options: const [
              SegmentOption(value: 1, label: 'One', tooltip: 'First option'),
              SegmentOption(
                value: 2,
                label: 'Two',
                labelKey: ValueKey('second'),
              ),
            ],
            currentValue: 1,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.byTooltip('First option'), findsOneWidget);
    expect(find.byTooltip('One'), findsNothing);
    expect(find.byTooltip('Two'), findsOneWidget);
    expect(find.byKey(const ValueKey('second')), findsOneWidget);
  });

  // q12 Q8: בטלפון האייקונים לקחו את מקום התווית ("...מד").
  testWidgets('במקטע צר מ-96 בלי אייקונים ובתווית הקצרה, ברוחב רגיל לא', (
    tester,
  ) async {
    Widget at(double width) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: AppSegmentedControl<int>(
              expandToFillWidth: true,
              options: const [
                SegmentOption(
                  value: 1,
                  label: 'מדויק',
                  icon: FluentIcons.text_quote_24_regular,
                ),
                SegmentOption(
                  value: 2,
                  label: 'מתקדם',
                  icon: FluentIcons.search_24_regular,
                ),
                SegmentOption(
                  value: 3,
                  label: 'מקורב',
                  icon: FluentIcons.arrow_autofit_width_24_regular,
                ),
                SegmentOption(
                  value: 4,
                  label: 'חיפוש חכם',
                  shortLabel: 'חכם',
                  icon: FluentIcons.sparkle_24_regular,
                ),
              ],
              currentValue: 1,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(at(280));
    expect(find.byIcon(FluentIcons.search_24_regular), findsNothing);
    expect(find.text('מתקדם'), findsOneWidget);
    // במקטע צר התווית הקצרה, והמלאה ב-tooltip.
    expect(find.text('חכם'), findsOneWidget);
    expect(find.text('חיפוש חכם'), findsNothing);
    expect(find.byTooltip('חיפוש חכם'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(at(600));
    expect(find.byIcon(FluentIcons.search_24_regular), findsOneWidget);
    expect(find.text('חיפוש חכם'), findsOneWidget);
    expect(find.text('חכם'), findsNothing);
  });

  // סקירה שלישית 4.11, q-ss7: 2×2 "רק כשממש קטן ויחתך חלק מהטקסט בכפתור".
  // בגופן הבדיקות כל אות ברוחב 14, והריווח 12 מכל צד: "Three" (70) נכנס
  // במקטע של 94 ומעלה.
  group('twoRowsWhenClipped', () {
    const icons = [
      FluentIcons.text_quote_24_regular,
      FluentIcons.search_24_regular,
      FluentIcons.arrow_autofit_width_24_regular,
      FluentIcons.sparkle_24_regular,
    ];
    Widget at(
      double width, {
      List<String> labels = const ['One', 'Two', 'Three', 'Four'],
      int current = 1,
      ValueChanged<int>? onChanged,
      bool twoRows = true,
      double textScale = 1,
    }) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: AppSegmentedControl<int>(
                expandToFillWidth: true,
                twoRowsWhenClipped: twoRows,
                options: [
                  for (var i = 0; i < labels.length; i++)
                    SegmentOption(
                      value: i + 1,
                      label: labels[i],
                      icon: icons[i],
                    ),
                ],
                currentValue: current,
                onChanged: onChanged ?? (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    final rows = find.byType(SegmentedButton<int>);

    testWidgets('התוויות נכנסות: שורה אחת, והאייקונים יורדים לפי מדידה', (
      tester,
    ) async {
      // 600: מקטע 150, "Three" עם אייקון (70 ועוד 52) נכנס.
      await tester.pumpWidget(at(600));
      expect(rows, findsOneWidget);
      expect(find.byIcon(icons[1]), findsOneWidget);
      // 400: מקטע 100 — עם אייקון 122 לא נכנס, בלי אייקון (76) כן.
      await tester.pumpWidget(at(400));
      expect(rows, findsOneWidget);
      expect(find.byIcon(icons[1]), findsNothing);
      // 360: מקטע 90, ותוויות של 3 אותיות נכנסות בלי אייקון.
      await tester.pumpWidget(
        at(360, labels: const ['אבג', 'דהו', 'זחט', 'יכל']),
      );
      expect(rows, findsOneWidget);
      expect(find.byIcon(icons[1]), findsNothing);
      for (final p in tester.renderObjectList<RenderParagraph>(
        find.byType(RichText),
      )) {
        expect(p.didExceedMaxLines, isFalse);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('תווית נחתכת גם בלי אייקון: 2×2 עם האייקונים', (tester) async {
      // 360: מקטע 90, ל-"Three" נשארים 66.
      await tester.pumpWidget(at(360));
      expect(rows, findsNWidgets(2));
      // בשתי שורות מקטע של 180: האייקונים חוזרים, וכל התוויות שלמות.
      expect(find.byIcon(icons[2]), findsOneWidget);
      final three = tester.renderObject<RenderParagraph>(find.text('Three'));
      expect(three.didExceedMaxLines, isFalse);
      expect(
        tester.getTopLeft(find.text('Three')).dy,
        greaterThan(tester.getBottomLeft(find.text('One')).dy),
      );
      expect(tester.takeException(), isNull);

      // בלי ההגדרה: שורה אחת, כמו קודם.
      await tester.pumpWidget(at(360, twoRows: false));
      expect(rows, findsOneWidget);
    });

    testWidgets('הגדלת טקסט נמדדת: אותו רוחב, ב-×2 שתי שורות', (tester) async {
      const short = ['אבג', 'דהו', 'זחט', 'יכל'];
      await tester.pumpWidget(at(360, labels: short));
      expect(rows, findsOneWidget);
      // ×2: התווית 84, והריווח 8 מכל צד — 74 בלבד.
      await tester.pumpWidget(at(360, labels: short, textScale: 2));
      expect(rows, findsNWidgets(2));
    });

    testWidgets('ב-2×2 בחירה, חצים ו-semantics כמו בשורה', (tester) async {
      final semantics = tester.ensureSemantics();
      var current = 1;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => at(
            360,
            current: current,
            onChanged: (v) => setState(() => current = v),
          ),
        ),
      );
      expect(rows, findsNWidgets(2));

      // לחיצה על מקטע בשורה השנייה בוחרת אותו, והשורה הראשונה בלי בחירה.
      await tester.tap(find.text('Four'));
      await tester.pumpAndSettle();
      expect(current, 4);
      expect(
        tester.widget<SegmentedButton<int>>(rows.first).selected,
        isEmpty,
      );
      expect(tester.widget<SegmentedButton<int>>(rows.last).selected, {4});
      // אותם דגלים כמו מקטע בשורה אחת (SegmentedButton): נבחר, בקבוצה בלעדית.
      final four = tester.getSemantics(find.text('Four')).getSemanticsData();
      expect(four.flagsCollection.isSelected, Tristate.isTrue);
      expect(four.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
      final one = tester.getSemantics(find.text('One')).getSemanticsData();
      expect(one.flagsCollection.isSelected, Tristate.isFalse);
      expect(one.flagsCollection.isInMutuallyExclusiveGroup, isTrue);

      // לחיצה על הנבחר אינה מבטלת את הבחירה.
      await tester.tap(find.text('Four'));
      await tester.pumpAndSettle();
      expect(current, 4);

      // מקלדת: Tab למקטע הראשון, חץ ימינה לשני, חץ למטה לרביעי, Space בוחר.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(current, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(current, 3);
      semantics.dispose();
    });

    testWidgets('ב-2×2 לחיצה על הנבחר שקטה, כמו בשורה', (tester) async {
      final calls = <int>[];
      Widget control() => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: AppSegmentedControl<int>(
                expandToFillWidth: true,
                twoRowsWhenClipped: true,
                options: [
                  for (final (i, label) in [
                    'One',
                    'Two',
                    'Three',
                    'Four',
                  ].indexed)
                    SegmentOption(value: i + 1, label: label, icon: icons[i]),
                ],
                currentValue: 4,
                onChanged: calls.add,
              ),
            ),
          ),
        ),
      );

      await tester.pumpWidget(control());
      expect(rows, findsNWidgets(2));
      // הנבחר בשורה השנייה, והשורה שלו מתירה בחירה ריקה: הלחיצה עליו לא
      // מדווחת, ומקטע בשורה בלי בחירה מדווח את הערך שלו.
      await tester.tap(find.text('Four'));
      await tester.pump();
      await tester.tap(find.text('Two'));
      await tester.pump();
      expect(calls, [2]);
    });
  });
}
