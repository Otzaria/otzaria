import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/migration/sync/file_sync_service.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/panels/custom_folders_panel.dart';
import 'package:otzaria/settings/services/custom_folders/bloc/custom_folders_bloc.dart';
import 'package:otzaria/settings/services/custom_folders/custom_folder.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/theme/app_theme_data.dart';

import '../../../helpers/memory_settings_cache.dart';

const _fileError = 'מגילה_links.json: ספר היעד "ספר חסר" לא נמצא';
const _scanError = 'שגיאות בסריקת התיקיות האישיות:\n$_fileError';
const _rootCaptureKey = ValueKey('custom-folders-scan-capture-root');

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in manifest.cast<Map<String, dynamic>>()) {
      final family = entry['family'] as String;
      if (family == 'Rubik' ||
          family.contains('FluentSystemIcons') ||
          family.contains('OtzariaIcons')) {
        final loader = FontLoader(family);
        for (final font in (entry['fonts'] as List).cast<Map>()) {
          loader.addFont(rootBundle.load(font['asset'] as String));
        }
        await loader.load();
      }
    }
  });

  testWidgets('סריקה מהגדרות הספרייה מציגה שגיאות קובץ הקישורים', (
    tester,
  ) async {
    const width = 1200.0;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(width, 900);
    final scan = Completer<FileSyncResult>();
    final bloc = CustomFoldersBloc(
      addLibraryEvent: (_) {},
      loadFolders: () => [
        CustomFolder(path: 'C:/personal-books', addedAt: DateTime(2026)),
      ],
      syncFolders: (_, {String? onlyFolderPath}) => scan.future,
      deleteFolderFromDb: (_) async {},
    )..add(const LoadCustomFolders());
    final capture = Platform.environment['OTZARIA_CAPTURE_UI'] == '1';
    final expectScanErrors =
        Platform.environment['OTZARIA_EXPECT_SCAN_ERRORS'] != '0';

    addTearDown(() async {
      UiSnack.hide();
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.reset();
      if (!scan.isCompleted) scan.complete(const FileSyncResult());
      await bloc.close();
    });

    final theme =
        AppThemeData.light(
          AppThemeData.createColorScheme(AppSeedColors.blue, Brightness.light),
          compactMenuMode: false,
          variant: AppThemeVariant.ofSeed(AppSeedColors.blue),
        ).copyWith(
          textTheme: ThemeData.light().textTheme.apply(fontFamily: 'Rubik'),
          primaryTextTheme: ThemeData.light().primaryTextTheme.apply(
            fontFamily: 'Rubik',
          ),
        );
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        locale: const Locale('he', 'IL'),
        supportedLocales: const [Locale('he', 'IL')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: theme,
        builder: (context, child) => RepaintBoundary(
          key: _rootCaptureKey,
          child: child!,
        ),
        home: Scaffold(
          body: BlocProvider.value(
            value: bloc,
            child: const SingleChildScrollView(child: CustomFoldersPanel()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      Directionality.of(tester.element(find.byType(CustomFoldersPanel))),
      TextDirection.rtl,
    );
    await tester.tap(find.text('הוסף תיקייה').first);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('סרוק מחדש תיקיות אישיות'));
    await tester.pump();
    expect(bloc.state.isSyncing, isTrue);
    scan.complete(const FileSyncResult(errors: [_fileError]));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.textContaining('מגילה_links.json'),
      expectScanErrors ? findsOneWidget : findsNothing,
    );
    expect(
      find.textContaining('ספר היעד "ספר חסר" לא נמצא'),
      expectScanErrors ? findsOneWidget : findsNothing,
    );
    expect(
      find.textContaining('הסריקה הושלמה. לא נמצאו ספרים חדשים.'),
      expectScanErrors ? findsNothing : findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    if (capture) {
      await expectLater(
        find.byKey(_rootCaptureKey),
        matchesGoldenFile('custom_folders_scan_error_after.png'),
      );
    }
    UiSnack.hide();
    await tester.pump();
  });

  for (final (themeName, seed, brightness) in [
    ('בהיר', AppSeedColors.blue, Brightness.light),
    ('כהה', AppSeedColors.blue, Brightness.dark),
    ('לבן', AppSeedColors.white, Brightness.light),
  ]) {
    for (final width in [360.0, 1200.0]) {
      testWidgets(
        'UiSnack: $themeName, רוחב $width, RTL, טקסט ×1.3 מציג קובץ וסיבה',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 900);
          addTearDown(() {
            tester.view.reset();
            UiSnack.hide();
          });

          final colorScheme = AppThemeData.createColorScheme(seed, brightness);
          final baseTheme = brightness == Brightness.light
              ? AppThemeData.light(
                  colorScheme,
                  compactMenuMode: false,
                  variant: AppThemeVariant.ofSeed(seed),
                )
              : AppThemeData.dark(
                  colorScheme,
                  compactMenuMode: false,
                  variant: AppThemeVariant.ofSeed(seed),
                );
          final theme = baseTheme.copyWith(
            textTheme: baseTheme.textTheme.apply(fontFamily: 'Rubik'),
            primaryTextTheme: baseTheme.primaryTextTheme.apply(
              fontFamily: 'Rubik',
            ),
          );
          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: navigatorKey,
              locale: const Locale('he', 'IL'),
              supportedLocales: const [Locale('he', 'IL')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              theme: theme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(1.3),
                ),
                child: child!,
              ),
              home: const Scaffold(body: SizedBox()),
            ),
          );
          UiSnack.showError(_scanError, duration: const Duration(seconds: 10));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));

          final message = find.textContaining('מגילה_links.json');
          expect(Directionality.of(tester.element(message)), TextDirection.rtl);
          expect(message, findsOneWidget);
          expect(
            find.textContaining('ספר היעד "ספר חסר" לא נמצא'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          UiSnack.hide();
          await tester.pump();
        },
      );
    }
  }
}
