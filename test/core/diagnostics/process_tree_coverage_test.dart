import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/diagnostics/process_tree_sampler.dart';

void main() {
  const mib = 1 << 20;

  test('failed reads remain observed and the sum has partial coverage', () {
    final sample = buildProcessTreeSample(
      metric: ProcessMemoryMetric.privateCommit,
      hostBytes: 10 * mib,
      processes: [
        (kind: 'RENDERER', bytes: 4 * mib, page: 'readable'),
        (kind: 'RENDERER', bytes: null, page: 'unreadable'),
        (kind: 'GPU', bytes: null, page: null),
      ],
    );
    final json = sample.toJson();
    expect(json['observedProcessCount'], 3);
    expect(json['measuredProcessCount'], 1);
    expect(json['unavailableProcessCount'], 2);
    expect(json['memoryCoverage'], 'partial');
    expect(json['webviewPrivMb'], 4);
    expect((json['webview'] as Map)['GPU'], containsPair('observedCount', 1));
  });

  test('unreadable processes never become a zero memory measurement', () {
    final sample = buildProcessTreeSample(
      hostBytes: null,
      processes: [(kind: 'RENDERER', bytes: null, page: null)],
    );
    expect(sample.webviewPrivMb, isNull);
    expect(sample.toJson()['observedProcessCount'], 1);
    expect(sample.toJson()['measuredProcessCount'], 0);
    expect(sample.toJson()['memoryCoverage'], 'unavailable');
  });

  test('detail limits are explicit and never limit counts or totals', () {
    final sample = buildProcessTreeSample(
      hostBytes: null,
      processes: [
        for (var i = 1; i <= 20; i++)
          (kind: 'RENDERER', bytes: i * mib, page: 'page$i'),
      ],
    );
    final renderer = (sample.toJson()['webview'] as Map)['RENDERER'] as Map;
    expect(renderer['observedCount'], 20);
    expect(renderer['measuredCount'], 20);
    expect(renderer['privMb'], 210);
    expect(renderer['eachMbTruncated'], isTrue);
    expect(renderer['pagesTruncated'], isTrue);
    expect(renderer['measuredPageCount'], 20);
  });

  group('Windows collection and independent host reads', () {
    for (final error in <Object>[
      PlatformException(
        code: 'process_info_collection_failed',
        message: 'Private diagnostic text must not be copied',
        details: {
          'stage': 'GetProcessExtendedInfos.callback',
          'hresult': -2147467259,
          'path': 'private-path',
        },
      ),
      PlatformException(code: 'webview_environment_unavailable'),
      PlatformException(code: 'process_info_unsupported'),
      MissingPluginException('not registered'),
      UnsupportedError('no API'),
      StateError('unexpected collector failure'),
    ]) {
      test('host survives ${error.runtimeType}: $error', () async {
        final reads = <List<int>>[];
        final sample = await sampleWindowsProcessTree(
          webViewProcesses: () async => throw error,
          readBytes: (ids) async {
            reads.add(ids);
            return [40 * mib];
          },
        );
        expect(reads, [
          [pid],
        ]);
        expect(sample.hostPrivMb, 40);
        expect(sample.webviewPrivMb, isNull);
        expect(sample.observedProcessCount, isNull);
        expect(sample.measuredProcessCount, isNull);
        expect(sample.unavailableProcessCount, isNull);
        final unsupported =
            error is UnsupportedError ||
            error is MissingPluginException ||
            error is PlatformException &&
                error.code == 'process_info_unsupported';
        expect(
          sample.webviewCollection.status,
          unsupported
              ? ProcessCollectionStatus.unsupported
              : ProcessCollectionStatus.unavailable,
        );
        final json = jsonEncode(sample.toJson());
        expect(json, isNot(contains('Private diagnostic')));
        expect(json, isNot(contains('private-path')));
        if (error is PlatformException &&
            error.code == 'process_info_collection_failed') {
          expect(
            sample.webviewCollection.stage,
            'GetProcessExtendedInfos.callback',
          );
          expect(sample.webviewCollection.hresult, -2147467259);
        }
      });
    }

    test('native failure stages retain the process collection index', () async {
      for (final stage in [
        'GetProcessInfos.GetValueAtIndex[3]',
        'GetProcessExtendedInfos[7].get_Kind',
      ]) {
        final sample = await sampleWindowsProcessTree(
          webViewProcesses: () async => throw PlatformException(
            code: 'process_info_collection_failed',
            details: {'stage': stage, 'hresult': -2147467259},
          ),
          readBytes: (ids) async => [1 << 20],
        );
        expect(sample.webviewCollection.stage, stage);
        expect(sample.webviewCollection.hresult, -2147467259);
      }
    });

    test(
      'unknown exception metadata is bounded and not copied as prose',
      () async {
        final sample = await sampleWindowsProcessTree(
          webViewProcesses: () async => throw PlatformException(
            code: 'some private error',
            details: {'stage': '/Users/private', 'hresult': 'E_FAIL'},
          ),
          readBytes: (ids) async => [0],
        );
        expect(sample.hostPrivMb, 0);
        expect(
          sample.webviewCollection.reason,
          'process_info_collection_failed',
        );
        expect(sample.webviewCollection.stage, isNull);
        expect(sample.webviewCollection.hresult, isNull);
      },
    );

    test(
      'host read starts before an unanswered enumeration and is preserved',
      () async {
        final pending = Completer<WebViewProcessSnapshot>();
        var hostStarted = false;
        final sample = await sampleWindowsProcessTree(
          webViewProcesses: () {
            expect(hostStarted, isTrue);
            return pending.future;
          },
          readBytes: (ids) async {
            hostStarted = true;
            expect(ids, [pid]);
            return [24 * mib];
          },
          enumerationTimeout: Duration.zero,
        );
        expect(sample.hostPrivMb, 24);
        expect(sample.webviewCollection.reason, 'process_info_timeout');
        expect(sample.observedProcessCount, isNull);
        pending.completeError(StateError('late native failure'));
        await Future<void>.delayed(Duration.zero);
      },
    );

    test(
      'explicit empty and absent environment have different counts',
      () async {
        final empty = await sampleWindowsProcessTree(
          webViewProcesses: () async =>
              const WebViewProcessSnapshot.collected([]),
          readBytes: (ids) async => [8 * mib],
        );
        final absent = await sampleWindowsProcessTree(
          readBytes: (ids) async => [8 * mib],
        );
        expect(empty.observedProcessCount, 0);
        expect(empty.measuredProcessCount, 0);
        expect(
          empty.webviewCollection.status,
          ProcessCollectionStatus.collected,
        );
        expect(absent.observedProcessCount, isNull);
        expect(
          absent.webviewCollection.reason,
          'webview_environment_unavailable',
        );
        for (final sample in [empty, absent]) {
          expect(sample.hostPrivMb, 8);
          expect(sample.webviewPrivMb, isNull);
          expect(sample.toJson()['engineComplete'], isNull);
        }
      },
    );

    test(
      'missing PIDs are observed, never read, and a measured zero survives',
      () async {
        final reads = <List<int>>[];
        final sample = await sampleWindowsProcessTree(
          webViewProcesses: () async => const WebViewProcessSnapshot.collected([
            (kind: 'RENDERER', pid: null, page: 'missing-pid'),
            (kind: 'RENDERER', pid: 42, page: 'zero'),
          ]),
          readBytes: (ids) async {
            reads.add(ids);
            return [for (final id in ids) id == pid ? 4 * mib : 0];
          },
        );
        expect(reads, [
          [pid],
          [42],
        ]);
        expect(sample.observedProcessCount, 2);
        expect(sample.measuredProcessCount, 1);
        expect(sample.unavailableProcessCount, 1);
        expect(sample.webviewPrivMb, 0);
        expect(sample.memoryCoverage, ProcessMemoryCoverage.partial);
        expect(sample.renderers!.pages, [(page: 'zero', mb: 0)]);
      },
    );

    test(
      'host read failure does not suppress readable engine observations',
      () async {
        final sample = await sampleWindowsProcessTree(
          webViewProcesses: () async => const WebViewProcessSnapshot.collected([
            (kind: 'RENDERER', pid: 42, page: null),
          ]),
          readBytes: (ids) async {
            if (ids.single == pid) throw StateError('host unavailable');
            return [3 * mib];
          },
        );
        expect(sample.hostPrivMb, isNull);
        expect(sample.webviewPrivMb, 3);
        expect(sample.measuredProcessCount, 1);
      },
    );

    test('all memory reads may fail after a successful enumeration', () async {
      final sample = await sampleWindowsProcessTree(
        webViewProcesses: () async => const WebViewProcessSnapshot.collected([
          (kind: 'RENDERER', pid: 42, page: 'gone'),
          (kind: 'GPU', pid: 43, page: null),
        ]),
        readBytes: (ids) async => List<int?>.filled(ids.length, null),
      );
      expect(
        sample.webviewCollection.status,
        ProcessCollectionStatus.collected,
      );
      expect(sample.observedProcessCount, 2);
      expect(sample.measuredProcessCount, 0);
      expect(sample.unavailableProcessCount, 2);
      expect(sample.hostPrivMb, isNull);
      expect(sample.webviewPrivMb, isNull);
      expect(sample.renderers!.pages, isEmpty);
      expect(sample.renderers!.eachMbTruncated, isFalse);
    });
  });

  group('Linux source coverage', () {
    late Directory proc;
    setUp(() => proc = Directory.systemTemp.createTempSync('process-coverage'));
    tearDown(() => proc.deleteSync(recursive: true));

    void process(int id, int parent, String name, {int? anonymousKiB}) {
      Directory('${proc.path}/$id').createSync();
      File(
        '${proc.path}/$id/stat',
      ).writeAsStringSync('$id ($name) S $parent 0 0');
      if (anonymousKiB != null) {
        File(
          '${proc.path}/$id/status',
        ).writeAsStringSync('RssAnon:\t$anonymousKiB kB\n');
      }
    }

    test(
      'counts WPE descendants with missing status and reports partial scanning',
      () {
        process(1, 0, 'otzaria', anonymousKiB: 8192);
        process(2, 1, 'WPEWebProcess', anonymousKiB: 4096);
        process(3, 2, 'WPEGPUProcess');
        process(4, 1, 'WPENetworkProce', anonymousKiB: 0);
        process(5, 99, 'WPEWebProcess', anonymousKiB: 99999);
        Directory('${proc.path}/6').createSync();
        final sample = sampleLinuxProcessTree(
          procRoot: proc.path,
          hostProcessId: 1,
        );
        expect(sample.metric, ProcessMemoryMetric.anonymousRss);
        expect(
          sample.webviewCollection.status,
          ProcessCollectionStatus.collected,
        );
        expect(sample.webviewCollection.source, '/proc/<pid>/stat');
        expect(sample.webviewCollection.partial, isTrue);
        expect(sample.hostPrivMb, 8);
        expect(sample.observedProcessCount, 3);
        expect(sample.measuredProcessCount, 2);
        expect(sample.unavailableProcessCount, 1);
        expect(sample.webviewPrivMb, 4);
        expect(sample.webview['GPU']!.privMb, isNull);
        expect(sample.webview['UTILITY']!.privMb, 0);
        expect(sample.memoryCoverage, ProcessMemoryCoverage.partial);
        expect(sample.toJson()['engineComplete'], isNull);
      },
    );

    test(
      'a successful empty scan is observed zero, not complete engine memory',
      () {
        process(1, 0, 'otzaria', anonymousKiB: 1024);
        final sample = sampleLinuxProcessTree(
          procRoot: proc.path,
          hostProcessId: 1,
        );
        expect(sample.webviewCollection.partial, isFalse);
        expect(sample.observedProcessCount, 0);
        expect(sample.webviewPrivMb, isNull);
        expect(sample.hostPrivMb, 1);
        expect(sample.toJson()['engineComplete'], isNull);
      },
    );

    test('malformed process records do not discard available host memory', () {
      process(1, 0, 'otzaria', anonymousKiB: 2048);
      process(2, 1, 'WPEWebProcess', anonymousKiB: 4096);
      File('${proc.path}/2/status').writeAsBytesSync([255]);
      Directory('${proc.path}/3').createSync();
      File('${proc.path}/3/stat').writeAsBytesSync([255]);
      Directory('${proc.path}/4').createSync();
      File('${proc.path}/4/stat').writeAsStringSync('4 (truncated)');
      final sample = sampleLinuxProcessTree(
        procRoot: proc.path,
        hostProcessId: 1,
      );
      expect(sample.hostPrivMb, 2);
      expect(
        sample.webviewCollection.status,
        ProcessCollectionStatus.collected,
      );
      expect(sample.webviewCollection.partial, isTrue);
      expect(sample.observedProcessCount, 1);
      expect(sample.measuredProcessCount, 0);
      expect(sample.unavailableProcessCount, 1);
      expect(sample.webviewPrivMb, isNull);
    });

    test('failed scan is unavailable rather than empty', () {
      final sample = sampleLinuxProcessTree(
        procRoot: '${proc.path}/missing',
        hostProcessId: 1,
      );
      expect(
        sample.webviewCollection.status,
        ProcessCollectionStatus.unavailable,
      );
      expect(sample.webviewCollection.reason, 'proc_scan_failed');
      expect(sample.observedProcessCount, isNull);
      expect(sample.hostPrivMb, isNull);
    });
  });
}
