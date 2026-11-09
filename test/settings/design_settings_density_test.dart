// "צפיפות ממשק" בהגדרות (DD-15): שלושה מקטעים, "רגיל | אוטומטי | מצומצם".
// "אוטומטי" הוא בלי בחירה שמורה, והצפיפות לפי גודל החלון; בטלפון היא
// מצומצמת. הבורר מוצג גם בטלפון, כדי שאפשר יהיה לבחור "רגיל".

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:otzaria/core/windowing/device_chrome.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/l10n/settings_language.dart';
import 'package:otzaria/settings/l10n/settings_text_scope.dart';
import 'package:otzaria/settings/tabs/design_settings_tab.dart';
import 'package:otzaria/widgets/controls/segmented_control.dart';

import '../test_helpers/memory_cache_provider.dart';

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

const _autoCompact = 'כרגע מצומצם, לפי גודל החלון';
const _autoRegular = 'כרגע רגיל, לפי גודל החלון';
const _compactHint = 'הצג יותר תוכן על ידי הקטנת המרווחים';

void main() {
  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });
  setUpAll(() {
    registerFallbackValue(const UpdateCompactMenuMode(false));
  });

  void setWindow(WidgetTester tester, Size size, {required bool mobile}) {
    DeviceChrome.debugMobileOverride = mobile;
    addTearDown(() => DeviceChrome.debugMobileOverride = null);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpWith(
    WidgetTester tester,
    SettingsBloc bloc, {
    SettingsLanguage language = SettingsLanguage.hebrew,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: SettingsTextScope(
            language: language,
            child: Scaffold(
              body: BlocProvider<SettingsBloc>.value(
                value: bloc,
                child: const DesignSettingsTab(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<_MockSettingsBloc> pumpTab(
    WidgetTester tester, {
    required bool mobile,
    required Size size,
    SettingsState? state,
    SettingsLanguage language = SettingsLanguage.hebrew,
  }) async {
    setWindow(tester, size, mobile: mobile);
    final bloc = _MockSettingsBloc();
    whenListen(
      bloc,
      const Stream<SettingsState>.empty(),
      initialState: state ?? SettingsState.initial(),
    );
    await pumpWith(tester, bloc, language: language);
    return bloc;
  }

  Finder densityControl() => find.byType(AppSegmentedControl<bool?>);

  AppSegmentedControl<bool?> control(WidgetTester tester) =>
      tester.widget<AppSegmentedControl<bool?>>(densityControl());

  Future<Finder> segment(WidgetTester tester, String label) async {
    final finder = find.descendant(
      of: densityControl(),
      matching: find.text(label),
    );
    await tester.ensureVisible(finder);
    await tester.pump();
    return finder;
  }

  testWidgets('שלושה מקטעים: רגיל | אוטומטי | מצומצם, "אוטומטי" באמצע', (
    tester,
  ) async {
    await pumpTab(tester, mobile: false, size: const Size(900, 900));
    expect(control(tester).options.map((o) => o.value), [false, null, true]);
    final regular = await segment(tester, 'רגיל');
    final auto = await segment(tester, 'אוטומטי');
    final compact = await segment(tester, 'מצומצם');
    // RTL: הראשון מימין, כמו "בהיר | מערכת | כהה".
    expect(
      tester.getCenter(regular).dx,
      greaterThan(tester.getCenter(auto).dx),
    );
    expect(
      tester.getCenter(auto).dx,
      greaterThan(tester.getCenter(compact).dx),
    );
  });

  testWidgets('טלפון 360×640 בלי בחירה: "אוטומטי" מסומן, וכרגע מצומצם', (
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
    expect(control(tester).currentValue, isNull);
    expect(find.text(_autoCompact), findsOneWidget);
    // "מיקום הכרטיסיות" נשאר רק במחשב.
    expect(find.text('מיקום הכרטיסיות'), findsNothing);

    await tester.tap(await segment(tester, 'רגיל'));
    await tester.pump();
    expect(verify(() => bloc.add(captureAny())).captured, [
      const UpdateCompactMenuMode(false),
    ]);
  });

  testWidgets('מחשב בלי בחירה: "אוטומטי", כרגע רגיל, ושני הבוררים מוצגים', (
    tester,
  ) async {
    await pumpTab(tester, mobile: false, size: const Size(900, 900));
    expect(find.text('צפיפות ממשק'), findsOneWidget);
    expect(find.text('מיקום הכרטיסיות'), findsOneWidget);
    expect(control(tester).currentValue, isNull);
    expect(find.text(_autoRegular), findsOneWidget);
  });

  testWidgets('בחירה מפורשת: מסומנת עם ההסבר שלה, ו"אוטומטי" מוחק אותה', (
    tester,
  ) async {
    final bloc = await pumpTab(
      tester,
      mobile: true,
      size: const Size(360, 640),
      state: SettingsState.initial().copyWith(
        compactMenuMode: true,
        compactMenuModeIsSet: true,
      ),
    );
    expect(control(tester).currentValue, isTrue);
    expect(find.text(_compactHint), findsOneWidget);
    expect(find.text(_autoCompact), findsNothing);

    // המקטע המסומן שקט, כמו בכל בורר.
    await tester.tap(await segment(tester, 'מצומצם'));
    await tester.pump();
    verifyNever(() => bloc.add(any()));

    await tester.tap(await segment(tester, 'אוטומטי'));
    await tester.pump();
    expect(verify(() => bloc.add(captureAny())).captured, [
      const UpdateCompactMenuMode(null),
    ]);
  });

  testWidgets('באנגלית: Normal | Automatic | Compact', (tester) async {
    await pumpTab(
      tester,
      mobile: true,
      size: const Size(360, 640),
      language: SettingsLanguage.english,
    );
    await tester.ensureVisible(find.text('Toolbar Density'));
    await tester.pump();
    expect(
      control(tester).options.map((o) => o.label),
      ['Normal', 'Automatic', 'Compact'],
    );
    expect(find.text('Currently Compact, by window size'), findsOneWidget);
  });

  group('עם SettingsBloc ומאגר אמיתיים', () {
    Future<SettingsBloc> realBloc(WidgetTester tester) async {
      final repository = SettingsRepository();
      final bloc = SettingsBloc(
        repository: repository,
        initialSettings: repository.readSettings(),
      );
      addTearDown(bloc.close);
      await pumpWith(tester, bloc);
      return bloc;
    }

    bool? stored() =>
        SettingsRepository().readSettings()['compactMenuMode'] as bool?;

    testWidgets('"אוטומטי" מוחק את המפתח, והצפיפות שוב לפי החלון', (
      tester,
    ) async {
      // ערך שנשמר בגרסה קודמת נטען כבחירה מפורשת.
      await Settings.setValue<bool>(
        SettingsRepository.keyCompactMenuMode,
        false,
      );
      setWindow(tester, const Size(360, 640), mobile: true);
      final bloc = await realBloc(tester);
      expect(control(tester).currentValue, isFalse);

      await tester.tap(await segment(tester, 'אוטומטי'));
      await tester.pumpAndSettle();
      expect(
        Settings.containsKey(SettingsRepository.keyCompactMenuMode),
        isFalse,
      );
      expect(stored(), isNull);
      expect(bloc.state.compactMenuModeIsSet, isFalse);
      expect(control(tester).currentValue, isNull);
      // טלפון: מצומצם.
      expect(bloc.state.compactMenuModeFor(isSmallWindow: true), isTrue);
      expect(find.text(_autoCompact), findsOneWidget);

      // החלון גדל לטאבלט: אותה הגדרה, עכשיו רגיל.
      tester.view.physicalSize = const Size(800, 1280);
      await tester.pumpAndSettle();
      expect(find.text(_autoRegular), findsOneWidget);
      expect(control(tester).currentValue, isNull);
    });

    testWidgets('"רגיל" ו"מצומצם" נשמרים במפתח', (tester) async {
      setWindow(tester, const Size(360, 640), mobile: true);
      final bloc = await realBloc(tester);
      expect(stored(), isNull);

      await tester.tap(await segment(tester, 'רגיל'));
      await tester.pumpAndSettle();
      expect(stored(), isFalse);
      expect(bloc.state.compactMenuModeIsSet, isTrue);
      expect(bloc.state.compactMenuModeFor(isSmallWindow: true), isFalse);
      expect(control(tester).currentValue, isFalse);

      await tester.tap(await segment(tester, 'מצומצם'));
      await tester.pumpAndSettle();
      expect(stored(), isTrue);
      expect(control(tester).currentValue, isTrue);
    });
  });
}
