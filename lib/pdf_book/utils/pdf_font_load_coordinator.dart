import 'dart:async';

import 'package:pdfrx/pdfrx.dart';

typedef _FontQueryKey = (String, int, bool, PdfFontCharset, int);

/// מאחד טעינות גופן ממתינות, ושומר את הצורך בפתיחה מחדש לכל מסמך שממתין.
class PdfFontLoadCoordinator {
  PdfFontLoadCoordinator({required this._load, this._refreshPendingFonts});

  final Future<PdfFontLoadResult> Function(Iterable<PdfFontQuery>) _load;
  final Future<bool> Function()? _refreshPendingFonts;
  final _pending = <_FontQueryKey, Completer<bool>>{};
  final _openings = <PdfFontOpening>{};
  Future<void>? _pendingRefresh;
  var _revision = 0;

  PdfFontOpening beginOpening() {
    final opening = PdfFontOpening._(_revision);
    _openings.add(opening);
    return opening;
  }

  /// המנוע הנעול מנקז גופנים חסרים ברמת ה־worker, ולא לכל מסמך בנפרד.
  /// ממתינים לגילוי של פתיחות חופפות לפני שמחזירים מסמך עם גופן חלופי ישן.
  Future<bool> completeOpening(
    PdfFontOpening opening,
    Iterable<PdfFontQuery> queries,
  ) async {
    try {
      opening._fonts = loadMissingFonts(queries).then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {},
      );
      opening._discovered.complete();
      // הצילום סופי: בקשות שיגיעו בהמשך אינן מעכבות פתיחה שכבר הסתיימה.
      final peers = List.of(_openings);
      await Future.wait(
        peers.map((peer) async {
          await peer._discovered.future;
          await peer._fonts;
        }),
      );
      // רינדור של מסמך שכבר נמסר יכול לדווח גופן ששייך לפתיחה הנוכחית.
      await Future.wait([
        for (final pending in _pending.values) pending.future,
      ]).then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {},
      );
      // רישום יכול להצליח לפני כשל refresh, ואז הפתיחה הבאה לא תדווח חוסר.
      await _refreshPending();
      return opening._revision != _revision;
    } finally {
      cancelOpening(opening);
    }
  }

  Future<void> _refreshPending() {
    final refresh = _refreshPendingFonts;
    if (refresh == null) return Future.value();
    return _pendingRefresh ??= Future<bool>.sync(refresh)
        .then<void>(
          (changed) {
            if (changed) _revision++;
          },
          onError: (Object error, StackTrace stackTrace) {},
        )
        .whenComplete(() => _pendingRefresh = null);
  }

  /// משחרר ממתינים גם בכשל פתיחה או בהמתנה להזנת סיסמה.
  void cancelOpening(PdfFontOpening opening) {
    if (!opening._discovered.isCompleted) opening._discovered.complete();
    _openings.remove(opening);
  }

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
      if (loaded.isNotEmpty) _revision++;
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

/// ניסיון פתיחה פעיל ששייך למתאם; אינו מחזיק במסמך עצמו.
class PdfFontOpening {
  PdfFontOpening._(this._revision);

  final int _revision;
  final _discovered = Completer<void>();
  Future<void> _fonts = Future<void>.value();
}
