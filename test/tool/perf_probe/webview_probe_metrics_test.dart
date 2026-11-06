import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/diagnostics/process_tree_sampler.dart';

import '../../../integration_test/support/webview_probe_metrics.dart';

void main() {
  Map<String, Object?> metric(
    ProbeAvailability state, {
    num? value,
    String? reason,
    String? source,
  }) => probeMetric(
    availability: state,
    metric: 'test',
    unit: 'bytes',
    scope: 'host',
    value: value,
    reason: reason,
    source: source,
  );

  test('a measured zero is preserved with its source and unit', () {
    final result = metric(
      ProbeAvailability.collected,
      value: 0,
      source: 'OS API',
    );
    expect(result['value'], 0);
    expect(result['unit'], 'bytes');
    expect(jsonDecode(jsonEncode(result))['availability'], 'collected');
  });

  for (final state in ProbeAvailability.values.where(
    (s) => s != ProbeAvailability.collected,
  )) {
    test('${state.name} never contains a fabricated zero', () {
      final result = metric(state, reason: 'No observation');
      expect(result['value'], isNull);
      expect(result['availability'], state.name);
      expect(
        () => metric(state, value: 0, reason: 'No observation'),
        throwsArgumentError,
      );
      expect(() => metric(state), throwsArgumentError);
    });
  }

  for (final value in <num?>[null, double.nan, double.infinity, -1]) {
    test('rejects invalid collected value $value', () {
      expect(
        () =>
            metric(ProbeAvailability.collected, value: value, source: 'OS API'),
        throwsArgumentError,
      );
    });
  }
  test('a collected value requires a measurement source', () {
    expect(
      () => metric(ProbeAvailability.collected, value: 1),
      throwsArgumentError,
    );
  });

  for (final platform in ['android', 'ios', 'macos']) {
    test('$platform declares process sampling unsupported', () {
      final result = webViewProbeMemory(null, platform: platform);
      expect((result['host'] as Map)['availability'], 'unsupported');
      expect((result['engineObserved'] as Map)['value'], isNull);
      expect(result['complete'], isNull);
      expect(result['observedReadableProcessCount'], isNull);
    });
  }

  for (final platform in ['windows', 'linux']) {
    test('$platform keeps sampler failure distinct from unsupported', () {
      final result = webViewProbeMemory(
        null,
        platform: platform,
        error: 'access denied',
      );
      final host = result['host'] as Map;
      expect(host['availability'], 'unavailable');
      expect(host['reason'], 'access denied');
      expect(host['value'], isNull);
    });
  }

  test('an empty engine enumeration is not zero engine memory', () {
    final result = webViewProbeMemory(
      const ProcessTreeSample(
        metric: ProcessMemoryMetric.privateCommit,
        hostPrivMb: 10,
      ),
      platform: 'windows',
    );
    expect((result['host'] as Map)['value'], 10);
    expect((result['engineObserved'] as Map)['availability'], 'unavailable');
    expect((result['engineObserved'] as Map)['value'], isNull);
    expect(result['observedReadableProcessCount'], isNull);
  });

  test('unknown metrics cannot become comparable memory observations', () {
    final sample = buildProcessTreeSample(
      hostBytes: 100,
      processes: [
        (kind: 'RENDERER', bytes: 100, page: 'synthetic'),
      ],
    );
    final result = webViewProbeMemory(sample, platform: 'linux');
    expect((result['host'] as Map)['availability'], 'unavailable');
    expect((result['engineObserved'] as Map)['value'], isNull);
    expect(result['observedProcessCount'], 1);
    expect(result['observedReadableProcessCount'], 1);
    expect((result['byKind'] as Map)['RENDERER']['memoryMiB'], isNull);
    expect(result['memoryCoverage'], 'unavailable');
  });

  test('commit and anonymous RSS retain distinct labels and sources', () {
    final windows = webViewProbeMemory(
      const ProcessTreeSample(
        metric: ProcessMemoryMetric.privateCommit,
        hostPrivMb: 20,
      ),
      platform: 'windows',
    );
    final linux = webViewProbeMemory(
      const ProcessTreeSample(
        metric: ProcessMemoryMetric.anonymousRss,
        hostPrivMb: 20,
      ),
      platform: 'linux',
    );
    final commit = windows['host'] as Map;
    final rss = linux['host'] as Map;
    expect(commit['metric'], 'privateCommit');
    expect(rss['metric'], 'anonymousRss');
    expect(commit['source'], isNot(rss['source']));
    expect(commit['unit'], 'MiB');
    expect(rss['unit'], 'MiB');
  });

  test(
    'readable aggregates neither use capped detail nor claim completeness',
    () {
      final sample = buildProcessTreeSample(
        metric: ProcessMemoryMetric.privateCommit,
        hostBytes: null,
        processes: [
          for (var i = 0; i < 20; i++)
            (kind: 'RENDERER', bytes: 1 << 20, page: 'p$i'),
          (kind: 'RENDERER', bytes: null, page: 'unreadable'),
        ],
      );
      expect(sample.renderers!.eachMb, hasLength(12));
      final result = webViewProbeMemory(sample, platform: 'windows');
      expect(result['observedReadableProcessCount'], 20);
      expect(result['observedProcessCount'], 21);
      expect(result['measuredProcessCount'], 20);
      expect(result['unavailableProcessCount'], 1);
      expect(result['memoryCoverage'], 'partial');
      expect((result['engineObserved'] as Map)['value'], 20);
      expect((result['host'] as Map)['availability'], 'unavailable');
      expect(result['complete'], isNull);
      expect(result['coverage'], contains('Unreadable'));
      expect(jsonEncode(result), isNot(contains('p19')));
    },
  );

  test(
    'explicit empty enumeration exposes zero observations but no memory',
    () {
      final result = webViewProbeMemory(
        buildProcessTreeSample(
          metric: ProcessMemoryMetric.anonymousRss,
          hostBytes: 8 << 20,
          processes: [],
        ),
        platform: 'linux',
      );
      expect(result['observedProcessCount'], 0);
      expect(result['measuredProcessCount'], 0);
      expect(result['unavailableProcessCount'], 0);
      expect((result['webviewCollection'] as Map)['status'], 'collected');
      expect((result['engineObserved'] as Map)['availability'], 'unavailable');
      expect((result['engineObserved'] as Map)['value'], isNull);
      expect(result['complete'], isNull);
    },
  );

  test('engine source failure preserves host and signed HRESULT metadata', () {
    for (final status in [
      ProcessCollectionStatus.unsupported,
      ProcessCollectionStatus.unavailable,
    ]) {
      final result = webViewProbeMemory(
        ProcessTreeSample(
          metric: ProcessMemoryMetric.privateCommit,
          hostPrivMb: 8,
          webviewCollection: ProcessCollection(
            status: status,
            reason: status == ProcessCollectionStatus.unsupported
                ? 'process_info_unsupported'
                : 'process_info_collection_failed',
            stage: 'GetProcessExtendedInfos.callback',
            hresult: -2147467259,
          ),
        ),
        platform: 'windows',
      );
      expect((result['host'] as Map)['availability'], 'collected');
      expect((result['host'] as Map)['value'], 8);
      expect((result['engineObserved'] as Map)['availability'], status.name);
      expect((result['engineObserved'] as Map)['value'], isNull);
      expect(result['observedProcessCount'], isNull);
      expect(result['measuredProcessCount'], isNull);
      expect((result['webviewCollection'] as Map)['hresult'], -2147467259);
    }
  });

  test('all unreadable observations stay counted without a memory value', () {
    final result = webViewProbeMemory(
      buildProcessTreeSample(
        metric: ProcessMemoryMetric.privateCommit,
        hostBytes: null,
        processes: [(kind: 'RENDERER', bytes: null, page: 'missing')],
      ),
      platform: 'windows',
    );
    expect(result['observedProcessCount'], 1);
    expect(result['measuredProcessCount'], 0);
    expect(result['unavailableProcessCount'], 1);
    expect((result['engineObserved'] as Map)['value'], isNull);
    expect((result['byKind'] as Map)['RENDERER']['memoryMiB'], isNull);
    expect(jsonEncode(result), isNot(contains('missing')));
  });

  test(
    'a measured zero and limited detail remain visible without page labels',
    () {
      final result = webViewProbeMemory(
        buildProcessTreeSample(
          metric: ProcessMemoryMetric.privateCommit,
          hostBytes: 0,
          processes: [
            for (var i = 0; i < 20; i++)
              (kind: 'RENDERER', bytes: 0, page: 'private-page$i'),
          ],
        ),
        platform: 'windows',
      );
      expect((result['engineObserved'] as Map)['value'], 0);
      expect((result['engineObserved'] as Map)['availability'], 'collected');
      expect(result['memoryCoverage'], 'allObserved');
      final kind = (result['byKind'] as Map)['RENDERER'] as Map;
      expect(kind['observedProcessCount'], 20);
      expect(kind['eachMbTruncated'], isTrue);
      expect(kind['measuredPageCount'], 20);
      expect(kind['pagesTruncated'], isTrue);
      expect(jsonEncode(result), isNot(contains('private-page')));
    },
  );
}
