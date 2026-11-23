import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../integration_test/support/installed_plugin_pdf_readiness.dart';

Future<void> _wait(
  bool Function() ready,
  String description, {
  required Duration timeout,
}) async {
  final clock = Stopwatch()..start();
  while (!ready()) {
    if (clock.elapsed >= timeout) {
      throw TimeoutException(description, timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

class _Controller extends Fake implements PdfViewerController {
  final incompleteNavigation = Completer<void>();
  bool stallNavigation = false;
  bool hasLayout = true;
  bool hasViewSize = true;
  var navigationCalls = 0;
  @override
  bool get isReady => true;
  @override
  final ValueNotifier<PdfVisibleRenderState> visibleRenderState = ValueNotifier(
    PdfVisibleRenderState.ready,
  );
  @override
  Rect visibleRect = const Rect.fromLTWH(0, 0, 200, 100);
  @override
  PdfPageLayout get layout {
    if (!hasLayout) throw StateError('Layout has not been initialized');
    return _layout;
  }

  @override
  Size get viewSize {
    if (!hasViewSize) throw StateError('View size has not been initialized');
    return const Size(200, 100);
  }

  final _layout = PdfPageLayout(
    pageLayouts: const [Rect.fromLTWH(0, 0, 200, 400)],
    documentSize: const Size(200, 400),
  );

  @override
  Future<void> goToPage({
    required int pageNumber,
    PdfPageAnchor? anchor,
    Duration duration = const Duration(milliseconds: 200),
  }) async {
    navigationCalls++;
    // pdfrx's canceled animation Future never completes; a zero-duration jump does.
    if (stallNavigation || duration != Duration.zero) {
      await incompleteNavigation.future;
      return;
    }
    if (anchor == PdfPageAnchor.center) {
      visibleRect = const Rect.fromLTWH(0, 150, 200, 100);
    }
    visibleRenderState.value = PdfVisibleRenderState.pending;
  }
}

void main() {
  test(
    'isReady alone does not navigate before layout and viewport exist',
    () async {
      final controller = _Controller()
        ..hasLayout = false
        ..hasViewSize = false;
      addTearDown(controller.visibleRenderState.dispose);
      final pending = navigateInstalledPdfTarget(
        controller,
        1,
        nextFrame: () async =>
            controller.visibleRenderState.value = PdfVisibleRenderState.ready,
        wait: _wait,
        timeout: const Duration(seconds: 1),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.navigationCalls, 0);
      controller.hasLayout = true;
      await Future<void>.delayed(Duration.zero);
      expect(controller.navigationCalls, 0);
      controller.hasViewSize = true;
      await pending;
      expect(controller.navigationCalls, 1);
      expect(installedPdfTargetReady(controller, 1), true);
    },
  );

  test(
    'ready controller outside the target navigates without an animation',
    () async {
      final controller = _Controller();
      addTearDown(controller.visibleRenderState.dispose);
      expect(installedPdfTargetReady(controller, 1), false);
      await navigateInstalledPdfTarget(
        controller,
        1,
        nextFrame: () async {
          expect(controller.visibleRect.contains(const Offset(100, 200)), true);
          expect(installedPdfTargetReady(controller, 1), false);
          controller.visibleRenderState.value = PdfVisibleRenderState.ready;
        },
        wait: _wait,
        timeout: const Duration(seconds: 1),
      );
      expect(installedPdfTargetReady(controller, 1), true);
    },
  );

  test(
    'navigation waits for a new frame and then the final target image',
    () async {
      final controller = _Controller();
      addTearDown(controller.visibleRenderState.dispose);
      final frame = Completer<void>();
      var completed = false;
      final pending = navigateInstalledPdfTarget(
        controller,
        1,
        nextFrame: () => frame.future,
        wait: _wait,
        timeout: const Duration(seconds: 1),
      ).then((_) => completed = true);
      await Future<void>.delayed(Duration.zero);
      expect(completed, false);
      frame.complete();
      await Future<void>.delayed(Duration.zero);
      expect(completed, false);
      controller.visibleRenderState.value = PdfVisibleRenderState.ready;
      await pending;
      expect(completed, true);
    },
  );

  test('a stalled navigation fails within the operation deadline', () async {
    final controller = _Controller()..stallNavigation = true;
    addTearDown(controller.visibleRenderState.dispose);
    var frameRequested = false;
    await expectLater(
      navigateInstalledPdfTarget(
        controller,
        1,
        nextFrame: () async {
          frameRequested = true;
        },
        wait: _wait,
        timeout: const Duration(milliseconds: 10),
      ),
      throwsA(
        isA<TimeoutException>().having(
          (error) => error.message,
          'navigation stage',
          contains('Navigation to PDF target page 1'),
        ),
      ),
    );
    expect(frameRequested, false);
    controller.incompleteNavigation.complete();
  });

  test('a stalled frame also exhausts the shared deadline', () async {
    final controller = _Controller();
    addTearDown(controller.visibleRenderState.dispose);
    final frame = Completer<void>();
    await expectLater(
      navigateInstalledPdfTarget(
        controller,
        1,
        nextFrame: () => frame.future,
        wait: _wait,
        timeout: const Duration(milliseconds: 10),
      ),
      throwsA(isA<TimeoutException>()),
    );
    frame.complete();
  });
}
