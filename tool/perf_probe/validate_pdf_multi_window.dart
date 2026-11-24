import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'src/pdf_multi_window.dart';
import 'src/pdf_reader_case.dart';
import 'src/probe_binding.dart';
import 'src/probe_engine.dart';
import 'src/report.dart';

void _require(bool condition, String message) {
  if (!condition) throw FormatException(message);
}

Map<String, dynamic> _map(Object? value, String description) {
  if (value is! Map<String, dynamic>) {
    throw FormatException('$description must be a JSON object.');
  }
  return value;
}

bool _same(Object? first, Object? second) {
  if (first is Map && second is Map) {
    return first.length == second.length &&
        first.keys.every(
          (key) => second.containsKey(key) && _same(first[key], second[key]),
        );
  }
  if (first is List && second is List) {
    return first.length == second.length &&
        List.generate(
          first.length,
          (index) => index,
        ).every((index) => _same(first[index], second[index]));
  }
  return first == second;
}

void _fields(Map<String, dynamic> source, Map<String, Object?> expected) {
  for (final entry in expected.entries) {
    final actual = source[entry.key];
    _require(
      actual == entry.value && (entry.value is! int || actual is int),
      'Missing or unexpected ${entry.key}: $actual',
    );
  }
}

Future<File> _ownedFile(Directory root, String path) async {
  final file = File(path).absolute;
  _require(
    await FileSystemEntity.type(file.path, followLinks: false) ==
        FileSystemEntityType.file,
    'Evidence is not a regular file: $path',
  );
  final actual = await file.resolveSymbolicLinks();
  final parent = await root.resolveSymbolicLinks();
  _require(p.isWithin(parent, actual), 'Evidence escaped the owned run: $path');
  return file;
}

Future<Map<String, dynamic>> _readJson(Directory root, String path) async {
  final file = await _ownedFile(root, path);
  _require(await file.length() < 128 * 1024 * 1024, 'Evidence is too large.');
  final source = (await file.readAsString()).replaceFirst('\ufeff', '');
  return _map(jsonDecode(source), p.basename(path));
}

Future<String> _hash(Directory root, String path) async {
  final file = await _ownedFile(root, path);
  return (await sha256.bind(file.openRead()).first).toString();
}

