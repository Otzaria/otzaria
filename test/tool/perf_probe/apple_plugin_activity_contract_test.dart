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
  Map<String, dynamic>? driver,
  int armStartMs = 1000,
  int armEndMs = 1020,
}) => analyzeAppleQuietWindow(
  before: before ?? snapshot(readWall: 900, readMono: 900),
  after: after,
  driver:
      driver ??
      {
        'quietStartMs': 2000,
        'quietEndMs': 10000,
        'quietElapsedMs': 8000,
        'armReceivedMs': 1005,
        'armReplyMs': 1010,
      },
  armStartMs: armStartMs,
  armEndMs: armEndMs,
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
      expect(report['deviceToDriverOffsetMs'], {'min': -12.0, 'max': 6.0});
    },
  );

  test('frozen iOS arm exchange excludes the measured server delay', () {
    const send = 1794027539655;
    final report = analyze(
      snapshot(
        callbacks: [send + 5000],
        readWall: send + 30000,
        readMono: send + 30000,
      ),
      before: snapshot(readWall: send - 1000, readMono: send - 1000),
      armStartMs: send,
      armEndMs: 1794027540303,
      driver: {
        'quietStartMs': send + 1000,
        'quietEndMs': send + 21000,
        'quietElapsedMs': 20000,
        'armReceivedMs': 1794027539707.806,
        'armReplyMs': 1794027540224.722,
      },
    );
    final offset = report['deviceToDriverOffsetMs'] as Map;
    expect(offset['min'], closeTo(-80.278076171875, 0.000001));
    expect(offset['max'], closeTo(53.805908203125, 0.000001));
    expect(report['clockUncertaintyMs'], closeTo(134.083984375, 0.000001));
    expect(report['clockStable'], true);
    expect(report['edgeGuardMs'], 1000);
    expect(report['clockToleranceMs'], 250);
    for (final stream in (report['streams'] as Map).values.cast<Map>()) {
      expect(stream['classification'], 'callbacksObservedInsideQuiet');
      expect(stream['callbacksInsideQuiet'], 1);
    }
  });

  test('causal bounds preserve asymmetric latency and either offset sign', () {
    for (final offset in [-100000, 0, 100000]) {
      for (final outward in [10, 90]) {
        for (final processing in [0, 500, 5000]) {
          final report = analyze(
            snapshot(callbacks: [15000], readWall: 22000, readMono: 22000),
            armEndMs: 1100 + processing,
            driver: {
              'quietStartMs': 12000 + offset,
              'quietEndMs': 20000 + offset,
              'quietElapsedMs': 8000,
              'armReceivedMs': 1000 + outward + offset,
              'armReplyMs': 1000 + outward + processing + offset,
            },
          );
          expect(report['deviceToDriverOffsetMs'], {
            'min': offset - (100 - outward) - 2.0,
            'max': offset + outward + 1.0,
          });
          expect(report['clockUncertaintyMs'], 103);
          expect(report['clockStable'], true);
          expect(
            ((report['streams'] as Map)['interval']
                as Map)['callbacksInsideQuiet'],
            1,
          );
        }
      }
    }
  });

  test(
    'integer client bins and fractional host margins retain possible offsets',
    () {
      const offset = 125.5;
      // Actual client send/receive are 1000.1/1000.9. Host samples at
      // 1125.7/1126.3 are perturbed by opposite 0.999ms representation errors.
      final report = analyze(
        snapshot(callbacks: [4000]),
        armEndMs: 1000,
        driver: {
          'quietStartMs': 2000 + offset,
          'quietEndMs': 10000 + offset,
          'quietElapsedMs': 8000,
          'armReceivedMs': 1124.701,
          'armReplyMs': 1127.299,
        },
      );
      final bounds = report['deviceToDriverOffsetMs'] as Map;
      expect(bounds['min'], closeTo(125.299, 0.000001));
      expect(bounds['max'], closeTo(125.701, 0.000001));
      expect(bounds['min'] as num, lessThanOrEqualTo(offset));
      expect(bounds['max'] as num, greaterThanOrEqualTo(offset));
      expect(report['clockStable'], true);
      expect(report['integerTimestampBinMs'], 1);
      expect(report['fractionalTimestampMarginMs'], 1);
    },
  );

  test('callback millisecond bins remain outside both guarded edges', () {
    final report = analyze(
      snapshot(callbacks: [3013, 3014, 8991, 8992, 10012, 10013]),
    );
    for (final stream in (report['streams'] as Map).values.cast<Map>()) {
      expect(stream['callbacksInsideQuiet'], 2);
      expect(stream['callbacksAtUncertainEdges'], 3);
      expect(stream['callbacksAfterQuiet'], 1);
    }
  });

  test('late-read validation includes both timestamp envelopes', () {
    expect(
      analyze(snapshot(readWall: 9992, readMono: 9992))['clockStable'],
      true,
    );
    expect(
      () => analyze(snapshot(readWall: 9991, readMono: 9991)),
      throwsStateError,
    );
  });

  for (final width in [999, 1000, 1001]) {
    test('the clock uncertainty threshold remains 1000ms ($width)', () {
      final report = analyze(
        snapshot(callbacks: [4000]),
        armEndMs: width + 1002,
      );
      expect(report['clockUncertaintyMs'], width);
      expect(report['clockStable'], width <= 1000);
      for (final stream in (report['streams'] as Map).values.cast<Map>()) {
        expect(
          stream['classification'],
          width <= 1000 ? 'callbacksObservedInsideQuiet' : 'clockUncertain',
        );
        expect(stream['callbacksInsideQuiet'], width <= 1000 ? 1 : null);
      }
    });
  }

  test(
    'causally impossible exchanges and reversed boundaries are rejected',
    () {
      final driver = <String, dynamic>{
        'quietStartMs': 2000,
        'quietEndMs': 10000,
        'quietElapsedMs': 8000,
        'armReceivedMs': 1005,
        'armReplyMs': 1010,
      };
      for (final changed in [
        {'armReplyMs': 1030},
        {'armReceivedMs': 1011},
        {'armReplyMs': 2001},
        {'quietEndMs': 2000},
        {'quietElapsedMs': 0},
      ]) {
        expect(
          () => analyze(snapshot(), driver: {...driver, ...changed}),
          throwsStateError,
          reason: changed.toString(),
        );
      }
      expect(
        () => analyze(snapshot(), armEndMs: 999),
        throwsStateError,
      );
      expect(
        analyze(
          snapshot(),
          driver: {...driver, 'armReplyMs': 1028},
        )['clockUncertaintyMs'],
        0,
      );
      expect(
        () => analyze(snapshot(), driver: {...driver, 'armReplyMs': 1028.001}),
        throwsStateError,
      );
    },
  );

  test(
    'nonfinite coordination times and page anchors cannot certify a window',
    () {
      final driver = <String, dynamic>{
        'quietStartMs': 2000,
        'quietEndMs': 10000,
        'quietElapsedMs': 8000,
        'armReceivedMs': 1005,
        'armReplyMs': 1010,
      };
      for (final invalid in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        for (final key in driver.keys) {
          expect(
            () => analyze(snapshot(), driver: {...driver, key: invalid}),
            throwsStateError,
            reason: key,
          );
        }
        for (final key in ['wallMs', 'monoMs']) {
          final before = snapshot(readWall: 900, readMono: 900);
          before['readAt'] = <String, dynamic>{
            ...(before['readAt'] as Map),
            key: invalid,
          };
          expect(() => analyze(snapshot(), before: before), throwsStateError);
          final after = snapshot();
          after['readAt'] = <String, dynamic>{
            ...(after['readAt'] as Map),
            key: invalid,
          };
          expect(() => analyze(after), throwsStateError);
        }
      }
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
      expect(report['clockUncertaintyMs'], 18);
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
