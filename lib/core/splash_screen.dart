import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/theme/app_theme_data.dart';

/// סמל מסך הפתיחה, באטימות 70%. החלון הראשי מוסתר לכל אורך שלב ה-splash —
/// הסמל שנראה למשתמש הוא חלון ה-splash הנייטיבי הנפרד (ראה runner).
class SplashIcon extends StatelessWidget {
  const SplashIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Opacity(
        opacity: 0.70,
        child: Image.asset(
          'assets/icon/icon_256.png',
          width: 128,
          height: 128,
        ),
      ),
    );
  }
}

/// מסך פתיחה מוצג בזמן האתחול לפני שה-App נטען. ההגדרות עוד לא נטענו,
/// ולכן הבהירות נלקחת ממערכת ההפעלה והצבעים מזרעי ברירת המחדל.
class SplashApp extends StatelessWidget {
  const SplashApp({super.key});

  static ThemeData _theme(Brightness brightness) => ThemeData(
    colorScheme: AppThemeData.createColorScheme(
      brightness == Brightness.dark
          ? AppSeedColors.defaultDark
          : AppSeedColors.defaultLight,
      brightness,
    ),
  );

  @override
  Widget build(BuildContext context) {
    // הרקע חייב להיות אטום (נצבע): סצנה שקופה מייצרת פריימים ריקים, ופריים ריק
    // בזמן resize משכלף את ה-surface בגלל באג מנוע (flutter#187922) — זום מוזר.
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: const Scaffold(
        body: SplashIcon(),
      ),
    );
  }
}