/// Fixed one-launch CI smoke. General repeated measurements use the runner report.
Future<Map<String, Object?>> validatePerfPdfMultiWindowSmoke(
  Directory root, {
  required String commit,
  required String platform,
  required String buildMode,
  String expectedEngineSha256 = '',
}) async {
  _require(
    RegExp(r'^[a-f0-9]{40}$').hasMatch(commit),
    'Invalid expected commit.',
  );
  _require(
    const ['windows', 'linux', 'macos'].contains(platform) &&
        const ['profile', 'release'].contains(buildMode),
    'Expected a desktop profile or release build.',
  );
  _require(
    (platform == 'windows' && buildMode == 'release')
        ? RegExp(r'^[a-f0-9]{64}$').hasMatch(expectedEngineSha256)
        : expectedEngineSha256.isEmpty,
    'Only Windows release smoke requires the patched action SHA-256.',
  );
  final manifest = await _readJson(root, p.join(root.path, 'manifest.json'));
  final report = await _readJson(root, p.join(root.path, 'report.json'));
  _require(
    report['complete'] == true &&
        report['successful'] == true &&
        _same(report['comparisonEligibility'], const []),
    'The actual app report must be complete, successful and verified.',
  );
  final metadata = _map(report['metadata'], 'metadata');
  final expected = <String, Object?>{
    'schemaVersion': 2,
    'protocolVersion': 2,
    'status': 'passed',
    'commit': commit,
    'buildMode': buildMode,
    'cacheState': 'cold',
    'scenarioSet': 'pdf-multi-window',
    'bindingMode': 'framework',
    'probeTarget': PerfBindingMode.framework.target,
    'launchCount': 1,
    'warmup': 0,
    'repetitions': 1,
    'dirty': false,
  };
  _fields(manifest, expected);
  _fields(metadata, expected);
  final provenance = _map(manifest['sourceProvenance'], 'sourceProvenance');
  for (final stage in ['beforeBuild', 'afterBuild', 'afterRuns']) {
    final value = _map(provenance[stage], stage);
    _require(
      _same(value['statusPorcelain'], const []) &&
          _same(value['trackedDiffSummary'], const []),
      'Source changed at $stage.',
    );
  }
  _require(
    _same(manifest['sampling'], metadata['sampling']),
    'Process sampling identity changed.',
  );
  final settings = _map(metadata['settings'], 'settings');
  _fields(settings, PerfBindingMode.framework.toComparisonJson());
  _fields(settings, {
    'scenarioSet': 'pdf-multi-window',
    'pdfLayout': 'regularView',
    'pdfPageCount': 10,
  });
  _require(
    _same(settings['pdfMultiWindowProtocol'], perfPdfMultiWindowProtocol),
    'The native multi-window actions do not match the recorded protocol.',
  );
  final pdfCase = await PerfPdfCase.load(p.join(root.path, 'pdf-case.json'));
  _require(
    pdfCase.sourceKind == PerfPdfSourceKind.generated &&
        pdfCase.pageCount == 10 &&
        pdfCase.mixedPageSizes == true &&
        _same(settings['pdfReaderCase'], pdfCase.toComparisonJson()),
    'The prepared generated ten-page case differs from the measured case.',
  );
  final fixtureId = metadata['fixtureId'];
  _require(
    fixtureId is String &&
        RegExp(r'^synthetic-v4-pdf-cases:[a-f0-9]{64}$').hasMatch(fixtureId),
    'Missing fixture schema and digest.',
  );

  final journal = await _ownedFile(root, p.join(root.path, 'phases.jsonl'));
  _require(await journal.length() < 128 * 1024 * 1024, 'Journal is too large.');
  final records = parseProbeRecords(await journal.readAsString());
  final primary = records
      .where(
        (row) => row['type'] == 'meta' && row.containsKey('pid'),
      )
      .toList();
  _require(
    primary.length == 1 &&
        primary.single['launchIndex'] == 0 &&
        primary.single['fixtureId'] == fixtureId &&
        primary.single['buildMode'] == buildMode,
    'Expected one measured fixture with the actual build mode.',
  );
  final launch = Directory(p.join(root.path, 'launch-000'));
  final process = await _readJson(root, p.join(launch.path, 'launch.json'));
  final appPid = primary.single['pid'];
  final processStart = process['identityStartTicks'];
  _require(
    appPid is int &&
        appPid > 0 &&
        processStart is String &&
        RegExp(r'^[1-9][0-9]*$').hasMatch(processStart),
    'Missing native process identity.',
  );
  _fields(process, {'launchIndex': 0, 'pid': appPid});
  final sourcePath = p.join(
    root.path,
    'data',
    'cold-0',
    'pdf',
    'reader-mixed.pdf',
  );
  final sourceHash = await _hash(root, sourcePath);
  _require(
    _same(primary.single['fixturePdf'], {
      'pages': 10,
      'mixedPageSizes': true,
      'source': 'generated',
      'sha256': sourceHash,
    }),
    'Measured source PDF hash, count or kind differs from the prepared file.',
  );
  final phases = records
      .where(
        (row) => row['type'] == 'phase' && row['name'] == 'pdf_multi_window',
      )
      .toList();
  _require(phases.length == 1, 'Expected one native multi-window phase.');
  final phase = phases.single;
  _fields(phase, {
    'status': 'passed',
    'launchIndex': 0,
    'iteration': 0,
    'warmup': false,
  });
  final evidence = _map(phase['details'], 'multi-window details');
  final errors = perfPdfMultiWindowErrors(evidence);
  _require(errors.isEmpty, errors.join('\n'));
  _require(evidence['platform'] == platform, 'The wrong native platform ran.');
  final fixture = _map(evidence['fixture'], 'multi-window fixture');
  _require(
    fixture['pageCount'] == 10 &&
        fixture['sha256'] == sourceHash &&
        fixture['copySha256'] == sourceHash &&
        fixture['sourcePath'] is String &&
        p.equals(fixture['sourcePath'] as String, sourcePath),
    'Native readers used a different source fixture.',
  );
  final receipts = (await launch.list(followLinks: false).toList())
      .whereType<Directory>()
      .where((entry) => p.basename(entry.path).startsWith('pdf-multi-window-'))
      .toList();
  _require(receipts.length == 1, 'Missing or duplicate owned-window receipt.');
  final directory = receipts.single;
  final sidecar = await _readJson(root, p.join(directory.path, 'report.json'));
  _require(
    _same(sidecar, evidence),
    'Journal and native-window receipt differ.',
  );
  final copyPath = p.join(directory.path, 'secondary.pdf');
  _require(
    fixture['copyPath'] is String &&
        p.equals(fixture['copyPath'] as String, copyPath) &&
        await _hash(root, copyPath) == sourceHash,
    'The independent reader copy is missing or changed.',
  );
  final steps = _map(evidence['steps'], 'steps');
  final printing = _map(
    _map(steps['concurrentWork'], 'concurrentWork')['printing'],
    'printing',
  );
  _require(
    await _hash(root, p.join(directory.path, 'two-up.pdf')) ==
        printing['sha256'],
    'The actual vector output differs from the native printing receipt.',
  );
  final png = await _ownedFile(root, p.join(directory.path, 'two-up.png'));
  final signature = await png.openRead(0, 8).expand((bytes) => bytes).toList();
  _require(
    _same(signature, const [137, 80, 78, 71, 13, 10, 26, 10]) &&
        await png.length() == printing['pngBytes'] &&
        await _hash(root, png.path) == printing['pngSha256'],
    'The PNG artifact differs from the native printing output.',
  );

  final notes = report['notes'];
  _require(notes is List, 'Framework scheduling evidence is missing.');
  final scheduling = (notes as List)
      .whereType<Map<String, dynamic>>()
      .where((row) => row['name'] == 'framework.scheduler_contract')
      .toList();
  _require(scheduling.length == 1, 'Expected one deferred scheduling receipt.');
  _fields(scheduling.single, {'launchIndex': 0});
  final scheduler = _map(
    scheduling.single['frameworkScheduler'],
    'frameworkScheduler',
  );
  _fields(scheduler, {
    'status': 'passed',
    'source': 'Timer -> SchedulerBinding.scheduleFrame -> postFrameCallback',
    'deferredFrameDelivered': true,
    'nativePlatformDispatcher': true,
    'bindingClass': 'WidgetsFlutterBinding',
  });
  for (final field in ['requestedAtUs', 'completedAtUs', 'frameTimestampUs']) {
    _require(
      scheduler[field] is int && (scheduler[field] as int) >= 0,
      'Missing deferred frame timestamp: $field',
    );
  }
  _require(
    (scheduler['completedAtUs'] as int) >= (scheduler['requestedAtUs'] as int),
    'The frame predates its request.',
  );
  final completion = await _readJson(
    root,
    p.join(launch.path, 'completion.json'),
  );
  _fields(completion, {
    'status': 'passed',
    'fixtureId': fixtureId,
    'preparationOnly': false,
    ...PerfBindingMode.framework.toComparisonJson(),
  });
  _require(
    completion['error'] == null && _same(completion['testFailures'], const []),
    'The native target reported an error.',
  );
  final scenarios = report['scenarios'];
  _require(scenarios is List, 'Aggregated phase evidence is missing.');
  final rows = (scenarios as List)
      .whereType<Map<String, dynamic>>()
      .where((row) => row['name'] == 'pdf_multi_window')
      .toList();
  _require(rows.length == 1, 'Expected one aggregated native-window phase.');
  _fields(rows.single, {
    'status': 'passed',
    'measured': 1,
    'warmupExcluded': 0,
    'failures': 0,
    'skipped': 0,
  });

  Map<String, Object?>? engine;
  if (platform == 'windows') {
    engine = parsePerfEngineIdentity(
      jsonEncode(manifest['engineIdentity']),
      buildMode: buildMode,
      platform: platform,
    );
    _require(
      _same(settings['engineBinary'], engine),
      'The app and host disagree on the bundled Flutter engine.',
    );
    if (buildMode == 'release') {
      _require(
        engine!['verification'] == 'patched-action-sha256' &&
            engine['expectedSha256'] == expectedEngineSha256,
        'The actual release engine was not verified against the patched action.',
      );
    } else {
      _require(
        engine!['verification'] == 'bundle-sha256',
        'Profile must not claim it used the patched release engine.',
      );
    }
  } else {
    final identity = _map(manifest['engineIdentity'], 'POSIX engine identity');
    final binaryName = platform == 'linux'
        ? 'libflutter_linux_gtk.so'
        : 'FlutterMacOS';
    _fields(identity, {
      'schemaVersion': 1,
      'platform': platform,
      'buildMode': buildMode,
      'binaryName': binaryName,
    });
    _require(
      identity.length == 6 &&
          identity['bytes'] is int &&
          (identity['bytes'] as int) > 0 &&
          identity['bundleSha256'] is String &&
          RegExp(
            r'^[a-f0-9]{64}$',
          ).hasMatch(identity['bundleSha256'] as String) &&
          _same(metadata['engineIdentity'], identity) &&
          !settings.containsKey('engineBinary'),
      'The POSIX engine identity is missing, malformed or inconsistent.',
    );
    final engineEvidence = _map(manifest['engineEvidence'], 'engineEvidence');
    final canonicalPath = engineEvidence['canonicalPath'];
    _require(
      engineEvidence['verifiedAfterRuns'] == true &&
          canonicalPath is String &&
          p.posix.isAbsolute(canonicalPath) &&
          p.posix.basename(canonicalPath) == binaryName &&
          _same(metadata['engineEvidence'], engineEvidence),
      'The POSIX runner did not verify the same bundled engine after its runs.',
    );
    _fields(process, {
      'preparationOnly': false,
      'completedBeforeTermination': true,
      'engineVerifiedAfterCompletion': true,
    });
    final proof = await _readJson(root, p.join(launch.path, 'engine.json'));
    _fields(proof, {
      'pid': appPid,
      'canonicalPath': canonicalPath,
      'observedAfterCompletion': true,
      'source': platform == 'linux'
          ? '/proc/$appPid/maps'
          : 'lsof -a -p <owned PID> -d txt -Fpcfn0',
    });
    // The runner validates the loaded mapping; bind its receipt to this launch.
    _require(
      _same(proof['identity'], identity) &&
          proof['rawObservation'] is String &&
          (proof['rawObservation'] as String).trim().isNotEmpty,
      'Missing or inconsistent mapped engine evidence for the owned process.',
    );
    engine = identity;
  }
  if (buildMode == 'release') {
    _require(
      _map(metadata['sampling'], 'sampling')['heap'] == false &&
          phase['heapBefore'] == null &&
          phase['heapAfter'] == null &&
          phase['heapUnavailableReason'] ==
              'Dart VM service is unavailable in release builds.',
      'Release VM heap must remain explicitly unavailable.',
    );
  }
  return {
    'status': 'passed',
    'commit': commit,
    'platform': platform,
    'buildMode': buildMode,
    'bindingMode': 'framework',
    'fixtureId': fixtureId,
    'sourceSha256': sourceHash,
    'engineIdentity': engine,
    'steps': perfPdfMultiWindowSteps,
    'primary': _map(steps['open'], 'open')['primary'],
    'secondary': _map(steps['open'], 'open')['secondary'],
    'teardown': steps['teardown'],
    'limitations': [
      'One functional smoke; no baseline comparison or performance threshold.',
      'Final image is in the layer tree, not a GPU presentation timestamp.',
      'Submitted operation intervals do not prove native parallel execution.',
      'Physical sleep and a physical printer were not exercised.',
    ],
  };
}

Future<void> main(List<String> arguments) async {
  try {
    final options = <String, String>{};
    const allowed = {
      '--root',
      '--commit',
      '--platform',
      '--mode',
      '--expected-engine-sha256',
    };
    for (var index = 0; index < arguments.length; index += 2) {
      if (index + 1 >= arguments.length ||
          !allowed.contains(arguments[index]) ||
          options.containsKey(arguments[index])) {
        throw const FormatException('Expected unique --option value pairs.');
      }
      options[arguments[index]] = arguments[index + 1];
    }
    for (final key in ['--root', '--commit', '--platform', '--mode']) {
      _require(options[key]?.isNotEmpty == true, 'Missing $key');
    }
    final result = await validatePerfPdfMultiWindowSmoke(
      Directory(options['--root']!).absolute,
      commit: options['--commit']!,
      platform: options['--platform']!,
      buildMode: options['--mode']!,
      expectedEngineSha256: options['--expected-engine-sha256'] ?? '',
    );
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
  } catch (error) {
    stderr.writeln('Incomplete native PDF multi-window smoke: $error');
    exitCode = 1;
  }
}
