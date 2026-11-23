const installedPdfDesktopPlatforms = {'linux', 'windows', 'macos'};
const installedPdfRepeatedLifecycleCycles = 50;
// Lifecycle liveness budget for serial software-rendered cycles, not a speed gate.
const installedPdfRepeatedLifecycleTimeout = Duration(minutes: 10);
const installedPdfRepeatedLifecycleStages = [
  'openAndReady',
  'nativeProof',
  'close',
];
const installedPdfDesktopActions = [
  'hide',
  'minimize',
  'resize',
  'switchSecondary',
  'switchPrimary',
  'memoryPressure',
];

bool _number(Object? value) => value is num && value.isFinite;
bool _integer(Object? value, int expected) => value is int && value == expected;
Object? _field(Object? value, String key) => value is Map ? value[key] : null;

bool _bounds(Object? value) =>
    value is Map &&
    ['x', 'y', 'width', 'height'].every((key) => _number(value[key])) &&
    (value['width'] as num) > 0 &&
    (value['height'] as num) > 0;

bool installedPdfWindowBoundsMatch(Object? actual, Object? expected) =>
    _bounds(actual) &&
    _bounds(expected) &&
    ['x', 'y', 'width', 'height'].every(
      (key) => ((actual as Map)[key] - (expected as Map)[key]).abs() <= 2,
    );

bool _window(Object? value) =>
    value is Map &&
    value['source'] == 'window_manager native window queries' &&
    [
      'visible',
      'minimized',
      'maximized',
      'fullScreen',
    ].every((key) => value[key] is bool) &&
    _bounds(value['logicalBounds']);

bool _readyWindow(Object? value) =>
    _window(value) &&
    (value as Map)['visible'] == true &&
    value['minimized'] == false &&
    value['ready'] == true;

bool _interval(Object? value) =>
    value is Map &&
    value['startUs'] is int &&
    value['endUs'] is int &&
    (value['startUs'] as int) >= 0 &&
    (value['endUs'] as int) >= (value['startUs'] as int);

bool _reader(Object? value, int page, String path) =>
    value is Map &&
    value['path'] == path &&
    _integer(value['targetPage'], page) &&
    value['targetCenterVisible'] == true &&
    value['visibleRenderState'] == 'ready' &&
    value['documentUnchanged'] == true &&
    value['navigationIssued'] == false &&
    _number(value['viewWidth']) &&
    (value['viewWidth'] as num) > 0 &&
    _number(value['viewHeight']) &&
    (value['viewHeight'] as num) > 0;

bool _raster(Object? value, int page) {
  const sizes = [(240, 320), (320, 240), (200, 400), (400, 200)];
  return value is Map &&
      _integer(value['page'], page) &&
      _integer(value['width'], sizes[page - 1].$1) &&
      _integer(value['height'], sizes[page - 1].$2) &&
      value['contentPixelsVerified'] == true &&
      value['pixelSha256'] is String &&
      RegExp(r'^[0-9a-f]{64}$').hasMatch(value['pixelSha256'] as String);
}

