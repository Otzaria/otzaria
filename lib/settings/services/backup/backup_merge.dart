import 'dart:convert';

/// מיזוג מניפסטים של גיבוי לארכיון מתגלגל — איחוד לפי זהות פריט.
///
/// עיקרון: פריט שקיים בגיבוי החדש מנצח; פריט שקיים רק בישן נשמר עם
/// `lastSeenAt` (מועד הגיבוי האחרון שהכיל אותו), כך שמחיקות מכוונות של
/// המשתמש אינן "קמות לתחייה" בגיבויים רגילים אך נשמרות בארכיון.
class BackupMerge {
  /// פריט ארכיון שלא נראה מעל תקופה זו נמחק סופית בעת המיזוג הבא.
  static const Duration archiveItemMaxAge = Duration(days: 365 * 3);

  /// ממיר timestamp של מניפסט (ISO עם `-` במקום `:`) ל-DateTime.
  static DateTime? parseManifestTimestamp(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final fixed = raw.replaceFirstMapped(
      RegExp(r'T(\d{2})-(\d{2})-(\d{2})'),
      (m) => 'T${m[1]}:${m[2]}:${m[3]}',
    );
    return DateTime.tryParse(fixed);
  }

  /// ממזג את [newer] לתוך [older] (הארכיון הקיים) ומחזיר מניפסט ארכיון חדש.
  ///
  /// [olderTimestamp]/[newerTimestamp] — מועדי הגיבויים, לסימון `lastSeenAt`.
  /// [now] מוזרק כדי לאפשר בדיקות דטרמיניסטיות של גיזום לפי גיל.
  static Map<String, dynamic> merge(
    Map<String, dynamic> older,
    Map<String, dynamic> newer, {
    required DateTime olderTimestamp,
    required DateTime newerTimestamp,
    required DateTime now,
  }) {
    final cutoff = now.subtract(archiveItemMaxAge);
    final olderSeen = olderTimestamp.toIso8601String();
    final newerSeen = newerTimestamp.toIso8601String();

    final result = <String, dynamic>{
      'version': '2.0',
      'origin': 'archive',
      'timestamp': newer['timestamp'] ?? older['timestamp'],
      'includes': _mergeIncludes(older, newer),
    };

    // הגדרות: החדש מנצח תמיד — ערכים ישנים (כמו נתיב ספרייה שהוחלף) מזיקים.
    final settings = newer['settings'] ?? older['settings'];
    if (settings != null) result['settings'] = settings;

    final bookmarks = _mergeItemLists(
      older['bookmarks'],
      newer['bookmarks'],
      keyOf: _bookmarkKey,
      olderSeen: olderSeen,
      newerSeen: newerSeen,
      cutoff: cutoff,
    );
    if (bookmarks != null) result['bookmarks'] = bookmarks;

    final history = _mergeItemLists(
      older['history'],
      newer['history'],
      keyOf: _historyKey,
      olderSeen: olderSeen,
      newerSeen: newerSeen,
      cutoff: cutoff,
      maxItems: _maxHistoryEntries,
    );
    if (history != null) result['history'] = history;

    final notes = _mergeNotes(
      older['notes'],
      newer['notes'],
      olderSeen: olderSeen,
      newerSeen: newerSeen,
      cutoff: cutoff,
    );
    if (notes != null) result['notes'] = notes;

    final workspaces = _mergeItemLists(
      older['workspaces'],
      newer['workspaces'],
      keyOf: (m) => (m['id'] ?? m['name'] ?? '').toString(),
      olderSeen: olderSeen,
      newerSeen: newerSeen,
      cutoff: cutoff,
    );
    if (workspaces != null) {
      result['workspaces'] = workspaces;
      result['currentWorkspace'] =
          newer['currentWorkspace'] ?? older['currentWorkspace'];
    }

    final shamorZachor = _mergeShamorZachor(
      _asStringMap(older['shamorZachor']),
      _asStringMap(newer['shamorZachor']),
    );
    if (shamorZachor != null) result['shamorZachor'] = shamorZachor;

    final plugins = _mergeItemLists(
      older['plugins'],
      newer['plugins'],
      keyOf: (m) {
        final installation = m['installation'];
        return installation is Map
            ? (installation['plugin_id'] ?? '').toString()
            : '';
      },
      olderSeen: olderSeen,
      newerSeen: newerSeen,
      cutoff: cutoff,
    );
    if (plugins != null) result['plugins'] = plugins;

    return result;
  }

  static const int _maxHistoryEntries = 500;

  static Map<String, dynamic> _mergeIncludes(
    Map<String, dynamic> older,
    Map<String, dynamic> newer,
  ) {
    final merged = <String, dynamic>{};
    for (final src in [older['includes'], newer['includes']]) {
      if (src is! Map) continue;
      for (final entry in src.entries) {
        merged[entry.key.toString()] =
            (merged[entry.key.toString()] == true) || (entry.value == true);
      }
    }
    return merged;
  }

