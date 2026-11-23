import 'dart:async';

import 'package:pdfrx/pdfrx.dart';

typedef _FontQueryKey = (String, int, bool, PdfFontCharset, int);

/// מאחד טעינות גופן ממתינות, ושומר את הצורך בפתיחה מחדש לכל מסמך שממתין.
class PdfFontLoadCoordinator {
  PdfFontLoadCoordinator({
    required Future<PdfFontLoadResult> Function(Iterable<PdfFontQuery>) load,
  }) : _load = load;

  final Future<PdfFontLoadResult> Function(Iterable<PdfFontQuery>) _load;
  final _pending = <_FontQueryKey, Completer<bool>>{};

  Future<bool> loadMissingFonts(Iterable<PdfFontQuery> queries) {
    final unique = {for (final query in queries) _key(query): query};
    final added = <_FontQueryKey, PdfFontQuery>{};
    final waiting = <Future<bool>>[];
    for (final entry in unique.entries) {
      var pending = _pending[entry.key];
      if (pending == null) {
        pending = _pending[entry.key] = Completer<bool>();
        added[entry.key] = entry.value;
      }
      waiting.add(pending.future);
    }
    final completion = Future.wait(waiting);
    if (added.isNotEmpty) unawaited(_loadBatch(added));
    return completion.then((loaded) => loaded.any((value) => value));
  }

  Future<void> _loadBatch(Map<_FontQueryKey, PdfFontQuery> queries) async {
    try {
      final result = await _load(List.unmodifiable(queries.values));
      final loaded = {for (final font in result.loaded) _key(font.query)};
      for (final key in queries.keys) {
        _pending[key]!.complete(loaded.contains(key));
      }
    } catch (error, stackTrace) {
      for (final key in queries.keys) {
        _pending[key]!.completeError(error, stackTrace);
      }
    } finally {
      // ה־manager מחזיק את הרישום; כאן נשארות רק פעולות שעדיין לא הסתיימו.
      for (final key in queries.keys) {
        _pending.remove(key);
      }
    }
  }

  static _FontQueryKey _key(PdfFontQuery query) => (
    query.face,
    query.weight,
    query.isItalic,
    query.charset,
    query.pitchFamily,
  );
}