List<String> installedPdfDesktopErrors(Object? value) {
  if (value is! Map || value['status'] != 'passed') {
    return ['Missing passed native PDF desktop lifecycle'];
  }
  final errors = <String>[];
  if (!_number(value['durationMs']) || (value['durationMs'] as num) < 0) {
    errors.add('Missing desktop lifecycle timing');
  }
  final primary = value['primaryPath'];
  final secondary = value['secondaryPath'];
  if (primary is! String ||
      primary.isEmpty ||
      secondary is! String ||
      secondary.isEmpty ||
      primary == secondary ||
      value['distinctDocuments'] != true ||
      value['secondaryNativeCloseCompleted'] != true ||
      !_integer(value['additionalNativeCloses'], 9)) {
    errors.add(
      'PDF lifecycle requires two distinct real tabs and native close',
    );
  }
  final cohorts = value['tabCohorts'];
  if (cohorts is! List || cohorts.length != 3) {
    errors.add('Missing native PDF tab counts 1, 5 and 10');
  } else {
    for (var i = 0; i < cohorts.length; i++) {
      final count = const [1, 5, 10][i];
      final cohort = cohorts[i];
      final paths = _field(cohort, 'paths');
      if (cohort is! Map ||
          !_integer(cohort['tabCount'], count) ||
          !_integer(cohort['nativeDocumentCount'], count) ||
          paths is! List ||
          paths.length != count ||
          paths.toSet().length != count ||
          paths.any((path) => path is! String || path.isEmpty) ||
          !paths.contains(primary) ||
          primary is! String ||
          !_reader(cohort['primaryReader'], 2, primary)) {
        errors.add('PDF tab cohort $count lacks distinct live documents');
      }
    }
  }
  if (value['memoryPressureSource'] !=
          'flutter/system memoryPressure (synthetic)' ||
      value['memoryPressureAcknowledged'] != true ||
      !_integer(value['documentsRetainedAfterPressure'], 10)) {
    errors.add(
      'Synthetic memory pressure did not preserve all ten PDF documents',
    );
  }
  final original = value['originalWindow'];
  final restored = value['restoredWindow'];
  if (!_window(original) ||
      !_window(restored) ||
      ![
        'visible',
        'minimized',
        'maximized',
        'fullScreen',
      ].every((key) => (original as Map)[key] == (restored as Map)[key]) ||
      !installedPdfWindowBoundsMatch(
        (original as Map)['logicalBounds'],
        (restored as Map)['logicalBounds'],
      ) ||
      value['windowRestored'] != true) {
    errors.add('Original native window bounds and flags were not restored');
  }
  final actions = value['actions'];
  if (actions is! List || actions.length != installedPdfDesktopActions.length) {
    errors.add('Missing PDF desktop transitions');
    return errors;
  }
  for (var i = 0; i < actions.length; i++) {
    final action = actions[i];
    final name = installedPdfDesktopActions[i];
    if (action is! Map ||
        action['name'] != name ||
        action['status'] != 'passed') {
      errors.add('PDF desktop transition missing or out of order: $name');
      continue;
    }
    final page = name == 'switchSecondary' ? 3 : 2;
    final path = name == 'switchSecondary' ? secondary : primary;
    if (!_readyWindow(action['beforeWindow']) ||
        !_readyWindow(action['afterWindow']) ||
        path is! String ||
        !_reader(action['reader'], page, path)) {
      errors.add('PDF content did not recover without navigation after $name');
    }
    final acknowledgement = action['nativeAcknowledgement'];
    if (!_window(acknowledgement) ||
        (name == 'hide' && (acknowledgement as Map)['visible'] != false) ||
        (name == 'minimize' && (acknowledgement as Map)['minimized'] != true)) {
      errors.add('Missing native acknowledgement for $name');
    }
    if (name == 'resize' &&
        (!installedPdfWindowBoundsMatch(
              _field(acknowledgement, 'logicalBounds'),
              action['requestedBounds'],
            ) ||
            installedPdfWindowBoundsMatch(
              _field(action['beforeWindow'], 'logicalBounds'),
              action['requestedBounds'],
            ))) {
      errors.add('PDF window resize did not change to the requested bounds');
    }
    if (name == 'resize') {
      final beforeReader = _field(actions[i - 1], 'reader');
      if (!['viewWidth', 'viewHeight'].every((axis) {
        final before = _field(beforeReader, axis);
        final after = _field(action['reader'], axis);
        return _number(before) &&
            _number(after) &&
            (after as num) < (before as num);
      })) {
        errors.add(
          'PDF reader viewport did not shrink after the native resize',
        );
      }
    }
    final activity = action['activity'];
    final transition = action['transition'];
    if (!_interval(activity) ||
        !_interval(transition) ||
        (activity as Map)['startUs'] > (transition as Map)['startUs'] ||
        activity['endUs'] < transition['startUs'] ||
        transition['endUs'] < activity['startUs']) {
      errors.add('No overlapping submitted native raster work for $name');
    }
    final raster = activity is Map ? activity['raster'] : null;
    if (!_raster(raster, 1)) {
      errors.add('Native activity raster did not verify its pixels for $name');
    }
  }
  if (primary is! String || !_reader(value['restoredReader'], 2, primary)) {
    errors.add('The primary PDF did not remain ready after window restoration');
  }
  return errors;
}

List<String> installedPdfRepeatedLifecycleErrors(Object? value) {
  if (value is! Map ||
      value['status'] != 'passed' ||
      !_integer(value['requiredCycles'], installedPdfRepeatedLifecycleCycles) ||
      !_integer(
        value['completedCycles'],
        installedPdfRepeatedLifecycleCycles,
      ) ||
      !_integer(
        value['deadlineSeconds'],
        installedPdfRepeatedLifecycleTimeout.inSeconds,
      ) ||
      !_number(value['cyclesElapsedMs']) ||
      (value['cyclesElapsedMs'] as num) < 0 ||
      (value['cyclesElapsedMs'] as num) >=
          installedPdfRepeatedLifecycleTimeout.inMilliseconds) {
    return ['Missing fifty completed native PDF open/render/close cycles'];
  }
  final cycles = value['cycles'];
  if (cycles is! List || cycles.length != installedPdfRepeatedLifecycleCycles) {
    return ['Missing native PDF cycle receipts'];
  }
  final errors = <String>[];
  var cyclesDurationMs = 0.0;
  for (var i = 0; i < cycles.length; i++) {
    final cycle = cycles[i];
    final page = i % 4 + 1;
    if (cycle is! Map ||
        !_integer(cycle['cycle'], i + 1) ||
        !_integer(cycle['targetPage'], page) ||
        cycle['differentDocument'] != true ||
        cycle['visibleRenderState'] != 'ready' ||
        cycle['targetCenterVisible'] != true ||
        !_raster(cycle['raster'], page) ||
        cycle['nativeCloseCompleted'] != true ||
        !_integer(cycle['ownedTabsRemaining'], 0) ||
        !_number(cycle['durationMs']) ||
        (cycle['durationMs'] as num) < 0 ||
        !_cycleTimings(cycle['stageDurationMs'], cycle['durationMs'] as num)) {
      errors.add(
        'Native PDF cycle ${i + 1} lacks content or completed teardown',
      );
    } else {
      cyclesDurationMs += cycle['durationMs'] as num;
    }
  }
  if (cyclesDurationMs > (value['cyclesElapsedMs'] as num) + 0.001) {
    errors.add('Native PDF cycles exceed their reported wall duration');
  }
  return errors;
}

bool _cycleTimings(Object? value, num durationMs) {
  if (value is! Map) return false;
  var total = 0.0;
  for (final stage in installedPdfRepeatedLifecycleStages) {
    final duration = value[stage];
    if (duration is! num || !duration.isFinite || duration < 0) return false;
    total += duration;
  }
  return total <= durationMs + 0.001;
}
