// במסך ההגדרות המלא הספרים הפתוחים מוסתרים, וכל צעד של הסליידר בנה מחדש
// את כל הכרטיסיות. שם הערך מוחל בסוף הגרירה; בחלונית שמעל הספר — בכל צעד.

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/tabs/text_settings_tab.dart';

import '../test_helpers/memory_cache_provider.dart';

class MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    registerFallbackValue(const UpdateFontSize(0));
    registerFallbackValue(const UpdateTextMaxWidth(0));
  });

  late MockSettingsBloc settingsBloc;

  setUp(() {
    settingsBloc = MockSettingsBloc();
    whenListen(
      settingsBloc,
      const Stream<SettingsState>.empty(),
      initialState: SettingsState.initial(),
    );
  });

  final fontSizeSlider = find.byWidgetPredicate(
    (widget) => widget is Slider && widget.min == 15 && widget.max == 60,
  );

  Future<void> pumpTab(WidgetTester tester, {required bool isDialog}) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<SettingsBloc>.value(
          value: settingsBloc,
          child: Scaffold(
            body: PrimaryScrollController.none(
              child: TextSettingsTab(isDialog: isDialog),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(fontSizeSlider, findsOneWidget);
  }

  Future<TestGesture> dragInSteps(WidgetTester tester) async {
    final gesture = await tester.startGesture(
      tester.getCenter(fontSizeSlider),
    );
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(15, 0));
      await tester.pump();
    }
    return gesture;
  }

  List<double> sentFontSizes() => verify(
    () => settingsBloc.add(captureAny(that: isA<UpdateFontSize>())),
  ).captured.cast<UpdateFontSize>().map((e) => e.fontSize).toList();

  testWidgets('במסך ההגדרות המלא הגרירה מחילה את הגודל פעם אחת, בסוף', (
    tester,
  ) async {
    await pumpTab(tester, isDialog: false);

    final gesture = await dragInSteps(tester);
    verifyNever(() => settingsBloc.add(any(that: isA<UpdateFontSize>())));
    final shownWhileDragging = tester.widget<Slider>(fontSizeSlider).value;
    expect(shownWhileDragging, greaterThan(SettingsState.initial().fontSize));

    await gesture.up();
    await tester.pump();

    expect(sentFontSizes(), [shownWhileDragging]);
  });

  testWidgets('בחלונית שמעל הספר הגרירה מחילה את הגודל בכל צעד', (
    tester,
  ) async {
    await pumpTab(tester, isDialog: true);

    final gesture = await dragInSteps(tester);
    final shownWhileDragging = tester.widget<Slider>(fontSizeSlider).value;
    await gesture.up();
    await tester.pump();

    final sent = sentFontSizes();
    expect(sent.length, greaterThan(1));
    expect(sent.last, shownWhileDragging);
  });

  testWidgets('במסך ההגדרות המלא לחיצה בודדת על הסליידר מחילה את הגודל', (
    tester,
  ) async {
    await pumpTab(tester, isDialog: false);

    await tester.tapAt(
      tester.getCenter(fontSizeSlider) + const Offset(100, 0),
    );
    await tester.pump();

    expect(sentFontSizes(), [tester.widget<Slider>(fontSizeSlider).value]);
  });

  group('סליידר רוחב הטקסט', () {
    final widthSlider = find.byWidgetPredicate(
      (widget) => widget is Slider && widget.min == 10 && widget.max == 41,
    );

    Future<TestGesture> dragWidth(WidgetTester tester) async {
      final gesture = await tester.startGesture(tester.getCenter(widthSlider));
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(60, 0));
        await tester.pump();
      }
      return gesture;
    }

    List<double> sentWidths() => verify(
      () => settingsBloc.add(captureAny(that: isA<UpdateTextMaxWidth>())),
    ).captured.cast<UpdateTextMaxWidth>().map((e) => e.textMaxWidth).toList();

    testWidgets('במסך ההגדרות המלא הגרירה מחילה את הרוחב פעם אחת, בסוף', (
      tester,
    ) async {
      await pumpTab(tester, isDialog: false);

      final gesture = await dragWidth(tester);
      verifyNever(
        () => settingsBloc.add(any(that: isA<UpdateTextMaxWidth>())),
      );
      final shownStop = tester.widget<Slider>(widthSlider).value;
      expect(shownStop, lessThan(41), reason: 'הגרירה עברה לרוחב מוגבל');

      await gesture.up();
      await tester.pump();

      expect(sentWidths(), [closeTo(shownStop * 96 / 2.54, 1e-9)]);
    });

    testWidgets('בחלונית שמעל הספר הגרירה מחילה את הרוחב בכל צעד', (
      tester,
    ) async {
      await pumpTab(tester, isDialog: true);

      final gesture = await dragWidth(tester);
      await gesture.up();
      await tester.pump();

      expect(sentWidths().length, greaterThan(1));
    });

    testWidgets('במסך ההגדרות המלא לחיצה בודדת מחילה את הרוחב', (
      tester,
    ) async {
      await pumpTab(tester, isDialog: false);

      await tester.tapAt(tester.getCenter(widthSlider) + const Offset(100, 0));
      await tester.pump();

      final sent = sentWidths();
      expect(sent, hasLength(1));
      expect(sent.single, greaterThan(0));
    });
  });
}
