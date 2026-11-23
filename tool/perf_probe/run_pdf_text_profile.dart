import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
// The CLI uses the same engine pinned transitively by pdfrx.
// ignore: depend_on_referenced_packages
import 'package:pdfrx_engine/pdfrx_engine.dart';

import 'pdf_text_fixture.dart';
import 'src/pdf_text_profile.dart';
import 'src/pdf_text_profile_report.dart';

const pdfTextFixtureQueries = [
  PdfTextProfileQuery.literal('literal_hebrew', 'שלום'),
  PdfTextProfileQuery.regex('niqqud_tolerant', pdfTextNiqqudPattern),
  PdfTextProfileQuery.regex('niqqud_marks', r'[\u0591-\u05C7]'),
  PdfTextProfileQuery.literal('latin_case_insensitive', 'pdf'),
  PdfTextProfileQuery.literal(
    'latin_case_sensitive',
    'pdf',
    caseSensitive: true,
  ),
  PdfTextProfileQuery.regex('two_columns', 'טור (ימין|שמאל)'),
  PdfTextProfileQuery.literal('no_match', 'מילהשאינהבקורפוס'),
  PdfTextProfileQuery.regex('zero_length', r'(?=ש)'),
];

/// משווה את כל המדידות לציפיות קלט ידועות, בנוסף ל-parity של הליבה.
void validatePdfTextCorpusResults(Map<String, Object?> profile) {
  validatePdfTextProfileReport(profile);
  final configuration = profile['configuration'] as Map<String, Object?>;
  final numbers = configuration['pageNumbers'] as List;
  if (configuration['normalizeHebrewText'] != true ||
      configuration['decodeLegacyHebrewText'] != true ||
      numbers.length != pdfTextFixturePageCount ||
      !List.generate(pdfTextFixturePageCount, (i) => i + 1).every(
        numbers.contains,
      ) ||
      jsonEncode(configuration['queries']) !=
          jsonEncode([
            for (final query in pdfTextFixtureQueries) query.toJson(),
          ])) {
    throw StateError('The measured corpus/query configuration changed');
  }
  for (final value in profile['observations'] as List) {
    final row = value as Map<String, Object?>;
    final expected = pdfTextExpectedMatches(row['pageNumber'] as int);
    for (final value in row['queries'] as List) {
      final query = value as Map<String, Object?>;
      final count = expected[query['id']];
      if (count == null ||
          query['matches'] != count ||
          (count > 0 ? (query['rects'] as int) < count : query['rects'] != 0)) {
        throw StateError(
          'Unexpected ${query['id']} matches/rects on page ${row['pageNumber']}',
        );
      }
    }
  }
}

