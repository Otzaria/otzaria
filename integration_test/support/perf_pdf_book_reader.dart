import 'dart:async';

import 'package:otzaria/pdf_book/models/pdf_book_render_observation.dart';

import 'perf_probe_wait.dart';

/// ממתין לכפולת היעד אחרי שהצילומים ושכבות הדפדוף של האפליקציה הוסרו.
/// הבדיקה אינה מסיקה חדות של overlay ממוכנות ה-PdfViewer שמתחתיו.
Future<PdfBookRenderObservation> waitForPdfBookFinalImage({
  required int pageNumber,
  required bool Function() ownershipIsCurrent,
  required PdfBookRenderObservation? Function() observe,
  required Future<void> Function() nextFrame,
  Duration timeout = const Duration(seconds: 45),
  Future<void> Function()? advance,
}) async {
  if (pageNumber < 1) throw RangeError.value(pageNumber, 'pageNumber');
  final elapsed = Stopwatch()..start();
  PdfBookRenderObservation? last;
  PdfBookRenderObservation currentObservation() {
    if (!ownershipIsCurrent()) {
      throw StateError('PDF book document changed while waiting for its image');
    }
    final state = last = observe();
    if (state == null) throw StateError('PDF book screen was removed');
    if (state.viewerState == 'failed') {
      throw StateError('PDF book failed to render page $pageNumber');
    }
    return state;
  }

  try {
    await nextFrame().timeout(timeout);
    while (true) {
      await waitForPdfProbeCondition(
        () => currentObservation().finalImageReadyFor(pageNumber),
        'live book image of PDF page $pageNumber after page-turn layers clear',
        timeout: timeout - elapsed.elapsed,
        advance: advance,
      );
      // Fields change before the scheduled frame removes the old overlay from
      // the layer tree. Cross that frame, then recheck in case another turn
      // began during it. The entire loop shares the original deadline.
      await nextFrame().timeout(timeout - elapsed.elapsed);
      final state = currentObservation();
      if (state.finalImageReadyFor(pageNumber)) return state;
    }
  } on TimeoutException catch (error) {
    throw TimeoutException(
      '${error.message}; last observation: ${last?.toJson()}',
      timeout,
    );
  }
}
