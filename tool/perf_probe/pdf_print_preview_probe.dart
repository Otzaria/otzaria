// This manual Flutter test intentionally lives outside the test directory.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/printing/print_pdf_source.dart';
import 'package:otzaria/printing/print_preview_controller.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:vm_service/vm_service.dart' as vm;
import 'package:vm_service/vm_service_io.dart';

// Manual probe: flutter test tool/perf_probe/pdf_print_preview_probe.dart
// --enable-vmservice --no-dds --concurrency=1. No timing thresholds enter CI.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'probe: PDF print preview pipeline',
    runPdfPrintPreviewProbe,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Future<void> runPdfPrintPreviewProbe({
  String runner = 'flutter-test-debug',
}) async {
  final file = File(_requiredEnvironment('OTZARIA_PREVIEW_PDF'));
  final source = Platform.environment['OTZARIA_PREVIEW_SOURCE'] ?? 'bytes';
  final pipeline = Platform.environment['OTZARIA_PREVIEW_PIPELINE'] ?? 'png';
  final cancel = Platform.environment['OTZARIA_PREVIEW_CANCEL'] ?? 'none';
  if (!['bytes', 'file'].contains(source) ||
      !['png', 'direct', 'controller'].contains(pipeline) ||
      !['none', 'after-render', 'during-render'].contains(cancel)) {
    throw ArgumentError(
      'source: bytes/file; pipeline: png/direct/controller; '
      'cancel: none/after-render/during-render',
    );
  }
  final limit = _environmentInt('OTZARIA_PREVIEW_LIMIT', 60);
  final firstPage = _environmentInt('OTZARIA_PREVIEW_START', 1);
  final visiblePages = _environmentInt('OTZARIA_PREVIEW_VISIBLE', 2);
  final budget = _environmentInt('OTZARIA_PREVIEW_BUDGET_MIB', 32) << 20;
  final scale = double.parse(
    Platform.environment['OTZARIA_PREVIEW_SCALE'] ?? '1.5',
  );
  if (!scale.isFinite || scale <= 0) throw ArgumentError('Invalid scale');

  Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
  await pdfrxFlutterInitialize();
  if (pipeline == 'controller') {
    await _measureController(
      file: file,
      fromFile: source == 'file',
      startPage: firstPage,
      budget: budget,
      cancel: cancel,
      runner: runner,
    );
    return;
  }
  final profiler = await _AllocationProfiler.connect();
  await profiler?.reset();

  final memory = _ProcessMemorySample()..start();
  final total = Stopwatch()..start();
  final phases = <String, int>{};
  final cache = <int, ui.Image>{};
  final pngs = <Uint8List>[];
  final decodes = <Future<void>>[];
  var cacheBytes = 0;
  var peakCacheBytes = 0;
  var rendered = 0;
  var encoded = 0;
  var decoded = 0;
  var canceled = false;
  int? canceledAtUs;
  int? firstReadyUs;
  int? firstPreviewAvailableUs;
  int? firstEncodedPngReadyUs;
  int? documentClosedUs;
  int? firstImageWidth;
  int? firstImageHeight;
  var pageCount = 0;
  Uint8List? cachedSource;
  Timer? cancellationTimer;
  PdfDocument? document;
  try {
    final open = Stopwatch()..start();
    if (source == 'file') {
      document = await PdfDocument.openFile(
        file.path,
        useProgressiveLoading: false,
      );
    } else {
      final bytes = await file.readAsBytes();
      cachedSource = bytes;
      phases['readFileUs'] = open.elapsedMicroseconds;
      document = await PdfDocument.openCustom(
        read: (buffer, position, size) {
          final count = min(size, bytes.length - position);
          if (count <= 0) return 0;
          buffer.setRange(0, count, bytes, position);
          return count;
        },
        fileSize: bytes.length,
        sourceName: 'preview-probe-${file.path}',
        maxSizeToCacheOnMemory: 1024 * 1024 * 1024,
        useProgressiveLoading: false,
      );
    }
    phases['openIncludingReadUs'] = open.elapsedMicroseconds;
    pageCount = document.pages.length;
    final start = (firstPage - 1).clamp(0, pageCount - 1);
    final end = min(pageCount, start + limit);
    memory.sample();
    for (var index = start; index < end; index++) {
      final page = document.pages[index];
      final token = pipeline == 'direct'
          ? page.createCancellationToken()
          : null;
      void requestCancellation() {
        canceled = true;
        canceledAtUs ??= total.elapsedMicroseconds;
        token?.cancel();
      }

      if (cancel == 'during-render') {
        cancellationTimer = Timer(
          const Duration(milliseconds: 1),
          requestCancellation,
        );
      }
      final render = Stopwatch()..start();
      final pixels = await page.render(
        fullWidth: page.width * scale,
        fullHeight: page.height * scale,
        backgroundColor: 0xffffffff,
        cancellationToken: token,
      );
      _addPhase(phases, 'renderUs', render.elapsedMicroseconds);
      if (pixels == null) break;
      rendered++;
      if (cancel == 'after-render') requestCancellation();
      ui.Image? image;
      try {
        if (pipeline == 'direct' && canceled) break;
        final create = Stopwatch()..start();
        image = await pixels.createImage();
        _addPhase(phases, 'createImageUs', create.elapsedMicroseconds);
      } finally {
        pixels.dispose();
      }
      if (pipeline == 'png') {
        late Uint8List png;
        try {
          final encode = Stopwatch()..start();
          final data = (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!;
          _addPhase(phases, 'encodePngUs', encode.elapsedMicroseconds);
          png = data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
          encoded++;
          firstEncodedPngReadyUs ??= total.elapsedMicroseconds;
        } finally {
          image.dispose();
          image = null;
        }
        if (!canceled) {
          pngs.add(png);
          firstPreviewAvailableUs ??= total.elapsedMicroseconds;
          // dev@2ba2e6d publishes each PNG from onPage immediately. Model the
          // visible Image.memory decodes concurrently with later PDF renders;
          // this measures image readiness, not framework scheduling or paint.
          if (index - start < visiblePages) {
            decodes.add(() async {
              final decode = Stopwatch()..start();
              final image = await _decode(png);
              decoded++;
              _addPhase(phases, 'decodePngUs', decode.elapsedMicroseconds);
              cache[index] = image;
              cacheBytes += image.width * image.height * 4;
              peakCacheBytes = max(peakCacheBytes, cacheBytes);
              if (index == start) {
                firstReadyUs = total.elapsedMicroseconds;
                firstImageWidth = image.width;
                firstImageHeight = image.height;
              }
              memory.sample();
            }());
          }
        }
      }
      if (image != null) {
        if (canceled) {
          image.dispose();
        } else {
          final bytes = image.width * image.height * 4;
          while (cache.isNotEmpty && cacheBytes + bytes > budget) {
            final removed = cache.remove(cache.keys.first)!;
            cacheBytes -= removed.width * removed.height * 4;
            removed.dispose();
          }
          cache[index] = image;
          cacheBytes += bytes;
          peakCacheBytes = max(peakCacheBytes, cacheBytes);
          if (firstReadyUs == null) {
            firstReadyUs = total.elapsedMicroseconds;
            firstPreviewAvailableUs = firstReadyUs;
            firstImageWidth = image.width;
            firstImageHeight = image.height;
          }
        }
      }
      memory.sample();
      if (canceled) break;
    }
    final close = Stopwatch()..start();
    await document.dispose();
    document = null;
    phases['closeUs'] = close.elapsedMicroseconds;
    documentClosedUs = total.elapsedMicroseconds;
    await Future.wait(decodes);
    total.stop();
    memory.stop();
    final allocations = await profiler?.read();
    final result = <String, Object?>{
      'pid': pid,
      'mode': runner,
      'platform': Platform.operatingSystem,
      'dart': Platform.version,
      'file': file.uri.pathSegments.last,
      'fileBytes': await file.length(),
      'source': source,
      'pipeline': pipeline,
      'pageCount': pageCount,
      'firstPage': firstPage,
      'renderLimit': limit,
      'visibleDecodeLimit': visiblePages,
      'scale': scale,
      'cancel': cancel,
      'firstPreviewAvailableUs': firstPreviewAvailableUs,
      'firstEncodedPngReadyUs': firstEncodedPngReadyUs,
      'firstImageReadyUs': firstReadyUs,
      'firstImageWidth': firstImageWidth,
      'firstImageHeight': firstImageHeight,
      'totalUs': total.elapsedMicroseconds,
      'documentClosedUs': documentClosedUs,
      'cancelToDocumentClosedUs': canceledAtUs == null
          ? null
          : documentClosedUs - canceledAtUs!,
      'renderedPages': rendered,
      'encodedPages': encoded,
      'decodedPages': decoded,
      'retainedPngBytes': pngs.fold<int>(0, (n, bytes) => n + bytes.length),
      'retainedSourceDartBytes': cachedSource?.length ?? 0,
      'retainedUiImages': cache.length,
      'peakCachePixelBytes': peakCacheBytes,
      'cacheBudgetBytes': budget,
      ...phases,
      ...memory.toJson(),
      'dartAllocations': allocations,
    };
    await _writeResult(result);
    _require(pageCount > 0, 'Document has no pages');
    if (cancel == 'none') {
      _require(firstReadyUs != null, 'No preview image was produced');
    }
    if (pipeline == 'direct') _require(encoded == 0, 'Unexpected PNG encoding');
  } finally {
    cancellationTimer?.cancel();
    memory.stop();
    await document?.dispose();
    await Future.wait(decodes);
    for (final image in cache.values) {
      image.dispose();
    }
    await profiler?.dispose();
  }
}

Future<void> _measureController({
  required File file,
  required bool fromFile,
  required int startPage,
  required int budget,
  required String cancel,
  required String runner,
}) async {
  final profiler = await _AllocationProfiler.connect();
  await profiler?.reset();
  final memory = _ProcessMemorySample()..start();
  final total = Stopwatch()..start();
  var tail = Future<void>.value();
  final controller = PrintPreviewController(
    maximumBytes: budget,
    serialize: (action) async {
      final previous = tail;
      final complete = Completer<void>();
      tail = complete.future;
      try {
        await previous;
        await action();
      } finally {
        complete.complete();
      }
    },
  );
  final cells = _environmentInt('OTZARIA_PREVIEW_NUP', 1);
  final endValue = Platform.environment['OTZARIA_PREVIEW_END'];
  final endPage = endValue == null ? null : int.parse(endValue);
  controller.reset(pagesPerSheet: cells);
  var stale = false;
  int? canceledAtUs;
  int? firstReadyUs;
  int? firstImageWidth;
  int? firstImageHeight;
  var peakCacheBytes = 0;
  var peakCachedImages = 0;
  var selectedPages = 0;
  var documentPages = 0;
  Timer? timer;
  void requestCancellation() {
    if (stale) return;
    stale = true;
    canceledAtUs = total.elapsedMicroseconds;
    controller.reset(pagesPerSheet: cells);
  }

  void sampleCache() {
    peakCacheBytes = max(peakCacheBytes, controller.estimatedBytes);
    peakCachedImages = max(peakCachedImages, controller.cachedImageCount);
  }

  controller.addListener(() {
    selectedPages = max(selectedPages, controller.pageCount);
    sampleCache();
    if (firstReadyUs == null) {
      final image = controller.image(0);
      if (image != null) {
        firstReadyUs = total.elapsedMicroseconds;
        firstImageWidth = image.width;
        firstImageHeight = image.height;
        if (cancel == 'after-render') scheduleMicrotask(requestCancellation);
      }
    }
    memory.sample();
  });
  final cacheSampler = Timer.periodic(
    const Duration(milliseconds: 10),
    (_) => sampleCache(),
  );
  try {
    final read = Stopwatch()..start();
    final data = fromFile ? null : await file.readAsBytes();
    final readFileUs = read.elapsedMicroseconds;
    final source = data == null
        ? PrintPdfSource.file(file.path)
        : PrintPdfSource.data(data);
    if (cancel == 'during-render') {
      timer = Timer(const Duration(milliseconds: 1), requestCancellation);
    }
    await controller.load(
      source,
      startPage: startPage,
      endPage: endPage,
      isStale: () => stale,
      onPageCount: (count) => documentPages = count,
    );
    final initialWindowReadyUs = total.elapsedMicroseconds;
    final viewports = <Map<String, Object?>>[];
    final requestedSheets =
        (Platform.environment['OTZARIA_PREVIEW_SCROLL_SHEETS'] ?? '')
            .split(',')
            .where((value) => value.trim().isNotEmpty)
            .map((value) => int.parse(value.trim()));
    if (cancel == 'none') {
      for (final sheet in requestedSheets) {
        _require(
          sheet >= 0 && sheet * cells < controller.pageCount,
          'Requested sheet is outside the selected range',
        );
        final watch = Stopwatch()..start();
        controller.showSheets({sheet});
        await tail;
        final image = controller.image(sheet * cells);
        _require(image != null, 'Requested viewport has no image');
        viewports.add({
          'sheetIndex': sheet,
          'readyAndDocumentClosedUs': watch.elapsedMicroseconds,
          'cachedImages': controller.cachedImageCount,
          'estimatedCacheBytes': controller.estimatedBytes,
          'firstImageWidth': image?.width,
          'firstImageHeight': image?.height,
        });
        memory.sample();
      }
    }
    total.stop();
    cacheSampler.cancel();
    memory.stop();
    final allocations = await profiler?.read();
    await _writeResult({
      'pid': pid,
      'mode': runner,
      'platform': Platform.operatingSystem,
      'dart': Platform.version,
      'file': file.uri.pathSegments.last,
      'fileBytes': await file.length(),
      'source': fromFile ? 'file' : 'bytes',
      'pipeline': 'controller',
      'pageCount': documentPages,
      'selectedPages': selectedPages,
      'firstPage': startPage,
      'endPage': endPage,
      'pagesPerSheet': cells,
      'firstPreviewAvailableUs': firstReadyUs,
      'firstImageReadyUs': firstReadyUs,
      'firstImageWidth': firstImageWidth,
      'firstImageHeight': firstImageHeight,
      'initialWindowReadyAndDocumentClosedUs': initialWindowReadyUs,
      'viewportRequests': viewports,
      'totalUs': total.elapsedMicroseconds,
      'readFileUs': fromFile ? 0 : readFileUs,
      'cancel': cancel,
      'cancellationPoint': cancel == 'after-render'
          ? 'after first image publication'
          : cancel == 'during-render'
          ? '1 ms after load request'
          : null,
      'cancelToDocumentClosedUs': canceledAtUs == null
          ? null
          : total.elapsedMicroseconds - canceledAtUs!,
      'peakCachedImages': peakCachedImages,
      'retainedUiImages': controller.cachedImageCount,
      'pngEncodingUsed': false,
      'sampledPeakCacheBudgetBytes': peakCacheBytes,
      'cacheBudgetBytes': budget,
      'retainedSourceDartBytes': data?.length ?? 0,
      ...memory.toJson(),
      'dartAllocations': allocations,
    });
    _require(!controller.failed, 'Preview controller failed');
    _require(peakCacheBytes <= budget, 'Preview cache exceeded its budget');
    if (cancel == 'none') {
      _require(firstReadyUs != null, 'No preview image was produced');
    }
  } finally {
    timer?.cancel();
    cacheSampler.cancel();
    controller.dispose();
    await tail;
    memory.stop();
    await profiler?.dispose();
  }
}

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> _writeResult(Map<String, Object?> result) async {
  stdout.writeln('PDF_PRINT_PREVIEW_PERF ${jsonEncode(result)}');
  final output = Platform.environment['OTZARIA_PREVIEW_RESULT'];
  if (output != null) {
    await File(output).writeAsString('${jsonEncode(result)}\n');
  }
}

Future<ui.Image> _decode(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

void _addPhase(Map<String, int> phases, String name, int microseconds) {
  phases.update(
    name,
    (previous) => previous + microseconds,
    ifAbsent: () => microseconds,
  );
}

String _requiredEnvironment(String name) {
  final value = Platform.environment[name];
  if (value == null || value.isEmpty) throw ArgumentError('Set $name');
  return value;
}

int _environmentInt(String name, int fallback) {
  final value = int.parse(Platform.environment[name] ?? '$fallback');
  if (value <= 0) throw ArgumentError('$name must be positive');
  return value;
}

class _ProcessMemorySample {
  Timer? _timer;
  int _baselineRss = 0;
  int _peakRss = 0;
  int? _baselinePrivateResident;
  int? _peakPrivateResident;

  void start() {
    _baselineRss = ProcessInfo.currentRss;
    _baselinePrivateResident = _privateResident();
    sample();
    _timer = Timer.periodic(const Duration(milliseconds: 10), (_) => sample());
  }

  void sample() {
    _peakRss = max(_peakRss, ProcessInfo.currentRss);
    final resident = _privateResident();
    if (resident != null) {
      _peakPrivateResident = max(_peakPrivateResident ?? 0, resident);
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    sample();
  }

  int? _privateResident() {
    if (!Platform.isLinux) return null;
    final status = File('/proc/self/smaps_rollup').readAsStringSync();
    return RegExp(r'^Private_(?:Clean|Dirty):\s+(\d+) kB$', multiLine: true)
            .allMatches(status)
            .fold<int>(0, (sum, match) => sum + int.parse(match[1]!)) *
        1024;
  }

  Map<String, Object?> toJson() => {
    'baselineRssBytes': _baselineRss,
    'sampledPeakRssBytes': _peakRss,
    'processLifetimePeakRssBytes': ProcessInfo.maxRss,
    'baselinePrivateResidentBytes': _baselinePrivateResident,
    'sampledPeakPrivateResidentBytes': _peakPrivateResident,
    'memorySampleIntervalMs': 10,
  };
}

class _AllocationProfiler {
  _AllocationProfiler(this.service, this.isolateId);
  final vm.VmService service;
  final String isolateId;

  static Future<_AllocationProfiler?> connect() async {
    final info = await developer.Service.getInfo();
    final uri = info.serverUri;
    if (uri == null) return null;
    final service = await vmServiceConnectUri(
      uri.replace(scheme: 'ws', path: '${uri.path}ws').toString(),
    );
    return _AllocationProfiler(
      service,
      developer.Service.getIsolateId(Isolate.current)!,
    );
  }

  Future<void> reset() async {
    await service.getAllocationProfile(isolateId, gc: true, reset: true);
  }

  Future<Map<String, Object?>> read() async {
    final profile = await service.getAllocationProfile(isolateId);
    final classes = profile.members ?? const <vm.ClassHeapStats>[];
    final supported =
        classes.isNotEmpty &&
        classes.every(
          (entry) =>
              (entry.instancesAccumulated ?? -1) >= 0 &&
              (entry.accumulatedSize ?? -1) >= 0,
        );
    return {
      'scope': 'current Dart isolate; excludes native and worker allocations',
      'accumulatorsSupported': supported,
      'allocatedInstances': supported
          ? classes.fold<int>(0, (n, item) => n + item.instancesAccumulated!)
          : null,
      'allocatedBytes': supported
          ? classes.fold<int>(0, (n, item) => n + item.accumulatedSize!)
          : null,
      'heapUsageBytes': profile.memoryUsage?.heapUsage,
      'externalUsageBytes': profile.memoryUsage?.externalUsage,
    };
  }

  Future<void> dispose() => service.dispose();
}
