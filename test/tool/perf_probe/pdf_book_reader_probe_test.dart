import 'dart:async';

import 'package:otzaria/pdf_book/models/pdf_book_render_observation.dart';
import 'package:test/test.dart';

import '../../../integration_test/support/perf_pdf_book_reader.dart';

PdfBookRenderObservation observation({
  bool visible = true,
  bool bookView = true,
  bool layoutReady = true,
  String viewerState = 'ready',
  List<int> visiblePages = const [4, 5],
  bool overlay = false,
  bool turnActive = false,
  bool animating = false,
  int queued = 0,
}) => PdfBookRenderObservation(
  visible: visible,
  bookView: bookView,
  layoutReady: layoutReady,
  viewerState: viewerState,
  visiblePages: visiblePages,
  hasTransitionOverlay: overlay,
  pageTurnActive: turnActive,
  animationRunning: animating,
  queuedTurns: queued,
);

void main() {
  test(
    'ready viewer under an old spread snapshot is not a final book image',
    () async {
      var state = observation(overlay: true, turnActive: true, queued: 1);
      var polls = 0;
      final result = await waitForPdfBookFinalImage(
        pageNumber: 5,
        ownershipIsCurrent: () => true,
        observe: () => state,
        nextFrame: () async {},
        advance: () async {
          polls++;
          state = polls == 1
              ? observation(overlay: true, animating: true)
              : observation();
        },
      );
      expect(polls, 2);
      expect(result.visiblePages, [4, 5]);
      expect(result.hasTransitionOverlay, false);
    },
  );

  test('a ready adjacent spread cannot satisfy the requested target', () async {
    var state = observation(visiblePages: const [2, 3]);
    var polls = 0;
    await waitForPdfBookFinalImage(
      pageNumber: 5,
      ownershipIsCurrent: () => true,
      observe: () => state,
      nextFrame: () async {},
      advance: () async {
        polls++;
        state = observation();
      },
    );
    expect(polls, 1);
  });

  test(
    'one fresh frame is required even when the previous observation was ready',
    () async {
      var frame = false;
      await waitForPdfBookFinalImage(
        pageNumber: 4,
        ownershipIsCurrent: () => true,
        observe: () {
          expect(frame, true);
          return observation();
        },
        nextFrame: () async {
          frame = true;
        },
      );
    },
  );

  test(
    'document replacement cannot complete a stale book measurement',
    () async {
      var current = true;
      await expectLater(
        waitForPdfBookFinalImage(
          pageNumber: 4,
          ownershipIsCurrent: () => current,
          observe: () => observation(overlay: true),
          nextFrame: () async {},
          advance: () async {
            current = false;
          },
        ),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'overlay removal must cross a new frame before readiness completes',
    () async {
      var state = observation(overlay: true);
      var frames = 0;
      var removalPainted = false;
      await waitForPdfBookFinalImage(
        pageNumber: 4,
        ownershipIsCurrent: () => true,
        observe: () => state,
        nextFrame: () async {
          frames++;
          if (frames > 1 && !state.hasTransitionOverlay) removalPainted = true;
        },
        advance: () async => state = observation(),
      );
      expect(removalPainted, true);
      expect(frames, 2);
    },
  );

  test(
    'another turn during the removal frame invalidates a ready candidate',
    () async {
      var state = observation();
      var frames = 0;
      var polls = 0;
      await waitForPdfBookFinalImage(
        pageNumber: 4,
        ownershipIsCurrent: () => true,
        observe: () => state,
        nextFrame: () async {
          frames++;
          if (frames == 2) state = observation(overlay: true, turnActive: true);
        },
        advance: () async {
          polls++;
          state = observation();
        },
      );
      expect(polls, 1);
      expect(frames, 3);
    },
  );

  test('removed and failed screens cannot be recorded as successful', () async {
    for (final state in [null, observation(viewerState: 'failed')]) {
      await expectLater(
        waitForPdfBookFinalImage(
          pageNumber: 4,
          ownershipIsCurrent: () => true,
          observe: () => state,
          nextFrame: () async {},
        ),
        throwsA(isA<StateError>()),
      );
    }
  });

  test('unsettled book layers time out with the last observation', () async {
    await expectLater(
      waitForPdfBookFinalImage(
        pageNumber: 4,
        ownershipIsCurrent: () => true,
        observe: () => observation(overlay: true),
        nextFrame: () async {},
        timeout: const Duration(milliseconds: 5),
      ),
      throwsA(
        isA<TimeoutException>().having(
          (error) => error.message,
          'last observation',
          contains('hasTransitionOverlay: true'),
        ),
      ),
    );
  });

  test('hidden, regular-view and incomplete layouts remain unready', () {
    for (final state in [
      observation(visible: false),
      observation(bookView: false),
      observation(layoutReady: false),
      observation(viewerState: 'loading'),
      observation(visiblePages: const []),
      observation(turnActive: true),
      observation(animating: true),
      observation(queued: 1),
    ]) {
      expect(state.finalImageReadyFor(4), false);
    }
  });

  test('the report endpoint describes live layers without a GPU claim', () {
    final data = observation().toJson();
    expect(data['readinessEndpoint'], 'liveViewerAfterTransitionLayersRemoved');
    expect(data['gpuPresentation'], 'notMeasured');
    expect(data['visiblePages'], [4, 5]);
  });
}
