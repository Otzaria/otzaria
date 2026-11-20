// דיאלוג שנפתח מתוך לשונית קריאה ונשאר פתוח בזמן החלפת ערכה.
// `DialogRoute` לוכד את עטיפות ה-`Theme` שבין ההקשר ל-Navigator (בלשונית
// קריאה: `ReaderSurfaceScope`), והלכידה מחזיקה את ה-`Theme` כפי שהיה בפתיחה.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/view/plugin_confirmation_dialog.dart';
import 'package:otzaria/theme/app_surface_colors.dart';
import 'package:otzaria/theme/app_theme_data.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/widgets/dialogs/app_dialogs.dart';
import 'package:otzaria/widgets/dialogs/blocking_progress_dialog.dart';

import '../../support/golden_fonts.dart';

/// פותח דיאלוג מתוך לשונית קריאה (עטיפות Theme מתחת ל-Navigator) באמצעות
/// [open], ומחזיר את ההקשר שבתוך הדיאלוג דרך [dialogContext].
typedef _Opener =
    void Function(
      BuildContext context,
      void Function(BuildContext inner) onDialogBuilt,
    );

void main() {
  setUpAll(loadGoldenFonts);

  final lightScheme = AppThemeData.createColorScheme(
    AppSeedColors.defaultLight,
    Brightness.light,
  );
  final darkScheme = AppThemeData.createColorScheme(
    AppSeedColors.defaultDark,
    Brightness.dark,
  );

  final openers = <String, _Opener>{
    'showDialogUntilTornDown (showSingleActionDialog)': (context, onBuilt) {
      showSingleActionDialog(
        context: context,
        title: 'כותרת',
        customContent: Builder(
          builder: (inner) {
            onBuilt(inner);
            return const Text('תוכן');
          },
        ),
        confirmText: 'הבנתי',
      );
    },
    'showBlockingProgress': (context, onBuilt) {
      showBlockingProgress(
        context: context,
        title: 'מעבד',
        message: 'אנא המתן',
      );
    },
    'PluginConfirmationDialog': (context, onBuilt) {
      PluginConfirmationDialog().show(
        context: context,
        title: 'אישור',
        content: 'להמשיך?',
      );
    },
  };

  for (final entry in openers.entries) {
    testWidgets('החלפת ערכה בזמן שדיאלוג פתוח מלשונית קריאה: ${entry.key}', (
      tester,
    ) async {
      final mode = ValueNotifier(ThemeMode.light);
      addTearDown(mode.dispose);

      late BuildContext tabContext;
      BuildContext? dialogContext;

      await tester.pumpWidget(
        ValueListenableBuilder<ThemeMode>(
          valueListenable: mode,
          builder: (_, themeMode, _) => MaterialApp(
            theme: AppThemeData.light(lightScheme, compactMenuMode: false),
            darkTheme: AppThemeData.dark(darkScheme, compactMenuMode: false),
            themeMode: themeMode,
            home: Builder(
              // כמו לשונית קריאה: עטיפת Theme בין הקשר הפתיחה ל-Navigator.
              builder: (context) => Theme(
                data: Theme.of(context),
                child: ReaderSurfaceScope(
                  child: Scaffold(
                    body: Builder(
                      builder: (context) {
                        tabContext = context;
                        return Center(
                          child: TextButton(
                            onPressed: () =>
                                entry.value(context, (c) => dialogContext = c),
                            child: const Text('פתח'),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('פתח'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // הקשר בתוך הדיאלוג: ל-Builder של התוכן, ובלעדיו לדיאלוג עצמו.
      BuildContext inside() =>
          dialogContext ?? tester.element(find.byType(Dialog));
      expect(Theme.of(inside()).brightness, Brightness.light);

      mode.value = ThemeMode.dark;
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(
        Theme.of(tabContext).brightness,
        Brightness.dark,
        reason: 'הלשונית עצמה עברה לערכה הכהה',
      );
      expect(
        Theme.of(inside()).brightness,
        Brightness.dark,
        reason: 'הדיאלוג הפתוח נשאר בערכה הישנה',
      );
      expect(
        Theme.of(inside()).colorScheme.surface,
        darkScheme.surface,
        reason: 'רקע הדיאלוג נשאר בצבע הישן',
      );
    });
  }
}
