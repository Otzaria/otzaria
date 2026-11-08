import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
import 'package:otzaria/text_display/view/text_display_bar_button.dart';
import 'package:otzaria/text_display/view/text_display_profile_editor.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/misc/app_dropdown_field.dart';
import 'package:otzaria/widgets/controls/segmented_control.dart';

import '../support/golden_fonts.dart';

/// פאנל "תצוגת הטקסט" כטבלה: שורה לכל הגדרה ועמודה לכל מקטע, וההסברים
/// ב-tooltip על שם השורה (q12 Q7).
const _labels = [
  'ניקוד',
  'טעמי המקרא',
  'סימני פיסוק',
  'שם הוי"ה',
  'שאר שמות הקודש',
  'ציוני המפרשים',
];
const _titles = ['גוף הספר', 'מפרשים'];

/// גובה הפאנל של אפשרות A בדף q12 היה בערך 353 (בלי כפתור "איפוס").
const _maxHeight = 360.0;

/// ערכת הנושא האמיתית בפלטפורמת ה-goldens, עם גופן ממשק אמיתי: גובה הפקדים
/// ורוחב השמות בה קובעים את גובה הפאנל.
ThemeData _theme() => AppThemeData.light(
  AppThemeData.createColorScheme(
    AppSeedColors.defaultLight,
    Brightness.light,
  ),
  compactMenuMode: false,
);

