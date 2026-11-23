import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../tool/perf_probe/src/pdf_multi_window.dart';
import '../../../tool/perf_probe/src/pdf_reader_case.dart';
import '../../../tool/perf_probe/src/probe_binding.dart';
import '../../../tool/perf_probe/validate_pdf_multi_window.dart';

const _hash =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const _primaryPath = '/fixture/מקור.pdf';
const _secondaryPath = '/fixture/עותק.pdf';

List<Map<String, dynamic>> _indexedSearches(String path) => [
  for (final page in [2, 4])
    {
      'query': 'PDF preview fixture - page $page',
      'page': page,
      'totalHits': 1,
      'matchingHits': 1,
      'hits': [
        {'filePath': path, 'isPdf': true, 'segment': (page - 1).toString()},
      ],
    },
];

Map<String, dynamic> _reader(
  String path,
  int view,
  int handle,
  int page, {
  List<int> views = const [0, 1],
}) => {
  'path': path,
  'targetPage': page,
  'visibleRenderState': 'ready',
  'targetCenterVisible': true,
  'documentUnchanged': true,
  'windowVisible': true,
  'windowMinimized': false,
  'viewId': view,
  'screenViewId': view,
  'nativeHandle': handle,
  'liveViewIds': [...views],
};

Map<String, dynamic> _raster([String format = 'bgra8888']) => {
  'width': 100,
  'height': 80,
  'pixelFormat': format,
  'alphaPremultiplied': false,
  'pixelBytes': 32000,
  'inkPixels': 120,
  'sha256': _hash,
};

Map<String, dynamic> _interval(int start, int end) => {
  'startUs': start,
  'endUs': end,
};

Map<String, dynamic> _transition(int start, List<int> views) => {
  'status': 'passed',
  'rasterInterval': _interval(start, start + 400),
  'transitionInterval': _interval(start + 50, start + 300),
  'raster': _raster(),
  'primaryAfter': _reader(_primaryPath, 0, 1001, 3, views: views),
  'primaryUnchanged': true,
};

Map<String, dynamic> _closed(int view, int handle) => {
  'viewId': view,
  'nativeHandle': handle,
  'documentEventsClosed': true,
  'nativeDisposeAwaited': true,
  'registryEntryRemoved': true,
  'liveViewIdsAfter': [0],
};

Map<String, dynamic> _fixture() => {
  'schemaVersion': 1,
  'status': 'passed',
  'platform': 'windows',
  'bindingMode': 'framework',
  'realPlatformDispatcher': true,
  'windowingOwnerInstalled': true,
  'engineId': 42,
  'initialViewIds': [0],
  'fixture': {
    'sourceKind': 'generated',
    'pageCount': 4,
    'sha256': _hash,
    'copySha256': _hash,
    'sourcePath': _primaryPath,
    'copyPath': _secondaryPath,
  },
  'steps': {
    'open': {
      'status': 'passed',
      'primary': _reader(_primaryPath, 0, 1001, 1),
      'secondary': _reader(_secondaryPath, 1, 1002, 2),
      'separateDocuments': true,
      'separateControllers': true,
    },
    'concurrentWork': {
      'status': 'passed',
      'submittedOperations': {
        'viewing': _interval(100, 400),
        'indexing': _interval(120, 300),
        'printing': _interval(150, 350),
      },
      'primary': _reader(_primaryPath, 0, 1001, 3),
      'secondary': _reader(_secondaryPath, 1, 1002, 4),
      'primaryUnchangedBySecondaryNavigation': true,
      'secondaryUnchangedByPrimaryNavigation': true,
      'indexing': {
        'clean': true,
        'indexedBooks': 1,
        'indexedPath': _primaryPath,
        'verifiedPages': [2, 4],
        'searchResults': _indexedSearches(_primaryPath),
      },
      'printing': {
        'sourcePages': [2, 3],
        'textPreserved': true,
        'rightToLeft': true,
        'width': 480,
        'height': 320,
        'sha256': _hash,
        'pngSha256': _hash,
        'pngBytes': 1000,
        'raster': {
          ..._raster('rgba8888'),
          'width': 480,
          'height': 320,
          'pixelBytes': 614400,
        },
      },
    },
    'minimizeRestore': {
      ..._transition(1000, [0, 1]),
      'nativeMinimized': true,
      'secondaryAfter': _reader(_secondaryPath, 1, 1002, 4),
    },
    'closeSecondary': {
      ..._transition(2000, [0]),
      'closed': _closed(1, 1002),
    },
    'reopen': {
      'status': 'passed',
      'secondary': _reader(_secondaryPath, 2, 1003, 2, views: [0, 2]),
      'differentDocument': true,
    },
    'closeReopened': {
      ..._transition(3000, [0]),
      'closed': _closed(2, 1003),
    },
    'teardown': {
      'status': 'passed',
      'primaryDocumentEventsClosed': true,
      'primaryNativeDisposeAwaited': true,
      'ownedWindowsRemaining': 0,
      'ownedDocumentsRemaining': 0,
      'pendingOperations': 0,
      'indexingActive': false,
      'finalViewIds': [0],
    },
  },
};

