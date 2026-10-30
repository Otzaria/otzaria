// סליידר "רוחב הטקסט" מציג ס"מ ושומר רוחב יעד בפיקסלים לוגיים (96 DPI), או 0
// לרוחב מלא בעצירה האחרונה.

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
    registerFallbackValue(const UpdateTextMaxWidth(0));
  });

  late MockSettingsBloc settingsBloc;

  setUp(() {
    settingsBloc = MockSettingsBloc();
  });

  Future<Slider> pumpAndFindWidthSlider(
    WidgetTester tester, {
    double textMaxWidth = 0,
  }) async {
    whenListen(
      settingsBloc,
      const Stream<SettingsState>.empty(),
      initialState: SettingsState.initial().copyWith(
        textMaxWidth: textMaxWidth,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<SettingsBloc>.value(
          value: settingsBloc,
          child: const Scaffold(
            body: PrimaryScrollController.none(child: TextSettingsTab()),
          ),
        ),
      ),
    );
    await tester.pump();

    // סליידר רוחב הטקסט: 10–40 ס"מ ועצירה אחרונה לרוחב מלא
    final finder = find.byWidgetPredicate(
      (widget) => widget is Slider && widget.min == 10 && widget.max == 41,
    );
    expect(finder, findsOneWidget);
    return tester.widget<Slider>(finder);
  }

  const pxPerCm = 96 / 2.54;

  testWidgets('עצירת ס"מ שולחת פיקסלים לוגיים', (tester) async {
    final slider = await pumpAndFindWidthSlider(tester);
    (slider.onChangeEnd ?? slider.onChanged)!(25);

    verify(
      () => settingsBloc.add(const UpdateTextMaxWidth(25 * pxPerCm)),
    ).called(1);
  });

  testWidgets('העצירה האחרונה (רוחב מלא) שולחת 0', (tester) async {
    final slider = await pumpAndFindWidthSlider(tester);
    (slider.onChangeEnd ?? slider.onChanged)!(41);

    verify(() => settingsBloc.add(const UpdateTextMaxWidth(0))).called(1);
  });

  testWidgets('רוחב שמור מוצג בס"מ', (tester) async {
    final slider = await pumpAndFindWidthSlider(
      tester,
      textMaxWidth: 25 * pxPerCm,
    );
    expect(slider.value, 25);
    expect(slider.label, '25 ס"מ');
  });

  testWidgets('רמת אחוזים ישנה (שלילית) מוצגת כ"מלא"', (tester) async {
    final slider = await pumpAndFindWidthSlider(tester, textMaxWidth: -3);
    expect(slider.value, 41);
    expect(slider.label, 'מלא');
  });

  for (final boundary in [(5, 10), (50, 40)]) {
    testWidgets('רוחב ${boundary.$1} ס"מ נתחם ל-${boundary.$2} ונשמר', (
      tester,
    ) async {
      final slider = await pumpAndFindWidthSlider(
        tester,
        textMaxWidth: boundary.$1 * pxPerCm,
      );
      expect(slider.value, boundary.$2);
      expect(slider.label, '${boundary.$2} ס"מ');
      (slider.onChangeEnd ?? slider.onChanged)!(slider.value);
      verify(
        () => settingsBloc.add(UpdateTextMaxWidth(boundary.$2 * pxPerCm)),
      ).called(1);
    });
  }
}
