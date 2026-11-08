import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/android_update/bloc/android_update_bloc.dart';
import 'package:otzaria/android_update/bloc/android_update_event.dart';
import 'package:otzaria/android_update/bloc/android_update_state.dart';
import 'package:otzaria/android_update/models/android_update.dart';
import 'package:otzaria/core/foreground_work.dart';

import 'support.dart';

Future<void> drainEvents() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<AndroidUpdateState> nextPhase(
  AndroidUpdateBloc bloc,
  AndroidUpdatePhase phase,
) => bloc.stream
    .firstWhere((state) => state.phase == phase)
    .timeout(
      const Duration(seconds: 3),
    );

Future<AndroidUpdateState> dispatch(
  AndroidUpdateBloc bloc,
  AndroidUpdateEvent event,
  AndroidUpdatePhase phase,
) {
  final result = nextPhase(bloc, phase);
  bloc.add(event);
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeAndroidUpdateRepository repository;
  var allowed = true;
  var due = false;
  var recorded = 0;

  AndroidUpdateBloc createBloc() {
    final bloc = AndroidUpdateBloc(
      repository: repository,
      networkAllowed: () => allowed,
      checkDue: () => due,
      recordSuccessfulCheck: () async => recorded++,
      foregroundWork: ForegroundWork(isAndroid: false),
    );
    addTearDown(bloc.close);
    return bloc;
  }

  setUp(() {
    repository = FakeAndroidUpdateRepository();
    allowed = true;
    due = false;
    recorded = 0;
  });

  test(
    'manual check bypasses frequency; automatic check respects it',
    () async {
      final bloc = createBloc();
      bloc.add(const AndroidUpdateCheck(automatic: true));
      await drainEvents();
      expect(repository.calls, isEmpty);
      await dispatch(
        bloc,
        const AndroidUpdateCheck(),
        AndroidUpdatePhase.available,
      );
      await drainEvents();
      expect(repository.calls, ['checkDirect']);
      expect(recorded, 1);
    },
  );

  test('offline setting blocks both manual check and download', () async {
    final bloc = createBloc();
    await dispatch(
      bloc,
      const AndroidUpdateCheck(),
      AndroidUpdatePhase.available,
    );
    allowed = false;
    await dispatch(
      bloc,
      const AndroidUpdateDownload(),
      AndroidUpdatePhase.failed,
    );
    expect(bloc.state.failure, AndroidUpdateFailure.disabled);
    bloc.add(const AndroidUpdateCheck(automatic: true));
    bloc.add(const AndroidUpdateCheck());
    await drainEvents();
    expect(repository.calls, ['checkDirect']);
  });

  test(
    'verified download waits for user installation and permission',
    () async {
      repository.permission = false;
      repository.permissionAnswer = false;
      final bloc = createBloc();
      await dispatch(
        bloc,
        const AndroidUpdateCheck(),
        AndroidUpdatePhase.available,
      );
      await dispatch(
        bloc,
        const AndroidUpdateDownload(),
        AndroidUpdatePhase.ready,
      );
      expect(repository.calls, isNot(contains('install')));
      await dispatch(
        bloc,
        const AndroidUpdateInstall(),
        AndroidUpdatePhase.failed,
      );
      expect(bloc.state.failure, AndroidUpdateFailure.permissionDenied);
      expect(bloc.state.prepared, same(fakePrepared));
      expect(repository.calls, isNot(contains('install')));

      repository.permissionAnswer = true;
      await dispatch(
        bloc,
        const AndroidUpdateInstall(),
        AndroidUpdatePhase.confirmation,
      );
      expect(repository.calls.where((call) => call == 'permission').length, 2);
      expect(repository.calls.where((call) => call == 'install').length, 1);
      expect(bloc.state.phase, isNot(AndroidUpdatePhase.completed));

      final complete = nextPhase(bloc, AndroidUpdatePhase.completed);
      repository.controller.add(
        const AndroidNativeUpdateStatus(
          stage: 'completed',
          versionCode: 99804,
        ),
      );
      await complete;
    },
  );

  test(
    'cancel waits for downloader cleanup and discards a late result',
    () async {
      final download = Completer<PreparedAndroidUpdate>();
      late AndroidDownloadCancellation cancellation;
      late void Function(int, int) progress;
      repository.downloadAction = (token, onProgress) {
        cancellation = token;
        progress = onProgress;
        return download.future;
      };
      final bloc = createBloc();
      await dispatch(
        bloc,
        const AndroidUpdateCheck(),
        AndroidUpdatePhase.available,
      );
      await dispatch(
        bloc,
        const AndroidUpdateDownload(),
        AndroidUpdatePhase.downloading,
      );
      await dispatch(
        bloc,
        const AndroidUpdateCancel(),
        AndroidUpdatePhase.cancelling,
      );
      expect(cancellation.isCancelled, isTrue);
      bloc.add(const AndroidUpdateDownload());
      await drainEvents();
      expect(repository.calls.where((call) => call == 'download').length, 1);
      final cancelled = nextPhase(bloc, AndroidUpdatePhase.cancelled);
      download.complete(fakePrepared);
      await cancelled;
      progress(4, 4);
      await drainEvents();
      expect(bloc.state.prepared, isNull);
      expect(bloc.state.phase, AndroidUpdatePhase.cancelled);
      expect(repository.calls, contains('discard'));
      expect(repository.calls, isNot(contains('install')));
    },
  );

  test(
    'old installer events cannot unlock or replace an active download',
    () async {
      final download = Completer<PreparedAndroidUpdate>();
      repository.downloadAction = (_, _) => download.future;
      final bloc = createBloc();
      await dispatch(
        bloc,
        const AndroidUpdateCheck(),
        AndroidUpdatePhase.available,
      );
      await dispatch(
        bloc,
        const AndroidUpdateDownload(),
        AndroidUpdatePhase.downloading,
      );
      for (final stage in [
        'failed',
        'cancelled',
        'confirmation',
        'completed',
      ]) {
        repository.controller.add(
          AndroidNativeUpdateStatus(
            stage: stage,
            versionCode: 99804,
          ),
        );
        await drainEvents();
        expect(bloc.state.phase, AndroidUpdatePhase.downloading);
        bloc.add(const AndroidUpdateDownload());
        bloc.add(const AndroidUpdateInstall());
      }
      await drainEvents();
      expect(repository.calls.where((call) => call == 'download').length, 1);
      expect(repository.calls, isNot(contains('install')));
      final ready = nextPhase(bloc, AndroidUpdatePhase.ready);
      download.complete(fakePrepared);
      await ready;
    },
  );

  test(
    'signature failure removes prepared state instead of retrying unsafe APK',
    () async {
      repository.installError = const AndroidUpdateException(
        AndroidUpdateFailure.signatureMismatch,
      );
      final bloc = createBloc();
      await dispatch(
        bloc,
        const AndroidUpdateCheck(),
        AndroidUpdatePhase.available,
      );
      await dispatch(
        bloc,
        const AndroidUpdateDownload(),
        AndroidUpdatePhase.ready,
      );
      await dispatch(
        bloc,
        const AndroidUpdateInstall(),
        AndroidUpdatePhase.failed,
      );
      expect(bloc.state.failure, AndroidUpdateFailure.signatureMismatch);
      expect(bloc.state.prepared, isNull);
      expect(repository.calls, contains('discard'));
    },
  );

  test(
    'interrupted direct install restores verified local APK without network',
    () async {
      repository.native = const AndroidNativeUpdateStatus(
        stage: 'interrupted',
        versionCode: 99804,
      );
      repository.restored = fakePrepared;
      allowed = false;
      final bloc = createBloc();
      await dispatch(
        bloc,
        const AndroidUpdateInitialize(),
        AndroidUpdatePhase.ready,
      );
      expect(bloc.state.prepared, same(fakePrepared));
      expect(repository.calls, ['status', 'restore']);
    },
  );

  test(
    'resume response started before a new install cannot overwrite it',
    () async {
      final resume = Completer<AndroidNativeUpdateStatus>();
      final bloc = createBloc();
      await dispatch(
        bloc,
        const AndroidUpdateCheck(),
        AndroidUpdatePhase.available,
      );
      await dispatch(
        bloc,
        const AndroidUpdateDownload(),
        AndroidUpdatePhase.ready,
      );
      repository.statusAction = () => resume.future;
      bloc.add(const AndroidUpdateResumed());
      await drainEvents();
      await dispatch(
        bloc,
        const AndroidUpdateInstall(),
        AndroidUpdatePhase.confirmation,
      );
      resume.complete(
        const AndroidNativeUpdateStatus(stage: 'failed', versionCode: 99804),
      );
      await drainEvents();
      expect(bloc.state.phase, AndroidUpdatePhase.confirmation);
    },
  );

  test(
    'Play process start restores an update even when check is not due',
    () async {
      repository.appEnvironment = playEnvironment;
      repository.native = const AndroidNativeUpdateStatus(
        stage: 'ready',
        versionCode: 99804,
      );
      final bloc = createBloc();
      await dispatch(
        bloc,
        const AndroidUpdateInitialize(),
        AndroidUpdatePhase.ready,
      );
      expect(repository.calls, ['resume']);
      expect(bloc.state.isPlay, isTrue);
      expect(repository.calls, isNot(contains('completePlay')));
    },
  );

  test('offline Play startup does not contact the store', () async {
    repository.appEnvironment = playEnvironment;
    allowed = false;
    final bloc = createBloc();
    await dispatch(
      bloc,
      const AndroidUpdateInitialize(),
      AndroidUpdatePhase.idle,
    );
    await drainEvents();
    expect(repository.calls, isEmpty);
  });

  test('a Play update with no allowed flow offers store recovery', () async {
    repository.appEnvironment = playEnvironment;
    repository.native = const AndroidNativeUpdateStatus(stage: 'unavailable');
    final bloc = createBloc();
    await dispatch(
      bloc,
      const AndroidUpdateInitialize(),
      AndroidUpdatePhase.failed,
    );
    expect(bloc.state.failure, AndroidUpdateFailure.playUnavailable);
    expect(repository.calls, ['resume']);
  });

  test(
    'Play listener wins over stale start response and completion is explicit',
    () async {
      repository.appEnvironment = playEnvironment;
      repository.native = const AndroidNativeUpdateStatus(
        stage: 'available',
        versionCode: 99804,
      );
      final start = Completer<AndroidNativeUpdateStatus>();
      repository.playStartAction = () => start.future;
      final bloc = createBloc();
      await dispatch(
        bloc,
        const AndroidUpdateInitialize(),
        AndroidUpdatePhase.available,
      );
      await dispatch(
        bloc,
        const AndroidUpdateDownload(),
        AndroidUpdatePhase.installing,
      );
      final ready = nextPhase(bloc, AndroidUpdatePhase.ready);
      repository.controller.add(
        const AndroidNativeUpdateStatus(stage: 'ready', versionCode: 99804),
      );
      await ready;
      start.complete(
        const AndroidNativeUpdateStatus(
          stage: 'confirmation',
          versionCode: 99804,
        ),
      );
      await drainEvents();
      expect(bloc.state.phase, AndroidUpdatePhase.ready);
      expect(repository.calls, ['resume', 'startPlay']);
      await dispatch(
        bloc,
        const AndroidUpdateInstall(),
        AndroidUpdatePhase.installing,
      );
      await drainEvents();
      expect(repository.calls, ['resume', 'startPlay', 'completePlay']);
      expect(bloc.state.phase, isNot(AndroidUpdatePhase.completed));
    },
  );
}
