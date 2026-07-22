import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/utils/ui/fullscreen_helper.dart';
import '../../unit/mocks/mock_settings_repository.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> windowManagerCalls;
  late List<MethodCall> platformCalls;

  setUp(() {
    windowManagerCalls = [];
    platformCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), (
          call,
        ) async {
          windowManagerCalls.add(call);
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          platformCalls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<SettingsBloc> buildSettingsBloc() async {
    final bloc = SettingsBloc(repository: MockSettingsRepository());
    addTearDown(bloc.close);
    return bloc;
  }

  Future<void> toggleAsDesktop(BuildContext context, bool isFullscreen) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await FullscreenHelper.toggleFullscreen(context, isFullscreen);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
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

      await toggleAsDesktop(readingScreenContext, true);
      await tester.pump();

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

      await toggleAsDesktop(context, true);

      final methodsWhenEntering = windowManagerCalls
          .map((c) => c.method)
          .toList();
      expect(
        methodsWhenEntering.indexOf('setTitleBarStyle'),
        lessThan(methodsWhenEntering.indexOf('setFullScreen')),
        reason: 'הסתרת ה-titlebar חייבת לקרות לפני setFullScreen (מונע הבהוב)',
      );

      windowManagerCalls.clear();
      await toggleAsDesktop(context, false);

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

      await toggleAsDesktop(context, true);
      await tester.pump();
      await toggleAsDesktop(context, true);
      await tester.pump();

      final fullscreenEmits = emitted.where((s) => s.isFullscreen).toList();
      expect(
        fullscreenEmits.length,
        1,
        reason: 'אין למנוע emit כפול כשהמצב לא באמת השתנה',
      );
    },
  );

  testWidgets('במובייל toggleFullscreen מפעיל את SystemChrome', (tester) async {
    final settingsBloc = await buildSettingsBloc();
    late BuildContext context;

    await tester.pumpWidget(
      BlocProvider<SettingsBloc>.value(
        value: settingsBloc,
        child: MaterialApp(
          home: Builder(
            builder: (currentContext) {
              context = currentContext;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await FullscreenHelper.toggleFullscreen(context, true);

      final call = platformCalls.singleWhere(
        (item) => item.method == 'SystemChrome.setEnabledSystemUIMode',
      );
      expect(call.arguments, 'SystemUiMode.immersiveSticky');
      expect(windowManagerCalls, isEmpty);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
