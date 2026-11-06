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
  final collection = !supported
      ? const ProcessCollection(
          status: ProcessCollectionStatus.unsupported,
          reason: 'platform_unsupported',
        )
      : sample?.webviewCollection ??
            ProcessCollection.unavailable(error ?? 'not_collected');
  final observed = supported ? sample?.observedProcessCount : null;
  final measured = supported ? sample?.measuredProcessCount : null;
  final unavailable = supported ? sample?.unavailableProcessCount : null;
  Map<String, Object?> memory(String scope, int? value, {bool engine = false}) {
    final unsupported =
        !supported ||
        engine && collection.status == ProcessCollectionStatus.unsupported;
    final readable =
        known &&
        value != null &&
        (!engine || collection.status == ProcessCollectionStatus.collected);
    return probeMetric(
      availability: unsupported
          ? ProbeAvailability.unsupported
          : readable
          ? ProbeAvailability.collected
          : ProbeAvailability.unavailable,
      metric: sample?.metric.jsonName ?? 'unknown',
      unit: 'MiB',
      scope: scope,
      source: sample?.metric.source,
      value: !unsupported && readable ? value : null,
      reason: unsupported
          ? engine && supported
                ? collection.reason ?? 'process_info_unsupported'
                : 'No in-process WebView process sampler on this platform; use external tools.'
          : !readable
          ? (engine ? collection.reason : null) ??
                error ??
                'No readable sample with a known memory metric.'
          : null,
    );
  }

  return {
    'schemaVersion': 2,
    'host': memory('host', sample?.hostPrivMb),
    'engineObserved': memory(
      'observed-readable-engine-processes',
      sample?.webviewPrivMb,
      engine: true,
    ),
    'webviewCollection': collection.toJson(),
    'observedProcessCount': observed,
    'measuredProcessCount': measured,
    'unavailableProcessCount': unavailable,
    'observedReadableProcessCount': measured,
    'memoryCoverage': supported && known
        ? sample.memoryCoverage.name
        : 'unavailable',
    'complete': null,
    'coverage':
        'Counts describe observed processes, not widget hosts or the complete '
        'engine footprint. Unreadable observations remain counted; memory sums '
        'include only successful reads.',
    'byKind': {
      if (supported && sample != null)
        for (final entry in sample.webview.entries)
          entry.key: {
            'observedProcessCount': entry.value.observedCount,
            'measuredProcessCount': entry.value.measuredCount,
            'unavailableProcessCount': entry.value.unavailableCount,
            'observedReadableProcessCount': entry.value.measuredCount,
            'memoryMiB': known ? entry.value.privMb : null,
            'memoryCoverage': known
                ? entry.value.memoryCoverage.name
                : 'unavailable',
            'eachMbTruncated': entry.value.eachMbTruncated,
            'measuredPageCount': entry.value.measuredPageCount,
            'pagesTruncated': entry.value.pagesTruncated,
          },
    },
  };
}
