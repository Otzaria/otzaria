// הספרייה במסכים קטנים (q12 Q8, ss5): בחלון נמוך (טלפון לרוחב) התצוגה
// המקדימה סגורה עד שהמשתמש פותח אותה. במחשב היא פתוחה כמו קודם.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/navigation/view/main_window_screen.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/theme/theme_exports.dart';

import '../../helpers/memory_settings_cache.dart';
import '../../support/golden_fonts.dart';
import 'small_screens_fixture.dart';

Future<void> _loadFonts() async {
  await loadGoldenFonts();
  final roboto = FontLoader('Roboto')
    ..addFont(rootBundle.load('fonts/Rubik-VariableFont_wght.ttf'));
  await roboto.load();
}

Future<void> _pumpHome(WidgetTester tester, Size size) async {
  await Settings.init(cacheProvider: MemorySettingsCache());
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final wrap = smallScreenProviders(
    tester,
    screen: SmallScreen.home,
    size: size,
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
        theme: AppThemeData.light(
          cs,
          compactMenuMode: AppDensity.isSmallWindow(size),
        ),
        home: const MainWindowScreen(),
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(_loadFonts);

  const placeholder = 'בחר ספר או תיקייה לתצוגה מקדימה';

  testWidgets('844×390 (חלון נמוך): התצוגה המקדימה סגורה, וכפתור העין פותח', (
    tester,
  ) async {
    await _pumpHome(tester, const Size(844, 390));
    expect(find.text(placeholder), findsNothing);
    // הכפתור לפתיחה נשאר בסרגל.
    expect(find.byTooltip('הצג תצוגה מקדימה'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('1024×600: התצוגה המקדימה פתוחה כמו קודם', (tester) async {
    await _pumpHome(tester, const Size(1024, 600));
    expect(find.text(placeholder), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
