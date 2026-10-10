import 'dart:convert';

import 'package:otzaria/bookmarks/models/bookmark_group.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/workspaces/workspace.dart';

/// אופן החלת קובץ גיבוי על הנתונים הקיימים.
enum BackupImportMode {
  /// שחזור: נתוני הגיבוי מחליפים את הקיימים.
  replace,

  /// ייבוא ממזג: פריטי הגיבוי מתווספים, ופריט מקומי אינו נמחק ואינו נדרס.
  merge,
}

/// מה נוסף בייבוא ממזג — לדיווח למשתמש בסיום.
class BackupImportCounts {
  int bookmarks = 0;
  int bookmarkGroups = 0;
  int history = 0;
  int notes = 0;
  int notesUpdated = 0;
  int workspaces = 0;
  int plugins = 0;
  int shamorZachorBooks = 0;

  int get total =>
      bookmarks +
      bookmarkGroups +
      history +
      notes +
      notesUpdated +
      workspaces +
      plugins +
      shamorZachorBooks;
}

/// כללי המיזוג של ייבוא מגיבוי של מכשיר אחר.
///
/// כולן פונקציות טהורות על נתונים טעונים — הכתיבה עצמה נשארת ב-`BackupService`.
class BackupImportMerge {
  /// תקרת ההיסטוריה, כמו ב-`HistoryBloc` — ייבוא לא יגדיל אותה מעבר לכך.
  static const int maxHistory = 200;

  /// שם שולחן עבודה שיובא ושמו כבר תפוס.
  static const String _importedSuffix = 'ממכשיר אחר';

  /// סימניות: פריט מהגיבוי נוסף רק אם אין מקומית סימניה באותה
  /// [Bookmark.bookmarkIdentity]. הסדר המקומי נשמר, והמיובאות בסופו.
  static ({List<Bookmark> merged, int added}) mergeBookmarks(
    List<Bookmark> local,
    List<Bookmark> incoming,
  ) => _mergeByKey(local, incoming, (b) => b.bookmarkIdentity);

  /// Bookmark groups: an imported group is added unless a group with the same
  /// id exists here, so re-importing a backup of this device adds nothing.
  static ({List<BookmarkGroup> merged, int added}) mergeBookmarkGroups(
    List<BookmarkGroup> local,
    List<BookmarkGroup> incoming,
  ) => _mergeByKey(local, incoming, (g) => g.id);

  /// היסטוריה: רשומה אחת לכל [Bookmark.historyKey], גזורה ל-[maxHistory].
  /// המקומיות קודמות, אך בתקרה מפנות מקום למיובאות — אחרת הייבוא לא-פעולה.
  static ({List<Bookmark> merged, int added}) mergeHistory(
    List<Bookmark> local,
    List<Bookmark> incoming,
  ) {
    final result = _mergeByKey(local, incoming, (b) => b.historyKey);
    if (result.merged.length <= maxHistory) return result;

    final imported = result.merged.skip(local.length).take(maxHistory).toList();
    final localCapacity = maxHistory - imported.length;
    return (
      merged: [...local.take(localCapacity), ...imported],
      added: imported.length,
    );
  }

  static ({List<T> merged, int added}) _mergeByKey<T>(
    List<T> local,
    List<T> incoming,
    String Function(T) keyOf,
  ) {
    final merged = [...local];
    final keys = local.map(keyOf).toSet();
    var added = 0;
    for (final item in incoming) {
      if (!keys.add(keyOf(item))) continue;
      merged.add(item);
      added++;
    }
    return (merged: merged, added: added);
  }

  /// שמור-וזכור: מחזירה את המפתחות שיש לכתוב בפועל.
  ///
  /// המקומי מנצח תמיד — ייבוא אינו מחזיר סימוני דפים שבוטלו כאן בכוונה.
  /// `sz:progress_by_id` ממוזג פר-ספר (ולא פר-דף), `sz:tracked_books` הוא
  /// איחוד, וכל מפתח אחר נכתב רק אם אינו קיים מקומית.
  static ({Map<String, Object?> toWrite, int addedBooks}) mergeShamorZachor(
    Map<String, Object?> local,
    Map<String, dynamic> incoming,
  ) {
    const progressKey = 'sz:progress_by_id';
    const trackedKey = 'sz:tracked_books';

    final toWrite = <String, Object?>{};
    var addedBooks = 0;

    for (final entry in incoming.entries) {
      if (entry.value == null) continue;
      if (entry.key == progressKey || entry.key == trackedKey) continue;
      if (local.containsKey(entry.key)) continue;
      toWrite[entry.key] = entry.value;
    }

    final localProgress = _decodeJsonMap(local[progressKey]);
    final incomingProgress = _decodeJsonMap(incoming[progressKey]);
    if (incomingProgress != null) {
      final merged = {...incomingProgress, ...?localProgress};
      addedBooks = incomingProgress.keys
          .where(
            (id) => localProgress == null || !localProgress.containsKey(id),
          )
          .length;
      if (localProgress == null || addedBooks > 0) {
        toWrite[progressKey] = json.encode(merged);
      }
    }

    final localTracked = _decodeJsonList(local[trackedKey]);
    final incomingTracked = _decodeJsonList(incoming[trackedKey]);
    if (incomingTracked != null) {
      final union = {...?localTracked, ...incomingTracked};
      if (localTracked == null || union.length != localTracked.length) {
        toWrite[trackedKey] = json.encode(union.toList());
      }
    }

    return (toWrite: toWrite, addedBooks: addedBooks);
  }

  /// שולחנות עבודה שיש להוסיף — הקיימים אינם נוגעים.
  ///
  /// שולחן שמזההו כבר קיים דולג, כך שייבוא חוזר של אותו קובץ אינו מכפיל.
  /// שם תפוס מקבל סיומת, כי שני שולחנות באותו שם אינם ניתנים להבחנה.
  static List<Workspace> workspacesToAdd(
    List<Workspace> existing,
    List<Workspace> incoming,
  ) {
    final ids = existing.map((w) => w.id).toSet();
    final names = existing.map((w) => w.name).toSet();

    final toAdd = <Workspace>[];
    for (final workspace in incoming) {
      if (!ids.add(workspace.id)) continue;
      final name = _availableName(workspace.name, names);
      names.add(name);
      toAdd.add(workspace.copyWith(name: name));
    }
    return toAdd;
  }

  static String _availableName(String name, Set<String> taken) {
    if (!taken.contains(name)) return name;
    final base = '$name ($_importedSuffix)';
    if (!taken.contains(base)) return base;
    for (var i = 2; ; i++) {
      final candidate = '$name ($_importedSuffix $i)';
      if (!taken.contains(candidate)) return candidate;
    }
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

  static List<int>? _decodeJsonList(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    try {
      final decoded = json.decode(raw);
      return decoded is List ? decoded.whereType<int>().toList() : null;
    } catch (_) {
      return null;
    }
  }
}
