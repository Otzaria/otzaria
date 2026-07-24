import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/settings_exports.dart';
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
