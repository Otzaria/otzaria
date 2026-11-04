// מסכים קטנים (q12 Q8, "מאמץ סביר"): המסכים העיקריים בחלון הראשי האמיתי,
// בטלפון לאורך (320×568), בטלפון לרוחב (640×360) ובמחשב 10" (1024×600), בלי
// גלישת RenderFlex ובלי חריגה אחרת. "צפיפות ממשק" נבחרה במפורש כ"רגיל", המצב
// הצפוף ביותר: הבחירה נשמרת גם בחלון קטן ונמוך.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/navigation/view/main_window_screen.dart';
import 'package:otzaria/plugins/services/plugin_search_dialog_registry.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tools/tools_launcher_controller.dart';
import 'package:otzaria/tools/view/tools_launcher_panel.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';

import '../../helpers/memory_settings_cache.dart';
import '../../support/golden_fonts.dart';
import 'small_screens_fixture.dart';

const _sizes = {
  'טלפון לאורך 320×568': Size(320, 568),
  'טלפון לרוחב 640×360': Size(640, 360),
  'מחשב 10" 1024×600': Size(1024, 600),
};

Future<void> _loadFonts() async {
  await loadGoldenFonts();
  // הפלטפורמה בבדיקה היא Android, וערכת הנושא מבקשת Roboto: אותו גופן ממשק.
  final roboto = FontLoader('Roboto')
    ..addFont(rootBundle.load('fonts/Rubik-VariableFont_wght.ttf'));
  await roboto.load();
}

Future<void> _pump(WidgetTester tester, SmallScreen screen, Size size) async {
  await Settings.init(cacheProvider: MemorySettingsCache());
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final wrap = smallScreenProviders(
    tester,
    screen: screen,
    size: size,
    compactMenuMode: false,
  );
  final cs = AppThemeData.createColorScheme(
    AppSeedColors.defaultLight,
    Brightness.light,
  );
  await tester.pumpWidget(
    wrap(
      MaterialApp(
        localizationsDelegates: const [
          GlobalCupertinoLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: const [Locale('he', 'IL')],
        locale: const Locale('he', 'IL'),
        theme: AppThemeData.light(cs, compactMenuMode: false),
        home: const MainWindowScreen(),
      ),
    ),
  );
  await _settle(tester);
}

/// פריימים קצובים ולא pumpAndSettle: יש במסכים אנימציות שלא נגמרות.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(_loadFonts);

  for (final MapEntry(key: name, value: size) in _sizes.entries) {
    group(name, () {
      for (final screen in [
        SmallScreen.home,
        SmallScreen.reader,
        SmallScreen.search,
        SmallScreen.settings,
      ]) {
        testWidgets('${screen.name}: בלי גלישה', (tester) async {
          await _pump(tester, screen, size);
          expect(tester.takeException(), isNull);
          expect(find.byType(MainWindowScreen), findsOneWidget);
          final topBar = find.byType(AppTopBar);
          if (topBar.evaluate().isNotEmpty) {
            expect(
              AppDensity.of(tester.element(topBar.first)).isCompact,
              isFalse,
              reason: '"רגיל" מפורש נשמר גם בחלון נמוך',
            );
          }
        });
      }

      testWidgets('לוח הכלים: בלי גלישה', (tester) async {
        await _pump(tester, SmallScreen.home, size);
        ToolsLauncherController.instance.open();
        await _settle(tester);
        expect(tester.takeException(), isNull);
        expect(find.byType(ToolsLauncherPanel), findsOneWidget);
      });

      testWidgets('דיאלוג גדול (חיפוש): בלי גלישה', (tester) async {
        await _pump(tester, SmallScreen.home, size);
        final registry = PluginSearchDialogRegistry.forTesting();
        addTearDown(registry.dispose);
        showDialog<void>(
          context: tester.element(find.byType(MainWindowScreen)),
          builder: (_) => SearchDialog(
            initialSearchMode: SearchMode.exact,
            pluginSearchDialogRegistry: registry,
          ),
        );
        await _settle(tester);
        expect(tester.takeException(), isNull);
        expect(find.byType(SearchDialog), findsOneWidget);
      });
    });
  }
}
