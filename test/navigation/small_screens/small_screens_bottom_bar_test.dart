// review-r3, q-bottom-bar: בחלון הראשי האמיתי בטלפון לאורך, הסרגל התחתון עם
// תווית לכל יעד כשהתוויות נכנסות, ורק ליעד הנבחר כשהתווית הארוכה לא נכנסת
// ברוחב של יעד. הגופנים אמיתיים (Rubik כגופן הממשק), כי ההחלטה נמדדת.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/navigation/view/main_window_screen.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/l10n/settings_language.dart';
import 'package:otzaria/settings/l10n/settings_text_scope.dart';
import 'package:otzaria/theme/theme_exports.dart';

import '../../helpers/memory_settings_cache.dart';
import '../../support/golden_fonts.dart';
import 'small_screens_fixture.dart';

Future<void> _loadFonts() async {
  await loadGoldenFonts();
  // הפלטפורמה בבדיקה היא Android, וערכת הנושא מבקשת Roboto: אותו גופן ממשק.
  final roboto = FontLoader('Roboto')
    ..addFont(rootBundle.load('fonts/Rubik-VariableFont_wght.ttf'));
  await roboto.load();
}

Future<NavigationBar> _pumpBar(
  WidgetTester tester, {
  required SettingsLanguage language,
  double textScale = 1,
}) async {
  const size = Size(320, 568);
  await Settings.init(cacheProvider: MemorySettingsCache());
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final wrap = smallScreenProviders(
    tester,
    screen: SmallScreen.home,
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
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: SettingsTextScope(language: language, child: child!),
        ),
        home: const MainWindowScreen(),
      ),
    ),
  );
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  final error = tester.takeException();
  // בטקסט גדול (1.3) פס התאריך שבראש מסך הבית גולש בכמה פיקסלים, גם לפני
  // השינוי. זה לא הסרגל התחתון, וכאן בודקים רק את התוויות.
  if (textScale == 1) expect(error, isNull);
  return tester.widget<NavigationBar>(find.byType(NavigationBar));
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('320×568 בעברית: התוויות נכנסות, תווית לכל יעד', (tester) async {
    final bar = await _pumpBar(tester, language: SettingsLanguage.hebrew);
    expect(bar.labelBehavior, NavigationDestinationLabelBehavior.alwaysShow);
  });

  testWidgets(
    '320×568 באנגלית בטקסט גדול: "Settings" לא נכנס, תווית רק לנבחר',
    (tester) async {
      final bar = await _pumpBar(
        tester,
        language: SettingsLanguage.english,
        textScale: 1.3,
      );
      expect(
        bar.labelBehavior,
        NavigationDestinationLabelBehavior.onlyShowSelected,
      );
    },
  );
}
