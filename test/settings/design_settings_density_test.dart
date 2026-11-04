// "צפיפות ממשק" בהגדרות (DD-15): בטלפון היא מצומצמת כברירת מחדל, ולכן הבורר
// מוצג גם שם, כדי שאפשר יהיה לבחור "רגיל".

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:otzaria/core/windowing/device_chrome.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/tabs/design_settings_tab.dart';
import 'package:otzaria/widgets/controls/segmented_control.dart';

import '../test_helpers/memory_cache_provider.dart';

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    registerFallbackValue(const UpdateCompactMenuMode(false));
  });

  Future<_MockSettingsBloc> pumpTab(
    WidgetTester tester, {
    required bool mobile,
    required Size size,
    SettingsState? state,
  }) async {
    DeviceChrome.debugMobileOverride = mobile;
    addTearDown(() => DeviceChrome.debugMobileOverride = null);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final bloc = _MockSettingsBloc();
    whenListen(
      bloc,
      const Stream<SettingsState>.empty(),
      initialState: state ?? SettingsState.initial(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<SettingsBloc>.value(
            value: bloc,
            child: const DesignSettingsTab(),
          ),
        ),
      ),
    );
    await tester.pump();
    return bloc;
  }

  Finder densityControl() => find.ancestor(
    of: find.text('מצומצם'),
    matching: find.byType(AppSegmentedControl<bool>),
  );

  bool selectedValue(WidgetTester tester) =>
      tester.widget<AppSegmentedControl<bool>>(densityControl()).currentValue;

  testWidgets('טלפון 360×640: "צפיפות ממשק" מוצגת, ואפשר לבחור "רגיל"', (
    tester,
  ) async {
    final bloc = await pumpTab(
      tester,
      mobile: true,
      size: const Size(360, 640),
    );

    final tile = find.text('צפיפות ממשק');
    await tester.ensureVisible(tile);
    expect(tile, findsOneWidget);
    // בלי בחירה, בטלפון: מצומצם.
    expect(selectedValue(tester), isTrue);
    // "מיקום הכרטיסיות" נשאר רק במחשב.
    expect(find.text('מיקום הכרטיסיות'), findsNothing);

    final regular = find.descendant(
      of: densityControl(),
      matching: find.text('רגיל'),
    );
    await tester.ensureVisible(regular);
    await tester.pump();
    await tester.tap(regular);
    await tester.pump();
    expect(verify(() => bloc.add(captureAny())).captured, [
      const UpdateCompactMenuMode(false),
    ]);
  });

  testWidgets('מחשב: "צפיפות ממשק" ו"מיקום הכרטיסיות" מוצגים', (tester) async {
    await pumpTab(tester, mobile: false, size: const Size(900, 900));
    expect(find.text('צפיפות ממשק'), findsOneWidget);
    expect(find.text('מיקום הכרטיסיות'), findsOneWidget);
  });

  group('בחירה אוטומטית', () {
    Future<Finder> segment(WidgetTester tester, String label) async {
      final finder = find.descendant(
        of: densityControl(),
        matching: find.text(label),
      );
      await tester.ensureVisible(finder);
      await tester.pump();
      return finder;
    }

    testWidgets('בלי בחירה: "אוטומטי", ולחיצה על המקטע המסומן קובעת אותו', (
      tester,
    ) async {
      final bloc = await pumpTab(
        tester,
        mobile: true,
        size: const Size(360, 640),
      );
      expect(find.text('אוטומטי, לפי גודל החלון'), findsOneWidget);
      expect(selectedValue(tester), isTrue);

      await tester.tap(await segment(tester, 'מצומצם'));
      await tester.pump();
      expect(verify(() => bloc.add(captureAny())).captured, [
        const UpdateCompactMenuMode(true),
      ]);
    });

    testWidgets('במחשב בלי בחירה אפשר לקבוע את "רגיל" המסומן', (tester) async {
      final bloc = await pumpTab(
        tester,
        mobile: false,
        size: const Size(900, 900),
      );
      expect(selectedValue(tester), isFalse);

      await tester.tap(await segment(tester, 'רגיל'));
      await tester.pump();
      expect(verify(() => bloc.add(captureAny())).captured, [
        const UpdateCompactMenuMode(false),
      ]);
    });

    testWidgets('אחרי בחירה: בלי "אוטומטי", והמקטע המסומן שקט', (tester) async {
      final bloc = await pumpTab(
        tester,
        mobile: true,
        size: const Size(360, 640),
        state: SettingsState.initial().copyWith(
          compactMenuMode: true,
          compactMenuModeIsSet: true,
        ),
      );
      expect(find.text('אוטומטי, לפי גודל החלון'), findsNothing);
      expect(find.text('הצג יותר תוכן על ידי הקטנת המרווחים'), findsOneWidget);

      await tester.tap(await segment(tester, 'מצומצם'));
      await tester.pump();
      verifyNever(() => bloc.add(any()));
    });
  });
}
