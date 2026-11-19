import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
import 'package:otzaria/text_display/view/text_display_bar_button.dart';
import 'package:otzaria/widgets/misc/app_dropdown_field.dart';

/// חלונית "תצוגת הטקסט" שומרת את בחירות התצוגה לכל מקטע.
void main() {
  /// מארח את החלונית עם פרופיל לכל מקטע שמתעדכן בכל שינוי.
  Future<List<TextDisplayProfile>> pumpPanel(
    WidgetTester tester, {
    required List<TextDisplayProfile> profiles,
    List<String> titles = const ['גוף הספר', 'מפרשים'],
    VoidCallback? onReset,
  }) async {
    final current = [...profiles];
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) => TextDisplayPopupPanel(
                  viewLabel: 'תצוגה רגילה',
                  sections: [
                    for (var i = 0; i < current.length; i++)
                      TextDisplaySection(
                        title: titles[i],
                        profile: current[i],
                        onChanged: (p) => setState(() => current[i] = p),
                      ),
                  ],
                  footer: 'השינויים חלים על כרטיסייה זו בלבד',
                  onReset: onReset,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return current;
  }

  /// המתג בשורה שהכותרת שלה [title]; [last] — המופע האחרון (מקטע המפרשים).
  Finder switchOf(String title, {bool last = false}) {
    final text = last ? find.text(title).last : find.text(title).first;
    final row = find.ancestor(of: text, matching: find.byType(Row)).first;
    return find.descendant(of: row, matching: find.byType(Switch));
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('מקטע המפרשים מקופל, ונפתח ונסגר בלחיצה על הכותרת', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      profiles: const [
        TextDisplayProfile.defaults,
        TextDisplayProfile.defaults,
      ],
    );

    expect(find.text('גוף הספר'), findsOneWidget);
    expect(find.text('מפרשים'), findsOneWidget);
    // רק השורות של גוף הספר גלויות.
    expect(find.text('ציוני המפרשים'), findsOneWidget);
    expect(find.byType(Switch), findsNWidgets(4));

    await tapAndSettle(tester, find.text('מפרשים'));
    expect(find.text('ציוני המפרשים'), findsNWidgets(2));
    expect(find.text('ניקוד'), findsNWidgets(2));
    expect(find.text('שאר שמות הקודש'), findsNWidgets(2));

    await tapAndSettle(tester, find.text('מפרשים'));
    expect(find.text('ציוני המפרשים'), findsOneWidget);
  });

  testWidgets('שינוי במקטע המפרשים נוגע במפרשים בלבד', (tester) async {
    final current = await pumpPanel(
      tester,
      profiles: const [
        TextDisplayProfile.defaults,
        TextDisplayProfile.defaults,
      ],
    );
    await tapAndSettle(tester, find.text('מפרשים'));

    await tapAndSettle(tester, switchOf('סימני פיסוק', last: true));

    expect(current[0].punctuation, MarkVisibility.show);
    expect(current[1].punctuation, MarkVisibility.hide);
  });

  testWidgets('נוסחי שמות הקודש נשמרים בנפרד לכל מקטע', (tester) async {
    final current = await pumpPanel(
      tester,
      profiles: const [
        TextDisplayProfile.defaults,
        TextDisplayProfile.defaults,
      ],
    );
    await tapAndSettle(tester, find.text('מפרשים'));

    final dropdowns = find.byType(AppDropdownField<HolyNameDisplay>);
    expect(dropdowns, findsNWidgets(2));
    final commentary = tester.widget<AppDropdownField<HolyNameDisplay>>(
      dropdowns.last,
    );
    expect(
      commentary.entries.map((entry) => entry.value),
      unorderedEquals(HolyNameDisplay.values),
    );
    await tapAndSettle(tester, dropdowns.last);
    await tapAndSettle(tester, find.text('ידוד').hitTestable());
    expect(current[1].holyName, HolyNameDisplay.daletDalet);
    expect(current[1].divineNames, DivineNamesDisplay.asIs);

    await tapAndSettle(tester, find.text('בכינוי').last);
    expect(current[1].holyName, HolyNameDisplay.daletDalet);
    expect(current[1].divineNames, DivineNamesDisplay.substitute);
    expect(current[0], TextDisplayProfile.defaults);
  });

  testWidgets('"איפוס" מוצג רק כשיש עקיפה', (tester) async {
    await pumpPanel(
      tester,
      profiles: const [
        TextDisplayProfile.defaults,
        TextDisplayProfile.defaults,
      ],
    );
    expect(find.text('איפוס'), findsNothing);

    var resets = 0;
    await pumpPanel(
      tester,
      profiles: const [
        TextDisplayProfile.defaults,
        TextDisplayProfile.defaults,
      ],
      onReset: () => resets++,
    );
    await tapAndSettle(tester, find.text('איפוס'));
    expect(resets, 1);
  });

  group('תג "כמו הניקוד"', () {
    Finder chip() => find.text('כמו הניקוד');

    testWidgets('לחיצה על התג מקשרת את הטעמים לניקוד', (tester) async {
      final current = await pumpPanel(
        tester,
        profiles: const [TextDisplayProfile(teamim: TeamimVisibility.hide)],
        titles: const ['גוף הספר'],
      );

      await tapAndSettle(tester, chip());
      expect(current[0].teamim, TeamimVisibility.followNikud);
    });

    for (final (nikud, expected) in [
      (MarkVisibility.hide, TeamimVisibility.hide),
      (MarkVisibility.show, TeamimVisibility.show),
    ]) {
      testWidgets(
        'לחיצה שנייה מנתקת ושומרת את המצב בפועל (ניקוד ${nikud.name})',
        (tester) async {
          final current = await pumpPanel(
            tester,
            profiles: [
              TextDisplayProfile(
                nikud: nikud,
                teamim: TeamimVisibility.followNikud,
              ),
            ],
            titles: const ['גוף הספר'],
          );
          final shownBefore = !current[0].removeTeamim;

          await tapAndSettle(tester, chip());

          expect(current[0].teamim, expected);
          expect(!current[0].removeTeamim, shownBefore);
          expect(current[0].nikud, nikud);
        },
      );
    }

    for (final (nikud, expected) in [
      (MarkVisibility.show, TeamimVisibility.hide),
      (MarkVisibility.hide, TeamimVisibility.show),
    ]) {
      testWidgets(
        'מתג הטעמים כשהתג בחור קובע ${expected.name} ומבטל את הקישור',
        (tester) async {
          final current = await pumpPanel(
            tester,
            profiles: [
              TextDisplayProfile(
                nikud: nikud,
                teamim: TeamimVisibility.followNikud,
              ),
            ],
            titles: const ['גוף הספר'],
          );
          // המתג מראה את המצב בפועל — הטעמים הולכים אחרי הניקוד.
          expect(
            tester.widget<Switch>(switchOf('טעמי המקרא')).value,
            nikud == MarkVisibility.show,
          );

          await tapAndSettle(tester, switchOf('טעמי המקרא'));

          expect(current[0].teamim, expected);
          expect(current[0].nikud, nikud);
        },
      );
    }

    testWidgets('בלי בורר טעמים (includeTeamimSelector: false) אין תג', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TextDisplayPopupPanel(
                viewLabel: 'תצוגה רגילה',
                sections: [
                  TextDisplaySection(
                    title: 'גוף הספר',
                    profile: TextDisplayProfile.defaults,
                    onChanged: (_) {},
                    includeTeamimSelector: false,
                  ),
                ],
                footer: 'הערה',
              ),
            ),
          ),
        ),
      );
      expect(chip(), findsNothing);
      expect(find.text('טעמי המקרא'), findsNothing);
    });
  });
}
