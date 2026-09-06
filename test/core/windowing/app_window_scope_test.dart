import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:window_manager/window_manager.dart' show TitleBarStyle;

/// ה-scope הוא הדרך של widget להגיע לחלון שהוא יושב בו, במקום לפנות
/// ל-singleton גלובלי שמתאר תמיד את החלון היחיד.
void main() {
  testWidgets('controllerOf ו-geometryOf מחזירים את מה שהוזרק', (tester) async {
    const controller = _FakeWindow(AppWindowId('window-7'));
    late AppWindowController seenController;
    late AppWindowGeometry seenGeometry;

    await tester.pumpWidget(
      AppWindowScope(
        controller: controller,
        geometry: controller,
        child: Builder(
          builder: (context) {
            seenController = AppWindowScope.controllerOf(context);
            seenGeometry = AppWindowScope.geometryOf(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(seenController.id, const AppWindowId('window-7'));
    expect(identical(seenGeometry, controller), isTrue);
  });

  testWidgets('widget ללא scope נכשל ב-assert ברור', (tester) async {
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          AppWindowScope.controllerOf(context);
          return const SizedBox();
        },
      ),
    );

    expect(tester.takeException(), isAssertionError);
  });

  test('updateShouldNotify מודיע רק כשהבקר מתחלף', () {
    // נבדק ישירות ולא דרך pumpWidget: כל pump יוצר מופע widget חדש
    // לילד, והוא נבנה מחדש בלי קשר להודעה — כך שבדיקה דרך מונה בנייה
    // הייתה מודדת משהו אחר לגמרי.
    const first = _FakeWindow(AppWindowId('window-1'));
    const second = _FakeWindow(AppWindowId('window-2'));
    const child = SizedBox();

    const scope = AppWindowScope(
      controller: first,
      geometry: first,
      child: child,
    );

    expect(
      scope.updateShouldNotify(
        const AppWindowScope(controller: first, geometry: first, child: child),
      ),
      isFalse,
    );
    expect(
      scope.updateShouldNotify(
        const AppWindowScope(
          controller: second,
          geometry: second,
          child: child,
        ),
      ),
      isTrue,
    );
  });
}

/// בקר בדיקה: המימוש האמיתי מאציל ל-singleton גלובלי, ולבדיקת ה-scope
/// מספיק אובייקט שאפשר להשוות את זהותו.
class _FakeWindow implements AppWindowController, AppWindowGeometry {
  const _FakeWindow(this.id);

  @override
  final AppWindowId id;

  @override
  Future<void> center() async {}
  @override
  Future<void> close() async {}
  @override
  Future<void> quitApplication() async {}
  @override
  Future<void> focus() async {}
  @override
  Future<Rect> getBounds() async => Rect.zero;
  @override
  Future<bool> isFullScreen() async => false;
  @override
  Future<bool> isMaximized() async => false;
  @override
  Future<bool> isMinimized() async => false;
  @override
  Future<bool> isVisible() async => true;
  @override
  Future<void> maximize() async {}
  @override
  Future<void> minimize() async {}
  @override
  Future<void> setBounds(Rect bounds) async {}
  @override
  Future<void> setFullScreen(bool value) async {}
  @override
  Future<void> setMinimumSize(Size size) async {}
  @override
  Future<void> setSize(Size size) async {}
  @override
  Future<void> setTitleBarStyle(
    TitleBarStyle style, {
    required bool windowButtonVisibility,
  }) async {}
  @override
  Future<void> show() async {}
  @override
  Future<void> startDragging() async {}
  @override
  Future<void> unmaximize() async {}
}
