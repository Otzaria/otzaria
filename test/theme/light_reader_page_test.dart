// דף הספר בהיר גם במצב כהה (issue #2435): בממשק כהה עם ההגדרה דולקת, דף
// הספר (טקסט, מפרשים, PDF) בתמת הבהיר, והסרגלים והחלוניות שסביבו כהים.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/utils/pdf_color_filter.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/tabs/design_settings_tab.dart';
import 'package:otzaria/settings/widgets/settings_card.dart';
import 'package:otzaria/theme/theme_exports.dart';

import '../test_helpers/memory_cache_provider.dart';

final _light = AppThemeData.light(
  AppThemeData.createColorScheme(AppSeedColors.defaultLight, Brightness.light),
  compactMenuMode: false,
);
final _dark = AppThemeData.dark(
  AppThemeData.createColorScheme(AppSeedColors.defaultDark, Brightness.dark),
  compactMenuMode: false,
);

const _pageKey = Key('page');
const _chromeKey = Key('chrome');

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int count = 0;

  @override
  Widget build(BuildContext context) => Text('$count', key: _pageKey);
}

Widget _app({required ThemeMode mode, required bool lightPage}) {
  return MaterialApp(
    theme: _light,
    darkTheme: _dark,
    themeMode: mode,
    builder: (context, child) =>
        ReaderPageTheme(light: lightPage ? _light : null, child: child!),
    home: ReaderSurfaceScope(
      child: Scaffold(
        body: Column(
          children: [
            const Text('סרגל', key: _chromeKey),
            const Expanded(child: ReaderPageScope(child: _Counter())),
          ],
        ),
      ),
    ),
  );
}

Color? _pageBackground(WidgetTester tester) => tester
    .widget<ColoredBox>(
      find
          .ancestor(of: find.byKey(_pageKey), matching: find.byType(ColoredBox))
          .first,
    )
    .color;

void main() {
  group('light page in dark UI (issue #2435)', () {
    testWidgets('כהה + דולק: הדף בבהיר, הסרגל נשאר כהה', (tester) async {
      await tester.pumpWidget(_app(mode: ThemeMode.dark, lightPage: true));

      final page = tester.element(find.byKey(_pageKey));
      final chrome = tester.element(find.byKey(_chromeKey));
      expect(Theme.of(page).brightness, Brightness.light);
      expect(Theme.of(chrome).brightness, Brightness.dark);
      expect(
        _pageBackground(tester),
        _light.extension<AppSurfaceColors>()!.readerBackground,
      );
      // צבע הטקסט, הקישורים והבחירה מתמת הבהיר.
      expect(
        DefaultTextStyle.of(page).style.color,
        _light.textTheme.bodyMedium!.color,
      );
      expect(
        AppSurfaces.readerLink(Theme.of(page).colorScheme),
        AppSurfaces.readerLink(_light.colorScheme),
      );
      // ה-Scaffold-ים בתוך הדף מקבלים את רקע הקריאה הבהיר.
      expect(
        Theme.of(page).scaffoldBackgroundColor,
        _light.extension<AppSurfaceColors>()!.readerBackground,
      );
      // PDF: בלי היפוך צבעים ועל נייר לבן.
      expect(pdfPageColorFilter(ReaderPageTheme.of(chrome).brightness), isNull);
      expect(
        pdfPageColor(ReaderPageTheme.of(chrome).brightness),
        AppColors.pageWhite,
      );
    });

    testWidgets('כהה + כבוי: הדף כהה כמו קודם', (tester) async {
      await tester.pumpWidget(_app(mode: ThemeMode.dark, lightPage: false));

      final page = tester.element(find.byKey(_pageKey));
      expect(Theme.of(page).brightness, Brightness.dark);
      expect(_pageBackground(tester), Colors.transparent);
      expect(
        pdfPageColorFilter(ReaderPageTheme.of(page).brightness),
        pdfInvertColors,
      );
    });

    testWidgets('בהיר + דולק: אין שינוי', (tester) async {
      await tester.pumpWidget(_app(mode: ThemeMode.light, lightPage: true));

      final page = tester.element(find.byKey(_pageKey));
      expect(Theme.of(page).brightness, Brightness.light);
      expect(_pageBackground(tester), Colors.transparent);
    });

    testWidgets('החלפת ההגדרה חלה מיד ושומרת את מצב הקורא', (tester) async {
      await tester.pumpWidget(_app(mode: ThemeMode.dark, lightPage: false));
      tester.state<_CounterState>(find.byType(_Counter)).count = 7;

      await tester.pumpWidget(_app(mode: ThemeMode.dark, lightPage: true));
      await tester.pumpAndSettle();

      final page = tester.element(find.byKey(_pageKey));
      expect(Theme.of(page).brightness, Brightness.light);
      expect(tester.state<_CounterState>(find.byType(_Counter)).count, 7);
    });
  });

  group('הגדרת "דף הספר בהיר גם במצב כהה"', () {
    setUpAll(() async {
      await Settings.init(cacheProvider: MemoryCacheProvider());
    });

    test('נשמרת ונטענת מחדש', () async {
      final repository = SettingsRepository();
      final bloc = SettingsBloc(repository: repository);
      expect(bloc.state.lightReaderPageInDarkMode, isFalse);

      bloc.add(const UpdateLightReaderPageInDarkMode(true));
      await bloc.stream.firstWhere((s) => s.lightReaderPageInDarkMode);
      await bloc.close();

      final reloaded = SettingsBloc(
        repository: repository,
        initialSettings: repository.readSettings(),
      );
      expect(reloaded.state.lightReaderPageInDarkMode, isTrue);
      await reloaded.close();
    });

    Future<SettingsBloc> pumpTab(WidgetTester tester, ThemeData theme) async {
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final bloc = SettingsBloc(repository: SettingsRepository());
      addTearDown(bloc.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
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

    Finder tile() => find.ancestor(
      of: find.text('דף הספר בהיר גם במצב כהה'),
      matching: find.byType(SettingsSwitchTile),
    );

    testWidgets('במצב כהה המתג פעיל ומעדכן את ההגדרה', (tester) async {
      final bloc = await pumpTab(tester, _dark);
      expect(tester.widget<SettingsSwitchTile>(tile()).enabled, isTrue);

      await tester.ensureVisible(tile());
      await tester.tap(tile());
      await tester.pump();
      await tester.pump();

      expect(bloc.state.lightReaderPageInDarkMode, isTrue);
    });

    testWidgets('במצב בהיר המתג מושבת', (tester) async {
      await pumpTab(tester, _light);
      expect(tester.widget<SettingsSwitchTile>(tile()).enabled, isFalse);
    });
  });
}
