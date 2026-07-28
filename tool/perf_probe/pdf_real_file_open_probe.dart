import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/pdf_headings.dart';
import 'package:otzaria/pdf_book/utils/pdf_links_window.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/utils/text/ref_helper.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';
import 'package:path/path.dart' as path;

const _probeModeVariable = 'OTZARIA_PDF_PROBE_MODE';
const _talmudPdfVariable = 'OTZARIA_TALMUD_PDF';
const _issue586PdfVariable = 'OTZARIA_ISSUE_586_PDF';
const _libraryPathVariable = 'OTZARIA_LIBRARY_PATH';
const _defaultLibraryFolderName = 'otzaria';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mode = _readProbeMode();
  final runSynthetic =
      mode == _PdfProbeMode.synthetic || mode == _PdfProbeMode.all;
  final runReal = mode == _PdfProbeMode.real || mode == _PdfProbeMode.all;
  final runIssue586 =
      mode == _PdfProbeMode.issue586 || mode == _PdfProbeMode.all;
  final talmudPdf = runReal
      ? _requiredFile(_talmudPdfVariable, 'PDF תלמוד למדידה')
      : null;
  final issue586Pdf = runIssue586
      ? _requiredFile(_issue586PdfVariable, 'PDF לרפרודוקציית pdfrx #586')
      : null;
  final libraryPath = runReal
      ? _requiredEnvironmentValue(
          _libraryPathVariable,
          'שורש ספריית אוצריא המכיל את מסד הנתונים',
        )
      : null;
  final targetPage = _environmentInt('OTZARIA_TALMUD_TARGET_PAGE', 20);
  final issue586TargetPage = _environmentInt(
    'OTZARIA_ISSUE_586_TARGET_PAGE',
    229,
  );
  final libraryFolderName =
      Platform.environment['OTZARIA_LIBRARY_FOLDER'] ??
      _defaultLibraryFolderName;

  Directory? fixtureDirectory;

  setUpAll(() async {
    fixtureDirectory = await Directory.systemTemp.createTemp(
      'otzaria_pdf_open_performance_',
    );
    final initialization = Stopwatch()..start();
    await pdfrxInitialize(tmpPath: fixtureDirectory!.path);
    initialization.stop();
    _printMetric('engine-initialization', {
      'elapsedMs': initialization.elapsedMilliseconds,
    });
  });

  tearDownAll(() async {
    if (runReal) {
      await SqliteDataProvider.instance.dispose();
    }
    final directory = fixtureDirectory;
    if (directory != null && directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  });

  if (runSynthetic) {
    test('probe: פתיחת PDF רגיל', () async {
      final regularPdf = File(
        path.join(fixtureDirectory!.path, 'regular-12-pages.pdf'),
      );
      await _createPdf(regularPdf, pageCount: 12);
      final result = await _measureProgressiveOpen(
        scenario: 'regular-pdf',
        file: regularPdf,
        targetPage: 1,
      );

      expect(result.pageCount, 12);
      expect(result.renderedWidth, greaterThan(0));
      expect(result.renderedHeight, greaterThan(0));
    });

    test(
      'probe: פתיחת מסמך בן מאות עמודים באמצעו',
      () async {
        final largePdf = File(
          path.join(fixtureDirectory!.path, 'large-600-pages.pdf'),
        );
        await _createPdf(largePdf, pageCount: 600);
        final result = await _measureProgressiveOpen(
          scenario: 'large-pdf-middle',
          file: largePdf,
          targetPage: 300,
        );

        expect(result.pageCount, 600);
        expect(result.targetPage, 300);
        expect(result.renderedWidth, greaterThan(0));
        expect(result.renderedHeight, greaterThan(0));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }

  if (runReal) {
    test(
      'probe: פתיחת PDF מתלמוד בבלי עם outline וקישורי האפליקציה',
      () async {
        final result = await _measureProgressiveOpen(
          scenario: 'talmud-bavli-pdf',
          file: talmudPdf!,
          targetPage: targetPage,
          inspectLinks: true,
        );

        expect(result.outlineEntries, greaterThan(0));
        expect(result.renderedWidth, greaterThan(0));
        expect(result.renderedHeight, greaterThan(0));

        await _measureStandardOpen(
          scenario: 'talmud-bavli-standard-loading',
          file: talmudPdf,
          targetPage: targetPage,
        );

        final linksResult = await _measureTalmudAppLinks(
          pdfFile: talmudPdf,
          targetReference: result.targetReference,
          libraryPath: libraryPath!,
          libraryFolderName: libraryFolderName,
        );
        if (linksResult == null) {
          fail(
            'מסד הספרייה או ספר הטקסט המקביל לא נמצאו עבור ${talmudPdf.path}',
          );
        }
        expect(linksResult.summaryTargets, greaterThan(0));
        expect(linksResult.windowLinks, greaterThan(0));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }

  if (runIssue586) {
    test(
      'probe: רפרודוקציה ל-pdfrx #586',
      () async {
        final progressive = await _measureProgressiveOpen(
          scenario: 'pdfrx-586-progressive',
          file: issue586Pdf!,
          targetPage: issue586TargetPage,
        );
        await _measureStandardOpen(
          scenario: 'pdfrx-586-standard',
          file: issue586Pdf,
          targetPage: issue586TargetPage,
        );

        expect(
          progressive.pageCount,
          greaterThanOrEqualTo(issue586TargetPage),
        );
        expect(
          progressive.pagesWithChangedMetricsBeforeTarget,
          greaterThan(0),
        );
      },
      timeout: const Timeout(Duration(minutes: 1)),
    );
  }
}

enum _PdfProbeMode { synthetic, real, issue586, all }

_PdfProbeMode _readProbeMode() {
  final raw =
      Platform.environment[_probeModeVariable]?.trim().toLowerCase() ??
      'synthetic';
  for (final mode in _PdfProbeMode.values) {
    if (mode.name == raw) return mode;
  }
  throw ArgumentError(
    '$_probeModeVariable חייב להיות אחד מהערכים: '
    '${_PdfProbeMode.values.map((mode) => mode.name).join(', ')}',
  );
}

File _requiredFile(String variable, String description) {
  final value = _requiredEnvironmentValue(variable, description);
  final file = File(value);
  if (!file.existsSync()) {
    throw ArgumentError('$description אינו קיים: $value');
  }
  return file;
}

String _requiredEnvironmentValue(String variable, String description) {
  final value = Platform.environment[variable]?.trim();
  if (value == null || value.isEmpty) {
    throw ArgumentError(
      'חסר $variable — יש להגדיר $description לפני הרצת ה-probe',
    );
  }
  return value;
}

int _environmentInt(String variable, int fallback) {
  final raw = Platform.environment[variable]?.trim();
  if (raw == null || raw.isEmpty) return fallback;
  final value = int.tryParse(raw);
  if (value == null || value < 1) {
    throw ArgumentError('$variable חייב להיות מספר עמוד חיובי; התקבל: $raw');
  }
  return value;
}

Future<void> _createPdf(File file, {required int pageCount}) async {
  final document = pw.Document(compress: true);
  for (var pageNumber = 1; pageNumber <= pageCount; pageNumber++) {
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (_) => pw.Center(
          child: pw.Container(
            width: 100 + (pageNumber % 20).toDouble(),
            height: 80,
            decoration: pw.BoxDecoration(border: pw.Border.all()),
          ),
        ),
      ),
    );
  }
  await file.writeAsBytes(await document.save(), flush: true);
}

Future<_OpenMeasurement> _measureProgressiveOpen({
  required String scenario,
  required File file,
  required int targetPage,
  bool inspectLinks = false,
}) async {
  final total = Stopwatch()..start();
  final open = Stopwatch()..start();
  final document = await PdfDocument.openFile(
    file.path,
    useProgressiveLoading: true,
  );
  open.stop();
  final initialPageMetrics = [
    for (final page in document.pages) (width: page.width, height: page.height),
  ];

  try {
    final resolvedTarget = targetPage.clamp(1, document.pages.length);
    final targetLoaded = Completer<int>();
    final progressive = Stopwatch()..start();
    final progressiveFuture = document.loadPagesProgressively(
      onPageLoadProgress: (currentPageNumber, _, _) {
        if (!targetLoaded.isCompleted && currentPageNumber >= resolvedTarget) {
          targetLoaded.complete(progressive.elapsedMilliseconds);
        }
        return true;
      },
    );

    final outline = Stopwatch()..start();
    final outlineFuture = document.loadOutline().whenComplete(outline.stop);

    final targetLoadedMs = document.pages[resolvedTarget - 1].isLoaded
        ? 0
        : await targetLoaded.future;
    final page = await document.pages[resolvedTarget - 1].ensureLoaded();

    final render = Stopwatch()..start();
    final image = await page.render(fullWidth: 1200, fullHeight: 1600);
    render.stop();

    final links = Stopwatch()..start();
    final pageLinks = inspectLinks
        ? await page.loadLinks(compact: true)
        : const <PdfLink>[];
    links.stop();

    await progressiveFuture;
    progressive.stop();
    final layoutDrift = _measureLayoutDrift(
      initialPageMetrics,
      document.pages,
      resolvedTarget,
    );
    final outlineNodes = await outlineFuture;
    total.stop();
    final targetReference = referenceFromPageNumber(
      resolvedTarget,
      outlineNodes,
      path.basenameWithoutExtension(file.path),
    );

    final measurement = _OpenMeasurement(
      fileSizeBytes: file.lengthSync(),
      pageCount: document.pages.length,
      targetPage: resolvedTarget,
      openMs: open.elapsedMilliseconds,
      targetLoadedMs: targetLoadedMs,
      targetRenderMs: render.elapsedMilliseconds,
      allPagesLoadedMs: progressive.elapsedMilliseconds,
      outlineMs: outline.elapsedMilliseconds,
      outlineEntries: _countOutlineEntries(outlineNodes),
      linksMs: links.elapsedMilliseconds,
      linksOnTargetPage: pageLinks.length,
      totalMs: total.elapsedMilliseconds,
      renderedWidth: image?.width ?? 0,
      renderedHeight: image?.height ?? 0,
      targetReference: targetReference,
      pagesWithChangedMetricsBeforeTarget:
          layoutDrift.pagesWithChangedMetricsBeforeTarget,
      targetOffsetDeltaPoints: layoutDrift.targetOffsetDeltaPoints,
      absoluteHeightDeltaPoints: layoutDrift.absoluteHeightDeltaPoints,
    );
    image?.dispose();
    _printMetric(scenario, measurement.toJson());
    return measurement;
  } finally {
    await document.dispose();
  }
}

({
  int pagesWithChangedMetricsBeforeTarget,
  int targetOffsetDeltaPoints,
  int absoluteHeightDeltaPoints,
})
_measureLayoutDrift(
  List<({double width, double height})> initialMetrics,
  List<PdfPage> loadedPages,
  int targetPage,
) {
  var changedPages = 0;
  var targetOffsetDelta = 0.0;
  var absoluteHeightDelta = 0.0;
  final pagesBeforeTarget = targetPage - 1;
  for (var index = 0; index < pagesBeforeTarget; index++) {
    final initial = initialMetrics[index];
    final loaded = loadedPages[index];
    final widthChanged = (loaded.width - initial.width).abs() > 0.01;
    final heightDelta = loaded.height - initial.height;
    if (widthChanged || heightDelta.abs() > 0.01) {
      changedPages++;
      targetOffsetDelta += heightDelta;
      absoluteHeightDelta += heightDelta.abs();
    }
  }
  return (
    pagesWithChangedMetricsBeforeTarget: changedPages,
    targetOffsetDeltaPoints: targetOffsetDelta.round(),
    absoluteHeightDeltaPoints: absoluteHeightDelta.round(),
  );
}

Future<void> _measureStandardOpen({
  required String scenario,
  required File file,
  required int targetPage,
}) async {
  final total = Stopwatch()..start();
  final open = Stopwatch()..start();
  final document = await PdfDocument.openFile(
    file.path,
    useProgressiveLoading: false,
  );
  open.stop();

  try {
    final resolvedTarget = targetPage.clamp(1, document.pages.length);
    final render = Stopwatch()..start();
    final image = await document.pages[resolvedTarget - 1].render(
      fullWidth: 1200,
      fullHeight: 1600,
    );
    render.stop();
    total.stop();

    _printMetric(scenario, {
      'fileSizeBytes': file.lengthSync(),
      'pageCount': document.pages.length,
      'targetPage': resolvedTarget,
      'openMs': open.elapsedMilliseconds,
      'targetRenderMs': render.elapsedMilliseconds,
      'totalMs': total.elapsedMilliseconds,
      'renderedWidth': image?.width ?? 0,
      'renderedHeight': image?.height ?? 0,
    });
    image?.dispose();
  } finally {
    await document.dispose();
  }
}

Future<({int summaryTargets, int windowLinks})?> _measureTalmudAppLinks({
  required File pdfFile,
  required String targetReference,
  required String libraryPath,
  required String libraryFolderName,
}) async {
  final databaseFile = File(
    path.join(
      libraryPath,
      libraryFolderName,
      DatabaseConstants.databaseFileName,
    ),
  );
  if (!databaseFile.existsSync()) return null;

  await Settings.init(cacheProvider: _ProbeMemoryCacheProvider());
  await Settings.setValue<String>(
    SettingsRepository.keyLibraryPath,
    libraryPath,
  );
  await Settings.setValue<String>(
    SettingsRepository.keyLibraryFolderName,
    libraryFolderName,
  );
  await Settings.setValue<String>(SettingsRepository.keyDbEffectivePath, '');

  final databaseInitialization = Stopwatch()..start();
  await SqliteDataProvider.instance.initialize();
  databaseInitialization.stop();
  final repository = SqliteDataProvider.instance.repository;
  if (repository == null) return null;

  final title = path.basenameWithoutExtension(pdfFile.path);
  final bookLookup = Stopwatch()..start();
  final textBook = await repository.getBookByTitle(title);
  bookLookup.stop();
  if (textBook == null) return null;

  final headingsLoad = Stopwatch()..start();
  final headings = await PdfHeadings.loadFromDatabase(
    title,
    categoryId: textBook.categoryId,
  );
  headingsLoad.stop();
  final targetLine = headings?.getLineNumberForHeading(targetReference);
  final rangeStart = targetLine ?? 1;
  var rangeEnd = rangeStart + 100;
  for (final heading in headings?.getSortedHeadings() ?? const []) {
    if (heading.value > rangeStart) {
      rangeEnd = heading.value;
      break;
    }
  }
  final window = PdfLinksWindowPolicy.nextWindow(
    rangeStart: rangeStart,
    rangeEnd: rangeEnd,
  )!;

  final provider = DatabaseLibraryProvider.instance;
  final summaryLoad = Stopwatch()..start();
  final summary = await provider.getBookLinkTargetsSummary(
    textBook.title,
    textBook.categoryId,
  );
  summaryLoad.stop();
  if (summary == null) return null;

  const legacyMarginLines = 1500;
  final legacyStart = rangeStart > legacyMarginLines
      ? rangeStart - legacyMarginLines
      : 1;
  final legacyEnd = rangeEnd + legacyMarginLines;
  final legacyWindowLoad = Stopwatch()..start();
  final legacyLinks = await provider.getLinksForBookRange(
    textBook.title,
    textBook.categoryId,
    textBook.fileType ?? 'txt',
    startLineIndex: legacyStart - 1,
    endLineIndex: legacyEnd - 1,
  );
  legacyWindowLoad.stop();

  final windowLoad = Stopwatch()..start();
  final links = await provider.getLinksForBookRange(
    textBook.title,
    textBook.categoryId,
    textBook.fileType ?? 'txt',
    startLineIndex: window.startLine - 1,
    endLineIndex: window.endLine - 1,
  );
  windowLoad.stop();
  final dependentTargets =
      summary.targets
          .where(
            (target) => LinkTypes.isDependentTextLink(target.connectionType),
          )
          .toList()
        ..sort((a, b) => b.linkCount.compareTo(a.linkCount));
  final selectedTarget = dependentTargets.firstOrNull;

  final filteredWindowLoad = Stopwatch()..start();
  final filteredLinks = await provider.getLinksForBookRange(
    textBook.title,
    textBook.categoryId,
    textBook.fileType ?? 'txt',
    startLineIndex: window.startLine - 1,
    endLineIndex: window.endLine - 1,
    targetBookTitles: selectedTarget == null
        ? const []
        : [selectedTarget.targetTitle],
  );
  filteredWindowLoad.stop();

  final narrowStart = rangeStart > 50 ? rangeStart - 50 : 1;
  final narrowEnd = rangeStart + 150;
  final narrowWindowLoad = Stopwatch()..start();
  final narrowLinks = await provider.getLinksForBookRange(
    textBook.title,
    textBook.categoryId,
    textBook.fileType ?? 'txt',
    startLineIndex: narrowStart - 1,
    endLineIndex: narrowEnd - 1,
  );
  narrowWindowLoad.stop();

  final currentPageWindowLoad = Stopwatch()..start();
  final currentPageLinks = await provider.getLinksForBookRange(
    textBook.title,
    textBook.categoryId,
    textBook.fileType ?? 'txt',
    startLineIndex: rangeStart - 1,
    endLineIndex: rangeEnd - 1,
  );
  currentPageWindowLoad.stop();

  final candidateStart = rangeStart > 300 ? rangeStart - 300 : 1;
  final candidateEnd = rangeEnd + 300;
  final candidateWindowLoad = Stopwatch()..start();
  final candidateLinks = await provider.getLinksForBookRange(
    textBook.title,
    textBook.categoryId,
    textBook.fileType ?? 'txt',
    startLineIndex: candidateStart - 1,
    endLineIndex: candidateEnd - 1,
  );
  candidateWindowLoad.stop();

  final currentPageLinksFromWindow = links
      .where(
        (link) => link.index1 >= rangeStart && link.index1 <= rangeEnd,
      )
      .length;
  final currentPageLinksFromLegacyWindow = legacyLinks
      .where(
        (link) => link.index1 >= rangeStart && link.index1 <= rangeEnd,
      )
      .length;
  expect(currentPageLinksFromWindow, currentPageLinks.length);
  expect(currentPageLinksFromLegacyWindow, currentPageLinks.length);

  _printMetric('talmud-bavli-app-links', {
    'databaseFileSizeBytes': databaseFile.lengthSync(),
    'databaseInitializationMs': databaseInitialization.elapsedMilliseconds,
    'bookLookupMs': bookLookup.elapsedMilliseconds,
    'headingsLoadMs': headingsLoad.elapsedMilliseconds,
    'headingsCount': headings?.headingsMap.length ?? 0,
    'targetReference': targetReference,
    'targetLine': targetLine ?? -1,
    'usedFallbackLine': targetLine == null,
    'summaryLoadMs': summaryLoad.elapsedMilliseconds,
    'summaryTargets': summary.targets.length,
    'summaryLinks': summary.targets.fold<int>(
      0,
      (total, target) => total + target.linkCount,
    ),
    'legacyWindowStartLine': legacyStart,
    'legacyWindowEndLine': legacyEnd,
    'legacyWindowLoadMs': legacyWindowLoad.elapsedMilliseconds,
    'legacyWindowLinks': legacyLinks.length,
    'windowStartLine': window.startLine,
    'windowEndLine': window.endLine,
    'windowLoadMs': windowLoad.elapsedMilliseconds,
    'windowLinks': links.length,
    'selectedTarget': selectedTarget?.targetTitle ?? '',
    'selectedTargetLinkCount': selectedTarget?.linkCount ?? 0,
    'filteredWindowLoadMs': filteredWindowLoad.elapsedMilliseconds,
    'filteredWindowLinks': filteredLinks.length,
    'narrowWindowStartLine': narrowStart,
    'narrowWindowEndLine': narrowEnd,
    'narrowWindowLoadMs': narrowWindowLoad.elapsedMilliseconds,
    'narrowWindowLinks': narrowLinks.length,
    'currentPageWindowStartLine': rangeStart,
    'currentPageWindowEndLine': rangeEnd,
    'currentPageWindowLoadMs': currentPageWindowLoad.elapsedMilliseconds,
    'currentPageWindowLinks': currentPageLinks.length,
    'currentPageLinksFromWindow': currentPageLinksFromWindow,
    'currentPageLinksFromLegacyWindow': currentPageLinksFromLegacyWindow,
    'candidateWindowStartLine': candidateStart,
    'candidateWindowEndLine': candidateEnd,
    'candidateWindowLoadMs': candidateWindowLoad.elapsedMilliseconds,
    'candidateWindowLinks': candidateLinks.length,
  });

  return (
    summaryTargets: summary.targets.length,
    windowLinks: links.length,
  );
}

int _countOutlineEntries(List<PdfOutlineNode> nodes) {
  var count = 0;
  for (final node in nodes) {
    count += 1 + _countOutlineEntries(node.children);
  }
  return count;
}

void _printMetric(String scenario, Map<String, Object> values) {
  // פורמט יציב מאפשר להשוות תוצאות בין הרצות בלי לגרד את פלט הטסט.
  debugPrint('PDF_PERF ${jsonEncode({'scenario': scenario, ...values})}');
}

class _OpenMeasurement {
  const _OpenMeasurement({
    required this.fileSizeBytes,
    required this.pageCount,
    required this.targetPage,
    required this.openMs,
    required this.targetLoadedMs,
    required this.targetRenderMs,
    required this.allPagesLoadedMs,
    required this.outlineMs,
    required this.outlineEntries,
    required this.linksMs,
    required this.linksOnTargetPage,
    required this.totalMs,
    required this.renderedWidth,
    required this.renderedHeight,
    required this.targetReference,
    required this.pagesWithChangedMetricsBeforeTarget,
    required this.targetOffsetDeltaPoints,
    required this.absoluteHeightDeltaPoints,
  });

  final int fileSizeBytes;
  final int pageCount;
  final int targetPage;
  final int openMs;
  final int targetLoadedMs;
  final int targetRenderMs;
  final int allPagesLoadedMs;
  final int outlineMs;
  final int outlineEntries;
  final int linksMs;
  final int linksOnTargetPage;
  final int totalMs;
  final int renderedWidth;
  final int renderedHeight;
  final String targetReference;
  final int pagesWithChangedMetricsBeforeTarget;
  final int targetOffsetDeltaPoints;
  final int absoluteHeightDeltaPoints;

  Map<String, Object> toJson() => {
    'fileSizeBytes': fileSizeBytes,
    'pageCount': pageCount,
    'targetPage': targetPage,
    'openMs': openMs,
    'targetLoadedMs': targetLoadedMs,
    'targetRenderMs': targetRenderMs,
    'allPagesLoadedMs': allPagesLoadedMs,
    'outlineMs': outlineMs,
    'outlineEntries': outlineEntries,
    'linksMs': linksMs,
    'linksOnTargetPage': linksOnTargetPage,
    'totalMs': totalMs,
    'renderedWidth': renderedWidth,
    'renderedHeight': renderedHeight,
    'targetReference': targetReference,
    'pagesWithChangedMetricsBeforeTarget': pagesWithChangedMetricsBeforeTarget,
    'targetOffsetDeltaPoints': targetOffsetDeltaPoints,
    'absoluteHeightDeltaPoints': absoluteHeightDeltaPoints,
  };
}

class _ProbeMemoryCacheProvider extends CacheProvider {
  final Map<String, Object?> _values = {};

  @override
  Future<void> init() async {}

  @override
  bool containsKey(String key) => _values.containsKey(key);

  @override
  Set getKeys() => _values.keys.toSet();

  @override
  bool? getBool(String key, {bool? defaultValue}) =>
      _values[key] as bool? ?? defaultValue;

  @override
  double? getDouble(String key, {double? defaultValue}) =>
      _values[key] as double? ?? defaultValue;

  @override
  int? getInt(String key, {int? defaultValue}) =>
      _values[key] as int? ?? defaultValue;

  @override
  String? getString(String key, {String? defaultValue}) =>
      _values[key] as String? ?? defaultValue;

  @override
  T? getValue<T>(String key, {T? defaultValue}) {
    final value = _values[key];
    return value is T ? value : defaultValue;
  }

  @override
  Future<void> remove(String key) async => _values.remove(key);

  @override
  Future<void> removeAll() async => _values.clear();

  @override
  Future<void> setBool(String key, bool? value) async => _values[key] = value;

  @override
  Future<void> setDouble(String key, double? value) async =>
      _values[key] = value;

  @override
  Future<void> setInt(String key, int? value) async => _values[key] = value;

  @override
  Future<void> setObject<T>(String key, T? value) async => _values[key] = value;

  @override
  Future<void> setString(String key, String? value) async =>
      _values[key] = value;
}
