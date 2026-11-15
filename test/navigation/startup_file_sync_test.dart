import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library_update/bloc/library_update_bloc.dart';
import 'package:otzaria/navigation/view/startup_work_gate.dart';

void main() {
  group('StartupRefreshWait', () {
    test('רענון שהיה בתנועה אינו משחרר; המאוחד עם מזהה העדכון משחרר', () async {
      final wait = StartupRefreshWait();
      final pending = wait.begin();
      wait.attachRequest(7);
      var finished = false;
      pending.then((_) => finished = true);

      wait.settle(const LibraryState(completedRefreshRequestIds: {3}));
      await pumpEventQueue();
      expect(finished, isFalse);
      expect(wait.requestId, 7);

      wait.settle(const LibraryState(completedRefreshRequestIds: {7, 8}));
      await pending;
      expect(finished, isTrue);
      expect(wait.requestId, isNull);
    });

    test(
      'כשל מסיים את ההמתנה, ופירוק בזמן ריענון בטוח גם בסיום מאוחר',
      () async {
        final wait = StartupRefreshWait();
        final failed = wait.begin();
        wait.attachRequest(11);
        wait.settle(const LibraryState(failedRefreshRequestIds: {11}));
        await failed;
        expect(wait.isPending, isFalse);

        final interrupted = wait.begin();
        wait.attachRequest(12);
        wait.cancel();
        await interrupted;
        wait.settle(const LibraryState(completedRefreshRequestIds: {12}));
        expect(wait.requestId, isNull);
      },
    );
  });

  group('tryStartDeferredStartupWork', () {
    late int backgroundSyncCalls;

    setUp(() => backgroundSyncCalls = 0);

    bool tryStart(StartupWorkGate gate) => tryStartDeferredStartupWork(
      gate: gate,
      startBackgroundSync: () => backgroundSyncCalls++,
    );

    test('מתחיל סנכרון רקע פעם אחת כשהשער נפתח', () {
      final gate = StartupWorkGate();
      gate.markLibraryLoaded();
      gate.markIndexingDecisionResolved(expectIndexing: false);

      expect(tryStart(gate), isTrue);
      expect(tryStart(gate), isFalse);
      expect(backgroundSyncCalls, 1);
    });

    test('לא מתחיל עבודות לפני שהשער נפתח', () {
      expect(tryStart(StartupWorkGate()), isFalse);
      expect(backgroundSyncCalls, 0);
    });
  });

  group('runStartupUpdatesBeforeIndexing', () {
    late List<String> steps;

    setUp(() => steps = []);

    Future<void> run({
      bool shouldCheck = true,
      Future<void> Function()? tourFinished,
      Future<bool> Function()? softwareUpdateAvailable,
    }) => runStartupUpdatesBeforeIndexing(
      shouldCheckLibraryUpdate: () {
        steps.add('shouldCheck');
        return shouldCheck;
      },
      tourFinished: () async {
        steps.add('tour');
        await tourFinished?.call();
      },
      isSoftwareUpdateAvailable: () {
        steps.add('software');
        return softwareUpdateAvailable?.call() ?? Future.value(false);
      },
      runLibraryUpdate: () async => steps.add('library'),
    );

    test('סיור ← תוכנה ← ספרייה', () async {
      await run();
      expect(steps, [
        'shouldCheck',
        'tour',
        'shouldCheck',
        'software',
        'shouldCheck',
        'library',
      ]);
    });

    test('עדכונים כבויים: חוזר מיד, בלי סיור ובלי בדיקת תוכנה', () async {
      await run(shouldCheck: false);
      expect(steps, ['shouldCheck']);
    });

    test('לא מעדכן ספרייה כשזמינה גרסת תוכנה חדשה', () async {
      await run(softwareUpdateAvailable: () => Future.value(true));
      expect(steps, ['shouldCheck', 'tour', 'shouldCheck', 'software']);
    });

    test('ממתין לסוף הסיור לפני בדיקת התוכנה', () async {
      final tour = Completer<void>();
      final done = run(tourFinished: () => tour.future);
      await pumpEventQueue();
      expect(steps, ['shouldCheck', 'tour']);

      tour.complete();
      await done;
      expect(steps.last, 'library');
    });

    test('עדכון הספרייה ממתין לתשובת בדיקת התוכנה', () async {
      final software = Completer<bool>();
      final done = run(softwareUpdateAvailable: () => software.future);
      await pumpEventQueue();
      expect(steps, isNot(contains('library')));

      software.complete(false);
      await done;
      expect(steps.last, 'library');
    });

    test('כיבוי סנכרון בזמן הסיור מבטל את עדכון הספרייה', () async {
      final tour = Completer<void>();
      var enabled = true;
      final done = runStartupUpdatesBeforeIndexing(
        shouldCheckLibraryUpdate: () => enabled,
        tourFinished: () => tour.future,
        isSoftwareUpdateAvailable: () async {
          steps.add('software');
          return false;
        },
        runLibraryUpdate: () async => steps.add('library'),
      );
      await pumpEventQueue();
      enabled = false;
      tour.complete();
      await done;
      expect(steps, isEmpty);
    });

    test('כיבוי סנכרון בזמן בדיקת התוכנה מבטל את עדכון הספרייה', () async {
      final software = Completer<bool>();
      var enabled = true;
      var libraryUpdated = false;
      final done = runStartupUpdatesBeforeIndexing(
        shouldCheckLibraryUpdate: () => enabled,
        tourFinished: () async {},
        isSoftwareUpdateAvailable: () => software.future,
        runLibraryUpdate: () async => libraryUpdated = true,
      );
      await pumpEventQueue();
      enabled = false;
      software.complete(false);
      await done;
      expect(libraryUpdated, isFalse);
    });
  });

  group('runStartupIndexingSequence', () {
    test('כשל בהחלטת אינדוקס נרשם, פותח שער וממשיך לעדכון', () async {
      final gate = StartupWorkGate();
      final errors = <Object>[];
      var updated = false;
      await runStartupIndexingSequence(
        tourActive: true,
        resolveIndexing: () => resolveStartupIndexingNonFatal(
          gate: gate,
          resolve: () => Future<void>.error(StateError('index unavailable')),
          onError: (error, _) => errors.add(error),
        ),
        waitForIndexing: () => gate.indexingSettled,
        runUpdates: () async => updated = true,
      );
      expect(errors.single, isA<StateError>());
      expect(updated, isTrue);
      expect(gate.indexingDecisionResolved, isTrue);
    });

    test('כשל אחרי סימון אינדוקס צפוי אינו תוקע את שער העלייה', () async {
      final gate = StartupWorkGate();
      var updated = false;
      await runStartupIndexingSequence(
        tourActive: true,
        resolveIndexing: () => resolveStartupIndexingNonFatal(
          gate: gate,
          resolve: () async {
            gate.markIndexingDecisionResolved(expectIndexing: true);
            throw StateError('dispatch failed');
          },
          onError: (_, _) {},
        ),
        waitForIndexing: () => gate.indexingSettled,
        runUpdates: () async => updated = true,
      );
      expect(updated, isTrue);
    });

    test('סיור פעיל: אינדוקס ראשון לפני העדכון, וממתין לסיומו', () async {
      final gate = StartupWorkGate()..markLibraryLoaded();
      final tourFinished = Completer<void>();
      final steps = <String>[];
      var indexSettled = false;
      gate.indexingSettled.then((_) => indexSettled = true);
      gate.holdDeferredWork();
      final done = runStartupIndexingSequence(
        tourActive: true,
        resolveIndexing: () async {
          steps.add('index');
          gate.markIndexingDecisionResolved(expectIndexing: true);
        },
        waitForIndexing: () => gate.indexingSettled,
        runUpdates: () async {
          steps.add('waitTour');
          await tourFinished.future;
          steps.add('update');
        },
      );
      await pumpEventQueue();
      expect(steps, ['index']);
      expect(gate.consumeStartPermission(), isFalse);
      // אות סיום של עבודה אחרת אינו משחרר את האינדוקס של העלייה.
      gate.markIndexingRunning(false);
      await pumpEventQueue();
      expect(indexSettled, isFalse);
      gate.markStartupIndexingSettled();
      await pumpEventQueue();
      expect(indexSettled, isTrue);
      expect(steps, ['index', 'waitTour']);
      tourFinished.complete();
      await done;
      gate.releaseDeferredWork();
      expect(steps, ['index', 'waitTour', 'update']);
      expect(gate.consumeStartPermission(), isTrue);
    });

    test('אישור איפוס ידני מחכה לסיום האירוע לפני העדכון', () async {
      final gate = StartupWorkGate();
      final dialog = Completer<void>();
      var updated = false;
      final done = runStartupIndexingSequence(
        tourActive: true,
        resolveIndexing: () async {
          await dialog.future;
          gate.markIndexingDecisionResolved(expectIndexing: true);
        },
        waitForIndexing: () => gate.indexingSettled,
        runUpdates: () async => updated = true,
      );
      await pumpEventQueue();
      expect(updated, isFalse);
      dialog.complete();
      await pumpEventQueue();
      expect(updated, isFalse);
      gate.markStartupIndexingSettled();
      await done;
      expect(updated, isTrue);
    });

    test('עדכון שנכשל עדיין מסיים את הרצף ב-onFinished', () async {
      var finished = false;
      await expectLater(
        runStartupIndexingSequence(
          tourActive: false,
          resolveIndexing: () async => fail('אין אינדוקס אחרי כשל'),
          waitForIndexing: () async {},
          runUpdates: () => Future<void>.error(StateError('update failed')),
          onFinished: () => finished = true,
        ),
        throwsStateError,
      );
      expect(finished, isTrue);
    });

    test('onFinished רץ אחרי האינדוקס שבסוף הרצף', () async {
      final steps = <String>[];
      await runStartupIndexingSequence(
        tourActive: false,
        resolveIndexing: () async => steps.add('index'),
        waitForIndexing: () async {},
        runUpdates: () async => steps.add('update'),
        onFinished: () => steps.add('finished'),
      );
      expect(steps, ['update', 'index', 'finished']);
    });

    test(
      'בלי סיור: חיווי האינדקס מתרענן לפני העדכון ולא מחליף את ההחלטה',
      () async {
        final steps = <String>[];
        await runStartupIndexingSequence(
          tourActive: false,
          previewIndexStatus: () async => steps.add('preview'),
          resolveIndexing: () async => steps.add('index'),
          waitForIndexing: () async => fail('אין המתנה בלי סיור'),
          runUpdates: () async => steps.add('update'),
        );
        expect(steps, ['preview', 'update', 'index']);
      },
    );

    test('כשל ברענון החיווי אינו עוצר את העדכון והאינדוקס (#4461)', () async {
      final steps = <String>[];
      await runStartupIndexingSequence(
        tourActive: false,
        previewIndexStatus: () => Future<void>.error(StateError('no engine')),
        resolveIndexing: () async => steps.add('index'),
        waitForIndexing: () async {},
        runUpdates: () async => steps.add('update'),
      );
      expect(steps, ['update', 'index']);
    });

    test('סיור פעיל: אין רענון חיווי, ההחלטה קודמת לעדכון', () async {
      final gate = StartupWorkGate();
      final steps = <String>[];
      await runStartupIndexingSequence(
        tourActive: true,
        previewIndexStatus: () async => steps.add('preview'),
        resolveIndexing: () async {
          steps.add('index');
          gate.markIndexingDecisionResolved(expectIndexing: false);
        },
        waitForIndexing: () => gate.indexingSettled,
        runUpdates: () async => steps.add('update'),
      );
      expect(steps, ['index', 'update']);
    });

    test('בלי סיור: עדכון הספרייה קודם לאינדוקס', () async {
      final steps = <String>[];
      await runStartupIndexingSequence(
        tourActive: false,
        resolveIndexing: () async => steps.add('index'),
        waitForIndexing: () async => fail('אין המתנה בלי סיור'),
        runUpdates: () async => steps.add('update'),
      );
      expect(steps, ['update', 'index']);
    });
  });

  group('StartupIndexingDeferral', () {
    late ValueNotifier<bool> flag;
    late StreamController<IndexingState> states;
    late StartupIndexingDeferral deferral;

    setUp(() {
      flag = ValueNotifier(true);
      states = StreamController<IndexingState>.broadcast();
      deferral = StartupIndexingDeferral(
        flag,
        startTimeout: const Duration(seconds: 30),
      );
    });

    tearDown(() => states.close());

    test('נשאר דלוק עד שהאינדוקס מתחיל, ואז נכבה ומפסיק להאזין', () {
      fakeAsync((async) {
        deferral.releaseWhenStarted(IndexingInitial(), states.stream);
        async.flushMicrotasks();
        expect(flag.value, isTrue);
        expect(states.hasListener, isTrue);

        states.add(IndexingInitial());
        async.flushMicrotasks();
        expect(flag.value, isTrue);

        states.add(const IndexingInProgress(booksProcessed: 0, totalBooks: 5));
        async.flushMicrotasks();
        expect(flag.value, isFalse);
        expect(states.hasListener, isFalse);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('אינדוקס שלא התחיל אינו משאיר את הסימון דלוק לתמיד', () {
      fakeAsync((async) {
        deferral.releaseWhenStarted(IndexingInitial(), states.stream);
        async.elapse(const Duration(seconds: 29));
        expect(flag.value, isTrue);
        async.elapse(const Duration(seconds: 1));
        expect(flag.value, isFalse);
        expect(states.hasListener, isFalse);
      });
    });

    test('נכבה מיד כשהאינדוקס כבר רץ או שהסתיים', () {
      deferral.releaseWhenStarted(const IndexingComplete(), states.stream);
      expect(flag.value, isFalse);
      expect(states.hasListener, isFalse);
    });

    test('clear מבטל המתנה פתוחה', () {
      fakeAsync((async) {
        deferral.releaseWhenStarted(IndexingInitial(), states.stream);
        deferral.clear();
        async.flushMicrotasks();
        expect(flag.value, isFalse);
        expect(states.hasListener, isFalse);
        expect(async.pendingTimers, isEmpty);
      });
    });
  });

  group('libraryUpdateSettledForIndexing', () {
    bool settled(LibraryUpdateStatus status) =>
        libraryUpdateSettledForIndexing(LibraryUpdateState(status: status));

    test('ממתין בזמן עבודה ובדיאלוג ההורדה המלאה החוסם', () {
      for (final status in [
        LibraryUpdateStatus.checking,
        LibraryUpdateStatus.downloading,
        LibraryUpdateStatus.applying,
        LibraryUpdateStatus.refreshing,
        LibraryUpdateStatus.needsFullConfirmation,
      ]) {
        expect(settled(status), isFalse, reason: status.name);
      }
    });

    test('ממשיך בסיום, בכשל, ובבחירת מסלול שאינה חוסמת', () {
      for (final status in [
        LibraryUpdateStatus.idle,
        LibraryUpdateStatus.completed,
        LibraryUpdateStatus.error,
        LibraryUpdateStatus.disconnected,
        LibraryUpdateStatus.blocked,
        LibraryUpdateStatus.needsRouteChoice,
      ]) {
        expect(settled(status), isTrue, reason: status.name);
      }
    });
  });
}
