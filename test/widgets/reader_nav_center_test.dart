import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/widgets/controls/bar_button.dart';
import 'package:otzaria/widgets/navigation/reader_nav_center.dart';

void main() {
  group('ReaderNavCenter', () {
    testWidgets('מציג כותרת וארבעה כפתורי ניווט שמפעילים את ה-callbacks', (
      tester,
    ) async {
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());
      addTearDown(settingsBloc.close);

      final pressed = <String>[];
      await tester.pumpWidget(
        _buildHarness(
          settingsBloc: settingsBloc,
          child: ReaderNavCenter(
            title: const Text('ספר בדיקה'),
            prevMajorTooltip: 'פרק קודם',
            prevMinorTooltip: 'קטע קודם',
            nextMinorTooltip: 'קטע הבא',
            nextMajorTooltip: 'פרק הבא',
            onPrevMajor: () => pressed.add('prevMajor'),
            onPrevMinor: () => pressed.add('prevMinor'),
            onNextMinor: () => pressed.add('nextMinor'),
            onNextMajor: () => pressed.add('nextMajor'),
          ),
        ),
      );

      expect(find.text('ספר בדיקה'), findsOneWidget);

      for (final tooltip in ['פרק קודם', 'קטע קודם', 'קטע הבא', 'פרק הבא']) {
        await tester.tap(find.byTooltip(tooltip));
      }
      expect(pressed, ['prevMajor', 'prevMinor', 'nextMinor', 'nextMajor']);
    });

    testWidgets('במרכז צר הכותרת מתכווצת ואין overflow', (tester) async {
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());
      addTearDown(settingsBloc.close);

      await tester.pumpWidget(
        _buildHarness(
          settingsBloc: settingsBloc,
          child: SizedBox(
            width: 200,
            child: ReaderNavCenter(
              title: const Text(
                'כותרת ארוכה מאוד מאוד מאוד שלא נכנסת במקום צר',
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              prevMajorTooltip: 'פרק קודם',
              prevMinorTooltip: 'קטע קודם',
              nextMinorTooltip: 'קטע הבא',
              nextMajorTooltip: 'פרק הבא',
              onPrevMajor: () {},
              onPrevMinor: () {},
              onNextMinor: () {},
              onNextMajor: () {},
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('מיקום החיצים אינו תלוי באורך הכותרת (#1863)', (tester) async {
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());
      addTearDown(settingsBloc.close);

      Future<Offset> prevMinorFor(String title) async {
        await tester.pumpWidget(
          _buildHarness(
            settingsBloc: settingsBloc,
            child: SizedBox(
              width: 800,
              child: Center(
                child: ReaderNavCenter(
                  title: Text(title, textAlign: TextAlign.center),
                  prevMajorTooltip: 'פרק קודם',
                  prevMinorTooltip: 'קטע קודם',
                  nextMinorTooltip: 'קטע הבא',
                  nextMajorTooltip: 'פרק הבא',
                  onPrevMajor: () {},
                  onPrevMinor: () {},
                  onNextMinor: () {},
                  onNextMajor: () {},
                ),
              ),
            ),
          ),
        );
        return tester.getCenter(find.byTooltip('קטע קודם'));
      }

      final short = await prevMinorFor('הלכות גדולות');
      final long = await prevMinorFor('הלכות גדולות, הקדמה, סימן א');
      expect(long, short);
    });

    // q12 Q8, סקירה שלישית של 4.11: ארבעת החיצים קודמים לכותרת כל עוד הם
    // נכנסים; כשלא — כולם יוצאים, והכותרת מקבלת את כל המרכז.
    group('ההחלטה לפי הרוחב שנמדד', () {
      const titleKey = Key('title');
      const tooltips = ['פרק קודם', 'קטע קודם', 'קטע הבא', 'פרק הבא'];

      Future<ReaderNavPlacement> pumpAt(
        WidgetTester tester,
        double width,
      ) async {
        final settingsBloc = _TestSettingsBloc(SettingsState.initial());
        addTearDown(settingsBloc.close);
        final placement = ReaderNavPlacement();
        await tester.pumpWidget(
          _buildHarness(
            settingsBloc: settingsBloc,
            child: SizedBox(
              width: width,
              child: ReaderNavCenter(
                placement: placement,
                title: const Text(
                  'בראשית, פרק א',
                  key: titleKey,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                prevMajorTooltip: 'פרק קודם',
                prevMinorTooltip: 'קטע קודם',
                nextMinorTooltip: 'קטע הבא',
                nextMajorTooltip: 'פרק הבא',
                onPrevMajor: () {},
                onPrevMinor: () {},
                onNextMinor: () {},
                onNextMajor: () {},
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        return placement;
      }

      // מתחת ל-240 הכפתורים compact גם בצפיפות רגילה.
      final fourCompact = ReaderNavCenter.navButtonsWidth(compact: true);

      testWidgets('נכנסים בדיוק: ארבעתם בסרגל, והכותרת נדחית ל-0', (
        tester,
      ) async {
        final placement = await pumpAt(tester, fourCompact);
        for (final tooltip in tooltips) {
          expect(find.byTooltip(tooltip), findsOneWidget, reason: tooltip);
        }
        expect(placement.arrowsInBar, isTrue);
        expect(tester.getSize(find.byKey(titleKey)).width, 0);
      });

      testWidgets('נכנסים עם עודף: הכותרת מקבלת את מה שנשאר', (tester) async {
        final placement = await pumpAt(tester, fourCompact + 40);
        expect(find.byTooltip('פרק קודם'), findsOneWidget);
        expect(placement.arrowsInBar, isTrue);
        expect(tester.getSize(find.byKey(titleKey)).width, 40);
      });

      testWidgets('חסר פיקסל: אף חץ, והכותרת מקבלת את כל המרכז', (
        tester,
      ) async {
        final placement = await pumpAt(tester, fourCompact - 1);
        for (final tooltip in tooltips) {
          expect(find.byTooltip(tooltip), findsNothing, reason: tooltip);
        }
        expect(placement.arrowsInBar, isFalse);
        expect(tester.getSize(find.byKey(titleKey)).width, fourCompact - 1);
      });

      testWidgets('לעולם לא חלק מהחיצים (#891): ארבעה או אפס בכל רוחב', (
        tester,
      ) async {
        for (var width = 40.0; width <= 400; width += 8) {
          final placement = await pumpAt(tester, width);
          final shown = tooltips
              .where((t) => find.byTooltip(t).evaluate().isNotEmpty)
              .length;
          expect(shown, placement.arrowsInBar ? 4 : 0, reason: '$width');
          expect(
            placement.arrowsInBar,
            ReaderNavCenter.navFits(width, isCompact: false),
            reason: '$width',
          );
        }
      });
    });

    test('navFits: לפי רוחב הכפתורים האמיתי, בלי מספר קבוע', () {
      final compact = ReaderNavCenter.navButtonsWidth(compact: true);
      final regular = ReaderNavCenter.navButtonsWidth(compact: false);
      expect(
        compact,
        4 * BarButton.toolbarWidth(true) + 2 * ReaderNavCenter.navGap,
      );
      expect(
        regular,
        4 * BarButton.toolbarWidth(false) + 2 * ReaderNavCenter.navGap,
      );
      expect(ReaderNavCenter.navFits(compact, isCompact: true), isTrue);
      expect(ReaderNavCenter.navFits(compact - 1, isCompact: true), isFalse);
      // בצפיפות רגילה מרכז צר מ-240 עובר ל-compact, ולכן גם בו די ב-compact.
      expect(ReaderNavCenter.navFits(compact, isCompact: false), isTrue);
      expect(ReaderNavCenter.navFits(regular, isCompact: false), isTrue);
    });

    testWidgets('afterTitle בגודל טבעי כשיש מקום ומתכווץ במרכז צר בלי לגלוש', (
      tester,
    ) async {
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());
      addTearDown(settingsBloc.close);

      // רוחב 100 — גדול מ-PageNumberDisplay טיפוסי, כדי לא להניח רוחב מסוים.
      const afterTitleKey = Key('after-title');
      Widget harness(double width) => _buildHarness(
        settingsBloc: settingsBloc,
        child: SizedBox(
          width: width,
          child: ReaderNavCenter(
            title: const Text(
              'כותרת ארוכה מאוד מאוד מאוד שלא נכנסת במקום צר',
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            afterTitle: const SizedBox(
              key: afterTitleKey,
              width: 100,
              height: 20,
            ),
            prevMajorTooltip: 'פרק קודם',
            prevMinorTooltip: 'קטע קודם',
            nextMinorTooltip: 'קטע הבא',
            nextMajorTooltip: 'פרק הבא',
            onPrevMajor: () {},
            onPrevMinor: () {},
            onNextMinor: () {},
            onNextMajor: () {},
          ),
        ),
      );

      // ברוחב מספיק — גודל טבעי מלא.
      await tester.pumpWidget(harness(600));
      expect(tester.getSize(find.byType(FittedBox)).width, 100);
      expect(tester.takeException(), isNull);

      // במרכז צר (270px) — 4 כפתורים (44px כולל ריפוד = 176px) + 2 רווחים (8px)
      // → נשאר 86px < 100px. afterTitle מתכווץ ל-86px בלי לגלוש.
      await tester.pumpWidget(harness(270));
      expect(find.byKey(afterTitleKey), findsOneWidget);
      expect(
        tester.getSize(find.byType(FittedBox)).width,
        lessThanOrEqualTo(86),
      );
      expect(tester.takeException(), isNull);
    });

    // #1534: מעבר כותרת הוא שברון כפול, ותחילת/סוף הספר נשארים חץ עם פס.
    group('אייקוני הדף/פרק ב-RTL', () {
      Future<IconData?> majorGlyph(
        WidgetTester tester,
        String tooltip, {
        IconData? prevMajorIcon,
        IconData? nextMajorIcon,
      }) async {
        final settingsBloc = _TestSettingsBloc(SettingsState.initial());
        addTearDown(settingsBloc.close);
        final center = prevMajorIcon == null
            ? ReaderNavCenter(
                title: const Text('ספר'),
                prevMajorTooltip: 'קודם',
                prevMinorTooltip: 'קטע קודם',
                nextMinorTooltip: 'קטע הבא',
                nextMajorTooltip: 'הבא',
                onPrevMajor: () {},
                onPrevMinor: () {},
                onNextMinor: () {},
                onNextMajor: () {},
              )
            : ReaderNavCenter(
                title: const Text('ספר'),
                prevMajorTooltip: 'קודם',
                prevMinorTooltip: 'קטע קודם',
                nextMinorTooltip: 'קטע הבא',
                nextMajorTooltip: 'הבא',
                prevMajorIcon: prevMajorIcon,
                nextMajorIcon: nextMajorIcon!,
                onPrevMajor: () {},
                onPrevMinor: () {},
                onNextMinor: () {},
                onNextMajor: () {},
              );
        await tester.pumpWidget(
          _buildHarness(
            settingsBloc: settingsBloc,
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: SizedBox(width: 600, child: center),
            ),
          ),
        );
        return tester
            .widget<Icon>(
              find.descendant(
                of: find.byTooltip(tooltip),
                matching: find.byType(Icon),
              ),
            )
            .icon;
      }

      testWidgets('ברירת המחדל: שברון כפול שפונה החוצה כמו השברון הבודד', (
        tester,
      ) async {
        // לשברון הכפול אין matchTextDirection, ולכן הגליף המוצג הוא הנגדי.
        expect(
          await majorGlyph(tester, 'קודם'),
          FluentIcons.chevron_double_right_20_regular,
        );
        expect(
          await majorGlyph(tester, 'הבא'),
          FluentIcons.chevron_double_left_20_regular,
        );
      });

      testWidgets('אייקון שנמסר (תחילת/סוף הספר ב-PDF) מוצג כמו קודם', (
        tester,
      ) async {
        expect(
          await majorGlyph(
            tester,
            'קודם',
            prevMajorIcon: FluentIcons.arrow_previous_24_filled,
            nextMajorIcon: FluentIcons.arrow_next_24_filled,
          ),
          FluentIcons.arrow_previous_24_filled,
        );
      });
    });
  });
}

Widget _buildHarness({
  required SettingsBloc settingsBloc,
  required Widget child,
}) {
  return MaterialApp(
    home: Scaffold(
      body: BlocProvider<SettingsBloc>.value(
        value: settingsBloc,
        child: Center(child: child),
      ),
    ),
  );
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
