import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/diagnostics/process_tree_sampler.dart';

void main() {
  const mb = 1 << 20;

  group('buildProcessTreeSample', () {
    test('sums by kind, sorts renderers and skips processes that exited', () {
      final sample = buildProcessTreeSample(
        metric: ProcessMemoryMetric.privateCommit,
        hostBytes: 262 * mb,
        processes: [
          (kind: 'BROWSER', bytes: 61 * mb, page: null),
          (kind: 'RENDERER', bytes: 59 * mb, page: 'p1/index.html'),
          (kind: 'RENDERER', bytes: 70 * mb, page: 'p0/index.html'),
          (kind: 'RENDERER', bytes: null, page: 'gone/index.html'),
          (kind: 'GPU', bytes: 50 * mb, page: null),
        ],
      );

      expect(sample.hostPrivMb, 262);
      expect(sample.webviewPrivMb, 240);
      expect(sample.toJson(ageMs: 5), {
        'metric': 'privateCommit',
        'source': 'GetProcessMemoryInfo.PagefileUsage',
        'unit': 'MiB',
        'ageMs': 5,
        'hostPrivMb': 262,
        'webviewPrivMb': 240,
        'webview': {
          'BROWSER': {'count': 1, 'privMb': 61},
          'RENDERER': {
            'count': 2,
            'privMb': 129,
            'eachMb': [70, 59],
            'pages': [
              {'page': 'p0/index.html', 'mb': 70},
              {'page': 'p1/index.html', 'mb': 59},
            ],
          },
          'GPU': {'count': 1, 'privMb': 50},
        },
      });
    });

    test('keeps at most 12 renderers in the detail', () {
      final sample = buildProcessTreeSample(
        hostBytes: null,
        processes: [
          for (var i = 0; i < 20; i++)
            (kind: 'RENDERER', bytes: (i + 1) * mb, page: null),
        ],
      );
      final renderers = sample.renderers!;
      expect(renderers.count, 20);
      expect(renderers.eachMb, hasLength(12));
      expect(renderers.eachMb.first, 20);
      expect(sample.toJson(), isNot(contains('hostPrivMb')));
    });

    test('without WebView processes only the host is reported', () {
      final sample = buildProcessTreeSample(hostBytes: 10 * mb, processes: []);
      expect(sample.toJson(), {
        'metric': 'unknown',
        'unit': 'MiB',
        'hostPrivMb': 10,
      });
    });

    test('anonymous RSS is labelled explicitly, including host-only samples', () {
      final sample = buildProcessTreeSample(
        metric: ProcessMemoryMetric.anonymousRss,
        hostBytes: 4 * mb,
        processes: [],
      );
      expect(sample.metric, ProcessMemoryMetric.anonymousRss);
      expect(sample.toJson(), {
        'metric': 'anonymousRss',
        'source': '/proc/<pid>/status:RssAnon',
        'unit': 'MiB',
        'hostPrivMb': 4,
      });
    });

    test('missing measurements are not serialized as zero', () {
      final sample = buildProcessTreeSample(
        metric: ProcessMemoryMetric.anonymousRss,
        hostBytes: null,
        processes: [(kind: 'RENDERER', bytes: null, page: null)],
      );
      expect(sample.toJson(), {
        'metric': 'anonymousRss',
        'source': '/proc/<pid>/status:RssAnon',
        'unit': 'MiB',
      });
    });

    test('a measured zero is distinct from a missing measurement', () {
      final sample = buildProcessTreeSample(
        metric: ProcessMemoryMetric.anonymousRss,
        hostBytes: 0,
        processes: [(kind: 'RENDERER', bytes: 0, page: null)],
      );
      expect(sample.toJson()['hostPrivMb'], 0);
      expect(sample.toJson()['webviewPrivMb'], 0);
      expect(sample.renderers!.count, 1);
    });

    test('a manually constructed sample does not assume Windows', () {
      const sample = ProcessTreeSample(hostPrivMb: 1);
      expect(sample.metric, ProcessMemoryMetric.unknown);
      expect(sample.metric.label, 'memory');
      expect(sample.toJson(), {
        'metric': 'unknown',
        'unit': 'MiB',
        'hostPrivMb': 1,
      });
    });
  });

  group('Linux /proc parsing', () {
    test('stat keeps a name with spaces and reads the parent', () {
      expect(
        parseProcStat('4242 (WPE Web Process) S 4000 4242 4000 0 -1'),
        (name: 'WPE Web Process', ppid: 4000),
      );
      expect(parseProcStat('garbage'), isNull);
    });

    test('status reports RssAnon in bytes', () {
      const status =
          'Name:\tWPEWebProcess\nVmRSS:\t  90000 kB\n'
          'RssAnon:\t   61440 kB\nRssFile:\t  28000 kB\n';
      expect(parseRssAnonBytes(status), 61440 * 1024);
      expect(parseRssAnonBytes('Name:\tx\n'), isNull);
    });

    test('WPE kinds, including the truncated network process name', () {
      expect(wpeProcessKind('WPEWebProcess'), 'RENDERER');
      expect(wpeProcessKind('WPENetworkProce'), 'UTILITY');
      expect(wpeProcessKind('WPEGPUProcess'), 'GPU');
      expect(wpeProcessKind('bash'), isNull);
    });
  });

  test(
    'on Windows each listed WebView process is measured with its page',
    () async {
      final sample = await sampleProcessTree(
        webViewProcesses: () async => [
          (kind: 'RENDERER', pid: pid, page: 'p0/index.html'),
          (kind: 'GPU', pid: 0x7ffffff0, page: null),
        ],
      );
      final renderers = sample!.renderers!;
      expect(sample.metric, ProcessMemoryMetric.privateCommit);
      expect(renderers.count, 1);
      expect(renderers.privMb, greaterThan(0));
      expect(renderers.pages.single.page, 'p0/index.html');
      // תהליך שאינו קיים (OpenProcess נכשל) מדולג.
      expect(sample.webview, isNot(contains('GPU')));
    },
    skip: !Platform.isWindows,
  );

  test(
    'on Windows the host is measured without a WebView environment',
    () async {
      final sample = await sampleProcessTree();
      expect(sample!.hostPrivMb, greaterThan(0));
      expect(sample.metric, ProcessMemoryMetric.privateCommit);
      expect(sample.webview, isEmpty);
    },
    skip: !Platform.isWindows,
  );

  test(
    'the Linux sampler identifies anonymous RSS without waking WebViews',
    () async {
      final sample = await sampleProcessTree(
        webViewProcesses: () async => throw StateError('must not be called'),
      );
      expect(sample, isNotNull);
      expect(sample!.metric, ProcessMemoryMetric.anonymousRss);
      expect(sample.toJson()['unit'], 'MiB');
      expect(sample.toJson()['source'], '/proc/<pid>/status:RssAnon');
    },
    skip: !Platform.isLinux,
  );
}
