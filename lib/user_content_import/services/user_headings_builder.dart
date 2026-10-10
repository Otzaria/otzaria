import 'package:otzaria/user_content_import/models/user_import_models.dart';
import 'package:otzaria/utils/text/text_manipulation.dart'
    show removeVolwels, stripHtmlIfNeeded;

/// ערך כותרת מוכן לכתיבה. [parentIndex] מצביע על מיקום האב ב-[entries] של
/// המבנה.
class UserAltTocEntryData {
  final int level;
  final String text;
  final int? lineIndex;
  final int? parentIndex;
  final bool hasChildren;
  final bool isLastChild;

  const UserAltTocEntryData({
    required this.level,
    required this.text,
    required this.lineIndex,
    required this.parentIndex,
    required this.hasChildren,
    required this.isLastChild,
  });
}

/// מבנה כותרות אחד של ספר, בסדר הופעתו בקובץ.
class UserAltTocStructureData {
  final String key;
  final String heTitle;
  final List<UserAltTocEntryData> entries;

  const UserAltTocStructureData({
    required this.key,
    required this.heTitle,
    required this.entries,
  });
}

/// בונה את מבני הכותרות של ספר אחד משורות קובץ הכותרות, מול שורות הספר.
class UserHeadingsBuilder {
  /// [lines] — שורות הספר כפי שהקורא מציג אותן (לאיתור לפי טקסט ולגבולות).
  static ({List<UserAltTocStructureData> structures, List<String> errors})
  build(List<ParsedHeading> rows, List<String> lines) {
    final errors = <String>[];
    final byStructure = <String, List<ParsedHeading>>{};
    for (final row in rows) {
      (byStructure[row.structure] ??= []).add(row);
    }

    // נרמול כל שורות הספר יקר, ונדרש רק לאיתור כותרת לפי טקסט.
    final normalizedLines = rows.any((row) => row.anchorText != null)
        ? [for (final line in lines) _normalize(line)]
        : lines;
    final structures = <UserAltTocStructureData>[];
    for (final MapEntry(key: name, value: structureRows)
        in byStructure.entries) {
      final resolved = <({ParsedHeading row, int? lineIndex})>[];
      var cursor = 0;
      for (final row in structureRows) {
        final lineIndex = _resolveLine(row, normalizedLines, cursor, errors);
        if (lineIndex == -1) continue;
        if (lineIndex != null) cursor = lineIndex + 1;
        resolved.add((row: row, lineIndex: lineIndex));
      }
      final entries = _buildTree(resolved, errors);
      if (entries.isEmpty) continue;
      structures.add(
        UserAltTocStructureData(
          key: kHebrewAltTocStructureKeys[name] ?? name,
          heTitle: name,
          entries: entries,
        ),
      );
    }
    return (structures: structures, errors: errors);
  }

  /// null = כותרת-אב בלי שורה; ‎-1‎ = שגיאה (נרשמה ב-[errors]).
  static int? _resolveLine(
    ParsedHeading row,
    List<String> lines,
    int cursor,
    List<String> errors,
  ) {
    final lineNumber = row.lineNumber;
    if (lineNumber != null) {
      if (lineNumber > lines.length) {
        errors.add(
          'שורה ${row.rowNumber}: שורה $lineNumber חורגת מגבולות הספר '
          '(${lines.length} שורות)',
        );
        return -1;
      }
      return lineNumber - 1;
    }
    final anchor = row.anchorText;
    if (anchor == null) return null;
    final target = _normalize(anchor);
    if (target.isEmpty) return null;

    // סדר הכותרות בקובץ הוא סדר הספר: מחפשים קודם אחרי הכותרת הקודמת, כך
    // שטקסט שחוזר בספר נקשר למופע הנכון.
    for (final matches in <bool Function(String)>[
      (line) => line.startsWith(target),
      (line) => line.contains(target),
    ]) {
      for (var i = cursor; i < lines.length; i++) {
        if (matches(lines[i])) return i;
      }
      for (var i = 0; i < cursor && i < lines.length; i++) {
        if (matches(lines[i])) return i;
      }
    }
    errors.add('שורה ${row.rowNumber}: הטקסט "$anchor" לא נמצא בספר');
    return -1;
  }

  static List<UserAltTocEntryData> _buildTree(
    List<({ParsedHeading row, int? lineIndex})> resolved,
    List<String> errors,
  ) {
    final parents = List<int?>.filled(resolved.length, null);
    final stack = <int>[];
    for (var i = 0; i < resolved.length; i++) {
      final level = resolved[i].row.level;
      while (stack.isNotEmpty && resolved[stack.last].row.level >= level) {
        stack.removeLast();
      }
      parents[i] = stack.isEmpty ? null : stack.last;
      stack.add(i);
    }

    final hasChildren = List<bool>.filled(resolved.length, false);
    final lastChildOf = <int?, int>{};
    for (var i = 0; i < resolved.length; i++) {
      final parent = parents[i];
      if (parent != null) hasChildren[parent] = true;
      lastChildOf[parent] = i;
    }

    // כותרת-אב בלי שורה חייבת צאצא עם שורה — אחרת אין לאן לנווט ממנה.
    final hasLine = [for (final r in resolved) r.lineIndex != null];
    for (var i = resolved.length - 1; i >= 0; i--) {
      final parent = parents[i];
      if (hasLine[i] && parent != null) hasLine[parent] = true;
    }
    final keep = <int, int>{};
    final entries = <UserAltTocEntryData>[];
    for (var i = 0; i < resolved.length; i++) {
      if (!hasLine[i]) {
        errors.add(
          'שורה ${resolved[i].row.rowNumber}: לכותרת "${resolved[i].row.title}" '
          'אין שורה, טקסט או כותרות-משנה',
        );
        continue;
      }
      final parent = parents[i];
      keep[i] = entries.length;
      entries.add(
        UserAltTocEntryData(
          level: resolved[i].row.level,
          text: resolved[i].row.title,
          lineIndex: resolved[i].lineIndex,
          parentIndex: parent == null ? null : keep[parent],
          hasChildren: hasChildren[i],
          isLastChild: lastChildOf[parent] == i,
        ),
      );
    }
    return entries;
  }

  static String _normalize(String text) => removeVolwels(
    stripHtmlIfNeeded(text),
  ).replaceAll(RegExp(r'\s+'), ' ').trim();
}
