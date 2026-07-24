// רגרסיה: ColorPickerTile במצב מערכת (followSystemTheme=true) חייב להשתמש
// בבהירות האמיתית של הפלטפורמה (MediaQuery.platformBrightness) ולא ב-isDarkMode
// השמור. לפני התיקון, המעבר ממצב ידני למצב מערכת שמר את isDarkMode הישן,
// ושינוי הצבע השפיע על הנושא הלא-נכון — השינוי לא היה גלוי.

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/tabs/design_settings_tab.dart';
import 'package:otzaria/theme/app_seed_colors.dart';

import '../test_helpers/memory_cache_provider.dart';

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    registerFallbackValue(const UpdateSeedColor(AppSeedColors.blue));
  });

  // שני צבעים שונים עם שמות עבריים מובחנים כדי לאמת איזה מוצג
  const lightSeed = AppSeedColors.blue; // 'כחול'
  const darkSeed = AppSeedColors.teal; // 'טורקיז'

  Widget buildTab({
    required _MockSettingsBloc bloc,
    Brightness brightness = Brightness.light,
  }) {
    final state = bloc.state;
    final effectiveDark = state.followSystemTheme
        ? brightness == Brightness.dark
        : state.isDarkMode;
    return MaterialApp(
      theme: ThemeData(brightness: Brightness.light),
      darkTheme: ThemeData(brightness: Brightness.dark),
      themeMode: effectiveDark ? ThemeMode.dark : ThemeMode.light,
      home: Scaffold(
        body: BlocProvider<SettingsBloc>.value(
          value: bloc,
          child: const DesignSettingsTab(),
        ),
      ),
    );
  }

  _MockSettingsBloc makeBloc(SettingsState state) {
    final bloc = _MockSettingsBloc();
    whenListen(bloc, const Stream<SettingsState>.empty(), initialState: state);
    return bloc;
  }

  group('ColorPickerTile — מצב ידני (followSystemTheme=false)', () {
    testWidgets('מצב בהיר: מציג שם הצבע הבהיר', (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final state = SettingsState.initial().copyWith(
        isDarkMode: false,
        followSystemTheme: false,
        seedColor: lightSeed,
        darkSeedColor: darkSeed,
      );
      await tester.pumpWidget(buildTab(bloc: makeBloc(state)));
      await tester.pump();

      expect(find.text('כחול'), findsOneWidget);
      expect(find.text('טורקיז'), findsNothing);
    });

    testWidgets('מצב כהה: מציג שם הצבע הכהה', (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final state = SettingsState.initial().copyWith(
        isDarkMode: true,
        followSystemTheme: false,
        seedColor: lightSeed,
        darkSeedColor: darkSeed,
      );
      await tester.pumpWidget(buildTab(bloc: makeBloc(state)));
      await tester.pump();

      expect(find.text('טורקיז'), findsOneWidget);
      expect(find.text('כחול'), findsNothing);
    });
  });

  group('ColorPickerTile — מצב מערכת (followSystemTheme=true)', () {
    testWidgets(
      'מערכת כהה + isDarkMode=false שמור: מציג צבע כהה (רגרסיה)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        // isDarkMode=false הוא ה"עדפה השמורה" הישנה (היה במצב בהיר ועבר למצב מערכת)
        final state = SettingsState.initial().copyWith(
          isDarkMode: false,
          followSystemTheme: true,
          seedColor: lightSeed,
          darkSeedColor: darkSeed,
        );
        await tester.pumpWidget(
          buildTab(
            bloc: makeBloc(state),
            brightness: Brightness.dark,
          ),
        );
        await tester.pump();

        // המערכת כהה → חייב להציג צבע כהה, לא בהיר
        expect(find.text('טורקיז'), findsOneWidget);
        expect(find.text('כחול'), findsNothing);
      },
    );

    testWidgets(
      'מערכת בהירה + isDarkMode=true שמור: מציג צבע בהיר (רגרסיה)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        // isDarkMode=true הוא ה"עדפה השמורה" הישנה (היה במצב כהה ועבר למצב מערכת)
        final state = SettingsState.initial().copyWith(
          isDarkMode: true,
          followSystemTheme: true,
          seedColor: lightSeed,
          darkSeedColor: darkSeed,
        );
        await tester.pumpWidget(
          buildTab(
            bloc: makeBloc(state),
            brightness: Brightness.light,
          ),
        );
        await tester.pump();

        // המערכת בהירה → חייב להציג צבע בהיר, לא כהה
        expect(find.text('כחול'), findsOneWidget);
        expect(find.text('טורקיז'), findsNothing);
      },
    );
  });

  group('ColorPickerTile — שליחת אירוע לפי בהירות מערכת אמיתית', () {
    testWidgets(
      'מערכת כהה + followSystemTheme=true: שינוי צבע שולח UpdateDarkSeedColor',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final state = SettingsState.initial().copyWith(
          isDarkMode: false, // ה"עדפה השמורה" בהירה
          followSystemTheme: true,
          seedColor: lightSeed,
          darkSeedColor: darkSeed,
        );
        final bloc = makeBloc(state);
        await tester.pumpWidget(
          buildTab(
            bloc: bloc,
            brightness: Brightness.dark,
          ),
        );
        await tester.pump();

        await tester.tap(find.text('שינוי צבע'));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('אדום'));
        await tester.pump();

        verify(
          () => bloc.add(const UpdateDarkSeedColor(AppSeedColors.red)),
        ).called(1);
        verifyNever(() => bloc.add(const UpdateSeedColor(AppSeedColors.red)));
      },
    );

    testWidgets(
      'מערכת בהירה + followSystemTheme=true: שינוי צבע שולח UpdateSeedColor',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final state = SettingsState.initial().copyWith(
          isDarkMode: true, // ה"עדפה השמורה" כהה
          followSystemTheme: true,
          seedColor: lightSeed,
          darkSeedColor: darkSeed,
        );
        final bloc = makeBloc(state);
        await tester.pumpWidget(
          buildTab(
            bloc: bloc,
            brightness: Brightness.light,
          ),
        );
        await tester.pump();

        await tester.tap(find.text('שינוי צבע'));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('אדום'));
        await tester.pump();

        verify(
          () => bloc.add(const UpdateSeedColor(AppSeedColors.red)),
        ).called(1);
        verifyNever(
          () => bloc.add(const UpdateDarkSeedColor(AppSeedColors.red)),
        );
      },
    );
  });
}
