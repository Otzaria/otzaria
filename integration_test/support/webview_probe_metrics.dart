import 'package:otzaria/core/diagnostics/process_tree_sampler.dart';

enum ProbeAvailability { collected, unsupported, unavailable, notRun }

Map<String, Object?> probeMetric({
  required ProbeAvailability availability,
  required String metric,
  required String unit,
  required String scope,
  String? source,
  num? value,
  String? reason,
}) {
  if (availability == ProbeAvailability.collected) {
    if (value == null || !value.isFinite || value < 0 || source == null) {
      throw ArgumentError(
        'Collected metrics require a finite value and source.',
      );
    }
  } else if (value != null || reason == null || reason.isEmpty) {
    throw ArgumentError('Missing metrics require a reason and no value.');
  }
  return {
    'availability': availability.name,
    'metric': metric,
    'unit': unit,
    'scope': scope,
    'source': source,
    'value': value,
    'reason': reason,
  };
}

Map<String, Object?> webViewProbeMemory(
  ProcessTreeSample? sample, {
  required String platform,
  String? error,
}) {
  final supported = platform == 'windows' || platform == 'linux';
  final known = sample != null && sample.metric != ProcessMemoryMetric.unknown;
  final count =
      sample?.webview.values.fold(0, (n, kind) => n + kind.count) ?? 0;
  Map<String, Object?> memory(String scope, int? value) => probeMetric(
    availability: !supported
        ? ProbeAvailability.unsupported
        : known && value != null
        ? ProbeAvailability.collected
        : ProbeAvailability.unavailable,
    metric: sample?.metric.jsonName ?? 'unknown',
    unit: 'MiB',
    scope: scope,
    source: sample?.metric.source,
    value: supported && known ? value : null,
    reason: !supported
        ? 'No in-process WebView process sampler on this platform; use external tools.'
        : value == null || !known
        ? error ?? 'No readable sample with a known memory metric.'
        : null,
  );
  return {
    'host': memory('host', sample?.hostPrivMb),
    'engineObserved': memory(
      'observed-readable-engine-processes',
      count == 0 ? null : sample?.webviewPrivMb,
    ),
    'observedReadableProcessCount': !supported || !known || count == 0
        ? null
        : count,
    'complete': null,
    'coverage':
        'Exited or unreadable processes may be omitted; an empty list '
        'may mean unavailable enumeration. Process count is not host count.',
    'byKind': {
      if (supported && known)
        for (final entry in sample.webview.entries)
          entry.key: {
            'observedReadableProcessCount': entry.value.count,
            'memoryMiB': entry.value.privMb,
          },
    },
  };
}
