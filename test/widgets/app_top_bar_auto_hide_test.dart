import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/window_fullscreen_cubit.dart';
import 'package:otzaria/core/windowing/window_fullscreen_top_bar.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';

import '../helpers/memory_settings_cache.dart';
import '../helpers/semantics_update_recorder.dart';
import '../test_helpers/stub_settings_bloc.dart';

// במסך מלא סרגל הקורא לא תופס גובה, ומוצג בריחוף בראש החלונית (#5199).
void main() {
  SemanticsRecordingBinding.ensure();
  final recorder = SemanticsRecordingBinding.recorder;

  const contentKey = Key('content');
  const buttonKey = Key('bar-button');
  const paneKey = Key('pane');
  var contentPresses = 0;

  setUp(() async {
    recorder.reset();
    contentPresses = 0;
    await Settings.init(cacheProvider: MemorySettingsCache());
    // ההודעה החד-פעמית נבדקת במסך הספר (text_book_screen_actions_test).
    await Settings.setValue(
      SettingsRepository.keyFullscreenToolbarHintShown,
      true,
    );
  });

  Future<WindowFullscreenCubit> pumpBar(
    WidgetTester tester, {
    bool isFullscreen = true,
    bool autoHide = true,
    TextDirection direction = TextDirection.rtl,
    double paneStart = 0,
    FocusNode? buttonFocus,
    VoidCallback? onPressed,
    VoidCallback? onContentTap,
  }) async {
    final settingsBloc = StubSettingsBloc(
      SettingsState.initial().copyWith(fullscreenAutoHideToolbar: autoHide),
    );
    addTearDown(settingsBloc.close);
    final cubit = WindowFullscreenCubit(
      initial: isFullscreen,
      persist: (_) async {},
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: direction,
          child: Scaffold(
            body: MultiBlocProvider(
              providers: [
                BlocProvider<SettingsBloc>.value(value: settingsBloc),
                BlocProvider<WindowFullscreenCubit>.value(value: cubit),
              ],
              child: WindowFullscreenTopBarScope(
                child: Row(
                  children: [
                    SizedBox(width: paneStart),
                    Expanded(
                      child: AppTopBarLayout(
                        key: paneKey,
                        children: [
                          AppTopBar(
                            center: const Text('כותרת'),
                            leadingItems: [
                              AppTopBarItem(
                                widget: TextButton(
                                  key: buttonKey,
                                  focusNode: buttonFocus,
                                  onPressed: onPressed ?? () {},
                                  child: const Text('פעולה'),
                                ),
                              ),
                            ],
                          ),
                          Expanded(
                            child: Listener(
                              key: contentKey,
                              behavior: HitTestBehavior.opaque,
                              onPointerDown: (_) => contentPresses++,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: onContentTap,
                                child: Semantics(
                                  label: 'תוכן',
                                  child: const SizedBox.expand(),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return cubit;
  }

  /// כמה מהסרגל גלוי: 0 מוסתר, 1 מוצג.
  double reveal(WidgetTester tester) {
    final align = find.ancestor(
      of: find.byType(AppTopBar),
      matching: find.byWidgetPredicate(
        (w) => w is Align && w.alignment == Alignment.bottomCenter,
      ),
    );
    return tester.widget<Align>(align.first).heightFactor!;
  }

  Future<void> waitUntilHidden(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  }

  Future<TestGesture> mouseAt(WidgetTester tester, Offset location) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: location);
    await tester.pump();
    return mouse;
  }

  testWidgets('התוכן מתחיל בראש החלונית, והסרגל נעלם אחרי הכניסה', (
    tester,
  ) async {
    await pumpBar(tester);

    expect(tester.getTopLeft(find.byKey(contentKey)).dy, 0);
    expect(reveal(tester), 1.0, reason: 'מוצג לרגע בכניסה');
    expect(find.byKey(buttonKey).hitTestable(), findsOneWidget);

    await waitUntilHidden(tester);
    expect(reveal(tester), 0.0);
    expect(find.byKey(buttonKey).hitTestable(), findsNothing);
    expect(tester.getTopLeft(find.byKey(contentKey)).dy, 0);
  });

  testWidgets('ריחוף בראש החלונית מציג את הסרגל, ויציאה ממנו מסתירה', (
    tester,
  ) async {
    await pumpBar(tester);
    final mouse = await mouseAt(tester, const Offset(400, 300));
    await waitUntilHidden(tester);

    await mouse.moveTo(const Offset(400, 3));
    await tester.pumpAndSettle();
    expect(reveal(tester), 1.0);
    expect(find.byKey(buttonKey).hitTestable(), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(reveal(tester), 1.0, reason: 'כל עוד העכבר עליו');

    await mouse.moveTo(const Offset(400, 300));
    await waitUntilHidden(tester);
    expect(reveal(tester), 0.0);
  });

  testWidgets('פס הרגישות לא בולע לחיצות על התוכן שמתחתיו', (tester) async {
    var barPresses = 0;
    var contentTaps = 0;
    await pumpBar(
      tester,
      onPressed: () => barPresses++,
      onContentTap: () => contentTaps++,
    );
    await waitUntilHidden(tester);

    await tester.tapAt(const Offset(400, 30));
    await tester.pumpAndSettle();
    expect(reveal(tester), 0.0);

    final touch = await tester.startGesture(const Offset(400, 4));
    await tester.pumpAndSettle();
    expect(reveal(tester), 1.0);
    expect(find.byTooltip('צא ממסך מלא').hitTestable(), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(contentKey)).dy, 0);
    await touch.up();
    expect(contentPresses, 2);
    expect(contentTaps, 2);

    await tester.tap(find.byKey(buttonKey));
    expect(barPresses, 1);
    expect(contentPresses, 2);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(reveal(tester), 0.0);
  });

  testWidgets('מיקוד מקלדת בכפתור מציג את הסרגל ומשאיר אותו', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await pumpBar(tester, buttonFocus: focus);
    await waitUntilHidden(tester);

    focus.requestFocus();
    await tester.pumpAndSettle();
    expect(reveal(tester), 1.0);

    await tester.pump(const Duration(seconds: 2));
    expect(reveal(tester), 1.0);

    focus.unfocus();
    await waitUntilHidden(tester);
    expect(reveal(tester), 0.0);
  });

  testWidgets('מיקוד בסרגל בזמן הכניסה למסך מלא משאיר אותו גלוי', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final cubit = await pumpBar(
      tester,
      isFullscreen: false,
      buttonFocus: focus,
    );
    focus.requestFocus();
    await tester.pump();
    final state = tester.state(find.byKey(buttonKey));

    await cubit.set(true);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(reveal(tester), 1.0);
    expect(focus.hasFocus, isTrue);
    expect(tester.state(find.byKey(buttonKey)), same(state));

    await cubit.set(false);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(contentKey)).dy, greaterThan(0));
    expect(tester.state(find.byKey(buttonKey)), same(state));
  });

  testWidgets('לא נעלם מתחת לדיאלוג שנפתח ממנו', (tester) async {
    late BuildContext barContext;
    await pumpBar(
      tester,
      onPressed: () => showDialog<void>(
        context: barContext,
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('סגור'),
        ),
      ),
    );
    barContext = tester.element(find.byKey(buttonKey));
    final mouse = await mouseAt(tester, const Offset(400, 3));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(buttonKey));
    await tester.pumpAndSettle();
    await mouse.moveTo(const Offset(400, 300));
    await tester.pump(const Duration(seconds: 3));
    expect(reveal(tester), 1.0);

    await tester.tap(find.text('סגור'));
    await waitUntilHidden(tester);
    expect(reveal(tester), 0.0);
  });

  for (final direction in TextDirection.values) {
    testWidgets('בחלון מפוצל הסרגל נשאר בתוך החלונית שלו $direction', (
      tester,
    ) async {
      await pumpBar(tester, direction: direction, paneStart: 300);

      final pane = tester.getRect(find.byKey(paneKey));
      final bar = tester.getRect(find.byType(AppTopBar));
      expect(bar.left, pane.left);
      expect(bar.right, pane.right);
      expect(bar.top, pane.top);
      expect(tester.getTopLeft(find.byKey(contentKey)).dy, pane.top);
    });
  }

  for (final (name, isFullscreen, autoHide) in [
    ('ההגדרה כבויה', true, false),
    ('לא במסך מלא', false, true),
  ]) {
    testWidgets('$name: הסרגל בפריסה ודוחף את התוכן', (tester) async {
      await pumpBar(tester, isFullscreen: isFullscreen, autoHide: autoHide);
      await tester.pump(const Duration(seconds: 2));

      expect(reveal(tester), 1.0);
      expect(
        tester.getTopLeft(find.byKey(contentKey)).dy,
        tester.getBottomLeft(find.byType(AppTopBar)).dy,
      );
      expect(find.byKey(buttonKey).hitTestable(), findsOneWidget);
    });
  }

  testWidgets('כניסה, הסתרה, ריחוף ויציאה בלי עדכון סמנטיקה פגום (#3336)', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final cubit = await pumpBar(tester, isFullscreen: false);
    final mouse = await mouseAt(tester, const Offset(400, 300));

    await cubit.set(true);
    await waitUntilHidden(tester);
    await mouse.moveTo(const Offset(400, 3));
    await tester.pumpAndSettle();
    await mouse.moveTo(const Offset(400, 300));
    await waitUntilHidden(tester);
    await cubit.set(false);
    await tester.pumpAndSettle();

    expect(recorder.violations, isEmpty);
    handle.dispose();
  });

  testWidgets('קורא המסך מקריא את הסרגל הגלוי לפני התוכן', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpBar(tester);

    final labels = <String>[];
    void visit(SemanticsNode node) {
      if (node.label.isNotEmpty) labels.add(node.label);
      for (final child in node.debugListChildrenInOrder(
        DebugSemanticsDumpOrder.traversalOrder,
      )) {
        visit(child);
      }
    }

    visit(tester.getSemantics(find.byType(Scaffold)));
    expect(labels.indexOf('פעולה'), lessThan(labels.indexOf('תוכן')));
    handle.dispose();
  });

  Future<void> pumpPlain(
    WidgetTester tester, {
    required ValueListenable<bool> autoHide,
    ValueListenable<bool>? visible,
    ValueSetter<BuildContext>? onEntered,
    List<String>? paintLog,
  }) async {
    final settingsBloc = StubSettingsBloc(SettingsState.initial());
    addTearDown(settingsBloc.close);
    Widget recorder(String name, Widget? child) => CustomPaint(
      painter: _PaintRecorder(() => paintLog?.add(name)),
      child: child,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<SettingsBloc>.value(
            value: settingsBloc,
            child: ListenableBuilder(
              listenable: Listenable.merge([autoHide, visible]),
              builder: (context, _) => TickerMode(
                enabled: visible?.value ?? true,
                child: AppTopBarScope(
                  autoHide: autoHide.value,
                  onAutoHideEntered: onEntered,
                  child: AppTopBarLayout(
                    children: [
                      AppTopBar(center: recorder('bar', const Text('כותרת'))),
                      Expanded(
                        child: recorder('body', const SizedBox.expand()),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('בחלון רגיל צל הסרגל לא נחתך, והתוכן מצויר אחריו כמו ב-Column', (
    tester,
  ) async {
    final autoHide = ValueNotifier(false);
    addTearDown(autoHide.dispose);
    final paintLog = <String>[];
    await pumpPlain(tester, autoHide: autoHide, paintLog: paintLog);

    final clip = tester.renderObject<RenderClipRect>(
      find
          .ancestor(
            of: find.byWidgetPredicate(
              (w) => w is Align && w.alignment == Alignment.bottomCenter,
            ),
            matching: find.byType(ClipRect),
          )
          .first,
    );
    expect(
      clip.clipper!.getClip(clip.size).bottom,
      greaterThan(clip.size.height),
    );
    expect(paintLog, ['bar', 'body']);

    paintLog.clear();
    autoHide.value = true;
    await tester.pump();
    expect(paintLog, ['body', 'bar']);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('קורא שנטען ברקע מציג את הסרגל ואת ההודעה כשהוא עובר לחזית', (
    tester,
  ) async {
    final autoHide = ValueNotifier(false);
    final visible = ValueNotifier(false);
    addTearDown(autoHide.dispose);
    addTearDown(visible.dispose);
    var entered = 0;
    await pumpPlain(
      tester,
      autoHide: autoHide,
      visible: visible,
      onEntered: (_) => entered++,
    );

    autoHide.value = true;
    await tester.pump(const Duration(seconds: 2));
    expect(entered, 0);

    visible.value = true;
    await tester.pump();
    expect(entered, 1);
    expect(reveal(tester), 1.0);
    await waitUntilHidden(tester);
    expect(reveal(tester), 0.0);

    visible.value = false;
    await tester.pump();
    visible.value = true;
    await tester.pump();
    expect(entered, 1);
  });
}

class _PaintRecorder extends CustomPainter {
  final VoidCallback onPaint;

  _PaintRecorder(this.onPaint);

  @override
  void paint(Canvas canvas, Size size) => onPaint();

  @override
  bool shouldRepaint(_PaintRecorder oldDelegate) => true;
}