Future<Map<String, TextDisplayProfile>> _open(
  WidgetTester tester, {
  Size window = const Size(1280, 800),
  List<String> titles = _titles,
  VoidCallback? onReset,
}) async {
  tester.view.physicalSize = window;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await loadGoldenFonts();
  final changes = <String, TextDisplayProfile>{};
  await tester.pumpWidget(
    MaterialApp(
      theme: _theme(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Builder(
            builder: (context) => Align(
              alignment: AlignmentDirectional.topStart,
              child: Builder(
                builder: (anchor) => TextButton(
                  onPressed: () => showTextDisplayPopup(
                    context,
                    anchorContext: anchor,
                    panelBuilder: (_) => TextDisplayPopupPanel(
                      viewLabel: 'תצוגה רגילה',
                      sections: [
                        for (final t in titles)
                          TextDisplaySection(
                            title: t,
                            profile: TextDisplayProfile.defaults,
                            onChanged: (next) => changes[t] = next,
                          ),
                      ],
                      footer: 'השינויים חלים על כרטיסייה זו בלבד',
                      onReset: onReset,
                    ),
                  ),
                  child: const Text('פתח'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('פתח'));
  await tester.pumpAndSettle();
  return changes;
}

/// התא של [label] בעמודה [title].
Finder _cell(String label, String title) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == '$label, $title',
);

/// בפלטפורמת ה-goldens (Windows): צפיפות וגופן כמו באפליקציה.
void _test(String description, WidgetTesterCallback body) => testWidgets(
  description,
  body,
  variant: TargetPlatformVariant.only(goldenPlatform),
);

void main() {
  _test('ב-1280×800 הפאנל טבלה נמוכה: כל שם פעם אחת, עמודה לכל מקטע', (
    tester,
  ) async {
    await _open(tester);

    final panel = find.byType(TextDisplayPopupPanel);
    final size = tester.getSize(panel);
    expect(size.height, lessThan(_maxHeight), reason: 'גובה $size');
    expect(find.byType(Table), findsOneWidget);
    for (final label in _labels) {
      expect(find.text(label), findsOneWidget, reason: label);
      for (final title in _titles) {
        expect(_cell(label, title), findsOneWidget, reason: '$label/$title');
      }
    }
    for (final title in _titles) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.byType(AppSegmentedControl<MarkVisibility>), findsNWidgets(6));
    expect(
      find.byType(AppSegmentedControl<TeamimVisibility>),
      findsNWidgets(2),
    );
    expect(
      find.byType(AppSegmentedControl<DivineNamesDisplay>),
      findsNWidgets(2),
    );
    expect(find.byType(AppDropdownField<HolyNameDisplay>), findsNWidgets(2));
    expect(find.byTooltip('סגור'), findsOneWidget);

    // התאים של אותה שורה מיושרים; "גוף הספר" בימין (RTL).
    final body = tester.getCenter(_cell('ניקוד', 'גוף הספר'));
    final commentary = tester.getCenter(_cell('ניקוד', 'מפרשים'));
    expect(body.dy, closeTo(commentary.dy, 0.5));
    expect(body.dx, greaterThan(commentary.dx));
    expect(
      tester.getCenter(find.text('ניקוד')).dx,
      greaterThan(body.dx),
      reason: 'עמודת השמות בצד ההתחלה',
    );
  });

  _test('כל פקד בטבלה משנה את השדה שלו ביעד של העמודה שלו', (
    tester,
  ) async {
    final changes = await _open(tester);

    Future<void> tapIn(String label, String title, String option) async {
      await tester.tap(
        find.descendant(of: _cell(label, title), matching: find.text(option)),
      );
      await tester.pumpAndSettle();
    }

    const d = TextDisplayProfile.defaults;
    for (final title in _titles) {
      await tapIn('ניקוד', title, 'הסתר');
      expect(changes[title], d.copyWith(nikud: MarkVisibility.hide));
      await tapIn('טעמי המקרא', title, 'הסתר');
      expect(changes[title], d.copyWith(teamim: TeamimVisibility.hide));
      await tapIn('סימני פיסוק', title, 'הסתר');
      expect(changes[title], d.copyWith(punctuation: MarkVisibility.hide));
      await tapIn('שאר שמות הקודש', title, 'בכינוי');
      expect(
        changes[title],
        d.copyWith(divineNames: DivineNamesDisplay.substitute),
      );
      await tapIn('ציוני המפרשים', title, 'הסתר');
      expect(changes[title], d.copyWith(anchorMarkers: MarkVisibility.hide));

      await tester.tap(
        find.descendant(
          of: _cell('שם הוי"ה', title),
          matching: find.byType(AppDropdownField<HolyNameDisplay>),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('ידוד').last);
      await tester.pumpAndSettle();
      expect(
        changes[title],
        d.copyWith(holyName: HolyNameDisplay.daletDalet),
      );
    }
    expect(changes.keys, unorderedEquals(_titles));
  });

  _test('ההסברים ב-tooltip על שם השורה, לא כטקסט גלוי', (tester) async {
    await _open(tester);

    const explained = {
      'שאר שמות הקודש': 'אלהים, שדי, צבאות ועוד — בספרים שבהם השמות מסומנים',
      'ציוני המפרשים': 'אותיות הציון שבטקסט, למשל (א)',
    };
    for (final MapEntry(key: label, value: subtitle) in explained.entries) {
      expect(find.text(subtitle), findsNothing);
      final tooltip = find.ancestor(
        of: find.text(label),
        matching: find.byType(Tooltip),
      );
      expect(tooltip, findsOneWidget, reason: label);
      expect(tester.widget<Tooltip>(tooltip).message, subtitle);
    }

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.text('שאר שמות הקודש')));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text(explained['שאר שמות הקודש']!), findsOneWidget);
  });

  _test('"איפוס" בשורת ההסבר כשיש עקיפות', (tester) async {
    var reset = 0;
    await _open(tester, onReset: () => reset++);
    await tester.tap(find.text('איפוס'));
    expect(reset, 1);
    expect(find.text('השינויים חלים על כרטיסייה זו בלבד'), findsOneWidget);
  });

  _test('מקטע אחד: עמודה אחת, בלי כותרת עמודה כפולה', (tester) async {
    await _open(tester, titles: const ['גוף הספר']);
    for (final label in _labels) {
      expect(_cell(label, 'גוף הספר'), findsOneWidget);
    }
    expect(
      tester.getSize(find.byType(TextDisplayPopupPanel)).height,
      lessThan(_maxHeight),
    );
  });

  _test('בחלון צר השם עולה מעל, שורה לכל יעד, וכל הפקדים נשארים', (
    tester,
  ) async {
    await _open(tester, window: const Size(420, 800));

    expect(find.byType(Table), findsNothing);
    expect(find.byType(TextDisplayProfileTable), findsOneWidget);
    for (final label in _labels) {
      for (final title in _titles) {
        expect(_cell(label, title), findsOneWidget);
      }
      // השם מעל התא של "גוף הספר", והמפרשים בשורה משלהם מתחתיו.
      final body = tester.getRect(_cell(label, 'גוף הספר'));
      final commentary = tester.getRect(_cell(label, 'מפרשים'));
      expect(
        tester.getBottomLeft(find.text(label)).dy,
        lessThanOrEqualTo(body.top),
      );
      expect(commentary.top, greaterThanOrEqualTo(body.bottom - 0.5));
    }
    expect(tester.takeException(), isNull);
  });
}