List<Map<String, dynamic>> _readers(Map<String, dynamic> report) {
  final steps = report['steps'];
  return [
    steps['open']['primary'],
    steps['open']['secondary'],
    steps['concurrentWork']['primary'],
    steps['concurrentWork']['secondary'],
    steps['minimizeRestore']['primaryAfter'],
    steps['minimizeRestore']['secondaryAfter'],
    steps['closeSecondary']['primaryAfter'],
    steps['reopen']['secondary'],
    steps['closeReopened']['primaryAfter'],
  ];
}

void _reject(
  void Function(Map<String, dynamic>) change, {
  required String reason,
}) {
  // Real receipts arrive as JSON, including malformed values in negative tests.
  final report = jsonDecode(jsonEncode(_fixture())) as Map<String, dynamic>;
  change(report);
  expect(perfPdfMultiWindowErrors(report), isNotEmpty, reason: reason);
}

void main() {
  test('raster proof counts antialiased text as it appears on white', () {
    expect(perfPdfInkPixelsOnWhite([0, 0, 0, 192]), 1);
    expect(perfPdfInkPixelsOnWhite([0, 0, 0, 128]), 1);
    expect(perfPdfInkPixelsOnWhite([0, 0, 0, 127]), 0);
    expect(perfPdfInkPixelsOnWhite([127, 127, 127, 255]), 1);
    expect(perfPdfInkPixelsOnWhite([128, 128, 128, 255]), 0);
  });

  test('blank, transparent and bright pixels cannot establish native ink', () {
    for (final pixel in [
      [0, 0, 0, 0],
      [255, 255, 255, 0],
      [255, 255, 255, 255],
      [255, 0, 0, 255],
      [0, 255, 0, 255],
      [0, 0, 255, 255],
      [100, 100, 100, 128],
    ]) {
      expect(perfPdfInkPixelsOnWhite(pixel), 0, reason: '$pixel');
    }
    expect(perfPdfInkPixelsOnWhite([]), 0);
    expect(() => perfPdfInkPixelsOnWhite([0, 0, 0]), throwsArgumentError);
  });

  test('raster proof preserves opaque RGB and BGRA darkness semantics', () {
    final rgba = [20, 50, 80, 200, 100, 120, 110, 255];
    final bgra = [80, 50, 20, 200, 110, 120, 100, 255];
    expect(perfPdfInkPixelsOnWhite(rgba), 2);
    expect(perfPdfInkPixelsOnWhite(bgra), 2);
  });

  test('premultiplied Apple pixels are not multiplied by alpha twice', () {
    final gray = [50, 50, 50, 160];
    expect(perfPdfInkPixelsOnWhite(gray), 1);
    expect(perfPdfInkPixelsOnWhite(gray, premultipliedAlpha: true), 0);
    expect(
      perfPdfInkPixelsOnWhite([0, 0, 0, 192], premultipliedAlpha: true),
      1,
    );
    expect(
      perfPdfInkPixelsOnWhite([0, 0, 0, 0], premultipliedAlpha: true),
      0,
    );
  });

  test('accepts complete actual-window evidence on all desktop platforms', () {
    for (final platform in ['windows', 'linux', 'macos']) {
      final report = _fixture()..['platform'] = platform;
      report['steps']['concurrentWork']['printing']['raster']['alphaPremultiplied'] =
          platform == 'macos';
      expect(perfPdfMultiWindowErrors(report), isEmpty, reason: platform);
    }
  });

  test('missing or malformed reports and phases fail closed', () {
    for (final value in [null, [], {}, 'passed', {'status': 'passed'}]) {
      expect(perfPdfMultiWindowErrors(value), isNotEmpty);
    }
    for (final name in perfPdfMultiWindowSteps) {
      for (final value in [null, {}, {'status': 'notRun'}, {'status': 'failed'}]) {
        _reject(
          (report) => report['steps'][name] = value,
          reason: '$name $value',
        );
      }
    }
  });

  test('a test dispatcher or absent native owner cannot establish windows', () {
    for (final entry in {
      'status': 'notRun',
      'schemaVersion': 2,
      'platform': 'android',
      'bindingMode': 'test',
      'realPlatformDispatcher': false,
      'windowingOwnerInstalled': false,
      'engineId': 0,
    }.entries) {
      _reject(
        (report) => report[entry.key] = entry.value,
        reason: entry.key,
      );
    }
  });

  test('the two PDF paths require deterministic matching content hashes', () {
    for (final entry in {
      'sourceKind': 'external',
      'pageCount': 3,
      'sha256': 'invalid',
      'copySha256': 'f' * 64,
      'copyPath': _primaryPath,
    }.entries) {
      _reject(
        (report) => report['fixture'][entry.key] = entry.value,
        reason: entry.key,
      );
    }
    for (final path in ['', '   ']) {
      _reject((report) {
        report['fixture']['sourcePath'] = path;
        for (final reader in _readers(report)) {
          if (reader['path'] == _primaryPath) reader['path'] = path;
        }
        report['steps']['concurrentWork']['indexing']['indexedPath'] = path;
      }, reason: 'empty source path with otherwise consistent evidence');
    }
  });

  test('every reader requires real view ownership and final target content', () {
    for (var i = 0; i < _readers(_fixture()).length; i++) {
      for (final entry in {
        'path': '/another.pdf',
        'targetPage': 99,
        'visibleRenderState': 'loading',
        'targetCenterVisible': false,
        'documentUnchanged': false,
        'windowVisible': false,
        'windowMinimized': true,
        'screenViewId': 99,
        'nativeHandle': 0,
        'liveViewIds': <int>[],
      }.entries) {
        _reject(
          (report) => _readers(report)[i][entry.key] = entry.value,
          reason: 'reader $i ${entry.key}',
        );
      }
    }
  });

  test('the original windows use distinct native views and independent PDFs', () {
    for (final field in ['viewId', 'nativeHandle']) {
      _reject((report) {
        final open = report['steps']['open'];
        open['secondary'][field] = open['primary'][field];
        if (field == 'viewId') {
          open['secondary']['screenViewId'] = open['secondary']['viewId'];
        }
      }, reason: 'duplicate $field');
    }
    for (final field in ['separateDocuments', 'separateControllers']) {
      _reject(
        (report) => report['steps']['open'][field] = false,
        reason: field,
      );
    }
    _reject((report) {
      report['initialViewIds'] = <int>[];
      report['steps']['teardown']['finalViewIds'] = <int>[];
    }, reason: 'primary view must already exist before secondary opens');
  });

  test('identity is retained across navigation and native transitions', () {
    const locations = [
      ('concurrentWork', 'primary'),
      ('concurrentWork', 'secondary'),
      ('minimizeRestore', 'primaryAfter'),
      ('minimizeRestore', 'secondaryAfter'),
      ('closeSecondary', 'primaryAfter'),
      ('closeReopened', 'primaryAfter'),
    ];
    for (final (step, key) in locations) {
      for (final field in ['viewId', 'nativeHandle']) {
        _reject((report) {
          final reader = report['steps'][step][key];
          reader[field] = 99;
          if (field == 'viewId') {
            reader['screenViewId'] = 99;
            reader['liveViewIds'] = [0, 1, 99];
          }
        }, reason: '$step $key replaced $field');
      }
    }
  });

  test('navigation in one reader cannot mutate the other document', () {
    for (final field in [
      'primaryUnchangedBySecondaryNavigation',
      'secondaryUnchangedByPrimaryNavigation',
    ]) {
      _reject(
        (report) => report['steps']['concurrentWork'][field] = false,
        reason: field,
      );
    }
    for (final name in ['minimizeRestore', 'closeSecondary', 'closeReopened']) {
      _reject(
        (report) => report['steps'][name]['primaryUnchanged'] = false,
        reason: name,
      );
    }
    _reject(
      (report) => report['steps']['minimizeRestore']['nativeMinimized'] = false,
      reason: 'native minimized state must be observed',
    );
  });

  test('viewing overlaps submitted indexing and printing work', () {
    for (final operation in ['indexing', 'printing']) {
      for (final interval in [
        null,
        _interval(500, 600),
        _interval(400, 500),
        _interval(200, 200),
        _interval(300, 200),
        _interval(-1, 300),
        {'startUs': 120.5, 'endUs': 300},
      ]) {
        _reject(
          (report) => report['steps']['concurrentWork']['submittedOperations'][operation] =
              interval,
          reason: '$operation $interval',
        );
      }
    }
  });

  test('native raster overlaps every minimize or close transition', () {
    for (final name in ['minimizeRestore', 'closeSecondary', 'closeReopened']) {
      for (final key in ['rasterInterval', 'transitionInterval']) {
        _reject(
          (report) => report['steps'][name][key] = _interval(9000, 9500),
          reason: '$name $key',
        );
      }
    }
  });

  test('indexing verifies the requested real pages and correct source', () {
    for (final entry in <String, Object?>{
      'clean': false,
      'indexedBooks': 0,
      'indexedPath': _secondaryPath,
      'verifiedPages': [2],
    }.entries) {
      _reject(
        (report) => report['steps']['concurrentWork']['indexing'][entry.key] =
            entry.value,
        reason: entry.key,
      );
    }
    for (final pages in [
      [4, 2],
      [2, 2],
      [2, 4, 4],
      ['2', '4'],
      [2.0, 4.0],
      [true, 4],
    ]) {
      _reject(
        (report) => report['steps']['concurrentWork']['indexing']['verifiedPages'] =
            pages,
        reason: '$pages',
      );
    }
  });

  test('indexing details must substantiate the verified page summary', () {
    _reject((report) {
      report['steps']['concurrentWork']['indexing'].remove('searchResults');
    }, reason: 'page summary without detailed hits');
    for (final mutation in {
      'filePath': _secondaryPath,
      'isPdf': false,
      'segment': '0',
    }.entries) {
      _reject((report) {
        final search =
            report['steps']['concurrentWork']['indexing']['searchResults'][0];
        search['hits'][0][mutation.key] = mutation.value;
      }, reason: mutation.key);
    }
    _reject((report) {
      final search =
          report['steps']['concurrentWork']['indexing']['searchResults'][0];
      search['hits'].add(search['hits'].single);
      search['totalHits'] = 2;
    }, reason: 'duplicate matching hit despite claimed count of one');
  });

  test('vector export preserves source order, RTL, text and native raster', () {
    for (final entry in {
      'textPreserved': false,
      'rightToLeft': false,
      'width': 479,
      'height': 319,
      'sha256': 'invalid',
      'pngSha256': 'invalid',
      'pngBytes': 8,
    }.entries) {
      _reject(
        (report) => report['steps']['concurrentWork']['printing'][entry.key] =
            entry.value,
        reason: entry.key,
      );
    }
    for (final pages in [
      [3, 2],
      [2, 2],
      [2],
      ['2', '3'],
      [2.0, 3.0],
      [true, 3],
    ]) {
      _reject(
        (report) => report['steps']['concurrentWork']['printing']['sourcePages'] =
            pages,
        reason: '$pages',
      );
    }
  });

  test('raster receipts require correct byte count, ink and source format', () {
    _reject(
      (report) => report['steps']['concurrentWork']['printing']['raster'] =
          _raster('rgba8888'),
      reason: 'Printing raster must match the actual 480 by 320 sheet at 72 dpi',
    );
    for (final name in [
      'printing',
      'minimizeRestore',
      'closeSecondary',
      'closeReopened',
    ]) {
      for (final entry in <String, Object?>{
        'width': 0,
        'height': -1,
        'pixelBytes': 31999,
        'inkPixels': 10,
        'alphaPremultiplied': true,
        'sha256': 'invalid',
        'pixelFormat': name == 'printing' ? 'bgra8888' : 'rgba8888',
      }.entries) {
        _reject((report) {
          final step = name == 'printing'
              ? report['steps']['concurrentWork']['printing']
              : report['steps'][name];
          step['raster'][entry.key] = entry.value;
        }, reason: '$name ${entry.key}');
      }
      _reject((report) {
        final step = name == 'printing'
            ? report['steps']['concurrentWork']['printing']
            : report['steps'][name];
        step['raster'].remove('alphaPremultiplied');
      }, reason: '$name must identify its alpha representation');

      final report = _fixture();
      final step = name == 'printing'
          ? report['steps']['concurrentWork']['printing']
          : report['steps'][name];
      step['raster']['inkPixels'] = 11;
      expect(perfPdfMultiWindowErrors(report), isEmpty, reason: name);
    }
  });

  test('event-stream closure alone does not prove native disposal', () {
    for (final name in ['closeSecondary', 'closeReopened']) {
      for (final field in [
        'documentEventsClosed',
        'nativeDisposeAwaited',
        'registryEntryRemoved',
      ]) {
        _reject(
          (report) => report['steps'][name]['closed'][field] = false,
          reason: '$name $field',
        );
      }
      _reject((report) {
        final closed = report['steps'][name]['closed'];
        closed['liveViewIdsAfter'] = [0, closed['viewId']];
      }, reason: '$name still registered in the real dispatcher');
      for (final field in ['viewId', 'nativeHandle']) {
        _reject(
          (report) => report['steps'][name]['closed'][field] = 99,
          reason: '$name receipt belongs to another $field',
        );
        _reject((report) {
          final closed = report['steps'][name]['closed'];
          closed[field] = (closed[field] as int).toDouble();
        }, reason: '$name $field must be a native integer');
      }
    }
  });

  test('reopening needs a new document in a separate secondary window', () {
    _reject(
      (report) => report['steps']['reopen']['differentDocument'] = false,
      reason: 'reused document',
    );
    _reject((report) {
      report['steps']['reopen']['secondary'] =
          _reader(_secondaryPath, 0, 1001, 2);
      report['steps']['closeReopened']['closed'] = _closed(0, 1001)
        ..['liveViewIdsAfter'] = <int>[];
    }, reason: 'primary native window cannot stand in for a reopened secondary');
  });

  test('teardown releases native documents and restores the initial view set', () {
    for (final entry in <String, Object?>{
      'primaryDocumentEventsClosed': false,
      'primaryNativeDisposeAwaited': false,
      'ownedWindowsRemaining': 1,
      'ownedDocumentsRemaining': 1,
      'indexingActive': true,
      'finalViewIds': [0, 1],
    }.entries) {
      _reject(
        (report) => report['steps']['teardown'][entry.key] = entry.value,
        reason: entry.key,
      );
    }
    for (final value in [null, 1, true, 0.0]) {
      _reject(
        (report) => report['steps']['teardown']['pendingOperations'] = value,
        reason: 'missing or pending original native operations: $value',
      );
    }
    for (final ids in [<int>[], [0, 0], [0.0], [true]]) {
      _reject(
        (report) => report['steps']['teardown']['finalViewIds'] = ids,
        reason: '$ids',
      );
    }
  });
  _smokeTests();
}


