import 'package:flutter_test/flutter_test.dart';

import '../../../tool/perf_probe/apple_plugin_activity/contract.dart';

Map<String, dynamic> snapshot({
  List<int> callbacks = const [],
  int dropped = 0,
  int readWall = 12000,
  int readMono = 12000,
}) => {
  'documentToken': 'document-A',
  'stateCanary': 'local-state-A',
  'timeOrigin': 1,
  'bootCount': 1,
  'phase': 'offstage',
  'ready': true,
  'errors': [],
  'readAt': {'wallMs': readWall, 'monoMs': readMono},
  'streams': {
    for (final name in ['interval', 'raf', 'localAsync'])
      name: {
        'total': callbacks.length + dropped,
        'dropped': dropped,
        'callbacks': [
          for (final t in callbacks) {'wallMs': t, 'monoMs': t},
        ],
      },
  },
};

Map<String, Object?> analyze(
  Map<String, dynamic> after, {
  Map<String, dynamic>? before,
}) => analyzeAppleQuietWindow(
  before: before ?? snapshot(readWall: 900, readMono: 900),
  after: after,
  driver: {
    'quietStartMs': 2000,
    'quietEndMs': 10000,
    'quietElapsedMs': 8000,
    'armReceivedMs': 1005,
    'armReplyMs': 1010,
  },
  armStartMs: 1000,
  armEndMs: 1020,
);

