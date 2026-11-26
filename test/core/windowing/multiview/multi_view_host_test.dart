// ignore_for_file: implementation_imports, invalid_use_of_internal_member
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_scope/app_scope_providers.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/windowing/multiview/multi_view_host.dart';
import 'package:otzaria/core/windowing/multiview/multiview_flag.dart';
import 'package:otzaria/core/windowing/multiview/view_window_registry.dart';
import 'package:otzaria/plugins/bloc/plugin_updates_cubit.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

void main() {
  tearDown(() {
    AppWindowKeys.resetForTest();
  });

  testWidgets('שני חלונות נטענים תחת AppScopeProviders אחד ונסגרים', (
    tester,
  ) async {
    final registry = _registry(tester);
    final contexts = <int, BuildContext>{};
    late BuildContext mainContext;

    await tester.pumpWidget(
      AppScopeProviders(
        settingsRepository: SettingsRepository(),
        child: MultiViewHost(
          registry: registry,
          contentBuilder: (context, entry) {
            contexts[entry.slot] = context;
            return const SizedBox.shrink();
          },
          child: Builder(
            builder: (context) {
              mainContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    final a = registry.open(size: const Size(800, 600))!;
    final b = registry.open(size: const Size(800, 600))!;
    await tester.pump();

    expect([a.slot, b.slot], [2, 3]);
    await a.firstFrame;
    await b.firstFrame;
    final shared = mainContext.read<PluginUpdatesCubit>();
    expect(identical(contexts[2]!.read<PluginUpdatesCubit>(), shared), isTrue);
    expect(identical(contexts[3]!.read<PluginUpdatesCubit>(), shared), isTrue);
    expect(View.of(contexts[2]!), same(a.handle.view));
    expect(View.of(contexts[3]!), same(b.handle.view));

    // בקשת סגירה מהמערכת → destroy → הסרה מהרשימה ופירוק העץ.
    (a.handle as _StubHandle).requestClose();
    await tester.pump();
    expect(registry.windows, [b]);
    expect(find.byType(View), findsNWidgets(2));

    // משבצת שהתפנתה חוזרת לשימוש.
    expect(registry.open(size: const Size(800, 600))!.slot, 2);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('התקרה הרכה כוללת את החלון הראשי', (tester) async {
    final registry = _registry(tester);
    for (var i = 1; i < ViewWindowRegistry.maxWindows; i++) {
      expect(registry.open(size: const Size(800, 600)), isNotNull);
    }
    expect(registry.canOpenAnotherWindow, isFalse);
    expect(registry.open(size: const Size(800, 600)), isNull);
  });
}

var _nextViewId = 100;

ViewWindowRegistry _registry(WidgetTester tester) => ViewWindowRegistry(
  factory:
      ({
        required size,
        required title,
        required onCloseRequested,
        required onDestroyed,
      }) {
        final controller = _StubController(
          _FakeView(tester.view, _nextViewId++),
        );
        final handle = _StubHandle(controller, onCloseRequested);
        controller.onDestroy = () => onDestroyed(handle);
        return handle;
      },
);

class _StubHandle extends ViewWindowHandle {
  _StubHandle(super.controller, this._onCloseRequested) : super.forTesting();

  final void Function(ViewWindowHandle handle) _onCloseRequested;

  void requestClose() => _onCloseRequested(this);
}

class _StubController extends WindowController {
  _StubController(FlutterView view) : super.empty() {
    rootView = view;
  }

  VoidCallback? onDestroy;
  bool _destroyed = false;

  @override
  void destroy() {
    if (_destroyed) return;
    _destroyed = true;
    onDestroy?.call();
  }

  @override
  bool get isDestroyed => _destroyed;
  @override
  Size get contentSize => Size.zero;
  @override
  String get title => '';
  @override
  bool get isActivated => false;
  @override
  bool get isMaximized => false;
  @override
  bool get isMinimized => false;
  @override
  bool get isFullscreen => false;
  @override
  void setSize(Size size) {}
  @override
  void setConstraints(BoxConstraints constraints) {}
  @override
  void setTitle(String title) {}
  @override
  void activate() {}
  @override
  void setMaximized(bool maximized) {}
  @override
  void setMinimized(bool minimized) {}
  @override
  void setFullscreen(bool fullscreen, {Display? display}) {}
}

// תצוגה נוספת שאינה מציירת למנוע, כמו ב-multi_view_testing של Flutter.
class _FakeView extends TestFlutterView {
  _FakeView(FlutterView view, this.viewId)
    : super(
        view: view,
        platformDispatcher: view.platformDispatcher as TestPlatformDispatcher,
        display: view.display as TestDisplay,
      );

  @override
  final int viewId;

  @override
  void render(Scene scene, {Size? size}) {}

  @override
  void updateSemantics(SemanticsUpdate update) {}
}
