// q12 Q8 (B): כפתור "מסך מלא" בסרגל הקורא, בטלפון בלבד, כשאין לו מקום
// בשורת הכותרת (הערת בעל הפרויקט, 4.11).
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/core/windowing/device_chrome.dart';
import 'package:otzaria/core/windowing/window_fullscreen_cubit.dart';
import 'package:otzaria/core/windowing/window_fullscreen_top_bar.dart';
import 'package:otzaria/core/windowing/window_manager_app_window_controller.dart';
import 'package:otzaria/widgets/navigation/responsive_action_bar.dart';

Future<WindowFullscreenCubit> _pump(
  WidgetTester tester, {
  required bool mobile,
  bool fullscreen = false,
  // חצי מסך בטלפון לרוחב: הכרטיסיות בשורת הכותרת, ואין בה מקום לכפתור.
  Size size = const Size(420, 390),
  required void Function(ActionButtonData? action) onBuild,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  DeviceChrome.debugMobileOverride = mobile;
  addTearDown(() => DeviceChrome.debugMobileOverride = null);
  final cubit = WindowFullscreenCubit(
    initial: fullscreen,
    persist: (_) async {},
  );
  addTearDown(cubit.close);
  await tester.pumpWidget(
    AppWindowScope(
      controller: const WindowManagerAppWindowController(),
      geometry: const WindowManagerAppWindowController(),
      child: BlocProvider<WindowFullscreenCubit>.value(
        value: cubit,
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              final action = buildMobileFullscreenAction(
                context,
                compact: false,
              );
              onBuild(action);
              return Scaffold(body: action?.widget ?? const SizedBox());
            },
          ),
        ),
      ),
    ),
  );
  return cubit;
}

void main() {
  testWidgets('בטלפון: כשיש מקום בשורת הכותרת, הכפתור שם ולא בסרגל', (
    tester,
  ) async {
    for (final size in const [Size(360, 640), Size(390, 844), Size(844, 390)]) {
      ActionButtonData? action;
      await _pump(tester, mobile: true, size: size, onBuild: (a) => action = a);
      expect(action, isNull, reason: '$size');
    }
  });

  testWidgets('בטלפון בלי מקום בכותרת: פעולת "מסך מלא" שנכנסת למסך מלא', (
    tester,
  ) async {
    ActionButtonData? action;
    final cubit = await _pump(tester, mobile: true, onBuild: (a) => action = a);

    expect(action, isNotNull);
    expect(action!.actionId, ToolbarActionId.fullscreen);
    expect(find.byTooltip('מסך מלא'), findsOneWidget);

    await tester.tap(find.byTooltip('מסך מלא'));
    await tester.pump();
    expect(cubit.state, isTrue);
    // במסך מלא הכניסה נעלמת: היציאה כבר בסוף הסרגל.
    expect(action, isNull);
  });

  testWidgets('במחשב אין פעולה: הכפתור בשורת הכותרת ו-F11', (tester) async {
    ActionButtonData? action;
    await _pump(tester, mobile: false, onBuild: (a) => action = a);
    expect(action, isNull);
  });

  testWidgets('בטלפון במסך מלא אין פעולת כניסה', (tester) async {
    ActionButtonData? action;
    await _pump(
      tester,
      mobile: true,
      fullscreen: true,
      onBuild: (a) => action = a,
    );
    expect(action, isNull);
  });
}