  /// איחוד רשימות פריטים לפי מפתח זהות: פריטי החדש קודמים ומנצחים,
  /// פריטים ישנים-בלבד מצורפים אחריהם, ופריטים שחצו את גיל הארכיון נגזמים.
  static List<Map<String, dynamic>>? _mergeItemLists(
    Object? olderRaw,
    Object? newerRaw, {
    required String Function(Map<String, dynamic>) keyOf,
    required String olderSeen,
    required String newerSeen,
    required DateTime cutoff,
    int? maxItems,
  }) {
    final olderList = _asItemList(olderRaw);
    final newerList = _asItemList(newerRaw);
    if (olderList == null && newerList == null) return null;

    final merged = <String, Map<String, dynamic>>{};

    for (final item in newerList ?? const <Map<String, dynamic>>[]) {
      merged[keyOf(item)] = {...item, 'lastSeenAt': newerSeen};
    }
    for (final item in olderList ?? const <Map<String, dynamic>>[]) {
      final key = keyOf(item);
      if (merged.containsKey(key)) continue;
      merged[key] = {...item, 'lastSeenAt': item['lastSeenAt'] ?? olderSeen};
    }

    final pruned = merged.values.where((item) {
      final seen = DateTime.tryParse(item['lastSeenAt']?.toString() ?? '');
      return seen == null || seen.isAfter(cutoff);
    }).toList();

    if (maxItems != null && pruned.length > maxItems) {
      return pruned.sublist(0, maxItems);
    }
    return pruned;
  }

  static List<Map<String, dynamic>>? _asItemList(Object? raw) {
    if (raw is! List) return null;
    return raw.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
  }

  static Map<String, dynamic>? _asStringMap(Object? raw) {
    if (raw is! Map) return null;
    return raw.cast<String, dynamic>();
  }

  static String _bookTitleOf(Map<String, dynamic> m) {
    final book = m['book'];
    if (book is! Map) return '';
    final id = book['id'];
    final title = book['title'] ?? '';
    return id != null ? 'id:$id' : 'title:$title';
  }

  static String _bookmarkKey(Map<String, dynamic> m) =>
      '${m['targetKind']}|${m['ref']}|${m['index']}|${m['isSearch']}|${_bookTitleOf(m)}';

  /// זהות רשומת היסטוריה: אחת לכל ספר (כמו historyKey באפליקציה),
  /// כך שמיזוג משמר את מיקום הקריאה האחרון פר-ספר ולא כל ביקור.
  static String _historyKey(Map<String, dynamic> m) {
    if (m['isSearch'] == true) return 'search:${m['ref']}';
    return '${m['targetKind']}:${_bookTitleOf(m)}';
  }

  /// מיזוג הערות: איחוד לפי `note.id`, ה-`updatedAt` המאוחר מנצח.
  static List<Map<String, dynamic>>? _mergeNotes(
    Object? olderRaw,
    Object? newerRaw, {
    required String olderSeen,
    required String newerSeen,
    required DateTime cutoff,
  }) {
    final olderList = _asItemList(olderRaw);
    final newerList = _asItemList(newerRaw);
    if (olderList == null && newerList == null) return null;

    // noteId → (הערה, lastSeenAt)
    final byId = <String, Map<String, dynamic>>{};

    void absorb(List<Map<String, dynamic>>? bookEntries, String seenAt) {
      for (final bookEntry in bookEntries ?? const <Map<String, dynamic>>[]) {
        final notes = _asItemList(bookEntry['notes']);
        for (final note in notes ?? const <Map<String, dynamic>>[]) {
          final id = note['id']?.toString();
          if (id == null) continue;
          final existing = byId[id];
          if (existing != null &&
              !_isNewerNote(candidate: note, existing: existing)) {
            continue;
          }
          byId[id] = {...note, 'lastSeenAt': note['lastSeenAt'] ?? seenAt};
        }
      }
    }

    // הישן נקלט קודם כדי שהחדש ידרוס אותו בשוויון updatedAt.
    absorb(olderList, olderSeen);
    absorb(newerList, newerSeen);

    final byBook = <String, List<Map<String, dynamic>>>{};
    for (final note in byId.values) {
      final seen = DateTime.tryParse(note['lastSeenAt']?.toString() ?? '');
      if (seen != null && !seen.isAfter(cutoff)) continue;
      final bookId = note['bookId']?.toString() ?? '';
      byBook.putIfAbsent(bookId, () => []).add(note);
    }

    return byBook.entries
        .map((e) => <String, dynamic>{'bookId': e.key, 'notes': e.value})
        .toList();
  }

  static bool _isNewerNote({
    required Map<String, dynamic> candidate,
    required Map<String, dynamic> existing,
  }) {
    final candidateUpdated = DateTime.tryParse(
      candidate['updatedAt']?.toString() ?? '',
    );
    final existingUpdated = DateTime.tryParse(
      existing['updatedAt']?.toString() ?? '',
    );
    if (candidateUpdated == null) return false;
    if (existingUpdated == null) return true;
    return !candidateUpdated.isBefore(existingUpdated);
  }

  /// שמור-וזכור: מיזוג פר-ספר בתוך `sz:progress_by_id` (החדש מנצח לכל ספר,
  /// ספר ישן-בלבד נשמר). מיזוג פר-דף אסור — היה מחזיר סימונים שבוטלו בכוונה.
  static Map<String, dynamic>? _mergeShamorZachor(
    Map<String, dynamic>? older,
    Map<String, dynamic>? newer,
  ) {
    if (older == null && newer == null) return null;
    final merged = <String, dynamic>{...?older, ...?newer};

    const progressKey = 'sz:progress_by_id';
    final olderProgress = _decodeJsonMap(older?[progressKey]);
    final newerProgress = _decodeJsonMap(newer?[progressKey]);
    if (olderProgress != null || newerProgress != null) {
      merged[progressKey] = json.encode({...?olderProgress, ...?newerProgress});
    }
    return merged;
  }

  static Map<String, dynamic>? _decodeJsonMap(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    try {
      final decoded = json.decode(raw);
      return decoded is Map ? decoded.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }
}