void main() {
  test(
    'queued post-resume callbacks and uncertain edges cannot count as background work',
    () {
      final report = analyze(
        snapshot(callbacks: [1500, 2001, 3999, 10005, 10100]),
      );
      final stream = (report['streams'] as Map)['interval'] as Map;
      expect(stream['callbacksInsideQuiet'], 1);
      expect(stream['callbacksAfterQuiet'], 1);
      expect(stream['callbacksAtUncertainEdges'], 2);
      expect(report['deviceToDriverOffsetMs'], {'min': -15.0, 'max': 10.0});
    },
  );

  test(
    'no callback is an observation, never an engine-suspension assertion',
    () {
      final report = analyze(snapshot(callbacks: [10100, 11000]));
      expect(
        ((report['streams'] as Map)['raf'] as Map)['classification'],
        'noCallbacksObservedInsideQuiet',
      );
      expect(report['engineSuspension'], startsWith('unavailable:'));
    },
  );

  test('dropped callbacks cannot become a zero-progress conclusion', () {
    final report = analyze(snapshot(dropped: 7));
    expect(
      ((report['streams'] as Map)['localAsync'] as Map)['classification'],
      'incompleteCallbackLog',
    );
  });

  test('wall/monotonic disagreement suppresses time-window conclusions', () {
    final report = analyze(snapshot(callbacks: [4000], readMono: 8000));
    final stream = (report['streams'] as Map)['interval'] as Map;
    expect(report['clockStable'], false);
    expect(stream['classification'], 'clockUncertain');
    expect(stream['callbacksInsideQuiet'], null);
  });

  for (final execution in [
    (wall: 4000, mono: 11000),
    (wall: 11000, mono: 4000),
  ]) {
    test('transient callback clock step $execution suppresses all streams', () {
      final after = snapshot(callbacks: [4000], dropped: 7);
      final lastStream = (after['streams'] as Map)['localAsync'] as Map;
      lastStream['callbacks'] = [
        {'wallMs': execution.wall, 'monoMs': execution.mono},
      ];
      final report = analyze(after);
      expect(report['clockStable'], false);
      expect(report['maxCallbackClockDriftMs'], 7000);
      expect(report['clockToleranceMs'], 250);
      expect(report['clockUncertaintyMs'], 25);
      for (final stream in (report['streams'] as Map).values.cast<Map>()) {
        expect(stream['classification'], 'clockUncertain');
        expect(stream['callbacksInsideQuiet'], null);
        expect(stream['callbacksAfterQuiet'], null);
        expect(stream['longestRecordedInteriorGapMs'], null);
        expect(stream['totalSinceArm'], 8);
        expect(stream['dropped'], 7);
      }
      expect(lastStream['callbacks'], [
        {'wallMs': execution.wall, 'monoMs': execution.mono},
      ]);
    });
  }

  test('callback clocks are checked against both read anchors', () {
    final after = snapshot(readWall: 12200);
    for (final stream in (after['streams'] as Map).values.cast<Map>()) {
      stream['total'] = 1;
      stream['callbacks'] = [
        {'wallMs': 3800, 'monoMs': 4000},
      ];
    }
    final report = analyze(after);
    expect(report['deviceWallMinusMonotonicDeltaMs'], 200);
    expect(report['maxCallbackClockDriftMs'], 400);
    expect(report['clockStable'], false);
    expect(
      ((report['streams'] as Map)['interval'] as Map)['callbacksInsideQuiet'],
      null,
    );
  });

  for (final key in [
    'documentToken',
    'stateCanary',
    'timeOrigin',
    'bootCount',
    'phase',
  ]) {
    test(
      'changed $key rejects a relaunch/reload as preserved-state resume',
      () {
        final changed = snapshot()..[key] = 'changed';
        expect(() => analyze(changed), throwsStateError);
      },
    );
  }

  test('inconsistent bounded log fails instead of silently dropping data', () {
    final value = snapshot(callbacks: [4000]);
    ((value['streams'] as Map)['interval'] as Map)['total'] = 12;
    expect(() => analyze(value), throwsStateError);
  });

  test(
    'reading before the declared end cannot be accepted as a quiet window',
    () {
      expect(
        () => analyze(snapshot(readWall: 8000, readMono: 8000)),
        throwsStateError,
      );
    },
  );

  test('callbacks from beyond the snapshot cannot be counted', () {
    expect(() => analyze(snapshot(callbacks: [13000])), throwsStateError);
  });

  test('host/controller identity requires all independent identifiers', () {
    final identity = {
      'hostPid': 12,
      'appBootToken': 'app-A',
      'controllerToken': 1,
    };
    verifyAppleRuntimeIdentity(identity, Map.of(identity));
    for (final field in identity.keys) {
      expect(
        () => verifyAppleRuntimeIdentity(identity, {...identity, field: 'new'}),
        throwsStateError,
      );
      expect(
        () => verifyAppleRuntimeIdentity({...identity, field: null}, identity),
        throwsStateError,
      );
    }
  });

  AppleActivityBoundary boundary() => (
    identity: {
      'hostPid': 12,
      'appBootToken': 'app-A',
      'controllerToken': 1,
    },
    document: snapshot(),
  );

  test('one baseline survives hiding, hidden commands and showing', () {
    final beforeHide = boundary();
    final hidden = boundary();
    final shown = boundary();
    hidden.document['readAt'] = {'wallMs': 13000, 'monoMs': 13000};
    shown.document['readAt'] = {'wallMs': 14000, 'monoMs': 14000};
    shown.document['commands'] = [
      {'nonce': 'command-delivered-while-hidden'},
    ];
    verifyAppleVisibilityRoundTrip(beforeHide, hidden, shown);
  });

  for (final stage in ['hidden', 'shown']) {
    test('a $stage replacement cannot be accepted as a new baseline', () {
      for (final field in [
        'hostPid',
        'appBootToken',
        'controllerToken',
        'documentToken',
        'stateCanary',
        'timeOrigin',
        'bootCount',
        'phase',
      ]) {
        final beforeHide = boundary();
        final hidden = boundary();
        final shown = boundary();
        final changed = stage == 'hidden' ? hidden : shown;
        (changed.identity.containsKey(field)
                ? changed.identity
                : changed.document)[field] =
            'replaced';
        expect(
          () => verifyAppleVisibilityRoundTrip(beforeHide, hidden, shown),
          throwsStateError,
          reason: '$field changed while $stage',
        );
      }
    });
  }
}
