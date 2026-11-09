// theme.changed לתוספים כשהצפיפות שבפועל מתהפכת עם גודל החלון (סקירת הקוד r3):
// קודם האירוע נשלח רק כשההגדרות השתנו, ותוסף נשאר עם הצפיפות הקודמת.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/navigation/view/main_window_screen.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/theme/theme_exports.dart';

import '../../helpers/memory_settings_cache.dart';
import 'small_screens_fixture.dart';

void main() {
  testWidgets('במחשב: theme.changed פעם אחת לכל היפוך של הצפיפות', (
    tester,
  ) async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    const start = Size(1280, 800);
    tester.view.physicalSize = start;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final wrap = smallScreenProviders(
      tester,
      screen: SmallScreen.home,
      size: start,
    );

    final themeEvents = <String>[];
    final previousPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message == 'PluginRuntimeDispatcher: Dispatching theme.changed') {
        themeEvents.add(message!);
      }
    };
    // מוחזר בגוף הבדיקה: הבודק דורש שמשתני הדיבאג יחזרו לפני סופה.
    try {
      final cs = AppThemeData.createColorScheme(
        AppSeedColors.defaultLight,
        Brightness.light,
      );
      // כמו App: ערכת הנושא בצפיפות שבפועל, בלי בחירה.
      await tester.pumpWidget(
        wrap(
          SmallWindowBuilder(
            builder: (isSmall) => MaterialApp(
              localizationsDelegates: const [
                GlobalCupertinoLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
              ],
              supportedLocales: const [Locale('he', 'IL')],
              locale: const Locale('he', 'IL'),
              theme: AppThemeData.light(
                cs,
                compactMenuMode: SettingsState.initial().compactMenuModeFor(
                  isSmallWindow: isSmall,
                ),
              ),
              home: const MainWindowScreen(),
            ),
          ),
        ),
      );

      Future<void> settle() async {
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      Future<void> resize(Size size) async {
        tester.view.physicalSize = size;
        await settle();
      }

      await settle();
      final atStart = themeEvents.length;

      // מעל הסף: בלי היפוך, בלי אירוע.
      await resize(const Size(1093, 566));
      expect(themeEvents.length, atStart);

      // חלון נמוך מ-480: מצומצם, אירוע אחד גם אחרי כמה שינויי גודל.
      await resize(const Size(1200, 450));
      await resize(const Size(1150, 430));
      expect(themeEvents.length, atStart + 1);

      // ובחזרה.
      await resize(const Size(1280, 800));
      expect(themeEvents.length, atStart + 2);
      expect(tester.takeException(), isNull);
    } finally {
      debugPrint = previousPrint;
    }
  });
}
