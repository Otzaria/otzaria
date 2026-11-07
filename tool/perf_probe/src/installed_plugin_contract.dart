import 'dart:convert';

/// ערך null מה־WebView אינו תצפית מוכנות של מסמך התוסף.
Map<String, Object?> decodeInstalledPluginSnapshot(Object? value) {
  final decoded = value is String ? jsonDecode(value) : value;
  if (decoded == null) return {};
  return Map<String, Object?>.from(decoded as Map);
}

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
