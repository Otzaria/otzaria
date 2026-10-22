import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/windowing/multi_window_service.dart';
import 'package:otzaria/core/windowing/window_bus.dart';
import 'package:otzaria/marker/models/marker_highlight.dart';

/// שינוי בסימונים. [bookKeys] הם כותרות הספרים ומזהיהם היציבים; ריק
/// פירושו "כל הספרים" (ייבוא), ואז נטען מחדש כל מה שבזיכרון.
class MarkerChange {
  final Set<String> bookKeys;

  /// מזהי הסימונים שנשמרו; null — לא ידוע מה השתנה, וטוענים את הספר מחדש.
  final Set<String>? savedIds;
  final Set<String> removedIds;

  /// הסימונים שנשמרו, כשהשינוי נעשה בחלון הזה.
  final List<MarkerHighlight>? saved;

  const MarkerChange(
    this.bookKeys, {
    this.savedIds,
    this.removedIds = const {},
  }) : saved = null;

  const MarkerChange.all()
    : bookKeys = const {},
      savedIds = null,
      removedIds = const {},
      saved = null;

  MarkerChange.saved(List<MarkerHighlight> highlights)
    : bookKeys = _keysOf(highlights),
      savedIds = {for (final highlight in highlights) highlight.id},
      removedIds = const {},
      saved = highlights;

  MarkerChange.removed(Iterable<MarkerHighlight> highlights)
    : bookKeys = _keysOf(highlights),
      savedIds = const {},
      removedIds = {for (final highlight in highlights) highlight.id},
      saved = const [];

  static Set<String> _keysOf(Iterable<MarkerHighlight> highlights) => {
    for (final highlight in highlights) ...[
      highlight.bookTitle,
      ?highlight.bookUid,
    ],
  };

  bool get isAll => bookKeys.isEmpty;

  bool affects(String bookTitle, String? bookUid) =>
      isAll ||
      bookKeys.contains(bookTitle) ||
      (bookUid != null && bookKeys.contains(bookUid));
}

/// מפיץ שינויים בחלון ובשאר החלונות. לאחרים נשלחת רק פסילה גסה (אילו ספרים)
/// והם קוראים מהמסד, כך שהודעה שאבדה מתוקנת בטעינה הבאה.
class MarkerChanges {
  MarkerChanges({WindowBus? bus}) : _bus = bus ?? WindowBus.instance;

  static final MarkerChanges instance = MarkerChanges();

  static const String requestChanged = 'markerChanged';

  /// מעל זה החלונות האחרים טוענים את הספרים מחדש במקום לקבל רשימת מזהים.
  static const int _maxBroadcastIds = 2000;

  final WindowBus _bus;
  final StreamController<MarkerChange> _controller =
      StreamController<MarkerChange>.broadcast(sync: true);

  Stream<MarkerChange> get stream => _controller.stream;

  void notify(MarkerChange change) {
    _controller.add(change);
    if (!MultiWindowService.canOpenWindows) return;
    final slot = _bus.slot;
    if (slot == null) return;
    try {
      final ids = change.savedIds;
      final withIds =
          ids != null &&
          ids.length + change.removedIds.length <= _maxBroadcastIds;
      _bus.broadcast({
        'type': requestChanged,
        'origin': slot,
        'books': change.bookKeys.toList(),
        if (withIds) 'saved': ids.toList(),
        if (withIds) 'removed': change.removedIds.toList(),
      });
    } catch (error) {
      // חלון שלא קיבל את ההודעה יקרא את המצב הנכון בטעינה הבאה שלו.
      debugPrint('MarkerChanges broadcast failed: $error');
    }
  }

  /// מטפל בהודעת [requestChanged] מחלון אחר.
  Object? handleRequest(Map<String, dynamic> request) {
    if (request['type'] != requestChanged) return null;
    if (request['origin'] == _bus.slot) return true;
    final books = request['books'];
    final saved = request['saved'];
    _controller.add(
      MarkerChange(
        _strings(books),
        savedIds: saved is List ? _strings(saved) : null,
        removedIds: _strings(request['removed']),
      ),
    );
    return true;
  }

  static Set<String> _strings(Object? list) => {
    if (list is List)
      for (final item in list)
        if (item is String) item,
  };
}
