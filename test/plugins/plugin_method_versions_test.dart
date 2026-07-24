import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_extended_validator.dart';
import 'package:otzaria/plugins/utils/plugin_version_utils.dart';

/// מוודא שמפת גרסאות ה-API (`_methodMinVersion` ב-PluginExtendedValidator),
/// הטבלה ב-`docs/plugin-sdk/API_REFERENCE.md` ורשימת ה-methods המוכרים
/// נשארות עקביות. כל API חדש חייב להופיע בכל שלושת המקומות עם אותה גרסה,
/// אחרת האכיפה בעת אריזה תתפצל מהתיעוד.
void main() {
  group('סנכרון גרסאות API (מפה ⇄ טבלת התיעוד ⇄ known methods)', () {
    final versions = PluginExtendedValidator.methodMinVersions;

    test('לכל method מוכר יש גרסת מינימום במפה', () {
      final missing =
          PluginExtendedValidator.knownApiMethods
              .where((m) => !versions.containsKey(m))
              .toList()
            ..sort();
      expect(
        missing,
        isEmpty,
        reason:
            'methods ללא גרסה ב-_methodMinVersion: $missing. הוסף שורה '
            'במפה ובטבלה שב-API_REFERENCE.md.',
      );
    });

    test('כל method במפה הוא method מוכר', () {
      final unknown =
          versions.keys
              .where(
                (m) => !PluginExtendedValidator.knownApiMethods.contains(m),
              )
              .toList()
            ..sort();
      expect(
        unknown,
        isEmpty,
        reason: 'גרסה הוגדרה ל-method שאינו ב-_knownApiMethods: $unknown',
      );
    });

    test('כל גרסה במפה היא SemVer חוקי', () {
      for (final entry in versions.entries) {
        expect(
          () => PluginVersionUtils.parseCoreSegments(entry.value),
          returnsNormally,
          reason: 'גרסה לא חוקית עבור ${entry.key}: ${entry.value}',
        );
      }
    });

    test('הטבלה ב-API_REFERENCE.md זהה למפה בקוד', () {
      final md = File('docs/plugin-sdk/API_REFERENCE.md').readAsStringSync();
      final tableVersions = _parseVersionTable(md);

      expect(
        tableVersions,
        isNotEmpty,
        reason: 'לא נמצאה טבלת גרסאות בפורמט "| `x.y` | 0.9.90 |" במסמך.',
      );

      final inMapNotTable =
          versions.keys.where((m) => !tableVersions.containsKey(m)).toList()
            ..sort();
      expect(
        inMapNotTable,
        isEmpty,
        reason: 'methods במפה שחסרים מהטבלה שבמסמך: $inMapNotTable',
      );

      final mismatched = <String>[];
      tableVersions.forEach((method, tableVer) {
        final mapVer = versions[method];
        if (mapVer == null) {
          mismatched.add('$method: בטבלה $tableVer אך לא במפה');
        } else if (mapVer != tableVer) {
          mismatched.add('$method: מפה=$mapVer טבלה=$tableVer');
        }
      });
      expect(
        mismatched,
        isEmpty,
        reason: 'אי-התאמה בין המפה לטבלה: $mismatched',
      );
    });
  });
}

/// מפענח שורות טבלה בפורמט ``| `namespace.method` | 0.9.90 |``.
/// משחזר את ה-regex שעל ה-website (pluginValidation.js) ליישם לפענוח METHOD_MIN_VERSION.
Map<String, String> _parseVersionTable(String md) {
  final rowRe = RegExp(
    r'^\|\s*`([a-z][a-zA-Z0-9_]*\.[a-zA-Z0-9_]+)`\s*\|\s*(\d+\.\d+\.\d+)\s*\|',
    multiLine: true,
  );
  final out = <String, String>{};
  for (final m in rowRe.allMatches(md)) {
    out[m.group(1)!] = m.group(2)!;
  }
  return out;
}
