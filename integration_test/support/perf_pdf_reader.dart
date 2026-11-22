import 'dart:async';

import 'package:pdfrx/pdfrx.dart';

/// אותו גבול polling של ה-probe הראשי; timeout הוא כשל ולא דגימה מוצלחת.
Future<void> waitForPdfProbeCondition(
  bool Function() ready,
  String description, {
  Duration timeout = const Duration(seconds: 45),
  Future<void> Function()? advance,
}) async {
  final clock = Stopwatch()..start();
  while (!ready()) {
    final remaining = timeout - clock.elapsed;
    if (remaining <= Duration.zero) {
      throw TimeoutException('Waiting for $description', timeout);
    }
    await (advance?.call() ??
            Future<void>.delayed(const Duration(milliseconds: 16)))
        .timeout(
          remaining,
          onTimeout: () => throw TimeoutException(
            'Waiting for $description',
            timeout,
          ),
        );
  }
}

/// פריים חדש אחרי הניווט מונע קבלת ready של viewport קודם.
/// ready מכסה תמונה ב-layer tree, לא GPU presentation או overlays.
Future<void> waitForPdfFinalImage(
  PdfViewerController controller, {
  required int pageNumber,
  required Future<void> Function() nextFrame,
  double? expectedZoom,
  Duration timeout = const Duration(seconds: 45),
  Future<void> Function()? advance,
}) async {
  final document = controller.isReady ? controller.document : null;
  if (document == null) throw StateError('PDF controller is not ready');
  if (pageNumber < 1 || pageNumber > document.pages.length) {
    throw RangeError.range(pageNumber, 1, document.pages.length, 'pageNumber');
  }
  final clock = Stopwatch()..start();
  await nextFrame().timeout(timeout);
  await waitForPdfProbeCondition(
    () {
      if (!controller.isReady || !identical(controller.document, document)) {
        throw StateError('PDF document changed while waiting for its image');
      }
      final state = controller.visibleRenderState.value;
      if (state == PdfVisibleRenderState.failed ||
          state == PdfVisibleRenderState.hidden ||
          state == PdfVisibleRenderState.detached) {
        throw StateError('PDF visible rendering ended in ${state.name}');
      }
      if (state != PdfVisibleRenderState.ready) return false;
      if (expectedZoom != null &&
          (controller.currentZoom - expectedZoom).abs() > 0.000001) {
        throw StateError(
          'PDF rendered at zoom ${controller.currentZoom}, expected $expectedZoom',
        );
      }
      final page = controller.layout.pageLayouts[pageNumber - 1];
      if (!page.overlaps(controller.visibleRect)) {
        throw StateError('PDF rendered a view without target page $pageNumber');
      }
      return true;
    },
    'final image of PDF page $pageNumber',
    timeout: timeout - clock.elapsed,
    advance: advance,
  );
}

/// שתי נקודות מוכנות מאותה תחילת פתיחה, בתוך phase יחיד. כך דגימת heap
/// והמתנת frame timings של PerfRecorder אינן נכנסות בין שתי המדידות.
Future<void> measurePdfReaderOpening({
  required FutureOr<void> Function() open,
  required bool Function() controllerReady,
  required PdfViewerController Function() controller,
  required int pageNumber,
  required Future<void> Function() nextFrame,
  required Map<String, double> checkpointsMs,
  Duration timeout = const Duration(seconds: 90),
  Future<void> Function()? advance,
}) async {
  final clock = Stopwatch()..start();
  await Future<void>.sync(open).timeout(timeout);
  await waitForPdfProbeCondition(
    controllerReady,
    'PDF controller and reader layout',
    timeout: timeout - clock.elapsed,
    advance: advance,
  );
  checkpointsMs['controller_ready'] = clock.elapsedMicroseconds / 1000;
  await waitForPdfFinalImage(
    controller(),
    pageNumber: pageNumber,
    nextFrame: nextFrame,
    timeout: timeout - clock.elapsed,
    advance: advance,
  );
  checkpointsMs['final_image_ready'] = clock.elapsedMicroseconds / 1000;
}