class _SmokeFiles {
  _SmokeFiles(this.root, this.receipt, this.manifest, this.report, this.records);

  final Directory root;
  final Directory receipt;
  final Map<String, dynamic> manifest;
  final Map<String, dynamic> report;
  final List<Map<String, dynamic>> records;
  Map<String, dynamic> get evidence => records[1]['details'];
  Map<String, dynamic> get settings => report['metadata']['settings'];

  Future<void> save({bool synchronizeReceipt = true}) async {
    await File(p.join(root.path, 'manifest.json'))
        .writeAsString(jsonEncode(manifest));
    await File(p.join(root.path, 'report.json'))
        .writeAsString(jsonEncode(report));
    await File(p.join(root.path, 'phases.jsonl'))
        .writeAsString(records.map(jsonEncode).join('\n'));
    if (synchronizeReceipt) {
      await File(p.join(receipt.path, 'report.json'))
          .writeAsString(jsonEncode(evidence));
    }
  }

  Future<Map<String, Object?>> validate() => validatePerfPdfMultiWindowSmoke(
    root,
    commit: '1' * 40,
    platform: evidence['platform'],
    buildMode: manifest['buildMode'],
    expectedEngineSha256: manifest['buildMode'] == 'release' ? _hash : '',
  );
}

Future<_SmokeFiles> _smoke({
  String platform = 'linux',
  String mode = 'profile',
}) async {
  final root = await Directory.systemTemp.createTemp('pdf-multi-smoke-');
  addTearDown(() => root.delete(recursive: true));
  final receipt = await Directory(
    p.join(root.path, 'launch-000', 'pdf-multi-window-owned'),
  ).create(recursive: true);
  final source = File(
    p.join(root.path, 'data', 'cold-0', 'pdf', 'reader-mixed.pdf'),
  );
  await source.parent.create(recursive: true);
  // Host contract bytes only; native PDF rendering is exercised by actual CI.
  final bytes = utf8.encode('%PDF-1.7 host contract source');
  final pdfHash = sha256.convert(bytes).toString();
  await source.writeAsBytes(bytes);
  final copy = await source.copy(p.join(receipt.path, 'secondary.pdf'));
  final vector = utf8.encode('%PDF-1.7 host contract vector output');
  final vectorHash = sha256.convert(vector).toString();
  await File(p.join(receipt.path, 'two-up.pdf')).writeAsBytes(vector);
  final pngBytes = [137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3, 4];
  await File(p.join(receipt.path, 'two-up.png')).writeAsBytes(pngBytes);
  final evidence = _fixture()..['platform'] = platform;
  evidence['steps']['concurrentWork']['printing']['raster']['alphaPremultiplied'] =
      platform == 'macos';
  evidence['fixture'] = {
    'sourceKind': 'generated',
    'pageCount': 10,
    'sha256': pdfHash,
    'copySha256': pdfHash,
    'sourcePath': source.path,
    'copyPath': copy.path,
  };
  for (final reader in _readers(evidence)) {
    reader['path'] = reader['path'] == _primaryPath ? source.path : copy.path;
  }
  final indexing = evidence['steps']['concurrentWork']['indexing'];
  indexing['indexedPath'] = source.path;
  indexing['searchResults'] = _indexedSearches(source.path);
  evidence['steps']['concurrentWork']['printing']['sha256'] = vectorHash;
  evidence['steps']['concurrentWork']['printing']['pngSha256'] =
      sha256.convert(pngBytes).toString();
  evidence['steps']['concurrentWork']['printing']['pngBytes'] = pngBytes.length;
  final pdfCase = PerfPdfCase.fromJson({
    'schemaVersion': 1,
    'source': {'kind': 'generated', 'pageCount': 10},
  }, baseDirectory: root.path);
  await File(p.join(root.path, 'pdf-case.json'))
      .writeAsString(jsonEncode(pdfCase.toJson()));
  final fixtureId = 'synthetic-v4-pdf-cases:$pdfHash';
  final manifest = <String, dynamic>{
    'schemaVersion': 2,
    'protocolVersion': 2,
    'status': 'passed',
    'commit': '1' * 40,
    'buildMode': mode,
    'cacheState': 'cold',
    'scenarioSet': 'pdf-multi-window',
    'bindingMode': 'framework',
    'probeTarget': PerfBindingMode.framework.target,
    'launchCount': 1,
    'warmup': 0,
    'repetitions': 1,
    'dirty': false,
    'sampling': {'intervalMs': 500, 'heap': mode != 'release'},
    'sourceProvenance': {
      for (final stage in ['beforeBuild', 'afterBuild', 'afterRuns'])
        stage: {'statusPorcelain': [], 'trackedDiffSummary': []},
    },
  };
  final settings = <String, Object?>{
    ...PerfBindingMode.framework.toComparisonJson(),
    'scenarioSet': 'pdf-multi-window',
    'pdfLayout': 'regularView',
    'pdfPageCount': 10,
    'pdfReaderCase': pdfCase.toComparisonJson(),
    'pdfMultiWindowProtocol': perfPdfMultiWindowProtocol,
  };
  if (platform == 'windows') {
    final engine = {
      'schemaVersion': 1,
      'platform': 'windows',
      'architecture': 'x64',
      'buildMode': mode,
      'engineRevision': '2' * 40,
      'bundleSha256': _hash,
      'verification':
          mode == 'release' ? 'patched-action-sha256' : 'bundle-sha256',
      if (mode == 'release') 'expectedSha256': _hash,
    };
    manifest['engineIdentity'] = engine;
    settings['engineBinary'] = engine;
  }
  final report = <String, dynamic>{
    'complete': true,
    'successful': true,
    'comparisonEligibility': [],
    'metadata': {...manifest, 'fixtureId': fixtureId, 'settings': settings},
    'notes': [
      {
        'name': 'framework.scheduler_contract',
        'launchIndex': 0,
        'frameworkScheduler': {
          'status': 'passed',
          'source': 'Timer -> SchedulerBinding.scheduleFrame -> postFrameCallback',
          'deferredFrameDelivered': true,
          'nativePlatformDispatcher': true,
          'bindingClass': 'WidgetsFlutterBinding',
          'requestedAtUs': 25,
          'completedAtUs': 40,
          'frameTimestampUs': 40,
        },
      },
    ],
    'scenarios': [
      {
        'name': 'pdf_multi_window',
        'status': 'passed',
        'measured': 1,
        'warmupExcluded': 0,
        'failures': 0,
        'skipped': 0,
      },
    ],
  };
  final records = <Map<String, dynamic>>[
    {
      'type': 'meta',
      'pid': 123,
      'launchIndex': 0,
      'fixtureId': fixtureId,
      'buildMode': mode,
      'fixturePdf': {
        'pages': 10,
        'mixedPageSizes': true,
        'source': 'generated',
        'sha256': pdfHash,
      },
    },
    {
      'type': 'phase',
      'name': 'pdf_multi_window',
      'status': 'passed',
      'launchIndex': 0,
      'iteration': 0,
      'warmup': false,
      'details': evidence,
      if (mode == 'release') ...{
        'heapBefore': null,
        'heapAfter': null,
        'heapUnavailableReason':
            'Dart VM service is unavailable in release builds.',
      },
    },
  ];
  await File(p.join(root.path, 'launch-000', 'launch.json')).writeAsString(
    jsonEncode({'launchIndex': 0, 'pid': 123, 'identityStartTicks': '1234'}),
  );
  await File(p.join(root.path, 'launch-000', 'completion.json')).writeAsString(
    jsonEncode({
      'status': 'passed',
      'fixtureId': fixtureId,
      'preparationOnly': false,
      'error': null,
      'testFailures': [],
      ...PerfBindingMode.framework.toComparisonJson(),
    }),
  );
  final files = _SmokeFiles(root, receipt, manifest, report, records);
  await files.save();
  return files;
}

