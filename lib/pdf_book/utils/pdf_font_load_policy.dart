import 'package:pdfrx/pdfrx.dart';

typedef _RegisterFonts =
    Future<PdfFontLoadResult> Function(
      Iterable<PdfFontQuery> queries,
    );

/// שומר גופן עברי גם כשה־PDF מדווח ANSI, ומרענן רישומים חדשים פעם אחת.
/// פעולות הרישום שנמסרות לכאן חייבות להשתמש ב־reloadFonts: false.
class PdfFontLoadPolicy {
  PdfFontLoadPolicy({
    required this._registerHebrew,
    required this._registerPlatform,
    required this._reload,
  });

  final _RegisterFonts _registerHebrew;
  final _RegisterFonts _registerPlatform;
  final Future<void> Function() _reload;
  final _awaitingRefresh = <PdfLoadedFont>[];
  Future<void>? _tail;
  Future<PdfFontLoadResult>? _flush;
  var _queuedBatches = 0;

  /// מתאם רק רישום גופנים; פתיחות המסמכים עצמן ממשיכות במקביל.
  Future<PdfFontLoadResult> loadMissingFonts(Iterable<PdfFontQuery> queries) {
    final fonts = List<PdfFontQuery>.unmodifiable(queries);
    if (fonts.isNotEmpty) return _enqueue(fonts);
    final flush = _flush;
    if (flush != null) return flush;
    // כשל refresh אינו מצדיק המתנה לרישום מאוחר שמחוץ לצילום הפתיחה.
    if (_awaitingRefresh.isEmpty || _queuedBatches != 0) {
      return Future.value(_emptyResult);
    }
    return _flush = _enqueue(fonts).whenComplete(() => _flush = null);
  }

  Future<PdfFontLoadResult> _enqueue(List<PdfFontQuery> fonts) {
    _queuedBatches++;
    Future<PdfFontLoadResult> run() async {
      try {
        return await _load(fonts);
      } finally {
        _queuedBatches--;
        // Future שכבר הסתיים מתזמן מאזין חדש ב־zone הישן שלו.
        if (_queuedBatches == 0) _tail = null;
      }
    }

    final tail = _tail;
    final result = tail == null
        ? Future<PdfFontLoadResult>.microtask(run)
        : tail.then((_) => run());
    _tail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return result;
  }

  Future<PdfFontLoadResult> _load(List<PdfFontQuery> queries) async {
    final hebrew = <PdfFontQuery>[];
    final platform = <PdfFontQuery>[];
    for (final query in queries) {
      final supportsHebrew = switch (query.charset) {
        PdfFontCharset.ansi ||
        PdfFontCharset.default_ ||
        PdfFontCharset.hebrew => true,
        _ => false,
      };
      (supportsHebrew ? hebrew : platform).add(query);
    }
    final results = [
      if (hebrew.isNotEmpty) await _register(_registerHebrew, hebrew),
      if (platform.isNotEmpty) await _register(_registerPlatform, platform),
    ];
    final loaded = [
      ..._awaitingRefresh,
      for (final result in results) ...result.loaded,
    ];
    final refreshed = loaded.isNotEmpty;
    if (refreshed) {
      try {
        await _reload();
      } catch (_) {
        // המנהלים כבר זוכרים את ה־face; שומרים רק עד לרענון מוצלח.
        _awaitingRefresh
          ..clear()
          ..addAll(loaded);
        rethrow;
      }
    }
    _awaitingRefresh.clear();
    return PdfFontLoadResult(
      loaded: loaded,
      unresolved: [for (final result in results) ...result.unresolved],
      failed: [for (final result in results) ...result.failed],
      fontsReloaded: refreshed,
    );
  }

  Future<PdfFontLoadResult> _register(
    _RegisterFonts register,
    List<PdfFontQuery> queries,
  ) async {
    try {
      return await register(queries);
    } catch (error, stackTrace) {
      return PdfFontLoadResult(
        loaded: const [],
        unresolved: const [],
        failed: [
          for (final query in queries)
            PdfFontLoadFailure(
              query: query,
              error: error,
              stackTrace: stackTrace,
            ),
        ],
        fontsReloaded: false,
      );
    }
  }

  static const _emptyResult = PdfFontLoadResult(
    loaded: [],
    unresolved: [],
    failed: [],
    fontsReloaded: false,
  );
}
