import 'dart:async';
import 'dart:convert';

const installedPluginPlatforms = [
  'windows',
  'macos',
  'linux',
  'android',
  'ios',
];
const installedPluginRequiredPhases = [
  'startup',
  'firstOpen',
  'visibleIdle',
  'stateAndScroll',
  'multipleOpen',
  'hiddenIdle',
  'memoryPressure',
  'restore',
  'protectedControls',
  'countPolicy',
  'agePolicy',
  'storeRestore',
  'backgroundOpen',
  'backgroundIdle',
  'backgroundClose',
  'close',
  'closedIdle',
];

Map<String, Object?> decodeInstalledStoreSnapshot(Object? reply) {
  final value = reply is String ? jsonDecode(reply) : reply;
  // A created WebView can return no result while its document is loading.
  if (value == null) {
    return {'evaluation': 'unavailable', 'sdkBooted': false, 'ready': false};
  }
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw FormatException('Store read did not return a JSON object: $value');
  }
  final snapshot = Map<String, Object?>.from(value);
  if (snapshot['error'] != null) {
    throw StateError('Store JavaScript read failed: $snapshot');
  }
  final document = snapshot['document'];
  final rendering = snapshot['rendering'];
  final missing = snapshot['missingElements'];
  if (snapshot['sdkBooted'] is! bool ||
      snapshot['ready'] is! bool ||
      snapshot['documentToken'] is! String ||
      (snapshot['documentToken'] as String).isEmpty ||
      snapshot['userAgent'] is! String ||
      document is! Map ||
      document['readyState'] is! String ||
      document['url'] is! String ||
      rendering is! Map ||
      !rendering.containsKey('pendingScroll') ||
      missing is! List ||
      missing.any((id) => id is! String)) {
    throw FormatException('Malformed Store readiness snapshot: $snapshot');
  }
  final view = snapshot['view'];
  if (snapshot['ready'] == true &&
      (!{'interactive', 'complete'}.contains(document['readyState']) ||
          missing.isNotEmpty ||
          rendering['pendingScroll'] != null ||
          view is! Map ||
          view['search'] is! String ||
          view['status'] is! String ||
          view['sort'] is! String ||
          view['hideInstalled'] is! bool ||
          view['scrollTop'] is! num ||
          !(view['scrollTop'] as num).isFinite)) {
    throw FormatException('Incomplete ready Store snapshot: $snapshot');
  }
  return snapshot;
}

Future<Map<String, Object?>> waitForInstalledStoreReady({
  required Future<Map<String, Object?>> Function() read,
  required bool Function() hasRestoreState,
  required Duration timeout,
}) async {
  final elapsed = Stopwatch()..start();
  while (true) {
    final value = await read();
    if (value['sdkBooted'] == true &&
        value['ready'] == true &&
        hasRestoreState()) {
      return value;
    }
    if (elapsed.elapsed >= timeout) {
      throw TimeoutException(
        'Unmodified store SDK, catalog and first accepted snapshot: $value',
        timeout,
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

List<String> installedRestoreErrors(Map<String, Object?> proof) {
  final errors = <String>[];
  for (final key in [
    'sameInstanceId',
    'releasedByDispatcher',
    'controllerAbsentAfterDiscard',
    'hostWidgetRemovedBeforeRestore',
    'differentControllerObject',
    'differentDocument',
    'sdkBooted',
    'visibleStateMatches',
  ]) {
    if (proof[key] != true) errors.add('Restore proof requires $key');
  }
  final before = proof['before'];
  final after = proof['after'];
  if (before is! Map || after is! Map) {
    errors.add('Restore proof requires both observed identities');
    return errors;
  }
  for (final key in ['pluginId', 'instanceId']) {
    if (before[key] is! String ||
        (before[key] as String).isEmpty ||
        before[key] != after[key]) {
      errors.add('Restore identity changed or is missing: $key');
    }
  }
  // Native texture IDs can be reused. The controller and document prove recreation.
  for (final key in ['documentToken']) {
    if (before[key] is! String ||
        after[key] is! String ||
        (before[key] as String).isEmpty ||
        (after[key] as String).isEmpty ||
        before[key] == after[key]) {
      errors.add('Restore requires different observed $key values');
    }
  }
  final latency = proof['resumeMs'];
  if (latency is! num || !latency.isFinite || latency < 0) {
    errors.add('Restore requires a measured resume duration');
  }
  return errors;
}

List<String> installedReportErrors(Map<String, Object?> report) {
  final errors = <String>[];
  final phases = report['phases'];
  if (phases is! List) return ['Missing phase records'];
  final byName = <Object?, Map>{};
  for (final phase in phases) {
    if (phase is! Map || byName.containsKey(phase['name'])) {
      errors.add('Invalid or duplicate phase');
    } else {
      byName[phase['name']] = phase;
    }
  }
  for (final name in installedPluginRequiredPhases) {
    if (byName[name]?['status'] != 'passed') {
      errors.add('Required phase did not pass: $name');
    }
  }
  final proofs = report['restorations'];
  if (proofs is! List || proofs.length < 4) {
    errors.add('Missing pressure/count/age/store restoration proofs');
  } else {
    final scenarios = <Object?>{};
    for (final proof in proofs) {
      if (proof is! Map) {
        errors.add('Invalid restoration');
        continue;
      }
      scenarios.add(proof['scenario']);
      errors.addAll(installedRestoreErrors(Map<String, Object?>.from(proof)));
    }
    if (!scenarios.containsAll(['pressure', 'count', 'age', 'store'])) {
      errors.add('Each discard policy and the pinned store must be exercised');
    }
  }
  final guards = report['protectedControls'];
  const reasons = {
    'noRestoreState',
    'unsavedChanges',
    'busyRpc',
    'contextMenu',
  };
  if (guards is! List || guards.length != reasons.length) {
    errors.add('Missing protected negative controls');
  } else {
    final observed = <Object?>{};
    final requests = <Object?>{};
    for (final guard in guards) {
      if (guard is! Map) {
        errors.add('Invalid protected control');
        continue;
      }
      observed.add(guard['firstBlockingReason']);
      requests.add(guard['discardRequestId']);
      if (guard['sameControllerAfterRequest'] != true ||
          guard['released'] != false) {
        errors.add('A protected instance was released');
      }
    }
    if (!observed.containsAll(reasons) ||
        requests.length != 1 ||
        requests.contains(null)) {
      errors.add(
        'First blockers must be observed under the same discard request',
      );
    }
  }
  final quiet = report['quietWindows'];
  if (quiet is! List || quiet.isEmpty) {
    errors.add('Missing quiet-window evidence');
  } else {
    for (final window in quiet) {
      if (window is! Map ||
          window['probeJsCalls'] != 0 ||
          window['probeNativeQueries'] != 0 ||
          window['elapsedMs'] is! num ||
          (window['elapsedMs'] as num) <= 0) {
        errors.add('Quiet window contains probe work or lacks timing');
      }
    }
  }
  if (report['policyRestored'] != true) {
    errors.add('Dispatcher policy override was not restored');
  }
  return errors;
}
