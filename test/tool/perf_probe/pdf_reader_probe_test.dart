import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../integration_test/support/perf_pdf_reader.dart';

class _Page extends Fake implements PdfPage {}

class _Document extends Fake implements PdfDocument {
  @override
  final pages = <PdfPage>[_Page(), _Page()];
}

class _Controller extends Fake implements PdfViewerController {
  @override
  bool isReady = true;
  @override
  PdfDocument document = _Document();
  @override
  final ValueNotifier<PdfVisibleRenderState> visibleRenderState = ValueNotifier(
    PdfVisibleRenderState.ready,
  );
  @override
  Rect visibleRect = const Rect.fromLTWH(0, 0, 100, 100);
  @override
  double currentZoom = 1;
  @override
  final layout = PdfPageLayout(
    pageLayouts: const [
      Rect.fromLTWH(0, 0, 100, 100),
      Rect.fromLTWH(0, 200, 100, 100),
    ],
    documentSize: const Size(100, 300),
  );
}

void main() {
  test(
    'a ready target at the old zoom cannot count as a zoom sample',
    () async {
      final controller = _Controller();
      await expectLater(
        waitForPdfFinalImage(
          controller,
          pageNumber: 1,
          nextFrame: () async {},
          expectedZoom: 1.5,
        ),
        throwsStateError,
      );
      await waitForPdfFinalImage(
        controller,
        pageNumber: 1,
        nextFrame: () async => controller.currentZoom = 1.5,
        expectedZoom: 1.5,
      );
    },
  );

  test(
    'ready from the old viewport cannot finish before the new frame',
    () async {
      final controller = _Controller();
      final frame = Completer<void>();
      final advance = Completer<void>();
      var completed = false;
      final pending = waitForPdfFinalImage(
        controller,
        pageNumber: 2,
        nextFrame: () => frame.future,
        advance: () => advance.future,
      ).then((_) => completed = true);
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);

      controller.visibleRect = controller.layout.pageLayouts[1];
      controller.visibleRenderState.value = PdfVisibleRenderState.pending;
      frame.complete();
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);

      controller.visibleRenderState.value = PdfVisibleRenderState.ready;
      advance.complete();
      await pending;
      expect(completed, isTrue);
    },
  );

  for (final state in [
    PdfVisibleRenderState.failed,
    PdfVisibleRenderState.hidden,
    PdfVisibleRenderState.detached,
  ]) {
    test('$state is an explicit failure', () async {
      final controller = _Controller();
      await expectLater(
        waitForPdfFinalImage(
          controller,
          pageNumber: 1,
          nextFrame: () async => controller.visibleRenderState.value = state,
        ),
        throwsStateError,
      );
    });
  }

  test('replacement document cannot satisfy the old render request', () async {
    final controller = _Controller();
    await expectLater(
      waitForPdfFinalImage(
        controller,
        pageNumber: 1,
        nextFrame: () async => controller.document = _Document(),
      ),
      throwsStateError,
    );
  });

  test('ready for a different page is not a successful navigation', () async {
    await expectLater(
      waitForPdfFinalImage(
        _Controller(),
        pageNumber: 2,
        nextFrame: () async {},
      ),
      throwsStateError,
    );
  });

  test('pending rendering times out instead of producing a sample', () async {
    final controller = _Controller();
    controller.visibleRenderState.value = PdfVisibleRenderState.pending;
    await expectLater(
      waitForPdfFinalImage(
        controller,
        pageNumber: 1,
        nextFrame: () async {},
        timeout: const Duration(milliseconds: 1),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });

  test(
    'a condition deadline also bounds a stalled frame/poll callback',
    () async {
      final stalled = Completer<void>();
      await expectLater(
        waitForPdfProbeCondition(
          () => false,
          'PDF fixture readiness',
          advance: () => stalled.future,
          timeout: const Duration(milliseconds: 1),
        ),
        throwsA(
          isA<TimeoutException>().having(
            (error) => error.message,
            'description',
            contains('PDF fixture readiness'),
          ),
        ),
      );
      stalled.complete();
    },
  );

  test(
    'opening resolves the mounted controller and records two endpoints',
    () async {
      var controller = _Controller()..isReady = false;
      final mounted = _Controller();
      final checkpoints = <String, double>{};
      final frame = Completer<void>();
      final pending = measurePdfReaderOpening(
        open: () => controller = mounted,
        controllerReady: () => controller.isReady,
        controller: () => controller,
        pageNumber: 1,
        nextFrame: () => frame.future,
        checkpointsMs: checkpoints,
      );
      await Future<void>.delayed(Duration.zero);
      expect(checkpoints.keys, ['controller_ready']);
      frame.complete();
      await pending;
      expect(checkpoints.keys, ['controller_ready', 'final_image_ready']);
      expect(checkpoints['controller_ready'], greaterThanOrEqualTo(0));
      expect(
        checkpoints['final_image_ready'],
        greaterThanOrEqualTo(checkpoints['controller_ready']!),
      );
    },
  );

  test('failed opening retains only the observed endpoint', () async {
    final controller = _Controller();
    final checkpoints = <String, double>{};
    await expectLater(
      measurePdfReaderOpening(
        open: () {},
        controllerReady: () => true,
        controller: () => controller,
        pageNumber: 1,
        nextFrame: () async {
          controller.visibleRenderState.value = PdfVisibleRenderState.failed;
        },
        checkpointsMs: checkpoints,
      ),
      throwsStateError,
    );
    expect(checkpoints.keys, ['controller_ready']);
  });

  test(
    'book opening keeps its final checkpoint behind application layers',
    () async {
      final controller = _Controller();
      final layersRemoved = Completer<void>();
      final checkpoints = <String, double>{};
      final pending = measurePdfReaderOpening(
        open: () {},
        controllerReady: () => true,
        controller: () => controller,
        pageNumber: 1,
        nextFrame: () async {},
        checkpointsMs: checkpoints,
        waitForFinalImage: (remaining) {
          expect(remaining, greaterThan(Duration.zero));
          return layersRemoved.future;
        },
      );
      await Future<void>.delayed(Duration.zero);
      expect(checkpoints.keys, ['controller_ready']);
      layersRemoved.complete();
      await pending;
      expect(checkpoints.keys, ['controller_ready', 'final_image_ready']);
    },
  );

  test('a stalled application layer endpoint remains bounded', () async {
    final layersRemoved = Completer<void>();
    final checkpoints = <String, double>{};
    await expectLater(
      measurePdfReaderOpening(
        open: () {},
        controllerReady: () => true,
        controller: _Controller.new,
        pageNumber: 1,
        nextFrame: () async {},
        checkpointsMs: checkpoints,
        timeout: const Duration(milliseconds: 5),
        waitForFinalImage: (_) => layersRemoved.future,
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(checkpoints.keys, ['controller_ready']);
    layersRemoved.complete();
  });
}
