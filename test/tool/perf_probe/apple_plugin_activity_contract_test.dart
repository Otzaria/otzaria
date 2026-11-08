import 'dart:convert';

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
  'timeOriginAtBootstrap': 1,
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
  Map<String, dynamic> driver = const {},
}) => analyzeAppleQuietWindow(
  before: before ?? snapshot(readWall: 900, readMono: 900),
  after: after,
  driver: {
    'quietStartMs': 2000,
    'quietEndMs': 10000,
    'quietElapsedMs': 8000,
    'armReceivedMs': 1005,
    'armReplyMs': 1010,
    'driverClockAnchors': {
      'armReply': {'wallMs': 1010, 'monotonicMs': 1010},
      'quietStart': {'wallMs': 2000, 'monotonicMs': 2000},
      'quietEnd': {'wallMs': 10000, 'monotonicMs': 10000},
    },
    ...driver,
  },
  armStartMs: 1000,
  armEndMs: 1020,
);

void main() {
  final settings = <String, Object?>{
    'storeInitialized': true,
    'defaultsInitialized': true,
    'offlineMode': true,
    'updatesEnabled': false,
    'autoUpdateIndex': false,
    'indexUpdateMode': 'off',
    'autoSync': false,
    'appCrashReportMode': 'never',
    'autoBackupFrequency': 'none',
    'showLocalHebrewBooks': false,
    'fontFamily': 'NotoSerifHebrew',
    'fontSize': 22.0,
  };
  test('startup settings audit records the observed fixture values', () {
    final observed = {...settings, 'observedAtMs': 1234};
    final report = analyzeAppleFixtureSettings(observed);
    expect(report['status'], 'passed');
    expect(report['mismatches'], isEmpty);
    expect((jsonDecode(jsonEncode(report)) as Map)['observed'], observed);
  });
  test('missing or changed startup settings cannot pass the fixture audit', () {
    for (final entry in settings.entries) {
      final missing = {...settings}..remove(entry.key);
      final changed = {
        ...settings,
        entry.key: entry.value is bool ? !(entry.value as bool) : 'changed',
      };
      for (final observed in [missing, changed]) {
        final report = analyzeAppleFixtureSettings(observed);
        expect(report['status'], 'failed', reason: entry.key);
        expect(report['mismatches'], contains(entry.key));
        expect(report['observed'], observed);
      }
    }
  });
  test('startup default overwrite remains visible in the failed audit', () {
    final observed = {
      ...settings,
      'updatesEnabled': true,
      'indexUpdateMode': 'all',
      'appCrashReportMode': 'ask',
      'showLocalHebrewBooks': true,
      'fontFamily': 'FrankRuhlCLM',
      'fontSize': 25.0,
    };
    final report = analyzeAppleFixtureSettings(observed);
    expect(report['status'], 'failed');
    expect(
      report['mismatches'],
      unorderedEquals([
        'updatesEnabled',
        'indexUpdateMode',
        'appCrashReportMode',
        'showLocalHebrewBooks',
        'fontFamily',
        'fontSize',
      ]),
    );
    expect((report['observed'] as Map)['offlineMode'], true);
    expect(observed['updatesEnabled'], true);
  });
  for (final platform in ['macos', 'ios']) {
    for (final frameworkPassed in [true, false]) {
      test(
        '$platform final report preserves framework verdict and boolean metadata ($frameworkPassed)',
        () {
          final report = <String, dynamic>{
            'status': 'running',
            'errors': <String>[],
            'platformMatrix': createAppleActivityPlatformMatrix(),
          };
          final failures = frameworkPassed
              ? <String?>[]
              : ['original framework failure', null];
          finalizeAppleActivityReport(
            report,
            frameworkPassed: frameworkPassed,
            failureDetails: failures,
            platform: platform,
            buildMode: 'profile',
          );
          final decoded = jsonDecode(jsonEncode(report)) as Map;
          expect(decoded['status'], frameworkPassed ? 'passed' : 'failed');
          expect(decoded['testFailures'], failures);
          final matrix = decoded['platformMatrix'] as Map;
          expect(matrix[platform], {
            'status': decoded['status'],
            'buildMode': 'profile',
            'physicalDeviceAcceptance': false,
          });
          expect(
            matrix.keys,
            containsAll(['macos', 'ios', 'windows', 'linux', 'android']),
          );
          for (final other in matrix.keys.where((name) => name != platform)) {
            expect(matrix[other]['status'], 'notRun');
          }
        },
      );
    }
  }
  test(
    'final report cannot turn a fixture failure into a framework success',
    () {
      final report = <String, dynamic>{
        'status': 'running',
        'errors': ['original fixture error'],
        'platformMatrix': createAppleActivityPlatformMatrix(),
      };
      finalizeAppleActivityReport(
        report,
        frameworkPassed: true,
        failureDetails: [],
        platform: 'macos',
        buildMode: 'profile',
      );
      expect(report['status'], 'failed');
      expect(report['errors'], ['original fixture error']);
      expect((report['platformMatrix'] as Map)['macos']['status'], 'failed');
    },
  );
  test('unsupported platform completion remains explicitly unsupported', () {
    final report = <String, dynamic>{
      'status': 'notSupported',
      'errors': <String>[],
      'platformMatrix': createAppleActivityPlatformMatrix(),
    };
    finalizeAppleActivityReport(
      report,
      frameworkPassed: true,
      failureDetails: [],
      platform: 'linux',
      buildMode: 'debug',
    );
    expect(report['status'], 'notSupported');
    expect(
      (report['platformMatrix'] as Map)['linux']['physicalDeviceAcceptance'],
      false,
    );
  });
  test('unsupported platform status cannot conceal a framework failure', () {
    final report = <String, dynamic>{
      'status': 'notSupported',
      'errors': <String>[],
      'platformMatrix': createAppleActivityPlatformMatrix(),
    };
    finalizeAppleActivityReport(
      report,
      frameworkPassed: false,
      failureDetails: ['original framework failure'],
      platform: 'linux',
      buildMode: 'debug',
    );
    expect(report['status'], 'failed');
    expect(report['testFailures'], ['original framework failure']);
    expect((report['platformMatrix'] as Map)['linux']['status'], 'failed');
  });

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

  for (final jump in [-10000, 10000]) {
    test(
      'driver clock step between arm and control invalidates every stream ($jump)',
      () {
        final report = analyze(
          snapshot(callbacks: [15000], readWall: 22000, readMono: 22000),
          driver: {
            'platform': 'ios',
            'quietStartMs': 2000 + jump,
            'quietEndMs': 10000 + jump,
            'driverClockAnchors': {
              'armReply': {'wallMs': 1010, 'monotonicMs': 1010},
              'controlReply': {'wallMs': 1100 + jump, 'monotonicMs': 1100},
              'controlResult': {'wallMs': 10100 + jump, 'monotonicMs': 10100},
            },
          },
        );
        expect(report['driverWallMinusMonotonicDeltaMs'], 0);
        expect(report['deviceWallMinusMonotonicDeltaMs'], 0);
        expect(report['clockStable'], false);
        for (final stream in (report['streams'] as Map).values.cast<Map>()) {
          expect(stream['classification'], 'clockUncertain');
          expect(stream['callbacksInsideQuiet'], null);
          expect(stream['callbacksAfterQuiet'], null);
          expect(stream['totalSinceArm'], 1);
        }
        expect(report['driverCoordinationClockDriftMs'], 10000);
      },
    );
  }

  for (final drift in [-251, -250, 250, 251]) {
    test('driver coordination preserves the existing 250ms bound ($drift)', () {
      final report = analyze(
        snapshot(callbacks: [4000]),
        driver: {
          'platform': 'ios',
          'driverClockAnchors': {
            'armReply': {'wallMs': 1010, 'monotonicMs': 1010},
            'controlReply': {'wallMs': 1500 + drift, 'monotonicMs': 1500},
            'controlResult': {'wallMs': 10100 + drift, 'monotonicMs': 10100},
          },
        },
      );
      expect(report['driverCoordinationClockDriftMs'], drift.abs());
      expect(report['clockStable'], drift.abs() <= 250);
    });
  }

  test(
    'missing or reversed driver anchors cannot establish clock stability',
    () {
      for (final anchors in [
        null,
        <String, Object?>{},
        {
          'armReply': {'wallMs': 1010, 'monotonicMs': 1010},
          'quietStart': {'wallMs': 2000, 'monotonicMs': 2000},
        },
        {
          'armReply': {'wallMs': 1010, 'monotonicMs': 1010},
          'quietStart': {'wallMs': 2000, 'monotonicMs': 1000},
          'quietEnd': {'wallMs': 10000, 'monotonicMs': 10000},
        },
      ]) {
        final report = analyze(
          snapshot(callbacks: [4000]),
          driver: {'driverClockAnchors': anchors},
        );
        expect(report['clockStable'], false);
        expect(report['driverCoordinationClockDriftMs'], null);
        expect(report['driverClockAnchorsComplete'], false);
        expect(
          ((report['streams'] as Map)['interval']
              as Map)['callbacksInsideQuiet'],
          null,
        );
      }
    },
  );

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
    'timeOriginAtBootstrap',
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

  test(
    'raw timeOrigin projection changes preserve bootstrap document identity',
    () {
      final before = snapshot(readWall: 900, readMono: 900);
      final after = snapshot()..['timeOrigin'] = 15;
      final report = analyze(after, before: before);
      expect(report['clockStable'], true);
      expect(after['timeOrigin'], 15);
      expect(after['timeOriginAtBootstrap'], before['timeOriginAtBootstrap']);
    },
  );

  for (final field in ['timeOrigin', 'timeOriginAtBootstrap']) {
    test('$field must be present and finite at both document boundaries', () {
      for (final invalid in [
        null,
        double.nan,
        double.infinity,
        -double.infinity,
        '1',
      ]) {
        final bad = snapshot()..[field] = invalid;
        expect(
          () => verifyAppleDocumentIdentity(snapshot(), bad),
          throwsStateError,
        );
        expect(
          () => verifyAppleDocumentIdentity(bad, snapshot()),
          throwsStateError,
        );
      }
      final missing = snapshot()..remove(field);
      expect(
        () => verifyAppleDocumentIdentity(snapshot(), missing),
        throwsStateError,
      );
      expect(
        () => verifyAppleDocumentIdentity(missing, snapshot()),
        throwsStateError,
      );
    });
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
        'timeOriginAtBootstrap',
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