void _smokeTests() {
  group('actual smoke evidence and bundled engine identity', () {
    test('rejects a journal attributed to a different process', () async {
      final files = await _smoke();
      files.records.first['pid'] = 456;
      await files.save();
      await expectLater(files.validate(), throwsFormatException);
    });

    test('accepts all desktop profiles and the verified Windows release', () async {
      for (final platform in ['linux', 'macos', 'windows']) {
        final files = await _smoke(platform: platform);
        expect((await files.validate())['status'], 'passed');
      }
      final release = await _smoke(platform: 'windows', mode: 'release');
      final result = await release.validate();
      expect(result['buildMode'], 'release');
      expect(
        (result['engineIdentity'] as Map)['verification'],
        'patched-action-sha256',
      );
    });

    test('dirty or missing source evidence never becomes a verified run', () async {
      for (final stage in ['beforeBuild', 'afterBuild', 'afterRuns']) {
        for (final field in ['statusPorcelain', 'trackedDiffSummary']) {
          final files = await _smoke();
          files.manifest['sourceProvenance'][stage][field] = ['changed'];
          await files.save();
          await expectLater(files.validate(), throwsFormatException);
        }
      }
      final files = await _smoke();
      files.manifest['dirty'] = true;
      await files.save();
      await expectLater(files.validate(), throwsFormatException);
      files.manifest['dirty'] = false;
      files.manifest['sourceProvenance'].remove('afterRuns');
      await files.save();
      await expectLater(files.validate(), throwsFormatException);
    });

    test('rejects foreign HEAD, protocol, fixture and scheduler identities', () async {
      for (final field in ['commit', 'protocolVersion', 'bindingMode', 'fixtureId']) {
        final files = await _smoke();
        files.report['metadata'][field] = 'wrong';
        await files.save();
        await expectLater(files.validate(), throwsFormatException);
      }
      final files = await _smoke();
      files.report['notes'][0]['frameworkScheduler']['nativePlatformDispatcher'] =
          false;
      await files.save();
      await expectLater(files.validate(), throwsFormatException);
      files.report['notes'][0]['frameworkScheduler']['nativePlatformDispatcher'] =
          true;
      files.settings['pdfMultiWindowProtocol'] = {'version': 1};
      await files.save();
      await expectLater(files.validate(), throwsFormatException);
    });

    test('changed source, independent copy and vector or raster artifacts fail', () async {
      for (final relative in [
        'data/cold-0/pdf/reader-mixed.pdf',
        'launch-000/pdf-multi-window-owned/secondary.pdf',
        'launch-000/pdf-multi-window-owned/two-up.pdf',
        'launch-000/pdf-multi-window-owned/two-up.png',
      ]) {
        final files = await _smoke();
        await File(p.join(files.root.path, relative)).writeAsString('changed');
        await expectLater(files.validate(), throwsFormatException);
      }
    });

    test('PNG bytes are bound to the native writer even when signature survives', () async {
      for (final tail in [<int>[], [9, 9, 9, 9]]) {
        final files = await _smoke();
        await File(p.join(files.receipt.path, 'two-up.png')).writeAsBytes(
          [137, 80, 78, 71, 13, 10, 26, 10, ...tail],
        );
        await expectLater(files.validate(), throwsFormatException);
      }
    });

    test('a successful summary cannot replace native receipts or cleanup', () async {
      final files = await _smoke();
      files.evidence['steps']['teardown']['pendingOperations'] = 1;
      await files.save();
      await expectLater(files.validate(), throwsFormatException);
      files.evidence['steps']['teardown']['pendingOperations'] = 0;
      await files.save(synchronizeReceipt: false);
      await expectLater(files.validate(), throwsFormatException);
      await files.save();
      files.records.add({...files.records[1]});
      await files.save();
      await expectLater(files.validate(), throwsFormatException);
    });

    test('the actual case and completion must match the measured launch', () async {
      final files = await _smoke();
      await File(p.join(files.root.path, 'pdf-case.json')).writeAsString(
        '{"schemaVersion":1,"source":{"kind":"generated","pageCount":100}}',
      );
      await expectLater(files.validate(), throwsFormatException);
      final incomplete = await _smoke();
      await File(p.join(incomplete.root.path, 'launch-000', 'completion.json'))
          .writeAsString('{"status":"passed"}');
      await expectLater(incomplete.validate(), throwsFormatException);
    });

    test('patched release proof needs the actual matching action hash', () async {
      final files = await _smoke(platform: 'windows', mode: 'release');
      files.manifest['engineIdentity'] = {
        ...files.manifest['engineIdentity'],
        'bundleSha256': 'f' * 64,
      };
      await files.save();
      await expectLater(files.validate(), throwsFormatException);
      final profile = await _smoke(platform: 'windows');
      profile.settings['engineBinary'] = null;
      await profile.save();
      await expectLater(profile.validate(), throwsFormatException);
    });

    test('release heap absence cannot be turned into a numeric zero', () async {
      final files = await _smoke(platform: 'windows', mode: 'release');
      files.records[1]['heapBefore'] = {'heapUsage': 0};
      await files.save();
      await expectLater(files.validate(), throwsFormatException);
      files.records[1]['heapBefore'] = null;
      files.records[1].remove('heapUnavailableReason');
      await files.save();
      await expectLater(files.validate(), throwsFormatException);
    });
  });
}
