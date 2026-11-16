import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/snap_layouts.dart';
import 'package:otzaria/core/windowing/window_caption_hit_test.dart';

void main() {
  late List<Map<String, Object?>> sent;
  late bool supported;

  setUp(() {
    sent = [];
    supported = true;
    SnapLayoutsBridge.debugPlatformOverride = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SnapLayoutsBridge.channel, (call) async {
          sent.add((call.arguments as Map).cast<String, Object?>());
          return supported;
        });
  });

  tearDown(() {
    SnapLayoutsBridge.instance.debugReset();
    SnapLayoutsBridge.debugPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SnapLayoutsBridge.channel, null);
  });

  Future<void> nativeEvent(
    WidgetTester tester,
    Map<String, Object?> args,
  ) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          SnapLayoutsBridge.channel.name,
          SnapLayoutsBridge.channel.codec.encodeMethodCall(
            MethodCall('maximizeButton', args),
          ),
          (_) {},
        );
    await tester.pump();
  }

  Widget app({
    int? window = 0,
    VoidCallback? onPressed,
    void Function(bool hovered, bool pressed)? onBuild,
    Widget? overlay,
  }) => Directionality(
    textDirection: TextDirection.ltr,
    child: Stack(
      children: [
        Positioned(
          left: 100,
          top: 0,
          width: 46,
          height: 32,
          child: SnapLayoutsMaximizeButton(
            window: window,
            onPressed: onPressed ?? () {},
            builder: (context, hovered, pressed) {
              onBuild?.call(hovered, pressed);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onPressed,
                child: const SizedBox.expand(),
              );
            },
          ),
        ),
        ?overlay,
      ],
    ),
  );

  testWidgets('publishes the exposed button in physical pixels', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app());
    await tester.pump();

    expect(sent.last, {
      'hwnd': 0,
      'left': 150,
      'top': 0,
      'right': 219,
      'bottom': 48,
    });
  });

  testWidgets('a menu over one corner of the button disables Snap Layouts', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app());
    await tester.pump();
    expect(sent.last['right'], 146);

    // מכסה רק את הפינה התחתונה הימנית; המרכז עדיין חשוף.
    await tester.pumpWidget(
      app(
        overlay: Positioned(
          left: 140,
          top: 28,
          width: 200,
          height: 200,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(sent.last, {
      'hwnd': 0,
      'left': 0,
      'top': 0,
      'right': 0,
      'bottom': 0,
    });

    await tester.pumpWidget(app());
    await tester.pump();
    expect(sent.last['right'], 146);
  });

  testWidgets('above a dialog barrier only content over the button disables', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => WindowCaptionHitTestScope(child: child!),
        home: Builder(
          builder: (c) {
            context = c;
            return Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 100),
                child: SizedBox(
                  width: 46,
                  height: 32,
                  child: WindowCaptionRegion(
                    child: SnapLayoutsMaximizeButton(
                      window: 0,
                      onPressed: () {},
                      builder: (context, hovered, pressed) => GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {},
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();
    expect(sent.last['right'], 146);

    // DD-16: שכבת ההחשכה אינה מכסה את הכפתור.
    showDialog<void>(
      context: context,
      builder: (_) => const Center(child: SizedBox(width: 50, height: 50)),
    );
    await tester.pumpAndSettle();
    expect(sent.last['right'], 146);
    Navigator.of(context).pop();
    await tester.pumpAndSettle();

    // תוכן הדיאלוג מעל הפינה התחתונה של הכפתור.
    showDialog<void>(
      context: context,
      builder: (_) => const Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: EdgeInsets.only(left: 140, top: 28),
          child: Material(child: SizedBox(width: 200, height: 200)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(sent.last['right'], 0);
  });

  testWidgets('hover, press and click come from the runner', (tester) async {
    var clicks = 0;
    final states = <(bool, bool)>[];
    await tester.pumpWidget(
      app(onPressed: () => clicks++, onBuild: (h, p) => states.add((h, p))),
    );
    await tester.pump();

    await nativeEvent(tester, {'hwnd': 0, 'hovered': true, 'pressed': false});
    expect(states.last, (true, false));
    await nativeEvent(tester, {'hwnd': 0, 'hovered': true, 'pressed': true});
    expect(states.last, (true, true));
    await nativeEvent(tester, {
      'hwnd': 0,
      'hovered': true,
      'pressed': false,
      'clicked': true,
    });
    expect(states.last, (true, false));
    expect(clicks, 1);

    // אירוע של חלון אחר אינו נוגע בכפתור הזה.
    await nativeEvent(tester, {'hwnd': 77, 'clicked': true});
    expect(clicks, 1);
  });

  testWidgets('disposing the button clears the native rect', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(sent.last['right'], 0);
  });

  testWidgets('a runner without Snap Layouts stops the checks', (
    tester,
  ) async {
    supported = false;
    await tester.pumpWidget(app());
    await tester.pump();
    expect(sent, hasLength(1));

    await tester.pumpWidget(app(window: 0));
    await tester.pump();
    await tester.pump();
    expect(sent, hasLength(1));
  });

  testWidgets('no window key means no native calls', (tester) async {
    await tester.pumpWidget(app(window: null));
    await tester.pump();
    expect(sent, isEmpty);
  });
}
