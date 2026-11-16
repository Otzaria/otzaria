import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/widgets/download_network_settings_tile.dart';
import 'package:otzaria/settings/widgets/settings_card.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/theme/app_theme_data.dart';

import '../../helpers/memory_settings_cache.dart';
import '../../support/golden_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadGoldenFonts();
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('fonts/Rubik-VariableFont_wght.ttf'))).load();
  });
  late SettingsRepository repository;
  late SettingsBloc bloc;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    repository = SettingsRepository();
    bloc = SettingsBloc(
      repository: repository,
      initialSettings: repository.readSettings(),
      ensureFontLoaded: (_) async {},
    );
  });
  tearDown(() async {
    await bloc.close();
    debugDefaultTargetPlatformOverride = null;
  });

  test('הגבלת הורדות נשמרת בלי לשנות מצב מנותק', () async {
    await repository.updateOfflineMode(true);
    bloc.add(UpdateDownloadsWifiOnly(true));
    await bloc.stream.firstWhere((state) => state.downloadsWifiOnly);
    expect(repository.readSettings()['downloadsWifiOnly'], isTrue);
    expect(repository.readSettings()['isOfflineMode'], isTrue);
    expect(
      SettingsRepository.allKeys,
      contains(SettingsRepository.keyDownloadsWifiOnly),
    );
    bloc.add(UpdateDownloadsWifiOnly(false));
    await bloc.stream.firstWhere((state) => !state.downloadsWifiOnly);
    expect(repository.readSettings()['downloadsWifiOnly'], isFalse);
    expect(repository.readSettings()['isOfflineMode'], isTrue);
  });

  Future<void> pump(
    WidgetTester tester,
    double width,
    Brightness brightness,
    bool white,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.physicalSize = Size(width, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final scheme = AppThemeData.createColorScheme(
      white
          ? AppSeedColors.white
          : brightness == Brightness.dark
          ? AppSeedColors.defaultDark
          : AppSeedColors.defaultLight,
      brightness,
    );
    final theme = brightness == Brightness.dark
        ? AppThemeData.dark(scheme, compactMenuMode: false)
        : AppThemeData.light(
            scheme,
            compactMenuMode: false,
            variant: white ? AppThemeVariant.white : AppThemeVariant.standard,
          );
    await tester.pumpWidget(
      BlocProvider.value(
        value: bloc,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('he', 'IL'),
          supportedLocales: const [Locale('he', 'IL')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.3)),
            child: child!,
          ),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: SettingsCard(
                title: 'עדכוני מערכת',
                children: [DownloadNetworkSettingsTile()],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final width in [360.0, 1100.0]) {
    for (final mode in ['light', 'dark', 'white']) {
      testWidgets('הגדרה אמיתית ב־RTL, $mode, רוחב $width וטקסט1.3', (
        tester,
      ) async {
        try {
          await pump(
            tester,
            width,
            mode == 'dark' ? Brightness.dark : Brightness.light,
            mode == 'white',
          );
          expect(
            Directionality.of(
              tester.element(find.byType(DownloadNetworkSettingsTile)),
            ),
            TextDirection.rtl,
          );
          expect(find.text('רשת להורדת קבצים'), findsOneWidget);
          expect(find.textContaining('גם מתוספים'), findsOneWidget);
          final enabled = bloc.stream.firstWhere(
            (state) => state.downloadsWifiOnly,
          );
          await tester.tap(find.text('WiFi בלבד'));
          await tester.runAsync(() => enabled);
          await tester.pumpAndSettle();
          expect(bloc.state.downloadsWifiOnly, isTrue);
          expect(tester.takeException(), isNull);
          final disabled = bloc.stream.firstWhere(
            (state) => !state.downloadsWifiOnly,
          );
          await tester.tap(find.text('כל רשת'));
          await tester.runAsync(() => disabled);
          await tester.pumpAndSettle();
          expect(bloc.state.downloadsWifiOnly, isFalse);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }
}