Future<void> main(List<String> arguments) async {
  Directory? output;
  final cleanupErrors = <String>[];
  try {
    final options = _arguments(arguments);
    final requested = Directory(options['output']!);
    if (await requested.exists()) {
      throw ArgumentError('Output directory must be new: ${requested.path}');
    }
    output = await requested.create(recursive: true);
    final font = File(options['font']!);
    final pdfium = File(options['pdfium']!);
    final expectedHash = options['pdfium-sha256']!;
    final warmup = int.parse(options['warmup'] ?? '1');
    final repetitions = int.parse(options['repetitions'] ?? '5');
    if (warmup < 0 || repetitions < 1) {
      throw ArgumentError('Invalid warmup/repetitions');
    }
    final pdfiumHash = await _hash(pdfium);
    if (pdfiumHash != expectedHash) {
      throw StateError('PDFium SHA-256 does not match the requested binary');
    }
    final input = File('${output.path}/corpus.pdf');
    final corpus = await writePdfTextFixture(input, fontFile: font);
    await _writeJson(File('${output.path}/corpus.json'), corpus);
    final cache = await Directory('${output.path}/native-cache').create();
    Pdfrx.pdfiumModulePath = await pdfium.resolveSymbolicLinks();
    Pdfrx.normalizeHebrewText = true;
    Pdfrx.decodeLegacyHebrewText = true;
    PdfDocument? document;
    RandomAccessFile? observations;
    Map<String, Object?>? profile;
    Map<String, Object?>? validation;
    Object? failure;
    StackTrace? failureStack;
    try {
      await pdfrxInitialize(tmpPath: cache.path);
      document = await PdfDocument.openFile(input.path);
      validation = await validatePdfTextFixture(
        document,
        rasterDirectory: Directory('${output.path}/rasters'),
      );
      await _writeJson(
        File('${output.path}/corpus-validation.json'),
        validation,
      );
      observations = File('${output.path}/observations.jsonl').openSync(
        mode: FileMode.writeOnly,
      );
      profile = await runPdfTextProfile(
        document: document,
        queries: pdfTextFixtureQueries,
        warmup: warmup,
        repetitions: repetitions,
        onObservation: (row) {
          observations!.writeStringSync('${jsonEncode(row)}\n');
        },
      );
      validatePdfTextCorpusResults(profile);
    } catch (error, stack) {
      failure = error;
      failureStack = stack;
    } finally {
      for (final close in <Future<void> Function()>[
        () async => observations?.closeSync(),
        () async => document?.dispose(),
        () => PdfrxEntryFunctions.instance.stopBackgroundWorker(),
      ]) {
        try {
          await close();
        } catch (error, stack) {
          cleanupErrors.add(error.toString());
          if (failure == null) {
            failure = error;
            failureStack = stack;
          }
        }
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
    if (profile == null || validation == null) {
      throw StateError('Missing complete native profile');
    }
    if (await _hash(input) != corpus['sha256'] ||
        await _hash(pdfium) != pdfiumHash ||
        await _hash(font) != corpus['fontSha256']) {
      throw StateError('Corpus, font or native library changed during the run');
    }
    await _writeJson(File('${output.path}/report.json'), {
      'protocolVersion': 1,
      'status': 'passed',
      'component': 'pdfrx-public-text-pipeline',
      'executionMode': const String.fromEnvironment(
        'PDF_TEXT_PROFILE_MODE',
        defaultValue: 'dart-jit-validation',
      ),
      'dartVersion': Platform.version,
      'operatingSystem': Platform.operatingSystem,
      'operatingSystemVersion': Platform.operatingSystemVersion,
      'processors': Platform.numberOfProcessors,
      'pdfiumSha256': pdfiumHash,
      'pdfiumBytes': await pdfium.length(),
      'corpus': corpus,
      'corpusValidation': validation,
      'profile': profile,
      'uiLatencyCollected': false,
      'nativeTransferSeparated': false,
      'osCacheCleared': false,
    });
    stdout.writeln(
      jsonEncode({
        'status': 'passed',
        'output': output.absolute.path,
        'corpusSha256': corpus['sha256'],
        'summary': profile['summary'],
      }),
    );
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    if (output != null && await output.exists()) {
      try {
        await _writeJson(File('${output.path}/failure.json'), {
          'status': 'failed',
          'error': error.toString(),
          'stack': stack.toString(),
          'cleanupErrors': cleanupErrors,
        });
      } catch (reportError) {
        stderr.writeln('Could not preserve failure report: $reportError');
      }
    }
    exitCode = 1;
  }
}

Map<String, String> _arguments(List<String> arguments) {
  const allowed = {
    'output',
    'font',
    'pdfium',
    'pdfium-sha256',
    'warmup',
    'repetitions',
  };
  final result = <String, String>{};
  for (var index = 0; index < arguments.length; index += 2) {
    final key = arguments[index];
    if (!key.startsWith('--') ||
        !allowed.contains(key.substring(2)) ||
        index + 1 == arguments.length ||
        result.containsKey(key.substring(2))) {
      throw ArgumentError('Unknown, duplicate or incomplete argument: $key');
    }
    result[key.substring(2)] = arguments[index + 1];
  }
  for (final required in ['output', 'font', 'pdfium', 'pdfium-sha256']) {
    if (result[required]?.isNotEmpty != true) {
      throw ArgumentError('Missing --$required');
    }
  }
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(result['pdfium-sha256']!)) {
    throw ArgumentError('Invalid --pdfium-sha256');
  }
  return result;
}

Future<String> _hash(File file) async =>
    (await sha256.bind(file.openRead()).single).toString();

Future<void> _writeJson(File file, Object? value) async {
  await file.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(value)}\n',
    flush: true,
  );
}
