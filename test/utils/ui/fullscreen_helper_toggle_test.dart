import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/utils/ui/fullscreen_helper.dart';
import '../../unit/mocks/mock_settings_repository.mocks.dart';

/// רגרסיה ל-98f1ae119: מסך ההגדרות עדכן את מצב המסך המלא ישירות מול
/// windowManager, בעוד מסך העיון עבר דרך FullscreenHelper.toggleFullscreen —
/// כך ה-titlebar וה-SettingsBloc יצאו מסונכרנים בין המסכים. הבדיקות מוודאות
/// שקריאה אחת ל-toggleFullscreen (מכל מסך) מעדכנת את ה-SettingsBloc המשותף,
/// כך שכל מסך אחר שקורא ממנו את isFullscreen יראה את אותו ערך.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> windowManagerCalls;

  setUp(() {
    windowManagerCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), (
          call,
        ) async {
          windowManagerCalls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), null);
  });

  Future<SettingsBloc> buildSettingsBloc() async {
    final bloc = SettingsBloc(repository: MockSettingsRepository());
    addTearDown(bloc.close);
    return bloc;
  }

  testWidgets(
    'toggleFullscreen שנקרא מהקשר אחד משתקף מיד ב-SettingsBloc המשותף '
    'שנקרא ממסך אחר',
    (tester) async {
      final settingsBloc = await buildSettingsBloc();
      late BuildContext readingScreenContext;
      late BuildContext settingsScreenContext;

      await tester.pumpWidget(
        BlocProvider<SettingsBloc>.value(
          value: settingsBloc,
          child: MaterialApp(
            home: Column(
              children: [
                Builder(
                  builder: (context) {
                    readingScreenContext = context;
                    return const SizedBox();
                  },
                ),
                Builder(
                  builder: (context) {
                    settingsScreenContext = context;
                    return const SizedBox();
                  },
                ),
              ],
            ),
          ),
        ),
      );

      expect(
        settingsScreenContext.read<SettingsBloc>().state.isFullscreen,
        isFalse,
      );

      // מדמים לחיצה על כפתור מסך מלא במסך העיון.
      await FullscreenHelper.toggleFullscreen(readingScreenContext, true);
      // bloc.add מתוזמן אסינכרונית; pump מפנה את התור לפני קריאת ה-state.
      await tester.pump();

      // מסך ההגדרות קורא מאותו ה-bloc המשותף — חייב לראות את אותו מצב.
      expect(
        settingsScreenContext.read<SettingsBloc>().state.isFullscreen,
        isTrue,
        reason:
            'שני המסכים חולקים SettingsBloc אחד; שינוי מכל אחד מהם '
            'צריך להשתקף מיד באחר',
      );
    },
  );

  testWidgets(
    'toggleFullscreen(true) מסתיר את הכותרת לפני setFullScreen, ו-(false) '
    'משאיר אותה מוסתרת (CustomTitleBar) — עקבי בכל קריאה',
    (tester) async {
      final settingsBloc = await buildSettingsBloc();
      late BuildContext context;

      await tester.pumpWidget(
        BlocProvider<SettingsBloc>.value(
          value: settingsBloc,
          child: MaterialApp(
            home: Builder(
              builder: (c) {
                context = c;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      await FullscreenHelper.toggleFullscreen(context, true);

      final methodsWhenEntering = windowManagerCalls
          .map((c) => c.method)
          .toList();
      expect(
        methodsWhenEntering.indexOf('setTitleBarStyle'),
        lessThan(methodsWhenEntering.indexOf('setFullScreen')),
        reason: 'הסתרת ה-titlebar חייבת לקרות לפני setFullScreen (מונע הבהוב)',
      );

      windowManagerCalls.clear();
      await FullscreenHelper.toggleFullscreen(context, false);

      expect(
        windowManagerCalls.map((c) => c.method),
        containsAll(['setFullScreen', 'setTitleBarStyle']),
        reason: 'גם ביציאה ממסך מלא ה-titlebar המותאם-אישית נשאר מוסתר',
      );
    },
  );

  testWidgets(
    'קריאה חוזרת עם אותו מצב לא שולחת UpdateIsFullscreen כפול',
    (tester) async {
      final settingsBloc = await buildSettingsBloc();
      late BuildContext context;

      await tester.pumpWidget(
        BlocProvider<SettingsBloc>.value(
          value: settingsBloc,
          child: MaterialApp(
            home: Builder(
              builder: (c) {
                context = c;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      final emitted = <SettingsState>[];
      final subscription = settingsBloc.stream.listen(emitted.add);
      addTearDown(subscription.cancel);

      await FullscreenHelper.toggleFullscreen(context, true);
      await tester.pump();
      await FullscreenHelper.toggleFullscreen(context, true);
      await tester.pump();

      final fullscreenEmits = emitted.where((s) => s.isFullscreen).toList();
      expect(
        fullscreenEmits.length,
        1,
        reason: 'אין למנוע emit כפול כשהמצב לא באמת השתנה',
      );
    },
  );
}
