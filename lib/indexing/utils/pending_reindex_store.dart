import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// מה שנשאר לריצת האינדוקס הבאה ושורד קריסה או ביטול: ספרים שמסמכיהם ממתינים
/// להחלפה ([PendingReindex.keys]), ובדיקות שטרם הושלמו ונחתמו — של ספרייה או ספרים.
class PendingReindexStore {
  PendingReindexStore._(this._file);

  static const fileName = 'otzaria_pending_reindex.json';
  static const _version = 1;

  /// null כשאין אינדקס פתוח.
  static PendingReindexStore? forIndex(String? indexPath) => indexPath == null
      ? null
      : PendingReindexStore._(File(p.join(indexPath, fileName)));

  // עותק בזיכרון: כשהכתיבה לדיסק נכשלת, ביטול באותה הפעלה עדיין לא מאבד אותו.
  static final Map<String, PendingReindex> _memory = {};

  /// האינדקס נמחק או הוחלף — מה שנזכר עליו כבר אינו נכון.
  static void clearMemory() => _memory.clear();

  @visibleForTesting
  static void resetMemoryForTesting() => clearMemory();

  final File _file;

  Future<PendingReindex> read() async {
    final cached = _memory[_file.path];
    final keys = {...?cached?.keys};
    final checkKeys = {...?cached?.checkKeys};
    var checkLibrary = cached?.checkLibrary ?? false;
    try {
      if (await _file.exists()) {
        final json = jsonDecode(await _file.readAsString());
        if (json is Map && json['version'] == _version) {
          keys.addAll((json['keys'] as List).cast<String>());
          checkKeys.addAll(
            ((json['checkKeys'] as List?) ?? const []).cast<String>(),
          );
          checkLibrary |= json['checkLibrary'] == true;
        }
      }
    } catch (e) {
      debugPrint('⚠️ קריאת רשימת הספרים להחלפה באינדקס נכשלה: $e');
    }
    return PendingReindex(
      keys: keys,
      checkKeys: checkKeys,
      checkLibrary: checkLibrary,
    );
  }

  Future<Set<String>> load() async => (await read()).keys;

  /// האם נדחתה בדיקה מלאה של הספרייה (ריצה שבוטלה לפני שבדקה).
  Future<bool> checkLibraryPending() async => (await read()).checkLibrary;

  /// מחליף את הרשימה; [checkLibrary] ו-[checkKeys] null שומרים את הקיים.
  /// מחזיר האם נשמר בדיסק.
  Future<bool> save(
    Set<String> keys, {
    bool? checkLibrary,
    Set<String>? checkKeys,
  }) async {
    final current = checkLibrary == null || checkKeys == null
        ? await read()
        : null;
    final state = PendingReindex(
      keys: {...keys},
      checkKeys: {...?checkKeys ?? current?.checkKeys},
      checkLibrary: checkLibrary ?? current!.checkLibrary,
    );
    _memory[_file.path] = state;
    try {
      if (state.isEmpty) {
        if (await _file.exists()) await _file.delete();
        return true;
      }
      final temp = File('${_file.path}.tmp');
      await temp.writeAsString(
        jsonEncode({
          'version': _version,
          'keys': state.keys.toList()..sort(),
          if (state.checkLibrary) 'checkLibrary': true,
          if (state.checkKeys.isNotEmpty)
            'checkKeys': state.checkKeys.toList()..sort(),
        }),
        flush: true,
      );
      await temp.rename(_file.path);
      return true;
    } catch (e) {
      debugPrint('⚠️ שמירת רשימת הספרים להחלפה באינדקס נכשלה: $e');
      return false;
    }
  }
}

class PendingReindex {
  const PendingReindex({
    required this.keys,
    required this.checkKeys,
    required this.checkLibrary,
  });

  final Set<String> keys;
  final Set<String> checkKeys;
  final bool checkLibrary;

  bool get isEmpty => keys.isEmpty && checkKeys.isEmpty && !checkLibrary;
}
