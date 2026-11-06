import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/diagnostics/process_tree_sampler.dart';

void main() {
  const mb = 1 << 20;

  group('buildProcessTreeSample', () {
    test('sums all readable observations and retains unreadable counts', () {
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
      final json = jsonDecode(jsonEncode(sample.toJson(ageMs: 5))) as Map;
      expect(json['schemaVersion'], 2);
      expect(json['metric'], 'privateCommit');
      expect(json['source'], 'GetProcessMemoryInfo.PagefileUsage');
      expect(json['unit'], 'MiB');
      expect(json['ageMs'], 5);
      expect(json['hostPrivMb'], 262);
      expect(json['hostMemoryStatus'], 'collected');
      expect(json['webviewCollection'], {
        'status': 'collected',
        'partial': null,
      });
      expect(json['observedProcessCount'], 5);
      expect(json['measuredProcessCount'], 4);
      expect(json['unavailableProcessCount'], 1);
      expect(json['memoryCoverage'], 'partial');
      expect(json['engineComplete'], isNull);
      expect(json['webviewPrivMb'], 240);
      final kinds = json['webview'] as Map;
      expect(kinds.keys, ['BROWSER', 'RENDERER', 'GPU']);
      expect(kinds['BROWSER']['privMb'], 61);
      expect(kinds['GPU']['privMb'], 50);
      expect(kinds['RENDERER'], {
        'count': 2,
        'observedCount': 3,
        'measuredCount': 2,
        'unavailableCount': 1,
        'memoryCoverage': 'partial',
        'privMb': 129,
        'eachMb': [70, 59],
        'eachMbTruncated': false,
        'measuredPageCount': 2,
        'pagesTruncated': false,
        'pages': [
          {'page': 'p0/index.html', 'mb': 70},
          {'page': 'p1/index.html', 'mb': 59},
        ],
      });
    });

    test(
      'keeps at most 12 renderers in details, with independent page cap',
      () {
        final sample = buildProcessTreeSample(
          hostBytes: null,
          processes: [
            for (var i = 0; i < 20; i++)
              (
                kind: 'RENDERER',
                bytes: (i + 1) * mb,
                page: i < 3 ? 'page$i' : null,
              ),
          ],
        );
        final renderers = sample.renderers!;
        expect(renderers.count, 20);
        expect(renderers.observedCount, 20);
        expect(renderers.eachMb, [
          20,
          19,
          18,
          17,
          16,
          15,
          14,
          13,
          12,
          11,
          10,
          9,
        ]);
        expect(renderers.eachMbTruncated, isTrue);
        expect(renderers.measuredPageCount, 3);
        expect(renderers.pagesTruncated, isFalse);
        expect(renderers.pages.map((p) => p.mb), [3, 2, 1]);
        expect(sample.webviewPrivMb, 210);
        expect(sample.toJson(), isNot(contains('hostPrivMb')));
      },
    );

    test('successful empty enumeration has zero observed, not zero memory', () {
      final sample = buildProcessTreeSample(hostBytes: 10 * mb, processes: []);
      expect(
        sample.webviewCollection.status,
        ProcessCollectionStatus.collected,
      );
      expect(sample.observedProcessCount, 0);
      expect(sample.measuredProcessCount, 0);
      expect(sample.unavailableProcessCount, 0);
      expect(sample.memoryCoverage, ProcessMemoryCoverage.unavailable);
      expect(sample.webviewPrivMb, isNull);
      expect(sample.toJson()['hostPrivMb'], 10);
      expect(sample.toJson(), isNot(contains('webviewPrivMb')));
      expect(sample.toJson()['engineComplete'], isNull);
    });

    test('anonymous RSS stays explicitly labelled in host-only samples', () {
      final sample = buildProcessTreeSample(
        metric: ProcessMemoryMetric.anonymousRss,
        hostBytes: 4 * mb,
        processes: [],
      );
      expect(sample.metric, ProcessMemoryMetric.anonymousRss);
      expect(sample.toJson()['metric'], 'anonymousRss');
      expect(sample.toJson()['source'], '/proc/<pid>/status:RssAnon');
      expect(
        sample.webviewCollection.status,
        ProcessCollectionStatus.collected,
      );
      expect(sample.toJson()['unit'], 'MiB');
      expect(sample.toJson()['hostPrivMb'], 4);
    });

    test('missing measurements are not serialized as zero', () {
      final sample = buildProcessTreeSample(
        metric: ProcessMemoryMetric.anonymousRss,
        hostBytes: null,
        processes: [(kind: 'RENDERER', bytes: null, page: null)],
      );
      final json = sample.toJson();
      expect(json, isNot(contains('hostPrivMb')));
      expect(json, isNot(contains('webviewPrivMb')));
      expect(json['hostMemoryStatus'], 'unavailable');
      expect(sample.renderers!.privMb, isNull);
      expect((json['webview'] as Map)['RENDERER'], isNot(contains('privMb')));
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
      expect(sample.memoryCoverage, ProcessMemoryCoverage.allObserved);
    });

    test(
      'a manually constructed sample assumes neither Windows nor a list',
      () {
        const sample = ProcessTreeSample(hostPrivMb: 1);
        expect(sample.metric, ProcessMemoryMetric.unknown);
        expect(sample.metric.label, 'memory');
        expect(sample.observedProcessCount, isNull);
        expect(sample.measuredProcessCount, isNull);
        expect(sample.webviewPrivMb, isNull);
        expect(sample.toJson()['webviewCollection'], {
          'status': 'unavailable',
          'reason': 'not_collected',
          'partial': null,
        });
      },
    );
  });

  group('Linux /proc parsing', () {
    test('stat keeps a name with spaces and reads the parent', () {
      expect(
        parseProcStat('4242 (WPE Web Process) S 4000 4242 4000 0 -1'),
        (name: 'WPE Web Process', ppid: 4000),
      );
      expect(parseProcStat('garbage'), isNull);
      expect(parseProcStat('4242 (truncated)'), isNull);
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
        webViewProcesses: () async => WebViewProcessSnapshot.collected([
          (kind: 'RENDERER', pid: pid, page: 'p0/index.html'),
          (kind: 'GPU', pid: 0x7ffffff0, page: null),
          (kind: 'UTILITY', pid: null, page: null),
        ]),
      );
      final renderers = sample!.renderers!;
      expect(sample.metric, ProcessMemoryMetric.privateCommit);
      expect(renderers.count, 1);
      expect(renderers.privMb, greaterThan(0));
      expect(renderers.pages.single.page, 'p0/index.html');
      expect(sample.observedProcessCount, 3);
      expect(sample.measuredProcessCount, 1);
      expect(sample.unavailableProcessCount, 2);
      expect(sample.webview['GPU']!.privMb, isNull);
      expect(sample.webview['UTILITY']!.observedCount, 1);
      expect(sample.memoryCoverage, ProcessMemoryCoverage.partial);
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
      expect(
        sample.webviewCollection.status,
        ProcessCollectionStatus.unavailable,
      );
      expect(
        sample.webviewCollection.reason,
        'webview_environment_unavailable',
      );
    },
    skip: !Platform.isWindows,
  );

  test(
    'on Windows an enumeration HRESULT still yields a real host measurement',
    () async {
      final sample = await sampleProcessTree(
        webViewProcesses: () async => throw PlatformException(
          code: 'process_info_collection_failed',
          details: {
            'stage': 'GetProcessExtendedInfos.callback',
            'hresult': -2147467259,
          },
        ),
      );
      expect(sample!.hostPrivMb, greaterThan(0));
      expect(sample.observedProcessCount, isNull);
      expect(sample.webviewPrivMb, isNull);
      expect(sample.webviewCollection.hresult, -2147467259);
      expect(
        sample.webviewCollection.status,
        ProcessCollectionStatus.unavailable,
      );
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
      expect(
        sample.webviewCollection.status,
        ProcessCollectionStatus.collected,
      );
    },
    skip: !Platform.isLinux,
  );
}
